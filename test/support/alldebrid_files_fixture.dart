import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:debrify/models/series_source.dart';
import 'package:debrify/screens/alldebrid/alldebrid_files_screen.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/secret_vault.dart';
import 'package:debrify/services/storage/alldebrid_storage.dart';
import 'package:debrify/widgets/cloud/cloud_file_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> adMagnet(
  String id, {
  String? name,
  int status = 4,
  String? hash,
}) => {
  'id': id,
  'filename': name ?? 'Library $id',
  'size': 3000,
  'hash': hash ?? 'hash-$id',
  'statusCode': status,
  'status': status == 4 ? 'Ready' : 'Downloading',
  'downloaded': 1500,
};
Map<String, dynamic> adLink(
  String id, {
  bool video = true,
  String host = 'fixture.host',
}) => {
  'link': 'https://locked.test/$id',
  'filename': 'Saved $id.${video ? 'mkv' : 'zip'}',
  'size': 1000,
  'date': 1767225600,
  'host': host,
};
Map<String, dynamic> adFile(String id, {String? name, int size = 1000}) => {
  'n': name ?? '$id.mkv',
  's': size,
  'l': 'https://locked.test/file-$id',
};

typedef AdRequest = (String, String, String, String?);
AdRequest adRequest(
  String path, {
  String method = 'POST',
  String body = '',
  String key = 'fixture-key',
}) => (method, 'https://api.alldebrid.com$path', body, 'Bearer $key');
AdRequest adList({String key = 'fixture-key'}) =>
    adRequest('/v4.1/magnet/status', key: key);
AdRequest adLinks({String key = 'fixture-key'}) =>
    adRequest('/v4/user/links', method: 'GET', key: key);
AdRequest adFiles(String id, {String key = 'fixture-key'}) => adRequest(
  '/v4/magnet/files',
  body: Uri(queryParameters: {'id[]': id}).query,
  key: key,
);
AdRequest adUnlock(String link, {String key = 'fixture-key'}) => adRequest(
  '/v4/link/unlock',
  body: Uri(queryParameters: {'link': link}).query,
  key: key,
);

class AdObserver extends NavigatorObserver {
  final popped = <Route<dynamic>>[];
  final pushed = <Route<dynamic>>[];
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    popped.add(route);
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushed.add(route);
  }
}

class AllDebridFixture {
  final key = GlobalKey<State<AllDebridFilesScreen>>();
  final navigatorKey = GlobalKey<NavigatorState>();
  final observer = AdObserver();
  final requests = <http.Request>[];
  final clipboard = <String>[];
  String clipboardText = '';
  List<Map<String, dynamic>> magnets = [
    adMagnet('z9'),
    adMagnet('a2'),
    adMagnet('m5'),
  ];
  List<Map<String, dynamic>> links = [
    adLink('w8'),
    adLink('b3', video: false),
    adLink('n6'),
  ];
  List<Map<String, dynamic>> files = [
    {
      'n': 'Root',
      'e': [
        adFile('z9', name: 'A.S02E01.mkv'),
        adFile('a2', name: 'C.S01E01.mkv'),
        adFile('m5', name: 'B.S01E02.mkv'),
        adFile('q7', name: 'Notes.txt'),
      ],
    },
  ];
  final held = <String, Completer<http.Response>>{};
  final failures = <String>{};
  final unlockUrls = <String, String>{};
  String defaultUnlockUrl =
      ''; // Playback fixtures stop before the native handoff.
  void Function(http.Request)? onRequest;
  bool pushed = false, picker = false;
  String? query;
  Future<void> Function(SeriesSource)? selected;

