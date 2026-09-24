import 'dart:convert';
import 'package:debrify/models/media_identity.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/secret_vault.dart';
import 'package:debrify/services/simkl/simkl_continue_watching_service.dart';
import 'package:debrify/services/simkl/simkl_item_transformer.dart';
import 'package:debrify/services/simkl/simkl_service.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/services/tracking_source_policy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final simkl = SimklService.instance;
  // Public identity from GET /tv/2274121; account history below is synthetic.
  const show = {
    'title': 'Big Brother',
    'year': 2023,
    'ids': {'simkl': 2274121, 'tmdb': '237243', 'tvdb': '440642'},
  };
  setUp(() async {
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    SharedPreferences.setMockInitialValues({});
    SecretVault.debugReset(deviceIdOverride: 'native-simkl-test');
    simkl.resetProfileScope();
    await StorageService.setSimklAccessToken('synthetic');
  });
  tearDown(() {
    simkl.resetProfileScope();
    SecretVault.debugReset();
    ProfileRuntime.debugReset();
  });

  test('native IDs are retained without inventing IMDb or metahub artwork', () {
    final item = SimklItemTransformer.transformItem({'show': show})!;
    expect(item.id, 'tmdb:237243');
    expect(item.imdbId, isNull);
    expect(item.effectiveImdbId, isNull);
    expect(item.progressId, 'tmdb:237243');
    expect(item.poster, isNull);
    expect(MediaIdentity.apiIds(item.id), {'tmdb': 237243});
    expect(MediaIdentity.preferred({'imdb': 'tt123', 'tmdb': 1}), 'tt123');
    expect(
      MediaIdentity.preferred({'imdb': 'ttwrong', 'tmdb': -1, 'simkl': 3}),
      'simkl:3',
    );
    expect(MediaIdentity.preferred({'tmdb': 1.5}), isNull);
    expect(() => MediaIdentity.apiIds('custom:1'), throwsArgumentError);
  });

  test(
    'paused and next rows join sparse aliases without colliding with movies',
    () async {
      final client = MockClient((request) async {
        final Object body;
        switch (request.url.path) {
          case '/sync/all-items/all/all':
            body = {
              'shows': [
                {'show': show, 'status': 'watching'},
              ],
              'movies': [
                {
                  'movie': {
                    'title': 'Different movie',
                    'ids': {'tmdb': 237243},
                  },
                  'status': 'hold',
                },
              ],
            };
          case '/sync/playback/episodes':
            body = [
              {
                'id': 99,
                'show': {
                  'ids': {'simkl': 2274121},
                },
                'episode': {'season': 4, 'number': 6},
                'progress': 42,
                'paused_at': '2026-09-24T01:00:00Z',
              },
            ];
          case '/sync/playback/movies':
            body = [];
          case '/sync/all-items/shows/watching':
            body = {
              'shows': [
                {'show': show, 'next_to_watch': 'S04E07'},
              ],
            };
          case '/sync/watched':
            expect(jsonDecode(request.body), [
              {'tmdb': 237243, 'type': 'show'},
            ]);
            body = [
              {'tmdb': 237243, 'result': true, 'seasons': []},
            ];
          default:
            throw StateError('Unexpected ${request.url}');
        }
        return http.Response(jsonEncode(body), 200);
      });
      await http.runWithClient(() async {
        final result = (await SimklContinueWatchingService.instance
            .fetchItems())!;
        expect(result.shows, hasLength(1));
        final entry = result.shows.single;
        expect(entry.id, 'tmdb:237243');
        expect(entry.meta.name, 'Big Brother');
        expect(entry.season, 4);
        expect(entry.episode, 6);
        expect(entry.progress, 42);
        expect(entry.isUpNext, isFalse);
        expect((await simkl.fetchShowPlaybackSelection(entry.id))?.episode, 6);
        expect(await simkl.fetchEpisodePlaybackProgress(entry.id), {
          '4-6': 42.0,
        });
        expect(await simkl.fetchNextToWatch(entry.id), (season: 4, episode: 7));
        final selection = SimklContinueWatchingService.instance
            .selectionForItem(entry);
        expect(selection.imdbId, entry.id);
        expect(selection.hasStremioEpisodeIdentity, isFalse);
      }, () => client);
    },
  );

  test(
    'watched reads use flat native IDs; unmatched is not empty history',
    () async {
      var notFound = false;
      await http.runWithClient(
        () async {
          expect(await simkl.fetchWatchedShowEpisodesOrNull('tmdb:237243'), {
            '4-5',
          });
          notFound = true;
          expect(
            await simkl.fetchWatchedShowEpisodesOrNull('tmdb:237243'),
            isNull,
          );
        },
        () => MockClient((request) async {
          expect(jsonDecode(request.body), [
            {'tmdb': 237243, 'type': 'show'},
          ]);
          return http.Response(
            jsonEncode([
              {
                'result': notFound ? 'not_found' : true,
                'seasons': [
                  {
                    'number': 4,
                    'episodes': [
                      {'number': 5, 'watched': true},
                    ],
                  },
                ],
              },
            ]),
            200,
          );
        }),
      );
    },
  );

  test(
    'native scrobble preserves provider namespace and episode coordinates',
    () async {
      await http.runWithClient(
        () async {
          await simkl.scrobbleStart('tmdb:237243', 25, season: 4, episode: 6);
        },
        () => MockClient((request) async {
          final body = jsonDecode(request.body);
          expect(body['show']['ids'], {'tmdb': 237243});
          expect(body['episode'], {'season': 4, 'number': 6});
          return http.Response('{"action":"start"}', 200);
        }),
      );
    },
  );

  test(
    'revival progress never borrows or overwrites the same-title original',
    () async {
      await StorageService.saveSeriesPlaybackState(
        seriesTitle: 'Big Brother',
        season: 20,
        episode: 6,
        positionMs: 1000,
        durationMs: 10000,
        imdbId: 'tt0251497',
      );
      expect(
        await StorageService.getMergedEpisodeProgress(
          seriesTitle: 'Big Brother',
          imdbId: 'tmdb:237243',
        ),
        isEmpty,
      );
      await StorageService.saveSeriesPlaybackState(
        seriesTitle: 'Big Brother',
        season: 4,
        episode: 6,
        positionMs: 2000,
        durationMs: 10000,
        imdbId: 'tmdb:237243',
      );
      expect(
        (await StorageService.getLastPlayedEpisodeByImdbId(
          'tt0251497',
        ))?['season'],
        20,
      );
      expect(
        (await StorageService.getLastPlayedEpisodeByImdbId(
          'tmdb:237243',
        ))?['season'],
        4,
      );
      final original = await StorageService.getMergedEpisodeProgress(
        seriesTitle: 'Big Brother',
        imdbId: 'tt0251497',
      );
      expect(original.keys, isNot(contains('4-6')));
    },
  );

  test('status and removal distinguish TMDB movies from shows', () async {
    final deleted = <String>[];
    await http.runWithClient(
      () async {
        expect(
          (await simkl.fetchTitleStatus(
            'tmdb:237243',
            contentType: 'series',
          ))?.currentStatus,
          'watching',
        );
        expect(
          (await simkl.fetchTitleStatus(
            'tmdb:237243',
            contentType: 'movie',
          ))?.currentStatus,
          'completed',
        );
        expect(
          await simkl.deletePlaybackForImdb(
            'tmdb:237243',
            contentType: 'series',
          ),
          isTrue,
        );
        expect(deleted, ['/sync/playback/1']);
      },
      () => MockClient((request) async {
        if (request.method == 'DELETE') {
          deleted.add(request.url.path);
          return http.Response('', 204);
        }
        Object body;
        switch (request.url.path) {
          case '/sync/all-items/all/all':
            body = {
              'shows': [
                {'show': show, 'status': 'watching'},
              ],
              'movies': [
                {
                  'movie': {
                    'ids': {'tmdb': 237243},
                  },
                  'status': 'completed',
                },
              ],
            };
          case '/sync/playback/episodes':
            body = [
              {
                'id': 1,
                'show': {
                  'ids': {'simkl': 2274121},
                },
              },
            ];
          case '/sync/playback/movies':
            body = [
              {
                'id': 2,
                'movie': {
                  'ids': {'tmdb': 237243},
                },
              },
            ];
          default:
            throw StateError('Unexpected request');
        }
        return http.Response(jsonEncode(body), 200);
      }),
    );
  });

  test('native tracking excludes IMDb-only destinations', () {
    const original = TrackingSourcePolicy(
      scrobbleTargets: {
        TrackingSource.trakt,
        TrackingSource.simkl,
        TrackingSource.mdblist,
      },
      progressSource: WatchProgressSource.smart,
      homeTickSources: {TrackingSource.trakt, TrackingSource.simkl},
    );
    final policy = original.forContent('tmdb:237243');
    expect(policy.scrobbles(TrackingSource.simkl), isTrue);
    expect(policy.scrobbles(TrackingSource.trakt), isFalse);
    expect(policy.progressFrom(TrackingSource.trakt), isFalse);
    expect(policy.progressFrom(TrackingSource.simkl), isTrue);
  });
}
