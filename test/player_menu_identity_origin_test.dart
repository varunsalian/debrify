import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:debrify/models/playlist_view_mode.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/models/tracking_source.dart';
import 'package:debrify/screens/video_player/services/player_terminal_backend.dart';
import 'package:debrify/screens/video_player/widgets/controls.dart';
import 'package:debrify/screens/video_player/widgets/player_menu_panel.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/debrify_tv_database.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/secret_vault.dart';
import 'package:debrify/services/storage/playback_progress_store.dart';
import 'package:debrify/services/storage/tracking_prefs.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/services/stremio_service.dart';
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
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// Pins the player-menu identity snapshot: the imdb id / content type /
// season / episode / cached-slot context the real screen resolves before it
// opens `PlayerMenuPanel`, both on the tracks-button path
// (`Controls.onShowTracks()`, which may await a metadata fetch) and on the
// quick path (`Controls.onSleepTimer()` / `onAspect()`, caches only).
// Harness adapted from test/player_menu_track_apply_origin_test.dart: only
// external SDK state and terminal operations are scripted (track lists,
// `open`/`stop`/`play`/`pause`/`seek`, dart:io HTTP for Cinemeta / TVMaze / a
// seeded Stremio catalog addon, path_provider). The launch itself runs under
// `tester.runAsync` (a playlist launch's resume lookup and the metadata
// preload only settle on the real clock — same reason the common brief gives
// for the vault); the menu is then driven on the fake clock. Assertions read
// the `PlayerMenuPanel` props the screen passes in.
//
// Not driven here (source-preserved): the single-file in-snapshot fetch
// branch (`!_singleFileImdbFetched`) — the launch preload always runs that
// fetch first, so by the time the menu opens the flag is already set.
class _TerminalStreams extends mk.PlatformPlayer {
  _TerminalStreams(mk.PlayerConfiguration configuration)
    : super(configuration: configuration);
}

class _Properties implements mk.NativePlayer {
  _Properties(mk.PlayerConfiguration configuration, this.unexpected)
    : _streams = _TerminalStreams(configuration);

  final _TerminalStreams _streams;
  @override
  mk.PlayerConfiguration get configuration => _streams.configuration;
  @override
  mk.PlayerState get state => _streams.state;
  @override
  set state(mk.PlayerState value) => _streams.state = value;
  @override
  mk.PlayerStream get stream => _streams.stream;

  final List<String> unexpected;
  final reads = <String>[];
  final writes = <(String, String)>[];
  bool closed = false;
  Future<void>? disposal;
  @override
  Future<String> getProperty(
    String property, {
    bool waitForInitialization = true,
  }) async {
    reads.add(property);
    unexpected.add('getProperty:$property');
    throw StateError('Unscripted property $property');
  }

  @override
  Future<void> setProperty(
    String property,
    String value, {
    bool waitForInitialization = true,
  }) async {
    writes.add((property, value));
    if (property != 'video-zoom' &&
        property != 'sub-visibility' &&
        property != 'stream-lavf-o') {
      unexpected.add('setProperty:$property');
      throw StateError('Unscripted property write $property');
    }
  }

  /// A playlist launch opens the start entry through the terminal. The
  /// startup candidate waits for a decoded frame (width), a moving position
  /// and a duration before it commits the source; only that external state
  /// transition is scripted (the harness fires `ready` and publishes tracks).
  void openMedia(mk.Media playable, {required bool play}) {
    state = state.copyWith(
      playlist: mk.Playlist([playable]),
      playing: play,
      completed: false,
      position: const Duration(seconds: 1),
      duration: const Duration(seconds: 60),
      width: 1280,
      height: 720,
    );
    _streams.playlistController.add(state.playlist);
    _streams.durationController.add(state.duration);
    _streams.widthController.add(state.width);
    _streams.heightController.add(state.height);
    _streams.positionController.add(state.position);
    _streams.playingController.add(play);
  }

  void setPlaying(bool playing) {
    state = state.copyWith(playing: playing);
    _streams.playingController.add(playing);
  }

  void seekTo(Duration target) {
    state = state.copyWith(position: target);
    _streams.positionController.add(target);
  }

  void emitPlayback(Duration position) {
    state = state.copyWith(
      playing: true,
      duration: const Duration(minutes: 10),
      position: position,
    );
    _streams.durationController.add(state.duration);
    _streams.positionController.add(position);
    _streams.playingController.add(true);
  }

