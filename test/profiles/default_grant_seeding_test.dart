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
