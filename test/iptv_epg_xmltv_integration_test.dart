import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/services/iptv_epg_service.dart';

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

void main() {
  late Directory storageRoot;
  late HttpServer server;
  late int port;
  var xmltvHits = 0;
  var shortEpgHits = 0;
  // When true, get_simple_data_table answers real rows (with has_archive) —
  // the healthy-panel case whose catchup flags the schedule path must keep.
  var serveDataTable = false;

  String guideXml() {
    final now = DateTime.now().toUtc();
    const slot = Duration(minutes: 30);
    final start = DateTime.utc(now.year, now.month, now.day, now.hour)
        .subtract(slot);
    String fmt(DateTime t) =>
        '${t.year.toString().padLeft(4, '0')}'
        '${t.month.toString().padLeft(2, '0')}'
        '${t.day.toString().padLeft(2, '0')}'
        '${t.hour.toString().padLeft(2, '0')}'
        '${t.minute.toString().padLeft(2, '0')}00 +0000';
    final b = StringBuffer('<?xml version="1.0" encoding="UTF-8"?><tv>');
    // Guide publishes lowercase ids; the "playlist" below carries uppercase.
    b.write('<channel id="mock1.test">'
        '<display-name>Mock One</display-name></channel>');
    b.write('<channel id="namedonly.guide">'
        '<display-name>Named Only Channel</display-name></channel>');
    for (final id in ['mock1.test', 'namedonly.guide']) {
      for (var i = 0; i < 8; i++) {
        final s = start.add(slot * i);
        final e = start.add(slot * (i + 1));
        b.write('<programme start="${fmt(s)}" stop="${fmt(e)}" '
            'channel="$id"><title>Show $i on $id</title>'
            '<desc>Description $i</desc></programme>');
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
        // Served as a gzip FILE (magic bytes), like real panels do.
        final body = gzip.encode(utf8.encode(guideXml()));
        request.response.headers.contentType =
            ContentType('application', 'octet-stream');
        request.response.add(body);
      } else {
        shortEpgHits++;
        request.response.headers.contentType = ContentType.json;
        final action = request.uri.queryParameters['action'] ?? '';
        if (serveDataTable && action == 'get_simple_data_table') {
          // Healthy panel: a data table with archive flags on past rows.
          final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
          const slot = 1800;
          final start = (now ~/ slot) * slot;
          final rows = [
            for (var i = -2; i < 4; i++)
              {
                'title': base64Encode(utf8.encode('Panel Show ${i + 2}')),
                'description': '',
                'start_timestamp': '${start + i * slot}',
                'stop_timestamp': '${start + (i + 1) * slot}',
                if (i < 0) 'has_archive': 1,
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

  IptvChannel liveChannel(int id, {String? tvgId, String? name}) => IptvChannel(
        name: name ?? 'Channel $id',
        url: 'http://127.0.0.1:$port/live/user/pass/$id.ts',
        duration: -1,
        contentType: 'live',
        attributes: {if (tvgId != null) 'tvg-id': tvgId},
      );

  test(
      'healthy panel: schedule prefers the per-stream data table (catchup '
      'flags survive) while now/next keeps the local XMLTV fast path',
      () async {
    serveDataTable = true;
    final ch = liveChannel(10, tvgId: 'MOCK1.TEST');
    // Distinct guide URL => distinct snapshot, so this test's filtered
    // snapshot can't shadow the next test's channels.
    final epgUrl = IptvEpgService.xmltvUrlFor(
        'http://127.0.0.1:$port', 'ordering', 'pass');
    final status = await IptvEpgService.instance.setM3uEpgContext(
      playlistKey: 'itest-order',
      epgUrl: epgUrl,
      channels: [ch],
    );
    expect(status, M3uEpgStatus.matched);

    // Schedule = per-stream rows, not the XMLTV index — and the archive
    // flags catchup replay needs are intact.
    final schedule = await IptvEpgService.instance.schedule(ch.url);
    expect(schedule.any((p) => p.title.startsWith('Panel Show')), isTrue,
        reason: 'per-stream data table must win over the XMLTV index');
    expect(schedule.any((p) => p.hasArchive), isTrue,
        reason: 'has_archive flags must survive for catchup');

    // now/next still answers instantly from the local XMLTV index.
    final peek = IptvEpgService.instance.peekNowNext(ch.url);
    expect(peek, isNotNull);
    expect(peek!.now?.title, contains('mock1.test'));

    serveDataTable = false;
    IptvEpgService.instance.clearM3uEpgContext();
  });

  test(
      'broken-short_epg panel: xmltv.php layering delivers now/next '
      '(case-insensitive ids + name-only fallback), snapshot survives '
      'the panel going down', () async {
    xmltvHits = 0; // this test's guide URL is distinct from the one above
    // Channels shaped exactly like XtreamCodesService builds them.
    final byId = liveChannel(1, tvgId: 'MOCK1.TEST'); // case-mismatched id
    final byName =
        liveChannel(2, name: 'Named Only Channel'); // no tvg-id at all
    final uncovered = liveChannel(3, tvgId: 'not.in.guide');
    final channels = [byId, byName, uncovered];

    final epgUrl =
        IptvEpgService.xmltvUrlFor('http://127.0.0.1:$port', 'user', 'pass');

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
