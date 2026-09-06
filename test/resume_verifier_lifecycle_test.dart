import 'dart:async';

import 'package:debrify/screens/video_player/resume_controller.dart';
import 'package:debrify/services/resume_write_guard.dart';
import 'package:flutter_test/flutter_test.dart';

// PREPARATION ONLY: cancelResumeVerification/dispose are proposed controller
// APIs, not implemented on the frozen origin. This file has NOT been run.
// Unlike the unchanged origin pin, these assert intended lifetime corrections.
const _poll = Duration(milliseconds: 200);
const _confirm = Duration(milliseconds: 800);
const _target = Duration(seconds: 30);

class _Session implements ResumeSession {
  @override
  final ResumeWriteGuard writeGuard = ResumeWriteGuard();
  @override
  Duration duration = const Duration(seconds: 100);
  @override
  int resumeVerifyEpoch = 0;
  @override
  bool isMounted = true;
  @override
  bool screenDisposed = false;
  Duration reportedPosition = _target;
  int positionReads = 0;
  final List<Duration> seeks = <Duration>[];
  Completer<void>? initialSeek;
  Completer<void>? retrySeek;
  final Completer<void> retryEntered = Completer<void>();

  @override
  Duration get playerPosition {
    positionReads++;
    return reportedPosition;
  }

  @override
  Future<void> seek(Duration target) {
    seeks.add(target);
    if (seeks.length == 1 && initialSeek != null) return initialSeek!.future;
    if (seeks.length == 2 && retrySeek != null) {
      retryEntered.complete();
      return retrySeek!.future;
    }
    return Future<void>.value();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unexpected session call: ${invocation.memberName}');
}

class _Fixture {
  final _Session session = _Session();
  late final ResumeController controller = ResumeController(session);
  final List<Duration> waits = <Duration>[];
  final List<Timer> timers = <Timer>[];
  // Observes a real timer after its callback completes the production wait,
  // but before the resulting microtask continuation can run.
  void Function(Duration)? afterTimerCallback;

