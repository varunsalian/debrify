import 'dart:io';

import 'package:debrify/models/profiles/connection_resource.dart';
import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/services/profiles/device_job_store.dart';
import 'package:debrify/services/profiles/profile_bootstrap.dart';
import 'package:debrify/services/profiles/profile_registry.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory temporaryDirectory;
  late ProfileRegistry registry;
  late String adminId;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp('jobs-test-');
    registry = await ProfileRegistry.open(
      path: p.join(temporaryDirectory.path, 'profiles.db'),
    );
    adminId = (await registry.createProfile(
      name: 'Admin',
      role: UserProfileRole.admin,
    )).id;
    ProfileBootstrap.debugInstallRegistry(registry);
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeCommitted(
      ProfileScope(profileId: adminId, dataGeneration: 1, sessionEpoch: 1),
    );
  });

  tearDown(() async {
    ProfileRuntime.debugReset();
    ProfileBootstrap.debugInstallRegistry(null);
    await registry.close();
    await temporaryDirectory.delete(recursive: true);
  });

  test(
    'captures immutable ownership and rejects a stale policy revision',
    () async {
      final authorization = await DeviceJobStore.authorize(
        ProfileFeature.downloads,
      );
      expect(authorization, isNotNull);

      await DeviceJobStore.register(
        backend: 'testBackend',
        externalJobId: 'task-1',
        kind: DeviceJobKind.download,
        authorization: authorization!,
      );
      final rows = await registry.listJobOwnership(ownerProfileId: adminId);
      expect(rows, hasLength(1));
      expect(rows.single['owner_profile_id'], adminId);
      expect(
        rows.single['profile_authorization_revision'],
        authorization.profileAuthorizationRevision,
      );

      await registry.updateProfile(
        id: adminId,
        policy: ProfilePolicy(
          enabled: ProfileFeature.values.toSet()
            ..remove(ProfileFeature.downloads),
        ),
      );
      expect(
        await DeviceJobStore.validateAuthorization(
          profileId: adminId,
          profileAuthorizationRevision:
              authorization.profileAuthorizationRevision,
          feature: ProfileFeature.downloads,
        ),
        isFalse,
      );
    },
  );

  test('reconciliation marks only missing owner jobs terminal', () async {
    final authorization = (await DeviceJobStore.authorize(
      ProfileFeature.recordings,
    ))!;
    for (final id in <String>['present', 'missing']) {
      await DeviceJobStore.register(
        backend: 'testBackend',
        externalJobId: id,
        kind: DeviceJobKind.recording,
        authorization: authorization,
      );
    }

    await DeviceJobStore.reconcileBackend(
      backend: 'testBackend',
      ownerProfileId: adminId,
      presentExternalJobIds: const <String>['present'],
    );

    final active = await registry.listJobOwnership(
      ownerProfileId: adminId,
      includeTerminal: false,
    );
    expect(active.map((row) => row['external_job_id']), <String>['present']);
  });

  test('resource-bound job is revoked by credential rotation', () async {
    const resourceId = 'resource-rd';
    await registry.insertResource(
      resource: ConnectionResource(
        id: resourceId,
        type: ConnectionResourceType.realDebrid,
        label: 'Real-Debrid',
        ownerProfileId: adminId,
        publicConfig: const <String, dynamic>{'schemaVersion': 1},
        authorizationRevision: 1,
        enabled: true,
      ),
      sealedSecretPayload: 'sealed-v1',
      secretPayloadVersion: 1,
      ownerPermissions: ResourcePermission.values.fold<int>(
        0,
        (mask, permission) => mask | permission.bit,
      ),
    );
    final authorization = (await DeviceJobStore.authorize(
      ProfileFeature.downloads,
    ))!;

    expect(
      await DeviceJobStore.validateAuthorization(
        profileId: adminId,
        profileAuthorizationRevision:
            authorization.profileAuthorizationRevision,
        feature: ProfileFeature.downloads,
        resourceId: resourceId,
        resourceAuthorizationRevision: 1,
      ),
      isTrue,
    );
    await DeviceJobStore.register(
      backend: 'testBackend',
      externalJobId: 'resource-task',
      kind: DeviceJobKind.download,
      authorization: authorization,
      resourceId: resourceId,
      resourceAuthorizationRevision: 1,
    );
    final row = (await registry.listJobOwnership(
      ownerProfileId: adminId,
    )).single;
    expect(row['resource_id'], resourceId);
    expect(row['resource_authorization_revision'], 1);

    await registry.updateResourceSecret(
      resourceId: resourceId,
      sealedSecretPayload: 'sealed-v2',
      secretPayloadVersion: 1,
    );
    expect(
      await DeviceJobStore.validateAuthorization(
        profileId: adminId,
        profileAuthorizationRevision:
            authorization.profileAuthorizationRevision,
        feature: ProfileFeature.downloads,
        resourceId: resourceId,
        resourceAuthorizationRevision: 1,
      ),
      isFalse,
    );
  });

  test('revision drift tolerance survives a bump but not revocation', () async {
    const resourceId = 'resource-drift';
    await registry.insertResource(
      resource: ConnectionResource(
        id: resourceId,
        type: ConnectionResourceType.iptvM3u,
        label: 'IPTV source',
        ownerProfileId: adminId,
        publicConfig: const <String, dynamic>{},
        authorizationRevision: 1,
        enabled: true,
      ),
      sealedSecretPayload: 'sealed-v1',
      secretPayloadVersion: 1,
      ownerPermissions: ResourcePermission.values.fold<int>(
        0,
        (mask, permission) => mask | permission.bit,
      ),
    );
    final authorization = (await DeviceJobStore.authorize(
      ProfileFeature.recordings,
    ))!;

    // Any collection save bumps every retained resource — the stored job
    // revision goes stale without anything about THIS resource changing.
    await registry.updateResourceSecret(
      resourceId: resourceId,
      sealedSecretPayload: 'sealed-v2',
      secretPayloadVersion: 1,
    );

    Future<bool> validate({bool drift = false}) =>
        DeviceJobStore.validateAuthorization(
          profileId: adminId,
          profileAuthorizationRevision:
              authorization.profileAuthorizationRevision,
          feature: ProfileFeature.recordings,
          resourceId: resourceId,
          resourceAuthorizationRevision: 1,
          allowRevisionDrift: drift,
        );

    expect(await validate(), isFalse, reason: 'strict stays strict');
    expect(await validate(drift: true), isTrue,
        reason: 'a replayed job outlives an unrelated collection save');

    // Drift never bypasses the live gates: an unbound record and a deleted
    // resource still refuse.
    expect(
      await DeviceJobStore.validateAuthorization(
        profileId: adminId,
        profileAuthorizationRevision:
            authorization.profileAuthorizationRevision,
        feature: ProfileFeature.recordings,
        resourceId: resourceId,
        resourceAuthorizationRevision: null,
        allowRevisionDrift: true,
      ),
      isFalse,
    );
    await registry.deleteOwnedResource(
      resourceId: resourceId,
      ownerProfileId: adminId,
      revokeBorrowers: true,
    );
    expect(await validate(drift: true), isFalse);
  });

  test('use-only resource grant cannot authorize downloads', () async {
    const resourceId = 'resource-use-only';
    await registry.insertResource(
      resource: ConnectionResource(
        id: resourceId,
        type: ConnectionResourceType.realDebrid,
        label: 'Shared provider',
        ownerProfileId: adminId,
        publicConfig: const <String, dynamic>{},
        authorizationRevision: 1,
        enabled: true,
      ),
      sealedSecretPayload: 'sealed',
      secretPayloadVersion: 1,
      ownerPermissions: ResourcePermission.values.fold<int>(
        0,
        (mask, permission) => mask | permission.bit,
      ),
    );
    final member = await registry.createProfile(
      name: 'Member',
      role: UserProfileRole.member,
    );
    await registry.upsertGrant(
      profileId: member.id,
      resourceId: resourceId,
      permissions: ResourcePermission.use.bit,
      grantedByProfileId: adminId,
      origin: const <String, dynamic>{'origin': 'test'},
    );
    final current = (await registry.getProfile(member.id))!;

    expect(
      await DeviceJobStore.validateAuthorization(
        profileId: member.id,
        profileAuthorizationRevision: current.authorizationRevision,
        feature: ProfileFeature.downloads,
        resourceId: resourceId,
        resourceAuthorizationRevision: 1,
      ),
      isFalse,
    );
    expect(
      await DeviceJobStore.validateAuthorization(
        profileId: member.id,
        profileAuthorizationRevision: current.authorizationRevision,
        feature: ProfileFeature.downloads,
        resourceId: resourceId,
        resourceAuthorizationRevision: 1,
        requiredResourcePermission: ResourcePermission.use,
      ),
      isTrue,
    );
  });
}