  /// Real embedded tracks, as libmpv publishes them after demux. The host's
  /// restore path waits for a non-placeholder subtitle id before proceeding.
  void emitTracks() {
    state = state.copyWith(
      tracks: const mk.Tracks(
        audio: [
          mk.AudioTrack('auto', null, null),
          mk.AudioTrack('no', null, null),
          mk.AudioTrack('1', 'Stereo', 'jpn'),
        ],
        subtitle: [
          mk.SubtitleTrack('auto', null, null),
          mk.SubtitleTrack('no', null, null),
          mk.SubtitleTrack('3', 'Full', 'jpn'),
        ],
      ),
    );
    _streams.tracksController.add(state.tracks);
  }

  void applyTrack(mk.Track track) {
    state = state.copyWith(track: track);
    _streams.trackController.add(track);
  }

  @override
  Future<void> dispose({bool synchronized = true}) =>
      disposal ??= closeStreams();
  Future<void> closeStreams() async {
    await _streams.dispose();
    closed = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    unexpected.add('native:${invocation.memberName}');
    throw StateError('Unexpected native API ${invocation.memberName}');
  }
}

class _Player implements mk.Player {
  _Player(this.backend);
  final _Properties backend;

  @override
  mk.PlatformPlayer? get platform => backend;
  @override
  set platform(mk.PlatformPlayer? value) =>
      throw StateError('Unexpected platform replacement');
  @override
  mk.PlayerState get state => backend.state;
  @override
  mk.PlayerStream get stream => backend.stream;
  @override
  Future<void> dispose() => backend.dispose();

  final rates = <double>[];
  @override
  Future<void> setRate(double value) async {
    rates.add(value);
    backend.state = backend.state.copyWith(rate: value);
  }

  final opens = <String>[];
  @override
  Future<void> open(mk.Playable playable, {bool play = true}) async {
    if (playable is! mk.Media) throw StateError('Expected one media');
    opens.add(playable.uri);
    backend.openMedia(playable, play: play);
  }

  final stops = <int>[];
  @override
  Future<void> stop() async {
    stops.add(opens.length);
  }

  @override
  Future<void> play() async => backend.setPlaying(true);

  @override
  Future<void> pause() async => backend.setPlaying(false);

  final seeks = <Duration>[];
  @override
  Future<void> seek(Duration target) async {
    seeks.add(target);
    backend.seekTo(target);
  }

  final subtitleCalls = <String>[];
  @override
  Future<void> setSubtitleTrack(mk.SubtitleTrack track) async {
    subtitleCalls.add(track.id);
    backend.applyTrack(backend.state.track.copyWith(subtitle: track));
  }

