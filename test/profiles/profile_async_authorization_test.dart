import 'dart:io';

import 'package:debrify/models/profiles/connection_resource.dart';
import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/services/profiles/profile_async_authorization.dart';
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
  late String firstId;
  late String secondId;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'profile-async-authorization-test-',
    );
    registry = await ProfileRegistry.open(
      path: p.join(temporaryDirectory.path, 'profiles.db'),
    );
    firstId = (await registry.createProfile(
      name: 'First',
      role: UserProfileRole.admin,
    )).id;
    secondId = (await registry.createProfile(
      name: 'Second',
      role: UserProfileRole.admin,
    )).id;
    ProfileBootstrap.debugInstallRegistry(registry);
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeCommitted(
      ProfileScope(profileId: firstId, dataGeneration: 1, sessionEpoch: 1),
    );
  });

  tearDown(() async {
    ProfileRuntime.debugReset();
    ProfileBootstrap.debugInstallRegistry(null);
    await registry.close();
    await temporaryDirectory.delete(recursive: true);
  });

  test('completion remains bound to the initiating profile scope', () async {
    final capability = await ProfileAsyncAuthorization.capture(
      ProfileFeature.trackersAndDiscovery,
    );
    ProfileRuntime.publish(
      ProfileScope(profileId: secondId, dataGeneration: 1, sessionEpoch: 2),
    );

    final scopes = await capability!.run(() async {
      return (
        captured: ProfileRuntime.capture(),
        visible: ProfileRuntime.scope.value!,
      );
    });

    expect(scopes.captured.profileId, firstId);
    expect(scopes.captured.sessionEpoch, 1);
    // Interactive completions must consult the notifier, not capture(): the
    // captured zone intentionally continues to expose First after Second is
    // the visible profile.
    expect(scopes.visible.profileId, secondId);
    expect(scopes.visible.sessionEpoch, 2);
    expect(ProfileRuntime.capture().profileId, secondId);
    expect(capability.isCurrentlyActive, isFalse);
    await expectLater(capability.runIfCurrent(() async {}), throwsStateError);
  });

  test(
    'authorization revision change revokes an in-flight completion',
    () async {
      final capability = await ProfileAsyncAuthorization.capture(
        ProfileFeature.trackersAndDiscovery,
      );
      await registry.updateProfile(id: firstId, name: 'Changed');

      expect(() => capability!.run(() async {}), throwsA(isA<StateError>()));
    },
  );

  test('feature removal revokes an in-flight completion', () async {
    final capability = await ProfileAsyncAuthorization.capture(
      ProfileFeature.trackersAndDiscovery,
    );
    final profile = (await registry.getProfile(firstId))!;
    await registry.updateProfile(
      id: firstId,
      policy: ProfilePolicy(
        enabled: profile.policy.enabled
            .where((item) => item != ProfileFeature.trackersAndDiscovery)
            .toSet(),
      ),
    );

    expect(() => capability!.run(() async {}), throwsA(isA<StateError>()));
  });

  test('resource rotation revokes an in-flight tracker completion', () async {
    const resourceId = 'resource-mdblist';
    await registry.insertResource(
      resource: ConnectionResource(
        id: resourceId,
        type: ConnectionResourceType.mdblist,
        label: 'MDBList',
        ownerProfileId: firstId,
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
    final capability = await ProfileAsyncAuthorization.capture(
      ProfileFeature.trackersAndDiscovery,
      resourceId: resourceId,
      resourceAuthorizationRevision: 1,
    );

    await registry.updateResourceSecret(
      resourceId: resourceId,
      sealedSecretPayload: 'sealed-v2',
      secretPayloadVersion: 1,
    );

    expect(() => capability!.runIfCurrent(() async {}), throwsStateError);
  });
}
