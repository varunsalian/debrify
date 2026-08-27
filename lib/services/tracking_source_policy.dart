import 'package:flutter/foundation.dart';

import '../models/tracking_source.dart';
import 'storage_service.dart';

export '../models/tracking_source.dart';

/// One immutable snapshot of the user's Tracking preferences.
///
/// Keeping all three decisions here prevents individual playback and Home
/// surfaces from growing subtly different interpretations of the settings.
class TrackingSourcePolicy {
  const TrackingSourcePolicy({
    required this.scrobbleTargets,
    required this.progressSource,
    required this.homeTickSources,
  });

  final Set<TrackingSource> scrobbleTargets;
  final WatchProgressSource progressSource;
  final Set<TrackingSource> homeTickSources;

  static Future<TrackingSourcePolicy> load() async {
    final scrobbleTargets = await StorageService.getTrackingScrobbleTargets();
    var progressSource = await StorageService.getWatchProgressSource();
    final dedicated = switch (progressSource) {
      WatchProgressSource.trakt => TrackingSource.trakt,
      WatchProgressSource.simkl => TrackingSource.simkl,
      WatchProgressSource.mdblist => TrackingSource.mdblist,
      _ => null,
    };
    if (dedicated != null) {
      final connected = switch (dedicated) {
        TrackingSource.trakt => StorageService.hasTraktCredential(),
        TrackingSource.simkl => StorageService.hasSimklCredential(),
        TrackingSource.mdblist => StorageService.hasMdblistCredential(),
        TrackingSource.local => Future<bool>.value(true),
      };
      if (!await connected) {
        await StorageService.fallbackDisconnectedProgressSource(dedicated);
        progressSource = WatchProgressSource.smart;
      }
    }
    final policy = TrackingSourcePolicy(
      scrobbleTargets: scrobbleTargets,
      progressSource: progressSource,
      homeTickSources: await StorageService.getHomeTickSources(),
    );
    // Diagnostic trail: one line whenever the effective policy CHANGES (this
    // loader runs constantly — logging every load would drown the capture).
    final snapshot =
        'scrobble=${policy.scrobbleTargets.map((s) => s.name).join('+')} '
        'progress=${policy.progressSource.name} '
        'homeTicks=${policy.homeTickSources.map((s) => s.name).join('+')}';
    if (snapshot != _lastLoggedSnapshot) {
      _lastLoggedSnapshot = snapshot;
      debugPrint('[TrackingDiag] policy $snapshot');
    }
    return policy;
  }

  static String? _lastLoggedSnapshot;

  bool scrobbles(TrackingSource source) =>
      source == TrackingSource.local || scrobbleTargets.contains(source);

  /// Smart preserves the legacy merged/recency behavior. A dedicated source
  /// admits only itself; local means data written by this Debrify profile.
  bool progressFrom(TrackingSource source) => switch (progressSource) {
    WatchProgressSource.smart => true,
    WatchProgressSource.local => source == TrackingSource.local,
    WatchProgressSource.trakt => source == TrackingSource.trakt,
    WatchProgressSource.simkl => source == TrackingSource.simkl,
    WatchProgressSource.mdblist => source == TrackingSource.mdblist,
  };

  bool homeTicksFrom(TrackingSource source) => homeTickSources.contains(source);

  /// Episode guides always merge completed ticks, while partial bars follow
  /// [progressSource]. This supplier-side mask is also used by the native TV
  /// payload so late metadata cannot reintroduce a foreign partial bar.
  double? guideProgressFrom(
    TrackingSource source,
    double? percent, {
    double completionThreshold = 95.0,
  }) {
    if (percent == null || !percent.isFinite) return null;
    final normalized = percent.clamp(0.0, 100.0).toDouble();
    return progressFrom(source) || normalized >= completionThreshold
        ? normalized
        : null;
  }

  bool get forcesLocalCompletion => progressSource == WatchProgressSource.local;

  bool get isSmart => progressSource == WatchProgressSource.smart;
}