  Future<void> start() => runZoned<Future<void>>(
    () => controller.seekForResume(30000, verifyLanding: true),
    zoneSpecification: ZoneSpecification(
      createTimer: (self, parent, zone, duration, callback) {
        waits.add(duration);
        final timer = parent.createTimer(zone, duration, () {
          callback();
          afterTimerCallback?.call(duration);
        });
        timers.add(timer);
        return timer;
      },
    ),
  );
}

// Real-clock held-seek tests only. Even a failed assertion releases the foreign
// seek and joins controller retirement. Report cleanup failures separately when
// there is already a primary failure, rather than replacing its error/stack.
Future<void> _finishHeld(
  _Fixture f,
  Completer<void> held, {
  Object? originalError,
}) async {
  try {
    final reads = f.session.positionReads;
    final seeks = f.session.seeks.length;
    final waits = f.waits.length;
    late final Future<void> disposed;
    late final bool timersInactive;
    try {
      disposed = f.controller.dispose();
      timersInactive = f.timers.every((timer) => !timer.isActive);
    } finally {
      if (!held.isCompleted) held.complete();
    }
    await disposed.timeout(const Duration(seconds: 10));
    expect(timersInactive, isTrue);
    expect(f.session.positionReads, reads);
    expect(f.session.seeks.length, seeks);
    expect(f.waits.length, waits);
  } catch (error, stack) {
    if (originalError == null) Error.throwWithStackTrace(error, stack);
    Zone.current.handleUncaughtError(error, stack);
  }
}

void main() {
  for (final wait in <Duration>[_poll, _confirm]) {
    for (final terminal in <bool>[false, true]) {
      testWidgets('${terminal ? 'dispose' : 'cancel'} settles $wait without time', (
        tester,
      ) async {
        final f = _Fixture();
        f.session.reportedPosition = wait == _poll ? Duration.zero : _target;
        await f.start();
        expect(f.waits, <Duration>[wait]);
        final reads = f.session.positionReads;
        var settled = false;
        late final Future<void> stopped;
        if (terminal) {
          stopped = f.controller.dispose();
          expect(f.timers.every((timer) => !timer.isActive), isTrue);
          f.controller.dispose();
        } else {
          stopped = f.controller.cancelResumeVerification();
          expect(f.timers.every((timer) => !timer.isActive), isTrue);
          f.controller.cancelResumeVerification();
        }
        unawaited(stopped.then((_) => settled = true));
        await tester.pump(); // Microtasks only; original timer must be cancelled.
        expect(settled, isTrue, reason: 'cancel must settle the suspended job');
        expect(f.session.positionReads, reads);
        expect(f.session.seeks, <Duration>[_target]);
        expect(f.waits, <Duration>[wait]);
        expect(f.session.writeGuard.pendingTargetMs, 30000);
        // Binding end-of-test invariant catches a retained timer. STOP must not
        // become "not landed", which would re-seek or schedule another wait.
      });
    }

    testWidgets('cancel after $wait callback dominates completed wait value', (
      tester,
    ) async {
      final f = _Fixture();
      f.session.reportedPosition = wait == _poll ? Duration.zero : _target;
      var cancelledAtBoundary = false;
      var settled = false;
      f.afterTimerCallback = (duration) {
        if (duration == wait && !cancelledAtBoundary) {
          cancelledAtBoundary = true;
          final stopped = f.controller.cancelResumeVerification();
          expectSync(f.timers.every((timer) => !timer.isActive), isTrue);
          unawaited(stopped.then((_) => settled = true));
        }
      };
      await f.start();
      final reads = f.session.positionReads;
      await tester.pump(wait);
      expect(cancelledAtBoundary, isTrue);
      expect(settled, isTrue);
      expect(f.session.positionReads, reads);
      expect(f.session.seeks, <Duration>[_target]);
    });
  }

  testWidgets('snapshot cancellation stops both overlaps but allows a new job', (
    tester,
  ) async {
    final f = _Fixture();
    await f.start();
    await f.start();
    var settled = false;
    final stopped = f.controller.cancelResumeVerification();
    expect(f.timers.every((timer) => !timer.isActive), isTrue);
    unawaited(stopped.then((_) => settled = true));
    await f.start();
    final beforeConfirm = f.session.positionReads;
    await tester.pump(_confirm);
    expect(settled, isTrue);
    expect(f.session.positionReads, beforeConfirm + 1);
    expect(f.session.seeks, <Duration>[_target, _target, _target]);
  });

  for (final terminal in <bool>[false, true]) {
    testWidgets('held initial seek across ${terminal ? 'dispose' : 'cancel'}', (
      tester,
    ) async {
      final f = _Fixture();
      final held = Completer<void>();
      f.session.initialSeek = held;
      final started = f.start();
      if (terminal) {
        f.controller.dispose();
        expect(f.timers.every((timer) => !timer.isActive), isTrue);
      } else {
        f.controller.cancelResumeVerification();
        expect(f.timers.every((timer) => !timer.isActive), isTrue);
        f.session.resumeVerifyEpoch++;
      }
      held.complete();
      await started;
      if (terminal) {
        expect(f.session.positionReads, 0);
        await tester.pump();
      } else {
        expect(f.session.positionReads, 1);
        await tester.pump(_confirm);
        expect(f.session.positionReads, 2);
      }
      expect(f.session.seeks, <Duration>[_target]);
    });
  }

  // REVIEW REQUIRED: these are ordinary tests using REAL DateTime and REAL
  // production Timers, not testWidgets/fake_async. A 10s admission watchdog
  // FAILS on failure to reach the first retry; it never advances time or retries.
  // They prove first-retry entry only, NOT exact deadline timing or the cap.
  test('cancelled held retry remains owned while a newer job completes', () async {
    final f = _Fixture();
    f.session.reportedPosition = Duration.zero;
    final held = Completer<void>();
    f.session.retrySeek = held;
    Object? originalError;
    try {
      await f.start();
      await f.session.retryEntered.future.timeout(const Duration(seconds: 10));
      var firstSettled = false;
      final firstStopped = f.controller.cancelResumeVerification();
      expect(f.timers.every((timer) => !timer.isActive), isTrue);
      unawaited(firstStopped.then((_) => firstSettled = true));
      // J1 cannot finalize yet: its already-issued seek is still held.
      // J2 then J3 demonstrate snapshot cancellation with a still-retiring J1.
      f.session.reportedPosition = _target;
      await f.start();
      var secondSettled = false;
      final secondStopped = f.controller.cancelResumeVerification();
      expect(f.timers.every((timer) => !timer.isActive), isTrue);
      unawaited(secondStopped.then((_) => secondSettled = true));
      final confirmed = Completer<void>();
      f.afterTimerCallback = (duration) {
        if (duration == _confirm && !confirmed.isCompleted) confirmed.complete();
      };
      await f.start();
      expect(firstSettled, isFalse);
      expect(secondSettled, isFalse);
      final reads = f.session.positionReads;
      held.complete(); // Old finalizer must not erase/cancel J3 ownership.
      await Future.wait(<Future<void>>[firstStopped, secondStopped])
          .timeout(const Duration(seconds: 10));
      expect(firstSettled, isTrue);
      expect(secondSettled, isTrue);
      await confirmed.future.timeout(const Duration(seconds: 10));
      await Future<void>.delayed(Duration.zero); // Next real event after callback.
      expect(f.session.positionReads, reads + 1);
      expect(f.session.seeks, <Duration>[_target, _target, _target, _target]);
    } catch (error) {
      originalError = error;
      rethrow;
    } finally {
      await _finishHeld(f, held, originalError: originalError);
    }
  });

  test('cancellation does not swallow a held retry seek error', () async {
    final f = _Fixture();
    f.session.reportedPosition = Duration.zero;
    late final Completer<void> held;
    final surfaced = Completer<(Object, StackTrace)>();
    final failure = StateError('native seek failed');
    final failureStack = StackTrace.current;
    final parentZone = Zone.current;
    final startup = Completer<void>();
    runZonedGuarded(() {
      // Keep the failed future in the same error zone as the real verifier.
      held = Completer<void>();
      f.session.retrySeek = held;
      f.start().then((_) => startup.complete());
    }, (error, stack) {
      if (identical(error, failure) &&
          stack.toString() == failureStack.toString() &&
          !surfaced.isCompleted) {
        surfaced.complete((error, stack));
      } else {
        parentZone.handleUncaughtError(error, stack);
      }
    });
    Object? originalError;
    try {
      await startup.future.timeout(const Duration(seconds: 10));
      await f.session.retryEntered.future.timeout(const Duration(seconds: 10));
      var firstSettled = false;
      var secondSettled = false;
      final firstStopped = f.controller.cancelResumeVerification();
      expect(f.timers.every((timer) => !timer.isActive), isTrue);
      final secondStopped = f.controller.cancelResumeVerification();
      expect(f.timers.every((timer) => !timer.isActive), isTrue);
      unawaited(firstStopped.then((_) => firstSettled = true));
      unawaited(secondStopped.then((_) => secondSettled = true));
      await Future<void>.delayed(Duration.zero);
      expect(firstSettled, isFalse);
      expect(secondSettled, isFalse);
      held.completeError(failure, failureStack);
      final observed = await surfaced.future.timeout(const Duration(seconds: 10));
      expect(observed.$1, same(failure));
      expect(observed.$2.toString(), failureStack.toString());
      await Future.wait(<Future<void>>[firstStopped, secondStopped])
          .timeout(const Duration(seconds: 10));
      expect(firstSettled, isTrue);
      expect(secondSettled, isTrue);
      expect(f.session.seeks, <Duration>[_target, _target]);
    } catch (error) {
      originalError = error;
      rethrow;
    } finally {
      await _finishHeld(f, held, originalError: originalError);
    }
  });
}
