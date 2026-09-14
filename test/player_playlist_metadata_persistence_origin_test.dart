import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:debrify/models/playlist_view_mode.dart';
import 'package:debrify/models/tracking_source.dart';
import 'package:debrify/screens/video_player/widgets/controls.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/debrify_tv_database.dart';
import 'package:debrify/services/episode_info_service.dart';
import 'package:debrify/services/iptv_media_store.dart';
import 'package:debrify/services/movie_metadata_service.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/profiles/device_key_provider.dart';
import 'package:debrify/services/profiles/profile_registry.dart';
import 'package:debrify/services/profiles/profile_bootstrap.dart';
import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/services/secret_vault.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/services/stremio_service.dart';
import 'package:debrify/services/tvmaze_service.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/utils/app_storage.dart';
import 'package:debrify/widgets/video_output_lease.dart';
import 'package:flutter/foundation.dart' show debugPrintSynchronously;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:media_kit_video/media_kit_video.dart' as mkv;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// Origin pin for the playlist metadata persistence tail of
// _preloadEpisodeInfo: after TVMaze resolves a series imdb id and show
// poster, the host writes both back to the launch's playlist item through
// StorageService, keyed by the launch identifiers.
//
// The two native constructors are replaced through narrow test hooks.
// TVMaze is answered by canned HttpOverrides; no extracted fork owners are
// required. The current host lifecycle and public Controls remain real.
// Host metadata loading, store lookup and the persistence tail stay real lib
// code; nothing private on the State is touched.
class _Streams extends mk.PlatformPlayer {
  _Streams(mk.PlayerConfiguration config, this.unexpected)
    : super(configuration: config);
  final List<String> unexpected;
  final events = <String>[];
  final disposalEntered = Completer<void>();
  Future<void>? disposal;
  bool closed = false;
  bool readySent = false;

  Future<void> openMedia(mk.Playable playable, {required bool play}) async {
    if (playable is! mk.Media) throw StateError('Expected one external media');
    if (closed) {
      unexpected.add('open-after-dispose:${playable.uri}');
      throw StateError('External open after actual disposal');
    }
    events.add('open:${playable.uri}:play=$play');
    state = state.copyWith(
      playlist: mk.Playlist([playable]),
      playing: play,
      completed: false,
      position: const Duration(seconds: 1),
      duration: const Duration(seconds: 60),
      width: 1280,
      height: 720,
      tracks: const mk.Tracks(),
    );
    if (!readySent) {
      readySent = true;
      configuration.ready!();
    }
    playlistController.add(state.playlist);
    durationController.add(state.duration);
    tracksController.add(state.tracks);
    widthController.add(state.width);
    heightController.add(state.height);
    positionController.add(state.position);
    playingController.add(play);
  }

  Future<void> attachAudio(mk.AudioTrack track) async {
    events.add('audio:${track.id}');
    state = state.copyWith(track: state.track.copyWith(audio: track));
    trackController.add(state.track);
  }

  Future<void> selectSubtitle(mk.SubtitleTrack track) async {
    events.add('subtitle:${track.id}');
    state = state.copyWith(track: state.track.copyWith(subtitle: track));
    trackController.add(state.track);
  }

  Future<void> changePlaying(bool playing) async {
    events.add(playing ? 'play' : 'pause');
    state = state.copyWith(playing: playing);
    playingController.add(playing);
  }

  Future<void> seekTo(Duration target) async {
    events.add('seek:${target.inMilliseconds}');
    state = state.copyWith(position: target);
    positionController.add(target);
  }

  Future<void> changeRate(double value) async {
    events.add('rate:$value');
    state = state.copyWith(rate: value);
    rateController.add(value);
  }

  @override
  Future<void> dispose() {
    if (disposal != null) return disposal!;
    events.add('dispose-enter');
    disposalEntered.complete();
    return disposal = (() async {
      await super.dispose();
      closed = true;
      events.add('dispose-complete');
    })();
  }
}

