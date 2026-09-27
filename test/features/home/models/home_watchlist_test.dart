import 'package:debrify/features/home/models/home_watchlist.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'case-insensitive series grouping preserves order, duplicates and original metadata',
    () {
      StremioMeta item(String id, String type) =>
          StremioMeta(id: id, type: type, name: id, poster: 'poster:$id');
      final movie = item('m', 'movie');
      final series = item('s', 'SeRiEs');
      final spaced = item('spaced', 'series ');
      final unknown = item('other', 'channel');
      final input = [series, movie, spaced, series, unknown];
      final result = HomeWatchlist.fromItems(input);
      expect(result.movies, [movie, spaced, unknown]);
      expect(result.series, [series, series]);
      expect(result.movies.first, same(movie));
      expect(result.series.first, same(series));
      input.clear();
      expect(result.movies.length, 3);
      expect(result.series.length, 2);
      expect(result.movies.clear, throwsUnsupportedError);
      expect(result.series.clear, throwsUnsupportedError);
    },
  );

  test('empty refresh clears both rows with immutable membership', () {
    final result = HomeWatchlist.fromItems([]);
    expect(result.movies, isEmpty);
    expect(result.series, isEmpty);
    expect(result.movies.clear, throwsUnsupportedError);
    expect(result.series.clear, throwsUnsupportedError);
  });
}
