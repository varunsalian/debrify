import 'dart:convert';
import 'dart:io';

import 'package:debrify/models/profiles/connection_resource.dart';
import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/models/profiles/user_profile.dart';
import 'package:debrify/services/profiles/profile_authorization.dart';
import 'package:debrify/services/profiles/profile_bootstrap.dart';
import 'package:debrify/services/profiles/profile_registry.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Default-on sharing (profile_features spec): everything on this device
/// starts enabled for every profile — EXCEPT the personal kinds (trackers),
/// whose history belongs to one person. Seeds are use+download only; the
/// stronger permissions stay owner-only or explicit grants.
void main() {
  late Directory root;
  late ProfileRegistry registry;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late ProfileAuthorizationContext actor;

  setUp(() async {
    ProfileRuntime.debugReset();
    root = await Directory.systemTemp.createTemp('grant-seed-');
    registry = await ProfileRegistry.open(
      path: p.join(root.path, 'profiles.db'),
    );
  });

  tearDown(() async {
    ProfileBootstrap.debugInstallRegistry(null);
    ProfileRuntime.debugReset();
    await registry.close();
    await root.delete(recursive: true);
  });

  Future<UserProfilePair> household() async {
    final admin = await registry.createProfile(
      name: 'Admin',
      role: UserProfileRole.admin,
      policy: ProfilePolicy.defaultsFor(UserProfileRole.admin),
    );
    final kid = await registry.createProfile(
      name: 'Maya',
      role: UserProfileRole.child,
      policy: ProfilePolicy.defaultsFor(UserProfileRole.child),
    );
    await registry.commitBootstrap(
      activeProfileId: admin.id,
      migratedLegacyInstall: false,
    );
    ProfileBootstrap.debugInstallRegistry(registry);
    ProfileRuntime.initializeCommitted(
      ProfileScope(profileId: admin.id, dataGeneration: 1, sessionEpoch: 1),
    );
    actor = await ProfileAuthorizationContext.capture(registry);
    return (admin: admin.id, kid: kid.id);
  }

  // Captured FRESH per call: inserting a resource bumps the owner's
  // authorizationRevision, so a context captured before the insert is
  // stale by design.
  Future<UserProfile> createActing(String name, UserProfileRole role) async {
    final fresh = await ProfileAuthorizationContext.capture(registry);
    return registry.createProfile(
      name: name,
      role: role,
      policy: ProfilePolicy.defaultsFor(role),
      actingProfileId: fresh.profileId,
      actingAuthorizationRevision: fresh.authorizationRevision,
      actingSessionEpoch: fresh.sessionEpoch,
    );
  }

  Future<void> insert(
    String owner,
    ConnectionResourceType type, {
    String id = 'r1',
  }) async {
    await registry.insertResource(
      resource: ConnectionResource(
        id: id,
        type: type,
        label: 'Resource $id',
        ownerProfileId: owner,
        publicConfig: const <String, dynamic>{},
        authorizationRevision: 1,
        enabled: true,
      ),
      sealedSecretPayload: jsonEncode(<String, dynamic>{'sealed': true}),
      secretPayloadVersion: 1,
      ownerPermissions: ResourcePermission.values.fold<int>(
        0,
        (mask, permission) => mask | permission.bit,
      ),
    );
  }

  test('a new shareable resource is granted to every existing profile', () async {
    final ids = await household();
    await insert(ids.admin, ConnectionResourceType.realDebrid);

    final grant = await registry.getGrant(ids.kid, 'r1');
    expect(grant, isNotNull);
    expect(grant!.allows(ResourcePermission.use), isTrue);
    expect(grant.allows(ResourcePermission.download), isTrue);
    expect(grant.allows(ResourcePermission.revealSecret), isFalse);
    expect(grant.allows(ResourcePermission.manage), isFalse);
    expect(grant.allows(ResourcePermission.share), isFalse);
  });

  test('revoking owned shares unblocks deleting a scaffold profile', () async {
    // The post-restore trap: a setup admin's auto-seeded resources are
    // granted to every profile, which made the scaffold profile
    // undeletable. Revocation strips the borrowers' grants (bumping their
    // authorization revisions) and the delete-time shared==0 guard passes.
    final ids = await household();
    // A second admin so the admin invariant survives deleting the first;
    // give the scaffold-to-be a seeded resource shared with everyone.
    final keeper = await createActing('Keeper', UserProfileRole.admin);
    await insert(ids.admin, ConnectionResourceType.stremioAddon);
    expect(await registry.getGrant(ids.kid, 'r1'), isNotNull);

    // The REAL post-restore shape: the acting admin is NOT the owner — it
    // borrows the scaffold's seeded resources like everyone else, so the
    // revocation bumps the ACTOR's own revision and its captured context
    // goes stale (the live bug: every later authority check failed).
    await registry.setActiveProfile(keeper.id);
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeCommitted(
      ProfileScope(profileId: keeper.id, dataGeneration: 1, sessionEpoch: 1),
    );
    final kidBefore = (await registry.getProfile(ids.kid))!;
    final actorBefore = await ProfileAuthorizationContext.capture(registry);
    final revoked = await registry.revokeGrantsOnOwnedResources(
      ownerProfileId: ids.admin,
      actingProfileId: actorBefore.profileId,
      actingAuthorizationRevision: actorBefore.authorizationRevision,
      actingSessionEpoch: actorBefore.sessionEpoch,
    );
    expect(revoked, greaterThanOrEqualTo(2)); // kid + keeper at minimum
    expect(await registry.getGrant(ids.kid, 'r1'), isNull);
    expect(
      (await registry.getProfile(ids.kid))!.authorizationRevision,
      greaterThan(kidBefore.authorizationRevision),
    );
    // The owner's own grant survives.
    expect(await registry.getGrant(ids.admin, 'r1'), isNotNull);
    // The acting admin was a borrower: its OWN revision bumped, so the
    // pre-revocation context is now stale and must be refused.
    expect(
      (await registry.getProfile(keeper.id))!.authorizationRevision,
      greaterThan(actorBefore.authorizationRevision),
    );
    await expectLater(
      registry.deleteProfileWithDisposition(
        id: ids.admin,
        deleteOwnedResources: true,
        detachPublicArtifacts: true,
        actingProfileId: actorBefore.profileId,
        actingAuthorizationRevision: actorBefore.authorizationRevision,
        actingSessionEpoch: actorBefore.sessionEpoch,
      ),
      throwsA(isA<StateError>()),
    );

    // With a FRESH capture (the fix), deletion passes the shared==0 guard.
    final acting = await ProfileAuthorizationContext.capture(registry);
    await registry.deleteProfileWithDisposition(
      id: ids.admin,
      deleteOwnedResources: true,
      detachPublicArtifacts: true,
      actingProfileId: acting.profileId,
      actingAuthorizationRevision: acting.authorizationRevision,
      actingSessionEpoch: acting.sessionEpoch,
    );
    expect(await registry.getProfile(ids.admin), isNull);
  });

  test('a new profile is granted every existing shareable resource', () async {
    final ids = await household();
    await insert(ids.admin, ConnectionResourceType.torbox, id: 'r2');
    final lateJoiner = await createActing('Sam', UserProfileRole.member);

    final grant = await registry.getGrant(lateJoiner.id, 'r2');
    expect(grant, isNotNull);
    expect(grant!.allows(ResourcePermission.use), isTrue);
  });

  test('personal kinds (trackers) are never seeded', () async {
    final ids = await household();
    await insert(ids.admin, ConnectionResourceType.trakt, id: 'trakt1');
    await insert(ids.admin, ConnectionResourceType.simkl, id: 'simkl1');

    expect(await registry.getGrant(ids.kid, 'trakt1'), isNull);
    expect(await registry.getGrant(ids.kid, 'simkl1'), isNull);

    final lateJoiner = await createActing('Sam', UserProfileRole.member);
    expect(await registry.getGrant(lateJoiner.id, 'trakt1'), isNull);
  });

  test('seeding never overwrites an explicit grant', () async {
    final ids = await household();
    final sam = await createActing('Sam', UserProfileRole.member);
    await insert(ids.admin, ConnectionResourceType.premiumize, id: 'r3');
    // An admin later strengthens Sam's grant explicitly (writeRemote is
    // legal for a member — the registry's child grant-ceiling forbids it
    // for kids, which its own suite covers)…
    await registry.upsertGrant(
      profileId: sam.id,
      resourceId: 'r3',
      permissions:
          ResourcePermission.use.bit |
          ResourcePermission.download.bit |
          ResourcePermission.writeRemote.bit,
      grantedByProfileId: ids.admin,
      origin: const <String, dynamic>{'origin': 'profileShare'},
    );
    // …and a later profile-create sweep must not downgrade it (IGNORE).
    await createActing('Riva', UserProfileRole.member);
    final grant = await registry.getGrant(sam.id, 'r3');
    expect(grant!.allows(ResourcePermission.writeRemote), isTrue);
  });
}

typedef UserProfilePair = ({String admin, String kid});
