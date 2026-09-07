import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:collection/collection.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:debrify/services/storage/tracking_prefs.dart';
import 'package:debrify/services/simkl/simkl_constants.dart';
import 'package:debrify/screens/video_player/services/player_terminal_backend.dart';
import 'package:debrify/screens/video_player/widgets/controls.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/widgets/series_browser.dart';
import 'package:debrify/services/storage/playback_progress_store.dart';
import 'package:debrify/services/debrify_tv_database.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/secret_vault.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/utils/app_storage.dart';
import 'package:debrify/widgets/video_output_lease.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'
    show DebugPrintCallback, debugPrintSynchronously;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:media_kit_video/media_kit_video.dart' as mkv;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// Construction-assisted origin: real host, SeriesBrowser callback, policy,
// stores and ResumeController. Only external playback IO/state is scripted.
// This is not native decoding, renderer, guide policy or identity-race proof.
class _Streams extends mk.PlatformPlayer {
  _Streams(mk.PlayerConfiguration config, this.unexpected)
    : super(configuration: config);
  final List<String> unexpected;
  final events = <String>[];
  final seeks = <(String, Duration)>[];
  final disposalEntered = Completer<void>();
  Future<void>? disposal;
  bool closed = false;
  bool readySent = false;

  Future<void> openMedia(mk.Playable playable, {required bool play}) async {
    if (playable is! mk.Media) throw StateError('Expected one external media');
    events.add('open:${playable.uri}');
    state = state.copyWith(
      playlist: mk.Playlist([playable]),
      playing: play,
      completed: false,
      position: const Duration(seconds: 1),
      duration: const Duration(seconds: 60),
      width: 1280,
      height: 720,
      tracks: const mk.Tracks(
        subtitle: [mk.SubtitleTrack('1', 'Fixture', 'en')],
      ),
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

  Future<void> changePlaying(bool playing) async {
    events.add(playing ? 'play' : 'pause');
    state = state.copyWith(playing: playing);
    playingController.add(playing);
  }

  Future<void> seekTo(Duration target) async {
    final uri = state.playlist.medias.single.uri;
    events.add('seek:$uri:${target.inMilliseconds}');
    seeks.add((uri, target));
    state = state.copyWith(position: target);
    positionController.add(target);
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

  Future<void> changeRate(double value) async {
    events.add('rate:$value');
    state = state.copyWith(rate: value);
    rateController.add(value);
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

class _Terminal extends PlayerTerminalBackend {
  final construction = <String>[];
  final unexpected = <String>[];
  _Streams? properties;
  _Player? player;
  _TexturelessVideo? video;

  @override
  void ensureInitialized() {
    expect(PlayerTerminalBackend.debugOverride, same(this));
    construction.add('bootstrap');
  }

  @override
  mk.Player createPlayer({required mk.PlayerConfiguration configuration}) {
    expect(PlayerTerminalBackend.debugOverride, same(this));
    construction.add('player');
    expect(configuration.logLevel, mk.MPVLogLevel.error);
    expect(configuration.ready, isNotNull);
    properties = _Streams(configuration, unexpected);
    return player = _Player(properties!);
  }

  @override
  mkv.VideoController createVideoController(
    mk.Player player, {
    required mkv.VideoControllerConfiguration configuration,
  }) {
    expect(PlayerTerminalBackend.debugOverride, same(this));
    construction.add('video');
    expect(player, same(this.player));
    return video = _TexturelessVideo(player, unexpected);
  }
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final previousFactory = databaseFactoryOrNull;
  Directory? fixtureRoot;
  const window = MethodChannel('window_manager');
  const brightness = MethodChannel('github.com/aaassseee/screen_brightness');
  const wake =
      'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle';
  late PlayerTerminalBackend? previous;
  late _Terminal terminal;
  late DebugPrintCallback originalPrint;
  final observed = <String>[];
  var phase = 'setup';
  final requests = <String>[];
  final introRequests = <String>{};
  Object? primary;
  StackTrace? primaryStack;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });
  tearDownAll(() { databaseFactoryOrNull = previousFactory; });
  setUp(() async {
    previous = PlayerTerminalBackend.debugOverride;
    terminal = _Terminal();
    originalPrint = debugPrint;
    observed.clear();
    requests.clear();
    introRequests.clear();
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) observed.add(message);
      originalPrint(message, wrapWidth: wrapWidth);
    };
    SharedPreferences.setMockInitialValues({});
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    SecretVault.debugReset(deviceIdOverride: 'tracker-terminal-origin');
    StorageService.resetProfileCaches();
    final root = await Directory(
      '.dart_tool',
    ).absolute.createTemp('tracker-terminal-');
    fixtureRoot = root;
    AppStorage.debugOverride(documents: root, support: root, cache: root);
    await DebrifyTvDatabase.instance.debugResetScopeState();
    await DebrifyTvDatabase.instance.database;
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
      throw StateError('Unexpected brightness ${call.method}');
    });
    PlayerTerminalBackend.debugOverride = terminal;
  });
  tearDown(() async {
    try {
      terminal.video?.close();
      await DebrifyTvDatabase.instance.debugResetScopeState();
      final root = fixtureRoot;
      if (root != null) {
        final parent = await root.parent.resolveSymbolicLinks();
        expect(parent, await Directory('.dart_tool').resolveSymbolicLinks());
        await root.delete(recursive: true);
        fixtureRoot = null;
      }
      expect(PlayerTerminalBackend.debugOverride, same(terminal));
    } finally {
      PlayerTerminalBackend.debugOverride = previous;
      debugPrint = originalPrint;
      binding.defaultBinaryMessenger.setMockMethodCallHandler(window, null);
      binding.defaultBinaryMessenger.setMockMethodCallHandler(brightness, null);
      binding.defaultBinaryMessenger.setMockMessageHandler(wake, null);
      StorageService.resetProfileCaches();
      AppStorage.debugReset();
      ProfileRuntime.debugReset();
      SecretVault.debugReset();
    }
  });

  // Fixed feasibility bound: 80 frame/event turns per phase, 50ms per frame.
  // The root event turn permits real SQLite/file Futures, with no sleep.
  Future<void> reach(WidgetTester tester, bool Function() predicate) async {
    for (var i = 0; i < 80 && !predicate(); i++) {
      await tester.runAsync(() => Future<void>(() {}));
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(predicate(), isTrue, reason: 'Phase did not complete: $phase');
  }

  testWidgets(
    'public selected episode resumes from real Simkl store via terminal IO',
    (tester) async {
      await http.runWithClient(
        () async {
          tester.view.physicalSize = const Size(1280, 720);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          const imdb = 'tt1234567';
          const first = 'https://fixture.invalid/Example.S01E01.mp4';
          const second = 'https://fixture.invalid/Example.S01E02.mp4';
          var selectionCompleted = false;
          Object? selectionError;
          StackTrace? selectionStack;
          primary = null;
          primaryStack = null;
          try {
            phase = 'seed actual stores';
            await TrackingPrefs.setSimklAccessToken(
              'tracker-terminal-test-token',
            );
            await PlaybackProgressStore.saveEpisodeSimklProgress(
              imdbId: imdb,
              percents: {'1_1': 10.0, '1_2': 35.0, '1_3': 80.0},
            );
            expect(
              await PlaybackProgressStore.getEpisodeTraktProgress(imdbId: imdb),
              isEmpty,
            );
            expect(
              await PlaybackProgressStore.getEpisodeMdblistProgress(
                imdbId: imdb,
              ),
              isEmpty,
            );
            expect(
              await PlaybackProgressStore.getMergedEpisodeProgress(
                seriesTitle: 'Example',
                imdbId: imdb,
              ),
              isEmpty,
            );
            phase = 'mount and actual initial resume completion';
            await tester.pumpWidget(
              MaterialApp(
                builder: (_, child) => AppThemeScope(
                  theme: AppThemes.byId('spotlight'),
                  child: child!,
                ),
                home: VideoPlayerScreen(
                  videoUrl: first,
                  title: 'Example.S01E01.mp4',
                  playlist: [
                    PlaylistEntry(url: first, title: 'Example.S01E01.mp4'),
                    PlaylistEntry(url: second, title: 'Example.S01E02.mp4'),
                  ],
                  contentType: 'series',
                  contentTitle: 'Example',
                  contentImdbId: imdb,
                  contentSeason: 1,
                  contentEpisode: 1,
                ),
              ),
            );
            await reach(
              tester,
              () =>
                  terminal.properties?.seeks.contains((
                        first,
                        const Duration(seconds: 6),
                      )) ==
                      true &&
                  observed.any((s) => s.startsWith('SubAuto: restore done')) &&
                  find.byType(Controls).evaluate().isNotEmpty,
            );
            await tester.pump();
            expect(terminal.construction, ['bootstrap', 'player', 'video']);
            final backend = terminal.properties!;
            expect(backend.state.playlist.medias.single.uri, first);
            phase = 'public Controls playlist';
            tester
                .widget<Controls>(find.byType(Controls).first)
                .onShowPlaylist();
            // Keep the original guide phase budget; observe the real committed
            // replacement, not merely requests or the pre-seeded 35 percent.
            Map<String, double> refreshed = {};
            for (var i = 0; i < 80; i++) {
              await tester.runAsync(() => Future<void>(() {}));
              await tester.pump(const Duration(milliseconds: 50));
              refreshed = (await tester.runAsync(
                () =>
                    PlaybackProgressStore.getEpisodeSimklProgress(imdbId: imdb),
              ))!;
              if (find.byType(SeriesBrowser).evaluate().isNotEmpty &&
                  refreshed.length == 2 &&
                  refreshed['1_1'] == 10 &&
                  refreshed['1_2'] == 35) {
                break;
              }
            }
            expect(find.byType(SeriesBrowser), findsOneWidget);
            expect(refreshed, {'1_1': 10.0, '1_2': 35.0});
            expect(
              requests.where((r) => r == 'POST /sync/watched'),
              hasLength(1),
            );
            expect(
              requests.where((r) => r == 'GET /sync/playback/episodes'),
              hasLength(1),
            );
            debugPrintSynchronously(
              'TRACKER_REFRESH_COMMITTED $refreshed requests=$requests',
            );
            final browser = tester.widget<SeriesBrowser>(
              find.byType(SeriesBrowser),
            );
            expect(
              browser.seriesPlaylist.findOriginalIndexBySeasonEpisode(1, 2),
              1,
            );
            phase = 'public selected episode Future';
            final selection = browser.onEpisodeSelected(1, 2) as Future<void>;
            final observedSelection = selection.then<void>(
              (_) {
                selectionCompleted = true;
              },
              onError: (Object error, StackTrace stack) {
                selectionError = error;
                selectionStack = stack;
                selectionCompleted = true;
              },
            );
            await reach(tester, () => selectionCompleted);
            await observedSelection;
            if (selectionError != null) {
              Error.throwWithStackTrace(selectionError!, selectionStack!);
            }
            phase = 'selected identity and actual resume seek';
            expect(backend.state.playlist.medias.single.uri, second);
            expect(backend.state.duration, const Duration(seconds: 60));
            expect(backend.seeks.where((x) => x.$1 == second).toList(), [
              (second, const Duration(seconds: 21)),
            ]);
            expect(backend.state.position, const Duration(seconds: 21));
            expect(terminal.unexpected, isEmpty);
            expect(introRequests, {
              'api.skipdb.tv/api/segments',
              'api.theintrodb.org/v3/media',
              'api.introdb.app/segments',
            });
            phase = 'behavior complete';
          } catch (error, stack) {
            primary = error;
            primaryStack = stack;
            debugPrintSynchronously(
              'TRACKER_PRIMARY phase=$phase $error\n$stack',
            );
            rethrow;
          } finally {
            debugPrintSynchronously(
              'TRACKER_PHASE $phase selection=$selectionCompleted error=$selectionError events=${terminal.properties?.events}',
            );
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
                final settledSeeks = List<(String, Duration)>.of(backend.seeks);
                // Retained origin owed an 800ms fake-clock confirmation wake.
                // Current main cancels owned waits; either way, after disposal
                // this full window must produce no late resume seek effects.
                await tester.pump(const Duration(milliseconds: 800));
                expect(backend.seeks, settledSeeks);
                expect(backend.closed, isTrue);
              }
              expect(VideoOutputLease.isHeld, isFalse);
              expect(terminal.unexpected, isEmpty);
            } catch (error, stack) {
              debugPrintSynchronously(
                'TRACKER_CLEANUP phase=$phase $error\n$stack',
              );
              if (primary != null) {
                Error.throwWithStackTrace(primary!, primaryStack!);
              }
              rethrow;
            } finally {
              debugPrint = originalPrint;
            }
          }
        },
        () => MockClient((request) async {
          final uri = request.url;
          requests.add('${request.method} ${uri.path}');
          if (uri.host == 'api.simkl.com') {
            expect(
              request.headers['authorization'],
              'Bearer tracker-terminal-test-token',
            );
            expect(request.headers['simkl-api-key'], kSimklClientId);
            expect(uri.queryParameters['client_id'], kSimklClientId);
            expect(uri.queryParameters['app-name'], kSimklAppName);
            expect(uri.queryParameters['app-version'], kSimklAppVersion);
            if (request.method == 'POST' && uri.path == '/sync/watched') {
              expect(uri.queryParameters['extended'], 'episodes');
              expect(jsonDecode(request.body), [
                {
                  'ids': {'imdb': 'tt1234567'},
                },
              ]);
              return http.Response('[]', 200);
            }
            if (request.method == 'GET' &&
                uri.path == '/sync/playback/episodes') {
              return http.Response(
                jsonEncode([
                  {
                    'show': {
                      'ids': {'imdb': 'tt1234567'},
                    },
                    'episode': {'season': 1, 'number': 1},
                    'progress': 10,
                  },
                  {
                    'show': {
                      'ids': {'imdb': 'tt1234567'},
                    },
                    'episode': {'season': 1, 'number': 2},
                    'progress': 35,
                  },
                ]),
                200,
              );
            }
          }
          // Exact observed optional metadata requests: exercise the real
          // providers' non-200 path, without admitting unknown transport.
          final introQueries = <String, Map<String, String>>{
            'api.skipdb.tv/api/segments': {
              'imdb_id': 'tt1234567',
              'season': '1',
              'episode': '1',
              'duration': '60',
            },
            'api.theintrodb.org/v3/media': {
              'imdb_id': 'tt1234567',
              'season': '1',
              'episode': '1',
              'duration_ms': '60000',
            },
            'api.introdb.app/segments': {
              'imdb_id': 'tt1234567',
              'season': '1',
              'episode': '1',
            },
          };
          final introKey = '${uri.host}${uri.path}';
          final expectedQuery = introQueries[introKey];
          if (expectedQuery != null) {
            // Record mismatches before throwing: production catches transport
            // errors, so the final unexpected-list assertion must retain them.
            final valid =
                request.method == 'GET' &&
                uri.scheme == 'https' &&
                uri.userInfo.isEmpty &&
                uri.fragment.isEmpty &&
                uri.port == 443 &&
                const MapEquality<String, String>().equals(
                  uri.queryParameters,
                  expectedQuery,
                ) &&
                uri.queryParametersAll.values.every((v) => v.length == 1) &&
                request.headers['accept'] == 'application/json' &&
                !request.headers.containsKey('authorization') &&
                !request.headers.containsKey('simkl-api-key') &&
                introRequests.add(introKey);
            if (!valid) {
              terminal.unexpected.add('intro-request:${request.method} $uri');
              throw StateError(
                'Unexpected intro request ${request.method} $uri',
              );
            }
            return http.Response('metadata unavailable', 400);
          }
          // Preserve the earlier fixture's unavailable optional TVMaze metadata.
          // These are explicit negative responses, never fabricated metadata.
          if (request.method == 'GET' &&
              uri.host == 'api.tvmaze.com' &&
              (uri.path == '/shows/1' ||
                  uri.path == '/lookup/shows' ||
                  uri.path == '/search/shows' ||
                  uri.path == '/singlesearch/shows')) {
            return http.Response('metadata unavailable', 400);
          }
          terminal.unexpected.add('http:${request.method} $uri');
          throw StateError('Unexpected HTTP ${request.method} $uri');
        }),
      );
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );
}
