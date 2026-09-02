import 'dart:async';

import '../profiles/profile_preference_portability.dart';
import 'webdav_sync_engine.dart';
import 'webdav_sync_hot_merge.dart';

abstract interface class WebDavSyncRuntimeGate {
  bool get playbackActive;

  bool get playbackActiveOnTelevision;

  bool get tvOsLowMemory;
}

typedef WebDavSyncContextProvider = Future<WebDavSyncCycleContext?> Function();

/// Trigger/debounce plumbing only. M4 never calls [arm]; M5 does so only after
/// seed/adoption establishes both identity maps and promotes the binding.
final class WebDavSyncScheduler {
  WebDavSyncScheduler({
    required WebDavSyncCycleRunner runner,
    required WebDavSyncRuntimeGate gate,
    this.debounce = const Duration(seconds: 45),
    this.period = const Duration(minutes: 15),
    this.localChangeDebounce = const Duration(seconds: 10),
    this.playbackDebounce = const Duration(seconds: 60),
    DateTime Function()? clock,
  }) : _runner = runner,
       _gate = gate,
       _clock = clock ?? DateTime.now;

  final WebDavSyncCycleRunner _runner;
  final WebDavSyncRuntimeGate _gate;
  final DateTime Function() _clock;
  final Duration debounce;
  final Duration period;
  final Duration localChangeDebounce;
  final Duration playbackDebounce;

  WebDavSyncContextProvider? _contextProvider;
  Timer? _periodic;
  Timer? _localChangeTimer;
  DateTime? _lastStartedAt;
  bool _running = false;
  bool _dirtyDuringRun = false;

  bool get isArmed => _contextProvider != null;

  void arm(WebDavSyncContextProvider contextProvider) {
    _contextProvider = contextProvider;
    _periodic?.cancel();
    _localChangeTimer?.cancel();
    _localChangeTimer = null;
    _dirtyDuringRun = false;
    _periodic = Timer.periodic(period, (_) => unawaited(_signalPeriodic()));
  }

  /// Synchronous write-side ingress. Filtering and timer coalescing stay here
  /// so profile persistence never waits for, or owns, sync scheduling.
  void notifyLocalChange(String logicalKey) {
    if (_contextProvider == null || !admitsLocalChangeKey(logicalKey)) return;
    if (_running) {
      _dirtyDuringRun = true;
      return;
    }
    _scheduleLocalChange();
  }

  static bool admitsLocalChangeKey(String logicalKey) =>
      ProfilePreferencePortability.allowsKey(logicalKey) ||
      logicalKey == WebDavSyncHotMerge.playbackPreference ||
      logicalKey == WebDavSyncHotMerge.continueWatchingPreference ||
      logicalKey == WebDavSyncHotMerge.finishedMoviesPreference ||
      logicalKey == WebDavSyncHotMerge.explicitlyWatchedSeriesPreference ||
      logicalKey == WebDavSyncHotMerge.playlistPreference ||
      logicalKey == WebDavSyncHotMerge.playlistFavoritesPreference ||
      logicalKey.startsWith(WebDavSyncHotMerge.seriesSourcePrefix);

  void _scheduleLocalChange() {
    if (_contextProvider == null) return;
    // Coalescing window, not a resetting debounce: the first write arms the
    // timer and later writes join it. A resetting timer would starve the push
    // for as long as a steady write stream (playback progress) keeps arriving.
    if (_localChangeTimer != null) return;
    final delay = _gate.playbackActive ? playbackDebounce : localChangeDebounce;
    _localChangeTimer = Timer(delay, () {
      _localChangeTimer = null;
      unawaited(_signalLocalChange());
    });
  }

  Future<void> _signalLocalChange() async {
    try {
      await signal(WebDavSyncTrigger.localChange);
    } catch (_) {
      // Local writes must remain independent of routine network failures. The
      // engine owns durable error/status reporting for any cycle that starts.
    }
  }

  Future<void> _signalPeriodic() async {
    try {
      await signal(WebDavSyncTrigger.periodic);
    } catch (_) {
      // Periodic LAN sync is best effort. The engine records durable status;
      // a transport failure must never become an unhandled timer exception.
    }
  }

  void disarm() {
    _contextProvider = null;
    _periodic?.cancel();
    _periodic = null;
    _localChangeTimer?.cancel();
    _localChangeTimer = null;
    _dirtyDuringRun = false;
  }

  Future<WebDavSyncCycleReport> signal(WebDavSyncTrigger trigger) async {
    final provider = _contextProvider;
    if (provider == null) {
      return const WebDavSyncCycleReport(
        disposition: WebDavSyncCycleDisposition.inactive,
      );
    }
    if (_running) {
      if (trigger == WebDavSyncTrigger.localChange) _dirtyDuringRun = true;
      return const WebDavSyncCycleReport(
        disposition: WebDavSyncCycleDisposition.inactive,
      );
    }
    if (_gate.playbackActiveOnTelevision || _gate.tvOsLowMemory) {
      return const WebDavSyncCycleReport(
        disposition: WebDavSyncCycleDisposition.inactive,
      );
    }
    final now = _clock();
    final last = _lastStartedAt;
    if (trigger != WebDavSyncTrigger.manual &&
        trigger != WebDavSyncTrigger.localChange &&
        last != null &&
        !now.isBefore(last) &&
        now.difference(last) < debounce) {
      return const WebDavSyncCycleReport(
        disposition: WebDavSyncCycleDisposition.inactive,
      );
    }
    _running = true;
    try {
      final context = await provider();
      if (context == null || !context.active || !context.isComplete) {
        return const WebDavSyncCycleReport(
          disposition: WebDavSyncCycleDisposition.inactive,
        );
      }
      _lastStartedAt = _clock();
      return await _runner.runCycle(context, trigger: trigger);
    } finally {
      _running = false;
      if (_dirtyDuringRun && _contextProvider != null) {
        _dirtyDuringRun = false;
        _scheduleLocalChange();
      }
    }
  }

  void dispose() => disarm();
}
