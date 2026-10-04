import 'dart:async';
import 'dart:convert';

import 'package:debrify/models/rd_file_node.dart';
import 'package:debrify/models/series_playlist.dart';
import 'package:debrify/models/webdav_item.dart';
import 'package:debrify/screens/playlist_content_view_screen.dart';
import 'package:debrify/services/android_tv_player_bridge.dart';
import 'package:debrify/services/episode_info_service.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/secret_vault.dart';
import 'package:debrify/services/storage/playlist_preferences_storage.dart';
import 'package:debrify/services/storage/webdav_server_storage.dart';
import 'package:debrify/services/tvmaze_service.dart';
import 'package:debrify/services/text_brightness.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_adapter.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'playlist_content_images.dart';

Map<String, dynamic> contentItem(String provider) => {
  'provider': provider,
  'title': 'Fixture collection',
  'rdTorrentId': 'rd9',
  'torboxTorrentId': 91,
  'torrent_hash': 'abc123',
  'pikpakFileId': 'folder-z9',
  'webdavServerId': 'server-9',
  'webdavBaseUrl': 'https://webdav.test/dav',
  'webdavFolderPath': '/Pack',
  'webdavFiles': [
    {'path': '/Pack/10. Ten.mkv', 'sizeBytes': 200000000},
    {'path': '/Pack/2. Two.mkv', 'sizeBytes': 300000000},
    {'path': '/Pack/readme.txt', 'sizeBytes': 7},
  ],
};

Map<String, dynamic> contentPikpakFile(
  String id,
  String name, {
  bool folder = false,
}) => {
  'id': id,
  'name': name,
  'kind': folder ? 'drive#folder' : 'drive#file',
  'size': '200000000',
  'phase': 'PHASE_TYPE_COMPLETE',
  'mime_type': 'video/x-matroska',
  'web_content_link': 'https://stream.test/$id.mkv',
};

class PlaylistContentObserver extends NavigatorObserver {
  final popped = <Route<dynamic>>[];
  final pushed = <Route<dynamic>>[];
  final events = <String>[];
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushed.add(route);
    events.add(route is DialogRoute ? 'dialog push' : 'route push');
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    popped.add(route);
    events.add(route is DialogRoute ? 'dialog pop' : 'route pop');
  }
}

