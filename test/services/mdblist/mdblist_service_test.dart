import 'dart:convert';

import 'package:debrify/services/episode_tracker_snapshot_revision.dart';
import 'package:debrify/services/mdblist/mdblist_models.dart';
import 'package:debrify/services/mdblist/mdblist_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

MdblistService serviceWith(
  Future<http.Response> Function(http.Request) handler, {
  bool enabled = true,
}) => MdblistService.forTesting(
  client: MockClient(handler),
  apiKeyProvider: () async => 'test-key',
  featureEnabled: () => enabled,
);

void main() {
  setUp(EpisodeTrackerSnapshotRevision.resetForTesting);

  group('MDBList transport error taxonomy', () {
    for (final testCase in <({int status, MdblistResultKind kind})>[
      (status: 401, kind: MdblistResultKind.unauthenticated),
      (status: 403, kind: MdblistResultKind.denied),
      (status: 404, kind: MdblistResultKind.notFound),
      (status: 409, kind: MdblistResultKind.conflict),
      (status: 429, kind: MdblistResultKind.rateLimited),
      (status: 503, kind: MdblistResultKind.transientFailure),
    ]) {
      test('${testCase.status} maps to ${testCase.kind.name}', () async {
        final service = serviceWith(
          (_) async => http.Response(
            '{}',
            testCase.status,
            headers: testCase.status == 429 ? {'retry-after': '12'} : const {},
          ),
        );
        final result = await service.fetchPlaybackSessions();
        expect(result.kind, testCase.kind);
        if (testCase.status == 429) {
          expect(result.retryAfter, const Duration(seconds: 12));
        }
      });
    }

    test('malformed JSON and 200 error envelopes are failures', () async {
      var call = 0;
      final service = serviceWith((_) async {
        call++;
        return call == 1
            ? http.Response('{broken', 200)
            : http.Response(jsonEncode({'error': 'bad key'}), 200);
      });
      expect(
        (await service.fetchPlaybackSessions()).kind,
        MdblistResultKind.malformedResponse,
      );
      expect(
        (await service.fetchPlaybackSessions()).kind,
        MdblistResultKind.malformedResponse,
      );
    });
  });

  group('MDBList list transport', () {
    test('walks next_cursor and merges mixed movie/show pages', () async {
      final seen = <Uri>[];
      final service = serviceWith((request) async {
        seen.add(request.url);
        expect(request.url.queryParameters['apikey'], 'test-key');
        final cursor = request.url.queryParameters['cursor'];
        if (cursor == null) {
          return http.Response(
            jsonEncode({
              'movies': [
                {'imdb_id': 'tt1'},
              ],
              'shows': const [],
              'pagination': {'next_cursor': 'opaque/next+='},
            }),
            200,
          );
        }
        expect(cursor, 'opaque/next+=');
        return http.Response(
          jsonEncode({
            'movies': const [],
            'shows': [
              {'imdb_id': 'tt2'},
            ],
            'pagination': {'next_cursor': null},
          }),
          200,
        );
      });

      final result = await service.fetchListItemsResult(42);

      expect(result.kind, MdblistResultKind.success);
      expect(result.data?['complete'], isTrue);
      expect(result.data?['movies'], hasLength(1));
      expect(result.data?['shows'], hasLength(1));
      expect(seen, hasLength(2));
      expect(seen.last.queryParameters, isNot(contains('offset')));
    });

    test(
      'surfaces a later-page failure as partial and does not cache it',
      () async {
        var firstPageCalls = 0;
        final service = serviceWith((request) async {
          if (!request.url.queryParameters.containsKey('cursor')) {
            firstPageCalls++;
            return http.Response(
              jsonEncode({
                'movies': [
                  {'imdb_id': 'tt1'},
                ],
                'shows': const [],
                'pagination': {'next_cursor': 'next'},
              }),
              200,
            );
          }
          return http.Response('temporarily unavailable', 503);
        });

        final first = await service.fetchListItemsResult(7);
        final second = await service.fetchListItemsResult(7);

        expect(first.kind, MdblistResultKind.partial);
        expect(first.data?['complete'], isFalse);
        expect(second.kind, MdblistResultKind.partial);
        expect(firstPageCalls, 2);
      },
    );

    test('real like and unlike use idempotent endpoint semantics', () async {
      final methods = <String>[];
      final service = serviceWith((request) async {
        methods.add(request.method);
        expect(request.url.path, '/lists/9/like');
        return request.method == 'PUT'
            ? http.Response('{}', 409)
            : http.Response('', 404);
      });

      expect(await service.likeList(9), isTrue);
      expect(await service.unlikeList(9), isTrue);
      expect(methods, ['PUT', 'DELETE']);
    });

    test('feature flag prevents every list network request', () async {
      var calls = 0;
      final service = serviceWith((request) async {
        calls++;
        return http.Response('[]', 200);
      }, enabled: false);

      expect(
        (await service.fetchUserListsResult()).kind,
        MdblistResultKind.disabled,
      );
      expect(
        (await service.fetchListItemsResult(1)).kind,
        MdblistResultKind.disabled,
      );
      expect(await service.likeList(1), isFalse);
      expect(calls, 0);
    });

    test('accepts object and legacy-array create responses', () async {
      var calls = 0;
      final service = serviceWith((request) async {
        calls++;
        return http.Response(
          calls == 1
              ? jsonEncode({'id': 11})
              : jsonEncode([
                  {'id': 12},
                ]),
          201,
        );
      });

      expect(await service.createList('one'), 11);
      expect(await service.createList('two'), 12);
    });

    test('clone rolls back the new list when an item chunk fails', () async {
      final calls = <String>[];
      final service = serviceWith((request) async {
        calls.add('${request.method} ${request.url.path}');
        switch ('${request.method} ${request.url.path}') {
          case 'GET /lists/5/items':
            return http.Response(
              jsonEncode({
                'movies': [
                  {
                    'ids': {'imdb': 'tt1'},
                  },
                ],
                'shows': const [],
                'pagination': {'next_cursor': null},
              }),
              200,
            );
          case 'POST /lists/user/add':
            return http.Response(jsonEncode({'id': 99}), 201);
          case 'POST /lists/99/items/add':
            return http.Response('', 503);
          case 'DELETE /lists/99':
            return http.Response('', 204);
          default:
            return http.Response('', 404);
        }
      });

      expect(
        await service.saveListAsClone(sourceListId: 5, name: 'Copy'),
        isNull,
      );
      expect(calls.last, 'DELETE /lists/99');
    });
  });

  group('MDBList tracker reads', () {
    test('walks every cursor page of a sync snapshot', () async {
      final cursors = <String?>[];
      final service = serviceWith((request) async {
        final cursor = request.url.queryParameters['cursor'];
        cursors.add(cursor);
        return http.Response(
          jsonEncode({
            'movies': [
              {
                'movie': {
                  'ids': {'imdb': cursor == null ? 'tt1' : 'tt2'},
                },
              },
            ],
            'pagination': {'next_cursor': cursor == null ? 'next-page' : null},
          }),
          200,
        );
      });

      final result = await service.fetchSyncSnapshot(
        'watched',
        mediaType: 'movie',
      );

      expect(result.kind, MdblistResultKind.success);
      expect(result.data, hasLength(2));
      expect(cursors, [null, 'next-page']);
    });

    test('later sync snapshot failure is explicitly partial', () async {
      final service = serviceWith((request) async {
        if (request.url.queryParameters['cursor'] != null) {
          return http.Response('', 503);
        }
        return http.Response(
          jsonEncode({
            'shows': [
              {
                'show': {
                  'ids': {'imdb': 'tt1'},
                },
              },
            ],
            'pagination': {'next_cursor': 'next'},
          }),
          200,
        );
      });

      final result = await service.fetchSyncSnapshot('watched');
      expect(result.kind, MdblistResultKind.partial);
      expect(result.data, hasLength(1));
    });

    test(
      'parses calendar events envelope and filters at the model layer',
      () async {
        final service = serviceWith(
          (request) async => http.Response(
            jsonEncode({
              'events': [
                {'type': 'episode', 'show_tmdb': 1},
                {'type': 'movie', 'id': 2},
              ],
            }),
            200,
          ),
        );
        final result = await service.fetchCalendarEvents(
          start: DateTime(2026, 8, 1),
          end: DateTime(2026, 8, 31),
        );
        expect(result.isSuccess, isTrue);
        expect(result.data, hasLength(2));
      },
    );

    test('merges paused and watched episode progress for one show', () async {
      final service = serviceWith((request) async {
        switch (request.url.path) {
          case '/imdb/show/tt-show/':
            return http.Response(
              jsonEncode({
                'ids': {'tmdb': 55},
              }),
              200,
            );
          case '/sync/playback':
            return http.Response(
              jsonEncode([
                {
                  'id': 1,
                  'type': 'episode',
                  'progress': '42.5',
                  'show': {
                    'ids': {'imdb': 'tt-show'},
                  },
                  'episode': {'season': 1, 'number': 2},
                },
              ]),
              200,
            );
          case '/sync/history/show/tmdb/55':
            return http.Response(
              jsonEncode({
                'truncated': false,
                'plays': [
                  {'season_num': 1, 'episode_num': 1},
                ],
              }),
              200,
            );
          default:
            return http.Response('missing', 404);
        }
      });

      final result = await service.fetchShowEpisodeProgress('tt-show');
      expect(result.kind, MdblistResultKind.success);
      expect(result.data, {'1-1': 100.0, '1-2': 42.5});
    });

    test(
      'playback failure keeps watched data partial instead of authoritative',
      () async {
        final service = serviceWith((request) async {
          switch (request.url.path) {
            case '/imdb/show/tt-show/':
              return http.Response(
                jsonEncode({
                  'ids': {'tmdb': 55},
                }),
                200,
              );
            case '/sync/playback':
              return http.Response('', 503);
            case '/sync/history/show/tmdb/55':
              return http.Response(
                jsonEncode({
                  'truncated': false,
                  'plays': [
                    {'season_num': 1, 'episode_num': 1},
                  ],
                }),
                200,
              );
            default:
              return http.Response('missing', 404);
          }
        });

        final result = await service.fetchShowEpisodeProgress('tt-show');

        expect(result.kind, MdblistResultKind.partial);
        expect(result.isComplete, isFalse);
        expect(result.data, {'1-1': 100.0});
      },
    );

    test(
      'title status resolves IMDb to TMDB before the batch state call',
      () async {
        final paths = <String>[];
        final service = serviceWith((request) async {
          paths.add(request.url.path);
          if (request.url.path == '/imdb/movie/tt-movie/') {
            return http.Response(
              jsonEncode({
                'ids': {'tmdb': 99},
              }),
              200,
            );
          }
          return http.Response(
            jsonEncode({
              'items': [
                {
                  'id': 99,
                  'watchlist': true,
                  'rating': 8,
                  'collected': false,
                  'watched': false,
                },
              ],
            }),
            200,
          );
        });
        final status = await service.fetchTitleStatus('tt-movie', 'movie');
        expect(status?.inWatchlist, isTrue);
        expect(status?.rating, 8);
        expect(paths, ['/imdb/movie/tt-movie/', '/sync/state/movie/tmdb']);
      },
    );

    test('episode ratings accept flattened and nested sync shapes', () async {
      final service = serviceWith((request) async {
        expect(request.url.path, '/sync/ratings');
        expect(request.url.queryParameters['mediatype'], 'episode');
        return http.Response(
          jsonEncode({
            'episodes': [
              {
                'ids': {'imdb': 'tt-show'},
                'season': 1,
                'episode': 2,
                'rating': 8,
              },
              {
                'show': {
                  'ids': {'imdb': 'tt-show'},
                  'seasons': [
                    {
                      'number': 3,
                      'episodes': [
                        {'number': 4, 'rating': 9},
                      ],
                    },
                  ],
                },
              },
              {
                'ids': {'imdb': 'tt-other'},
                'season': 1,
                'episode': 1,
                'rating': 10,
              },
            ],
            'pagination': {'next_cursor': null},
          }),
          200,
        );
      });

      final result = await service.fetchShowEpisodeRatings('TT-SHOW');
      expect(result.kind, MdblistResultKind.success);
      expect(result.data, {'1-2': 8, '3-4': 9});
    });
  });

  group('MDBList tracker writes', () {
    test('episode mutations never emit a one-coordinate payload', () async {
      var calls = 0;
      final service = serviceWith((request) async {
        calls++;
        return http.Response('{}', 200);
      });
      const ids = MdblistMediaIds(imdb: 'tt-show');
      expect(await service.markWatched(ids, 'episode', season: 1), isFalse);
      expect(await service.rateTitle(ids, 'episode', 8, episode: 2), isFalse);
      expect(calls, 0);
    });

    test(
      'writes nested episode coordinates and rating to official paths',
      () async {
        final requests = <http.Request>[];
        final service = serviceWith((request) async {
          requests.add(request);
          return http.Response('{}', 200);
        });
        const ids = MdblistMediaIds(imdb: 'tt-show');
        expect(
          await service.rateTitle(ids, 'episode', 9, season: 3, episode: 4),
          isTrue,
        );
        expect(requests.single.url.path, '/sync/ratings');
        final body = jsonDecode(requests.single.body) as Map<String, dynamic>;
        final show = (body['shows'] as List).single as Map<String, dynamic>;
        final season = (show['seasons'] as List).single as Map<String, dynamic>;
        final episode =
            (season['episodes'] as List).single as Map<String, dynamic>;
        expect(season['number'], 3);
        expect(episode['number'], 4);
        expect(episode['rating'], 9);
        expect(episode['rated_at'], isA<String>());
      },
    );

    test(
      'scrobble actions use isolated pause stop and clear endpoints',
      () async {
        final paths = <String>[];
        final service = serviceWith((request) async {
          paths.add(request.url.path);
          return http.Response('{}', 200);
        });
        const target = MdblistScrobbleTarget.movie(
          MdblistMediaIds(imdb: 'tt-movie'),
        );
        await service.scrobblePause(target, 20);
        await service.scrobbleStop(target, 80);
        await service.scrobbleClear(target);
        expect(paths, ['/scrobble/pause', '/scrobble/stop', '/scrobble/clear']);
        expect(service.playbackRevision.value, 3);
      },
    );

    test('successful episode scrobble invalidates guide snapshot', () async {
      final service = serviceWith((_) async => http.Response('{}', 200));
      const target = MdblistScrobbleTarget.episode(
        MdblistMediaIds(imdb: 'tt-show'),
        season: 1,
        episode: 8,
      );

      expect(EpisodeTrackerSnapshotRevision.identity('mdblist', 'tt-show'), 0);
      await service.scrobbleStop(target, 98.5);
      expect(EpisodeTrackerSnapshotRevision.identity('mdblist', 'tt-show'), 1);
    });

    test('failed scrobbles do not publish a playback revision', () async {
      final service = serviceWith((request) async => http.Response('{}', 400));
      const target = MdblistScrobbleTarget.movie(
        MdblistMediaIds(imdb: 'tt-movie'),
      );

      await service.scrobblePause(target, 20);

      expect(service.playbackRevision.value, 0);
    });

    test('scrobble payload limits progress to two decimal places', () async {
      late Map<String, dynamic> body;
      final service = serviceWith((request) async {
        body = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response('{}', 200);
      });
      const target = MdblistScrobbleTarget.movie(
        MdblistMediaIds(imdb: 'tt-movie'),
      );

      await service.scrobblePause(target, 14.257);

      expect(body['progress'], 14.26);
    });
  });
}
