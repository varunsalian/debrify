import 'package:debrify/services/profiles/portable_profile_package.dart';
import 'package:debrify/services/profiles/profile_authorization.dart';
import 'package:debrify/services/profiles/profile_restore_coordinator.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_adoption.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_adoption_models.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_engine_state.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_safety_backup.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late _MemoryStateRepository states;
  late List<String> events;
  late _FakeSafetyBackups backups;
  late _FakeAdoptionOperations operations;
  late WebDavSyncCircleAdoption adoption;

  setUp(() {
    states = _MemoryStateRepository();
    events = <String>[];
    backups = _FakeSafetyBackups(events);
    operations = _FakeAdoptionOperations(events, states);
    adoption = WebDavSyncCircleAdoption(
      stateRepository: states,
      safetyBackups: backups,
      operations: operations,
      adoptionIdFactory: () => 'adoption-1',
    );
  });

  test(
    'first join backs up, journals, restores, hands off, then prunes',
    () async {
      final result = await adoption.adopt(
        _request(mode: WebDavSyncAdoptionMode.firstJoin),
      );

      expect(result.phase, WebDavSyncAdoptionPhase.complete);
      expect(events, <String>[
        'list',
        'backup',
        'gate:hold',
        'restore:restoring',
        'select-admin',
        'active',
        'handoff:start:new-admin',
        'gate:release',
        'handoff:end:new-admin',
        'prune:old-admin',
        'prune:old-kid',
      ]);
      expect(states.state.adoption, isNull);
      expect(states.state.circleToLocalProfiles, <String, String>{
        'circle-admin': 'new-admin',
        'circle-kid': 'new-kid',
      });
      expect(states.state.circleToLocalResources, <String, String>{
        'circle-resource': 'new-resource',
      });
    },
  );

  test(
    'restart during first join retains onboarding completion intent',
    () async {
      operations.handoffFailure = StateError('process stopped before handoff');

      await expectLater(
        adoption.adopt(
          _request(
            mode: WebDavSyncAdoptionMode.firstJoin,
            completeOnboarding: true,
          ),
        ),
        throwsStateError,
      );

      final persisted = states.state.adoption;
      expect(persisted?.phase, WebDavSyncAdoptionPhase.handingOff);
      expect(persisted?.completeOnboarding, isTrue);
      expect(
        WebDavSyncAdoptionRecord.fromJson(
          persisted!.toJson(),
        ).completeOnboarding,
        isTrue,
      );

      operations.handoffFailure = null;
      final resumed = await adoption.recover('circle:one');

      expect(resumed?.phase, WebDavSyncAdoptionPhase.complete);
      expect(operations.handoffCompleteOnboarding, isTrue);
      expect(states.state.adoption, isNull);
    },
  );

  test(
    'refresh copies inactive pair and drains active pair in handoff',
    () async {
      states.state = const WebDavSyncEngineState(
        circleToLocalProfiles: <String, String>{
          'circle-admin': 'old-admin',
          'circle-kid': 'old-kid',
        },
        circleToLocalResources: <String, String>{
          'circle-resource': 'old-resource',
        },
      );

      await adoption.adopt(_request(mode: WebDavSyncAdoptionMode.refresh));

      final inactiveCopy = events.indexOf('copy:old-kid:new-kid');
      final handoffStart = events.indexOf('handoff:start:new-admin');
      final activeCopy = events.indexOf('copy:old-admin:new-admin');
      final handoffEnd = events.indexOf('handoff:end:new-admin');
      expect(inactiveCopy, lessThan(handoffStart));
      expect(activeCopy, greaterThan(handoffStart));
      expect(activeCopy, lessThan(handoffEnd));
      expect(
        events,
        containsAll(<String>[
          'remap:new-kid:old-resource=new-resource',
          'carry:old-kid:new-kid:old-resource=new-resource',
          'remap:new-admin:old-resource=new-resource',
          'carry:old-admin:new-admin:old-resource=new-resource',
          'prune:old-admin',
          'prune:old-kid',
        ]),
      );
    },
  );

  test(
    'refused prune quarantines the old profile and blocks graph only',
    () async {
      states.state = const WebDavSyncEngineState(
        circleToLocalProfiles: <String, String>{
          'circle-admin': 'old-admin',
          'circle-kid': 'old-kid',
        },
        circleToLocalResources: <String, String>{
          'circle-resource': 'old-resource',
        },
      );
      operations.pruneFailures.add('old-kid');

      await adoption.adopt(_request(mode: WebDavSyncAdoptionMode.refresh));

      expect(events, contains('quarantine:old-kid'));
      expect(states.state.adoption, isNull);
      expect(states.state.prunePendingProfileIds, <String>{'old-kid'});
      expect(states.state.blocksAllPushes, isFalse);
      expect(states.state.blocksSeedPushes, isTrue);
    },
  );

  test(
    'lost safety backup quarantines predecessors instead of pruning',
    () async {
      backups.retained = false;

      final result = await adoption.adopt(
        _request(mode: WebDavSyncAdoptionMode.firstJoin),
      );

      expect(result.phase, WebDavSyncAdoptionPhase.complete);
      expect(events, isNot(contains('prune:old-admin')));
      expect(events, isNot(contains('prune:old-kid')));
      expect(
        events,
        containsAll(<String>['quarantine:old-admin', 'quarantine:old-kid']),
      );
      expect(states.state.prunePendingProfileIds, <String>{
        'old-admin',
        'old-kid',
      });
      expect(states.state.safetyProtectedProfileIds, <String>{
        'old-admin',
        'old-kid',
      });
      expect(states.state.blocksSeedPushes, isTrue);
    },
  );

  test('restoring crash rolls back every post-snapshot profile', () async {
    states.state = WebDavSyncEngineState(
      adoption: WebDavSyncAdoptionRecord(
        adoptionId: 'adoption-1',
        mode: WebDavSyncAdoptionMode.firstJoin,
        phase: WebDavSyncAdoptionPhase.restoring,
        graphSemanticDigest: 'a' * 64,
        preRestoreProfileIds: const <String>{'old-admin', 'old-kid'},
        backupPath: '/backup.json',
        backupSha256: 'b' * 64,
        backupVerified: true,
      ),
    );
    operations.profileIds.add('orphan-import');

    final result = await adoption.recover('circle:one');

    expect(result, isNull);
    expect(events, <String>[
      'gate:hold',
      'rollback:orphan-import',
      'gate:release',
    ]);
    expect(states.state.adoption, isNull);
  });

  test(
    'interactive restore failure rolls back and releases its gate',
    () async {
      operations.restoreFailure = StateError('restore failed');

      await expectLater(
        adoption.adopt(_request(mode: WebDavSyncAdoptionMode.firstJoin)),
        throwsStateError,
      );

      expect(events, <String>[
        'list',
        'backup',
        'gate:hold',
        'restore:restoring',
        'rollback:orphan-import',
        'gate:release',
      ]);
      expect(states.state.adoption, isNull);
    },
  );

  test(
    'pre-handoff failure rolls back imports and releases the database gate',
    () async {
      states.state = const WebDavSyncEngineState(
        circleToLocalProfiles: <String, String>{
          'circle-admin': 'old-admin',
          'circle-kid': 'old-kid',
        },
        circleToLocalResources: <String, String>{
          'circle-resource': 'old-resource',
        },
      );
      operations.copyFailureProfileId = 'old-kid';

      await expectLater(
        adoption.adopt(_request(mode: WebDavSyncAdoptionMode.refresh)),
        throwsStateError,
      );

      expect(operations.gateHeld, isFalse);
      expect(events.last, 'gate:release');
      expect(
        events,
        containsAll(<String>[
          'rollback-import:new-admin',
          'rollback-import:new-kid',
        ]),
      );
      expect(operations.profileIds, <String>{'old-admin', 'old-kid'});
      expect(states.state.adoption, isNull);
    },
  );

  test(
    'startup rolls back a prepared adoption that never reached handoff',
    () async {
      states.state = WebDavSyncEngineState(
        circleToLocalProfiles: const <String, String>{
          'circle-admin': 'old-admin',
          'circle-kid': 'old-kid',
        },
        circleToLocalResources: const <String, String>{
          'circle-resource': 'old-resource',
        },
        adoption: WebDavSyncAdoptionRecord(
          adoptionId: 'adoption-1',
          mode: WebDavSyncAdoptionMode.refresh,
          phase: WebDavSyncAdoptionPhase.carryingLocalState,
          graphSemanticDigest: 'a' * 64,
          preRestoreProfileIds: const <String>{'old-admin', 'old-kid'},
          backupPath: '/backup.json',
          backupSha256: 'b' * 64,
          backupVerified: true,
          circleProfileToNewLocal: const <String, String>{
            'circle-admin': 'new-admin',
            'circle-kid': 'new-kid',
          },
          circleResourceToNewLocal: const <String, String>{
            'circle-resource': 'new-resource',
          },
          oldToNewProfiles: const <String, String>{
            'old-admin': 'new-admin',
            'old-kid': 'new-kid',
          },
          oldToNewResources: const <String, String>{
            'old-resource': 'new-resource',
          },
          targetAdminProfileId: 'new-admin',
        ),
      );
      operations.profileIds.addAll(<String>{'new-admin', 'new-kid'});

      final result = await adoption.recover('circle:one');

      expect(result, isNull);
      expect(operations.profileIds, <String>{'old-admin', 'old-kid'});
      expect(states.state.adoption, isNull);
      expect(events, <String>[
        'gate:hold',
        'active',
        'list',
        'rollback-import:new-admin',
        'rollback-import:new-kid',
        'gate:release',
      ]);
    },
  );

  test(
    'deferred active database failure aborts before profile publication',
    () async {
      states.state = const WebDavSyncEngineState(
        circleToLocalProfiles: <String, String>{
          'circle-admin': 'old-admin',
          'circle-kid': 'old-kid',
        },
        circleToLocalResources: <String, String>{
          'circle-resource': 'old-resource',
        },
      );
      operations.copyFailureProfileId = 'old-admin';

      await expectLater(
        adoption.adopt(_request(mode: WebDavSyncAdoptionMode.refresh)),
        throwsStateError,
      );

      expect(operations.active, 'old-admin');
      expect(operations.gateHeld, isFalse);
      expect(events, contains('handoff:start:new-admin'));
      expect(events.last, 'gate:release');
      expect(states.state.adoption, isNotNull);
    },
  );

  test('first connection cannot bypass replacement consent', () async {
    await expectLater(
      adoption.adopt(
        WebDavSyncAdoptionRequest(
          namespaceId: 'circle:one',
          mode: WebDavSyncAdoptionMode.firstJoin,
          package: _package(),
          graphSemanticDigest: 'a' * 64,
          profileMap: const <String, String>{
            'profile-0': 'circle-admin',
            'profile-1': 'circle-kid',
          },
          resourceMap: const <String, String>{'resource-0': 'circle-resource'},
          passphrase: 'circle-secret',
          authorization: _authorization,
          replacementConfirmed: false,
        ),
      ),
      throwsStateError,
    );
    expect(events, isEmpty);
    expect(states.state.adoption, isNull);
  });

  test(
    'restored profile IDs follow package order, not local ID order',
    () async {
      operations
        ..importedProfileIds = <String>['restored-kid', 'restored-admin']
        ..targetAdmin = 'restored-admin';
      final package = PortableProfilePackage(
        mode: 'deviceGraph',
        createdAt: DateTime.utc(2026, 1, 1),
        profiles: const <Map<String, dynamic>>[
          <String, dynamic>{'backupId': 'profile-kid', 'name': 'Kid'},
          <String, dynamic>{'backupId': 'profile-admin', 'name': 'Admin'},
        ],
        resources: const <Map<String, dynamic>>[
          <String, dynamic>{'backupId': 'resource-0'},
        ],
        sections: const <String, dynamic>{},
      );

      await adoption.adopt(
        WebDavSyncAdoptionRequest(
          namespaceId: 'circle:one',
          mode: WebDavSyncAdoptionMode.firstJoin,
          package: package,
          graphSemanticDigest: 'a' * 64,
          profileMap: const <String, String>{
            'profile-kid': 'circle-kid',
            'profile-admin': 'circle-admin',
          },
          resourceMap: const <String, String>{'resource-0': 'circle-resource'},
          passphrase: 'circle-secret',
          authorization: _authorization,
          replacementConfirmed: true,
        ),
      );

      expect(states.state.circleToLocalProfiles, <String, String>{
        'circle-kid': 'restored-kid',
        'circle-admin': 'restored-admin',
      });
    },
  );

  test(
    'the next Admin cycle retries and clears pending profile prune',
    () async {
      states.state = const WebDavSyncEngineState(
        prunePendingProfileIds: <String>{'old-kid'},
      );
      operations.pruneFailures.add('old-kid');

      expect(await adoption.retryPendingPrunes('circle:one'), const <String>{
        'old-kid',
      });
      expect(events, <String>['list', 'prune:old-kid', 'quarantine:old-kid']);

      operations.pruneFailures.clear();
      expect(await adoption.retryPendingPrunes('circle:one'), isEmpty);
      expect(states.state.prunePendingProfileIds, isEmpty);
      expect(events.last, 'prune:old-kid');
    },
  );
}

