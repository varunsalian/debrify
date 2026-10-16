import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'video_player_environment.dart';
import 'vp_fixture_actions.dart';

/// Observes real await completion and timers belonging to landing verification.
/// It changes neither DateTime.now nor a production deadline.
class ResumeVerifierDriver {
  ResumeVerifierDriver(this.t, this.f);
  final WidgetTester t;
  final VideoPlayerEnvironment f;
  final awaits = <VpFixtureActivity>[];
  final timers = <(Duration, Timer)>[];
  final periodic = <(Duration, Timer)>[];
  final logs = <String>[];
  DebugPrintCallback? oldPrint;
  bool get pending => awaits.any((a) => !a.isCompleted);
  void captureLogs() {
    oldPrint = debugPrint;
    debugPrint = (message, {wrapWidth}) {
      logs.add(message ?? '');
      oldPrint!(message, wrapWidth: wrapWidth);
    };
  }

  T observe<T>(T Function() body) => runZoned(
    body,
    zoneSpecification: ZoneSpecification(
      registerUnaryCallback:
          <R, V>(self, parent, zone, R Function(V) callback) {
            final frames = StackTrace.current.toString().split('\n');
            final frame = frames
                .where((v) => v.contains('package:debrify/'))
                .firstOrNull;
            final selected = frame?.contains('verifyResumeLanding') ?? false;
            final activity = selected
                ? f.actions.begin('resume-verifier-await')
                : null;
            if (activity != null) awaits.add(activity);
            return parent.registerUnaryCallback(zone, (V value) {
              try {
                return callback(value);
              } finally {
                activity?.complete();
              }
            });
          },
      createTimer: (self, parent, zone, duration, callback) {
        final selected = StackTrace.current.toString().contains(
          'resumeSeekLanded',
        );
        final timer = parent.createTimer(zone, duration, callback);
        if (selected) timers.add((duration, timer));
        return timer;
      },
      createPeriodicTimer: (self, parent, zone, duration, callback) {
        final timer = parent.createPeriodicTimer(zone, duration, callback);
        periodic.add((duration, timer));
        return timer;
      },
    ),
  );
  Future<void> drain() async {
    await f.until(
      t,
      () => !pending,
      reason:
          'Every original landing verifier await must finish before teardown',
    );
    await f.actions.settle(t);
    expect(timers.where((v) => v.$2.isActive), isEmpty);
  }

  void restoreLogs() {
    if (oldPrint != null) debugPrint = oldPrint!;
  }
}
