import 'package:debrify/models/media_identity.dart';
import 'package:debrify/services/playback_recovery_intent.dart';
import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/storage/continue_watching_storage.dart';
import 'package:debrify/services/storage/local_completion_storage.dart';
import 'package:debrify/services/storage/playback_cleanup_storage.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_hot_merge.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_tombstones.dart';
import 'package:flutter/foundation.dart';

final class MovieProgressStorage {
  const MovieProgressStorage._();
  static const String _explicitlyWatchedSeriesKey = 'explicitly_watched_series_v1';

  /// Tracker/account watched-title invalidation. Kept separate from local
  /// playback so finishing an episode never reloads entire remote histories.
  static final ValueNotifier<int> movieFinishedRevision = ValueNotifier(0);
  // Shared within lib/services/storage/.
  static const String finishedMoviesKey = 'finished_movies_v1';

  /// Movies finished locally by the Debrify player. This intentionally stays
  /// separate from Trakt and Simkl: tracker-backed sessions use the tracker as
  /// their source of truth, while offline/local sessions still need a durable
  /// completed state for the detail screen.
  // Shared within lib/services/storage/.
  static Future<Set<String>> getFinishedMovieIdsInternal() async {
    final prefs = await ProfilePreferences.instance();
    final stored = prefs.getStringList(finishedMoviesKey) ?? const <String>[];
    return {
      for (final raw in stored)
        if (raw.trim().isNotEmpty) MediaIdentity.progressId(raw.trim().toLowerCase(), 'movie'),
    };
  }

  /// Snapshot used by poster badges. Returned IDs are normalized lowercase.
  static Future<Set<String>> getFinishedMovieIds() => getFinishedMovieIdsInternal();

  static Future<bool> isMovieFinished(String imdbId) async {
    imdbId = MediaIdentity.progressId(imdbId, 'movie');
    final normalized = imdbId.trim().toLowerCase();
    if (normalized.isEmpty) return false;
    return (await getFinishedMovieIdsInternal()).contains(normalized);
  }

  /// Mark a locally tracked movie finished, remove it from Continue Watching,
  /// and clear its resumable state. The finished record itself remains so the
  /// detail action can accurately read "Rewatch".
  static Future<void> markMovieAsFinished(String imdbId) async {
    imdbId = MediaIdentity.progressId(imdbId, 'movie');
    final normalized = imdbId.trim().toLowerCase();
    if (normalized.isEmpty) return;

    final finished = await getFinishedMovieIdsInternal();
    if (finished.add(normalized)) {
      final prefs = await ProfilePreferences.instance();
      await prefs.setStringList(finishedMoviesKey, finished.toList()..sort());
      LocalCompletionStorage.localCompletionRevision.value++;
    }
    await Future.wait([
      ContinueWatchingStorage.removeContinueWatchingItem(normalized),
      PlaybackCleanupStorage.clearPlaybackStateByImdbId(normalized),
    ]);
    debugPrint('StorageService: markMovieAsFinished imdbId="$normalized"');
  }

  /// Start a local rewatch. The caller saves a fresh resume point afterwards,
  /// so only the completed marker is removed here.
  static Future<void> unmarkMovieAsFinished(String imdbId) async {
    imdbId = MediaIdentity.progressId(imdbId, 'movie');
    final normalized = imdbId.trim().toLowerCase();
    if (normalized.isEmpty) return;

    final finished = await getFinishedMovieIdsInternal();
    if (!finished.remove(normalized)) return;

    await PlaybackRecoveryIntent.record({
      WebDavSyncRecordKey.finishedMovie(normalized),
    });
    await WebDavSyncTombstoneRecorder.recordForCurrentProfile(<String>{
      WebDavSyncRecordKey.finishedMovie(normalized),
    });
    final prefs = await ProfilePreferences.instance();
    if (finished.isEmpty) {
      await prefs.remove(finishedMoviesKey);
    } else {
      await prefs.setStringList(finishedMoviesKey, finished.toList()..sort());
    }
    LocalCompletionStorage.localCompletionRevision.value++;
    debugPrint('StorageService: unmarkMovieAsFinished imdbId="$normalized"');
  }

  static Future<Set<String>> getExplicitlyWatchedSeriesIds() async {
    final prefs = await ProfilePreferences.instance();
    return (prefs.getStringList(_explicitlyWatchedSeriesKey) ?? const [])
        .map((id) => id.trim().toLowerCase())
        .where((id) => id.isNotEmpty)
        .toSet();
  }

  static Future<void> setSeriesExplicitlyWatched(
    String imdbId, {
    required bool watched,
  }) async {
    final normalized = imdbId.trim().toLowerCase();
    if (normalized.isEmpty) return;
    final ids = await getExplicitlyWatchedSeriesIds();
    final changed = watched ? ids.add(normalized) : ids.remove(normalized);
    if (!changed) return;
    if (!watched) {
      await WebDavSyncTombstoneRecorder.recordForCurrentProfile(<String>{
        WebDavSyncRecordKey.explicitlyWatchedSeries(normalized),
      });
    }
    final prefs = await ProfilePreferences.instance();
    if (ids.isEmpty) {
      await prefs.remove(_explicitlyWatchedSeriesKey);
    } else {
      await prefs.setStringList(
        _explicitlyWatchedSeriesKey,
        ids.toList()..sort(),
      );
    }
    LocalCompletionStorage.localCompletionRevision.value++;
  }
}
