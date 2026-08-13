import 'dart:io';

import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/services/profiles/profile_bootstrap.dart';
import 'package:debrify/services/profiles/profile_registry.dart';
import 'package:debrify/services/profiles/profile_remote_lease.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/remote_control/remote_command_router.dart';
import 'package:debrify/services/remote_control/remote_constants.dart';
import 'package:debrify/services/remote_control/remote_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory temporaryDirectory;
  late ProfileRegistry registry;
  late String firstId;
  late String secondId;
  final router = RemoteCommandRouter();
  const peer = RemoteCommandContext(
    encrypted: true,
    authorized: true,
    sidB64: 'session-one',
    peerFingerprint: 'peer-one',
  );

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'remote-profile-test-',
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
      role: UserProfileRole.member,
    )).id;
    ProfileBootstrap.debugInstallRegistry(registry);
    ProfileRuntime.debugReset();
    final scope = ProfileScope(
      profileId: firstId,
      dataGeneration: 1,
      sessionEpoch: 1,
    );
    ProfileRuntime.initializeCommitted(scope);
    ProfileRemoteLease.instance.authorize(
      (await registry.getProfile(firstId))!,
      scope,
    );
    router.clearProfileTransferBuffer();
  });

  tearDown(() async {
    router.clearProfileTransferBuffer();
    ProfileRemoteLease.instance.revoke();
    ProfileRuntime.debugReset();
    ProfileBootstrap.debugInstallRegistry(null);
    await registry.close();
    await temporaryDirectory.delete(recursive: true);
  });

  test(
    'buffer is replaced rather than inherited after a profile switch',
    () async {
      await router.debugDispatchAndWait(
        RemoteAction.config,
        ConfigCommand.realDebrid,
        'first-secret',
        peer,
      );
      expect(router.debugProfileTransferKeys, contains('realDebridApiKey'));

      final secondScope = ProfileScope(
        profileId: secondId,
        dataGeneration: 1,
        sessionEpoch: 2,
      );
      ProfileRuntime.publish(secondScope);
      ProfileRemoteLease.instance.authorize(
        (await registry.getProfile(secondId))!,
        secondScope,
      );
      await router.debugDispatchAndWait(
        RemoteAction.config,
        ConfigCommand.torbox,
        'second-secret',
        peer,
      );

      expect(router.debugProfileTransferKeys, contains('torboxApiKey'));
      expect(
        router.debugProfileTransferKeys,
        isNot(contains('realDebridApiKey')),
      );
      expect(router.debugProfileTransferScope, secondScope);
    },
  );

  test('a second peer cannot merge into an existing receive buffer', () async {
    await router.debugDispatchAndWait(
      RemoteAction.config,
      ConfigCommand.realDebrid,
      'first-secret',
      peer,
    );
    await router.debugDispatchAndWait(
      RemoteAction.config,
      ConfigCommand.torbox,
      'other-secret',
      const RemoteCommandContext(
        encrypted: true,
        authorized: true,
        sidB64: 'session-two',
        peerFingerprint: 'peer-two',
      ),
    );

    expect(router.debugProfileTransferKeys, contains('realDebridApiKey'));
    expect(router.debugProfileTransferKeys, isNot(contains('torboxApiKey')));
  });
}
