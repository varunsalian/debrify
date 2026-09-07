import 'package:debrify/models/playlist_view_mode.dart';
import 'package:debrify/screens/video_player/widgets/player_menu_panel.dart';
import 'package:debrify/services/movie_metadata_service.dart';
import 'package:debrify/services/tvmaze_service.dart';
import 'package:debrify/services/episode_info_service.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:debrify/screens/video_player/services/player_terminal_backend.dart';
import 'package:debrify/screens/video_player/widgets/controls.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/mdblist/mdblist_service.dart';
import 'package:debrify/services/debrify_tv_database.dart';
import 'package:debrify/services/iptv_media_store.dart';
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

import 'package:debrify/services/storage/tracking_prefs.dart';
import 'package:debrify/services/tracking_source_policy.dart';
import 'package:debrify/services/stremio_service.dart';
import 'package:debrify/services/stremio_subtitle_service.dart';

// UNRUN Navigation PREP; borrowed external terminal transport only. External terminal fixture adapted from
// merged SkipA fixture. Five actual-host navigation cases; no native decoding,
// policy substitutes, private State access or aggregate startup-join proof.
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
  Future<void> Function(String uri)? beforeOpen;

  Future<void> openMedia(mk.Playable playable, {required bool play}) async {
    if (playable is! mk.Media) throw StateError('Expected one external media');
    if (closed) {
      unexpected.add('open-after-dispose:${playable.uri}');
      throw StateError('External open after actual disposal');
    }
    final observer = beforeOpen;
    if (observer != null) await observer(playable.uri);
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

  // External backend events, not a copy of host admission/selection policy.
  void reportPosition(Duration value) {
    state = state.copyWith(position: value);
    positionController.add(value);
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
  Future<void> setAudioTrack(mk.AudioTrack track) => backend.attachAudio(track);
  @override
  Future<void> setSubtitleTrack(mk.SubtitleTrack track) => backend.selectSubtitle(track);
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
    if (properties != null) {
      unexpected.add('duplicate-player-construction');
      throw StateError('Second player outside this fixture contract');
    }
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
    if (video != null) {
      unexpected.add('duplicate-video-construction');
      throw StateError('Second video outside this fixture contract');
    }
    return video = _TexturelessVideo(player, unexpected);
  }
}

// MdblistService.instance owns this for the fresh test isolate. Unlike the
// request-scoped TVMaze clients it is not disposed by a player/case. No IO,
// timers, delegation or permissive responses exist behind this sentinel.
class _IsolateRejectingClient extends http.BaseClient {
  int requests = 0;
  int closeCalls = 0;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    requests++;
    throw StateError('Unexpected disabled MDBList request ${request.method} ${request.url}');
  }
  @override
  void close() {
    closeCalls++;
    throw StateError('Unexpected close of isolate-owned MDBList sentinel');
  }
}

