import 'dart:async';
import 'dart:io';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/screens/video_player/widgets/source_sheet.dart';
import 'package:debrify/screens/video_player/widgets/transition_overlay.dart';

import 'package:debrify/screens/video_player/services/player_terminal_backend.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/debrify_tv_database.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/secret_vault.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/utils/app_storage.dart';
import 'package:debrify/widgets/video_output_lease.dart';
import 'package:flutter/material.dart';
import 'package:debrify/screens/video_player/widgets/tv_controls.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:flutter/foundation.dart' show debugPrintSynchronously;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:media_kit_video/media_kit_video.dart' as mkv;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// Draft adapted from frozen cd2451 real-host scrub fixture; these tests mount old
// VideoPlayerScreen. No scrub algorithm, generation mutation or private State call.
// Harness originally adapted from the accepted decoder fixture.
// Only external SDK state and terminal operations are scripted; host controls,
// scrub/input policy, preview, seek ordering and focus remain real lib code.
class _TerminalStreams extends mk.PlatformPlayer {
  _TerminalStreams(mk.PlayerConfiguration configuration)
    : super(configuration: configuration);

  void emitPlaying(bool playing) => playingController.add(playing);
  void emitPosition(Duration position) => positionController.add(position);
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
  bool allowSourceOpen = false;
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
        !(allowSourceOpen && ((property == 'stream-lavf-o' && value == '') ||
            (property == 'sub-visibility' && value == 'no')))) {
      unexpected.add('setProperty:$property');
      throw StateError('Unscripted property write $property');
    }
  }

  void emitPlayback(
    Duration position, {bool playing = false, Duration duration = const Duration(minutes: 10)}
  ) {
    state = state.copyWith(
      playing: playing,
      duration: duration,
      position: position,
    );
    _streams.durationController.add(state.duration);
    _streams.positionController.add(position);
    _streams.playingController.add(playing);
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

  // Terminal responses only: no scrub admission, clamping or seek policy here.
  final operations = <String>[];
  final seeks = <Duration>[];
  @override
  Future<void> pause() async {
    operations.add('pause');
    backend.state = backend.state.copyWith(playing: false);
    backend._streams.emitPlaying(false);
  }

  @override
  Future<void> play() async {
    operations.add('play');
    backend.state = backend.state.copyWith(playing: true);
    backend._streams.emitPlaying(true);
  }

  @override
  Future<void> seek(Duration position) async {
    operations.add('seek:${position.inMilliseconds}');
    seeks.add(position);
    backend.state = backend.state.copyWith(position: position);
    backend._streams.emitPosition(position);
  }

  Completer<void>? openGate;
  bool openEntered = false;
  bool openCompleted = false;
  bool audioCompleted = false;
  final opened = <mk.Playable>[];
  final openPlay = <bool>[];
  final audioIds = <String>[];

  @override
  Future<void> open(mk.Playable playable, {bool play = true}) async {
    if (!backend.allowSourceOpen) {
      backend.unexpected.add('player:unexpected-open');
      throw StateError('Open outside declared source scenario');
    }
    operations.add('open');
    opened.add(playable);
    openPlay.add(play);
    openEntered = true;
    final gate = openGate;
    if (gate == null) throw StateError('Missing owned open gate');
    await gate.future;
    operations.add('open-done');
    openCompleted = true;
  }

  @override
  Future<void> setAudioTrack(mk.AudioTrack track) async {
    if (!backend.allowSourceOpen) {
      backend.unexpected.add('player:unexpected-audio');
      throw StateError('Audio outside declared source scenario');
    }
    operations.add('audio');
    audioIds.add(track.id);
    audioCompleted = true;
  }

  final rates = <double>[];
  @override
  Future<void> setRate(double value) async {
    rates.add(value);
    backend.state = backend.state.copyWith(rate: value);
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

// No HTTP endpoint belongs to these empty-URL, synthetic-callback scenarios.
class _NoHttpClient implements HttpClient {
  _NoHttpClient(this.unexpected);
  final List<String> unexpected;
  @override
  bool autoUncompress = true;
  @override
  String? userAgent;
  @override
  Duration? connectionTimeout;
  @override
  Duration idleTimeout = const Duration(seconds: 15);
  @override
  int? maxConnectionsPerHost;
  @override
  void close({bool force = false}) {}
  @override
  dynamic noSuchMethod(Invocation invocation) {
    unexpected.add('HTTP:${invocation.memberName}:${invocation.positionalArguments}');
    throw StateError('Unscripted HTTP ${invocation.memberName}');
  }
}

class _PopObserver extends NavigatorObserver {
  int pops = 0;
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pops++;
    super.didPop(route, previousRoute);
  }
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const window = MethodChannel('window_manager');
  const brightness = MethodChannel('github.com/aaassseee/screen_brightness');
  const wake =
      'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle';
  late PlayerTerminalBackend? previous;
  late _Terminal terminal;
  late _PopObserver observer;
  DatabaseFactory? previousDatabaseFactory;
  Directory? ownedRoot;
  String? verifiedParent;
  Object? primaryFailure;
  StackTrace? primaryStack;

  setUpAll(() {
    previousDatabaseFactory = databaseFactoryOrNull;
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });
  tearDownAll(() { databaseFactoryOrNull = previousDatabaseFactory; });

  setUp(() async {
    primaryFailure = null;
    primaryStack = null;
    previous = PlayerTerminalBackend.debugOverride;
    terminal = _Terminal();
    observer = _PopObserver();
    // These tests own an isolated test process's TV/profile caches.
    // The nullable private TV cache is not exposed; no full-global restore claim.
    expect(PlatformUtil.isAndroidTvCached, isFalse);
    PlatformUtil.debugSetAndroidTvCached(true);
    SharedPreferences.setMockInitialValues({});
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    SecretVault.debugReset(deviceIdOverride: 'transition-origin');
    StorageService.resetProfileCaches();
    final parent = await Directory('.dart_tool').absolute.create(recursive: true);
    verifiedParent = await parent.resolveSymbolicLinks();
    ownedRoot = await parent.createTemp('transition-origin-');
    AppStorage.debugOverride(documents: ownedRoot!, support: ownedRoot!, cache: ownedRoot!);
    await DebrifyTvDatabase.instance.debugResetScopeState();
    await DebrifyTvDatabase.instance.database;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(window, (call) async {
      switch (call.method) {
        case 'setFullScreen':
        case 'setBounds': return null;
        case 'getBounds': return {'x': 0.0, 'y': 0.0, 'width': 1280.0, 'height': 720.0};
        case 'isFullScreen': return false;
        default:
          terminal.unexpected.add('window:${call.method}');
          throw StateError('Unexpected window call ${call.method}');
      }
    });
    binding.defaultBinaryMessenger.setMockMessageHandler(wake,
        (_) async => const StandardMessageCodec().encodeMessage([null]));
    binding.defaultBinaryMessenger.setMockMethodCallHandler(brightness, (call) async {
      if (call.method == 'resetApplicationScreenBrightness') return null;
      terminal.unexpected.add('brightness:${call.method}');
      throw StateError('Unexpected brightness call ${call.method}');
    });
    PlayerTerminalBackend.debugOverride = terminal;
  });

  tearDown(() async {
    try {
      final backend = terminal.properties;
      if (backend != null && !backend.closed) {
        // Safety only. A successful case already required host initiation/close.
        debugPrintSynchronously('TRANSITION_SAFETY_CLOSE');
        await binding.runAsync(() async {
          await (backend.disposal ?? backend.dispose())
              .timeout(const Duration(milliseconds: 250));
        });
      }
      terminal.video?.close();
      await DebrifyTvDatabase.instance.debugResetScopeState();
      final root = ownedRoot;
      if (root != null) {
        final actual = await root.resolveSymbolicLinks();
        final parent = verifiedParent!;
        if (!actual.startsWith('$parent${Platform.pathSeparator}') ||
            !actual.substring(parent.length + 1).startsWith('transition-origin-') ||
            actual.substring(parent.length + 1).contains(Platform.pathSeparator)) {
          throw StateError('Owned temporary directory boundary mismatch');
        }
        await root.delete(recursive: true);
        ownedRoot = null;
      }
      expect(PlayerTerminalBackend.debugOverride, same(terminal));
      expect(terminal.unexpected, isEmpty);
    } catch (error, stack) {
      debugPrintSynchronously('TRANSITION_TEARDOWN $error\n$stack');
      rethrow;
    } finally {
      try {
        PlatformUtil.debugSetAndroidTvCached(null);
        PlayerTerminalBackend.debugOverride = previous;
        binding.defaultBinaryMessenger.setMockMethodCallHandler(window, null);
        binding.defaultBinaryMessenger.setMockMethodCallHandler(brightness, null);
        binding.defaultBinaryMessenger.setMockMessageHandler(wake, null);
      } finally {
        StorageService.resetProfileCaches();
        AppStorage.debugReset();
        ProfileRuntime.debugReset();
        SecretVault.debugReset();
      }
    }
  });

  TvControls controls(WidgetTester tester) =>
      tester.widget<TvControls>(find.byType(TvControls));
  TransitionOverlay overlay(WidgetTester tester) =>
      tester.widget<TransitionOverlay>(find.byType(TransitionOverlay));
  Torrent source(int index) => Torrent(
    rowid: index, infohash: '', name: 'Transition source $index', sizeBytes: 1,
    createdUnix: 0, seeders: 0, leechers: 0, completed: 0, scrapedDate: 0,
    streamType: StreamType.directUrl, directUrl: 'https://transition.invalid/$index',
  );

  Future<void> withHost(WidgetTester tester,
      Future<void> Function(_Properties) exercise, {
      Future<Map<String, String>?> Function()? requestMagicNext,
      bool sourceMode = false,
      void Function()? releaseOwnedGates,
  }) async {
    await HttpOverrides.runZoned(() async {
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      try {
        await tester.pumpWidget(MaterialApp(
          navigatorObservers: [observer],
          builder: (_, child) =>
              AppThemeScope(theme: AppThemes.byId('spotlight'), child: child!),
          home: VideoPlayerScreen(
            videoUrl: '', title: 'Transition fixture', disableAutoResume: true,
            requestMagicNext: requestMagicNext,
            audioUrl: sourceMode ? 'https://transition.invalid/audio' : null,
            stremioSources: sourceMode ? [source(0), source(1)] : null,
            resolveStremioSource: sourceMode ? (torrent) async => torrent.directUrl : null,
          ),
        ));
        // Fixed setup budget. Missing construction is STOP, not another pump loop.
        await tester.pump();
        await tester.pump();
        expect(terminal.construction, ['bootstrap', 'player', 'video']);
        final backend = terminal.properties!;
        backend.configuration.ready!();
        backend.emitPlayback(Duration.zero);
        await tester.pump();
        expect(find.byType(TvControls), findsOneWidget);
        expect(find.byType(TransitionOverlay), findsNothing);
        expect(backend.reads, isEmpty);
        expect(terminal.player!.operations, isEmpty);
        await exercise(backend);
        expect(terminal.unexpected, isEmpty);
        expect(tester.takeException(), isNull);
      } catch (error, stack) {
        primaryFailure = error;
        primaryStack = stack;
        debugPrintSynchronously('TRANSITION_PRIMARY $error\n$stack');
        rethrow;
      } finally {
        try {
          // Unmount BEFORE releasing a held producer if the primary path failed.
          Object? unmountFailure;
          StackTrace? unmountStack;
          try {
            await tester.pumpWidget(const SizedBox.shrink());
          } catch (error, stack) {
            unmountFailure = error;
            unmountStack = stack;
            rethrow;
          } finally {
            try {
              releaseOwnedGates?.call();
              final gate = terminal.player?.openGate;
              if (gate != null && !gate.isCompleted) gate.complete();
            } catch (error, stack) {
              debugPrintSynchronously('TRANSITION_RELEASE $error\n$stack');
              if (unmountFailure != null) {
                Error.throwWithStackTrace(unmountFailure, unmountStack!);
              }
              rethrow;
            }
          }
          await tester.pump(const Duration(milliseconds: 250));
          final backend = terminal.properties;
          if (backend != null) {
            expect(backend.disposal, isNotNull,
                reason: 'Host must initiate real terminal disposal');
            expect(backend.closed, isTrue,
                reason: 'Actual close must finish at declared cleanup boundary');
            // Completion was observed above; no missing producer is awaited.
            await tester.runAsync(() => backend.disposal!);
          }
          expect(VideoOutputLease.isHeld, isFalse);
          expect(terminal.unexpected, isEmpty);
          expect(tester.takeException(), isNull);
        } catch (error, stack) {
          debugPrintSynchronously('TRANSITION_CLEANUP $error\n$stack');
          if (primaryFailure != null) {
            Error.throwWithStackTrace(primaryFailure!, primaryStack!);
          }
          rethrow;
        }
      }
    }, createHttpClient: (_) => _NoHttpClient(terminal.unexpected));
  }

  testWidgets('old host playing event rearms transition retirement from 3000 to 4000', (tester) async {
    final reply = Completer<Map<String, String>?>();
    var requests = 0;
    await withHost(tester, (backend) async {
      controls(tester).onNext!();
      await tester.pump();
      expect(requests, 1);
      expect(controls(tester).isTransitioning, isTrue);
      final animation = overlay(tester).rainbowController;
      expect(animation.isAnimating, isTrue);
      expect(terminal.player!.operations, ['pause']);
      // T0 is the delivered playing event, all continuations in widget zone.
      backend.emitPlayback(Duration.zero, playing: true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1000));
      backend.emitPlayback(Duration.zero, playing: false);
      await tester.pump();
      backend.emitPlayback(Duration.zero, playing: true);
      await tester.pump(); // T1000: actual false->true, survives distinct streams.
      expect(overlay(tester).rainbowController, same(animation));
      await tester.pump(const Duration(milliseconds: 1999));
      expect(find.byType(TransitionOverlay), findsOneWidget); // T2999.
      await tester.pump(const Duration(milliseconds: 1));
      expect(find.byType(TransitionOverlay), findsOneWidget); // Old T3000 cancelled.
      expect(animation.isAnimating, isTrue);
      await tester.pump(const Duration(milliseconds: 999));
      expect(find.byType(TransitionOverlay), findsOneWidget); // T3999.
      await tester.pump(const Duration(milliseconds: 1));
      expect(find.byType(TransitionOverlay), findsNothing); // New T4000.
      expect(animation.isAnimating, isFalse);
      expect(controls(tester).isTransitioning, isTrue); // Provider still pending.
      expect(requests, 1);
      reply.complete(null);
      await tester.pump();
      expect(controls(tester).isTransitioning, isFalse);
      expect(terminal.player!.operations, ['pause']);
      expect(terminal.player!.seeks, isEmpty);
      expect(observer.pops, 0);
    }, requestMagicNext: () { requests++; return reply.future; },
       releaseOwnedGates: () { if (!reply.isCompleted) reply.complete(null); });
  });

  testWidgets('old public source selection replaces playing timer with direct 1500 finish', (tester) async {
    await withHost(tester, (backend) async {
      backend.allowSourceOpen = true;
      final player = terminal.player!;
      player.openGate = Completer<void>();
      expect(controls(tester).onShowSources, isNotNull);
      controls(tester).onShowSources!();
      await tester.pump();
      final sheet = tester.widget<SourceSheet>(find.byType(SourceSheet));
      expect(sheet.currentSourceIndex, 0);
      // Actual rendered public callback; resolver/physical button are not claimed.
      sheet.onSourceSelected(1, 'https://transition.invalid/1');
      await tester.pump();
      await tester.pump();
      expect(find.byType(SourceSheet), findsNothing);
      expect(controls(tester).isTransitioning, isTrue);
      expect(player.openEntered, isTrue);
      expect(player.openCompleted, isFalse);
      expect(player.operations, ['pause', 'open']);
      expect(player.openPlay, [false]); // Actual external-audio branch opens paused.
      expect((player.opened.single as mk.Media).uri, 'https://transition.invalid/1');
      final animation = overlay(tester).rainbowController;
      backend.emitPlayback(Duration.zero, playing: true);
      await tester.pump(); // T0 event arms original3000 timer while open is held.
      await tester.pump(const Duration(milliseconds: 1000));
      expect(overlay(tester).rainbowController, same(animation));
      player.openGate!.complete();
      await tester.pump();
      await tester.pump(); // Only microtasks; direct finish is now T1000.
      expect(player.openCompleted, isTrue);
      expect(player.audioCompleted, isTrue);
      expect(player.audioIds, ['https://transition.invalid/audio']);
      expect(player.operations, ['pause', 'open', 'open-done', 'audio', 'play']);
      expect(player.seeks, isEmpty); // Original position0, no resume seek.
      expect(controls(tester).isTransitioning, isFalse); // Actual finish observation.
      expect(overlay(tester).rainbowController, same(animation));
      expect(backend.reads, isEmpty);
      expect(backend.writes.where((x) => x.$1 != 'video-zoom').toList(), [
        ('stream-lavf-o', ''), ('sub-visibility', 'no'),
      ]);
      // _Player.play emits true again. Existing distinct prevents an extra event;
      // even if delivered, direct finish follows that await and replaces its timer.
      await tester.pump(const Duration(milliseconds: 1499));
      expect(find.byType(TransitionOverlay), findsOneWidget); // T2499.
      expect(animation.isAnimating, isTrue);
      await tester.pump(const Duration(milliseconds: 1));
      expect(find.byType(TransitionOverlay), findsNothing); // T2500, before old3000.
      expect(animation.isAnimating, isFalse);
      expect(controls(tester).isTransitioning, isFalse);
      expect(observer.pops, 0);
    }, sourceMode: true);
  });
}
