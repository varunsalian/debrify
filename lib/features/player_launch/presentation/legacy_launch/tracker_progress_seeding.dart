import 'package:debrify/services/episode_tracker_snapshot_service.dart';
import 'package:debrify/services/mdblist/mdblist_service.dart';
import 'package:flutter/foundation.dart';

final class TrackerProgressSeeding {
  /// Refresh the replaceable Trakt snapshot used by every guide surface.
  ///
  /// Older builds also copied remote completion into local finished/resume
  /// stores here. That made a later Trakt rewatch impossible to represent and
  /// had no provenance for safe deletion. New launches never create that
  /// pollution; legacy values are neutralized non-destructively when snapshots
  /// are merged for display/resume.
  static Future<void> refreshTraktEpisodeProgress(String imdbId) async {
    try {
      await EpisodeTrackerSnapshotService.refreshTrakt(imdbId);
    } catch (e) {
      debugPrint('VideoPlayerLauncher: Trakt snapshot refresh failed: $e');
    }
  }

  /// Refresh the replaceable Simkl snapshot. Like Trakt, it remains remote
  /// truth and is merged at display/resume time rather than copied locally.
  static Future<void> seedSimklEpisodeProgress(String imdbId) async {
    await EpisodeTrackerSnapshotService.refreshSimkl(imdbId);
  }

  static Future<void> seedMdblistEpisodeProgress(String imdbId) async {
    if (!kMdblistEnabled) return;
    await EpisodeTrackerSnapshotService.seedMdblistPlayback(imdbId);
  }
}
