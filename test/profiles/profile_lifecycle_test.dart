import 'dart:io';

import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/services/profiles/profile_lifecycle.dart';
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
    ProfileRuntime.debugReset();
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'lifecycle-test-',
    );
    registry = await ProfileRegistry.open(
      path: p.join(temporaryDirectory.path, 'profiles.db'),
    );
    firstId = (await registry.createProfile(
      name: 'Admin',
      role: UserProfileRole.admin,
    )).id;
    secondId = (await registry.createProfile(
      name: 'Member',
      role: UserProfileRole.member,
    )).id;
    await registry.commitBootstrap(
      activeProfileId: firstId,
      migratedLegacyInstall: false,
    );
    ProfileRuntime.initializeCommitted(
      ProfileScope(profileId: firstId, dataGeneration: 1, sessionEpoch: 1),
    );
  });

  tearDown(() async {
    ProfileRuntime.debugReset();
    await registry.close();
    await temporaryDirectory.delete(recursive: true);
  });

  test('candidate work starts only after authoritative publication', () async {
    final participant = _RecordingParticipant();
    final lifecycle = ProfileLifecycleCoordinator(
      registry: registry,
      participants: <ProfileLifecycleParticipant>[participant],
    );

    expect(await lifecycle.switchTo(secondId), isTrue);
    expect(participant.candidateCapture?.profileId, secondId);
    expect(participant.globalDuringCandidate?.profileId, secondId);
    expect(ProfileRuntime.capture().profileId, secondId);
    expect((await registry.activeProfile())?.id, secondId);
    lifecycle.dispose();
  });

  test(
    'post-commit candidate failure rolls forward to committed profile',
    () async {
      final lifecycle = ProfileLifecycleCoordinator(
        registry: registry,
        participants: <ProfileLifecycleParticipant>[_FailingParticipant()],
      );

      await expectLater(() => lifecycle.switchTo(secondId), throwsStateError);
      expect(ProfileRuntime.capture().profileId, secondId);
      expect((await registry.activeProfile())?.id, secondId);
      lifecycle.dispose();
    },
  );
}

class _RecordingParticipant implements ProfileLifecycleParticipant {
  ProfileScope? candidateCapture;
  ProfileScope? globalDuringCandidate;

  @override
  Future<void> prepareDeactivate(ProfileScope current) async {}

  @override
  Future<void> initializeCandidate(ProfileScope candidate) async {
    await ProfileRuntime.withCapturedScope(candidate, () async {
      candidateCapture = ProfileRuntime.capture();
      globalDuringCandidate = ProfileRuntime.scope.value;
    });
  }

  @override
  Future<void> didActivate(ProfileScope active) async {}

  @override
  Future<void> rollback(ProfileScope restored) async {}
}

class _FailingParticipant implements ProfileLifecycleParticipant {
  @override
  Future<void> prepareDeactivate(ProfileScope current) async {}

  @override
  Future<void> initializeCandidate(ProfileScope candidate) async {
    throw StateError('candidate failed');
  }

  @override
  Future<void> didActivate(ProfileScope active) async {}

  @override
  Future<void> rollback(ProfileScope restored) async {}
}
