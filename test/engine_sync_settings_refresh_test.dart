import 'dart:convert';
import 'dart:io';
import 'package:debrify/screens/settings/widgets/dynamic_settings_builder.dart';
import 'package:debrify/services/engine/engine_registry.dart';
import 'package:debrify/services/engine/local_engine_storage.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_active_profile_refresh.dart';
import 'package:debrify/utils/app_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
    'an open Search settings page refreshes remote engine installs and deletions',
    (tester) async {
      final root = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('engine-settings-refresh-'),
      ))!;
      SharedPreferences.setMockInitialValues({});
      ProfileRuntime.debugReset();
      ProfileRuntime.initializeLegacy();
      AppStorage.debugOverride(documents: root);
      LocalEngineStorage.instance.resetProfileScope();
      EngineRegistry.instance.invalidateProfileScope();
      addTearDown(() async {
        LocalEngineStorage.instance.resetProfileScope();
        EngineRegistry.instance.invalidateProfileScope();
        ProfileRuntime.debugReset();
        AppStorage.debugReset();
        await root.delete(recursive: true);
      });
      await tester.runAsync(() => EngineRegistry.instance.reload());
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: DynamicSettingsBuilder()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('No Search Engines Configured'), findsOneWidget);
      final key = LocalEngineStorage.definitionKey('custom');
      final storage = LocalEngineStorage.forDirectory(
        Directory('${root.path}/engines'),
      );
      const refresher = DefaultWebDavSyncActiveProfileRefresher();
      await tester.runAsync(() async {
        await storage.applySyncDefinitions({
          key: jsonEncode({
            'id': 'custom',
            'name': 'Custom Test Engine',
            'icon': null,
            'deleted': false,
            'yaml': '''
id: custom
display_name: Custom Test Engine
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
settings:
  - id: enabled
    type: toggle
    label: Enabled
    default: true
''',
          }),
        });
        await refresher.refresh({key}, authorizationBarrier: () {});
      });
      await tester.pumpAndSettle();
      expect(find.text('Custom Test Engine'), findsOneWidget);
      await tester.runAsync(() async {
        await storage.applySyncDefinitions({
          key: jsonEncode({'id': 'custom', 'deleted': true}),
        });
        await refresher.refresh({key}, authorizationBarrier: () {});
      });
      await tester.pumpAndSettle();
      expect(find.text('Custom Test Engine'), findsNothing);
      expect(find.text('No Search Engines Configured'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
