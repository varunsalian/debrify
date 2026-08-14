import 'dart:convert';
import 'dart:io';

import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/models/profiles/user_profile.dart';
import 'package:debrify/services/engine/local_engine_storage.dart';
import 'package:debrify/services/profiles/profile_authorization.dart';
import 'package:debrify/services/profiles/profile_engine_assignment_service.dart';
import 'package:debrify/services/profiles/profile_lock_controller.dart';
import 'package:debrify/services/profiles/profile_registry.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
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
  late UserProfile admin;
  late UserProfile member;
  late ProfileAuthorizationContext authorization;
  late ProfileEngineAssignmentService service;

  Future<void> saveActiveEngine({
    required String id,
    required String name,
    required String yaml,
  }) async {
    await LocalEngineStorage.instance.saveEngine(
      engineId: id,
      fileName: '$id.yaml',
      yamlContent: yaml,
      displayName: name,
    );
  }

  ProfileScope scope(UserProfile profile, {int sessionEpoch = 0}) =>
      ProfileScope(
        profileId: profile.id,
        dataGeneration: profile.visibleDataGeneration,
        sessionEpoch: sessionEpoch,
      );

  Directory engineDirectory(ProfileScope scope) => Directory(
    p.join(scope.storageDirectory(documents, 'documents').path, 'engines'),
  );

  Future<Map<String, String>> readEngineFiles(ProfileScope scope) async {
    final directory = engineDirectory(scope);
    final metadata =
        jsonDecode(
              await File(
                p.join(directory.path, 'metadata.json'),
              ).readAsString(),
            )
            as Map<String, dynamic>;
    final records = Map<String, dynamic>.from(metadata['engines'] as Map);
    return <String, String>{
      for (final entry in records.entries)
        entry.key: await File(
          p.join(directory.path, (entry.value as Map)['fileName'] as String),
        ).readAsString(),
    };
  }

  Future<void> writeEngineDirect(
    ProfileScope scope, {
    required String id,
    required String name,
    required String yaml,
    required bool merge,
  }) async {
    final directory = engineDirectory(scope);
    await directory.create(recursive: true);
    final metadataFile = File(p.join(directory.path, 'metadata.json'));
    final records = <String, dynamic>{};
    if (merge && await metadataFile.exists()) {
      final decoded = jsonDecode(await metadataFile.readAsString()) as Map;
      records.addAll(Map<String, dynamic>.from(decoded['engines'] as Map));
    }
    final fileName = '$id.yaml';
    await File(p.join(directory.path, fileName)).writeAsString(yaml);
    records[id] = <String, Object?>{
      'id': id,
      'fileName': fileName,
      'displayName': name,
      'importedAt': DateTime.utc(2026, 1, 1).toIso8601String(),
      'icon': null,
    };
    await metadataFile.writeAsString(
      jsonEncode(<String, Object?>{
        'version': '1.0',
        'updatedAt': DateTime.utc(2026, 1, 1).toIso8601String(),
        'engines': records,
      }),
    );
  }

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'profile-engine-assignment-test-',
    );
    documents = await Directory(
      p.join(temporaryDirectory.path, 'documents'),
    ).create(recursive: true);
    support = await Directory(
      p.join(temporaryDirectory.path, 'support'),
    ).create(recursive: true);
    cache = await Directory(
      p.join(temporaryDirectory.path, 'cache'),
    ).create(recursive: true);
    AppStorage.debugOverride(
      documents: documents,
      support: support,
      cache: cache,
    );
    registry = await ProfileRegistry.open(
      path: p.join(temporaryDirectory.path, 'profiles.db'),
    );
    admin = await registry.createProfile(
      name: 'Admin',
      role: UserProfileRole.admin,
      setupComplete: true,
    );
    member = await registry.createProfile(
      name: 'Member',
      role: UserProfileRole.member,
      setupComplete: true,
    );
    await registry.commitBootstrap(
      activeProfileId: admin.id,
      migratedLegacyInstall: false,
    );
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeCommitted(scope(admin, sessionEpoch: 1));
    LocalEngineStorage.instance.resetProfileScope();
    authorization = await ProfileAuthorizationContext.capture(registry);
    service = ProfileEngineAssignmentService(registry);
  });

  tearDown(() async {
    LocalEngineStorage.instance.resetProfileScope();
    ProfileLockController.instance.dispose();
    ProfileRuntime.debugReset();
    AppStorage.debugReset();
    await registry.close();
    await temporaryDirectory.delete(recursive: true);
  });

  test(
    'copies selected engines into an independent target generation',
    () async {
      await saveActiveEngine(
        id: 'public_engine',
        name: 'Public Engine',
        yaml: _engineYaml('public_engine', 'Public Engine'),
      );
      await saveActiveEngine(
        id: 'private_endpoint',
        name: 'Private Endpoint',
        yaml: _engineYaml(
          'private_endpoint',
          'Private Endpoint',
          baseUrl: 'https://private.invalid/search?token=SENTINEL',
        ),
      );

      final choices = await service.listForTarget(
        actor: authorization,
        targetProfileId: member.id,
      );
      expect(choices.map((choice) => choice.id), <String>[
        'private_endpoint',
        'public_engine',
      ]);
      expect(choices.every((choice) => !choice.assignedToTarget), isTrue);

      await service.apply(
        actor: authorization,
        targetProfileId: member.id,
        selectedEngineIds: const <String>{'private_endpoint'},
      );

      final published = (await registry.getProfile(member.id))!;
      expect(published.visibleDataGeneration, 2);
      final target = await readEngineFiles(scope(published));
      expect(target.keys, <String>{'private_endpoint'});
      expect(target['private_endpoint'], contains('SENTINEL'));

      final source = await readEngineFiles(scope(admin));
      expect(source.keys, <String>{'public_engine', 'private_endpoint'});
      expect(
        engineDirectory(scope(published)).path,
        isNot(engineDirectory(scope(admin)).path),
      );

      await registry.setActiveProfile(published.id);
      ProfileRuntime.publish(scope(published, sessionEpoch: 2));
      LocalEngineStorage.instance.resetProfileScope();
      expect(await LocalEngineStorage.instance.getImportedEngineIds(), <String>[
        'private_endpoint',
      ]);
    },
  );

  test(
    'editing assignments retains target-only engines and removes deselected ones',
    () async {
      await saveActiveEngine(
        id: 'admin_engine',
        name: 'Admin Engine',
        yaml: _engineYaml('admin_engine', 'Admin Engine'),
      );
      await service.apply(
        actor: authorization,
        targetProfileId: member.id,
        selectedEngineIds: const <String>{'admin_engine'},
      );
      member = (await registry.getProfile(member.id))!;
      await writeEngineDirect(
        scope(member),
        id: 'member_custom',
        name: 'Member Custom',
        yaml: _engineYaml('member_custom', 'Member Custom'),
        merge: true,
      );

      final choices = await service.listForTarget(
        actor: authorization,
        targetProfileId: member.id,
      );
      final custom = choices.singleWhere(
        (choice) => choice.id == 'member_custom',
      );
      expect(custom.assignedToTarget, isTrue);
      expect(custom.availableFromManager, isFalse);

      await service.apply(
        actor: authorization,
        targetProfileId: member.id,
        selectedEngineIds: const <String>{'member_custom'},
      );
      member = (await registry.getProfile(member.id))!;
      final target = await readEngineFiles(scope(member));
      expect(target.keys, <String>{'member_custom'});
      expect(target['member_custom'], contains('Member Custom'));
    },
  );

  test(
    'staged profile receives engines before it becomes picker-visible',
    () async {
      await saveActiveEngine(
        id: 'setup_engine',
        name: 'Setup Engine',
        yaml: _engineYaml('setup_engine', 'Setup Engine'),
      );
      final staged = await registry.createProfile(
        name: 'Staged',
        role: UserProfileRole.member,
        lifecycle: UserProfileLifecycle.staging,
        actingProfileId: authorization.profileId,
        actingAuthorizationRevision: authorization.authorizationRevision,
        actingSessionEpoch: authorization.sessionEpoch,
      );

      await service.apply(
        actor: authorization,
        targetProfileId: staged.id,
        selectedEngineIds: const <String>{'setup_engine'},
      );

      final unchanged = (await registry.getProfile(staged.id))!;
      expect(unchanged.lifecycle, UserProfileLifecycle.staging);
      expect(unchanged.visibleDataGeneration, 1);
      expect((await readEngineFiles(scope(unchanged))).keys, <String>{
        'setup_engine',
      });
      expect(
        await registry.listProfiles(includeStaging: false),
        isNot(
          contains(
            predicate<UserProfile>((profile) => profile.id == staged.id),
          ),
        ),
      );
    },
  );

  test(
    'active Admin engines cannot be removed through profile setup',
    () async {
      await saveActiveEngine(
        id: 'admin_engine',
        name: 'Admin Engine',
        yaml: _engineYaml('admin_engine', 'Admin Engine'),
      );

      await expectLater(
        service.apply(
          actor: authorization,
          targetProfileId: admin.id,
          selectedEngineIds: const <String>{},
        ),
        throwsStateError,
      );
      expect((await readEngineFiles(scope(admin))).keys, <String>{
        'admin_engine',
      });
    },
  );
}

String _engineYaml(
  String id,
  String name, {
  String baseUrl = 'https://example.invalid/search',
}) =>
    '''
id: $id
display_name: "$name"
icon: travel_explore
categories: [general]
capabilities:
  keyword_search: true
  imdb_search: false
  series_support: false
api:
  base_url: "$baseUrl"
  method: GET
query_params:
  type: query_params
  param_name: q
response_format:
  type: direct_json
  results_path: results
''';
