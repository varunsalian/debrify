import 'dart:convert';
import 'package:debrify/features/sources/data/stremio_source_seasons_repository.dart';
import 'package:debrify/features/sources/models/sources_session.dart';
import 'package:debrify/models/advanced_search_selection.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:debrify/services/storage_service.dart';

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
      'Sources repository records inventory using ${originHasMeta ? 'origin catalog ID' : 'fallback IMDb ID'} for its guide',
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
            final repository = StremioSourceSeasonsRepository(
              SourcesSession(
                owner: ProfileSessionMemory.captureOwner(),
                viewIdentity: Object(),
                selection: const AdvancedSearchSelection(
                  imdbId: 'tt0118360',
                  title: 'Show',
                  isSeries: true,
                ),
                catalogItem: item,
              ),
            );
            final loaded = await repository.load();
            expect(loaded!.seasons, [1, 2, 3]);
            await loaded.record();
            final prefs = await SharedPreferences.getInstance();
            final state = jsonDecode(
              prefs.getString(StorageService.localSeriesCompletionStateKey)!,
            );
            expect(state['tt0118360']['title'], 'Show');
            expect(
              state['tt0118360']['episodes'].keys,
              unorderedEquals(['1-1', '2-1', '3-1']),
            );
            await prefs.remove(StorageService.localSeriesCompletionStateKey);
            ProfileSessionMemory.clearAll();
            await loaded.record();
            expect(
              prefs.getString(StorageService.localSeriesCompletionStateKey),
              isNull,
            );
            expect(await repository.load(), isNull);
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
                        'released': '2025-01-01T00:00:00Z',
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
