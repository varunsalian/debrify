import 'dart:async';
import 'dart:io';

import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/profiles/connection_resource_service.dart';
import 'package:debrify/services/profiles/device_key_provider.dart';
import 'package:debrify/services/profiles/profile_authorization.dart';
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
  late MemoryDeviceSecretCipher cipher;
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
    cipher = MemoryDeviceSecretCipher(
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

  test('addon save publishes canonical authority into the cache', () async {
    service.debugManifestFetcher = (manifestUrl) async => StremioAddon(
      id: 'manifest-addon-id',
      name: 'Canonical addon',
      manifestUrl: manifestUrl,
      baseUrl: 'https://addon.invalid/configured',
      types: const <String>['movie'],
      resources: const <String>['stream'],
    );

    final added = await service.addAddon(
      'https://addon.invalid/configured/manifest.json',
    );
    expect(added.connectionResourceId, isNotNull);
    expect(added.connectionResourceRevision, isNotNull);

    final cached = (await service.getAddons()).single;
    expect(cached.connectionResourceId, added.connectionResourceId);
    expect(cached.connectionResourceRevision, added.connectionResourceRevision);

    await ConnectionResourceService(
      registry: registry,
      cipher: cipher,
    ).updateSecret(
      context: await ProfileAuthorizationContext.capture(registry),
      resourceId: added.connectionResourceId!,
      secretConfig: <String, dynamic>{
        'id': 'manifest-addon-id',
        'name': 'Rotated canonical addon',
        'manifest_url': added.manifestUrl,
        'base_url': added.baseUrl,
        'enabled': true,
        'types': const <String>['movie'],
        'resources': const <String>['stream'],
        'added_at': added.addedAt.millisecondsSinceEpoch,
      },
    );
    final reloaded = (await service.getAddons()).single;
    expect(
      reloaded.connectionResourceRevision,
      greaterThan(added.connectionResourceRevision!),
    );
    expect(reloaded.name, 'Rotated canonical addon');

    await service.setAddonEnabled(reloaded.storageKey, false);
    final settings = await service.getAddons(forSettings: true);
    expect(settings.single.enabled, isFalse);
  });
}
