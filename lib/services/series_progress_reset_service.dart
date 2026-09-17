import 'episode_tracker_snapshot_revision.dart';
import 'local_series_completion_service.dart';
import 'mdblist/mdblist_continue_watching_service.dart';
import 'mdblist/mdblist_models.dart';
import 'mdblist/mdblist_service.dart';
import 'profiles/profile_runtime.dart';
import 'simkl/simkl_service.dart';
import 'storage_service.dart';
import 'trakt/trakt_service.dart';
import '../models/tracking_source.dart';

/// Explicit user reset: connected trackers are included regardless of scrobble
/// preferences. Failures are independent and are never reported as success.
class SeriesProgressResetService {
  static Future<List<String>> clearProvider(
    String id,
    String title, {
    required TrackingSource provider,
    required bool isMovie,
    MdblistService? mdblistService,
  }) {
    if (!{
      TrackingSource.trakt,
      TrackingSource.simkl,
      TrackingSource.mdblist,
    }.contains(provider)) {
      throw ArgumentError.value(provider, 'provider');
    }
    Future<List<String>> run() => _clear(
      id,
      title,
      provider: provider,
      isMovie: isMovie,
      mdblistService: mdblistService,
    );
    if (ProfileRuntime.isInitialized && ProfileRuntime.isProfileCommitted) {
      return ProfileRuntime.withCapturedScope(ProfileRuntime.capture(), run);
    }
    return run();
  }

  static Future<List<String>> clear(
    String id,
    String title, {
    bool isMovie = false,
  }) {
    if (ProfileRuntime.isInitialized && ProfileRuntime.isProfileCommitted) {
      return ProfileRuntime.withCapturedScope(
        ProfileRuntime.capture(),
        () => _clear(id, title, isMovie: isMovie),
      );
    }
    return _clear(id, title, isMovie: isMovie);
  }

  static Future<List<String>> _clear(
    String id,
    String title, {
    TrackingSource? provider,
    bool isMovie = false,
    MdblistService? mdblistService,
  }) async {
    final failures = <String>[];
    Future<void> attempt(String label, Future<bool> Function() action) async {
      try {
        if (!await action()) failures.add(label);
      } catch (_) {
        failures.add(label);
      }
    }

    if (provider == null)
      await attempt('this device', () async {
        if (isMovie) {
          await StorageService.clearPlaybackStateByImdbId(id);
          await StorageService.unmarkMovieAsFinished(id);
        } else {
          await StorageService.clearSeriesWatchProgress(id, title);
          // The exact reset already removed completion records. Only rederive;
          // legacy title-based cleanup can also match a different IMDb show.
          await LocalSeriesCompletionService.instance.caughtUpIds();
        }
        await StorageService.removeContinueWatchingItem(id);
        return true;
      });
    // Sequential per account, but a failed account never prevents the others.
    if (provider == null || provider == TrackingSource.trakt)
      await attempt('Trakt', () async {
        final service = TraktService.instance;
        final token = await StorageService.getTraktAccessToken();
        if (token == null || token.isEmpty) return provider == null;
        // Credentials exist: failed refresh is a failed reset, not disconnection.
        if (!await service.isAuthenticated()) return false;
        final sessions = await service.fetchPlaybackItemsOrNull(
          isMovie ? 'movies' : 'episodes',
        );
        var ok = sessions != null;
        for (final row in sessions ?? []) {
          final kind = isMovie ? 'movie' : 'show';
          if (row is! Map || row[kind] is! Map) continue;
          final ids = row[kind]['ids'];
          if (ids is! Map || ids['imdb'] != id) continue;
          if (row['id'] is! num) {
            ok = false;
            continue;
          }
          if (!await service.removePlaybackItem((row['id'] as num).toInt()))
            ok = false;
        }
        if (!await service.removeFromHistory(id, isMovie ? 'movie' : 'series'))
          ok = false;
        if (ok && !isMovie)
          await StorageService.saveEpisodeTraktProgress(
            imdbId: id,
            percents: {},
          );
        return ok;
      });
    if (provider == null || provider == TrackingSource.simkl)
      await attempt('Simkl', () async {
        final service = SimklService.instance;
        if (!await service.isAuthenticated()) return provider == null;
        final history = isMovie
            ? await service.markUnwatched(id, 'movie')
            : await service.clearSeriesHistory(id);
        final playback = await service.deletePlaybackForImdb(id);
        if (history && playback && !isMovie)
          await StorageService.saveEpisodeSimklProgress(
            imdbId: id,
            percents: {},
          );
        return history && playback;
      });
    if (provider == null || provider == TrackingSource.mdblist)
      await attempt('MDBList', () async {
        final service = mdblistService ?? MdblistService.instance;
        if (!await service.isAuthenticated()) return provider == null;
        final sessions = await service.fetchPlaybackSessions();
        var ok = sessions.isSuccess;
        for (final row in sessions.data ?? <MdblistPlaybackSession>[]) {
          if (row.isEpisode == isMovie || row.imdbId != id) continue;
          if (!isMovie && (row.season == null || row.episode == null)) {
            ok = false;
            continue;
          }
          final result = await service.scrobbleClear(
            isMovie
                ? MdblistScrobbleTarget.movie(MdblistMediaIds(imdb: id))
                : MdblistScrobbleTarget.episode(
                    MdblistMediaIds(imdb: id),
                    season: row.season!,
                    episode: row.episode!,
                  ),
          );
          if (!result.isSuccess) ok = false;
        }
        if (!await service.markUnwatched(
          MdblistMediaIds(imdb: id),
          isMovie ? 'movie' : 'show',
        ))
          ok = false;
        MdblistContinueWatchingService.instance.invalidate();
        if (ok && !isMovie)
          await StorageService.saveEpisodeMdblistProgress(
            imdbId: id,
            percents: {},
          );
        return ok;
      });
    for (final tracker in ['trakt', 'simkl', 'mdblist']) {
      if (provider != null && provider.name != tracker) continue;
      EpisodeTrackerSnapshotRevision.invalidateTitle(tracker, id);
    }
    if (provider == null) StorageService.localCompletionRevision.value++;
    StorageService.movieFinishedRevision.value++;
    return failures;
  }
}
