import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/models/media_server.dart';
import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/services/media_server_service.dart';
import 'package:debrify/services/profiles/profile_bootstrap.dart';
import 'package:debrify/services/profiles/profile_registry.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/profiles/device_key_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:debrify/models/stremio_tv/stremio_tv_channel.dart';
import 'package:debrify/screens/stremio_tv/stremio_tv_screen.dart';
import 'package:debrify/screens/stremio_tv/widgets/stremio_tv_tuner.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/screens/catalog_item_detail_screen.dart';
import 'package:debrify/services/stremio_service.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/secret_vault.dart';
import 'package:debrify/services/storage/stremio_tv_storage.dart';
import 'package:debrify/services/storage/stremio_catalog_storage.dart';
import 'package:debrify/services/storage/real_debrid_storage.dart';
import 'package:debrify/services/storage/torbox_storage.dart';
import 'package:debrify/services/storage/premiumize_storage.dart';
import 'package:debrify/services/storage/alldebrid_storage.dart';
import 'package:debrify/services/storage/pikpak_storage.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/theme/app_theme_adapter.dart';
import 'package:debrify/theme/legacy_theme_boundary.dart';
import 'package:debrify/theme/premium_looks.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:debrify/utils/app_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const stremioTvCanvas = ValueKey('stremio-tv-original-canvas');

class StremioTvObserver extends NavigatorObserver {
  StremioTvObserver(this.hostKey);
  final GlobalKey hostKey;
  final players = <VideoPlayerScreen>[];
  final details = <CatalogItemDetailScreen>[];
  final events = <String>[];
  final routes = <Route<dynamic>>[];
  void Function(VideoPlayerScreen)? onPlayer;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    routes.add(route);
    if (route is MaterialPageRoute && hostKey.currentContext != null) {
      Widget built = route.builder(hostKey.currentContext!);
      if (built is LegacyThemeBoundary) {
        built = built.child;
      }
      if (built is Builder) {
        built = built.builder(hostKey.currentContext!);
      }
      if (built is VideoPlayerScreen) {
        players.add(built);
        onPlayer?.call(built);
        events.add('player');
        scheduleMicrotask(() {
          if (route.isActive) {
            navigator!.removeRoute(route);
          }
        });
        return;
      }
    }
    if (route is PageRouteBuilder && hostKey.currentContext != null) {
      final content = route.pageBuilder(
        hostKey.currentContext!,
        const AlwaysStoppedAnimation<double>(1),
        const AlwaysStoppedAnimation<double>(0),
      );
      if (content is CatalogItemDetailScreen) {
        details.add(content);
        events.add('detail');
        scheduleMicrotask(() {
          if (route.isActive) {
            navigator!.removeRoute(route);
          }
        });
        return;
      }
    }
    events.add(previousRoute == null ? 'home' : 'route');
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    events.add('pop');
  }
}

/// Drives only production storage, mounted callbacks, HTTP and bridge hooks.
/// Player routes are inspected before their first frame; no player is mounted.
class StremioTvFixture {
  final hostKey = GlobalKey();
  final navigator = GlobalKey<NavigatorState>();
  late final observer = StremioTvObserver(hostKey);
  late final MockClient client = MockClient(respond);
  final requests = <http.Request>[];
  final clipboard = <String>[];
  final probes = <String>[];
  late Directory directory;
  ProfileRegistry? mediaRegistry;
  Future<http.Response> Function(http.Request)? onRequest;
  List<Map<String, dynamic>> streams = [
    {
      'name': 'Fixture',
      'title': 'Original.1080p.mkv',
      'infoHash': 'a' * 40,
      'behaviorHints': {'videoSize': 100000000},
    },
    {
      'name': 'Fixture',
      'title': 'Original.720p.mkv',
      'infoHash': 'b' * 40,
      'behaviorHints': {'videoSize': 100000000},
    },
  ];
  int count = 2;
  int itemCount = 1;
  String type = 'movie';
  bool television = true;
  bool streamAddon = true;
  List<Map<String, dynamic>> addonCatalogs = [];
  bool rdFails = false;
  bool headValid = true;
  int rdAdds = 0;
  int torboxCreates = 70;
  bool torboxReject = false;
  List<String> torboxCached = ['a' * 40, 'b' * 40];
  int allDebridAdds = 0;
  int allDebridRejects = 0;
  final logs = <String>[];
  late DebugPrintCallback originalPrint;
  int discoverHolds = 0;
  Completer<http.Response>? heldUnrestrict;
  bool holdUsed = false;
  final january = DateTime.utc(2026, 1, 2);

