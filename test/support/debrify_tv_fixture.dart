import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:debrify/models/debrify_tv/channel.dart';
import 'package:debrify/models/debrify_tv_cache.dart';
import 'package:debrify/models/debrify_tv_channel_record.dart';
import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/models/profiles/user_profile.dart';
import 'package:debrify/screens/debrify_tv/layouts/spotlight_layout.dart';
import 'package:debrify/screens/magic_tv_screen.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/debrify_tv_cache_service.dart';
import 'package:debrify/services/debrify_tv_database.dart';
import 'package:debrify/services/debrify_tv_repository.dart';
import 'package:debrify/services/download_service.dart';
import 'package:debrify/services/engine/settings_manager.dart';
import 'package:debrify/services/engine/config_loader.dart';
import 'package:debrify/services/engine/engine_registry.dart';
import 'package:debrify/services/engine/local_engine_storage.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/services/profiles/device_key_provider.dart';
import 'package:debrify/services/profiles/profile_bootstrap.dart';
import 'package:debrify/services/profiles/profile_cache_ledger.dart';
import 'package:debrify/services/profiles/profile_policy_guard.dart';
import 'package:debrify/services/profiles/profile_registry.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/profiles/tvos_profile_recovery_store.dart';
import 'package:debrify/services/secret_vault.dart';
import 'package:debrify/services/pikpak_api_service.dart';
import 'package:debrify/services/storage/alldebrid_storage.dart';
import 'package:debrify/services/storage/debrify_tv_storage.dart';
import 'package:debrify/services/storage/pikpak_storage.dart';
import 'package:debrify/services/storage/premiumize_storage.dart';
import 'package:debrify/services/storage/real_debrid_storage.dart';
import 'package:debrify/services/storage/torbox_storage.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_library_models.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/theme/app_theme_adapter.dart';
import 'package:debrify/theme/legacy_theme_boundary.dart';
import 'package:debrify/theme/premium_looks.dart';
import 'package:debrify/utils/app_storage.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const debrifyTvCanvas = ValueKey('debrify-tv-original-canvas');
const debrifyTvEngineYaml = '''
id: debrify-tv-original
display_name: Debrify TV original fixture
icon: live_tv
categories: [general]
capabilities:
  keyword_search: true
  imdb_search: false
  series_support: false
api:
  base_url: https://debrify-tv-original.test/search
  method: GET
query_params:
  type: query_params
  param_name: q
response_format:
  type: direct_json
  results_path: results
field_mappings:
  name: {source: name}
  infohash: {source: infohash}
  size: {source: size}
  seeders: {source: seeders}
  leechers: {source: leechers}
tv_mode:
  enabled_default: true
  limits: {small: 1, large: 1, quick_play: 1}
request:
  retry_attempts: 0
''';

class DebrifyTvPicker extends FilePicker {
  FilePickerResult? next;
  final saves = <String?>[];
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
  }) async => next;
  @override
  Future<String?> saveFile({
    String? dialogTitle,
    String? fileName,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Uint8List? bytes,
    bool lockParentWindow = false,
  }) async {
    saves.add(fileName);
    return null;
  }
}

class DebrifyTvObserver extends NavigatorObserver {
  final GlobalKey hostKey;
  final players = <VideoPlayerScreen>[];
  final events = <String>[];
  final dialogs = <Route<dynamic>>[];
  final activeDialogsAtPlayer = <int>[];
  void Function(VideoPlayerScreen)? onPlayer;
  DebrifyTvObserver(this.hostKey);
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is MaterialPageRoute && hostKey.currentContext != null) {
      final context = hostKey.currentContext!;
      Widget built = route.builder(context);
      if (built is LegacyThemeBoundary) {
        built = built.child;
      }
      if (built is Builder) {
        built = built.builder(context);
      }
      if (built is VideoPlayerScreen) {
        activeDialogsAtPlayer.add(dialogs.where((r) => r.isActive).length);
        players.add(built);
        events.add('player');
        onPlayer?.call(built);
        // Navigator is locked during didPush. Its microtask runs before the
        // next frame, so the original builder is observed but never mounted.
        scheduleMicrotask(() {
          if (route.isActive) {
            navigator!.removeRoute(route);
            events.add('player removed');
          }
        });
        return;
      }
    }
    if (previousRoute != null) dialogs.add(route);
    events.add(previousRoute == null ? 'home' : 'dialog');
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    events.add('pop');
  }
}

