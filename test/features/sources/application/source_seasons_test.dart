import 'package:debrify/features/sources/application/source_seasons.dart';
import 'package:debrify/models/advanced_search_selection.dart';
import 'package:debrify/models/torrent.dart';
import 'package:flutter_test/flutter_test.dart';

Torrent row(
  String name, {
  String? coverage,
  int? season,
  int? start,
  int? end,
  StreamType type = StreamType.torrent,
}) => Torrent(
  rowid: 0,
  infohash: name,
  name: name,
  sizeBytes: 0,
  createdUnix: 0,
  seeders: 0,
  leechers: 0,
  completed: 0,
  scrapedDate: 0,
  streamType: type,
  coverageType: coverage,
  seasonNumber: season,
  startSeason: start,
  endSeason: end,
);

void main() {
  AdvancedSearchSelection selection({
    bool series = true,
    int? season,
    int? episode,
  }) => AdvancedSearchSelection(
    imdbId: 'fixture',
    title: 'Fixture',
    isSeries: series,
    season: season,
    episode: episode,
  );

  test('movies and episode selections retain every stream and input order', () {
    final rows = [
      row('direct', type: StreamType.directUrl),
      row('pack', coverage: 'seasonPack', season: 1),
      row('external', type: StreamType.externalUrl),
    ];
    for (final chosen in [
      selection(series: false),
      selection(season: 2, episode: 3),
      selection(episode: 3),
    ]) {
      final filtered = filterSourceSeasonPacks(
        rows,
        selection: chosen,
        bindMode: false,
        isIptvSource: (_) => throw StateError('must not inspect IPTV'),
      );
      expect(filtered, same(rows));
    }
  });

  test('unscoped series keeps only torrents, including unknown coverage', () {
    final torrent = row('unknown');
    final direct = row('direct', type: StreamType.directUrl);
    final external = row('external', type: StreamType.externalUrl);
    final rows = [direct, torrent, external];
    expect(
      filterSourceSeasonPacks(
        rows,
        selection: selection(),
        bindMode: false,
        isIptvSource: (_) => throw StateError('disabled binding'),
      ),
      [torrent],
    );
    expect(rows, [direct, torrent, external]);
  });

  test(
    'binding permits owned IPTV direct entries but no other direct streams',
    () {
      final iptv = row('IPTV', type: StreamType.directUrl);
      final other = row('other', type: StreamType.directUrl);
      final torrent = row('torrent');
      final inspected = <Torrent>[];
      expect(
        filterSourceSeasonPacks(
          [other, iptv, torrent],
          selection: selection(),
          bindMode: true,
          isIptvSource: (candidate) {
            inspected.add(candidate);
            return identical(candidate, iptv);
          },
        ),
        [iptv, torrent],
      );
      expect(inspected, [other, iptv]);
    },
  );

  test(
    'season scope keeps provider order and conservative coverage behavior',
    () {
      final unknown = row('unknown');
      final exact = row('exact', coverage: 'seasonPack', season: 4);
      final complete = row('complete', coverage: 'completeSeries');
      final range = row('range', coverage: 'multiSeasonPack', start: 3, end: 5);
      final rows = [
        unknown,
        row('wrong', coverage: 'seasonPack', season: 3),
        exact,
        row('missing range', coverage: 'multiSeasonPack', start: 4),
        complete,
        range,
        row('reversed', coverage: 'multiSeasonPack', start: 5, end: 3),
      ];
      expect(
        filterSourceSeasonPacks(
          rows,
          selection: selection(season: 4),
          bindMode: false,
          isIptvSource: (_) => false,
        ),
        [unknown, exact, complete, range],
      );
      expect(rows, hasLength(7));
    },
  );

  for (final name in [
    'Show.S04E01',
    'Show.S4E01',
    'Show.Season 4',
    'Show.SEASON4',
    'Show.4x01',
    'Show.S40E01',
  ]) {
    test('retains legacy single-episode substring match: $name', () {
      final torrent = row(name, coverage: 'singleEpisode');
      expect(
        filterSourceSeasonPacks(
          [torrent],
          selection: selection(season: 4),
          bindMode: false,
          isIptvSource: (_) => false,
        ),
        [torrent],
      );
    });
  }

  test('single episode with no matching season token is excluded', () {
    expect(
      filterSourceSeasonPacks(
        [row('Show.S03E01', coverage: 'singleEpisode')],
        selection: selection(season: 4),
        bindMode: false,
        isIptvSource: (_) => false,
      ),
      isEmpty,
    );
  });

  test('fallback seasons combine positive pack numbers and bounded ranges', () {
    final rows = [
      row('one', season: 4),
      row('duplicates', start: 3, end: 5),
      row('specials', season: 0, start: -2, end: 2),
      row('backwards', start: 8, end: 6),
      row('missing', start: 9),
      row('too wide', start: 20, end: 71),
    ];
    expect(deriveSourceSeasons(rows), [1, 2, 3, 4, 5]);
  });

  test('range expansion accepts exactly fifty steps, rejects fifty-one', () {
    expect(
      deriveSourceSeasons([row('range', start: 1, end: 51)]),
      List.generate(51, (index) => index + 1),
    );
    expect(deriveSourceSeasons([row('range', start: 1, end: 52)]), isEmpty);
  });

  test(
    'menu prefers metadata over result fallback and retains a missing selection',
    () {
      final metadata = [1, 3];
      final derived = [2, 4];
      expect(
        sourceSeasonMenu(available: metadata, derived: derived, selected: 5),
        [1, 3, 5],
      );
      expect(metadata, [1, 3]);
      expect(derived, [2, 4]);
      expect(sourceSeasonMenu(available: [], derived: derived, selected: 1), [
        1,
        2,
        4,
      ]);
      expect(
        sourceSeasonMenu(available: metadata, derived: derived, selected: 3),
        same(metadata),
      );
      expect(sourceSeasonMenu(available: [], derived: [], selected: 0), [0]);
    },
  );
}
