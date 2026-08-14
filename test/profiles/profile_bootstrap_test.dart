import 'dart:io';

import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/services/profiles/device_key_provider.dart';
import 'package:debrify/services/profiles/profile_bootstrap.dart';
import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/profiles/profile_registry.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/utils/app_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory temporaryDirectory;
  late Directory documents;
  late Directory support;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('profile rollout flags are enabled for the test rollout', () {
    expect(ProfileBootstrap.profilesEnabled, isTrue);
    expect(ProfileBootstrap.migrationRolloutReady, isTrue);
  });

  setUp(() async {
    ProfileRuntime.debugReset();
    ProfileBootstrap.debugInstallRegistry(null);
    DeviceKeyProvider.debugReset();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'profile-bootstrap-test-',
    );
    documents = Directory(p.join(temporaryDirectory.path, 'documents'));
    support = Directory(p.join(temporaryDirectory.path, 'support'));
    await documents.create(recursive: true);
    await support.create(recursive: true);
    AppStorage.debugOverride(documents: documents, support: support);
  });

  tearDown(() async {
    await ProfileBootstrap.close();
    ProfileRuntime.debugReset();
    DeviceKeyProvider.debugReset();
    AppStorage.debugReset();
    await temporaryDirectory.delete(recursive: true);
  });

  test(
    'committed registry stays authoritative when rollout flags are off',
    () async {
      final registry = await ProfileRegistry.open();
      final admin = await registry.createProfile(
        name: 'Admin',
        role: UserProfileRole.admin,
      );
      await registry.commitBootstrap(
        activeProfileId: admin.id,
        migratedLegacyInstall: true,
      );
      await registry.close();
      SharedPreferences.setMockInitialValues(<String, Object>{
        'profiles_committed_once_v1': true,
      });
      final cipher = MemoryDeviceSecretCipher(
        List<int>.generate(32, (index) => index + 23),
      );
      await cipher.initialize();
      DeviceKeyProvider.debugInstallCipher(cipher);

      await ProfileBootstrap.initialize(enabled: false);

      expect(ProfileRuntime.isProfileCommitted, isTrue);
      expect(ProfileRuntime.capture().profileId, admin.id);
    },
  );

  test(
    'native launch snapshots do not turn a fresh install into a migration',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        DevicePreferences.tvTrailerUnderlayEffectiveKey: false,
        DevicePreferences.tvLowResRenderActiveKey: true,
      });
      final cipher = MemoryDeviceSecretCipher(
        List<int>.generate(32, (index) => index + 7),
      );
      await cipher.initialize();
      DeviceKeyProvider.debugInstallCipher(cipher);

      await ProfileBootstrap.initialize();

      expect(
        (await ProfileBootstrap.registry.activeProfile())?.id,
        ProfileBootstrap.freshAdminId,
      );
    },
  );

  test('one-way marker plus missing registry enters recovery', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'profiles_committed_once_v1': true,
      'theme_mode': 'legacy-must-not-mount',
    });

    await expectLater(
      ProfileBootstrap.initialize(enabled: false),
      throwsA(isA<ProfileBootstrapRecoveryRequired>()),
    );
    expect(ProfileRuntime.isInitialized, isFalse);
  });

  test('one-way marker plus zero-byte registry enters recovery', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'profiles_committed_once_v1': true,
    });
    await File(await ProfileRegistry.defaultPath()).create(recursive: true);

    await expectLater(
      ProfileBootstrap.initialize(enabled: false),
      throwsA(isA<ProfileBootstrapRecoveryRequired>()),
    );
    expect(ProfileRuntime.isInitialized, isFalse);
  });

  test(
    'recovery quarantines an unreadable registry and creates safe Admin',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'profiles_committed_once_v1': true,
        'legacy_secret': 'must-not-be-mounted',
      });
      final originalPath = await ProfileRegistry.defaultPath();
      await File(originalPath).create(recursive: true);
      await File(originalPath).writeAsBytes(const <int>[1, 2, 3, 4]);
      await expectLater(
        ProfileBootstrap.initialize(enabled: false),
        throwsA(isA<ProfileBootstrapRecoveryRequired>()),
      );
      final cipher = MemoryDeviceSecretCipher(
        List<int>.generate(32, (index) => index + 41),
      );
      await cipher.initialize();
      DeviceKeyProvider.debugInstallCipher(cipher);

      final recovered = await ProfileBootstrap.initializeRecoveryAuthority();
      final active = await recovered.activeProfile();
      expect(active?.id, ProfileBootstrap.recoveryAdminId);
      expect(active?.role, UserProfileRole.admin);
      expect(ProfileRuntime.capture().profileId, active?.id);
      expect(
        support.listSync().whereType<File>().any(
          (file) => file.path.contains('profiles.db.recovery-'),
        ),
        isTrue,
      );
    },
  );
}
