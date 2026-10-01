import 'dart:async';
import 'dart:io';
import 'package:debrify/services/profiles/profile_bootstrap.dart';
import 'package:debrify/services/profiles/profile_registry.dart';
import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:debrify/features/home/application/home_detail_providers.dart';
import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:debrify/services/secret_vault.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/services/tracking_source_policy.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    SecretVault.debugReset(deviceIdOverride: 'tracking-fixture');
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(ProfileRuntime.debugReset);

  for (final direct in [false, true]) {
    for (final write in ['seed', 'fallback', 'credential']) {
      test(
        direct
            ? 'direct policy: retired $write cannot commit through the preference barrier'
            : 'retired $write cannot commit through the preference barrier',
        () async {
          SharedPreferences.setMockInitialValues({
            if (write != 'seed')
              StorageService.trackingScrobbleTargetsKey: ['local'],
            StorageService.watchProgressSourceKey: 'trakt',
            if (write == 'credential') 'trakt_access_token': 'fixture-token',
          });
          final container = ProviderContainer.test();
          final repository = container.read(
            homeTrackingPolicyRepositoryProvider(
              ProfileSessionMemory.captureOwner(),
            ),
          );
          final entered = Completer<void>(), release = Completer<void>();
          final snapshot = ProfilePreferences.captureMutationSnapshot((
            _,
          ) async {
            entered.complete();
            await release.future;
          });
          await entered.future;
          final revision = StorageService.trackingSourceRevision.value;
          final owner = ProfileSessionMemory.captureOwner();
          Future<TrackingSourcePolicy?> directLoad() async {
            try {
              return await TrackingSourcePolicy.load(
                canContinue: () => owner == ProfileSessionMemory.captureOwner(),
              );
            } on StateError {
              expect(owner == ProfileSessionMemory.captureOwner(), isFalse);
              return null;
            }
          }

          final operation = direct
              ? directLoad()
              : repository.loadForContent('tt123', isCurrent: () => true);
          // Let the real storage path reach the held commit, including vault sealing.
          await Future<void>.delayed(const Duration(milliseconds: 50));
          ProfileSessionMemory.clearAll();
          release.complete();
          await snapshot;
          expect(await operation, isNull);
          final prefs = await SharedPreferences.getInstance();
          expect(
            prefs.getString(StorageService.watchProgressSourceKey),
            'trakt',
          );
          expect(prefs.getBool('tracking_progress_fallback_notice'), isNull);
          expect(StorageService.trackingSourceRevision.value, revision);
          if (write == 'seed') {
            expect(
              prefs.getStringList(StorageService.trackingScrobbleTargetsKey),
              isNull,
            );
          }
          if (write == 'credential') {
            expect(prefs.getString('trakt_access_token'), 'fixture-token');
          }
        },
      );
    }
  }

  test(
    'active fallback writes only captured profile and retained factory stays fresh',
    () async {
      ProfileRuntime.debugReset();
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      final temp = await Directory.systemTemp.createTemp('tracking-policy-');
      final registry = await ProfileRegistry.open(
        path: '${temp.path}/profiles.db',
      );
      addTearDown(() async {
        ProfileBootstrap.debugInstallRegistry(null);
        await registry.close();
        await temp.delete(recursive: true);
      });
      final profile = await registry.createProfile(
        name: 'Tracking',
        role: UserProfileRole.admin,
      );
      await registry.commitBootstrap(
        activeProfileId: profile.id,
        migratedLegacyInstall: false,
      );
      ProfileBootstrap.debugInstallRegistry(registry);
      final scope = ProfileScope(
        profileId: profile.id,
        dataGeneration: 1,
        sessionEpoch: 1,
      );
      ProfileRuntime.initializeCommitted(scope);
      SharedPreferences.setMockInitialValues({
        scope.preferenceKey(StorageService.watchProgressSourceKey): 'trakt',
      });
      final container = ProviderContainer.test();
      final repository = container.read(
        homeTrackingPolicyRepositoryProvider(
          ProfileSessionMemory.captureOwner(),
        ),
      );
      await container.pump();
      final revision = StorageService.trackingSourceRevision.value;
      final policy = await repository.loadForContent(
        'tt123',
        isCurrent: () => true,
      );
      expect(policy!.progressSource, WatchProgressSource.smart);
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString(
          scope.preferenceKey(StorageService.watchProgressSourceKey),
        ),
        'smart',
      );
      expect(
        prefs.getBool(scope.preferenceKey('tracking_progress_fallback_notice')),
        isTrue,
      );
      expect(prefs.getString(StorageService.watchProgressSourceKey), isNull);
      expect(
        prefs.getStringList(StorageService.trackingScrobbleTargetsKey),
        isNull,
      );
      expect(StorageService.trackingSourceRevision.value, revision + 1);
      await StorageService.setWatchProgressSource(WatchProgressSource.local);
      expect(
        (await repository.loadForContent(
          'tt123',
          isCurrent: () => true,
        ))!.progressSource,
        WatchProgressSource.local,
      );
      ProfileSessionMemory.clearAll();
      expect(
        await repository.loadForContent('tt123', isCurrent: () => true),
        isNull,
      );
    },
  );

  test(
    'snapshot between fallback writes settles and guards the notice commit',
    () async {
      SharedPreferences.setMockInitialValues({
        StorageService.trackingScrobbleTargetsKey: ['local'],
        StorageService.watchProgressSourceKey: 'trakt',
      });
      final container = ProviderContainer.test();
      final repository = container.read(
        homeTrackingPolicyRepositoryProvider(
          ProfileSessionMemory.captureOwner(),
        ),
      );
      final entered = Completer<void>(), release = Completer<void>();
      Future<void>? snapshot;
      void onRevision() {
        snapshot ??= ProfilePreferences.captureMutationSnapshot((_) async {
          entered.complete();
          await release.future;
        });
      }

      StorageService.trackingSourceRevision.addListener(onRevision);
      addTearDown(
        () => StorageService.trackingSourceRevision.removeListener(onRevision),
      );
      var current = true;
      final operation = repository.loadForContent(
        'tt123',
        isCurrent: () => current,
      );
      await entered.future.timeout(const Duration(seconds: 2));
      await Future<void>.delayed(Duration.zero);
      current = false;
      release.complete();
      await snapshot;
      expect(await operation.timeout(const Duration(seconds: 2)), isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(StorageService.watchProgressSourceKey), 'smart');
      expect(prefs.getBool('tracking_progress_fallback_notice'), isNull);
    },
  );

  for (final source in ['trakt', 'simkl', 'mdblist']) {
    test(
      'active legacy $source credential preserves dedicated mode and seals value',
      () async {
        final key = source == 'mdblist'
            ? 'mdblist_api_key'
            : '${source}_access_token';
        SharedPreferences.setMockInitialValues({
          StorageService.watchProgressSourceKey: source,
          key: 'fixture-token',
        });
        final container = ProviderContainer.test();
        final repository = container.read(
          homeTrackingPolicyRepositoryProvider(
            ProfileSessionMemory.captureOwner(),
          ),
        );
        final policy = await repository.loadForContent(
          'tt123',
          isCurrent: () => true,
        );
        expect(policy!.progressSource.name, source);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString(key), startsWith(SecretVault.prefix));
        expect(prefs.getBool('tracking_progress_fallback_notice'), isNull);
      },
    );
  }
}
