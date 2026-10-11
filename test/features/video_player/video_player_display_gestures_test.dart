import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/display_mode_driver.dart';
import 'support/player_actions.dart';
import 'support/video_player_environment.dart';

void main() {
  for (final flags in [
    (true, true),
    (true, false),
    (false, true),
    (false, false),
  ]) {
    testWidgets(
      'display hold lock back=${flags.$1} options=${flags.$2} reads current widget flags',
      (t) async {
        final f = VideoPlayerEnvironment();
        await t.runAsync(f.initialize);
        final d = DisplayModeDriver(t, f);
        try {
          await d.defaults();
          await f.mount(
            t,
            displayScreen(hideBackButton: flags.$1, hideOptions: flags.$2),
          );
          final blocked = flags.$1 && flags.$2;
          await d.startHold();
          expect(d.rates, blocked ? isEmpty : [2.0]);
          expect(playerControls(t).speed, blocked ? 1.0 : 2.0);
          expect(speedHudOpacity(t), blocked ? 0.0 : 1.0);
          if (!blocked) await d.endHold();
          // Same State, different public widget configuration: reads stay live.
          await d.rebuild(
            displayScreen(hideBackButton: true, hideOptions: true),
          );
          expect(f.players, hasLength(1));
          final before = d.rates.length;
          await d.startHold();
          expect(d.rates.length, before);
        } finally {
          await f.close(t);
        }
      },
    );
  }

  testWidgets(
    'display paused hold and release without a hold have no effects',
    (t) async {
      final f = VideoPlayerEnvironment();
      await t.runAsync(f.initialize);
      final d = DisplayModeDriver(t, f);
      try {
        await d.defaults();
        await f.mount(t, displayScreen());
        await d.endHold();
        expect(d.rates, isEmpty);
        await f.player.pause();
        await f.advance(t);
        expect(playerControls(t).isPlaying, isFalse);
        await d.startHold();
        expect(d.rates, isEmpty);
        expect(playerControls(t).speed, 1.0);
        expect(speedHudOpacity(t), 0.0);
      } finally {
        await f.close(t);
      }
    },
  );

  testWidgets(
    'display hold edge and visible-bar strict boundaries preserve button regions',
    (t) async {
      final f = VideoPlayerEnvironment();
      await t.runAsync(f.initialize);
      final d = DisplayModeDriver(t, f);
      try {
        await d.defaults();
        await f.mount(t, displayScreen());
        for (final sample in <(Offset, bool)>[
          (const Offset(23.999, 400), false),
          (const Offset(24, 400), true),
          (const Offset(1256, 400), true),
          (const Offset(1256.001, 400), false),
          (const Offset(640, 71.999), false),
          (const Offset(640, 72), true),
          (const Offset(640, 728), true),
          (const Offset(640, 728.001), false),
        ]) {
          final before = d.rates.length;
          await d.startHold(sample.$1);
          expect(
            d.rates.length,
            before + (sample.$2 ? 1 : 0),
            reason: '${sample.$1}',
          );
          expect(speedHudOpacity(t), sample.$2 ? 1.0 : 0.0);
          if (sample.$2) {
            await d.endHold();
            expect(d.rates.last, 1.0);
          }
        }
      } finally {
        await f.close(t);
      }
    },
  );

  testWidgets(
    'display hidden controls allow top and bottom holds and restore prior speed with one haptic',
    (t) async {
      final f = VideoPlayerEnvironment();
      await t.runAsync(f.initialize);
      final d = DisplayModeDriver(t, f);
      try {
        await d.defaults();
        await f.mount(t, displayScreen());
        await d.speed(1.25);
        // Drain the production auto-hide timer so both bars are hidden.
        await f.advance(t, const Duration(seconds: 3));
        final haptics = f.channels
            .where((c) => c.$2.method == 'HapticFeedback.vibrate')
            .length;
        for (final at in [const Offset(640, 20), const Offset(640, 780)]) {
          await d.startHold(at);
          expect(d.rates.last, 2.0);
          expect(playerControls(t).speed, 2.0);
          expect(speedHudOpacity(t), 1.0);
          await d.endHold();
          expect(d.rates.last, 1.25);
          expect(playerControls(t).speed, 1.25);
          expect(speedHudOpacity(t), 0.0);
        }
        final added = f.channels
            .where((c) => c.$2.method == 'HapticFeedback.vibrate')
            .skip(haptics)
            .toList();
        expect(added.map((c) => c.$2.arguments), [
          'HapticFeedbackType.mediumImpact',
          'HapticFeedbackType.mediumImpact',
        ]);
      } finally {
        await f.close(t);
      }
    },
  );

  testWidgets(
    'display real pointer hold spans rebuild and releases the same recognizer once',
    (t) async {
      final f = VideoPlayerEnvironment();
      await t.runAsync(f.initialize);
      final d = DisplayModeDriver(t, f);
      TestGesture? pointer;
      try {
        await d.defaults();
        await f.mount(t, displayScreen());
        await d.speed(1.5);
        final before = displayGesture(t);
        pointer = await t.startGesture(const Offset(640, 400));
        await t.pump(kLongPressTimeout + const Duration(milliseconds: 1));
        await f.advance(t);
        expect(d.rates, [1.5, 2.0]);
        expect(speedHudOpacity(t), 1.0);
        await d.rebuild(displayScreen(hideBackButton: true));
        final after = displayGesture(t);
        expect(after.onLongPressStart, before.onLongPressStart);
        expect(after.onLongPressEnd, before.onLongPressEnd);
        expect(f.players, hasLength(1));
        await pointer.up();
        pointer = null;
        await f.advance(t);
        expect(d.rates, [1.5, 2.0, 1.5]);
        expect(playerControls(t).speed, 1.5);
        expect(speedHudOpacity(t), 0.0);
      } finally {
        await pointer?.cancel();
        await f.close(t);
      }
    },
  );

  testWidgets(
    'display late release after dispose clears hold without changing disposed player rate',
    (t) async {
      final f = VideoPlayerEnvironment();
      await t.runAsync(f.initialize);
      final d = DisplayModeDriver(t, f);
      try {
        await d.defaults();
        await f.mount(t, displayScreen());
        await d.speed(1.75);
        await d.startHold();
        final end = displayGesture(t).onLongPressEnd!;
        await t.pumpWidget(const SizedBox.shrink());
        await f.until(t, () => f.player.disposed.isCompleted);
        final before = d.rates.length;
        expect(() => end(const LongPressEndDetails()), returnsNormally);
        await f.advance(t);
        expect(() => end(const LongPressEndDetails()), returnsNormally);
        await f.advance(t);
        expect(d.rates.length, before);
        expect(t.takeException(), isNull);
      } finally {
        await f.close(t);
      }
    },
  );
}
