import 'dart:convert';

import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/secret_vault.dart';
import 'package:debrify/services/simkl/simkl_anime.dart';
import 'package:debrify/services/simkl/simkl_calendar_service.dart';
import 'package:debrify/services/simkl/simkl_continue_watching_service.dart';
import 'package:debrify/services/simkl/simkl_completed_titles.dart';
import 'package:debrify/services/simkl/simkl_episode_codes.dart';
import 'package:debrify/services/simkl/simkl_service.dart';
import 'package:debrify/services/storage/simkl_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Trimmed from the live `GET /anime/episodes/931899` (Attack on Titan Season
/// 3 Part 2, 2026-11-21): its episode 1 is TVDB S3E13. The special shares
/// episode number 1 and must not overwrite it.
const _aotS3p2Episodes = [
  {
    'episode': 1,
    'type': 'episode',
    'tvdb': {'season': 3, 'episode': 13},
  },
  {
    'episode': 2,
    'type': 'episode',
    'tvdb': {'season': 3, 'episode': 14},
  },
  {
    'episode': 5,
    'type': 'episode',
    'tvdb': {'season': 3, 'episode': 17},
  },
  {'episode': 1, 'type': 'special', 'season': 0},
];

const _aotIds = {'simkl': 931899, 'imdb': 'tt2560140', 'tvdb': '267440'};

