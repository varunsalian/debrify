import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/services/profiles/device_key_provider.dart';
import 'package:debrify/services/profiles/profile_authorization.dart';
import 'package:debrify/services/profiles/profile_bootstrap.dart';
import 'package:debrify/services/profiles/profile_data_generation.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/services/profiles/profile_lifecycle.dart';
import 'package:debrify/services/profiles/profile_preference_budget.dart';
import 'package:debrify/services/profiles/profile_registry.dart';
import 'package:debrify/services/profiles/profile_restore_coordinator.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_adoption_operations.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_models.dart';
import 'package:debrify/utils/app_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory temporaryDirectory;
  late Directory documents;
  late Directory support;
  late Directory cache;
  late ProfileRegistry registry;
  late String oldId;
  late String newId;
  late ProfileLifecycleCoordinator lifecycle;
  late DefaultWebDavSyncAdoptionOperations operations;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    ProfileRuntime.debugReset();
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'webdav-sync-adoption-ops-',
    );
    documents = Directory(p.join(temporaryDirectory.path, 'documents'));
    support = Directory(p.join(temporaryDirectory.path, 'support'));
    cache = Directory(p.join(temporaryDirectory.path, 'cache'));
    await Future.wait(<Future<Directory>>[
      documents.create(recursive: true),
      support.create(recursive: true),
      cache.create(recursive: true),
    ]);
    AppStorage.debugOverride(
      documents: documents,
      support: support,
      cache: cache,
    );
    registry = await ProfileRegistry.open(
      path: p.join(support.path, 'profiles.db'),
    );
    oldId = (await registry.createProfile(
      name: 'Old Admin',
      role: UserProfileRole.admin,
    )).id;
    newId = (await registry.createProfile(
      name: 'New Admin',
      role: UserProfileRole.admin,
    )).id;
    await registry.commitBootstrap(
      activeProfileId: oldId,
      migratedLegacyInstall: false,
    );
    ProfileRuntime.initializeCommitted(
      ProfileScope(profileId: oldId, dataGeneration: 1, sessionEpoch: 1),
    );
    lifecycle = ProfileLifecycleCoordinator(registry: registry);
    operations = DefaultWebDavSyncAdoptionOperations(
      registry: registry,
      restoreCoordinator: ProfileRestoreCoordinator(
        registry: registry,
        cipher: MemoryDeviceSecretCipher(List<int>.filled(32, 5)),
      ),
      lifecycleCoordinator: lifecycle,
    );
  });

  tearDown(() async {
    ProfilePreferenceBudget.debugReset();
    lifecycle.dispose();
    ProfileRuntime.debugReset();
    AppStorage.debugReset();
    await registry.close();
    await temporaryDirectory.delete(recursive: true);
  });

  test(
    'same-ID Settings handoff refreshes a stale generation before checkpoint',
    () async {
      ProfileBootstrap.debugInstallRegistry(registry);
      addTearDown(() => ProfileBootstrap.debugInstallRegistry(null));
      final original = ProfileRuntime.capture();
      final generationManager = ProfileDataGenerationManager(registry);
      final staged = await generationManager.finalize(
        await generationManager.stage(
          operationId: 'same-id-handoff',
          profileId: oldId,
          preferenceOverlay: const {},
          copyDurableAreas: false,
        ),
      );
      await registry.publishDataGeneration(
        profileId: oldId,
        baseGeneration: staged.baseGeneration,
        stagedGeneration: staged.generation,
        operationId: staged.operationId,
      );
      // Pin the actual generation check, without claiming validate checks it.
      await expectLater(
        StorageService.isInitialSetupComplete(),
        throwsStateError,
      );
      await (await ProfileAuthorizationContext.capture(
        registry,
      )).validate(registry);
      final retiredAuthorization = await ProfileAuthorizationContext.capture(
        registry,
      );
      var publications = 0;
      void published() => publications++;
      ProfileRuntime.scope.addListener(published);
      addTearDown(() => ProfileRuntime.scope.removeListener(published));
      var sawCommittedCheckpoint = false;
      registry.authorityChangedCallback = () async {
        if (await registry.activationInProgress()) return;
        sawCommittedCheckpoint = true;
        expect(ProfileRuntime.capture().dataGeneration, staged.generation);
        expect(
          ProfileRuntime.capture().sessionEpoch,
          greaterThan(original.sessionEpoch),
        );
      };
      expect(
        await operations.handoff(
          targetProfileId: oldId,
          completeOnboarding: false,
          beforeCommit: () async {},
          beforeTargetInitialize: () async {
            await (await ProfileAuthorizationContext.capture(
              registry,
            )).validate(registry);
            expect(await StorageService.isInitialSetupComplete(), isFalse);
          },
        ),
        isTrue,
      );
      expect(sawCommittedCheckpoint, isTrue);
      expect(publications, 1);
      await expectLater(
        retiredAuthorization.validate(registry),
        throwsStateError,
      );
    },
  );

  test(
    'same-ID onboarding completion is durable before initialization',
    () async {
      expect(
        await operations.handoff(
          targetProfileId: oldId,
          completeOnboarding: true,
          beforeCommit: () async {},
          beforeTargetInitialize: () async {
            expect((await registry.getProfile(oldId))!.setupComplete, isTrue);
            expect(ProfileRuntime.capture().sessionEpoch, greaterThan(1));
          },
        ),
        isTrue,
      );
    },
  );

  test('resumed same-ID drain failure remains post-handoff', () async {
    await expectLater(
      operations.handoff(
        targetProfileId: oldId,
        completeOnboarding: false,
        beforeCommit: () async => throw StateError('drain failed'),
        beforeTargetInitialize: () async {},
      ),
      throwsA(isA<WebDavSyncPostHandoffException>()),
    );
    expect(ProfileRuntime.capture().profileId, oldId);
  });

  test(
    'Settings handoff selects imported Admin from a graph containing a member',
    () async {
      final actor = await ProfileAuthorizationContext.capture(registry);
      final member = await registry.createProfile(
        name: 'Imported Member',
        role: UserProfileRole.member,
        actingProfileId: actor.profileId,
        actingAuthorizationRevision: actor.authorizationRevision,
        actingSessionEpoch: actor.sessionEpoch,
      );
      await lifecycle.switchTo(member.id);
      final target = await operations.selectTargetAdmin({member.id, newId});
      expect(target, newId);
      expect(
        await operations.handoff(
          targetProfileId: target,
          completeOnboarding: false,
          beforeCommit: () async {},
          beforeTargetInitialize: () async {
            expect(await registry.getActiveProfileId(), newId);
            expect(ProfileRuntime.capture().profileId, newId);
          },
        ),
        isTrue,
      );
      expect(await registry.getActiveProfileId(), newId);
      expect((await registry.getProfile(newId))!.setupComplete, isFalse);
    },
  );

  test('tvOS refresh refuses an unsafe whole-graph preference carry', () async {
    final prefs = await SharedPreferences.getInstance();
    final oldScope = ProfileScope(
      profileId: oldId,
      dataGeneration: 1,
      sessionEpoch: 0,
    );
    final newScope = ProfileScope(
      profileId: newId,
      dataGeneration: 1,
      sessionEpoch: 0,
    );
    await prefs.setString(
      'unscoped_filler',
      'x' * (ProfilePreferenceBudget.emergencyLimitBytes - 30 * 1024),
    );
    await prefs.setString(oldScope.preferenceKey('large'), 'y' * (20 * 1024));
    ProfilePreferenceBudget.debugEnforcedOverride = true;

    await expectLater(
      operations.preflightLocalStateCarry(
        oldToNewProfiles: <String, String>{oldId: newId},
        oldToNewResources: const <String, String>{},
        unmappedOldResourceIds: const <String>{},
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('Apple TV preference storage'),
        ),
      ),
    );
    expect(prefs.containsKey(newScope.preferenceKey('large')), isFalse);
  });

  test(
    'carry preserves staged values, remaps refs, and excludes DB/temp',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final oldScope = ProfileScope(
        profileId: oldId,
        dataGeneration: 1,
        sessionEpoch: 0,
      );
      final newScope = ProfileScope(
        profileId: newId,
        dataGeneration: 1,
        sessionEpoch: 0,
      );
      await prefs.setString(oldScope.preferenceKey('theme'), 'source');
      await prefs.setString(oldScope.preferenceKey('device_path'), '/local');
      await prefs.setString(
        oldScope.preferenceKey('webdav_servers_v1'),
        jsonEncode(<String, Object?>{
          'selected': 'old-resource',
          'items': <String>['old-resource', 'removed-resource'],
        }),
      );
      await prefs.setString(
        oldScope.preferenceKey('selected_resource'),
        'old-resource',
      );
      await prefs.setString(
        oldScope.preferenceKey('resource_layout_v1'),
        jsonEncode(<String, Object?>{
          'primary': 'old-resource',
          'items': <String>['old-resource', 'removed-resource'],
        }),
      );
      await prefs.setString(newScope.preferenceKey('theme'), 'staged');

      final sourceRoot = oldScope.generationDirectory(documents);
      final targetRoot = newScope.generationDirectory(documents);
      await File(
        p.join(sourceRoot.path, 'engines', 'carry.json'),
      ).create(recursive: true).then((file) => file.writeAsString('source'));
      await File(
        p.join(sourceRoot.path, 'engines', 'staged.json'),
      ).create(recursive: true).then((file) => file.writeAsString('source'));
      await File(
        p.join(targetRoot.path, 'engines', 'staged.json'),
      ).create(recursive: true).then((file) => file.writeAsString('target'));
      await File(
        p.join(sourceRoot.path, 'documents', 'ignored.db'),
      ).create(recursive: true).then((file) => file.writeAsString('database'));
      await File(
        p.join(sourceRoot.path, 'documents', 'ignored.tmp'),
      ).create(recursive: true).then((file) => file.writeAsString('temporary'));

      await operations.carryLocalState(
        oldProfileId: oldId,
        newProfileId: newId,
        oldToNewResources: const <String, String>{
          'old-resource': 'new-resource',
        },
        unmappedOldResourceIds: const <String>{'removed-resource'},
      );

      expect(prefs.getString(newScope.preferenceKey('theme')), 'staged');
      expect(prefs.getString(newScope.preferenceKey('device_path')), '/local');
      expect(
        jsonDecode(
          prefs.getString(newScope.preferenceKey('webdav_servers_v1'))!,
        ),
        <String, Object?>{
          'selected': 'new-resource',
          'items': <String>['new-resource'],
        },
      );
      expect(
        prefs.getString(newScope.preferenceKey('selected_resource')),
        'new-resource',
      );
      expect(
        jsonDecode(
          prefs.getString(newScope.preferenceKey('resource_layout_v1'))!,
        ),
        <String, Object?>{
          'primary': 'new-resource',
          'items': <String>['new-resource'],
        },
      );
      expect(
        await File(
          p.join(targetRoot.path, 'engines', 'carry.json'),
        ).readAsString(),
        'source',
      );
      expect(
        await File(
          p.join(targetRoot.path, 'engines', 'staged.json'),
        ).readAsString(),
        'target',
      );
      expect(
        await File(p.join(targetRoot.path, 'documents', 'ignored.db')).exists(),
        isFalse,
      );
      expect(
        await File(
          p.join(targetRoot.path, 'documents', 'ignored.tmp'),
        ).exists(),
        isFalse,
      );
    },
  );

  test(
    'database copy uses a validated temp replacement and remaps rows',
    () async {
      final oldScope = ProfileScope(
        profileId: oldId,
        dataGeneration: 1,
        sessionEpoch: 0,
      );
      final newScope = ProfileScope(
        profileId: newId,
        dataGeneration: 1,
        sessionEpoch: 0,
      );
      final source = oldScope.fileIn(documents, 'documents', 'debrify_tv.db');
      await source.parent.create(recursive: true);
      final sourceDb = await openDatabase(source.path, singleInstance: false);
      await sourceDb.execute(
        'CREATE TABLE iptv_list_channels (playlist_id TEXT NOT NULL)',
      );
      await sourceDb.insert('iptv_list_channels', <String, Object?>{
        'playlist_id': 'old-resource',
      });
      await sourceDb.close();

      await operations.copyDatabases(oldProfileId: oldId, newProfileId: newId);
      await operations.remapDatabases(
        newProfileId: newId,
        oldToNewResources: const <String, String>{
          'old-resource': 'new-resource',
        },
      );

      final destination = newScope.fileIn(
        documents,
        'documents',
        'debrify_tv.db',
      );
      final copied = await openDatabase(
        destination.path,
        singleInstance: false,
      );
      final rows = await copied.query('iptv_list_channels');
      await copied.close();
      expect(rows.single['playlist_id'], 'new-resource');
      expect(
        await File('${destination.path}.webdav-adoption.tmp').exists(),
        isFalse,
      );
    },
  );

  test('prune uses the authorized deletion path and cleanup ledger', () async {
    final oldScope = ProfileScope(
      profileId: oldId,
      dataGeneration: 1,
      sessionEpoch: 0,
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(oldScope.preferenceKey('private'), 'value');
    final privateFile = oldScope.fileIn(documents, 'documents', 'private.json');
    await privateFile.create(recursive: true);
    await privateFile.writeAsString('private');
    expect(await lifecycle.switchTo(newId), isTrue);

    await operations.pruneProfile(oldId);

    expect(await registry.getProfile(oldId), isNull);
    expect(prefs.getString(oldScope.preferenceKey('private')), isNull);
    expect(await privateFile.exists(), isFalse);
  });

  test('prepared rollback removes only the journal-listed import', () async {
    final unrelated = await registry.createProfile(
      name: 'Unrelated',
      role: UserProfileRole.member,
      actingProfileId: oldId,
      actingAuthorizationRevision: 1,
      actingSessionEpoch: 1,
    );

    await operations.rollbackImportedProfiles(<String>{newId});

    expect(await registry.getProfile(oldId), isNotNull);
    expect(await registry.getProfile(newId), isNull);
    expect(await registry.getProfile(unrelated.id), isNotNull);
  });

  test(
    'handoff atomically completes an imported Admin before the await returns',
    () async {
      expect((await registry.getProfile(newId))?.setupComplete, isFalse);
      lifecycle.dispose();
      final participant = _BlockingActivationParticipant();
      lifecycle = ProfileLifecycleCoordinator(
        registry: registry,
        participants: <ProfileLifecycleParticipant>[participant],
      );
      operations = DefaultWebDavSyncAdoptionOperations(
        registry: registry,
        restoreCoordinator: ProfileRestoreCoordinator(
          registry: registry,
          cipher: MemoryDeviceSecretCipher(List<int>.filled(32, 5)),
        ),
        lifecycleCoordinator: lifecycle,
      );
      var returned = false;

      final handoff = operations
          .handoff(
            targetProfileId: newId,
            completeOnboarding: true,
            beforeCommit: () async {},
            beforeTargetInitialize: () async {},
          )
          .whenComplete(() => returned = true);
      await participant.initializeStarted.future;

      expect(returned, isFalse, reason: 'the handoff await is still pending');
      expect((await registry.activeProfile())?.id, newId);
      expect(
        (await registry.getProfile(newId))?.setupComplete,
        isTrue,
        reason:
            'activation and setup completion must be visible in one registry publication',
      );

      participant.release.complete();
      expect(await handoff, isTrue);
    },
  );

  test('handoff wraps failures only after profile authority commits', () async {
    await expectLater(
      operations.handoff(
        targetProfileId: newId,
        completeOnboarding: false,
        beforeCommit: () async => throw StateError('before commit'),
        beforeTargetInitialize: () async {},
      ),
      throwsA(isA<StateError>()),
    );
    expect((await registry.activeProfile())?.id, oldId);

    await expectLater(
      operations.handoff(
        targetProfileId: newId,
        completeOnboarding: true,
        beforeCommit: () async {},
        beforeTargetInitialize: () async => throw StateError('after commit'),
      ),
      throwsA(
        isA<WebDavSyncPostHandoffException>().having(
          (error) => error.error,
          'original error',
          isA<StateError>(),
        ),
      ),
    );
    expect((await registry.activeProfile())?.id, newId);
    expect((await registry.getProfile(newId))?.setupComplete, isTrue);
  });

  test('checkpoint failure after activation commit is post-handoff', () async {
    registry.authorityChangedCallback = () async {
      if ((await registry.activeProfile())?.id == newId) {
        throw StateError('checkpoint failed after authority commit');
      }
    };

    await expectLater(
      operations.handoff(
        targetProfileId: newId,
        completeOnboarding: false,
        beforeCommit: () async {},
        beforeTargetInitialize: () async {},
      ),
      throwsA(
        isA<WebDavSyncPostHandoffException>().having(
          (error) => error.error,
          'original error',
          isA<StateError>(),
        ),
      ),
    );

    expect((await registry.activeProfile())?.id, newId);
    expect(ProfileRuntime.capture().profileId, newId);
  });

  test('activation transaction failure remains pre-handoff', () async {
    await expectLater(
      operations.handoff(
        targetProfileId: newId,
        completeOnboarding: false,
        beforeCommit: () => registry.abortActivation(),
        beforeTargetInitialize: () async {},
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'No activation is being prepared',
        ),
      ),
    );

    expect((await registry.activeProfile())?.id, oldId);
    expect(ProfileRuntime.capture().profileId, oldId);
  });
}

final class _BlockingActivationParticipant
    implements ProfileLifecycleParticipant {
  final Completer<void> initializeStarted = Completer<void>();
  final Completer<void> release = Completer<void>();

  @override
  Future<void> prepareDeactivate(ProfileScope current) async {}

  @override
  Future<void> initializeCandidate(ProfileScope candidate) async {
    initializeStarted.complete();
    await release.future;
  }

  @override
  Future<void> didActivate(ProfileScope active) async {}

  @override
  Future<void> rollback(ProfileScope restored) async {}
}