  final audioCalls = <String>[];
  @override
  Future<void> setAudioTrack(mk.AudioTrack track) async {
    audioCalls.add(track.id);
    backend.applyTrack(backend.state.track.copyWith(audio: track));
  }

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
  _Properties? properties;
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
    properties = _Properties(configuration, unexpected);
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

const _plainTitle = 'Menu identity fixture';
const _launchImdbId = 'tt0000001';

// Cinemeta (MovieMetadataService): availability probe + title search. The
// search path carries the cleaned, percent-encoded query (`Uri.path` keeps
// the encoding).
const _cinemetaManifest = '/manifest.json';
const _singleFileTitle = 'Fixture Single (2003).mkv';
const _singleFileSearch = '/catalog/movie/top/search=fixture%20single.json';
const _singleFileImdbId = 'tt0000333';
const _collectionSearchOne =
    '/catalog/movie/top/search=fixture%20movie%20one.json';
const _collectionSearchTwo =
    '/catalog/movie/top/search=fixture%20movie%20two.json';
const _collectionImdbIdTwo = 'tt0000222';

// TVMaze (SeriesPlaylistMetadataLoader / EpisodeInfoService).
const _tvmazeProbe = '/shows/1';
const _tvmazeSearch = '/search/shows';
const _tvmazeEpisodes = '/shows/7/episodes';
const _seriesImdbId = 'tt0000777';

// Seeded Stremio catalog addon answering the identify-title sheet search.
const _catalogBase = 'https://catalog.example.test';
const _catalogSearchPrefix = '/catalog/movie/fixture/search=';
const _manualImdbId = 'tt0000999';
const _manualName = 'Manual Pick';

String _metas(String id, String name, String year) => jsonEncode({
  'metas': [
    {'id': id, 'type': 'movie', 'name': name, 'year': year},
  ],
});

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const window = MethodChannel('window_manager');
  const brightness = MethodChannel('github.com/aaassseee/screen_brightness');
  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
  const wake =
      'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle';
  late PlayerTerminalBackend? previous;
  late HttpOverrides? previousOverrides;
  late _Terminal terminal;
  late _CannedHttp http;
  late Directory root;
  Object? primaryFailure;
  StackTrace? primaryStack;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  setUp(() async {
    previous = PlayerTerminalBackend.debugOverride;
    previousOverrides = HttpOverrides.current;
    terminal = _Terminal();
    http = _CannedHttp({});
    HttpOverrides.global = http;
    SharedPreferences.setMockInitialValues({});
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    SecretVault.debugReset(deviceIdOverride: 'menu-identity-origin');
    StorageService.resetProfileCaches();
    root = await Directory('.dart_tool').absolute.createTemp('menu-identity-');
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
      throw StateError('Unexpected brightness call ${call.method}');
    });
    binding.defaultBinaryMessenger.setMockMethodCallHandler(pathProvider, (
      call,
    ) async {
      if (call.method == 'getTemporaryDirectory') return root.path;
      terminal.unexpected.add('path_provider:${call.method}');
      throw StateError('Unexpected path_provider call ${call.method}');
    });
    PlayerTerminalBackend.debugOverride = terminal;
  });

  tearDown(() async {
    try {
      if (terminal.properties != null && !terminal.properties!.closed) {
        await terminal.properties!.dispose();
      }
      terminal.video?.close();
      await DebrifyTvDatabase.instance.debugResetScopeState();
      expect(PlayerTerminalBackend.debugOverride, same(terminal));
    } catch (error, stack) {
      debugPrintSynchronously('MENU_IDENTITY_TEARDOWN $error\n$stack');
      if (primaryFailure != null) {
        Error.throwWithStackTrace(primaryFailure!, primaryStack!);
      }
      rethrow;
    } finally {
      PlayerTerminalBackend.debugOverride = previous;
      HttpOverrides.global = previousOverrides;
      binding.defaultBinaryMessenger.setMockMethodCallHandler(window, null);
      binding.defaultBinaryMessenger.setMockMethodCallHandler(brightness, null);
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
        pathProvider,
        null,
      );
      binding.defaultBinaryMessenger.setMockMessageHandler(wake, null);
      StorageService.resetProfileCaches();
      AppStorage.debugReset();
      ProfileRuntime.debugReset();
      SecretVault.debugReset();
    }
  });

  /// Mounts the real screen and lets its launch settle on the real clock
  /// until [launched] holds (plus a short tail), then hands the fake clock
  /// to [exercise]. The poll is a bounded fixture wait, not a timing
  /// assertion.
  Future<void> withHost(
    WidgetTester tester,
    VideoPlayerScreen screen, {
    required bool Function() launched,
    required Future<void> Function(_Properties) exercise,
  }) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    primaryFailure = null;
    primaryStack = null;
    try {
      late final _Properties backend;
      await tester.runAsync(() async {
        // Local-only tracking policy so the resume path's policy load never
        // touches the credential vault; same pre-seed as the
        // playlist-navigation origin test.
        await TrackingPrefs.setTrackingScrobbleTargets({});
        await TrackingPrefs.setWatchProgressSource(WatchProgressSource.local);
        await TrackingPrefs.setHomeTickSources({});
        await tester.pumpWidget(
          MaterialApp(
            builder: (_, child) => AppThemeScope(
              theme: AppThemes.byId('spotlight'),
              child: child!,
            ),
            home: screen,
          ),
        );
        // Accepted fixture construction bound.
        for (var i = 0; i < 20 && terminal.video == null; i++) {
          await tester.pump();
        }
        expect(terminal.construction, ['bootstrap', 'player', 'video']);
        backend = terminal.properties!;
        backend.configuration.ready!();
        backend.emitTracks();
        backend.emitPlayback(const Duration(seconds: 1));
        await tester.pump();
        var tail = 3;
        for (var i = 0; i < 80 && tail > 0; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          await tester.pump();
          if (launched()) tail--;
        }
        expect(launched(), isTrue);
      });
      expect(find.byType(Controls), findsOneWidget);
      expect(backend.reads, isEmpty);
      await exercise(backend);
      expect(terminal.unexpected, isEmpty);
    } catch (error, stack) {
      primaryFailure = error;
      primaryStack = stack;
      debugPrintSynchronously('MENU_IDENTITY_PRIMARY $error\n$stack');
      rethrow;
    } finally {
      try {
        // Unmount on the real clock: the screen's dispose-time resume /
        // playlist-state saves run sqflite transactions that must settle
        // before tearDown closes the database (as the playlist-navigation
        // origin test awaits disposal under runAsync).
        await tester.runAsync(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(const Duration(milliseconds: 250));
          await Future<void>.delayed(const Duration(milliseconds: 400));
          if (terminal.properties != null) await terminal.properties!.dispose();
        });
        expect(VideoOutputLease.isHeld, isFalse);
        expect(terminal.unexpected, isEmpty);
      } catch (error, stack) {
        debugPrintSynchronously('MENU_IDENTITY_CLEANUP $error\n$stack');
        if (primaryFailure != null) {
          Error.throwWithStackTrace(primaryFailure!, primaryStack!);
        }
        rethrow;
      }
    }
  }

  Controls controls(WidgetTester tester) =>
      tester.widget<Controls>(find.byType(Controls));

  PlayerMenuPanel menu(WidgetTester tester) =>
      tester.widget<PlayerMenuPanel>(find.byType(PlayerMenuPanel));

  /// Opens the Subtitles pane the way the Controls bar does.
  Future<PlayerMenuPanel> openTracks(WidgetTester tester) async {
    controls(tester).onShowTracks();
    await tester.pump();
    await tester.pump();
    expect(find.byType(PlayerMenuPanel), findsOneWidget);
    return menu(tester);
  }

  /// Opens a non-subtitle section the way the Controls bar does (the quick
  /// path: no fetch, caches only).
  Future<PlayerMenuPanel> openQuick(
    WidgetTester tester,
    void Function(Controls) trigger,
  ) async {
    trigger(controls(tester));
    await tester.pump();
    expect(find.byType(PlayerMenuPanel), findsOneWidget);
    return menu(tester);
  }

  Future<void> closeMenu(WidgetTester tester) async {
    menu(tester).onClose();
    await tester.pump();
    expect(find.byType(PlayerMenuPanel), findsNothing);
  }

  void expectIdentity(
    PlayerMenuPanel panel, {
    required String? imdbId,
    required String? contentType,
    required int? season,
    required int? episode,
    required PlayerMenuSection section,
    required Matcher cachedSlots,
  }) {
    expect(panel.initialSection, section);
    expect(panel.contentImdbId, imdbId);
    expect(panel.contentType, contentType);
    expect(panel.contentSeason, season);
    expect(panel.contentEpisode, episode);
    // With no subtitle addons configured, an addon fetch keyed to the
    // current identity caches an empty slot list; a key mismatch yields null.
    expect(panel.cachedAddonSlots, cachedSlots);
  }

  testWidgets(
    'single-file launch with a cached imdb id opens with it, typed movie, no fetch (both paths)',
    (tester) async {
      await withHost(
        tester,
        const VideoPlayerScreen(
          videoUrl: '',
          title: _plainTitle,
          disableAutoResume: true,
          contentImdbId: _launchImdbId,
        ),
        launched: () => true,
        exercise: (backend) async {
          expect(http.requests, isEmpty);

          final tracks = await openTracks(tester);
          expectIdentity(
            tracks,
            imdbId: _launchImdbId,
            contentType: 'movie',
            season: null,
            episode: null,
            section: PlayerMenuSection.subtitles,
            // Nothing cached yet at the first open; the Subtitles pane's own
            // (addon-less) fetch then caches [] under the launch key.
            cachedSlots: isNull,
          );
          expect(http.requests, isEmpty);
          await closeMenu(tester);

          final sleep = await openQuick(tester, (c) => c.onSleepTimer());
          expectIdentity(
            sleep,
            imdbId: _launchImdbId,
            contentType: 'movie',
            season: null,
            episode: null,
            section: PlayerMenuSection.sleep,
            cachedSlots: isEmpty,
          );
          expect(http.requests, isEmpty);
          expect(terminal.player!.subtitleCalls, isEmpty);
          expect(
            await PlaybackProgressStore.getVideoTrackPreferences(
              videoTitle: _plainTitle,
            ),
            isNull,
          );
        },
      );
    },
  );

  testWidgets(
    'single-file launch without an imdb id shows the Cinemeta id found for the title and year',
    (tester) async {
      http.routes[_cinemetaManifest] = const _Canned(200, '{}');
      http.routes[_singleFileSearch] = _Canned(
        200,
        _metas(_singleFileImdbId, 'Fixture Single', '2003'),
      );
      await withHost(
        tester,
        const VideoPlayerScreen(
          videoUrl: '',
          title: _singleFileTitle,
          disableAutoResume: true,
        ),
        launched: () => http.requests.contains('GET $_singleFileSearch'),
        exercise: (backend) async {
          expect(http.requests, contains('GET $_singleFileSearch'));
          final before = http.requests.length;

          final tracks = await openTracks(tester);
          expectIdentity(
            tracks,
            imdbId: _singleFileImdbId,
            contentType: 'movie',
            season: null,
            episode: null,
            section: PlayerMenuSection.subtitles,
            cachedSlots: anyOf(isNull, isEmpty),
          );
          // Cached from the launch preload: the menu did not fetch again.
          expect(http.requests.length, before);
          await closeMenu(tester);

          final aspect = await openQuick(tester, (c) => c.onAspect());
          expectIdentity(
            aspect,
            imdbId: _singleFileImdbId,
            contentType: 'movie',
            season: null,
            episode: null,
            section: PlayerMenuSection.aspect,
            cachedSlots: anyOf(isNull, isEmpty),
          );
          expect(http.requests.length, before);
        },
      );
    },
  );

  testWidgets(
    'series playlist shares the TVMaze-discovered show imdb id and the parsed season/episode',
    (tester) async {
      http.routes[_tvmazeProbe] = const _Canned(200, '{}');
      http.routes[_tvmazeSearch] = _Canned(
        200,
        jsonEncode([
          {
            'show': {
              'id': 7,
              'name': 'Fixture Show',
              'externals': {'imdb': _seriesImdbId},
            },
          },
        ]),
      );
      http.routes[_tvmazeEpisodes] = _Canned(
        200,
        jsonEncode([
          {'season': 1, 'number': 1, 'name': 'One'},
          {'season': 1, 'number': 2, 'name': 'Two'},
        ]),
      );
      const entries = [
        PlaylistEntry(
          url: 'https://identity.invalid/e1.mp4',
          title: 'Fixture.Show.S01E01.mkv',
        ),
        PlaylistEntry(
          url: 'https://identity.invalid/e2.mp4',
          title: 'Fixture.Show.S01E02.mkv',
        ),
      ];
      await withHost(
        tester,
        const VideoPlayerScreen(
          videoUrl: 'https://identity.invalid/e2.mp4',
          title: 'Fixture.Show.S01E02.mkv',
          playlist: entries,
          startIndex: 1,
          viewMode: PlaylistViewMode.series,
          disableAutoResume: true,
        ),
        launched: () => http.requests.contains('GET $_tvmazeEpisodes'),
        exercise: (backend) async {
          expect(http.requests, contains('GET $_tvmazeSearch'));
          final before = http.requests.length;

          final tracks = await openTracks(tester);
          expectIdentity(
            tracks,
            imdbId: _seriesImdbId,
            contentType: 'series',
            season: 1,
            episode: 2,
            section: PlayerMenuSection.subtitles,
            cachedSlots: anyOf(isNull, isEmpty),
          );
          expect(http.requests.length, before);
          await closeMenu(tester);

          final sleep = await openQuick(tester, (c) => c.onSleepTimer());
          expectIdentity(
            sleep,
            imdbId: _seriesImdbId,
            contentType: 'series',
            season: 1,
            episode: 2,
            section: PlayerMenuSection.sleep,
            cachedSlots: anyOf(isNull, isEmpty),
          );
          expect(http.requests.length, before);
        },
      );
    },
  );

  testWidgets(
    'movie collection resolves the current index and the tracks path awaits the Cinemeta fetch before opening',
    (tester) async {
      final gate = Completer<void>();
      http.routes[_cinemetaManifest] = const _Canned(200, '{}');
      http.routes[_collectionSearchOne] = _Canned(
        200,
        _metas('tt0000111', 'Fixture Movie One', '2001'),
      );
      http.routes[_collectionSearchTwo] = _Canned(
        200,
        _metas(_collectionImdbIdTwo, 'Fixture Movie Two', '2002'),
        gate: gate,
      );
      const entries = [
        PlaylistEntry(
          url: 'https://identity.invalid/m1.mp4',
          title: 'Fixture Movie One (2001).mkv',
        ),
        PlaylistEntry(
          url: 'https://identity.invalid/m2.mp4',
          title: 'Fixture Movie Two (2002).mkv',
        ),
      ];
      await withHost(
        tester,
        const VideoPlayerScreen(
          videoUrl: 'https://identity.invalid/m2.mp4',
          title: 'Fixture Movie Two (2002).mkv',
          playlist: entries,
          startIndex: 1,
          viewMode: PlaylistViewMode.raw,
          disableAutoResume: true,
        ),
        launched: () =>
            http.requests.contains('GET $_collectionSearchTwo') &&
            find.byType(Controls).evaluate().isNotEmpty,
        exercise: (backend) async {
          // The launch preload asked for the current index only, and is
          // still waiting on the gated response.
          expect(
            http.requests.where((r) => r == 'GET $_collectionSearchTwo'),
            hasLength(1),
          );
          expect(http.requests, isNot(contains('GET $_collectionSearchOne')));

          // Nothing cached for the index yet: the tracks path fetches (a
          // second request) and does not open the menu until it resolves.
          controls(tester).onShowTracks();
          await tester.pump();
          await tester.pump();
          expect(
            http.requests.where((r) => r == 'GET $_collectionSearchTwo'),
            hasLength(2),
          );
          expect(find.byType(PlayerMenuPanel), findsNothing);

          // Release both waiters (the launch preload lives on the real clock,
          // the menu's fetch on the fake one).
          await tester.runAsync(() async {
            gate.complete();
            await Future<void>.delayed(const Duration(milliseconds: 100));
          });
          await tester.pump();
          await tester.pump();
          expect(find.byType(PlayerMenuPanel), findsOneWidget);
          expectIdentity(
            menu(tester),
            imdbId: _collectionImdbIdTwo,
            contentType: 'movie',
            season: null,
            episode: null,
            section: PlayerMenuSection.subtitles,
            // Nothing was cached under the per-index key before this open.
            cachedSlots: isNull,
          );
          expect(http.requests, isNot(contains('GET $_collectionSearchOne')));
          final before = http.requests.length;
          await closeMenu(tester);

          // Quick path: caches only, so it now sees the per-index id.
          final aspect = await openQuick(tester, (c) => c.onAspect());
          expectIdentity(
            aspect,
            imdbId: _collectionImdbIdTwo,
            contentType: 'movie',
            season: null,
            episode: null,
            section: PlayerMenuSection.aspect,
            // The Subtitles pane's own fetch cached [] under that key.
            cachedSlots: isEmpty,
          );
          expect(http.requests.length, before);
        },
      );
    },
  );

  testWidgets(
    'a manual identity override wins over the launch imdb id on both paths',
    (tester) async {
      final addon = StremioAddon(
        id: 'fixture.catalog',
        name: 'Fixture catalog',
        manifestUrl: '$_catalogBase/manifest.json',
        baseUrl: _catalogBase,
        types: const ['movie'],
        resources: const ['catalog'],
        catalogs: const [
          StremioAddonCatalog(
            id: 'fixture',
            type: 'movie',
            name: 'Fixture',
            extraSupported: ['search'],
          ),
        ],
      );
      SharedPreferences.setMockInitialValues({
        'stremio_addons_v1': jsonEncode([addon.toJson()]),
      });
      // The singleton caches the addon list across tests; drop it so the
      // seeded prefs are read, and again afterwards so later tests see none.
      StremioService.instance.invalidateCache();
      addTearDown(StremioService.instance.invalidateCache);
      http.prefixes[_catalogSearchPrefix] = _Canned(
        200,
        _metas(_manualImdbId, _manualName, '2001'),
      );
      await withHost(
        tester,
        const VideoPlayerScreen(
          videoUrl: '',
          title: _plainTitle,
          disableAutoResume: true,
          contentImdbId: _launchImdbId,
        ),
        launched: () => true,
        exercise: (backend) async {
          final tracks = await openTracks(tester);
          expect(tracks.contentImdbId, _launchImdbId);
          expect(tracks.onIdentifyTitle, isNotNull);

          // "Fix the title": the real identify sheet searches the seeded
          // catalog addon with the detected title, then the pick is applied.
          final identified = tracks.onIdentifyTitle!();
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          await tester.pump(const Duration(milliseconds: 300));
          expect(
            http.requests.where((r) => r.contains(_catalogSearchPrefix)),
            hasLength(1),
          );
          expect(find.text(_manualName), findsOneWidget);
          await tester.tap(find.text(_manualName));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          await tester.pump(const Duration(milliseconds: 300));
          final result = await identified;
          expect(result, isNotNull);
          expect(result!.imdbId, _manualImdbId);
          expect(result.contentType, 'movie');
          await closeMenu(tester);

          final reopened = await openTracks(tester);
          expectIdentity(
            reopened,
            imdbId: _manualImdbId,
            contentType: 'movie',
            season: null,
            episode: null,
            section: PlayerMenuSection.subtitles,
            cachedSlots: isEmpty,
          );
          await closeMenu(tester);

          final sleep = await openQuick(tester, (c) => c.onSleepTimer());
          expectIdentity(
            sleep,
            imdbId: _manualImdbId,
            contentType: 'movie',
            season: null,
            episode: null,
            section: PlayerMenuSection.sleep,
            cachedSlots: isEmpty,
          );
        },
      );
    },
  );
}

