import 'package:flutter_test/flutter_test.dart';

import 'package:debrify/models/torrent.dart';
import 'package:debrify/services/source_priority.dart';

Torrent _t(String name, String source) => Torrent(
  rowid: 0,
  infohash: name,
  name: name,
  sizeBytes: 0,
  createdUnix: 0,
  seeders: 0,
  leechers: 0,
  completed: 0,
  scrapedDate: 0,
  source: source,
);

void main() {
  group('keyForSource', () {
    test('addon rows keep their stremio key, engines get the prefix', () {
      expect(SourcePriority.keyForSource('stremio:Torrentio'), 'stremio:torrentio');
      expect(SourcePriority.keyForSource('bitsearch'), 'engine:bitsearch');
    });

    test('indexer-manager display names map through aliases', () {
      expect(
        SourcePriority.keyForSource(
          'My Jackett',
          aliases: {'my jackett': 'engine:indexer_manager_my_jackett_1'},
        ),
        'engine:indexer_manager_my_jackett_1',
      );
    });
  });

  group('order', () {
    final torrents = [
      _t('a1', 'engineA'),
      _t('b1', 'stremio:Comet'),
      _t('a2', 'engineA'),
      _t('c1', 'engineB'),
    ];

    test('empty priority returns the list unchanged (never customized)', () {
      final out = SourcePriority.order(torrents, const []);
      expect(identical(out, torrents), isTrue);
    });

    test('priority groups providers, stable within each group', () {
      final out = SourcePriority.order(torrents, const [
        'stremio:comet',
        'engine:engineb',
        'engine:enginea',
      ]);
      expect(out.map((t) => t.name).toList(), ['b1', 'c1', 'a1', 'a2']);
    });

    test('unlisted providers keep relative order after listed ones', () {
      final out = SourcePriority.order(torrents, const ['engine:engineb']);
      expect(out.map((t) => t.name).toList(), ['c1', 'a1', 'b1', 'a2']);
    });
  });

  test('orderBy sorts bare keys the same way', () {
    final out = SourcePriority.orderBy(
      ['engineA', 'stremio:Comet', 'engineB'],
      (s) => SourcePriority.keyForSource(s),
      const ['engine:engineb', 'stremio:comet'],
    );
    expect(out, ['engineB', 'stremio:Comet', 'engineA']);
  });

  test('Watch Next is recommendation-only, not a source provider', () {
    expect(
      SourcePriority.isRecommendationOnlyAddon('community.watch.next'),
      isTrue,
    );
    expect(
      SourcePriority.isRecommendationOnlyAddon('com.stremio.torrentio'),
      isFalse,
    );
  });
}
