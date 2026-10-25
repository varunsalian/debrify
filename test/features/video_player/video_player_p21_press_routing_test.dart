import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
// Existing resolved interface; application dependencies stay frozen.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'support/p21_controls_driver.dart';
import 'support/sleep_timer_driver.dart';

const _right = LogicalKeyboardKey.arrowRight;

List<Map<String, dynamic>> _records(SleepResumeWrites store) => [
  for (final write in store.writes)
    if (write.$1.endsWith('playback_state_v1'))
      (jsonDecode(write.$2 as String) as Map<String, dynamic>).values.single
          as Map<String, dynamic>,
];

/// Phase 21 re-sample closure (T24, T27): which path a press takes. A scrub
/// pauses and resumes the player itself, never through the screen's
/// play/pause toggle, so it writes no resume save and no user-pause intent
/// (the toggle's pause branch writes both together; no television reader of
/// the intent flags is reachable during a scrub, so the save is their
/// boundary). The toggle re-arms the countdown, never through the bar raise.
void main() {
  p21Timeouts();

  testWidgets(
    'P21 TV a scrub while playing pauses, seeks and plays the player without a resume save',
    (t) async {
      final d = P21Driver(t, tv: true);
      await d.initialize();
      final oldStore = SharedPreferencesStorePlatform.instance;
      try {
        await d.mount(screen: P21Driver.screen());
        await d.wait(4000);
        await d.at(const Duration(seconds: 300));
        expect(d.player.state.playing, isTrue);
        final store = await t.runAsync(SleepResumeWrites.install);
        // Two quick nudges, then the third press enters the scrub.
        await d.key(_right);
        await d.key(_right);
        final calls = d.player.calls.length;
        final saved = _records(store!).length;
        await d.key(_right);
        expect(d.bar.scrubPreview, const Duration(seconds: 330));
        expect([for (final c in d.player.calls.skip(calls)) c.$1], ['pause']);
        await d.key(_right);
        await d.key(LogicalKeyboardKey.select);
        expect(d.bar.scrubPreview, isNull);
        expect(
          [for (final c in d.player.calls.skip(calls)) c.$1],
          ['pause', 'seek', 'play'],
        );
        expect(d.seeks.last, const Duration(seconds: 340));
        await d.wait(500);
        expect(_records(store).skip(saved), isEmpty);
        expect(d.player.state.playing, isTrue);
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
        SharedPreferencesStorePlatform.instance = oldStore;
      }
    },
  );

  testWidgets(
    'P21 TV a scrub cancelled while playing pauses and plays the player without a resume save',
    (t) async {
      final d = P21Driver(t, tv: true);
      await d.initialize();
      final oldStore = SharedPreferencesStorePlatform.instance;
      try {
        await d.mount(screen: P21Driver.screen());
        await d.wait(4000);
        await d.at(const Duration(seconds: 300));
        final store = await t.runAsync(SleepResumeWrites.install);
        await d.key(_right);
        await d.key(_right);
        final calls = d.player.calls.length;
        final saved = _records(store!).length;
        await d.key(_right);
        expect(d.bar.scrubPreview, isNotNull);
        await d.key(LogicalKeyboardKey.escape);
        expect(d.bar.scrubPreview, isNull);
        expect(
          [for (final c in d.player.calls.skip(calls)) c.$1],
          ['pause', 'play'],
        );
        await d.wait(500);
        expect(_records(store).skip(saved), isEmpty);
        expect(d.player.state.playing, isTrue);
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
        SharedPreferencesStorePlatform.instance = oldStore;
      }
    },
  );

  testWidgets(
    'P21 TV a play press on a paused bar keeps its remembered block, so the bar stays one extra interval',
    (t) async {
      final d = P21Driver(t, tv: true);
      await d.initialize();
      try {
        await d.mount(screen: P21Driver.screen());
        await d.wait(4000);
        await d.key(LogicalKeyboardKey.arrowDown);
        expect(d.focused, 'tvPlayPause');
        await d.f.finish(t, d.player.pause());
        await d.wait(450);
        // The 3 s poll finds the bar paused, remembers the block and re-arms.
        await d.wait(3000);
        expect(d.barUp, isTrue);
        d.observe(d.bar.onPlayPause);
        await d.wait(50);
        expect(d.count('play'), 1);
        // The press's countdown finds the remembered block and grants one
        // more interval: about six seconds after the press, not three.
        await d.wait(3050);
        expect(d.barUp, isTrue);
        await d.wait(2800);
        expect(d.barUp, isTrue);
        await d.wait(200);
        expect(d.barUp, isFalse);
        expect(d.focused, 'tvPlayerRoot');
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P21 TV a play press with the bar hidden neither raises the bar nor moves focus to Play/Pause',
    (t) async {
      final d = P21Driver(t, tv: true);
      await d.initialize();
      try {
        await d.mount(screen: P21Driver.screen());
        await d.wait(4000);
        expect(d.barUp, isFalse);
        expect(d.focused, 'tvPlayerRoot');
        await d.key(LogicalKeyboardKey.space);
        expect(d.count('pause'), 1);
        await d.wait(100);
        expect(d.barUp, isFalse);
        expect(d.focused, 'tvPlayerRoot');
        await d.key(LogicalKeyboardKey.space);
        expect(d.count('play'), 1);
        await d.wait(100);
        expect(d.barUp, isFalse);
        expect(d.focused, 'tvPlayerRoot');
        // The press's countdown finds the bar hidden and lapses.
        await d.wait(3500);
        expect(d.barUp, isFalse);
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );
}
