import 'dart:convert';

import 'package:debrify/services/stremio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('Stremio addon JSON import', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      StremioService.instance.invalidateCache();
    });

    test('imports Debrify Stremio importer export payloads', () async {
      final payload = jsonEncode({
        'source': 'stremio',
        'exportedAt': '2026-04-26T16:05:37.444Z',
        'addons': [
          {
            'manifest': {
              'id': 'org.example.streams',
              'name': 'Example Streams',
              'version': '1.0.0',
              'resources': ['stream'],
              'types': ['movie', 'series'],
            },
            'transportUrl': 'https://example.com/config/manifest.json',
            'flags': {},
          },
          {
            'manifest': {
              'id': 'org.example.catalog',
              'name': 'Example Catalog',
              'resources': ['catalog', 'meta'],
              'types': ['movie'],
              'catalogs': [
                {'id': 'popular', 'type': 'movie', 'name': 'Popular'},
              ],
            },
            'transportUrl': 'stremio://catalog.example.com/manifest.json',
            'flags': {},
          },
        ],
      });

      final result = await StremioService.instance.importAddonsFromJson(
        payload,
      );
      final addons = await StremioService.instance.getAddons();

      expect(result.discovered, 2);
      expect(result.imported, 2);
      expect(result.failed, 0);
      expect(addons.map((addon) => addon.name), contains('Example Streams'));
      expect(addons.map((addon) => addon.name), contains('Example Catalog'));
      expect(
        addons.map((addon) => addon.manifestUrl),
        contains('https://catalog.example.com/manifest.json'),
      );
    });

    test('skips duplicate transport URLs on repeated import', () async {
      final payload = jsonEncode({
        'addons': [
          {
            'manifest': {
              'id': 'org.example.streams',
              'name': 'Example Streams',
              'resources': ['stream'],
              'types': ['movie'],
            },
            'transportUrl': 'https://example.com/manifest.json',
          },
        ],
      });

      await StremioService.instance.importAddonsFromJson(payload);
      final secondResult = await StremioService.instance.importAddonsFromJson(
        payload,
      );
      final addons = await StremioService.instance.getAddons();

      expect(secondResult.imported, 0);
      expect(secondResult.skippedDuplicates, 1);
      expect(addons, hasLength(1));
    });

    test(
      'skips duplicate base URL when manifest URL was already added',
      () async {
        final manualStylePayload = jsonEncode({
          'addons': [
            {
              'manifest': {
                'id': 'org.example.streams',
                'name': 'Example Streams',
                'resources': ['stream'],
                'types': ['movie'],
              },
              'transportUrl': 'https://example.com/addon/manifest.json',
            },
          ],
        });
        final exportStylePayload = jsonEncode({
          'addons': [
            {
              'manifest': {
                'id': 'org.example.streams',
                'name': 'Example Streams',
                'resources': ['stream'],
                'types': ['movie'],
              },
              'transportUrl': 'https://example.com/addon',
            },
          ],
        });

        await StremioService.instance.importAddonsFromJson(manualStylePayload);
        final secondResult = await StremioService.instance.importAddonsFromJson(
          exportStylePayload,
        );
        final addons = await StremioService.instance.getAddons();

        expect(secondResult.imported, 0);
        expect(secondResult.skippedDuplicates, 1);
        expect(addons, hasLength(1));
        expect(
          addons.single.manifestUrl,
          'https://example.com/addon/manifest.json',
        );
      },
    );

    test(
      'skips duplicate trailing-slash base URL when manifest URL was already added',
      () async {
        final manualStylePayload = jsonEncode({
          'addons': [
            {
              'manifest': {
                'id': 'org.example.streams',
                'name': 'Example Streams',
                'resources': ['stream'],
                'types': ['movie'],
              },
              'transportUrl': 'https://example.com/addon/manifest.json',
            },
          ],
        });
        final exportStylePayload = jsonEncode({
          'addons': [
            {
              'manifest': {
                'id': 'org.example.streams',
                'name': 'Example Streams',
                'resources': ['stream'],
                'types': ['movie'],
              },
              'transportUrl': 'https://example.com/addon/',
            },
          ],
        });

        await StremioService.instance.importAddonsFromJson(manualStylePayload);
        final secondResult = await StremioService.instance.importAddonsFromJson(
          exportStylePayload,
        );
        final addons = await StremioService.instance.getAddons();

        expect(secondResult.imported, 0);
        expect(secondResult.skippedDuplicates, 1);
        expect(addons, hasLength(1));
        expect(
          addons.single.manifestUrl,
          'https://example.com/addon/manifest.json',
        );
      },
    );

    test(
      'preserves imported transport URLs that are not manifest URLs',
      () async {
        final payload = jsonEncode({
          'addons': [
            {
              'manifest': {
                'id': 'org.stremio.opensubtitles',
                'name': 'OpenSubtitles',
                'resources': ['subtitles'],
                'types': ['movie', 'series'],
              },
              'transportUrl': 'https://opensubtitles.strem.io/stremio/v1',
            },
          ],
        });

        final result = await StremioService.instance.importAddonsFromJson(
          payload,
        );
        final addons = await StremioService.instance.getAddons();

        expect(result.imported, 1);
        expect(
          addons.single.manifestUrl,
          'https://opensubtitles.strem.io/stremio/v1',
        );
        expect(
          addons.single.baseUrl,
          'https://opensubtitles.strem.io/stremio/v1',
        );
      },
    );

    test('trims trailing slash from imported addon base URLs', () async {
      final payload = jsonEncode({
        'addons': [
          {
            'manifest': {
              'id': 'org.example.streams',
              'name': 'Example Streams',
              'resources': ['stream'],
              'types': ['movie'],
            },
            'transportUrl': 'https://example.com/addon/',
          },
        ],
      });

      final result = await StremioService.instance.importAddonsFromJson(
        payload,
      );
      final addons = await StremioService.instance.getAddons();

      expect(result.imported, 1);
      expect(addons.single.manifestUrl, 'https://example.com/addon');
      expect(addons.single.baseUrl, 'https://example.com/addon');
    });

    test('skips local Stremio desktop-only addon URLs', () async {
      final payload = jsonEncode({
        'addons': [
          {
            'manifest': {
              'id': 'org.stremio.local',
              'name': 'Local Files',
              'resources': ['meta', 'stream'],
              'types': ['movie', 'series', 'other'],
            },
            'transportUrl': 'http://127.0.0.1:11470/manifest.json',
          },
        ],
      });

      final result = await StremioService.instance.importAddonsFromJson(
        payload,
      );
      final addons = await StremioService.instance.getAddons();

      expect(result.discovered, 1);
      expect(result.imported, 0);
      expect(result.skippedUnsupported, 1);
      expect(addons, isEmpty);
    });
  });
}
