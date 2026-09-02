import 'dart:async';

import '../profiles/profile_preference_portability.dart';
import '../profiles/profile_preferences.dart';
import 'webdav_sync_engine.dart';
import 'webdav_sync_hot_merge.dart';
import 'webdav_sync_transport.dart';

abstract interface class WebDavSyncRuntimeGate {
  bool get playbackActive;

  bool get playbackActiveOnTelevision;

  bool get tvOsLowMemory;
}

typedef WebDavSyncContextProvider = Future<WebDavSyncCycleContext?> Function();

const bool webDavSyncRemotePollEnabled = bool.fromEnvironment(
  'DEBRIFY_WEBDAV_SYNC_POLL',
  defaultValue: true,
);

enum WebDavSyncPollState { active, pausedBackoff, disabledNoValidators, gated }

final class WebDavSyncRemotePollContext {
  const WebDavSyncRemotePollContext({
    required this.transport,
    required this.peerDeviceIds,
    required this.validators,
  });

  final WebDavSyncTransport transport;
  final List<String> peerDeviceIds;
  final Map<String, WebDavSyncManifestValidator> validators;
}

typedef WebDavSyncRemotePollContextProvider =
    Future<WebDavSyncRemotePollContext?> Function();

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
    this.remotePollPeriod = const Duration(seconds: 60),
    this.remotePollingEnabled = webDavSyncRemotePollEnabled,
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
  final Duration remotePollPeriod;
  final bool remotePollingEnabled;

  WebDavSyncContextProvider? _contextProvider;
  WebDavSyncRemotePollContextProvider? _remotePollContextProvider;
  Timer? _periodic;
  Timer? _remotePollTimer;
  Timer? _localChangeTimer;
  DateTime? _lastStartedAt;
  DateTime? _nextRemotePollAt;
  bool _running = false;
  bool _polling = false;
  bool _remotePollingForeground = true;
  bool _pollDisabledNoValidators = false;
  bool _dirtyDuringRun = false;
  int _consecutivePollFailures = 0;
  int _pollGeneration = 0;
  Completer<void>? _pollCompletion;

  bool get isArmed => _contextProvider != null;

  WebDavSyncPollState get pollState {
    if (_pollDisabledNoValidators) {
      return WebDavSyncPollState.disabledNoValidators;
    }
    final nextPoll = _nextRemotePollAt;
    if (_consecutivePollFailures > 0 &&
        nextPoll != null &&
        _clock().isBefore(nextPoll)) {
      return WebDavSyncPollState.pausedBackoff;
    }
    if (!remotePollingEnabled ||
        !_remotePollingForeground ||
        _remotePollContextProvider == null ||
        _running ||
        _polling ||
        _gateHolds) {
      return WebDavSyncPollState.gated;
    }
    return WebDavSyncPollState.active;
  }

  bool get _gateHolds =>
      _gate.playbackActiveOnTelevision || _gate.tvOsLowMemory;

  void arm(
    WebDavSyncContextProvider contextProvider, {
    WebDavSyncRemotePollContextProvider? remotePollContextProvider,
  }) {
    _contextProvider = contextProvider;
    _remotePollContextProvider = remotePollContextProvider;
    _periodic?.cancel();
    _remotePollTimer?.cancel();
    _localChangeTimer?.cancel();
    _localChangeTimer = null;
    _dirtyDuringRun = false;
    _pollDisabledNoValidators = false;
    _resetPollBackoff();
    _pollGeneration++;
    _periodic = Timer.periodic(period, (_) => unawaited(_signalPeriodic()));
    _armRemotePollTimer();
  }

  void pauseRemotePolling() {
    _remotePollingForeground = false;
    _remotePollTimer?.cancel();
    _remotePollTimer = null;
    _pollGeneration++;
  }

  void resumeRemotePolling() {
    if (_remotePollingForeground) return;
    _remotePollingForeground = true;
    _pollGeneration++;
    _armRemotePollTimer();
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
      logicalKey == ProfilePreferences.webDavSyncRegistryLogicalKey ||
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

  void _armRemotePollTimer() {
    _remotePollTimer?.cancel();
    _remotePollTimer = null;
    if (!remotePollingEnabled ||
        !_remotePollingForeground ||
        _remotePollContextProvider == null ||
        _pollDisabledNoValidators) {
      return;
    }
    _remotePollTimer = Timer.periodic(
      remotePollPeriod,
      (_) => unawaited(_pollForRemoteChanges()),
    );
  }

  Future<void> _pollForRemoteChanges() async {
    final provider = _remotePollContextProvider;
    final now = _clock();
    if (provider == null ||
        !remotePollingEnabled ||
        !_remotePollingForeground ||
        _pollDisabledNoValidators ||
        _running ||
        _polling ||
        _gateHolds ||
        (_nextRemotePollAt != null && now.isBefore(_nextRemotePollAt!))) {
      return;
    }

    final generation = _pollGeneration;
    _polling = true;
    final completion = Completer<void>();
    _pollCompletion = completion;
    WebDavSyncRemotePollContext? context;
    try {
      context = await provider();
      if (context == null ||
          generation != _pollGeneration ||
          !_remotePollingForeground ||
          _running ||
          _gateHolds) {
        return;
      }
      final peerDeviceIds = context.peerDeviceIds.toSet().toList()..sort();
      if (peerDeviceIds.isEmpty) return;
      final outcomes = await _mapPollConcurrentOrdered<String, _PollOutcome>(
        peerDeviceIds,
        limit: 4,
        operation: (deviceId) async {
          try {
            return _PollOutcome(
              deviceId: deviceId,
              probe: await context!.transport.probeManifest(deviceId),
            );
          } catch (error) {
            return _PollOutcome(deviceId: deviceId, error: error);
          }
        },
      );
      if (generation != _pollGeneration || !_remotePollingForeground) return;
      if (outcomes.any((outcome) => outcome.error != null)) {
        _recordPollFailure();
        return;
      }
      _resetPollBackoff();
      final changed = outcomes.any((outcome) {
        final probe = outcome.probe!;
        if (!probe.exists) return true;
        final validator = probe.validator;
        return validator != null &&
            validator != context!.validators[outcome.deviceId];
      });
      if (changed) {
        await signal(WebDavSyncTrigger.remoteChange);
        return;
      }
      if (outcomes.any(
        (outcome) => outcome.probe!.exists && outcome.probe!.validator == null,
      )) {
        _pollDisabledNoValidators = true;
        _remotePollTimer?.cancel();
        _remotePollTimer = null;
      }
    } catch (_) {
      // A metadata hint never becomes a sync error. The ordinary lifecycle
      // and 15-minute cycles remain the durable retry and reporting path.
      _recordPollFailure();
    } finally {
      context?.transport.close();
      _polling = false;
      if (identical(_pollCompletion, completion)) _pollCompletion = null;
      if (!completion.isCompleted) completion.complete();
    }
  }

  void _recordPollFailure() {
    _consecutivePollFailures++;
    var delayMs = remotePollPeriod.inMilliseconds;
    for (var index = 1; index < _consecutivePollFailures; index++) {
      delayMs *= 2;
      if (delayMs >= period.inMilliseconds) {
        delayMs = period.inMilliseconds;
        break;
      }
    }
    if (delayMs > period.inMilliseconds) delayMs = period.inMilliseconds;
    _nextRemotePollAt = _clock().add(Duration(milliseconds: delayMs));
  }

  void _resetPollBackoff() {
    _consecutivePollFailures = 0;
    _nextRemotePollAt = null;
  }

  void disarm() {
    _contextProvider = null;
    _remotePollContextProvider = null;
    _periodic?.cancel();
    _periodic = null;
    _remotePollTimer?.cancel();
    _remotePollTimer = null;
    _localChangeTimer?.cancel();
    _localChangeTimer = null;
    _dirtyDuringRun = false;
    _pollDisabledNoValidators = false;
    _resetPollBackoff();
    _pollGeneration++;
  }

  Future<WebDavSyncCycleReport> signal(WebDavSyncTrigger trigger) async {
    final pollCompletion = trigger == WebDavSyncTrigger.remoteChange
        ? null
        : _pollCompletion;
    if (pollCompletion != null) await pollCompletion.future;
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
    if (_gateHolds) {
      return const WebDavSyncCycleReport(
        disposition: WebDavSyncCycleDisposition.inactive,
      );
    }
    final now = _clock();
    final last = _lastStartedAt;
    if (trigger != WebDavSyncTrigger.manual &&
        trigger != WebDavSyncTrigger.localChange &&
        trigger != WebDavSyncTrigger.remoteChange &&
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

final class _PollOutcome {
  const _PollOutcome({required this.deviceId, this.probe, this.error});

  final String deviceId;
  final WebDavSyncManifestProbe? probe;
  final Object? error;
}

Future<List<R>> _mapPollConcurrentOrdered<T, R>(
  List<T> input, {
  required int limit,
  required Future<R> Function(T value) operation,
}) async {
  if (input.isEmpty) return <R>[];
  final results = List<R?>.filled(input.length, null);
  var nextIndex = 0;

  Future<void> worker() async {
    while (nextIndex < input.length) {
      final index = nextIndex++;
      results[index] = await operation(input[index]);
    }
  }

  final workerCount = input.length < limit ? input.length : limit;
  await Future.wait<void>(
    List<Future<void>>.generate(workerCount, (_) => worker()),
  );
  return List<R>.generate(input.length, (index) => results[index] as R);
}
