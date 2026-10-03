import 'dart:async';
import 'dart:convert';

import 'package:debrify/models/torbox_torrent.dart';
import 'package:debrify/models/torbox_web_download.dart';
import 'package:debrify/screens/torbox/torbox_downloads_screen.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/secret_vault.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, Object?> torboxRow(int id, {int files = 3}) => {
  'id': id,
  'hash': 'hash-$id',
  'name': 'Library $id',
  'created_at': '2026-01-01T00:00:00Z',
  'updated_at': '2026-01-02T00:00:00Z',
  'size': 3000,
  'download_finished': true,
  'download_state': 'cached',
  'files': [
    for (var i = 0; i < files; i++)
      {
        'id': i + 1,
        'name': ['Zebra.mkv', 'Alpha.mkv', 'Nested/Show.S02E03.mkv'][i % 3],
        'short_name': ['Zebra.mkv', 'Alpha.mkv', 'Show.S02E03.mkv'][i % 3],
        'size': 1000,
        'mimetype': 'video/x-matroska',
      },
  ],
};

class TorboxFixture {
  final key = GlobalKey<State<TorboxDownloadsScreen>>();
  final navigatorKey = GlobalKey<NavigatorState>();
  final requests = <http.Request>[];
  List<Map<String, Object?>> torrents = [
    torboxRow(1),
    torboxRow(2),
    torboxRow(3),
  ];
  List<Map<String, Object?>> web = [
    torboxRow(11),
    torboxRow(12),
    torboxRow(13),
  ];
  int? failDelete;
  bool failLists = false;
  bool failCreate = false;
  Completer<http.Response>? pending;
  bool holdLists = false;
  bool holdDelete = false;
  int deleteCount = 0;

  Map<String, Object?> get access =>
      torboxDownloadsTestAccess(key.currentState!);
  dynamic member(String name) => access[name];
  TorboxTorrent torrent(int id, {int files = 3}) =>
      TorboxTorrent.fromJson(torboxRow(id, files: files));
  TorboxWebDownload download(int id, {int files = 3}) =>
      TorboxWebDownload.fromJson(torboxRow(id, files: files));

  Future<http.Response> respond(http.Request request) async {
    requests.add(request);
    if (request.url.path.endsWith('/mylist')) {
      if (holdLists) return pending!.future;
      if (failLists) {
        return http.Response(
          '{"success":false,"error":"fixture failure"}',
          200,
        );
      }
      final rows = request.url.path.contains('/webdl/') ? web : torrents;
      final offset = int.parse(request.url.queryParameters['offset'] ?? '0');
      return http.Response(
        jsonEncode({'success': true, 'data': offset == 0 ? rows : []}),
        200,
      );
    }
    if (request.url.path.endsWith('/controltorrent') ||
        request.url.path.endsWith('/controlwebdownload')) {
      deleteCount++;
      if (holdDelete && deleteCount == 1) return pending!.future;
      final data = jsonDecode(request.body) as Map;
      final id = int.parse('${data['torrent_id'] ?? data['webdl_id'] ?? -1}');
      return http.Response(
        jsonEncode({
          'success': id != failDelete,
          'error': 'fixture delete failure',
        }),
        200,
      );
    }
    if (request.url.path.contains('/create')) {
      return http.Response(
        jsonEncode({
          'success': !failCreate,
          'error': 'fixture create failure',
          'detail': 'Added fixture',
        }),
        200,
      );
    }
    if (request.url.path.endsWith('/requestdl')) {
      return http.Response(
        '{"success":true,"data":"https://example.test/video.mkv"}',
        200,
      );
    }
    throw StateError(
      'Unexpected fixture request ${request.method} ${request.url.path}',
    );
  }

  Future<void> mount(
    WidgetTester tester, {
    bool pushed = false,
    bool picker = false,
    String? query,
    TorboxTorrent? initial,
    void Function(dynamic)? selected,
  }) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    final screen = TorboxDownloadsScreen(
      key: key,
      isPushedRoute: pushed,
      selectSourceMode: picker,
      initialSearchQuery: query,
      initialTorrentToOpen: initial,
      onSourceSelected: selected,
    );
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        theme: ThemeData.dark(),
        home: pushed
            ? const Scaffold(body: Text('Caller'))
            : RepaintBoundary(
                key: const ValueKey('torbox-canvas'),
                child: screen,
              ),
      ),
    );
    if (pushed) {
      navigatorKey.currentState!.push(
        MaterialPageRoute<void>(builder: (_) => screen),
      );
      await tester.pump();
    }
    if (!holdLists) await until(tester, () => member('initialLoad') == false);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
  }

  Future<void> until(WidgetTester tester, bool Function() ready) async {
    for (var i = 0; i < 100 && !ready(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    expect(ready(), isTrue, reason: 'Original TorBox action did not finish');
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 11));
    await tester.pump();
    tester.view.reset();
    expect(tester.takeException(), isNull);
  }
}

Future<void> torboxCase(
  WidgetTester tester,
  Future<void> Function(TorboxFixture) body,
) async {
  SharedPreferences.setMockInitialValues({'torbox_api_key': 'fixture-key'});
  ProfileRuntime.debugReset();
  ProfileRuntime.initializeLegacy();
  SecretVault.debugReset(deviceIdOverride: 'torbox-characterization');
  MainPageBridge.returnToTorrentSearchOnBack = false;
  MainPageBridge.setActiveTab('torbox');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, (call) async => null);
  final f = TorboxFixture();
  await http.runWithClient(() async {
    try {
      await body(f);
    } finally {
      await f.close(tester);
    }
  }, () => MockClient(f.respond));
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, null);
  MainPageBridge.switchTab = null;
  MainPageBridge.setActiveTab(null);
  ProfileRuntime.debugReset();
}
