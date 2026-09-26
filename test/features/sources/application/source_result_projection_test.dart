import 'package:debrify/features/sources/application/source_result_projection.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/models/torrent_filter_state.dart';
import 'package:flutter_test/flutter_test.dart';

Torrent row(
  String name, {
  String? hash,
  String source = 'first',
  int size = 100,
  int seeders = 1,
  int date = 1,
}) => Torrent(
  rowid: 0,
  infohash: hash ?? name,
  name: name,
  source: source,
  sizeBytes: size,
  seeders: seeders,
  createdUnix: date,
  leechers: 0,
  completed: 0,
  scrapedDate: 0,
);

List<Torrent> project(
  List<Torrent> rows, {
  String? source,
  Map<String, String> aliases = const {},
  bool series = false,
  TorrentFilterState filters = const TorrentFilterState.empty(),
  List<String> priority = const [],
  String sort = 'source',
  bool ascending = true,
}) => projectSourceResults(
  rows,
  sourceFilter: source,
  sourceAliases: aliases,
  isSeries: series,
  filters: filters,
  sourcePriority: priority,
  sortBy: sort,
  sortAsc: ascending,
);

void main() {
  test('provider aliases filter before cross-provider deduplication', () {
    final preferred = row('preferred', hash: 'shared');
    final selected = row('selected', hash: 'shared', source: 'custom engine');
    expect(
      project(
        [preferred, selected],
        source: 'engine:configured',
        aliases: {'custom engine': 'engine:configured'},
        priority: ['engine:first', 'engine:configured'],
      ),
      [same(selected)],
    );
  });

  test(
    'quality filters precede priority dedupe and retain eligible duplicate',
    () {
      final preferred = row('Title 720p', hash: 'shared');
      final eligible = row('Title 1080p', hash: 'shared', source: 'second');
      expect(
        project(
          [preferred, eligible],
          priority: ['engine:first', 'engine:second'],
          filters: TorrentFilterState(qualities: {QualityTier.fullHd}),
        ),
        [same(eligible)],
      );
    },
  );

  test(
    'series ignore size alone, preserving other facets and filter state',
    () {
      final hd = row('Title 1080p');
      final sd = row('Title 480p');
      final filters = TorrentFilterState(
        qualities: {QualityTier.fullHd},
        sizes: {SizeBucket.over40gb},
      );
      expect(project([hd, sd], filters: filters), isEmpty);
      expect(project([hd, sd], filters: filters, series: true), [same(hd)]);
      expect(filters.sizes, {SizeBucket.over40gb});
    },
  );

  test(
    'provider priority selects duplicate identity before explicit sorting',
    () {
      final discarded = row('AAA', hash: 'shared');
      final retained = row('ZZZ', hash: 'shared', source: 'second');
      final other = row('MMM');
      expect(
        project(
          [discarded, retained, other],
          priority: ['engine:second', 'engine:first'],
          sort: 'name',
        ),
        [same(other), same(retained)],
      );
    },
  );

  for (final sort in ['name', 'size', 'seeders', 'date']) {
    test('$sort supports both directions after provider ordering', () {
      final low = row('alpha', size: 10, seeders: 2, date: 3);
      final high = row('Beta', source: 'second', size: 20, seeders: 4, date: 6);
      final input = [high, low];
      expect(project(input, sort: sort), [same(low), same(high)]);
      expect(project(input, sort: sort, ascending: false), [
        same(high),
        same(low),
      ]);
      expect(input, [same(high), same(low)]);
    });
  }

  test(
    'source order is stable, direction independent, and snapshot immutable',
    () {
      final a = row('a');
      final b = row('b', source: 'second');
      final c = row('c', source: 'second');
      final input = [a, b, c];
      final result = project(
        input,
        priority: ['engine:second', 'engine:first'],
        ascending: false,
      );
      expect(result, [same(b), same(c), same(a)]);
      expect(() => result.clear(), throwsUnsupportedError);
      input.clear();
      expect(result, hasLength(3));
    },
  );
}
