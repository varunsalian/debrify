import 'dart:convert';
import 'dart:io';

import 'package:debrify/models/profiles/connection_resource.dart';
import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/profiles/connection_resource_service.dart';
import 'package:debrify/services/profiles/device_key_provider.dart';
import 'package:debrify/services/profiles/native_profile_projection.dart';
import 'package:debrify/services/profiles/profile_authorization.dart';
import 'package:debrify/services/profiles/profile_bootstrap.dart';
import 'package:debrify/services/profiles/profile_collection_resource_facade.dart';
import 'package:debrify/services/profiles/profile_credential_facade.dart';
import 'package:debrify/services/profiles/profile_package_service.dart';
import 'package:debrify/services/profiles/profile_registry.dart';
import 'package:debrify/services/profiles/profile_restore_coordinator.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/profiles/profile_session_unavailable.dart';
import 'package:debrify/services/stremio_service.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/utils/app_storage.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _FailingReadCipher implements DeviceSecretCipher {
  _FailingReadCipher(this.failure, {this.beforeFailure});
  final DeviceVaultFailure failure;
  final Future<void> Function()? beforeFailure;
  @override
  Future<void> initialize() async {}
  @override
  Future<String> seal(
    List<int> plaintext, {
    required List<int> associatedData,
  }) => throw UnimplementedError();
  @override
  Future<List<int>> open(
    String envelope, {
    required List<int> associatedData,
  }) async {
    await beforeFailure?.call();
    throw DeviceVaultException(failure: failure, operation: 'open');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('debrify/device_secret');
  late Directory directory;
  late ProfileRegistry registry;
  late MemoryDeviceSecretCipher cipher;
  late ConnectionResourceService service;
  late ProfileScope scope;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    ProfileRuntime.debugReset();
    DeviceKeyProvider.debugReset();
    directory = await Directory.systemTemp.createTemp('connection-recovery-');
    AppStorage.debugOverride(
      documents: directory,
      support: directory,
      cache: directory,
    );
    registry = await ProfileRegistry.open(
      path: p.join(directory.path, 'profiles.db'),
    );
    final owner = await registry.createProfile(
      name: 'Owner',
      role: UserProfileRole.admin,
    );
    await registry.commitBootstrap(
      activeProfileId: owner.id,
      migratedLegacyInstall: false,
    );
    cipher = MemoryDeviceSecretCipher(List<int>.generate(32, (i) => i + 1));
    await cipher.initialize();
    service = ConnectionResourceService(registry: registry, cipher: cipher);
    DeviceKeyProvider.debugInstallCipher(cipher);
    ProfileBootstrap.debugInstallRegistry(registry);
    scope = ProfileScope(
      profileId: owner.id,
      dataGeneration: 1,
      sessionEpoch: 1,
    );
    ProfileRuntime.initializeCommitted(scope);
    StremioService().invalidateCache();
    StremioService().debugManifestFetcher = null;
  });
  tearDown(() async {
    StremioService().debugManifestFetcher = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await NativeProfileProjection.clear();
    StremioService().invalidateCache();
    ProfileRuntime.debugReset();
    ProfileBootstrap.debugInstallRegistry(null);
    DeviceKeyProvider.debugReset();
    AppStorage.debugReset();
    await registry.close();
    await directory.delete(recursive: true);
  });

  Future<ConnectionResource> createAddon(String name) async => service.create(
    context: await ProfileAuthorizationContext.capture(registry),
    type: ConnectionResourceType.stremioAddon,
    label: name,
    publicConfig: {'addonName': name},
    secretConfig: {
      'name': name,
      'manifest_url': 'https://$name.invalid/manifest.json',
      'base_url': 'https://$name.invalid',
      'resources': ['stream'],
    },
  );

  Future<String> corrupt(ConnectionResource resource) async {
    // A valid envelope encrypted under another key models an AEAD failure,
    // rather than merely triggering a parser error in a fake cipher.
    final other = MemoryDeviceSecretCipher(List<int>.filled(32, 99));
    final envelope = await other.seal(
      utf8.encode('{"private":"unreadable"}'),
      associatedData: ConnectionResourceService.associatedDataForSecret(
        resourceId: resource.id,
        type: resource.type,
        ownerProfileId: resource.ownerProfileId,
        publicSchemaVersion: resource.publicSchemaVersion,
        payloadVersion: 1,
      ),
    );
    await registry.updateResourceSecret(
      resourceId: resource.id,
      sealedSecretPayload: envelope,
      secretPayloadVersion: 1,
    );
    return envelope;
  }

  Future<List<Map<String, dynamic>>> read({
    bool settings = false,
    bool transfer = false,
  }) => ProfileCollectionResourceFacade.read(
    types: {ConnectionResourceType.stremioAddon},
    feature: ProfileFeature.addonUse,
    forSettings: settings,
    forRemoteTransfer: transfer,
  );

  test(
    'startup isolates a bad addon, preserves it on saves, and accepts a repair',
    () async {
      final bad = await createAddon('bad');
      final good = await createAddon('good');
      final original = await corrupt(bad);
      await NativeProfileProjection.publish(scope);
      final prefs = await SharedPreferences.getInstance();
      final projection =
          jsonDecode(prefs.getString(NativeProfileProjection.deviceKey)!)
              as Map;
      expect(projection['state'], 'active');
      final nativeAddons =
          jsonDecode(
                (projection['values'] as Map)['stremio_addons_v1'] as String,
              )
              as List;
      expect(nativeAddons.single['id'], good.id);
      var settings = await read(settings: true);
      expect(settings, hasLength(2));
      final pending = settings.singleWhere((row) => row['id'] == bad.id);
      expect(pending['_connectionResourceSecretPending'], isTrue);
      expect(pending['manifest_url'], isEmpty);
      expect(pending['description'], contains('Reconnect required'));
      await expectLater(
        read(transfer: true),
        throwsA(isA<ResourceSecretUnavailableException>()),
      );
      await expectLater(
        ProfilePackageService(
          registry: registry,
          resources: service,
        ).exportAllProfiles(
          context: await ProfileAuthorizationContext.capture(registry),
          includeSecrets: true,
          includeDatabases: false,
        ),
        throwsA(isA<ResourceSecretUnavailableException>()),
      );

      final badRevision = (await registry.getResource(
        bad.id,
      ))!.authorizationRevision;
      for (final rows in [await read(), settings]) {
        await service.replaceOwnedCollection(
          context: await ProfileAuthorizationContext.capture(registry),
          types: {ConnectionResourceType.stremioAddon},
          feature: ProfileFeature.addonsAndEngines,
          preserveUnavailable: true,
          items: [
            for (final row in rows)
              ResourceCollectionItem(
                type: ConnectionResourceType.stremioAddon,
                label: row['name'] as String,
                publicConfig: {'addonName': row['name']},
                secretConfig: row,
                sourceResourceId: row['_connectionResourceId'] as String,
              ),
          ],
        );
        expect(
          (await registry.getSealedResourceSecret(bad.id))!.envelope,
          original,
        );
        expect(
          (await registry.getResource(bad.id))!.authorizationRevision,
          badRevision,
        );
        expect((await registry.getResource(bad.id))!.secretPending, isFalse);
      }
      await service.updateSecret(
        context: await ProfileAuthorizationContext.capture(registry),
        resourceId: bad.id,
        secretConfig: {
          'name': 'Repaired',
          'manifest_url': 'https://repaired.invalid/manifest.json',
          'base_url': 'https://repaired.invalid',
        },
      );
      expect((await registry.getResource(bad.id))!.needsReconnect, isFalse);
      expect(await read(), hasLength(2));
    },
  );

  test(
    'unreadable scalar credential becomes reconnectable and can be replaced',
    () async {
      final resource = await service.create(
        context: await ProfileAuthorizationContext.capture(registry),
        type: ConnectionResourceType.torbox,
        label: 'TorBox',
        publicConfig: {},
        secretConfig: {'apiKey': 'original'},
        bindingSlot: 'provider.torbox',
      );
      final original = await corrupt(resource);
      expect(
        (await ProfileCredentialFacade.read('torbox_api_key')).value,
        isNull,
      );
      expect(
        (await ProfileCredentialFacade.isConfigured('torbox_api_key')).pending,
        isTrue,
      );
      expect(
        (await registry.getSealedResourceSecret(resource.id))!.envelope,
        original,
      );
      await ProfileCredentialFacade.write('torbox_api_key', 'repaired');
      expect(
        (await ProfileCredentialFacade.read('torbox_api_key')).value,
        'repaired',
      );
      expect(
        (await ProfileCredentialFacade.isConfigured('torbox_api_key')).pending,
        isFalse,
      );
    },
  );

  test('automatic addon hydration retains an unreadable sibling', () async {
    final bad = await createAddon('bad');
    final original = await corrupt(bad);
    const url = 'https://restored.invalid/manifest.json';
    final restored = await service.create(
      context: await ProfileAuthorizationContext.capture(registry),
      type: ConnectionResourceType.stremioAddon,
      label: 'Restored',
      publicConfig: {'addonName': 'Restored'},
      secretConfig: {'manifestUrl': url},
    );
    StremioService().debugManifestFetcher = (manifestUrl) async => StremioAddon(
      id: 'provider',
      name: 'Restored',
      manifestUrl: manifestUrl,
      baseUrl: 'https://restored.invalid',
      resources: ['stream'],
    );
    final executable = await StremioService().getAddons();
    expect(executable.single.connectionResourceId, restored.id);
    expect(
      (await registry.getSealedResourceSecret(bad.id))!.envelope,
      original,
    );
    expect(await read(settings: true), hasLength(2));
  });

  test(
    'an explicit WebDAV disconnect can remove an unreadable connection',
    () async {
      final resource = await service.create(
        context: await ProfileAuthorizationContext.capture(registry),
        type: ConnectionResourceType.webDav,
        label: 'DAV',
        publicConfig: {},
        secretConfig: {
          'name': 'DAV',
          'baseUrl': 'https://dav.invalid',
          'password': 'saved',
        },
      );
      await corrupt(resource);
      expect(
        (await StorageService.getWebDavServers()).single.credentialsRedacted,
        isTrue,
      );
      await StorageService.deleteWebDavServer(resource.id);
      expect(await registry.getResource(resource.id), isNull);
    },
  );

  for (final failure in [
    DeviceVaultFailure.unavailable,
    DeviceVaultFailure.missing,
    DeviceVaultFailure.unreadable,
  ]) {
    test(
      'global vault ${failure.name} is not hidden as a bad connection',
      () async {
        final resource = await createAddon('addon');
        DeviceKeyProvider.debugInstallCipher(_FailingReadCipher(failure));
        await expectLater(
          NativeProfileProjection.publish(scope),
          throwsA(isA<DeviceVaultException>()),
        );
        expect(
          (await registry.getResource(resource.id))!.needsReconnect,
          isFalse,
        );
      },
    );
  }

  test(
    'a profile switch during a failed read still rejects the collection',
    () async {
      await createAddon('addon');
      final actor = await ProfileAuthorizationContext.capture(registry);
      final other = await registry.createProfile(
        name: 'Other',
        role: UserProfileRole.member,
        actingProfileId: actor.profileId,
        actingAuthorizationRevision: actor.authorizationRevision,
        actingSessionEpoch: scope.sessionEpoch,
      );
      DeviceKeyProvider.debugInstallCipher(
        _FailingReadCipher(
          DeviceVaultFailure.recordUnreadable,
          beforeFailure: () async {
            ProfileRuntime.publish(
              ProfileScope(
                profileId: other.id,
                dataGeneration: 1,
                sessionEpoch: 2,
              ),
            );
          },
        ),
      );
      await expectLater(
        read(settings: true),
        throwsA(isA<ProfileSessionUnavailable>()),
      );
    },
  );

  test(
    'removing one unreadable addon uses resource identity, not the empty URL',
    () async {
      final first = await createAddon('first');
      final second = await createAddon('second');
      await corrupt(first);
      await corrupt(second);
      final addons = await StremioService().getAddons(forSettings: true);
      expect(
        addons.every((addon) => addon.connectionResourceSecretPending),
        isTrue,
      );
      await StremioService().removeAddon(second.id);
      expect(await registry.getResource(first.id), isNotNull);
      expect(await registry.getResource(second.id), isNull);
    },
  );

  test(
    'failed native readback leaves existing credentials and restore graph unchanged',
    () async {
      final resource = await createAddon('good');
      final original = (await registry.getSealedResourceSecret(
        resource.id,
      ))!.envelope;
      final package =
          await ProfilePackageService(
            registry: registry,
            resources: service,
          ).exportAllProfiles(
            context: await ProfileAuthorizationContext.capture(registry),
            includeSecrets: true,
            includeDatabases: false,
          );
      final beforeProfiles = (await registry.listProfiles(
        includeDisabled: true,
      )).map((p) => p.id).toList();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'seal') return 'unusable';
            if (call.method == 'open') {
              throw PlatformException(code: 'device_secret_record_unreadable');
            }
            return 'ready';
          });
      final platform = PlatformDeviceSecretCipher();
      final failingService = ConnectionResourceService(
        registry: registry,
        cipher: platform,
      );
      await expectLater(
        failingService.updateSecret(
          context: await ProfileAuthorizationContext.capture(registry),
          resourceId: resource.id,
          secretConfig: {'name': 'replacement'},
        ),
        throwsA(isA<DeviceVaultException>()),
      );
      expect(
        (await registry.getSealedResourceSecret(resource.id))!.envelope,
        original,
      );
      await expectLater(
        ProfileRestoreCoordinator(
          registry: registry,
          cipher: platform,
        ).restoreDeviceGraph(
          package: package,
          authorization: await ProfileAuthorizationContext.capture(registry),
        ),
        throwsA(isA<DeviceVaultException>()),
      );
      expect(
        (await registry.listProfiles(includeDisabled: true)).map((p) => p.id),
        beforeProfiles,
      );
      expect(
        (await registry.getSealedResourceSecret(resource.id))!.envelope,
        original,
      );
      expect(ProfileRuntime.scope.value, scope);
    },
  );
}