// ---------------------------------------------------------------------------
// Canned dart:io HTTP. package:http's IOClient goes through HttpClient(), which
// honours HttpOverrides, so this answers the real Cinemeta / TVMaze / addon
// calls. Routes are keyed by decoded URL path (exact, then prefix); a
// gated route holds its response until the test completes the gate.
// ---------------------------------------------------------------------------

class _Canned {
  const _Canned(this.status, this.body, {this.gate});
  final int status;
  final String body;
  final Completer<void>? gate;
}

class _CannedHttp extends HttpOverrides {
  _CannedHttp(this.routes);

  /// URL path → response. Anything unrouted is an error, not a silent 400.
  final Map<String, _Canned> routes;
  final Map<String, _Canned> prefixes = {};
  final List<String> requests = [];

  _Canned? resolve(Uri url) {
    final exact = routes[url.path];
    if (exact != null) return exact;
    for (final entry in prefixes.entries) {
      if (url.path.startsWith(entry.key)) return entry.value;
    }
    return null;
  }

  @override
  HttpClient createHttpClient(SecurityContext? context) => _CannedClient(this);
}

class _CannedClient implements HttpClient {
  _CannedClient(this.fixture);
  final _CannedHttp fixture;

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    fixture.requests.add('$method ${url.path}');
    final canned = fixture.resolve(url);
    if (canned == null) {
      throw StateError('Unexpected request: $method $url');
    }
    return _CannedRequest(method, url, canned);
  }

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _CannedRequest implements HttpClientRequest {
  _CannedRequest(this.method, this.uri, this._canned);

  @override
  final String method;
  @override
  final Uri uri;
  final _Canned _canned;

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

  late final _CannedResponse _response = _CannedResponse(
    _canned.status,
    utf8.encode(_canned.body),
    {
      'content-type': ['application/json'],
    },
  );

  @override
  Future<void> addStream(Stream<List<int>> stream) => stream.drain<void>();

  @override
  void add(List<int> data) {}

  Future<HttpClientResponse> _deliver() async {
    final gate = _canned.gate;
    if (gate != null) await gate.future;
    return _response;
  }

  @override
  Future<HttpClientResponse> close() => _deliver();

  @override
  Future<HttpClientResponse> get done => _deliver();

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _CannedResponse extends Stream<List<int>> implements HttpClientResponse {
  _CannedResponse(this.statusCode, this._bytes, Map<String, List<String>> map)
    : headers = _CannedHeaders(map);

  final List<int> _bytes;

  @override
  final HttpHeaders headers;

  @override
  final int statusCode;
  @override
  String get reasonPhrase => statusCode == 200 ? 'OK' : 'Error';
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
