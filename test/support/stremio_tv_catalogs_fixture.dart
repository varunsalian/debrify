import 'dart:convert';

import 'package:debrify/screens/stremio_tv/widgets/stremio_tv_local_catalogs_dialog.dart';
import 'package:debrify/services/mdblist/mdblist_service.dart';
import 'package:debrify/services/secret_vault.dart';
import 'package:debrify/services/storage/mdblist_storage.dart';
import 'package:debrify/services/storage/stremio_catalog_storage.dart';
import 'package:debrify/services/storage/trakt_storage.dart';
import 'package:debrify/services/storage/tv_display_storage.dart';
import 'package:debrify/services/trakt/trakt_service.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'profile_fixture.dart';

export 'package:debrify/screens/stremio_tv/widgets/stremio_tv_local_catalogs_dialog.dart';
export 'package:debrify/services/storage/stremio_catalog_storage.dart';

Map<String, dynamic> catalog({
  String id = 'cat',
  String name = 'Cinema',
  String? type = 'movie',
  int count = 3,
  Map<String, dynamic> meta = const {},
}) => {
  'id': id,
  'name': name,
  if (type != null) 'type': type,
  'items': [
    for (var i = 0; i < count; i++)
      {'id': 'tt$i', 'name': 'Item $i', 'type': type ?? 'movie'},
  ],
  ...meta,
};
Map<String, dynamic> traktItem(
  String id, {
  bool series = false,
  String? year = '2020',
  List<String> genres = const ['science-fiction'],
}) => {
  'type': series ? 'show' : 'movie',
  (series ? 'show' : 'movie'): {
    'title': 'Title $id',
    'ids': {'imdb': id},
    'year': year,
    'overview': 'Overview $id',
    'rating': 8.46,
    'genres': genres,
    'images': {
      'poster': ['https://poster.test/$id'],
      'fanart': ['https://fanart.test/$id'],
    },
  },
};
List<Map<String, dynamic>> get mixedTrakt => [
  traktItem('tt10'),
  traktItem('tt20', series: true),
];
Map<String, dynamic> get mdblistItems => {
  'movies': [
    {'imdb_id': 'tt10', 'title': 'MDB movie', 'mediatype': 'movie'},
  ],
  'shows': [
    {'imdb_id': 'tt20', 'title': 'MDB show', 'mediatype': 'show'},
  ],
};
http.Response response(Object body, {int status = 200}) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

/// Initialized in a suite-owned zone BEFORE touching either MDBList singleton.
/// The handler changes per test; the captured client stays alive until tearDownAll.
class CatalogNetwork {
  final requests = <http.Request>[];
  Future<http.Response> Function(http.Request) handler = (r) async =>
      response([]);
  late final MockClient client = MockClient((r) {
    requests.add(r);
    return handler(r);
  });
  void reset() {
    requests.clear();
    handler = (r) async => response([]);
  }

  Future<T> run<T>(Future<T> Function() action) =>
      http.runWithClient(action, () => client);
  void install() => http.runWithClient(() {
    MdblistService.instance.resetProfileScope();
  }, () => client);
}

class CatalogPicker extends FilePicker {
  FilePickerResult? result;
  Object? error;
  FileType? type;
  bool? withData;
  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = true,
    int compressionQuality = 30,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async {
    this.type = type;
    this.withData = withData;
    if (error != null) throw error!;
    return result;
  }

  void file(String name, {int? size, List<int>? bytes}) {
    result = FilePickerResult([
      PlatformFile(
        name: name,
        size: size ?? bytes?.length ?? 0,
        bytes: bytes == null ? null : Uint8List.fromList(bytes),
      ),
    ]);
  }
}

class CatalogObserver extends NavigatorObserver {
  final pushed = <Route<dynamic>>[];
  final popped = <Route<dynamic>>[];
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      pushed.add(route);
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      popped.add(route);
}

class CatalogFixture {
  final profiles = ProfileFixture();
  final picker = CatalogPicker();
  final observer = CatalogObserver();
  FilePicker? savedPicker;
  late bool savedKeyboard, savedTv, savedTvOS;
  late BuildContext context;
  Object? result = 'pending';
  Future<void> open() async {
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SecretVault.debugReset(deviceIdOverride: 'stremio-catalogs-fixture');
    try {
      savedPicker = FilePicker.platform;
    } on Error {
      savedPicker = null;
    }
    FilePicker.platform = picker;
    savedKeyboard = TvDisplayStorage.tvKeyboardEnabledCached;
    savedTv = PlatformUtil.isAndroidTvCached;
    savedTvOS = PlatformUtil.isTvOS;
    PlatformUtil.debugSetAndroidTvCached(false);
    PlatformUtil.debugSetTvOS(false);
    TvDisplayStorage.tvKeyboardEnabledCached = false;
    await profiles.open();
    TraktService.instance.resetProfileScope();
    MdblistService.instance.resetProfileScope();
  }

