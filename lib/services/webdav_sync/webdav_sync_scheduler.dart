import 'dart:async';

import '../profiles/profile_preference_portability.dart';
import '../webdav_protocol_client.dart' show WebDavException;
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
typedef WebDavSyncLocalChangeObserver = void Function(String logicalKey);
typedef WebDavSyncLocalChangeDeferredObserver =
    void Function(String reason, int attempt, Duration delay);

const bool webDavSyncRemotePollEnabled = bool.fromEnvironment(
  'DEBRIFY_WEBDAV_SYNC_POLL',
  defaultValue: true,
);

const Duration warmPollPeriod = Duration(seconds: 5);
const Duration idlePollPeriod = Duration(seconds: 60);
const Duration warmDuration = Duration(minutes: 3);

enum WebDavSyncPollState { active, pausedBackoff, disabledNoValidators, gated }

final class WebDavSyncRemotePollContext {
  const WebDavSyncRemotePollContext({
    required this.transport,
    required this.peerDeviceIds,
    required this.validators,
    this.clientGeneration,
    this.isClientGenerationCurrent,
  });

  final WebDavSyncTransport transport;
  final List<String> peerDeviceIds;
  final Map<String, WebDavSyncManifestValidator> validators;
  final int? clientGeneration;
  final bool Function(int generation)? isClientGenerationCurrent;

  bool get hasCurrentClientGeneration {
    final generation = clientGeneration;
    final isCurrent = isClientGenerationCurrent;
    return generation == null || isCurrent == null || isCurrent(generation);
  }
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
    this.localChangeDebounce = const Duration(seconds: 2),
    this.playbackDebounce = const Duration(seconds: 60),
    this.remotePollingEnabled = webDavSyncRemotePollEnabled,
    this.localChangeObserver,
    this.localChangeDeferredObserver,
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
  final bool remotePollingEnabled;
  final WebDavSyncLocalChangeObserver? localChangeObserver;
  final WebDavSyncLocalChangeDeferredObserver? localChangeDeferredObserver;

  WebDavSyncContextProvider? _contextProvider;
  WebDavSyncRemotePollContextProvider? _remotePollContextProvider;
  Timer? _periodic;
  Timer? _remotePollTimer;
  Timer? _warmExpiryTimer;
  Timer? _localChangeTimer;
  DateTime? _lastStartedAt;
  DateTime? _nextRemotePollAt;
  DateTime? _warmUntil;
  bool _running = false;
  bool _polling = false;
  bool _remotePollingForeground = true;
  bool _pollDisabledNoValidators = false;
  bool _dirtyDuringRun = false;
  bool _immediateDirtyDuringRun = false;
  bool _capacityBlocked = false;
  String? _pendingLocalChangeKey;