class _Player implements mk.Player {
  _Player(this.backend);
  final _Streams backend;
  @override
  mk.PlatformPlayer get platform => backend;
  @override
  set platform(mk.PlatformPlayer? value) =>
      throw StateError('Unexpected replacement');
  @override
  mk.PlayerState get state => backend.state;
  @override
  mk.PlayerStream get stream => backend.stream;
  @override
  Future<void> open(mk.Playable playable, {bool play = true}) =>
      backend.openMedia(playable, play: play);
  @override
  Future<void> play() => backend.changePlaying(true);
  @override
  Future<void> pause() => backend.changePlaying(false);
  @override
  Future<void> seek(Duration target) => backend.seekTo(target);
  @override
  Future<void> setRate(double value) => backend.changeRate(value);
  @override
  Future<void> dispose() => backend.dispose();
  @override
  Future<void> setAudioTrack(mk.AudioTrack track) => backend.attachAudio(track);
  @override
  Future<void> setSubtitleTrack(mk.SubtitleTrack track) =>
      backend.selectSubtitle(track);
  @override
  dynamic noSuchMethod(Invocation invocation) {
    backend.unexpected.add('player:${invocation.memberName}');
    throw StateError('Unexpected player API ${invocation.memberName}');
  }
}

class _TexturelessVideo implements mkv.VideoController {
  _TexturelessVideo(this.player, this.unexpected);
  @override
  final mk.Player player;
  final List<String> unexpected;
  @override
  final platform = Completer<mkv.PlatformVideoController>();
  @override
  final notifier = ValueNotifier<mkv.PlatformVideoController?>(null);
  @override
  final id = ValueNotifier<int?>(null);
  @override
  final rect = ValueNotifier<Rect?>(null);

  void close() {
    notifier.dispose();
    id.dispose();
    rect.dispose();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    unexpected.add('video:${invocation.memberName}');
    throw StateError('Unexpected video API ${invocation.memberName}');
  }
}

class _Terminal {
  final construction = <String>[];
  final unexpected = <String>[];
  _Streams? properties;
  _Player? player;
  _TexturelessVideo? video;

  mk.Player createPlayer(mk.PlayerConfiguration configuration) {
    construction.add('player');
    expect(configuration.logLevel, mk.MPVLogLevel.error);
    expect(configuration.ready, isNotNull);
    if (properties != null) {
      unexpected.add('duplicate-player-construction');
      throw StateError('Second player outside this fixture contract');
    }
    properties = _Streams(configuration, unexpected);
    return player = _Player(properties!);
  }

  mkv.VideoController createVideoController(
    mk.Player player,
    mkv.VideoControllerConfiguration configuration,
  ) {
    construction.add('video');
    expect(player, same(this.player));
    if (video != null) {
      unexpected.add('duplicate-video-construction');
      throw StateError('Second video outside this fixture contract');
    }
    return video = _TexturelessVideo(player, unexpected);
  }
}

// ---------------------------------------------------------------------------
// Canned dart:io HTTP. package:http's IOClient goes through HttpClient(), which
// honours HttpOverrides, so this answers the host's real TVMaze service calls.
// ---------------------------------------------------------------------------

class _CannedHttp extends HttpOverrides {
  _CannedHttp(this.routesByPath);

  /// URL path -> JSON body. Anything else is an error, not a silent 400.
  final Map<String, String> routesByPath;
  final List<String> requests = [];
  Completer<void>? episodeGate;
  final episodeEntered = Completer<void>();

  @override
  HttpClient createHttpClient(SecurityContext? context) => _CannedClient(this);
}

