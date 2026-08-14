import 'dart:io';

import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/services/profiles/profile_bootstrap.dart';
import 'package:debrify/services/profiles/profile_registry.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/remote_control/remote_command_router.dart';
import 'package:debrify/services/remote_control/remote_constants.dart';
import 'package:debrify/services/remote_control/remote_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// A committed profile install drops every unauthenticated packet, and
/// `reject` is deliberately absent for plaintext — so a pre-v2 phone gets
/// total silence. These pin the on-screen notice that replaces that silence.
void main() {
  late Directory temporaryDirectory;
  late ProfileRegistry registry;
  final router = RemoteCommandRouter();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    ProfileRuntime.debugReset();
    router.debugResetStaleRemoteNotices();
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'profile-remote-stale-notice-test-',
    );
    registry = await ProfileRegistry.open(
      path: p.join(temporaryDirectory.path, 'profiles.db'),
    );
    final admin = await registry.createProfile(
      name: 'Admin',
      role: UserProfileRole.admin,
      policy: ProfilePolicy.defaultsFor(UserProfileRole.admin),
    );
    await registry.commitBootstrap(
      activeProfileId: admin.id,
      migratedLegacyInstall: true,
    );
    ProfileBootstrap.debugInstallRegistry(registry);
    ProfileRuntime.initializeCommitted(
      ProfileScope(profileId: admin.id, dataGeneration: 1, sessionEpoch: 1),
    );
  });

  tearDown(() async {
    await registry.close();
    ProfileBootstrap.debugInstallRegistry(null);
    ProfileRuntime.debugReset();
    router.debugResetStaleRemoteNotices();
    await temporaryDirectory.delete(recursive: true);
  });

  Future<void> sendPlaintextNavigate({required String sourceIp}) =>
      router.debugDispatchAndWait(
        RemoteAction.navigate,
        NavigateCommand.up,
        null,
        RemoteCommandContext(
          encrypted: false,
          authorized: false,
          sourceIp: sourceIp,
        ),
      );

  test(
    'a burst of dropped plaintext from one phone raises the notice',
    () async {
      await sendPlaintextNavigate(sourceIp: '192.168.1.50');
      await sendPlaintextNavigate(sourceIp: '192.168.1.50');
      expect(
        router.debugStaleRemoteNoticeCount,
        0,
        reason: 'a stray datagram or two is not a stuck remote',
      );

      await sendPlaintextNavigate(sourceIp: '192.168.1.50');
      expect(router.debugStaleRemoteNoticeCount, 1);
    },
  );

  test(
    'the notice does not repeat while the same phone keeps pressing',
    () async {
      for (var press = 0; press < 12; press++) {
        await sendPlaintextNavigate(sourceIp: '192.168.1.50');
      }
      expect(
        router.debugStaleRemoteNoticeCount,
        1,
        reason: 'a held D-pad must not parade a snackbar per keypress',
      );
    },
  );

  test('drops are counted per source, not pooled across the LAN', () async {
    await sendPlaintextNavigate(sourceIp: '192.168.1.50');
    await sendPlaintextNavigate(sourceIp: '192.168.1.51');
    await sendPlaintextNavigate(sourceIp: '192.168.1.52');
    expect(
      router.debugStaleRemoteNoticeCount,
      0,
      reason: 'three different hosts are not one old phone',
    );
  });

  test(
    'an encrypted peer that has merely not paired is never told to update',
    () async {
      for (var attempt = 0; attempt < 6; attempt++) {
        await router.debugDispatchAndWait(
          RemoteAction.navigate,
          NavigateCommand.up,
          null,
          const RemoteCommandContext(
            encrypted: true,
            authorized: false,
            sourceIp: '192.168.1.60',
          ),
        );
      }
      expect(
        router.debugStaleRemoteNoticeCount,
        0,
        reason: 'that phone is current and needs the pairing UI, not an update',
      );
    },
  );
}
