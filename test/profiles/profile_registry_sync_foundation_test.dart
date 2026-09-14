import 'dart:convert';
import 'dart:io';

import 'package:debrify/models/profiles/connection_resource.dart';
import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/models/profiles/user_profile.dart';
import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/profiles/profile_registry.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_tombstones.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory temporaryDirectory;
  late String databasePath;
  late ProfileRegistry registry;
  late List<Set<WebDavSyncRegistryRecordId>> tombstoneBatches;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'registry-sync-foundation-',
    );
    databasePath = p.join(temporaryDirectory.path, 'profiles.db');
    registry = await ProfileRegistry.open(path: databasePath);
    tombstoneBatches = <Set<WebDavSyncRegistryRecordId>>[];
  });

  tearDown(() async {
    WebDavSyncTombstoneRecorder.debugReset();
    ProfilePreferences.webDavSyncLocalChangeSink = null;
    await registry.close();
    await temporaryDirectory.delete(recursive: true);
  });

  Future<Database> raw() => databaseFactory.openDatabase(
    databasePath,
    options: OpenDatabaseOptions(singleInstance: false),
  );

  ConnectionResource resource(
    String id,
    String ownerProfileId, {
    int authorizationRevision = 1,
    ConnectionResourceType type = ConnectionResourceType.realDebrid,
    String? label,
  }) => ConnectionResource(
    id: id,
    type: type,
    label: label ?? id,
    ownerProfileId: ownerProfileId,
    publicConfig: const <String, dynamic>{'schemaVersion': 1},
    authorizationRevision: authorizationRevision,
    enabled: true,
  );

  int allPermissions() => ResourcePermission.values.fold<int>(
    0,
    (value, permission) => value | permission.bit,
  );

  Future<UserProfile> admin([String id = 'admin']) => registry.createProfile(
    id: id,
    name: 'Admin $id',
    role: UserProfileRole.admin,
    policy: ProfilePolicy.allAllowedFor(UserProfileRole.admin),
  );

  void captureRegistryTombstones() {
    WebDavSyncTombstoneRecorder.debugInstall(
      registrySink: (records) => tombstoneBatches.add(records),
    );
  }

  test(
    'local registry writes schedule sync but remote apply does not loop',
    () async {
      final keys = <String>[];
      ProfilePreferences.webDavSyncLocalChangeSink = (_, key) => keys.add(key);

      await admin();
      expect(keys, <String>[ProfilePreferences.webDavSyncRegistryLogicalKey]);
      keys.clear();

      await registry.applySyncedRegistryDelta(
        SyncedRegistryDelta(
          profiles: <SyncedRegistryProfileRecord>[
            SyncedRegistryProfileRecord(
              id: 'remote-member',
              name: 'Remote member',
              role: UserProfileRole.member,
              policy: ProfilePolicy.defaultsFor(UserProfileRole.member),
              enabled: true,
              lockOnResume: false,
              setupComplete: true,
              updatedAtMs: 1,
            ),
          ],
        ),
      );
      expect(keys, isEmpty);
    },
  );

  test('sync delta returns a typed conflict and aborts every row', () async {
    final local = await admin('edited-admin');
    final observed = (await registry.readProfileSyncProjection()).singleWhere(
      (entry) => entry.profile.id == local.id,
    );
    await Future<void>.delayed(const Duration(milliseconds: 2));
    await registry.updateProfile(id: local.id, name: 'Fresh local edit');

    final result = await registry.applySyncedRegistryDelta(
      SyncedRegistryDelta(
        profiles: <SyncedRegistryProfileRecord>[
          SyncedRegistryProfileRecord(
            id: local.id,
            name: 'Stale remote value',
            role: local.role,
            policy: local.policy,
            enabled: true,
            lockOnResume: local.lockOnResume,
            setupComplete: local.setupComplete,
            updatedAtMs: observed.updatedAtMs + 1,
            expectedPriorUpdatedAtMs: observed.updatedAtMs,
          ),
          SyncedRegistryProfileRecord(
            id: 'must-not-be-created',
            name: 'Atomic companion',
            role: UserProfileRole.member,
            policy: ProfilePolicy.defaultsFor(UserProfileRole.member),
            enabled: true,
            lockOnResume: false,
            setupComplete: true,
            updatedAtMs: observed.updatedAtMs + 1,
          ),
        ],
      ),
    );

    expect(result, SyncedRegistryApplyResult.conflict);
    expect((await registry.getProfile(local.id))?.name, 'Fresh local edit');
    expect(await registry.getProfile('must-not-be-created'), isNull);
  });

  test('fresh v8 schema and v6 upgrade have exact defaults/backfill', () async {
    var db = await raw();
    Future<Map<String, Map<String, Object?>>> columns(String table) async => {
      for (final row in await db.rawQuery('PRAGMA table_info($table)'))
        row['name']! as String: row,
    };

    expect(
      (await columns(
        'profile_resource_grants',
      ))['updated_at_ms']!['dflt_value'],
      '0',
    );
    expect(
      (await columns(
        'profile_resource_settings',
      ))['updated_at_ms']!['dflt_value'],
      '0',
    );
    expect(
      (await columns('connection_resources'))['secret_pending']!['dflt_value'],
      '0',
    );
    expect(await columns('webdav_sync_tombstone_outbox'), contains('id'));
    await db.close();

    await registry.close();
    final v6Path = p.join(temporaryDirectory.path, 'v6.db');
    db = await databaseFactory.openDatabase(
      v6Path,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    String withoutV7(String statement) => statement
        .replaceAll('      secret_pending INTEGER NOT NULL DEFAULT 0,\n', '')
        .replaceAll('      updated_at_ms INTEGER NOT NULL DEFAULT 0,\n', '');
    for (final statement in ProfileRegistry.debugSchemaStatements) {
      if (statement.contains('webdav_sync_tombstone_outbox')) {
        continue;
      }
      await db.execute(withoutV7(statement));
    }
    await db.insert('user_profiles', <String, Object?>{
      'id': 'admin-v6',
      'name': 'Admin',
      'role': UserProfileRole.admin.name,
      'policy_json': ProfilePolicy.allAllowedFor(
        UserProfileRole.admin,
      ).encode(),
      'policy_schema_version': ProfilePolicy.currentSchemaVersion,
      'created_at_ms': 10,
      'updated_at_ms': 10,
    });
    await db.insert('connection_resources', <String, Object?>{
      'id': 'resource-v6',
      'type': ConnectionResourceType.realDebrid.name,
      'label': 'Resource',
      'owner_profile_id': 'admin-v6',
      'public_config_json': '{"schemaVersion":1}',
      'created_at_ms': 20,
      'updated_at_ms': 21,
    });
    await db.insert('profile_resource_grants', <String, Object?>{
      'profile_id': 'admin-v6',
      'resource_id': 'resource-v6',
      'permissions': 1,
      'grant_origin_json': '{}',
      'created_at_ms': 1234,
    });
    await db.insert('profile_resource_settings', <String, Object?>{
      'profile_id': 'admin-v6',
      'resource_id': 'resource-v6',
      'enabled': 1,
      'settings_json': '{}',
    });
    await db.execute('PRAGMA user_version = 6');
    await db.close();

    registry = await ProfileRegistry.open(path: v6Path);
    db = await databaseFactory.openDatabase(
      v6Path,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    expect(
      (await db.query('profile_resource_grants')).single['updated_at_ms'],
      1234,
    );
    expect(
      (await db.query('profile_resource_settings')).single['updated_at_ms'],
      0,
    );
    expect(
      (await db.query('connection_resources')).single['secret_pending'],
      0,
    );
    expect(
      (await db.rawQuery('PRAGMA user_version')).single['user_version'],
      ProfileRegistry.schemaVersion,
    );
    expect(await columns('webdav_sync_tombstone_outbox'), contains('id'));
    await db.close();
  });

  test('grant/settings writers stamp every approved inventory path', () async {
    final owner = await admin();
    await registry.insertResource(
      resource: resource('seed-resource', owner.id),
      sealedSecretPayload: 'secret',
      secretPayloadVersion: 1,
      ownerPermissions: allPermissions(),
    );
    var projection = await registry.readRegistrySyncProjection();
    expect(projection.grants.single.updatedAtMs, greaterThan(0));

    final member = await registry.createProfile(
      id: 'member',
      name: 'Member',
      role: UserProfileRole.member,
      policy: ProfilePolicy.allAllowedFor(UserProfileRole.member),
    );
    projection = await registry.readRegistrySyncProjection();
    expect(
      projection.grants
          .singleWhere(
            (grant) =>
                grant.profileId == member.id &&
                grant.resourceId == 'seed-resource',
          )
          .updatedAtMs,
      greaterThan(0),
    );

    await registry.insertResource(
      resource: resource('second-resource', owner.id),
      sealedSecretPayload: 'secret-2',
      secretPayloadVersion: 1,
      ownerPermissions: allPermissions(),
    );
    projection = await registry.readRegistrySyncProjection();
    for (final grant in projection.grants.where(
      (grant) => grant.resourceId == 'second-resource',
    )) {
      expect(grant.updatedAtMs, greaterThan(0));
    }

    var db = await raw();
    await db.update(
      'profile_resource_grants',
      <String, Object?>{'updated_at_ms': 1},
      where: 'profile_id = ? AND resource_id = ?',
      whereArgs: <Object>[member.id, 'seed-resource'],
    );
    await db.close();
    await registry.upsertGrant(
      profileId: member.id,
      resourceId: 'seed-resource',
      permissions: ResourcePermission.use.bit,
      grantedByProfileId: owner.id,
      origin: const <String, dynamic>{'origin': 'test'},
    );
    expect(
      (await registry.readRegistrySyncProjection()).grants
          .singleWhere(
            (grant) =>
                grant.profileId == member.id &&
                grant.resourceId == 'seed-resource',
          )
          .updatedAtMs,
      greaterThan(1),
    );

    await registry.initializeDeviceState(
      activeProfileId: member.id,
      bootstrapState: 'uninitialized',
      migrationState: 'notStarted',
    );
    await registry.setProfileResourceSettings(
      profileId: member.id,
      resourceId: 'seed-resource',
      enabled: false,
      settings: const <String, dynamic>{'layout': 'compact'},
      actingAuthorizationRevision: (await registry.getProfile(
        member.id,
      ))!.authorizationRevision,
      expectedResourceAuthorizationRevision: (await registry.getResource(
        'seed-resource',
      ))!.authorizationRevision,
      feature: ProfileFeature.cloud,
    );
    db = await raw();
    await db.update(
      'profile_resource_settings',
      <String, Object?>{'updated_at_ms': 1},
      where: 'profile_id = ? AND resource_id = ?',
      whereArgs: <Object>[member.id, 'seed-resource'],
    );
    await db.close();
    await registry.setProfileResourceSettings(
      profileId: member.id,
      resourceId: 'seed-resource',
      enabled: true,
      settings: const <String, dynamic>{'layout': 'wide'},
      actingAuthorizationRevision: (await registry.getProfile(
        member.id,
      ))!.authorizationRevision,
      expectedResourceAuthorizationRevision: (await registry.getResource(
        'seed-resource',
      ))!.authorizationRevision,
      feature: ProfileFeature.cloud,
    );
    expect(
      (await registry.readRegistrySyncProjection()).settings.single.updatedAtMs,
      greaterThan(1),
    );

    db = await raw();
    await db.update(
      'profile_resource_grants',
      <String, Object?>{'updated_at_ms': 1},
      where: 'profile_id = ? AND resource_id = ?',
      whereArgs: <Object>[member.id, 'seed-resource'],
    );
    await db.close();
    await registry.transferResourceOwnership(
      resourceId: 'seed-resource',
      currentOwnerProfileId: owner.id,
      newOwnerProfileId: member.id,
      resealedSecretPayload: 'transferred',
      secretPayloadVersion: 2,
      ownerPermissions: allPermissions(),
      transferredByProfileId: owner.id,
    );
    expect(
      (await registry.readRegistrySyncProjection()).grants
          .singleWhere(
            (grant) =>
                grant.profileId == member.id &&
                grant.resourceId == 'seed-resource',
          )
          .updatedAtMs,
      greaterThan(1),
    );

    await registry.replaceOwnedResourceCollection(
      ownerProfileId: owner.id,
      types: const <ConnectionResourceType>{ConnectionResourceType.webDav},
      replacements: <PreparedConnectionResource>[
        PreparedConnectionResource(
          resource: resource(
            'collection-resource',
            owner.id,
            type: ConnectionResourceType.webDav,
          ),
          sealedSecretPayload: 'collection-secret',
          secretPayloadVersion: 1,
        ),
      ],
      ownerPermissions: allPermissions(),
    );
    db = await raw();
    await db.update(
      'profile_resource_grants',
      <String, Object?>{'updated_at_ms': 1},
      where: 'profile_id = ? AND resource_id = ?',
      whereArgs: <Object>[owner.id, 'collection-resource'],
    );
    await db.close();
    await registry.replaceOwnedResourceCollection(
      ownerProfileId: owner.id,
      types: const <ConnectionResourceType>{ConnectionResourceType.webDav},
      replacements: <PreparedConnectionResource>[
        PreparedConnectionResource(
          resource: resource(
            'collection-resource',
            owner.id,
            authorizationRevision: 2,
            type: ConnectionResourceType.webDav,
          ),
          sealedSecretPayload: 'collection-secret-2',
          secretPayloadVersion: 2,
        ),
      ],
      ownerPermissions: allPermissions(),
    );
    expect(
      (await registry.readRegistrySyncProjection()).grants
          .singleWhere(
            (grant) =>
                grant.resourceId == 'collection-resource' &&
                grant.profileId == owner.id,
          )
          .updatedAtMs,
      greaterThan(1),
    );

    const graphProfileId = 'graph-member';
    await registry.beginProfileGraphRestore(
      operationId: 'graph-restore',
      stagedProfileIds: const <String>[graphProfileId],
    );
    await registry.createProfile(
      id: graphProfileId,
      name: 'Graph Member',
      role: UserProfileRole.member,
      lifecycle: UserProfileLifecycle.staging,
    );
    await registry.finalizeGraphProfileGeneration(
      operationId: 'graph-restore',
      profileId: graphProfileId,
      manifest: const <String, dynamic>{'version': 1},
      manifestHash: 'graph-hash',
    );
    await registry.verifyProfileGraphRestore('graph-restore');
    await registry.publishProfileGraphRestore(
      operationId: 'graph-restore',
      stagedProfileIds: const <String>[graphProfileId],
      resources: <StagedGraphResource>[
        StagedGraphResource(
          id: 'graph-resource',
          type: ConnectionResourceType.trakt,
          label: 'Graph resource',
          ownerProfileId: graphProfileId,
          publicConfig: const <String, dynamic>{'schemaVersion': 1},
          sealedSecretPayload: 'graph-secret',
          secretPayloadVersion: 1,
          grants: const <StagedGraphGrant>[
            StagedGraphGrant(profileId: graphProfileId, permissions: 1),
          ],
          bindings: const <StagedGraphBinding>[],
          settings: const <StagedGraphSettings>[
            StagedGraphSettings(profileId: graphProfileId, enabled: true),
          ],
        ),
      ],
    );
    projection = await registry.readRegistrySyncProjection();
    expect(
      projection.grants
          .singleWhere((grant) => grant.resourceId == 'graph-resource')
          .updatedAtMs,
      greaterThan(0),
    );
    expect(
      projection.settings
          .singleWhere((setting) => setting.resourceId == 'graph-resource')
          .updatedAtMs,
      greaterThan(0),
    );

    final generation = await registry.reserveDataGeneration(
      profileId: owner.id,
      operationId: 'data-restore',
      mode: 'merge',
    );
    await registry.stageRestoreResource(
      operationId: 'data-restore',
      backupId: 'backup-resource',
      resourceId: 'data-resource',
      type: ConnectionResourceType.trakt,
      label: 'Data resource',
      ownerProfileId: owner.id,
      publicConfig: const <String, dynamic>{'schemaVersion': 1},
      sealedSecretPayload: 'data-secret',
      secretPayloadVersion: 1,
      permissions: 1,
      profileEnabled: true,
      profileSettings: const <String, dynamic>{},
    );
    await registry.updateStagedGenerationManifest(
      profileId: owner.id,
      generation: generation,
      operationId: 'data-restore',
      manifest: const <String, dynamic>{'version': 1},
      manifestHash: 'data-hash',
    );
    await registry.publishDataGeneration(
      profileId: owner.id,
      baseGeneration: 1,
      stagedGeneration: generation,
      operationId: 'data-restore',
    );
    projection = await registry.readRegistrySyncProjection();
    expect(
      projection.grants
          .singleWhere((grant) => grant.resourceId == 'data-resource')
          .updatedAtMs,
      greaterThan(0),
    );
    expect(
      projection.settings
          .singleWhere((setting) => setting.resourceId == 'data-resource')
          .updatedAtMs,
      greaterThan(0),
    );
  });

  test(
    'sync delta orders relations and drives secret_pending transitions',
    () async {
      const adminId = 'circle-admin';
      const memberId = 'circle-member';
      const resourceId = 'circle-resource';
      await registry.applySyncedRegistryDelta(
        SyncedRegistryDelta(
          profiles: <SyncedRegistryProfileRecord>[
            SyncedRegistryProfileRecord(
              id: adminId,
              name: 'Circle Admin',
              role: UserProfileRole.admin,
              policy: ProfilePolicy.allAllowedFor(UserProfileRole.admin),
              enabled: true,
              lockOnResume: true,
              setupComplete: true,
              updatedAtMs: 100,
            ),
            SyncedRegistryProfileRecord(
              id: memberId,
              name: 'Circle Member',
              role: UserProfileRole.member,
              policy: ProfilePolicy.allAllowedFor(UserProfileRole.member),
              enabled: true,
              lockOnResume: false,
              setupComplete: true,
              updatedAtMs: 101,
            ),
          ],
          resources: <SyncedRegistryResourceRecord>[
            SyncedRegistryResourceRecord(
              resource: resource(resourceId, adminId),
              updatedAtMs: 200,
            ),
          ],
          grants: const <SyncedRegistryGrantRecord>[
            SyncedRegistryGrantRecord(
              profileId: adminId,
              resourceId: resourceId,
              permissions: 63,
              updatedAtMs: 201,
            ),
            SyncedRegistryGrantRecord(
              profileId: memberId,
              resourceId: resourceId,
              permissions: 1,
              updatedAtMs: 202,
            ),
          ],
          settings: const <SyncedRegistrySettingsRecord>[
            SyncedRegistrySettingsRecord(
              profileId: memberId,
              resourceId: resourceId,
              enabled: true,
              settings: <String, dynamic>{'view': 'grid'},
              updatedAtMs: 203,
            ),
          ],
          bindings: const <SyncedRegistryBindingRecord>[
            SyncedRegistryBindingRecord(
              profileId: memberId,
              slot: 'provider.realDebrid',
              resourceId: resourceId,
              updatedAtMs: 204,
            ),
          ],
        ),
      );

      var syncedResource = await registry.getResource(resourceId);
      expect(syncedResource!.secretPending, isTrue);
      expect(await registry.getSealedResourceSecret(resourceId), isNull);
      var projection = await registry.readRegistrySyncProjection();
      expect(projection.resources.single.updatedAtMs, 200);
      expect(projection.grants.map((item) => item.updatedAtMs), [201, 202]);
      expect(projection.settings.single.updatedAtMs, 203);
      expect(projection.bindings.single.updatedAtMs, 204);

      await registry.applySyncedRegistryDelta(
        SyncedRegistryDelta(
          resources: <SyncedRegistryResourceRecord>[
            SyncedRegistryResourceRecord(
              resource: resource(resourceId, adminId, label: 'With secret'),
              updatedAtMs: 300,
              sealedSecretPayload: 'local-sealed-secret',
              secretPayloadVersion: 1,
              expectedPriorUpdatedAtMs: 200,
            ),
          ],
        ),
      );
      syncedResource = await registry.getResource(resourceId);
      expect(syncedResource!.secretPending, isFalse);
      expect(
        (await registry.getSealedResourceSecret(resourceId))!.envelope,
        'local-sealed-secret',
      );

      await registry.applySyncedRegistryDelta(
        SyncedRegistryDelta(
          resources: <SyncedRegistryResourceRecord>[
            SyncedRegistryResourceRecord(
              resource: resource(resourceId, adminId, label: 'Metadata only'),
              updatedAtMs: 400,
              expectedPriorUpdatedAtMs: 300,
            ),
          ],
        ),
      );
      syncedResource = await registry.getResource(resourceId);
      expect(syncedResource!.secretPending, isFalse);
      expect(
        (await registry.getSealedResourceSecret(resourceId))!.envelope,
        'local-sealed-secret',
      );

      await registry.applySyncedRegistryDelta(
        SyncedRegistryDelta(
          deletes: <SyncedRegistryDeleteRecord>[
            SyncedRegistryDeleteRecord(
              record: WebDavSyncRegistryRecordId.binding(
                memberId,
                'provider.realDebrid',
                resourceId: resourceId,
              ),
              expectedPriorUpdatedAtMs: 204,
            ),
            SyncedRegistryDeleteRecord(
              record: WebDavSyncRegistryRecordId.setting(memberId, resourceId),
              expectedPriorUpdatedAtMs: 203,
            ),
            SyncedRegistryDeleteRecord(
              record: WebDavSyncRegistryRecordId.grant(memberId, resourceId),
              expectedPriorUpdatedAtMs: 202,
            ),
          ],
        ),
      );
      projection = await registry.readRegistrySyncProjection();
      expect(projection.settings, isEmpty);
      expect(projection.bindings, isEmpty);
      expect(
        projection.grants.where((grant) => grant.profileId == memberId),
        isEmpty,
      );
      final db = await raw();
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      await db.close();
    },
  );

  test('synced profile creation never seeds default resource grants', () async {
    final owner = await admin();
    await registry.insertResource(
      resource: resource('preexisting-shareable', owner.id),
      sealedSecretPayload: 'secret',
      secretPayloadVersion: 1,
      ownerPermissions: allPermissions(),
    );

    await registry.applySyncedRegistryDelta(
      SyncedRegistryDelta(
        profiles: <SyncedRegistryProfileRecord>[
          SyncedRegistryProfileRecord(
            id: 'remote-member',
            name: 'Remote member',
            role: UserProfileRole.member,
            policy: ProfilePolicy.defaultsFor(UserProfileRole.member),
            enabled: true,
            lockOnResume: false,
            setupComplete: true,
            updatedAtMs: 500,
          ),
        ],
      ),
    );

    expect(await registry.getProfile('remote-member'), isNotNull);
    expect(
      await registry.getGrant('remote-member', 'preexisting-shareable'),
      isNull,
    );
  });

  test(
    'fresh peer accepts a managing grant retained by a child downgrade',
    () async {
      await registry.applySyncedRegistryDelta(
        SyncedRegistryDelta(
          profiles: <SyncedRegistryProfileRecord>[
            SyncedRegistryProfileRecord(
              id: 'surviving-admin',
              name: 'Surviving Admin',
              role: UserProfileRole.admin,
              policy: ProfilePolicy.allAllowedFor(UserProfileRole.admin),
              enabled: true,
              lockOnResume: false,
              setupComplete: true,
              updatedAtMs: 10,
            ),
            SyncedRegistryProfileRecord(
              id: 'downgraded-child',
              name: 'Downgraded Child',
              role: UserProfileRole.child,
              policy: ProfilePolicy.defaultsFor(UserProfileRole.child),
              enabled: true,
              lockOnResume: false,
              setupComplete: true,
              updatedAtMs: 11,
            ),
          ],
          resources: <SyncedRegistryResourceRecord>[
            SyncedRegistryResourceRecord(
              resource: resource('retained-grant-resource', 'surviving-admin'),
              updatedAtMs: 12,
            ),
          ],
          grants: <SyncedRegistryGrantRecord>[
            SyncedRegistryGrantRecord(
              profileId: 'downgraded-child',
              resourceId: 'retained-grant-resource',
              permissions:
                  ResourcePermission.use.bit | ResourcePermission.manage.bit,
              updatedAtMs: 13,
            ),
          ],
        ),
      );

      expect(
        (await registry.getGrant(
          'downgraded-child',
          'retained-grant-resource',
        ))?.permissions,
        ResourcePermission.use.bit | ResourcePermission.manage.bit,
      );
    },
  );

  test(
    'sync delta refuses active deletion and preserves admin invariant',
    () async {
      final first = await admin('first-admin');
      final member = await registry.createProfile(
        id: 'active-member',
        name: 'Member',
        role: UserProfileRole.member,
      );
      await registry.commitBootstrap(
        activeProfileId: first.id,
        migratedLegacyInstall: false,
      );
      final firstVersion = (await registry.readProfileSyncProjection())
          .singleWhere((entry) => entry.profile.id == first.id)
          .updatedAtMs;
      await expectLater(
        registry.applySyncedRegistryDelta(
          SyncedRegistryDelta(
            deletes: <SyncedRegistryDeleteRecord>[
              SyncedRegistryDeleteRecord(
                record: WebDavSyncRegistryRecordId.profile(first.id),
                expectedPriorUpdatedAtMs: firstVersion,
              ),
            ],
          ),
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('active profile'),
          ),
        ),
      );
      expect(await registry.getProfile(first.id), isNotNull);

      await registry.setActiveProfile(member.id);
      final refreshedFirstVersion = (await registry.readProfileSyncProjection())
          .singleWhere((entry) => entry.profile.id == first.id)
          .updatedAtMs;
      await expectLater(
        registry.applySyncedRegistryDelta(
          SyncedRegistryDelta(
            deletes: <SyncedRegistryDeleteRecord>[
              SyncedRegistryDeleteRecord(
                record: WebDavSyncRegistryRecordId.profile(first.id),
                expectedPriorUpdatedAtMs: refreshedFirstVersion,
              ),
            ],
          ),
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('enabled managing Admin'),
          ),
        ),
      );
      expect(await registry.getProfile(first.id), isNotNull);
    },
  );

  test(
    'profile/resource/grant/binding delete chokepoints capture cascades',
    () async {
      final owner = await admin();
      final member = await registry.createProfile(
        id: 'borrower',
        name: 'Borrower',
        role: UserProfileRole.member,
      );
      await registry.insertResource(
        resource: resource('shared-resource', owner.id),
        sealedSecretPayload: 'secret',
        secretPayloadVersion: 1,
        ownerPermissions: allPermissions(),
        bindingSlot: 'provider.realDebrid',
      );
      await registry.upsertGrant(
        profileId: member.id,
        resourceId: 'shared-resource',
        permissions: ResourcePermission.use.bit,
        grantedByProfileId: owner.id,
        origin: const <String, dynamic>{},
        bindingSlot: 'provider.realDebrid',
      );
      captureRegistryTombstones();

      await registry.unbindResource(member.id, 'provider.realDebrid');
      expect(
        tombstoneBatches.removeLast().single.kind,
        WebDavSyncRegistryRecordKind.binding,
      );

      await registry.revokeGrant(member.id, 'shared-resource');
      final grantCascade = tombstoneBatches.removeLast();
      expect(
        grantCascade,
        contains(
          WebDavSyncRegistryRecordId.grant(member.id, 'shared-resource'),
        ),
      );

      await registry.upsertGrant(
        profileId: member.id,
        resourceId: 'shared-resource',
        permissions: ResourcePermission.use.bit,
        grantedByProfileId: owner.id,
        origin: const <String, dynamic>{},
      );
      await registry.revokeGrantsOnOwnedResources(ownerProfileId: owner.id);
      expect(
        tombstoneBatches.removeLast(),
        contains(
          WebDavSyncRegistryRecordId.grant(member.id, 'shared-resource'),
        ),
      );

      await registry.upsertGrant(
        profileId: member.id,
        resourceId: 'shared-resource',
        permissions: ResourcePermission.use.bit,
        grantedByProfileId: owner.id,
        origin: const <String, dynamic>{},
      );
      await registry.initializeDeviceState(
        activeProfileId: member.id,
        bootstrapState: 'uninitialized',
        migrationState: 'notStarted',
      );
      await registry.detachBorrowedResource(
        profileId: member.id,
        authorizationRevision: (await registry.getProfile(
          member.id,
        ))!.authorizationRevision,
        resourceId: 'shared-resource',
        expectedResourceAuthorizationRevision: (await registry.getResource(
          'shared-resource',
        ))!.authorizationRevision,
      );
      expect(
        tombstoneBatches.removeLast(),
        contains(
          WebDavSyncRegistryRecordId.grant(member.id, 'shared-resource'),
        ),
      );

      await registry.deleteOwnedResource(
        resourceId: 'shared-resource',
        ownerProfileId: owner.id,
        revokeBorrowers: true,
      );
      final resourceCascade = tombstoneBatches.removeLast();
      expect(
        resourceCascade,
        contains(
          WebDavSyncRegistryRecordId.resource(
            'shared-resource',
            ownerProfileId: owner.id,
          ),
        ),
      );

      const stagingId = 'staging-delete';
      await registry.createProfile(
        id: stagingId,
        name: 'Staging',
        role: UserProfileRole.member,
        lifecycle: UserProfileLifecycle.staging,
      );
      final baselineResource = WebDavSyncRegistryRecordId.resource(
        'baseline-resource',
        ownerProfileId: stagingId,
      );
      final baselineGrant = WebDavSyncRegistryRecordId.grant(
        stagingId,
        'baseline-resource',
      );
      await registry.deleteProfile(
        stagingId,
        mergedBaselineRecords: <WebDavSyncRegistryRecordId>[
          baselineResource,
          baselineGrant,
        ],
      );
      final profileCascade = tombstoneBatches.removeLast();
      expect(
        profileCascade,
        contains(WebDavSyncRegistryRecordId.profile(stagingId)),
      );
      expect(
        profileCascade,
        containsAll(<WebDavSyncRegistryRecordId>[
          baselineResource,
          baselineGrant,
        ]),
      );
    },
  );

  test(
    'rolled-back collection delete leaves no tombstone outbox row',
    () async {
      final owner = await admin();
      await registry.insertResource(
        resource: resource(
          'rollback-resource',
          owner.id,
          type: ConnectionResourceType.webDav,
        ),
        sealedSecretPayload: 'secret',
        secretPayloadVersion: 1,
        ownerPermissions: allPermissions(),
      );
      captureRegistryTombstones();

      await expectLater(
        registry.replaceOwnedResourceCollection(
          ownerProfileId: owner.id,
          types: const <ConnectionResourceType>{ConnectionResourceType.webDav},
          replacements: <PreparedConnectionResource>[
            PreparedConnectionResource(
              resource: resource(
                'invalid-replacement',
                owner.id,
                authorizationRevision: 2,
                type: ConnectionResourceType.webDav,
              ),
              sealedSecretPayload: 'replacement-secret',
              secretPayloadVersion: 1,
            ),
          ],
          ownerPermissions: allPermissions(),
        ),
        throwsStateError,
      );

      expect(await registry.getResource('rollback-resource'), isNotNull);
      expect(tombstoneBatches, isEmpty);
      final db = await raw();
      expect(await db.query('webdav_sync_tombstone_outbox'), isEmpty);
      await db.close();
    },
  );

  test(
    'failed tombstone drain retains and retries the committed outbox',
    () async {
      final owner = await admin();
      await registry.insertResource(
        resource: resource('drain-resource', owner.id),
        sealedSecretPayload: 'secret',
        secretPayloadVersion: 1,
        ownerPermissions: allPermissions(),
        bindingSlot: 'provider.realDebrid',
      );
      WebDavSyncTombstoneRecorder.debugInstall(
        registrySink: (_) => throw StateError('simulated drain failure'),
      );

      await registry.unbindResource(owner.id, 'provider.realDebrid');
      var db = await raw();
      expect(await db.query('webdav_sync_tombstone_outbox'), hasLength(1));
      await db.close();
      final pendingSnapshot = await registry.readCircleSyncProjection();
      expect(pendingSnapshot.outboxRowCount, 1);
      expect(pendingSnapshot.registry.bindings, isEmpty);

      captureRegistryTombstones();
      await registry.drainWebDavSyncTombstoneOutbox();

      expect(
        tombstoneBatches.single.single.kind,
        WebDavSyncRegistryRecordKind.binding,
      );
      db = await raw();
      expect(await db.query('webdav_sync_tombstone_outbox'), isEmpty);
      await db.close();
      expect((await registry.readCircleSyncProjection()).outboxRowCount, 0);
    },
  );

  test('concurrent tombstone drains serialize through row deletion', () async {
    final record = WebDavSyncRegistryRecordId.profile('same-profile');
    final db = await raw();
    for (final time in <int>[100, 200]) {
      await db.insert('webdav_sync_tombstone_outbox', <String, Object?>{
        'namespace_id': 'namespace',
        'origin_device_id': time == 100 ? 'device-old' : 'device-new',
        'created_at_ms': time,
        'records_json': jsonEncode(<Object?>[record.toJson()]),
      });
    }
    await db.close();
    final repository = _DelayedRegistryTombstoneRepository();
    WebDavSyncTombstoneRecorder.debugInstall(registryRepository: repository);

    final drains = await Future.wait<bool>(<Future<bool>>[
      registry.drainWebDavSyncTombstoneOutbox(),
      registry.drainWebDavSyncTombstoneOutbox(),
    ]);

    expect(drains, everyElement(isTrue));
    expect(repository.recordCalls, 2);
    expect(repository.records[record.storageKey]?.timeMs, 200);
    expect(repository.records[record.storageKey]?.originDeviceId, 'device-new');
    final verify = await raw();
    expect(await verify.query('webdav_sync_tombstone_outbox'), isEmpty);
    await verify.close();
  });

  test('bound outbox insert failure aborts the registry delete', () async {
    final owner = await admin();
    await registry.insertResource(
      resource: resource('insert-failure-resource', owner.id),
      sealedSecretPayload: 'secret',
      secretPayloadVersion: 1,
      ownerPermissions: allPermissions(),
      bindingSlot: 'provider.realDebrid',
    );
    captureRegistryTombstones();
    final db = await raw();
    await db.execute('''
      CREATE TRIGGER fail_tombstone_outbox_insert
      BEFORE INSERT ON webdav_sync_tombstone_outbox
      BEGIN
        SELECT RAISE(ABORT, 'simulated outbox failure');
      END
    ''');
    await db.close();

    await expectLater(
      registry.unbindResource(owner.id, 'provider.realDebrid'),
      throwsA(anything),
    );

    expect(
      await registry.getBoundResourceId(owner.id, 'provider.realDebrid'),
      'insert-failure-resource',
    );
    expect(tombstoneBatches, isEmpty);
  });

  test(
    'restore redundant-default prune captures its dependent leaves',
    () async {
      final owner = await admin();
      await registry.insertResource(
        resource: resource(
          'default-addon',
          owner.id,
          type: ConnectionResourceType.stremioAddon,
        ),
        sealedSecretPayload: 'addon-secret',
        secretPayloadVersion: 1,
        ownerPermissions: allPermissions(),
      );
      const stagedId = 'prune-profile';
      await registry.beginProfileGraphRestore(
        operationId: 'prune-restore',
        stagedProfileIds: const <String>[stagedId],
      );
      await registry.createProfile(
        id: stagedId,
        name: 'Prune profile',
        role: UserProfileRole.member,
        lifecycle: UserProfileLifecycle.staging,
      );
      await registry.bindResource(
        profileId: stagedId,
        slot: 'addon.default',
        resourceId: 'default-addon',
      );
      final db = await raw();
      await db.insert('profile_resource_settings', <String, Object?>{
        'profile_id': stagedId,
        'resource_id': 'default-addon',
        'enabled': 1,
        'settings_json': '{}',
        'updated_at_ms': 1,
      });
      await db.close();
      await registry.finalizeGraphProfileGeneration(
        operationId: 'prune-restore',
        profileId: stagedId,
        manifest: const <String, dynamic>{'version': 1},
        manifestHash: 'prune-hash',
      );
      await registry.verifyProfileGraphRestore('prune-restore');
      captureRegistryTombstones();

      await registry.publishProfileGraphRestore(
        operationId: 'prune-restore',
        stagedProfileIds: const <String>[stagedId],
        resources: const <StagedGraphResource>[],
        redundantDefaultAddonGrants: const <GraphRestoreDefaultGrantPrune>[
          GraphRestoreDefaultGrantPrune(
            profileId: stagedId,
            resourceId: 'default-addon',
            expectedResourceAuthorizationRevision: 1,
          ),
        ],
      );

      final captured = tombstoneBatches.single;
      expect(
        captured,
        contains(WebDavSyncRegistryRecordId.grant(stagedId, 'default-addon')),
      );
      expect(
        captured,
        contains(WebDavSyncRegistryRecordId.setting(stagedId, 'default-addon')),
      );
      expect(
        captured,
        contains(
          WebDavSyncRegistryRecordId.binding(
            stagedId,
            'addon.default',
            resourceId: 'default-addon',
          ),
        ),
      );
    },
  );

  test(
    'collection removal and disposition capture resource/profile rows',
    () async {
      final owner = await admin();
      captureRegistryTombstones();
      await registry.replaceOwnedResourceCollection(
        ownerProfileId: owner.id,
        types: const <ConnectionResourceType>{ConnectionResourceType.webDav},
        replacements: <PreparedConnectionResource>[
          PreparedConnectionResource(
            resource: resource(
              'collection-delete',
              owner.id,
              type: ConnectionResourceType.webDav,
            ),
            sealedSecretPayload: 'secret',
            secretPayloadVersion: 1,
          ),
        ],
        ownerPermissions: allPermissions(),
      );
      await registry.replaceOwnedResourceCollection(
        ownerProfileId: owner.id,
        types: const <ConnectionResourceType>{ConnectionResourceType.webDav},
        replacements: const <PreparedConnectionResource>[],
        ownerPermissions: allPermissions(),
      );
      expect(
        tombstoneBatches.removeLast(),
        contains(
          WebDavSyncRegistryRecordId.resource(
            'collection-delete',
            ownerProfileId: owner.id,
          ),
        ),
      );

      final retired = await registry.createProfile(
        id: 'retired',
        name: 'Retired',
        role: UserProfileRole.member,
      );
      await registry.deleteProfileWithDisposition(
        id: retired.id,
        deleteOwnedResources: true,
        detachPublicArtifacts: true,
      );
      expect(
        tombstoneBatches.removeLast(),
        contains(WebDavSyncRegistryRecordId.profile(retired.id)),
      );
    },
  );

  test(
    'importRecoverySnapshot deliberately emits no registry tombstones',
    () async {
      await admin();
      final snapshot = await registry.exportRecoverySnapshot();
      await registry.createProfile(
        id: 'later-profile',
        name: 'Later',
        role: UserProfileRole.member,
      );
      captureRegistryTombstones();

      await registry.importRecoverySnapshot(snapshot);

      expect(tombstoneBatches, isEmpty);
      expect(await registry.getProfile('later-profile'), isNull);
    },
  );
}