  /// Durable local-change intent: the latest admitted write not yet flushed by
  /// a successfully completed cycle whose snapshot could include it. Sequence
  /// ordering is deliberate: wall clocks can return the same value for a cycle
  /// start and a later write. Survives disarm.
  int _localChangeSequence = 0;
  int? _pendingLocalChangeSequence;
  int _localChangeRetries = 0;
  static const Duration localChangeRetryFloor = Duration(seconds: 1);
  static const Duration localChangeRetryCap = Duration(minutes: 2);
  int _consecutivePollFailures = 0;
  bool _pollBackoffHoldsThroughCycles = false;
  int _pollGeneration = 0;
  int _pollTimerGeneration = 0;
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
    _warmExpiryTimer?.cancel();
    _localChangeTimer?.cancel();
    _localChangeTimer = null;
    _dirtyDuringRun = false;
    _immediateDirtyDuringRun = false;
    _pendingLocalChangeKey = null;
    _pollDisabledNoValidators = false;
    // A local-change intent recorded before a disarm/rearm bounce (or while
    // the sink was dark) must not wait for an unrelated trigger.
    if (_pendingLocalChangeSequence != null) _scheduleLocalChange();
    _warmUntil = null;
    _resetPollBackoff();
    _pollGeneration++;
    _periodic = Timer.periodic(period, (_) => unawaited(_signalPeriodic()));
    _armRemotePollTimer();
  }

  void pauseRemotePolling() {
    _remotePollingForeground = false;
    _cancelRemotePollTimer();
    _pollGeneration++;
  }

  void resumeRemotePolling() {
    if (_remotePollingForeground) return;
    _remotePollingForeground = true;
    _pollGeneration++;
    _rearmWarmPolling();
  }

  /// Synchronous write-side ingress. Filtering and timer coalescing stay here
  /// so profile persistence never waits for, or owns, sync scheduling.
  void notifyLocalChange(String logicalKey) {
    if (_contextProvider == null || !admitsLocalChangeKey(logicalKey)) return;
    _capacityBlocked = false;
    _pendingLocalChangeKey = logicalKey;
    _localChangeSequence++;
    _pendingLocalChangeSequence = _localChangeSequence;
    if (_running) {
      _dirtyDuringRun = true;
      return;
    }
    _scheduleLocalChange();
  }

  /// A fenced registry conflict needs a fresh snapshot immediately. Unlike an
  /// ordinary local write, this replaces any already-armed debounce window.
  void notifyConflictFollowUp() {
    if (_contextProvider == null) return;
    if (_running) {
      _dirtyDuringRun = true;
      _immediateDirtyDuringRun = true;
      return;
    }
    _scheduleLocalChange(immediate: true);
  }

  /// A playback checkpoint (pause, settled seek, explicit save) is a human
  /// handoff moment: flush the pending window now instead of waiting out the
  /// playback coalescing interval. Harmless when nothing is pending — the
  /// cycle is digest-suppressed.
  void notifyPlaybackCheckpoint() {
    // Television and low-memory gates forbid cycles outright. Do not even
    // replace a durable-intent retry timer here: repeated remote/button events
    // during TV playback could otherwise keep escalating its backoff while no
    // cycle was permitted to run.
    if (_contextProvider == null || _gateHolds) return;
    if (_running) {
      _dirtyDuringRun = true;
      _immediateDirtyDuringRun = true;
      return;
    }
    _scheduleLocalChange(immediate: true);
  }

  /// A lifecycle handoff (the app going inactive ahead of a possible
  /// process freeze) flushes an unpublished local change immediately.
  /// Unlike a checkpoint this requires a pending intent: shade pulls,
  /// dialogs, and focus flips with nothing to say spend no cycle. The
  /// immediate local-change path is exempt from the 45s trigger debounce,
  /// which would otherwise swallow exactly the post-churn handoffs this
  /// exists for.
  void flushPendingLocalChangeForLifecycle() {
    if (_contextProvider == null ||
        _pendingLocalChangeSequence == null ||
        _gateHolds) {
      return;
    }
    // A running cycle needs no dirty flags here: if it started at or after
    // the pending sequence it clears the intent itself, and if it started
    // earlier the outcome handler rearms the durable retry at its 1s floor.
    // Setting the immediate flags instead would schedule a redundant cycle
    // after a covering run.
    if (_running) return;
    _scheduleLocalChange(immediate: true);
  }

  /// Applied remote watch activity means another device is mid-session:
  /// keep the fast poll cadence alive for the duration of that session.
  void extendWarmSession() {
    if (_contextProvider == null) return;
    _rearmWarmPolling();
  }

  static bool admitsLocalChangeKey(String logicalKey) {
    if (WebDavSyncHotMerge.hotLocalOnlyScalarKeys.contains(logicalKey)) {
      return false;
    }
    return ProfilePreferencePortability.allowsKey(logicalKey) ||
        logicalKey == WebDavSyncHotMerge.playbackPreference ||
        logicalKey == WebDavSyncHotMerge.continueWatchingPreference ||
        logicalKey == WebDavSyncHotMerge.finishedMoviesPreference ||
        logicalKey == WebDavSyncHotMerge.explicitlyWatchedSeriesPreference ||
        logicalKey == WebDavSyncHotMerge.playlistPreference ||
        logicalKey == WebDavSyncHotMerge.playlistFavoritesPreference ||
        logicalKey == ProfilePreferences.webDavSyncRegistryLogicalKey ||
        logicalKey == ProfilePreferences.webDavSyncLibraryLogicalKey ||
        logicalKey.startsWith(WebDavSyncHotMerge.seriesSourcePrefix);
  }

  /// Clears the pending intent only when a completed cycle started with a
  /// sequence snapshot that included it and did not request a fresh snapshot.
  void _handleLocalChangeOutcome({
    required int sequenceAtStart,
    required bool completed,
    required bool localChangeFollowUp,
    required bool immediateRetry,
  }) {
    final pending = _pendingLocalChangeSequence;
    if (pending == null) return;
    if (completed && !localChangeFollowUp && pending <= sequenceAtStart) {
      _pendingLocalChangeSequence = null;
      _localChangeRetries = 0;
      return;
    }
    _rearmPendingLocalChange(
      !completed
          ? 'cycle did not complete'
          : localChangeFollowUp
          ? 'cycle requested a local-change follow-up'
          : 'write landed during the cycle',
      immediate: immediateRetry,
    );
  }

  void _rearmPendingLocalChange(String reason, {bool immediate = false}) {
    if (_contextProvider == null || _pendingLocalChangeSequence == null) return;
    if (_localChangeTimer != null) {
      if (!immediate) return;
      _localChangeTimer!.cancel();
      _localChangeTimer = null;
    }
    _localChangeRetries++;
    final delay = immediate
        ? Duration.zero
        : _localChangeRetryDelay(_localChangeRetries);
    _armLocalChangeTimer(delay);
    try {
      localChangeDeferredObserver?.call(reason, _localChangeRetries, delay);
    } catch (_) {
      // Observability must never affect scheduling.
    }
  }

  Duration _localChangeRetryDelay(int attempt) {
    var delay = _gate.playbackActive ? playbackDebounce : localChangeDebounce;
    if (delay < localChangeRetryFloor) delay = localChangeRetryFloor;
    if (delay >= localChangeRetryCap) return localChangeRetryCap;
    final doublings = (attempt - 1).clamp(0, 8);
    for (var index = 0; index < doublings; index++) {
      if (delay > localChangeRetryCap - delay) {
        return localChangeRetryCap;
      }
      delay += delay;
    }
    return delay;
  }

  void _armLocalChangeTimer(Duration delay) {
    late final Timer timer;
    timer = Timer(delay, () {
      if (!identical(_localChangeTimer, timer)) return;
      _localChangeTimer = null;
      unawaited(_signalLocalChange());
    });
    _localChangeTimer = timer;
  }

  void _scheduleLocalChange({bool immediate = false}) {
    if (_contextProvider == null) return;
    // Coalescing window, not a resetting debounce: the first write arms the
    // timer and later writes join it. A resetting timer would starve the push
    // for as long as a steady write stream (playback progress) keeps arriving.
    if (immediate) {
      _localChangeTimer?.cancel();
      _localChangeTimer = null;
    } else if (_localChangeTimer != null) {
      return;
    }
    final delay = immediate
        ? Duration.zero
        : _gate.playbackActive
        ? playbackDebounce
        : localChangeDebounce;
    _armLocalChangeTimer(delay);
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
    _cancelRemotePollTimer();
    if (!remotePollingEnabled ||
        !_remotePollingForeground ||
        _remotePollContextProvider == null ||
        _pollDisabledNoValidators) {
      return;
    }
    final now = _clock();
    final backoffUntil = _nextRemotePollAt;
    final delay = backoffUntil != null && now.isBefore(backoffUntil)
        ? backoffUntil.difference(now)
        : _isWarm(now)
        ? warmPollPeriod
        : idlePollPeriod;
    final timerGeneration = _pollTimerGeneration;
    _remotePollTimer = Timer(delay, () {
      if (timerGeneration != _pollTimerGeneration) return;
      _remotePollTimer = null;
      unawaited(_handleRemotePollTimer(timerGeneration));
    });
  }

  void _cancelRemotePollTimer() {
    _remotePollTimer?.cancel();
    _remotePollTimer = null;
    _pollTimerGeneration++;
  }

  Future<void> _handleRemotePollTimer(int timerGeneration) async {
    await _pollForRemoteChanges();
    if (timerGeneration == _pollTimerGeneration) {
      _armRemotePollTimer();
    }
  }

  bool _isWarm(DateTime now) {
    final until = _warmUntil;
    return until != null && now.isBefore(until);
  }

  void _rearmWarmPolling() {
    final now = _clock();
    final wasWarm = _isWarm(now);
    _warmUntil = now.add(warmDuration);
    _warmExpiryTimer?.cancel();
    _warmExpiryTimer = Timer(warmDuration, _expireWarmPolling);
    if (!wasWarm) _armRemotePollTimer();
  }

  void _expireWarmPolling() {
    final now = _clock();
    final until = _warmUntil;
    if (until != null && now.isBefore(until)) {
      _warmExpiryTimer = Timer(until.difference(now), _expireWarmPolling);
      return;
    }
    _warmExpiryTimer = null;
    _warmUntil = null;
    _armRemotePollTimer();
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
          !context.hasCurrentClientGeneration ||
          !_remotePollingForeground ||
          _running ||
          _gateHolds) {
        return;
      }
      final pollContext = context;
      final peerDeviceIds = pollContext.peerDeviceIds.toSet().toList()..sort();
      if (peerDeviceIds.isEmpty) return;
      final outcomes = await _mapPollConcurrentOrdered<String, _PollOutcome?>(
        peerDeviceIds,
        limit: 4,
        operation: (deviceId) async {
          if (generation != _pollGeneration ||
              !pollContext.hasCurrentClientGeneration) {
            return null;
          }
          try {
            return _PollOutcome(
              deviceId: deviceId,
              probe: await pollContext.transport.probeManifest(deviceId),
            );
          } catch (error) {
            return _PollOutcome(deviceId: deviceId, error: error);
          }
        },
      );
      if (generation != _pollGeneration ||
          !pollContext.hasCurrentClientGeneration ||
          !_remotePollingForeground ||
          outcomes.any((outcome) => outcome == null)) {
        return;
      }
      final completedOutcomes = outcomes.cast<_PollOutcome>();
      if (completedOutcomes.any((outcome) => outcome.error != null)) {
        _recordPollFailure(
          completedOutcomes
              .firstWhere((outcome) => outcome.error != null)
              .error,
        );
        return;
      }
      _resetPollBackoff();
      final changed = completedOutcomes.any((outcome) {
        final probe = outcome.probe!;
        if (!probe.exists) return true;
        final validator = probe.validator;
        return validator != null &&
            validator != pollContext.validators[outcome.deviceId];
      });
      if (changed) {
        _rearmWarmPolling();
        await signal(WebDavSyncTrigger.remoteChange);
        return;
      }
      if (completedOutcomes.any(
        (outcome) => outcome.probe!.exists && outcome.probe!.validator == null,
      )) {
        _pollDisabledNoValidators = true;
        _remotePollTimer?.cancel();
        _remotePollTimer = null;
      }
    } catch (error) {
      // A metadata hint never becomes a sync error. The ordinary lifecycle
      // and 15-minute cycles remain the durable retry and reporting path.
      _recordPollFailure(error);
    } finally {
      context?.transport.close();
      _polling = false;
      if (identical(_pollCompletion, completion)) _pollCompletion = null;
      if (!completion.isCompleted) completion.complete();
    }
  }

  void _recordPollFailure(Object? error) {
    // A failure the server ANSWERED (429/5xx) is the server asking for
    // space: that backoff holds even while full cycles succeed. A failure
    // with no status is connectivity, which a completed cycle disproves.
    _pollBackoffHoldsThroughCycles =
        error is WebDavException && error.statusCode != null;
    _consecutivePollFailures++;
    var delayMs = idlePollPeriod.inMilliseconds;
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
    _pollBackoffHoldsThroughCycles = false;
  }

  void disarm() {
    _contextProvider = null;
    _remotePollContextProvider = null;
    _periodic?.cancel();
    _periodic = null;
    _remotePollTimer?.cancel();
    _remotePollTimer = null;
    _warmExpiryTimer?.cancel();
    _warmExpiryTimer = null;
    _localChangeTimer?.cancel();
    _localChangeTimer = null;
    _dirtyDuringRun = false;
    _immediateDirtyDuringRun = false;
    _pendingLocalChangeKey = null;
    _pollDisabledNoValidators = false;
    _warmUntil = null;
    _resetPollBackoff();
    _pollGeneration++;
    _pollTimerGeneration++;
    final runner = _runner;
    if (runner is WebDavSyncCycleTransportOwner) {
      (runner as WebDavSyncCycleTransportOwner).closeCycleTransports();
    }
  }

  Future<WebDavSyncCycleReport> signal(WebDavSyncTrigger trigger) async {
    // A local change never queues behind an in-flight poll probe: the probe
    // can hold its completer for a full request deadline, which is exactly
    // the window an OS process freeze eats after a lifecycle handoff. The
    // overlap is benign — the poll owns a private transport, and a
    // late 'remote changed' conclusion is swallowed by the running guard.
    final pollCompletion =
        trigger == WebDavSyncTrigger.remoteChange ||
            trigger == WebDavSyncTrigger.localChange
        ? null
        : _pollCompletion;
    if (pollCompletion != null) await pollCompletion.future;
    final provider = _contextProvider;
    if (provider == null) {
      return const WebDavSyncCycleReport(
        disposition: WebDavSyncCycleDisposition.inactive,
      );
    }
    if (_capacityBlocked && trigger != WebDavSyncTrigger.manual) {
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
      if (trigger == WebDavSyncTrigger.localChange) {
        _rearmPendingLocalChange('a platform gate holds');
      }
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
    int? intentSequenceAtStart;
    var intentCycleCompleted = false;
    var intentCycleRequestedFollowUp = false;
    try {
      final context = await provider();
      if (context == null || !context.active || !context.isComplete) {
        return const WebDavSyncCycleReport(
          disposition: WebDavSyncCycleDisposition.inactive,
        );
      }
      _lastStartedAt = _clock();
      intentSequenceAtStart = _localChangeSequence;
      if (trigger == WebDavSyncTrigger.localChange) {
        final logicalKey = _pendingLocalChangeKey;
        _pendingLocalChangeKey = null;
        if (logicalKey != null) {
          try {
            localChangeObserver?.call(logicalKey);
          } catch (_) {
            // Observability must never prevent the already-admitted cycle.
          }
        }
      }
      final report = await _runner.runCycle(context, trigger: trigger);
      intentCycleCompleted =
          report.disposition == WebDavSyncCycleDisposition.completed ||
          report.disposition == WebDavSyncCycleDisposition.capacityBlocked;
      intentCycleRequestedFollowUp = report.localChangeFollowUp;
      if (report.disposition == WebDavSyncCycleDisposition.capacityBlocked) {
        _capacityBlocked = _localChangeSequence <= intentSequenceAtStart;
      } else if (report.disposition == WebDavSyncCycleDisposition.completed) {
        _capacityBlocked = false;
      }
      if (intentCycleCompleted &&
          _consecutivePollFailures > 0 &&
          !_pollBackoffHoldsThroughCycles) {
        // This cycle just proved the server reachable. Connectivity backoff
        // measures an outage and must not outlive one — a launch-time
        // network flap otherwise jails remote pulls for up to fifteen
        // minutes while pushes visibly succeed. Server-answered backoff
        // (rate limiting) deliberately stays.
        _resetPollBackoff();
        _armRemotePollTimer();
      }
      if (trigger == WebDavSyncTrigger.localChange ||
          trigger == WebDavSyncTrigger.manual) {
        _rearmWarmPolling();
      }
      if (report.localChangeFollowUp) {
        _dirtyDuringRun = true;
        _immediateDirtyDuringRun = true;
      }
      return report;
    } finally {
      _running = false;
      final dirtyDuringRun = _dirtyDuringRun;
      final immediateDirtyDuringRun = _immediateDirtyDuringRun;
      _dirtyDuringRun = false;
      _immediateDirtyDuringRun = false;
      if (intentSequenceAtStart != null) {
        _handleLocalChangeOutcome(
          sequenceAtStart: intentSequenceAtStart,
          completed: intentCycleCompleted,
          localChangeFollowUp: intentCycleRequestedFollowUp,
          immediateRetry: immediateDirtyDuringRun,
        );
      } else if (trigger == WebDavSyncTrigger.localChange) {
        // Includes context-provider exceptions as well as inactive snapshots.
        _rearmPendingLocalChange(
          'cycle did not start',
          immediate: immediateDirtyDuringRun,
        );
      }
      if (dirtyDuringRun &&
          _contextProvider != null &&
          _localChangeTimer == null &&
          (_pendingLocalChangeSequence != null || immediateDirtyDuringRun)) {
        _scheduleLocalChange(immediate: immediateDirtyDuringRun);
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
