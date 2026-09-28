import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/watched_action_coordinator.dart';
import 'package:debrify/models/custom_series_identity.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'dart:async';
import 'dart:convert';

import 'package:debrify/models/tracking_source.dart';
import 'package:debrify/services/profile_tracker_title_actions.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:debrify/services/secret_vault.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/services/tracker_title_actions.dart';
import 'package:debrify/services/trakt/trakt_service.dart';
import 'package:debrify/services/simkl/simkl_service.dart';
import 'package:debrify/services/mdblist/mdblist_service.dart';
import 'package:debrify/services/watched_status_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Future<http.Response> Function(http.Request) activeHandler;
  http.Client fixtureClient(
    Future<http.Response> Function(http.Request) handler,
  ) {
    activeHandler = handler;
    return MockClient(handler);
  }

  Future<T> runWithFixtureClient<T>(
    Future<T> Function() body,
    http.Client Function() factory,
  ) {
    final client = factory();
    return http.runWithClient(body, () => client);
  }

  // MDBList intentionally owns one long-lived client; install its fixture at
  // first construction, while per-call clients still follow the HTTP zone.
  setUpAll(
    () => http.runWithClient(() async {
      MdblistService.instance.resetProfileScope();
    }, () => MockClient((request) => activeHandler(request))),
  );

  setUp(() async {
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    SecretVault.debugReset(deviceIdOverride: 'title-actions');
    SharedPreferences.setMockInitialValues({});
    await StorageService.setTraktSession(
      accessToken: 'fixture',
      refreshToken: 'refresh',
      expiryMs: 9000000000000,
    );
    await StorageService.setSimklAccessToken('fixture');
    await StorageService.saveMdblistApiKey('fixture');
    await StorageService.setTrackingScrobbleTargets({TrackingSource.local});
    await StorageService.setHomeTickSources({TrackingSource.local});
    TraktService.instance.resetProfileScope();
    SimklService.instance.resetProfileScope();
    MdblistService.instance.resetProfileScope();
    WatchedStatusService.instance.resetProfileScope();
  });
  tearDown(() async {
    WatchedStatusService.instance.resetProfileScope();
    await Future<void>.delayed(Duration.zero);
    ProfileRuntime.debugReset();
    SecretVault.debugReset();
  });

  for (final tracker in [
    TrackingSource.trakt,
    TrackingSource.simkl,
    TrackingSource.mdblist,
  ]) {
    test(
      'branded $tracker watched action preserves forced target and local completion',
      () async {
        final writes = <http.Request>[];
        await runWithFixtureClient(
          () async {
            final actions = ProfileTrackerTitleActions(
              ProfileSessionMemory.captureOwner(),
            );
            if (tracker == TrackingSource.mdblist) {
              expect(await MdblistService.instance.isAuthenticated(), isTrue);
            }
            expect(
              await actions.mutate(
                tracker,
                TrackerTitleMutation.markWatched,
                'tt1234567',
                'movie',
                isCurrent: () => true,
              ),
              isTrue,
            );
            await WatchedStatusService.instance.firstSnapshot;
            expect(
              (await SharedPreferences.getInstance()).getStringList(
                'finished_movies_v1',
              ),
              contains('tt1234567'),
            );
          },
          () => fixtureClient((request) async {
            if (request.method == 'POST') {
              writes.add(request);
              return http.Response(
                '{"added":{"movies":1},"updated":{"movies":1}}',
                200,
              );
            }
            return http.Response(
              '[]',
              200,
              headers: {'x-pagination-page-count': '1'},
            );
          }),
        );
        final history = writes
            .where(
              (r) =>
                  r.url.path == '/sync/history' ||
                  r.url.path == '/sync/watched',
            )
            .toList();
        expect(history, hasLength(1));
        expect(history.single.url.host, contains(tracker.name));
        expect(
          jsonDecode(history.single.body)['movies'][0]['ids']['imdb'],
          'tt1234567',
        );
      },
    );
  }

  for (final tracker in [
    TrackingSource.trakt,
    TrackingSource.simkl,
    TrackingSource.mdblist,
  ]) {
    test(
      '$tracker mutation retires during credential migration before sending',
      () async {
        await Future<void>.delayed(Duration.zero);
        final key = switch (tracker) {
          TrackingSource.trakt => 'trakt_access_token',
          TrackingSource.simkl => 'simkl_access_token',
          _ => 'mdblist_api_key',
        };
        SharedPreferences.setMockInitialValues({key: 'legacy-token'});
        final actions = ProfileTrackerTitleActions(
          ProfileSessionMemory.captureOwner(),
        );
        final entered = Completer<void>(), release = Completer<void>();
        final snapshot = ProfilePreferences.captureMutationSnapshot((_) async {
          entered.complete();
          await release.future;
        });
        await entered.future;
        var requests = 0;
        await runWithFixtureClient(
          () async {
            final mutation = actions.mutate(
              tracker,
              TrackerTitleMutation.rate,
              'tt1234567',
              'movie',
              rating: 8,
              isCurrent: () => true,
            );
            await Future<void>.delayed(const Duration(milliseconds: 50));
            ProfileSessionMemory.clearAll();
            release.complete();
            await snapshot;
            expect(await mutation, isFalse);
          },
          () => fixtureClient((_) async {
            requests++;
            return http.Response('{}', 200);
          }),
        );
        expect(requests, 0);
        expect(
          (await SharedPreferences.getInstance()).getString(key),
          'legacy-token',
        );
      },
    );
  }

  test(
    'watched action retires after accepted Trakt write without starting later trackers',
    () async {
      final entered = Completer<void>(), release = Completer<void>();
      final writes = <http.Request>[];
      await runWithFixtureClient(
        () async {
          final operation = WatchedActionCoordinator.setTitleWatched(
            imdbId: 'tt1234567',
            contentType: 'movie',
            watched: true,
            forceTargets: {
              TrackingSource.trakt,
              TrackingSource.simkl,
              TrackingSource.mdblist,
            },
          );
          await entered.future;
          ProfileSessionMemory.clearAll();
          release.complete();
          final result = await operation;
          expect(result.cancelled, isTrue);
          expect(result.success, isFalse);
        },
        () => fixtureClient((request) async {
          if (request.method == 'POST') {
            writes.add(request);
            if (!entered.isCompleted) {
              entered.complete();
              await release.future;
            }
            return http.Response('{}', 200);
          }
          return http.Response('[]', 200);
        }),
      );
      expect(writes, hasLength(1));
      expect(writes.single.url.host, contains('trakt'));
      expect(
        (await SharedPreferences.getInstance()).getStringList(
          'finished_movies_v1',
        ),
        contains('tt1234567'),
      );
    },
  );

  for (final retirement in ['none', 'view', 'profile']) {
    test(
      'Simkl drop preserves write then cleanup; retirement=$retirement',
      () async {
        var current = true;
        final entered = Completer<void>(), release = Completer<void>();
        final paths = <String>[];
        await runWithFixtureClient(
          () async {
            final actions = ProfileTrackerTitleActions(
              ProfileSessionMemory.captureOwner(),
            );
            final drop = actions.mutate(
              TrackingSource.simkl,
              TrackerTitleMutation.drop,
              'tt1234567',
              'series',
              isCurrent: () => current,
            );
            await entered.future;
            if (retirement == 'view') current = false;
            if (retirement == 'profile') ProfileSessionMemory.clearAll();
            release.complete();
            expect(await drop, retirement == 'none');
          },
          () => fixtureClient((request) async {
            paths.add(request.url.path);
            if (request.url.path == '/sync/add-to-list') {
              expect(jsonDecode(request.body)['shows'][0]['to'], 'dropped');
              entered.complete();
              await release.future;
              return http.Response('{"added":{"shows":1}}', 200);
            }
            return http.Response('[]', 200);
          }),
        );
        expect(paths.first, '/sync/add-to-list');
        final playbackReads = paths
            .where((p) => p.startsWith('/sync/playback/'))
            .toList();
        expect(playbackReads.length, retirement == 'none' ? 2 : 0);
        if (retirement != 'none') expect(paths, ['/sync/add-to-list']);
      },
    );
  }

  test(
    'dependency retains its origin despite a foreign ambient scope',
    () async {
      await Future<void>.delayed(Duration.zero);
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
      ProfileRuntime.debugReset();
      ProfileRuntime.initializeCommitted(origin);
      final actions = ProfileTrackerTitleActions(
        ProfileSessionMemory.captureOwner(),
      );
      final id = const CustomSeriesIdentity('fixture', 'series').id;
      expect(
        await ProfileRuntime.withCapturedScope(
          other,
          () => actions.mutate(
            TrackingSource.trakt,
            TrackerTitleMutation.markWatched,
            id,
            'series',
            isCurrent: () => true,
          ),
        ),
        isTrue,
      );
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getStringList(
          origin.preferenceKey('explicitly_watched_series_v1'),
        ),
        [id],
      );
      expect(
        prefs.getStringList(
          other.preferenceKey('explicitly_watched_series_v1'),
        ),
        isNull,
      );
    },
  );

  test(
    'retired dependency cannot start mutations, list reads or resets',
    () async {
      final actions = ProfileTrackerTitleActions(
        ProfileSessionMemory.captureOwner(),
      );
      ProfileSessionMemory.clearAll();
      var requests = 0;
      await runWithFixtureClient(
        () async {
          expect(
            await actions.mutate(
              TrackingSource.trakt,
              TrackerTitleMutation.markWatched,
              'tt1234567',
              'movie',
              isCurrent: () => true,
            ),
            isFalse,
          );
          expect(await actions.customLists(isCurrent: () => true), isEmpty);
          expect(
            await actions.reset(
              'tt1234567',
              'Fixture',
              isMovie: true,
              isCurrent: () => true,
            ),
            isNotEmpty,
          );
        },
        () => fixtureClient((_) async {
          requests++;
          return http.Response('{}', 500);
        }),
      );
      expect(requests, 0);
      expect(
        (await SharedPreferences.getInstance()).getStringList(
          'finished_movies_v1',
        ),
        isNull,
      );
    },
  );
}
