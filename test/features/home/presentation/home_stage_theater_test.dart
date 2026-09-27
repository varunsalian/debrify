import 'package:debrify/features/home/presentation/home_stage_theater.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _Fixture {
  bool current = true;
  bool eligible = true;
  bool showing = true;
  final changes = <bool>[];
  late final HomeStageTheater theater = HomeStageTheater(
    isCurrent: () => current,
    isEligible: () => eligible,
    isShowing: () => showing,
    onChanged: () => changes.add(theater.active),
  );
}

const down = KeyDownEvent(
  physicalKey: PhysicalKeyboardKey.space,
  logicalKey: LogicalKeyboardKey.space,
  timeStamp: Duration.zero,
);
const repeat = KeyRepeatEvent(
  physicalKey: PhysicalKeyboardKey.space,
  logicalKey: LogicalKeyboardKey.space,
  timeStamp: Duration.zero,
);
const up = KeyUpEvent(
  physicalKey: PhysicalKeyboardKey.space,
  logicalKey: LogicalKeyboardKey.space,
  timeStamp: Duration.zero,
);

void main() {
  test(
    'five-second dwell, observe-only wake and fresh dwell retain key grammar',
    () {
      fakeAsync((clock) {
        final f = _Fixture();
        f.theater.showingChanged();
        expect(f.theater.handleKey(down), isFalse);
        clock.elapse(const Duration(milliseconds: 4999));
        expect(f.changes, isEmpty);
        clock.elapse(const Duration(milliseconds: 1));
        expect(f.changes, [true]);
        expect(f.theater.handleKey(repeat), isFalse);
        expect(f.theater.handleKey(up), isFalse);
        expect(f.theater.active, isTrue);
        expect(f.theater.handleKey(down), isFalse);
        expect(f.changes, [true, false]);
        clock.elapse(const Duration(milliseconds: 4999));
        expect(f.theater.active, isFalse);
        clock.elapse(const Duration(milliseconds: 1));
        expect(f.changes, [true, false, true]);
        f.theater.dispose();
      });
    },
  );

  for (final gate in ['current', 'eligible', 'showing']) {
    test('dwell checks live $gate state before hiding the shelf', () {
      fakeAsync((clock) {
        final f = _Fixture();
        f.theater.showingChanged();
        clock.elapse(const Duration(seconds: 4));
        switch (gate) {
          case 'current':
            f.current = false;
          case 'eligible':
            f.eligible = false;
          case 'showing':
            f.showing = false;
        }
        clock.elapse(const Duration(seconds: 2));
        expect(f.theater.active, isFalse);
        expect(f.changes, isEmpty);
        f.theater.dispose();
      });
    });
  }

  test(
    'frame stop cancels pending dwell and restores an active shelf once',
    () {
      fakeAsync((clock) {
        final f = _Fixture();
        f.theater.showingChanged();
        clock.elapse(const Duration(seconds: 4));
        f.showing = false;
        f.theater.showingChanged();
        clock.elapse(const Duration(seconds: 2));
        expect(f.changes, isEmpty);
        f.showing = true;
        f.theater.showingChanged();
        clock.elapse(const Duration(seconds: 5));
        f.showing = false;
        f.theater.showingChanged();
        f.theater.showingChanged();
        expect(f.changes, [true, false]);
        expect(clock.nonPeriodicTimerCount, 0);
        f.theater.dispose();
      });
    },
  );

  test(
    'layout reset is silent, cancels old work and permits a fresh dwell',
    () {
      fakeAsync((clock) {
        final f = _Fixture();
        f.theater.showingChanged();
        clock.elapse(const Duration(seconds: 5));
        f.theater.reset();
        expect(f.theater.active, isFalse);
        expect(f.changes, [true]);
        f.theater.showingChanged();
        clock.elapse(const Duration(seconds: 4));
        f.theater.reset();
        clock.elapse(const Duration(seconds: 2));
        expect(f.changes, [true]);
        f.theater.showingChanged();
        clock.elapse(const Duration(seconds: 5));
        expect(f.theater.active, isTrue);
        expect(f.changes, [true, true]);
        f.eligible = false;
        f.theater.showingChanged();
        expect(f.changes, [true, true, false]);
        f.theater.dispose();
      });
    },
  );

  test(
    'disposal cancels pending work and prevents stale signals from rearming',
    () {
      fakeAsync((clock) {
        final f = _Fixture();
        f.theater.showingChanged();
        clock.elapse(const Duration(seconds: 5));
        f.theater.handleKey(down);
        f.theater.dispose();
        f.theater.showingChanged();
        f.theater.handleKey(down);
        f.theater.dispose();
        clock.elapse(const Duration(seconds: 6));
        expect(f.changes, [true, false]);
        expect(clock.nonPeriodicTimerCount, 0);
      });
    },
  );
}
