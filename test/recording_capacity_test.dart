import 'package:debrify/services/recording_capacity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('peakOverlap', () {
    test('empty and fully-outside intervals never count', () {
      expect(peakOverlap(const [], 100, 200), 0);
      expect(peakOverlap(const [(0, 100), (200, 300)], 100, 200), 0);
    });

    test('a single overlapping interval peaks at 1', () {
      expect(peakOverlap(const [(150, 250)], 100, 200), 1);
      expect(peakOverlap(const [(0, 1000)], 100, 200), 1);
    });

    test('back-to-back intervals never overlap (half-open windows)', () {
      // A ends exactly when B starts: peak is 1, not 2.
      expect(peakOverlap(const [(100, 150), (150, 200)], 100, 200), 1);
      // Three in a chain: still 1.
      expect(
        peakOverlap(const [(100, 130), (130, 160), (160, 200)], 100, 200),
        1,
      );
    });

    test('true simultaneity counts every participant', () {
      expect(peakOverlap(const [(100, 200), (150, 250)], 100, 300), 2);
      expect(
        peakOverlap(const [(0, 300), (100, 200), (150, 180)], 100, 200),
        3,
      );
    });

    test('the peak is measured inside the window only', () {
      // Both intervals overlap each other, but only before the window: at
      // 100+ a single one remains.
      expect(peakOverlap(const [(0, 120), (50, 300)], 150, 300), 1);
    });

    test('disjoint clusters report the busiest moment', () {
      expect(
        peakOverlap(
          const [(100, 140), (110, 140), (160, 200), (170, 200), (180, 200)],
          100,
          200,
        ),
        3,
      );
    });

    test('degenerate intervals are ignored', () {
      expect(peakOverlap(const [(150, 150), (200, 100)], 100, 300), 0);
    });
  });
}
