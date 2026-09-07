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
import 'package:debrify/screens/video_player/widgets/pikpak_retry_overlay.dart';

// IGNORED, UNRUN draft only. No tracked test or production edits.
// Existing real host + external terminal transport; no retry algorithm copy.
// Four finite cases, not six-writer/stale-UI/exhaustion/native coverage.
enum _Scenario { directDuration, initialOpenError, disposedHeldOpen, disposedStabilization }

class _Streams extends mk.PlatformPlayer {
  _Streams(mk.PlayerConfiguration config, this.unexpected, this.scenario)
    : super(configuration: config);
  final List<String> unexpected;
  final events = <String>[];
  final seeks = <(String, Duration)>[];
  final disposalEntered = Completer<void>();
  Future<void>? disposal;
  bool closed = false;
  bool readySent = false;
  final _Scenario scenario;
  final openEntered = Completer<void>();
  final releaseOpen = Completer<void>();
  final openFinished = Completer<void>();
  final expectedOpenError = StateError('retry fixture initial open failure');
  final mediaHeaders = <Map<String, String>?>[];
  final stateReads = <String>[];
  int opens = 0;
  Object? openError;
  StackTrace? openErrorStack;

  void publishDuration(Duration value) {
    events.add('duration-stream:${value.inMilliseconds}');
    state = state.copyWith(duration: value);
    durationController.add(value);
  }

  Future<void> openMedia(mk.Playable playable, {required bool play}) async {
    if (playable is! mk.Media) throw StateError('Expected one media');
    if (closed || ++opens != 1) {
      unexpected.add('unexpected-open:$closed:$opens');
      throw StateError('Open outside this finite fixture');
    }
    mediaHeaders.add(playable.httpHeaders);
    events.add('open-enter:${playable.uri}:play=$play');
    openEntered.complete();
    try {
      if (scenario == _Scenario.disposedHeldOpen) {
        await releaseOpen.future;
        // Model completion of an already-entered terminal call after disposal.
        // No second open/state/stream write; this is not a host cancellation hook.
        if (closed) {
          events.add('held-open-return-after-dispose');
          return;
        }
      }
      state = state.copyWith(
        playlist: mk.Playlist([playable]), playing: false,
        completed: false, position: Duration.zero,
        duration: const Duration(seconds: 60), width: 1280, height: 720,
        tracks: const mk.Tracks(),
      );
      if (!readySent) { readySent = true; configuration.ready!(); }
      playlistController.add(state.playlist);
      widthController.add(state.width);
      heightController.add(state.height);
      tracksController.add(state.tracks);
      playingController.add(false);
      // Deliberately NO duration-stream event: monitor must read direct state.
      if (scenario == _Scenario.initialOpenError) throw expectedOpenError;
      events.add('open-return');
    } catch (error, stack) {
      openError = error; openErrorStack = stack;
      rethrow; // Actual host catches the initial terminal error.
    } finally {
      openFinished.complete();
    }
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
  mk.PlayerState get state {
    backend.stateReads.add('state-read:closed=${backend.closed}');
    return backend.state;
  }
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
  _Terminal(this.scenario);
  final _Scenario scenario;
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
    properties = _Streams(configuration, unexpected, scenario);
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

class _RejectHttp extends http.BaseClient {
  _RejectHttp(this.unexpected);
  final List<String> unexpected;
  int sent = 0;
  int closes = 0;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    sent++;
    unexpected.add('HTTP:${request.method}:${request.url}');
    throw StateError('No HTTP endpoint admitted in this retry fixture');
  }
  @override
  void close() { closes++; }
}

class _TimerObservation {
  _TimerObservation(this.timer, this.delay, this.created, this.stack, this.periodic);
  final Timer timer;
  final Duration delay;
  final DateTime created;
  final String stack;
  final bool periodic;
  bool get retry => stack.contains('_waitForVideoMetadata');
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final previousFactory = databaseFactoryOrNull;
  const window = MethodChannel('window_manager');
  const brightness = MethodChannel('github.com/aaassseee/screen_brightness');
  const wake = 'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle';
  const mediaUrl = 'https://retry-fixture.mypikpak.com/Retry.mp4';
  const headers = {'X-Retry-Fixture': 'synthetic'};
  final sentinelUnexpected = <String>[];
  final sentinel = _RejectHttp(sentinelUnexpected);
  int sentinelConstructions = 0;
  bool contaminated = false;

