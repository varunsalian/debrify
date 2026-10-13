import 'dart:async';

import 'package:debrify/screens/video_player/player_pip_route.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/pip_service.dart';
import 'package:debrify/services/player_display_controls.dart';
import 'package:wakelock_plus/wakelock_plus.dart' as wakelock;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
// Existing resolved transport; application dependencies remain frozen.
// ignore: depend_on_referenced_packages
import 'package:wakelock_plus_platform_interface/wakelock_plus_platform_interface.dart';

import 'fake_player.dart';
import 'trakt_transport.dart';
import 'player_actions.dart';
import 'video_player_environment.dart';

const pipScreen = VideoPlayerScreen(
  videoUrl: 'https://player.test/pip.mp4',
  title: 'PiP lifecycle fixture',
);

class PipWake extends VideoPlayerWake {
  final attempts = <bool>[];
  Completer<void>? barrier;
  bool Function(bool)? holdWhen;
  Object? failure;
  @override
  Future<void> toggle({required bool enable}) async {
    attempts.add(enable);
    if (barrier != null && (holdWhen?.call(enable) ?? true)) {
      await barrier!.future;
    }
    final error = failure;
    failure = null;
    if (error != null) {
      throw error;
    }
    await super.toggle(enable: enable);
  }

  void release() {
    if (barrier?.isCompleted == false) {
      barrier!.complete();
    }
    barrier = null;
  }
}

class PipLifecycleDriver {
  PipLifecycleDriver(this.t, this.f, {this.ios = false});
  final WidgetTester t;
  final VideoPlayerEnvironment f;
  final bool ios;
  WakelockPlusPlatformInterface? previousWake;
  static final _sharedWake = PipWake();
  final wake = _sharedWake;
  final calls = <MethodCall>[];
  final errors = <Object>[];
  final timers = <Timer>[];
  final timed = <(Duration, Timer)>[];
  final periodic = <(Duration, Timer)>[];
  final owners = <Object>[];
  FutureOr<Object?> Function(MethodCall)? handler;
  FutureOr<Object?> Function(MethodCall)? systemHandler;
  IosPipPlayerRoute<Object?>? route;
  Object? stateOwner;
  static const channel = MethodChannel('com.debrify.app/pip');
  final wakeDrainMarker = Object();

  T observe<T>(T Function() body) => runZoned(
    body,
    zoneSpecification: ZoneSpecification(
      handleUncaughtError: (self, parent, zone, error, stack) =>
          errors.add(error),
      createPeriodicTimer: (self, parent, zone, duration, callback) {
        final timer = parent.createPeriodicTimer(zone, duration, callback);
        periodic.add((duration, timer));
        return timer;
      },
      createTimer: (self, parent, zone, duration, callback) {
        final timer = parent.createTimer(zone, duration, callback);
        timers.add(timer);
        timed.add((duration, timer));
        return timer;
      },
    ),
  );

  Future<void> initialize() async {
    await t.runAsync(f.initialize);
    TraktTestTransport.instance.attach(f);
    installPlatform();
    await flushWake();
    wake.attempts.clear();
    wake.writes.clear();
  }

