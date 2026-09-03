import 'dart:convert';
import 'dart:io';

import 'package:debrify/models/profiles/connection_resource.dart';
import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/models/profiles/user_profile.dart';
import 'package:debrify/services/profiles/connection_resource_service.dart';
import 'package:debrify/services/profiles/device_key_provider.dart';
import 'package:debrify/services/profiles/profile_authorization.dart';
import 'package:debrify/services/profiles/profile_bootstrap.dart';
import 'package:debrify/services/profiles/profile_lock_controller.dart';
import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/profiles/profile_registry.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_circle_models.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_codec.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_engine_state.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_hot_merge.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_hot_models.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_local_adapter.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_tombstones.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory directory;
  late ProfileRegistry registry;
  late MemoryDeviceSecretCipher cipher;
  late ProfileWebDavSyncLocalAdapter adapter;
  late WebDavSyncLocalSession session;
  late String activeId;
  late OpenedWebDavSyncRoot circleRoot;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    directory = await Directory.systemTemp.createTemp('circle-adapter-');
    registry = await ProfileRegistry.open(
      path: p.join(directory.path, 'profiles.db'),
    );
    activeId = (await registry.createProfile(
      id: 'local-active-admin',
      name: 'Local Admin',
      role: UserProfileRole.admin,
      policy: ProfilePolicy.allAllowedFor(UserProfileRole.admin),
    )).id;
    await registry.commitBootstrap(
      activeProfileId: activeId,
      migratedLegacyInstall: false,
    );
    cipher = MemoryDeviceSecretCipher(List<int>.generate(32, (i) => i));
    await cipher.initialize();
    DeviceKeyProvider.debugInstallCipher(cipher);
    ProfileBootstrap.debugInstallRegistry(registry);
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeCommitted(
      ProfileScope(profileId: activeId, dataGeneration: 1, sessionEpoch: 1),
    );
    adapter = ProfileWebDavSyncLocalAdapter(registry);
    session = await adapter.beginCycle();
    final codec = WebDavSyncCodec();
    final marker = await codec.sealRoot(
      passphrase: 'passphrase',
      circleId: 'circle-1',
      createdAt: DateTime.utc(2026, 9, 1),
      memoryKiB: 8,
      iterations: 1,
    );
    circleRoot = await codec.openRoot(marker, 'passphrase');
  });

  tearDown(() async {
    ProfileLockController.instance.dispose();
    ProfileRuntime.debugReset();
    ProfileBootstrap.debugInstallRegistry(null);
    DeviceKeyProvider.debugReset();
    await registry.close();
    await directory.delete(recursive: true);
  });

  test('an unchanged playback target reports zero applied keys', () async {
    const playback = '{"movie":{"positionMs":42000}}';
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(WebDavSyncHotMerge.playbackPreference, playback);
    session = await adapter.beginCycle();

    final appliedKeys = await adapter.applyProfile(
      session,
      activeId,
      const <String, Object>{WebDavSyncHotMerge.playbackPreference: playback},
    );

    expect(appliedKeys, isEmpty);
  });

  test(
    'foreign profile is created before its resource without grant seeding',
    () async {
      final request = _request(
        root: circleRoot,
        profiles: _profiles(
          <String, WebDavSyncCircleLeaf<WebDavSyncProfileValue>>{
            'p-owner': _profileLeaf('Remote Owner', 10),
          },
        ),
        resources: _resources(
          metadata: _metadataLeaf(owner: 'p-owner', time: 11),
          grants:
              const <
                String,
                Map<String, WebDavSyncCircleLeaf<WebDavSyncGrantValue>>
              >{},
        ),
        profileMap: <String, String>{
          'p-active': activeId,
          'p-owner': 'remote-owner',
        },
        resourceMap: const <String, String>{'r-shared': 'remote-resource'},
      );

      await adapter.applyCircleState(session, request);

      expect(await registry.getProfile('remote-owner'), isNotNull);
      expect(
        (await registry.getResource('remote-resource'))?.ownerProfileId,
        'remote-owner',
      );
      expect(
        (await registry.getResource('remote-resource'))?.secretPending,
        isTrue,
      );
      expect(
        await registry.getGrant('remote-owner', 'remote-resource'),
        isNull,
      );
      final db = await databaseFactory.openDatabase(
        p.join(directory.path, 'profiles.db'),
        options: OpenDatabaseOptions(singleInstance: false),
      );
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      await db.close();
    },
  );

  test(
    'circle apply conflicts preserve an edit made after its snapshot',
    () async {
      final maps = WebDavSyncIdentityMaps(
        circleToLocalProfiles: <String, String>{'p-active': activeId},
        circleToLocalResources: const <String, String>{},
      );
      final built = await adapter.buildCircleState(
        session,
        WebDavSyncCircleBuildRequest(
          identityMaps: maps,
          deviceId: 'device-local',
          circleId: circleRoot.document.circleId,
          circleKey: circleRoot.key,
          localNowMs: DateTime.now().millisecondsSinceEpoch,
          clockOffsetMs: 0,
          serverNowMs: DateTime.now().millisecondsSinceEpoch,
        ),
      );
      final observed = built.profiles.profiles['p-active']!;
      await Future<void>.delayed(const Duration(milliseconds: 2));
      final actor = await ProfileAuthorizationContext.capture(registry);
      await registry.updateProfile(
        id: activeId,
        name: 'Edited locally',
        actingProfileId: actor.profileId,
        actingAuthorizationRevision: actor.authorizationRevision,
        actingSessionEpoch: actor.sessionEpoch,
      );

      final result = await adapter.applyCircleState(
        session,
        _request(
          root: circleRoot,
          profiles:
              _profiles(<String, WebDavSyncCircleLeaf<WebDavSyncProfileValue>>{
                'p-active': _profileLeaf(
                  'Stale remote',
                  observed.stamp.normalizedTimeMs + 1,
                ),
              }),
          resources: _emptyResources(),
          profileMap: <String, String>{'p-active': activeId},
          resourceMap: const <String, String>{},
          registryVersions: built.registryVersions,
        ),
      );

      expect(result, WebDavSyncCircleApplyResult.conflict);
      expect((await registry.getProfile(activeId))?.name, 'Edited locally');
      final followUp = await adapter.buildCircleState(
        session,
        WebDavSyncCircleBuildRequest(
          identityMaps: maps,
          deviceId: 'device-local',
          circleId: circleRoot.document.circleId,
          circleKey: circleRoot.key,
          localNowMs: DateTime.now().millisecondsSinceEpoch,
          clockOffsetMs: 0,
          serverNowMs: DateTime.now().millisecondsSinceEpoch,
          previousProfiles: built.profiles,
          previousResources: built.resources,
        ),
      );
      expect(
        followUp.profiles.profiles['p-active']!.value!.name,
        'Edited locally',
      );
      expect(
        followUp.profiles.profiles['p-active']!.stamp.normalizedTimeMs,
        greaterThan(observed.stamp.normalizedTimeMs),
      );
    },
  );

  test(
    'circle apply conflicts do not resurrect a post-snapshot deletion',
    () async {
      final tombstones = <WebDavSyncRegistryRecordId>{};
      WebDavSyncTombstoneRecorder.debugInstall(
        registrySink: (records) => tombstones.addAll(records),
      );
      addTearDown(WebDavSyncTombstoneRecorder.debugReset);
      final actor = await ProfileAuthorizationContext.capture(registry);
      const deletedId = 'deleted-in-window';
      await registry.createProfile(
        id: deletedId,
        name: 'Delete me',
        role: UserProfileRole.member,
        actingProfileId: actor.profileId,
        actingAuthorizationRevision: actor.authorizationRevision,
        actingSessionEpoch: actor.sessionEpoch,
      );
      final maps = WebDavSyncIdentityMaps(
        circleToLocalProfiles: <String, String>{
          'p-active': activeId,
          'p-deleted': deletedId,
        },
        circleToLocalResources: const <String, String>{},
      );
      final built = await adapter.buildCircleState(
        session,
        WebDavSyncCircleBuildRequest(
          identityMaps: maps,
          deviceId: 'device-local',
          circleId: circleRoot.document.circleId,
          circleKey: circleRoot.key,
          localNowMs: DateTime.now().millisecondsSinceEpoch,
          clockOffsetMs: 0,
          serverNowMs: DateTime.now().millisecondsSinceEpoch,
        ),
      );
      final deleteActor = await ProfileAuthorizationContext.capture(registry);
      await registry.deleteProfileWithDisposition(
        id: deletedId,
        deleteOwnedResources: false,
        detachPublicArtifacts: false,
        actingProfileId: deleteActor.profileId,
        actingAuthorizationRevision: deleteActor.authorizationRevision,
        actingSessionEpoch: deleteActor.sessionEpoch,
      );

      final result = await adapter.applyCircleState(
        session,
        _request(
          root: circleRoot,
          profiles:
              _profiles(<String, WebDavSyncCircleLeaf<WebDavSyncProfileValue>>{
                'p-active': built.profiles.profiles['p-active']!,
                'p-deleted': _profileLeaf('Remote resurrection', 9999999999999),
              }),
          resources: _emptyResources(),
          profileMap: maps.circleToLocalProfiles,
          resourceMap: const <String, String>{},
          registryVersions: built.registryVersions,
        ),
      );

      expect(result, WebDavSyncCircleApplyResult.conflict);
      expect(await registry.getProfile(deletedId), isNull);
      expect(
        tombstones,
        contains(WebDavSyncRegistryRecordId.profile(deletedId)),
      );
    },
  );

  test('captured owner publishes a circle-bound canonical secret', () async {
    final authorization = await ProfileAuthorizationContext.capture(registry);
    final resource =
        await ConnectionResourceService(
          registry: registry,
          cipher: cipher,
        ).create(
          context: authorization,
          type: ConnectionResourceType.realDebrid,
          label: 'Owned RD',
          publicConfig: const <String, Object?>{},
          secretConfig: const <String, Object?>{'apiKey': 'owner-secret'},
        );
    final maps = WebDavSyncIdentityMaps(
      circleToLocalProfiles: <String, String>{'p-active': activeId},
      circleToLocalResources: <String, String>{'r-owned': resource.id},
    );

    final built = await adapter.buildCircleState(
      session,
      WebDavSyncCircleBuildRequest(
        identityMaps: maps,
        deviceId: 'device-owner',
        circleId: circleRoot.document.circleId,
        circleKey: circleRoot.key,
        localNowMs: 1000,
        clockOffsetMs: 0,
        serverNowMs: 1000,
      ),
    );

    final leaf = built.resources.resources['r-owned']!.secretConfig!;
    expect(leaf.stamp.originDeviceId, 'device-owner');
    expect(leaf.value!.ownerCircleProfileId, 'p-active');
    final opened = await WebDavSyncCodec().openDocument(
      key: circleRoot.key,
      encoded: base64Decode(leaf.value!.envelope),
      circleId: circleRoot.document.circleId,
      deviceId: leaf.stamp.originDeviceId,
      logicalName: 'resource-secret/r-owned',
      schemaVersion: 1,
      maxBytes: WebDavSyncLimits.maxGraphDocumentBytes,
      runInBackground: true,
    );
    expect(opened, const <String, Object?>{'apiKey': 'owner-secret'});
  });

  test(
    'metadata-only resource becomes usable when owner secret arrives',
    () async {
      const profileMap = <String, String>{'p-active': 'local-active-admin'};
      const resourceMap = <String, String>{'r-shared': 'local-resource'};
      final metadataOnly = _request(
        root: circleRoot,
        profiles: _profiles(
          <String, WebDavSyncCircleLeaf<WebDavSyncProfileValue>>{
            'p-active': _profileLeaf('Local Admin', 20),
          },
        ),
        resources: _resources(
          metadata: _metadataLeaf(owner: 'p-active', time: 21),
          grants:
              <String, Map<String, WebDavSyncCircleLeaf<WebDavSyncGrantValue>>>{
                'p-active':
                    <String, WebDavSyncCircleLeaf<WebDavSyncGrantValue>>{
                      'r-shared': WebDavSyncCircleLeaf<WebDavSyncGrantValue>(
                        stamp: _stamp(22),
                        value: WebDavSyncGrantValue(
                          permissions: _allPermissions(),
                        ),
                      ),
                    },
              },
        ),
        profileMap: profileMap,
        resourceMap: resourceMap,
      );
      await adapter.applyCircleState(session, metadataOnly);
      expect(
        (await registry.getResource('local-resource'))?.secretPending,
        isTrue,
      );

      final secret = <String, Object?>{'apiKey': 'circle-secret'};
      final codec = WebDavSyncCodec();
      final envelope = await codec.sealDocument(
        key: metadataOnly.circleKey,
        circleId: metadataOnly.circleId,
        deviceId: 'device-owner',
        logicalName: 'resource-secret/r-shared',
        schemaVersion: 1,
        payload: secret,
        maxBytes: WebDavSyncLimits.maxGraphDocumentBytes,
        runInBackground: true,
      );
      final withSecret = _request(
        root: circleRoot,
        profiles: metadataOnly.profiles,
        resources: _resources(
          metadata: _metadataLeaf(owner: 'p-active', time: 21),
          secret: WebDavSyncCircleLeaf<WebDavSyncResourceSecretConfig>(
            stamp: _stamp(23, origin: 'device-owner'),
            value: WebDavSyncResourceSecretConfig(
              semanticDigest: semanticDigestOf(secret),
              type: ConnectionResourceType.realDebrid,
              ownerCircleProfileId: 'p-active',
              publicSchemaVersion: 1,
              payloadVersion: ConnectionResourceService.secretPayloadVersion,
              envelope: base64Encode(envelope),
            ),
          ),
          grants: metadataOnly.resources.grants,
        ),
        profileMap: profileMap,
        resourceMap: resourceMap,
      );
      await adapter.applyCircleState(session, withSecret);

      expect(
        (await registry.getResource('local-resource'))?.secretPending,
        isFalse,
      );
      final authorization = await ProfileAuthorizationContext.capture(registry);
      expect(
        await ConnectionResourceService(
          registry: registry,
          cipher: cipher,
        ).revealOwnedSecretForProfileBackup(
          context: authorization,
          resourceId: 'local-resource',
        ),
        secret,
      );

      final revision = (await registry.getResource(
        'local-resource',
      ))!.authorizationRevision;
      await adapter.applyCircleState(
        session,
        withSecret,
        replayingPending: true,
      );
      expect(
        (await registry.getResource('local-resource'))!.authorizationRevision,
        revision,
        reason: 'replaying an already committed target must be idempotent',
      );

      final secretDeleted = _request(
        root: circleRoot,
        profiles: withSecret.profiles,
        resources: _resources(
          metadata: _metadataLeaf(owner: 'p-active', time: 21),
          secret: WebDavSyncCircleLeaf<WebDavSyncResourceSecretConfig>(
            stamp: _stamp(24, origin: 'device-owner'),
            value: null,
          ),
          grants: withSecret.resources.grants,
        ),
        profileMap: profileMap,
        resourceMap: resourceMap,
      );
      await adapter.applyCircleState(session, secretDeleted);
      expect(
        (await registry.getResource('local-resource'))?.secretPending,
        isTrue,
      );
      expect(await registry.getSealedResourceSecret('local-resource'), isNull);
    },
  );

  test(
    'ownership transfer and decrypt failure ignore stale secret leaves',
    () async {
      final diagnostics = <String>[];
      adapter = ProfileWebDavSyncLocalAdapter(
        registry,
        diagnostic: diagnostics.add,
      );
      session = await adapter.beginCycle();
      final actor = await ProfileAuthorizationContext.capture(registry);
      final nextOwner = await registry.createProfile(
        id: 'next-owner',
        name: 'Next Owner',
        role: UserProfileRole.member,
        actingProfileId: actor.profileId,
        actingAuthorizationRevision: actor.authorizationRevision,
        actingSessionEpoch: actor.sessionEpoch,
      );
      final service = ConnectionResourceService(
        registry: registry,
        cipher: cipher,
      );
      final resource = await service.create(
        context: await ProfileAuthorizationContext.capture(registry),
        type: ConnectionResourceType.realDebrid,
        label: 'Transferred RD',
        publicConfig: const <String, Object?>{},
        secretConfig: const <String, Object?>{'apiKey': 'only-valid-secret'},
      );
      final maps = WebDavSyncIdentityMaps(
        circleToLocalProfiles: <String, String>{
          'p-active': activeId,
          'p-next': nextOwner.id,
        },
        circleToLocalResources: <String, String>{'r-shared': resource.id},
      );
      final beforeTransfer = await adapter.buildCircleState(
        session,
        WebDavSyncCircleBuildRequest(
          identityMaps: maps,
          deviceId: 'device-active-owner',
          circleId: circleRoot.document.circleId,
          circleKey: circleRoot.key,
          localNowMs: 1000,
          clockOffsetMs: 0,
          serverNowMs: 1000,
        ),
      );
      await service.transferOwnership(
        actor: await ProfileAuthorizationContext.capture(registry),
        resourceId: resource.id,
        newOwnerProfileId: nextOwner.id,
      );
      final expected = await registry.getSealedResourceSecret(resource.id);
      final underOldActiveOwner = await adapter.buildCircleState(
        session,
        WebDavSyncCircleBuildRequest(
          identityMaps: maps,
          deviceId: 'device-active-owner',
          circleId: circleRoot.document.circleId,
          circleKey: circleRoot.key,
          localNowMs: 1100,
          clockOffsetMs: 0,
          serverNowMs: 1100,
          previousProfiles: beforeTransfer.profiles,
          previousResources: beforeTransfer.resources,
        ),
      );
      final transferredEntry =
          underOldActiveOwner.resources.resources['r-shared']!;
      expect(transferredEntry.metadata.value!.ownerCircleProfileId, 'p-next');
      expect(
        transferredEntry.secretConfig!.value!.ownerCircleProfileId,
        'p-active',
      );

      await adapter.applyCircleState(
        session,
        WebDavSyncCircleApplyRequest(
          identityMaps: maps,
          circleId: circleRoot.document.circleId,
          circleKey: circleRoot.key,
          profiles: underOldActiveOwner.profiles,
          resources: underOldActiveOwner.resources,
        ),
      );
      expect(
        (await registry.getSealedResourceSecret(resource.id))?.envelope,
        expected?.envelope,
      );
      expect(diagnostics, <String>[
        'Ignored an attachment-incompatible synced resource secret',
      ]);

      diagnostics.clear();
      final corrupt = WebDavSyncResourcesDocument(
        resources: <String, WebDavSyncResourceEntry>{
          'r-shared': WebDavSyncResourceEntry(
            metadata: transferredEntry.metadata,
            secretConfig: WebDavSyncCircleLeaf<WebDavSyncResourceSecretConfig>(
              stamp: _stamp(1200, origin: 'device-next-owner'),
              value: WebDavSyncResourceSecretConfig(
                semanticDigest: List<String>.filled(64, '0').join(),
                type: ConnectionResourceType.realDebrid,
                ownerCircleProfileId: 'p-next',
                publicSchemaVersion: 1,
                payloadVersion: ConnectionResourceService.secretPayloadVersion,
                envelope: base64Encode(const <int>[1, 2, 3]),
              ),
            ),
          ),
        },
        grants: underOldActiveOwner.resources.grants,
        settings: underOldActiveOwner.resources.settings,
        bindings: underOldActiveOwner.resources.bindings,
      );
      await adapter.applyCircleState(
        session,
        WebDavSyncCircleApplyRequest(
          identityMaps: maps,
          circleId: circleRoot.document.circleId,
          circleKey: circleRoot.key,
          profiles: underOldActiveOwner.profiles,
          resources: corrupt,
        ),
      );

      expect(
        (await registry.getSealedResourceSecret(resource.id))?.envelope,
        expected?.envelope,
      );
      expect(diagnostics, <String>[
        'Ignored an unreadable synced resource secret',
      ]);
    },
  );

  test('admin safety deferral applies every other profile leaf', () async {
    final actor = await ProfileAuthorizationContext.capture(registry);
    final retainedId = (await registry.createProfile(
      id: 'local-retained-admin',
      name: 'Retained Admin',
      role: UserProfileRole.admin,
      policy: ProfilePolicy.allAllowedFor(UserProfileRole.admin),
      actingProfileId: actor.profileId,
      actingAuthorizationRevision: actor.authorizationRevision,
      actingSessionEpoch: actor.sessionEpoch,
    )).id;
    final request = WebDavSyncCircleApplyRequest(
      identityMaps: WebDavSyncIdentityMaps(
        circleToLocalProfiles: <String, String>{
          'x-admin': activeId,
          'y-admin': retainedId,
        },
        circleToLocalResources: const <String, String>{},
      ),
      circleId: circleRoot.document.circleId,
      circleKey: circleRoot.key,
      profiles: _profiles(<
        String,
        WebDavSyncCircleLeaf<WebDavSyncProfileValue>
      >{
        'x-admin': _profileLeaf('Demoted X', 200, role: UserProfileRole.member),
        'y-admin': _profileLeaf('Demoted Y', 200, role: UserProfileRole.member),
      }),
      resources: const WebDavSyncResourcesDocument(
        resources: <String, WebDavSyncResourceEntry>{},
        grants:
            <String, Map<String, WebDavSyncCircleLeaf<WebDavSyncGrantValue>>>{},
        settings:
            <
              String,
              Map<String, WebDavSyncCircleLeaf<WebDavSyncSettingsValue>>
            >{},
        bindings:
            <
              String,
              Map<String, WebDavSyncCircleLeaf<WebDavSyncBindingValue>>
            >{},
      ),
      deferredAdminCircleProfileId: 'y-admin',
    );

    await adapter.applyCircleState(session, request);

    expect((await registry.getProfile(activeId))?.role, UserProfileRole.member);
    expect(
      (await registry.getProfile(retainedId))?.role,
      UserProfileRole.admin,
    );
  });

  test('metadata apply preserves local-only PIN failure state', () async {
    final actor = await ProfileAuthorizationContext.capture(registry);
    final hash = List<int>.filled(32, 3);
    final salt = List<int>.filled(16, 4);
    const params = '{"algo":"test"}';
    await registry.setPinRecord(
      profileId: activeId,
      hash: hash,
      salt: salt,
      paramsJson: params,
      actingProfileId: actor.profileId,
      actingAuthorizationRevision: actor.authorizationRevision,
      actingSessionEpoch: actor.sessionEpoch,
    );
    final expected = (await registry.getPinRecord(activeId))!;
    await registry.recordPinFailureIfUnchanged(
      profileId: activeId,
      nowMs: 100,
      expected: expected,
    );

    await adapter.applyCircleState(
      session,
      _request(
        root: circleRoot,
        profiles:
            _profiles(<String, WebDavSyncCircleLeaf<WebDavSyncProfileValue>>{
              'p-active': _profileLeaf(
                'Renamed remotely',
                200,
                pin: WebDavSyncProfilePin(
                  hash: base64Encode(hash),
                  salt: base64Encode(salt),
                  paramsJson: params,
                  resetRequired: false,
                ),
              ),
            }),
        resources: const WebDavSyncResourcesDocument(
          resources: <String, WebDavSyncResourceEntry>{},
          grants:
              <
                String,
                Map<String, WebDavSyncCircleLeaf<WebDavSyncGrantValue>>
              >{},
          settings:
              <
                String,
                Map<String, WebDavSyncCircleLeaf<WebDavSyncSettingsValue>>
              >{},
          bindings:
              <
                String,
                Map<String, WebDavSyncCircleLeaf<WebDavSyncBindingValue>>
              >{},
        ),
        profileMap: <String, String>{'p-active': activeId},
        resourceMap: const <String, String>{},
      ),
    );

    expect((await registry.getProfile(activeId))?.name, 'Renamed remotely');
    expect((await registry.getPinRecord(activeId))?.failedAttempts, 1);
  });
}

