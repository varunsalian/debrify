import 'dart:async';
import 'dart:io';
import 'package:debrify/services/profiles/profile_preferences.dart';

import 'package:debrify/models/profiles/connection_resource.dart';
import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/models/tracking_source.dart';
import 'package:debrify/services/profiles/connection_resource_service.dart';
import 'package:debrify/services/profiles/device_key_provider.dart';
import 'package:debrify/services/profiles/profile_authorization.dart';
import 'package:debrify/services/profiles/profile_registry.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temporaryDirectory;
  late ProfileRegistry registry;
  late ConnectionResourceService resources;
  late String adminId;
  late String memberId;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'resource-test-',
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
    final cipher = MemoryDeviceSecretCipher(List<int>.generate(32, (i) => i));
    await cipher.initialize();
    resources = ConnectionResourceService(registry: registry, cipher: cipher);
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeCommitted(
      ProfileScope(profileId: adminId, dataGeneration: 1, sessionEpoch: 1),
    );
  });

  Future<void> activate(String profileId, int sessionEpoch) async {
    await registry.setActiveProfile(profileId);
    ProfileRuntime.publish(
      ProfileScope(
        profileId: profileId,
        dataGeneration: 1,
        sessionEpoch: sessionEpoch,
      ),
    );
  }

  tearDown(() async {
    ProfileRuntime.debugReset();
    await registry.close();
    await temporaryDirectory.delete(recursive: true);
  });

  test(
    'identical credential saves preserve revisions and do not notify sync',
    () async {
      final resource = await resources.create(
        context: await ProfileAuthorizationContext.capture(registry),
        type: ConnectionResourceType.realDebrid,
        label: 'RD',
        publicConfig: const {},
        secretConfig: const {
          'apiKey': 'original',
          'nested': {
            'a': 1,
            'b': ['x'],
          },
        },
      );
      final before = (await registry.getResource(resource.id))!;
      final intents = <String>[];
      ProfilePreferences.webDavSyncLocalChangeSink = (_, key) =>
          intents.add(key);
      try {
        await resources.updateSecret(
          context: await ProfileAuthorizationContext.capture(registry),
          resourceId: resource.id,
          secretConfig: const {
            'nested': {
              'b': ['x'],
              'a': 1,
            },
            'apiKey': 'original',
          },
        );
        expect(
          (await registry.getResource(resource.id))!.authorizationRevision,
          before.authorizationRevision,
        );
        expect(intents, isEmpty);
        await resources.updateSecret(
          context: await ProfileAuthorizationContext.capture(registry),
          resourceId: resource.id,
          secretConfig: const {'apiKey': 'changed'},
        );
        expect(
          (await registry.getResource(resource.id))!.authorizationRevision,
          greaterThan(before.authorizationRevision),
        );
        expect(intents, [ProfilePreferences.webDavSyncRegistryLogicalKey]);
        expect(
          await resources.revealSecret(
            context: await ProfileAuthorizationContext.capture(registry),
            resourceId: resource.id,
          ),
          {'apiKey': 'changed'},
        );
      } finally {
        ProfilePreferences.webDavSyncLocalChangeSink = null;
      }
    },
  );

  test(
    'identical save still rejects a profile switch during comparison',
    () async {
      final resource = await resources.create(
        context: await ProfileAuthorizationContext.capture(registry),
        type: ConnectionResourceType.realDebrid,
        label: 'RD',
        publicConfig: const {},
        secretConfig: const {'apiKey': 'same'},
      );
      final cipher = _BlockingDeviceSecretCipher(
        MemoryDeviceSecretCipher(List<int>.generate(32, (i) => i)),
        blockOpen: true,
      );
      await cipher.initialize();
      final delayed = ConnectionResourceService(
        registry: registry,
        cipher: cipher,
      );
      final write = delayed.updateSecret(
        context: await ProfileAuthorizationContext.capture(registry),
        resourceId: resource.id,
        secretConfig: const {'apiKey': 'same'},
      );
      await cipher.operationStarted.future;
      await activate(memberId, 2);
      cipher.release();
      await expectLater(write, throwsA(isA<ResourceAuthorizationException>()));
    },
  );

  test(
    'credential replacement can repair an unreadable prior envelope',
    () async {
      final resource = await resources.create(
        context: await ProfileAuthorizationContext.capture(registry),
        type: ConnectionResourceType.realDebrid,
        label: 'RD',
        publicConfig: const {},
        secretConfig: const {'apiKey': 'old'},
      );
      final cipher = _BlockingDeviceSecretCipher(
        MemoryDeviceSecretCipher(List<int>.generate(32, (i) => i)),
        failOpen: true,
      );
      await cipher.initialize();
      await ConnectionResourceService(
        registry: registry,
        cipher: cipher,
      ).updateSecret(
        context: await ProfileAuthorizationContext.capture(registry),
        resourceId: resource.id,
        secretConfig: const {'apiKey': 'replacement'},
      );
      expect(
        await resources.revealSecret(
          context: await ProfileAuthorizationContext.capture(registry),
          resourceId: resource.id,
        ),
        {'apiKey': 'replacement'},
      );
    },
  );

  test('seals secrets and requires explicit grant and binding', () async {
    final owner = await ProfileAuthorizationContext.capture(registry);
    final resource = await resources.create(
      context: owner,
      type: ConnectionResourceType.realDebrid,
      label: 'Main RD',
      publicConfig: const <String, dynamic>{'region': 'auto'},
      secretConfig: const <String, dynamic>{'apiKey': 'super-secret'},
    );
    final sharingAdmin = await ProfileAuthorizationContext.capture(registry);
    await resources.grant(
      actor: sharingAdmin,
      targetProfileId: memberId,
      resourceId: resource.id,
      permissions: const <ResourcePermission>{ResourcePermission.use},
    );
    await activate(memberId, 2);
    final member = await ProfileAuthorizationContext.capture(registry);
    await resources.bind(
      context: member,
      slot: 'cloud.primary',
      resourceId: resource.id,
      acceptedTypes: const <ConnectionResourceType>{
        ConnectionResourceType.realDebrid,
      },
      feature: ProfileFeature.cloud,
    );

    expect(
      (await resources.resolveBinding(
        context: member,
        slot: 'cloud.primary',
        permission: ResourcePermission.use,
        acceptedTypes: const <ConnectionResourceType>{
          ConnectionResourceType.realDebrid,
        },
        feature: ProfileFeature.cloud,
      )).id,
      resource.id,
    );
    expect(
      () => resources.revealSecret(context: member, resourceId: resource.id),
      throwsA(isA<ResourceAuthorizationException>()),
    );
    await activate(adminId, 3);
    final revealingAdmin = await ProfileAuthorizationContext.capture(registry);
    expect(
      await resources.revealSecret(
        context: revealingAdmin,
        resourceId: resource.id,
      ),
      <String, dynamic>{'apiKey': 'super-secret'},
    );
  });

  test('sharing a scalar credential also binds it for the target', () async {
    final resource = await resources.create(
      context: await ProfileAuthorizationContext.capture(registry),
      type: ConnectionResourceType.allDebrid,
      label: 'Family AllDebrid',
      publicConfig: const <String, dynamic>{},
      secretConfig: const <String, dynamic>{'apiKey': 'ad-secret'},
    );

    await resources.grant(
      actor: await ProfileAuthorizationContext.capture(registry),
      targetProfileId: memberId,
      resourceId: resource.id,
      permissions: const <ResourcePermission>{ResourcePermission.use},
    );

    expect(
      await registry.getBoundResourceId(memberId, 'provider.allDebrid'),
      resource.id,
    );
    await activate(memberId, 2);
    final member = await ProfileAuthorizationContext.capture(registry);
    expect(
      (await resources.resolveBinding(
        context: member,
        slot: 'provider.allDebrid',
        permission: ResourcePermission.use,
        acceptedTypes: const <ConnectionResourceType>{
          ConnectionResourceType.allDebrid,
        },
        feature: ProfileFeature.cloud,
      )).id,
      resource.id,
    );
  });

  test('new shared tracker bindings enable only the target profile', () async {
    await StorageService.setTrackingScrobbleTargets(<TrackingSource>{
      TrackingSource.local,
    });
    final trackerResources = <ConnectionResourceType, ConnectionResource>{};
    for (final type in const <ConnectionResourceType>[
      ConnectionResourceType.trakt,
      ConnectionResourceType.simkl,
      ConnectionResourceType.mdblist,
    ]) {
      trackerResources[type] = await resources.create(
        context: await ProfileAuthorizationContext.capture(registry),
        type: type,
        label: 'Shared ${type.name}',
        publicConfig: const <String, dynamic>{},
        secretConfig: <String, dynamic>{'credential': '${type.name}-secret'},
      );
    }

    await activate(memberId, 2);
    await StorageService.setTrackingScrobbleTargets(<TrackingSource>{
      TrackingSource.local,
    });
    await activate(adminId, 3);
    final actor = await ProfileAuthorizationContext.capture(registry);
    for (final resource in trackerResources.values) {
      await resources.grant(
        actor: actor,
        targetProfileId: memberId,
        resourceId: resource.id,
        permissions: const <ResourcePermission>{ResourcePermission.use},
      );
    }

    expect(await StorageService.getTrackingScrobbleTargets(), <TrackingSource>{
      TrackingSource.local,
    });
    await activate(memberId, 4);
    expect(
      await StorageService.getTrackingScrobbleTargets(),
      Set<TrackingSource>.of(TrackingSource.values),
    );
  });

  test(
    'an unchanged grant preserves opt-out but revoke and regrant enables it',
    () async {
      final resource = await resources.create(
        context: await ProfileAuthorizationContext.capture(registry),
        type: ConnectionResourceType.trakt,
        label: 'Shared Trakt',
        publicConfig: const <String, dynamic>{},
        secretConfig: const <String, dynamic>{'accessToken': 'trakt-secret'},
      );
      var actor = await ProfileAuthorizationContext.capture(registry);
      await resources.grant(
        actor: actor,
        targetProfileId: memberId,
        resourceId: resource.id,
        permissions: const <ResourcePermission>{ResourcePermission.use},
      );

      await activate(memberId, 2);
      await StorageService.setTrackingScrobbleTargets(<TrackingSource>{
        TrackingSource.local,
      });
      await activate(adminId, 3);
      actor = await ProfileAuthorizationContext.capture(registry);
      await resources.grant(
        actor: actor,
        targetProfileId: memberId,
        resourceId: resource.id,
        permissions: const <ResourcePermission>{ResourcePermission.use},
      );
      await activate(memberId, 4);
      expect(
        await StorageService.getTrackingScrobbleTargets(),
        <TrackingSource>{TrackingSource.local},
      );

      await activate(adminId, 5);
      actor = await ProfileAuthorizationContext.capture(registry);
      await resources.revokeGrant(
        actor: actor,
        targetProfileId: memberId,
        resourceId: resource.id,
      );
      actor = await ProfileAuthorizationContext.capture(registry);
      await resources.grant(
        actor: actor,
        targetProfileId: memberId,
        resourceId: resource.id,
        permissions: const <ResourcePermission>{ResourcePermission.use},
      );

      await activate(memberId, 6);
      expect(
        await StorageService.getTrackingScrobbleTargets(),
        <TrackingSource>{TrackingSource.local, TrackingSource.trakt},
      );
    },
  );

  test('repairs one unambiguous legacy scalar grant', () async {
    final resource = await resources.create(
      context: await ProfileAuthorizationContext.capture(registry),
      type: ConnectionResourceType.allDebrid,
      label: 'Legacy shared AllDebrid',
      publicConfig: const <String, dynamic>{},
      secretConfig: const <String, dynamic>{'apiKey': 'legacy-ad-secret'},
    );
    await registry.bindResource(
      profileId: adminId,
      slot: 'provider.allDebrid',
      resourceId: resource.id,
    );
    await registry.upsertGrant(
      profileId: memberId,
      resourceId: resource.id,
      permissions: ResourcePermission.use.bit,
      grantedByProfileId: adminId,
      origin: const <String, dynamic>{'origin': 'old-profile-build'},
    );
    expect(
      await registry.getBoundResourceId(memberId, 'provider.allDebrid'),
      isNull,
    );

    expect(await registry.repairUnambiguousSingletonBindings(), 1);
    expect(
      await registry.getBoundResourceId(memberId, 'provider.allDebrid'),
      resource.id,
    );
  });

  test('does not guess between ambiguous legacy scalar grants', () async {
    for (final label in const <String>['First AllDebrid', 'Second AllDebrid']) {
      final resource = await resources.create(
        context: await ProfileAuthorizationContext.capture(registry),
        type: ConnectionResourceType.allDebrid,
        label: label,
        publicConfig: const <String, dynamic>{},
        secretConfig: <String, dynamic>{'apiKey': '$label-secret'},
      );
      await registry.upsertGrant(
        profileId: memberId,
        resourceId: resource.id,
        permissions: ResourcePermission.use.bit,
        grantedByProfileId: adminId,
        origin: const <String, dynamic>{'origin': 'old-profile-build'},
      );
    }

    expect(await registry.repairUnambiguousSingletonBindings(), 0);
    expect(
      await registry.getBoundResourceId(memberId, 'provider.allDebrid'),
      isNull,
    );
  });

  test('rejects secret-like public configuration', () async {
    final owner = await ProfileAuthorizationContext.capture(registry);
    expect(
      () => resources.create(
        context: owner,
        type: ConnectionResourceType.iptvM3u,
        label: 'IPTV',
        publicConfig: const <String, dynamic>{
          'playlistUrl': 'https://example.test/list?token=secret',
        },
        secretConfig: const <String, dynamic>{'url': 'https://example.test'},
      ),
      throwsArgumentError,
    );
  });

  test('revocation is Admin-authorized and removes stale bindings', () async {
    final owner = await ProfileAuthorizationContext.capture(registry);
    final resource = await resources.create(
      context: owner,
      type: ConnectionResourceType.realDebrid,
      label: 'Shared RD',
      publicConfig: const <String, dynamic>{},
      secretConfig: const <String, dynamic>{'apiKey': 'secret'},
    );
    await resources.grant(
      actor: await ProfileAuthorizationContext.capture(registry),
      targetProfileId: memberId,
      resourceId: resource.id,
      permissions: const <ResourcePermission>{ResourcePermission.use},
    );
    await activate(memberId, 2);
    await resources.bind(
      context: await ProfileAuthorizationContext.capture(registry),
      slot: 'cloud.primary',
      resourceId: resource.id,
      acceptedTypes: const <ConnectionResourceType>{
        ConnectionResourceType.realDebrid,
      },
      feature: ProfileFeature.cloud,
    );

    await activate(adminId, 3);
    await resources.revokeGrant(
      actor: await ProfileAuthorizationContext.capture(registry),
      targetProfileId: memberId,
      resourceId: resource.id,
    );

    expect(await registry.getGrant(memberId, resource.id), isNull);
    expect(
      await registry.getBoundResourceId(memberId, 'cloud.primary'),
      isNull,
    );
  });

  test('borrower disconnect removes only its binding and grant', () async {
    final resource = await resources.create(
      context: await ProfileAuthorizationContext.capture(registry),
      type: ConnectionResourceType.realDebrid,
      label: 'Shared RD',
      publicConfig: const <String, dynamic>{},
      secretConfig: const <String, dynamic>{'apiKey': 'owner-secret'},
    );
    await registry.bindResource(
      profileId: adminId,
      slot: 'provider.realDebrid',
      resourceId: resource.id,
    );
    await resources.grant(
      actor: await ProfileAuthorizationContext.capture(registry),
      targetProfileId: memberId,
      resourceId: resource.id,
      permissions: const <ResourcePermission>{ResourcePermission.use},
    );
    await activate(memberId, 2);
    await registry.bindResource(
      profileId: memberId,
      slot: 'provider.realDebrid',
      resourceId: resource.id,
    );

    await resources.disconnectBinding(
      context: await ProfileAuthorizationContext.capture(registry),
      slot: 'provider.realDebrid',
      resourceId: resource.id,
    );

    expect(await registry.getGrant(memberId, resource.id), isNull);
    expect(
      await registry.getBoundResourceId(memberId, 'provider.realDebrid'),
      isNull,
    );
    expect(await registry.getResource(resource.id), isNotNull);
    await activate(adminId, 3);
    expect(
      await resources.revealSecret(
        context: await ProfileAuthorizationContext.capture(registry),
        resourceId: resource.id,
      ),
      <String, dynamic>{'apiKey': 'owner-secret'},
    );
  });

  test('owner disconnect requires shared-impact disposition', () async {
    final resource = await resources.create(
      context: await ProfileAuthorizationContext.capture(registry),
      type: ConnectionResourceType.realDebrid,
      label: 'Shared RD',
      publicConfig: const <String, dynamic>{},
      secretConfig: const <String, dynamic>{'apiKey': 'owner-secret'},
    );
    await registry.bindResource(
      profileId: adminId,
      slot: 'provider.realDebrid',
      resourceId: resource.id,
    );
    await resources.grant(
      actor: await ProfileAuthorizationContext.capture(registry),
      targetProfileId: memberId,
      resourceId: resource.id,
      permissions: const <ResourcePermission>{ResourcePermission.use},
    );

    expect(
      () async => resources.disconnectBinding(
        context: await ProfileAuthorizationContext.capture(registry),
        slot: 'provider.realDebrid',
        resourceId: resource.id,
      ),
      throwsA(isA<ResourceImpactRequiredException>()),
    );
    expect(await registry.getResource(resource.id), isNotNull);
    expect(await registry.getGrant(memberId, resource.id), isNotNull);

    await resources.deleteOwnedResourceForAll(
      context: await ProfileAuthorizationContext.capture(registry),
      resourceId: resource.id,
    );
    expect(await registry.getResource(resource.id), isNull);
    expect(await registry.getGrant(memberId, resource.id), isNull);
    expect(
      await registry.getBoundResourceId(adminId, 'provider.realDebrid'),
      isNull,
    );
  });

  test(
    'Admin transfer re-seals owner-bound secret and preserves grants',
    () async {
      final resource = await resources.create(
        context: await ProfileAuthorizationContext.capture(registry),
        type: ConnectionResourceType.trakt,
        label: 'Family Trakt',
        publicConfig: const <String, dynamic>{},
        secretConfig: const <String, dynamic>{'accessToken': 'tracker-secret'},
      );

      await resources.transferOwnership(
        actor: await ProfileAuthorizationContext.capture(registry),
        resourceId: resource.id,
        newOwnerProfileId: memberId,
      );

      expect(
        (await registry.getResource(resource.id))!.ownerProfileId,
        memberId,
      );
      await activate(memberId, 2);
      expect(
        await resources.revealSecret(
          context: await ProfileAuthorizationContext.capture(registry),
          resourceId: resource.id,
        ),
        <String, dynamic>{'accessToken': 'tracker-secret'},
      );
      expect(
        (await registry.getGrant(
          memberId,
          resource.id,
        ))!.allows(ResourcePermission.manage),
        isTrue,
      );
    },
  );

  test(
    'target role revision is rechecked inside a sharing transaction',
    () async {
      final resource = await resources.create(
        context: await ProfileAuthorizationContext.capture(registry),
        type: ConnectionResourceType.realDebrid,
        label: 'Shared RD',
        publicConfig: const <String, dynamic>{},
        secretConfig: const <String, dynamic>{'apiKey': 'secret'},
      );
      final targetBefore = (await registry.getProfile(memberId))!;
      final actor = await ProfileAuthorizationContext.capture(registry);
      await registry.updateProfile(
        id: memberId,
        role: UserProfileRole.child,
        actingProfileId: actor.profileId,
        actingAuthorizationRevision: actor.authorizationRevision,
        actingSessionEpoch: actor.sessionEpoch,
      );

      await expectLater(
        registry.upsertGrant(
          profileId: memberId,
          resourceId: resource.id,
          permissions:
              ResourcePermission.use.bit | ResourcePermission.writeRemote.bit,
          grantedByProfileId: adminId,
          origin: const <String, dynamic>{'origin': 'test-race'},
          actingProfileId: adminId,
          actingAuthorizationRevision: (await registry.getProfile(
            adminId,
          ))!.authorizationRevision,
          expectedResourceAuthorizationRevision: resource.authorizationRevision,
          expectedTargetAuthorizationRevision:
              targetBefore.authorizationRevision,
        ),
        throwsStateError,
      );
      // Default-on sharing seeds use|download at resource creation, so a
      // grant exists here by design — the FAILED race transaction must not
      // have strengthened it.
      final afterRace = await registry.getGrant(memberId, resource.id);
      expect(afterRace, isNotNull);
      expect(afterRace!.allows(ResourcePermission.writeRemote), isFalse);

      await registry.upsertGrant(
        profileId: memberId,
        resourceId: resource.id,
        permissions:
            ResourcePermission.use.bit | ResourcePermission.download.bit,
        grantedByProfileId: adminId,
        origin: const <String, dynamic>{'origin': 'internal-restore'},
      );
      expect(
        (await registry.getGrant(
          memberId,
          resource.id,
        ))!.allows(ResourcePermission.download),
        isTrue,
      );
    },
  );

  test('authenticated encryption rejects changed associated data', () async {
    final cipher = MemoryDeviceSecretCipher(List<int>.filled(32, 7));
    final envelope = await cipher.seal(
      <int>[1, 2, 3],
      associatedData: <int>[4],
    );

    expect(
      () => cipher.open(envelope, associatedData: <int>[5]),
      throwsA(anything),
    );
  });

  test(
    'profile switch revokes plaintext while decryption is in flight',
    () async {
      final resource = await resources.create(
        context: await ProfileAuthorizationContext.capture(registry),
        type: ConnectionResourceType.realDebrid,
        label: 'Delayed RD',
        publicConfig: const <String, dynamic>{},
        secretConfig: const <String, dynamic>{'apiKey': 'never-leak'},
      );
      final blockingCipher = _BlockingDeviceSecretCipher(
        MemoryDeviceSecretCipher(List<int>.generate(32, (i) => i)),
        blockOpen: true,
      );
      await blockingCipher.initialize();
      final delayed = ConnectionResourceService(
        registry: registry,
        cipher: blockingCipher,
      );

      final read = delayed.resolveSecretForUse(
        context: await ProfileAuthorizationContext.capture(registry),
        resourceId: resource.id,
        feature: ProfileFeature.cloud,
      );
      await blockingCipher.operationStarted.future;
      await activate(memberId, 2);
      blockingCipher.release();

      await expectLater(read, throwsA(isA<ResourceAuthorizationException>()));
    },
  );

  test('profile switch aborts a secret rotation after sealing', () async {
    final resource = await resources.create(
      context: await ProfileAuthorizationContext.capture(registry),
      type: ConnectionResourceType.realDebrid,
      label: 'Delayed RD',
      publicConfig: const <String, dynamic>{},
      secretConfig: const <String, dynamic>{'apiKey': 'original'},
    );
    final blockingCipher = _BlockingDeviceSecretCipher(
      MemoryDeviceSecretCipher(List<int>.generate(32, (i) => i)),
      blockSeal: true,
    );
    await blockingCipher.initialize();
    final delayed = ConnectionResourceService(
      registry: registry,
      cipher: blockingCipher,
    );

    final write = delayed.updateSecret(
      context: await ProfileAuthorizationContext.capture(registry),
      resourceId: resource.id,
      secretConfig: const <String, dynamic>{'apiKey': 'must-not-commit'},
    );
    await blockingCipher.operationStarted.future;
    await activate(memberId, 2);
    blockingCipher.release();

    await expectLater(write, throwsA(isA<ResourceAuthorizationException>()));
    await activate(adminId, 3);
    expect(
      await resources.revealSecret(
        context: await ProfileAuthorizationContext.capture(registry),
        resourceId: resource.id,
      ),
      const <String, dynamic>{'apiKey': 'original'},
    );
  });
}

class _BlockingDeviceSecretCipher implements DeviceSecretCipher {
  final DeviceSecretCipher delegate;
  final bool blockOpen;
  final bool blockSeal;
  final bool failOpen;
  final Completer<void> operationStarted = Completer<void>();
  final Completer<void> _release = Completer<void>();

  _BlockingDeviceSecretCipher(
    this.delegate, {
    this.blockOpen = false,
    this.blockSeal = false,
    this.failOpen = false,
  });

  @override
  Future<void> initialize() => delegate.initialize();

  @override
  Future<List<int>> open(
    String envelope, {
    required List<int> associatedData,
  }) async {
    if (failOpen) throw const FormatException('Unreadable prior envelope');
    if (blockOpen) await _block();
    return delegate.open(envelope, associatedData: associatedData);
  }

  @override
  Future<String> seal(
    List<int> plaintext, {
    required List<int> associatedData,
  }) async {
    if (blockSeal) await _block();
    return delegate.seal(plaintext, associatedData: associatedData);
  }

  Future<void> _block() async {
    if (!operationStarted.isCompleted) operationStarted.complete();
    await _release.future;
  }

  void release() {
    if (!_release.isCompleted) _release.complete();
  }
}
