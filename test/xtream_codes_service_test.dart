import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:debrify/services/iptv_catalog_key.dart';
import 'package:debrify/services/iptv_catalog_db.dart';
import 'package:debrify/services/xtream_codes_service.dart';

/// End-to-end coverage of the Xtream stream fetch against a fake panel.
///
/// The decode + channel construction moved into a single isolate pass (it was
/// blocking the UI thread long enough on a 50k-channel panel for Android to
/// declare the app unresponsive). These tests pin the observable contract of
/// that path: the URL shapes, the attribute mapping each content type
/// carries, how category failures degrade, and — via a deliberately oversized
/// payload — that the built channels survive the isolate boundary intact.
void main() {
  group('xtream stream fetch (real fetch against an in-test panel)', () {
    late HttpServer server;
    late String base;

    // Per-test panel behavior.
    var liveRows = <Map<String, dynamic>>[];

    /// Overrides for the streams response's wire format. Null means "behave
    /// like a normal panel": JSON declaring charset=utf-8.
    ContentType? streamsContentType;
    List<int>? streamsRawBytes;
    var vodRows = <Map<String, dynamic>>[];
    var seriesRows = <Map<String, dynamic>>[];
    var categoriesFail = false;
    var streamsError = false;
    var streamsHttpStatus = HttpStatus.ok;

    /// Which live-URL dialect this panel routes. Everything else 404s, so the
    /// probe has to actually find the right one — a panel that 200s every
    /// path would make "first 2xx wins" degenerate into "first enum value
    /// wins" and leave the probe (and the regex feeding it) untested.
    var servedLiveForm = 'standard-ts';

    bool servesLivePath(String path) {
      final legacy = RegExp(r'^/[^/]+/[^/]+/(\d+)\.(ts|m3u8)$');
      final standard = RegExp(r'^/live/[^/]+/[^/]+/(\d+)\.(ts|m3u8)$');
      final match = standard.firstMatch(path) ?? legacy.firstMatch(path);
      if (match == null) return false;
      final isStandard = standard.hasMatch(path);
      // Only ids the panel actually publishes answer. A probe aimed at a
      // stream that doesn't exist must fail like the real thing — otherwise
      // a sample-id bug (probing "12" out of "12ab") would look like success.
      final ids = {for (final row in liveRows) row['stream_id'].toString()};
      if (!ids.contains(match.group(1))) return false;
      final ext = path.endsWith('.ts') ? 'ts' : 'm3u8';
      return switch (servedLiveForm) {
        'standard-ts' => isStandard && ext == 'ts',
        'standard-hls' => isStandard && ext == 'm3u8',
        'legacy-ts' => !isStandard && ext == 'ts',
        // A panel routing BOTH standard forms: the probe order decides, and
        // raw TS must win (an HLS ladder can pin a 4K channel at 720p).
        'standard-both' => isStandard,
        // 'none': every dialect 404s.
        _ => false,
      };
    }

    setUpAll(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      base = 'http://127.0.0.1:${server.port}';
      server.listen((request) {
        final path = request.uri.path;
        // The live-URL-form probe asks for a real stream URL and takes the
        // first 2xx as the panel's dialect.
        if (path != '/player_api.php') {
          request.response.statusCode = servesLivePath(path)
              ? HttpStatus.ok
              : HttpStatus.notFound;
          request.response.close();
          return;
        }
        final action = request.uri.queryParameters['action'] ?? '';
        if (!action.endsWith('_categories') &&
            streamsHttpStatus != HttpStatus.ok) {
          request.response.statusCode = streamsHttpStatus;
          request.response.close();
          return;
        }
        if (action.endsWith('_categories')) {
          if (categoriesFail) {
            request.response.statusCode = HttpStatus.internalServerError;
            request.response.close();
            return;
          }
          request.response
            ..headers.contentType = ContentType.json
            ..write(
              jsonEncode([
                {'category_id': '1', 'category_name': 'Sports'},
                {'category_id': '2', 'category_name': 'News'},
              ]),
            );
          request.response.close();
          return;
        }
        if (streamsError) {
          // Panels report auth/subscription problems as a 200 object, not a
          // status code.
          request.response
            ..headers.contentType = ContentType.json
            ..write(jsonEncode({'error': 'Account expired'}));
          request.response.close();
          return;
        }
        final rows = switch (action) {
          'get_live_streams' => liveRows,
          'get_vod_streams' => vodRows,
          'get_series' => seriesRows,
          _ => const <Map<String, dynamic>>[],
        };
        // Raw bytes when a test needs to control the wire encoding exactly;
        // `write` would re-encode using the declared charset and hide it.
        final raw = streamsRawBytes;
        request.response.headers.contentType =
            streamsContentType ?? ContentType.json;
        if (raw != null) {
          request.response.add(raw);
        } else {
          request.response.write(jsonEncode(rows));
        }
        request.response.close();
      });
    });

    tearDownAll(() async => server.close(force: true));

    setUp(() {
      categoriesFail = false;
      streamsError = false;
      streamsHttpStatus = HttpStatus.ok;
      servedLiveForm = 'standard-ts';
      liveRows = [];
      vodRows = [];
      seriesRows = [];
      streamsContentType = null;
      streamsRawBytes = null;
      XtreamCodesService.isolateBuilds = 0;
      XtreamCodesService.buildsOnThisIsolate = 0;
      // The service caches per server:user:type for 30 minutes and remembers
      // the probed URL form per server:user — both would leak between tests.
      XtreamCodesService.instance.clearCache();
    });

    test('live streams become /live/ TS channels with guide + catchup '
        'attributes', () async {
      liveRows = [
        {
          'name': 'Sky Sports F1',
          'stream_id': 42,
          'category_id': '1',
          'stream_icon': 'http://logo/f1.png',
          'epg_channel_id': 'SkySportsF1.uk',
          'tv_archive': 1,
          'tv_archive_duration': 7,
        },
      ];

      final result = await XtreamCodesService.instance.fetchLiveStreams(
        base,
        'u1',
        'p1',
      );

      expect(result.hasError, isFalse);
      expect(result.channels, hasLength(1));
      final channel = result.channels.single;
      expect(channel.name, 'Sky Sports F1');
      expect(channel.url, '$base/live/u1/p1/42.ts');
      expect(channel.group, 'Sports');
      expect(channel.logoUrl, 'http://logo/f1.png');
      expect(channel.isLive, isTrue);
      expect(channel.duration, -1, reason: 'the live sentinel');
      expect(channel.tvgId, 'SkySportsF1.uk');
      expect(channel.attributes['stream_id'], '42');
      expect(channel.attributes['tv_archive'], '1');
      expect(channel.attributes['tv_archive_duration'], '7');
      expect(result.categories, containsAll(['Sports', 'News']));
    });

    test('rows without a name or stream id are dropped', () async {
      liveRows = [
        {'name': '', 'stream_id': 1},
        {'name': 'No id', 'category_id': '1'},
        {'name': 'Keeper', 'stream_id': 7, 'category_id': '2'},
      ];

      final result = await XtreamCodesService.instance.fetchLiveStreams(
        base,
        'u2',
        'p2',
      );

      expect(result.channels.map((c) => c.name), ['Keeper']);
      expect(result.channels.single.group, 'News');
    });

    test(
      'a category failure degrades to ungrouped channels with a warning',
      () async {
        categoriesFail = true;
        liveRows = [
          {'name': 'Orphan', 'stream_id': 9, 'category_id': '1'},
        ];

        final result = await XtreamCodesService.instance.fetchLiveStreams(
          base,
          'u3',
          'p3',
        );

        expect(result.channels.single.group, isNull);
        expect(result.categories, isEmpty);
        expect(result.warning, contains('ungrouped'));
        expect(result.hasError, isFalse, reason: 'channels still load');
      },
    );

    test(
      'VOD streams become /movie/ URLs honoring container_extension',
      () async {
        vodRows = [
          {
            'name': 'Dune',
            'stream_id': 5,
            'category_id': '1',
            'container_extension': 'mkv',
            'rating': '8.8',
          },
          {'name': 'No extension', 'stream_id': 6},
        ];

        final result = await XtreamCodesService.instance.fetchVodStreams(
          base,
          'u4',
          'p4',
        );

        expect(result.channels.first.url, '$base/movie/u4/p4/5.mkv');
        expect(result.channels.first.contentType, 'vod');
        expect(result.channels.first.attributes['rating'], '8.8');
        expect(
          result.channels.last.url,
          '$base/movie/u4/p4/6.mp4',
          reason: 'mp4 is the documented default',
        );
      },
    );

    test(
      'series become sentinel-URL entries carrying their metadata',
      () async {
        seriesRows = [
          {
            'name': 'Planet Earth',
            'series_id': 77,
            'category_id': '2',
            // Both art fields present: `cover` is the series art and must win.
            'cover': 'http://art/cover.jpg',
            'stream_icon': 'http://art/icon.jpg',
            'plot': 'Nature.',
            'genre': 'Documentary',
            'release_date': '2006-03-05',
            'rating': '9.4',
            'backdrop_path': ['http://art/back.jpg', 'http://art/back2.jpg'],
          },
        ];

        final result = await XtreamCodesService.instance.fetchSeriesStreams(
          base,
          'u5',
          'p5',
        );

        final series = result.channels.single;
        expect(series.url, 'xtream-series://77');
        expect(series.contentType, 'series');
        expect(series.logoUrl, 'http://art/cover.jpg');
        expect(series.attributes['series_id'], '77');
        expect(series.attributes['plot'], 'Nature.');
        expect(series.attributes['genre'], 'Documentary');
        expect(series.attributes['releaseDate'], '2006-03-05');
        expect(
          series.attributes['backdrop'],
          'http://art/back.jpg',
          reason: 'the FIRST backdrop is the one shown',
        );
        expect(series.group, 'News');
        expect(series.isLive, isFalse);
      },
    );

    test('series rows without a series_id are dropped', () async {
      // They would otherwise all collapse onto the same sentinel URL, which
      // every URL-keyed pathway (focus nodes, dedupe, search) treats as one.
      seriesRows = [
        {'name': 'No id', 'category_id': '1'},
        {'name': 'Keeper', 'series_id': 8},
      ];

      final result = await XtreamCodesService.instance.fetchSeriesStreams(
        base,
        'u16',
        'p16',
      );

      expect(result.channels.map((c) => c.name), ['Keeper']);
    });

    test('a panel serving only HLS is detected and its channels get .m3u8 '
        'URLs', () async {
      servedLiveForm = 'standard-hls';
      liveRows = [
        {'name': 'HLS only', 'stream_id': 11},
      ];

      final result = await XtreamCodesService.instance.fetchLiveStreams(
        base,
        'u8',
        'p8',
      );

      expect(result.channels.single.url, '$base/live/u8/p8/11.m3u8');
    });

    test('a legacy panel (no /live/ prefix) is detected', () async {
      servedLiveForm = 'legacy-ts';
      liveRows = [
        {'name': 'Legacy', 'stream_id': 12},
      ];

      final result = await XtreamCodesService.instance.fetchLiveStreams(
        base,
        'u9',
        'p9',
      );

      expect(result.channels.single.url, '$base/u9/p9/12.ts');
    });

    test('raw TS is preferred over HLS when a panel serves both', () async {
      servedLiveForm = 'standard-both';
      liveRows = [
        {'name': 'Both dialects', 'stream_id': 14},
      ];

      final result = await XtreamCodesService.instance.fetchLiveStreams(
        base,
        'u12',
        'p12',
      );

      expect(
        result.channels.single.url,
        endsWith('.ts'),
        reason: 'an HLS ladder can pin a 4K channel at 720p on TV boxes',
      );
    });

    test('a panel that 404s every dialect freezes no verdict in', () async {
      servedLiveForm = 'none';
      liveRows = [
        {'name': 'Nothing routes', 'stream_id': 15},
      ];

      final result = await XtreamCodesService.instance.fetchLiveStreams(
        base,
        'u13',
        'p13',
      );

      expect(
        result.channels.single.url,
        '$base/live/u13/p13/15.ts',
        reason: 'falls back to the standard form for this fetch',
      );
      expect(
        XtreamCodesService.instance.cachedLiveUrlFormCount,
        0,
        reason: 'learning nothing must not pin a dialect for the session',
      );
    });

    test('a detected dialect is remembered for the panel', () async {
      servedLiveForm = 'legacy-ts';
      liveRows = [
        {'name': 'Legacy', 'stream_id': 16},
      ];

      await XtreamCodesService.instance.fetchLiveStreams(base, 'u14', 'p14');

      expect(
        XtreamCodesService.instance.cachedLiveUrlFormCount,
        1,
        reason: 'probe once per panel, not once per fetch',
      );
    });

    test('a non-numeric stream_id does not send the probe after a phantom '
        'stream', () async {
      // The sample is read from the RAW body, so a junk id must not match a
      // numeric prefix ("12ab" → 12) and probe a stream that doesn't exist.
      servedLiveForm = 'legacy-ts';
      liveRows = [
        {'name': 'Junk id', 'stream_id': '12ab'},
        {'name': 'Real', 'stream_id': 17},
      ];

      final result = await XtreamCodesService.instance.fetchLiveStreams(
        base,
        'u15',
        'p15',
      );

      expect(
        result.channels.last.url,
        '$base/u15/p15/17.ts',
        reason: 'the probe must have used the real id to detect legacy',
      );
    });

    test('a string-typed stream_id still seeds the probe', () async {
      // Panels disagree on whether ids are numbers or strings, and the probe
      // reads its sample out of the RAW body — the quoted form is a distinct
      // branch of that regex.
      servedLiveForm = 'legacy-ts';
      liveRows = [
        {'name': 'Quoted id', 'stream_id': '13'},
      ];

      final result = await XtreamCodesService.instance.fetchLiveStreams(
        base,
        'u10',
        'p10',
      );

      expect(
        result.channels.single.url,
        '$base/u10/p10/13.ts',
        reason: 'a missed sample would fall back to the standard form',
      );
    });

    // Everything above stays under the size threshold and so exercises the
    // inline path. This one proves the isolate really runs AND that a built
    // catalog survives the boundary.
    test('a large payload is built in an isolate and returns intact', () async {
      liveRows = [
        for (var i = 0; i < 1200; i++)
          {
            'name': 'Channel $i ${'padding' * 12}',
            'stream_id': i,
            'category_id': i.isEven ? '1' : '2',
            'epg_channel_id': 'chan$i.tv',
          },
      ];
      expect(
        jsonEncode(liveRows).length,
        greaterThan(XtreamCodesService.computeDecodeThreshold),
        reason: 'must exceed the real threshold to take the isolate path',
      );

      // The counter only proves which BRANCH was taken. What actually
      // matters is that the build didn't run HERE. Timing can't prove that
      // — on a fast machine an inline build of this payload is only ~20ms —
      // but a static can: statics aren't shared across isolates, so the
      // worker increments its own copy and ours stays untouched.
      final result = await XtreamCodesService.instance.fetchLiveStreams(
        base,
        'u6',
        'p6',
      );

      expect(XtreamCodesService.isolateBuilds, 1);
      expect(
        XtreamCodesService.buildsOnThisIsolate,
        0,
        reason: 'the whole point is that this isolate stayed free',
      );
      expect(result.channels, hasLength(1200));
      final first = result.channels.first;
      expect(first.url, '$base/live/u6/p6/0.ts');
      expect(first.tvgId, 'chan0.tv');
      expect(first.group, 'Sports');
      expect(result.channels.last.group, 'News');
      // Lazily-initialized field, read for the first time on this side of the
      // boundary — the built objects have to be whole for this to work.
      expect(first.searchKey, contains('channel 0'));
    });

    // The bodies cross to the worker as raw bytes and are decoded THERE —
    // `Response.body` would have burned that decode on the calling thread,
    // which for a tens-of-MB panel is hundreds of milliseconds of the freeze
    // the isolate exists to remove. These lock the two halves of that: the
    // decode must still be correct, and it must still match what package:http
    // would have produced.
    test('non-ASCII names survive the byte handoff intact', () async {
      liveRows = [
        for (var i = 0; i < 1200; i++)
          {
            'name': 'Спорт Канал $i ᴴᴰ ${'padding' * 12}',
            'stream_id': i,
            'category_id': '1',
          },
      ];
      expect(
        utf8.encode(jsonEncode(liveRows)).length,
        greaterThan(XtreamCodesService.computeDecodeThreshold),
      );

      final result = await XtreamCodesService.instance.fetchLiveStreams(
        base,
        'u20',
        'p20',
      );

      expect(
        XtreamCodesService.buildsOnThisIsolate,
        0,
        reason: 'the decode has to happen on the worker, not here',
      );
      expect(result.channels.first.name, startsWith('Спорт Канал 0 ᴴᴰ'));
      expect(result.channels.last.name, contains('Канал 1199'));
      // A multi-byte name must not have derailed the id probe, which reads
      // the head of the payload as raw bytes.
      expect(result.channels.first.url, '$base/live/u20/p20/0.ts');
    });

    test(
      'an undeclared charset falls back to latin1, as package:http does',
      () async {
        // A panel that serves UTF-8 bytes without saying so. package:http's
        // `Response.body` resolves an absent charset to latin1, so it produced
        // mojibake here long before any isolate existed. Moving the decode must
        // not quietly change what a user's channel list says — fixing that is a
        // separate, deliberate change with its own migration story for the
        // URL-keyed favorites that would suddenly disagree.
        const name = 'Спорт';
        streamsContentType = ContentType('application', 'json');
        streamsRawBytes = utf8.encode(
          jsonEncode([
            {'name': name, 'stream_id': 7},
          ]),
        );

        final result = await XtreamCodesService.instance.fetchLiveStreams(
          base,
          'u21',
          'p21',
        );

        expect(
          result.channels.single.name,
          latin1.decode(utf8.encode(name)),
          reason: 'byte-for-byte what Response.body would have returned',
        );
        expect(result.channels.single.name, isNot(name));
      },
    );

    test('a declared charset is honoured on the worker', () async {
      const name = 'Спорт';
      streamsContentType = ContentType('application', 'json', charset: 'utf-8');
      streamsRawBytes = utf8.encode(
        jsonEncode([
          {'name': name, 'stream_id': 7},
        ]),
      );

      final result = await XtreamCodesService.instance.fetchLiveStreams(
        base,
        'u22',
        'p22',
      );

      expect(result.channels.single.name, name);
    });

    test('a fat first record does not hide the id from the probe', () async {
      servedLiveForm = 'legacy-ts';
      // One oversized first record pushes the id far past the first few KB.
      // A panel whose dialect goes undetected serves every channel under the
      // wrong URL — nothing plays at all — so the probe window has to be
      // generous, not merely "one screen of records".
      liveRows = [
        {'plot': 'x' * 200000, 'name': 'Fat', 'stream_id': 1},
        {'name': 'Normal', 'stream_id': 2},
      ];
      expect(
        200000,
        lessThan(XtreamCodesService.streamIdProbeWindow),
        reason: 'the fat record must sit inside the window, not beyond it',
      );

      final result = await XtreamCodesService.instance.fetchLiveStreams(
        base,
        'u30',
        'p30',
      );

      expect(
        result.channels.first.url,
        '$base/u30/p30/1.ts',
        reason: 'legacy dialect must still be detected',
      );
    });

    test('a small payload skips the isolate', () async {
      liveRows = [
        {'name': 'Tiny', 'stream_id': 1},
      ];

      await XtreamCodesService.instance.fetchLiveStreams(base, 'u11', 'p11');

      expect(
        XtreamCodesService.isolateBuilds,
        0,
        reason: 'spawning an isolate would cost more than the work',
      );
    });

    test(
      'a repeat fetch is served from cache without touching the panel',
      () async {
        liveRows = [
          {'name': 'Cached', 'stream_id': 20},
        ];
        await XtreamCodesService.instance.fetchLiveStreams(base, 'u17', 'p17');

        // The panel now answers with something completely different; a cache
        // hit means we never see it.
        liveRows = [
          {'name': 'Changed', 'stream_id': 21},
        ];
        final second = await XtreamCodesService.instance.fetchLiveStreams(
          base,
          'u17',
          'p17',
        );

        expect(second.channels.single.name, 'Cached');
      },
    );

    test('the cache is keyed by content type, not just the account', () async {
      liveRows = [
        {'name': 'A live channel', 'stream_id': 22},
      ];
      vodRows = [
        {'name': 'A movie', 'stream_id': 23},
      ];

      await XtreamCodesService.instance.fetchLiveStreams(base, 'u18', 'p18');
      final vod = await XtreamCodesService.instance.fetchVodStreams(
        base,
        'u18',
        'p18',
      );

      expect(
        vod.channels.single.name,
        'A movie',
        reason: 'Movies must never be served the live catalog',
      );
      expect(vod.channels.single.contentType, 'vod');
    });

    test(
      'a non-200 streams response is an error, not an empty catalog',
      () async {
        streamsHttpStatus = HttpStatus.badGateway;

        final result = await XtreamCodesService.instance.fetchLiveStreams(
          base,
          'u19',
          'p19',
        );

        expect(result.hasError, isTrue);
        expect(result.error, contains('502'));
        expect(result.channels, isEmpty);
      },
    );

    test(
      'a panel error object is privacy-safe, not an empty catalog',
      () async {
        streamsError = true;

        final result = await XtreamCodesService.instance.fetchLiveStreams(
          base,
          'u7',
          'p7',
        );

        expect(result.hasError, isTrue);
        expect(result.error, 'Server returned an error');
        expect(result.error, isNot(contains('Account expired')));
        expect(result.channels, isEmpty);
        expect(
          result.warning,
          isNull,
          reason: 'the error is the message, not a degradation notice',
        );
      },
    );

    test('a non-JSON body is rejected without reflecting server text', () {
      final (list, error) = XtreamCodesService.decodeJsonListSync(
        '<html>Forbidden</html>',
        'streams',
      );
      expect(list, isNull);
      expect(error, 'Server returned invalid response for streams');
      expect(error, isNot(contains('Forbidden')));
    });
  });

  group('DB-catalog mode (worker ingests, UI gets a receipt)', () {
    late HttpServer server;
    late String base;
    late Directory dir;

    setUpAll(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      base = 'http://127.0.0.1:${server.port}';
      server.listen((request) {
        final action = request.uri.queryParameters['action'] ?? '';
        if (request.uri.path != '/player_api.php') {
          // Live-URL probe: standard TS answers.
          request.response.statusCode =
              request.uri.path.startsWith('/live/') &&
                  request.uri.path.endsWith('.ts')
              ? HttpStatus.ok
              : HttpStatus.notFound;
          request.response.close();
          return;
        }
        request.response.headers.contentType = ContentType.json;
        if (action.endsWith('_categories')) {
          request.response.write(
            jsonEncode([
              {'category_id': '1', 'category_name': 'Sports'},
            ]),
          );
        } else {
          request.response.write(
            jsonEncode([
              {'name': 'Sky Sports F1', 'stream_id': 42, 'category_id': '1'},
              {'name': 'BBC One', 'stream_id': 43, 'category_id': ''},
            ]),
          );
        }
        request.response.close();
      });
    });

    tearDownAll(() async => server.close(force: true));

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      dir = await Directory.systemTemp.createTemp('xtream_ingest');
      IptvCatalogDb.debugDirectoryOverride = dir.path;
      await IptvCatalogDb.open();
      XtreamCodesService.instance.clearCache();
    });

    tearDown(() async {
      IptvCatalogDb.debugClose();
      IptvCatalogDb.debugDirectoryOverride = null;
      await dir.delete(recursive: true);
    });

    test('a fetch lands in the DB and returns a receipt, not a list', () async {
      final result = await XtreamCodesService.instance.fetchLiveStreams(
        base,
        'user',
        'pass',
      );

      expect(result.hasError, isFalse);
      expect(
        result.channels,
        isEmpty,
        reason: 'the object graph must not cross back to this isolate',
      );
      expect(
        result.isEmpty,
        isFalse,
        reason: 'an ingested catalog is not an empty result',
      );
      final receipt = result.ingest!;
      expect(receipt.channelCount, 2);
      expect(
        receipt.catalogKey,
        IptvCatalogKey.forXtream(base, 'user', 'live'),
      );

      final snap = IptvCatalogDb.snapshot(receipt.catalogKey)!;
      expect(snap.channelCount, 2);
      expect(snap.contentDigest, receipt.contentDigest);
      expect(snap.categories, ['Sports']);
      final rows = snap.page(offset: 0, limit: 10);
      expect(rows.first.name, 'Sky Sports F1');
      expect(rows.first.url, '$base/live/user/pass/42.ts');
      expect(rows.first.group, 'Sports');

      expect(
        XtreamCodesService.instance.cachedResult(base, 'user', 'live'),
        isNull,
        reason: 'DB mode must not also hold the catalog on the service heap',
      );
    });

    test('without an open catalog DB the fetch returns a plain list', () async {
      // The old `iptv_db_catalog_enabled` preference is gone — ingest now
      // depends only on whether the catalog database is available, which is
      // the condition that actually decides where rows can go.
      IptvCatalogDb.debugClose();

      final result = await XtreamCodesService.instance.fetchLiveStreams(
        base,
        'u2',
        'p2',
      );

      expect(result.ingest, isNull);
      expect(result.channels.length, 2);
    });
  });
}
