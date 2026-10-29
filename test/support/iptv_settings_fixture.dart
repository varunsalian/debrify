import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/models/profiles/connection_resource.dart';
import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/screens/settings/iptv_settings_page.dart';
import 'package:debrify/services/debrify_tv_database.dart';
import 'package:debrify/services/iptv_catalog_db.dart';
import 'package:debrify/services/iptv_catalog_refresh_service.dart';
import 'package:debrify/services/iptv_media_store.dart';
import 'package:debrify/services/iptv_service.dart';
import 'package:debrify/services/profiles/connection_resource_service.dart';
import 'package:debrify/services/profiles/device_key_provider.dart';
import 'package:debrify/services/profiles/profile_authorization.dart';
import 'package:debrify/services/profiles/profile_bootstrap.dart';
import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/profiles/profile_registry.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/storage/iptv_favorites_storage.dart';
import 'package:debrify/services/storage/iptv_playlist_storage.dart';
import 'package:debrify/services/xtream_codes_service.dart';
import 'package:debrify/utils/app_storage.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'iptv_settings_held_boundaries.dart';

const iptvFixtureM3u =
    '#EXTM3U\n#EXTINF:-1 group-title="News",Café\n'
    'https://fixture.invalid/live.ts\n';

IptvPlaylist iptvFixtureSource(
  String id, {
  bool local = false,
  bool xtream = false,
}) => IptvPlaylist(
  id: id,
  name: 'Source $id',
  url: local || xtream ? '' : 'https://fixture.invalid/$id.m3u',
  content: local ? iptvFixtureM3u : null,
  serverUrl: xtream ? 'https://fixture.invalid/panel' : null,
  username: xtream ? 'user' : null,
  password: xtream ? 'pass' : null,
  epgUrl: 'https://fixture.invalid/guide.xml',
  addedAt: DateTime.utc(2026, 1, 2),
);

final class IptvSettingsFilePicker extends FilePicker {
  final List<({FileType type, bool multiple, bool data})> calls = [];
  final List<Completer<FilePickerResult?>> held = [];
  FilePickerResult? next;
  bool hold = false;

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
    calls.add((type: type, multiple: allowMultiple, data: withData));
    if (hold) {
      final waiter = Completer<FilePickerResult?>();
      held.add(waiter);
      return waiter.future;
    }
    return next;
  }

  void file(String name, Uint8List? bytes, {String? path}) {
    next = FilePickerResult([
      PlatformFile(
        name: name,
        size: bytes?.length ?? 0,
        bytes: bytes,
        path: path,
      ),
    ]);
  }
}

final class IptvSettingsFixture {
  final key = GlobalKey();
  final navigatorKey = GlobalKey<NavigatorState>();
  final requests = <({String method, Uri url})>[];
  final picker = IptvSettingsFilePicker();
  final cipher = IptvHeldCipher();
  final outstanding = <Future<void>>[];
  final catalogPaths = <String, String>{};
  late Directory directory;
  late ProfileRegistry registry;
  late ConnectionResourceService resources;
  late String ownerId;
  late String incomingId;
  FilePicker? oldPicker;
  Completer<http.Response>? heldHttp;
  String? holdAction;
  String? failAction;
  String m3u = iptvFixtureM3u;
  bool authSuccess = true;
  int m3uStatus = 200;
  String? connectionId;
  bool singleProfile = false;
  State get state => key.currentState!;
  Map<String, dynamic> get access => iptvSettingsTestAccess(state);
  dynamic member(String name) => access[name];
  List<IptvPlaylist> get playlists =>
      (member('playlists') as List).cast<IptvPlaylist>();
  List<IptvListMeta> get lists =>
      (member('customLists') as List).cast<IptvListMeta>();

