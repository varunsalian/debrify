import 'dart:async';
import 'dart:convert';

import 'package:debrify/models/tracking_source.dart';
import 'package:debrify/services/episode_tracker_snapshot_revision.dart';
import 'package:debrify/services/mdblist/mdblist_models.dart';
import 'package:debrify/services/mdblist/mdblist_scrobble_session.dart';
import 'package:debrify/services/mdblist/mdblist_service.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/secret_vault.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/services/trakt/trakt_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

http.Response json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'x-pagination-page-count': '1'},
);
MdblistService mdblist(Future<http.Response> Function(http.Request) handler) =>
    MdblistService.forTesting(
      client: MockClient(handler),
      apiKeyProvider: () async => 'test-key',
      featureEnabled: () => true,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final trakt = TraktService.instance;
  setUp(() async {
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    SharedPreferences.setMockInitialValues({});
    SecretVault.debugReset(deviceIdOverride: 'native-trackers-test');
    EpisodeTrackerSnapshotRevision.resetForTesting();
    trakt.resetProfileScope();
    await StorageService.setTraktSession(
      accessToken: 'test-access',
      refreshToken: 'test-refresh',
      expiryMs: 9000000000000,
    );
    await StorageService.setTrackingScrobbleTargets({
      TrackingSource.local,
      TrackingSource.trakt,
      TrackingSource.mdblist,
    });
  });
  tearDown(() {
    trakt.resetProfileScope();
    SecretVault.debugReset();
    ProfileRuntime.debugReset();
  });

  test('unresolved series never produce a movie scrobble', () async {
    await http.runWithClient(() async {
      for (final id in ['tmdb:237243', 'simkl:990050', 'tt0251497']) {
        for (final coordinates in [
          (season: null, episode: null),
          (season: 0, episode: 0),
          (season: 4, episode: null),
          (season: null, episode: 6),
        ]) {
          for (final send in [
            trakt.scrobbleStart,
            trakt.scrobblePause,
            trakt.scrobbleStop,
          ]) {
            expect(
              await send(
                id,
                95,
                contentType: 'series',
                season: coordinates.season,
                episode: coordinates.episode,
              ),
              isFalse,
            );
          }
        }
      }
      expect(await trakt.scrobbleStop('tmdb:237243', 95), isFalse);
      expect(await trakt.scrobbleStop('simkl:990050', 95), isFalse);
    }, () => MockClient((_) async => fail('Unresolved series made a request')));
  });

  test(
    'declared TMDB movies remain movies even with parsed episode numbers',
    () async {
      await http.runWithClient(
        () async {
          expect(
            await trakt.scrobbleStop(
              'tmdb:237243',
              95,
              contentType: 'movie',
              season: 5,
              episode: 1,
            ),
            isTrue,
          );
        },
        () => MockClient((request) async {
          expect(jsonDecode(request.body), {
            'movie': {
              'ids': {'tmdb': 237243},
            },
            'progress': 95,
          });
          return json({}, 201);
        }),
      );
    },
  );

  test(
    'Trakt start/pause/stop and manual watched actions keep UK ID and coordinates',
    () async {
      final requests = <http.Request>[];
      final before = EpisodeTrackerSnapshotRevision.identity(
        'trakt',
        'tmdb:237243',
      );
      await http.runWithClient(
        () async {
          expect(
            await trakt.scrobbleStart('tmdb:237243', 1, season: 4, episode: 6),
            isTrue,
          );
          expect(
            await trakt.scrobblePause('tmdb:237243', 40, season: 4, episode: 6),
            isTrue,
          );
          expect(
            await trakt.scrobbleStop('tmdb:237243', 95, season: 4, episode: 6),
            isTrue,
          );
          expect(
            await trakt.scrobbleStart('tmdb:237243', 1, season: 4, episode: 7),
            isTrue,
          );
          expect(await trakt.markEpisodeWatched('tmdb:237243', 4, 7), isTrue);
          expect(await trakt.markEpisodeUnwatched('tmdb:237243', 4, 7), isTrue);
        },
        () => MockClient((request) async {
          requests.add(request);
          return json({}, 201);
        }),
      );
      expect(requests.map((r) => r.url.path), [
        '/scrobble/start',
        '/scrobble/pause',
        '/scrobble/stop',
        '/scrobble/start',
        '/sync/history',
        '/sync/history/remove',
      ]);
      for (var i = 0; i < 4; i++) {
        final body = jsonDecode(requests[i].body);
        expect(body['show']['ids'], {'tmdb': 237243});
        expect(body['episode'], {'season': 4, 'number': i == 3 ? 7 : 6});
      }
      for (final r in requests.skip(4)) {
        final show = jsonDecode(r.body)['shows'].single;
        expect(show['ids'], {'tmdb': 237243});
        expect(show['seasons'].single['number'], 4);
        expect(show['seasons'].single['episodes'].single['number'], 7);
      }
      expect(
        EpisodeTrackerSnapshotRevision.identity('trakt', 'tmdb:237243'),
        isNot(before),
      );
    },
  );

  test(
    'Trakt uses verified Simkl mapping and preserves ordinary IMDb payloads',
    () async {
      final writes = <Map<String, dynamic>>[];
      await http.runWithClient(
        () async {
          expect(
            await trakt.scrobbleStop(
              'simkl:2274121',
              95,
              season: 4,
              episode: 6,
            ),
            isTrue,
          );
          expect(
            await trakt.scrobbleStop('tt1234567', 95, season: 1, episode: 2),
            isTrue,
          );
          expect(await trakt.scrobbleStop('tmdb:movie:237243', 95), isTrue);
        },
        () => MockClient((r) async {
          if (r.url.host == 'api.simkl.com') {
            expect(r.url.path, '/tv/2274121');
            return json({
              'type': 'show',
              'ids': {'simkl': 2274121, 'tmdb': 237243, 'imdb': 'tt0251497'},
            });
          }
          writes.add(jsonDecode(r.body));
          return json({}, 201);
        }),
      );
      expect(writes[0]['show']['ids'], {'tmdb': 237243});
      expect(writes[1]['show']['ids'], {'imdb': 'tt1234567'});
      expect(writes[2]['movie']['ids'], {'tmdb': 237243});
    },
  );

  test('unmapped Simkl identity makes no Trakt or MDBList write', () async {
    var simklReads = 0;
    final service = mdblist((_) async => fail('Unmapped ID reached MDBList'));
    await http.runWithClient(
      () async {
        expect(
          await trakt.scrobbleStop('simkl:990001', 95, season: 4, episode: 6),
          isFalse,
        );
        final result = await service.scrobbleStop(
          MdblistScrobbleTarget.episode(
            MdblistMediaIds.forContent('simkl:990001'),
            season: 4,
            episode: 6,
          ),
          95,
        );
        expect(result.isSuccess, isFalse);
      },
      () => MockClient((r) async {
        expect(r.url.host, 'api.simkl.com');
        expect(r.url.path, '/tv/990001');
        simklReads++;
        return json({
          'type': 'show',
          'ids': {'simkl': 990002, 'tmdb': 10160},
        });
      }),
    );
    expect(simklReads, 2);
  });

  test('disabled Trakt does not even resolve a Simkl identity', () async {
    await StorageService.setTrackingScrobbleTargets({TrackingSource.local});
    await http.runWithClient(() async {
      expect(
        await trakt.scrobbleStop('simkl:990010', 95, season: 4, episode: 6),
        isFalse,
      );
    }, () => MockClient((_) async => fail('Disabled tracker made a request')));
  });

  test(
    'MDBList Simkl mapping keeps the original progress identity on success',
    () async {
      final before = EpisodeTrackerSnapshotRevision.identity(
        'mdblist',
        'simkl:990011',
      );
      final service = mdblist((r) async {
        expect(r.url.path, '/scrobble/stop');
        expect(jsonDecode(r.body)['show'], {
          'ids': {'tmdb': 237243},
          'season': 4,
          'episode': 6,
        });
        return json({});
      });
      await http.runWithClient(
        () async {
          final result = await service.scrobbleStop(
            MdblistScrobbleTarget.episode(
              MdblistMediaIds.forContent('simkl:990011'),
              season: 4,
              episode: 6,
            ),
            95,
          );
          expect(result.isSuccess, isTrue);
        },
        () => MockClient((r) async {
          expect(r.url.path, '/tv/990011');
          return json({
            'type': 'show',
            'ids': {'simkl': 990011, 'tmdb': 237243},
          });
        }),
      );
      expect(
        EpisodeTrackerSnapshotRevision.identity('mdblist', 'simkl:990011'),
        isNot(before),
      );
    },
  );

  for (final provider in ['trakt', 'mdblist']) {
    test(
      '$provider refuses a write when profile changes during ID mapping',
      () async {
        final started = Completer<void>();
        final response = Completer<http.Response>();
        final id = provider == 'trakt' ? 990012 : 990013;
        final service = mdblist(
          (_) async => fail('Stale playback reached MDBList'),
        );
        await http.runWithClient(
          () async {
            final pending = provider == 'trakt'
                ? trakt.scrobbleStop('simkl:$id', 95, season: 4, episode: 6)
                : service
                      .scrobbleStop(
                        MdblistScrobbleTarget.episode(
                          MdblistMediaIds.forContent('simkl:$id'),
                          season: 4,
                          episode: 6,
                        ),
                        95,
                      )
                      .then((r) => r.isSuccess);
            await started.future;
            ProfileRuntime.initializeCommitted(
              ProfileScope(
                profileId: 'another-profile',
                dataGeneration: 1,
                sessionEpoch: 2,
              ),
            );
            response.complete(
              json({
                'type': 'show',
                'ids': {'simkl': id, 'tmdb': 237243},
              }),
            );
            expect(await pending, isFalse);
          },
          () => MockClient((r) {
            expect(r.url.host, 'api.simkl.com');
            started.complete();
            return response.future;
          }),
        );
      },
    );
  }

  test(
    'Trakt watched lookup verifies TMDB identity and reuses the exact Trakt show ID',
    () async {
      final paths = <String>[];
      await http.runWithClient(
        () async {
          expect(await trakt.fetchWatchedShowEpisodesOrNull('tmdb:237243'), {
            '4-6',
          });
          expect(await trakt.fetchNextEpisode('tmdb:237243'), (
            season: 4,
            episode: 7,
          ));
        },
        () => MockClient((r) async {
          paths.add(r.url.path);
          if (r.url.path == '/search/tmdb/237243') {
            expect(r.url.queryParameters['type'], 'show');
            return json([
              {
                'type': 'show',
                'show': {
                  'ids': {'trakt': 10, 'tmdb': 10160},
                },
              },
              {
                'type': 'show',
                'show': {
                  'ids': {'trakt': 99, 'tmdb': 237243},
                },
              },
            ]);
          }
          expect(r.url.path, '/shows/99/progress/watched');
          return json({
            'seasons': [
              {
                'number': 4,
                'episodes': [
                  {'number': 6, 'completed': true},
                ],
              },
            ],
            'next_episode': {'season': 4, 'number': 7},
          });
        }),
      );
      expect(paths.where((p) => p.startsWith('/search/')), hasLength(1));
    },
  );

  test('Trakt rejects ambiguous and mismatched show lookups', () async {
    for (final matches in [
      [
        {
          'type': 'show',
          'show': {
            'ids': {'trakt': 10, 'tmdb': 10160},
          },
        },
      ],
      [
        for (final id in [10, 11])
          {
            'type': 'show',
            'show': {
              'ids': {'trakt': id, 'tmdb': 237243},
            },
          },
      ],
    ]) {
      trakt.resetProfileScope();
      await http.runWithClient(
        () async {
          expect(
            await trakt.fetchWatchedShowEpisodesOrNull('tmdb:237243'),
            isNull,
          );
        },
        () => MockClient((r) async {
          expect(r.url.path, '/search/tmdb/237243');
          return json(matches);
        }),
      );
    }
  });

  test(
    'Trakt paused progress separates identically named UK/US shows',
    () async {
      await http.runWithClient(
        () async {
          expect(
            await trakt.fetchEpisodePlaybackProgressOrNull('tmdb:237243'),
            {'4-7': 42},
          );
        },
        () => MockClient((r) async {
          expect(r.url.path, '/sync/playback/episodes');
          return json([
            {
              'show': {
                'ids': {'tmdb': 237243},
              },
              'episode': {'season': 4, 'number': 7},
              'progress': 42,
            },
            {
              'show': {
                'ids': {'tmdb': 10160, 'imdb': 'tt0251497'},
              },
              'episode': {'season': 4, 'number': 6},
              'progress': 75,
            },
          ]);
        }),
      );
    },
  );

  test(
    'MDBList completion, episode switch, and manual unwatch use TMDB with original snapshot key',
    () async {
      final writes = <http.Request>[];
      final service = mdblist((r) async {
        writes.add(r);
        return json({});
      });
      final before = EpisodeTrackerSnapshotRevision.identity(
        'mdblist',
        'tmdb:237243',
      );
      MdblistScrobbleTarget target(int episode) =>
          MdblistScrobbleTarget.episode(
            MdblistMediaIds.forContent('tmdb:237243'),
            season: 4,
            episode: episode,
          );
      final session = MdblistScrobbleSession.forService(
        service: service,
        target: target(6),
        capability: null,
      );
      session.updatePosition(
        const Duration(minutes: 40),
        const Duration(minutes: 100),
      );
      session.pause();
      await session.flush();
      session.complete();
      await session.switchTarget(
        target(7),
        duration: const Duration(minutes: 100),
      );
      session.updatePosition(
        const Duration(minutes: 25),
        const Duration(minutes: 100),
      );
      await session.close();
      expect(
        await service.markUnwatched(
          MdblistMediaIds.forContent('tmdb:237243'),
          'episode',
          season: 4,
          episode: 6,
        ),
        isTrue,
      );
      expect(writes.map((r) => r.url.path), [
        '/scrobble/pause',
        '/scrobble/stop',
        '/scrobble/pause',
        '/sync/watched/remove',
      ]);
      for (var i = 0; i < 3; i++) {
        expect(jsonDecode(writes[i].body)['show'], {
          'ids': {'tmdb': 237243},
          'season': 4,
          'episode': i == 2 ? 7 : 6,
        });
      }
      final show = jsonDecode(writes.last.body)['shows'].single;
      expect(show['ids'], {'tmdb': 237243});
      expect(
        EpisodeTrackerSnapshotRevision.identity('mdblist', 'tmdb:237243'),
        isNot(before),
      );
    },
  );

  test(
    'MDBList reads TMDB history and matching paused sessions without IMDb',
    () async {
      final paths = <String>[];
      final service = mdblist((r) async {
        paths.add(r.url.path);
        switch (r.url.path) {
          case '/tmdb/show/237243/':
            return json({
              'ids': {'tmdb': 237243},
            });
          case '/sync/playback':
            return json([
              {
                'id': 1,
                'progress': 42,
                'show': {
                  'ids': {'tmdb': 237243},
                },
                'episode': {'season': 4, 'number': 7},
              },
              {
                'id': 2,
                'progress': 75,
                'show': {
                  'ids': {'tmdb': 10160},
                },
                'episode': {'season': 4, 'number': 8},
              },
            ]);
          case '/sync/history/show/tmdb/237243':
            return json({
              'plays': [
                {'season_num': 4, 'episode_num': 6},
              ],
              'truncated': false,
            });
          default:
            return json({}, 404);
        }
      });
      final result = await service.fetchShowEpisodeProgress('tmdb:237243');
      expect(result.isComplete, isTrue);
      expect(result.data, {'4-6': 100, '4-7': 42});
      expect(paths, isNot(contains('/imdb/show/tmdb:237243/')));
    },
  );

  test(
    'MDBList mismatched metadata never queries another show history',
    () async {
      final service = mdblist((r) async {
        if (r.url.path == '/sync/playback') return json([]);
        expect(r.url.path, '/tmdb/show/237243/');
        return json({
          'ids': {'tmdb': 10160, 'imdb': 'tt0251497'},
        });
      });
      final result = await service.fetchShowEpisodeProgress('tmdb:237243');
      expect(result.isComplete, isFalse);
      expect(result.data, isEmpty);
    },
  );

  test('watched badges keep TMDB movies and shows separate', () async {
    expect(
      TraktService.debugParseWatchedMovies([
        {
          'movie': {
            'ids': {'tmdb': 237243},
          },
        },
      ]),
      {'tmdb:movie:237243': 100},
    );
    expect(
      TraktService.debugParseFullyWatchedShows([
        {
          'show': {
            'ids': {'tmdb': 237243},
            'aired_episodes': 1,
          },
          'seasons': [
            {
              'number': 4,
              'episodes': [
                {'number': 6},
              ],
            },
          ],
        },
      ]),
      {'tmdb:237243'},
    );
    final service = mdblist((r) async {
      if (r.url.path == '/sync/watched') {
        return json({
          'movies': [
            {
              'movie': {
                'ids': {'tmdb': 237243},
              },
            },
          ],
          'shows': [],
          'episodes': [
            {
              'episode': {
                'show': {
                  'ids': {'tmdb': 237243, 'mdblist': 'uk-show'},
                },
              },
            },
          ],
          'pagination': {'next_cursor': null},
        });
      }
      expect(r.url.path, '/sync/state/show/mdblist');
      return json({
        'items': [
          {'id': 'uk-show', 'completed': true},
        ],
      });
    });
    final result = await service.fetchCompletedTitleIds();
    expect(result?.movies, {'tmdb:movie:237243'});
    expect(result?.series, {'tmdb:237243'});
  });
}
