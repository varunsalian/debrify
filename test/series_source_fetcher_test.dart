import 'package:flutter_test/flutter_test.dart';

import 'package:debrify/models/torrent.dart';
import 'package:debrify/services/series_source_fetcher.dart';

Torrent t(
  String name, {
  String infohash = '',
  String? directUrl,
}) =>
    Torrent(
      rowid: 0,
      infohash: infohash,
      name: name,
      sizeBytes: 0,
      createdUnix: 0,
      seeders: 0,
      leechers: 0,
      completed: 0,
      scrapedDate: 0,
      streamType: directUrl != null ? StreamType.directUrl : StreamType.torrent,
      directUrl: directUrl,
    );

void main() {
  group('SeriesSourceFetcher.mergeSources', () {
    test('append-only: existing entries keep their positions', () {
      final existing = [t('a', infohash: 'AAA'), t('b', infohash: 'BBB')];
      final fetched = [t('c', infohash: 'CCC'), t('d', infohash: 'DDD')];
      final merged = SeriesSourceFetcher.mergeSources(existing, fetched);
      expect(merged.map((x) => x.name).toList(), ['a', 'b', 'c', 'd']);
    });

    test('dedupes by infohash, case-insensitive', () {
      final existing = [t('a', infohash: 'AbC123')];
      final fetched = [t('a-dupe', infohash: 'ABC123'), t('b', infohash: 'X1')];
      final merged = SeriesSourceFetcher.mergeSources(existing, fetched);
      expect(merged.map((x) => x.name).toList(), ['a', 'b']);
    });

    test('dedupes direct streams by URL, falls back to name', () {
      final existing = [
        t('stream', directUrl: 'https://x/1.mp4'),
        t('no-id-at-all'),
      ];
      final fetched = [
        t('stream-dupe', directUrl: 'https://x/1.mp4'),
        t('no-id-at-all'),
        t('fresh', directUrl: 'https://x/2.mp4'),
      ];
      final merged = SeriesSourceFetcher.mergeSources(existing, fetched);
      expect(merged.map((x) => x.name).toList(),
          ['stream', 'no-id-at-all', 'fresh']);
    });

    test('duplicates WITHIN the fetched batch collapse to one', () {
      final merged = SeriesSourceFetcher.mergeSources(
        [],
        [t('a', infohash: 'A1'), t('a-dupe', infohash: 'a1')],
      );
      expect(merged.length, 1);
    });
  });

  group('SeriesSourceFetcher.fetch', () {
    test('success (even empty) flips only that mode\'s flag', () async {
      final fetcher = SeriesSourceFetcher(
        season: 1,
        episode: 1,
        searchPacks: (s, e) async => <Torrent>[],
        searchEpisodes: (s, e) async => [t('e', infohash: 'E1')],
      );
      expect(fetcher.packsFetched, isFalse);
      expect(fetcher.episodesFetched, isFalse);

      final packs = await fetcher.fetch(SeriesSourceFetcher.modePacks);
      expect(packs, isEmpty);
      expect(fetcher.packsFetched, isTrue);
      expect(fetcher.episodesFetched, isFalse);

      final eps = await fetcher.fetch(SeriesSourceFetcher.modeEpisodes);
      expect(eps, hasLength(1));
      expect(fetcher.episodesFetched, isTrue);
    });

    test('targets the caller\'s current position, launch episode as fallback',
        () async {
      final seen = <String>[];
      final fetcher = SeriesSourceFetcher(
        season: 1,
        episode: 1,
        searchPacks: (s, e) async {
          seen.add('packs S${s}E$e');
          return <Torrent>[];
        },
        searchEpisodes: (s, e) async {
          seen.add('eps S${s}E$e');
          return <Torrent>[];
        },
      );
      // Auto-advanced mid-pack: player says we're on S1E3 now.
      await fetcher.fetch(SeriesSourceFetcher.modeEpisodes,
          season: 1, episode: 3);
      // No position given → launch episode.
      await fetcher.fetch(SeriesSourceFetcher.modePacks);
      expect(seen, ['eps S1E3', 'packs S1E1']);
    });

    test('failure (null) leaves the flag down so the button can retry',
        () async {
      final fetcher = SeriesSourceFetcher(
        season: 1,
        episode: 1,
        searchPacks: (s, e) async => null,
        searchEpisodes: (s, e) async => null,
      );
      expect(await fetcher.fetch(SeriesSourceFetcher.modePacks), isNull);
      expect(fetcher.packsFetched, isFalse);
    });

    test('unknown mode is a no-op', () async {
      final fetcher = SeriesSourceFetcher(
        season: 1,
        episode: 1,
        searchPacks: (s, e) async => <Torrent>[],
        searchEpisodes: (s, e) async => <Torrent>[],
      );
      expect(await fetcher.fetch('bogus'), isNull);
      expect(fetcher.packsFetched, isFalse);
      expect(fetcher.episodesFetched, isFalse);
    });

    test('flavors reject each other\'s modes', () async {
      final series = SeriesSourceFetcher(
        season: 1,
        episode: 1,
        searchPacks: (s, e) async => <Torrent>[],
        searchEpisodes: (s, e) async => <Torrent>[],
      );
      expect(series.isMovie, isFalse);
      expect(await series.fetch(SeriesSourceFetcher.modeMovie), isNull);
      expect(series.movieFetched, isTrue); // pre-marked: no movie button

      final movie = SeriesSourceFetcher.movie(
        searchMovie: () async => [t('m', infohash: 'M1')],
      );
      expect(movie.isMovie, isTrue);
      expect(movie.packsFetched, isTrue); // pre-marked: no series buttons
      expect(movie.episodesFetched, isTrue);
      expect(await movie.fetch(SeriesSourceFetcher.modePacks), isNull);
      expect(await movie.fetch(SeriesSourceFetcher.modeEpisodes), isNull);
    });

    test('movie flavor: success flips movieFetched, failure retries', () async {
      var fail = true;
      final movie = SeriesSourceFetcher.movie(
        searchMovie: () async => fail ? null : [t('m', infohash: 'M1')],
      );
      expect(await movie.fetch(SeriesSourceFetcher.modeMovie), isNull);
      expect(movie.movieFetched, isFalse); // failed → button stays
      fail = false;
      expect(
          await movie.fetch(SeriesSourceFetcher.modeMovie), hasLength(1));
      expect(movie.movieFetched, isTrue);
    });
  });

  group('SeriesSourceFetcher automatic candidate validation', () {
    test(
      'defaults to allowing candidates for backward compatibility',
      () async {
        final fetcher = SeriesSourceFetcher(
          season: 1,
          episode: 1,
          searchPacks: (s, e) async => <Torrent>[],
          searchEpisodes: (s, e) async => <Torrent>[],
        );

        expect(
          await fetcher.allowsCandidate(
            t('direct', directUrl: 'https://x/1.mp4'),
          ),
          isTrue,
        );
      },
    );

    test(
      'delegates automatic candidates to the configured preflight',
      () async {
        final seen = <String>[];
        final fetcher = SeriesSourceFetcher(
          season: 1,
          episode: 1,
          searchPacks: (s, e) async => <Torrent>[],
          searchEpisodes: (s, e) async => <Torrent>[],
          validateCandidate: (source) async {
            seen.add(source.name);
            return source.name != 'dead';
          },
        );

        expect(
          await fetcher.allowsCandidate(
            t('dead', directUrl: 'https://x/dead.mp4'),
          ),
          isFalse,
        );
        expect(
          await fetcher.allowsCandidate(
            t('alive', directUrl: 'https://x/alive.mp4'),
          ),
          isTrue,
        );
        expect(seen, ['dead', 'alive']);
      },
    );

    test('validation failure is fail-open', () async {
      final fetcher = SeriesSourceFetcher(
        season: 1,
        episode: 1,
        searchPacks: (s, e) async => <Torrent>[],
        searchEpisodes: (s, e) async => <Torrent>[],
        validateCandidate: (_) async => throw StateError('prefs unavailable'),
      );

      expect(
        await fetcher.allowsCandidate(
          t('unknown', directUrl: 'https://x/unknown.mp4'),
        ),
        isTrue,
      );
    });
  });
}
