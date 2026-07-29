import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/services/iptv_catalog_db.dart';

IptvChannel _ch(
  int i, {
  String? group,
  String? name,
  String? contentType = 'live',
  Map<String, String> attributes = const {},
  Map<String, String> headers = const {},
}) =>
    IptvChannel(
      name: name ?? 'Channel $i',
      url: 'http://h/live/u/p/$i.ts',
      logoUrl: 'http://h/logo/$i.png',
      group: group,
      duration: -1,
      contentType: contentType,
      attributes: attributes,
      httpHeaders: headers,
    );

int _ingestInWorker(List<Object> args) {
  final channels = [for (var i = 0; i < 500; i++) _ch(i, group: 'G${i % 5}')];
  IptvCatalogDb.ingest(
    dbPath: args[0] as String,
    catalogKey: args[1] as String,
    channels: channels,
  );
  return channels.length;
}

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('catalog_db_test');
    IptvCatalogDb.debugDirectoryOverride = dir.path;
    await IptvCatalogDb.open();
  });

  tearDown(() async {
    IptvCatalogDb.debugClose();
    IptvCatalogDb.debugDirectoryOverride = null;
    await dir.delete(recursive: true);
  });

  test('ingest → snapshot round-trips every channel field in order', () {
    IptvCatalogDb.ingest(
      dbPath: IptvCatalogDb.path,
      catalogKey: 'xc|http://h|u|live',
      channels: [
        _ch(0,
            group: 'Спорт',
            name: 'Канал ᴴᴰ',
            attributes: {'stream_id': '7', 'tvg-id': 'ch7.tv'},
            headers: {'User-Agent': 'X'}),
        _ch(1, group: 'News'),
      ],
      epgUrl: 'http://h/xmltv.php',
    );

    final snap = IptvCatalogDb.snapshot('xc|http://h|u|live')!;
    expect(snap.channelCount, 2);
    expect(snap.epgUrl, 'http://h/xmltv.php');

    final page = snap.page(offset: 0, limit: 10);
    expect(page.map((c) => c.name), ['Канал ᴴᴰ', 'Channel 1']);
    final c = page.first;
    expect(c.url, 'http://h/live/u/p/0.ts');
    expect(c.logoUrl, 'http://h/logo/0.png');
    expect(c.group, 'Спорт');
    expect(c.duration, -1);
    expect(c.contentType, 'live');
    expect(c.attributes, {'stream_id': '7', 'tvg-id': 'ch7.tv'});
    expect(c.httpHeaders, {'User-Agent': 'X'});
    expect(c.isLive, isTrue);
  });

  test('windowed pages walk the full catalog in provider order', () {
    IptvCatalogDb.ingest(
      dbPath: IptvCatalogDb.path,
      catalogKey: 'k',
      channels: [for (var i = 0; i < 95; i++) _ch(i)],
    );
    final snap = IptvCatalogDb.snapshot('k')!;
    expect(snap.count(), 95);
    expect(snap.page(offset: 30, limit: 30).first.name, 'Channel 30');
    expect(snap.page(offset: 90, limit: 30).length, 5);
  });

  test('group filter and counts match the chip semantics', () {
    IptvCatalogDb.ingest(
      dbPath: IptvCatalogDb.path,
      catalogKey: 'k',
      channels: [
        _ch(0, group: 'Sports'),
        _ch(1), // no group — the M3U no-group-title case
        _ch(2, group: 'News'),
        _ch(3, group: 'Sports'),
      ],
    );
    final snap = IptvCatalogDb.snapshot('k')!;

    final groups = snap.groups();
    expect(
      [for (final g in groups) '${g.name}:${g.count}'],
      ['Sports:2', 'null:1', 'News:1'],
      reason: 'first-appearance order, null group preserved',
    );

    expect(snap.count(group: 'Sports'), 2);
    expect(snap.page(offset: 0, limit: 10, group: 'Sports').length, 2);
  });

  test('search matches name and group, case-insensitively, as substrings',
      () {
    IptvCatalogDb.ingest(
      dbPath: IptvCatalogDb.path,
      catalogKey: 'k',
      channels: [
        _ch(0, name: 'Sky Sports Main Event', group: 'UK'),
        _ch(1, name: 'CNN', group: 'News USA'),
        _ch(2, name: 'BBC One', group: 'UK'),
      ],
    );
    final snap = IptvCatalogDb.snapshot('k')!;

    expect(snap.page(offset: 0, limit: 10, search: 'sport').single.name,
        'Sky Sports Main Event');
    expect(snap.page(offset: 0, limit: 10, search: 'usa').single.name, 'CNN',
        reason: 'the group is part of the search haystack, as today');
    expect(snap.count(search: 'PORT'), 1, reason: 'mid-word substring match');
    expect(snap.count(search: 'zzz'), 0);
  });

  test('LIKE metacharacters in the query match literally', () {
    IptvCatalogDb.ingest(
      dbPath: IptvCatalogDb.path,
      catalogKey: 'k',
      channels: [
        _ch(0, name: '100% Hits'),
        _ch(1, name: 'Plain'),
      ],
    );
    final snap = IptvCatalogDb.snapshot('k')!;
    expect(snap.count(search: '100%'), 1,
        reason: '"%" must not act as a wildcard');
    expect(snap.count(search: '0% h'), 1);
    expect(snap.count(search: '_'), 0,
        reason: '"_" must not match arbitrary characters');
  });

  test('re-ingest swaps generations atomically and staleness is visible', () {
    IptvCatalogDb.ingest(
      dbPath: IptvCatalogDb.path,
      catalogKey: 'k',
      channels: [_ch(0), _ch(1), _ch(2)],
    );
    final old = IptvCatalogDb.snapshot('k')!;
    expect(old.isStale, isFalse);

    IptvCatalogDb.ingest(
      dbPath: IptvCatalogDb.path,
      catalogKey: 'k',
      channels: [_ch(10), _ch(11)],
    );

    expect(old.isStale, isTrue);
    expect(old.count(), 3,
        reason: 'the previous generation survives ONE refresh — the UI may '
            'still be scrolled through it while the commit lands');
    expect(old.page(offset: 0, limit: 10).first.name, 'Channel 0');

    final fresh = IptvCatalogDb.snapshot('k')!;
    expect(fresh.channelCount, 2);
    expect(fresh.page(offset: 0, limit: 10).map((c) => c.name),
        ['Channel 10', 'Channel 11']);

    IptvCatalogDb.ingest(
      dbPath: IptvCatalogDb.path,
      catalogKey: 'k',
      channels: [_ch(20)],
    );
    expect(old.count(), 0,
        reason: 'two refreshes later the first generation is finally swept');
    expect(fresh.count(), 2, reason: 'the second is now the retained one');
  });

  test('content digest is order-sensitive and field-sensitive', () {
    final a = [_ch(0), _ch(1)];
    final same = [_ch(0), _ch(1)];
    final reordered = [_ch(1), _ch(0)];
    final renamed = [_ch(0), _ch(1, name: 'Renamed')];

    expect(IptvCatalogDb.contentDigest(a), IptvCatalogDb.contentDigest(same));
    expect(IptvCatalogDb.contentDigest(a),
        isNot(IptvCatalogDb.contentDigest(reordered)));
    expect(IptvCatalogDb.contentDigest(a),
        isNot(IptvCatalogDb.contentDigest(renamed)));
  });

  test('ingest reports the digest of what it wrote; unchanged re-ingest '
      'produces the stored digest', () {
    final channels = [_ch(0), _ch(1)];
    final digest = IptvCatalogDb.ingest(
      dbPath: IptvCatalogDb.path,
      catalogKey: 'k',
      channels: channels,
    );
    expect(IptvCatalogDb.snapshot('k')!.contentDigest, digest);

    final again = IptvCatalogDb.ingest(
      dbPath: IptvCatalogDb.path,
      catalogKey: 'k',
      channels: channels,
    );
    expect(again, digest,
        reason: 'the revalidate path compares digests to decide "Up to date"');
  });

  test('removeCatalogs deletes only the named catalogs', () {
    for (final key in ['xc|s|u|live', 'xc|s|u|vod', 'm3u|http://other']) {
      IptvCatalogDb.ingest(
        dbPath: IptvCatalogDb.path,
        catalogKey: key,
        channels: [_ch(0)],
      );
    }

    IptvCatalogDb.removeCatalogs(['xc|s|u|live', 'xc|s|u|vod']);

    expect(IptvCatalogDb.snapshot('xc|s|u|live'), isNull);
    expect(IptvCatalogDb.snapshot('xc|s|u|vod'), isNull);
    expect(IptvCatalogDb.snapshot('m3u|http://other')!.channelCount, 1);
  });

  group('global-search queries', () {
    setUp(() {
      IptvCatalogDb.ingest(
        dbPath: IptvCatalogDb.path,
        catalogKey: 'k',
        channels: [
          _ch(0, name: 'Sky Sports F1', group: 'Sports'),
          IptvChannel(
            name: 'Sky Movies',
            url: 'http://h/movie/u/p/9.mp4',
            contentType: 'vod',
          ),
          _ch(2, name: 'CNN Sky News', group: 'News'),
          IptvChannel(
            name: 'Old Film',
            url: 'http://h/movie/u/p/10.mp4',
            // no contentType — M3U row; a real duration means on-demand
            duration: 5400,
          ),
        ],
      );
    });

    test('AND-of-terms with name-prefix leads, in catalog order', () {
      final snap = IptvCatalogDb.snapshot('k')!;
      expect(snap.searchCount(['sky']), 3);
      expect(snap.searchCount(['sky', 'news']), 1);

      final leads =
          snap.searchPage(['sky'], namePrefixLead: true, limit: 10);
      expect(leads.map((c) => c.name), ['Sky Sports F1', 'Sky Movies'],
          reason: 'CNN Sky News matches but its NAME has no sky prefix');
      final rest =
          snap.searchPage(['sky'], namePrefixLead: false, limit: 10);
      expect(rest.map((c) => c.name), ['CNN Sky News']);
    });

    test('live bucketing matches IptvChannel.isLive exactly', () {
      final snap = IptvCatalogDb.snapshot('k')!;
      expect(snap.count(live: true), 2,
          reason: 'explicit live + the duration-less M3U heuristic');
      expect(snap.count(live: false), 2,
          reason: 'explicit vod + the real-duration M3U row');
      expect(snap.searchCount(['sky'], live: false), 1);
    });

    test('positionOf + beforePosition rebuild a zap window', () {
      final snap = IptvCatalogDb.snapshot('k')!;
      final pos = snap.positionOf(url: 'http://h/live/u/p/2.ts', name: 'CNN Sky News')!;
      expect(snap.count(live: true, beforePosition: pos), 1,
          reason: 'one live row precedes it, so it is live index 1');
      final window = snap.page(offset: 0, limit: 10, live: true);
      expect(window[1].name, 'CNN Sky News');
    });
  });

  group('EPG guide storage', () {
    test('ingest → info + programme rows round-trip; re-ingest replaces',
        () {
      IptvCatalogDb.ingestEpgGuide(
        dbPath: IptvCatalogDb.path,
        guideKey: 'g1',
        epgUrl: 'http://h/xmltv.php',
        byId: {
          'bbcone.uk': [
            [1000, 2000, 'News', 'The news'],
            [2000, 3000, 'Weather', ''],
          ],
          'itv.uk': [
            [1500, 2500, 'Drama', 'A drama'],
          ],
        },
        nameToId: {'bbcone': 'bbcone.uk'},
        sawWanted: true,
      );

      final info = IptvCatalogDb.epgGuideInfo('g1')!;
      expect(info.channelCount, 2);
      expect(info.sawWanted, isTrue);
      expect(info.nameToId, {'bbcone': 'bbcone.uk'});

      final rows = IptvCatalogDb.epgProgrammes('g1', 'bbcone.uk');
      expect(rows, [
        [1000, 2000, 'News', 'The news'],
        [2000, 3000, 'Weather', ''],
      ]);
      expect(IptvCatalogDb.epgProgrammes('g1', 'nope'), isEmpty);

      IptvCatalogDb.ingestEpgGuide(
        dbPath: IptvCatalogDb.path,
        guideKey: 'g1',
        epgUrl: 'http://h/xmltv.php',
        byId: {
          'bbcone.uk': [
            [5000, 6000, 'Replaced', ''],
          ],
        },
        nameToId: const {},
        sawWanted: true,
      );
      expect(IptvCatalogDb.epgProgrammes('g1', 'bbcone.uk'), [
        [5000, 6000, 'Replaced', ''],
      ]);
      expect(IptvCatalogDb.epgProgrammes('g1', 'itv.uk'), isEmpty,
          reason: 'a re-ingest fully replaces the guide');
    });

    test('markEpgGuideEmpty writes only metadata (negative cache)', () {
      IptvCatalogDb.markEpgGuideEmpty(
        guideKey: 'g2',
        epgUrl: 'http://h/xmltv.php',
        sawWanted: false,
      );
      final info = IptvCatalogDb.epgGuideInfo('g2')!;
      expect(info.channelCount, 0);
      expect(info.sawWanted, isFalse);
    });

    test('channelTvgIdentity resolves a URL against the current generation',
        () {
      IptvCatalogDb.ingest(
        dbPath: IptvCatalogDb.path,
        catalogKey: 'cat',
        channels: [
          _ch(0,
              name: 'BBC One ᴴᴰ',
              attributes: {'tvg-id': 'BBCOne.uk', 'tvg-name': 'BBC One'}),
        ],
      );
      final identity = IptvCatalogDb.channelTvgIdentity(
        catalogKey: 'cat',
        url: 'http://h/live/u/p/0.ts',
      )!;
      expect(identity.name, 'BBC One ᴴᴰ');
      expect(identity.attributes['tvg-id'], 'BBCOne.uk');
      expect(
        IptvCatalogDb.channelTvgIdentity(catalogKey: 'cat', url: 'http://x'),
        isNull,
      );
    });
  });

  test('ingest from a worker isolate is read back on this one', () async {
    final written = await compute(
      _ingestInWorker,
      <Object>[IptvCatalogDb.path, 'worker|k'],
    );
    final snap = IptvCatalogDb.snapshot('worker|k')!;
    expect(snap.channelCount, written);
    expect(snap.count(group: 'G3'), 100);
    expect(snap.page(offset: 499, limit: 1).single.name, 'Channel 499');
  });
}
