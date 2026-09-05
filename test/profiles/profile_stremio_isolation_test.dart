import 'dart:async';
import 'dart:io';

import 'package:debrify/models/profiles/connection_resource.dart';
import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/backup_restore_service.dart';
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
    'management rejects executable resource denial; display fallback is uncached',
    () async {
      final resources = ConnectionResourceService(
        registry: registry,
        cipher: cipher,
      );
      const manifestUrl = 'https://addon.invalid/shared/manifest.json';
      final shared = await resources.create(
        context: await ProfileAuthorizationContext.capture(registry),
        type: ConnectionResourceType.stremioAddon,
        label: 'Shared addon',
        publicConfig: const {'addonName': 'Shared addon'},
        secretConfig: const {
          'id': 'shared-addon',
          'name': 'Shared addon',
          'manifest_url': manifestUrl,
          'base_url': 'https://addon.invalid/shared',
          'types': ['movie'],
          'resources': ['stream'],
        },
      );
      // The default use grant gives the borrower a redacted Settings entry.
      await registry.setActiveProfile(secondId);
      ProfileRuntime.publish(
        ProfileScope(profileId: secondId, dataGeneration: 1, sessionEpoch: 2),
      );
      final rejectingCipher = _RotatingReadCipher(cipher, () async {
        // Rotate between decryption and the service's strict revalidation.
        final sealed = (await registry.getSealedResourceSecret(shared.id))!;
        await registry.updateResourceSecret(
          resourceId: shared.id,
          sealedSecretPayload: sealed.envelope,
          secretPayloadVersion: sealed.payloadVersion,
        );
      });
      DeviceKeyProvider.debugInstallCipher(rejectingCipher);
      expect(
        (await service.getAddons(
          forSettings: true,
        )).single.connectionResourceCredentialsRedacted,
        isTrue,
      );
      await expectLater(
        service.getAddonsForManagement(),
        throwsA(isA<ResourceAuthorizationException>()),
      );
      expect(await service.getAddons(), isEmpty);
      expect(await service.getAddons(), isEmpty);
      expect(rejectingCipher.reads, 3);
      rejectingCipher.reject = false;
      expect((await service.getAddons()).single.manifestUrl, manifestUrl);
      expect(
        (await service.getAddonsForManagement()).single.manifestUrl,
        manifestUrl,
      );
    },
  );

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

    // A disabled addon is hidden from the plain read, so the toggle back ON
    // has to look it up through the settings read or it can never find the
    // thing it is meant to re-enable.
    expect(await service.getAddons(), isEmpty);
    await service.setAddonEnabled(settings.single.storageKey, true);
    expect((await service.getAddons(forSettings: true)).single.enabled, isTrue);
    expect(await service.getAddons(), hasLength(1));
  });

  test('toggling by manifest URL is refused instead of doing nothing', () async {
    // The Addon Hub passed a manifest URL here. Under profiles the storage key
    // is the connection resource id, so the lookup missed and the toggle was a
    // silent no-op — the shape of bug this throw exists to prevent.
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
    expect(added.storageKey, isNot(added.manifestUrl));

    await expectLater(
      () => service.setAddonEnabled(added.manifestUrl, false),
      throwsA(isA<ArgumentError>()),
    );
    expect((await service.getAddons(forSettings: true)).single.enabled, isTrue);
  });

  test(
    'shared addons keep executable identity across management and saves',
    () async {
      const sharedManifestUrl =
          'https://addon.invalid/shared-key/manifest.json';
      final resourceService = ConnectionResourceService(
        registry: registry,
        cipher: cipher,
      );
      final shared = await resourceService.create(
        context: await ProfileAuthorizationContext.capture(registry),
        type: ConnectionResourceType.stremioAddon,
        label: 'Shared addon',
        publicConfig: const <String, dynamic>{
          'addonName': 'Shared addon',
          'contentKinds': <String>['movie'],
        },
        secretConfig: const <String, dynamic>{
          'id': 'shared-addon',
          'name': 'Shared addon',
          'manifest_url': sharedManifestUrl,
          'base_url': 'https://addon.invalid/shared-key',
          'enabled': true,
          'types': <String>['movie'],
          'resources': <String>['stream', 'subtitles', 'meta'],
        },
      );
      await resourceService.grant(
        actor: await ProfileAuthorizationContext.capture(registry),
        targetProfileId: secondId,
        resourceId: shared.id,
        permissions: const <ResourcePermission>{ResourcePermission.use},
      );
      await registry.setActiveProfile(secondId);
      ProfileRuntime.publish(
        ProfileScope(profileId: secondId, dataGeneration: 1, sessionEpoch: 2),
      );
      service.invalidateCache();

      final settings = (await service.getAddons(forSettings: true)).single;
      expect(settings.connectionResourceCredentialsRedacted, isTrue);
      expect(settings.manifestUrl, isEmpty);

      final management = (await service.getAddonsForManagement()).single;
      expect(management.connectionResourceId, shared.id);
      expect(management.manifestUrl, sharedManifestUrl);
      expect(
        management.resources,
        containsAll(<String>['stream', 'subtitles', 'meta']),
      );
      expect(management.baseUrl, 'https://addon.invalid/shared-key');

      await expectLater(
        () => service.addAddon(sharedManifestUrl),
        throwsA(isA<Exception>()),
      );
      final imported = await service.importAddonsFromJson('''{
          "addons": [{
            "manifest": {
              "id": "shared-addon",
              "name": "Shared addon",
              "resources": ["stream", "subtitles"],
              "types": ["movie"]
            },
            "transportUrl": "$sharedManifestUrl"
          }]
        }''');
      expect(imported.imported, 0);
      expect(imported.skippedDuplicates, 1);

      service.debugManifestFetcher = (manifestUrl) async => StremioAddon(
        id: 'owned-addon',
        name: 'Owned addon',
        manifestUrl: manifestUrl,
        baseUrl: 'https://addon.invalid/owned',
        types: const <String>['movie'],
        resources: const <String>['stream'],
      );
      await service.addAddon('https://addon.invalid/owned/manifest.json');

      final playback = await service.getAddons();
      expect(playback, hasLength(2));
      final executableShared = playback.singleWhere(
        (addon) => addon.connectionResourceId == shared.id,
      );
      expect(executableShared.manifestUrl, sharedManifestUrl);
      expect(executableShared.resources, contains('subtitles'));
      expect(executableShared.connectionResourceCredentialsRedacted, isFalse);

      expect(
        BackupRestoreService.backupAddonManifestUrls(<String>[
          settings.manifestUrl,
        ]),
        isEmpty,
      );
    },
  );

  test('management operations retain disabled addons', () async {
    var version = '1.0.0';
    service.debugManifestFetcher = (manifestUrl) async => StremioAddon(
      id: 'managed-disabled-addon',
      name: 'Managed disabled addon',
      version: version,
      manifestUrl: manifestUrl,
      baseUrl: 'https://addon.invalid/managed-disabled',
      types: const <String>['movie'],
      resources: const <String>['stream'],
    );
    final added = await service.addAddon(
      'https://addon.invalid/managed-disabled/manifest.json',
    );
    await service.setAddonEnabled(added.storageKey, false);
    expect(await service.getAddons(), isEmpty);

    // Management reads must still find the hidden playback row: adding or
    // importing it cannot create a duplicate, and updates/removal still work.
    await expectLater(
      () => service.addAddon(added.manifestUrl),
      throwsA(isA<Exception>()),
    );
    final imported = await service.importAddonsFromJson('''{
        "addons": [{
          "manifest": {
            "id": "managed-disabled-addon",
            "name": "Managed disabled addon",
            "version": "1.0.0",
            "resources": ["stream"],
            "types": ["movie"]
          },
          "transportUrl": "https://addon.invalid/managed-disabled/manifest.json"
        }]
      }''');
    expect(imported.imported, 0);
    expect(imported.skippedDuplicates, 1);

    version = '1.5.0';
    final singlyRefreshed = await service.refreshAddon(added.manifestUrl);
    expect(singlyRefreshed, isNotNull);
    expect(singlyRefreshed!.version, '1.5.0');
    expect(singlyRefreshed.enabled, isFalse);
    expect(singlyRefreshed.connectionResourceId, added.connectionResourceId);
    expect(
      singlyRefreshed.connectionResourceRevision,
      greaterThan(added.connectionResourceRevision!),
    );

    version = '2.0.0';
    final refreshed = await service.refreshAllAddons();
    expect(refreshed.updated, 1);
    final disabled = (await service.getAddons(forSettings: true)).single;
    expect(disabled.version, '2.0.0');
    expect(disabled.enabled, isFalse);
    expect(disabled.connectionResourceId, added.connectionResourceId);
    expect(
      disabled.connectionResourceRevision,
      greaterThan(singlyRefreshed.connectionResourceRevision!),
    );
    expect(await service.getAddons(), isEmpty);

    await service.removeAddon(disabled.manifestUrl);
    expect(await service.getAddons(forSettings: true), isEmpty);
  });

  test('owner can confirm removal from every shared profile', () async {
    const manifestUrl = 'https://addon.invalid/shared/manifest.json';
    service.debugManifestFetcher = (url) async => StremioAddon(
      id: 'shared-removal-addon',
      name: 'Shared removal addon',
      manifestUrl: url,
      baseUrl: 'https://addon.invalid/shared',
      types: const <String>['movie'],
      resources: const <String>['stream'],
    );
    final added = await service.addAddon(manifestUrl);
    final resourceId = added.connectionResourceId!;
    final resourceService = ConnectionResourceService(
      registry: registry,
      cipher: cipher,
    );
    await resourceService.grant(
      actor: await ProfileAuthorizationContext.capture(registry),
      targetProfileId: secondId,
      resourceId: resourceId,
      permissions: const <ResourcePermission>{ResourcePermission.use},
    );

    expect(await service.addonBorrowerCount(manifestUrl), 1);
    await expectLater(
      () => service.removeAddon(manifestUrl),
      throwsA(isA<StateError>()),
    );
    expect(await registry.getResource(resourceId), isNotNull);
    expect(await registry.getGrant(secondId, resourceId), isNotNull);

    await service.removeAddon(manifestUrl, revokeSharedProfiles: true);

    expect(await registry.getResource(resourceId), isNull);
    expect(await registry.getGrant(secondId, resourceId), isNull);
    expect(await service.getAddons(forSettings: true), isEmpty);
  });

  test('delete all atomically revokes shared addon access', () async {
    service.debugManifestFetcher = (url) async {
      final shared = url.contains('/shared/');
      return StremioAddon(
        id: shared ? 'bulk-shared-addon' : 'bulk-owned-addon',
        name: shared ? 'Bulk shared addon' : 'Bulk owned addon',
        manifestUrl: url,
        baseUrl: shared
            ? 'https://addon.invalid/shared'
            : 'https://addon.invalid/owned',
        types: const <String>['movie'],
        resources: const <String>['stream'],
      );
    };
    final shared = await service.addAddon(
      'https://addon.invalid/shared/manifest.json',
    );
    final owned = await service.addAddon(
      'https://addon.invalid/owned/manifest.json',
    );
    final resourceService = ConnectionResourceService(
      registry: registry,
      cipher: cipher,
    );
    await resourceService.grant(
      actor: await ProfileAuthorizationContext.capture(registry),
      targetProfileId: secondId,
      resourceId: shared.connectionResourceId!,
      permissions: const <ResourcePermission>{ResourcePermission.use},
    );
    final borrowerRevision = (await registry.getProfile(
      secondId,
    ))!.authorizationRevision;

    expect(await service.sharedAddonCount(), 1);
    await expectLater(
      () => service.clearAllAddons(),
      throwsA(isA<StateError>()),
    );
    expect(await registry.getResource(shared.connectionResourceId!), isNotNull);
    expect(await registry.getResource(owned.connectionResourceId!), isNotNull);

    await service.clearAllAddons(revokeSharedProfiles: true);

    expect(await registry.getResource(shared.connectionResourceId!), isNull);
    expect(await registry.getResource(owned.connectionResourceId!), isNull);
    expect(
      await registry.getGrant(secondId, shared.connectionResourceId!),
      isNull,
    );
    expect(
      (await registry.getProfile(secondId))!.authorizationRevision,
      borrowerRevision + 1,
    );
    expect(await service.getAddons(forSettings: true), isEmpty);
  });
}

class _RotatingReadCipher implements DeviceSecretCipher {
  _RotatingReadCipher(this.delegate, this.rotate);
  final DeviceSecretCipher delegate;
  final Future<void> Function() rotate;
  bool reject = true;
  int reads = 0;
  @override
  Future<void> initialize() => delegate.initialize();
  @override
  Future<String> seal(
    List<int> plaintext, {
    required List<int> associatedData,
  }) => delegate.seal(plaintext, associatedData: associatedData);
  @override
  Future<List<int>> open(
    String envelope, {
    required List<int> associatedData,
  }) async {
    reads++;
    final plaintext = await delegate.open(
      envelope,
      associatedData: associatedData,
    );
    if (reject) await rotate();
    return plaintext;
  }
}
