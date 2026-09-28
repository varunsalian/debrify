import 'dart:async';
import 'dart:convert';

import 'package:debrify/models/tracking_source.dart';
import 'package:debrify/services/secret_vault.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/services/trakt/trakt_service.dart';
import 'package:debrify/services/simkl/simkl_service.dart';
import 'package:debrify/services/local_history_removal.dart';
import 'package:debrify/services/playback_recovery_intent.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:debrify/services/series_progress_reset_service.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_tombstones.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final origin = ProfileScope(
    profileId: 'origin',
    dataGeneration: 1,
    sessionEpoch: 1,
  );
  final other = ProfileScope(
    profileId: 'other',
    dataGeneration: 1,
    sessionEpoch: 2,
  );
  final history = jsonEncode([
    {'imdbId': 'tt1', 'title': 'Reset', 'contentType': 'movie'},
    {'imdbId': 'tt2', 'title': 'Keep', 'contentType': 'movie'},
  ]);
  final playback = jsonEncode({
    for (final id in ['tt1', 'tt2'])
      'imdb:$id': {
        'imdbId': id,
        'type': 'movie',
        'positionMs': 50,
        'durationMs': 100,
      },
  });
  setUp(() {
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeCommitted(origin);
    PlaybackRecoveryIntent.debugSupportedOverride = true;
    SharedPreferences.setMockInitialValues({
      for (final scope in [origin, other]) ...{
        scope.preferenceKey('continue_watching_v1'): history,
        scope.preferenceKey('playback_state_v1'): playback,
        scope.preferenceKey('finished_movies_v1'): ['tt1', 'tt2'],
      },
    });
  });
  tearDown(() async {
    await LocalHistoryRemoval.drain();
    WebDavSyncTombstoneRecorder.debugReset();
    PlaybackRecoveryIntent.debugReset();
    SecretVault.debugReset();
    TraktService.instance.resetProfileScope();
    SimklService.instance.resetProfileScope();
    ProfileRuntime.debugReset();
  });

  for (final publish in [false, true]) {
    test(
      'accepted reset drains all origin records after retirement; publish=$publish',
      () async {
        final entered = Completer<void>(), release = Completer<void>();
        final journalProfiles = <String>[];
        WebDavSyncTombstoneRecorder.debugInstall(
          sink: (profile, keys) async {
            journalProfiles.add(profile);
            if (!entered.isCompleted) {
              entered.complete();
              await release.future;
            }
          },
        );
        var requests = 0;
        await http.runWithClient(
          () async {
            final reset = SeriesProgressResetService.clear(
              'tt1',
              'Reset',
              isMovie: true,
            );
            await entered.future;
            ProfileSessionMemory.clearAll();
            if (publish) ProfileRuntime.publish(other);
            var drained = false;
            final drain = LocalHistoryRemoval.drain().then(
              (_) => drained = true,
            );
            await Future<void>.delayed(Duration.zero);
            expect(drained, isFalse);
            release.complete();
            expect(await reset, ['Trakt', 'Simkl', 'MDBList']);
            await drain;
            expect(drained, isTrue);
          },
          () => MockClient((_) async {
            requests++;
            return http.Response('{}', 500);
          }),
        );
        expect(requests, 0);
        final prefs = await SharedPreferences.getInstance();
        final rows =
            jsonDecode(
                  prefs.getString(
                    origin.preferenceKey('continue_watching_v1'),
                  )!,
                )
                as List;
        expect(rows.map((row) => row['imdbId']), ['tt2']);
        final positions =
            jsonDecode(
                  prefs.getString(origin.preferenceKey('playback_state_v1'))!,
                )
                as Map;
        expect(positions.keys, ['imdb:tt2']);
        expect(
          prefs.getStringList(origin.preferenceKey('finished_movies_v1')),
          ['tt2'],
        );
        expect(
          prefs.getString(other.preferenceKey('continue_watching_v1')),
          history,
        );
        expect(
          prefs.getString(other.preferenceKey('playback_state_v1')),
          playback,
        );
        expect(prefs.getStringList(other.preferenceKey('finished_movies_v1')), [
          'tt1',
          'tt2',
        ]);
        expect(journalProfiles.toSet(), {'origin'});
        expect(
          prefs.getString(
            origin.preferenceKey('remote_tv_playback_recovery_deletions_v1'),
          ),
          isNotNull,
        );
        expect(
          prefs.getString(
            other.preferenceKey('remote_tv_playback_recovery_deletions_v1'),
          ),
          isNull,
        );
      },
    );
  }

  test('foreign captured scope cannot start a reset', () async {
    var journals = 0;
    WebDavSyncTombstoneRecorder.debugInstall(sink: (_, _) => journals++);
    final failures = await ProfileRuntime.withCapturedScope(
      other,
      () => SeriesProgressResetService.clear('tt1', 'Reset', isMovie: true),
    );
    expect(failures, ['this device', 'Trakt', 'Simkl', 'MDBList']);
    expect(journals, 0);
    final prefs = await SharedPreferences.getInstance();
    for (final scope in [origin, other]) {
      expect(
        prefs.getString(scope.preferenceKey('continue_watching_v1')),
        history,
      );
      expect(
        prefs.getString(scope.preferenceKey('playback_state_v1')),
        playback,
      );
      expect(prefs.getStringList(scope.preferenceKey('finished_movies_v1')), [
        'tt1',
        'tt2',
      ]);
    }
  });
  for (final provider in [TrackingSource.trakt, TrackingSource.simkl]) {
    for (final retire in [false, true]) {
      test('$provider reset history read retirement=$retire', () async {
        ProfileRuntime.debugReset();
        ProfileRuntime.initializeLegacy();
        SecretVault.debugReset(deviceIdOverride: 'reset-owner-test');
        SharedPreferences.setMockInitialValues({
          'simkl_access_token': 'test-token',
        });
        await StorageService.setTraktSession(
          accessToken: 'test-access',
          refreshToken: 'test-refresh',
          expiryMs: 9000000000000,
        );
        final entered = Completer<void>(), release = Completer<void>();
        final requests = <String>[];
        await http.runWithClient(
          () async {
            final reset = SeriesProgressResetService.clearProvider(
              'tt001',
              'Reset',
              provider: provider,
              isMovie: false,
            );
            await entered.future;
            if (retire) ProfileSessionMemory.clearAll();
            release.complete();
            expect(
              await reset,
              retire
                  ? [provider == TrackingSource.trakt ? 'Trakt' : 'Simkl']
                  : isEmpty,
            );
          },
          () => MockClient((request) async {
            requests.add('${request.method} ${request.url.path}');
            if (request.url.path == '/sync/playback/episodes' ||
                request.url.path == '/sync/watched') {
              if (!entered.isCompleted) {
                entered.complete();
                await release.future;
              }
              return http.Response(
                jsonEncode(
                  provider == TrackingSource.trakt
                      ? [
                          {
                            'id': 1,
                            'show': {
                              'ids': {'imdb': 'tt001'},
                            },
                          },
                        ]
                      : [
                          {
                            'seasons': [
                              {
                                'number': 1,
                                'episodes': [
                                  {'number': 1, 'watched': true},
                                ],
                              },
                            ],
                          },
                        ],
                ),
                200,
                headers: {'x-pagination-page-count': '1'},
              );
            }
            if (request.method == 'DELETE') return http.Response('', 204);
            if (request.url.path == '/sync/history/remove') {
              return http.Response('{"deleted":{"shows":1}}', 200);
            }
            return http.Response('[]', 200);
          }),
        );
        expect(
          requests
              .where(
                (r) =>
                    r.startsWith('DELETE') || r == 'POST /sync/history/remove',
              )
              .isEmpty,
          retire,
        );
        if (retire) expect(requests, hasLength(1));
      });
    }
  }
}
