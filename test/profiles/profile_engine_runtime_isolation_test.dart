import 'dart:async';
import 'dart:io';

import 'package:debrify/services/engine/config_loader.dart';
import 'package:debrify/services/engine/engine_profile_lifecycle.dart';
import 'package:debrify/services/engine/engine_registry.dart';
import 'package:debrify/services/engine/local_engine_storage.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/utils/app_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late Directory documents;
  late ProfileScope profileA;
  late ProfileScope profileB;

  Future<void> saveEngine(
    ProfileScope scope, {
    required String id,
    required String name,
  }) async {
    await ProfileRuntime.withCapturedScope(scope, () async {
      LocalEngineStorage.instance.resetProfileScope();
      await LocalEngineStorage.instance.saveEngine(
        engineId: id,
        fileName: '$id.yaml',
        yamlContent: _engineYaml(id, name),
        displayName: name,
      );
    });
    LocalEngineStorage.instance.resetProfileScope();
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp(
      'profile-engine-runtime-isolation-',
    );
    documents = await Directory(
      p.join(root.path, 'documents'),
    ).create(recursive: true);
    final support = await Directory(
      p.join(root.path, 'support'),
    ).create(recursive: true);
    final cache = await Directory(
      p.join(root.path, 'cache'),
    ).create(recursive: true);
    AppStorage.debugOverride(
      documents: documents,
      support: support,
      cache: cache,
    );
    profileA = ProfileScope(
      profileId: 'profile-a',
      dataGeneration: 1,
      sessionEpoch: 1,
    );
    profileB = ProfileScope(
      profileId: 'profile-b',
      dataGeneration: 1,
      sessionEpoch: 2,
    );
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeCommitted(profileA);
    EngineRegistry.instance.invalidateProfileScope();
    LocalEngineStorage.instance.resetProfileScope();
  });

  tearDown(() async {
    EngineRegistry.debugBeforePublish = null;
    EngineRegistry.instance.invalidateProfileScope();
    LocalEngineStorage.instance.resetProfileScope();
    ProfileRuntime.debugReset();
    AppStorage.debugReset();
    await root.delete(recursive: true);
  });

  test('profile switch replaces both parsed engine caches with the target',
      () async {
    await saveEngine(profileA, id: 'a_engine', name: 'A Engine');
    await saveEngine(profileB, id: 'b_engine', name: 'B Engine');

    await EngineRegistry.instance.reload();
    expect(EngineRegistry.instance.getEngineIds(), <String>['a_engine']);

    EngineProfileLifecycle.prepareDeactivate();
    ProfileRuntime.publish(profileB);

    // Publication itself must fail closed. Candidate warming happens after
    // this point and no caller may observe A's map in that window.
    expect(EngineRegistry.instance.isInitialized, isFalse);
    expect(EngineRegistry.instance.getEngineIds(), isEmpty);

    await EngineProfileLifecycle.warmCurrentScope();
    expect(EngineRegistry.instance.getEngineIds(), <String>['b_engine']);
    expect(EngineRegistry.instance.getEngine('a_engine'), isNull);
    expect(
      (await ConfigLoader().getEngines()).map((config) => config.metadata.id),
      <String>['b_engine'],
    );
  });

  test('profile generation reset cannot retain the previous parsed engine',
      () async {
    await saveEngine(profileA, id: 'a_engine', name: 'A Engine');
    await EngineRegistry.instance.reload();
    expect(EngineRegistry.instance.getEngineIds(), <String>['a_engine']);

    final resetScope = ProfileScope(
      profileId: profileA.profileId,
      dataGeneration: 2,
      sessionEpoch: 2,
    );
    EngineProfileLifecycle.prepareDeactivate();
    ProfileRuntime.publish(resetScope);
    expect(EngineRegistry.instance.getEngineIds(), isEmpty);

    await EngineProfileLifecycle.warmCurrentScope();
    expect(EngineRegistry.instance.isInitialized, isTrue);
    expect(EngineRegistry.instance.getEngineIds(), isEmpty);
    expect(await ConfigLoader().getEngines(), isEmpty);
  });

  test('an outgoing async load cannot publish after profile activation',
      () async {
    await saveEngine(profileA, id: 'a_engine', name: 'A Engine');
    await saveEngine(profileB, id: 'b_engine', name: 'B Engine');
    final reachedPublish = Completer<void>();
    final releasePublish = Completer<void>();
    EngineRegistry.debugBeforePublish = () {
      reachedPublish.complete();
      return releasePublish.future;
    };

    final outgoingLoad = EngineRegistry.instance.reload();
    await reachedPublish.future;
    EngineProfileLifecycle.prepareDeactivate();
    ProfileRuntime.publish(profileB);
    releasePublish.complete();
    await outgoingLoad;

    expect(EngineRegistry.instance.isInitialized, isFalse);
    expect(EngineRegistry.instance.getEngineIds(), isEmpty);

    EngineRegistry.debugBeforePublish = null;
    await EngineProfileLifecycle.warmCurrentScope();
    expect(EngineRegistry.instance.getEngineIds(), <String>['b_engine']);
  });
}

String _engineYaml(String id, String name) =>
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
  base_url: "https://example.invalid/search"
  method: GET
query_params:
  type: query_params
  param_name: q
response_format:
  type: direct_json
  results_path: results
''';
