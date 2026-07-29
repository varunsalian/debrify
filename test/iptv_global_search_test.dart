import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/services/iptv_catalog_db.dart';
import 'package:debrify/services/iptv_global_search.dart';

IptvPlaylist _pl(String name) => IptvPlaylist(
      id: name,
      name: name,
      url: 'http://h/$name.m3u',
      addedAt: DateTime.fromMillisecondsSinceEpoch(0),
    );

IptvChannel _ch(String name, {String group = 'G', String type = 'live'}) =>
    IptvChannel(
      name: name,
      url: 'http://h/${name.hashCode}.ts',
      logoUrl: null,
      group: group,
      duration: -1,
      contentType: type,
      attributes: const {},
      httpHeaders: const {},
    );

void main() {
  // A source big enough to cross the in-memory isolate threshold (5000).
  List<IptvChannel> bigFiller(String needleName) => [
        for (var i = 0; i < 6000; i++)
          if (i == 4242) _ch(needleName) else _ch('Filler Channel $i'),
      ];

  test('searchAsync fans a large in-memory scan out to a worker isolate '
      'and matches the inline result', () async {
    final index = IptvGlobalSearchIndex(
      sources: [
        IptvGlobalSearchSource(
          playlist: _pl('Local'),
          contentType: 'mixed',
          channels: bigFiller('Sky Sports Needle HD'),
        ),
      ],
      unindexed: const [],
    );

    final async = await index.searchAsync('needle');
    expect(async.liveTotal, 1);
    expect(async.live.single.channel.name, 'Sky Sports Needle HD');
    // The hit must reference this index's live source object, not a copy.
    expect(identical(async.live.single.source, index.sources.first), isTrue);

    // Parity with the inline algorithm.
    final sync = index.search('needle');
    expect(sync.liveTotal, async.liveTotal);
    expect(sync.live.single.channel.name, async.live.single.channel.name);
  });

  test('small / DB-only indexes stay inline (no worker) yet searchAsync works',
      () async {
    final index = IptvGlobalSearchIndex(
      sources: [
        IptvGlobalSearchSource(
          playlist: _pl('Small'),
          contentType: 'mixed',
          channels: [_ch('BBC One'), _ch('Sky News'), _ch('Sky Sports')],
        ),
      ],
      unindexed: const [],
    );
    final res = await index.searchAsync('sky');
    expect(res.liveTotal, 2);
    expect(res.live.map((h) => h.channel.name),
        containsAll(['Sky News', 'Sky Sports']));
  });

  group('with a catalog-DB source', () {
    late Directory dir;
    setUp(() async {
      dir = await Directory.systemTemp.createTemp('global_search_test');
      IptvCatalogDb.debugDirectoryOverride = dir.path;
      await IptvCatalogDb.open();
    });
    tearDown(() async {
      IptvCatalogDb.debugClose();
      IptvCatalogDb.debugDirectoryOverride = null;
      await dir.delete(recursive: true);
    });

    test('the worker opens its own connection and searches DB + memory '
        'sources together', () async {
      // A DB-backed source with the needle...
      IptvCatalogDb.ingest(
        dbPath: IptvCatalogDb.path,
        catalogKey: 'k',
        channels: [_ch('ESPN Needle 4K'), _ch('CNN')],
      );
      final snap = IptvCatalogDb.snapshot('k')!;

      // ...alongside a big in-memory source, so searchAsync takes the worker
      // path and the worker must re-pin the snapshot on its own connection.
      final index = IptvGlobalSearchIndex(
        sources: [
          IptvGlobalSearchSource(
            playlist: _pl('Xtream'),
            contentType: 'live',
            channels: const [],
            snapshot: snap,
          ),
          IptvGlobalSearchSource(
            playlist: _pl('Local'),
            contentType: 'mixed',
            channels: bigFiller('Local Needle Sports'),
          ),
        ],
        unindexed: const [],
      );

      final res = await index.searchAsync('needle');
      // One from the DB source, one from the in-memory source.
      expect(res.liveTotal, 2);
      final names = res.live.map((h) => h.channel.name).toSet();
      expect(names, containsAll(['ESPN Needle 4K', 'Local Needle Sports']));
      // The DB hit points back at the DB-backed source object.
      final dbHit =
          res.live.firstWhere((h) => h.channel.name == 'ESPN Needle 4K');
      expect(identical(dbHit.source, index.sources.first), isTrue);
    });

    test('an all-short query on a big DB catalog offloads and still matches',
        () async {
      // A DB catalog large enough to cross the isolate threshold, with the
      // short token "uk" reachable only via the LIKE fallback (trigram can't
      // index <3 chars) — the exact case that must not full-scan on the UI.
      IptvCatalogDb.ingest(
        dbPath: IptvCatalogDb.path,
        catalogKey: 'k',
        channels: [
          for (var i = 0; i < 6000; i++)
            _ch(i == 99 ? 'BBC One' : 'Filler $i',
                group: i == 99 ? 'UK' : 'ZZ'),
        ],
      );
      final index = IptvGlobalSearchIndex(
        sources: [
          IptvGlobalSearchSource(
            playlist: _pl('Big'),
            contentType: 'live',
            channels: const [],
            snapshot: IptvCatalogDb.snapshot('k')!,
          ),
        ],
        unindexed: const [],
      );
      final res = await index.searchAsync('uk');
      expect(res.liveTotal, 1);
      expect(res.live.single.channel.name, 'BBC One');
    });
  });
}
