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
  List<IptvChannel> filler(String needle) => [
        for (var i = 0; i < 3000; i++)
          if (i == 1234) _ch(needle) else _ch('Filler Channel $i'),
      ];

  test('searchAsync runs the scan on a worker isolate and matches search()',
      () async {
    final index = IptvGlobalSearchIndex(
      sources: [
        IptvGlobalSearchSource(
          playlist: _pl('Local'),
          contentType: 'mixed',
          channels: filler('Sky Sports Needle HD'),
        ),
      ],
      unindexed: const [],
    );

    final async = await index.searchAsync('needle');
    expect(async.liveTotal, 1);
    expect(async.live.single.channel.name, 'Sky Sports Needle HD');
    // The hit must point at this index's live source object, not a copy.
    expect(identical(async.live.single.source, index.sources.first), isTrue);

    // Parity with the inline algorithm.
    final sync = index.search('needle');
    expect(sync.liveTotal, async.liveTotal);
    expect(sync.live.single.channel.name, async.live.single.channel.name);
  });

  test('searchAsync returns empty for a blank query without spawning work',
      () async {
    final index = IptvGlobalSearchIndex(
      sources: [
        IptvGlobalSearchSource(
          playlist: _pl('Local'),
          contentType: 'mixed',
          channels: [_ch('BBC One')],
        ),
      ],
      unindexed: const [],
    );
    expect((await index.searchAsync('   ')).isEmpty, isTrue);
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
      IptvCatalogDb.ingest(
        dbPath: IptvCatalogDb.path,
        catalogKey: 'k',
        channels: [_ch('ESPN Needle 4K'), _ch('CNN')],
      );
      final snap = IptvCatalogDb.snapshot('k')!;

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
            channels: filler('Local Needle Sports'),
          ),
        ],
        unindexed: const [],
      );

      final res = await index.searchAsync('needle');
      expect(res.liveTotal, 2);
      final names = res.live.map((h) => h.channel.name).toSet();
      expect(names, containsAll(['ESPN Needle 4K', 'Local Needle Sports']));
      // The DB hit points back at the DB-backed source object.
      final dbHit =
          res.live.firstWhere((h) => h.channel.name == 'ESPN Needle 4K');
      expect(identical(dbHit.source, index.sources.first), isTrue);
    });
  });
}
