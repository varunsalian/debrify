import 'dart:io';

import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/screens/profiles/profile_gate.dart';
import 'package:debrify/services/profiles/profile_authorization.dart';
import 'package:debrify/services/profiles/profile_lifecycle.dart';
import 'package:debrify/services/profiles/profile_registry.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_engine_state.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_runtime.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_tombstones.dart';
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

  for (final sameProfile in [false, true]) {
    test(
      'abort checkpoint failure restores every participant (same ID: $sameProfile)',
      () async {
        final events = <String>[];
        final original = StateError('precommit failed');
        final before = ProfileRuntime.capture();
        final lifecycle = ProfileLifecycleCoordinator(
          registry: registry,
          participants: [
            _RollbackParticipant('first', events),
            _RollbackParticipant('second', events, fail: true),
            _RollbackParticipant('third', events),
          ],
        );
        addTearDown(lifecycle.dispose);
        await expectLater(
          lifecycle.switchTo(
            sameProfile ? firstId : secondId,
            afterDeactivateBeforeCommit: () async {
              registry.authorityChangedCallback = () async {
                throw StateError('abort checkpoint failed');
              };
              throw original;
            },
          ),
          throwsA(same(original)),
        );
        expect(events, ['third', 'second', 'first']);
        expect(ProfileRuntime.capture(), before);
        expect(await registry.getActiveProfileId(), firstId);
        expect(await registry.activationInProgress(), isFalse);
        expect(lifecycle.switching.value, isFalse);
      },
    );
  }

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

  test('post-commit hook runs before candidate initialization', () async {
    final events = <String>[];
    final participant = _OrderedParticipant(events);
    final lifecycle = ProfileLifecycleCoordinator(
      registry: registry,
      participants: <ProfileLifecycleParticipant>[participant],
    );

    expect(
      await lifecycle.switchTo(
        secondId,
        afterCommitBeforeInitialize: () async {
          events.add('hook:${ProfileRuntime.capture().profileId}');
        },
      ),
      isTrue,
    );
    expect(events, <String>[
      'prepare:$firstId',
      'hook:$secondId',
      'initialize:$secondId',
      'activate:$secondId',
    ]);
    lifecycle.dispose();
  });

  test('pre-commit hook runs after drain and before publication', () async {
    final events = <String>[];
    final participant = _OrderedParticipant(events);
    final lifecycle = ProfileLifecycleCoordinator(
      registry: registry,
      participants: <ProfileLifecycleParticipant>[participant],
    );

    expect(
      await lifecycle.switchTo(
        secondId,
        afterDeactivateBeforeCommit: () async {
          events.add('precommit:${ProfileRuntime.capture().profileId}');
          expect((await registry.activeProfile())?.id, firstId);
        },
        afterCommitBeforeInitialize: () async {
          events.add('postcommit:${ProfileRuntime.capture().profileId}');
        },
      ),
      isTrue,
    );
    expect(events, <String>[
      'prepare:$firstId',
      'precommit:$firstId',
      'postcommit:$secondId',
      'initialize:$secondId',
      'activate:$secondId',
    ]);
    lifecycle.dispose();
  });

  test('synced active deletion lands only after replacement switch', () async {
    final actor = await ProfileAuthorizationContext.capture(registry);
    final replacementId = (await registry.createProfile(
      name: 'Replacement Admin',
      role: UserProfileRole.admin,
      actingProfileId: actor.profileId,
      actingAuthorizationRevision: actor.authorizationRevision,
      actingSessionEpoch: actor.sessionEpoch,
    )).id;
    final participant = _RecordingParticipant();
    final lifecycle = ProfileLifecycleCoordinator(
      registry: registry,
      participants: <ProfileLifecycleParticipant>[participant],
    );
    final retiredVersion = (await registry.readProfileSyncProjection())
        .singleWhere((entry) => entry.profile.id == firstId)
        .updatedAtMs;

    expect(await registry.getProfile(firstId), isNotNull);
    expect(
      await switchThenApplySyncedProfileOutcome(
        lifecycle: lifecycle,
        replacementProfileId: replacementId,
        applyOutcome: () async {
          await registry.applySyncedRegistryDelta(
            SyncedRegistryDelta(
              deletes: <SyncedRegistryDeleteRecord>[
                SyncedRegistryDeleteRecord(
                  record: WebDavSyncRegistryRecordId.profile(firstId),
                  expectedPriorUpdatedAtMs: retiredVersion,
                ),
              ],
            ),
          );
        },
      ),
      isTrue,
    );

    expect(participant.candidateCapture?.profileId, replacementId);
    expect(ProfileRuntime.capture().profileId, replacementId);
    expect((await registry.activeProfile())?.id, replacementId);
    expect(await registry.getProfile(firstId), isNull);
    lifecycle.dispose();
  });

  test(
    'a throwing synced outcome still completes the replacement activation',
    () async {
      final actor = await ProfileAuthorizationContext.capture(registry);
      final replacementId = (await registry.createProfile(
        name: 'Replacement Admin',
        role: UserProfileRole.admin,
        actingProfileId: actor.profileId,
        actingAuthorizationRevision: actor.authorizationRevision,
        actingSessionEpoch: actor.sessionEpoch,
      )).id;
      final lifecycle = ProfileLifecycleCoordinator(registry: registry);

      expect(
        await switchThenApplySyncedProfileOutcome(
          lifecycle: lifecycle,
          replacementProfileId: replacementId,
          applyOutcome: () async => throw StateError('simulated apply failure'),
        ),
        isTrue,
      );

      expect(ProfileRuntime.capture().profileId, replacementId);
      expect((await registry.activeProfile())?.id, replacementId);
      lifecycle.dispose();
    },
  );

  test(
    'legacy active deletion round-trips and executes locally after switch',
    () async {
      final actor = await ProfileAuthorizationContext.capture(registry);
      final replacementId = (await registry.createProfile(
        name: 'Replacement Admin',
        role: UserProfileRole.admin,
        actingProfileId: actor.profileId,
        actingAuthorizationRevision: actor.authorizationRevision,
        actingSessionEpoch: actor.sessionEpoch,
      )).id;
      final legacyJson = <String, Object?>{
        ...const WebDavSyncEngineState().toJson(),
        'pendingActiveProfileDeletion': firstId,
      };
      final migrated = WebDavSyncEngineState.fromJson(legacyJson);
      final roundTripped = WebDavSyncEngineState.fromJson(migrated.toJson());
      final pending = roundTripped.pendingActiveProfile!;
      final lifecycle = ProfileLifecycleCoordinator(registry: registry);

      expect(pending.reason, WebDavSyncPendingActiveProfileReason.deleted);
      expect(pending.isLegacyDeletion, isTrue);
      expect(pending.localProfileId, firstId);
      expect(
        await switchThenApplySyncedProfileOutcome(
          lifecycle: lifecycle,
          replacementProfileId: replacementId,
          applyOutcome: () async {
            expect(
              await applyLegacyWebDavSyncActiveProfileDeletion(
                registry: registry,
                pending: pending,
              ),
              isTrue,
            );
          },
        ),
        isTrue,
      );

      expect(ProfileRuntime.capture().profileId, replacementId);
      expect(await registry.getProfile(firstId), isNull);
      lifecycle.dispose();
    },
  );

  test('synced active disable lands only after replacement switch', () async {
    final actor = await ProfileAuthorizationContext.capture(registry);
    final replacementId = (await registry.createProfile(
      name: 'Replacement Admin',
      role: UserProfileRole.admin,
      actingProfileId: actor.profileId,
      actingAuthorizationRevision: actor.authorizationRevision,
      actingSessionEpoch: actor.sessionEpoch,
    )).id;
    final current = (await registry.readProfileSyncProjection()).singleWhere(
      (entry) => entry.profile.id == firstId,
    );
    final lifecycle = ProfileLifecycleCoordinator(registry: registry);

    expect(
      await switchThenApplySyncedProfileOutcome(
        lifecycle: lifecycle,
        replacementProfileId: replacementId,
        applyOutcome: () async {
          final result = await registry.applySyncedRegistryDelta(
            SyncedRegistryDelta(
              profiles: <SyncedRegistryProfileRecord>[
                SyncedRegistryProfileRecord(
                  id: firstId,
                  name: current.profile.name,
                  avatarKey: current.profile.avatarKey,
                  role: current.profile.role,
                  policy: current.profile.policy,
                  enabled: false,
                  lockOnResume: current.profile.lockOnResume,
                  inactivityTimeoutMinutes:
                      current.profile.inactivityTimeoutMinutes,
                  setupComplete: current.profile.setupComplete,
                  lifecycle: current.profile.lifecycle,
                  pin: current.pin,
                  updatedAtMs: current.updatedAtMs + 1,
                  expectedPriorUpdatedAtMs: current.updatedAtMs,
                ),
              ],
            ),
          );
          expect(result, SyncedRegistryApplyResult.applied);
        },
      ),
      isTrue,
    );

    expect(ProfileRuntime.capture().profileId, replacementId);
    expect((await registry.getProfile(firstId))?.isEnabled, isFalse);
    lifecycle.dispose();
  });
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

class _OrderedParticipant implements ProfileLifecycleParticipant {
  _OrderedParticipant(this.events);

  final List<String> events;

  @override
  Future<void> prepareDeactivate(ProfileScope current) async {
    events.add('prepare:${current.profileId}');
  }

  @override
  Future<void> initializeCandidate(ProfileScope candidate) async {
    events.add('initialize:${candidate.profileId}');
  }

  @override
  Future<void> didActivate(ProfileScope active) async {
    events.add('activate:${active.profileId}');
  }

  @override
  Future<void> rollback(ProfileScope restored) async {}
}

class _RollbackParticipant implements ProfileLifecycleParticipant {
  _RollbackParticipant(this.name, this.events, {this.fail = false});
  final String name;
  final List<String> events;
  final bool fail;
  @override
  Future<void> prepareDeactivate(ProfileScope current) async {}
  @override
  Future<void> initializeCandidate(ProfileScope candidate) async {}
  @override
  Future<void> didActivate(ProfileScope active) async {}
  @override
  Future<void> rollback(ProfileScope restored) async {
    events.add(name);
    if (fail) throw StateError('participant rollback failed');
  }
}
