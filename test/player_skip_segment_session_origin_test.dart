import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:collection/collection.dart';
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

import 'package:debrify/services/storage/player_prefs.dart';
import 'package:debrify/services/storage/tracking_prefs.dart';
import 'package:debrify/services/tracking_source_policy.dart';
import 'package:debrify/services/stremio_service.dart';
import 'package:debrify/services/stremio_subtitle_service.dart';
import 'package:debrify/screens/video_player/widgets/skip_segment_button.dart';

// UNRUN SkipA positive origin PREP. External terminal fixture adapted from
// green Media982e. One direct/no-playlist case; no reset/stale/cache-revisit
// coverage, real decoding, production hooks or host algorithm substitutes.
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

// External HTTP transport only. Send completion and response-body consumption
// are separate observations; neither is a host Future or disposal join.
class _TrackedClient extends http.BaseClient {
  _TrackedClient(this.unexpected, this.requests, this.ordinal, this.release);
  final List<String> unexpected;
  final List<String> requests;
  final int ordinal;
  final Completer<void> release;
  int sent = 0;
  int closeCalls = 0;
  int bodyStarted = 0;
  int bodyDone = 0;
  bool get closed => closeCalls == 1;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    sent++;
    requests.add('${request.method} ${request.url}');
    final uri = request.url;
    final valid = closeCalls == 0 && request.method == 'GET' &&
        uri.scheme == 'https' && uri.host == 'api.skipdb.tv' &&
        uri.port == 443 && uri.userInfo.isEmpty && uri.fragment.isEmpty &&
        uri.path == '/api/segments' &&
        const MapEquality<String, String>().equals(uri.queryParameters, {
          'imdb_id': 'tt1234567', 'season': '1', 'episode': '1', 'duration': '60',
        }) && uri.queryParametersAll.values.every((v) => v.length == 1) &&
        request.headers.length == 1 &&
        request.headers['accept'] == 'application/json';
    if (!valid) {
      unexpected.add('http:${request.method} $uri headers=${request.headers}');
      throw StateError('Unexpected skip fixture request');
    }
    final requestBytes = await request.finalize().toBytes();
    if (requestBytes.isNotEmpty) {
      unexpected.add('nonempty-get-body');
      throw StateError('Unexpected GET request payload');
    }
    await release.future;
    return http.StreamedResponse(_responseBody(), 200,
        headers: {'content-type': 'application/json'});
  }

  Stream<List<int>> _responseBody() async* {
    bodyStarted++;
    try {
      yield utf8.encode('{"segments":{"intro":{"start_ms":10000,"end_ms":20000,"match":"exact"}}}');
    } finally {
      bodyDone++;
    }
  }

  @override
  void close() {
    closeCalls++;
    if (closeCalls != 1) unexpected.add('duplicate-http-close');
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
    debugPrintSynchronously('SKIP_CLIENTS ${jsonEncode({
      'label': label,
      'phase': phase,
      'mdblistFactory': mdblistClientConstructions,
      'mdblistRequests': mdblistSentinel.requests,
      'mdblistCloses': mdblistSentinel.closeCalls,
      'clients': clients.map((client) => {
        'ordinal': client.ordinal,
        'sent': client.sent,
        'closes': client.closeCalls,
        'bodyStarted': client.bodyStarted,
        'bodyDone': client.bodyDone,
      }).toList(),
    })}');
  }

  int addonStarts() => observed.where((s) =>
    s == 'VideoPlayer: Fetching addon subtitles (IMDB: tt1234567)').length;
  int addonCached() => observed.where((s) =>
    s == 'VideoPlayer: Fetched and cached 0 addon subtitles').length;
  int addonDone() => observed.where((s) =>
    s == 'SubAuto: SKIP — zero addon subtitles fetched').length;
  int restoredTracks() => observed.where((s) => s.startsWith('SubAuto: restore done')).length;

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
    SecretVault.debugReset(deviceIdOverride: 'skip-terminal-origin');
    StorageService.resetProfileCaches();
    final root = await Directory(
      '.dart_tool',
    ).absolute.createTemp('skip-terminal-');
    fixtureRoot = root;
    AppStorage.debugOverride(documents: root, support: root, cache: root);
    await DebrifyTvDatabase.instance.debugResetScopeState();
    IptvMediaStore.debugResetMigration();
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
    if (!cleanupSafe) {
      contaminated = true;
      debugPrint = originalPrint;
      debugPrintSynchronously('SKIP_UNSETTLED resources retained at $fixtureRoot');
      // Do not reset globals/close DB/delete files beneath unresolved work.
      // Subsequent setUp fails before changing any of these resources.
      return;
    }
    var resourcesClosed = false;
    try {
      // A failed close must NOT fall through to global/profile/factory reset.
      await DebrifyTvDatabase.instance.debugResetScopeState();
      terminal.video?.close();
      final root = fixtureRoot;
      if (root != null) {
        final parent = await root.parent.resolveSymbolicLinks();
        expect(parent, await Directory('.dart_tool').resolveSymbolicLinks());
        await root.delete(recursive: true);
        fixtureRoot = null;
      }
      expect(PlayerTerminalBackend.debugOverride, same(terminal));
      expectIsolateClientUntouched();
      resourcesClosed = true;
    } catch (error, stack) {
      contaminated = true;
      cleanupSafe = false;
      debugPrintSynchronously('SKIP_RESOURCE_CLOSE_FAILURE $error\n$stack root=$fixtureRoot');
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

  testWidgets('actual SkipDB held request deduplicates and Skip intro seeks to 20 seconds',
      (tester) async {
    const mediaUrl = 'https://skip-fixture.invalid/Example.S01E01.mp4';
    final release = Completer<void>();
    var mountStarted = false;
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    Controls controls() => tester.widget<Controls>(find.byType(Controls).first);
    bool addonTail() => addonStarts() == 1 && addonCached() == 1 && addonDone() == 1 &&
        restoredTracks() == 1;
    void expectNoErrorLogs() {
      expect(observed.where((s) => s.startsWith('SubAuto: ABORT') ||
          s.startsWith('SkipSegments:') && s.contains('fetch failed') ||
          s.startsWith('SubAuto: auto-select FAILED with exception:') ||
          s.contains('Error fetching addon subtitles')), isEmpty);
    }

    await http.runWithClient(() async {
      try {
        phase = 'public preference and authorized empty-addon setup';
        final policy = await tester.runAsync(() async {
          await PlayerPrefs.setSkipSegmentsEnabled(true);
          await PlayerPrefs.setSkipSegmentProvider('skipdb');
          await TrackingPrefs.setTrackingScrobbleTargets({});
          await TrackingPrefs.setWatchProgressSource(WatchProgressSource.local);
          await TrackingPrefs.setHomeTickSources({});
          await StremioService.instance.clearAllAddons();
          expect(await StremioService.instance.getEnabledAddons(), isEmpty);
          expect(await StremioSubtitleService.instance.getSubtitleAddons(), isEmpty);
          expect(await PlayerPrefs.getSkipSegmentsEnabled(), isTrue);
          expect(await PlayerPrefs.getSkipSegmentProvider(), 'skipdb');
          return TrackingSourcePolicy.load();
        });
        expect(policy, isNotNull);
        expect(policy!.scrobbleTargets, {TrackingSource.local});
        expect(policy.progressSource, WatchProgressSource.local);
        phase = 'direct positive IMDb ready video; held skip HTTP';
        mountStarted = true;
        await tester.pumpWidget(MaterialApp(
          builder: (_, child) => AppThemeScope(
              theme: AppThemes.byId('spotlight'), child: child!),
          home: const VideoPlayerScreen(
            videoUrl: mediaUrl, title: 'Example.S01E01.mp4',
            contentType: 'series', contentTitle: 'Example',
            contentImdbId: 'tt1234567', contentSeason: 1, contentEpisode: 1,
            traktScrobble: false, simklScrobble: false, mdblistScrobble: false,
          ),
        ));
        await reach(tester, () => clients.length == 1 && clients.single.sent == 1 &&
            find.byType(mkv.Video).evaluate().length == 1);
        expect(tester.widget<mkv.Video>(find.byType(mkv.Video)).controller,
            same(terminal.video));
        expect(terminal.construction, ['bootstrap', 'player', 'video']);
        expect(terminal.properties!.events.where((e) => e.startsWith('open:')),
            ['open:$mediaUrl:play=true']);
        expect(clients.single.bodyStarted, 0);
        expect(clients.single.bodyDone, 0);
        expect(find.byType(SkipSegmentButton), findsNothing);

        phase = 'same public position events while provider producer held';
        // Controls is gated during startup restoration. These are delivered
        // public stream events, NOT per-event Controls-clock assertions.
        terminal.properties!.reportPosition(const Duration(seconds: 15));
        await tester.runAsync(() => Future<void>(() {}));
        await tester.pump(const Duration(milliseconds: 50));
        terminal.properties!.reportPosition(const Duration(seconds: 16));
        await tester.runAsync(() => Future<void>(() {}));
        await tester.pump(const Duration(milliseconds: 50));
        terminal.properties!.reportPosition(const Duration(seconds: 15));
        await tester.runAsync(() => Future<void>(() {}));
        await tester.pump(const Duration(milliseconds: 50));
        expect(clients, hasLength(1));
        expect(clients.single.sent, 1);
        expect(clients.single.bodyStarted, 0);
        expect(requests, hasLength(1));
        expect(find.byType(SkipSegmentButton), findsNothing);

        phase = 'release actual HTTP body; real parser and rendered action';
        release.complete();
        await reach(tester, () => clients.single.bodyDone == 1 &&
            find.byType(SkipSegmentButton).evaluate().length == 1);
        expect(find.text('Skip intro »'), findsOneWidget);
        expect(clients.single.bodyStarted, 1);
        expect(terminal.properties!.seeks, isEmpty);
        await tester.tap(find.text('Skip intro »'));
        await reach(tester, () => terminal.properties!.seeks.contains(
            (mediaUrl, const Duration(seconds: 20))));
        expect(terminal.properties!.seeks, [(mediaUrl, const Duration(seconds: 20))]);
        expect(requests, hasLength(1));
        phase = 'explicit empty-track timer frontier after HTTP and skip proof';
        expect(observed.where((s) => s.startsWith(
            'SubAuto: _restoreTrackPreferences entered (token=')), hasLength(1));
        expect(clients.single.bodyDone, 1);
        final subtitleClockBefore = binding.clock.now();
        // Source: waitForSubtitleTracks is 50 chained 100ms fake-zone delays.
        // Pinned fake_async elapse executes due timers and their microtasks.
        // This advances that timer frontier, not real prefs/DB Future work.
        await tester.pump(const Duration(seconds: 5));
        final subtitleClockAfter = binding.clock.now();
        expect(subtitleClockAfter.difference(subtitleClockBefore),
            const Duration(seconds: 5));
        debugPrintSynchronously('SKIP_SUBTITLE_PHASE '
            'before=$subtitleClockBefore after=$subtitleClockAfter');
        // Existing bounded root/event turns observe the real positive tail.
        await reach(tester, () => addonTail() &&
            find.byType(Controls).evaluate().isNotEmpty && controls().isReady &&
            controls().clock.value.position == const Duration(seconds: 20));
        expectNoErrorLogs();
      } catch (error, stack) {
        primary = error;
        primaryStack = stack;
        reportClients('primary');
        rethrow;
      } finally {
        try {
          phase = 'unmount, real terminal disposal, owned HTTP body tail';
          if (mountStarted) {
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pump(const Duration(milliseconds: 250));
          }
          // Always release our producer, including failed held assertions. Do
          // not equate this completion with the host fetch chain settling.
          if (!release.isCompleted) release.complete();
          final backend = terminal.properties;
          if (backend != null) {
            await tester.runAsync(() async {
              await backend.disposalEntered.future.timeout(const Duration(seconds: 5));
              await backend.disposal!.timeout(const Duration(seconds: 5));
            });
            expect(backend.closed, isTrue);
          }
          await reach(tester, () => clients.length == 1 &&
              clients.single.sent == 1 && clients.single.bodyDone == 1 &&
              clients.single.closed && addonTail());
          final counts = (clients.length, requests.length, clients.single.sent,
              clients.single.bodyStarted, clients.single.bodyDone, clients.single.closeCalls,
              addonStarts(), addonCached(), addonDone(), restoredTracks());
          final seeks = List.of(backend!.seeks);
          await tester.pump(const Duration(milliseconds: 800));
          expect((clients.length, requests.length, clients.single.sent,
              clients.single.bodyStarted, clients.single.bodyDone, clients.single.closeCalls,
              addonStarts(), addonCached(), addonDone(), restoredTracks()), counts);
          expect(backend.seeks, seeks);
          expect(backend.closed, isTrue);
          expect(VideoOutputLease.isHeld, isFalse);
          expect(terminal.unexpected, isEmpty);
          expectNoErrorLogs();
          expectIsolateClientUntouched();
          reportClients('finite-successful-cleanup');
          cleanupSafe = true;
        } catch (error, stack) {
          reportClients('cleanup-failure');
          debugPrintSynchronously('SKIP_CLEANUP $error\n$stack');
          if (primary != null) Error.throwWithStackTrace(primary!, primaryStack!);
          rethrow;
        } finally {
          debugPrint = originalPrint;
        }
      }
    }, () {
      final client = _TrackedClient(terminal.unexpected, requests, clients.length, release);
      clients.add(client);
      return client;
    });
  }, timeout: const Timeout(Duration(seconds: 45)));
}
