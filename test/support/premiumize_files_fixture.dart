import 'dart:async';
import 'dart:convert';
import 'package:debrify/models/premiumize_folder_item.dart';
import 'package:debrify/screens/premiumize/premiumize_files_screen.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/secret_vault.dart';
import 'package:debrify/services/series_source_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> premiumizeFile(
  String id, {
  String? name,
  bool folder = false,
  bool video = true,
  bool url = true,
  bool stream = false,
  int size = 209715200,
}) => {
  'id': id,
  'name':
      name ??
      (folder
          ? 'Folder $id'
          : video
          ? 'Video $id.mkv'
          : 'Archive $id.zip'),
  'type': folder ? 'folder' : 'file',
  'size': folder ? 0 : size,
  'created_at': 1767225600,
  if (!folder && url) 'link': 'https://example.test/$id.mkv',
  if (!folder && stream) 'stream_link': 'https://example.test/$id.m3u8',
};

PremiumizeFolderItem premiumizeItem(
  String id, {
  bool folder = false,
  bool video = true,
  bool url = true,
}) => PremiumizeFolderItem.fromJson(
  premiumizeFile(id, folder: folder, video: video, url: url),
);

class PremiumizeObserver extends NavigatorObserver {
  final popped = <Route<dynamic>>[];
  final pushed = <Route<dynamic>>[];
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      popped.add(route);
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      pushed.add(route);
}

class PremiumizeFixture {
  final key = GlobalKey<State<PremiumizeFilesScreen>>();
  final navigatorKey = GlobalKey<NavigatorState>();
  final nestedKey = GlobalKey<NavigatorState>();
  final observer = PremiumizeObserver();
  final nestedObserver = PremiumizeObserver();
  final requests = <http.Request>[];
  final pages = <String, List<Map<String, dynamic>>>{};
  final searches = <String, List<Map<String, dynamic>>>{};
  final details = <String, Map<String, dynamic>>{};
  final held = <String, Completer<http.Response>>{};
  final failures = <String>{};
  final clipboard = <String>[];
  String clipboardText = '';
  bool enabled = true, nested = false;
  Future<void> Function(http.Request)? onRequest;
  List<Map<String, dynamic>> rows = [
    premiumizeFile('z9', folder: true),
    premiumizeFile('a2'),
    premiumizeFile('m5'),
  ];
  List<Map<String, dynamic>> transfers = [
    {
      'id': 't9',
      'name': 'Finished fixture',
      'status': 'finished',
      'progress': 1,
    },
    {
      'id': 't2',
      'name': 'Running fixture',
      'status': 'running',
      'progress': 0.5,
      'message': 'Loading 50%',
    },
    {'id': 't5', 'name': 'Error fixture', 'status': 'error', 'progress': 0},
  ];
  Map<String, Object?> get access =>
      premiumizeFilesTestAccess(key.currentState!);
  dynamic member(String name) => access[name];
  List<PremiumizeFolderItem> get items =>
      member('items') as List<PremiumizeFolderItem>;
  List<String> get ids => items.map((r) => r.id).toList();
  List<String> get resultIds =>
      (member('searchResults') as List<PremiumizeFolderItem>)
          .map((r) => r.id)
          .toList();
  List<Map<String, Object>> get log => [
    for (final r in requests)
      {
        'method': r.method,
        'path': r.url.path,
        'query': r.url.queryParameters,
        'body': r.body.isEmpty ? <String, String>{} : r.bodyFields,
      },
  ];
  Map<String, Object> getRequest(
    String endpoint, [
    Map<String, String> query = const {},
  ]) => {
    'method': 'GET',
    'path': '/api/$endpoint',
    'query': {'apikey': 'fixture-key', ...query},
    'body': <String, String>{},
  };
  Map<String, Object> postRequest(
    String endpoint,
    Map<String, String> body, [
    Map<String, String> query = const {},
  ]) => {
    'method': 'POST',
    'path': '/api/$endpoint',
    'query': query,
    'body': body,
  };
  Map<String, dynamic> page(List<Map<String, dynamic>> content) => {
    'status': 'success',
    'content': content,
  };
  http.Response json(Object body, [int status = 200]) =>
      http.Response(jsonEncode(body), status);
  String requestKey(http.Request r) =>
      '${r.url.path.substring(5)}|${r.url.queryParameters['id'] ?? r.url.queryParameters['q'] ?? (r.body.isEmpty ? '' : r.bodyFields['id'] ?? '')}';
  Future<http.Response> respond(http.Request r) async {
    requests.add(r);
    expect(r.url.host, 'www.premiumize.me');
    expect(r.url.path, startsWith('/api/'));
    expect(r.bodyBytes.length, lessThan(32768));
    await onRequest?.call(r);
    final k = requestKey(r);
    if (held.containsKey(k)) return held[k]!.future;
    if (failures.contains(k)) {
      return json({'status': 'error', 'message': 'fixture failure'}, 500);
    }
    final endpoint = r.url.path.substring(5);
    switch (endpoint) {
      case 'folder/list':
        final id = r.url.queryParameters['id'] ?? '';
        return json(
          page(
            pages[id] ??
                (id.isEmpty
                    ? rows
                    : [premiumizeFile('n6'), premiumizeFile('b3')]),
          ),
        );
      case 'folder/search':
        return json(
          page(searches[r.url.queryParameters['q']] ?? [premiumizeFile('hit')]),
        );
      case 'item/details':
        final id = r.url.queryParameters['id']!;
        return json({
          'status': 'success',
          ...details[id] ?? premiumizeFile(id),
        });
      case 'transfer/list':
        return json({'status': 'success', 'transfers': transfers});
      case 'item/delete':
      case 'folder/delete':
      case 'transfer/delete':
      case 'transfer/clearfinished':
      case 'transfer/create':
        return json({'status': 'success', 'id': 'new-transfer'});
      default:
        throw StateError(
          'Unexpected original Premiumize fixture ${r.method} ${r.url}',
        );
    }
  }

