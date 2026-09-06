import 'dart:async';

import 'package:debrify/screens/video_player/resume_controller.dart';
import 'package:debrify/services/resume_write_guard.dart';
import 'package:flutter_test/flutter_test.dart';

// Invariant pins against the actual old controller. The zone observes requested
// durations and delegates every timer unchanged to the existing test binding.
// It neither replaces DateTime.now nor proves deadline exhaustion/retry caps.
// Finite pumps below deliver specifically observed events, not cleanup retries.
// Immediate cancellation/pending-timer removal belongs in future correction
// tests: it is deliberately NOT an invariant asserted by this origin fixture.
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
  Completer<void>? heldSeek;

  @override
  Duration get playerPosition {
    positionReads++;
    return reportedPosition;
  }

  @override
  Future<void> seek(Duration target) {
    seeks.add(target);
    return heldSeek?.future ?? Future<void>.value();
  }

  // Only the existing seekForResume session surface is implemented. Unexpected
  // calls fail instead of supplying permissive defaults for unrelated features.
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unexpected session call: ${invocation.memberName}');
}

class _Fixture {
  final _Session session = _Session();
  late final ResumeController controller = ResumeController(session);
  final List<Duration> requestedWaits = <Duration>[];

  Future<void> start({bool verify = true, int targetMs = 30000}) =>
      runZoned<Future<void>>(
        () => controller.seekForResume(targetMs, verifyLanding: verify),
        zoneSpecification: ZoneSpecification(
          createTimer: (self, parent, zone, duration, callback) {
            requestedWaits.add(duration);
            return parent.createTimer(zone, duration, callback);
          },
        ),
      );
}

enum _Stop { userSeek, epoch, unmounted, disposed }

void main() {
  testWidgets('default false seeks and arms without starting verification', (
    tester,
  ) async {
    final f = _Fixture();
    // Omit the argument on the real method, not only on the fixture helper.
    await f.controller.seekForResume(_target.inMilliseconds);
    expect(f.session.seeks, <Duration>[_target]);
    expect(f.session.writeGuard.pendingTargetMs, _target.inMilliseconds);
    expect(f.session.positionReads, 0);
    // The binding's end-of-test timer invariant also checks the unobserved call.
  });

  testWidgets('80 percent boundary seeks but clears guard and skips verifier', (
    tester,
  ) async {
    final f = _Fixture();
    f.session.writeGuard.arm(30000);
    await f.start(targetMs: 80000);
    expect(f.session.seeks, <Duration>[const Duration(seconds: 80)]);
    expect(f.session.writeGuard.pendingTargetMs, isNull);
    expect(f.requestedWaits, isEmpty);
    expect(f.session.positionReads, 0);
  });

  testWidgets('startup returns before stable landing confirmation', (tester) async {
    final f = _Fixture();
    await f.start();
    expect(f.requestedWaits, <Duration>[_confirm]);
    expect(f.session.positionReads, 1);
    expect(f.session.seeks, <Duration>[_target]);
    await tester.pump(_confirm);
    expect(f.session.positionReads, 2);
    expect(f.requestedWaits, <Duration>[_confirm]);
    expect(f.session.seeks, <Duration>[_target]);
    // The verifier observes landing; it does not consume the persistence guard.
    expect(f.session.writeGuard.pendingTargetMs, 30000);
  });

  testWidgets('below tolerance polls then confirms at the inclusive boundary', (
    tester,
  ) async {
    final f = _Fixture();
    f.session.reportedPosition = const Duration(milliseconds: 19999);
    await f.start();
    expect(f.requestedWaits, <Duration>[_poll]);
    f.session.reportedPosition = const Duration(milliseconds: 20000);
    await tester.pump(_poll);
    expect(f.requestedWaits, <Duration>[_poll, _confirm]);
    await tester.pump(_confirm);
    expect(f.requestedWaits, <Duration>[_poll, _confirm]);
    expect(f.session.seeks, <Duration>[_target]);
  });

  testWidgets('transient landing returns to polling before a stable landing', (
    tester,
  ) async {
    final f = _Fixture();
    await f.start();
    expect(f.requestedWaits, <Duration>[_confirm]);
    f.session.reportedPosition = Duration.zero;
    await tester.pump(_confirm);
    expect(f.requestedWaits, <Duration>[_confirm, _poll]);
    f.session.reportedPosition = _target;
    await tester.pump(_poll);
    expect(f.requestedWaits, <Duration>[_confirm, _poll, _confirm]);
    await tester.pump(_confirm);
    expect(f.session.seeks, <Duration>[_target]);
    expect(f.requestedWaits, <Duration>[_confirm, _poll, _confirm]);
  });

  // This is a finite case matrix, not a polling/retry loop. Assert effects after
  // the original event boundary; do not assert timer retention after invalidation.
  for (final wait in <Duration>[_poll, _confirm]) {
    for (final stop in _Stop.values) {
      testWidgets('${stop.name} prevents effects after ${wait.inMilliseconds}ms', (
        tester,
      ) async {
        final f = _Fixture();
        f.session.reportedPosition = wait == _poll ? Duration.zero : _target;
        await f.start();
        expect(f.requestedWaits, <Duration>[wait]);
        final readsBeforeStop = f.session.positionReads;
        switch (stop) {
          case _Stop.userSeek:
            f.session.writeGuard.noteUserSeek();
            break;
          case _Stop.epoch:
            f.session.resumeVerifyEpoch++;
            break;
          case _Stop.unmounted:
            f.session.isMounted = false;
            break;
          case _Stop.disposed:
            f.session.screenDisposed = true;
            break;
        }
        await tester.pump(wait);
        expect(f.session.positionReads, readsBeforeStop);
        expect(f.session.seeks, <Duration>[_target]);
        expect(f.requestedWaits, <Duration>[wait]);
        expect(
          f.session.writeGuard.pendingTargetMs,
          stop == _Stop.userSeek ? isNull : equals(30000),
        );
      });
    }
  }

  testWidgets('same epoch overlapping calls each keep their confirmation', (
    tester,
  ) async {
    final f = _Fixture();
    await f.start();
    await f.start();
    expect(f.requestedWaits, <Duration>[_confirm, _confirm]);
    expect(f.session.positionReads, 2);
    await tester.pump(_confirm);
    expect(f.session.positionReads, 4);
    expect(f.session.seeks, <Duration>[_target, _target]);
    expect(f.requestedWaits, <Duration>[_confirm, _confirm]);
  });

  testWidgets('epoch is captured after the held initial seek completes', (
    tester,
  ) async {
    final f = _Fixture();
    final held = Completer<void>();
    f.session.heldSeek = held;
    var returned = false;
    final started = f.start().then((_) => returned = true);
    await tester.pump();
    expect(f.session.seeks, <Duration>[_target]);
    expect(returned, isFalse);
    expect(f.requestedWaits, isEmpty);
    f.session.resumeVerifyEpoch++;
    held.complete();
    await started;
    expect(returned, isTrue);
    expect(f.requestedWaits, <Duration>[_confirm]);
    await tester.pump(_confirm);
    expect(f.session.positionReads, 2);
    expect(f.session.seeks, <Duration>[_target]);
  });
}
