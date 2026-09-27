import 'package:debrify/features/home/presentation/home_hero_swap.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('only the latest title applies after its full focus-rest interval', () {
    fakeAsync((clock) {
      final swap = HomeHeroSwap();
      final applied = <String>[];
      swap.schedule(isCurrent: () => true, apply: () => applied.add('A'));
      clock.elapse(const Duration(milliseconds: 150));
      swap.schedule(isCurrent: () => true, apply: () => applied.add('B'));
      expect(clock.nonPeriodicTimerCount, 1);
      clock.elapse(const Duration(milliseconds: 259));
      expect(applied, isEmpty);
      clock.elapse(const Duration(milliseconds: 1));
      expect(applied, ['B']);
      expect(clock.nonPeriodicTimerCount, 0);
      swap.dispose();
    });
  });

  test('cancel allows rearming but disposal rejects future schedules', () {
    fakeAsync((clock) {
      final swap = HomeHeroSwap();
      var calls = 0;
      void schedule() =>
          swap.schedule(isCurrent: () => true, apply: () => calls++);
      schedule();
      swap.cancel();
      expect(clock.nonPeriodicTimerCount, 0);
      clock.elapse(const Duration(seconds: 1));
      expect(calls, 0);
      schedule();
      clock.elapse(const Duration(milliseconds: 260));
      expect(calls, 1);
      schedule();
      swap.dispose();
      schedule();
      clock.elapse(const Duration(seconds: 1));
      expect(calls, 1);
      expect(clock.nonPeriodicTimerCount, 0);
    });
  });

  test('current-view check is evaluated at firing, not when scheduled', () {
    fakeAsync((clock) {
      final swap = HomeHeroSwap();
      var current = true;
      var checks = 0;
      var calls = 0;
      swap.schedule(
        isCurrent: () {
          checks++;
          return current;
        },
        apply: () => calls++,
      );
      expect(checks, 0);
      current = false;
      clock.elapse(const Duration(milliseconds: 260));
      expect(checks, 1);
      expect(calls, 0);
      swap.dispose();
    });
  });

  test('applying a title may schedule another without losing its timer', () {
    fakeAsync((clock) {
      final swap = HomeHeroSwap();
      final applied = <String>[];
      swap.schedule(
        isCurrent: () => true,
        apply: () {
          applied.add('A');
          swap.schedule(isCurrent: () => true, apply: () => applied.add('B'));
        },
      );
      clock.elapse(const Duration(milliseconds: 260));
      expect(applied, ['A']);
      expect(clock.nonPeriodicTimerCount, 1);
      swap.cancel();
      clock.elapse(const Duration(milliseconds: 260));
      expect(applied, ['A']);
      swap.dispose();
    });
  });
}
