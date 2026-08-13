import 'dart:async';
import 'dart:io';

import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/profiles/device_key_provider.dart';
import 'package:debrify/services/profiles/profile_bootstrap.dart';
import 'package:debrify/services/profiles/profile_registry.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/stremio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory temporaryDirectory;
  late ProfileRegistry registry;
  late String firstId;
  late String secondId;
  final service = StremioService.instance;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    ProfileRuntime.debugReset();
    DeviceKeyProvider.debugReset();
    service
      ..debugManifestFetcher = null
      ..invalidateCache();
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'profile-stremio-isolation-test-',
    );
    registry = await ProfileRegistry.open(
      path: p.join(temporaryDirectory.path, 'profiles.db'),
    );
    firstId = (await registry.createProfile(
      name: 'First',
      role: UserProfileRole.admin,
    )).id;
    secondId = (await registry.createProfile(
      name: 'Second',
      role: UserProfileRole.admin,
    )).id;
    await registry.commitBootstrap(
      activeProfileId: firstId,
      migratedLegacyInstall: false,
    );
    final cipher = MemoryDeviceSecretCipher(
      List<int>.generate(32, (index) => index + 17),
    );
    await cipher.initialize();
    DeviceKeyProvider.debugInstallCipher(cipher);
    ProfileBootstrap.debugInstallRegistry(registry);
    ProfileRuntime.initializeCommitted(
      ProfileScope(profileId: firstId, dataGeneration: 1, sessionEpoch: 1),
    );
  });

  tearDown(() async {
    service
      ..debugManifestFetcher = null
      ..invalidateCache();
    ProfileRuntime.debugReset();
    ProfileBootstrap.debugInstallRegistry(null);
    DeviceKeyProvider.debugReset();
    await registry.close();
    await temporaryDirectory.delete(recursive: true);
  });

  test(
    'delayed manifest from profile A cannot publish into profile B',
    () async {
      final started = Completer<void>();
      final release = Completer<void>();
      service.debugManifestFetcher = (manifestUrl) async {
        started.complete();
        await release.future;
        return StremioAddon(
          id: 'delayed-addon',
          name: 'Delayed addon',
          manifestUrl: manifestUrl,
          baseUrl: 'https://addon.invalid/credential-sentinel',
          types: const <String>['movie'],
          resources: const <String>['stream'],
        );
      };

      final addition = service.addAddon(
        'https://addon.invalid/credential-sentinel/manifest.json',
      );
      await started.future;
      await registry.setActiveProfile(secondId);
      ProfileRuntime.publish(
        ProfileScope(profileId: secondId, dataGeneration: 1, sessionEpoch: 2),
      );
      service.invalidateCache();
      release.complete();

      await expectLater(addition, throwsA(isA<StateError>()));
      expect(await registry.listGrantedResources(firstId), isEmpty);
      expect(await registry.listGrantedResources(secondId), isEmpty);
      expect(await service.getAddons(), isEmpty);
    },
  );
}
