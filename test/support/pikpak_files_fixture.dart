import 'dart:async';
import 'dart:convert';
import 'package:debrify/screens/pikpak/pikpak_files_screen.dart';
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

Map<String, dynamic> pikpakFile(
  String id, {
  String? name,
  bool folder = false,
  int? mib = 200,
  bool complete = true,
  bool video = true,
  bool url = true,
}) => {
  'id': id,
  'name':
      name ??
      (folder
          ? 'Folder $id'
          : video
          ? 'Video $id.mkv'
          : 'Archive $id.zip'),
  'kind': folder ? 'drive#folder' : 'drive#file',
  'mime_type': folder
      ? ''
      : video
      ? 'video/x-matroska'
      : 'application/zip',
  if (mib != null) 'size': '${mib * 1024 * 1024}',
  'phase': complete ? 'PHASE_TYPE_COMPLETE' : 'PHASE_TYPE_RUNNING',
  'created_time': '2026-01-01T00:00:00Z',
  if (url) 'web_content_link': 'https://example.test/$id.mkv',
};

class PikpakObserver extends NavigatorObserver {
  final popped = <Route<dynamic>>[];
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    popped.add(route);
  }
}

class PikpakFixture {
  final key = GlobalKey<State<PikPakFilesScreen>>();
  final navigatorKey = GlobalKey<NavigatorState>();
  final observer = PikpakObserver();
  final requests = <http.Request>[];
  final pages = <String, Map<String, dynamic>>{};
  final details = <String, Map<String, dynamic>>{};
  final failingDetails = <String>{};
  final heldDetails = <String, Completer<http.Response>>{};
  final heldPages = <String, Completer<http.Response>>{};
  final clipboard = <String>[];
  String clipboardText = '';
  bool failLists = false, failPost = false, enabled = true;
  Completer<http.Response>? heldPost;
  Future<void> Function(http.Request)? onRequest;
  List<Map<String, dynamic>> rows = [
    pikpakFile('z9', folder: true),
    pikpakFile('a2'),
    pikpakFile('m5'),
  ];
  Map<String, Object?> get access => pikpakFilesTestAccess(key.currentState!);
  dynamic member(String name) => access[name];
  List<String> get ids =>
      (member('files') as List).map((dynamic r) => r['id'] as String).toList();
  Map<String, dynamic> page(List<Map<String, dynamic>> files, {String? next}) =>
      {'files': files, if (next != null) 'next_page_token': next};
  http.Response json(Object body, [int status = 200]) =>
      http.Response(jsonEncode(body), status);
  List<String> get log => requests
      .map(
        (r) =>
            '${r.method} ${r.url.path}${r.url.query.isEmpty ? '' : '?${r.url.query}'}',
      )
      .toList();
  Future<http.Response> respond(http.Request r) async {
    requests.add(r);
    expect(r.url.host, 'api-drive.mypikpak.com');
    await onRequest?.call(r);
    final path = r.url.path;
    if (path == '/drive/v1/files' && r.method == 'GET') {
      final parent = r.url.queryParameters['parent_id'] ?? '';
      final token = r.url.queryParameters['page_token'] ?? '';
      final k = '$parent|$token';
      if (heldPages.containsKey(k)) return heldPages[k]!.future;
      if (failLists) {
        return json({'error_description': 'fixture list failure'}, 500);
      }
      return json(
        pages[k] ??
            page(parent.isEmpty ? rows : [pikpakFile('n6'), pikpakFile('b3')]),
      );
    }
    if (path.startsWith('/drive/v1/files/') && r.method == 'GET') {
      final id = path.split('/').last;
      if (heldDetails.containsKey(id)) return heldDetails[id]!.future;
      if (failingDetails.contains(id)) {
        return json({'error_description': 'fixture details failure'}, 500);
      }
      return json(
        details[id] ?? pikpakFile(id, folder: id == 'z9' || id == 'restricted'),
      );
    }
    if (r.method == 'POST' &&
        (path == '/drive/v1/files:batchTrash' ||
            path == '/drive/v1/files:batchDelete' ||
            path == '/drive/v1/files')) {
      if (heldPost != null) return heldPost!.future;
      if (failPost) {
        return json({'error_description': 'fixture post failure'}, 500);
      }
      return json(
        path == '/drive/v1/files'
            ? {
                'file': {'name': 'Fixture added'},
              }
            : <String, dynamic>{},
      );
    }
    throw StateError('Unexpected original PikPak fixture ${r.method} ${r.url}');
  }

  Future<void> mount(
    WidgetTester t, {
    bool pushed = false,
    bool picker = false,
    String? initialId,
    String? initialName,
    Future<void> Function(SeriesSource)? selected,
    bool wait = true,
  }) async {
    t.view.physicalSize = const Size(1000, 800);
    t.view.devicePixelRatio = 1;
    final screen = PikPakFilesScreen(
      key: key,
      isPushedRoute: pushed,
      selectSourceMode: picker,
      initialFolderId: initialId,
      initialFolderName: initialName,
      onSourceSelected: selected,
    );
    await t.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        navigatorObservers: [observer],
        theme: ThemeData.dark(),
        home: pushed
            ? const Scaffold(body: Text('Caller'))
            : RepaintBoundary(
                key: const ValueKey('pikpak-canvas'),
                child: screen,
              ),
      ),
    );
    if (pushed) {
      navigatorKey.currentState!.push(
        MaterialPageRoute<void>(builder: (_) => screen),
      );
      await t.pump();
    }
    if (wait) {
      await until(
        t,
        () => enabled
            ? requests.isNotEmpty && member('isLoading') == false
            : member('pikpakEnabled') == false,
      );
    }
    await t.pump(const Duration(milliseconds: 600));
    await t.pump();
  }

  Future<void> until(WidgetTester t, bool Function() ready) async {
    for (var i = 0; i < 100 && !ready(); i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await t.pump();
    }
    expect(ready(), isTrue, reason: 'Original PikPak action did not finish');
  }

  Future<void> close(WidgetTester t) async {
    await t.pumpWidget(const SizedBox.shrink());
    await t.pump(const Duration(seconds: 11));
    await t.pump();
    t.view.reset();
    expect(t.takeException(), isNull);
  }
}

Future<void> pikpakCase(
  WidgetTester t,
  Future<void> Function(PikpakFixture) body, {
  Map<String, Object> preferences = const {},
}) async {
  SharedPreferences.setMockInitialValues({
    'pikpak_enabled': true,
    'pikpak_email': 'fixture@example.test',
    'pikpak_access_token': 'fixture-access',
    'pikpak_refresh_token': 'fixture-refresh',
    ...preferences,
  });
  ProfileRuntime.debugReset();
  ProfileRuntime.initializeLegacy();
  SecretVault.debugReset(deviceIdOverride: 'pikpak-characterization');
  MainPageBridge.returnToTorrentSearchOnBack = false;
  MainPageBridge.setActiveTab('pikpak');
  MainPageBridge.setActiveTvTab(6);
  final f = PikpakFixture();
  f.enabled = preferences['pikpak_enabled'] != false;
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
        await f.close(t);
      }
    }, () => MockClient(f.respond));
  } finally {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    MainPageBridge.switchTab = null;
    MainPageBridge.focusTvSidebar = null;
    MainPageBridge.setActiveTab(null);
    ProfileRuntime.debugReset();
    SecretVault.debugReset();
  }
}
