import 'dart:async';

import 'webdav_sync_engine.dart';

enum WebDavSyncTrigger {
  launch,
  foreground,
  playbackStopped,
  background,
  periodic,
  manual,
}

abstract interface class WebDavSyncRuntimeGate {
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
    DateTime Function()? clock,
  }) : _runner = runner,
       _gate = gate,
       _clock = clock ?? DateTime.now;

  final WebDavSyncCycleRunner _runner;
  final WebDavSyncRuntimeGate _gate;
  final DateTime Function() _clock;
  final Duration debounce;
  final Duration period;

  WebDavSyncContextProvider? _contextProvider;
  Timer? _periodic;
  DateTime? _lastStartedAt;
  bool _running = false;

  bool get isArmed => _contextProvider != null;

  void arm(WebDavSyncContextProvider contextProvider) {
    _contextProvider = contextProvider;
    _periodic?.cancel();
    _periodic = Timer.periodic(period, (_) => unawaited(_signalPeriodic()));
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
  }

  Future<WebDavSyncCycleReport> signal(WebDavSyncTrigger trigger) async {
    final provider = _contextProvider;
    if (provider == null) {
      return const WebDavSyncCycleReport(
        disposition: WebDavSyncCycleDisposition.inactive,
      );
    }
    if (_gate.playbackActiveOnTelevision || _gate.tvOsLowMemory || _running) {
      return const WebDavSyncCycleReport(
        disposition: WebDavSyncCycleDisposition.inactive,
      );
    }
    final now = _clock();
    final last = _lastStartedAt;
    if (trigger != WebDavSyncTrigger.manual &&
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
      return await _runner.runCycle(context);
    } finally {
      _running = false;
    }
  }

  void dispose() => disarm();
}
