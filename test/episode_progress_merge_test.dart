import 'package:debrify/utils/episode_progress_merge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('buildEpisodeTrackerSnapshot', () {
    test('watched wins and partial progress only raises meaningful values', () {
      final result = buildEpisodeTrackerSnapshot(
        watched: const {'1-1'},
        playback: const {'1-1': 20, '1-2': 5, '1-3': 42.5, '2_1': 101},
      );

      expect(result, const {'1_1': 100.0, '1_3': 42.5, '2_1': 100.0});
    });

    test('ignores malformed episode keys and non-finite progress', () {
      final result = buildEpisodeTrackerSnapshot(
        watched: const {'bad', '1-2'},
        playback: {'also-bad': 50, '1-3': double.nan},
      );

      expect(result, const {'1_2': 100.0});
    });
  });

  test(
    'furthestEpisodeTrackerPercent clamps and selects the furthest source',
    () {
      expect(furthestEpisodeTrackerPercent([null, 35, 72.5]), 72.5);
      expect(furthestEpisodeTrackerPercent([-5, 140]), 100.0);
      expect(furthestEpisodeTrackerPercent([null, double.infinity]), isNull);
    },
  );
}
