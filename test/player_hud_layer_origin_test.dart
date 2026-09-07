import 'dart:async';
import 'dart:io';

import 'package:debrify/screens/video_player/models/hud_state.dart';
import 'package:debrify/screens/video_player/painters/double_tap_ripple_painter.dart';
import 'package:debrify/screens/video_player/services/player_terminal_backend.dart';
import 'package:debrify/screens/video_player/widgets/buffering_indicator.dart';
import 'package:debrify/screens/video_player/widgets/controls.dart';
import 'package:debrify/screens/video_player/widgets/seek_hud.dart';
import 'package:debrify/screens/video_player/widgets/vertical_hud.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/debrify_tv_database.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/secret_vault.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/utils/app_storage.dart';
import 'package:debrify/utils/time_formatters.dart';
import 'package:debrify/widgets/video_output_lease.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show debugPrintSynchronously;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:media_kit_video/media_kit_video.dart' as mkv;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// Harness copied from test/player_presentation_controls_origin_test.dart.
// Only external SDK state and terminal operations are scripted; the host's
// gesture handlers, HUD notifiers, buffering debounce, double-tap ripple and
// Stremio "next" transaction remain real lib code. The pin drives the HUD
// layer through the public surface (pointer gestures on the gesture layer,
// terminal buffering events, Controls.onNext) and asserts the rendered HUD
// slots so the layer can move out of video_player_screen.dart without the
// pin importing the destination.
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
    if (property != 'video-zoom') {
      unexpected.add('setProperty:$property');
      throw StateError('Unscripted property write $property');
    }
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

  void emitBuffering(bool buffering) {
    state = state.copyWith(buffering: buffering);
    _streams.bufferingController.add(buffering);
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

  final seeks = <Duration>[];
  @override
  Future<void> seek(Duration duration) async {
    seeks.add(duration);
  }

  final volumes = <double>[];
  @override
  Future<void> setVolume(double volume) async {
    volumes.add(volume);
    backend.state = backend.state.copyWith(volume: volume);
  }

  final transport = <String>[];
  @override
  Future<void> play() async {
    transport.add('play');
  }

  @override
  Future<void> pause() async {
    transport.add('pause');
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

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const window = MethodChannel('window_manager');
  const brightness = MethodChannel('github.com/aaassseee/screen_brightness');
  const wake =
      'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle';
  late PlayerTerminalBackend? previous;
  late _Terminal terminal;
  late List<String> brightnessReads;
  Object? primaryFailure;
  StackTrace? primaryStack;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  setUp(() async {
    previous = PlayerTerminalBackend.debugOverride;
    terminal = _Terminal();
    brightnessReads = <String>[];
    SharedPreferences.setMockInitialValues({});
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    SecretVault.debugReset(deviceIdOverride: 'hud-layer-origin');
    StorageService.resetProfileCaches();
    final root = await Directory(
      '.dart_tool',
    ).absolute.createTemp('hud-layer-');
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
      // The pan handler samples the current brightness on every pan start
      // (it is the brightness gesture's baseline). Answer the read; any
      // brightness WRITE stays unexpected so a pan that lands on the left
      // half is rejected by the harness rather than silently accepted.
      if (call.method == 'getApplicationScreenBrightness') {
        brightnessReads.add(call.method);
        return 0.5;
      }
      terminal.unexpected.add('brightness:${call.method}');
      throw StateError('Unexpected brightness call ${call.method}');
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
      debugPrintSynchronously('HUD_TEARDOWN $error\n$stack');
      if (primaryFailure != null) {
        Error.throwWithStackTrace(primaryFailure!, primaryStack!);
      }
      rethrow;
    } finally {
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
    VideoPlayerScreen screen = const VideoPlayerScreen(
      videoUrl: '',
      title: 'HUD fixture',
      disableAutoResume: true,
    ),
  }) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    primaryFailure = null;
    primaryStack = null;
    try {
      await tester.pumpWidget(
        MaterialApp(
          builder: (_, child) =>
              AppThemeScope(theme: AppThemes.byId('spotlight'), child: child!),
          home: screen,
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
      expect(find.byType(Controls), findsOneWidget);
      expect(backend.reads, isEmpty);
      await exercise(backend);
      expect(terminal.unexpected, isEmpty);
    } catch (error, stack) {
      primaryFailure = error;
      primaryStack = stack;
      debugPrintSynchronously('HUD_PRIMARY $error\n$stack');
      rethrow;
    } finally {
      try {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 250));
        if (terminal.properties != null) await terminal.properties!.dispose();
        expect(VideoOutputLease.isHeld, isFalse);
        expect(terminal.unexpected, isEmpty);
      } catch (error, stack) {
        debugPrintSynchronously('HUD_CLEANUP $error\n$stack');
        if (primaryFailure != null) {
          Error.throwWithStackTrace(primaryFailure!, primaryStack!);
        }
        rethrow;
      }
    }
  }

  // The nearest AnimatedOpacity above a HUD slot's content is the slot's
  // fade; the host keeps the slot mounted and drives opacity 1/0.
  Finder fadeOf(Finder content) =>
      find.ancestor(of: content, matching: find.byType(AnimatedOpacity)).first;
  double opacityOf(WidgetTester tester, Finder content) =>
      tester.widget<AnimatedOpacity>(fadeOf(content)).opacity;
  List<double> fades120(WidgetTester tester) => tester
      .widgetList<AnimatedOpacity>(find.byType(AnimatedOpacity))
      .where((fade) => fade.duration == const Duration(milliseconds: 120))
      .map((fade) => fade.opacity)
      .toList();

  // A pan's first movement is absorbed by drag acceptance (touch slop);
  // pumping afterwards lets the async pan-start baseline settle before the
  // seek/volume movement that follows. Both are real host handlers.
  Future<TestGesture> beginPan(WidgetTester tester, Offset at) async {
    final gesture = await tester.startGesture(at);
    await gesture.moveBy(const Offset(30, 0));
    await tester.pump();
    return gesture;
  }

  testWidgets(
    'horizontal pan shows the formatted seek HUD then seeks and fades on pan end',
    (tester) async {
      await withHost(tester, (backend) async {
        final gesture = await beginPan(tester, const Offset(640, 360));
        expect(brightnessReads, ['getApplicationScreenBrightness']);
        expect(find.byType(SeekHud), findsNothing);
        // 100 px of 1280 across a 10-minute file maps to 120 s * 100/1280.
        await gesture.moveBy(const Offset(100, 0));
        await tester.pump();
        final seekHud = find.byType(SeekHud);
        expect(seekHud, findsOneWidget);
        final state = tester.widget<SeekHud>(seekHud).hud;
        expect(state.base, const Duration(seconds: 1));
        expect(state.target, const Duration(seconds: 10));
        expect(state.isForward, isTrue);
        expect(
          tester.widget<SeekHud>(seekHud).format(const Duration(seconds: 10)),
          formatDuration(const Duration(seconds: 10)),
        );
        expect(find.text('00:10  (+00:09)'), findsOneWidget);
        expect(opacityOf(tester, seekHud), 1);
        expect(
          tester.widget<AnimatedOpacity>(fadeOf(seekHud)).duration,
          const Duration(milliseconds: 120),
        );
        expect(terminal.player!.seeks, isEmpty);

        await gesture.up();
        await tester.pump();
        expect(terminal.player!.seeks, [const Duration(seconds: 10)]);
        // The HUD is retired 250 ms after the pan ends; the slot fades out.
        expect(find.byType(SeekHud), findsOneWidget);
        await tester.pump(const Duration(milliseconds: 250));
        await tester.pump();
        expect(find.byType(SeekHud), findsNothing);
        // Both 120 ms slots (seek, vertical) stay mounted and sit at 0.
        expect(fades120(tester), hasLength(greaterThanOrEqualTo(2)));
        expect(fades120(tester), everyElement(0));
        expect(find.byType(VerticalHud), findsNothing);
      });
    },
  );

  testWidgets(
    'vertical pan on the right half shows the volume HUD and sets the volume',
    (tester) async {
      await withHost(tester, (backend) async {
        final gesture = await beginPan(tester, const Offset(900, 300));
        expect(find.byType(VerticalHud), findsNothing);
        // Dragging down 100 px of 720 lowers the 1.0 baseline by 100/720.
        await gesture.moveBy(const Offset(0, 100));
        await tester.pump();
        final verticalHud = find.byType(VerticalHud);
        expect(verticalHud, findsOneWidget);
        final state = tester.widget<VerticalHud>(verticalHud).hud;
        expect(state.kind, VerticalKind.volume);
        expect(state.value, closeTo(1 - 100 / 720, 1e-9));
        expect(terminal.player!.volumes, hasLength(1));
        expect(
          terminal.player!.volumes.single,
          closeTo(100 - 10000 / 720, 1e-6),
        );
        expect(find.byType(SeekHud), findsNothing);
        expect(opacityOf(tester, verticalHud), 1);
        expect(
          tester.widget<AnimatedOpacity>(fadeOf(verticalHud)).duration,
          const Duration(milliseconds: 120),
        );
        // The volume HUD sits on the right edge with a 24 px inset.
        final inset = find.ancestor(
          of: verticalHud,
          matching: find.byType(Padding),
        );
        expect(
          tester.widget<Padding>(inset.first).padding,
          const EdgeInsets.only(right: 24),
        );
        expect(
          tester.getTopRight(verticalHud).dx,
          tester.getSize(find.byType(Controls)).width - 24,
        );

        await gesture.up();
        await tester.pump();
        expect(terminal.player!.seeks, isEmpty);
        expect(find.byType(VerticalHud), findsOneWidget);
        await tester.pump(const Duration(milliseconds: 250));
        await tester.pump();
        expect(find.byType(VerticalHud), findsNothing);
        expect(terminal.player!.volumes, hasLength(1));
      });
    },
  );

  testWidgets(
    'buffering indicator appears after the debounce and hides on buffering end',
    (tester) async {
      await withHost(tester, (backend) async {
        final indicator = find.byType(BufferingIndicator);
        expect(indicator, findsOneWidget);
        expect(opacityOf(tester, indicator), 0);

        backend.emitBuffering(true);
        await tester.pump();
        expect(opacityOf(tester, indicator), 0);
        await tester.pump(const Duration(milliseconds: 799));
        expect(opacityOf(tester, indicator), 0);
        await tester.pump(const Duration(milliseconds: 1));
        expect(opacityOf(tester, indicator), 1);
        expect(
          tester.widget<AnimatedOpacity>(fadeOf(indicator)).duration,
          const Duration(milliseconds: 250),
        );
        expect(
          tester.getCenter(indicator),
          tester.getCenter(find.byType(Controls)),
        );

        backend.emitBuffering(false);
        await tester.pump();
        expect(opacityOf(tester, indicator), 0);
        expect(
          tester.widget<AnimatedOpacity>(fadeOf(indicator)).duration,
          const Duration(milliseconds: 200),
        );
        expect(indicator, findsOneWidget);
      });
    },
  );

  testWidgets(
    'double tap right of centre seeks forward and paints the ripple for 450 ms',
    (tester) async {
      await withHost(tester, (backend) async {
        final ripple = find.byWidgetPredicate(
          (widget) =>
              widget is CustomPaint && widget.painter is DoubleTapRipplePainter,
        );
        expect(ripple, findsNothing);

        const at = Offset(900, 360);
        await tester.tapAt(at);
        await tester.pump(const Duration(milliseconds: 100));
        await tester.tapAt(at);
        await tester.pump();
        expect(terminal.player!.seeks, [const Duration(seconds: 11)]);
        expect(ripple, findsOneWidget);
        final painted =
            (tester.widget<CustomPaint>(ripple).painter
                    as DoubleTapRipplePainter)
                .ripple;
        expect(painted.icon, Icons.forward_10_rounded);
        expect(painted.center.dx, closeTo(900, 1));
        expect(painted.center.dy, closeTo(360, 1));
        expect(
          find.ancestor(of: ripple, matching: find.byType(IgnorePointer)),
          findsWidgets,
        );

        await tester.pump(const Duration(milliseconds: 449));
        expect(ripple, findsOneWidget);
        await tester.pump(const Duration(milliseconds: 1));
        expect(ripple, findsNothing);
        expect(terminal.player!.seeks, [const Duration(seconds: 11)]);
      });
    },
  );

  testWidgets(
    'Stremio TV next shows Loading next... until the provider settles',
    (tester) async {
      final completer = Completer<Map<String, dynamic>?>();
      final requests = <String>[];
      await withHost(
        tester,
        screen: VideoPlayerScreen(
          videoUrl: '',
          title: 'HUD fixture',
          disableAutoResume: true,
          stremioTvChannels: const [
            {'id': 'ch1', 'name': 'One'},
            {'id': 'ch2', 'name': 'Two'},
          ],
          stremioTvCurrentChannelId: 'ch1',
          stremioTvNextProvider: (channelId) {
            requests.add(channelId);
            return completer.future;
          },
        ),
        (backend) async {
          expect(find.text('Loading next...'), findsNothing);
          final onNext = tester.widget<Controls>(find.byType(Controls)).onNext;
          expect(onNext, isNotNull);
          onNext!();
          await tester.pump();
          expect(requests, ['ch1']);
          expect(terminal.player!.transport, ['pause']);
          final loading = find.text('Loading next...');
          expect(loading, findsOneWidget);
          expect(opacityOf(tester, loading), 1);
          expect(
            tester.widget<AnimatedOpacity>(fadeOf(loading)).duration,
            const Duration(milliseconds: 160),
          );
          expect(
            find.descendant(
              of: fadeOf(loading),
              matching: find.byType(CircularProgressIndicator),
            ),
            findsOneWidget,
          );
          expect(
            find.ancestor(of: loading, matching: find.byType(IgnorePointer)),
            findsWidgets,
          );

          completer.complete(null);
          await tester.pump();
          await tester.pump();
          expect(find.text('Loading next...'), findsNothing);
          expect(terminal.player!.transport, ['pause', 'play']);
        },
      );
    },
  );
}