WebDavSyncCircleApplyRequest _request({
  required OpenedWebDavSyncRoot root,
  required WebDavSyncProfilesDocument profiles,
  required WebDavSyncResourcesDocument resources,
  required Map<String, String> profileMap,
  required Map<String, String> resourceMap,
  WebDavSyncRegistryVersionSnapshot registryVersions =
      const WebDavSyncRegistryVersionSnapshot(),
}) => WebDavSyncCircleApplyRequest(
  identityMaps: WebDavSyncIdentityMaps(
    circleToLocalProfiles: profileMap,
    circleToLocalResources: resourceMap,
  ),
  circleId: root.document.circleId,
  circleKey: root.key,
  profiles: profiles,
  resources: resources,
  registryVersions: registryVersions,
);

WebDavSyncResourcesDocument
_emptyResources() => const WebDavSyncResourcesDocument(
  resources: <String, WebDavSyncResourceEntry>{},
  grants: <String, Map<String, WebDavSyncCircleLeaf<WebDavSyncGrantValue>>>{},
  settings:
      <String, Map<String, WebDavSyncCircleLeaf<WebDavSyncSettingsValue>>>{},
  bindings:
      <String, Map<String, WebDavSyncCircleLeaf<WebDavSyncBindingValue>>>{},
);

WebDavSyncProfilesDocument _profiles(
  Map<String, WebDavSyncCircleLeaf<WebDavSyncProfileValue>> profiles,
) => WebDavSyncProfilesDocument(profiles: profiles);

