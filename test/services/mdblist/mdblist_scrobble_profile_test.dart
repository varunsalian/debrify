import 'dart:async';
import 'dart:io';
import 'package:debrify/models/advanced_search_selection.dart';
import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/services/episode_tracker_snapshot_revision.dart';
import 'package:debrify/services/mdblist/mdblist_continue_watching_service.dart';
import 'package:debrify/services/mdblist/mdblist_models.dart';
import 'package:debrify/services/mdblist/mdblist_service.dart';
import 'package:debrify/services/profiles/profile_bootstrap.dart';
import 'package:debrify/services/profiles/profile_async_authorization.dart';
import 'package:debrify/services/profiles/profile_registry.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const target = MdblistScrobbleTarget.episode(
  MdblistMediaIds(imdb: 'tt1'),
  season: 2,
  episode: 3,
);
const item = MdblistContinueWatchingItem(
  selection: AdvancedSearchSelection(
    imdbId: 'tt1',
    isSeries: true,
    title: 'Episode',
  ),
  paused: true,
  clearTarget: target,
);

// Exercises the continuation service's own acceptance boundary independently
// of the real scrobble service's retirement guard.
class RetiredClearService extends Fake implements MdblistService {
  @override
  Future<MdblistResult<Map<String, dynamic>>> scrobbleClear(
    MdblistScrobbleTarget target, {
    ProfileAsyncAuthorization? capability,
    bool Function()? canContinue,
  }) async {
    ProfileSessionMemory.clearAll();
    return const MdblistResult.success({});
  }
}

void main() {
  late Directory directory;
  late ProfileRegistry registry;
  late String secondId;
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('mdblist_profile_');
    registry = await ProfileRegistry.open(
      path: '${directory.path}/profiles.db',
    );
    final first = await registry.createProfile(
      name: 'First',
      role: UserProfileRole.admin,
    );
    secondId = (await registry.createProfile(
      name: 'Second',
      role: UserProfileRole.admin,
    )).id;
    ProfileBootstrap.debugInstallRegistry(registry);
    ProfileRuntime.debugReset();
    ProfileSessionMemory.debugReset();
    EpisodeTrackerSnapshotRevision.resetForTesting();
    ProfileRuntime.initializeCommitted(
      ProfileScope(profileId: first.id, dataGeneration: 1, sessionEpoch: 1),
    );
  });
  tearDown(() async {
    ProfileRuntime.debugReset();
    ProfileSessionMemory.debugReset();
    ProfileBootstrap.debugInstallRegistry(null);
    await registry.close();
    await directory.delete(recursive: true);
  });

  for (final action in ['start', 'pause', 'stop', 'clear']) {
    for (final retirement in ['profile', 'deactivation']) {
      test(
        '$action success after $retirement cannot notify or invalidate incoming snapshots',
        () async {
          final entered = Completer<void>();
          final response = Completer<http.Response>();
          var watchedReads = 0;
          final requests = <http.Request>[];
          final service = MdblistService.forTesting(
            featureEnabled: () => true,
            apiKeyProvider: () async => 'fixture-key',
            client: MockClient((request) async {
              requests.add(request);
              if (request.url.path.startsWith('/scrobble/')) {
                entered.complete();
                return response.future;
              }
              if (request.url.path == '/sync/watched') watchedReads++;
              return http.Response('[]', 200);
            }),
          );
          final request = switch (action) {
            'start' => service.scrobbleStart(target, 25),
            'pause' => service.scrobblePause(target, 25),
            'stop' => service.scrobbleStop(target, 90),
            _ => service.scrobbleClear(target),
          };
          await entered.future;
          // Request was authorized and sent for the outgoing session. Retirement
          // cannot undo that remote operation, but must reject local completion.
          if (retirement == 'profile') {
            ProfileRuntime.publish(
              ProfileScope(
                profileId: secondId,
                dataGeneration: 1,
                sessionEpoch: 2,
              ),
            );
          } else {
            ProfileSessionMemory.clearAll();
          }
          service.resetProfileScope();
          expect(
            (await service.fetchSyncSnapshot('watched')).isSuccess,
            isTrue,
          );
          response.complete(http.Response('{}', 200));
          final result = await request;
          expect(service.playbackRevision.value, 0);
          expect(service.libraryRevision.value, 0);
          expect(service.watchedRevision.value, 0);
          expect(EpisodeTrackerSnapshotRevision.identity('mdblist', 'tt1'), 0);
          expect(result.kind, MdblistResultKind.denied);
          expect(
            (await service.fetchSyncSnapshot('watched')).isSuccess,
            isTrue,
          );
          expect(watchedReads, 1);
          expect(
            requests.where((r) => r.url.path.startsWith('/scrobble/')),
            hasLength(1),
          );
        },
      );
    }
  }

  test(
    'continuation clear independently rejects a retired service success',
    () async {
      final continuation = MdblistContinueWatchingService.forTesting(
        RetiredClearService(),
      );
      expect(await continuation.clear(item), isFalse);
    },
  );

  for (final notifier in ['playback', 'library', 'watched']) {
    test(
      'stop retirement in $notifier listener suppresses remaining completion',
      () async {
        final service = MdblistService.forTesting(
          featureEnabled: () => true,
          apiKeyProvider: () async => 'fixture-key',
          client: MockClient((_) async => http.Response('{}', 200)),
        );
        final revision = switch (notifier) {
          'playback' => service.playbackRevision,
          'library' => service.libraryRevision,
          _ => service.watchedRevision,
        };
        revision.addListener(ProfileSessionMemory.clearAll);
        expect(
          (await service.scrobbleStop(target, 90)).kind,
          MdblistResultKind.denied,
        );
        expect(service.playbackRevision.value, 1);
        expect(service.libraryRevision.value, notifier == 'playback' ? 0 : 1);
        expect(service.watchedRevision.value, notifier == 'watched' ? 1 : 0);
      },
    );
  }
  test(
    'deactivation during authorization prevents outbound scrobble',
    () async {
      var calls = 0;
      final service = MdblistService.forTesting(
        featureEnabled: () => true,
        apiKeyProvider: () async => 'fixture-key',
        client: MockClient((_) async {
          calls++;
          return http.Response('{}', 200);
        }),
      );
      final request = service.scrobbleStart(target, 25);
      ProfileSessionMemory.clearAll();
      expect((await request).kind, MdblistResultKind.denied);
      expect(calls, 0);
      expect(service.playbackRevision.value, 0);
    },
  );
}
