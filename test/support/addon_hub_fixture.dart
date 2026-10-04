import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/screens/addons/addon_hub_screen.dart';
import 'package:debrify/services/engine/config_loader.dart';
import 'package:debrify/services/engine/engine_registry.dart';
import 'package:debrify/services/engine/local_engine_storage.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/secret_vault.dart';
import 'package:debrify/services/stremio_marketplace_service.dart';
import 'package:debrify/services/stremio_service.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/utils/app_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import 'profile_fixture.dart';

const addonHubMetadataUrl =
    'https://gitlab.com/mediacontent/search-engines/-/raw/main/torrents/metadata.yaml';
const addonHubTreeUrl =
    'https://gitlab.com/api/v4/projects/mediacontent%2Fsearch-engines/repository/tree?path=torrents&ref=main';
const addonHubOfficialUrl = 'https://api.strem.io/addonscollection.json';
const addonHubCommunityUrl =
    'https://stremio-addons.net/api/v0/addons?sort_by=stars&order=desc&limit=100&page=1';
const addonHubFallbackUrl =
    'https://stremio-addons.com/addon_catalog/all/community.json';

StremioAddon hubAddon(
  String id,
  String name, {
  List<String> types = const ['movie', 'series'],
  List<String> resources = const ['stream', 'catalog', 'meta', 'subtitles'],
  bool enabled = true,
  String? alias,
}) => StremioAddon(
  id: id,
  name: name,
  manifestUrl: 'https://$id.addon.test/manifest.json',
  baseUrl: 'https://$id.addon.test',
  version: '1.0.0',
  description: 'Fixture description for $name',
  types: types,
  resources: resources,
  enabled: enabled,
  userAlias: alias,
);

Map<String, Object?> hubManifest(
  String id,
  String name, {
  bool configurable = false,
  bool required = false,
  String version = '1.0.0',
}) => {
  'id': id,
  'name': name,
  'version': version,
  'description': 'Fixture description for $name',
  'resources': ['stream', 'catalog', 'meta', 'subtitles'],
  'types': ['movie', 'series'],
  'behaviorHints': {
    'configurable': configurable,
    'configurationRequired': required,
  },
};

Map<String, Object?> hubMarketEntry(
  String id,
  String name, {
  bool configurable = false,
  bool required = false,
}) => {
  'transportUrl': 'https://$id.addon.test/manifest.json',
  'manifestUrl': 'https://$id.addon.test/manifest.json',
  'manifest': hubManifest(
    id,
    name,
    configurable: configurable,
    required: required,
  ),
};

String hubEngineYaml(String id, String name) =>
    'id: $id\ndisplay_name: $name\nicon: travel_explore\ncategories: [general]\n'
    'capabilities:\n  keyword_search: true\n  imdb_search: false\n  series_support: false\n'
    'api:\n  base_url: https://engine.test/search\n  method: GET\n'
    'query_params:\n  type: query_params\n  param_name: q\n'
    'response_format:\n  type: direct_json\n  results_path: results\n';

class HubClient extends MockClient {
  HubClient(super.fn);
  bool closed = false;
  @override
  void close() {
    closed = true;
    super.close();
  }
}

class HubPicker extends FilePicker {
  FilePickerResult? result;
  Completer<FilePickerResult?>? pending;
  final calls = <Map<String, Object?>>[];
  void supply(String name, String contents, {String? path, bool bytes = true}) {
    result = FilePickerResult([
      PlatformFile(
        name: name,
        size: contents.length,
        path: path,
        bytes: bytes ? Uint8List.fromList(utf8.encode(contents)) : null,
      ),
    ]);
  }

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = false,
    int compressionQuality = 0,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async {
    calls.add({
      'type': type,
      'allowMultiple': allowMultiple,
      'withData': withData,
      'allowedExtensions': allowedExtensions,
    });
    return pending == null ? result : pending!.future;
  }
}

class HubUrls extends UrlLauncherPlatform {
  final calls = <(String, LaunchOptions)>[];
  bool result = true;
  bool fail = false;
  @override
  LinkDelegate? get linkDelegate => null;
  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    calls.add((url, options));
    if (fail) throw StateError('fixture browser failure');
    return result;
  }
}

class HubObserver extends NavigatorObserver {
  final pushes = <Route<dynamic>>[];
  final pops = <Route<dynamic>>[];
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      pushes.add(route);
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      pops.add(route);
}

FilePicker? _installedPicker() {
  try {
    return FilePicker.platform;
  } catch (_) {
    return null;
  }
}