  http.Response jsonResponse(Object data, [int status = 200]) => http.Response(
    jsonEncode(data),
    status,
    headers: {'content-type': 'application/json'},
  );
  Future<http.Response> respond(http.Request r) async {
    requests.add(r);
    return onRequest == null ? providerResponse(r) : onRequest!(r);
  }

  Future<http.Response> providerResponse(http.Request r) async {
    final path = r.url.path;
    if (r.url.host == 'media-original.test') {
      if (path.endsWith('AuthenticateByName')) {
        return jsonResponse({
          'User': {'Id': 'original-user'},
          'AccessToken': 'original-token',
          'ServerId': 'original-server',
        });
      }
      if (path.endsWith('System/Info/Public')) {
        return jsonResponse({'Id': 'original-server'});
      }
      if (path.endsWith('System/Info')) {
        return http.Response('', 403);
      }
      if (path.endsWith('Users/original-user')) {
        return jsonResponse({'Id': 'original-user'});
      }
      return jsonResponse({'Items': [], 'TotalRecordCount': 0});
    }
    if (path.endsWith('/manifest.json')) {
      return jsonResponse({
        'id': 'stremio-tv-original',
        'name': 'Original streams',
        'version': '1.0.0',
        'types': ['movie', 'series'],
        'resources': ['stream', 'meta', 'catalog'],
        'catalogs': addonCatalogs,
      });
    }
    if (path.contains('/stream/')) {
      return jsonResponse({'streams': streams});
    }
    if (path.contains('/catalog/')) {
      return jsonResponse({
        'metas': [meta(1).toJson()],
      });
    }
    if (path.contains('/meta/')) {
      return jsonResponse({
        'meta': {
          ...meta(1).toJson(),
          'videos': [
            {
              'id': '${meta(1).id}:1:1',
              'season': 1,
              'episode': 1,
              'title': 'January episode',
              'released': '2026-01-02T00:00:00Z',
            },
          ],
        },
      });
    }
    if (r.method == 'HEAD') {
      return http.Response(
        '',
        headValid ? 200 : 404,
        headers: {'content-length': '100000000', 'content-type': 'video/mp4'},
      );
    }
    if (path.endsWith('/torrents/addMagnet')) {
      return jsonResponse({
        'id': 'original-${++rdAdds}',
        'uri':
            'https://api.real-debrid.com/rest/1.0/torrents/info/original-$rdAdds',
      }, 201);
    }
    if (path.contains('/torrents/info/')) {
      return jsonResponse({
        'id': path.split('/').last,
        'status': 'downloaded',
        'filename': 'Original.S01E01.1080p.mkv',
        'files': [
          {
            'id': 1,
            'path': '/Original.S01E01.1080p.mkv',
            'bytes': 100000000,
            'selected': 1,
          },
        ],
        'links': rdFails
            ? []
            : ['https://restricted.test/${path.split('/').last}'],
        'bytes': 100000000,
      });
    }
    if (path.contains('/torrents/selectFiles/')) {
      return http.Response('', 204);
    }
    if (path.endsWith('/unrestrict/link')) {
      if (heldUnrestrict != null && !holdUsed) {
        holdUsed = true;
        return heldUnrestrict!.future;
      }
      return unrestricted();
    }
    if (path.contains('/torrents/delete/')) {
      return http.Response('', 204);
    }
    if (r.url.host.contains('mypikpak')) {
      if (path.endsWith('/files/original-folder')) {
        return jsonResponse({
          'id': 'original-folder',
          'name': 'stremio-tv',
          'kind': 'drive#folder',
          'parent_id': '',
        });
      }
      if (r.method == 'POST' && path.endsWith('/files')) {
        return jsonResponse({
          'task': {'id': 'original-task', 'file_id': 'original-video'},
        });
      }
      if (path.endsWith('/tasks/original-task')) {
        return jsonResponse({
          'id': 'original-task',
          'file_id': 'original-video',
          'phase': 'PHASE_TYPE_COMPLETE',
          'progress': '100',
        });
      }
      if (path.endsWith('/files/original-video')) {
        return jsonResponse({
          'id': 'original-video',
          'kind': 'drive#file',
          'name': 'Original.720p.mkv',
          'phase': 'PHASE_TYPE_COMPLETE',
          'web_content_link': 'https://streams.test/Original.720p.mkv',
        });
      }
    }
    if (r.url.host.contains('torbox')) {
      Object data;
      if (path.endsWith('/checkcached')) {
        data = [
          for (final hash in torboxCached) {'hash': hash},
        ];
      } else if (path.endsWith('/createtorrent')) {
        data = {'torrent_id': ++torboxCreates};
      } else if (path.endsWith('/mylist')) {
        final torrent = {
          'id': torboxCreates,
          'hash': 'a' * 40,
          'name': 'Original.720p.mkv',
          'size': 100000000,
          'created_at': january.toIso8601String(),
          'updated_at': january.toIso8601String(),
          'download_state': 'cached',
          'download_finished': true,
          'files': torboxReject
              ? []
              : [
                  {
                    'id': 1,
                    'name': 'Original.720p.mkv',
                    'short_name': 'Original.720p.mkv',
                    'size': 100000000,
                    'mimetype': 'video/x-matroska',
                  },
                ],
        };
        data = r.url.queryParameters.containsKey('id') ? torrent : [torrent];
      } else if (path.endsWith('/requestdl')) {
        data = 'https://streams.test/Original.720p.mkv';
      } else if (path.endsWith('/controltorrent')) {
        data = {};
      } else {
        throw StateError('Unexpected TorBox path $path');
      }
      return jsonResponse({'success': true, 'data': data});
    }
    if (r.url.host.contains('premiumize')) {
      if (path.endsWith('/cache/check')) {
        return jsonResponse({
          'status': 'success',
          'response': [true, true],
        });
      }
      if (path.endsWith('/transfer/directdl')) {
        return jsonResponse({
          'status': 'success',
          'content': [
            {
              'path': 'Original.720p.mkv',
              'size': 100000000,
              'link': 'https://streams.test/Original.720p.mkv',
            },
          ],
        });
      }
    }
    if (r.url.host.contains('alldebrid')) {
      Object data;
      if (path.endsWith('/magnet/upload')) {
        data = {
          'magnets': [
            {
              'id': ++allDebridAdds,
              'name': 'Original.720p.mkv',
              'ready': allDebridAdds > allDebridRejects,
            },
          ],
        };
      } else if (path.endsWith('/magnet/files')) {
        data = {
          'magnets': [
            {
              'files': torboxReject
                  ? []
                  : [
                      {
                        'n': 'Original.720p.mkv',
                        's': 100000000,
                        'l': 'https://locked.test/original',
                      },
                    ],
            },
          ],
        };
      } else if (path.endsWith('/link/unlock')) {
        data = {'link': 'https://streams.test/Original.720p.mkv'};
      } else if (path.endsWith('/magnet/delete')) {
        data = {};
      } else {
        throw StateError('Unexpected AllDebrid path $path');
      }
      return jsonResponse({'status': 'success', 'data': data});
    }
    throw StateError('Unexpected original request: ${r.method} ${r.url}');
  }

