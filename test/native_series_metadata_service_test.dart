import 'dart:convert';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/native_series_metadata_service.dart';
import 'package:debrify/services/tmdb_metadata_repository.dart';
import 'package:debrify/services/stremio_service.dart';
import 'package:debrify/services/next_episode_service.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/services/torrent_playback_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'catalog navigation keeps the exact origin despite addon order and duplicate IDs',
    () async {
      final wrong = StremioAddon(
        id: 'shared',
        name: 'Wrong configuration',
        baseUrl: 'https://wrong.invalid',
        manifestUrl: 'https://wrong.invalid/manifest.json',
        resources: ['meta'],
        types: ['series'],
      );
      final origin = StremioAddon(
        id: 'shared',
        name: 'Origin configuration',
        baseUrl: 'https://origin.invalid',
        manifestUrl: 'https://origin.invalid/manifest.json',
        resources: ['meta'],
        types: ['series'],
      );
      final movies = StremioAddon(
        id: 'movies',
        name: 'Movies',
        baseUrl: 'https://movies.invalid',
        manifestUrl: 'https://movies.invalid/manifest.json',
        resources: ['meta'],
        types: ['movie'],
      );
      final item = const StremioMeta(
        id: 'tmdb:2405',
        imdbId: 'tt0118360',
        name: 'Test show',
        type: 'series',
      ).withSourceAddon(origin);
      for (final order in [
        [movies, wrong, origin],
        [origin, movies, wrong],
      ]) {
        SharedPreferences.setMockInitialValues({
          'stremio_addons_v1': jsonEncode(
            order.map((addon) => addon.toJson()).toList(),
          ),
        });
        StremioService.instance.invalidateCache();
        final requests = <Uri>[];
        await http.runWithClient(
          () async {
            expect(
              await NextEpisodeService.findNextEpisode(
                'tt0118360',
                1,
                2,
                catalogItem: item,
              ),
              (season: 1, episode: 4),
            );
            final fetcher = TorrentPlaybackService.seriesFetcherFor(
              meta: PlaybackMeta.catalog(
                imdbId: 'tt0118360',
                contentType: 'series',
                season: 1,
                episode: 2,
                addonId: origin.id,
                catalogItem: item,
              ),
            )!;
            expect(await fetcher.resolveAdjacentEpisode!(1, 2, 1), (
              season: 1,
              episode: 4,
            ));
            expect(await fetcher.resolveAdjacentEpisode!(1, 2, -1), (
              season: 1,
              episode: 1,
            ));
            // An unqualified duplicate addon ID must not pick either configuration.
            expect(
              await NextEpisodeService.findNextEpisode(
                'tt0118360',
                1,
                2,
                originAddonId: origin.id,
              ),
              isNull,
            );
          },
          () => MockClient((request) async {
            requests.add(request.url);
            expect(request.url.host, 'origin.invalid');
            expect(
              Uri.decodeComponent(request.url.path),
              endsWith('/series/tmdb:2405.json'),
            );
            return http.Response(
              jsonEncode({
                'meta': {
                  'videos': [
                    for (final e in [1, 2, 4])
                      {'id': 'tt0118360:1:$e', 'season': 1, 'episode': e},
                  ],
                },
              }),
              200,
            );
          }),
        );
        expect(requests, hasLength(1));
      }
      StremioService.instance.invalidateCache();
    },
  );

  for (final boundary in [false, true]) {
    test(
      'built-in Previous loads only relevant seasons (boundary=$boundary)',
      () async {
        final paths = <String>[];
        final metadata = NativeSeriesMetadataService(
          tmdb: TmdbMetadataRepository(
            token: 'test',
            clientFactory: () => MockClient((request) async {
              paths.add(request.url.path);
              final body = switch (request.url.path) {
                '/3/find/tt0118360' => {
                  'tv_results': [
                    {'id': 2405},
                  ],
                },
                '/3/tv/2405/season/20' => {
                  'episodes': [
                    {'season_number': 20, 'episode_number': 1},
                    {'season_number': 20, 'episode_number': 3},
                  ],
                },
                '/3/tv/2405' => {
                  'seasons': [
                    for (var s = 0; s <= 40; s++) {'season_number': s},
                  ],
                },
                '/3/tv/2405/season/19' => {
                  'episodes': [
                    {'season_number': 19, 'episode_number': 1},
                    {'season_number': 19, 'episode_number': 6},
                  ],
                },
                _ => throw StateError('Unrelated season ${request.url}'),
              };
              return http.Response(jsonEncode(body), 200);
            }),
          ),
          fallbackSeasons: (_) async => throw StateError('Unexpected fallback'),
        );
        expect(
          await NextEpisodeService.findAdjacentEpisode(
            'tt0118360',
            20,
            boundary ? 1 : 3,
            direction: -1,
            metadata: metadata,
            preferBuiltIn: true,
          ),
          boundary ? (season: 19, episode: 6) : (season: 20, episode: 1),
        );
        expect(paths, [
          '/3/find/tt0118360',
          '/3/tv/2405/season/20',
          if (boundary) ...['/3/tv/2405', '/3/tv/2405/season/19'],
        ]);
      },
    );
  }

  test(
    'built-in next from specials still advances to the first regular season',
    () async {
      final metadata = NativeSeriesMetadataService(
        tmdb: TmdbMetadataRepository(
          token: 'test',
          clientFactory: () => MockClient((request) async {
            final body = switch (request.url.path) {
              '/3/tv/2405/season/0' => {
                'episodes': [
                  {'season_number': 0, 'episode_number': 1},
                  {'season_number': 0, 'episode_number': 2},
                ],
              },
              '/3/tv/2405' => {
                'seasons': [
                  {'season_number': 0},
                  {'season_number': 1},
                ],
              },
              '/3/tv/2405/season/1' => {
                'episodes': [
                  {'season_number': 1, 'episode_number': 1},
                ],
              },
              _ => throw StateError('Unexpected ${request.url}'),
            };
            return http.Response(jsonEncode(body), 200);
          }),
        ),
      );
      expect(
        await NextEpisodeService.findNextEpisode(
          'tmdb:2405',
          0,
          1,
          metadata: metadata,
        ),
        (season: 1, episode: 1),
      );
    },
  );

  test(
    'ordinary catalog next uses its working addon without TMDB or Trakt',
    () async {
      final addon = StremioAddon(
        id: 'working-guide',
        name: 'Working guide',
        baseUrl: 'https://guide.invalid',
        manifestUrl: 'https://guide.invalid/manifest.json',
        resources: ['meta'],
        types: ['series'],
      );
      SharedPreferences.setMockInitialValues({
        'stremio_addons_v1': jsonEncode([addon.toJson()]),
      });
      StremioService.instance.invalidateCache();
      addTearDown(StremioService.instance.invalidateCache);
      final requests = <Uri>[];
      await http.runWithClient(
        () async {
          expect(
            await NextEpisodeService.findNextEpisode(
              'tt0118360',
              2,
              3,
              originAddonId: addon.id,
            ),
            (season: 2, episode: 4),
          );
          expect(
            await NextEpisodeService.findNextEpisode(
              'tt0118360',
              2,
              3,
              originAddonId: addon.id,
            ),
            (season: 2, episode: 4),
          );
        },
        () => MockClient((request) async {
          requests.add(request.url);
          expect(request.url.host, 'guide.invalid');
          return http.Response(
            jsonEncode({
              'meta': {
                'videos': [
                  {'id': 'tt0118360:2:3', 'season': 2, 'episode': 3},
                  {'id': 'tt0118360:2:4', 'season': 2, 'episode': 4},
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

  for (final boundary in [false, true]) {
    test(
      'built-in next only requests relevant seasons (boundary=$boundary)',
      () async {
        final paths = <String>[];
        final metadata = NativeSeriesMetadataService(
          tmdb: TmdbMetadataRepository(
            token: 'test',
            clientFactory: () => MockClient((request) async {
              final path = request.url.path;
              paths.add(path);
              final Object body;
              switch (path) {
                case '/3/find/tt0118360':
                  body = {
                    'tv_results': [
                      {'id': 2405},
                    ],
                  };
                case '/3/tv/2405/season/20':
                  body = {
                    'episodes': [
                      {'season_number': 20, 'episode_number': 3},
                      if (!boundary) {'season_number': 20, 'episode_number': 4},
                    ],
                  };
                case '/3/tv/2405':
                  expect(boundary, isTrue);
                  body = {
                    'seasons': [
                      for (var s = 0; s <= 40; s++) {'season_number': s},
                    ],
                  };
                case '/3/tv/2405/season/21':
                  expect(boundary, isTrue);
                  body = {
                    'episodes': [
                      {'season_number': 21, 'episode_number': 1},
                    ],
                  };
                default:
                  fail('Unrelated season requested: $path');
              }
              return http.Response(jsonEncode(body), 200);
            }),
          ),
          fallbackSeasons: (_) async => throw StateError('Unexpected fallback'),
        );
        expect(
          await NextEpisodeService.findNextEpisode(
            'tt0118360',
            20,
            3,
            preferBuiltIn: true,
            metadata: metadata,
          ),
          boundary ? (season: 21, episode: 1) : (season: 20, episode: 4),
        );
        expect(paths, [
          '/3/find/tt0118360',
          '/3/tv/2405/season/20',
          if (boundary) ...['/3/tv/2405', '/3/tv/2405/season/21'],
        ]);
      },
    );
  }

  test(
    'next episode stops at an upcoming release without skipping ahead',
    () async {
      final metadata = NativeSeriesMetadataService(
        tmdb: TmdbMetadataRepository(token: ''),
        fallbackSeasons: (_) async => [
          {
            'episodes': [
              {'season': 1, 'number': 1, 'first_aired': '2000-01-01'},
              {'season': 1, 'number': 2, 'first_aired': '2999-01-01'},
              {'season': 1, 'number': 3, 'first_aired': '2000-01-02'},
            ],
          },
        ],
      );
      expect(
        await NextEpisodeService.findNextEpisode(
          'tt0118360',
          1,
          1,
          metadata: metadata,
        ),
        isNull,
      );
    },
  );

  test('next episode permits aired and undated episodes', () async {
    for (final release in ['2000-01-01', null, 'unknown']) {
      final metadata = NativeSeriesMetadataService(
        tmdb: TmdbMetadataRepository(token: ''),
        fallbackSeasons: (_) async => [
          {
            'episodes': [
              {'season': 1, 'number': 1},
              {'season': 1, 'number': 2, 'first_aired': release},
            ],
          },
        ],
      );
      expect(
        await NextEpisodeService.findNextEpisode(
          'tt0118360',
          1,
          1,
          metadata: metadata,
        ),
        (season: 1, episode: 2),
      );
    }
  });

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
