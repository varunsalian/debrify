import 'package:debrify/services/iptv_media_store.dart';
import 'package:debrify/services/playback_recovery_intent.dart';
import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/storage/local_completion_storage.dart';
import 'package:debrify/services/storage/movie_progress_storage.dart';
import 'package:debrify/services/storage/playback_state_store.dart';
import 'package:debrify/services/storage/video_resume_storage.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_hot_merge.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_library_models.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_tombstones.dart';
import 'package:flutter/foundation.dart';

final class PlaybackCleanupStorage {
  const PlaybackCleanupStorage._();

  /// Remove all playback state entries (series progress, video progress) for an IMDB ID.
  static Future<void> clearPlaybackStateByImdbId(String imdbId) async {
    final normalized = imdbId.trim().toLowerCase();
    if (normalized.isEmpty) return;
    final map = await PlaybackStateStore.getPlaybackStateMap();
    final keysToRemove = <String>[];
    for (final entry in map.entries) {
      if (entry.value is Map<String, dynamic> &&
          (entry.value['imdbId'] as String?)?.trim().toLowerCase() == normalized) {
        keysToRemove.add(entry.key);
      }
    }
    if (keysToRemove.isEmpty) return;
    for (final key in keysToRemove) {
      map.remove(key);
    }
    await PlaybackStateStore.savePlaybackStateMap(map, recordDeletions: true);
    // Series finished-episode markers share this map, so clearing a Continue
    // Watching item must also invalidate derived series completion.
    LocalCompletionStorage.localCompletionRevision.value++;
    debugPrint(
      'StorageService: Cleared ${keysToRemove.length} playback state entries for "$imdbId"',
    );
  }

  /// Clean up old playback state data (older than 30 days)
  static Future<void> cleanupOldPlaybackState() async {
    final map = await PlaybackStateStore.getPlaybackStateMap();
    final now = DateTime.now().millisecondsSinceEpoch;
    final thirtyDaysAgo = now - (30 * 24 * 60 * 60 * 1000);

    final keysToRemove = <String>[];

    for (final entry in map.entries) {
      final data = entry.value as Map<String, dynamic>;
      final updatedAt = data['updatedAt'] as int?;

      if (updatedAt != null && updatedAt < thirtyDaysAgo) {
        keysToRemove.add(entry.key);
      }
    }

    for (final key in keysToRemove) {
      map.remove(key);
    }

    if (keysToRemove.isNotEmpty) {
      await PlaybackStateStore.savePlaybackStateMap(map, recordDeletions: true);
    }
  }

  /// Clear all playback-related data (series and video states, track prefs, legacy resume)
  /// [recordSyncDeletions] distinguishes a deliberate clear (default, which
  /// deletes on every synced device) from a device-local wipe such as app
  /// reset, which must never mint circle-wide deletions.
  static Future<void> clearAllPlaybackData({
    bool recordSyncDeletions = true,
  }) async {
    final prefs = await ProfilePreferences.instance();
    // Device-local clears must invalidate native recovery too, without
    // publishing a deletion to the user's other devices.
    await PlaybackRecoveryIntent.recordClearAll();
    await PlaybackStateStore.savePlaybackStateMap(
      <String, dynamic>{},
      recordDeletions: recordSyncDeletions,
    );
    if (recordSyncDeletions) {
      final finishedMovies = await MovieProgressStorage.getFinishedMovieIdsInternal();
      await WebDavSyncTombstoneRecorder.recordForCurrentProfile(
        finishedMovies.map(WebDavSyncRecordKey.finishedMovie),
      );
    }
    await prefs.remove(MovieProgressStorage.finishedMoviesKey);
    await prefs.remove(LocalCompletionStorage.localSeriesCompletionStateKey);
    await prefs.remove(LocalCompletionStorage.localSeriesCalendarCheckedAtKey);
    await prefs.remove(LocalCompletionStorage.localSeriesCalendarAttemptedAtKey);
    LocalCompletionStorage.localCompletionRevision.value++;
    // Resume lives in the DB now; the prefs key only still exists for users
    // who wipe before the one-time import has run.
    await prefs.remove(VideoResumeStorage.videoResumeKey);
    await IptvMediaStore.clearVideoResume(
      origin: recordSyncDeletions ? WebDavSyncMutationOrigin.user : WebDavSyncMutationOrigin.maintenance,
    );
    debugPrint(
      'StorageService: cleared playback state, completed movies, and video resume data',
    );
  }
}