class PlaylistContentFixture {
  final key = GlobalKey<State<PlaylistContentViewScreen>>();
  final navigatorKey = GlobalKey<NavigatorState>();
  final observer = PlaylistContentObserver();
  final requests = <http.Request>[];
  final events = <String>[];
  final pages = <String, List<Map<String, dynamic>>>{};
  final held = <String, Completer<http.Response>>{};
  final failures = <String>{};
  Future<void> Function(http.Request)? onRequest;
  Map<String, dynamic> item = contentItem('realdebrid');
  List<Map<String, dynamic>> files = [
    {'id': 9, 'path': '/Pack/10. Ten.mkv', 'bytes': 200000000, 'selected': 1},
    {'id': 2, 'path': '/Pack/2. Two.mkv', 'bytes': 300000000, 'selected': 1},
    {'id': 5, 'path': '/Pack/readme.txt', 'bytes': 7, 'selected': 1},
  ];
  String? metadataImdb;
  String? metadataPoster;
  int torboxFailures = 0;
  bool failUnlock = false;
  Map<String, Object?> get access =>
      playlistContentTestAccess(key.currentState!);
  dynamic member(String name) => access[name];
  RDFileNode get root => member('rootContent') as RDFileNode;
  List<RDFileNode> get visible =>
      (member('currentViewNodes') as List).cast<RDFileNode>();
  SeriesPlaylist get series => member('seriesPlaylist') as SeriesPlaylist;
  Map<String, Map<String, dynamic>> get progress =>
      member('fileProgressCache') as Map<String, Map<String, dynamic>>;
  List<String> get log =>
      requests.map((r) => '${r.method} ${r.url.host}${r.url.path}').toList();
  http.Response json(Object body, [int status = 200]) => http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json'},
  );
  List<Map<String, dynamic>> get videos =>
      files.where((r) => r['path'].toString().endsWith('.mkv')).toList();
  String name(Map<String, dynamic> file) =>
      file['path'].toString().split('/').last;
  Future<http.Response> respond(http.Request r) async {
    requests.add(r);
    await onRequest?.call(r);
    final path = r.url.path;
    if (held.containsKey(path)) {
      return held[path]!.future;
    }
    if (failures.contains(path)) {
      return json({'error': 'fixture failure'}, 500);
    }
    switch (r.url.host) {
      case 'api.real-debrid.com':
        if (path == '/rest/1.0/torrents/info/rd9') {
          return json({
            'files': files,
            'links': [for (final f in files) 'https://locked.test/${f['id']}'],
          });
        }
        if (path == '/rest/1.0/unrestrict/link') {
          if (failUnlock) {
            return json({'error': 'fixture unlock'}, 400);
          }
          return json({'download': 'https://stream.test/start.mkv'});
        }
      case 'api.alldebrid.com':
        if (path == '/v4/magnet/upload') {
          return json({
            'status': 'success',
            'data': {
              'magnets': [
                {'id': 71, 'name': 'Pack', 'ready': true},
              ],
            },
          });
        }
        if (path == '/v4/magnet/files') {
          return json({
            'status': 'success',
            'data': {
              'magnets': [
                {
                  'files': [
                    for (final f in files)
                      {
                        'n': name(f),
                        's': f['bytes'],
                        'l': 'https://locked.test/${f['id']}',
                      },
                  ],
                },
              ],
            },
          });
        }
        if (path == '/v4/link/unlock') {
          if (failUnlock) {
            return json({
              'status': 'error',
              'error': {'message': 'fixture unlock'},
            }, 400);
          }
          return json({
            'status': 'success',
            'data': {'link': 'https://stream.test/start.mkv'},
          });
        }
      case 'api.torbox.app':
        if (path == '/v1/api/torrents/mylist') {
          if (torboxFailures-- > 0) {
            return json({'success': false}, 500);
          }
          return json({
            'success': true,
            'data': {
              'id': 91,
              'name': 'Pack',
              'created_at': '2026-01-01T00:00:00Z',
              'updated_at': '2026-01-02T00:00:00Z',
              'download_state': 'cached',
              'files': [
                for (final f in files)
                  {
                    'id': f['id'],
                    'name': f['path'].toString().replaceFirst('/', ''),
                    'short_name': name(f),
                    'size': f['bytes'],
                  },
              ],
            },
          });
        }
        if (path == '/v1/api/torrents/requestdl') {
          return json({
            'success': true,
            'data': 'https://stream.test/start.mkv',
          });
        }
      case 'api-drive.mypikpak.com':
        if (path == '/drive/v1/files') {
          final parent = r.url.queryParameters['parent_id'] ?? '';
          return json({
            'files':
                pages[parent] ??
                [
                  for (final f in files)
                    {
                      ...contentPikpakFile('file-${f['id']}', name(f)),
                      'size': f['bytes'].toString(),
                    },
                ],
          });
        }
        if (path.startsWith('/drive/v1/files/')) {
          return json(contentPikpakFile(path.split('/').last, 'Start.mkv'));
        }
      case 'www.premiumize.me':
        if (path == '/api/transfer/directdl') {
          return json({
            'status': 'success',
            'content': [
              for (final f in files)
                {
                  'path': f['path'],
                  'size': f['bytes'],
                  'link': 'https://stream.test/${f['id']}.mkv',
                },
            ],
          });
        }
        if (path == '/api/item/details') {
          return json({
            'status': 'success',
            'name': 'Cloud.mkv',
            'link': 'https://stream.test/cloud.mkv',
            'size': 200000000,
          });
        }
      case 'api.tvmaze.com':
        if (path.endsWith('/episodes')) {
          return json([
            for (final season in [1, 2])
              for (var episode = 1; episode <= 20; episode++)
                {
                  'id': season * 10 + episode,
                  'name': 'Episode $episode',
                  'season': season,
                  'number': episode,
                  'airdate': '2026-01-01',
                  'runtime': 45,
                  'summary': '<p>Fixture plot</p>',
                  'rating': {'average': 8.0},
                  'image': {
                    'original': 'https://artwork.test/episode.png',
                    'medium': 'https://artwork.test/episode.png',
                  },
                },
          ]);
        }
        if (path == '/search/shows') {
          return json([
            {
              'score': 1,
              'show': {
                'id': 41,
                'name': 'Fixture',
                'image': null,
                'externals': {'imdb': null},
              },
            },
          ]);
        }
        return json({
          'id': path == '/shows/42' ? 42 : 41,
          'name': 'Fixture',
          'image': metadataPoster == null
              ? null
              : {
                  'original': metadataPoster,
                  'medium': 'https://artwork.test/medium.png',
                },
          'externals': {'imdb': metadataImdb},
          'genres': ['Drama'],
        });
    }
    throw StateError('Unexpected fixture request: ${r.method} ${r.url}');
  }

  Future<void> mount(
    WidgetTester t, {
    String? provider,
    String? mode = 'raw',
    bool wait = true,
    bool pushed = false,
    bool playlistCaller = false,
    VoidCallback? started,
    double width = 1000,
  }) async {
    if (provider != null) {
      item['provider'] = provider;
    }
    if (mode != null) {
      await t.runAsync(
        () => PlaylistPreferencesStorage.savePlaylistItemViewMode(item, mode),
      );
    }
    t.view.physicalSize = Size(width, 800);
    t.view.devicePixelRatio = 1;
    Widget screen() => RepaintBoundary(
      key: const ValueKey('playlist-content-canvas'),
      child: PlaylistContentViewScreen(
        key: key,
        playlistItem: item,
        onPlaybackStarted: started,
      ),
    );
    await t.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        navigatorObservers: [observer],
        theme: AppThemeAdapter.legacy(TextBrightness.bright),
        builder: (_, child) =>
            AppThemeScope(theme: AppThemes.legacy, child: child!),
        home: pushed ? const Scaffold(body: Text('Caller')) : screen(),
      ),
    );
    if (pushed) {
      navigatorKey.currentState!.push(
        MaterialPageRoute<void>(
          builder: (context) => playlistCaller
              ? PlaylistContentViewScreen(
                  key: key,
                  playlistItem: item,
                  onPlaybackStarted: () => Navigator.of(context).pop(),
                )
              : screen(),
        ),
      );
      await t.pump();
    }
    if (wait) {
      await until(
        t,
        () =>
            member('isLoading') == false &&
            (member('errorMessage') != null ||
                member('currentViewNodes') != null),
      );
      if (member('seriesPlaylist') != null && series.isSeries) {
        await until(t, () => member('isLoadingSeriesMetadata') == false);
      }
    }
    await t.pump(const Duration(milliseconds: 600));
    await t.pump();
    await until(
      t,
      () => PaintingBinding.instance.imageCache.pendingImageCount == 0,
    );
  }

  Future<void> until(WidgetTester t, bool Function() ready) async {
    for (var i = 0; i < 200 && !ready(); i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await t.pump(const Duration(milliseconds: 10));
    }
    expect(
      ready(),
      isTrue,
      reason: 'Original playlist content action did not finish',
    );
  }

  Future<void> invoke(WidgetTester t, Future<void> Function() action) async {
    await t.runAsync(action);
    await t.pump();
  }

  Future<void> close(WidgetTester t) async {
    await t.pumpWidget(const SizedBox.shrink());
    EpisodeInfoService.dispose();
    await t.pump(const Duration(seconds: 3));
    await t.pump();
    t.view.reset();
    expect(t.takeException(), isNull);
  }
}

