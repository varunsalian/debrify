import 'dart:io';

import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/services/debrify_tv_database.dart';
import 'package:debrify/services/iptv_catalog_db.dart';
import 'package:debrify/services/profiles/device_key_provider.dart';
import 'package:debrify/services/profiles/profile_bootstrap.dart';
import 'package:debrify/services/profiles/profile_registry.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class PlaybackProfiles {
  late ProfileRegistry registry;
  late ProfileScope a;
  late ProfileScope b;

  Future<void> open(Directory directory) async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    registry = await ProfileRegistry.open(
      path: '${directory.path}/profiles.db',
    );
    final first = await registry.createProfile(
      name: 'A',
      role: UserProfileRole.admin,
    );
    await registry.commitBootstrap(
      activeProfileId: first.id,
      migratedLegacyInstall: false,
    );
    a = ProfileScope(profileId: first.id, dataGeneration: 1, sessionEpoch: 1);
    DeviceKeyProvider.debugInstallCipher(
      MemoryDeviceSecretCipher(List<int>.generate(32, (i) => i + 1)),
    );
    ProfileBootstrap.debugInstallRegistry(registry);
    ProfileRuntime.initializeCommitted(a);
    final second = await registry.createProfile(
      name: 'B',
      role: UserProfileRole.admin,
      actingProfileId: a.profileId,
      actingAuthorizationRevision: first.authorizationRevision,
      actingSessionEpoch: a.sessionEpoch,
    );
    b = ProfileScope(profileId: second.id, dataGeneration: 1, sessionEpoch: 2);
  }

  Future<void> publishB() async {
    await registry.setActiveProfile(b.profileId);
    ProfileRuntime.publish(b);
  }

  Future<void> close() async {
    await DebrifyTvDatabase.instance.closeScope();
    await IptvCatalogDb.closeScope();
    ProfileRuntime.debugReset();
    ProfileBootstrap.debugInstallRegistry(null);
    DeviceKeyProvider.debugReset();
    await registry.close();
    ProfileRuntime.initializeLegacy();
  }
}
