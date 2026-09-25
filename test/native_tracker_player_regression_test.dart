import 'dart:async';
import 'dart:convert';

import 'package:debrify/screens/video_player/models/playlist_entry.dart';
import 'package:debrify/services/debrify_tv_database.dart';
import 'package:debrify/services/iptv_media_store.dart';
import 'package:debrify/services/mdblist/mdblist_service.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/secret_vault.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/services/tracking_source_policy.dart';
import 'package:debrify/services/trakt/trakt_service.dart';
import 'package:debrify/services/video_player_launcher.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);
  setUp(() async {
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    SharedPreferences.setMockInitialValues({});
    SecretVault.debugReset(deviceIdOverride: 'native-player-review-test');
    TraktService.instance.resetProfileScope();
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
    IptvMediaStore.debugResetMigration();
    DebrifyTvDatabase.debugDatabaseOverride = await databaseFactoryFfiNoIsolate
        .openDatabase(
          inMemoryDatabasePath,
          options: OpenDatabaseOptions(
            version: 1,
            onCreate: (db, _) => DebrifyTvDatabase.createIptvStoreTables(db),
          ),
        );
  });
  tearDown(() async {
    await DebrifyTvDatabase.debugDatabaseOverride?.close();
    DebrifyTvDatabase.debugDatabaseOverride = null;
    IptvMediaStore.debugResetMigration();
    TraktService.instance.resetProfileScope();
    SecretVault.debugReset();
    ProfileRuntime.debugReset();
  });

  for (final threshold in [60, 80]) {
    for (final id in ['tmdb:movie:237243', 'tt1234567']) {
      test(
        '$id local completion at $threshold still delivers remote completion',
        () async {
          await StorageService.setMovieCompletionThreshold(threshold);
          // Local mode also covers the existing IMDb local + remote combination.
          if (id.startsWith('tt')) {
            await StorageService.setWatchProgressSource(
              WatchProgressSource.local,
            );
          }
          final traktWrites = <http.Request>[];
          final mdblistWrites = <http.Request>[];
          final traktStopped = Completer<void>();
          final mdblist = MdblistService.forTesting(
            client: MockClient((request) async {
              mdblistWrites.add(request);
              return http.Response('{}', 200);
            }),
            apiKeyProvider: () async => 'test-key',
            featureEnabled: () => true,
          );
          final args = VideoPlayerLaunchArgs(
            videoUrl: 'https://example.test/movie',
            title: 'Movie',
            httpHeaders: const {'X-Test': 'native'},
            contentImdbId: id,
            contentType: 'movie',
            traktScrobble: true,
            mdblistScrobble: true,
          );
          const resumeId = 'movie-resume-test';
          final payload = await http.runWithClient(
            () async {
              final payload =
                  await VideoPlayerLauncher.debugNativePlaybackSession(args, [
                    {
                      'positionMs': 40000,
                      'durationMs': 100000,
                      'isPlaying': true,
                      'resumeId': resumeId,
                    },
                    {
                      'positionMs': threshold * 1000,
                      'durationMs': 100000,
                      'isPlaying': true,
                      'localCompleted': true,
                      'resumeId': resumeId,
                    },
                    {
                      'positionMs': 95000,
                      'durationMs': 100000,
                      'isPlaying': true,
                      'resumeId': resumeId,
                    },
                  ], mdblistService: mdblist);
              await traktStopped.future.timeout(const Duration(seconds: 3));
              return payload;
            },
            () => MockClient((request) async {
              traktWrites.add(request);
              if (request.url.path == '/scrobble/stop' &&
                  !traktStopped.isCompleted) {
                traktStopped.complete();
              }
              return http.Response('{}', 201);
            }),
          );
          expect(payload['localCompletionTracking'], isTrue);
          final traktStop = traktWrites.singleWhere(
            (r) => r.url.path == '/scrobble/stop',
          );
          expect(jsonDecode(traktStop.body)['progress'], 95);
          final mdbStop = mdblistWrites.singleWhere(
            (r) => r.url.path == '/scrobble/stop',
          );
          expect(
            jsonDecode(mdbStop.body)['progress'],
            threshold == 80 ? 80 : 95,
          );
          final expectedIds = id.startsWith('tt')
              ? {'imdb': id}
              : {'tmdb': 237243};
          expect(jsonDecode(traktStop.body)['movie']['ids'], expectedIds);
          expect(jsonDecode(mdbStop.body)['movie']['ids'], expectedIds);
          expect(await StorageService.isMovieFinished(id), isTrue);
          expect(await StorageService.getVideoResume(resumeId), isNull);
          expect(
            await StorageService.getVideoPlaybackStateByImdbId(id),
            isNull,
          );
        },
      );
    }
  }

  test(
    'native single stream retains declared series type while coordinates resolve',
    () async {
      final writes = <http.Request>[];
      final stopped = Completer<void>();
      await http.runWithClient(
        () async {
          await VideoPlayerLauncher.debugNativePlaybackSession(
            const VideoPlayerLaunchArgs(
              videoUrl: 'https://example.test/episode',
              title: 'Big Brother',
              httpHeaders: {'X-Test': 'native'},
              contentImdbId: 'tmdb:237243',
              contentType: 'series',
              traktScrobble: true,
            ),
            [
              {'positionMs': 10000, 'durationMs': 100000, 'isPlaying': true},
              {
                'positionMs': 20000,
                'durationMs': 100000,
                'isPlaying': true,
                'season': 4,
                'episode': 6,
              },
              // A late unresolved frame must not replace the known episode or progress.
              {'positionMs': 95000, 'durationMs': 100000, 'isPlaying': true},
            ],
          );
          await stopped.future.timeout(const Duration(seconds: 3));
        },
        () => MockClient((request) async {
          writes.add(request);
          if (request.url.path == '/scrobble/stop' && !stopped.isCompleted) {
            stopped.complete();
          }
          return http.Response('{}', 201);
        }),
      );
      expect(writes.map((r) => r.url.path), [
        '/scrobble/start',
        '/scrobble/stop',
      ]);
      for (final request in writes) {
        final body = jsonDecode(request.body);
        expect(body['movie'], isNull);
        expect(body['show']['ids'], {'tmdb': 237243});
        expect(body['episode'], {'season': 4, 'number': 6});
        expect(body['progress'], 20);
      }
      expect(await StorageService.isMovieFinished('tmdb:237243'), isFalse);
    },
  );

  for (final id in ['tmdb:237243', 'simkl:990203', 'tt1234567']) {
    test(
      '$id MDBList starts when episode coordinates arrive and follows Next',
      () async {
        final writes = <http.Request>[];
        final mdblist = MdblistService.forTesting(
          client: MockClient((request) async {
            writes.add(request);
            return http.Response('{}', 200);
          }),
          apiKeyProvider: () async => 'test-key',
        );
        await http.runWithClient(
          () => VideoPlayerLauncher.debugNativePlaybackSession(
            VideoPlayerLaunchArgs(
              videoUrl: 'https://example.test/episode',
              title: 'Big Brother',
              httpHeaders: const {'X-Test': 'native'},
              contentImdbId: id,
              contentType: 'series',
              mdblistScrobble: true,
            ),
            [
              {'positionMs': 90000, 'durationMs': 100000, 'isPlaying': true},
              {'positionMs': 90000, 'durationMs': 100000, 'season': 4},
              for (var i = 0; i < 2; i++)
                {
                  'positionMs': 20000,
                  'durationMs': 100000,
                  'season': 4,
                  'episode': 6,
                },
              // Missing coordinates must not complete the last known episode.
              {'positionMs': 99000, 'durationMs': 100000, 'completed': true},
              {
                'positionMs': 90000,
                'durationMs': 100000,
                'season': 4,
                'episode': 6,
                'isPlaying': true,
              },
              {
                'positionMs': 10000,
                'durationMs': 100000,
                'season': 4,
                'episode': 7,
                'isPlaying': true,
              },
            ],
            mdblistService: mdblist,
          ),
          () => MockClient((request) async {
            expect(request.url.host, 'api.simkl.com');
            expect(request.url.path, '/tv/990203');
            return http.Response(
              jsonEncode({
                'type': 'show',
                'ids': {'simkl': 990203, 'tmdb': 237243},
              }),
              200,
            );
          }),
        );
        expect(writes.map((r) => r.url.path), [
          '/scrobble/pause',
          '/scrobble/stop',
          '/scrobble/pause',
        ]);
        expect(writes.map((r) => jsonDecode(r.body)['progress']), [20, 90, 10]);
        for (var i = 0; i < writes.length; i++) {
          expect(jsonDecode(writes[i].body)['movie'], isNull);
          expect(jsonDecode(writes[i].body)['show'], {
            'ids': id.startsWith('tt') ? {'imdb': id} : {'tmdb': 237243},
            'season': 4,
            'episode': i < 2 ? 6 : 7,
          });
        }
      },
    );
  }

  test(
    'MDBList can complete when the first resolved frame is already finished',
    () async {
      final writes = <http.Request>[];
      await VideoPlayerLauncher.debugNativePlaybackSession(
        const VideoPlayerLaunchArgs(
          videoUrl: 'https://example.test/episode',
          title: 'Big Brother',
          httpHeaders: {'X-Test': 'native'},
          contentImdbId: 'tmdb:237243',
          contentType: 'series',
          mdblistScrobble: true,
        ),
        [
          {'positionMs': 10000, 'durationMs': 100000},
          {
            'positionMs': 100000,
            'durationMs': 100000,
            'season': 4,
            'episode': 6,
            'completed': true,
          },
        ],
        mdblistService: MdblistService.forTesting(
          client: MockClient((request) async {
            writes.add(request);
            return http.Response('{}', 200);
          }),
          apiKeyProvider: () async => 'test-key',
        ),
      );
      expect(writes.single.url.path, '/scrobble/stop');
      expect(jsonDecode(writes.single.body), {
        'show': {
          'ids': {'tmdb': 237243},
          'season': 4,
          'episode': 6,
        },
        'progress': 100,
      });
    },
  );

  for (final scenario in ['unresolved', 'disabled', 'feature disabled']) {
    test('MDBList sends nothing for $scenario playback', () async {
      await VideoPlayerLauncher.debugNativePlaybackSession(
        VideoPlayerLaunchArgs(
          videoUrl: 'https://example.test/episode',
          title: 'Big Brother',
          httpHeaders: const {'X-Test': 'native'},
          contentImdbId: 'tmdb:237243',
          contentType: 'series',
          mdblistScrobble: scenario != 'disabled',
        ),
        [
          {'positionMs': 10000, 'durationMs': 100000},
          {
            'positionMs': 95000,
            'durationMs': 100000,
            'completed': true,
            if (scenario != 'unresolved') ...{'season': 4, 'episode': 6},
          },
        ],
        mdblistService: MdblistService.forTesting(
          client: MockClient((_) async => fail('Unexpected MDBList request')),
          apiKeyProvider: () async => 'test-key',
          featureEnabled: () => scenario != 'feature disabled',
        ),
      );
    });
  }

  for (final mode in [WatchProgressSource.trakt, WatchProgressSource.mdblist]) {
    for (final id in ['tmdb:237243', 'simkl:2274121']) {
      test(
        '$id $mode keeps S4E6 and local position without borrowing US history',
        () async {
          await StorageService.setWatchProgressSource(mode);
          if (mode == WatchProgressSource.mdblist) {
            await StorageService.saveMdblistApiKey('test-key');
          }
          await StorageService.saveSeriesPlaybackState(
            seriesTitle: 'Big Brother',
            season: 4,
            episode: 6,
            positionMs: 42000,
            durationMs: 100000,
            imdbId: id,
          );
          await StorageService.saveSeriesPlaybackState(
            seriesTitle: 'Big Brother',
            season: 20,
            episode: 1,
            positionMs: 9000,
            durationMs: 100000,
            imdbId: 'tt0251497',
          );
          final payload = await VideoPlayerLauncher.debugNativePlaybackSession(
            VideoPlayerLaunchArgs(
              videoUrl: 'https://example.test/s1e1',
              title: 'Big Brother',
              contentTitle: 'Big Brother',
              httpHeaders: const {'X-Test': 'native'},
              contentImdbId: id,
              contentType: 'series',
              playlist: [
                PlaylistEntry(
                  url: 'https://example.test/s1e1',
                  title: 'Big Brother S01E01',
                ),
                PlaylistEntry(
                  url: 'https://example.test/s4e6',
                  title: 'Big Brother S04E06',
                ),
              ],
            ),
            [],
          );
          expect(payload['startIndex'], 1);
          final current = (payload['items'] as List)[1];
          expect(current['season'], 4);
          expect(current['episode'], 6);
          expect(current['resumePositionMs'], 42000);
          expect((await TrackingSourcePolicy.load()).progressSource, mode);
        },
      );
    }
  }
}
