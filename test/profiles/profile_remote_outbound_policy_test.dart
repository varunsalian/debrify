import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/services/profiles/profile_async_authorization.dart';
import 'package:debrify/services/profiles/profile_authorization.dart';
import 'package:debrify/services/profiles/profile_bootstrap.dart';
import 'package:debrify/services/profiles/profile_registry.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/remote_control/remote_constants.dart';
import 'package:debrify/services/remote_control/remote_control_state.dart';
import 'package:debrify/services/remote_control/remote_session.dart';
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
    ProfileRuntime.debugReset();
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'profile-remote-outbound-policy-test-',
    );
    registry = await ProfileRegistry.open(
      path: p.join(temporaryDirectory.path, 'profiles.db'),
    );
    final policy = ProfilePolicy.defaultsFor(UserProfileRole.admin);
    final restricted = await registry.createProfile(
      name: 'Restricted Admin',
      role: UserProfileRole.admin,
      policy: ProfilePolicy(
        enabled: policy.enabled.difference(const <ProfileFeature>{
          ProfileFeature.remoteTransfer,
        }),
      ),
    );
    await registry.commitBootstrap(
      activeProfileId: restricted.id,
      migratedLegacyInstall: false,
    );
    ProfileBootstrap.debugInstallRegistry(registry);
    ProfileRuntime.initializeCommitted(
      ProfileScope(
        profileId: restricted.id,
        dataGeneration: 1,
        sessionEpoch: 1,
      ),
    );
  });

  tearDown(() async {
    await RemoteControlState().debugResetForTesting();
    ProfileRuntime.debugReset();
    ProfileBootstrap.debugInstallRegistry(null);
    await registry.close();
    await temporaryDirectory.delete(recursive: true);
  });

  test('outbound config and addon sends require remoteTransfer', () async {
    final state = RemoteControlState();

    await expectLater(
      state.sendConfigCommandToDevice(
        ConfigCommand.realDebrid,
        '127.0.0.1',
        configData: 'sentinel-secret',
      ),
      throwsStateError,
    );
    await expectLater(
      state.sendAddonCommandToDevice(
        AddonCommand.install,
        '127.0.0.1',
        manifestUrl: 'https://sentinel.invalid/manifest.json',
      ),
      throwsStateError,
    );
  });

  test('revocation during sealing prevents the socket send', () async {
    final creatingActor = await ProfileAuthorizationContext.capture(registry);
    final allowed = await registry.createProfile(
      name: 'Allowed Admin',
      role: UserProfileRole.admin,
      actingProfileId: creatingActor.profileId,
      actingAuthorizationRevision: creatingActor.authorizationRevision,
      actingSessionEpoch: creatingActor.sessionEpoch,
    );
    await registry.setActiveProfile(allowed.id);
    ProfileRuntime.publish(
      ProfileScope(profileId: allowed.id, dataGeneration: 1, sessionEpoch: 2),
    );
    final authorization = await ProfileAsyncAuthorization.capture(
      ProfileFeature.remoteTransfer,
    );
    final managingActor = await ProfileAuthorizationContext.capture(registry);
    final state = RemoteControlState();
    final session = RemoteSession(
      sid: Uint8List.fromList(List<int>.filled(16, 1)),
      role: RemoteSessionRole.sender,
      keys: const SessionKeys(
        c2s: <int>[],
        s2c: <int>[],
        conf: <int>[],
        sas: <int>[],
      ),
      peerStaticKey: const <int>[],
      peerFingerprint: 'peer',
      peerName: 'TV',
      sasCode: '123456',
      establishedAt: DateTime.now(),
    )..authorized = true;
    state.debugInstallOutboundSession(session, ip: '127.0.0.1');
    final sealing = Completer<void>();
    final release = Completer<void>();
    var sends = 0;
    state.debugCommandSealer = (_, _) async {
      sealing.complete();
      await release.future;
      return <String, dynamic>{'type': 'ecmd', 'ct': 'sealed-sentinel'};
    };
    state.debugRawSender = (_, _, _) {
      sends++;
      return true;
    };

    final send = state.sendConfigCommandToDevice(
      ConfigCommand.realDebrid,
      '127.0.0.1',
      configData: 'sentinel-secret',
      authorizationBarrier: () => authorization!.runIfCurrent(() async {}),
    );
    await sealing.future;
    await registry.updateProfile(
      id: allowed.id,
      policy: ProfilePolicy(
        enabled: allowed.policy.enabled.difference(const <ProfileFeature>{
          ProfileFeature.remoteTransfer,
        }),
      ),
      actingProfileId: managingActor.profileId,
      actingAuthorizationRevision: managingActor.authorizationRevision,
      actingSessionEpoch: managingActor.sessionEpoch,
    );
    release.complete();

    await expectLater(send, throwsStateError);
    expect(sends, 0);
  });
}
