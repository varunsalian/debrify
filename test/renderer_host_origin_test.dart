import 'dart:async';
import 'dart:io';

import 'package:debrify/screens/video_player/services/player_terminal_backend.dart';
import 'package:debrify/screens/video_player/services/renderer_startup_environment.dart';
import 'package:debrify/models/android_video_renderer_mode.dart';
import 'package:debrify/screens/video_player/widgets/controls.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/debrify_tv_database.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/secret_vault.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/utils/app_storage.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:debrify/widgets/video_output_lease.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show debugPrintSynchronously;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:media_kit_video/media_kit_video.dart' as mkv;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// UNRUN ignored draft against exact d7cdffb7 plus accepted two-site OS seam.
// Terminal support adapted from retained failed fixture; no host policy copied.
// Scripted terminal metadata is not a decoded frame or native playback proof.
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
  final scripts = <String, List<Future<String> Function()>>{};
  final responseOverrides = <String, String>{};
  final holds = <Completer<String>>[];
  bool allowMediaSwitch = false;

  Completer<String> holdNext(String property) {
    final held = Completer<String>();
    holds.add(held);
    scripts.putIfAbsent(property, () => []).add(() => held.future);
    return held;
  }
  bool closed = false;
  static const replies = {
    'hwdec-current': 'no',
    'current-vo': 'gpu',
    'current-ao': 'wasapi',
    'audio-out-params/channel-count': '2',
    'video-codec': 'h264',
    'audio-codec-name': 'aac',
    'audio-params/channel-count': '2',
    'audio-out-params/format': 'float',
  };

  @override
  Future<String> getProperty(
    String property, {
    bool waitForInitialization = true,
  }) async {
    reads.add(property);
    if (!replies.containsKey(property)) {
      unexpected.add('getProperty:$property');
      throw StateError('Unscripted property $property');
    }
    final queue = scripts[property];
    if (queue != null && queue.isNotEmpty) return queue.removeAt(0)();
    return responseOverrides[property] ?? replies[property]!;
  }

  @override
  Future<void> setProperty(
    String property,
    String value, {
    bool waitForInitialization = true,
  }) async {
    writes.add((property, value));
    if (property != 'video-zoom' &&
        !(allowMediaSwitch &&
            {'stream-lavf-o', 'sub-visibility', 'sub-delay'}.contains(property))) {
      unexpected.add('setProperty:$property');
      throw StateError('Unscripted property write $property');
    }
  }

  void emitParams(mk.VideoParams params) {
    state = state.copyWith(videoParams: params);
    _streams.videoParamsController.add(params);
  }

  @override
  Future<void> dispose({bool synchronized = true}) async {
    closed = true;
    await _streams.dispose();
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

  final actions = <String>[];
  final opened = <mk.Playable>[];
  final openPlay = <bool>[];
  final subtitleIds = <String>[];

  void _requireMediaSwitch(String action) {
    if (!backend.allowMediaSwitch) {
      backend.unexpected.add('player:$action');
      throw StateError('Unscripted player action $action');
    }
    actions.add(action);
  }

  @override
  Future<void> pause() async => _requireMediaSwitch('pause');

  @override
  Future<void> open(mk.Playable playable, {bool play = true}) async {
    _requireMediaSwitch('open');
    openPlay.add(play);
    opened.add(playable);
  }

  @override
  Future<void> setSubtitleTrack(mk.SubtitleTrack track) async {
    _requireMediaSwitch('subtitle:${track.id}');
    subtitleIds.add(track.id);
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

// Only the additional renderer-error case uses multiple terminal instances.
// These classes record terminal I/O; no renderer decisions are copied here.
class _CancelTrace {
  _CancelTrace(this.instance);
  final int instance;
  final records = <Map<String, Object>>[];
  final zones = Map<Zone, int>.identity();
  final futures = Map<Future<void>, int>.identity();
  int nextSubscription = 0;

  int zoneId() => zones.putIfAbsent(Zone.current, () => zones.length);

  void record(String phase, String stream, int subscription,
      [Future<void>? future]) {
    records.add({
      'instance': instance,
      'phase': phase,
      'stream': stream,
      'subscription': subscription,
      'zone': zoneId(),
      if (future != null)
        'future': futures.putIfAbsent(future, () => futures.length),
    });
  }
}

class _TraceStream<T> extends Stream<T> {
  _TraceStream(this.delegate, this.label, this.trace);
  final Stream<T> delegate;
  final String label;
  final _CancelTrace trace;

  @override
  bool get isBroadcast => delegate.isBroadcast;

  @override
  StreamSubscription<T> listen(void Function(T)? onData,
      {Function? onError, void Function()? onDone, bool? cancelOnError}) {
    final id = trace.nextSubscription++;
    trace.record('listen-enter', label, id);
    // Pass ORIGINAL callbacks and cancellation option unchanged; register them
    // in the caller's zone. No broadcast conversion, transform or controller.
    final subscription = delegate.listen(onData, onError: onError,
        onDone: onDone, cancelOnError: cancelOnError);
    trace.record('listen-return', label, id);
    return _TraceSubscription<T>(subscription, label, id, trace);
  }
}

class _TraceSubscription<T> implements StreamSubscription<T> {
  _TraceSubscription(this.delegate, this.label, this.id, this.trace);
  final StreamSubscription<T> delegate;
  final String label;
  final int id;
  final _CancelTrace trace;

  @override
  Future<void> cancel() {
    trace.record('cancel-enter', label, id);
    final result = delegate.cancel(); // Original call count; synchronous throws escape.
    trace.record('cancel-return', label, id, result);
    return result; // EXACT Future identity; no async/then/whenComplete/ignore.
  }

  @override
  void onData(void Function(T)? handler) => delegate.onData(handler);
  @override
  void onError(Function? handler) => delegate.onError(handler);
  @override
  void onDone(void Function()? handler) => delegate.onDone(handler);
  @override
  void pause([Future<void>? resumeSignal]) => delegate.pause(resumeSignal);
  @override
  void resume() => delegate.resume();
  @override
  bool get isPaused => delegate.isPaused;
  @override
  Future<E> asFuture<E>([E? futureValue]) => delegate.asFuture<E>(futureValue);
}

// Cached terminal-only view; no production or controller substitution.
class _RecoveryProperties extends _Properties {
  _RecoveryProperties(super.configuration, super.unexpected, this.events, this.number) {
    allowMediaSwitch = true;
    // Real terminal metadata lets unchanged subtitle restoration finish without
    // fabricating positive VideoParams or advancing its five-second wait loop.
    state = state.copyWith(tracks: const mk.Tracks(
      subtitle: [mk.SubtitleTrack('1', 'Fixture subtitle', 'en')],
    ));
  }

  final List<String> events;
  final int number;
  late final cancelTrace = _CancelTrace(number);
  late final mk.PlayerStream _tracedStream = _tracePlayerStream(super.stream);

  @override
  mk.PlayerStream get stream => _tracedStream;

  mk.PlayerStream _tracePlayerStream(mk.PlayerStream original) {
    Stream<T> wrap<T>(String name, Stream<T> stream) =>
        _TraceStream<T>(stream, name, cancelTrace);
    return mk.PlayerStream(
      original.playlist,
      wrap('playing', original.playing),
      wrap('completed', original.completed),
      wrap('position', original.position),
      wrap('duration', original.duration),
      original.volume,
      original.rate,
      original.pitch,
      wrap('buffering', original.buffering),
      original.bufferingPercentage,
      original.buffer,
      original.playlistMode,
      original.audioParams,
      wrap('videoParams', original.videoParams),
      original.audioBitrate,
      original.audioDevice,
      original.audioDevices,
      wrap('track', original.track),
      original.tracks,
      original.width,
      original.height,
      original.subtitle,
      wrap('log', original.log),
      wrap('error', original.error),
    );
  }


  Completer<void>? disposeGate;
  Future<void>? disposal;
  final expectedBackend = PlayerTerminalBackend.debugOverride;
  final lifetimeIdentities = <bool>[];
  // Observational signals created in the same widget-test zone as producers.
  final disposalEntered = Completer<void>();
  final disposalCompleted = Completer<void>();

  void emitError(String error) => _streams.errorController.add(error);

  @override
  Future<void> dispose({bool synchronized = true}) => disposal ??= _disposeHeld();

  Future<void> _disposeHeld() async {
    lifetimeIdentities.add(identical(PlayerTerminalBackend.debugOverride, expectedBackend) &&
        RendererStartupEnvironment.debugIsAndroid == true);
    events.add('$number:dispose-start');
    disposalEntered.complete();
    final gate = disposeGate;
    if (gate != null) await gate.future;
    await super.dispose();
    lifetimeIdentities.add(identical(PlayerTerminalBackend.debugOverride, expectedBackend) &&
        RendererStartupEnvironment.debugIsAndroid == true);
    events.add('$number:dispose-done');
    disposalCompleted.complete();
  }
}

class _RecoveryPlayer extends _Player {
  _RecoveryPlayer(_RecoveryProperties super.backend);
  _RecoveryProperties get recovery => backend as _RecoveryProperties;
  final rates = <double>[];
  final volumes = <double>[];
  final openCompleted = Completer<void>();
  final rateCompleted = Completer<void>();
  final volumeCompleted = Completer<void>();

  @override
  Future<void> pause() async {
    recovery.events.add('${recovery.number}:pause');
    await super.pause();
  }

  @override
  Future<void> open(mk.Playable playable, {bool play = true}) async {
    recovery.events.add('${recovery.number}:open');
    await super.open(playable, play: play);
    recovery.events.add('${recovery.number}:open-done');
    if (!openCompleted.isCompleted) openCompleted.complete();
  }

  @override
  Future<void> setRate(double rate) async {
    recovery.events.add('${recovery.number}:rate');
    rates.add(rate);
    if (!rateCompleted.isCompleted) rateCompleted.complete();
  }

  @override
  Future<void> setVolume(double volume) async {
    recovery.events.add('${recovery.number}:volume');
    volumes.add(volume);
    if (!volumeCompleted.isCompleted) volumeCompleted.complete();
  }
}

class _RecoveryVideo extends _TexturelessVideo {
  _RecoveryVideo(super.player, super.unexpected);
  bool closed = false;

  @override
  void close() {
    if (closed) return;
    closed = true;
    super.close();
  }
}

class _RecoveryTerminal extends _Terminal {
  final events = <String>[];
  final instances = <_RecoveryProperties>[];
  final players = <_RecoveryPlayer>[];
  final videos = <_RecoveryVideo>[];
  final configs = <mkv.VideoControllerConfiguration>[];
  final overrideIdentities = <bool>[];
  final readyCallbacks = <bool>[];
  final logLevels = <mk.MPVLogLevel>[];
  final videoPlayerIdentities = <bool>[];
  final leaseAtConstruction = <bool>[];
  final replacementCreated = Completer<_RecoveryPlayer>();

  @override
  void ensureInitialized() {
    overrideIdentities.add(identical(PlayerTerminalBackend.debugOverride, this));
    construction.add('bootstrap');
    events.add('bootstrap');
  }

  @override
  mk.Player createPlayer({required mk.PlayerConfiguration configuration}) {
    overrideIdentities.add(identical(PlayerTerminalBackend.debugOverride, this));
    readyCallbacks.add(configuration.ready != null);
    logLevels.add(configuration.logLevel);
    construction.add('player');
    final number = instances.length;
    leaseAtConstruction.add(VideoOutputLease.isHeld);
    events.add('$number:player');
    final backend = _RecoveryProperties(configuration, unexpected, events, number);
    instances.add(backend);
    properties = backend;
    final created = _RecoveryPlayer(backend);
    players.add(created);
    if (number == 1) replacementCreated.complete(created);
    return player = created;
  }

  @override
  mkv.VideoController createVideoController(mk.Player player, {
    required mkv.VideoControllerConfiguration configuration,
  }) {
    overrideIdentities.add(identical(PlayerTerminalBackend.debugOverride, this));
    videoPlayerIdentities.add(identical(player, this.player));
    construction.add('video');
    configs.add(configuration);
    leaseAtConstruction.add(VideoOutputLease.isHeld);
    events.add('${instances.length - 1}:video');
    final created = _RecoveryVideo(player, unexpected);
    videos.add(created);
    return video = created;
  }
}


// No real HttpClient or resource is created. Construction is permitted and
// recorded separately; requests and every unsupported API remain strict STOPs.
class _RejectRendererHttp extends HttpOverrides {
  final constructions = <_RejectRendererHttpClient>[];
  final requests = <String>[];
  final unsupported = <String>[];

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = _RejectRendererHttpClient(this);
    constructions.add(client);
    return client;
  }
}

class _RejectRendererHttpClient implements HttpClient {
  _RejectRendererHttpClient(this.recorder);

  // Retained service clients keep this recorder and rejection behavior even
  // after HttpOverrides.runWithHttpOverrides restores the prior zone override.
  final _RejectRendererHttp recorder;
  bool closed = false;

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) {
    recorder.requests.add('$method $url\n${StackTrace.current}');
    throw StateError('Unexpected renderer fixture HTTP request: $method $url');
  }

  @override
  void close({bool force = false}) {
    closed = true; // Idempotent bookkeeping; no resources or delegated close.
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    recorder.unsupported.add(
        '${invocation.memberName} positional=${invocation.positionalArguments} '
        'named=${invocation.namedArguments}\n${StackTrace.current}');
    throw StateError('Unsupported renderer fixture HttpClient API '
        '${invocation.memberName}');
  }
}

