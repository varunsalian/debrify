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

Torrent _direct(String name, String source) => Torrent(
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
  streamType: StreamType.directUrl,
  directUrl: 'https://example.com/$name',
  hasRealInfoHash: false,
);

void main() {
  group('keyForSource', () {
    test('addon rows keep their stremio key, engines get the prefix', () {
      expect(
        SourcePriority.keyForSource('stremio:Torrentio'),
        'stremio:torrentio',
      );
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

    test('source order keeps provider order and first-priority duplicate', () {
      final sharedHash = 'f' * 40;
      final input = [
        _t('engine first', 'engineA'),
        _t('aio first', 'stremio:AIOStreams'),
        _t('aio second', 'stremio:AIOStreams'),
        Torrent(
          rowid: 0,
          infohash: sharedHash,
          name: 'engine duplicate',
          sizeBytes: 0,
          createdUnix: 0,
          seeders: 999,
          leechers: 0,
          completed: 0,
          scrapedDate: 0,
          source: 'engineA',
        ),
        Torrent(
          rowid: 0,
          infohash: sharedHash,
          name: 'aio duplicate',
          sizeBytes: 0,
          createdUnix: 0,
          seeders: 0,
          leechers: 0,
          completed: 0,
          scrapedDate: 0,
          source: 'stremio:AIOStreams',
        ),
      ];

      final out = SourcePriority.orderAndDedupe(input, const [
        'stremio:aiostreams',
        'engine:enginea',
      ]);

      expect(out.map((t) => t.name), [
        'aio first',
        'aio second',
        'aio duplicate',
        'engine first',
      ]);
    });
  });

  group('directAddonLinksFirst', () {
    test(
      'puts addon direct links before torrents and preserves stable order',
      () {
        final input = [
          _t('torrent-a', 'stremio:Comet'),
          _t('engine', 'bitsearch'),
          _direct('direct-a', 'stremio:Comet'),
          _t('torrent-b', 'stremio:Torrentio'),
          _direct('direct-b', 'stremio:Torrentio'),
        ];

        final out = SourcePriority.directAddonLinksFirst(input);

        expect(out.map((t) => t.name), [
          'direct-a',
          'engine',
          'torrent-a',
          'direct-b',
          'torrent-b',
        ]);
      },
    );

    test('keeps AIO direct links in the addon response order', () {
      final input = [
        _direct('4K first', 'stremio:AIOStreams'),
        _t('4K first torrent', 'stremio:AIOStreams'),
        _direct('4K second', 'stremio:AIOStreams'),
        _t('4K second torrent', 'stremio:AIOStreams'),
        _direct('1080p third', 'stremio:AIOStreams'),
        _t('1080p third torrent', 'stremio:AIOStreams'),
      ];

      final out = SourcePriority.directAddonLinksFirst(input);

      expect(out.map((t) => t.name), [
        '4K first',
        '4K second',
        '1080p third',
        '4K first torrent',
        '4K second torrent',
        '1080p third torrent',
      ]);
    });

    test('does not promote non-addon direct URLs', () {
      final input = [_t('torrent', 'stremio:Comet'), _direct('direct', 'web')];

      final out = SourcePriority.directAddonLinksFirst(input);

      expect(identical(out, input), isTrue);
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
