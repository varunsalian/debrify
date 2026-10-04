import 'dart:io';

import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/screens/profiles/profile_wall_screen.dart';
import 'package:debrify/services/profiles/device_key_provider.dart';
import 'package:debrify/services/profiles/profile_bootstrap.dart';
import 'package:debrify/services/profiles/profile_cache_ledger.dart';
import 'package:debrify/services/profiles/profile_registry.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/storage/pikpak_storage.dart';
import 'package:debrify/utils/app_storage.dart';

class ProfileFixture {
  late Directory root;
  late ProfileRegistry registry;
  late MemoryDeviceSecretCipher cipher;
  late String a;
  Future<void> open() async {
    root = await Directory.systemTemp.createTemp('pikpak-profile-');
    AppStorage.debugOverride(documents: root, support: root, cache: root);
    registry = await ProfileRegistry.open(path: '${root.path}/profiles.db');
    a = (await registry.createProfile(
      name: 'A',
      role: UserProfileRole.admin,
    )).id;
    await registry.commitBootstrap(
      activeProfileId: a,
      migratedLegacyInstall: false,
    );
    cipher = MemoryDeviceSecretCipher(List<int>.generate(32, (i) => i + 5));
    await cipher.initialize();
    DeviceKeyProvider.debugInstallCipher(cipher);
    ProfileBootstrap.debugInstallRegistry(registry);
    ProfileRuntime.initializeCommitted(
      ProfileScope(profileId: a, dataGeneration: 1, sessionEpoch: 1),
    );
    await PikpakStorage.setPikPakEmail('profile-A@example.test');
    await PikpakStorage.setPikPakAccessToken('profile-A-access');
    await PikpakStorage.setPikPakRefreshToken('profile-A-refresh');
    await PikpakStorage.setPikPakEnabled(true);
    await ProfileGateAlwaysAsk.set(false);
    await ProfileGateStyle.set(ProfileGateStyle.classic);
  }

  Future<void> close() async {
    ProfileRuntime.debugReset();
    ProfileBootstrap.debugInstallRegistry(null);
    DeviceKeyProvider.debugReset();
    ProfileCacheLedger.debugReset();
    AppStorage.debugReset();
    await registry.close();
    await root.delete(recursive: true);
  }
}
