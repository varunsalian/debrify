import 'dart:io';

import 'package:debrify/models/profiles/profile_policy.dart';
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
  late String adminId;
  late String memberId;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'profile-self-service-',
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
      avatarKey: 'person',
    )).id;
    await registry.commitBootstrap(
      activeProfileId: adminId,
      migratedLegacyInstall: false,
    );
    await registry.setActiveProfile(memberId);
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeCommitted(
      ProfileScope(profileId: memberId, dataGeneration: 1, sessionEpoch: 1),
    );
    ProfileLockController.instance.unlock(
      (await registry.getProfile(memberId))!,
    );
  });

  tearDown(() async {
    ProfileLockController.instance.dispose();
    ProfileRuntime.debugReset();
    await registry.close();
    await temporaryDirectory.delete(recursive: true);
  });

  test('Member can change only their active display identity', () async {
    final actor = await ProfileAuthorizationContext.capture(registry);
    final before = (await registry.getProfile(memberId))!;

    final updated = await registry.updateActiveProfileIdentity(
      profileId: actor.profileId,
      name: '  Maya  ',
      avatarKey: 'child',
      actingAuthorizationRevision: actor.authorizationRevision,
      actingSessionEpoch: actor.sessionEpoch,
    );

    expect(updated.name, 'Maya');
    expect(updated.avatarKey, 'child');
    expect(updated.role, before.role);
    expect(updated.policy.encode(), before.policy.encode());
    expect(updated.authorizationRevision, before.authorizationRevision);
    expect((await registry.getProfile(adminId))?.name, 'Admin');
  });

  test(
    'self identity write cannot target another or stale profile session',
    () async {
      final actor = await ProfileAuthorizationContext.capture(registry);
      var invalidations = 0;
      registry.authorityWillChangeCallback = () async {
        invalidations++;
      };

      await expectLater(
        registry.updateActiveProfileIdentity(
          profileId: adminId,
          name: 'Not allowed',
          avatarKey: 'person',
          actingAuthorizationRevision: actor.authorizationRevision,
          actingSessionEpoch: actor.sessionEpoch,
        ),
        throwsStateError,
      );
      expect((await registry.getProfile(adminId))?.name, 'Admin');
      expect(
        invalidations,
        0,
        reason: 'display-only writes must not deny native authority',
      );

      await registry.setActiveProfile(adminId);
      ProfileRuntime.publish(
        ProfileScope(profileId: adminId, dataGeneration: 1, sessionEpoch: 2),
      );
      invalidations = 0;
      await expectLater(
        registry.updateActiveProfileIdentity(
          profileId: memberId,
          name: 'Stale write',
          avatarKey: 'child',
          actingAuthorizationRevision: actor.authorizationRevision,
          actingSessionEpoch: actor.sessionEpoch,
        ),
        throwsStateError,
      );
      expect((await registry.getProfile(memberId))?.name, 'Member');
      expect(
        invalidations,
        0,
        reason: 'display-only writes must not deny native authority',
      );
    },
  );
}