class AddonHubFixture {
  final key = GlobalKey<State<AddonHubScreen>>();
  final navigator = GlobalKey<NavigatorState>();
  final observer = HubObserver();
  final picker = HubPicker();
  final urls = HubUrls();
  final clients = <HubClient>[];
  final requests = <String>[];
  final setupRequests = <String>[];
  final clipboard = <String>[];
  final sync = <(String, String)>[];
  final held = <String, Completer<http.Response>>{};
  final releases = <void Function()>[];
  final responses = <String, http.Response>{};
  Future<http.Response> Function(http.Request)? onRequest;
  bool setup = false;
  bool abortOnClose = false;
  late Directory directory;
  ProfileFixture? profiles;
  final previousPicker = _installedPicker();
  final previousUrls = UrlLauncherPlatform.instance;
  final installed = [
    hubAddon('z9', 'Zulu'),
    hubAddon('com.linvo.cinemeta', 'Cinemeta'),
    hubAddon('a2', 'Alpha'),
  ];
  final market = [
    hubMarketEntry('m7', 'Middle', configurable: true),
    hubMarketEntry('z9', 'Zulu'),
    hubMarketEntry('b3', 'Beta'),
  ];
  Map<String, Object?> get access => addonHubTestAccess(key.currentState!);
  dynamic member(String name) => access[name];
  List<String> ids(String name) =>
      (member(name) as List).map((dynamic x) => x.id as String).toList();
  http.Response json(Object value, [int status = 200]) =>
      http.Response(jsonEncode(value), status);
  HubClient client() {
    late HubClient c;
    c = HubClient((r) async {
      (setup ? setupRequests : requests).add('${r.method} ${r.url}');
      final response = held.containsKey(r.url.toString())
          ? await held[r.url.toString()]!.future
          : onRequest != null
          ? await onRequest!(r)
          : respond(r);
      if (abortOnClose && c.closed) {
        throw http.ClientException('fixture request aborted on close');
      }
      return response;
    });
    clients.add(c);
    return c;
  }

  http.Response respond(http.Request r) {
    final url = r.url.toString();
    if (responses.containsKey(url)) return responses[url]!;
    if (url == addonHubOfficialUrl || url == addonHubFallbackUrl) {
      return json(market);
    }
    if (r.url.host == 'stremio-addons.net') {
      return json({
        'addons': market,
        'pagination': {'totalPages': 1},
      });
    }
    if (url == addonHubMetadataUrl) {
      return http.Response(
        'version: "1.0"\nengines:\n  - name: Zulu engine\n    path: torrents/z9.yaml\n    description: Zulu fixture engine\n  - name: Alpha engine\n    path: torrents/a2.yaml\n    description: Alpha fixture engine\n',
        200,
      );
    }
    if (url == addonHubTreeUrl) {
      return json([
        {'name': 'z9.yaml'},
        {'name': 'a2.yaml'},
      ]);
    }
    if (r.url.host == 'gitlab.com' && r.url.path.endsWith('.yaml')) {
      final id = r.url.pathSegments.last.replaceAll('.yaml', '');
      return http.Response(
        hubEngineYaml(id, id == 'z9' ? 'Zulu engine' : 'Alpha engine'),
        200,
      );
    }
    if (r.url.host.endsWith('.addon.test') && r.url.path == '/manifest.json') {
      final id = r.url.host.replaceAll('.addon.test', '');
      return json(
        hubManifest(
          id,
          {
                'z9': 'Zulu',
                'com.linvo.cinemeta': 'Cinemeta',
                'a2': 'Alpha',
                'm7': 'Middle',
                'b3': 'Beta',
              }[id] ??
              id,
        ),
      );
    }
    throw StateError('Unexpected ORIGINAL fixture request ${r.method} $url');
  }

