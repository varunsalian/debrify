import 'dart:async';
import 'dart:convert';
import 'package:debrify/models/rd_torrent.dart';
import 'package:debrify/models/debrid_download.dart';
import 'package:debrify/screens/debrid_downloads_screen.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/secret_vault.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

// January UTC dates force the original absolute-date branch (> seven days).
Map<String, dynamic> debridTorrent(String id, {bool downloaded = true}) => {
  'id': id,
  'filename': 'Library $id',
  'hash': 'hash-$id',
  'bytes': 3000,
  'host': 'fixture',
  'split': 0,
  'progress': 100,
  'status': downloaded ? 'downloaded' : 'waiting_files_selection',
  'added': '2026-01-01T00:00:00Z',
  'links': [
    'https://example.test/restricted/$id/0',
    'https://example.test/restricted/$id/1',
    'https://example.test/restricted/$id/2',
  ],
};
Map<String, dynamic> debridDownload(String id, {bool playable = true}) => {
  'id': id,
  'filename': playable ? 'Download $id.mkv' : 'Archive $id.zip',
  'mimeType': 'video/x-matroska',
  'filesize': 1000,
  'link': 'https://example.test/restricted/$id',
  'host': 'fixture',
  'chunks': 1,
  'download': 'https://example.test/download/$id',
  'streamable': playable ? 1 : 0,
  'generated': '2026-01-01T00:00:00Z',
};

class DebridFixture {
  final key = GlobalKey<State<DebridDownloadsScreen>>();
  final navigatorKey = GlobalKey<NavigatorState>();
  final requests = <http.Request>[];
  final clipboard = <String>[];
  List<Map<String, dynamic>> torrents = [
    debridTorrent('z9'),
    debridTorrent('a2'),
    debridTorrent('m5'),
  ];
  List<Map<String, dynamic>> downloads = [
    debridDownload('w8'),
    debridDownload('b3'),
    debridDownload('n6'),
  ];
  Map<int, List<Map<String, dynamic>>>? allTorrentPages;
  Map<int, List<Map<String, dynamic>>>? allDownloadPages;
  String? failDelete;
  bool failLists = false,
      fullPages = false,
      rar = false,
      noLinks = false,
      emptyFolder = false;
  bool holdLists = false, holdDelete = false, holdAll = false;
  Completer<http.Response>? pending;
  int deleteCount = 0;
  Map<String, Object?> get access =>
      debridDownloadsTestAccess(key.currentState!);
  dynamic member(String name) => access[name];
  RDTorrent torrent(String id) => RDTorrent.fromJson(debridTorrent(id));
  DebridDownload download(String id) =>
      DebridDownload.fromJson(debridDownload(id));
  List<http.Request> get deletes =>
      requests.where((r) => r.method == 'DELETE').toList();
  Map<String, dynamic> info(String id) => {
    ...debridTorrent(id),
    'files': emptyFolder
        ? []
        : [
            {
              'id': 71,
              'path': rar ? '/Archive.rar' : '/Zebra.mkv',
              'name': 'Zebra.mkv',
              'bytes': 1000,
              'selected': 1,
            },
            {
              'id': 4,
              'path': '/Alpha.mkv',
              'name': 'Alpha.mkv',
              'bytes': 1000,
              'selected': 1,
            },
            if (!rar)
              {
                'id': 39,
                'path': '/Nested/Show.S02E03.mkv',
                'name': 'Show.S02E03.mkv',
                'bytes': 1000,
                'selected': 1,
              },
          ],
    'links': noLinks
        ? <String>[]
        : rar
        ? ['https://example.test/restricted/$id/0']
        : debridTorrent(id)['links'],
  };
  Future<http.Response> respond(http.Request r) async {
    requests.add(r);
    final path = r.url.path.replaceFirst('/rest/1.0', '');
    if (r.method == 'GET' && (path == '/torrents' || path == '/downloads')) {
      final page = int.parse(r.url.queryParameters['page'] ?? '1');
      final limit = int.parse(r.url.queryParameters['limit'] ?? '100');
      if (holdLists || holdAll && limit == 1000) return pending!.future;
      if (failLists) return http.Response('fixture failure', 500);
      final allPages = path == '/torrents' ? allTorrentPages : allDownloadPages;
      final rows = path == '/torrents' ? torrents : downloads;
      return http.Response(
        jsonEncode(
          limit == 1000 && allPages != null
              ? allPages[page] ?? []
              : page == 1
              ? rows
              : fullPages
              ? [
                  for (var i = 0; i < limit; i++)
                    path == '/torrents'
                        ? debridTorrent('page-$page-$i')
                        : debridDownload('page-$page-$i'),
                ]
              : [],
        ),
        200,
      );
    }
    if (r.method == 'DELETE') {
      deleteCount++;
      final id = path.split('/').last;
      if (holdDelete && deleteCount == 1) return pending!.future;
      if (id == failDelete) return http.Response('fixture delete failure', 500);
      (path.startsWith('/torrents/') ? torrents : downloads).removeWhere(
        (row) => row['id'] == id,
      );
      return http.Response('', 204);
    }
    if (path.startsWith('/torrents/info/')) {
      return http.Response(jsonEncode(info(path.split('/').last)), 200);
    }
    if (path == '/unrestrict/link') {
      return http.Response(
        jsonEncode({
          'id': 'new-ddl',
          'download': 'https://example.test/unrestricted.mkv',
          'filename': 'Fixture.mkv',
          'mimeType': 'video/x-matroska',
          'filesize': 1000,
          'streamable': 1,
        }),
        200,
      );
    }
    if (path == '/torrents/addMagnet') {
      return http.Response(
        '{"id":"new-torrent","uri":"https://example.test/info"}',
        201,
      );
    }
    if (path.startsWith('/torrents/selectFiles/')) {
      return http.Response('', 204);
    }
    throw StateError('Unexpected original-code fixture ${r.method} $path');
  }

