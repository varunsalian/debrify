import 'dart:convert';

import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/secret_vault.dart';
import 'package:debrify/services/simkl/simkl_continue_watching_service.dart';
import 'package:debrify/services/simkl/simkl_service.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Synthetic API responses, not a recording of the user's account. These tests
// cover the reproduced disagreement and conservative stale-session filtering.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final simkl = SimklService.instance;
  const imdb = 'tt7120662';

  setUp(() async {
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    SharedPreferences.setMockInitialValues({});
    SecretVault.debugReset(deviceIdOverride: 'simkl-cw-reproduction');
    simkl.resetProfileScope();
    await StorageService.setSimklAccessToken('synthetic-test-token');
  });

  tearDown(() {
    simkl.resetProfileScope();
    SecretVault.debugReset();
    ProfileRuntime.debugReset();
  });

  for (final status in ['watching', 'completed']) {
    test(
      'completed episode session is reconciled without hiding rewatches ($status)',
      () async {
        var hasPausedSession = true;
        var includeTimes = false;
        var historyFails = false;
        var earlierSession = false;
        String? lastWatched;
        String? watchedAt = '2026-09-11T18:00:00Z';
        String? pausedAt = '2026-09-11T17:00:00Z';
        var hasNextEpisode = false;
        var libraryFails = false;
        final requests = <String>[];
        final show = {
          'title': 'Derry Girls',
          'ids': {'imdb': imdb},
        };
        final client = MockClient((request) async {
          requests.add('${request.method} ${request.url.path}');
          Object body;
          switch (request.url.path) {
            case '/sync/watched':
              if (historyFails) return http.Response('{}', 503);
              body = [
                {
                  'seasons': [
                    for (var season = 1; season <= 3; season++)
                      {
                        'number': season,
                        'episodes': [
                          for (
                            var episode = 1;
                            episode <= (season == 3 ? 7 : 6);
                            episode++
                          )
                            {
                              'number': episode,
                              'watched': true,
                              if (includeTimes) 'last_watched_at': watchedAt,
                            },
                        ],
                      },
                  ],
                },
              ];
            case '/sync/all-items/all/all':
              if (libraryFails) return http.Response('{}', 503);
              body = {
                'shows': [
                  {
                    'show': show,
                    'status': status,
                    'watched_episodes_count': 19,
                    'total_episodes_count': 19,
                    'not_aired_episodes_count': 0,
                    'last_watched': lastWatched,
                    'last_watched_at': watchedAt,
                  },
                ],
              };
            case '/sync/all-items/shows/watching':
              body = {
                'shows': hasNextEpisode
                    ? [
                        {'show': show, 'next_to_watch': 'S04E01'},
                      ]
                    : [],
              };
            case '/sync/playback/episodes':
              body = hasPausedSession
                  ? [
                      {
                        'id': 123,
                        'show': show,
                        'episode': {'season': 3, 'number': 7},
                        'progress': 42,
                        'paused_at': pausedAt,
                      },
                    ]
                  : [];
              if (earlierSession && hasPausedSession) {
                (body as List).add({
                  'id': 124,
                  'show': show,
                  'episode': {'season': 3, 'number': 6},
                  'progress': 30,
                  'paused_at': '2026-09-11T16:00:00Z',
                });
              }
            case '/sync/playback/movies':
              body = [];
            default:
              fail('Unexpected request: ${request.method} ${request.url.path}');
          }
          return http.Response(jsonEncode(body), 200);
        });
        await http.runWithClient(() async {
          // The real SIMKL watched reader returns every episode as completed.
          final watched = await simkl.fetchWatchedShowEpisodes(imdb);
          expect(watched.length, 19);
          expect(watched, contains('3-7'));
          expect(
            (await simkl.fetchCompletedTitleIds())!.series,
            contains(imdb),
          );
          requests.clear();
          final cw = await SimklContinueWatchingService.instance.fetchItems();
          expect(cw!.shows.single.id, imdb);
          expect(cw.shows.single.episode, 7);
          expect(cw.shows.single.progress, 42);
          expect(cw.shows.single.isUpNext, isFalse);
          expect(
            requests.where((r) => r == 'POST /sync/watched'),
            hasLength(1),
          );

          // Watched flags alone are ambiguous. Episode timestamps provide
          // completion evidence for every paused episode, including older ones.
          Future<List<SimklContinueWatchingItem>> refreshShows() async {
            simkl.resetProfileScope();
            return (await SimklContinueWatchingService.instance.fetchItems())!
                .shows;
          }

          lastWatched = 'S03E07';
          includeTimes = true;
          earlierSession = true;
          requests.clear();
          expect(await refreshShows(), isEmpty);
          expect(
            requests.where((r) => r == 'POST /sync/watched'),
            hasLength(1),
          );

          // A genuinely newer rewatch must remain, even on a completed title.
          pausedAt = '2026-09-11T19:00:00Z';
          expect(await refreshShows(), hasLength(1));
          pausedAt = '2026-09-11T18:00:00Z';
          expect(await refreshShows(), hasLength(1)); // equal time is ambiguous
          pausedAt = null;
          expect(await refreshShows(), hasLength(1));
          pausedAt = '2026-09-11T17:00:00Z';
          watchedAt = 'invalid';
          expect(await refreshShows(), hasLength(1));
          watchedAt = '2026-09-11T18:00:00Z';
          lastWatched = 'S03E06';
          expect(
            await refreshShows(),
            isEmpty,
          ); // title-level code is irrelevant
          lastWatched = 'S03E07';
          libraryFails = true;
          expect(
            await refreshShows(),
            isEmpty,
          ); // episode history still proves completion
          libraryFails = false;
          historyFails = true;
          expect(await refreshShows(), hasLength(1));
          historyFails = false;

          // Filtering a stale pause must allow the next episode to surface.
          hasNextEpisode = true;
          final next = await refreshShows();
          expect(next.single.isUpNext, isTrue);
          expect(next.single.season, 4);
          expect(next.single.episode, 1);
          hasNextEpisode = false;

          // Model a server response after its leftover session is cleared.
          // The library is otherwise identical; there are no account writes.
          hasPausedSession = false;
          simkl.resetProfileScope();
          final afterClear = await SimklContinueWatchingService.instance
              .fetchItems();
          expect(afterClear!.shows, isEmpty);
        }, () => client);
      },
    );
  }
}
