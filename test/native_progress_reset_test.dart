import 'dart:convert';

import 'package:debrify/models/tracking_source.dart';
import 'package:debrify/services/mdblist/mdblist_service.dart';
import 'package:debrify/services/local_series_completion_service.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/secret_vault.dart';
import 'package:debrify/services/series_progress_reset_service.dart';
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

Map<String, dynamic> playback(int id, int tmdb, {required bool movie}) => {
  'id': id,
  'type': movie ? 'movie' : 'episode',
  (movie ? 'movie' : 'show'): {
    'title': 'Big Brother',
    'ids': {'tmdb': tmdb},
  },
  if (!movie) 'episode': {'season': 4, 'number': 6},
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    SharedPreferences.setMockInitialValues({});
    SecretVault.debugReset(deviceIdOverride: 'native-reset-test');
    TraktService.instance.resetProfileScope();
    await StorageService.setTraktSession(
      accessToken: 'test-access',
      refreshToken: 'test-refresh',
      expiryMs: 9000000000000,
    );
    // An explicit reset must still run with scrobbling disabled.
    await StorageService.setTrackingScrobbleTargets({TrackingSource.local});
  });
  tearDown(() {
    TraktService.instance.resetProfileScope();
    SecretVault.debugReset();
    ProfileRuntime.debugReset();
  });

  for (final provider in [TrackingSource.trakt, TrackingSource.mdblist]) {
    for (final movie in [false, true]) {
      for (final id in [
        movie ? 'tmdb:movie:237243' : 'tmdb:237243',
        'simkl:990201',
      ]) {
        test(
          '$provider resets $id movie=$movie without crossing identities',
          () async {
            await StorageService.saveEpisodeTraktProgress(
              imdbId: id,
              percents: {'4_6': 100},
            );
            await StorageService.saveEpisodeMdblistProgress(
              imdbId: id,
              percents: {'4_6': 100},
            );
            final writes = <http.Request>[];
            final client = MockClient((request) async {
              if (request.url.host == 'api.simkl.com') {
                expect(request.url.path, '${movie ? '/movies' : '/tv'}/990201');
                return json({
                  'type': movie ? 'movie' : 'show',
                  'ids': {'simkl': 990201, 'tmdb': 237243},
                });
              }
              expect(request.url.host, contains(provider.name));
              if (request.method == 'GET') {
                return json([
                  playback(12, 237243, movie: movie),
                  playback(99, 10160, movie: movie),
                  // TMDB TV and movie IDs are separate namespaces.
                  playback(98, 237243, movie: !movie),
                ]);
              }
              writes.add(request);
              return request.method == 'DELETE'
                  ? http.Response('', 204)
                  : json({});
            });
            final mdblist = MdblistService.forTesting(
              client: client,
              apiKeyProvider: () async => 'test-key',
            );
            await http.runWithClient(() async {
              expect(
                await SeriesProgressResetService.clearProvider(
                  id,
                  'Big Brother',
                  provider: provider,
                  isMovie: movie,
                  mdblistService: mdblist,
                ),
                isEmpty,
              );
            }, () => client);

            expect(writes, hasLength(2));
            if (provider == TrackingSource.trakt) {
              expect(writes.first.method, 'DELETE');
              expect(writes.first.url.path, '/sync/playback/12');
              expect(writes.last.url.path, '/sync/history/remove');
            } else {
              expect(writes.first.url.path, '/scrobble/clear');
              expect(jsonDecode(writes.first.body), {
                (movie ? 'movie' : 'show'): {
                  'ids': {'tmdb': 237243},
                  if (!movie) ...{'season': 4, 'episode': 6},
                },
                'progress': 0,
              });
              expect(writes.last.url.path, '/sync/watched/remove');
            }
            expect(jsonDecode(writes.last.body), {
              (movie ? 'movies' : 'shows'): [
                {
                  'ids': {'tmdb': 237243},
                },
              ],
            });
            expect(
              await StorageService.getEpisodeTraktProgress(imdbId: id),
              !movie && provider == TrackingSource.trakt
                  ? isEmpty
                  : {'4_6': 100},
            );
            expect(
              await StorageService.getEpisodeMdblistProgress(imdbId: id),
              !movie && provider == TrackingSource.mdblist
                  ? isEmpty
                  : {'4_6': 100},
            );
          },
        );
      }
    }

    test(
      '$provider missing native mapping reports failure without mutations',
      () async {
        final client = MockClient((request) async {
          expect(request.method, 'GET');
          expect(request.url.host, 'api.simkl.com');
          return json({
            'type': 'show',
            'ids': {'simkl': 990202},
          });
        });
        await http.runWithClient(() async {
          expect(
            await SeriesProgressResetService.clearProvider(
              'simkl:990202',
              'Big Brother',
              provider: provider,
              isMovie: false,
              mdblistService: MdblistService.forTesting(
                client: client,
                apiKeyProvider: () async => 'test-key',
              ),
            ),
            [provider == TrackingSource.trakt ? 'Trakt' : 'MDBList'],
          );
        }, () => client);
      },
    );

    test(
      '$provider failed native playback deletion preserves cached progress',
      () async {
        await StorageService.saveEpisodeTraktProgress(
          imdbId: 'tmdb:237243',
          percents: {'4_6': 100},
        );
        await StorageService.saveEpisodeMdblistProgress(
          imdbId: 'tmdb:237243',
          percents: {'4_6': 100},
        );
        final client = MockClient((request) async {
          if (request.method == 'GET') {
            return json([playback(12, 237243, movie: false)]);
          }
          if (request.url.path.endsWith('/remove')) return json({});
          return json({}, 503);
        });
        await http.runWithClient(() async {
          expect(
            await SeriesProgressResetService.clearProvider(
              'tmdb:237243',
              'Big Brother',
              provider: provider,
              isMovie: false,
              mdblistService: MdblistService.forTesting(
                client: client,
                apiKeyProvider: () async => 'test-key',
              ),
            ),
            [provider == TrackingSource.trakt ? 'Trakt' : 'MDBList'],
          );
        }, () => client);
        expect(
          await StorageService.getEpisodeTraktProgress(imdbId: 'tmdb:237243'),
          {'4_6': 100},
        );
        expect(
          await StorageService.getEpisodeMdblistProgress(imdbId: 'tmdb:237243'),
          {'4_6': 100},
        );
      },
    );
  }

  test(
    'global native reset includes connected Trakt with scrobbling disabled',
    () async {
      final paths = <String>[];
      await http.runWithClient(
        () async {
          expect(
            await SeriesProgressResetService.clear(
              'tmdb:237243',
              'Big Brother',
            ),
            isEmpty,
          );
        },
        () => MockClient((request) async {
          expect(request.url.host, 'api.trakt.tv');
          paths.add(request.url.path);
          return request.method == 'GET' ? json([]) : json({});
        }),
      );
      // Drain the reset's local-completion revision listener before teardown.
      await LocalSeriesCompletionService.instance.caughtUpIds();
      expect(paths, ['/sync/playback/episodes', '/sync/history/remove']);
    },
  );
}
