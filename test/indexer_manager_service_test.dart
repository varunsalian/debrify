import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:debrify/models/indexer_manager_config.dart';
import 'package:debrify/services/indexer_manager_service.dart';

void main() {
  group('IndexerManagerService', () {
    test('parses Jackett Torznab results', () async {
      final server = await _TestServer.start((request) async {
        expect(
          request.uri.path,
          contains('/api/v2.0/indexers/all/results/torznab/api'),
        );
        expect(request.uri.queryParameters['apikey'], 'jackett-key');
        expect(request.uri.queryParameters['t'], 'search');
        expect(request.uri.queryParameters['q'], 'Big Buck Bunny');

        request.response
          ..headers.contentType = ContentType('text', 'xml')
          ..write('''
<rss xmlns:torznab="http://torznab.com/schemas/2015/feed">
  <channel>
    <item>
      <title>Big Buck Bunny 1080p</title>
      <link>magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567&amp;dn=Big+Buck+Bunny</link>
      <pubDate>Thu, 30 Apr 2026 12:00:00 GMT</pubDate>
      <size>123456</size>
      <torznab:attr name="seeders" value="42" />
      <torznab:attr name="peers" value="50" />
    </item>
  </channel>
</rss>
''');
        await request.response.close();
      });

      addTearDown(server.close);

      final results = await IndexerManagerService.searchKeyword(
        IndexerManagerConfig(
          id: 'test',
          name: 'Local Jackett',
          type: IndexerManagerType.jackett,
          baseUrl: server.baseUrl,
          apiKey: 'jackett-key',
        ),
        'Big Buck Bunny',
      );

      expect(results, hasLength(1));
      expect(results.single.name, 'Big Buck Bunny 1080p');
      expect(
        results.single.infohash,
        '0123456789abcdef0123456789abcdef01234567',
      );
      expect(results.single.seeders, 42);
      expect(results.single.leechers, 8);
      expect(results.single.magnetUrl, startsWith('magnet:'));
      expect(results.single.source, 'local jackett');
    });

    test('parses Prowlarr search results', () async {
      final server = await _TestServer.start((request) async {
        expect(request.uri.path, '/api/v1/search');
        expect(request.headers.value('X-Api-Key'), 'prowlarr-key');
        expect(request.uri.queryParameters['query'], 'Big Buck Bunny');
        expect(request.uri.queryParameters['type'], 'search');

        request.response
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode([
              {
                'title': 'Big Buck Bunny 720p',
                'infoHash': 'abcdefabcdefabcdefabcdefabcdefabcdefabcd',
                'protocol': 'torrent',
                'magnetUrl':
                    'magnet:?xt=urn:btih:abcdefabcdefabcdefabcdefabcdefabcdefabcd',
                'size': 654321,
                'seeders': 12,
                'leechers': 3,
                'indexer': 'Private Indexer',
                'publishDate': '2026-04-30T12:00:00Z',
              },
            ]),
          );
        await request.response.close();
      });

      addTearDown(server.close);

      final results = await IndexerManagerService.searchKeyword(
        IndexerManagerConfig(
          id: 'test',
          name: 'Local Prowlarr',
          type: IndexerManagerType.prowlarr,
          baseUrl: server.baseUrl,
          apiKey: 'prowlarr-key',
        ),
        'Big Buck Bunny',
      );

      expect(results, hasLength(1));
      expect(results.single.name, 'Big Buck Bunny 720p');
      expect(
        results.single.infohash,
        'abcdefabcdefabcdefabcdefabcdefabcdefabcd',
      );
      expect(results.single.category, 'Private Indexer');
      expect(results.single.magnetUrl, startsWith('magnet:'));
      expect(results.single.hasRealInfoHash, isTrue);
      expect(results.single.source, 'local prowlarr');
    });

    test('uses only Prowlarr downloadUrl for torrent file URLs', () async {
      final server = await _TestServer.start((request) async {
        final fakeApiKey = 'abcdefabcdefabcdefabcdefabcdefabcdefabcd';
        request.response
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode([
              {
                'title': 'Details page only',
                'guid': '${serverBaseUrl(request)}/details/123',
                'infoUrl': '${serverBaseUrl(request)}/info/123',
                'seeders': 10,
              },
              {
                'title': 'Downloadable release',
                'protocol': 'torrent',
                'downloadUrl':
                    '${serverBaseUrl(request)}/download/456?apikey=$fakeApiKey',
                'guid': '${serverBaseUrl(request)}/details/456',
                'size': 1000,
                'seeders': 20,
              },
            ]),
          );
        await request.response.close();
      });

      addTearDown(server.close);

      final results = await IndexerManagerService.searchKeyword(
        IndexerManagerConfig(
          id: 'test',
          name: 'Local Prowlarr',
          type: IndexerManagerType.prowlarr,
          baseUrl: server.baseUrl,
          apiKey: 'prowlarr-key',
        ),
        'Big Buck Bunny',
      );

      expect(results, hasLength(1));
      expect(results.single.name, 'Downloadable release');
      expect(
        results.single.torrentUrl,
        '${server.baseUrl}/download/456?apikey=abcdefabcdefabcdefabcdefabcdefabcdefabcd',
      );
      expect(results.single.torrentUrl, isNot(contains('/details/')));
      expect(results.single.hasRealInfoHash, isFalse);
    });

    test('skips non-torrent Prowlarr results', () async {
      final server = await _TestServer.start((request) async {
        request.response
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode([
              {
                'title': 'Usenet release',
                'protocol': 'usenet',
                'downloadUrl': '${serverBaseUrl(request)}/download/usenet.nzb',
                'seeders': 50,
              },
              {
                'title': 'Torrent release',
                'protocol': 'torrent',
                'downloadUrl': '${serverBaseUrl(request)}/download/torrent',
                'seeders': 10,
              },
            ]),
          );
        await request.response.close();
      });

      addTearDown(server.close);

      final results = await IndexerManagerService.searchKeyword(
        IndexerManagerConfig(
          id: 'test',
          name: 'Local Prowlarr',
          type: IndexerManagerType.prowlarr,
          baseUrl: server.baseUrl,
          apiKey: 'prowlarr-key',
        ),
        'Big Buck Bunny',
      );

      expect(results, hasLength(1));
      expect(results.single.name, 'Torrent release');
    });
  });
}

String serverBaseUrl(HttpRequest request) =>
    'http://${request.requestedUri.host}:${request.requestedUri.port}';

class _TestServer {
  final HttpServer _server;

  _TestServer(this._server);

  String get baseUrl => 'http://${_server.address.host}:${_server.port}';

  static Future<_TestServer> start(
    Future<void> Function(HttpRequest request) handler,
  ) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen(handler);
    return _TestServer(server);
  }

  Future<void> close() async {
    await _server.close(force: true);
  }
}