WebDavSyncCircleLeaf<WebDavSyncProfileValue> _profileLeaf(
  String name,
  int time, {
  WebDavSyncProfilePin pin = const WebDavSyncProfilePin(resetRequired: false),
  UserProfileRole role = UserProfileRole.admin,
}) => WebDavSyncCircleLeaf<WebDavSyncProfileValue>(
  stamp: _stamp(time),
  value: WebDavSyncProfileValue(
    name: name,
    role: role,
    policy: Map<String, Object?>.from(
      jsonDecode(ProfilePolicy.allAllowedFor(role).encode()) as Map,
    ),
    enabled: true,
    lockOnResume: false,
    setupComplete: true,
    lifecycle: UserProfileLifecycle.active,
    pin: pin,
  ),
);

WebDavSyncCircleLeaf<WebDavSyncResourceMetadata> _metadataLeaf({
  required String owner,
  required int time,
}) => WebDavSyncCircleLeaf<WebDavSyncResourceMetadata>(
  stamp: _stamp(time),
  value: WebDavSyncResourceMetadata(
    type: ConnectionResourceType.realDebrid,
    label: 'Shared RD',
    ownerCircleProfileId: owner,
    publicConfig: const <String, Object?>{'schemaVersion': 1},
    publicSchemaVersion: 1,
    enabled: true,
  ),
);

WebDavSyncResourcesDocument _resources({
  required WebDavSyncCircleLeaf<WebDavSyncResourceMetadata> metadata,
  WebDavSyncCircleLeaf<WebDavSyncResourceSecretConfig>? secret,
  required Map<String, Map<String, WebDavSyncCircleLeaf<WebDavSyncGrantValue>>>
  grants,
}) => WebDavSyncResourcesDocument(
  resources: <String, WebDavSyncResourceEntry>{
    'r-shared': WebDavSyncResourceEntry(
      metadata: metadata,
      secretConfig: secret,
    ),
  },
  grants: grants,
  settings:
      const <
        String,
        Map<String, WebDavSyncCircleLeaf<WebDavSyncSettingsValue>>
      >{},
  bindings:
      const <
        String,
        Map<String, WebDavSyncCircleLeaf<WebDavSyncBindingValue>>
      >{},
);

WebDavSyncStamp _stamp(int time, {String origin = 'device-peer'}) =>
    WebDavSyncStamp(normalizedTimeMs: time, originDeviceId: origin);

int _allPermissions() => ResourcePermission.values.fold<int>(
  0,
  (mask, permission) => mask | permission.bit,
);