  Future<void> initialize({bool committed = false}) async {
    rootBundle.clear();
    SharedPreferences.setMockInitialValues({
      'stremio_addons_v1': jsonEncode(
        installed.map((a) => a.toJson()).toList(),
      ),
    });
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    SecretVault.debugReset(deviceIdOverride: 'addon-hub-characterization');
    directory = await Directory.systemTemp.createTemp('addon-hub-');
    AppStorage.debugOverride(
      documents: directory,
      support: directory,
      cache: directory,
    );
    if (committed) {
      profiles = ProfileFixture();
      await profiles!.open();
    }
    LocalEngineStorage.instance.resetProfileScope();
    StremioService.instance.invalidateCache();
    ConfigLoader().clearCache();
    EngineRegistry.instance.invalidateProfileScope();
    FilePicker.platform = picker;
    UrlLauncherPlatform.instance = urls;
    ProfilePreferences.webDavSyncLocalChangeSink = (profile, key) =>
        sync.add((profile, key));
    MainPageBridge.setActiveTvTab(7);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard.add((call.arguments as Map)['text'] as String);
          }
          return null;
        });
  }

  Future<void> warmMarket({bool fallback = false}) async {
    setup = true;
    try {
      await StremioMarketplaceService.instance.fetchOfficial(
        forceRefresh: true,
      );
      if (fallback) {
        responses[addonHubCommunityUrl] = http.Response(
          'fixture net failure',
          500,
        );
      }
      await StremioMarketplaceService.instance.fetchCommunity(
        forceRefresh: true,
      );
      responses.remove(addonHubCommunityUrl);
    } finally {
      setup = false;
    }
  }

  Future<void> until(WidgetTester t, bool Function() ready) async {
    for (var i = 0; i < 200 && !ready(); i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await t.pump(const Duration(milliseconds: 20));
    }
    expect(ready(), isTrue, reason: 'ORIGINAL addon hub action did not finish');
  }

  Future<void> mount(
    WidgetTester t, {
    double width = 1000,
    bool wait = true,
    Widget? home,
  }) async {
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = Size(width, 1100);
    await t.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        navigatorObservers: [observer],
        theme: ThemeData.dark(),
        home: AppThemeScope(
          theme: AppThemes.legacy,
          child:
              home ??
              RepaintBoundary(
                key: const ValueKey('addon-hub-canvas'),
                child: AddonHubScreen(key: key),
              ),
        ),
      ),
    );
    if (wait && home == null) await loaded(t);
  }

  Future<void> loaded(WidgetTester t) async {
    await until(
      t,
      () =>
          key.currentState != null &&
          member('installedLoading') == false &&
          member('hasDebrid') == false,
    );
    await t.pump(const Duration(milliseconds: 500));
    await t.pump();
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  }

  Future<void> tap(WidgetTester t, String label, {bool realIo = true}) async {
    await t.ensureVisible(find.text(label).last);
    if (realIo) {
      await t.runAsync(() => t.tap(find.text(label).last));
    } else {
      await t.tap(find.text(label).last);
    }
    await t.pump();
    await t.pump(const Duration(milliseconds: 500));
  }

  Future<void> dropdown(
    WidgetTester t,
    String current,
    String next, {
    bool wait = true,
    bool realIo = true,
  }) async {
    await tap(t, current, realIo: realIo);
    await tap(t, next, realIo: realIo);
    if (wait) {
      await until(
        t,
        () =>
            member('marketLoading') == false &&
            member('enginesLoading') == false,
      );
      await t.pumpAndSettle();
    }
  }

  Future<void> engines(WidgetTester t) async {
    await dropdown(t, 'Stremio Addons', 'Torrent Engines');
    await until(t, () => member('enginesLoading') == false);
    await t.pumpAndSettle();
  }

  Future<void> tapInRow(WidgetTester t, String title, String action) async {
    final row = find
        .ancestor(
          of: find.text(title),
          matching: find.byWidgetPredicate(
            (w) => [
              'InstalledRow',
              'MarketRow',
              'EngineRow',
            ].any((suffix) => w.runtimeType.toString().endsWith(suffix)),
          ),
        )
        .first;
    final button = find.descendant(of: row, matching: find.text(action));
    await t.ensureVisible(button);
    await t.runAsync(() => t.tap(button));
    await t.pump();
    await t.pump(const Duration(milliseconds: 500));
  }

  Future<void> options(WidgetTester t, String name, String action) async {
    await tap(t, name);
    await tap(t, action);
  }

  Future<List<StremioAddon>> saved(WidgetTester t) async =>
      (await t.runAsync(StremioService.instance.getAddonsForManagement))!;
  Future<void> close(WidgetTester t) async {
    for (final release in releases) {
      release();
    }
    EngineRegistry.debugBeforePublish = null;
    await t.pumpWidget(const SizedBox.shrink());
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    ProfilePreferences.webDavSyncLocalChangeSink = null;
    MainPageBridge.focusTvSidebar = null;
    FilePicker.platform = previousPicker ?? HubPicker();
    UrlLauncherPlatform.instance = previousUrls;
    LocalEngineStorage.instance.resetProfileScope();
    StremioService.instance.invalidateCache();
    EngineRegistry.instance.invalidateProfileScope();
    ConfigLoader().clearCache();
    if (profiles != null) await t.runAsync(profiles!.close);
    AppStorage.debugReset();
    ProfileRuntime.debugReset();
    await t.runAsync(() => directory.delete(recursive: true));
    t.view.reset();
  }
}

Future<void> hubCase(
  WidgetTester t,
  Future<void> Function(AddonHubFixture) body, {
  bool warm = true,
  bool fallback = false,
  bool committed = false,
}) async {
  final f = AddonHubFixture();
  await http.runWithClient(() async {
    await t.runAsync(() => f.initialize(committed: committed));
    try {
      if (warm) await t.runAsync(() => f.warmMarket(fallback: fallback));
      await body(f);
    } finally {
      await f.close(t);
    }
  }, f.client);
}