class DebrifyTvFixture {
  final hostKey = GlobalKey();
  final navigator = GlobalKey<NavigatorState>();
  late final observer = DebrifyTvObserver(hostKey);
  final picker = DebrifyTvPicker();
  final requests = <http.Request>[];
  final clipboard = <String>[];
  final nativeCalls = <MethodCall>[];
  final probes = <String>[];
  final originalLayoutDiagnostics = <FlutterErrorDetails>[];
  final channels = <DebrifyTvChannel>[];
  late final MockClient client = MockClient(respond);
  Future<http.Response> Function(http.Request)? onRequest;
  late Directory directory;
  late Database database;
  late ProfileRegistry registry;
  late UserProfile adult;
  late UserProfile child;
  bool television = false;
  String style = 'grid';
  int count = 2;
  bool goldenSearchNames = false;
  bool goldenFavorites = false;
  bool expectOriginalPhoneAddCardOverflow = false;
  final originalPhoneAddCardOverflows = <FlutterErrorDetails>[];
  bool childProfile = false;
  List<List<String>> cacheKeywords = const [
    ['one', 'two', 'three'],
  ];
  int rdAdds = 0;
  Completer<http.Response>? heldUnrestrict;
  bool holdUsed = false;
  final DateTime january = DateTime.utc(2026, 1, 2);

  String requestIdentity(http.Request r) => '${r.method} ${r.url.path}';
  http.Response jsonResponse(Object data, [int code = 200]) => http.Response(
    jsonEncode(data),
    code,
    headers: {'content-type': 'application/json'},
  );
  Future<http.Response> respond(http.Request request) async {
    requests.add(request);
    if (onRequest != null) {
      return onRequest!(request);
    }
    return providerResponse(request);
  }

