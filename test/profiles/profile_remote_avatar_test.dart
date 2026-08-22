import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:debrify/models/profiles/profile_avatar.dart';
import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/services/profiles/profile_avatar_policy.dart';
import 'package:debrify/services/profiles/profile_avatar_ingest.dart';
import 'package:debrify/services/profiles/profile_avatar_mutation.dart';
import 'package:debrify/services/profiles/profile_avatar_storage.dart';
import 'package:debrify/services/profiles/profile_authorization.dart';
import 'package:debrify/services/profiles/profile_bootstrap.dart';
import 'package:debrify/services/profiles/profile_registry.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/remote_control/remote_command_router.dart';
import 'package:debrify/services/remote_control/remote_control_state.dart';
import 'package:debrify/services/remote_control/remote_session.dart';
import 'package:debrify/utils/app_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'avatar_fixtures.dart';

/// The phone→TV avatar path. The handler is exercised directly: transport
/// authentication and the lease are pinned by the existing remote tests, and
/// what is new here is what happens AFTER a payload arrives.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late ProfileRegistry registry;
  final router = RemoteCommandRouter();

  const authenticated = RemoteCommandContext(
    encrypted: true,
    authorized: true,
    sidB64: 'sid',
    peerFingerprint: 'peer',
    sourceIp: '192.168.1.50',
  );

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await RemoteControlState().debugResetForTesting();
    ProfileRuntime.debugReset();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    root = await Directory.systemTemp.createTemp('remote-avatar-');
    AppStorage.debugOverride(documents: root, support: root, cache: root);
    registry = await ProfileRegistry.open(
      path: p.join(root.path, 'profiles.db'),
    );
  });

  tearDown(() async {
    await RemoteControlState().debugResetForTesting();
    await registry.close();
    ProfileBootstrap.debugInstallRegistry(null);
    ProfileRuntime.debugReset();
    ProfileAvatarPolicy.debugSetUserImagesSupported(null);
    AppStorage.debugReset();
    if (await root.exists()) await root.delete(recursive: true);
  });

  Future<String> commitAs(UserProfileRole role) async {
    final profile = await registry.createProfile(
      name: 'Actor',
      role: role,
      policy: ProfilePolicy.allAllowedFor(role),
    );
    await registry.commitBootstrap(
      activeProfileId: profile.id,
      migratedLegacyInstall: false,
    );
    ProfileBootstrap.debugInstallRegistry(registry);
    ProfileRuntime.initializeCommitted(
      ProfileScope(profileId: profile.id, dataGeneration: 1, sessionEpoch: 1),
    );
    return profile.id;
  }

  test('a managing Admin receives and applies the avatar', () async {
    final id = await commitAs(UserProfileRole.admin);
    final payload = base64Encode(await paintPng(size: 32));
    final replies = <String>[];

    await router.debugHandleProfileAvatar(
      payload,
      RemoteCommandContext(
        encrypted: true,
        authorized: true,
        sidB64: 'sid',
        peerFingerprint: 'peer',
        sourceIp: '192.168.1.50',
        reject: (code) async => replies.add(code),
      ),
    );

    final profile = await registry.getProfile(id);
    final avatar = ProfileAvatar.tryParse(profile!.avatarKey);
    expect(avatar?.kind, ProfileAvatarKind.image);
    expect(avatar?.dominantColor, isNotNull);
    final directory = Directory(p.join(root.path, 'profiles', id, 'avatars'));
    expect(await directory.list().length, 1);
    expect(replies, contains('avatar_ok'));
  });

  test('legacy mode refuses — there is no profile to attach it to', () async {
    ProfileRuntime.initializeLegacy();
    final payload = base64Encode(await paintPng(size: 32));
    await router.debugHandleProfileAvatar(payload, authenticated);
    expect(
      await Directory(p.join(root.path, 'profiles')).exists(),
      isFalse,
      reason: 'nothing may be written in legacy mode',
    );
  });

  test('tvOS refuses at the policy boundary and tells the sender', () async {
    await commitAs(UserProfileRole.admin);
    ProfileAvatarPolicy.debugSetUserImagesSupported(false);
    final rejections = <String>[];
    final context = RemoteCommandContext(
      encrypted: true,
      authorized: true,
      sidB64: 'sid',
      peerFingerprint: 'peer',
      sourceIp: '192.168.1.50',
      reject: (code) async => rejections.add(code),
    );

    await router.debugHandleProfileAvatar(
      base64Encode(await paintPng(size: 32)),
      context,
    );

    expect(rejections, contains('avatar_unsupported'));
  });

  test('a non-managing profile cannot apply an avatar remotely', () async {
    // Bootstrap requires a managing Admin and post-commit mutations require
    // an Admin actor — so create BOTH profiles first, commit with the Admin,
    // then point the runtime at the Member (a signed-in Member session).
    final admin = await registry.createProfile(
      name: 'Actor',
      role: UserProfileRole.admin,
      policy: ProfilePolicy.allAllowedFor(UserProfileRole.admin),
    );
    final member = await registry.createProfile(
      name: 'Member',
      role: UserProfileRole.member,
      policy: ProfilePolicy.allAllowedFor(UserProfileRole.member),
    );
    await registry.commitBootstrap(
      activeProfileId: admin.id,
      migratedLegacyInstall: false,
    );
    ProfileBootstrap.debugInstallRegistry(registry);
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeCommitted(
      ProfileScope(profileId: member.id, dataGeneration: 1, sessionEpoch: 1),
    );
    final before = (await registry.getProfile(member.id))!.avatarKey;
    final replies = <String>[];

    await router.debugHandleProfileAvatar(
      base64Encode(await paintPng(size: 32)),
      RemoteCommandContext(
        encrypted: true,
        authorized: true,
        sidB64: 'sid',
        peerFingerprint: 'peer',
        sourceIp: '192.168.1.50',
        reject: (code) async => replies.add(code),
      ),
    );

    expect((await registry.getProfile(member.id))!.avatarKey, before);
    expect(replies, contains('avatar_not_authorized'));
  });

  test('a correlated envelope replies only after apply', () async {
    final id = await commitAs(UserProfileRole.admin);
    final replies = <String>[];
    final envelope = jsonEncode(<String, Object?>{
      'version': 1,
      'requestId': 'request-1',
      'data': base64Encode(await paintPng(size: 32)),
    });

    await router.debugHandleProfileAvatar(
      envelope,
      RemoteCommandContext(
        encrypted: true,
        authorized: true,
        reject: (code) async => replies.add(code),
      ),
    );

    expect((await registry.getProfile(id))!.avatarKey, startsWith('file:'));
    expect(replies, List<String>.filled(3, 'profile_avatar:request-1:ok'));
  });

  test('overlapping avatar writers publish and prune in queue order', () async {
    final id = await commitAs(UserProfileRole.admin);
    final firstPrepared = await ProfileAvatarIngest.prepare(
      await paintPng(size: 32, color: const Color(0xFFCC3333)),
    );
    final secondPrepared = await ProfileAvatarIngest.prepare(
      await paintPng(size: 32, color: const Color(0xFF3366CC)),
    );
    final firstPersisted = Completer<void>();
    final releaseFirst = Completer<void>();
    var secondPersistStarted = false;
    final firstAuthorization = await ProfileAuthorizationContext.capture(
      registry,
    );

    final first = ProfileAvatarIngest.publish(
      registry: registry,
      profileId: id,
      avatarKey: firstPrepared.avatar.format(),
      prepared: firstPrepared,
      persist: () async {
        await registry.updateProfile(
          id: id,
          avatarKey: firstPrepared.avatar.format(),
          actingProfileId: firstAuthorization.profileId,
          actingAuthorizationRevision: firstAuthorization.authorizationRevision,
          actingSessionEpoch: firstAuthorization.sessionEpoch,
        );
        firstPersisted.complete();
        await releaseFirst.future;
      },
      wasPersisted: () async =>
          (await registry.getProfile(id))?.avatarKey ==
          firstPrepared.avatar.format(),
    );
    await firstPersisted.future;

    final second = ProfileAvatarIngest.publish(
      registry: registry,
      profileId: id,
      avatarKey: secondPrepared.avatar.format(),
      prepared: secondPrepared,
      persist: () async {
        secondPersistStarted = true;
        final authorization = await ProfileAuthorizationContext.capture(
          registry,
        );
        await registry.updateProfile(
          id: id,
          avatarKey: secondPrepared.avatar.format(),
          actingProfileId: authorization.profileId,
          actingAuthorizationRevision: authorization.authorizationRevision,
          actingSessionEpoch: authorization.sessionEpoch,
        );
      },
      wasPersisted: () async =>
          (await registry.getProfile(id))?.avatarKey ==
          secondPrepared.avatar.format(),
    );
    await Future<void>.delayed(Duration.zero);
    expect(secondPersistStarted, isFalse);

    releaseFirst.complete();
    await Future.wait(<Future<void>>[first, second]);

    expect(
      (await registry.getProfile(id))?.avatarKey,
      secondPrepared.avatar.format(),
    );
    expect(
      await (await ProfileAvatarStorage.fileFor(
        id,
        firstPrepared.avatar,
      )).exists(),
      isFalse,
    );
    expect(
      await (await ProfileAvatarStorage.fileFor(
        id,
        secondPrepared.avatar,
      )).exists(),
      isTrue,
    );
  });

  test(
    'a failed checkpoint retry preserves both files and the recovery intent',
    () async {
      final id = await commitAs(UserProfileRole.admin);
      final firstPrepared = await ProfileAvatarIngest.prepare(
        await paintPng(size: 32, color: const Color(0xFFCC3333)),
      );
      var authorization = await ProfileAuthorizationContext.capture(registry);
      await ProfileAvatarIngest.publish(
        registry: registry,
        profileId: id,
        avatarKey: firstPrepared.avatar.format(),
        prepared: firstPrepared,
        persist: () async {
          await registry.updateProfile(
            id: id,
            avatarKey: firstPrepared.avatar.format(),
            actingProfileId: authorization.profileId,
            actingAuthorizationRevision: authorization.authorizationRevision,
            actingSessionEpoch: authorization.sessionEpoch,
          );
        },
        wasPersisted: () async =>
            (await registry.getProfile(id))?.avatarKey ==
            firstPrepared.avatar.format(),
      );

      final secondPrepared = await ProfileAvatarIngest.prepare(
        await paintPng(size: 32, color: const Color(0xFF3366CC)),
      );
      authorization = await ProfileAuthorizationContext.capture(registry);
      registry.authorityChangedCallback = () async {
        if ((await registry.getProfile(id))?.avatarKey ==
            secondPrepared.avatar.format()) {
          throw StateError('durable checkpoint unavailable');
        }
      };

      await expectLater(
        ProfileAvatarIngest.publish(
          registry: registry,
          profileId: id,
          avatarKey: secondPrepared.avatar.format(),
          prepared: secondPrepared,
          persist: () async {
            await registry.updateProfile(
              id: id,
              avatarKey: secondPrepared.avatar.format(),
              actingProfileId: authorization.profileId,
              actingAuthorizationRevision: authorization.authorizationRevision,
              actingSessionEpoch: authorization.sessionEpoch,
            );
          },
          wasPersisted: () async =>
              (await registry.getProfile(id))?.avatarKey ==
              secondPrepared.avatar.format(),
        ),
        throwsStateError,
      );

      expect(
        await (await ProfileAvatarStorage.fileFor(
          id,
          firstPrepared.avatar,
        )).exists(),
        isTrue,
        reason: 'the previous durable authority must not be pruned yet',
      );
      expect(
        await (await ProfileAvatarStorage.fileFor(
          id,
          secondPrepared.avatar,
        )).exists(),
        isTrue,
      );

      registry.authorityChangedCallback = null;
      await ProfileAvatarMutation.recover(registry);
      expect(
        await (await ProfileAvatarStorage.fileFor(
          id,
          firstPrepared.avatar,
        )).exists(),
        isFalse,
      );
      expect(
        await (await ProfileAvatarStorage.fileFor(
          id,
          secondPrepared.avatar,
        )).exists(),
        isTrue,
      );
    },
  );

  test(
    'an unknown fallback key does not block unrelated profile edits',
    () async {
      final id = await commitAs(UserProfileRole.admin);
      var authorization = await ProfileAuthorizationContext.capture(registry);
      await registry.updateProfile(
        id: id,
        avatarKey: 'future-avatar:nebula',
        actingProfileId: authorization.profileId,
        actingAuthorizationRevision: authorization.authorizationRevision,
        actingSessionEpoch: authorization.sessionEpoch,
      );
      authorization = await ProfileAuthorizationContext.capture(registry);

      await ProfileAvatarIngest.publish(
        registry: registry,
        profileId: id,
        avatarKey: 'future-avatar:nebula',
        persist: () async {
          await registry.updateProfile(
            id: id,
            name: 'Renamed',
            avatarKey: 'future-avatar:nebula',
            actingProfileId: authorization.profileId,
            actingAuthorizationRevision: authorization.authorizationRevision,
            actingSessionEpoch: authorization.sessionEpoch,
          );
        },
        wasPersisted: () async {
          final profile = await registry.getProfile(id);
          return profile?.name == 'Renamed' &&
              profile?.avatarKey == 'future-avatar:nebula';
        },
      );

      expect((await registry.getProfile(id))?.name, 'Renamed');
    },
  );

  test(
    'an interrupted first ledger temporary does not block recovery',
    () async {
      await commitAs(UserProfileRole.admin);
      final temporary = File(
        p.join(root.path, 'profile-avatar-mutations-v1.json.write.tmp'),
      );
      await temporary.writeAsString('{', flush: true);

      await ProfileAvatarMutation.recover(registry);

      expect(await temporary.exists(), isFalse);
    },
  );

  test(
    'startup discards a candidate whose registry update never committed',
    () async {
      final id = await commitAs(UserProfileRole.admin);
      final prepared = await ProfileAvatarIngest.prepare(
        await paintPng(size: 32),
      );
      await ProfileAvatarMutation.begin(id, prepared.avatar.format());
      await ProfileAvatarIngest.writeCandidate(
        profileId: id,
        prepared: prepared,
      );

      await ProfileAvatarMutation.recover(registry);

      final file = await ProfileAvatarStorage.fileFor(id, prepared.avatar);
      expect(await file.exists(), isFalse);
      expect((await registry.getProfile(id))?.avatarKey, isNull);
    },
  );

  test(
    'startup finishes a candidate whose registry update committed',
    () async {
      final id = await commitAs(UserProfileRole.admin);
      final prepared = await ProfileAvatarIngest.prepare(
        await paintPng(size: 32),
      );
      await ProfileAvatarMutation.begin(id, prepared.avatar.format());
      await ProfileAvatarIngest.writeCandidate(
        profileId: id,
        prepared: prepared,
      );
      final authorization = await ProfileAuthorizationContext.capture(registry);
      await registry.updateProfile(
        id: id,
        avatarKey: prepared.avatar.format(),
        actingProfileId: authorization.profileId,
        actingAuthorizationRevision: authorization.authorizationRevision,
        actingSessionEpoch: authorization.sessionEpoch,
      );

      await ProfileAvatarMutation.recover(registry);

      final file = await ProfileAvatarStorage.fileFor(id, prepared.avatar);
      expect(await file.exists(), isTrue);
      expect(
        (await registry.getProfile(id))?.avatarKey,
        prepared.avatar.format(),
      );
      expect(
        await (await ProfileAvatarStorage.directoryFor(id)).list().length,
        1,
      );
    },
  );

  test('an oversized payload is bounced before decoding', () async {
    final id = await commitAs(UserProfileRole.admin);
    final huge = 'A' * (2 * 1024 * 1024);
    await router.debugHandleProfileAvatar(huge, authenticated);
    expect(
      (await registry.getProfile(id))!.avatarKey,
      isNot(startsWith('file:')),
    );
  });

  test(
    'sender result is false when the authenticated receiver rejects',
    () async {
      final state = RemoteControlState();
      final session = RemoteSession(
        sid: Uint8List.fromList(List<int>.filled(16, 7)),
        role: RemoteSessionRole.sender,
        keys: const SessionKeys(
          c2s: <int>[],
          s2c: <int>[],
          conf: <int>[],
          sas: <int>[],
        ),
        peerStaticKey: const <int>[],
        peerFingerprint: 'tv',
        peerName: 'TV',
        sasCode: '123456',
        establishedAt: DateTime.now(),
      )..authorized = true;
      state.debugInstallOutboundSession(session, ip: 'tv');
      state.debugCommandSealer = (_, command) async {
        final payload = jsonDecode(command['data']! as String) as Map;
        final requestId = payload['requestId']! as String;
        Future<void>.microtask(
          () => state.debugHandleProfileAvatarReply(
            'profile_avatar:$requestId:not_authorized',
          ),
        );
        return <String, dynamic>{'type': 'ecmd', 'ct': 'sealed'};
      };
      state.debugRawSender = (_, __, ___) => true;

      expect(
        await state.sendProfileAvatar('tv', await paintPng(size: 32)),
        isFalse,
      );
    },
  );
}
