import 'dart:async';
import 'dart:io';

import 'package:debrify/models/profiles/connection_resource.dart';
import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/services/alldebrid_account_service.dart';
import 'package:debrify/services/profiles/connection_resource_service.dart';
import 'package:debrify/services/profiles/device_key_provider.dart';
import 'package:debrify/services/profiles/profile_authorization.dart';
import 'package:debrify/services/profiles/profile_bootstrap.dart';
import 'package:debrify/services/profiles/profile_credential_facade.dart';
import 'package:debrify/services/profiles/profile_registry.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory temporaryDirectory;
  late ProfileRegistry registry;
  late ConnectionResourceService resources;
  late MemoryDeviceSecretCipher cipher;
  late String adminId;
  late String memberId;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'credential-disconnect-test-',
    );
    registry = await ProfileRegistry.open(
      path: p.join(temporaryDirectory.path, 'profiles.db'),
    );
    adminId = (await registry.createProfile(
      name: 'Admin',
      role: UserProfileRole.admin,
    )).id;
    memberId = (await registry.createProfile(
      name: 'Member',
      role: UserProfileRole.member,
    )).id;
    await registry.commitBootstrap(
      activeProfileId: adminId,
      migratedLegacyInstall: false,
    );
    cipher = MemoryDeviceSecretCipher(List<int>.generate(32, (i) => i));
    await cipher.initialize();
    DeviceKeyProvider.debugInstallCipher(cipher);
    ProfileBootstrap.debugInstallRegistry(registry);
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeCommitted(
      ProfileScope(profileId: adminId, dataGeneration: 1, sessionEpoch: 1),
    );
    resources = ConnectionResourceService(registry: registry, cipher: cipher);
    AllDebridAccountService.clearUserInfo();
  });

  tearDown(() async {
    ProfileRuntime.debugReset();
    ProfileBootstrap.debugInstallRegistry(null);
    DeviceKeyProvider.debugReset();
    await registry.close();
    await temporaryDirectory.delete(recursive: true);
  });

  Future<ConnectionResource> createTrakt() async {
    final resource = await resources.create(
      context: await ProfileAuthorizationContext.capture(registry),
      type: ConnectionResourceType.trakt,
      label: 'Trakt',
      publicConfig: const <String, dynamic>{},
      secretConfig: const <String, dynamic>{
        'accessToken': 'access',
        'refreshToken': 'refresh',
      },
    );
    await registry.bindResource(
      profileId: adminId,
      slot: 'tracker.trakt',
      resourceId: resource.id,
    );
    return resource;
  }

  test(
    'borrower logout detaches locally and never requests remote revoke',
    () async {
      final resource = await createTrakt();
      await resources.grant(
        actor: await ProfileAuthorizationContext.capture(registry),
        targetProfileId: memberId,
        resourceId: resource.id,
        permissions: const <ResourcePermission>{ResourcePermission.use},
      );
      await registry.setActiveProfile(memberId);
      ProfileRuntime.publish(
        ProfileScope(profileId: memberId, dataGeneration: 1, sessionEpoch: 2),
      );
      await registry.bindResource(
        profileId: memberId,
        slot: 'tracker.trakt',
        resourceId: resource.id,
      );

      expect(await StorageService.clearTraktAuth(), isFalse);
      expect(await registry.getGrant(memberId, resource.id), isNull);
      expect(await registry.getResource(resource.id), isNotNull);
    },
  );

  test('use-only scalar credential cannot be exported remotely', () async {
    final resource = await createTrakt();
    await resources.grant(
      actor: await ProfileAuthorizationContext.capture(registry),
      targetProfileId: memberId,
      resourceId: resource.id,
      permissions: const <ResourcePermission>{ResourcePermission.use},
    );
    await registry.bindResource(
      profileId: memberId,
      slot: 'tracker.trakt',
      resourceId: resource.id,
    );
    await registry.setActiveProfile(memberId);
    ProfileRuntime.publish(
      ProfileScope(profileId: memberId, dataGeneration: 1, sessionEpoch: 2),
    );

    expect(await StorageService.getTraktAccessToken(), 'access');
    expect(
      await StorageService.getTraktAccessToken(forRemoteTransfer: true),
      isNull,
    );

    await registry.setActiveProfile(adminId);
    ProfileRuntime.publish(
      ProfileScope(profileId: adminId, dataGeneration: 1, sessionEpoch: 3),
    );
    await resources.grant(
      actor: await ProfileAuthorizationContext.capture(registry),
      targetProfileId: memberId,
      resourceId: resource.id,
      permissions: const <ResourcePermission>{
        ResourcePermission.use,
        ResourcePermission.writeRemote,
      },
    );
    await registry.setActiveProfile(memberId);
    ProfileRuntime.publish(
      ProfileScope(profileId: memberId, dataGeneration: 1, sessionEpoch: 4),
    );
    expect(
      await StorageService.getTraktAccessToken(forRemoteTransfer: true),
      'access',
    );
  });

  test(
    'AllDebrid refresh treats a switch-to-Admin revocation as cancellation',
    () async {
      final resource = await resources.create(
        context: await ProfileAuthorizationContext.capture(registry),
        type: ConnectionResourceType.allDebrid,
        label: 'Shared AllDebrid',
        publicConfig: const <String, dynamic>{},
        secretConfig: const <String, dynamic>{'apiKey': 'ad-secret'},
        bindingSlot: 'provider.allDebrid',
      );
      await resources.grant(
        actor: await ProfileAuthorizationContext.capture(registry),
        targetProfileId: memberId,
        resourceId: resource.id,
        permissions: const <ResourcePermission>{ResourcePermission.use},
      );
      await registry.setActiveProfile(memberId);
      ProfileRuntime.publish(
        ProfileScope(profileId: memberId, dataGeneration: 1, sessionEpoch: 2),
      );

      final blockingCipher = _BlockingOpenCipher(cipher);
      DeviceKeyProvider.debugInstallCipher(blockingCipher);
      final refresh = AllDebridAccountService.refreshUserInfo();
      await blockingCipher.started.future;

      await registry.setActiveProfile(adminId);
      ProfileRuntime.publish(
        ProfileScope(profileId: adminId, dataGeneration: 1, sessionEpoch: 3),
      );
      blockingCipher.release();

      expect(await refresh, isFalse);
    },
  );

  test('shared owner logout fails before deleting or revoking', () async {
    final resource = await createTrakt();
    await resources.grant(
      actor: await ProfileAuthorizationContext.capture(registry),
      targetProfileId: memberId,
      resourceId: resource.id,
      permissions: const <ResourcePermission>{ResourcePermission.use},
    );

    expect(
      StorageService.clearTraktAuth,
      throwsA(isA<ResourceImpactRequiredException>()),
    );
    expect(await registry.getResource(resource.id), isNotNull);
    expect(await registry.getGrant(memberId, resource.id), isNotNull);
  });

  test('an owner can replace a synced secret-pending credential', () async {
    const resourceId = 'pending-rd';
    await registry.applySyncedRegistryDelta(
      SyncedRegistryDelta(
        resources: <SyncedRegistryResourceRecord>[
          SyncedRegistryResourceRecord(
            resource: ConnectionResource(
              id: resourceId,
              type: ConnectionResourceType.realDebrid,
              label: 'Pending Real-Debrid',
              ownerProfileId: adminId,
              publicConfig: const <String, dynamic>{'schemaVersion': 1},
              publicSchemaVersion: 1,
              authorizationRevision: 1,
              enabled: true,
              secretPending: true,
            ),
            updatedAtMs: 10,
          ),
        ],
        grants: <SyncedRegistryGrantRecord>[
          SyncedRegistryGrantRecord(
            profileId: adminId,
            resourceId: resourceId,
            permissions: ResourcePermission.values.fold<int>(
              0,
              (mask, permission) => mask | permission.bit,
            ),
            updatedAtMs: 11,
          ),
        ],
      ),
    );
    await registry.bindResource(
      profileId: adminId,
      slot: 'provider.realDebrid',
      resourceId: resourceId,
    );

    expect(
      await ProfileCredentialFacade.write('real_debrid_api_key', 'fresh-key'),
      isTrue,
    );

    expect((await registry.getResource(resourceId))!.secretPending, isFalse);
    expect(await StorageService.getApiKey(), 'fresh-key');
    expect(await StorageService.hasRealDebridCredential(), isTrue);
  });

  test(
    'pending shared credential field removal updates instead of deleting',
    () async {
      const resourceId = 'pending-shared-rd';
      await registry.applySyncedRegistryDelta(
        SyncedRegistryDelta(
          resources: <SyncedRegistryResourceRecord>[
            SyncedRegistryResourceRecord(
              resource: ConnectionResource(
                id: resourceId,
                type: ConnectionResourceType.realDebrid,
                label: 'Pending shared Real-Debrid',
                ownerProfileId: adminId,
                publicConfig: const <String, dynamic>{'schemaVersion': 1},
                publicSchemaVersion: 1,
                authorizationRevision: 1,
                enabled: true,
                secretPending: true,
              ),
              updatedAtMs: 10,
            ),
          ],
          grants: <SyncedRegistryGrantRecord>[
            SyncedRegistryGrantRecord(
              profileId: adminId,
              resourceId: resourceId,
              permissions: ResourcePermission.values.fold<int>(
                0,
                (mask, permission) => mask | permission.bit,
              ),
              updatedAtMs: 11,
            ),
            SyncedRegistryGrantRecord(
              profileId: memberId,
              resourceId: resourceId,
              permissions: ResourcePermission.use.bit,
              updatedAtMs: 12,
            ),
          ],
        ),
      );
      await registry.bindResource(
        profileId: adminId,
        slot: 'provider.realDebrid',
        resourceId: resourceId,
      );

      expect(
        await ProfileCredentialFacade.remove('real_debrid_api_key'),
        isTrue,
      );

      final resource = await registry.getResource(resourceId);
      expect(resource, isNotNull);
      expect(resource!.secretPending, isFalse);
      expect(await registry.getGrant(memberId, resourceId), isNotNull);
      expect(await StorageService.getApiKey(), isNull);
    },
  );

  test(
    'unshared owner logout deletes resource then permits remote revoke',
    () async {
      final resource = await createTrakt();

      expect(await StorageService.clearTraktAuth(), isTrue);
      expect(await registry.getResource(resource.id), isNull);
      expect(
        await registry.getBoundResourceId(adminId, 'tracker.trakt'),
        isNull,
      );
    },
  );
}

class _BlockingOpenCipher implements DeviceSecretCipher {
  final DeviceSecretCipher delegate;
  final Completer<void> started = Completer<void>();
  final Completer<void> _released = Completer<void>();

  _BlockingOpenCipher(this.delegate);

  @override
  Future<void> initialize() => delegate.initialize();

  @override
  Future<List<int>> open(
    String envelope, {
    required List<int> associatedData,
  }) async {
    if (!started.isCompleted) started.complete();
    await _released.future;
    return delegate.open(envelope, associatedData: associatedData);
  }

  @override
  Future<String> seal(
    List<int> plaintext, {
    required List<int> associatedData,
  }) => delegate.seal(plaintext, associatedData: associatedData);

  void release() {
    if (!_released.isCompleted) _released.complete();
  }
}
