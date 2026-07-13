import 'package:flutter_test/flutter_test.dart';
import 'package:debrify/utils/concurrency.dart';

void main() {
  group('mapWithConcurrency', () {
    test('returns results in input order, not completion order', () async {
      // Earlier items finish LATER, so completion order is the reverse of input
      // order. Output must still follow input order.
      final result = await mapWithConcurrency<int, int>(
        [0, 1, 2, 3, 4],
        (i) async {
          await Future<void>.delayed(Duration(milliseconds: (5 - i) * 10));
          return i * 10;
        },
        concurrency: 8,
      );
      expect(result, [0, 10, 20, 30, 40]);
    });

    test('never exceeds the concurrency limit', () async {
      var inFlight = 0;
      var peak = 0;
      await mapWithConcurrency<int, int>(
        List<int>.generate(50, (i) => i),
        (i) async {
          inFlight++;
          if (inFlight > peak) peak = inFlight;
          await Future<void>.delayed(const Duration(milliseconds: 5));
          inFlight--;
          return i;
        },
        concurrency: 4,
      );
      expect(peak, lessThanOrEqualTo(4));
      expect(peak, greaterThan(1)); // it actually ran things in parallel
    });

    test('processes every item exactly once', () async {
      final seen = <int>[];
      final result = await mapWithConcurrency<int, int>(
        List<int>.generate(37, (i) => i),
        (i) async {
          seen.add(i);
          return i;
        },
        concurrency: 5,
      );
      expect(result, List<int>.generate(37, (i) => i));
      expect(seen.length, 37);
      expect(seen.toSet().length, 37); // no duplicates
    });

    test('empty input returns empty without running any task', () async {
      var ran = false;
      final result = await mapWithConcurrency<int, int>([], (i) async {
        ran = true;
        return i;
      });
      expect(result, isEmpty);
      expect(ran, isFalse);
    });

    test('concurrency larger than item count still completes', () async {
      final result = await mapWithConcurrency<int, int>(
        [1, 2, 3],
        (i) async => i + 100,
        concurrency: 20,
      );
      expect(result, [101, 102, 103]);
    });

    test('zero or negative concurrency is clamped, not a silent no-op',
        () async {
      final result = await mapWithConcurrency<int, int>(
        [1, 2, 3],
        (i) async => i * 2,
        concurrency: 0,
      );
      expect(result, [2, 4, 6]);

      final negative = await mapWithConcurrency<int, int>(
        [7],
        (i) async => i,
        concurrency: -3,
      );
      expect(negative, [7]);
    });

    test('a throwing task propagates the error', () async {
      expect(
        () => mapWithConcurrency<int, int>(
          [1, 2, 3],
          (i) async {
            if (i == 2) throw StateError('boom');
            return i;
          },
        ),
        throwsStateError,
      );
    });
  });
}