// Strict negative optional-metadata transport; body and close counted separately.
class _TrackedClient extends http.BaseClient {
  _TrackedClient(this.unexpected, this.requests, this.creationStack);
  final List<String> unexpected;
  final List<String> requests;
  final String creationStack;
  int sent = 0, closeCalls = 0, bodyStarted = 0, bodyDone = 0;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    sent++;
    final uri = request.url;
    requests.add('${request.method} $uri');
    final endpoint = uri.host == 'api.tvmaze.com' && uri.path == '/shows/1' ||
        uri.host == 'v3-cinemeta.strem.io' && uri.path == '/manifest.json';
    if (closeCalls != 0 || request.method != 'GET' || uri.scheme != 'https' ||
        uri.port != 443 || uri.userInfo.isNotEmpty || uri.fragment.isNotEmpty ||
        uri.hasQuery || !endpoint || request.headers.length != 1 ||
        request.headers['accept'] != 'application/json') {
      unexpected.add('http:${request.method} $uri ${request.headers}');
      throw StateError('Unexpected navigation fixture request');
    }
    if ((await request.finalize().toBytes()).isNotEmpty) {
      unexpected.add('nonempty GET body');
      throw StateError('Nonempty GET body');
    }
    return http.StreamedResponse(_body(), 400);
  }
  Stream<List<int>> _body() async* {
    bodyStarted++;
    try { yield const <int>[]; } finally { bodyDone++; }
  }
  @override
  void close() {
    closeCalls++;
    if (closeCalls != 1) unexpected.add('duplicate HTTP close');
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
  final printed = <String>[];
  var phase = 'setup';
  final requests = <String>[];
  Object? primary;
  StackTrace? primaryStack;
  bool cleanupSafe = false;
  bool contaminated = false;
  final clients = <_TrackedClient>[];
  final mdblistSentinel = _IsolateRejectingClient();
  int mdblistClientConstructions = 0;

  void expectIsolateClientUntouched() {
    expect(mdblistClientConstructions, 1);
    expect(mdblistSentinel.requests, 0);
    expect(mdblistSentinel.closeCalls, 0);
  }

  void reportClients(String label) {
    debugPrintSynchronously('NAV_CLIENTS ${jsonEncode({
      'label': label,
      'phase': phase,
      'mdblistFactory': mdblistClientConstructions,
      'mdblistRequests': mdblistSentinel.requests,
      'mdblistCloses': mdblistSentinel.closeCalls,
      'clients': clients.map((client) => {
        'creationStack': client.creationStack,
        'sent': client.sent,
        'closes': client.closeCalls,
        'bodyStarted': client.bodyStarted,
        'bodyDone': client.bodyDone,
      }).toList(),
    })}');
  }

  setUpAll(() {
    // Public lazy singleton construction only, before per-case HTTP zones.
    // A preinitialized/non-fresh isolate fails the exactly-one factory check.
    http.runWithClient(() {
      expect(MdblistService.instance, same(MdblistService.instance));
    }, () {
      mdblistClientConstructions++;
      return mdblistSentinel;
    });
    expectIsolateClientUntouched();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });
  tearDownAll(() {
    expectIsolateClientUntouched();
    if (!contaminated) databaseFactoryOrNull = previousFactory;
  });
  setUp(() async {
    if (contaminated) throw StateError('Previous fixture unsettled; process must stop');
    expectIsolateClientUntouched();
    cleanupSafe = false;
    clients.clear();
    previous = PlayerTerminalBackend.debugOverride;
    terminal = _Terminal();
    originalPrint = debugPrint;
    observed.clear();
    printed.clear();
    phase = 'setup';
    primary = null;
    primaryStack = null;
    requests.clear();
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) observed.add(message);
      originalPrint(message, wrapWidth: wrapWidth);
    };
    SharedPreferences.setMockInitialValues({});
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    SecretVault.debugReset(deviceIdOverride: 'navigation-terminal-origin');
    StorageService.resetProfileCaches();
    final root = await Directory(
      '.dart_tool',
    ).absolute.createTemp('navigation-terminal-');
    fixtureRoot = root;
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
      throw StateError('Unexpected brightness ${call.method}');
    });
    PlayerTerminalBackend.debugOverride = terminal;
  });
  tearDown(() async {
    if (!cleanupSafe) {
      contaminated = true;
      debugPrint = originalPrint;
      debugPrintSynchronously('NAV_UNSETTLED resources retained at $fixtureRoot');
      // Do not reset globals/close DB/delete files beneath unresolved work.
      // Subsequent setUp fails before changing any of these resources.
      return;
    }
    var resourcesClosed = false;
    try {
      // A failed close must NOT fall through to global/profile/factory reset.
      await DebrifyTvDatabase.instance.debugResetScopeState();
      terminal.video?.close();
      // Preserve this isolated fixture directory as evidence; no deletion.
      expect(PlayerTerminalBackend.debugOverride, same(terminal));
      expectIsolateClientUntouched();
      resourcesClosed = true;
    } catch (error, stack) {
      contaminated = true;
      cleanupSafe = false;
      debugPrintSynchronously('NAV_RESOURCE_CLOSE_FAILURE $error\n$stack root=$fixtureRoot');
      if (primary != null) Error.throwWithStackTrace(primary!, primaryStack!);
      rethrow;
    } finally {
      debugPrint = originalPrint;
      if (resourcesClosed) {
        IptvMediaStore.debugResetMigration();
        PlayerTerminalBackend.debugOverride = previous;
        binding.defaultBinaryMessenger.setMockMethodCallHandler(window, null);
        binding.defaultBinaryMessenger.setMockMethodCallHandler(brightness, null);
        binding.defaultBinaryMessenger.setMockMessageHandler(wake, null);
        StorageService.resetProfileCaches();
        AppStorage.debugReset();
        ProfileRuntime.debugReset();
        SecretVault.debugReset();
      }
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

  int countPrefix(String prefix) => observed.where((s) => s.startsWith(prefix)).length;
  int restoredTracks() => countPrefix('SubAuto: restore done');
  int addonDone() => observed.where((s) => s ==
      'SubAuto: ABORT — no IMDB ID for addon subtitle fetch').length;
  int movieStarts() => countPrefix('MovieMetadata: Checking filename at index ');
  int movieDone() => observed.where((s) =>
      s.startsWith('MovieMetadata: No year pattern found at index ') ||
      s.startsWith('MovieMetadata: No match found in Cinemeta for index ')).length;
  bool metadataTail(bool series) => series
      ? observed.where((s) => s == 'TVMaze: Searching for "navigation"').length == 1 &&
        observed.where((s) => s ==
          'SeriesPlaylist: TVMaze unavailable, treating as MOVIE_COLLECTION fallback').length == 1 &&
        printed.where((s) => s ==
          '  ⚠️ No valid identifier found, skipping poster save').length == 1
      : movieStarts() > 0 && movieDone() == movieStarts();

  void noErrors() {
    expect(terminal.unexpected, isEmpty);
    expect(observed.where((s) => s.contains('FAILED with exception:') ||
        s.startsWith('SubAuto: restore aborted') ||
        s.contains('Error fetching addon subtitles') ||
        s.startsWith('SkipSegments:') && s.contains('fetch failed')), isEmpty);
  }

  // Current source role, not historical pre-SkipA host construction frames.
  bool autoRole(_TrackedClient c) {
    final a = c.creationStack.indexOf('new AutoSkipSegmentProvider (package:debrify/services/skip_segment_service.dart:');
    final b = c.creationStack.indexOf('SkipSegmentProviders.create (package:debrify/services/skip_segment_service.dart:');
    final d = c.creationStack.indexOf('SkipSegmentSession.configure (package:debrify/services/playback/skip_segment_session.dart:');
    final e = c.creationStack.indexOf('_VideoPlayerScreenState._loadSkipSegmentSettings (package:debrify/screens/video_player_screen.dart:');
    return a >= 0 && b > a && d > b && e > d;
  }

  Future<void> runCase(WidgetTester tester, {
    required List<PlaylistEntry> entries,
    required PlaylistViewMode? mode,
    required int start,
    required bool series,
    required Future<void> Function(
      Future<void> Function(bool) step,
      Future<void> Function(String) menuAction,
      String Function() current,
      Controls Function() controls,
    ) exercise,
  }) async {
    var mountStarted = false;
    var completedOpens = 0;
    var bodyPassed = false;
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Controls controls() => tester.widget<Controls>(find.byType(Controls).first);
    String current() => terminal.properties!.state.playlist.medias.single.uri;

    Future<void> loadTail() async {
      final target = completedOpens + 1;
      phase = 'open and actual restore entry $target';
      await reach(tester, () => terminal.properties != null &&
          terminal.properties!.events.where((e) => e.startsWith('open:')).length == target &&
          countPrefix('SubAuto: _restoreTrackPreferences entered (token=') == target);
      final before = binding.clock.now();
      // Exactly the existing empty-track 50x100ms frontier, after restore entry.
      // Not an HTTP/SQLite drain; terminal observations below remain required.
      await tester.pump(const Duration(seconds: 5));
      expect(binding.clock.now().difference(before), const Duration(seconds: 5));
      phase = 'restored ready controls and named metadata branch $target';
      await reach(tester, () => restoredTracks() == target && addonDone() == target &&
          metadataTail(series) && find.byType(Controls).evaluate().isNotEmpty &&
          controls().isReady);
      expect(terminal.properties!.state.duration, const Duration(seconds: 60));
      noErrors();
      completedOpens = target;
    }

    Future<void> step(bool next) async {
      final bound = next ? controls().onNext : controls().onPrevious;
      expect(bound, isNotNull, reason: 'Actual current Controls capability');
      // Real bound public callback is void; only loadTail observes its result.
      bound!();
      await loadTail();
    }

    Future<void> menuAction(String label) async {
      if (find.byType(PlayerMenuPanel).evaluate().isEmpty) {
        controls().onRandom();
        await reach(tester, () => find.byType(PlayerMenuPanel).evaluate().length == 1 &&
            find.descendant(of: find.byType(PlayerMenuPanel), matching: find.text(label))
                .hitTestable().evaluate().length == 1);
      }
      final panel = tester.widget<PlayerMenuPanel>(find.byType(PlayerMenuPanel));
      final turnsOff = label == 'Continuous shuffle' && panel.continuousShuffle;
      final row = find.descendant(of: find.byType(PlayerMenuPanel), matching: find.text(label)).hitTestable();
      expect(row, findsOneWidget);
      await tester.tap(row);
      if (!turnsOff) { await loadTail(); }
      else {
        await tester.pump();
        expect(tester.widget<PlayerMenuPanel>(find.byType(PlayerMenuPanel)).continuousShuffle, isFalse);
      }
      if (find.byType(PlayerMenuPanel).evaluate().isNotEmpty) {
        // Invoke only the currently mounted public close command; no private State.
        tester.widget<PlayerMenuPanel>(find.byType(PlayerMenuPanel)).onClose();
        await tester.pump();
      }
    }

    await runZoned(() => http.runWithClient(() async {
      try {
        phase = 'public local-only/addon setup';
        final policy = await tester.runAsync(() async {
          await TrackingPrefs.setTrackingScrobbleTargets({});
          await TrackingPrefs.setWatchProgressSource(WatchProgressSource.local);
          await TrackingPrefs.setHomeTickSources({});
          await StremioService.instance.clearAllAddons();
          final enabled = await StremioService.instance.getEnabledAddons();
          final addons = await StremioSubtitleService.instance.getSubtitleAddons();
          // Setup assertions are returned to the test zone below.
          return (await TrackingSourcePolicy.load(), enabled.isEmpty, addons.isEmpty);
        });
        expect(policy, isNotNull);
        expect(policy!.$1.scrobbleTargets, {TrackingSource.local});
        expect(policy.$1.progressSource, WatchProgressSource.local);
        expect(policy.$2, isTrue);
        expect(policy.$3, isTrue);
        phase = 'mount actual public playlist';
        mountStarted = true;
        await tester.pumpWidget(MaterialApp(
          builder: (_, child) => AppThemeScope(theme: AppThemes.byId('spotlight'), child: child!),
          home: VideoPlayerScreen(videoUrl: entries[start].url, title: entries[start].title,
            playlist: entries, startIndex: start, disableAutoResume: true, viewMode: mode,
            contentType: series ? 'series' : 'movie', startFromRandom: false,
            traktScrobble: false, simklScrobble: false, mdblistScrobble: false),
        ));
        await loadTail();
        expect(terminal.construction, ['bootstrap', 'player', 'video']);
        expect(current(), entries[start].url);
        await exercise(step, menuAction, current, controls);
        noErrors();
        bodyPassed = true;
      } catch (error, stack) {
        primary = error;
        primaryStack = stack;
        reportClients('primary');
        rethrow;
      } finally {
        try {
          phase = 'unmount and terminal disposal';
          if (mountStarted) {
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pump(const Duration(milliseconds: 250));
          }
          final backend = terminal.properties;
          if (backend != null) {
            await tester.runAsync(() async {
              await backend.disposalEntered.future.timeout(const Duration(seconds: 5));
              await backend.disposal!.timeout(const Duration(seconds: 5));
            });
            expect(backend.closed, isTrue);
          }
          expect(bodyPassed, isTrue, reason: 'Do not release dependent resources after incomplete policy/producer evidence');
          final autos = clients.where(autoRole).toList();
          expect(autos, hasLength(1));
          expect(autos.single.sent, 0);
          expect(autos.single.closeCalls, 1);
          for (final c in clients.where((c) => !autoRole(c))) {
            expect(c.sent, 1);
            expect(c.bodyStarted, 1);
            expect(c.bodyDone, 1);
            expect(c.closeCalls, 1);
          }
          expect(clients.fold<int>(0, (n, c) => n + c.sent), requests.length);
          final expectedRequests = series
              ? ['GET https://api.tvmaze.com/shows/1']
              : entries.any((e) => e.sizeBytes != null)
                ? ['GET https://v3-cinemeta.strem.io/manifest.json'] : <String>[];
          expect(requests, expectedRequests);
          expect(metadataTail(series), isTrue);
          expect(restoredTracks(), completedOpens);
          expect(addonDone(), completedOpens);
          final events = List.of(backend!.events);
          final requestsBefore = List.of(requests);
          final clientCount = clients.length;
          final branchCounts = (movieStarts(), movieDone(), restoredTracks(), addonDone());
          await tester.pump(const Duration(milliseconds: 800));
          expect(backend.events, events);
          expect(requests, requestsBefore);
          expect(clients.length, clientCount);
          expect((movieStarts(), movieDone(), restoredTracks(), addonDone()), branchCounts);
          expect(VideoOutputLease.isHeld, isFalse);
          expectIsolateClientUntouched();
          noErrors();
          reportClients('finite-branch-cleanup-not-aggregate-startup-join');
          // PREP LIMIT: private startup preference loaders have no public join.
          // This admits only the manifest's finite branches, not all-host settlement.
          cleanupSafe = true;
        } catch (error, stack) {
          reportClients('cleanup-failure');
          debugPrintSynchronously('NAV_CLEANUP $error\n$stack');
          if (primary != null) Error.throwWithStackTrace(primary!, primaryStack!);
          rethrow;
        } finally {
          debugPrint = originalPrint;
        }
      }
    }, () {
      final c = _TrackedClient(terminal.unexpected, requests, StackTrace.current.toString());
      clients.add(c);
      return c;
    }), zoneSpecification: ZoneSpecification(
      print: (self, parent, zone, line) {
        printed.add(line);
        parent.print(zone, line);
      },
    ));
  }

  List<PlaylistEntry> ordered() => const [
    PlaylistEntry(url: 'https://navigation.invalid/zero.mp4', title: 'Zulu'),
    PlaylistEntry(url: 'https://navigation.invalid/one.mp4', title: 'Alpha'),
    PlaylistEntry(url: 'https://navigation.invalid/two.mp4', title: 'Middle'),
  ];
  List<PlaylistEntry> collection() => const [
    PlaylistEntry(url: 'https://navigation.invalid/new.mp4', title: 'New 2004', sizeBytes: 1000),
    PlaylistEntry(url: 'https://navigation.invalid/below.mp4', title: 'Below 1998', sizeBytes: 399),
    PlaylistEntry(url: 'https://navigation.invalid/boundary.mp4', title: 'Boundary 2001', sizeBytes: 400),
    PlaylistEntry(url: 'https://navigation.invalid/unknown.mp4', title: 'Unknown 2003'),
    PlaylistEntry(url: 'https://navigation.invalid/old.mp4', title: 'Old 1999', sizeBytes: 500),
  ];

  for (final mode in [PlaylistViewMode.raw, PlaylistViewMode.sorted]) {
    testWidgets('actual ${mode.name} Controls follows supplied order both ways', (tester) async {
      final entries = ordered();
      await runCase(tester, entries: entries, mode: mode, start: 0, series: false,
        exercise: (step, menu, current, controls) async {
          expect(controls().onPrevious, isNull);
          for (final i in [1, 2]) { await step(true); expect(current(), entries[i].url); }
          expect(controls().onNext, isNull);
          for (final i in [1, 0]) { await step(false); expect(current(), entries[i].url); }
          expect(controls().onPrevious, isNull);
        });
    }, timeout: const Timeout(Duration(seconds: 45)));
  }
  testWidgets('actual collection admits 40-percent boundary and unknown size in year order', (tester) async {
    final entries = collection();
    await runCase(tester, entries: entries, mode: null, start: 4, series: false,
      exercise: (step, menu, current, controls) async {
        for (final i in [2, 3, 0]) { await step(true); expect(current(), entries[i].url); }
        expect(controls().onNext, isNull);
        for (final i in [3, 2, 4]) { await step(false); expect(current(), entries[i].url); }
      });
  }, timeout: const Timeout(Duration(seconds: 45)));
  testWidgets('actual parsed series next and previous follow episode order', (tester) async {
    const entries = [
      PlaylistEntry(url: 'https://navigation.invalid/e3.mp4', title: 'Navigation.S01E03.mkv'),
      PlaylistEntry(url: 'https://navigation.invalid/e1.mp4', title: 'Navigation.S01E01.mkv'),
      PlaylistEntry(url: 'https://navigation.invalid/e2.mp4', title: 'Navigation.S01E02.mkv'),
    ];
    await runCase(tester, entries: entries, mode: PlaylistViewMode.series, start: 1, series: true,
      exercise: (step, menu, current, controls) async {
        for (final i in [2, 0]) { await step(true); expect(current(), entries[i].url); }
        for (final i in [2, 1]) { await step(false); expect(current(), entries[i].url); }
      });
  }, timeout: const Timeout(Duration(seconds: 45)));
  testWidgets('actual shuffle menu exhausts other eligible entries then refills', (tester) async {
    final entries = collection();
    final eligible = {entries[0].url, entries[2].url, entries[3].url, entries[4].url};
    await runCase(tester, entries: entries, mode: null, start: 0, series: false,
      exercise: (step, menu, current, controls) async {
        await menu('Continuous shuffle');
        final visited = [current()];
        for (var i = 0; i < 2; i++) { await step(true); visited.add(current()); }
        expect(visited.toSet(), {entries[4].url, entries[2].url, entries[3].url});
        expect(visited.toSet(), hasLength(3));
        final before = current();
        await step(true);
        expect(eligible, contains(current()));
        expect(current(), isNot(before));
        // Refill may now select chronological last: NO further Next command.
        await menu('Continuous shuffle');
        await menu('Play random once');
        expect(eligible, contains(current()));
        controls().onRandom();
        await reach(tester, () => find.byType(PlayerMenuPanel).evaluate().length == 1);
        expect(tester.widget<PlayerMenuPanel>(find.byType(PlayerMenuPanel)).continuousShuffle, isFalse);
        tester.widget<PlayerMenuPanel>(find.byType(PlayerMenuPanel)).onClose();
        await tester.pump();
      });
  }, timeout: const Timeout(Duration(seconds: 45)));
}
