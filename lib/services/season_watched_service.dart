import '../models/tracking_source.dart';
import 'profiles/profile_runtime.dart';
import 'trakt/trakt_service.dart';
import 'simkl/simkl_service.dart';
import 'mdblist/mdblist_service.dart';
import 'mdblist/mdblist_models.dart';
import 'storage_service.dart';
import 'episode_tracker_snapshot_revision.dart';

class SeasonWatchedService {
  /// Use the resolved season inventory, not episode counts (specials and
  /// non-contiguous episode numbering are valid). Never fan out to other trackers.
  static Future<int> mark(
    String imdbId,
    int season,
    Iterable<int> episodes,
    TrackingSource provider, {
    String? seriesTitle,
    MdblistService? mdblistService,
  }) {
    final numbers = episodes.toSet().toList()..sort();
    Future<int> run() async {
      Set<String> watched = {};
      if (provider == TrackingSource.trakt && numbers.isNotEmpty) {
        // History adds plays, not a watched flag. Re-read on every attempt,
        // and never treat an unavailable inventory as an empty history.
        try {
          final inventory = await TraktService.instance
              .fetchWatchedShowEpisodesOrNull(imdbId);
          if (inventory == null) return numbers.length;
          watched = inventory;
        } catch (_) {
          return numbers.length;
        }
      }
      var failed = 0;
      for (final episode in numbers) {
        if (watched.contains('$season-$episode')) continue;
        try {
          if (provider == TrackingSource.local) {
            if (seriesTitle == null || seriesTitle.trim().isEmpty) {
              failed++;
              continue;
            }
            await StorageService.markEpisodeAsFinished(
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
              await TraktService.instance.markEpisodeWatched(
                imdbId,
                season,
                episode,
              ),
            TrackingSource.simkl =>
              await SimklService.instance.markEpisodeWatched(
                imdbId,
                season,
                episode,
              ),
            TrackingSource.mdblist =>
              await (mdblistService ?? MdblistService.instance).markWatched(
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
