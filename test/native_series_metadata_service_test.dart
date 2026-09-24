import 'dart:convert';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/native_series_metadata_service.dart';
import 'package:debrify/services/tmdb_metadata_repository.dart';
import 'package:debrify/services/stremio_service.dart';
import 'package:debrify/services/next_episode_service.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'saved tracker title restores built-in metadata and canonical progress',
    () async {
      SharedPreferences.setMockInitialValues({});
      final saved = StorageService.withMyWatchlistSource(
        const StremioMeta(
          id: 'tt0118360',
          imdbId: 'tt0118360',
          type: 'series',
          name: 'Johnny Bravo',
        ),
        NativeSeriesMetadataService.addon,
      );
      await StorageService.setMyWatchlistItem(saved, true);
      final restored = (await StorageService.getMyWatchlistItems()).single;
      final addon = NativeSeriesMetadataService.addonForItem(restored);
      expect(addon.id, NativeSeriesMetadataService.addon.id);
      expect(addon.baseUrl, isEmpty);
      final scoped = await StremioService.instance.scopeSeriesProgress(
        restored,
        addon,
      );
      expect(scoped.progressId, 'tt0118360');
    },
  );

  test(
    'TMDB outage falls back to canonical Trakt episodes and advances seasons',
    () async {
      SharedPreferences.setMockInitialValues({});
      final metadata = NativeSeriesMetadataService(
        tmdb: TmdbMetadataRepository(token: ''),
        fallbackSeasons: (id) async {
          expect(id, 'tt0118360');
          return [
            {
              'episodes': [
                {'season': 1, 'number': 3, 'title': 'Finale'},
                {'season': 1, 'number': 3, 'title': 'Duplicate'},
                {'season': 2, 'number': 0},
                {'season': 2, 'number': 1, 'title': 'Premiere', 'rating': 8.2},
                {'season': -1, 'number': 1},
              ],
            },
          ];
        },
      );
      final rows = await metadata.episodesWithFallback('tt0118360');
      expect(rows.last['id'], 'tt0118360:2:1');
      expect(rows.last['rating'], 8.2);
      expect(rows, hasLength(3));
      expect(
        await NextEpisodeService.findNextEpisode(
          'tt0118360',
          1,
          3,
          metadata: metadata,
        ),
        (season: 2, episode: 1),
      );
      expect(
        await NextEpisodeService.findNextEpisode(
          'tt0118360',
          2,
          1,
          metadata: metadata,
        ),
        isNull,
      );
    },
  );

  test(
    'TMDB success does not consult fallback and supplies next episode without addons',
    () async {
      SharedPreferences.setMockInitialValues({});
      final metadata = NativeSeriesMetadataService(
        tmdb: TmdbMetadataRepository(
          token: 'test',
          clientFactory: () => MockClient((request) async {
            final body = switch (request.url.path) {
              '/3/find/tt0118360' => {
                'tv_results': [
                  {'id': 2405},
                ],
              },
              '/3/tv/2405' => {
                'seasons': [
                  {'season_number': 1},
                ],
              },
              '/3/tv/2405/season/1' => {
                'episodes': [
                  {'season_number': 1, 'episode_number': 3},
                  {'season_number': 1, 'episode_number': 4},
                ],
              },
              _ => throw StateError('Unexpected ${request.url}'),
            };
            return http.Response(jsonEncode(body), 200);
          }),
        ),
        fallbackSeasons: (_) async => throw StateError('Fallback must not run'),
      );
      expect(
        await NextEpisodeService.findNextEpisode(
          'tt0118360',
          1,
          3,
          metadata: metadata,
        ),
        (season: 1, episode: 4),
      );
    },
  );

  test(
    'opening a tracker series does not require catalog episode verification',
    () async {
      SharedPreferences.setMockInitialValues({});
      const card = StremioMeta(
        id: 'tt0118360',
        imdbId: 'tt0118360',
        type: 'series',
        name: 'Johnny Bravo',
      );
      final scoped = await StremioService.instance.scopeSeriesProgress(
        card,
        NativeSeriesMetadataService.addonForItem(card),
      );
      expect(scoped, same(card));
      expect(scoped.progressId, 'tt0118360');
    },
  );

  test(
    'tracker cards use built-in metadata and preserve explicit addon owners',
    () {
      const card = StremioMeta(
        id: 'tt0118360',
        imdbId: 'tt0118360',
        type: 'series',
        name: 'Johnny Bravo',
      );
      expect(
        NativeSeriesMetadataService.addonForItem(card),
        same(NativeSeriesMetadataService.addon),
      );
      final owner = StremioAddon(
        id: 'custom',
        name: 'Custom',
        manifestUrl: 'https://example.test/manifest.json',
        baseUrl: 'https://example.test',
      );
      expect(
        NativeSeriesMetadataService.addonForItem(card.withSourceAddon(owner)),
        same(owner),
      );
    },
  );

  test(
    'IMDb tracker guide resolves TMDB while preserving playback IDs',
    () async {
      final requests = <Uri>[];
      final service = NativeSeriesMetadataService(
        tmdb: TmdbMetadataRepository(
          token: 'test',
          clientFactory: () => MockClient((request) async {
            requests.add(request.url);
            final body = switch (request.url.path) {
              '/3/find/tt0118360' => {
                'tv_results': [
                  {'id': 2405},
                ],
              },
              '/3/tv/2405' => {
                'seasons': [
                  {'season_number': 1},
                ],
              },
              '/3/tv/2405/season/1' => {
                'episodes': [
                  {
                    'season_number': 1,
                    'episode_number': 3,
                    'name': 'Episode 3',
                  },
                ],
              },
              _ => throw StateError('Unexpected request ${request.url}'),
            };
            return http.Response(jsonEncode(body), 200);
          }),
        ),
      );
      final videos = await service.episodes('tt0118360');
      expect(videos.single['id'], 'tt0118360:1:3');
      expect(videos.single['title'], 'Episode 3');
      expect(requests.first.queryParameters['external_source'], 'imdb_id');
      expect(requests, hasLength(3));
    },
  );

  test('missing or ambiguous IMDb mappings never guess a TMDB show', () async {
    for (final matches in [
      [],
      [
        {'id': 1},
        {'id': 2},
      ],
    ]) {
      final service = NativeSeriesMetadataService(
        tmdb: TmdbMetadataRepository(
          token: 'test',
          clientFactory: () => MockClient((request) async {
            expect(request.url.path, '/3/find/tt0118360');
            return http.Response(jsonEncode({'tv_results': matches}), 200);
          }),
        ),
      );
      expect(await service.episodes('tt0118360'), isEmpty);
    }
  });

  test(
    'TMDB-native episode guide retains revival numbering and specials',
    () async {
      final requests = <String>[];
      final service = NativeSeriesMetadataService(
        tmdb: TmdbMetadataRepository(
          token: 'test',
          clientFactory: () => MockClient((request) async {
            requests.add(request.url.path);
            Object body;
            switch (request.url.path) {
              case '/3/tv/237243':
                body = {
                  'seasons': [
                    {'season_number': 4},
                    {'season_number': 0},
                    {'season_number': 4},
                  ],
                };
              case '/3/tv/237243/season/4':
                body = {
                  'episodes': [
                    {
                      'season_number': 4,
                      'episode_number': 6,
                      'name': 'Day 5 - Live Eviction',
                      'air_date': '2026-09-18',
                      'still_path': '/still.jpg',
                    },
                    {'season_number': 99, 'episode_number': 2},
                  ],
                };
              case '/3/tv/237243/season/0':
                body = {
                  'episodes': [
                    {
                      'season_number': 0,
                      'episode_number': 1,
                      'name': 'Special',
                    },
                  ],
                };
              default:
                throw StateError('Unexpected ${request.url}');
            }
            return http.Response(jsonEncode(body), 200);
          }),
        ),
      );
      final videos = await service.episodes('tmdb:237243');
      expect(videos.map((v) => v['id']), [
        'tmdb:237243:0:1',
        'tmdb:237243:4:6',
      ]);
      expect(videos.last['title'], 'Day 5 - Live Eviction');
      expect(videos.last['released'], '2026-09-18');
      expect(requests.toSet(), {
        '/3/tv/237243',
        '/3/tv/237243/season/0',
        '/3/tv/237243/season/4',
      });
      await service.episodes('tmdb:237243');
      expect(requests, hasLength(3));
    },
  );

  test('Simkl-only TV IDs use the exact show episode endpoint', () async {
    await http.runWithClient(
      () async {
        final rows = await NativeSeriesMetadataService().episodes(
          'simkl:2274121',
        );
        expect(rows.single['id'], 'simkl:2274121:4:6');
        expect(rows.single['season'], 4);
        expect(rows.single['episode'], 6);
      },
      () => MockClient((request) async {
        expect(request.url.path, '/tv/episodes/2274121');
        expect(request.url.queryParameters['extended'], 'full');
        return http.Response(
          jsonEncode([
            {
              'season': 4,
              'episode': 6,
              'title': 'Eviction',
              'date': '2026-09-18',
            },
            {'season': -1, 'episode': 2},
          ]),
          200,
        );
      }),
    );
  });

  test('a failed season does not publish an incomplete guide', () async {
    final service = NativeSeriesMetadataService(
      tmdb: TmdbMetadataRepository(
        token: 'test',
        clientFactory: () => MockClient(
          (request) async => request.url.path == '/3/tv/1'
              ? http.Response('{"seasons":[{"season_number":1}]}', 200)
              : http.Response('{}', 503),
        ),
      ),
    );
    await expectLater(
      service.episodes('tmdb:1'),
      throwsA(isA<TmdbMetadataException>()),
    );
  });
}