/// How the account's lists name an anime: Simkl and TMDB ids only (Simkl's
/// anime guide). The IMDb id comes from the public `GET /anime/{id}`.
const _aotListIds = {'simkl': 931899, 'tmdb': '1429'};
const _aotCatalogIds = {
  'simkl': 931899,
  'slug': 'shingeki-no-kyojin-season-3-part-2',
  'mal': '38524',
  'imdb': 'tt2560140',
  'tmdb': '1429',
  'tvdb': '267440',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final simkl = SimklService.instance;

  setUp(() async {
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    SharedPreferences.setMockInitialValues({});
    SecretVault.debugReset(deviceIdOverride: 'simkl-anime');
    simkl.resetProfileScope();
    SimklAnimeEpisodes.debugReset();
    await SimklStorage.setSimklAccessToken('synthetic-test-token');
  });

  tearDown(() {
    simkl.resetProfileScope();
    SimklAnimeEpisodes.debugReset();
    SecretVault.debugReset();
    ProfileRuntime.debugReset();
  });

  /// Serves the catalog episode list and the given account responses.
  MockClient client(
    Map<String, Object> account, {
    List<String>? requests,
    bool catalogFails = false,
    bool idsFail = false,
  }) => MockClient((request) async {
    requests?.add(request.url.path);
    if (request.url.path == '/anime/931899') {
      if (idsFail) return http.Response('{}', 503);
      return http.Response(
        jsonEncode({'title': 'AoT S3P2', 'ids': _aotCatalogIds}),
        200,
      );
    }
    if (request.url.path == '/anime/episodes/931899') {
      if (catalogFails) return http.Response('{}', 503);
      return http.Response(jsonEncode(_aotS3p2Episodes), 200);
    }
    if (request.url.path == '/anime/episodes/439744') {
      return http.Response(
        jsonEncode([
          {
            'episode': 10,
            'type': 'episode',
            'tvdb': {'season': 2, 'episode': 10},
          },
        ]),
        200,
      );
    }
    final body = account[request.url.path];
    return body == null
        ? http.Response('{}', 404)
        : http.Response(jsonEncode(body), 200);
  });

  group('episode mapping', () {
    test('maps the cour\'s numbering to TVDB seasons, ignoring specials', () {
      final map = SimklAnimeEpisodes.parseEpisodeMap(_aotS3p2Episodes);
      expect(map[1], (season: 3, episode: 13));
      expect(map[5], (season: 3, episode: 17));
      expect(map, hasLength(3));
    });

    test('reads only anime-style next episode codes', () {
      expect(SimklEpisodeCodes.absolute('E05'), 5);
      expect(SimklEpisodeCodes.absolute(' e148 '), 148);
      expect(SimklEpisodeCodes.absolute('S01E05'), isNull);
      expect(SimklEpisodeCodes.absolute('E0'), isNull);
      expect(SimklEpisodeCodes.absolute(null), isNull);
    });

    test(
      'a title\'s catalog is read once; a failure is not hammered',
      () async {
        final requests = <String>[];
        await http.runWithClient(() async {
          expect(await SimklAnimeEpisodes.tvdbCoordinate(931899, 5), (
            season: 3,
            episode: 17,
          ));
          expect(await SimklAnimeEpisodes.tvdbCoordinate(931899, 1), (
            season: 3,
            episode: 13,
          ));
        }, () => client({}, requests: requests));
        expect(requests, hasLength(1), reason: 'the map is cached');
        SimklAnimeEpisodes.debugReset();
        requests.clear();
        await http.runWithClient(() async {
          expect(await SimklAnimeEpisodes.tvdbCoordinate(931899, 5), isNull);
          expect(await SimklAnimeEpisodes.tvdbCoordinate(931899, 1), isNull);
        }, () => client({}, requests: requests, catalogFails: true));
        expect(
          requests,
          hasLength(1),
          reason: 'a failed read waits before retrying',
        );
      },
    );
  });

  test('a failed refresh keeps the previous episode map', () async {
    final requests = <String>[];
    await http.runWithClient(() async {
      await SimklAnimeEpisodes.tvdbCoordinate(931899, 5);
    }, () => client({}, requests: requests));
    SimklAnimeEpisodes.debugAgeMaps(const Duration(hours: 7));
    await http.runWithClient(() async {
      expect(await SimklAnimeEpisodes.tvdbCoordinate(931899, 5), (
        season: 3,
        episode: 17,
      ));
      expect(await SimklAnimeEpisodes.tvdbCoordinate(931899, 1), (
        season: 3,
        episode: 13,
      ));
    }, () => client({}, requests: requests, catalogFails: true));
    expect(requests, hasLength(2), reason: 'one refresh try, then waits');
  });

  group('up next', () {
    test(
      'a watching anime becomes a TV up-next row in TVDB numbering',
      () async {
        await http.runWithClient(() async {
          final rows = await SimklAnimeEpisodes.upNextAsShows([
            {
              'show': {'title': 'AoT S3P2', 'ids': _aotIds},
              'next_to_watch': 'E05',
              'anime_type': 'tv',
            },
            // Anime-native container key, unmapped episode: left out.
            {
              'anime': {'title': 'AoT S3P2', 'ids': _aotIds},
              'next_to_watch': 'E09',
              'anime_type': 'tv',
            },
            // Films and caught-up entries have no next episode to place.
            {
              'show': {'ids': _aotIds},
              'next_to_watch': 'E01',
              'anime_type': 'movie',
            },
            {
              'show': {'ids': _aotIds},
              'next_to_watch': null,
              'anime_type': 'tv',
            },
          ], SimklAnimeEpisodes.accountGeneration);
          expect(rows, hasLength(1));
          expect(rows.single['next_to_watch'], 'S03E17');
          expect(rows.single['show'], {'title': 'AoT S3P2', 'ids': _aotIds});
          expect(
            SimklEpisodeCodes.seasonEpisode(rows.single['next_to_watch']),
            (season: 3, episode: 17),
          );
        }, () => client({}));
      },
    );

    test('Continue Watching lists the anime with the TV shows', () async {
      await http.runWithClient(
        () async {
          final items = await SimklContinueWatchingService.instance
              .fetchItems();
          final show = items!.shows.single;
          expect(show.id, 'tt2560140');
          expect((show.season, show.episode), (3, 17));
          expect(show.isUpNext, isTrue);
          expect(
            await simkl.fetchNextToWatch('tt2560140'),
            (season: 3, episode: 17),
            reason: 'the series-resume fallback reads the same rows',
          );
        },
        () => client({
          '/sync/all-items/all/watching': {
            'shows': [],
            'anime': [
              {
                'show': {'title': 'AoT S3P2', 'ids': _aotIds},
                'next_to_watch': 'E05',
                'anime_type': 'tv',
                'last_watched_at': '2026-11-20T10:00:00Z',
              },
            ],
          },
          '/sync/playback/episodes': [],
          '/sync/playback/movies': [],
          '/sync/all-items/all/all': {'shows': [], 'movies': [], 'anime': []},
        }),
      );
    });

    test('an anime listed without its IMDb id plays like any show', () async {
      Map<String, Object> account() => {
        '/sync/all-items/all/watching': {
          'shows': [],
          'anime': [
            {
              'show': {'title': 'AoT S3P2', 'ids': _aotListIds},
              'next_to_watch': 'E05',
              'anime_type': 'tv',
              'last_watched_at': '2026-11-20T10:00:00Z',
            },
          ],
        },
        '/sync/playback/episodes': [],
        '/sync/playback/movies': [],
        '/sync/all-items/all/all': {
          'shows': [],
          'movies': [],
          'anime': [
            {
              'show': {
                'title': 'AoT S3P2',
                'poster': '70/7098975f8b45ba7bc',
                'ids': _aotListIds,
              },
              'anime_type': 'tv',
              'status': 'watching',
            },
          ],
        },
      };
      final requests = <String>[];
      await http.runWithClient(() async {
        final show = (await SimklContinueWatchingService.instance.fetchItems())!
            .shows
            .single;
        expect(show.id, 'tt2560140');
        expect(show.meta.imdbId, 'tt2560140');
        expect(show.meta.poster, isNotNull);
        expect((show.season, show.episode), (3, 17));
        expect(await simkl.fetchNextToWatch('tt2560140'), (
          season: 3,
          episode: 17,
        ));
        expect(await SimklAnimeEpisodes.coursFor('tt2560140'), {931899});
      }, () => client(account(), requests: requests));
      expect(
        requests.where((path) => path == '/anime/931899'),
        hasLength(1),
        reason: 'the ids are read once per title',
      );

      // Without the catalog the row keeps the ids the account gave.
      simkl.resetProfileScope();
      SimklAnimeEpisodes.debugReset();
      await http.runWithClient(() async {
        final show = (await SimklContinueWatchingService.instance.fetchItems())!
            .shows
            .single;
        expect(show.id, 'tmdb:1429');
      }, () => client(account(), idsFail: true));
    });

    test(
      'a show found by its IMDb id gets the cours with that IMDb id',
      () async {
        final generation = SimklAnimeEpisodes.accountGeneration;
        Map<String, Object> cour(int simkl, String tmdb) => {
          'show': {
            'ids': {'simkl': simkl, 'tmdb': tmdb},
          },
          'anime_type': 'tv',
        };
        // Live catalog ids (2026-11-23): Simkl gives JoJo and Steel Ball Run
        // one TMDB id, while IMDb keeps them apart.
        const catalog = {
          38049: 'tt2359704', // JoJo Phantom Blood
          45984: 'tt2359704', // JoJo Stardust Crusaders
          2754038: 'tt38268282', // Steel Ball Run
        };
        SimklAnimeEpisodes.rememberLibrary({
          'anime': [
            for (final id in catalog.keys) cour(id, '45790'),
            cour(4242, '45790'), // Its ids can't be read.
            cour(1990194, '209867'),
          ],
        }, generation);
        final requests = <String>[];
        await http.runWithClient(
          () async {
            // Steel Ball Run's full ids arrive with Continue Watching.
            SimklAnimeEpisodes.remember({
              'simkl': 2754038,
              'imdb': 'tt38268282',
              'tmdb': '45790',
            }, generation);
            expect(await SimklAnimeEpisodes.coursFor('tt38268282'), {2754038});
            expect(await SimklAnimeEpisodes.coursFor('tt2359704'), isEmpty);
            SimklAnimeEpisodes.remember({
              'simkl': 38049,
              'imdb': 'tt2359704',
              'tmdb': '45790',
            }, generation);
            expect(await SimklAnimeEpisodes.coursFor('tt2359704'), {
              38049,
              45984,
            });
            expect(await SimklAnimeEpisodes.coursFor('tmdb:209867'), {1990194});
          },
          () => MockClient((request) async {
            requests.add(request.url.path);
            final id = int.parse(request.url.pathSegments.last);
            final imdb = catalog[id];
            return imdb == null
                ? http.Response('{}', 503)
                : http.Response(
                    jsonEncode({
                      'ids': {'simkl': id, 'imdb': imdb, 'tmdb': '45790'},
                    }),
                    200,
                  );
          }),
        );
        expect(
          requests.toSet(),
          hasLength(requests.length),
          reason: 'each cour\'s ids are read once',
        );
      },
    );

    test('shows that share a TMDB id keep their own up-next rows', () async {
      await http.runWithClient(
        () async {
          final rows = await SimklAnimeEpisodes.upNextAsShows([
            for (final (id, at) in [(38049, '10'), (2754038, '11')])
              {
                'show': {
                  'ids': {'simkl': id, 'tmdb': '45790'},
                },
                'next_to_watch': 'E02',
                'anime_type': 'tv',
                'last_watched_at':
                    '2026-11-$at'
                    'T10:00:00Z',
              },
          ], SimklAnimeEpisodes.accountGeneration);
          expect([
            for (final row in rows) row['show']['ids']['imdb'],
          ], unorderedEquals(['tt2359704', 'tt38268282']));
        },
        () => MockClient((request) async {
          final id = int.parse(request.url.pathSegments.last);
          if (request.url.path.startsWith('/anime/episodes/')) {
            return http.Response(
              jsonEncode([
                {
                  'episode': 2,
                  'type': 'episode',
                  'tvdb': {'season': 1, 'episode': 2},
                },
              ]),
              200,
            );
          }
          final imdb = id == 38049 ? 'tt2359704' : 'tt38268282';
          return http.Response(
            jsonEncode({
              'ids': {'simkl': id, 'imdb': imdb, 'tmdb': '45790'},
            }),
            200,
          );
        }),
      );
    });

    test(
      'an IMDb id from the account is used without a catalog read',
      () async {
        final requests = <String>[];
        await http.runWithClient(() async {
          await SimklAnimeEpisodes.upNextAsShows([
            {
              'show': {'ids': _aotIds},
              'next_to_watch': 'E05',
              'anime_type': 'tv',
            },
          ], SimklAnimeEpisodes.accountGeneration);
        }, () => client({}, requests: requests));
        expect(requests, isNot(contains('/anime/931899')));
      },
    );

    test('of two watching cours, the latest watched is next', () async {
      await http.runWithClient(
        () async {
          final show =
              (await SimklContinueWatchingService.instance.fetchItems())!
                  .shows
                  .single;
          expect((show.season, show.episode), (3, 17));
          expect(await simkl.fetchNextToWatch('tt2560140'), (
            season: 3,
            episode: 17,
          ));
        },
        () => client({
          '/sync/all-items/all/watching': {
            'shows': [],
            'anime': [
              {
                'show': {'ids': _aotIds},
                'next_to_watch': 'E05',
                'anime_type': 'tv',
                'last_watched_at': '2026-11-20T10:00:00Z',
              },
              {
                'show': {
                  'ids': {'simkl': 439744, 'imdb': 'tt2560140'},
                },
                'next_to_watch': 'E10',
                'anime_type': 'tv',
                'last_watched_at': '2026-01-05T10:00:00Z',
              },
            ],
          },
          '/sync/playback/episodes': [],
          '/sync/playback/movies': [],
          '/sync/all-items/all/all': {'shows': [], 'movies': [], 'anime': []},
        }),
      );
    });

    test('an anime that can\'t be placed leaves the TV rows intact', () async {
      final requests = <String>[];
      await http.runWithClient(
        () async {
          final rows = await simkl.fetchUpNextShowsOrNull();
          expect(rows, hasLength(1));
          expect(rows!.single['next_to_watch'], 'S02E06');
        },
        () => client(
          {
            '/sync/all-items/all/watching': {
              'shows': [
                {
                  'show': {
                    'ids': {'imdb': 'tt0903747'},
                  },
                  'next_to_watch': 'S02E06',
                },
              ],
              'anime': [
                {
                  'show': {'ids': _aotIds},
                  'next_to_watch': 'E05',
                  'anime_type': 'tv',
                },
              ],
            },
          },
          requests: requests,
          catalogFails: true,
        ),
      );
      expect(
        requests.where((path) => path.startsWith('/sync/')),
        ['/sync/all-items/all/watching'],
        reason: 'one account read, as before anime was included',
      );
    });
  });

  group('paused sessions', () {
    test('anime episodes are placed in TVDB numbering', () async {
      await http.runWithClient(() async {
        final sessions = await SimklAnimeEpisodes.normalizePlaybackSessions([
          {
            'id': 1,
            'type': 'episode',
            'progress': 40,
            'anime': {'ids': _aotIds},
            'episode': {
              'season': 1,
              'number': 2,
              'tvdb_season': 3,
              'tvdb_number': 14,
            },
          },
          // Without Simkl's tvdb fields the catalog mapping places it.
          {
            'id': 2,
            'type': 'episode',
            'anime': {'ids': _aotIds},
            'episode': {'season': 1, 'number': 5},
          },
          {
            'id': 3,
            'type': 'movie',
            'anime': {
              'ids': {'simkl': 49394, 'imdb': 'tt3646946'},
            },
          },
          // A special reuses regular numbers: it must not resume as S3E13.
          {
            'id': 4,
            'type': 'episode',
            'anime': {'ids': _aotIds},
            'episode': {'season': 0, 'number': 1},
          },
          {
            'id': 5,
            'type': 'episode',
            'anime': {'ids': _aotIds},
            'episode': {
              'season': 1,
              'number': 1,
              'tvdb_season': 0,
              'tvdb_number': 1,
            },
          },
        ], SimklAnimeEpisodes.accountGeneration);
        expect(sessions[0]['show'], {'ids': _aotIds});
        expect(sessions[0]['episode']['season'], 3);
        expect(sessions[0]['episode']['number'], 14);
        expect(sessions[0]['id'], 1, reason: 'Remove deletes by session id');
        expect(sessions[1]['episode']['season'], 3);
        expect(sessions[1]['episode']['number'], 17);
        expect(sessions[2]['movie'], {
          'ids': {'simkl': 49394, 'imdb': 'tt3646946'},
        });
        expect(sessions[3]['show'], isNull, reason: 'specials stay unplaced');
        expect(sessions[4]['show'], isNull);
      }, () => client({}));
    });

    test('a paused anime film on hold stays hidden', () async {
      await http.runWithClient(
        () async {
          final items = await SimklContinueWatchingService.instance
              .fetchItems();
          expect(items!.movies, isEmpty);
        },
        () => MockClient((request) async {
          final body = switch (request.url.path) {
            '/anime/49394' => {
              'ids': {'simkl': 49394, 'imdb': 'tt5311514', 'tmdb': '372058'},
            },
            '/sync/playback/movies' => [
              {
                'id': 7,
                'type': 'movie',
                'progress': 40,
                'paused_at': '2026-11-20T10:00:00Z',
                'anime': {
                  'title': 'Kimi no Na wa.',
                  'ids': {'simkl': 49394, 'tmdb': '372058'},
                },
              },
            ],
            '/sync/playback/episodes' => [],
            '/sync/all-items/all/watching' => {'shows': [], 'anime': []},
            '/sync/all-items/all/all' => {
              'shows': [],
              'movies': [],
              'anime': [
                {
                  'show': {
                    'title': 'Kimi no Na wa.',
                    'ids': {'simkl': 49394, 'tmdb': '372058'},
                  },
                  'anime_type': 'movie',
                  'status': 'hold',
                },
              ],
            },
            _ => null,
          };
          return body == null
              ? http.Response('{}', 404)
              : http.Response(jsonEncode(body), 200);
        }),
      );
    });

    test('a paused anime listed without its IMDb id gets it', () async {
      await http.runWithClient(() async {
        final sessions = await SimklAnimeEpisodes.normalizePlaybackSessions([
          {
            'id': 1,
            'type': 'episode',
            'progress': 40,
            'anime': {'title': 'AoT S3P2', 'ids': _aotListIds},
            'episode': {'season': 1, 'number': 5},
          },
        ], SimklAnimeEpisodes.accountGeneration);
        expect(sessions.single['show']['ids'], _aotCatalogIds);
        expect(sessions.single['show']['title'], 'AoT S3P2');
        expect(sessions.single['episode']['season'], 3);
      }, () => client({}));
    });

    test('TV-only session lists are returned as they are', () async {
      final sessions = <dynamic>[
        {
          'show': {
            'ids': {'imdb': 'tt0903747'},
          },
          'episode': {'season': 1, 'number': 1},
        },
      ];
      expect(
        identical(
          await SimklAnimeEpisodes.normalizePlaybackSessions(
            sessions,
            SimklAnimeEpisodes.accountGeneration,
          ),
          sessions,
        ),
        isTrue,
      );
    });

    test(
      'a paused anime episode resumes and shows in Continue Watching',
      () async {
        await http.runWithClient(
          () async {
            expect(await simkl.fetchShowPlaybackSelection('tt2560140'), (
              season: 3,
              episode: 14,
              progress: 40.0,
              pausedAt: DateTime.parse('2026-11-20T10:00:00Z'),
            ));
            expect(await simkl.fetchEpisodePlaybackProgress('tt2560140'), {
              '3-14': 40.0,
            });
            final show =
                (await SimklContinueWatchingService.instance.fetchItems())!
                    .shows
                    .single;
            expect((show.season, show.episode, show.progress), (3, 14, 40.0));
          },
          () => client({
            '/sync/playback/episodes': [
              {
                'id': 7,
                'type': 'episode',
                'progress': 40,
                'paused_at': '2026-11-20T10:00:00Z',
                'anime': {'title': 'AoT S3P2', 'ids': _aotIds},
                'episode': {
                  'season': 1,
                  'number': 2,
                  'tvdb_season': 3,
                  'tvdb_number': 14,
                },
              },
            ],
            '/sync/playback/movies': [],
            '/sync/all-items/all/all': {'shows': [], 'movies': [], 'anime': []},
            '/sync/all-items/all/watching': {'shows': []},
            '/sync/watched': [],
          }),
        );
      },
    );
  });

  group('history writes', () {
    test('episode writes ask Simkl to place anime by TVDB season', () async {
      final bodies = <Object?>[];
      await http.runWithClient(
        () async {
          expect(await simkl.markEpisodeWatched('tt2560140', 3, 13), isTrue);
          expect(await simkl.markEpisodeUnwatched('tt2560140', 3, 13), isTrue);
        },
        () => MockClient((request) async {
          bodies.add(jsonDecode(request.body));
          return http.Response('{"added": {}, "not_found": {}}', 201);
        }),
      );
      for (final body in bodies) {
        final show = ((body as Map)['shows'] as List).single as Map;
        expect(show['ids'], {'imdb': 'tt2560140'});
        expect(show['use_tvdb_anime_seasons'], isTrue);
        expect(show['seasons'], [
          {
            'number': 3,
            'episodes': [
              {'number': 13},
            ],
          },
        ]);
      }
      expect(bodies, hasLength(2));
    });
  });

  group('watched episodes', () {
    final library = {
      'shows': [],
      'movies': [],
      'anime': [
        {
          'show': {
            'ids': {'simkl': 39687, 'imdb': 'tt2560140'},
          },
          'anime_type': 'tv',
          'status': 'completed',
        },
        {
          'show': {'ids': _aotIds},
          'anime_type': 'tv',
          'status': 'watching',
        },
      ],
    };
    // Each cour answers in its own numbering (S3P2 episode 1 = TVDB S3E13).
    final perCour = [
      {
        'result': true,
        'simkl': 39687,
        'seasons': [
          {
            'number': 1,
            'episodes': [
              {'number': 1, 'watched': true},
            ],
          },
        ],
      },
      {
        'result': true,
        'simkl': 931899,
        'seasons': [
          {
            'number': 1,
            'episodes': [
              {
                'number': 1,
                'watched': true,
                'last_watched_at': '2026-11-20T10:00:00Z',
              },
              {'number': 2, 'watched': false},
            ],
          },
        ],
      },
    ];

    Future<http.Response> watchedHandler(
      http.Request request,
      List<Object?> bodies, {
      Object? watched,
      Object? imdbWatched,
    }) async {
      if (request.url.path == '/anime/episodes/931899') {
        return http.Response(jsonEncode(_aotS3p2Episodes), 200);
      }
      if (request.url.path == '/anime/episodes/39687') {
        return http.Response(
          jsonEncode([
            {
              'episode': 1,
              'type': 'episode',
              'tvdb': {'season': 1, 'episode': 1},
            },
          ]),
          200,
        );
      }
      if (request.url.path == '/sync/all-items/all/all') {
        return http.Response(jsonEncode(library), 200);
      }
      if (request.url.path == '/sync/watched') {
        final body = jsonDecode(request.body) as List;
        bodies.add(body);
        final byImdb = (body.first as Map).containsKey('imdb');
        return http.Response(
          jsonEncode(byImdb ? (imdbWatched ?? []) : (watched ?? perCour)),
          200,
        );
      }
      return http.Response('{"added": {}, "not_found": {}}', 201);
    }

    MockClient watchedClient(
      List<Object?> bodies, {
      Object? watched,
      Object? imdbWatched,
    }) => MockClient(
      (request) => watchedHandler(
        request,
        bodies,
        watched: watched,
        imdbWatched: imdbWatched,
      ),
    );

    test('every cour is read and placed in TVDB numbering', () async {
      final bodies = <Object?>[];
      await http.runWithClient(() async {
        await simkl.fetchLibrarySnapshotOrNull();
        expect(await simkl.fetchWatchedShowEpisodesOrNull('tt2560140'), {
          '1-1',
          '3-13',
        });
        expect(await simkl.fetchWatchedShowEpisodeTimes('tt2560140'), {
          '3-13': DateTime.parse('2026-11-20T10:00:00Z'),
        });
      }, () => watchedClient(bodies));
      expect(bodies.first, [
        {
          'ids': {'simkl': 39687},
        },
        {
          'ids': {'simkl': 931899},
        },
      ]);
    });

    test('the cours stay known after a write clears the library', () async {
      final bodies = <Object?>[];
      await http.runWithClient(() async {
        await simkl.fetchLibrarySnapshotOrNull();
        expect(await simkl.markEpisodeWatched('tt2560140', 3, 13), isTrue);
        expect(
          await simkl.fetchWatchedShowEpisodesOrNull('tt2560140'),
          contains('3-13'),
        );
      }, () => watchedClient(bodies));
      expect(bodies.single, hasLength(2), reason: 'per-cour read');
    });

    test('an unreadable per-cour answer falls back to the show read', () async {
      final bodies = <Object?>[];
      await http.runWithClient(
        () async {
          await simkl.fetchLibrarySnapshotOrNull();
          expect(await simkl.fetchWatchedShowEpisodesOrNull('tt2560140'), {
            '1-5',
          });
        },
        () => watchedClient(
          bodies,
          watched: {'unexpected': true},
          imdbWatched: [
            {
              'seasons': [
                {
                  'number': 1,
                  'episodes': [
                    {'number': 5, 'watched': true},
                  ],
                },
              ],
            },
          ],
        ),
      );
      expect(bodies, hasLength(2));
    });

    test('TV shows keep their single show read', () async {
      final bodies = <Object?>[];
      await http.runWithClient(() async {
        await simkl.fetchLibrarySnapshotOrNull();
        await simkl.fetchWatchedShowEpisodesOrNull('tt0903747');
      }, () => watchedClient(bodies));
      expect(bodies, [
        [
          {'imdb': 'tt0903747', 'type': 'show'},
        ],
      ]);
    });

    test(
      'a cour whose map can\'t be read falls back to the show read',
      () async {
        final bodies = <Object?>[];
        await http.runWithClient(
          () async {
            await simkl.fetchLibrarySnapshotOrNull();
            expect(await simkl.fetchWatchedShowEpisodesOrNull('tt2560140'), {
              '1-5',
            });
          },
          () => MockClient((request) async {
            if (request.url.path.startsWith('/anime/episodes/')) {
              return http.Response('{}', 503);
            }
            return watchedHandler(
              request,
              bodies,
              imdbWatched: [
                {
                  'seasons': [
                    {
                      'number': 1,
                      'episodes': [
                        {'number': 5, 'watched': true},
                      ],
                    },
                  ],
                },
              ],
            );
          }),
        );
        expect(
          bodies,
          hasLength(2),
          reason: 'per-cour read, then the fallback',
        );
      },
    );

    test('cours no longer in the library fall back to the show read', () async {
      final bodies = <Object?>[];
      await http.runWithClient(
        () async {
          await simkl.fetchLibrarySnapshotOrNull();
          expect(
            await simkl.fetchWatchedShowEpisodesOrNull('tt2560140'),
            isNull,
          );
        },
        () => watchedClient(
          bodies,
          watched: [
            {'result': 'not_found'},
          ],
          imdbWatched: [
            {'result': 'not_found'},
          ],
        ),
      );
      expect(bodies, hasLength(2));
    });

    test('resetting an anime clears every cour in its own numbering', () async {
      final bodies = <Object?>[];
      Object? removal;
      // A watched special and an episode the catalog can't map yet must go
      // too: both are left out of the TVDB-numbered read.
      final watched = [
        perCour.first,
        {
          'result': true,
          'simkl': 931899,
          'seasons': [
            {
              'number': 0,
              'episodes': [
                {'number': 1, 'watched': true},
              ],
            },
            {
              'number': 1,
              'episodes': [
                {'number': 1, 'watched': true},
                {'number': 2, 'watched': false},
                {'number': 9, 'watched': true},
              ],
            },
          ],
        },
      ];
      await http.runWithClient(
        () async {
          await simkl.fetchLibrarySnapshotOrNull();
          expect(await simkl.clearSeriesHistory('tt2560140'), isTrue);
        },
        () => MockClient((request) async {
          if (request.url.path == '/sync/history/remove') {
            removal = jsonDecode(request.body);
            return http.Response('{"deleted": {}, "not_found": {}}', 200);
          }
          return watchedHandler(request, bodies, watched: watched);
        }),
      );
      expect(removal, {
        'shows': [
          {
            'ids': {'simkl': 39687},
            'seasons': [
              {
                'number': 1,
                'episodes': [
                  {'number': 1},
                ],
              },
            ],
          },
          {
            'ids': {'simkl': 931899},
            'seasons': [
              {
                'number': 0,
                'episodes': [
                  {'number': 1},
                ],
              },
              {
                'number': 1,
                'episodes': [
                  {'number': 1},
                  {'number': 9},
                ],
              },
            ],
          },
        ],
      });
    });

    test(
      'an unreadable per-cour answer resets through the show read',
      () async {
        final bodies = <Object?>[];
        Object? removal;
        await http.runWithClient(
          () async {
            await simkl.fetchLibrarySnapshotOrNull();
            expect(await simkl.clearSeriesHistory('tt2560140'), isTrue);
          },
          () => MockClient((request) async {
            if (request.url.path == '/sync/history/remove') {
              removal = jsonDecode(request.body);
              return http.Response('{"deleted": {}, "not_found": {}}', 200);
            }
            return watchedHandler(
              request,
              bodies,
              watched: {'unexpected': true},
              imdbWatched: [
                {
                  'seasons': [
                    {
                      'number': 1,
                      'episodes': [
                        {'number': 4, 'watched': true},
                      ],
                    },
                  ],
                },
              ],
            );
          }),
        );
        expect(removal, {
          'shows': [
            {
              'ids': {'imdb': 'tt2560140'},
              'seasons': [
                {
                  'number': 1,
                  'episodes': [
                    {'number': 4},
                  ],
                },
              ],
            },
          ],
        });
      },
    );

    test(
      'a read that finishes after an account change records nothing',
      () async {
        final before = SimklAnimeEpisodes.accountGeneration;
        simkl.resetProfileScope();
        SimklAnimeEpisodes.rememberLibrary(library, before);
        expect(await SimklAnimeEpisodes.coursFor('tt2560140'), isEmpty);
        SimklAnimeEpisodes.rememberLibrary(
          library,
          SimklAnimeEpisodes.accountGeneration,
        );
        expect(await SimklAnimeEpisodes.coursFor('tt2560140'), {39687, 931899});
      },
    );

    test('a profile or account change forgets the cours', () async {
      final bodies = <Object?>[];
      await http.runWithClient(() async {
        await simkl.fetchLibrarySnapshotOrNull();
      }, () => watchedClient(bodies));
      expect(await SimklAnimeEpisodes.coursFor('tt2560140'), {39687, 931899});
      simkl.resetProfileScope();
      expect(await SimklAnimeEpisodes.coursFor('tt2560140'), isEmpty);
    });
  });

  group('calendar', () {
    // Shapes from the live data.simkl.in calendar files (2026-11-21).
    Map<String, Object> airing(int simklId, int episode) => {
      'title': 'Shingeki no Kyojin Season 3 Part 2',
      'date': '2026-11-22T00:00:00+09:00',
      'release_date': '2019-04-29',
      'ids': {'simkl_id': simklId, 'slug': 'x', 'tmdb': '1429', 'mal': '1'},
      'episode': {'episode': episode, 'url': 'https://simkl.com/anime/x'},
      'anime_type': 'tv',
    };
    final library = {
      'shows': [],
      'anime': [
        {
          'show': {'title': 'AoT S3P2', 'ids': _aotIds},
          'status': 'watching',
          'anime_type': 'tv',
        },
      ],
    };
    final tvShow = {
      'title': 'Breaking Bad',
      'date': '2026-11-23T00:00:00-05:00',
      'release_date': '2008-01-20',
      'ids': {'simkl_id': 1, 'imdb': 'tt0903747'},
      'episode': {'season': 6, 'episode': 1},
    };

    test('library anime airs in TVDB numbering beside TV shows', () async {
      SimklCalendarService.instance.invalidate();
      await http.runWithClient(
        () async {
          final range = await SimklCalendarService.instance.getRange(
            DateTime(2026, 11, 1),
            DateTime(2026, 11, 30),
            strict: true,
          );
          final entries = range.values.expand((day) => day).toList();
          final anime = entries.singleWhere((e) => e.showImdbId == 'tt2560140');
          expect((anime.seasonNumber, anime.episodeNumber), (3, 17));
          expect(entries.map((e) => e.showImdbId), contains('tt0903747'));
          expect(
            entries,
            hasLength(2),
            reason: 'titles not in the library drop',
          );
        },
        () => client({
          '/sync/all-items/all/all': {
            ...library,
            'shows': [
              {
                'show': {
                  'ids': {'imdb': 'tt0903747'},
                },
                'status': 'watching',
              },
            ],
          },
          '/calendar/tv.json': [tvShow],
          '/calendar/anime.json': [airing(931899, 5), airing(42, 3)],
        }),
      );
    });

    test('a malformed anime entry leaves the rest of the calendar', () async {
      SimklCalendarService.instance.invalidate();
      await http.runWithClient(
        () async {
          final range = await SimklCalendarService.instance.getRange(
            DateTime(2026, 11, 1),
            DateTime(2026, 11, 30),
            strict: true,
          );
          expect(range.values.expand((day) => day), hasLength(2));
        },
        () => client({
          '/sync/all-items/all/all': {
            ...library,
            'shows': [
              {
                'show': {
                  'ids': {'imdb': 'tt0903747'},
                },
                'status': 'watching',
              },
            ],
          },
          '/calendar/tv.json': [tvShow],
          '/calendar/anime.json': [
            {...airing(931899, 1), 'date': 20261122},
            airing(931899, 5),
          ],
        }),
      );
    });

    test('a timed anime air date lands on the viewer\'s own day', () async {
      SimklCalendarService.instance.invalidate();
      // 01:00 in Japan is the previous evening west of about UTC+1.
      const timed = '2026-11-22T01:00:00+09:00';
      final airs = DateTime.parse(timed).toLocal();
      await http.runWithClient(
        () async {
          final range = await SimklCalendarService.instance.getRange(
            DateTime(2026, 11, 1),
            DateTime(2026, 11, 30),
            strict: true,
          );
          final days = {
            for (final day in range.entries)
              for (final e in day.value) e.episodeNumber: e.firstAiredLocal,
          };
          expect(days[17], DateTime(airs.year, airs.month, airs.day));
          expect(
            days[14],
            DateTime(2026, 11, 22),
            reason: 'a bare midnight is a day marker, as in the TV file',
          );
        },
        () => client({
          '/sync/all-items/all/all': library,
          '/calendar/tv.json': [],
          '/calendar/anime.json': [
            {...airing(931899, 5), 'date': timed},
            airing(931899, 2),
          ],
        }),
      );
    });

    test('a failed anime file leaves the TV calendar intact', () async {
      SimklCalendarService.instance.invalidate();
      await http.runWithClient(
        () async {
          final range = await SimklCalendarService.instance.getRange(
            DateTime(2026, 11, 1),
            DateTime(2026, 11, 30),
            strict: true,
          );
          expect(
            range.values.expand((day) => day).single.showImdbId,
            'tt0903747',
          );
        },
        () => client({
          '/sync/all-items/all/all': {
            ...library,
            'shows': [
              {
                'show': {
                  'ids': {'imdb': 'tt0903747'},
                },
                'status': 'watching',
              },
            ],
          },
          '/calendar/tv.json': [tvShow],
        }),
      );
    });
  });

  group('shared ids', () {
    test(
      'a parked cour doesn\'t hide an active cour\'s paused episode',
      () async {
        await http.runWithClient(
          () async {
            final show =
                (await SimklContinueWatchingService.instance.fetchItems())!
                    .shows
                    .single;
            expect((show.season, show.episode), (3, 14));
          },
          () => client({
            '/sync/playback/episodes': [
              {
                'id': 7,
                'type': 'episode',
                'progress': 40,
                'anime': {'ids': _aotIds},
                'episode': {'number': 2, 'tvdb_season': 3, 'tvdb_number': 14},
              },
            ],
            '/sync/playback/movies': [],
            '/sync/all-items/all/watching': {'shows': []},
            '/sync/watched': [],
            '/sync/all-items/all/all': {
              'anime': [
                {
                  'show': {'ids': _aotIds},
                  'anime_type': 'tv',
                  'status': 'watching',
                },
                {
                  'show': {
                    'ids': {'simkl': 439744, 'imdb': 'tt2560140'},
                  },
                  'anime_type': 'tv',
                  'status': 'hold',
                },
              ],
            },
          }),
        );
      },
    );

    test('a parked cour\'s own paused episode stays hidden', () async {
      await http.runWithClient(
        () async {
          final items = await SimklContinueWatchingService.instance
              .fetchItems();
          expect(items!.shows, isEmpty);
        },
        () => client({
          '/sync/playback/episodes': [
            {
              'id': 7,
              'type': 'episode',
              'progress': 40,
              'anime': {'ids': _aotIds},
              'episode': {'number': 2, 'tvdb_season': 3, 'tvdb_number': 14},
            },
          ],
          '/sync/playback/movies': [],
          '/sync/all-items/all/watching': {'shows': []},
          '/sync/watched': [],
          '/sync/all-items/all/all': {
            'anime': [
              {
                'show': {'ids': _aotIds},
                'anime_type': 'tv',
                'status': 'hold',
              },
              {
                'show': {
                  'ids': {'simkl': 39687, 'imdb': 'tt2560140'},
                },
                'anime_type': 'tv',
                'status': 'watching',
              },
            ],
          },
        }),
      );
    });

    test('an older cour doesn\'t stand in for a newer unplaced one', () async {
      await http.runWithClient(
        () async {
          expect(
            await simkl.fetchNextToWatch('tt2560140'),
            isNull,
            reason: 'the user is past the older cour\'s next episode',
          );
          expect(
            (await SimklContinueWatchingService.instance.fetchItems())!.shows,
            isEmpty,
          );
        },
        () => client({
          '/sync/all-items/all/watching': {
            // Newest, but caught up: nothing to place.
            'shows': [
              {
                'show': {
                  'ids': {'imdb': 'tt2560140'},
                },
                'next_to_watch': null,
                'last_watched_at': '2026-11-21T10:00:00Z',
              },
            ],
            'anime': [
              {
                'show': {'ids': _aotIds},
                'next_to_watch': 'E05',
                'anime_type': 'tv',
                'last_watched_at': '2026-01-01T10:00:00Z',
              },
              // Newer, but its episode has no TVDB mapping.
              {
                'show': {
                  'ids': {'simkl': 439744, 'imdb': 'tt2560140'},
                },
                'next_to_watch': 'E09',
                'anime_type': 'tv',
                'last_watched_at': '2026-11-20T10:00:00Z',
              },
            ],
          },
          '/sync/playback/episodes': [],
          '/sync/playback/movies': [],
          '/sync/all-items/all/all': {'shows': [], 'movies': [], 'anime': []},
        }),
      );
    });
  });

  group('watched ticks', () {
    Map<String, dynamic> cour(
      Map<String, Object> ids,
      int watched,
      int total,
    ) => {
      'show': {'ids': ids},
      'anime_type': 'tv',
      'watched_episodes_count': watched,
      'total_episodes_count': total,
      'not_aired_episodes_count': 0,
    };

    test('a show split into cours is watched only when every cour is', () {
      final s1 = {'simkl': 39687, 'imdb': 'tt2560140', 'mal': '16498'};
      final s2 = {'simkl': 439744, 'imdb': 'tt2560140', 'mal': '25777'};
      final partly = SimklCompletedTitles.parse({
        'anime': [cour(s1, 25, 25), cour(s2, 4, 12)],
      }).series;
      expect(partly, isNot(contains('tt2560140')));
      expect(partly, contains('simkl:39687'), reason: 'S1 itself is finished');
      final all = SimklCompletedTitles.parse({
        'anime': [cour(s1, 25, 25), cour(s2, 12, 12)],
      }).series;
      expect(all, contains('tt2560140'));
    });

    test('an announced cour with nothing aired doesn\'t block the show', () {
      final s1 = {'simkl': 39687, 'imdb': 'tt2560140'};
      final next = {'simkl': 99, 'imdb': 'tt2560140'};
      final result = SimklCompletedTitles.parse({
        'anime': [
          cour(s1, 25, 25),
          {
            ...cour(next, 0, 12),
            'not_aired_episodes_count': 12,
            'status': 'plantowatch',
          },
        ],
      }).series;
      expect(result, contains('tt2560140'));
    });

    test('TV shows and single-entry anime are unchanged', () {
      final result = SimklCompletedTitles.parse({
        'shows': [
          cour({'imdb': 'tt0903747'}, 62, 62),
        ],
        'anime': [
          cour({'simkl': 38636, 'imdb': 'tt0388629'}, 1100, 1100),
        ],
      }).series;
      expect(result, containsAll(['tt0903747', 'tt0388629']));
    });
  });
}