class PlaylistContentProbe {
  final PlaylistContentFixture fixture;
  int calls = 0;
  int stops = 0;
  PlaylistContentProbe(this.fixture);
  void launching() {
    calls++;
    fixture.events.add('launch $calls');
    if (calls == 2) {
      throw NativePlayerSettingsUnavailable();
    }
  }

  void stopped() {
    stops++;
    fixture.events.add('stopped');
  }

  void install() {
    MainPageBridge.addPlayerLaunchListener(launching);
    MainPageBridge.addContentPlaybackStopListener(stopped);
  }

  void remove() {
    MainPageBridge.removePlayerLaunchListener(launching);
    MainPageBridge.removeContentPlaybackStopListener(stopped);
    MainPageBridge.notifyContentPlaybackStopped();
  }
}

bool _fontsLoaded = false;

Future<void> playlistContentCase(
  WidgetTester t,
  Future<void> Function(PlaylistContentFixture) body, {
  Map<String, Object> preferences = const {},
}) async {
  AppThemeAdapter.debugUseTestTypography = true;
  if (!_fontsLoaded) {
    await t.runAsync(() async {
      for (final family in ['Roboto', 'Inter', 'Poppins']) {
        await (FontLoader(
          family,
        )..addFont(rootBundle.load('assets/fonts/$family-Regular.ttf'))).load();
      }
    });
    _fontsLoaded = true;
  }
  SharedPreferences.setMockInitialValues({
    'real_debrid_api_key': 'fixture-rd',
    'torbox_api_key': 'fixture-torbox',
    'alldebrid_api_key': 'fixture-alldebrid',
    'premiumize_api_key': 'fixture-premiumize',
    'pikpak_enabled': true,
    'pikpak_email': 'fixture@example.test',
    'pikpak_access_token': 'fixture-access',
    'pikpak_refresh_token': 'fixture-refresh',
    ...preferences,
  });
  ProfileRuntime.debugReset();
  ProfileRuntime.initializeLegacy();
  SecretVault.debugReset(deviceIdOverride: 'playlist-content-characterization');
  EpisodeInfoService.dispose();
  MainPageBridge.setActiveTab('playlist');
  final previousImages = debugNetworkImageHttpClientProvider;
  final images = (await t.runAsync(PlaylistContentImages.load))!;
  debugNetworkImageHttpClientProvider = () => images;
  final f = PlaylistContentFixture();
  try {
    await http.runWithClient(() async {
      await t.runAsync(() async {
        await TVMazeService.clearCache();
        await TVMazeService.refreshAvailability();
        await WebdavServerStorage.saveWebDavServers(const [
          WebDavConfig(
            id: 'server-9',
            name: 'Fixture',
            baseUrl: 'https://webdav.test/dav',
            username: 'fixture-user',
            password: 'fixture-pass',
          ),
        ]);
      });
      f.requests.clear();
      try {
        await body(f);
      } finally {
        await f.close(t);
      }
    }, () => MockClient(f.respond));
  } finally {
    debugNetworkImageHttpClientProvider = previousImages;
    EpisodeInfoService.dispose();
    MainPageBridge.hideAutoLaunchOverlay = null;
    MainPageBridge.setActiveTab(null);
    ProfileRuntime.debugReset();
    SecretVault.debugReset();
    AppThemeAdapter.debugUseTestTypography = false;
  }
}