WebDavSyncAdoptionRequest _request({
  required WebDavSyncAdoptionMode mode,
  bool completeOnboarding = false,
}) => WebDavSyncAdoptionRequest(
  namespaceId: 'circle:one',
  mode: mode,
  package: _package(),
  graphSemanticDigest: 'a' * 64,
  profileMap: const <String, String>{
    'profile-0': 'circle-admin',
    'profile-1': 'circle-kid',
  },
  resourceMap: const <String, String>{'resource-0': 'circle-resource'},
  passphrase: 'circle-secret',
  authorization: _authorization,
  replacementConfirmed: true,
  completeOnboarding: completeOnboarding,
);

PortableProfilePackage _package() => PortableProfilePackage(
  mode: 'deviceGraph',
  createdAt: DateTime.utc(2026, 1, 1),
  profiles: const <Map<String, dynamic>>[
    <String, dynamic>{'backupId': 'profile-0', 'name': 'Admin'},
    <String, dynamic>{'backupId': 'profile-1', 'name': 'Kid'},
  ],
  resources: const <Map<String, dynamic>>[
    <String, dynamic>{'backupId': 'resource-0'},
  ],
  sections: const <String, dynamic>{},
);

const _authorization = _TestAuthorization();

final class _TestAuthorization implements ProfileAuthorizationContext {
  const _TestAuthorization();

