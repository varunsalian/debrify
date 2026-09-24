import 'dart:convert';

import 'package:debrify/models/media_identity.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/secret_vault.dart';
import 'package:debrify/services/series_progress_reset_service.dart';
import 'package:debrify/services/simkl/simkl_service.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/services/stremio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final simkl = SimklService.instance;
  setUp(() async {
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    SharedPreferences.setMockInitialValues({});
    SecretVault.debugReset(deviceIdOverride: 'simkl-review-test');
    simkl.resetProfileScope();
  });
  tearDown(() {
    simkl.resetProfileScope();
    SecretVault.debugReset();
    ProfileRuntime.debugReset();
  });

  for (final type in ['series', 'movie']) {
    test(
      'remove $type clears sparse playback before its library alias disappears',
      () async {
        await StorageService.setSimklAccessToken('synthetic');
        var inLibrary = true;
        var paused = true;
        final writes = <String>[];
        final content = type == 'movie' ? 'movie' : 'show';
        final bucket = type == 'movie' ? 'movies' : 'shows';
        await http.runWithClient(
          () async {
            final id = MediaIdentity.progressId('tmdb:42', type);
            expect(await simkl.removeFromListAndPlayback(id, type), isTrue);
            expect(writes, [
              'DELETE /sync/playback/9',
              'POST /sync/history/remove',
            ]);
            expect(paused, isFalse);
            expect(inLibrary, isFalse);
          },
          () => MockClient((request) async {
            if (request.url.path == '/sync/all-items/all/all') {
              return http.Response(
                jsonEncode({
                  bucket: inLibrary
                      ? [
                          {
                            content: {
                              'ids': {'tmdb': 42, 'simkl': 77},
                            },
                            'status': 'watching',
                          },
                        ]
                      : [],
                }),
                200,
              );
            }
            if (request.url.path.startsWith('/sync/playback/') &&
                request.method == 'GET') {
              final matching = request.url.path.endsWith(
                type == 'movie' ? 'movies' : 'episodes',
              );
              return http.Response(
                jsonEncode(
                  matching && paused
                      ? [
                          {
                            'id': 9,
                            content: {
                              'ids': {'simkl': 77},
                            },
                          },
                        ]
                      : [],
                ),
                200,
              );
            }
            writes.add('${request.method} ${request.url.path}');
            if (request.method == 'DELETE') {
              expect(inLibrary, isTrue);
              paused = false;
              return http.Response('', 204);
            }
            expect(jsonDecode(request.body), {
              bucket: [
                {
                  'ids': {'tmdb': 42},
                },
              ],
            });
            inLibrary = false;
            return http.Response(
              jsonEncode({
                'deleted': {bucket: 1},
              }),
              200,
            );
          }),
        );
      },
    );
  }

  for (final failure in ['library', 'playback', 'delete']) {
    test('$failure failure retains the library entry for retry', () async {
      await StorageService.setSimklAccessToken('synthetic');
      var removed = false;
      await http.runWithClient(
        () async {
          expect(
            await simkl.removeFromListAndPlayback('tmdb:42', 'series'),
            isFalse,
          );
          expect(removed, isFalse);
        },
        () => MockClient((request) async {
          if (request.url.path == '/sync/history/remove') {
            removed = true;
            return http.Response('{"deleted":{"shows":1}}', 200);
          }
          if (request.url.path == '/sync/all-items/all/all') {
            return http.Response(
              jsonEncode({
                'shows': [
                  {
                    'show': {
                      'ids': {'tmdb': 42, 'simkl': 77},
                    },
                  },
                ],
              }),
              failure == 'library' ? 503 : 200,
            );
          }
          if (request.method == 'DELETE') return http.Response('', 503);
          if (request.url.path.endsWith('/episodes')) {
            return http.Response(
              jsonEncode([
                {
                  'id': 9,
                  'show': {
                    'ids': {'simkl': 77},
                  },
                },
              ]),
              failure == 'playback' ? 503 : 200,
            );
          }
          return http.Response('[]', 200);
        }),
      );
    });
  }

  const movie = StremioMeta(id: 'tmdb:42', type: 'movie', name: 'Movie');
  const series = StremioMeta(id: 'tmdb:42', type: 'series', name: 'Series');
  Future<void> saveBoth() async {
    expect(movie.progressId, 'tmdb:movie:42');
    expect(series.progressId, 'tmdb:42');
    for (final item in [movie, series]) {
      // Even callers with a raw catalog ID get a type-aware CW key.
      await StorageService.saveContinueWatchingItem(
        imdbId: item.id,
        title: item.name,
        contentType: item.type,
      );
    }
    await StorageService.saveSeriesPlaybackState(
      seriesTitle: series.name,
      season: 4,
      episode: 6,
      positionMs: 500,
      durationMs: 1000,
      imdbId: series.progressId,
    );
    await StorageService.saveVideoPlaybackState(
      videoTitle: movie.name,
      videoUrl: 'https://fixture.invalid/movie',
      positionMs: 300,
      durationMs: 1000,
      imdbId: movie.progressId,
    );
    expect(
      (await StorageService.getContinueWatchingItems())
          .map((e) => e['imdbId'])
          .toSet(),
      {'tmdb:movie:42', 'tmdb:42'},
    );
  }

  test(
    'resetting a native movie leaves same-number TV history and CW intact',
    () async {
      await saveBoth();
      expect(
        await SeriesProgressResetService.clear(
          movie.id,
          movie.name,
          isMovie: true,
        ),
        isEmpty,
      );
      expect(
        (await StorageService.getContinueWatchingItems()).single['imdbId'],
        series.progressId,
      );
      expect(
        (await StorageService.getLastPlayedEpisodeByImdbId(
          series.progressId!,
        ))?['season'],
        4,
      );
      expect(
        await StorageService.getVideoPlaybackState(
          videoTitle: movie.name,
          contentIdentity: movie.progressId,
        ),
        isNull,
      );
    },
  );

  test(
    'resetting native TV leaves same-number movie history and CW intact',
    () async {
      await saveBoth();
      expect(
        await SeriesProgressResetService.clear(series.id, series.name),
        isEmpty,
      );
      expect(
        (await StorageService.getContinueWatchingItems()).single['imdbId'],
        movie.progressId,
      );
      expect(
        await StorageService.getVideoPlaybackState(
          videoTitle: movie.name,
          contentIdentity: movie.progressId,
        ),
        isNotNull,
      );
    },
  );

  test(
    'finishing a native movie does not clear same-number series progress',
    () async {
      await saveBoth();
      await StorageService.markMovieAsFinished(' TMDB:42 ');
      expect(await StorageService.isMovieFinished(movie.id), isTrue);
      expect(
        (await StorageService.getLastPlayedEpisodeByImdbId(
          series.progressId!,
        ))?['season'],
        4,
      );
      expect(
        (await StorageService.getContinueWatchingItems()).single['imdbId'],
        series.progressId,
      );
    },
  );

  test(
    'movie progress keys use ordinary IDs at Simkl and addon boundaries',
    () async {
      await StorageService.setSimklAccessToken('synthetic');
      expect(MediaIdentity.apiIds(movie.progressId!), {'tmdb': 42});
      await http.runWithClient(
        () async {
          expect(await simkl.scrobbleStart(movie.progressId!, 25), isTrue);
          await StremioService.instance.fetchStreamsForContentId(
            StremioAddon(
              id: 'fixture',
              name: 'Fixture',
              baseUrl: 'https://fixture.invalid',
              manifestUrl: '',
            ),
            'movie',
            movie.progressId!,
          );
        },
        () => MockClient((request) async {
          if (request.url.host == 'fixture.invalid') {
            expect(request.url.pathSegments.last, 'tmdb:42.json');
            return http.Response('{"streams":[]}', 200);
          }
          expect(jsonDecode(request.body)['movie']['ids'], {'tmdb': 42});
          return http.Response('{"action":"start"}', 200);
        }),
      );
    },
  );
}