final class _DelayedRegistryTombstoneRepository
    implements WebDavSyncRegistryTombstoneRepository {
  final Map<String, WebDavSyncRegistryRecordTombstone> records =
      <String, WebDavSyncRegistryRecordTombstone>{};
  int recordCalls = 0;

  @override
  Future<Map<String, WebDavSyncRegistryRecordTombstone>> load(
    String namespaceId,
  ) async =>
      Map<String, WebDavSyncRegistryRecordTombstone>.unmodifiable(records);

  @override
  Future<Map<String, WebDavSyncRegistryRecordTombstone>> freeze(
    String namespaceId, {
    required int clockOffsetMs,
    required int serverNowMs,
  }) async =>
      Map<String, WebDavSyncRegistryRecordTombstone>.unmodifiable(records);

  @override
  Future<void> record(
    String namespaceId, {
    required String deviceId,
    required Iterable<WebDavSyncRegistryRecordId> records,
    required int nowMs,
  }) async {
    recordCalls++;
    await Future<void>.delayed(const Duration(milliseconds: 10));
    for (final record in records) {
      final incoming = WebDavSyncRegistryRecordTombstone(
        record: record,
        timeMs: nowMs,
        originDeviceId: deviceId,
      );
      final old = this.records[record.storageKey];
      if (old == null ||
          incoming.timeMs > old.timeMs ||
          incoming.timeMs == old.timeMs &&
              incoming.originDeviceId.compareTo(old.originDeviceId) > 0) {
        this.records[record.storageKey] = incoming;
      }
    }
  }
}
