import 'dart:async';

import 'package:debrify/features/home/application/home_random_episode_dependencies.dart';
import 'package:debrify/features/home/models/home_random_playback_preparation.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(ProfileRuntime.debugReset);

  test(
    'production adapter forwards retirement through the actual inventory commit barrier',
    () async {
      final container = ProviderContainer.test();
      final owner = ProfileSessionMemory.captureOwner();
      final repository = container.read(
        homeRandomPlaybackRepositoryProvider(owner),
      );
      final entered = Completer<void>(), release = Completer<void>();
      final snapshot = ProfilePreferences.captureMutationSnapshot((
        token,
      ) async {
        entered.complete();
        await release.future;
      });
      await entered.future;
      final revision = StorageService.localCompletionRevision.value;
      var calls = 0;
      final write = repository.recordInventory(
        'tt1234567',
        'Fixture',
        [
          {'season': 1, 'episode': 1, 'released': '2025-01-01T00:00:00Z'},
        ],
        () {
          calls++;
          return true;
        },
      );
      await Future<void>.delayed(Duration.zero);
      expect(calls, greaterThanOrEqualTo(2));
      ProfileSessionMemory.clearAll();
      release.complete();
      await snapshot;
      await write;
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString(StorageService.localSeriesCompletionStateKey),
        isNull,
      );
      expect(StorageService.localCompletionRevision.value, revision);
    },
  );

  test(
    'retained stateless repository rejects a retired owner before service access',
    () async {
      final container = ProviderContainer.test();
      final owner = ProfileSessionMemory.captureOwner();
      final repository = container.read(
        homeRandomPlaybackRepositoryProvider(owner),
      );
      await container
          .pump(); // Factory disposal does not own explicit action work.
      ProfileSessionMemory.clearAll();
      final result = await repository.prepare(
        item: const StremioMeta(id: 'tt123', type: 'series', name: 'Fixture'),
        addon: StremioAddon(
          id: 'missing',
          name: 'Missing',
          manifestUrl: '',
          baseUrl: '',
          addedAt: DateTime.utc(2026),
        ),
        progressId: 'tt123',
        continuous: false,
        isCurrent: () => true,
      );
      expect(result.status, HomeRandomPlaybackStatus.retired);
    },
  );
  test(
    'active committed-profile inventory writes only its captured namespace',
    () async {
      ProfileRuntime.debugReset();
      final scope = ProfileScope(
        profileId: 'random-origin',
        dataGeneration: 1,
        sessionEpoch: 1,
      );
      ProfileRuntime.initializeCommitted(scope);
      final container = ProviderContainer.test();
      final repository = container.read(
        homeRandomPlaybackRepositoryProvider(
          ProfileSessionMemory.captureOwner(),
        ),
      );
      await repository.recordInventory('tt1234567', 'Fixture', [
        {'season': 1, 'episode': 1, 'released': '2025-01-01T00:00:00Z'},
      ], () => true);
      final prefs = await SharedPreferences.getInstance();
      final key = StorageService.localSeriesCompletionStateKey;
      expect(prefs.getString(scope.preferenceKey(key)), contains('tt1234567'));
      expect(prefs.getString(key), isNull);
    },
  );
}