// Register the ORIGINAL engine callbacks in a print-only recording zone.
// No callback/Future replacement and no custom error or microtask handler.
class _RendererLiveBinding extends LiveTestWidgetsFlutterBinding {
  _RendererLiveBinding(this.diagnostics);
  final List<String> diagnostics;

  @override
  void ensureFrameCallbacksRegistered() {
    runZoned(() => super.ensureFrameCallbacksRegistered(),
        zoneSpecification: ZoneSpecification(print: (self, parent, zone, line) {
      if (line.startsWith('DEBRIFY_PLAYER_DECODER ')) diagnostics.add(line);
      parent.print(zone, line);
    }));
  }
}

void main() {
  final diagnostics = <String>[];
  final binding = _RendererLiveBinding(diagnostics)
    ..framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.onlyPumps;
  const window = MethodChannel('window_manager');
  const brightness = MethodChannel('github.com/aaassseee/screen_brightness');
  const wake =
      'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle';

  final httpBoundary = _RejectRendererHttp();
  Directory? ownedTempRoot;
  String? ownedResolvedPath;
  String? ownedParentPath;
  Object? originalFailure;
  StackTrace? originalStack;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  // Genuine filesystem/database acquisition precedes the widget-test event
  // phase. No copied package graph, fake database completion or OS third seam.
  setUp(() async {
    httpBoundary.requests.clear();
    httpBoundary.unsupported.clear();
    httpBoundary.constructions.clear();
    final previousHttp = HttpOverrides.current;
    try {
      await HttpOverrides.runWithHttpOverrides(() async {
        SharedPreferences.setMockInitialValues({});
        ProfileRuntime.debugReset();
        ProfileRuntime.initializeLegacy();
        SecretVault.debugReset(deviceIdOverride: 'renderer-host-origin-draft');
        StorageService.resetProfileCaches();
        final parent = Directory('.dart_tool').absolute;
        ownedParentPath = await parent.resolveSymbolicLinks();
        final root = await parent.createTemp('renderer-');
        ownedTempRoot = root;
        ownedResolvedPath = await root.resolveSymbolicLinks();
        AppStorage.debugOverride(documents: root, support: root, cache: root);
        await DebrifyTvDatabase.instance.debugResetScopeState();
        await DebrifyTvDatabase.instance.database;
        await StorageService.setAndroidVideoRendererMode(
          AndroidVideoRendererMode.directSurface,
        ); // Actual API also writes its migration marker.
        expect(httpBoundary.requests, isEmpty);
        expect(httpBoundary.unsupported, isEmpty);
      }, httpBoundary);
    } catch (error, stack) {
      originalFailure ??= error;
      originalStack ??= stack;
      rethrow;
    } finally {
      // Zone-scoped override unwinds to the exact previously active override;
      // no global setter guesses a previous zone override's global identity.
      expect(HttpOverrides.current, same(previousHttp));
    }
  });

  tearDown(() async {
    final previousHttp = HttpOverrides.current;
    final cleanupErrors = <(Object, StackTrace)>[];
    void recordCleanup(Object error, StackTrace stack) {
      cleanupErrors.add((error, stack));
      debugPrintSynchronously('RENDERER_DRAFT_RESOURCE_CLEANUP $error\n$stack');
    }
    try {
      await HttpOverrides.runWithHttpOverrides(() async {
        var databaseClosed = false;
        try {
          await DebrifyTvDatabase.instance.debugResetScopeState();
          databaseClosed = true;
        } catch (error, stack) {
          recordCleanup(error, stack);
        }
        try {
          final root = ownedTempRoot;
          if (root != null) {
            if (!databaseClosed) {
              throw StateError('Owned temp directory retained: DB close failed');
            }
            // Only the captured createTemp result, still a real directory and
            // direct child of the captured canonical evidence parent, may go.
            final kind = await FileSystemEntity.type(root.path, followLinks: false);
            final resolved = await root.resolveSymbolicLinks();
            final parent = await root.parent.resolveSymbolicLinks();
            if (kind != FileSystemEntityType.directory ||
                resolved != ownedResolvedPath || parent != ownedParentPath ||
                Directory(resolved).parent.path != ownedParentPath ||
                !root.uri.pathSegments.where((s) => s.isNotEmpty).last.startsWith('renderer-')) {
              throw StateError('Owned temp directory identity changed; retained');
            }
            await root.delete(recursive: true);
            ownedTempRoot = null;
          }
        } catch (error, stack) {
          recordCleanup(error, stack);
        }
        try {
          expect(httpBoundary.requests, isEmpty,
              reason: 'HTTP requests across setup, main and ALL cleanup');
          expect(httpBoundary.unsupported, isEmpty,
              reason: 'Unsupported HTTP APIs across setup, main and ALL cleanup');
        } catch (error, stack) {
          recordCleanup(error, stack);
        }
      }, httpBoundary);
    } finally {
      binding.defaultBinaryMessenger.setMockMethodCallHandler(window, null);
      binding.defaultBinaryMessenger.setMockMethodCallHandler(brightness, null);
      binding.defaultBinaryMessenger.setMockMessageHandler(wake, null);
      StorageService.resetProfileCaches();
      AppStorage.debugReset();
      ProfileRuntime.debugReset();
      SecretVault.debugReset();
      expect(HttpOverrides.current, same(previousHttp));
    }
    if (cleanupErrors.isNotEmpty) {
      Error.throwWithStackTrace(originalFailure ?? cleanupErrors.first.$1,
          originalStack ?? cleanupErrors.first.$2);
    }
  });

  testWidgets('public renderer error awaits real old disposal before recreation',
      (tester) async {
    final previousHttp = HttpOverrides.current;
    final previousBackend = PlayerTerminalBackend.debugOverride;
    final previousRenderer = RendererStartupEnvironment.debugIsAndroid;
    final terminal = _RecoveryTerminal(); // ALL signals use this test zone.
    diagnostics.clear();
    final failures = <(Object, StackTrace)>[];
    final phaseWatch = Stopwatch();
    var requests = 0;
    var mountAttempted = false;
    var unmounted = false;

    void recordFailure(String phase, Object error, StackTrace stack) {
      failures.add((error, stack));
      originalFailure ??= error;
      originalStack ??= stack;
      debugPrintSynchronously('RENDERER_DRAFT_$phase $error\n$stack');
      debugPrintSynchronously('RENDERER_DRAFT_EVENTS ${terminal.events}');
      debugPrintSynchronously('RENDERER_DRAFT_UNEXPECTED ${terminal.unexpected}');
      for (final instance in terminal.instances) {
        // Snapshot PRIMARY before finally; later cleanup snapshots are labelled
        // separately and cannot be mistaken for fallback-helper progress.
        final traceSnapshot = List<Map<String, Object>>.of(instance.cancelTrace.records);
        debugPrintSynchronously('RENDERER_CANCEL_TRACE phase=$phase '
            'instance=${instance.number} boundary=${traceSnapshot.length} '
            'records=$traceSnapshot');
      }
    }

    // Synchronous observation only. Missing completion fails NOW; five seconds
    // is a maximum phase budget, never a timeout that waits for fake producers.
    void requirePhase(String phase, bool observed) {
      expect(observed, isTrue,
          reason: '$phase incomplete; events=${terminal.events}');
      expect(phaseWatch.elapsed <= const Duration(seconds: 5), isTrue,
          reason: '$phase exceeded retained five-second ceiling');
    }

    binding.defaultBinaryMessenger.setMockMethodCallHandler(window, (call) async {
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
    binding.defaultBinaryMessenger.setMockMethodCallHandler(brightness,
        (call) async {
      if (call.method == 'resetApplicationScreenBrightness') return null;
      terminal.unexpected.add('brightness:${call.method}');
      throw StateError('Unexpected brightness call ${call.method}');
    });
    binding.defaultBinaryMessenger.setMockMessageHandler(wake,
        (_) async => const StandardMessageCodec().encodeMessage([null]));
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    try {
      await HttpOverrides.runWithHttpOverrides(() async {
        await runZoned(() async {
      try {
        // Observe prerequisites; do not mutate cached TV state or reset lease.
        expect(PlatformUtil.isAndroidTvCached, isFalse);
        expect(VideoOutputLease.isHeld, isFalse);
        PlayerTerminalBackend.debugOverride = terminal;
        RendererStartupEnvironment.debugIsAndroid = true;
        phaseWatch..reset()..start();
        mountAttempted = true;
        await tester.pumpWidget(MaterialApp(
          builder: (_, child) => AppThemeScope(
            theme: AppThemes.byId('spotlight'), child: child!),
          home: VideoPlayerScreen(
            videoUrl: '',
            title: 'Renderer origin fixture',
            disableAutoResume: true,
            requestNextChannel: () async {
              requests++;
              return {
                'url': 'https://decoder.invalid/recovery.mkv',
                'title': 'Recovery fixture',
              };
            },
          ),
        ));
        // One declared setup boundary replaces the retained conditional loop.
        // Failure means setup admission missing, not permission to pump again.
        await tester.pump();
        requirePhase('initial construction', terminal.instances.length == 1 &&
            terminal.players.length == 1 && terminal.videos.length == 1);
        expect(terminal.construction, ['bootstrap', 'player', 'video']);
        final first = terminal.instances.single;
        first.configuration.ready!(); // Actual public terminal-ready callback.
        await tester.pump();
        expect(find.byType(Controls), findsOneWidget);
        expect(terminal.configs.single.vo, 'mediacodec_embed');
        expect(terminal.configs.single.hwdec, 'mediacodec');
        first.state = first.state.copyWith(rate: 1.25, volume: 37);
        final controls = tester.widget<Controls>(find.byType(Controls));
        expect(controls.onNextChannel, isNotNull);
        controls.onNextChannel!(); // No State access or private fallback call.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        expect(requests, 1);
        expect(terminal.players.single.opened, hasLength(1));
        expect(terminal.players.single.openPlay, [true]);
        expect(terminal.players.single.subtitleIds, ['no']);
        requirePhase('initial media open', terminal.players.single.openCompleted.isCompleted);
        // onNextChannel supplies no public transition Future. The retained 50ms
        // subtitle boundary plus subsequent accepted fallback is the admission
        // observation; Controls alone does not prove transition completion.
        expect(first.reads, isEmpty); // No VideoParams or property-probe entry.
        expect(diagnostics, isEmpty);

        final gate = Completer<void>(); // Captured widget zone, never root.
        first.disposeGate = gate;
        phaseWatch..reset()..start();
        first.emitError('Video output initialization failed');
        await tester.pump(); // EXISTING event barrier 1: ZERO duration.
        requirePhase('old disposal entered', first.disposalEntered.isCompleted);
        expect(first.disposal, isNotNull);
        expect(first.disposalCompleted.isCompleted, isFalse);
        expect(first.closed, isFalse);
        expect(identical(first.dispose(), first.disposal), isTrue);
        expect(gate.isCompleted, isFalse);
        expect(terminal.players, hasLength(1));
        expect(terminal.videos, hasLength(1));
        expect(terminal.instances, hasLength(1));
        expect(terminal.replacementCreated.isCompleted, isFalse);
        expect(VideoOutputLease.isHeld, isTrue);
        expect(await StorageService.getAndroidVideoRendererMode(),
            AndroidVideoRendererMode.directSurface);
        expect(terminal.events, containsAllInOrder([
          'bootstrap', '0:player', '0:video', '0:pause', '0:open',
          '0:open-done', '0:pause', '0:dispose-start',
        ]));
        expect(terminal.events.where((e) => e == '0:dispose-start'), hasLength(1));
        expect(diagnostics, hasLength(1));
        expect(diagnostics.single,
            contains('phase=fallback status=renderer_startup_failed'));
        expect(diagnostics.single, contains('reason=renderer_error'));

        phaseWatch..reset()..start();
        gate.complete();
        await tester.pump(); // EXISTING event barrier 2: ZERO duration.
        requirePhase('real old disposal complete', first.disposalCompleted.isCompleted);
        // completion is recorded AFTER awaiting PlatformPlayer.dispose's 24
        // controller closures and release callbacks, not at closed=true entry.
        await first.disposal!; // Never join an unobserved producer.
        requirePhase('replacement created', terminal.replacementCreated.isCompleted);
        expect(terminal.instances, hasLength(2));
        final replacement = terminal.players[1];
        requirePhase('replacement opened', replacement.openCompleted.isCompleted);
        requirePhase('replacement rate', replacement.rateCompleted.isCompleted);
        requirePhase('replacement volume', replacement.volumeCompleted.isCompleted);
        expect(terminal.events, containsAllInOrder([
          '0:dispose-done', '1:player', '1:video', '1:open', '1:open-done',
          '1:rate', '1:volume',
        ]));
        expect(first.closed, isTrue);
        expect(VideoOutputLease.isHeld, isTrue);
        expect(await StorageService.getAndroidVideoRendererMode(),
            AndroidVideoRendererMode.automatic);
        expect(terminal.configs.last.vo, isNull);
        expect(terminal.configs.last.hwdec, isNull);
        expect(replacement.opened, hasLength(1));
        expect((replacement.opened.single as mk.Media).uri,
            (terminal.players.first.opened.single as mk.Media).uri);
        expect(replacement.openPlay, [true]);
        expect(replacement.rates, [1.25]);
        expect(replacement.volumes, [37]);
        expect(find.text('Direct Surface was unavailable. Using Automatic renderer.'),
            findsOneWidget);
        expect(diagnostics, hasLength(1));
        expect(terminal.overrideIdentities, everyElement(isTrue));
        expect(terminal.readyCallbacks, [true, true]);
        expect(terminal.logLevels, [mk.MPVLogLevel.error, mk.MPVLogLevel.error]);
        expect(terminal.videoPlayerIdentities, [true, true]);
        expect(terminal.players, hasLength(2));
        expect(terminal.videos, hasLength(2));
        expect(terminal.leaseAtConstruction, [true, true, true, true]);
        expect(first.lifetimeIdentities, [true, true]);
        expect(diagnostics.where((line) => line.contains('phase=fallback status=failed')),
            isEmpty);
        expect(terminal.unexpected, isEmpty);
        expect(httpBoundary.requests, isEmpty, reason: 'HTTP requests in main');
        expect(httpBoundary.unsupported, isEmpty, reason: 'Unsupported HTTP APIs in main');
      } catch (error, stack) {
        recordFailure('PRIMARY', error, stack); // Before any cleanup attempt.
      } finally {
        // No runAsync here: live binding keeps real subscription continuations.
        // Snapshot+single pass; late instance growth FAILS, never chase loops.
        final cleanupInstances = List<_RecoveryProperties>.of(terminal.instances);
        final cleanupInitiated = Set<_RecoveryProperties>.identity();
        try {
          if (mountAttempted && !unmounted) {
            unmounted = true;
            await tester.pumpWidget(const SizedBox.shrink());
          }
          for (final instance in cleanupInstances) {
            final gate = instance.disposeGate;
            if (gate != null && !gate.isCompleted) gate.complete();
          }
          for (final instance in cleanupInstances) {
            if (instance.disposal == null) {
              cleanupInitiated.add(instance);
              terminal.events.add('${instance.number}:cleanup-initiated-disposal');
              // Recorded separately: this is resource cleanup, not evidence
              // that the real host reached its success disposal path.
              unawaited(instance.dispose());
            }
          }
          phaseWatch..reset()..start();
          await tester.pump(const Duration(milliseconds: 250)); // Retained cleanup budget.
          expect(terminal.instances, orderedEquals(cleanupInstances),
              reason: 'Late-created instances remain a cleanup blocker; no chase');
          for (final instance in cleanupInstances) {
            requirePhase('cleanup ${instance.number} complete',
                instance.disposalCompleted.isCompleted);
            expect(instance.disposal, isNotNull);
            await instance.disposal!;
            expect(instance.lifetimeIdentities, [true, true]);
          }
          for (final video in terminal.videos) {
            video.close();
          }
          expect(VideoOutputLease.isHeld, isFalse); // No forced lease release.
          expect(terminal.unexpected, isEmpty);
          expect(PlayerTerminalBackend.debugOverride, same(terminal));
          expect(RendererStartupEnvironment.debugIsAndroid, isTrue);
        } catch (error, stack) {
          recordFailure('CLEANUP', error, stack); // Original error stays first.
          // Honest failure evidence includes any unjoined operation/late output.
          // No claim of clean process or safe suite continuation after this.
        } finally {
          // Assess attribution independently even if drain/lease checks failed.
          // Safety cleanup must NEVER manufacture a successful host teardown.
          try {
            expect(cleanupInitiated, isEmpty,
                reason: 'Fixture initiated disposal for instances '
                    '${cleanupInitiated.map((p) => p.number).toList()}');
          } catch (error, stack) {
            recordFailure('CLEANUP_ATTRIBUTION', error, stack);
          }
          try {
            expect(httpBoundary.requests, isEmpty,
                reason: 'HTTP requests across main and terminal cleanup');
            expect(httpBoundary.unsupported, isEmpty,
                reason: 'Unsupported HTTP APIs across main and terminal cleanup');
          } catch (error, stack) {
            recordFailure('CLEANUP_HTTP', error, stack);
          }
          try {
            RendererStartupEnvironment.debugIsAndroid = previousRenderer;
          } finally {
            PlayerTerminalBackend.debugOverride = previousBackend;
          }
        }
      }
      if (failures.isNotEmpty) {
        // Each cleanup error was separately surfaced above; preserve the first
        // error and original stack rather than masking it with a finally error.
        Error.throwWithStackTrace(failures.first.$1, failures.first.$2);
      }
    });
      }, httpBoundary);
    } finally {
      expect(HttpOverrides.current, same(previousHttp));
    }
  });
}