  @override
  int get authorizationRevision => 1;

  @override
  String get profileId => 'old-admin';

  @override
  int get sessionEpoch => 1;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _MemoryStateRepository implements WebDavSyncEngineStateRepository {
  WebDavSyncEngineState state = const WebDavSyncEngineState();

  @override
  Future<WebDavSyncEngineState> load(String namespaceId) async => state;

  @override
  Future<WebDavSyncEngineState> update(
    String namespaceId,
    WebDavSyncEngineState Function(WebDavSyncEngineState current) update,
  ) async => state = update(state);
}

final class _FakeSafetyBackups implements WebDavSyncSafetyBackupStore {
  _FakeSafetyBackups(this.events);

  final List<String> events;
  bool retained = true;

  @override
  Future<WebDavSyncSafetyBackup> createVerified({
    required String adoptionId,
    required String passphrase,
    required ProfileAuthorizationContext authorization,
  }) async {
    events.add('backup');
    return WebDavSyncSafetyBackup(
      path: '/backups/$adoptionId.json',
      sha256Hex: 'b' * 64,
    );
  }

  @override
  Future<bool> verifyRetained(WebDavSyncSafetyBackup backup) async => retained;
}

final class _FakeAdoptionOperations implements WebDavSyncAdoptionOperations {
  _FakeAdoptionOperations(this.events, this.states);