  Future<http.Response> providerResponse(http.Request r) async {
    final path = r.url.path;
    if (r.url.host == 'debrify-tv-original.test') {
      return jsonResponse({
        'results': [
          {
            'name': 'Original.720p.mkv',
            'infohash': 'a' * 40,
            'size': 100000000,
            'seeders': 20,
            'leechers': 1,
          },
        ],
      });
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
        'filename': 'Original.720p.mkv',
        'files': [
          {
            'id': 1,
            'path': '/Original.720p.mkv',
            'bytes': 100000000,
            'selected': 1,
          },
        ],
        'links': ['https://restricted.test/${path.split('/').last}'],
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
      return streamResponse();
    }
    if (r.url.host.contains('mypikpak')) {
      if (path.endsWith('/files/original-folder')) {
        return jsonResponse({
          'id': 'original-folder',
          'name': 'debrify-tv',
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
          {'hash': 'a' * 40},
        ];
      } else if (path.endsWith('/createtorrent')) {
        data = {'torrent_id': 71};
      } else if (path.endsWith('/mylist')) {
        final torrent = {
          'id': 71,
          'hash': 'a' * 40,
          'name': 'Original.720p.mkv',
          'size': 100000000,
          'created_at': january.toIso8601String(),
          'updated_at': january.toIso8601String(),
          'download_state': 'cached',
          'download_finished': true,
          'files': [
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
      } else {
        throw StateError('Unexpected TorBox path $path');
      }
      return jsonResponse({'success': true, 'data': data});
    }
    if (r.url.host.contains('premiumize')) {
      if (path.endsWith('/cache/check')) {
        return jsonResponse({
          'status': 'success',
          'response': [true],
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
            {'id': 61, 'name': 'Original.720p.mkv', 'ready': true},
          ],
        };
      } else if (path.endsWith('/magnet/files')) {
        data = {
          'magnets': [
            {
              'files': [
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
      } else {
        throw StateError('Unexpected AllDebrid path $path');
      }
      return jsonResponse({'status': 'success', 'data': data});
    }
    throw StateError(
      'Unexpected ORIGINAL Debrify TV fixture request ${requestIdentity(r)}',
    );
  }

  http.Response streamResponse() => jsonResponse({
    'download': 'https://streams.test/Original.720p.mkv',
    'filename': 'Original.720p.mkv',
    'filesize': 100000000,
  });

  Future<void> initialize() async {
    AppThemeAdapter.debugUseTestTypography = true;
    PlatformUtil.debugSetTvOS(false);
    PlatformUtil.debugSetAndroidTvCached(false);
    TvOsProfileRecoveryStore.checkpointCallback = () async {
      probes.add('checkpoint');
    };
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('debrify/tvos_profile_recovery'),
          (call) async => call.method == 'publish' ? true : null,
        );
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    SharedPreferences.setMockInitialValues({});
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    SecretVault.debugReset(deviceIdOverride: 'debrify-tv-characterization');
    final owned = Directory('.dart_tool/debrify_tv_fixture');
    await owned.create(recursive: true);
    directory = await owned.createTemp('case-');
    AppStorage.debugOverride(
      documents: directory,
      support: directory,
      cache: directory,
    );
    registry = await ProfileRegistry.open(
      path: '${directory.path}/profiles.db',
    );
    adult = await registry.createProfile(
      name: 'Original adult',
      role: UserProfileRole.admin,
    );
    child = await registry.createProfile(
      name: 'Original child',
      role: UserProfileRole.child,
    );
    await registry.commitBootstrap(
      activeProfileId: adult.id,
      migratedLegacyInstall: false,
    );
    final cipher = MemoryDeviceSecretCipher(
      List<int>.generate(32, (i) => i + 5),
    );
    await cipher.initialize();
    DeviceKeyProvider.debugInstallCipher(cipher);
    ProfileBootstrap.debugInstallRegistry(registry);
    ProfileRuntime.initializeCommitted(
      ProfileScope(profileId: adult.id, dataGeneration: 1, sessionEpoch: 1),
    );
    ProfilePolicyGuard.updateActiveProfile(adult);
    sqfliteFfiInit();
    database = await databaseFactoryFfiNoIsolate.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, _) async {
          await DebrifyTvDatabase.createTvStoreTables(db);
          await DebrifyTvDatabase.createIptvStoreTables(db);
        },
      ),
    );
    DebrifyTvDatabase.debugDatabaseOverride = database;
    LocalEngineStorage.instance.resetProfileScope();
    ConfigLoader().clearCache();
    EngineRegistry.instance.invalidateProfileScope();
    await LocalEngineStorage.instance.saveEngine(
      engineId: 'debrify-tv-original',
      fileName: 'debrify-tv-original.yaml',
      yamlContent: debrifyTvEngineYaml,
      displayName: 'Debrify TV original fixture',
    );
    await EngineRegistry.instance.reload();
    await SettingsManager().setGlobalMinTorrentsPerKeyword(1);
    DownloadService.instance.debugOverrideGeneratedFileDirectory(
      Directory('${directory.path}/exports'),
    );
    await RealDebridStorage.saveApiKey('original-rd');
    await RealDebridStorage.setRealDebridIntegrationEnabled(true);
    PikPakApiService.instance.resetProfileScope();
    await PikpakStorage.setPikPakEnabled(false);
    await DebrifyTvStorage.saveDebrifyTvProvider('real_debrid');
    await DebrifyTvStorage.saveDebrifyTvStartRandom(false);
    await DebrifyTvStorage.saveDebrifyTvRandomStartPercent(23);
    await DebrifyTvStorage.saveDebrifyTvHideSeekbar(false);
    await DebrifyTvStorage.saveDebrifyTvShowChannelName(false);
    await DebrifyTvStorage.saveDebrifyTvShowVideoTitle(false);
    FilePicker.platform = picker;
    MainPageBridge.watchDebrifyTvChannel = null;
    MainPageBridge.getAndClearDebrifyTvChannelToAutoPlay();
    MainPageBridge.hideAutoLaunchOverlay = () => probes.add('hide overlay');
    MainPageBridge.focusTvSidebar = () => probes.add('sidebar');
    MainPageBridge.setActiveTvTab(3);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard.add((call.arguments as Map)['text'] as String);
          }
          return null;
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.debrify.app/android_tv_player'),
          (call) async {
            nativeCalls.add(call);
            return false;
          },
        );
  }

  Future<void> provider(String name) async {
    switch (name) {
      case 'pikpak':
        await PikpakStorage.setPikPakEnabled(true);
        await PikpakStorage.setPikPakAccessToken('original-access');
        await PikpakStorage.setPikPakRefreshToken('original-refresh');
        await PikpakStorage.setPikPakTvFolderId('original-folder');
      case 'torbox':
        await TorboxStorage.saveTorboxApiKey('original-torbox');
        await TorboxStorage.setTorboxIntegrationEnabled(true);
      case 'premiumize':
        await PremiumizeStorage.savePremiumizeApiKey('original-premiumize');
        await PremiumizeStorage.setPremiumizeIntegrationEnabled(true);
      case 'alldebrid':
        await AllDebridStorage.saveAllDebridApiKey('original-alldebrid');
        await AllDebridStorage.setAllDebridIntegrationEnabled(true);
    }
    await DebrifyTvStorage.saveDebrifyTvProvider(name);
  }

  Future<void> seed() async {
    if (childProfile) {
      ProfileRuntime.publish(
        ProfileScope(profileId: child.id, dataGeneration: 1, sessionEpoch: 2),
      );
      ProfilePolicyGuard.updateActiveProfile(child);
    }
    await DebrifyTvStorage.setDebrifyTvStyle(style);
    PlatformUtil.debugSetTvOS(television);
    PlatformUtil.debugSetAndroidTvCached(television);
    for (var i = 0; i < count; i++) {
      final record = DebrifyTvChannelRecord(
        channelId: 'original-${i + 1}',
        name:
            '${goldenSearchNames && i >= 3 ? 'Other' : 'Original'} channel ${i + 1}',
        keywords: const ['one', 'two', 'three'],
        avoidNsfw: false,
        channelNumber: i + 1,
        createdAt: january,
        updatedAt: january,
      );
      await DebrifyTvRepository.instance.upsertChannel(
        record,
        origin: WebDavSyncMutationOrigin.rollback,
      );
      channels.add(DebrifyTvChannel.fromRecord(record));
      if (goldenFavorites && (i == 1 || i == 4)) {
        await DebrifyTvStorage.setDebrifyTvChannelFavorited(
          record.channelId,
          true,
        );
      }
      await DebrifyTvCacheService.saveEntry(
        DebrifyTvChannelCacheEntry(
          version: 1,
          channelId: record.channelId,
          normalizedKeywords: const ['one', 'two', 'three'],
          fetchedAt: 0,
          status: DebrifyTvCacheStatus.ready,
          errorMessage: null,
          torrents: [
            for (
              var torrentIndex = 0;
              torrentIndex < cacheKeywords.length;
              torrentIndex++
            )
              CachedTorrent(
                rowid: 0,
                infohash: String.fromCharCode(97 + torrentIndex) * 40,
                name: 'Original.720p.mkv',
                sizeBytes: 100000000,
                createdUnix: january.millisecondsSinceEpoch ~/ 1000,
                seeders: 20,
                leechers: 1,
                completed: 1,
                scrapedDate: 0,
                sources: const ['debrify-tv-original'],
                keywords: cacheKeywords[torrentIndex],
              ),
          ],
          keywordStats: const {},
        ),
      );
    }
  }

  Widget host() => MaterialApp(
    navigatorKey: navigator,
    navigatorObservers: [observer],
    locale: const Locale('en', 'US'),
    theme: ThemeData(
      brightness: Brightness.dark,
      platform: TargetPlatform.macOS,
    ),
    home: AppThemeScope(
      theme: PremiumLooks.byId('spotlight')!.build(),
      child: RepaintBoundary(
        key: debrifyTvCanvas,
        child: Scaffold(body: DebrifyTVScreen(key: hostKey)),
      ),
    ),
  );
  Future<void> mount(
    WidgetTester t, {
    Size size = const Size(1920, 1080),
  }) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.runAsync(seed);
    await t.pumpWidget(host());
    WidgetsBinding.instance.scheduleFrame();
    await until(
      t,
      () => count == 0
          ? find.text('No channels yet').evaluate().isNotEmpty
          : find
                .byWidgetPredicate(
                  (w) =>
                      w is Text &&
                      (w.data?.toLowerCase().contains('original channel 1') ??
                          false),
                )
                .evaluate()
                .isNotEmpty,
    );
    await settle(t);
  }

