import 'dart:io';

import 'package:debrify/screens/search_screen.dart';
import 'package:debrify/screens/search/keyword_search_screen.dart';
import 'package:debrify/services/engine/engine_registry.dart';
import 'package:debrify/services/engine/local_engine_storage.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/utils/app_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Actual-host characterization on main after #90/#96. Transport fixture
// matches the keyword TV origin pin; controller and widget behavior stay in lib.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    ProfileSessionMemory.clearAll();
    StorageService.resetProfileCaches();
    root = await Directory.systemTemp.createTemp('keyword-tv-origin-');
    AppStorage.debugOverride(documents: root, support: root, cache: root);
    LocalEngineStorage.instance.resetProfileScope();
    EngineRegistry.instance.invalidateProfileScope();
    await EngineRegistry.instance.initialize();
  });

  tearDown(() async {
    ProfileSessionMemory.clearAll();
    EngineRegistry.instance.invalidateProfileScope();
    LocalEngineStorage.instance.resetProfileScope();
    AppStorage.debugReset();
    ProfileRuntime.debugReset();
    await root.delete(recursive: true);
  });

  testWidgets('one selection notification rebuilds keyword without rebuilding host', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1920, 1080);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final previousSidebar = MainPageBridge.focusTvSidebar;
    var sidebarCalls = 0;
    MainPageBridge.focusTvSidebar = () => sidebarCalls++;
    addTearDown(() => MainPageBridge.focusTvSidebar = previousSidebar);

    await tester.pumpWidget(
      const MaterialApp(
        home: SearchScreen(searchMode: true, isTelevision: true),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      MediaQuery.sizeOf(tester.element(find.byType(SearchScreenHost))),
      const Size(1920, 1080),
    );
    // Seed the field as if the shell handed focus into the Search tab. Every
    // subsequent transition uses real keyboard events, never State methods.
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    final field = tester.widget<EditableText>(find.byType(EditableText));
    expect(field.focusNode.hasFocus, isTrue);

    Future<void> press(LogicalKeyboardKey key) async {
      await tester.sendKeyEvent(key);
      await tester.pumpAndSettle();
    }

    void expectFocusedLabel(String label) {
      final focusedWidget = FocusManager.instance.primaryFocus!.context!.widget;
      expect(
        find.descendant(
          of: find.byWidget(focusedWidget),
          matching: find.text(label),
        ),
        findsOneWidget,
      );
    }

    await press(LogicalKeyboardKey.arrowUp);
    expectFocusedLabel('Catalog');
    await press(LogicalKeyboardKey.arrowRight);
    expectFocusedLabel('Keyword');
    await press(LogicalKeyboardKey.enter);
    expect(find.text('Keyword torrent search'), findsOneWidget);
    expect(find.text('Search torrents by keyword'), findsOneWidget);
    await press(LogicalKeyboardKey.arrowUp);
    expect(field.focusNode.hasFocus, isTrue);
    await press(LogicalKeyboardKey.arrowDown);
    expect(field.focusNode.hasFocus, isFalse);
    expectFocusedLabel('Sources');
    await press(LogicalKeyboardKey.arrowLeft);
    expect(sidebarCalls, 1, reason: 'One key press hands off exactly once');
    await press(LogicalKeyboardKey.arrowUp);
    expect(field.focusNode.hasFocus, isTrue);
    expect(find.text('Keyword torrent search'), findsOneWidget);

    // One ordinary imported engine makes the results toolbar reachable. Only
    // transport is mocked; request/parse/render/focus all remain in lib.
    await tester.runAsync(() async {
      await LocalEngineStorage.instance.saveEngine(
        engineId: 'tv_origin',
        fileName: 'tv_origin.yaml',
        yamlContent: _engineYaml,
        displayName: 'TV Origin',
      );
      await EngineRegistry.instance.reload();
    });
    var requests = 0;
    await tester.enterText(find.byType(TextField), 'focus fixture');
    await http.runWithClient(
      () async {
        await tester.testTextInput.receiveAction(TextInputAction.search);
        await tester.pumpAndSettle();
      },
      () => MockClient((request) async {
        requests++;
        expect(
          request.url,
          Uri.parse('https://tv-origin.invalid/search?q=focus+fixture'),
        );
        return http.Response(
          '''{"results":[{
        "infohash":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        "name":"Focus Fixture 1080p", "seeders":12, "size_bytes":1000000000
      }]}''',
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    expect(requests, 1);
    final surface = find.byType(KeywordSearchScreen);
    final controller = tester.widget<KeywordSearchScreen>(surface).controller;
    controller.enterSelection();
    await tester.pumpAndSettle();
    final focusedNode = controller.kwToolbarNodes.first;
    focusedNode.requestFocus();
    await tester.pumpAndSettle();
    expectFocusedLabel('Cancel');
    expect(find.text('Add'), findsOneWidget);
    expect(find.text('Add · 1'), findsNothing);

    var hostBuilds = 0;
    var childBuilds = 0;
    var notifications = 0;
    void countNotification() => notifications++;
    controller.addListener(countNotification);
    final previousRebuild = debugOnRebuildDirtyWidget;
    debugOnRebuildDirtyWidget = (element, builtOnce) {
      previousRebuild?.call(element, builtOnce);
      if (element.widget is SearchScreenHost) hostBuilds++;
      if (element.widget is KeywordSearchScreen) childBuilds++;
    };
    try {
      // One synchronous lib notification reaches the child paint subscription.
      // Measure actual builds, not setState calls or listener registrations.
      controller.toggleSelection(controller.kwResults.single);
      expect(notifications, 1);
      await tester.pump();
      expect(hostBuilds, 0);
      expect(childBuilds, 1);
      expect(find.text('Add · 1'), findsOneWidget);
      expect(find.text('None'), findsOneWidget);
      expect(controller.kwToolbarNodes.first, same(focusedNode));
      expect(focusedNode.hasFocus, isTrue);
      expectFocusedLabel('Cancel');

      // The same notification must not cause a second build next frame.
      await tester.pump(const Duration(milliseconds: 16));
      expect(hostBuilds, 0);
      expect(childBuilds, 1);
      expect(notifications, 1);
      expect(focusedNode.hasFocus, isTrue);
      expect(requests, 1, reason: 'Selection must not re-run search');
      expect(tester.takeException(), isNull);
    } finally {
      debugOnRebuildDirtyWidget = previousRebuild;
      controller.removeListener(countNotification);
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}

const _engineYaml = '''
id: tv_origin
display_name: TV Origin
icon: travel_explore
categories: [general]
capabilities:
  keyword_search: true
  imdb_search: false
  series_support: false
api:
  base_url: https://tv-origin.invalid/search
  method: GET
query_params:
  type: query_params
  param_name: q
response_format:
  type: direct_json
  results_path: results
field_mappings:
  infohash: infohash
  name: name
  seeders: seeders
  size_bytes: size_bytes
''';
