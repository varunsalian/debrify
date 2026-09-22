import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/services/iptv_epg_service.dart';
import 'package:debrify/services/iptv_catalog_db.dart';
import 'package:debrify/services/iptv_catalog_key.dart';

/// True end-to-end run of the Xtream→xmltv.php guide layering, the exact
/// scenario field reports describe: a panel whose per-stream get_short_epg
/// answers nothing, but whose whole-account xmltv.php works (the source
/// TiviMate reads). Real HTTP server, real gzip download, real isolate
/// parse, real disk snapshot — nothing mocked but the storage paths.
class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.root);
  final String root;

  @override
  Future<String?> getTemporaryPath() async {
    final dir = Directory('$root/tmp');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir.path;
  }

  @override
  Future<String?> getApplicationSupportPath() async {
    final dir = Directory('$root/support');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir.path;
  }
}

IptvChannel saved(String url, String origin, {String name = 'Saved name'}) =>
    IptvChannel(
      name: name,
      url: url,
      duration: -1,
      attributes: {'list_playlist_id': origin},
    );

void main() {
  late Directory storageRoot;
  late HttpServer server;
  late int port;
  var xmltvHits = 0;
  var shortEpgHits = 0;
  // When true, get_simple_data_table answers real rows (with has_archive) —
  // the healthy-panel case whose catchup flags the schedule path must keep.
  var serveDataTable = false;
  var dataTableIncludesRawStart = true;
  void Function()? onGuideRequest;

  DateTime guideStart() {
    final now = DateTime.now().toUtc();
    return DateTime.utc(
      now.year,
      now.month,
      now.day,
      now.hour,
    ).subtract(const Duration(minutes: 30));
  }

  String rawPanelTime(DateTime time) =>
      '${time.year.toString().padLeft(4, '0')}-'
      '${time.month.toString().padLeft(2, '0')}-'
      '${time.day.toString().padLeft(2, '0')} '
      '${time.hour.toString().padLeft(2, '0')}:'
      '${time.minute.toString().padLeft(2, '0')}:00';

  String guideXml() {
    const slot = Duration(minutes: 30);
    final start = guideStart();
    String fmt(DateTime t) =>
        '${t.year.toString().padLeft(4, '0')}'
        '${t.month.toString().padLeft(2, '0')}'
        '${t.day.toString().padLeft(2, '0')}'
        '${t.hour.toString().padLeft(2, '0')}'
        '${t.minute.toString().padLeft(2, '0')}00 +0000';
    final b = StringBuffer('<?xml version="1.0" encoding="UTF-8"?><tv>');
    // Guide publishes lowercase ids; the "playlist" below carries uppercase.
    b.write(
      '<channel id="mock1.test">'
      '<display-name>Mock One</display-name></channel>',
    );
    b.write(
      '<channel id="namedonly.guide">'
      '<display-name>Named Only Channel</display-name></channel>',
    );
    for (final id in ['mock1.test', 'namedonly.guide']) {
      for (var i = 0; i < 8; i++) {
        final s = start.add(slot * i);
        final e = start.add(slot * (i + 1));
        b.write(
          '<programme start="${fmt(s)}" stop="${fmt(e)}" '
          'channel="$id"><title>Show $i on $id</title>'
          '<desc>Description $i</desc></programme>',
        );
      }
    }
    b.write('</tv>');
    return b.toString();
  }

  setUpAll(() async {
    storageRoot = await Directory.systemTemp.createTemp('epg_integration');
    PathProviderPlatform.instance = _FakePathProvider(storageRoot.path);

    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    port = server.port;
    server.listen((request) {
      final path = request.uri.path;
      if (path.endsWith('xmltv.php')) {
        xmltvHits++;
        onGuideRequest?.call();
        if (request.uri.queryParameters['variant'] == 'failed') {
          request.response.statusCode = 503;
          request.response.close();
          return;
        }
        // Served as a gzip FILE (magic bytes), like real panels do.
        final body = gzip.encode(
          utf8.encode(
            request.uri.queryParameters['variant'] == 'other'
                ? guideXml().replaceAll('Show ', 'Other ')
                : guideXml(),
          ),
        );
        request.response.headers.contentType = ContentType(
          'application',
          'octet-stream',
        );
        request.response.add(body);
      } else {
        shortEpgHits++;
        request.response.headers.contentType = ContentType.json;
        final action = request.uri.queryParameters['action'] ?? '';
        if (serveDataTable && action == 'get_simple_data_table') {
          // Healthy catch-up metadata, but with the real-world provider bug
          // this regression covers: the data-table timeline is two hours
          // ahead of the otherwise-correct xmltv.php timeline.
          const slot = Duration(minutes: 30);
          final start = guideStart();
          final rows = [
            for (var i = 0; i < 8; i++)
              {
                'title': base64Encode(utf8.encode('Show $i on mock1.test')),
                'description': '',
                'start_timestamp':
                    '${start.add(slot * i).add(const Duration(hours: 2)).millisecondsSinceEpoch ~/ 1000}',
                'stop_timestamp':
                    '${start.add(slot * (i + 1)).add(const Duration(hours: 2)).millisecondsSinceEpoch ~/ 1000}',
                if (dataTableIncludesRawStart)
                  'start': rawPanelTime(
                    start.add(slot * i).add(const Duration(hours: 2)),
                  ),
                // Include whichever half-hour slot contains now so the
                // archive-aware now/next path can prove it donates metadata.
                if (i <= 2) 'has_archive': 1,
              },
          ];
          request.response.write(jsonEncode({'epg_listings': rows}));
        } else {
          // Broken/empty per-stream EPG (the default panel in these tests).
          request.response.write('{"epg_listings":[]}');
        }
      }
      request.response.close();
    });
  });

  tearDownAll(() async {
    IptvEpgService.instance.clearM3uEpgContext();
    await server.close(force: true);
    await storageRoot.delete(recursive: true);
  });

  setUp(() {
    serveDataTable = false;
    dataTableIncludesRawStart = true;
    onGuideRequest = null;
  });

  for (final dbMode in [false, true]) {
    test(
      'successive lists cannot poison the ${dbMode ? 'DB' : 'memory'} provider guide',
      () async {
        final dir = await Directory.systemTemp.createTemp('epg_coverage');
        try {
          final guideUrl =
              'http://127.0.0.1:$port/xmltv.php?case=coverage-$dbMode';
          final provider = IptvPlaylist(
            id: 'coverage',
            name: 'Provider',
            url: 'https://coverage.test/provider',
            epgUrl: guideUrl,
            addedAt: DateTime.now(),
          );
          final channels = [
            saved('https://coverage.test/one', 'coverage', name: 'Mock One'),
            saved(
              'https://coverage.test/two',
              'coverage',
              name: 'Named Only Channel',
            ),
          ];
          String? catalogKey;
          if (dbMode) {
            IptvCatalogDb.debugDirectoryOverride = dir.path;
            await IptvCatalogDb.open();
            catalogKey = IptvCatalogKey.forPlaylist(provider, 'live')!;
            IptvCatalogDb.ingest(
              dbPath: IptvCatalogDb.path,
              catalogKey: catalogKey,
              channels: channels,
              epgUrl: guideUrl,
            );
          }
          final service = IptvEpgService.instance;
          await service.setListEpgContext(
            channels: [channels.first],
            playlists: [provider],
          );
          expect(
            service.peekNowNext(channels.first.url)?.now?.title,
            contains('mock1.test'),
          );
          await service.setListEpgContext(
            channels: [channels.last],
            playlists: [provider],
          );
          expect(
            service.peekNowNext(channels.last.url)?.now?.title,
            contains('namedonly.guide'),
          );
          final hits = xmltvHits;
          await service.setListEpgContext(
            channels: [channels.first],
            playlists: [provider],
          );
          expect(service.peekNowNext(channels.first.url)?.now, isNotNull);
          expect(
            xmltvHits,
            hits,
            reason: 'Returning to identical coverage reuses its snapshot',
          );
          await service.setM3uEpgContext(
            playlistKey: provider.id,
            epgUrl: guideUrl,
            channels: channels,
            dbCatalogKey: catalogKey,
          );
          expect(
            service.peekNowNext(channels.first.url)?.now?.title,
            contains('mock1.test'),
          );
          expect(
            service.peekNowNext(channels.last.url)?.now?.title,
            contains('namedonly.guide'),
          );
        } finally {
          IptvEpgService.instance.clearM3uEpgContext();
          if (dbMode) {
            IptvCatalogDb.debugClose();
            IptvCatalogDb.debugDirectoryOverride = null;
          }
          await dir.delete(recursive: true);
        }
      },
    );
  }

  test('one failed provider does not hide another Favorites guide', () async {
    final channels = [
      saved('https://failed.test/live', 'failed', name: 'Mock One'),
      saved('https://healthy.test/live', 'healthy', name: 'Mock One'),
    ];
    await IptvEpgService.instance.setListEpgContext(
      channels: channels,
      playlists: [
        IptvPlaylist(
          id: 'failed',
          name: 'Failed',
          url: 'https://failed.test/list',
          addedAt: DateTime.now(),
          epgUrl: 'http://127.0.0.1:$port/xmltv.php?variant=failed',
        ),
        IptvPlaylist(
          id: 'healthy',
          name: 'Healthy',
          url: 'https://healthy.test/list',
          addedAt: DateTime.now(),
          epgUrl: 'http://127.0.0.1:$port/xmltv.php?case=healthy-list',
        ),
      ],
    );
    expect(IptvEpgService.isEpgCapable(channels.first), false);
    expect(
      IptvEpgService.instance.peekNowNext(channels.last.url)?.now,
      isNotNull,
    );
  });

  test(
    'leaving Favorites during a download cannot publish stale programme data',
    () async {
      final channel = saved(
        'https://inflight.test/live',
        'inflight',
        name: 'Mock One',
      );
      onGuideRequest = () => IptvEpgService.instance.clearM3uEpgContext();
      await IptvEpgService.instance.setListEpgContext(
        channels: [channel],
        playlists: [
          IptvPlaylist(
            id: 'inflight',
            name: 'In flight',
            url: 'https://inflight.test/list',
            addedAt: DateTime.now(),
            epgUrl: 'http://127.0.0.1:$port/xmltv.php?case=inflight-list',
          ),
        ],
      );
      expect(IptvEpgService.isEpgCapable(channel), false);
    },
  );

  test(
    'Favorites and custom-list view activate their origin-aware guide path',
    () {
      final source = File(
        'lib/widgets/iptv/iptv_results_view.dart',
      ).readAsStringSync();
      final start = source.indexOf('void _updateEpgContext(');
      final end = source.indexOf('final isPlainM3u', start);
      final listBranch = source.substring(start, end);
      expect(
        listBranch,
        contains('playlist.isFavorites || playlist.isCustomList'),
      );
      expect(listBranch, contains('service.setListEpgContext('));
      expect(listBranch, contains('channels: result.channels'));
      expect(listBranch, contains('ticket == _loadTicket'));
    },
  );

  test(
    'Favorites recover IDs and header guide URLs from cached provider catalogs',
    () async {
      final dir = await Directory.systemTemp.createTemp('favorite_epg_catalog');
      IptvCatalogDb.debugDirectoryOverride = dir.path;
      await IptvCatalogDb.open();
      try {
        final provider = IptvPlaylist(
          id: 'provider',
          name: 'Provider',
          url: 'https://provider.test/list.m3u',
          addedAt: DateTime.now(),
        );
        const stream = 'https://stream.test/channel';
        IptvCatalogDb.ingest(
          dbPath: IptvCatalogDb.path,
          catalogKey: IptvCatalogKey.forPlaylist(provider, 'live')!,
          epgUrl: 'http://127.0.0.1:$port/xmltv.php?case=cached-favorite',
          channels: [
            IptvChannel(
              name: 'Renamed at provider',
              url: stream,
              duration: -1,
              attributes: {'tvg-id': 'mock1.test'},
            ),
          ],
        );
        final favorite = saved(stream, provider.id);
        await IptvEpgService.instance.setListEpgContext(
          channels: [favorite],
          playlists: [provider],
        );
        expect(IptvEpgService.isEpgCapable(favorite), true);
        expect(
          IptvEpgService.instance.peekNowNext(stream)?.now?.title,
          contains('mock1.test'),
        );
        expect(await IptvEpgService.instance.schedule(stream), isNotEmpty);
      } finally {
        IptvEpgService.instance.clearM3uEpgContext();
        IptvCatalogDb.debugClose();
        IptvCatalogDb.debugDirectoryOverride = null;
        await dir.delete(recursive: true);
      }
    },
  );

  test(
    'mixed Favorites keep overlapping guide IDs isolated across providers',
    () async {
      final first = IptvPlaylist(
        id: 'first',
        name: 'First',
        url: 'local-first',
        addedAt: DateTime.now(),
        content:
            '#EXTM3U url-tvg="http://127.0.0.1:$port/xmltv.php?case=first-list"\n#EXTINF:-1 tvg-id="mock1.test",Original\nhttps://first.test/live\n',
      );
      final second = IptvPlaylist(
        id: 'second',
        name: 'Second',
        url: 'local-second',
        addedAt: DateTime.now(),
        epgUrl:
            'http://127.0.0.1:$port/xmltv.php?variant=other&case=second-list',
        content:
            '#EXTM3U\n#EXTINF:-1 tvg-id="mock1.test",Original\nhttps://second.test/live\n',
      );
      final channels = [
        saved('https://first.test/live', 'first'),
        saved('https://second.test/live', 'second'),
      ];
      await IptvEpgService.instance.setListEpgContext(
        channels: channels,
        playlists: [first, second],
      );
      expect(
        IptvEpgService.instance.peekNowNext(channels[0].url)?.now?.title,
        startsWith('Show '),
      );
      expect(
        IptvEpgService.instance.peekNowNext(channels[1].url)?.now?.title,
        startsWith('Other '),
      );
      // Removing a provider or switching shelves cannot retain its old guide.
      await IptvEpgService.instance.setListEpgContext(
        channels: channels,
        playlists: [first],
      );
      expect(IptvEpgService.isEpgCapable(channels[1]), false);
      IptvEpgService.instance.clearM3uEpgContext();
      expect(IptvEpgService.isEpgCapable(channels[0]), false);
    },
  );

  test(
    'Favorites derive Xtream XMLTV when per-stream guide is empty',
    () async {
      final provider = IptvPlaylist(
        id: 'xc-list',
        name: 'Panel',
        url: 'xtream://',
        serverUrl: 'http://127.0.0.1:$port',
        username: 'list-user',
        password: 'pass',
        addedAt: DateTime.now(),
      );
      final channel = saved(
        'http://127.0.0.1:$port/live/list-user/pass/123.ts',
        provider.id,
        name: 'Mock One',
      );
      await IptvEpgService.instance.setListEpgContext(
        channels: [channel],
        playlists: [provider],
      );
      expect(
        (await IptvEpgService.instance.nowNext(channel.url)).now?.title,
        contains('mock1.test'),
      );
    },
  );

  test('superseded Favorites setup never republishes a guide', () async {
    final provider = IptvPlaylist(
      id: 'stale',
      name: 'Stale',
      url: 'local',
      addedAt: DateTime.now(),
      epgUrl: 'http://127.0.0.1:$port/xmltv.php?case=stale-list',
      content:
          '#EXTM3U\n#EXTINF:-1 tvg-id="mock1.test",Original\nhttps://stale.test/live\n',
    );
    final channel = saved('https://stale.test/live', provider.id);
    final pending = IptvEpgService.instance.setListEpgContext(
      channels: [channel],
      playlists: [provider],
    );
    IptvEpgService.instance.clearM3uEpgContext();
    await pending;
    expect(IptvEpgService.isEpgCapable(channel), false);
  });

  IptvChannel liveChannel(int id, {String? tvgId, String? name}) => IptvChannel(
    name: name ?? 'Channel $id',
    url: 'http://127.0.0.1:$port/live/user/pass/$id.ts',
    duration: -1,
    contentType: 'live',
    attributes: {if (tvgId != null) 'tvg-id': tvgId},
  );

  test('shifted panel: schedule keeps the XMLTV timeline while merging '
      'catchup metadata', () async {
    serveDataTable = true;
    final ch = liveChannel(10, tvgId: 'MOCK1.TEST');
    // Distinct guide URL => distinct snapshot, so this test's filtered
    // snapshot can't shadow the next test's channels.
    final epgUrl = IptvEpgService.xmltvUrlFor(
      'http://127.0.0.1:$port',
      'ordering',
      'pass',
    );
    final status = await IptvEpgService.instance.setM3uEpgContext(
      playlistKey: 'itest-order',
      epgUrl: epgUrl,
      channels: [ch],
    );
    expect(status, M3uEpgStatus.matched);

    final before = IptvEpgService.instance.peekNowNext(ch.url);
    expect(before?.now, isNotNull);

    final enriched = await IptvEpgService.instance.nowNextWithCatchupMetadata(
      ch.url,
    );
    expect(enriched.now?.title, before!.now!.title);
    expect(enriched.now?.hasArchive, isTrue);

    // The visible schedule stays on the same XMLTV timeline as the card even
    // though the provider's data table is shifted by two hours.
    final schedule = await IptvEpgService.instance.schedule(ch.url);
    final scheduleNow = schedule.firstWhere((p) => p.airsAt(DateTime.now()));
    expect(scheduleNow.title, before.now!.title);
    expect(scheduleNow.start, before.now!.start);

    // Catch-up metadata still rides on the matching XMLTV row, including the
    // raw panel-local start the replay URL requires. Display time is not
    // shifted to that raw value.
    final archived = schedule.firstWhere((p) => p.hasArchive);
    expect(archived.title, 'Show 0 on mock1.test');
    expect(
      archived.start.millisecondsSinceEpoch,
      guideStart().millisecondsSinceEpoch,
    );
    expect(
      archived.rawStart,
      rawPanelTime(guideStart().add(const Duration(hours: 2))),
    );
    expect(
      IptvEpgService.catchupStart(archived),
      rawPanelTime(
        guideStart().add(const Duration(hours: 2)),
      ).substring(0, 16).replaceFirst(' ', ':').replaceFirst(':', '-', 13),
    );

    serveDataTable = false;
    IptvEpgService.instance.clearM3uEpgContext();
  });

  test(
    'full guide deduplicates a shifted panel row without raw start',
    () async {
      serveDataTable = true;
      dataTableIncludesRawStart = false;
      final ch = liveChannel(11, tvgId: 'MOCK1.TEST');
      final epgUrl = IptvEpgService.xmltvUrlFor(
        'http://127.0.0.1:$port',
        'ordering-no-raw',
        'pass',
      );
      final status = await IptvEpgService.instance.setM3uEpgContext(
        playlistKey: 'itest-order-no-raw',
        epgUrl: epgUrl,
        channels: [ch],
      );
      expect(status, M3uEpgStatus.matched);

      final schedule = await IptvEpgService.instance.scheduleWithCatchupHistory(
        ch,
      );
      final matching = schedule
          .where((programme) => programme.title == 'Show 0 on mock1.test')
          .toList();

      expect(matching, hasLength(1));
      final archived = matching.single;
      final panelStart = guideStart().add(const Duration(hours: 2));
      expect(
        archived.start.millisecondsSinceEpoch,
        guideStart().millisecondsSinceEpoch,
      );
      expect(
        archived.replayStart?.millisecondsSinceEpoch,
        panelStart.millisecondsSinceEpoch,
      );
      final localPanelStart = panelStart.toLocal();
      final localRaw = rawPanelTime(localPanelStart);
      expect(
        IptvEpgService.catchupStart(archived),
        '${localRaw.substring(0, 10)}:${localRaw.substring(11, 13)}-'
        '${localRaw.substring(14, 16)}',
      );

      IptvEpgService.instance.clearM3uEpgContext();
    },
  );

  test('broken-short_epg panel: xmltv.php layering delivers now/next '
      '(case-insensitive ids + name-only fallback), snapshot survives '
      'the panel going down', () async {
    xmltvHits = 0; // this test's guide URL is distinct from the one above
    // Channels shaped exactly like XtreamCodesService builds them.
    final byId = liveChannel(1, tvgId: 'MOCK1.TEST'); // case-mismatched id
    final byName = liveChannel(
      2,
      name: 'Named Only Channel',
    ); // no tvg-id at all
    final uncovered = liveChannel(3, tvgId: 'not.in.guide');
    final channels = [byId, byName, uncovered];

    final epgUrl = IptvEpgService.xmltvUrlFor(
      'http://127.0.0.1:$port',
      'user',
      'pass',
    );

    final status = await IptvEpgService.instance.setM3uEpgContext(
      playlistKey: 'itest',
      epgUrl: epgUrl,
      channels: channels,
    );
    expect(status, M3uEpgStatus.matched);
    expect(xmltvHits, 1);

    // Case-insensitive tvg-id pairing: uppercase playlist id, lowercase
    // guide id — now/next computed locally, no per-stream fetch needed.
    final nowNext1 = IptvEpgService.instance.peekNowNext(byId.url);
    expect(nowNext1, isNotNull);
    expect(nowNext1!.now?.title, contains('mock1.test'));
    expect(nowNext1.next?.title, contains('mock1.test'));

    // Kodi-style display-name fallback for the id-less channel.
    final nowNext2 = IptvEpgService.instance.peekNowNext(byName.url);
    expect(nowNext2, isNotNull);
    expect(nowNext2!.now?.title, contains('namedonly.guide'));

    // Both are EPG-capable; schedules come straight from the local index.
    expect(IptvEpgService.isEpgCapable(byId), isTrue);
    expect(IptvEpgService.isEpgCapable(byName), isTrue);
    final schedule = await IptvEpgService.instance.schedule(byId.url);
    expect(schedule.length, 8);

    // The uncovered channel falls through to the (broken) per-stream
    // endpoint and quietly yields nothing — no crash, no misattribution.
    final nowNext3 = await IptvEpgService.instance.nowNext(uncovered.url);
    expect(nowNext3.isEmpty, isTrue);
    expect(shortEpgHits, greaterThan(0));

    // Reload with the panel still up: the fresh disk snapshot answers, no
    // second download.
    final again = await IptvEpgService.instance.setM3uEpgContext(
      playlistKey: 'itest',
      epgUrl: epgUrl,
      channels: channels,
    );
    expect(again, M3uEpgStatus.matched);
    expect(xmltvHits, 1, reason: 'snapshot should have served the reload');

    // Panel goes DOWN entirely: the snapshot still serves the guide.
    await server.close(force: true);
    final offline = await IptvEpgService.instance.setM3uEpgContext(
      playlistKey: 'itest',
      epgUrl: epgUrl,
      channels: channels,
    );
    expect(offline, M3uEpgStatus.matched);
    expect(
      IptvEpgService.instance.peekNowNext(byId.url)?.now?.title,
      contains('mock1.test'),
    );
  });
}