  Future<void> settle(WidgetTester t, {int frames = 10}) async {
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
    int frames = 160,
  }) async {
    for (var i = 0; i < frames && !ready(); i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 2)),
      );
      await t.pump(const Duration(milliseconds: 50));
    }
    expect(
      ready(),
      isTrue,
      reason:
          'ORIGINAL fixture readiness; requests=${requests.map(requestIdentity).toList()}',
    );
  }

  Future<void> tap(WidgetTester t, Finder finder) async {
    await t.ensureVisible(finder.last);
    await t.tap(finder.last);
    await t.pump();
    await settle(t);
  }

  FocusNode node(String label) {
    FocusNode? visit(FocusNode n) {
      if (n.debugLabel == label) return n;
      for (final child in n.children) {
        final result = visit(child);
        if (result != null) return result;
      }
      return null;
    }

    return visit(FocusManager.instance.rootScope) ??
        (throw StateError('Missing focus owner $label'));
  }

  SpotlightLayout get spotlight =>
      find.byType(SpotlightLayout).evaluate().single.widget as SpotlightLayout;
  Future<void> settings(WidgetTester t) async {
    if (style == 'spotlight') {
      spotlight.view.onSettings();
      await t.pump();
      await settle(t);
    } else {
      node('DebrifyTVChannelMenu').requestFocus();
      await t.pump();
      await t.sendKeyEvent(LogicalKeyboardKey.select);
      await settle(t);
      await tap(t, find.widgetWithText(MenuItemButton, 'Settings').last);
    }
    expect(find.text('Channel playback'), findsOneWidget);
  }

  Future<void> watch(WidgetTester t, [int index = 0]) async {
    MainPageBridge.watchDebrifyTvChannel!(channels[index].id);
    await t.pump();
    await settle(t);
  }

  Future<void> quick(WidgetTester t, {String keywords = 'one'}) async {
    if (style == 'spotlight') {
      spotlight.view.onQuickPlay();
      await t.pump();
      await settle(t);
    } else {
      await tap(t, find.byTooltip('Play'));
    }
    await t.enterText(find.byType(EditableText).last, keywords);
    await tap(t, find.text('Play now'));
  }

  Future<void> close() async {
    DownloadService.instance.debugOverrideGeneratedFileDirectory(null);
    FilePicker.platform = DebrifyTvPicker();
    MainPageBridge.hideAutoLaunchOverlay = null;
    MainPageBridge.focusTvSidebar = null;
    MainPageBridge.watchDebrifyTvChannel = null;
    PlatformUtil.debugSetTvOS(null);
    PlatformUtil.debugSetAndroidTvCached(null);
    DebrifyTvDatabase.debugDatabaseOverride = null;
    await database.close();
    ProfilePolicyGuard.updateActiveProfile(null);
    ProfileRuntime.debugReset();
    ProfileBootstrap.debugInstallRegistry(null);
    DeviceKeyProvider.debugReset();
    ProfileCacheLedger.debugReset();
    LocalEngineStorage.instance.resetProfileScope();
    ConfigLoader().clearCache();
    EngineRegistry.instance.invalidateProfileScope();
    SecretVault.debugReset(deviceIdOverride: 'debrify-tv-characterization');
    await registry.close();
    AppStorage.debugReset();
    TvOsProfileRecoveryStore.checkpointCallback = null;
    DebrifyTvStorage.debrifyTvStyleCached = 'grid';
    await directory.delete(recursive: true);
    client.close();
  }
}

