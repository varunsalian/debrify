import '../../../services/tracking_source_policy.dart';
import '../models/home_series_resume_signals.dart';

/// Fresh tracking preferences for one explicit catalog/resume action.
class HomeTrackingPolicyRepository {
  const HomeTrackingPolicyRepository({
    required this.readTargets,
    required this.readProgress,
    required this.hasCredential,
    required this.fallbackDisconnected,
    required this.readTicks,
    required this.isOwnerCurrent,
  });

  final Future<Set<TrackingSource>> Function(bool Function()) readTargets;
  final Future<WatchProgressSource> Function() readProgress;
  final Future<bool> Function(TrackingSource, bool Function()) hasCredential;
  final Future<bool> Function(TrackingSource, bool Function())
  fallbackDisconnected;
  final Future<Set<TrackingSource>> Function() readTicks;
  final bool Function() isOwnerCurrent;

  /// Null retires the action; it must not dispatch playback or publish a label.
  Future<TrackingSourcePolicy?> loadForContent(
    String? id, {
    required bool Function() isCurrent,
  }) async {
    bool current() => isOwnerCurrent() && isCurrent();
    if (!current()) return null;
    final targets = await readTargets(current);
    if (!current()) return null;
    var progress = await readProgress();
    if (!current()) return null;
    final dedicated = switch (progress) {
      WatchProgressSource.trakt => TrackingSource.trakt,
      WatchProgressSource.simkl => TrackingSource.simkl,
      WatchProgressSource.mdblist => TrackingSource.mdblist,
      _ => null,
    };
    if (dedicated != null) {
      final connected = await hasCredential(dedicated, current);
      if (!current()) return null;
      if (!connected) {
        await fallbackDisconnected(dedicated, current);
        if (!current()) return null;
        progress = WatchProgressSource.smart;
      }
    }
    final ticks = await readTicks();
    if (!current()) return null;
    return TrackingSourcePolicy(
      scrobbleTargets: targets,
      progressSource: progress,
      homeTickSources: ticks,
    ).forContent(id);
  }

  /// Keeps policy loading and the accepted label handoff behind the data boundary.
  static Future<HomeResumePosition> resolveLabel({
    required Future<TrackingSourcePolicy?> Function() loadPolicy,
    required bool Function() isCurrent,
    required Future<HomeResumePosition> Function(TrackingSourcePolicy) label,
  }) async {
    final trackingPolicy = await loadPolicy();
    if (!isCurrent() || trackingPolicy == null) {
      return (started: false, season: null, episode: null);
    }
    return label(trackingPolicy);
  }
}