  Map<String, Object?> get access =>
      allDebridFilesTestAccess(key.currentState!);
  dynamic member(String name) => access[name];
  List<AdRequest> get log => requests
      .map(
        (r) => (r.method, r.url.toString(), r.body, r.headers['Authorization']),
      )
      .toList();
  List<String> get ids =>
      (member('magnets') as List).map((dynamic m) => m.id as String).toList();
  ScrollController get scroll => member('scrollController') as ScrollController;
  FocusNode focus(String name) => member(name) as FocusNode;
  static http.Response success(Map<String, dynamic> data) =>
      http.Response(jsonEncode({'status': 'success', 'data': data}), 200);
  static http.Response failure() => http.Response(
    '{"status":"error","error":{"message":"fixture failure"}}',
    200,
  );
  http.Response listResponse() => success({'magnets': magnets});
  http.Response linksResponse() => success({'links': links});
  http.Response filesResponse() => success({
    'magnets': [
      {'id': 'fixture', 'files': files},
    ],
  });

  Future<http.Response> respond(http.Request r) async {
    expectSync(r.url.host, 'api.alldebrid.com');
    requests.add(r);
    onRequest?.call(r);
    final path = r.url.path;
    final form = r.method == 'GET' ? <String, String>{} : r.bodyFields;
    final identity =
        '$path|${form['link'] ?? form['links[]'] ?? form['id'] ?? form['id[]'] ?? ''}';
    final gate = held[identity] ?? held[path];
    if (gate != null) {
      return gate.future;
    }
    if (failures.contains(identity) || failures.contains(path)) {
      return failure();
    }
    switch (path) {
      case '/v4.1/magnet/status':
        return listResponse();
      case '/v4/user/links':
        return linksResponse();
      case '/v4/magnet/files':
        return filesResponse();
      case '/v4/link/unlock':
        return success({'link': unlockUrls[form['link']] ?? defaultUnlockUrl});
      case '/v4/magnet/delete':
        magnets.removeWhere((m) => m['id'] == form['id']);
        return success({});
      case '/v4/user/links/delete':
        links.removeWhere((l) => l['link'] == form['links[]']);
        return success({});
      case '/v4/magnet/upload':
        return success({
          'magnets': [
            {
              'id': 'upload-z7',
              'hash': 'uploaded-hash',
              'name': 'Uploaded',
              'ready': true,
            },
          ],
        });
      case '/v4/user/links/save':
        return success({});
      default:
        throw StateError(
          'Unexpected AllDebrid request ${r.method} ${r.url} ${r.body}',
        );
    }
  }