  final List<String> events;
  final _MemoryStateRepository states;
  final Set<String> profileIds = <String>{'old-admin', 'old-kid'};
  final Set<String> pruneFailures = <String>{};
  Object? restoreFailure;
  String? copyFailureProfileId;
  bool gateHeld = false;
  String active = 'old-admin';
  List<String> importedProfileIds = <String>['new-admin', 'new-kid'];
  String targetAdmin = 'new-admin';
  Object? handoffFailure;
  bool? handoffCompleteOnboarding;

  @override
  Future<Set<String>> listProfileIds() async {
    events.add('list');
    return Set<String>.from(profileIds);
  }

  @override
  Future<String> activeProfileId() async {
    events.add('active');
    return active;
  }

  @override
  Future<ProfileGraphRestoreReport> restoreGraph({
    required PortableProfilePackage package,
    required ProfileAuthorizationContext authorization,
  }) async {
    events.add('restore:${states.state.adoption?.phase.name}');
    if (restoreFailure != null) {
      profileIds.add('orphan-import');
      throw restoreFailure!;
    }
    profileIds.addAll(importedProfileIds);
    return ProfileGraphRestoreReport(
      profilesImported: importedProfileIds.length,
      resourcesImported: 1,
      grantsImported: 1,
      bindingsImported: 0,
      pinResetsRequired: 0,
      importedProfileIds: List<String>.unmodifiable(importedProfileIds),
      importedResourceIdsByBackupId: const <String, String>{
        'resource-0': 'new-resource',
      },
    );
  }

