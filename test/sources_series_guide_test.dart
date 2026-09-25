import 'dart:convert';

import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/stremio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final originHasMeta in [false, true]) {
    test(
      'Sources uses ${originHasMeta ? 'origin catalog ID' : 'fallback IMDb ID'} for its guide',
      () async {
        final origin = StremioAddon(
          id: 'catalog',
          name: 'Catalog',
          baseUrl: 'https://catalog.invalid',
          manifestUrl: 'https://catalog.invalid/manifest.json',
          resources: ['catalog', if (originHasMeta) 'meta'],
          types: ['series'],
        );
        final movieMeta = StremioAddon(
          id: 'movie-meta',
          name: 'Movie metadata',
          baseUrl: 'https://movies.invalid',
          manifestUrl: 'https://movies.invalid/manifest.json',
          resources: ['meta'],
          types: ['movie'],
        );
        final guide = StremioAddon(
          id: 'guide',
          name: 'Guide',
          baseUrl: 'https://guide.invalid',
          manifestUrl: 'https://guide.invalid/manifest.json',
          resources: ['meta'],
          types: ['series'],
          idPrefixes: ['tt'],
        );
        SharedPreferences.setMockInitialValues({
          'stremio_addons_v1': jsonEncode(
            [movieMeta, guide, origin].map((a) => a.toJson()).toList(),
          ),
        });
        final service = StremioService.instance..invalidateCache();
        addTearDown(service.invalidateCache);
        final item = const StremioMeta(
          id: 'private-show-id',
          imdbId: 'tt0118360',
          type: 'series',
          name: 'Show',
        ).withSourceAddon(origin);
        final requests = <Uri>[];
        await http.runWithClient(
          () async {
            final rows = await service.fetchSourcesSeriesGuide(
              imdbId: 'tt0118360',
              catalogItem: item,
            );
            expect(rows!.map((r) => r['season']).toSet(), {1, 2, 3});
          },
          () => MockClient((request) async {
            requests.add(request.url);
            expect(
              request.url.host,
              originHasMeta ? 'catalog.invalid' : 'guide.invalid',
            );
            expect(
              Uri.decodeComponent(request.url.path),
              '/meta/series/${originHasMeta ? 'private-show-id' : 'tt0118360'}.json',
            );
            return http.Response(
              jsonEncode({
                'meta': {
                  'videos': [
                    for (final season in [1, 2, 3])
                      {
                        'id': 'tt0118360:$season:1',
                        'season': season,
                        'episode': 1,
                      },
                  ],
                },
              }),
              200,
            );
          }),
        );
        expect(requests, hasLength(1));
      },
    );
  }
}