  Widget screen() => RepaintBoundary(
    key: const ValueKey('alldebrid-canvas'),
    child: AllDebridFilesScreen(
      key: key,
      isPushedRoute: pushed,
      initialSearchQuery: query,
      selectSourceMode: picker,
      onSourceSelected: selected,
    ),
  );
  Future<void> mount(
    WidgetTester t, {
    bool pushed = false,
    bool picker = false,
    String? query,
    Future<void> Function(SeriesSource)? selected,
  }) async {
    this.pushed = pushed;
    this.picker = picker;
    this.query = query;
    this.selected = selected;
    t.view.physicalSize = const Size(1000, 800);
    t.view.devicePixelRatio = 1;
    await t.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        navigatorObservers: [observer],
        theme: ThemeData(
          brightness: Brightness.dark,
          fontFamily: 'AllDebridFixtureInter',
        ),
        home: pushed ? const Scaffold(body: Text('Caller')) : screen(),
      ),
    );
    if (pushed) {
      navigatorKey.currentState!.push(
        MaterialPageRoute<void>(builder: (_) => screen()),
      );
      await t.pump();
    }
    if (!held.containsKey('/v4.1/magnet/status')) {
      await until(
        t,
        () => key.currentState != null && member('loading') == false,
      );
    }
    if (MainPageBridge.focusAllDebridWebDownloads != null &&
        member('selectedView') == 'webDownloads' &&
        !held.containsKey('/v4/user/links')) {
      await until(t, () => member('loadingLinks') == false);
    }
    await t.pump(const Duration(milliseconds: 600));
    await t.pump();
  }

  Future<void> update(
    WidgetTester t, {
    String? query,
    Future<void> Function(SeriesSource)? selected,
  }) async {
    this.query = query;
    this.selected = selected;
    await t.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        navigatorObservers: [observer],
        theme: ThemeData(
          brightness: Brightness.dark,
          fontFamily: 'AllDebridFixtureInter',
        ),
        home: screen(),
      ),
    );
    await t.pump();
  }

  Future<void> until(WidgetTester t, bool Function() ready) async {
    for (var i = 0; i < 200 && !ready(); i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await t.pump();
    }
    expect(ready(), isTrue, reason: 'Original AllDebrid action did not finish');
  }

  Future<void> tap(WidgetTester t, Finder finder) async {
    await t.ensureVisible(finder);
    await t.tap(finder);
    await t.pump();
    await t.pump(const Duration(milliseconds: 600));
  }

  Future<void> web(WidgetTester t) async {
    await tap(t, find.text('Web Downloads'));
    if (!held.containsKey('/v4/user/links')) {
      await until(t, () => member('loadingLinks') == false);
    }
  }

  Future<void> torrents(WidgetTester t) async {
    await tap(t, find.text('Torrent Downloads'));
  }

  Finder row(String title) =>
      find.byWidgetPredicate((w) => w is CloudFileRow && w.title == title);
  Future<void> open(WidgetTester t, {String id = 'z9'}) async {
    await tap(t, find.text('Library $id'));
    if (!held.containsKey('/v4/magnet/files')) {
      await until(t, () => member('loadingFiles') == false);
    }
  }

  Future<void> action(WidgetTester t, String title, String label) async {
    final target = row(title);
    await t.ensureVisible(target);
    final more = find.descendant(
      of: target,
      matching: find.byTooltip('More options'),
    );
    await tap(t, more);
    await tap(t, find.text(label).last);
  }

  Future<void> search(WidgetTester t, String text, {bool file = false}) async {
    if (member(file ? 'fileSearchActive' : 'searchActive') != true) {
      await tap(
        t,
        find.byTooltip(
          file
              ? 'Search files'
              : member('selectedView') == 'webDownloads'
              ? 'Search links'
              : 'Search magnets',
        ),
      );
    }
    await t.enterText(find.byType(TextField), text);
    await t.pump();
  }

  Future<void> changeCredential(WidgetTester t, String value) async {
    var done = false;
    Object? failure;
    AllDebridStorage.saveAllDebridApiKey(value).then(
      (_) {
        done = true;
      },
      onError: (Object error) {
        failure = error;
        done = true;
      },
    );
    await until(t, () => done);
    expect(failure, isNull);
  }

  Future<void> close(WidgetTester t) async {
    await t.pumpWidget(const SizedBox.shrink());
    await t.pump(const Duration(seconds: 4));
    t.view.reset();
    expect(t.takeException(), isNull);
  }
}

Future<void> allDebridCase(
  WidgetTester t,
  Future<void> Function(AllDebridFixture) body, {
  String? credential = 'fixture-key',
}) async {
  // A fixture-private Inter family keeps real menu text metrics deterministic and
  // avoids Ahem-only overflow without swallowing any framework exception.
  final font = FontLoader('AllDebridFixtureInter');
  for (final name in ['Inter-Regular.ttf']) {
    font.addFont(
      Future.value(
        ByteData.sublistView(File('assets/fonts/$name').readAsBytesSync()),
      ),
    );
  }
  await font.load();
  SharedPreferences.setMockInitialValues({
    if (credential != null) 'alldebrid_api_key': credential,
  });
  ProfileRuntime.debugReset();
  ProfileRuntime.initializeLegacy();
  SecretVault.debugReset(deviceIdOverride: 'alldebrid-characterization');
  MainPageBridge.focusAllDebridWebDownloads = null;
  MainPageBridge.getAndClearAllDebridFocusWebDownloads();
  MainPageBridge.setActiveTab('alldebrid');
  MainPageBridge.setActiveTvTab(12);
  final f = AllDebridFixture();
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
    MainPageBridge.focusAllDebridWebDownloads = null;
    MainPageBridge.getAndClearAllDebridFocusWebDownloads();
    MainPageBridge.setActiveTab(null);
    ProfileRuntime.debugReset();
    SecretVault.debugReset();
  }
}