  Future<void> initialize({
    List<IptvPlaylist> sources = const [],
    Map<String, Object> preferences = const {},
    UserProfileRole role = UserProfileRole.admin,
  }) async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await IptvCatalogRefreshService.instance.debugSettle();
    IptvCatalogRefreshService.instance.dispose();
    await DebrifyTvDatabase.instance.closeScope();
    await IptvCatalogDb.closeScope();
    IptvMediaStore.debugResetMigration();
    SharedPreferences.setMockInitialValues(preferences);
    ProfileRuntime.debugReset();
    DeviceKeyProvider.debugReset();
    directory = await Directory.systemTemp.createTemp('iptv-settings-case-');
    AppStorage.debugOverride(
      documents: directory,
      support: directory,
      cache: directory,
    );
    // Use the production profile paths. Each handoff closes both owned DBs;
    // a global directory override never aliases one profile to another.
    IptvCatalogDb.debugDirectoryOverride = null;
    registry = await ProfileRegistry.open(
      path: '${directory.path}/profiles.db',
    );
    ownerId = (await registry.createProfile(name: 'Owner', role: role)).id;
    incomingId = singleProfile
        ? ownerId
        : (await registry.createProfile(
            name: 'Incoming',
            role: UserProfileRole.admin,
          )).id;
    await registry.commitBootstrap(
      activeProfileId: ownerId,
      migratedLegacyInstall: false,
    );
    await cipher.initialize();
    resources = ConnectionResourceService(registry: registry, cipher: cipher);
    DeviceKeyProvider.debugInstallCipher(cipher);
    ProfileBootstrap.debugInstallRegistry(registry);
    ProfileRuntime.initializeCommitted(
      ProfileScope(profileId: ownerId, dataGeneration: 1, sessionEpoch: 1),
    );
    await (await ProfilePreferences.instance()).setInt(
      IptvCatalogRefreshService.intervalKey,
      0,
    );
    await IptvPlaylistStorage.setIptvPlaylists(sources);
    await IptvCatalogDb.open();
    catalogPaths[ownerId] = IptvCatalogDb.path;
    await IptvFavoritesStorage.getIptvLists();
    IptvService.debugDownloadDirectoryOverride = directory.path;
    XtreamCodesService.debugDownloadDirectory = directory.path;
    IptvService.instance.clearCache();
    XtreamCodesService.instance.clearCache();
    try {
      oldPicker = FilePicker.platform;
    } catch (_) {
      // No native picker is registered in the widget-test isolate.
    }
    FilePicker.platform = picker;
    PlatformUtil.debugSetAndroidTvCached(false);
    PlatformUtil.debugSetTvOS(false);
  }

  Future<http.Response> respond(http.Request request) async {
    requests.add((method: request.method, url: request.url));
    final action =
        request.url.queryParameters['action'] ??
        (request.url.path.endsWith('.m3u') ? 'm3u' : 'login');
    if (action == holdAction && heldHttp != null) return heldHttp!.future;
    if (action == failAction) return http.Response('denied', 403);
    if (request.url.path.endsWith('.m3u')) {
      return http.Response(
        m3u,
        m3uStatus,
        headers: {'content-type': 'application/x-mpegurl; charset=utf-8'},
      );
    }
    if (request.url.path.endsWith('player_api.php')) {
      if (!request.url.queryParameters.containsKey('action')) {
        return http.Response(
          jsonEncode({
            'user_info': {
              'auth': authSuccess ? 1 : 0,
              'status': authSuccess ? 'Active' : 'Disabled',
            },
          }),
          200,
        );
      }
      if (action.endsWith('_categories')) {
        return http.Response(
          '[{"category_id":"7","category_name":"News"}]',
          200,
        );
      }
      if (action == 'get_series') {
        return http.Response(
          '[{"series_id":3,"name":"Series","category_id":"7"}]',
          200,
        );
      }
      return http.Response(
        '[{"stream_id":9,"name":"Channel","category_id":"7"}]',
        200,
      );
    }
    if (request.url.path.contains('/live/')) return http.Response('', 200);
    throw StateError(
      'Unexpected IPTV fixture request ${request.method} ${request.url}',
    );
  }

  Future<void> mount(
    WidgetTester tester, {
    Size size = const Size(1200, 800),
    bool add = false,
    bool wait = true,
    // Wraps the app, e.g. in the root ProviderScope the real app provides.
    Widget Function(Widget app)? wrap,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    final app = RepaintBoundary(
      key: const ValueKey('iptv-settings-canvas'),
      child: MaterialApp(
        navigatorKey: navigatorKey,
        theme: ThemeData.dark(),
        home: IptvSettingsPage(key: key, openAddSource: add),
      ),
    );
    await tester.pumpWidget(wrap == null ? app : wrap(app));
    if (wait) await until(tester, () => member('loading') == false);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
  }

  Future<void> until(WidgetTester tester, bool Function() ready) async {
    for (var i = 0; i < 160 && !ready(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(ready(), isTrue, reason: 'Original IPTV action did not finish');
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.runAsync(() => tester.tap(finder));
  }

  Future<void> frames(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> action(WidgetTester tester, Future<void> Function() body) async {
    late Future<void> work;
    var done = false;
    await tester.runAsync(() async {
      work = body().whenComplete(() => done = true);
      outstanding.add(work);
    });
    await until(tester, () => done);
    await tester.runAsync(() => work);
    await frames(tester);
  }

  Future<void> switchProfile(String id, {bool close = true}) async {
    if (close) {
      await IptvCatalogRefreshService.instance.debugSettle();
      await DebrifyTvDatabase.instance.closeScope();
      await IptvCatalogDb.closeScope();
      IptvMediaStore.debugResetMigration();
    }
    final old = ProfileRuntime.scope.value!;
    ProfileRuntime.scope.value = ProfileScope(
      profileId: id,
      dataGeneration: 1,
      sessionEpoch: old.sessionEpoch + 1,
    );
    await (await ProfilePreferences.instance()).setInt(
      IptvCatalogRefreshService.intervalKey,
      0,
    );
    if (close) {
      await IptvCatalogDb.open();
      catalogPaths[id] = IptvCatalogDb.path;
      await IptvFavoritesStorage.getIptvLists();
      if (catalogPaths.length > 1) {
        expect(catalogPaths.values.toSet().length, catalogPaths.length);
      }
    }
  }

  Future<List<String>> catalogKeysOnDisk(String profileId) async {
    final path = catalogPaths[profileId]!;
    final db = await openDatabase(path, readOnly: true, singleInstance: false);
    try {
      return (await db.query(
        'catalogs',
        columns: ['catalog_key'],
      )).map((r) => r['catalog_key'] as String).toList();
    } finally {
      await db.close();
    }
  }

  Future<void> grantSource() async {
    final target = (await IptvPlaylistStorage.getIptvPlaylists()).first;
    connectionId = target.connectionResourceId!;
    await resources.grant(
      actor: await ProfileAuthorizationContext.capture(registry),
      targetProfileId: incomingId,
      resourceId: connectionId!,
      permissions: {ResourcePermission.use},
    );
  }

  Future<List<IptvPlaylist>> stored(String id) async {
    final live = ProfileRuntime.scope.value!;
    return ProfileRuntime.withCapturedScope(
      ProfileScope(
        profileId: id,
        dataGeneration: 1,
        sessionEpoch: live.sessionEpoch,
      ),
      () => IptvPlaylistStorage.getIptvPlaylists(forSettings: true),
    );
  }

  Future<void> close(WidgetTester tester) async {
    if (cipher.release != null && !cipher.release!.isCompleted) {
      cipher.release!.complete();
    }
    for (final held in picker.held) {
      if (!held.isCompleted) held.complete(null);
    }
    if (heldHttp != null && !heldHttp!.isCompleted) {
      heldHttp!.complete(http.Response('denied', 403));
    }
    navigatorKey.currentState?.popUntil((route) => route.isFirst);
    await frames(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    await frames(tester);
    await tester.runAsync(() async {
      await Future.wait(
        outstanding.map((work) => work.catchError((Object _) {})),
      );
      await IptvCatalogRefreshService.instance.debugSettle();
      IptvCatalogRefreshService.instance.dispose();
      await DebrifyTvDatabase.instance.closeScope();
      await IptvCatalogDb.closeScope();
      IptvMediaStore.debugResetMigration();
      IptvCatalogDb.debugDirectoryOverride = null;
      IptvService.debugDownloadDirectoryOverride = null;
      XtreamCodesService.debugDownloadDirectory = null;
      if (oldPicker != null) FilePicker.platform = oldPicker!;
      ProfileRuntime.debugReset();
      ProfileBootstrap.debugInstallRegistry(null);
      DeviceKeyProvider.debugReset();
      AppStorage.debugReset();
      await registry.close();
      await directory.delete(recursive: true);
    });
    PlatformUtil.debugSetAndroidTvCached(null);
    PlatformUtil.debugSetTvOS(null);
    tester.view.reset();
  }
}

Future<void> iptvSettingsCase(
  WidgetTester tester,
  Future<void> Function(IptvSettingsFixture) body, {
  List<IptvPlaylist> sources = const [],
  Map<String, Object> preferences = const {},
  UserProfileRole role = UserProfileRole.admin,
  bool singleProfile = false,
}) async {
  final fixture = IptvSettingsFixture()..singleProfile = singleProfile;
  await tester.runAsync(
    () => fixture.initialize(
      sources: sources,
      preferences: preferences,
      role: role,
    ),
  );
  try {
    await http.runWithClient(
      () => body(fixture),
      () => MockClient(fixture.respond),
    );
  } finally {
    await fixture.close(tester);
  }
}
