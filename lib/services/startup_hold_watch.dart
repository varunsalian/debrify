import 'dart:async';

import 'diagnostic_log.dart';

/// The steps a validated source goes through while the startup gate is held.
enum StartupHoldStage {
  waitVideoReady,
  externalAudio,
  resume,
  trackRestore,
  play,
}

typedef StartupHoldRecord =
    void Function(String event, StartupHoldStage stage, int elapsedMs);

/// Records when the startup gate outlasts source validation, and at which
/// step. A step that never finishes leaves the loading screen up with no
/// player error, so this is the only trace of it. Owned by the launch that
/// creates it: every exit calls [release], and a screen that was left stops
/// counting through [isCurrent].
class StartupHoldWatch {
  StartupHoldWatch({
    required bool Function() isCurrent,
    Duration threshold = defaultThreshold,
    StartupHoldRecord? record,
  }) : _isCurrent = isCurrent,
       _record = record ?? _recordDiagnostic {
    _timer = Timer(threshold, _onHeld);
  }

  static const Duration defaultThreshold = Duration(seconds: 20);

  final bool Function() _isCurrent;
  final StartupHoldRecord _record;
  final Stopwatch _elapsed = Stopwatch()..start();
  late final Timer _timer;
  StartupHoldStage _stage = StartupHoldStage.waitVideoReady;
  bool _held = false;
  bool _released = false;

  void stage(StartupHoldStage stage) => _stage = stage;

  void release() {
    if (_released) return;
    _released = true;
    _timer.cancel();
    if (_held && _isCurrent()) {
      _record(
        'startup_gate_released_late',
        _stage,
        _elapsed.elapsedMilliseconds,
      );
    }
  }

  void _onHeld() {
    if (_released || !_isCurrent()) return;
    _held = true;
    _record('startup_gate_held', _stage, _elapsed.elapsedMilliseconds);
  }

  static void _recordDiagnostic(
    String event,
    StartupHoldStage stage,
    int elapsedMs,
  ) => DiagnosticLog.instance.recordEvent(
    source: 'source_selection',
    event: event,
    level: DiagnosticLevel.warning,
    durable: true,
    fields: <String, Object?>{
      'stage': DiagnosticLabel(stage.name),
      'elapsed_ms': elapsedMs,
    },
  );
}
