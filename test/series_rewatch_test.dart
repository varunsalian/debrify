import 'package:flutter_test/flutter_test.dart';
import 'package:debrify/utils/series_rewatch.dart';

void main() {
  test('requires every episode of every regular season', () {
    final seasons = {
      0: [1],
      1: [1, 2],
      2: [1],
    };
    final progress = {'1-1': 100.0, '1-2': 100.0, '2-1': 100.0};
    expect(isSeriesFullyWatched(seasons, progress), true);
    progress['2-1'] = 99;
    expect(isSeriesFullyWatched(seasons, progress), false);
    progress.remove('2-1');
    expect(isSeriesFullyWatched(seasons, progress), false);
  });
  test('unknown seasons and specials-only inventories are not complete', () {
    expect(isSeriesFullyWatched({}, {}), false);
    expect(
      isSeriesFullyWatched(
        {
          1: [],
          2: [1],
        },
        {'2-1': 100},
      ),
      false,
    );
    expect(
      isSeriesFullyWatched(
        {
          0: [1],
        },
        {'0-1': 100},
      ),
      false,
    );
  });
}
