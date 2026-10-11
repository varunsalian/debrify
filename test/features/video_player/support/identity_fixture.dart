import 'dart:convert';

import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/stremio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'video_player_environment.dart';

Future<void> installIdentityCatalog(
  WidgetTester tester,
  VideoPlayerEnvironment fixture,
) async {
  final service = StremioService.instance;
  service.invalidateCache();
  service.debugManifestFetcher = (url) async => StremioAddon.fromManifest({
    'id': 'fixture.identity',
    'name': 'Fixture search',
    'version': '1.0.0',
    'resources': ['catalog'],
    'types': ['series', 'movie'],
    'catalogs': [
      {
        'id': 'search',
        'type': 'series',
        'name': 'Fixture catalog',
        'extraSupported': ['search'],
      },
    ],
  }, url);
  await tester.runAsync(
    () => service.addAddon('https://identity.test/manifest.json'),
  );
  service.debugManifestFetcher = null;
  fixture.network.handler = (request) => http.Response(
    jsonEncode({
      'metas': [
        {
          'id': 'sparse',
          'imdb_id': 'tt900001',
          'type': 'series',
          'name': 'Sparse duplicate',
        },
        {
          'id': 'best',
          'imdb_id': 'tt900001',
          'type': 'SERIES',
          'name': 'Fixture Series',
          'releaseInfo': '2024',
          'poster': '//player.test/poster.png',
        },
        {
          'id': 'unsupported',
          'type': 'tv',
          'imdb_id': 'tt900002',
          'name': 'Unsupported TV',
        },
        {'id': 'unidentified', 'type': 'series', 'name': 'No IMDb'},
        {
          'id': 'tt0900003',
          'type': 'movie',
          'name': 'Fixture Film',
          'releaseInfo': '2020',
        },
      ],
    }),
    200,
    headers: {'content-type': 'application/json'},
  );
}
