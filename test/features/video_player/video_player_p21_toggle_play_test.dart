import 'dart:async';
import 'dart:convert';

import 'package:debrify/models/android_video_renderer_mode.dart';
import 'package:debrify/screens/video_player/widgets/sleep_timer_sheet.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/storage/player_settings_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' as mk;
// Existing resolved interface; application dependencies stay frozen.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'support/engine_driver.dart';
import 'support/p21_controls_driver.dart';
import 'support/pip_lifecycle_driver.dart';
import 'support/player_actions.dart';
import 'support/sleep_timer_driver.dart';
import 'support/video_player_environment.dart';

List<Map<String, dynamic>> _records(SleepResumeWrites store) => [
  for (final write in store.writes)
    if (write.$1.endsWith('playback_state_v1'))
      (jsonDecode(write.$2 as String) as Map<String, dynamic>).values.single
          as Map<String, dynamic>,
];

/// Home and back: the screen pauses for the background and resumes.
Future<void> _cycle(PipLifecycleDriver d) async {
  for (final state in [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ]) {
    await d.lifecycle(state);
  }
  await d.settle();
}

void main() {
  p21Timeouts();

  testWidgets(
    'P21 a play press after a pause lets an Android renderer fallback resume playing',
    (t) async {
      final d = EngineDriver(t);
      await d.initialize();
      VpS2Hooks.install(VpS2Hooks(android: () => true));
      try {
        await d.f.finish<void>(
          t,
          PlayerSettingsStorage.setAndroidVideoRendererMode(
            AndroidVideoRendererMode.directSurface,
          ),
        );
        await d.mount();
        final old = d.player;
        old.state = old.state.copyWith(playing: true);
        old.emit('playing', true);
        await d.f.advance(t);
        playerControls(t).onPlayPause();
        await d.f.advance(t);
        playerControls(t).onPlayPause();
        await d.f.advance(t);
        expect(old.state.playing, isTrue);
        old.emit('error', 'synthetic MediaCodec video output failure');
        await d.f.until(t, () => d.f.players.length == 2);
        if (!d.player.readyDelivered) d.player.deliverReady();
        await d.f.advance(t, const Duration(seconds: 2));
        final rebuilt = d.player;
        final names = [for (final c in rebuilt.calls) c.$1];
        final open = rebuilt.calls.firstWhere((c) => c.$1 == 'open');
        // The rebuilt player resumes: opened playing, or played after open.
        expect(
          (open.$2 as (mk.Playable, bool)).$2 || names.contains('play'),
          isTrue,
          reason: '$names',
        );
        expect(rebuilt.state.playing, isTrue);
      } finally {
        await d.close();
        VpS2Hooks.install(null);
      }
    },
  );

  testWidgets(
    'P21 a pause press pauses at once and saves the playhead without waiting for the write',
    (t) async {
      final d = P21Driver(t);
      await d.initialize();
      final oldStore = SharedPreferencesStorePlatform.instance;
      SleepResumeWrites? store;
      try {
        await d.mount(screen: P21Driver.screen());
        await d.at(const Duration(seconds: 312));
        store = await t.runAsync(SleepResumeWrites.install);
        store!.barrier = Completer<void>();
        final before = _records(store).length;
        d.observe(d.controls.onPlayPause);
        await d.wait(0);
        expect(d.count('pause'), 1);
        await d.f.until(t, () => store!.entered);
        final saved = _records(store).skip(before).toList();
        expect(saved, hasLength(1));
        expect(saved.single['positionMs'], 312000);
        // The press returned while the write is still held: its countdown
        // is already armed.
        expect(d.activeTimers(const Duration(seconds: 3)), 1);
        store.release();
        await d.wait(100);
        expect(d.controls.isPlaying, isFalse);
        expect(d.errors, isEmpty);
      } finally {
        store?.release();
        await d.close();
        SharedPreferencesStorePlatform.instance = oldStore;
      }
    },
  );

  testWidgets('P21 a play press resumes playback without saving', (t) async {
    final d = P21Driver(t);
    await d.initialize();
    final oldStore = SharedPreferencesStorePlatform.instance;
    SleepResumeWrites? store;
    try {
      await d.mount(screen: P21Driver.screen());
      await d.f.finish(t, d.player.pause());
      await d.wait(100);
      store = await t.runAsync(SleepResumeWrites.install);
      final before = _records(store!).length;
      d.observe(d.controls.onPlayPause);
      await d.wait(100);
      expect(d.count('play'), 1);
      expect(d.player.state.playing, isTrue);
      expect(_records(store).skip(before), isEmpty);
      expect(d.errors, isEmpty);
    } finally {
      await d.close();
      SharedPreferencesStorePlatform.instance = oldStore;
    }
  });

  for (final pause in [true, false]) {
    testWidgets(
      'P21 a ${pause ? 'pause' : 'play'} press restarts the controls countdown',
      (t) async {
        final d = P21Driver(t);
        await d.initialize();
        try {
          await d.mount(screen: P21Driver.screen());
          if (!pause) {
            await d.f.finish(t, d.player.pause());
          }
          await d.wait(4000);
          await d.hover();
          await d.wait(2000);
          await d.key(LogicalKeyboardKey.space);
          expect(d.count(pause ? 'pause' : 'play'), 1);
          await d.wait(1500);
          expect(d.barUp, isTrue, reason: 'the press restarted the countdown');
          await d.wait(1600);
          expect(d.barUp, isFalse);
          expect(d.errors, isEmpty);
        } finally {
          await d.close();
        }
      },
    );
  }

  testWidgets('P21 the TV bar Play/Pause toggles through the same press', (
    t,
  ) async {
    final d = P21Driver(t, tv: true);
    await d.initialize();
    try {
      await d.mount(screen: P21Driver.screen());
      d.observe(d.bar.onPlayPause);
      await d.wait(50);
      expect(d.count('pause'), 1);
      expect(d.bar.isPlaying, isFalse);
      d.observe(d.bar.onPlayPause);
      await d.wait(50);
      expect(d.count('play'), 1);
      expect(d.bar.isPlaying, isTrue);
      expect(d.errors, isEmpty);
    } finally {
      await d.close();
    }
  });

  for (final tv in [false, true]) {
    testWidgets(
      'P21 ${tv ? 'TV OK' : 'space'} before the first ready drives nothing',
      (t) async {
        final d = P21Driver(t, tv: tv);
        await d.initialize();
        try {
          await d.mountUnready(P21Driver.screen());
          final calls = d.player.calls.length;
          await d.key(
            tv ? LogicalKeyboardKey.select : LogicalKeyboardKey.space,
          );
          await d.key(LogicalKeyboardKey.mediaPlayPause);
          expect(d.player.calls.length, calls);
          await d.ready();
          if (tv) await d.wait(4000);
          await d.key(
            tv ? LogicalKeyboardKey.select : LogicalKeyboardKey.mediaPlayPause,
          );
          expect(d.count('pause'), 1);
          expect(d.errors, isEmpty);
        } finally {
          await d.close();
        }
      },
    );
  }

  testWidgets(
    'P21 a pause press keeps a dropped live stream down and a play press lets it reconnect',
    (t) async {
      final channels = [P21Driver.channel(0), P21Driver.channel(1)];
      final d = P21Driver(t);
      await d.initialize();
      try {
        await d.mount(
          screen: P21Driver.iptv(channels),
          settleInitialization: false,
        );
        await d.wait(1000);
        d.observe(d.controls.onPlayPause);
        await d.f.actions.settle(t);
        final paused = d.opens.length;
        d.observe(() => d.player.emit('error', 'connection lost'));
        for (var i = 0; i < 10; i++) {
          await d.wait(1000);
        }
        expect(
          d.opens,
          hasLength(paused),
          reason: 'a user pause is not retuned',
        );
        d.observe(d.controls.onPlayPause);
        await d.f.actions.settle(t);
        d.observe(() => d.player.emit('error', 'connection lost'));
        for (var i = 0; i < 10; i++) {
          await d.wait(1000);
        }
        expect(d.opens.length, greaterThan(paused));
        expect(d.opens.last.uri, channels[0].url);
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P21 an explicit play clears a sleep stop, so returning from the background resumes again',
    (t) async {
      final f = VideoPlayerEnvironment();
      final d = PipLifecycleDriver(t, f);
      await d.initialize();
      try {
        await d.mount();
        await pickSleep(
          t,
          f,
          const SleepTimerSelection(SleepTimerMode.countdown, 1),
        );
        await f.advance(t, const Duration(minutes: 1));
        await f.until(t, () => d.operations('pause').length == 1);
        await d.settle();
        expect(f.player.state.playing, isFalse, reason: 'the sleep stop');
        // Latched: coming back from the background does not un-stop it.
        await _cycle(d);
        expect(d.operations('play'), isEmpty);
        d.observe(playerControls(t).onPlayPause);
        await d.settle();
        expect(d.operations('play'), hasLength(1));
        await _cycle(d);
        expect(d.operations('play'), hasLength(2));
        expect(f.player.state.playing, isTrue);
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P21 the PiP play-pause action pauses with a save, then resumes without one',
    (t) async {
      final f = VideoPlayerEnvironment();
      final d = PipLifecycleDriver(t, f);
      final previous = SharedPreferencesStorePlatform.instance;
      SleepResumeWrites? writes;
      await d.initialize();
      try {
        await d.mount();
        writes = await t.runAsync(SleepResumeWrites.install);
        await d.deliver('onPipAction', 'playpause');
        expect(d.operations('pause'), hasLength(1));
        expect(_records(writes!), hasLength(1));
        await d.deliver('onPipAction', 'playpause');
        expect(d.operations('play'), hasLength(1));
        expect(_records(writes), hasLength(1));
        // 'pause' and 'play' only toggle from the opposite state.
        await d.deliver('onPipAction', 'play');
        expect(d.operations('pause'), hasLength(1));
        await d.deliver('onPipAction', 'pause');
        expect(d.operations('pause'), hasLength(2));
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
        SharedPreferencesStorePlatform.instance = previous;
      }
    },
  );
}