class _CannedClient implements HttpClient {
  _CannedClient(this.fixture);
  final _CannedHttp fixture;

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    fixture.requests.add('$method ${url.host}${url.path}');
    if (url.path.endsWith('/episodes') && fixture.episodeGate != null) {
      if (!fixture.episodeEntered.isCompleted) {
        fixture.episodeEntered.complete();
      }
      await fixture.episodeGate!.future;
    }
    final body = fixture.routesByPath[url.path];
    if (body == null) {
      throw StateError('Unexpected request: $method $url');
    }
    return _CannedRequest(method, url, utf8.encode(body));
  }

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _CannedRequest implements HttpClientRequest {
  _CannedRequest(this.method, this.uri, this._body);

  @override
  final String method;
  @override
  final Uri uri;
  final List<int> _body;

  @override
  final HttpHeaders headers = _CannedHeaders({});
  @override
  bool followRedirects = true;
  @override
  int maxRedirects = 5;
  @override
  int contentLength = -1;
  @override
  bool persistentConnection = true;
  @override
  bool bufferOutput = true;

  late final _CannedResponse _response = _CannedResponse(_body, {
    'content-type': ['application/json'],
  });

  @override
  Future<void> addStream(Stream<List<int>> stream) => stream.drain<void>();

  @override
  void add(List<int> data) {}

  @override
  Future<HttpClientResponse> close() async => _response;

  @override
  Future<HttpClientResponse> get done async => _response;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _CannedResponse extends Stream<List<int>> implements HttpClientResponse {
  _CannedResponse(this._bytes, Map<String, List<String>> headerMap)
    : headers = _CannedHeaders(headerMap);

  final List<int> _bytes;

  @override
  final HttpHeaders headers;

  @override
  int get statusCode => 200;
  @override
  String get reasonPhrase => 'OK';
  @override
  int get contentLength => _bytes.length;
  @override
  bool get isRedirect => false;
  @override
  bool get persistentConnection => false;
  @override
  List<RedirectInfo> get redirects => const [];
  @override
  List<Cookie> get cookies => const [];
  @override
  X509Certificate? get certificate => null;
  @override
  HttpConnectionInfo? get connectionInfo => null;
  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream<List<int>>.value(_bytes).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _CannedHeaders implements HttpHeaders {
  _CannedHeaders(this._values);
  final Map<String, List<String>> _values;

  @override
  List<String>? operator [](String name) => _values[name.toLowerCase()];

  @override
  String? value(String name) => _values[name.toLowerCase()]?.join(', ');

  @override
  void forEach(void Function(String name, List<String> values) action) =>
      _values.forEach(action);

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    _values[name.toLowerCase()] = ['$value'];
  }

  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {
    _values.putIfAbsent(name.toLowerCase(), () => []).add('$value');
  }

  @override
  void remove(String name, Object value) {}

  @override
  void removeAll(String name) => _values.remove(name.toLowerCase());

  @override
  int contentLength = -1;
  @override
  bool chunkedTransferEncoding = false;
  @override
  bool persistentConnection = true;
  @override
  ContentType? contentType;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

// Observe the real storage facade at its platform boundary, including failed
// writes. No playlist update algorithm is reproduced by this fixture.
class _Preferences extends InMemorySharedPreferencesStore {
  _Preferences() : super.empty();
  final playlistWrites = <List<Map<String, dynamic>>>[];
  int? failPosterWrite;
  int posterWrites = 0;
  @override
  Future<bool> setValue(String type, String key, Object value) async {
    if (key.endsWith('user_playlist_v1')) {
      final items = (jsonDecode(value as String) as List)
          .cast<Map<String, dynamic>>();
      playlistWrites.add(items);
      if (items.any((item) => item.containsKey('posterUrl'))) {
        posterWrites++;
        if (posterWrites == failPosterWrite) {
          throw StateError('fixture write failed');
        }
      }
    }
    return super.setValue(type, key, value);
  }
}

// Fixture identities. The seeded store item carries only the RealDebrid id;
// the launch chooses which identifiers it hands the host.
const _rdId = 'rd-persist-origin-1';
const _tvmazeShowId = 4242;
const _showImdbId = 'tt0004242';
const _posterUrl = 'https://images.invalid/persist/original.jpg';

Map<String, dynamic> _show({required bool withImage}) => {
  'id': _tvmazeShowId,
  'name': 'Persist',
  'externals': {'imdb': _showImdbId, 'thetvdb': 1, 'tvrage': null},
  if (withImage)
    'image': {
      'medium': 'https://images.invalid/persist/medium.jpg',
      'original': _posterUrl,
    },
};

Map<String, String> _tvmazeRoutes({required bool withImage}) => {
  '/shows/1': jsonEncode({'id': 1, 'name': 'Under the Dome'}),
  '/search/shows': jsonEncode([
    {'score': 1.0, 'show': _show(withImage: withImage)},
  ]),
  '/lookup/shows': jsonEncode(_show(withImage: withImage)),
  '/shows/$_tvmazeShowId/episodes': jsonEncode([
    {'id': 1, 'season': 1, 'number': 1, 'name': 'One'},
    {'id': 2, 'season': 1, 'number': 2, 'name': 'Two'},
  ]),
};

const _entries = [
  PlaylistEntry(
    url: 'https://persist.invalid/e1.mp4',
    title: 'Persist.S01E01.mkv',
  ),
  PlaylistEntry(
    url: 'https://persist.invalid/e2.mp4',
    title: 'Persist.S01E02.mkv',
  ),
];

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const window = MethodChannel('window_manager');
  const brightness = MethodChannel('github.com/aaassseee/screen_brightness');
  const wake =
      'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle';
  late _Terminal terminal;
  late _Preferences preferences;
  ProfileRegistry? testRegistry;
  late HttpOverrides? previousOverrides;
  late _CannedHttp http;
  final printed = <String>[];
  Object? primaryFailure;
  StackTrace? primaryStack;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  setUp(() async {
    previousOverrides = HttpOverrides.current;
    terminal = _Terminal();
    printed.clear();
    SharedPreferences.setMockInitialValues({});
    preferences = _Preferences();
    SharedPreferencesStorePlatform.instance = preferences;
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    DeviceKeyProvider.debugInstallCipher(
      MemoryDeviceSecretCipher(List<int>.filled(32, 7)),
    );
    SecretVault.debugReset(deviceIdOverride: 'metadata-persistence-origin');
    StorageService.resetProfileCaches();
    final root = await Directory(
      '.dart_tool',
    ).absolute.createTemp('metadata-persistence-');
    AppStorage.debugOverride(documents: root, support: root, cache: root);
    await DebrifyTvDatabase.instance.debugResetScopeState();
    IptvMediaStore.debugResetMigration();
    await DebrifyTvDatabase.instance.database;
    MovieMetadataService.clearCache();
    EpisodeInfoService.clearCache();
    await TVMazeService.clearCache();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(window, (
      call,
    ) async {
      switch (call.method) {
        case 'setFullScreen':
        case 'setBounds':
          return null;
        case 'getBounds':
          return {'x': 0.0, 'y': 0.0, 'width': 1280.0, 'height': 720.0};
        case 'isFullScreen':
          return false;
        default:
          terminal.unexpected.add('window:${call.method}');
          throw StateError('Unexpected window call ${call.method}');
      }
    });
    binding.defaultBinaryMessenger.setMockMessageHandler(
      wake,
      (_) async => const StandardMessageCodec().encodeMessage([null]),
    );
    binding.defaultBinaryMessenger.setMockMethodCallHandler(brightness, (
      call,
    ) async {
      if (call.method == 'resetApplicationScreenBrightness') return null;
      terminal.unexpected.add('brightness:${call.method}');
      throw StateError('Unexpected brightness call ${call.method}');
    });
    VideoPlayerScreen.debugPlayerFactory = terminal.createPlayer;
    VideoPlayerScreen.debugVideoControllerFactory =
        terminal.createVideoController;
  });

  tearDown(() async {
    try {
      if (terminal.properties != null && !terminal.properties!.closed) {
        await terminal.properties!.dispose();
      }
      terminal.video?.close();
      await DebrifyTvDatabase.instance.debugResetScopeState();
      expect(VideoPlayerScreen.debugPlayerFactory, terminal.createPlayer);
    } catch (error, stack) {
      debugPrintSynchronously('PERSISTENCE_TEARDOWN $error\n$stack');
      if (primaryFailure != null) {
        Error.throwWithStackTrace(primaryFailure!, primaryStack!);
      }
      rethrow;
    } finally {
      HttpOverrides.global = previousOverrides;
      IptvMediaStore.debugResetMigration();
      VideoPlayerScreen.debugPlayerFactory = null;
      VideoPlayerScreen.debugVideoControllerFactory = null;
      binding.defaultBinaryMessenger.setMockMethodCallHandler(window, null);
      binding.defaultBinaryMessenger.setMockMethodCallHandler(brightness, null);
      binding.defaultBinaryMessenger.setMockMessageHandler(wake, null);
      StorageService.resetProfileCaches();
      AppStorage.debugReset();
      ProfileRuntime.debugReset();
      ProfileBootstrap.debugInstallRegistry(null);
      await testRegistry?.close();
      testRegistry = null;
      SecretVault.debugReset();
      DeviceKeyProvider.debugReset();
    }
  });

  Future<Map<String, dynamic>> seededItem(WidgetTester tester) async {
    final items = await tester.runAsync(StorageService.getPlaylistItemsRaw);
    expect(items, hasLength(1));
    expect(items!.single['rdTorrentId'], _rdId);
    return items.single;
  }

  // Fixed feasibility bound: 200 frame/event turns, 50ms per frame. The root
  // event turn lets the store's real prefs Futures settle; no sleep.
  Future<void> settle(
    WidgetTester tester,
    Future<bool> Function() probe, {
    required String phase,
  }) async {
    for (var i = 0; i < 200; i++) {
      if (await tester.runAsync(probe) == true) return;
      await tester.pump(const Duration(milliseconds: 50));
    }
    fail('Phase did not complete: $phase');
  }

  Future<void> withHost(
    WidgetTester tester, {
    required Map<String, String> routes,
    required VideoPlayerScreen launch,
    required Future<void> Function() exercise,
    List<Map<String, dynamic>>? seedItems,
    Completer<void>? episodeGate,
  }) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    primaryFailure = null;
    primaryStack = null;
    http = _CannedHttp(routes)..episodeGate = episodeGate;
    HttpOverrides.global = http;
    await runZoned(
      () async {
        try {
          await tester.runAsync(() async {
            await StorageService.setTrackingScrobbleTargets({});
            await StorageService.setWatchProgressSource(
              WatchProgressSource.local,
            );
            await StorageService.setHomeTickSources({});
            await StremioService.instance.clearAllAddons();
            await StorageService.savePlaylistItemsRaw(
              seedItems ??
                  [
                    {
                      'title': 'Persist',
                      'provider': 'realdebrid',
                      'rdTorrentId': _rdId,
                    },
                  ],
            );
          });
          final before = await tester.runAsync(
            StorageService.getPlaylistItemsRaw,
          );
          expect(
            before!.every(
              (item) =>
                  !item.containsKey('imdbId') && !item.containsKey('posterUrl'),
            ),
            isTrue,
          );
          preferences.playlistWrites.clear();
          await tester.pumpWidget(
            MaterialApp(
              builder: (_, child) => AppThemeScope(
                theme: AppThemes.byId('spotlight'),
                child: child!,
              ),
              home: launch,
            ),
          );
          await settle(
            tester,
            () async =>
                terminal.video != null &&
                find.byType(Controls).evaluate().isNotEmpty,
            phase: 'open playlist entry and mount controls',
          );
          expect(terminal.construction, ['player', 'video']);
          expect(
            terminal.properties!.events.where((e) => e.startsWith('open:')),
            ['open:${_entries.first.url}:play=true'],
          );
          await exercise();
          expect(terminal.unexpected, isEmpty);
        } catch (error, stack) {
          primaryFailure = error;
          primaryStack = stack;
          debugPrintSynchronously('PERSISTENCE_PRIMARY $error\n$stack');
          rethrow;
        } finally {
          if (episodeGate != null && !episodeGate.isCompleted) {
            episodeGate.complete();
          }
          try {
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pump(const Duration(milliseconds: 250));
            final backend = terminal.properties;
            if (backend != null) {
              await tester.runAsync(() async {
                await backend.disposalEntered.future.timeout(
                  const Duration(seconds: 5),
                );
                await backend.disposal!.timeout(const Duration(seconds: 5));
              });
              expect(backend.closed, isTrue);
            }
            expect(VideoOutputLease.isHeld, isFalse);
            expect(terminal.unexpected, isEmpty);
          } catch (error, stack) {
            debugPrintSynchronously('PERSISTENCE_CLEANUP $error\n$stack');
            if (primaryFailure != null) {
              Error.throwWithStackTrace(primaryFailure!, primaryStack!);
            }
            rethrow;
          }
        }
      },
      zoneSpecification: ZoneSpecification(
        print: (self, parent, zone, line) {
          printed.add(line);
          parent.print(zone, line);
        },
      ),
    );
  }

  VideoPlayerScreen launch({
    String? rdTorrentId,
    String? torboxTorrentId,
    String? pikpakCollectionId,
    String? contentImdbId,
  }) => VideoPlayerScreen(
    videoUrl: _entries.first.url,
    title: 'Persist',
    playlist: _entries,
    startIndex: 0,
    disableAutoResume: true,
    viewMode: PlaylistViewMode.series,
    contentType: 'series',
    contentImdbId: contentImdbId,
    rdTorrentId: rdTorrentId,
    torboxTorrentId: torboxTorrentId,
    pikpakCollectionId: pikpakCollectionId,
    startFromRandom: false,
    traktScrobble: false,
    simklScrobble: false,
    mdblistScrobble: false,
  );

  const noIdentifier = '  ⚠️ No valid identifier found, skipping poster save';
  const noPoster = '  ⚠️ No poster URL from fetchEpisodeInfo';
  int printedCount(String line) => printed.where((s) => s == line).length;

  testWidgets(
    'series launch with rdTorrentId persists discovered imdb id and show poster',
    (tester) async {
      await withHost(
        tester,
        routes: _tvmazeRoutes(withImage: true),
        launch: launch(rdTorrentId: _rdId),
        exercise: () async {
          await settle(tester, () async {
            final items = await StorageService.getPlaylistItemsRaw();
            return items.single['posterUrl'] == _posterUrl;
          }, phase: 'poster persisted to the RealDebrid playlist item');
          final item = await seededItem(tester);
          expect(item['imdbId'], _showImdbId);
          expect(item['posterUrl'], _posterUrl);
          expect(printedCount('  Poster URL: $_posterUrl'), 1);
          expect(printedCount(noIdentifier), 0);
          expect(printedCount(noPoster), 0);
          expect(http.requests, [
            'GET api.tvmaze.com/shows/1',
            'GET api.tvmaze.com/search/shows',
            'GET api.tvmaze.com/shows/$_tvmazeShowId/episodes',
          ]);
        },
      );
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  testWidgets(
    'series launch without any identifier writes neither imdb id nor poster',
    (tester) async {
      await withHost(
        tester,
        routes: _tvmazeRoutes(withImage: true),
        launch: launch(),
        exercise: () async {
          await settle(
            tester,
            () async => printedCount(noIdentifier) == 1,
            phase: 'poster save skipped for a launch without identifiers',
          );
          await tester.pump(const Duration(milliseconds: 500));
          final item = await seededItem(tester);
          expect(item.containsKey('imdbId'), isFalse);
          expect(item.containsKey('posterUrl'), isFalse);
          expect(printedCount('  Poster URL: $_posterUrl'), 0);
          expect(http.requests, [
            'GET api.tvmaze.com/shows/1',
            'GET api.tvmaze.com/search/shows',
            'GET api.tvmaze.com/shows/$_tvmazeShowId/episodes',
          ]);
        },
      );
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  testWidgets(
    'series launch whose show has no image persists the imdb id only',
    (tester) async {
      await withHost(
        tester,
        routes: _tvmazeRoutes(withImage: false),
        launch: launch(rdTorrentId: _rdId),
        exercise: () async {
          await settle(
            tester,
            () async => printedCount(noPoster) == 1,
            phase: 'poster save skipped for a show without an image',
          );
          await tester.pump(const Duration(milliseconds: 500));
          final item = await seededItem(tester);
          expect(item['imdbId'], _showImdbId);
          expect(item.containsKey('posterUrl'), isFalse);
          expect(printedCount(noIdentifier), 0);
        },
      );
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  testWidgets(
    'series launch with a catalog imdb id keeps the item imdb untouched and persists the poster',
    (tester) async {
      await withHost(
        tester,
        routes: _tvmazeRoutes(withImage: true),
        launch: launch(rdTorrentId: _rdId, contentImdbId: _showImdbId),
        exercise: () async {
          await settle(tester, () async {
            final items = await StorageService.getPlaylistItemsRaw();
            return items.single['posterUrl'] == _posterUrl;
          }, phase: 'poster persisted for a catalog-launched series');
          final item = await seededItem(tester);
          expect(item.containsKey('imdbId'), isFalse);
          expect(item['posterUrl'], _posterUrl);
          // A launch-time imdb id also starts the host's skip-segment lookups;
          // the canned client rejects those and lib logs the failure. Only the
          // TVMaze traffic is this pin's subject.
          expect(http.requests.where((r) => r.contains('api.tvmaze.com')), [
            'GET api.tvmaze.com/shows/1',
            'GET api.tvmaze.com/lookup/shows',
            'GET api.tvmaze.com/shows/$_tvmazeShowId/episodes',
          ]);
        },
      );
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  for (final provider in ['torbox', 'pikpak']) {
    testWidgets(
      '$provider launch updates through the unchanged storage facade',
      (tester) async {
        await withHost(
          tester,
          routes: _tvmazeRoutes(withImage: true),
          seedItems: [
            {
              'title': 'Persist',
              if (provider == 'torbox') 'torboxTorrentId': 42,
              if (provider == 'pikpak') 'pikpakFileIds': ['pikpak-origin'],
            },
          ],
          launch: launch(
            torboxTorrentId: provider == 'torbox' ? '42' : null,
            pikpakCollectionId: provider == 'pikpak' ? 'pikpak-origin' : null,
          ),
          exercise: () async {
            await settle(
              tester,
              () async =>
                  (await StorageService.getPlaylistItemsRaw())
                      .single['posterUrl'] ==
                  _posterUrl,
              phase: 'provider poster',
            );
            final items = await tester.runAsync(
              StorageService.getPlaylistItemsRaw,
            );
            expect(items!.single['imdbId'], _showImdbId);
            expect(items.single['posterUrl'], _posterUrl);
          },
        );
      },
    );
  }

  testWidgets(
    'multiple launch identifiers preserve IMDb selection then ordered poster writes',
    (tester) async {
      await withHost(
        tester,
        routes: _tvmazeRoutes(withImage: true),
        seedItems: [
          {'title': 'RD', 'rdTorrentId': _rdId},
          {'title': 'TorBox', 'torboxTorrentId': '42'},
          {
            'title': 'PikPak',
            'pikpakFileIds': ['pikpak-origin'],
          },
        ],
        launch: launch(
          rdTorrentId: _rdId,
          torboxTorrentId: '42',
          pikpakCollectionId: 'pikpak-origin',
        ),
        exercise: () async {
          await settle(
            tester,
            () async =>
                (await StorageService.getPlaylistItemsRaw())
                    .last['posterUrl'] ==
                _posterUrl,
            phase: 'all ordered posters',
          );
          expect(
            preferences.playlistWrites.map(
              (items) => items
                  .where((item) => item.containsKey('posterUrl'))
                  .map((item) => item['title'])
                  .toList(),
            ),
            [
              [],
              ['RD'],
              ['RD', 'TorBox'],
              ['RD', 'TorBox', 'PikPak'],
            ],
          );
          final items = await tester.runAsync(
            StorageService.getPlaylistItemsRaw,
          );
          expect(items!.map((item) => item['imdbId']).toList(), [
            _showImdbId,
            null,
            null,
          ]);
        },
      );
    },
  );

  testWidgets(
    'poster write exception stops later providers and stays optional',
    (tester) async {
      preferences.failPosterWrite = 2;
      await withHost(
        tester,
        routes: _tvmazeRoutes(withImage: true),
        seedItems: [
          {'title': 'RD', 'rdTorrentId': _rdId},
          {'title': 'TorBox', 'torboxTorrentId': '42'},
          {
            'title': 'PikPak',
            'pikpakFileIds': ['pikpak-origin'],
          },
        ],
        launch: launch(
          rdTorrentId: _rdId,
          torboxTorrentId: '42',
          pikpakCollectionId: 'pikpak-origin',
        ),
        exercise: () async {
          await settle(
            tester,
            () async => preferences.posterWrites == 2,
            phase: 'poster failure',
          );
          await tester.pump(const Duration(milliseconds: 500));
          expect(preferences.posterWrites, 2);
          expect(
            preferences.playlistWrites.last.last.containsKey('posterUrl'),
            isFalse,
          );
          expect(tester.takeException(), isNull);
        },
      );
    },
  );

  testWidgets(
    'late metadata after host disposal does not persist playlist fields',
    (tester) async {
      final gate = Completer<void>();
      await withHost(
        tester,
        routes: _tvmazeRoutes(withImage: true),
        episodeGate: gate,
        launch: launch(rdTorrentId: _rdId),
        exercise: () async {
          await settle(
            tester,
            () async => http.episodeEntered.isCompleted,
            phase: 'held episode metadata',
          );
          await tester.pumpWidget(const SizedBox.shrink());
          gate.complete();
          await settle(
            tester,
            () async => printed.any(
              (line) => line.contains('Fetched 2 episodes upfront'),
            ),
            phase: 'late model completion',
          );
          await tester.pump(const Duration(milliseconds: 500));
          final item = await seededItem(tester);
          expect(item.containsKey('imdbId'), isFalse);
          expect(item.containsKey('posterUrl'), isFalse);
          expect(preferences.playlistWrites, isEmpty);
        },
      );
    },
  );

  testWidgets(
    'held metadata retains captured profile ownership after another profile activates',
    (tester) async {
      final profiles = (await tester.runAsync(() async {
        final root = await AppStorage.support();
        final registry = await ProfileRegistry.open(
          path: '${root.path}/profiles.db',
        );
        testRegistry = registry;
        final a = await registry.createProfile(
          name: 'First',
          role: UserProfileRole.admin,
        );
        final b = await registry.createProfile(
          name: 'Second',
          role: UserProfileRole.admin,
        );
        await registry.commitBootstrap(
          activeProfileId: a.id,
          migratedLegacyInstall: false,
        );
        ProfileBootstrap.debugInstallRegistry(registry);
        return (a: a.id, b: b.id);
      }))!;
      final first = ProfileScope(
        profileId: profiles.a,
        dataGeneration: 1,
        sessionEpoch: 1,
      );
      final second = ProfileScope(
        profileId: profiles.b,
        dataGeneration: 1,
        sessionEpoch: 2,
      );
      ProfileRuntime.debugReset();
      ProfileRuntime.initializeCommitted(first);
      await tester.runAsync(() async {
        await DebrifyTvDatabase.instance.database;
      });
      final gate = Completer<void>();
      await ProfileRuntime.withCapturedScope(
        first,
        () => withHost(
          tester,
          routes: _tvmazeRoutes(withImage: true),
          episodeGate: gate,
          launch: launch(rdTorrentId: _rdId),
          exercise: () async {
            await settle(
              tester,
              () async => http.episodeEntered.isCompleted,
              phase: 'captured held metadata',
            );
            ProfileRuntime.publish(second);
            await tester.runAsync(
              () => ProfileRuntime.withCapturedScope(
                second,
                () => StorageService.savePlaylistItemsRaw([
                  {'title': 'Other profile', 'rdTorrentId': _rdId},
                ]),
              ),
            );
            gate.complete();
            await settle(
              tester,
              () async =>
                  (await StorageService.getPlaylistItemsRaw())
                      .single['posterUrl'] ==
                  _posterUrl,
              phase: 'origin profile persisted',
            );
            final own = await seededItem(tester);
            expect(own['imdbId'], _showImdbId);
            final other = await tester.runAsync(
              () => ProfileRuntime.withCapturedScope(
                second,
                StorageService.getPlaylistItemsRaw,
              ),
            );
            expect(other!.single['title'], 'Other profile');
            expect(other.single.containsKey('imdbId'), isFalse);
            expect(other.single.containsKey('posterUrl'), isFalse);
          },
        ),
      );
    },
  );
}
