import 'package:debrify/services/iptv_cw_history.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'recency split keeps movies and newest series per provider/explicit key',
    () async {
      final rows = await IptvCwHistory(
        readHistory: () async => [
          {
            'url': 'https://fixture.invalid/new',
            'name': 'New movie',
            'progress': 1.3,
          },
          {
            'seriesId': '7',
            'playlistId': 'a',
            'seriesName': 'Newest',
            'season': 2,
            'episode': 5,
            'progress': 0.5,
          },
          {'seriesId': '7', 'playlistId': 'a', 'seriesName': 'Older'},
          {
            'url': 'https://fixture.invalid/old',
            'name': 'Old movie',
            'progress': -0.2,
          },
          {'seriesId': '7', 'playlistId': 'b', 'group': 'Other provider'},
          {
            'seriesId': '8',
            'playlistId': 'a',
            '_seriesKey': 'a::7',
            'name': 'Explicit duplicate',
          },
        ],
      ).load();
      expect(rows.movies.map((e) => e.title), ['New movie', 'Old movie']);
      expect(rows.movies.map((e) => e.progress), [1.0, 0.0]);
      expect(rows.series.map((e) => e.title), ['Newest', 'Other provider']);
      expect(rows.series.map((e) => e.routeKey), [
        'xtream-series://a/7',
        'xtream-series://b/7',
      ]);
      expect(rows.series.first.seLabel, 'S2 · E5');
      expect(rows.series.first.raw['episode'], 5);
      expect(rows.isEmpty, isFalse);
      expect(() => rows.movies.clear(), throwsUnsupportedError);
      expect(() => rows.series.clear(), throwsUnsupportedError);
    },
  );

  test(
    'fallback titles and partial numeric episode labels retain IPTV rules',
    () async {
      final rows = await IptvCwHistory(
        readHistory: () async => [
          {'name': '', 'group': '', 'logoUrl': ''},
          {'name': ' ', 'group': ' ', 'logoUrl': ' '},
          {
            'seriesId': '1',
            'seriesName': '',
            'group': '',
            'name': 'Episode',
            'episode': 0,
          },
          {'seriesId': '2', 'season': -1.9},
          {'seriesId': '3', 'season': 2.9, 'episode': 5.8},
        ],
      ).load();
      expect(rows.movies.first.routeKey, '');
      expect(rows.movies.first.title, 'IPTV');
      expect(rows.movies.first.subtitle, 'IPTV');
      expect(rows.movies.first.posterUrl, isNull);
      expect(rows.movies.last.title, ' ');
      expect(rows.movies.last.posterUrl, ' ');
      expect(rows.series.map((e) => e.title), ['Episode', 'Series', 'Series']);
      expect(rows.series.map((e) => e.seLabel), ['E0', 'S-1', 'S2 · E5']);
      expect(rows.series.first.routeKey, 'xtream-series:///1');
    },
  );

  test(
    'routing payload and headers are detached without changing their values',
    () async {
      final headers = <String, dynamic>{'User-Agent': 'Fixture', 'X-Number': 4};
      final raw = <String, dynamic>{
        'url': 'https://fixture.invalid/movie',
        'playlistId': 'provider',
        'httpHeaders': headers,
        'positionMs': 60000,
        'durationMs': 180000,
      };
      final entry = (await IptvCwHistory(
        readHistory: () async => [raw],
      ).load()).movies.single;
      raw['playlistId'] = 'changed';
      headers['User-Agent'] = 'changed';
      expect(entry.raw['playlistId'], 'provider');
      expect(entry.raw['httpHeaders'], {
        'User-Agent': 'Fixture',
        'X-Number': 4,
      });
      expect(entry.raw['positionMs'], 60000);
      expect(() => entry.raw.clear(), throwsUnsupportedError);
      expect(
        () => (entry.raw['httpHeaders'] as Map).clear(),
        throwsUnsupportedError,
      );
    },
  );

  test(
    'empty history stays empty and read failures propagate without retries',
    () async {
      expect(
        (await IptvCwHistory(readHistory: () async => []).load()).isEmpty,
        isTrue,
      );
      var reads = 0;
      final error = StateError('fixture');
      final repository = IptvCwHistory(
        readHistory: () async {
          reads++;
          throw error;
        },
      );
      await expectLater(repository.load(), throwsA(same(error)));
      expect(reads, 1);
    },
  );
}