  Widget screen({
    bool pushed = false,
    bool picker = false,
    String? initialId,
    String? initialName,
    String? initialQuery,
    Future<void> Function(SeriesSource)? selected,
  }) => RepaintBoundary(
    key: const ValueKey('premiumize-canvas'),
    child: PremiumizeFilesScreen(
      key: key,
      isPushedRoute: pushed,
      selectSourceMode: picker,
      initialFolderId: initialId,
      initialFolderName: initialName,
      initialSearchQuery: initialQuery,
      onSourceSelected: selected,
    ),
  );
  Future<void> mount(
    WidgetTester t, {
    bool pushed = false,
    bool picker = false,
    String? initialId,
    String? initialName,
    String? initialQuery,
    Future<void> Function(SeriesSource)? selected,
    bool wait = true,
    bool useNested = false,
  }) async {
    t.view.physicalSize = const Size(1000, 800);
    t.view.devicePixelRatio = 1;
    final child = screen(
      pushed: pushed,
      picker: picker,
      initialId: initialId,
      initialName: initialName,
      initialQuery: initialQuery,
      selected: selected,
    );
    nested = useNested;
    await t.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        navigatorObservers: [observer],
        theme: ThemeData.dark(),
        home: useNested
            ? Navigator(
                key: nestedKey,
                observers: [nestedObserver],
                onGenerateRoute: (_) => MaterialPageRoute<void>(
                  builder: (_) => const Scaffold(body: Text('Nested caller')),
                ),
              )
            : pushed
            ? const Scaffold(body: Text('Caller'))
            : child,
      ),
    );
    if (pushed || useNested) {
      (useNested ? nestedKey : navigatorKey).currentState!.push(
        MaterialPageRoute<void>(builder: (_) => child),
      );
      await t.pump();
    }
    if (wait) await until(t, () => member('initialLoad') == false);
    await t.pump();
    // No elapsed fake time here: root debounce boundaries are observed by callers.
  }

  Future<void> until(WidgetTester t, bool Function() ready) async {
    for (var i = 0; i < 300 && !ready(); i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await t.pump();
    }
    expect(
      ready(),
      isTrue,
      reason: 'Original Premiumize action did not finish',
    );
  }

  Future<void> transitions(WidgetTester t) async {
    await t.pump(const Duration(milliseconds: 400));
    await t.pump();
  }

  Future<void> waitForText(WidgetTester t, String text) async {
    for (var i = 0; i < 40 && find.text(text).evaluate().isEmpty; i++) {
      await t.pump(const Duration(milliseconds: 300));
    }
    expect(
      find.text(text),
      findsOneWidget,
      reason: 'queued snackbar becomes visible',
    );
  }

  Future<void> close(WidgetTester t) async {
    await t.pumpWidget(const SizedBox.shrink());
    await t.pump();
    t.view.reset();
    expect(t.takeException(), isNull);
  }
}

Future<void> premiumizeCase(
  WidgetTester t,
  Future<void> Function(PremiumizeFixture) body, {
  Map<String, Object> preferences = const {},
  bool omitApiKey = false,
}) async {
  SharedPreferences.setMockInitialValues({
    if (!omitApiKey) 'premiumize_api_key': 'fixture-key',
    'premiumize_integration_enabled': true,
    ...preferences,
  });
  ProfileRuntime.debugReset();
  ProfileRuntime.initializeLegacy();
  SecretVault.debugReset(deviceIdOverride: 'premiumize-characterization');
  MainPageBridge.returnToTorrentSearchOnBack = false;
  MainPageBridge.setActiveTab('premiumize');
  MainPageBridge.setActiveTvTab(11);
  final f = PremiumizeFixture();
  f.enabled =
      preferences['premiumize_integration_enabled'] != false &&
      (preferences['premiumize_api_key'] ?? 'fixture-key') != '';
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          f.clipboard.add((call.arguments as Map)['text'] as String);
        }
        if (call.method == 'Clipboard.getData') {
          return {'text': f.clipboardText};
        }
        return null;
      });
  try {
    await http.runWithClient(() async {
      try {
        await body(f);
      } finally {
        try {
          await f.close(t);
        } finally {
          // A failed assertion can leave a held HTTP future outstanding. Drain
          // it after unmounting, so the service timeout is not a second failure.
          for (final response in f.held.values) {
            if (!response.isCompleted) {
              response.complete(
                f.json({'status': 'success', 'content': [], 'transfers': []}),
              );
            }
          }
          await t.pump();
        }
      }
    }, () => MockClient(f.respond));
  } finally {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    MainPageBridge.switchTab = null;
    MainPageBridge.focusTvSidebar = null;
    MainPageBridge.setActiveTab(null);
    MainPageBridge.returnToTorrentSearchOnBack = false;
    ProfileRuntime.debugReset();
    SecretVault.debugReset();
  }
}
