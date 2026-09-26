import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:debrify/features/search/data/engine_keyword_sources_repository.dart';
import 'package:debrify/models/engine_config/engine_config.dart';
import 'package:debrify/models/indexer_manager_config.dart';
import 'package:debrify/services/engine/dynamic_engine.dart';
import 'package:debrify/services/engine/engine_registry.dart';
import 'package:debrify/services/engine/local_engine_storage.dart';
import 'package:debrify/utils/app_storage.dart';
import 'package:debrify/services/engine/settings_manager.dart';
import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/services/torrent_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

DynamicEngine engine(String id, bool? enabled) => DynamicEngine(
  EngineConfig.fromMap({
    'metadata': {
      'id': id,
      'display_name': 'Label $id',
      'capabilities': {'keyword_search': true},
    },
    if (enabled != null)
      'settings': {
        'enabled': {'default_value': enabled},
      },
  }),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
  });
  tearDown(() {
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
  });

  EngineKeywordSourcesRepository repository(
    Future<List<DynamicEngine>> Function() engines,
  ) => EngineKeywordSourcesRepository(
    owner: ProfileSessionMemory.captureOwner(),
    settings: SettingsManager(),
    engines: engines,
  );

  test(
    'engine defaults and saved overrides match the keyword search contract',
    () async {
      final repo = repository(
        () async => [
          engine('default', null),
          engine('off', false),
          engine('on', true),
        ],
      );
      await SettingsManager().setEnabled('on', false);
      final choices = await repo.load();
      expect(choices.map((s) => s.id), ['default', 'off', 'on']);
      expect(choices.map((s) => s.label), [
        'Label default',
        'Label off',
        'Label on',
      ]);
      expect(choices.map((s) => s.enabled), [true, false, false]);
      expect(() => choices.clear(), throwsUnsupportedError);
      await repo.setEnabled('My Engine: A', true);
      expect(await SettingsManager().getEnabled('My Engine: A', false), isTrue);
    },
  );

  test(
    'the production combined loader includes a disabled user indexer',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'keyword-source-settings-',
      );
      AppStorage.debugOverride(
        documents: directory,
        support: directory,
        cache: directory,
      );
      EngineRegistry.instance.invalidateProfileScope();
      LocalEngineStorage.instance.resetProfileScope();
      addTearDown(() async {
        EngineRegistry.instance.invalidateProfileScope();
        LocalEngineStorage.instance.resetProfileScope();
        AppStorage.debugReset();
        await directory.delete(recursive: true);
      });
      await LocalEngineStorage.instance.saveEngine(
        engineId: 'installed',
        fileName: 'installed.yaml',
        displayName: 'Label installed',
        yamlContent: jsonEncode({
          'id': 'installed',
          'display_name': 'Label installed',
          'capabilities': {'keyword_search': true},
          'settings': [
            {'id': 'enabled', 'default': false},
          ],
        }),
      );
      const indexer = IndexerManagerConfig(
        id: 'fixture',
        name: 'Local Prowlarr',
        type: IndexerManagerType.prowlarr,
        baseUrl: 'https://indexer.invalid',
        apiKey: 'test-only',
        enabled: false,
      );
      await StorageService.setIndexerManagerConfigs([indexer]);
      final repo = repository(TorrentService.getKeywordSearchEngines);
      final choices = await repo.load();
      expect(choices.map((s) => s.id), ['installed', indexer.engineId]);
      expect(choices.first.enabled, isFalse);
      final custom = choices.singleWhere((s) => s.id == indexer.engineId);
      expect(custom.label, 'Local Prowlarr');
      expect(custom.enabled, isFalse);
      await repo.setEnabled(indexer.engineId, true);
      final updated = await repo.load();
      expect(
        updated.singleWhere((s) => s.id == indexer.engineId).enabled,
        isTrue,
      );
    },
  );

  test(
    'a late engine enumeration cannot expose the outgoing profile choices',
    () async {
      final pending = Completer<List<DynamicEngine>>();
      final repo = repository(() => pending.future);
      final loading = repo.load();
      ProfileRuntime.initializeCommitted(
        ProfileScope(profileId: 'incoming', dataGeneration: 1, sessionEpoch: 2),
      );
      pending.complete([engine('outgoing', true)]);
      expect(await loading, isEmpty);
      await repo.setEnabled('outgoing', true);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys(), isEmpty);
    },
  );

  test(
    'an engine settings write rejects profile retirement at the mutation barrier',
    () async {
      final origin = ProfileScope(
        profileId: 'origin',
        dataGeneration: 1,
        sessionEpoch: 1,
      );
      final incoming = ProfileScope(
        profileId: 'incoming',
        dataGeneration: 1,
        sessionEpoch: 2,
      );
      ProfileRuntime.initializeCommitted(origin);
      final repo = repository(() async => []);
      final entered = Completer<void>();
      final release = Completer<void>();
      final barrier = ProfilePreferences.captureMutationSnapshot((_) async {
        entered.complete();
        await release.future;
      });
      await entered.future;
      final rejected = expectLater(
        repo.setEnabled('retired', true),
        throwsStateError,
      );
      await Future<void>.delayed(Duration.zero);
      ProfileRuntime.publish(incoming);
      release.complete();
      await barrier;
      await rejected;
      final prefs = await SharedPreferences.getInstance();
      final key = SettingsManager().generateKey('retired', 'enabled');
      expect(prefs.containsKey(origin.preferenceKey(key)), isFalse);
      expect(prefs.containsKey(incoming.preferenceKey(key)), isFalse);
    },
  );
}
