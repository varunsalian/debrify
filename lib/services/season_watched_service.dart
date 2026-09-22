import '../models/tracking_source.dart';
import '../models/custom_series_identity.dart';
import 'profiles/profile_runtime.dart';
import 'trakt/trakt_service.dart';
import 'simkl/simkl_service.dart';
import 'mdblist/mdblist_service.dart';
import 'mdblist/mdblist_models.dart';
import 'storage_service.dart';
import 'episode_tracker_snapshot_revision.dart';

/// Panel-owned retry intent, isolated by title, season and provider.
class SeasonWatchedRetryState {
  final _pending = <(String, int, TrackingSource), bool>{};

  bool? pending(String id, int season, TrackingSource provider) =>
      _pending[(id, season, provider)];

  void begin(String id, int season, TrackingSource provider, bool watched) {
    _pending[(id, season, provider)] = watched;
  }

  void complete(String id, int season, TrackingSource provider) {
    _pending.remove((id, season, provider));
  }
}

class SeasonWatchedService {
  static Future<bool?> isWatched(
    String imdbId,
    String title,
    int season,
    Iterable<int> episodes,
    TrackingSource provider,
  ) async {
    if (CustomSeriesIdentity.isCustom(imdbId) && provider != TrackingSource.local) return null;
    final numbers = episodes.toSet();
    if (numbers.isEmpty) return null;
    try {
      Set<String>? inventory;
      switch (provider) {
        case TrackingSource.local:
          final local = await StorageService.getFinishedEpisodesByImdbId(
            imdbId: imdbId,
            seriesTitle: title,
          );
          inventory = {
            for (final e in local.entries)
              for (final n in e.value) '${e.key}-$n',
          };
        case TrackingSource.trakt:
          inventory = await TraktService.instance
              .fetchWatchedShowEpisodesOrNull(imdbId);
        case TrackingSource.simkl:
          inventory = await SimklService.instance
              .fetchWatchedShowEpisodesOrNull(imdbId);
        case TrackingSource.mdblist:
          final result = await MdblistService.instance.fetchShowEpisodeProgress(
            imdbId,
          );
          if (!result.isComplete) return null;
          inventory = {
            for (final e in result.data!.entries)
              if (e.value >= 100) e.key,
          };
        default:
          return null;
      }
      return inventory == null
          ? null
          : numbers.every((n) => inventory!.contains('$season-$n'));
    } catch (_) {
      return null;
    }
  }

  /// Use the resolved season inventory, not episode counts (specials and
  /// non-contiguous episode numbering are valid). Never fan out to other trackers.
  static Future<int> mark(
    String imdbId,
    int season,
    Iterable<int> episodes,
    TrackingSource provider, {
    String? seriesTitle,
    bool watched = true,
    MdblistService? mdblistService,
  }) {
    if (CustomSeriesIdentity.isCustom(imdbId) && provider != TrackingSource.local) return Future.value(0);
    final numbers = episodes.toSet().toList()..sort();
    Future<int> run() async {
      Set<String> alreadyWatched = {};
      if (watched && provider == TrackingSource.trakt && numbers.isNotEmpty) {
        // History adds plays, not a watched flag. Re-read on every attempt,
        // and never treat an unavailable inventory as an empty history.
        try {
          final inventory = await TraktService.instance
              .fetchWatchedShowEpisodesOrNull(imdbId);
          if (inventory == null) return numbers.length;
          alreadyWatched = inventory;
        } catch (_) {
          return numbers.length;
        }
      }
      var failed = 0;
      for (final episode in numbers) {
        if (alreadyWatched.contains('$season-$episode')) continue;
        try {
          if (provider == TrackingSource.local) {
            if (seriesTitle == null || seriesTitle.trim().isEmpty) {
              failed++;
              continue;
            }
            final write = watched
                ? StorageService.markEpisodeAsFinished
                : StorageService.unmarkEpisodeAsFinished;
            await write(
              seriesTitle: seriesTitle,
              imdbId: imdbId,
              season: season,
              episode: episode,
            );
            EpisodeTrackerSnapshotRevision.invalidateTitle('local', imdbId);
            continue;
          }
          final ok = switch (provider) {
            TrackingSource.trakt =>
              await (watched
                  ? TraktService.instance.markEpisodeWatched
                  : TraktService.instance.markEpisodeUnwatched)(
                imdbId,
                season,
                episode,
              ),
            TrackingSource.simkl =>
              await (watched
                  ? SimklService.instance.markEpisodeWatched
                  : SimklService.instance.markEpisodeUnwatched)(
                imdbId,
                season,
                episode,
              ),
            TrackingSource.mdblist =>
              await (watched
                  ? (mdblistService ?? MdblistService.instance).markWatched
                  : (mdblistService ?? MdblistService.instance).markUnwatched)(
                MdblistMediaIds(imdb: imdbId),
                'episode',
                season: season,
                episode: episode,
              ),
            _ => false,
          };
          if (!ok) {
            failed++;
          } else if (provider == TrackingSource.simkl) {
            final cleared = await SimklService.instance
                .deletePlaybackForEpisode(imdbId, season, episode);
            if (!cleared) failed++;
          }
        } catch (_) {
          failed++;
        }
      }
      return failed;
    }

    if (ProfileRuntime.isInitialized && ProfileRuntime.isProfileCommitted) {
      return ProfileRuntime.withCapturedScope(ProfileRuntime.capture(), run);
    }
    return run();
  }
}
