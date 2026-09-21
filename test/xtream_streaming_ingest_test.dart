import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:debrify/services/iptv_catalog_db.dart';
import 'package:debrify/services/iptv_catalog_key.dart';
import 'package:debrify/services/iptv_load_phase.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/xtream_codes_service.dart';
import 'package:debrify/utils/m3u_parser.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart' as raw;

void main() {
  test(
    'leading UTF-8 BOM matches existing decoder across every byte boundary',
    () async {
      final bytes = [0xef, 0xbb, 0xbf, ...utf8.encode(' [{"name":"日本"}]')];
      final decoded = XtreamCodesService.decodeJsonListSync(
        XtreamCodesService.decodeResponseBytes(bytes, null),
        'streams',
      );
      expect(decoded.$2, isNull);
      expect(decoded.$1, [
        {'name': '日本'},
      ]);
      expect(
        await xtreamJsonItems(
          Stream.fromIterable(bytes.map((b) => [b])),
        ).toList(),
        decoded.$1,
      );
      for (final invalid in [
        [0xef],
        [0xef, 0xbb],
        [0xef, 0xbb, 0x00],
        [32, 0xef, 0xbb, 0xbf, 91, 93],
        [0xef, 0xbb, 0xbf, 0xef, 0xbb, 0xbf, 91, 93],
      ]) {
        await expectLater(
          xtreamJsonItems(
            Stream.fromIterable(invalid.map((b) => [b])),
          ).drain<void>(),
          throwsFormatException,
        );
      }
    },
  );

  test(
    'item parser handles byte boundaries, escaped strings and legacy text',
    () async {
      final items = [
        {
          'name': '日本 \\" } ]',
          'nested': [
            {'x': true},
          ],
          'stream_id': 1,
        },
      ];
      final bytes = utf8.encode(jsonEncode(items));
      expect(
        await xtreamJsonItems(
          Stream.fromIterable(bytes.map((b) => [b])),
        ).toList(),
        items,
      );
      expect(
        (await xtreamJsonItems(
          Stream.value(latin1.encode('[{"name":"Café"}]')),
        ).first)['name'],
        'Café',
      );
    },
  );

  test(
    'item parser rejects malformed tails, oversized items and deep nesting',
    () async {
      for (final body in [
        '[{},]',
        '[{}',
        '[{}]x',
        '[{"a":[]}',
        '{}',
        '[null]',
        '[{"a": invalid}]',
      ]) {
        await expectLater(
          xtreamJsonItems(Stream.value(utf8.encode(body))).drain<void>(),
          throwsFormatException,
          reason: body,
        );
      }
      await expectLater(
        xtreamJsonItems(
          Stream.value(utf8.encode('[{"name":"long"}]')),
          maxItemBytes: 8,
        ).drain<void>(),
        throwsFormatException,
      );
      await expectLater(
        xtreamJsonItems(
          Stream.value(utf8.encode('[{"a":[[[]]]}]')),
          maxDepth: 2,
        ).drain<void>(),
        throwsFormatException,
      );
    },
  );

  group('disk-backed fetch', () {
    late Directory root;
    late Directory downloads;
    late HttpServer server;
    late String base;
    var body = '';
    var slow = false;
    var current = true;
    var guardCalls = 0;
    var cancelAtPublication = false;
    var generatedEntries = 0;
    var emittedEntries = 0;
    var streamRequests = 0;
    var stallsRemaining = 0;
    var streamStatus = HttpStatus.ok;
    var categoryRequests = 0;
    var stallCategories = false;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      ProfileRuntime.debugReset();
      ProfileRuntime.initializeLegacy();
      root = await Directory.systemTemp.createTemp('xtream-ingest-test-');
      downloads = await Directory('${root.path}/downloads').create();
      XtreamCodesService.debugDownloadDirectory = downloads.path;
      IptvCatalogDb.debugDirectoryOverride = root.path;
      await IptvCatalogDb.open();
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      base = 'http://${server.address.host}:${server.port}';
      slow = false;
      current = true;
      guardCalls = 0;
      cancelAtPublication = false;
      generatedEntries = 0;
      emittedEntries = 0;
      streamRequests = 0;
      stallsRemaining = 0;
      streamStatus = HttpStatus.ok;
      categoryRequests = 0;
      stallCategories = false;
      body = '[{"name":"Original","stream_id":1,"category_id":"7"}]';
      server.listen((request) async {
        try {
          request.response.headers.contentType = ContentType.json;
          if (request.uri.queryParameters['action'] == 'get_vod_streams') {
            streamRequests++;
            if (streamStatus != HttpStatus.ok) {
              request.response.statusCode = streamStatus;
              await request.response.close();
              return;
            }
            if (stallsRemaining > 0) {
              stallsRemaining--;
              request.response.write('[{"name":"Partial discarded entry');
              await request.response.flush();
              await Future<void>.delayed(const Duration(milliseconds: 500));
              await request.response.close();
              return;
            }
          }
          if (request.uri.queryParameters['action'] == 'get_vod_categories') {
            categoryRequests++;
            if (stallCategories) {
              request.response.write('[');
              await request.response.flush();
              await Future<void>.delayed(const Duration(milliseconds: 500));
              await request.response.close();
              return;
            }
            request.response.write(
              '[{"category_id":"7","category_name":"Movies"}]',
            );
          } else if (generatedEntries > 0) {
            request.response.add([0xef, 0xbb, 0xbf]);
            request.response.write('[');
            for (var i = 0; i < generatedEntries; i++) {
              if (i > 0) request.response.write(',');
              request.response.write(
                jsonEncode({
                  'name': 'Generated movie $i',
                  'stream_id': i,
                  'category_id': '7',
                  'stream_icon': 'https://example.test/posters/$i.jpg',
                }),
              );
              emittedEntries++;
              // Bound the server's output buffer too: never build a body list
              // or string for this fixture, and yield to socket backpressure.
              if (emittedEntries % 128 == 0) await request.response.flush();
            }
            request.response.write(']');
          } else if (slow) {
            request.response.write('[');
            await request.response.flush();
            await Future<void>.delayed(const Duration(milliseconds: 250));
          } else {
            request.response.write(body);
          }
          await request.response.close();
        } catch (_) {}
      });
    });

    tearDown(() async {
      XtreamCodesService.debugMaxDownloadBytes = null;
      XtreamCodesService.debugDownloadDeadline = null;
      XtreamCodesService.debugDownloadDirectory = null;
      expect(downloads.listSync(), isEmpty);
      await server.close(force: true);
      IptvCatalogDb.debugClose();
      IptvCatalogDb.debugDirectoryOverride = null;
      ProfileRuntime.debugReset();
      await root.delete(recursive: true);
    });

    Future<dynamic> fetch() => XtreamCodesService.instance.fetchVodStreams(
      base,
      'user',
      'pass',
      isCurrent: () {
        guardCalls++;
        if (cancelAtPublication && guardCalls >= 5) current = false;
        return current;
      },
    );

    test(
      'category timeout is not retried and usable streams still publish',
      () async {
        stallCategories = true;
        XtreamCodesService.debugDownloadDeadline = const Duration(
          milliseconds: 150,
        );
        final result = await fetch();
        expect(result.hasError, isFalse, reason: result.error);
        expect(result.ingest.channelCount, 1);
        expect(result.warning, contains('categories'));
        expect(categoryRequests, 1);
        expect(streamRequests, 1);
        final key = IptvCatalogKey.forXtream(base, 'user', 'vod');
        expect(
          IptvCatalogDb.snapshot(key)!.page(offset: 0, limit: 1).single.name,
          'Original',
        );
      },
    );

    test('retries partial downloads and truncates before recovery', () async {
      stallsRemaining = 2;
      XtreamCodesService.debugDownloadDeadline = const Duration(
        milliseconds: 150,
      );
      final result = await fetch();
      expect(result.hasError, isFalse, reason: result.error);
      expect(streamRequests, 3);
      expect(result.ingest.channelCount, 1);
      final key = IptvCatalogKey.forXtream(base, 'user', 'vod');
      expect(
        IptvCatalogDb.snapshot(key)!.page(offset: 0, limit: 1).single.name,
        'Original',
      );
    });

    test('HTTP failures and size limits are not retried', () async {
      streamStatus = HttpStatus.serviceUnavailable;
      expect((await fetch()).hasError, isTrue);
      expect(streamRequests, 1);
      streamStatus = HttpStatus.ok;
      XtreamCodesService.debugMaxDownloadBytes = 8;
      expect((await fetch()).hasError, isTrue);
      expect(streamRequests, 2);
    });

    test(
      '50k streamed entries keep main isolate responsive and return only receipt',
      () async {
        generatedEntries = 50000;
        final mainBuilds = XtreamCodesService.buildsOnThisIsolate;
        final workerLaunches = XtreamCodesService.isolateBuilds;
        var processing = false;
        var downloadBeats = 0;
        var processingBeats = 0;
        final heartbeat = Timer.periodic(const Duration(milliseconds: 2), (_) {
          if (processing) {
            processingBeats++;
          } else {
            downloadBeats++;
          }
        });
        try {
          final result = await XtreamCodesService.instance.fetchVodStreams(
            base,
            'user',
            'pass',
            onPhase: (phase, {bytes, totalBytes}) {
              if (phase == IptvLoadPhases.processing) processing = true;
            },
          );
          expect(result.hasError, isFalse, reason: result.error);
          expect(emittedEntries, 50000);
          expect(result.channels, isEmpty);
          expect(result.ingest?.channelCount, 50000);
          expect(result.categories, ['Movies']);
          expect(XtreamCodesService.buildsOnThisIsolate, mainBuilds);
          expect(XtreamCodesService.isolateBuilds, workerLaunches + 1);
          expect(downloadBeats, greaterThan(0));
          expect(
            processingBeats,
            greaterThan(2),
            reason: 'Main isolate must tick while worker parses and ingests',
          );
          final snapshot = IptvCatalogDb.snapshot(
            IptvCatalogKey.forXtream(base, 'user', 'vod'),
          )!;
          expect(
            snapshot.page(offset: 49999, limit: 1).single.name,
            'Generated movie 49999',
          );
        } finally {
          heartbeat.cancel();
        }
      },
    );

    test(
      'M3U empty, header-only and stream errors retain prior catalog',
      () async {
        const key = 'm3u|empty-regression';
        Future<dynamic> ingest(Stream<String> lines) =>
            IptvCatalogDb.ingestM3uLines(
              dbPath: IptvCatalogDb.path,
              catalogKey: key,
              lines: lines,
            );
        await ingest(
          Stream.fromIterable([
            '#EXTM3U',
            '#EXTINF:-1,Original',
            'http://example.test/live',
          ]),
        );
        final generation = IptvCatalogDb.snapshot(key)!.generation;
        for (final text in [
          '',
          '\n',
          '#EXTM3U url-tvg="https://example.test/epg.xml"\n',
        ]) {
          final expected = M3uParser.parse(text);
          final result = await ingest(
            Stream.fromIterable(const LineSplitter().convert(text)),
          );
          expect(
            result.error,
            expected.error,
            reason: 'Input: ${jsonEncode(text)}',
          );
          expect(result.categories, expected.categories);
          expect(result.epgUrl, expected.epgUrl);
          expect(result.channels, isEmpty);
          expect(result.ingest, isNull);
          expect(IptvCatalogDb.snapshot(key)!.generation, generation);
        }
        final failure = StateError('source failed after committed chunks');
        Stream<String> failingLines() async* {
          yield '#EXTM3U';
          for (var i = 0; i < 3000; i++) {
            yield '#EXTINF:-1,Replacement $i';
            yield 'http://example.test/$i';
          }
          throw failure;
        }

        await expectLater(ingest(failingLines()), throwsA(same(failure)));
        expect(IptvCatalogDb.snapshot(key)!.generation, generation);
        final db = raw.sqlite3.open(IptvCatalogDb.path);
        try {
          expect(
            db.select(
              'SELECT COUNT(*) AS n FROM channels WHERE catalog_key = ?',
              [key],
            ).single['n'],
            1,
          );
        } finally {
          db.dispose();
        }
      },
    );

    test(
      'large refresh publishes receipt; malformed tail rolls back committed chunks',
      () async {
        final first = await fetch();
        expect(first.ingest.channelCount, 1);
        final key = IptvCatalogKey.forXtream(base, 'user', 'vod');
        final original = IptvCatalogDb.snapshot(key)!;
        final rows = List.generate(
          6000,
          (i) => jsonEncode({
            'name': 'Movie $i',
            'stream_id': i,
            'category_id': '7',
          }),
        ).join(',');
        body = '[$rows,broken]';
        expect((await fetch()).hasError, isTrue);
        expect(IptvCatalogDb.snapshot(key)!.generation, original.generation);
        final db = raw.sqlite3.open(IptvCatalogDb.path);
        try {
          expect(db.select('SELECT COUNT(*) AS n FROM channels').first['n'], 1);
        } finally {
          db.dispose();
        }
        body = '[$rows]';
        final result = await fetch();
        expect(result.hasError, isFalse, reason: result.error);
        expect(result.channels, isEmpty);
        expect(result.ingest.channelCount, 6000);
        expect(
          IptvCatalogDb.snapshot(key)!.page(offset: 5999, limit: 1).single.name,
          'Movie 5999',
        );
        expect(result.categories, ['Movies']);
      },
    );

    test(
      'cap, deadline, empty response and cancellation preserve prior generation',
      () async {
        await fetch();
        final key = IptvCatalogKey.forXtream(base, 'user', 'vod');
        final generation = IptvCatalogDb.snapshot(key)!.generation;
        XtreamCodesService.debugMaxDownloadBytes = 8;
        expect((await fetch()).hasError, isTrue);
        XtreamCodesService.debugMaxDownloadBytes = null;
        slow = true;
        XtreamCodesService.debugDownloadDeadline = const Duration(
          milliseconds: 50,
        );
        expect((await fetch()).hasError, isTrue);
        slow = false;
        XtreamCodesService.debugDownloadDeadline = null;
        body = '[]';
        expect((await fetch()).ingest, isNull);
        body = '[{"name":"Replacement","stream_id":2}]';
        guardCalls = 0;
        cancelAtPublication = true;
        try {
          await fetch();
        } catch (_) {}
        expect(guardCalls, greaterThanOrEqualTo(5));
        expect(IptvCatalogDb.snapshot(key)!.generation, generation);
      },
    );
  });
}
