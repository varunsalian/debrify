import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/services/iptv_catalog_db.dart';
import 'package:debrify/services/iptv_catalog_key.dart';
import 'package:debrify/services/iptv_service.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/xtream_codes_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Directory directory;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    IptvService.instance.clearCache();
    XtreamCodesService.instance.clearCache();
    directory = await Directory.systemTemp.createTemp('iptv-download-scope-');
    IptvCatalogDb.debugDirectoryOverride = directory.path;
    await IptvCatalogDb.open();
  });
  tearDown(() async {
    IptvCatalogDb.debugClose();
    IptvCatalogDb.debugDirectoryOverride = null;
    ProfileRuntime.debugReset();
    await directory.delete(recursive: true);
  });

  for (final xtream in [false, true]) {
    for (final large in [false, true]) {
      for (final mode in [
        'keep connection',
        'replace connection',
        'cancel caller',
      ]) {
        final replaceConnection = mode == 'replace connection';
        final cancelCaller = mode == 'cancel caller';
        test(
          '${xtream ? 'Xtream' : 'M3U'} ${large ? 'worker' : 'inline'} download $mode',
          () async {
            final server = await HttpServer.bind(
              InternetAddress.loopbackIPv4,
              0,
            );
            final requested = Completer<void>();
            final release = Completer<void>();
            final base = 'http://127.0.0.1:${server.port}';
            final count = large ? 4000 : 1;
            final body = xtream
                ? jsonEncode([
                    for (var i = 1; i <= count; i++)
                      {
                        'stream_id': i,
                        'name': 'Movie $i',
                        'container_extension': 'mp4',
                      },
                  ])
                : '#EXTM3U\n${[for (var i = 1; i <= count; i++) '#EXTINF:-1,Channel $i\nhttp://example.test/live/$i.ts'].join('\n')}\n';
            server.listen((request) async {
              if (request.uri.queryParameters['action'] ==
                  'get_vod_categories') {
                request.response.write('[]');
              } else {
                if (!requested.isCompleted) requested.complete();
                await release.future;
                request.response.write(body);
              }
              await request.response.close();
            });
            final catalogKey = xtream
                ? IptvCatalogKey.forXtream(base, 'user', 'vod')
                : IptvCatalogKey.forUrl('$base/list.m3u');
            var current = true;
            final Future<IptvParseResult> download = xtream
                ? XtreamCodesService.instance.fetchVodStreams(
                    base,
                    'user',
                    'pass',
                    isCurrent: () => current,
                  )
                : IptvService.instance.fetchPlaylist(
                    '$base/list.m3u',
                    isCurrent: () => current,
                  );
            try {
              await requested.future.timeout(const Duration(seconds: 5));
              if (replaceConnection) {
                // Even reopening the SAME path must retire the earlier request.
                // Scope close must complete while the HTTP response is pending.
                IptvCatalogDb.markRevalidateStarted(catalogKey);
                await IptvCatalogDb.closeScope().timeout(
                  const Duration(seconds: 1),
                );
                await IptvCatalogDb.open();
                expect(
                  IptvCatalogDb.revalidateInterrupted(catalogKey),
                  isFalse,
                );
              }
              if (cancelCaller) current = false;
              release.complete();
              if (cancelCaller) {
                await expectLater(download, throwsStateError);
                expect(IptvCatalogDb.snapshot(catalogKey), isNull);
                return;
              }
              final result = await download.timeout(
                const Duration(seconds: 10),
              );
              if (replaceConnection) {
                expect(result.hasError, isTrue);
                expect(IptvCatalogDb.snapshot(catalogKey), isNull);
              } else {
                expect(result.hasError, isFalse, reason: result.error);
                expect(result.ingest?.channelCount, count);
                expect(IptvCatalogDb.snapshot(catalogKey)?.channelCount, count);
              }
            } finally {
              if (!release.isCompleted) release.complete();
              await server.close(force: true);
            }
          },
        );
      }
    }
  }

  test(
    'scope close clears live refreshes but preserves earlier crash markers',
    () async {
      IptvCatalogDb.markRevalidateStarted('crashed');
      IptvCatalogDb.debugClose();
      await IptvCatalogDb.open();
      IptvCatalogDb.markRevalidateStarted('running');
      await IptvCatalogDb.closeScope();
      await IptvCatalogDb.open();
      expect(IptvCatalogDb.revalidateInterrupted('crashed'), isTrue);
      expect(IptvCatalogDb.revalidateInterrupted('running'), isFalse);
    },
  );

  test('closing the scope drains an already admitted ingest', () async {
    final target = IptvCatalogDb.captureWriteTarget()!;
    final started = Completer<void>();
    final release = Completer<void>();
    final ingest = IptvCatalogDb.runWithWriteTarget(target, () async {
      started.complete();
      await release.future;
    });
    await started.future;
    var closed = false;
    final closing = IptvCatalogDb.closeScope().then((_) => closed = true);
    await Future<void>.delayed(Duration.zero);
    expect(closed, isFalse);
    release.complete();
    await ingest;
    await closing;
    var ranRetiredJob = false;
    await expectLater(
      IptvCatalogDb.runWithWriteTarget(target, () async {
        ranRetiredJob = true;
      }),
      throwsStateError,
    );
    expect(ranRetiredJob, isFalse);
  });
}