Future<void> debrifyTvCase(
  WidgetTester t,
  Future<void> Function(DebrifyTvFixture) body,
) async {
  final f = DebrifyTvFixture();
  final previousTypography = AppThemeAdapter.debugUseTestTypography;
  final previousErrorHandler = FlutterError.onError;
  FlutterError.onError = (details) {
    // Flutter 3.44.8 reports this existing SwitchRow/ListTile decoration on R.
    // Preserve the diagnostic as evidence; every other error remains fatal.
    if (details.exception is FlutterError &&
        details.exceptionAsString().startsWith(
          'ListTile background color or ink splashes may be invisible.\n',
        ) &&
        details.exceptionAsString().contains(
          'The ListTile is wrapped in a DecoratedBox',
        )) {
      f.originalLayoutDiagnostics.add(details);
    } else if (f.expectOriginalPhoneAddCardOverflow &&
        details.exception is FlutterError &&
        details.exceptionAsString().startsWith(
          'A RenderFlex overflowed by 37 pixels on the bottom.',
        )) {
      f.originalPhoneAddCardOverflows.add(details);
    } else {
      previousErrorHandler!(details);
    }
  };
  try {
    await http.runWithClient(() async {
      await t.runAsync(f.initialize);
      await body(f);
    }, () => f.client);
  } finally {
    await t.pumpWidget(const SizedBox.shrink());
    await t.pump(const Duration(seconds: 6));
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 4)),
    );
    await t.pump();
    await t.runAsync(f.close);
    FlutterError.onError = previousErrorHandler;
    AppThemeAdapter.debugUseTestTypography = previousTypography;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('debrify/tvos_profile_recovery'),
          null,
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.debrify.app/android_tv_player'),
          null,
        );
  }
}