  Future<void> seed(List<Map<String, dynamic>> values) =>
      StremioCatalogStorage.setStremioTvLocalCatalogs(values);
  Future<List<Map<String, dynamic>>> rows() =>
      StremioCatalogStorage.getStremioTvLocalCatalogs();
  Future<void> auth() async {
    await TraktStorage.setTraktSession(
      accessToken: 'fixture-access',
      refreshToken: 'fixture-refresh',
      expiryMs: DateTime.now()
          .add(const Duration(days: 2))
          .millisecondsSinceEpoch,
    );
    await TraktStorage.setTraktUsername('fixture-owner');
    await MdblistStorage.saveMdblistApiKey('fixture-mdblist');
  }

  void tv(bool enabled) {
    PlatformUtil.debugSetAndroidTvCached(enabled);
    TvDisplayStorage.tvKeyboardEnabledCached = enabled;
  }

  Future<void> close() async {
    TraktService.instance.resetProfileScope();
    MdblistService.instance.resetProfileScope();
    await profiles.close();
    SecretVault.debugReset();
    FilePicker.platform = savedPicker ?? CatalogPicker();
    PlatformUtil.debugSetAndroidTvCached(savedTv);
    PlatformUtil.debugSetTvOS(savedTvOS);
    TvDisplayStorage.tvKeyboardEnabledCached = savedKeyboard;
  }

  Future<void> mount(
    WidgetTester tester, {
    Size size = const Size(1280, 800),
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [observer],
        builder: (context, child) =>
            AppThemeScope(theme: AppThemes.legacy, child: child!),
        home: Scaffold(
          body: Builder(
            builder: (ctx) {
              context = ctx;
              return const SizedBox.expand();
            },
          ),
        ),
      ),
    );
  }

  Future<void> editor(
    WidgetTester tester, {
    String id = 'cat',
    String type = 'movie',
  }) async {
    StremioTvLocalCatalogEditorDialog.show(
      context,
      catalogId: id,
      catalogType: type,
    ).then((v) => result = v);
    await pumpCatalog(tester);
  }

  Future<void> manage(WidgetTester tester) async {
    StremioTvLocalCatalogsDialog.show(context).then((v) => result = v);
    await pumpCatalog(tester);
  }

  Future<void> dialog(
    WidgetTester tester,
    Future<bool> Function(BuildContext) show,
  ) async {
    show(context).then((v) => result = v);
    await pumpCatalog(tester);
  }
}

Future<void> pumpCatalog(WidgetTester tester, {int rounds = 10}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 15)),
    );
    await tester.pump(const Duration(milliseconds: 80));
  }
}

Future<void> keyCatalog(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(
    key,
    physicalKey:
        key == LogicalKeyboardKey.goBack ||
            key == LogicalKeyboardKey.browserBack
        ? PhysicalKeyboardKey.escape
        : null,
    platform: key == LogicalKeyboardKey.browserBack ? 'web' : 'android',
  );
  await pumpCatalog(tester, rounds: 4);
}

FocusNode catalogFocus(String label) => FocusManager
    .instance
    .rootScope
    .descendants
    .singleWhere((n) => n.debugLabel == label);
Future<void> focusCatalog(WidgetTester tester, String label) async {
  catalogFocus(label).requestFocus();
  await tester.pump();
}

Future<void> removeCatalogItem(
  WidgetTester tester,
  int index, {
  bool confirm = true,
}) async {
  await focusCatalog(tester, 'localCatalogEditorRemove$index');
  await keyCatalog(tester, LogicalKeyboardKey.select);
  await tester.tap(
    find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text(confirm ? 'Remove' : 'Cancel'),
    ),
  );
  await pumpCatalog(tester);
}

Future<void> catalogCase(
  WidgetTester tester,
  Future<void> Function(CatalogFixture) body,
) async {
  final f = CatalogFixture();
  await tester.runAsync(f.open);
  try {
    await body(f);
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
    await pumpCatalog(tester, rounds: 2);
    await tester.runAsync(f.close);
  }
}