  Future<void> mount(
    WidgetTester t, {
    bool pushed = false,
    bool picker = false,
    String? query,
    RDTorrent? initial,
    void Function(dynamic)? selected,
  }) async {
    t.view.physicalSize = const Size(1000, 800);
    t.view.devicePixelRatio = 1;
    final screen = DebridDownloadsScreen(
      key: key,
      isPushedRoute: pushed,
      selectSourceMode: picker,
      initialSearchQuery: query,
      initialTorrentForOptions: initial,
      onSourceSelected: selected,
    );
    await t.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        theme: ThemeData.dark(),
        home: pushed
            ? const Scaffold(body: Text('Caller'))
            : RepaintBoundary(
                key: const ValueKey('debrid-canvas'),
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
    if (!holdLists) {
      await until(
        t,
        () =>
            requests.any((r) => r.url.path.endsWith('/downloads')) &&
            member('isLoadingDownloads') == false,
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
    expect(
      ready(),
      isTrue,
      reason: 'Original Real-Debrid action did not finish',
    );
  }

  Future<void> ddl(WidgetTester t) async {
    await t.tap(find.text('DDL Downloads'));
    await t.pumpAndSettle();
  }

  Future<void> close(WidgetTester t) async {
    await t.pumpWidget(const SizedBox.shrink());
    await t.pump(const Duration(seconds: 11));
    await t.pump();
    t.view.reset();
    expect(t.takeException(), isNull);
  }
}

Future<void> debridCase(
  WidgetTester t,
  Future<void> Function(DebridFixture) body,
) async {
  SharedPreferences.setMockInitialValues({
    'real_debrid_api_key': 'fixture-key',
  });
  ProfileRuntime.debugReset();
  ProfileRuntime.initializeLegacy();
  SecretVault.debugReset(deviceIdOverride: 'debrid-characterization');
  MainPageBridge.returnToTorrentSearchOnBack = false;
  MainPageBridge.setActiveTab('realdebrid');
  final f = DebridFixture();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          f.clipboard.add((call.arguments as Map)['text'] as String);
        }
        if (call.method == 'Clipboard.getData') return {'text': ''};
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
    MainPageBridge.setActiveTab(null);
    ProfileRuntime.debugReset();
    SecretVault.debugReset();
  }
}
