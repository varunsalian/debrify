import 'package:debrify/services/profiles/profile_preferences.dart';
import 'dart:convert';
import 'dart:io';

import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/models/profiles/user_profile.dart';
import 'package:debrify/services/profiles/profile_authorization.dart';
import 'package:debrify/services/profiles/profile_lock_controller.dart';
import 'package:debrify/services/profiles/profile_registry.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory temporaryDirectory;
  late ProfileRegistry registry;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'profiles-test-',
    );
    registry = await ProfileRegistry.open(
      path: p.join(temporaryDirectory.path, 'profiles.db'),
    );
  });

  tearDown(() async {
    ProfileLockController.instance.dispose();
    ProfileRuntime.debugReset();
    await registry.close();
    await temporaryDirectory.delete(recursive: true);
  });

  for (final selfService in [false, true]) {
    test(
      'photo-only identity changes do not request publication ($selfService)',
      () async {
        final profile = await registry.createProfile(
          name: 'Admin',
          role: UserProfileRole.admin,
        );
        await registry.commitBootstrap(
          activeProfileId: profile.id,
          migratedLegacyInstall: false,
        );
        ProfileRuntime.initializeCommitted(
          ProfileScope(
            profileId: profile.id,
            dataGeneration: 1,
            sessionEpoch: 1,
          ),
        );
        final keys = <String>[];
        ProfilePreferences.webDavSyncLocalChangeSink = (_, key) =>
            keys.add(key);
        Future<void> save(String name, String avatar) async {
          final current = (await registry.getProfile(profile.id))!;
          if (selfService) {
            await registry.updateActiveProfileIdentity(
              profileId: profile.id,
              name: name,
              avatarKey: avatar,
              actingAuthorizationRevision: current.authorizationRevision,
              actingSessionEpoch: 1,
            );
          } else {
            await registry.updateProfile(
              id: profile.id,
              name: name,
              avatarKey: avatar,
              actingProfileId: profile.id,
              actingAuthorizationRevision: current.authorizationRevision,
              actingSessionEpoch: 1,
            );
          }
        }

        try {
          await save('Admin', 'file:avatars/a1b2.gif#4A90D9');
          expect(
            (await registry.getProfile(profile.id))!.avatarKey,
            'file:avatars/a1b2.gif#4A90D9',
          );
          expect(keys, isEmpty);
          await save('Renamed', 'file:avatars/other.webp');
          expect(keys, [ProfilePreferences.webDavSyncRegistryLogicalKey]);
          keys.clear();
          await save('Renamed', 'art:aurora');
          expect(keys, [ProfilePreferences.webDavSyncRegistryLogicalKey]);
          keys.clear();
          await save('Renamed', 'art:aurora');
          expect(keys, isEmpty);
        } finally {
          ProfilePreferences.webDavSyncLocalChangeSink = null;
        }
      },
    );
  }

  test('stale Admin cannot commit after switching away and back', () async {
    final first = await registry.createProfile(
      name: 'First Admin',
      role: UserProfileRole.admin,
    );
    final second = await registry.createProfile(
      name: 'Second Admin',
      role: UserProfileRole.admin,
    );
    final member = await registry.createProfile(
      name: 'Member',
      role: UserProfileRole.member,
    );
    await registry.commitBootstrap(
      activeProfileId: first.id,
      migratedLegacyInstall: false,
    );
    ProfileRuntime.initializeCommitted(
      ProfileScope(profileId: first.id, dataGeneration: 1, sessionEpoch: 1),
    );
    final stale = await ProfileAuthorizationContext.capture(registry);

    await registry.setActiveProfile(second.id);
    ProfileRuntime.publish(
      ProfileScope(profileId: second.id, dataGeneration: 1, sessionEpoch: 2),
    );
    await registry.setActiveProfile(first.id);
    ProfileRuntime.publish(
      ProfileScope(profileId: first.id, dataGeneration: 1, sessionEpoch: 3),
    );

    await expectLater(
      registry.updateProfile(
        id: member.id,
        name: 'Leaked mutation',
        actingProfileId: stale.profileId,
        actingAuthorizationRevision: stale.authorizationRevision,
        actingSessionEpoch: stale.sessionEpoch,
      ),
      throwsStateError,
    );
    expect((await registry.getProfile(member.id))?.name, 'Member');
  });

  test(
    'creates profiles, generation, and authoritative active state',
    () async {
      final admin = await registry.createProfile(
        name: 'Admin',
        role: UserProfileRole.admin,
        setupComplete: true,
      );
      await registry.commitBootstrap(
        activeProfileId: admin.id,
        migratedLegacyInstall: true,
      );

      expect((await registry.activeProfile())?.id, admin.id);
      expect(await registry.isMigrationCommitted(), isTrue);
      expect(admin.visibleDataGeneration, 1);
    },
  );

  test('rejects blank names and deletion of final enabled Admin', () async {
    expect(
      () => registry.createProfile(name: '   ', role: UserProfileRole.member),
      throwsArgumentError,
    );
    final admin = await registry.createProfile(
      name: 'Admin',
      role: UserProfileRole.admin,
    );
    final member = await registry.createProfile(
      name: 'Member',
      role: UserProfileRole.member,
    );
    await registry.commitBootstrap(
      activeProfileId: admin.id,
      migratedLegacyInstall: false,
    );
    await registry.setActiveProfile(member.id);

    expect(() => registry.deleteProfile(admin.id), throwsStateError);
  });

  test('cannot delete active profile', () async {
    final admin = await registry.createProfile(
      name: 'Admin',
      role: UserProfileRole.admin,
    );
    await registry.commitBootstrap(
      activeProfileId: admin.id,
      migratedLegacyInstall: false,
    );

    expect(() => registry.deleteProfile(admin.id), throwsStateError);
  });

  test('committed profile mutations require a live Admin capability', () async {
    final admin = await registry.createProfile(
      name: 'Admin',
      role: UserProfileRole.admin,
    );
    final member = await registry.createProfile(
      name: 'Member',
      role: UserProfileRole.member,
    );
    await registry.commitBootstrap(
      activeProfileId: admin.id,
      migratedLegacyInstall: false,
    );
    ProfileRuntime.initializeCommitted(
      ProfileScope(profileId: admin.id, dataGeneration: 1, sessionEpoch: 1),
    );

    await expectLater(
      registry.createProfile(
        name: 'Unauthorized',
        role: UserProfileRole.member,
      ),
      throwsStateError,
    );
    await expectLater(
      registry.updateProfile(id: member.id, name: 'Unauthorized'),
      throwsStateError,
    );
    await expectLater(registry.deleteProfile(member.id), throwsStateError);
    expect((await registry.getProfile(member.id))?.name, 'Member');
  });

  test('locking revokes an already captured Admin capability', () async {
    final admin = await registry.createProfile(
      name: 'Admin',
      role: UserProfileRole.admin,
    );
    final member = await registry.createProfile(
      name: 'Member',
      role: UserProfileRole.member,
    );
    await registry.commitBootstrap(
      activeProfileId: admin.id,
      migratedLegacyInstall: false,
    );
    ProfileRuntime.initializeCommitted(
      ProfileScope(profileId: admin.id, dataGeneration: 1, sessionEpoch: 1),
    );
    ProfileLockController.instance.activate(admin, unlocked: true);
    final actor = await ProfileAuthorizationContext.capture(registry);
    ProfileLockController.instance.lock();

    await expectLater(
      registry.updateProfile(
        id: member.id,
        name: 'Unauthorized',
        actingProfileId: actor.profileId,
        actingAuthorizationRevision: actor.authorizationRevision,
        actingSessionEpoch: actor.sessionEpoch,
      ),
      throwsStateError,
    );
    expect((await registry.getProfile(member.id))?.name, 'Member');
  });

  test('cannot demote or remove manageProfiles from the final Admin', () async {
    final admin = await registry.createProfile(
      name: 'Admin',
      role: UserProfileRole.admin,
    );

    expect(
      () => registry.updateProfile(id: admin.id, role: UserProfileRole.member),
      throwsStateError,
    );
    expect(
      () => registry.updateProfile(
        id: admin.id,
        policy: ProfilePolicy(
          enabled: ProfileFeature.values
              .where((feature) => feature != ProfileFeature.manageProfiles)
              .toSet(),
        ),
      ),
      throwsStateError,
    );
  });

  test('artifact discovery never steals another profile ownership', () async {
    final first = await registry.createProfile(
      name: 'First',
      role: UserProfileRole.admin,
    );
    final second = await registry.createProfile(
      name: 'Second',
      role: UserProfileRole.admin,
    );
    const ownedPath = 'content://recordings/owned';
    const orphanPath = 'content://recordings/orphan';

    await registry.upsertOwnedArtifact(
      kind: 'recording',
      ownerProfileId: first.id,
      canonicalPath: ownedPath,
    );
    await registry.recordUnassignedArtifact(
      kind: 'recording',
      canonicalPath: ownedPath,
    );
    await expectLater(
      registry.upsertOwnedArtifact(
        kind: 'recording',
        ownerProfileId: second.id,
        canonicalPath: ownedPath,
      ),
      throwsStateError,
    );
    await registry.recordUnassignedArtifact(
      kind: 'recording',
      canonicalPath: orphanPath,
      sizeBytes: 42,
    );

    expect(
      (await registry.listOwnedArtifacts(first.id)).single['canonical_path'],
      ownedPath,
    );
    expect(await registry.listOwnedArtifacts(second.id), isEmpty);
    final unassigned = await registry.listUnassignedArtifacts();
    expect(unassigned, hasLength(1));
    expect(unassigned.single['canonical_path'], orphanPath);
    expect(unassigned.single['owner_profile_id'], isNull);

    await registry.removeArtifactRecord(
      kind: 'recording',
      canonicalPath: orphanPath,
    );
    expect(await registry.listUnassignedArtifacts(), isEmpty);
  });

  test('diagnostics expose counts without profile identity', () async {
    final admin = await registry.createProfile(
      name: 'Private household name',
      role: UserProfileRole.admin,
    );
    await registry.createProfile(
      name: 'Private child name',
      role: UserProfileRole.child,
      disabled: true,
    );
    await registry.commitBootstrap(
      activeProfileId: admin.id,
      migratedLegacyInstall: false,
    );

    final diagnostics = await registry.privacySafeDiagnostics();
    final encoded = jsonEncode(diagnostics);
    expect((diagnostics['profiles'] as Map)['total'], 2);
    expect(encoded, isNot(contains(admin.id)));
    expect(encoded, isNot(contains('Private household name')));
    expect(encoded, isNot(contains('Private child name')));
  });

  test(
    'graph restore journal retains cleanup authority after staging row loss',
    () async {
      final admin = await registry.createProfile(
        name: 'Admin',
        role: UserProfileRole.admin,
      );
      await registry.commitBootstrap(
        activeProfileId: admin.id,
        migratedLegacyInstall: false,
      );
      ProfileRuntime.initializeCommitted(
        ProfileScope(profileId: admin.id, dataGeneration: 1, sessionEpoch: 1),
      );
      final actor = await ProfileAuthorizationContext.capture(registry);
      const stagedId = 'profile-interrupted-restore';
      await registry.beginProfileGraphRestore(
        operationId: 'restore-interrupted',
        stagedProfileIds: const <String>[stagedId],
      );
      await registry.createProfile(
        id: stagedId,
        name: 'Imported',
        role: UserProfileRole.member,
        lifecycle: UserProfileLifecycle.staging,
        actingProfileId: actor.profileId,
        actingAuthorizationRevision: actor.authorizationRevision,
        actingSessionEpoch: actor.sessionEpoch,
      );

      // Recreate the old crash boundary: registry cleanup completed while
      // generation-1 preferences/files were still present.
      await registry.deleteProfile(stagedId);

      final recoveries = await registry.recoverInterruptedRestores();
      expect(recoveries, hasLength(1));
      expect(recoveries.single.published, isFalse);
      expect(recoveries.single.abandoned, hasLength(1));
      expect(recoveries.single.abandoned.single.profileId, stagedId);
      expect(recoveries.single.abandoned.single.generation, 1);

      await registry.completeInterruptedRestoreRecovery(recoveries.single);
      expect(await registry.interruptedRestores(), isEmpty);
    },
  );
}
