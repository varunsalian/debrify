import 'dart:async';
import 'dart:convert';

import 'package:debrify/models/advanced_search_selection.dart';
import 'package:debrify/services/mdblist/mdblist_continue_watching_service.dart';
import 'package:debrify/services/mdblist/mdblist_models.dart';
import 'package:debrify/services/mdblist/mdblist_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

MdblistContinueWatchingService _service(
  Future<http.Response> Function(http.Request) handler,
) => MdblistContinueWatchingService.forTesting(
  MdblistService.forTesting(
    client: MockClient(handler),
    apiKeyProvider: () async => 'key',
    featureEnabled: () => true,
  ),
);

void main() {
  test('newest paused episode wins over older pause and Up Next', () async {
    final service = _service((request) async {
      if (request.url.path == '/sync/playback') {
        return http.Response(
          jsonEncode([
            {
              'id': 1,
              'type': 'episode',
              'progress': 20,
              'paused_at': '2026-08-20T00:00:00Z',
              'show': {
                'title': 'Show',
                'ids': {'imdb': 'tt-show'},
              },
              'episode': {'season': 1, 'number': 2},
            },
            {
              'id': 2,
              'type': 'episode',
              'progress': '45.5',
              'paused_at': '2026-08-21T00:00:00Z',
              'show': {
                'title': 'Show',
                'ids': {'imdb': 'tt-show'},
              },
              'episode': {'season': 1, 'number': 3},
            },
          ]),
          200,
        );
      }
      return http.Response(
        jsonEncode({
          'items': [
            {
              'show': {
                'title': 'Show',
                'ids': {'imdb': 'tt-show'},
              },
              'next_episode': {'season': 1, 'number': 4},
            },
          ],
          'has_more': false,
        }),
        200,
      );
    });

    final result = await service.fetch();
    expect(result.kind, MdblistResultKind.success);
    expect(result.data!.shows, hasLength(1));
    expect(result.data!.shows.single.paused, isTrue);
    expect(result.data!.shows.single.selection.episode, 3);
    expect(result.data!.shows.single.selection.mdblistProgressPercent, 45.5);
  });

  test(
    'completed stale playback advances using MDBList season inventory',
    () async {
      final service = _service((request) async {
        if (request.url.path == '/sync/playback') {
          return http.Response(
            jsonEncode([
              {
                'id': 6,
                'type': 'episode',
                'progress': 51.6,
                'show': {
                  'title': 'Narcos',
                  'ids': {'imdb': 'tt2707408'},
                },
                'episode': {'season': 1, 'number': 6},
              },
            ]),
            200,
          );
        }
        if (request.url.path == '/sync/watched') {
          return http.Response(
            jsonEncode({
              'episodes': [
                {
                  'episode': {
                    'season': 1,
                    'number': 6,
                    'show': {
                      'title': 'Narcos',
                      'ids': {'imdb': 'tt2707408'},
                    },
                  },
                },
              ],
              'pagination': {'has_more': false},
            }),
            200,
          );
        }
        if (request.url.path == '/imdb/show/tt2707408/') {
          return http.Response(
            jsonEncode({
              'seasons': [
                {'season_number': 1, 'aired_episode_count': 10},
              ],
            }),
            200,
          );
        }
        return http.Response(jsonEncode({'items': [], 'has_more': false}), 200);
      });

      final result = await service.fetch(force: true);

      expect(result.isSuccess, isTrue);
      expect(result.data!.shows, hasLength(1));
      expect(result.data!.shows.single.paused, isFalse);
      expect(result.data!.shows.single.selection.season, 1);
      expect(result.data!.shows.single.selection.episode, 7);
    },
  );

  test(
    'transient refresh failure returns the previous snapshot as partial',
    () async {
      var failing = false;
      final service = _service((request) async {
        if (failing) return http.Response('', 503);
        if (request.url.path == '/sync/playback') {
          return http.Response(
            jsonEncode([
              {
                'id': 4,
                'type': 'movie',
                'progress': 30,
                'movie': {
                  'title': 'Movie',
                  'ids': {'imdb': 'tt-movie'},
                },
              },
            ]),
            200,
          );
        }
        return http.Response(jsonEncode({'items': [], 'has_more': false}), 200);
      });
      expect((await service.fetch(force: true)).isSuccess, isTrue);
      failing = true;
      final stale = await service.fetch(force: true);
      expect(stale.kind, MdblistResultKind.partial);
      expect(stale.data!.movies.single.selection.imdbId, 'tt-movie');
    },
  );

  test(
    'incomplete watched history never publishes paused playback as truth',
    () async {
      var failWatched = false;
      var playbackEpisode = 2;
      final service = _service((request) async {
        if (request.url.path == '/sync/playback') {
          return http.Response(
            jsonEncode([
              {
                'id': playbackEpisode,
                'type': 'episode',
                'progress': 40,
                'show': {
                  'title': 'Show',
                  'ids': {'imdb': 'tt-show'},
                },
                'episode': {'season': 1, 'number': playbackEpisode},
              },
            ]),
            200,
          );
        }
        if (request.url.path == '/sync/watched') {
          return failWatched
              ? http.Response('', 503)
              : http.Response(
                  jsonEncode({
                    'episodes': <Object?>[],
                    'pagination': {'has_more': false},
                  }),
                  200,
                );
        }
        return http.Response(jsonEncode({'items': [], 'has_more': false}), 200);
      });

      final first = await service.fetch(force: true);
      expect(first.isSuccess, isTrue);
      expect(first.data!.shows.single.selection.episode, 2);

      failWatched = true;
      playbackEpisode = 3;
      final retained = await service.fetch(force: true);
      expect(retained.kind, MdblistResultKind.partial);
      expect(retained.data!.shows.single.selection.episode, 2);
    },
  );

  test(
    'watched-history failure without last-good returns no snapshot',
    () async {
      final service = _service((request) async {
        if (request.url.path == '/sync/playback') {
          return http.Response('[]', 200);
        }
        if (request.url.path == '/sync/watched') {
          return http.Response('', 503);
        }
        return http.Response(jsonEncode({'items': [], 'has_more': false}), 200);
      });

      final result = await service.fetch(force: true);
      expect(result.kind, MdblistResultKind.transientFailure);
      expect(result.data, isNull);
    },
  );

  test(
    'invalidation prevents an in-flight snapshot from becoming cache',
    () async {
      final firstPlayback = Completer<http.Response>();
      var playbackCalls = 0;
      final service = _service((request) async {
        if (request.url.path == '/sync/playback') {
          playbackCalls++;
          if (playbackCalls == 1) return firstPlayback.future;
          return http.Response('[]', 200);
        }
        return http.Response(jsonEncode({'items': [], 'has_more': false}), 200);
      });

      final staleFetch = service.fetch(force: true);
      await Future<void>.delayed(Duration.zero);
      service.invalidate();
      firstPlayback.complete(http.Response('[]', 200));
      expect((await staleFetch).isSuccess, isTrue);

      // If the pre-invalidation request had repopulated the cache, this would
      // return without issuing a second playback read.
      expect((await service.fetch()).isSuccess, isTrue);
      expect(playbackCalls, 2);
    },
  );

  test('clear is allowed only for paused rows', () async {
    var calls = 0;
    final service = _service((request) async {
      calls++;
      return http.Response('{}', 200);
    });
    const upNext = MdblistContinueWatchingItem(
      selection: AdvancedSearchSelection(
        imdbId: 'tt-show',
        isSeries: true,
        title: 'Show',
        season: 1,
        episode: 2,
      ),
      paused: false,
    );
    expect(await service.clear(upNext), isFalse);
    expect(calls, 0);
  });
}