  setUpAll(() {
    http.runWithClient(() {
      expect(MdblistService.instance, same(MdblistService.instance));
    }, () { sentinelConstructions++; return sentinel; });
    expect(sentinelConstructions, 1);
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });
  tearDownAll(() {
    expect(sentinelUnexpected, isEmpty);
    expect(sentinel.sent, 0);
    expect(sentinel.closes, 0); // Borrowed isolate client is never ours to close.
    if (!contaminated) databaseFactoryOrNull = previousFactory;
  });

  for (final scenario in _Scenario.values) {
    testWidgets(switch (scenario) {
      _Scenario.directDuration => 'actual retry direct duration stabilizes with both playing sources false',
      _Scenario.initialOpenError => 'actual retry swallows initial open error then accepts direct duration',
      _Scenario.disposedHeldOpen => 'public unmount during held initial open exits outer token guard',
      _Scenario.disposedStabilization => 'public unmount during stabilization settles actual 800ms wait',
    }, (tester) async {
      if (contaminated) throw StateError('Prior fixture unsettled; no next setup');
      Object? primary;
      StackTrace? primaryStack;
      Object? cleanupFailure;
      StackTrace? cleanupStack;
      var phase = 'setup';
      final terminal = _Terminal(scenario);
      final previousTerminal = PlayerTerminalBackend.debugOverride;
      final DebugPrintCallback previousPrint = debugPrint;
      final prints = <String>[];
      final debugs = <String>[];
      final timers = <_TimerObservation>[];
      final httpClients = <_RejectHttp>[];
      Directory? root;
      var mounted = false;
      var unmounted = false;
      var cleanupSafe = false;
      var globalsInstalled = false;
      DateTime? mountClock;
      _Streams? backend;

      bool logged(String exact) => prints.contains(exact);
      int debugCount(String prefix) => debugs.where((s) => s.startsWith(prefix)).length;
      bool addonTail() => debugCount('SubAuto: restore done') == 1 &&
          debugCount('VideoPlayer: Fetching addon subtitles (IMDB: tt1234567)') == 1 &&
          debugCount('VideoPlayer: Fetched and cached 0 addon subtitles') == 1 &&
          debugs.where((s) => s == 'SubAuto: SKIP — zero addon subtitles fetched').length == 1;
      Future<void> reach(bool Function() predicate) async {
        // Exactly80 zero-fake-time frame/event turns per phase, no sleep.
        // Real SQLite/file Futures get an event turn; this is not a Future join.
        for (var i = 0; i < 80 && !predicate(); i++) {
          await tester.runAsync(() => Future<void>(() {}));
          await tester.pump();
        }
        expect(predicate(), isTrue, reason: 'Unfinished producer: $phase');
      }
      Future<void> unmount() async {
        if (!mounted || unmounted) return;
        await tester.pumpWidget(const SizedBox.shrink());
        unmounted = true;
        await tester.pump(const Duration(milliseconds: 250));
        expect(find.byType(VideoPlayerScreen), findsNothing);
        final player = terminal.properties;
        if (player != null) {
          // Host must initiate disposal, not the fixture safety closer.
          expect(player.disposal, isNotNull, reason: 'Host did not initiate disposal');
          await tester.runAsync(() => player.disposal!);
          expect(player.closed, isTrue);
        }
      }

      await runZoned(() async {
        await http.runWithClient(() async {
          try {
            debugPrint = (String? message, {int? wrapWidth}) {
              if (message != null) debugs.add(message);
              debugPrintSynchronously(message, wrapWidth: wrapWidth);
            };
            await tester.runAsync(() async {
            SharedPreferences.setMockInitialValues({});
            ProfileRuntime.debugReset();
            ProfileRuntime.initializeLegacy();
            SecretVault.debugReset(deviceIdOverride: 'retry-origin-synthetic');
            StorageService.resetProfileCaches();
            root = await Directory('.dart_tool').absolute.createTemp('retry-origin-');
            AppStorage.debugOverride(documents: root, support: root, cache: root);
            await DebrifyTvDatabase.instance.debugResetScopeState();
            IptvMediaStore.debugResetMigration();
            await DebrifyTvDatabase.instance.database;
            });
            binding.defaultBinaryMessenger.setMockMethodCallHandler(window, (call) async {
              switch (call.method) {
                case 'setFullScreen': case 'setBounds': return null;
                case 'getBounds': return {'x': 0.0, 'y': 0.0, 'width': 1280.0, 'height': 720.0};
                case 'isFullScreen': return false;
                default:
                  terminal.unexpected.add('window:${call.method}');
                  throw StateError('Unscripted window method ${call.method}');
              }
            });
            binding.defaultBinaryMessenger.setMockMessageHandler(wake,
                (_) async => const StandardMessageCodec().encodeMessage([null]));
            binding.defaultBinaryMessenger.setMockMethodCallHandler(brightness, (call) async {
              if (call.method == 'resetApplicationScreenBrightness') return null;
              terminal.unexpected.add('brightness:${call.method}');
              throw StateError('Unexpected brightness method');
            });
            PlayerTerminalBackend.debugOverride = terminal;
            globalsInstalled = true;
            phase = 'public prefs and empty-addon registry';
            await tester.runAsync(() async {
              await PlayerPrefs.setSkipSegmentsEnabled(false);
              await PlayerPrefs.setSubtitleAutoSyncEnabled(false);
              await TrackingPrefs.setTrackingScrobbleTargets({});
              await TrackingPrefs.setWatchProgressSource(WatchProgressSource.local);
              await TrackingPrefs.setHomeTickSources({});
              await StremioService.instance.clearAllAddons();
              expect(await StremioService.instance.getEnabledAddons(), isEmpty);
              expect(await StremioSubtitleService.instance.getSubtitleAddons(), isEmpty);
              expect(await PlayerPrefs.getSkipSegmentsEnabled(), isFalse);
              expect(await PlayerPrefs.getSubtitleAutoSyncEnabled(), isFalse);
              final policy = await TrackingSourcePolicy.load();
              expect(policy.scrobbleTargets, {TrackingSource.local});
              expect(policy.progressSource, WatchProgressSource.local);
            });
            tester.view.physicalSize = const Size(1280, 720);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            phase = 'real no-playlist URL classification and initial open';
            mountClock = binding.clock.now();
            mounted = true;
            await tester.pumpWidget(MaterialApp(
              builder: (_, child) => AppThemeScope(theme: AppThemes.byId('spotlight'), child: child!),
              home: const VideoPlayerScreen(
                videoUrl: mediaUrl, title: 'Retry fixture', httpHeaders: headers,
                contentType: 'movie', contentImdbId: 'tt1234567',
                contentTitle: 'Retry fixture', disableAutoResume: true,
                traktScrobble: false, simklScrobble: false, mdblistScrobble: false,
              ),
            ));
            await reach(() => terminal.properties?.openEntered.isCompleted == true);
            backend = terminal.properties!;
            expect(terminal.construction, ['bootstrap', 'player', 'video']);
            expect(backend!.opens, 1);
            expect(const MapEquality<String, String>().equals(backend!.mediaHeaders.single, headers), isTrue);
            expect(prints.where((s) => s.startsWith('PikPak: _playPikPakVideoWithRetry called') &&
                s.contains('isPikPak: true')), hasLength(1));
            if (scenario == _Scenario.disposedHeldOpen) {
              expect(backend!.openFinished.isCompleted, isFalse);
              expect(prints.where((s) => s.startsWith('PikPak: Monitoring attempt')), isEmpty);
              phase = 'public unmount before releasing held terminal open';
              await unmount();
              expect(backend!.closed, isTrue);
              backend!.releaseOpen.complete();
              await tester.runAsync(() => backend!.openFinished.future);
              await tester.pump();
              expect(logged('PikPak: Retry loop cancelled before attempt 1 (navigation occurred)'), isTrue);
              expect(backend!.events, contains('held-open-return-after-dispose'));
              expect(prints.where((s) => s.startsWith('PikPak: Monitoring attempt')), isEmpty);
              expect(timers.where((t) => t.retry), isEmpty);
              expect(debugCount('SubAuto: _restoreTrackPreferences entered'), 0);
            } else {
              phase = 'actual direct-only metadata read and armed stabilization';
              await reach(() => logged('PikPak: Duration detected, waiting for playback to stabilize...'));
              expect(prints.where((s) => s.startsWith('PikPak: Video duration available') &&
                  s.contains('stream: 0:00:00.000000, direct: 0:01:00.000000')), hasLength(1));
              final stabilization = timers.where((t) => t.retry &&
                  t.delay == const Duration(milliseconds: 800)).single;
              expect(stabilization.timer.isActive, isTrue);
              expect(timers.where((t) => t.retry && t.delay == const Duration(milliseconds: 500)), isEmpty);
              expect(backend!.state.playing, isFalse);
              expect(backend!.state.duration, const Duration(seconds: 60));
              expect(backend!.events.where((s) => s.startsWith('duration-stream:')), isEmpty);
              expect(backend!.openFinished.isCompleted, isTrue);
              if (scenario == _Scenario.initialOpenError) {
                expect(backend!.openError, same(backend!.expectedOpenError));
                expect(backend!.openErrorStack, isNotNull);
                expect(backend!.openErrorStack.toString(), isNotEmpty);
                expect(prints.where((s) => s.startsWith('PikPak: Initial player.open() failed with error:') &&
                    s.contains('retry fixture initial open failure')), hasLength(1));
              } else {
                expect(backend!.openError, isNull);
              }
              if (scenario == _Scenario.disposedStabilization) {
                phase = 'public unmount while original stabilization is pending';
                expect(binding.clock.now(), stabilization.created);
                await unmount(); // Actual250ms; no forced timer cancellation.
                expect(stabilization.timer.isActive, isTrue);
                expect(binding.clock.now().difference(stabilization.created),
                    const Duration(milliseconds: 250));
                await tester.pump(const Duration(milliseconds: 550));
                expect(stabilization.timer.isActive, isFalse);
                expect(logged('PikPak: Widget disposed during stabilization delay'), isTrue);
                expect(logged('PikPak: Widget disposed before retry'), isTrue);
                expect(logged('PikPak: Retry mechanism fully deactivated, playback ready'), isFalse);
                expect(debugCount('SubAuto: _restoreTrackPreferences entered'), 0);
              } else {
                phase = 'same800ms monitor success; stream duration still zero';
                await tester.pump(const Duration(milliseconds: 800));
                expect(stabilization.timer.isActive, isFalse);
                expect(logged('PikPak: Duration available (0:01:00.000000), playback will start shortly'), isTrue);
                expect(logged('PikPak: Retry mechanism fully deactivated, playback ready'), isTrue);
                expect(find.byType(Controls), findsOneWidget);
                final controls = tester.widget<Controls>(find.byType(Controls));
                expect(controls.clock.value.duration, Duration.zero);
                expect(controls.isPlaying, isFalse);
                expect(backend!.state.playing, isFalse);
                expect(find.byType(PikPakRetryOverlay), findsNothing);
                // Retry return is NOT startup continuation completion.
                final readyWait = timers.where((t) => t.stack.contains('_waitForVideoReady') &&
                    t.delay == const Duration(milliseconds: 100)).single;
                expect(readyWait.timer.isActive, isTrue);
                phase = 'external duration stream releases host-duration-only startup wait';
                backend!.publishDuration(const Duration(seconds: 60));
                await tester.pump(const Duration(milliseconds: 100));
                expect(readyWait.timer.isActive, isFalse);
                expect(tester.widget<Controls>(find.byType(Controls)).clock.value.duration,
                    const Duration(seconds: 60));
                phase = 'actual resume tail reaches subtitle restore';
                await reach(() => debugCount('SubAuto: _restoreTrackPreferences entered') == 1);
                // Empty embedded tracks invoke real50x100ms wait. No clock seam.
                phase = 'explicit existing empty-track timer frontier';
                await tester.pump(const Duration(seconds: 5));
                phase = 'actual restore and empty-addon producer completion markers';
                await reach(addonTail);
                expect(backend!.seeks, isEmpty); // No stored resume or launch percentage.
                expect(backend!.opens, 1);
                expect(binding.clock.now().difference(mountClock!),
                    const Duration(milliseconds: 5900));
                // Cleanup-only external unload AFTER behavior assertions/tails.
                // dur<=0 makes actual dispose save return before persistence awaits;
                // this fixture does NOT claim disposal-with-positive-duration save proof.
                phase = 'explicit cleanup duration-zero event before public unmount';
                backend!.publishDuration(Duration.zero);
                await tester.pump();
                expect(tester.widget<Controls>(find.byType(Controls)).clock.value.duration, Duration.zero);
              }
            }
            expect(backend!.opens, 1);
            expect(terminal.unexpected, isEmpty);
          } catch (error, stack) {
            primary = error; primaryStack = stack;
            debugPrintSynchronously('RETRY_PRIMARY $scenario phase=$phase $error\n$stack');
          } finally {
            try {
              phase = 'final actual unmount and producer settlement';
              await unmount();
              final player = terminal.properties;
              if (player != null) {
                if (!player.releaseOpen.isCompleted) player.releaseOpen.complete();
                if (player.openEntered.isCompleted) {
                  await tester.runAsync(() => player.openFinished.future);
                }
                // At most one known800ms retry timer; settle remainder after unmount.
                // No general time drain and no Stopwatch manipulation.
                final pending = timers.where((t) => t.retry && t.timer.isActive).toList();
                for (final timer in pending) {
                  expect(timer.delay, const Duration(milliseconds: 800));
                  final left = timer.created.add(timer.delay).difference(binding.clock.now());
                  expect(left, lessThanOrEqualTo(const Duration(milliseconds: 800)));
                  if (left > Duration.zero) await tester.pump(left);
                }
                await tester.pump();
                expect(timers.where((t) => t.retry && t.timer.isActive), isEmpty);
                expect(player.disposal, isNotNull);
                await tester.runAsync(() => player.disposal!);
                expect(player.closed, isTrue);
                expect(player.opens, 1);
              }
              expect(find.byType(VideoPlayerScreen), findsNothing);
              expect(find.byType(PikPakRetryOverlay), findsNothing);
              expect(VideoOutputLease.isHeld, isFalse);
              expect(tester.takeException(), isNull);
              expect(terminal.unexpected, isEmpty);
              expect(sentinelUnexpected, isEmpty);
              expect(httpClients.every((c) => c.sent == 0 && c.closes == 1), isTrue);
              expect(sentinel.sent, 0);
              expect(sentinel.closes, 0);
              expect(debugs.where((s) => s.contains('restore FAILED') ||
                  s.startsWith('SubAuto: ABORT') || s.contains('Error fetching addon subtitles')), isEmpty);
              // These are finite completion witnesses, not a join of all host Futures.
              if (primary == null && (scenario == _Scenario.directDuration ||
                  scenario == _Scenario.initialOpenError)) {
                expect(addonTail(), isTrue);
              }
              cleanupSafe = true;
            } catch (error, stack) {
              cleanupFailure = error; cleanupStack = stack;
              debugPrintSynchronously('RETRY_CLEANUP $scenario $error\n$stack');
            }
            debugPrintSynchronously('RETRY_LEDGER ${jsonEncode({
              'scenario': scenario.name, 'phase': phase, 'cleanupSafe': cleanupSafe,
              'terminal': terminal.properties?.events,
              'stateReads': terminal.properties?.stateReads,
              'http': httpClients.map((c) => {'sent': c.sent, 'closes': c.closes}).toList(),
              'timers': timers.map((t) => {'delayMs': t.delay.inMilliseconds,
                'periodic': t.periodic, 'active': t.timer.isActive, 'stack': t.stack}).toList(),
              'debug': debugs, 'prints': prints,
            })}');
            if (!cleanupSafe || primary != null) {
              // Fail-stop: retain SDK/DB/root resources rather than reset under uncertainty.
              contaminated = true;
            } else {
              try {
                await tester.runAsync(() => DebrifyTvDatabase.instance.debugResetScopeState());
                terminal.video?.close();
                expect(PlayerTerminalBackend.debugOverride, same(terminal));
                IptvMediaStore.debugResetMigration();
                PlayerTerminalBackend.debugOverride = previousTerminal;
                StorageService.resetProfileCaches();
                AppStorage.debugReset();
                ProfileRuntime.debugReset();
                SecretVault.debugReset();
              } catch (error, stack) {
                contaminated = true;
                cleanupFailure ??= error; cleanupStack ??= stack;
              }
            }
            debugPrint = previousPrint;
            if (!contaminated && globalsInstalled) {
              binding.defaultBinaryMessenger.setMockMethodCallHandler(window, null);
              binding.defaultBinaryMessenger.setMockMethodCallHandler(brightness, null);
              binding.defaultBinaryMessenger.setMockMessageHandler(wake, null);
            }
            if (primary != null) Error.throwWithStackTrace(primary!, primaryStack!);
            if (cleanupFailure != null) Error.throwWithStackTrace(cleanupFailure!, cleanupStack!);
          }
        }, () { final client = _RejectHttp(terminal.unexpected); httpClients.add(client); return client; });
      }, zoneSpecification: ZoneSpecification(
        print: (self, parent, zone, line) {
          prints.add(line); parent.print(zone, line);
        },
        createTimer: (self, parent, zone, duration, callback) {
          final stack = StackTrace.current.toString();
          final timer = parent.createTimer(zone, duration, callback);
          timers.add(_TimerObservation(timer, duration, binding.clock.now(), stack, false));
          return timer;
        },
        createPeriodicTimer: (self, parent, zone, duration, callback) {
          final stack = StackTrace.current.toString();
          final timer = parent.createPeriodicTimer(zone, duration, callback);
          timers.add(_TimerObservation(timer, duration, binding.clock.now(), stack, true));
          return timer;
        },
      ));
    }, timeout: const Timeout(Duration(seconds: 45)));
  }
}
