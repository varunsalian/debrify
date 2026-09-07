import 'dart:async';
import 'dart:io';

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

// Transport fixture adapted from committed 104ac6de; these tests mount current
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
    if (property != 'video-zoom') {
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
  Object? primaryFailure;
  StackTrace? primaryStack;

  setUpAll(() {
    previousDatabaseFactory = databaseFactoryOrNull;
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  tearDownAll(() {
    databaseFactoryOrNull = previousDatabaseFactory;
  });

  setUp(() async {
    primaryFailure = null;
    primaryStack = null;
    previous = PlayerTerminalBackend.debugOverride;
    terminal = _Terminal();
    observer = _PopObserver();
    // This isolated fixture starts with the default cache, never a device override.
    expect(PlatformUtil.isAndroidTvCached, isFalse);
    PlatformUtil.debugSetAndroidTvCached(true);
    SharedPreferences.setMockInitialValues({});
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    SecretVault.debugReset(deviceIdOverride: 'decoder-terminal-origin');
    StorageService.resetProfileCaches();
    final root = await Directory(
      '.dart_tool',
    ).absolute.createTemp('scrub-session-');
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
    PlayerTerminalBackend.debugOverride = terminal;
  });

  tearDown(() async {
    try {
      if (terminal.properties != null && !terminal.properties!.closed) {
        if (terminal.properties!.disposal == null) {
          debugPrintSynchronously('SCRUB_SAFETY_CLOSE: host did not initiate disposal');
        }
        await binding.runAsync(() => terminal.properties!.disposal ?? terminal.properties!.dispose());
      }
      terminal.video?.close();
      await DebrifyTvDatabase.instance.debugResetScopeState();
      expect(PlayerTerminalBackend.debugOverride, same(terminal));
    } catch (error, stack) {
      debugPrintSynchronously('SCRUB_TEARDOWN $error\n$stack');
      if (primaryFailure != null) {
        Error.throwWithStackTrace(primaryFailure!, primaryStack!);
      }
      rethrow;
    } finally {
      PlatformUtil.debugSetAndroidTvCached(null);
      PlayerTerminalBackend.debugOverride = previous;
      binding.defaultBinaryMessenger.setMockMethodCallHandler(window, null);
      binding.defaultBinaryMessenger.setMockMethodCallHandler(brightness, null);
      binding.defaultBinaryMessenger.setMockMessageHandler(wake, null);
      StorageService.resetProfileCaches();
      AppStorage.debugReset();
      ProfileRuntime.debugReset();
      SecretVault.debugReset();
    }
  });

  Future<void> withHost(
    WidgetTester tester,
    Future<void> Function(_Properties) exercise, {
    bool hideSeekbar = false,
    Future<Map<String, String>?> Function()? requestMagicNext,
    Future<Map<String, dynamic>?> Function()? requestNextChannel,
  }) async {
    await HttpOverrides.runZoned(() async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    try {
      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [observer],
          builder: (_, child) =>
              AppThemeScope(theme: AppThemes.byId('spotlight'), child: child!),
          home: VideoPlayerScreen(
            videoUrl: '',
            title: 'Scrub fixture',
            disableAutoResume: true,
            hideSeekbar: hideSeekbar,
            requestMagicNext: requestMagicNext,
            requestNextChannel: requestNextChannel,
          ),
        ),
      );
      // Accepted fixture construction bound, not a behavior timing assertion.
      for (var i = 0; i < 20 && terminal.video == null; i++) {
        await tester.pump();
      }
      expect(terminal.construction, ['bootstrap', 'player', 'video']);
      final backend = terminal.properties!;
      backend.configuration.ready!();
      backend.emitPlayback(const Duration(seconds: 1));
      await tester.pump();
      expect(find.byType(TvControls), findsOneWidget);
      expect(backend.reads, isEmpty);
      await exercise(backend);
      expect(terminal.unexpected, isEmpty);
      expect(tester.takeException(), isNull);
    } catch (error, stack) {
      primaryFailure = error;
      primaryStack = stack;
      debugPrintSynchronously('SCRUB_PRIMARY $error\n$stack');
      rethrow;
    } finally {
      try {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 250));
        if (terminal.properties != null) {
          final hostDisposal = terminal.properties!.disposal;
          expect(hostDisposal, isNotNull,
              reason: 'host must initiate disposal before fixture safety cleanup');
          await tester.runAsync(() => hostDisposal!);
        }
        expect(VideoOutputLease.isHeld, isFalse);
        expect(terminal.unexpected, isEmpty);
      } catch (error, stack) {
        debugPrintSynchronously('SCRUB_CLEANUP $error\n$stack');
        primaryFailure ??= error;
        primaryStack ??= stack;
        Error.throwWithStackTrace(primaryFailure!, primaryStack!);
      }
    }
    }, createHttpClient: (_) => _NoHttpClient(terminal.unexpected));
  }

  TvControls controls(WidgetTester tester) =>
      tester.widget<TvControls>(find.byType(TvControls));

  Future<void> key(WidgetTester tester, LogicalKeyboardKey value) async {
    await tester.sendKeyEvent(value);
    await tester.pump();
  }

  Future<void> start(
    WidgetTester tester,
    _Properties backend, {
    bool playing = true,
    Duration position = const Duration(seconds: 1),
    LogicalKeyboardKey direction = LogicalKeyboardKey.arrowRight,
  }) async {
    backend.emitPlayback(position, playing: playing);
    await tester.pump();
    final progress = controls(tester).progressFocusNode;
    progress.requestFocus();
    await tester.pump();
    expect(FocusManager.instance.primaryFocus, same(progress));
    await key(tester, direction);
  }

  Future<void> hideBar(WidgetTester tester) async {
    controls(tester).playPauseFocusNode.requestFocus();
    await tester.pump();
    await key(tester, LogicalKeyboardKey.escape);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'tvPlayerRoot');
  }

  testWidgets('hidden third rapid arrow enters scrub after two real nudges', (tester) async {
    await withHost(tester, (backend) async {
      backend.emitPlayback(const Duration(seconds: 1), playing: true);
      await tester.pump();
      await hideBar(tester);
      final player = terminal.player!;
      final wall = Stopwatch()..start();
      await key(tester, LogicalKeyboardKey.arrowRight);
      expect(controls(tester).scrubPreview, isNull);
      expect(player.seeks, [const Duration(seconds: 11)]);
      await key(tester, LogicalKeyboardKey.arrowRight);
      expect(controls(tester).scrubPreview, isNull);
      expect(player.seeks, [const Duration(seconds: 11), const Duration(seconds: 21)]);
      expect(wall.elapsedMilliseconds, lessThan(400), reason: 'real DateTime admission precondition, not fake-clock proof');
      await key(tester, LogicalKeyboardKey.arrowRight);
      expect(wall.elapsedMilliseconds, lessThan(400));
      expect(controls(tester).scrubPreview, const Duration(seconds: 31));
      expect(player.operations, ['seek:11000', 'seek:21000', 'pause']);
      await key(tester, LogicalKeyboardKey.enter);
      expect(player.operations, ['seek:11000', 'seek:21000', 'pause', 'seek:31000', 'play']);
    });
  });

  testWidgets('slow hidden arrow resets admission then two more rapid arrows begin', (tester) async {
    await withHost(tester, (backend) async {
      await hideBar(tester);
      await key(tester, LogicalKeyboardKey.arrowRight);
      // Production uses DateTime.now, not Flutter's fake clock. One finite real
      // wait establishes the slow-input precondition; no timing retry loop.
      final slow = Stopwatch()..start();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 410)));
      expect(slow.elapsedMilliseconds, greaterThanOrEqualTo(400));
      await key(tester, LogicalKeyboardKey.arrowRight);
      expect(controls(tester).scrubPreview, isNull);
      final rapid = Stopwatch()..start();
      await key(tester, LogicalKeyboardKey.arrowRight);
      expect(controls(tester).scrubPreview, isNull);
      expect(rapid.elapsedMilliseconds, lessThan(400));
      await key(tester, LogicalKeyboardKey.arrowRight);
      expect(rapid.elapsedMilliseconds, lessThan(400));
      expect(controls(tester).scrubPreview, const Duration(seconds: 41));
      expect(terminal.player!.seeks, [const Duration(seconds: 11), const Duration(seconds: 21), const Duration(seconds: 31)]);
      await key(tester, LogicalKeyboardKey.escape);
      expect(terminal.player!.operations, ['seek:11000', 'seek:21000', 'seek:31000']);
    });
  });

  testWidgets('active acceleration crosses 8 and 16 then clamps without intermediate seeks', (tester) async {
    await withHost(tester, (backend) async {
      await start(tester, backend);
      final player = terminal.player!;
      final aspect = controls(tester).aspectMode;
      await key(tester, LogicalKeyboardKey.keyA);
      expect(controls(tester).aspectMode, aspect);
      expect(controls(tester).scrubPreview, const Duration(seconds: 11));
      for (var i = 0; i < 7; i++) { await key(tester, LogicalKeyboardKey.arrowRight); }
      expect(controls(tester).scrubPreview, const Duration(seconds: 81));
      await key(tester, LogicalKeyboardKey.arrowRight);
      expect(controls(tester).scrubPreview, const Duration(seconds: 111));
      for (var i = 0; i < 7; i++) { await key(tester, LogicalKeyboardKey.arrowRight); }
      expect(controls(tester).scrubPreview, const Duration(seconds: 321));
      await key(tester, LogicalKeyboardKey.arrowRight);
      expect(controls(tester).scrubPreview, const Duration(seconds: 381));
      for (var i = 0; i < 4; i++) { await key(tester, LogicalKeyboardKey.arrowRight); }
      expect(controls(tester).scrubPreview, const Duration(minutes: 10));
      expect(player.operations, ['pause']);
      expect(player.seeks, isEmpty);
      await key(tester, LogicalKeyboardKey.enter);
      expect(player.operations, ['pause', 'seek:600000', 'play']);
      expect(controls(tester).scrubPreview, isNull);
    });
  });

  testWidgets('paused left scrub clamps zero and confirm does not resume', (tester) async {
    await withHost(tester, (backend) async {
      await start(tester, backend, playing: false, direction: LogicalKeyboardKey.arrowLeft);
      expect(controls(tester).scrubPreview, Duration.zero);
      await key(tester, LogicalKeyboardKey.arrowLeft);
      expect(controls(tester).scrubPreview, Duration.zero);
      expect(terminal.player!.operations, isEmpty);
      await key(tester, LogicalKeyboardKey.enter);
      expect(terminal.player!.operations, ['seek:0']);
      expect(controls(tester).isPlaying, isFalse);
    });
  });

  testWidgets('Down cancels captured playing scrub without seek and restores focus', (tester) async {
    await withHost(tester, (backend) async {
      await start(tester, backend);
      final progress = controls(tester).progressFocusNode;
      final play = controls(tester).playPauseFocusNode;
      expect(controls(tester).isPlaying, isFalse);
      await key(tester, LogicalKeyboardKey.arrowDown);
      expect(controls(tester).scrubPreview, isNull);
      expect(terminal.player!.operations, ['pause', 'play']);
      expect(terminal.player!.seeks, isEmpty);
      expect(FocusManager.instance.primaryFocus, same(play));
      expect(controls(tester).progressFocusNode, same(progress));
    });
  });

  testWidgets('actual navigator maybePop cancels preview without popping player', (tester) async {
    await withHost(tester, (backend) async {
      await start(tester, backend);
      final nav = Navigator.of(tester.element(find.byType(TvControls)));
      expect(await nav.maybePop(), isTrue);
      await tester.pump();
      expect(observer.pops, 0);
      expect(find.byType(VideoPlayerScreen), findsOneWidget);
      expect(controls(tester).scrubPreview, isNull);
      expect(terminal.player!.operations, ['pause', 'play']);
      expect(terminal.player!.seeks, isEmpty);
    });
  });

  for (final hiddenByFlag in [true, false]) {
    testWidgets('hidden arrows cannot scrub with ${hiddenByFlag ? 'hideSeekbar' : 'zero duration'}', (tester) async {
      await withHost(tester, (backend) async {
        if (!hiddenByFlag) {
          backend.emitPlayback(Duration.zero, duration: Duration.zero);
          await tester.pump();
        }
        expect(controls(tester).progressFocusable, isFalse);
        await hideBar(tester);
        for (var i = 0; i < 3; i++) { await key(tester, LogicalKeyboardKey.arrowRight); }
        expect(controls(tester).scrubPreview, isNull);
        expect(terminal.player!.operations, isEmpty);
        expect(terminal.player!.seeks, isEmpty);
      }, hideSeekbar: hiddenByFlag);
    });
  }

  for (final channel in [false, true]) {
    testWidgets('public ${channel ? 'next-channel' : 'next-episode'} abandons before held request', (tester) async {
      final episodeReply = Completer<Map<String, String>?>();
      final channelReply = Completer<Map<String, dynamic>?>();
      var requests = 0;
      await withHost(tester, (backend) async {
        try {
          await start(tester, backend);
          final callback = channel ? controls(tester).onNextChannel : controls(tester).onNext;
          expect(callback, isNotNull);
          callback!(); // Actual rendered public callback; not a physical-button claim.
          await tester.pump();
          expect(requests, 1);
          expect(controls(tester).scrubPreview, isNull);
          expect(controls(tester).isTransitioning, isTrue);
          expect(terminal.player!.operations, ['pause', 'pause']);
          expect(terminal.player!.seeks, isEmpty);
          await key(tester, LogicalKeyboardKey.enter);
          expect(terminal.player!.operations, ['pause', 'pause']);
          if (channel) { channelReply.complete(null); } else { episodeReply.complete(null); }
          await tester.pump();
          expect(controls(tester).isTransitioning, isFalse);
          expect(controls(tester).scrubPreview, isNull);
          expect(terminal.player!.operations, ['pause', 'pause']);
          expect(observer.pops, 0);
        } finally {
          if (!episodeReply.isCompleted) episodeReply.complete(null);
          if (!channelReply.isCompleted) channelReply.complete(null);
          await tester.pump(); // Release held public requests before host teardown.
        }
      }, requestMagicNext: channel ? null : () { requests++; return episodeReply.future; },
         requestNextChannel: channel ? () { requests++; return channelReply.future; } : null);
    });
  }

  testWidgets('unmount with active scrub does not seek or resume borrowed player', (tester) async {
    await withHost(tester, (backend) async {
      await start(tester, backend);
      final player = terminal.player!;
      expect(controls(tester).scrubPreview, const Duration(seconds: 11));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.byType(VideoPlayerScreen), findsNothing);
      expect(player.operations, ['pause']);
      expect(player.seeks, isEmpty);
      expect(tester.takeException(), isNull);
    });
  });
}