  void installPlatform() {
    previousWake = wakelock.wakelockPlusPlatformInstance;
    PipService.resetForTesting();
    PipService.debugPlatform = ios
        ? TargetPlatform.iOS
        : TargetPlatform.android;
    VpS2Hooks.install(VpS2Hooks(ios: () => ios, android: () => !ios));
    WakelockPlusPlatformInterface.instance = wake;
    wakelock.wakelockPlusPlatformInstance = wake;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (handler != null) {
        return await handler!(call);
      }
      return call.method == 'isSupported' || call.method == 'enterPip'
          ? true
          : null;
    });
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      f.channels.add(('flutter/platform', call));
      return await systemHandler?.call(call);
    });
  }

  Future<void> flushWake() async {
    late Future<void> pending;
    // The final queue cursor must belong to the isolate's live real zone,
    // rather than a widget test's FakeAsync zone that ends between cases.
    // This owner marker never changes playback's requested wake state.
    await t.runAsync(() async {
      pending = PlayerDisplayControls.instance.setWakelockOwner(
        wakeDrainMarker,
        false,
      );
    });
    await f.finish<void>(t, pending);
  }

  Future<void> mount([VideoPlayerScreen screen = pipScreen]) =>
      observe(() => _mount(screen));

  Future<void> _mount(VideoPlayerScreen screen) async {
    if (!ios) {
      await observe(() => f.mount(t, screen));
    } else {
      t.view.physicalSize = const Size(1280, 800);
      t.view.devicePixelRatio = 1;
      await observe(
        () => t.pumpWidget(
          MaterialApp(
            navigatorKey: f.navigator,
            theme: ThemeData.dark(),
            home: const Scaffold(body: Text('PiP browser')),
          ),
        ),
      );
      route = IosPipPlayerRoute<Object?>(builder: (_) => screen);
      f.navigator.currentState!.push(route!);
      await f.until(t, () => f.controllers.isNotEmpty);
      f.player.deliverReady();
      await f.until(t, () => f.player.calls.any((c) => c.$1 == 'open'));
      for (var i = 0; i < 20; i++) {
        await f.advance(t, const Duration(milliseconds: 100));
      }
    }
    stateOwner = t.state(find.byType(VideoPlayerScreen));
    // Native readiness does not finish resume/storage initialization. Observe
    // its real autosave registration before a normal mount can be retired.
    await f.until(
      t,
      () => periodic.any((v) => v.$1 == const Duration(seconds: 6)),
    );
    await f.advance(t);
    await flushWake();
  }

  List<MethodCall> named(String name) =>
      calls.where((c) => c.method == name).toList();
  List<(String, Object?)> operations(String name, [FakePlayer? player]) =>
      (player ?? f.player).calls.where((c) => c.$1 == name).toList();

  Future<void> lifecycle(AppLifecycleState value) async {
    observe(() => t.binding.handleAppLifecycleStateChanged(value));
    await f.advance(t);
  }

  Future<void> settle() async {
    await f.actions.settle(t);
  }

  Future<void> enter() async {
    final dynamic callback = playerControls(t).onPip;
    expect(callback, isNotNull);
    final result = observe<dynamic>(() => callback());
    if (result is Future) {
      await f.finish<dynamic>(t, result);
    }
    await settle();
  }

  Future<Object?> event(String method, Object? value, {FakePlayer? from}) {
    final result = Completer<Object?>();
    final args = ios
        ? {'playerHandle': '${(from ?? f.player).handleValue}', 'value': value}
        : value;
    observe(
      () => t.binding.channelBuffers.push(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(MethodCall(method, args)),
        (reply) {
          try {
            result.complete(const StandardMethodCodec().decodeEnvelope(reply!));
          } catch (e, s) {
            result.completeError(e, s);
          }
        },
      ),
    );
    return result.future;
  }

  Future<Object?> acceptedEvent(
    String method,
    Object? value, {
    FakePlayer? from,
  }) async {
    Object? error;
    final result = await f.finish<Object?>(
      t,
      event(method, value, from: from).then(
        (v) => v,
        onError: (Object e) {
          error = e;
          return null;
        },
      ),
    );
    expect(
      error,
      isNull,
      reason: 'The original $method event must return without an error',
    );
    return result;
  }

  Future<void> deliver(String method, Object? value, {FakePlayer? from}) async {
    await acceptedEvent(method, value, from: from);
    await settle();
  }

  Future<void> retire({bool? expectedWake}) async {
    await t.pumpWidget(const SizedBox.shrink());
    t.binding.scheduleForcedFrame();
    await t.pump();
    await f.until(t, () => f.players.every((p) => p.disposed.isCompleted));
    await flushWake();
    if (expectedWake != null) {
      expect(wake.writes.last, expectedWake);
    }
  }

  Future<void> close() async {
    wake.release();
    await retire();
    for (final owner in owners) {
      await f.finish<void>(
        t,
        PlayerDisplayControls.instance.setWakelockOwner(owner, false),
      );
    }
    await flushWake();
    // Assertions above observe production release before this fixture reset.
    await f.finish<void>(t, PlayerDisplayControls.instance.setWakelock(false));
    await flushWake();
    await f.close(t);
    wakelock.wakelockPlusPlatformInstance = previousWake!;
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    PipService.resetForTesting();
    TraktTestTransport.instance.recorder = null;
    VpS2Hooks.install(null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  }
}
