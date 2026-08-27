import 'package:flutter/foundation.dart';

import 'episode_tracker_snapshot_revision.dart';
import 'local_series_completion_service.dart';
import 'mdblist/mdblist_models.dart';
import 'mdblist/mdblist_service.dart';
import 'simkl/simkl_service.dart';
import 'storage_service.dart';
import 'tracking_source_policy.dart';
import 'trakt/trakt_service.dart';
import 'watched_status_service.dart';

class WatchedActionResult {
  const WatchedActionResult(this.failedTargets);

  final List<String> failedTargets;
  bool get success => failedTargets.isEmpty;
}

/// Single fan-out point for every user-initiated watched/unwatched action.
/// Local is unconditional; remote writes follow the Scrobble selection.
class WatchedActionCoordinator {
  WatchedActionCoordinator._();

  static Future<WatchedActionResult> setTitleWatched({
    required String imdbId,
    required String contentType,
    required bool watched,
  }) async {
    final id = imdbId.trim();
    if (id.isEmpty) return const WatchedActionResult(['this device']);
    final series = contentType == 'series' || contentType == 'show';
    if (series) {
      await StorageService.setSeriesExplicitlyWatched(id, watched: watched);
      if (!watched) {
        await LocalSeriesCompletionService.instance.clearCompletedHistory(id);
      }
    } else if (watched) {
      await StorageService.markMovieAsFinished(id);
    } else {
      await StorageService.unmarkMovieAsFinished(id);
    }

    final policy = await TrackingSourcePolicy.load();
    final failures = <String>[];
    if (policy.scrobbleTargets.contains(TrackingSource.trakt) &&
        await TraktService.instance.isAuthenticated()) {
      final ok = watched
          ? await TraktService.instance.addToHistory(id, contentType)
          : await TraktService.instance.removeFromHistory(id, contentType);
      if (!ok) failures.add('Trakt');
    }
    if (policy.scrobbleTargets.contains(TrackingSource.simkl) &&
        await SimklService.instance.isAuthenticated()) {
      var ok = watched
          ? await SimklService.instance.markWatched(id, contentType)
          : await SimklService.instance.markUnwatched(id, contentType);
      if (watched && ok) {
        // Completed titles are NOT hidden by status (a paused session on them
        // is an active rewatch), so clearing the paused session is what takes
        // the title OFF Simkl's Continue Watching — fold the result in, and
        // keep this write behind the same Scrobble gate as the mark itself.
        ok = await SimklService.instance.deletePlaybackForImdb(id);
      }
      if (!ok) failures.add('Simkl');
    }
    if (id.startsWith('tt') &&
        policy.scrobbleTargets.contains(TrackingSource.mdblist) &&
        await MdblistService.instance.isAuthenticated()) {
      final ids = MdblistMediaIds(imdb: id);
      final type = series ? 'show' : 'movie';
      final ok = watched
          ? await MdblistService.instance.markWatched(ids, type)
          : await MdblistService.instance.markUnwatched(ids, type);
      if (!ok) failures.add('MDBList');
    }
    WatchedStatusService.instance.ensureStarted();
    debugPrint(
      '[TrackingDiag] watched-action title imdb=$id watched=$watched '
      'scrobbleSet=${policy.scrobbleTargets.map((s) => s.name).join('+')} '
      'failures=${failures.isEmpty ? 'none' : failures.join('+')}',
    );
    return WatchedActionResult(failures);
  }

  static Future<WatchedActionResult> setEpisodeWatched({
    required String imdbId,
    required String seriesTitle,
    required int season,
    required int episode,
    required bool watched,
  }) async {
    if (watched) {
      await StorageService.markEpisodeAsFinished(
        seriesTitle: seriesTitle,
        season: season,
        episode: episode,
        imdbId: imdbId,
      );
    } else {
      await StorageService.unmarkEpisodeAsFinished(
        seriesTitle: seriesTitle,
        season: season,
        episode: episode,
        imdbId: imdbId,
      );
    }
    EpisodeTrackerSnapshotRevision.invalidateTitle('local', imdbId);

    final policy = await TrackingSourcePolicy.load();
    final failures = <String>[];
    if (policy.scrobbleTargets.contains(TrackingSource.trakt) &&
        await TraktService.instance.isAuthenticated()) {
      final ok = watched
          ? await TraktService.instance.markEpisodeWatched(
              imdbId,
              season,
              episode,
            )
          : await TraktService.instance.markEpisodeUnwatched(
              imdbId,
              season,
              episode,
            );
      if (!ok) failures.add('Trakt');
    }
    if (policy.scrobbleTargets.contains(TrackingSource.simkl) &&
        await SimklService.instance.isAuthenticated()) {
      final ok = watched
          ? await SimklService.instance.markEpisodeWatched(
              imdbId,
              season,
              episode,
            )
          : await SimklService.instance.markEpisodeUnwatched(
              imdbId,
              season,
              episode,
            );
      if (watched && ok) {
        await SimklService.instance.deletePlaybackForEpisode(
          imdbId,
          season,
          episode,
        );
      }
      if (!ok) failures.add('Simkl');
    }
    if (imdbId.startsWith('tt') &&
        policy.scrobbleTargets.contains(TrackingSource.mdblist) &&
        await MdblistService.instance.isAuthenticated()) {
      final ids = MdblistMediaIds(imdb: imdbId);
      final ok = watched
          ? await MdblistService.instance.markWatched(
              ids,
              'episode',
              season: season,
              episode: episode,
            )
          : await MdblistService.instance.markUnwatched(
              ids,
              'episode',
              season: season,
              episode: episode,
            );
      if (!ok) failures.add('MDBList');
    }
    debugPrint(
      '[TrackingDiag] watched-action episode imdb=$imdbId '
      'S${season}E$episode watched=$watched '
      'scrobbleSet=${policy.scrobbleTargets.map((s) => s.name).join('+')} '
      'failures=${failures.isEmpty ? 'none' : failures.join('+')}',
    );
    return WatchedActionResult(failures);
  }
}
