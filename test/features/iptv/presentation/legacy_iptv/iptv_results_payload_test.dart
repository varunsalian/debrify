import 'dart:convert';
import 'dart:io';

import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/services/iptv_catalog_db.dart';
import 'package:debrify/services/iptv_catalog_key.dart';
import 'package:debrify/services/xtream_codes_service.dart';
import 'package:debrify/services/storage/iptv_playlist_storage.dart';
import 'package:debrify/widgets/iptv/iptv_results_view.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../support/iptv_results_fixture.dart';

class _LocalHttp extends HttpOverrides {}

void expectOrderedPayload(String name, Object? payload, {String? server}) {
  expect(payload, isNotNull);
  var encoded = jsonEncode(payload);
  if (server != null) encoded = encoded.replaceAll(server, '<panel>');
  final file = File('test/fixtures/iptv_results_payload/$name.json');
  expect(encoded, file.readAsStringSync().trim());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final cases = [
    (
      name: 'browse',
      request: <String, dynamic>{'category': 'Kids', 'query': 'channel 5'},
    ),
    (
      name: 'zap_page',
      request: <String, dynamic>{
        'action': 'zapPage',
        'category': 'Kids',
        'limit': 3,
        'anchorUrl': 'https://example.test/live/8.ts',
        'anchorName': 'Channel 8',
      },
    ),
    (
      name: 'zap_from_end',
      request: <String, dynamic>{
        'action': 'zapPage',
        'category': 'All',
        'limit': 4,
        'fromEnd': true,
      },
    ),
    (
      name: 'channel_number',
      request: <String, dynamic>{
        'action': 'channelNumber',
        'channelNumber': 8,
        'limit': 2,
      },
    ),
    (
      name: 'missing_channel_number',
      request: <String, dynamic>{
        'action': 'channelNumber',
        'channelNumber': 99,
      },
    ),
    (
      name: 'uncached_episodes',
      request: <String, dynamic>{'contentType': 'episodes'},
    ),
  ];
  for (final example in cases) {
    testWidgets(
      'ordered SQL payload: ${example.name}',
      (tester) => iptvResultsCase(tester, (view) async {
        await view.mount(tester);
        Object? payload;
        var completed = false;
        final future = iptvResultsViewTestAccess(
          view.state,
        ).browse(example.request);
        future.then((result) {
          payload = result;
          completed = true;
        });
        await view.until(tester, () => completed);
        await future;
        expectOrderedPayload(example.name, payload);
      }),
    );
  }

  testWidgets('ordered series drill-in and cached episode search payloads', (
    tester,
  ) async {
    late IptvResultsFixture view;
    late String base;
    await tester.runAsync(
      () => HttpOverrides.runWithHttpOverrides(() async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        base = 'http://127.0.0.1:${server.port}';
        server.listen((request) async {
          expect(request.uri.queryParameters['action'], 'get_series_info');
          expect(request.uri.queryParameters['series_id'], '71');
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'episodes': {
                '1': [
                  {'id': '702', 'episode_num': 2, 'title': 'Second'},
                  {'id': '701', 'episode_num': 1, 'title': 'First'},
                ],
              },
            }),
          );
          await request.response.close();
        });
        try {
          // Warm the real service cache; the view still calls its production
          // provider, and no private state is assigned by the test.
          final info = await XtreamCodesService.instance.fetchSeriesInfo(
            base,
            'fixture-user',
            'fixture-pass',
            '71',
          );
          expect(info!.episodes.length, 2);
          final playlist = IptvPlaylist(
            id: 'episode-provider',
            name: 'Episode TV',
            url: '',
            serverUrl: base,
            username: 'fixture-user',
            password: 'fixture-pass',
            addedAt: DateTime(2026),
          );
          view = await IptvResultsFixture.create();
          await IptvPlaylistStorage.setIptvPlaylists([view.playlist, playlist]);
          IptvCatalogDb.ingest(
            dbPath: IptvCatalogDb.path,
            catalogKey: IptvCatalogKey.forPlaylist(playlist, 'series')!,
            channels: [
              IptvChannel(
                name: 'Contract Show',
                url: 'xtream-series://episode-provider/71',
                group: 'Drama',
                contentType: 'series',
                attributes: const {'series_id': '71'},
              ),
            ],
            categories: const ['Drama'],
          );
        } finally {
          await server.close(force: true);
        }
      }, _LocalHttp()),
    );
    try {
      await view.mount(tester);
      final drillIn = iptvResultsViewTestAccess(view.state).browse({
        'action': 'seriesEpisodes',
        'sourceId': 'episode-provider',
        'channelUrl': 'xtream-series://episode-provider/71',
      });
      Object? payload;
      var completed = false;
      drillIn.then((result) {
        payload = result;
        completed = true;
      });
      await view.until(tester, () => completed);
      await drillIn;
      expectOrderedPayload('series_episodes', payload, server: base);
      completed = false;
      Object? cached;
      final cachedFuture = iptvResultsViewTestAccess(
        view.state,
      ).browse({'contentType': 'episodes', 'query': 'second'});
      cachedFuture.then((result) {
        cached = result;
        completed = true;
      });
      await view.until(tester, () => completed);
      await cachedFuture;
      expectOrderedPayload('cached_episodes', cached, server: base);
    } finally {
      await view.close(tester);
    }
  });
}