  http.Response unrestricted() => jsonResponse({
    'download': 'https://video.test/original.mp4',
    'filename': 'Original.1080p.mkv',
    'filesize': 100000000,
  });
  StremioMeta meta(int i, {int item = 1}) => StremioMeta(
    id: 'tt${9100000 + i * 10 + item}',
    imdbId: 'tt${9100000 + i * 10 + item}',
    type: type,
    name: 'Original item $i.$item',
    year: '2026',
  );
  String channelId(int i) => 'local:original-$i:$type';
  Future<void> initialize() async {
    originalPrint = debugPrint;
    debugPrint = (message, {wrapWidth}) {
      if (message != null) {
        logs.add(message);
      }
      originalPrint(message, wrapWidth: wrapWidth);
    };
    SharedPreferences.setMockInitialValues({});
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    SecretVault.debugReset(deviceIdOverride: 'stremio-tv-characterization');
    AppThemeAdapter.debugUseTestTypography = true;
    PlatformUtil.debugSetTvOS(false);
    PlatformUtil.debugSetAndroidTvCached(false);
    final owned = Directory('.dart_tool/stremio_tv_fixture');
    await owned.create(recursive: true);
    directory = await owned.createTemp('case-');
    AppStorage.debugOverride(
      documents: directory,
      support: directory,
      cache: directory,
    );
    await StremioService.instance.clearAllAddons();
    await StremioTvStorage.setStremioTvAutoRefresh(false);
    await StremioTvStorage.setStremioTvMaxStartPercent(0);
    await RealDebridStorage.saveApiKey('original-rd');
    await RealDebridStorage.setRealDebridIntegrationEnabled(true);
    await PikpakStorage.setPikPakEnabled(false);
    await StremioTvStorage.setStremioTvDebridProvider('realdebrid');
    MainPageBridge.watchStremioTvChannel = null;
    MainPageBridge.getAndClearStremioTvChannelToAutoPlay();
    MainPageBridge.hideAutoLaunchOverlay = () => probes.add('hide overlay');
    MainPageBridge.focusTvSidebar = () => probes.add('sidebar');
    MainPageBridge.setActiveTvTab(9);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard.add((call.arguments as Map)['text'] as String);
          }
          return null;
        });
  }

  Future<void> installMediaServer() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final registry = await ProfileRegistry.open(
      path: '${directory.path}/media-profiles.db',
    );
    mediaRegistry = registry;
    final profile = await registry.createProfile(
      name: 'Original',
      role: UserProfileRole.admin,
    );
    await registry.commitBootstrap(
      activeProfileId: profile.id,
      migratedLegacyInstall: false,
    );
    final cipher = MemoryDeviceSecretCipher(List.generate(32, (i) => i));
    await cipher.initialize();
    DeviceKeyProvider.debugInstallCipher(cipher);
    ProfileBootstrap.debugInstallRegistry(registry);
    ProfileRuntime.initializeCommitted(
      ProfileScope(profileId: profile.id, dataGeneration: 1, sessionEpoch: 1),
    );
    await StremioTvStorage.setStremioTvAutoRefresh(false);
    await StremioTvStorage.setStremioTvMaxStartPercent(0);
    await RealDebridStorage.saveApiKey('original-rd');
    await RealDebridStorage.setRealDebridIntegrationEnabled(true);
    await StremioTvStorage.setStremioTvDebridProvider('realdebrid');
    await MediaServerService.connect(
      kind: MediaServerKind.jellyfin,
      label: 'Original media',
      baseUrl: 'https://media-original.test/',
      username: 'original',
      password: 'original',
    );
  }

  Future<void> provider(String name) async {
    switch (name) {
      case 'torbox':
        await TorboxStorage.saveTorboxApiKey('original-torbox');
        await TorboxStorage.setTorboxIntegrationEnabled(true);
      case 'premiumize':
        await PremiumizeStorage.savePremiumizeApiKey('original-premiumize');
        await PremiumizeStorage.setPremiumizeIntegrationEnabled(true);
      case 'alldebrid':
        await AllDebridStorage.saveAllDebridApiKey('original-alldebrid');
        await AllDebridStorage.setAllDebridIntegrationEnabled(true);
      case 'pikpak':
        await PikpakStorage.setPikPakEnabled(true);
        await PikpakStorage.setPikPakEmail('original@example.test');
        await PikpakStorage.setPikPakPassword('original-password');
        await PikpakStorage.setPikPakAccessToken('original-access');
        await PikpakStorage.setPikPakRefreshToken('original-refresh');
        await PikpakStorage.setPikPakTvFolderId('original-folder');
    }
    await StremioTvStorage.setStremioTvDebridProvider(name);
  }

  Future<void> seed() async {
    if (streamAddon) {
      await StremioService.instance.addAddon(
        'https://stremio-tv-original.test/manifest.json',
      );
    }
    await StremioCatalogStorage.setStremioTvLocalCatalogs([
      for (var i = 1; i <= count; i++)
        {
          'id': 'original-$i',
          'name': 'Original channel $i',
          'type': type,
          'items': [
            for (var j = 1; j <= itemCount; j++) meta(i, item: j).toJson(),
          ],
        },
    ]);
    requests.clear();
  }

  Widget host() => MaterialApp(
    navigatorKey: navigator,
    navigatorObservers: [observer],
    locale: const Locale('en', 'US'),
    theme: ThemeData(
      brightness: Brightness.dark,
      platform: TargetPlatform.macOS,
    ),
    builder: (context, child) => AppThemeScope(
      theme: PremiumLooks.byId('spotlight')!.build(),
      child: MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
        child: child!,
      ),
    ),
    home: RepaintBoundary(
      key: stremioTvCanvas,
      child: StremioTvScreen(key: hostKey, isTelevision: television),
    ),
  );
  Future<void> mount(
    WidgetTester t, {
    Size size = const Size(1920, 1080),
    bool wait = true,
    bool seedChannels = true,
  }) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    if (seedChannels) {
      await t.runAsync(seed);
    }
    await t.pumpWidget(host());
    if (wait) {
      await until(
        t,
        () => count == 0
            ? find.text('No Catalog Addons').evaluate().isNotEmpty
            : find.byType(StremioTvTuner).evaluate().isNotEmpty,
      );
      await settle(t);
    }
  }

  StremioTvTuner tuner(WidgetTester t) =>
      t.widget<StremioTvTuner>(find.byType(StremioTvTuner));
  StremioTvChannel channel(WidgetTester t, [int i = 1]) =>
      tuner(t).allChannels.singleWhere((c) => c.id == channelId(i));
  FocusNode node(String label) => FocusManager.instance.rootScope.descendants
      .singleWhere((n) => n.debugLabel == label);
  Future<void> settle(WidgetTester t, {int frames = 8}) async {
    for (var i = 0; i < frames; i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 2)),
      );
      await t.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> until(
    WidgetTester t,
    bool Function() ready, {
    int frames = 200,
  }) async {
    for (var i = 0; i < frames && !ready(); i++) {
      await settle(t, frames: 1);
    }
    expect(ready(), isTrue, reason: 'ORIGINAL fixture boundary became ready');
  }

  Future<void> play(WidgetTester t, [int i = 1]) async {
    final before = observer.players.length;
    tuner(t).onPlay(channel(t, i));
    await until(
      t,
      () =>
          observer.players.length > before ||
          find
              .byWidgetPredicate(
                (w) => w.runtimeType.toString() == '_ManualSourcePickerSheet',
              )
              .evaluate()
              .isNotEmpty,
    );
    await settle(t);
  }

  Future<void> tap(WidgetTester t, Finder finder) async {
    await t.tap(finder);
    await t.pump();
    await settle(t);
  }

  Future<void> key(WidgetTester t, LogicalKeyboardKey key) async {
    await t.sendKeyEvent(key);
    await t.pump();
    await settle(t);
  }

  Future<void> menu(WidgetTester t) async {
    node('menuBtn').requestFocus();
    await t.pump();
    await key(t, LogicalKeyboardKey.enter);
  }

  Future<void> chooseProvider(WidgetTester t, String value) async {
    node('providerBtn').requestFocus();
    await t.pump();
    await key(t, LogicalKeyboardKey.enter);
    await tap(t, find.widgetWithText(MenuItemButton, value));
  }

  Future<void> dispose(WidgetTester t) async {
    if (heldUnrestrict != null && !heldUnrestrict!.isCompleted) {
      heldUnrestrict!.complete(unrestricted());
    }
    await settle(t);
    await t.pumpWidget(const SizedBox());
    await settle(t);
    MainPageBridge.hideAutoLaunchOverlay = null;
    MainPageBridge.focusTvSidebar = null;
    MainPageBridge.watchStremioTvChannel = null;
    MainPageBridge.getAndClearStremioTvChannelToAutoPlay();
    await t.runAsync(() async {
      await StremioService.instance.clearAllAddons();
      if (mediaRegistry != null) {
        await mediaRegistry!.close();
        ProfileBootstrap.debugInstallRegistry(null);
        DeviceKeyProvider.debugReset();
      }
      AppStorage.debugReset();
      SecretVault.debugReset();
      ProfileRuntime.debugReset();
      PlatformUtil.debugSetTvOS(null);
      PlatformUtil.debugSetAndroidTvCached(null);
      AppThemeAdapter.debugUseTestTypography = false;
      await directory.delete(recursive: true);
    });
    debugPrint = originalPrint;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  }
}

Future<void> stremioTvCase(
  WidgetTester t,
  Future<void> Function(StremioTvFixture) body,
) async {
  final f = StremioTvFixture();
  await http.runWithClient(() async {
    await t.runAsync(f.initialize);
    try {
      await body(f);
    } finally {
      await f.dispose(t);
    }
  }, () => f.client);
}
