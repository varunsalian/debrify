import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/widgets/clear_provider_progress_dialog.dart';
import 'package:debrify/models/tracking_source.dart';
import 'package:debrify/services/series_progress_reset_service.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/services/mdblist/mdblist_service.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    SharedPreferences.setMockInitialValues({
      'trakt_access_token': 'token',
      'simkl_access_token': 'token',
      'series_source_tt001': 'keep',
    });
  });
  tearDown(ProfileRuntime.debugReset);

  for (final provider in [
    TrackingSource.trakt,
    TrackingSource.simkl,
    TrackingSource.mdblist,
  ]) {
    testWidgets('$provider confirmation can cancel without changing anything', (
      tester,
    ) async {
      var calls = 0;
      await http.runWithClient(
        () async {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: Builder(
                  builder: (context) => TextButton(
                    onPressed: () => showClearProviderProgressDialog(
                      context,
                      const StremioMeta(
                        id: 'tt001',
                        type: 'movie',
                        name: 'Movie',
                      ),
                      provider,
                    ),
                    child: const Text('Reset'),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('Reset'));
          await tester.pumpAndSettle();
          expect(
            find.textContaining(
              'Local progress and other trackers will not be changed',
            ),
            findsOneWidget,
          );
          if (provider == TrackingSource.simkl)
            expect(
              find.textContaining('removes the movie from its library'),
              findsOneWidget,
            );
          await tester.tap(find.text('Cancel'));
          await tester.pumpAndSettle();
        },
        () => MockClient((_) async {
          calls++;
          return http.Response('{}', 503);
        }),
      );
      expect(calls, 0);
    });

    test('$provider reset reports provider failure', () async {
      final client = MockClient((request) async {
        expect(request.url.host, contains(provider.name));
        return http.Response('{}', 503);
      });
      await http.runWithClient(() async {
        final result = await SeriesProgressResetService.clearProvider(
          'tt001',
          'Show',
          provider: provider,
          isMovie: false,
          mdblistService: MdblistService.forTesting(
            client: client,
            apiKeyProvider: () async => 'key',
          ),
        );
        expect(result.map((e) => e.toLowerCase()), [provider.name]);
      }, () => client);
    });
  }

  for (final provider in [
    TrackingSource.trakt,
    TrackingSource.simkl,
    TrackingSource.mdblist,
  ]) {
    for (final movie in [false, true]) {
      test(
        '$provider reset movie=$movie touches only requested provider',
        () async {
          await StorageService.saveVideoPlaybackState(
            videoTitle: 'Show',
            videoUrl: 'https://test/video',
            positionMs: 1234,
            durationMs: 10000,
            imdbId: 'tt001',
          );
          await StorageService.saveEpisodeTraktProgress(
            imdbId: 'tt001',
            percents: {'1_1': 50},
          );
          await StorageService.saveEpisodeSimklProgress(
            imdbId: 'tt001',
            percents: {'1_1': 60},
          );
          await StorageService.saveEpisodeMdblistProgress(
            imdbId: 'tt001',
            percents: {'1_1': 70},
          );
          final prefs = await SharedPreferences.getInstance();
          final local = prefs.getString('playback_state_v1');
          final requests = <http.Request>[];
          final client = MockClient((request) async {
            requests.add(request);
            expect(request.url.host, contains(provider.name));
            if (request.method == 'GET' &&
                request.url.path.startsWith('/sync/playback')) {
              final appropriate =
                  !request.url.path.endsWith('/movies') || movie;
              return http.Response(
                jsonEncode(
                  appropriate
                      ? [
                          {
                            'id': 12,
                            'type': movie ? 'movie' : 'episode',
                            (movie ? 'movie' : 'show'): {
                              'ids': {'imdb': 'tt001'},
                            },
                            if (!movie) 'episode': {'season': 1, 'number': 1},
                          },
                          {
                            'id': 99,
                            (movie ? 'movie' : 'show'): {
                              'ids': {'imdb': 'tt999'},
                            },
                          },
                        ]
                      : [],
                ),
                200,
              );
            }
            if (request.method == 'DELETE') {
              expect(request.url.path, '/sync/playback/12');
              return http.Response('', 204);
            }
            if (request.url.path == '/sync/watched' &&
                provider == TrackingSource.simkl) {
              return http.Response(
                '[{"seasons":[{"number":1,"episodes":[{"number":1,"watched":true}]}]}]',
                200,
              );
            }
            if (request.url.path.endsWith('/remove')) {
              final body = jsonDecode(request.body) as Map;
              expect(body.containsKey(movie ? 'movies' : 'shows'), isTrue);
            }
            return http.Response('{}', 200);
          });
          final mdblist = MdblistService.forTesting(
            client: client,
            apiKeyProvider: () async => 'key',
          );
          await http.runWithClient(() async {
            expect(
              await SeriesProgressResetService.clearProvider(
                'tt001',
                'Show',
                provider: provider,
                isMovie: movie,
                mdblistService: mdblist,
              ),
              isEmpty,
            );
          }, () => client);
          expect(requests, isNotEmpty);
          expect(prefs.getString('playback_state_v1'), local);
          expect(prefs.getString('series_source_tt001'), 'keep');
          if (provider != TrackingSource.trakt || movie)
            expect(
              await StorageService.getEpisodeTraktProgress(imdbId: 'tt001'),
              {'1_1': 50},
            );
          if (provider != TrackingSource.simkl || movie)
            expect(
              await StorageService.getEpisodeSimklProgress(imdbId: 'tt001'),
              {'1_1': 60},
            );
          if (provider != TrackingSource.mdblist || movie)
            expect(
              await StorageService.getEpisodeMdblistProgress(imdbId: 'tt001'),
              {'1_1': 70},
            );
        },
      );
    }
  }
}