  @override
  Future<String> selectTargetAdmin(Set<String> importedProfileIds) async {
    events.add('select-admin');
    return targetAdmin;
  }

  @override
  Future<void> copyDatabases({
    required String oldProfileId,
    required String newProfileId,
  }) async {
    events.add('copy:$oldProfileId:$newProfileId');
    if (copyFailureProfileId == oldProfileId) {
      throw StateError('copy failed');
    }
  }

  @override
  Future<void> remapDatabases({
    required String newProfileId,
    required Map<String, String> oldToNewResources,
  }) async => events.add('remap:$newProfileId:${_mapText(oldToNewResources)}');

  @override
  Future<void> carryLocalState({
    required String oldProfileId,
    required String newProfileId,
    required Map<String, String> oldToNewResources,
    required Set<String> unmappedOldResourceIds,
  }) async => events.add(
    'carry:$oldProfileId:$newProfileId:${_mapText(oldToNewResources)}',
  );

  @override
  Future<void> preflightLocalStateCarry({
    required Map<String, String> oldToNewProfiles,
    required Map<String, String> oldToNewResources,
    required Set<String> unmappedOldResourceIds,
  }) async {}

  @override
  Future<bool> handoff({
    required String targetProfileId,
    required bool completeOnboarding,
    required Future<void> Function() beforeCommit,
    required Future<void> Function() beforeTargetInitialize,
  }) async {
    events.add('handoff:start:$targetProfileId');
    handoffCompleteOnboarding = completeOnboarding;
    if (handoffFailure case final error?) throw error;
    await beforeCommit();
    active = targetProfileId;
    await beforeTargetInitialize();
    events.add('handoff:end:$targetProfileId');
    return true;
  }

  @override
  Future<void> pruneProfile(String profileId) async {
    events.add('prune:$profileId');
    if (pruneFailures.contains(profileId)) {
      throw StateError('prune refused');
    }
    profileIds.remove(profileId);
  }

  @override
  Future<void> quarantineProfile(String profileId) async {
    events.add('quarantine:$profileId');
  }

  @override
  Future<void> rollbackProfilesNotIn(Set<String> retainedProfileIds) async {
    for (final id
        in profileIds.difference(retainedProfileIds).toList()..sort()) {
      events.add('rollback:$id');
      profileIds.remove(id);
    }
  }

  @override
  Future<void> rollbackImportedProfiles(Set<String> importedProfileIds) async {
    for (final id in importedProfileIds.toList()..sort()) {
      events.add('rollback-import:$id');
      profileIds.remove(id);
    }
  }

  @override
  Future<void> holdDatabaseGate() async {
    gateHeld = true;
    events.add('gate:hold');
  }

  @override
  Future<void> releaseDatabaseGate() async {
    gateHeld = false;
    events.add('gate:release');
  }

  static String _mapText(Map<String, String> value) =>
      (value.entries.toList()..sort((a, b) => a.key.compareTo(b.key)))
          .map((entry) => '${entry.key}=${entry.value}')
          .join(',');
}
