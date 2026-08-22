import 'dart:io';

import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/services/profiles/profile_bootstrap.dart';
import 'package:debrify/services/profiles/profile_registry.dart';
import 'package:debrify/services/profiles/profile_remote_lease.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/remote_control/remote_chunked_send.dart';
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

  test('a profile graph is never staged as a config category', () async {
    // Contrast: a normal config command stages into the transfer buffer...
    await router.debugDispatchAndWait(
      RemoteAction.config,
      ConfigCommand.searchEngines,
      '[]',
      peer,
    );
    expect(router.debugProfileTransferScope, isNotNull);
    router.clearProfileTransferBuffer();

    // ...but a profile graph must bypass staging entirely: it either runs
    // the atomic restoreDeviceGraph path (blocked here — no navigator for
    // its confirm dialog) or does nothing. It must never sit in the buffer
    // pretending to be an importable category.
    await router.debugDispatchAndWait(
      RemoteAction.config,
      ConfigCommand.profileGraph,
      '{"format":"debrify-profile-package"}',
      peer,
    );
    expect(router.debugProfileTransferScope, isNull);
    expect((await registry.listProfiles()).length, 2);
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

  test(
    'completion manifest detects a missing config or addon packet',
    () async {
      await router.debugDispatchAndWait(
        RemoteAction.config,
        ConfigCommand.realDebrid,
        'first-secret',
        peer,
      );

      expect(
        router.debugProfilePayloadContainsExpected(const {
          ConfigCommand.realDebrid: 1,
        }),
        isTrue,
      );
      expect(
        router.debugProfilePayloadContainsExpected(const {
          ConfigCommand.realDebrid: 1,
          ConfigCommand.torbox: 1,
        }),
        isFalse,
      );
      expect(
        router.debugProfilePayloadContainsExpected(const {
          RemoteAction.addon: 1,
        }),
        isFalse,
      );
    },
  );

  test('a v4 start discards stale staging from an interrupted batch', () async {
    await router.debugDispatchAndWait(
      RemoteAction.config,
      ConfigCommand.realDebrid,
      'stale-secret',
      peer,
    );
    await router.debugDispatchAndWait(
      RemoteAction.config,
      ConfigCommand.remoteTransferStart,
      remoteTransferRequestBody('fresh-request'),
      peer,
    );
    await router.debugDispatchAndWait(
      RemoteAction.config,
      ConfigCommand.torbox,
      remoteTransferItemBody(
        requestId: 'fresh-request',
        payload: 'fresh-secret',
      ),
      peer,
    );

    expect(router.debugProfileTransferKeys, contains('torboxApiKey'));
    expect(
      router.debugProfileTransferKeys,
      isNot(contains('realDebridApiKey')),
    );
    expect(
      router.debugProfilePayloadContainsExpected(const {
        ConfigCommand.torbox: 1,
      }),
      isTrue,
    );
  });

  test('a duplicate v4 start is idempotent after items arrive', () async {
    final start = remoteTransferRequestBody('same-request');
    await router.debugDispatchAndWait(
      RemoteAction.config,
      ConfigCommand.remoteTransferStart,
      start,
      peer,
    );
    await router.debugDispatchAndWait(
      RemoteAction.config,
      ConfigCommand.realDebrid,
      remoteTransferItemBody(requestId: 'same-request', payload: 'kept-secret'),
      peer,
    );
    await router.debugDispatchAndWait(
      RemoteAction.config,
      ConfigCommand.remoteTransferStart,
      start,
      peer,
    );

    expect(router.debugProfileTransferValue('realDebridApiKey'), 'kept-secret');
  });

  test('a delayed item cannot enter a newer v4 transfer', () async {
    await router.debugDispatchAndWait(
      RemoteAction.config,
      ConfigCommand.remoteTransferStart,
      remoteTransferRequestBody('request-a'),
      peer,
    );
    await router.debugDispatchAndWait(
      RemoteAction.config,
      ConfigCommand.remoteTransferStart,
      remoteTransferRequestBody('request-b'),
      peer,
    );
    await router.debugDispatchAndWait(
      RemoteAction.config,
      ConfigCommand.realDebrid,
      remoteTransferItemBody(requestId: 'request-a', payload: 'stale-secret'),
      peer,
    );
    await router.debugDispatchAndWait(
      RemoteAction.config,
      ConfigCommand.torbox,
      remoteTransferItemBody(requestId: 'request-b', payload: 'fresh-secret'),
      peer,
    );

    expect(
      router.debugProfileTransferKeys,
      isNot(contains('realDebridApiKey')),
    );
    expect(router.debugProfileTransferValue('torboxApiKey'), 'fresh-secret');
    expect(
      router.debugProfilePayloadContainsExpected(const {
        ConfigCommand.realDebrid: 1,
      }),
      isFalse,
    );
    expect(
      router.debugProfilePayloadContainsExpected(const {
        ConfigCommand.torbox: 1,
      }),
      isTrue,
    );
  });

  test('a delayed completion cannot clear a newer v4 transfer', () async {
    await router.debugDispatchAndWait(
      RemoteAction.config,
      ConfigCommand.remoteTransferStart,
      remoteTransferRequestBody('request-a'),
      peer,
    );
    await router.debugDispatchAndWait(
      RemoteAction.config,
      ConfigCommand.remoteTransferStart,
      remoteTransferRequestBody('request-b'),
      peer,
    );
    await router.debugDispatchAndWait(
      RemoteAction.config,
      ConfigCommand.torbox,
      remoteTransferItemBody(requestId: 'request-b', payload: 'fresh-secret'),
      peer,
    );
    await router.debugDispatchAndWait(
      RemoteAction.config,
      ConfigCommand.complete,
      remoteTransferRequestBody(
        'request-a',
        expectedCommands: const [ConfigCommand.realDebrid],
      ),
      peer,
    );

    expect(router.debugProfileTransferValue('torboxApiKey'), 'fresh-secret');
    expect(
      router.debugProfilePayloadContainsExpected(const {
        ConfigCommand.torbox: 1,
      }),
      isTrue,
    );
  });
}
