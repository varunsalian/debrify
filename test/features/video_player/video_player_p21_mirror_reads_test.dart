import 'dart:async';
import 'dart:convert';

import 'package:debrify/screens/video_player/models/hud_state.dart';
import 'package:debrify/screens/video_player/widgets/seek_hud.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
// Existing resolved interface; application dependencies stay frozen.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'support/p21_controls_driver.dart';
import 'support/skip_segment_driver.dart';
import 'support/sleep_timer_driver.dart';

const _left = LogicalKeyboardKey.arrowLeft;
const _right = LogicalKeyboardKey.arrowRight;
const _hide = Duration(seconds: 3);

/// Positions saved by resume writes, in order.
List<int> _saved(SleepResumeWrites store) => [
  for (final write in store.writes)
    if (write.$1.endsWith('playback_state_v1'))
      ((jsonDecode(write.$2 as String) as Map<String, dynamic>).values.single
              as Map<String, dynamic>)['positionMs']
          as int,
];

Future<P21Driver> _mount(
  WidgetTester t, {
  bool tv = false,
  Duration at = const Duration(seconds: 300),
}) async {
  final d = P21Driver(t, tv: tv);
  await d.initialize();
  await d.mount(screen: P21Driver.screen());
  await d.wait(4000);
  await d.at(at);
  return d;
}

Future<void> _progressRow(P21Driver d) async {
  await d.key(LogicalKeyboardKey.arrowDown);
  d.bar.progressFocusNode.requestFocus();
  await d.wait(50);
}

Future<void> _doubleTap(P21Driver d, Offset at) async {
  d.observe(
    () => d.gestures.onDoubleTapDown!(TapDownDetails(localPosition: at)),
  );
  await d.wait(0);
  await d.wait(0);
}

Future<SeekHudState?> _pan(P21Driver d, Offset from, Offset to) async {
  d.observe(
    () => d.gestures.onPanStart!(DragStartDetails(localPosition: from)),
  );
  await d.wait(0);
  await d.wait(0);
  d.observe(
    () => d.gestures.onPanUpdate!(
      DragUpdateDetails(globalPosition: to, localPosition: to),
    ),
  );
  await d.wait(0);
  final hud = find.byType(SeekHud);
  final state = hud.evaluate().isEmpty ? null : d.t.widget<SeekHud>(hud).hud;
  d.observe(() => d.gestures.onPanEnd!(DragEndDetails()));
  await d.wait(300);
  return state;
}

/// Phase 21a Step 0c, class 1: every moved read of the playhead, the playing
/// flag and the length uses the screen's own copy, not the player's reported
/// state. Each case makes the two differ (see [P21Driver.playerReports]) and
/// observes which one the behaviour followed.
void main() {
  p21Timeouts();

  testWidgets(
    'P21 a pause press follows the screen playing flag and saves the screen playhead',
    (t) async {
      final d = P21Driver(t);
      await d.initialize();
      final oldStore = SharedPreferencesStorePlatform.instance;
      SleepResumeWrites? store;
      try {
        await d.mount(screen: P21Driver.screen());
        await d.at(const Duration(seconds: 312));
        store = await t.runAsync(SleepResumeWrites.install);
        final before = _saved(store!).length;
        d.playerReports(playing: false, position: const Duration(seconds: 40));
        d.observe(d.controls.onPlayPause);
        await d.wait(100);
        expect(d.count('pause'), 1);
        expect(d.count('play'), 0);
        expect(_saved(store).skip(before), [312000]);
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
        SharedPreferencesStorePlatform.instance = oldStore;
      }
    },
  );

  testWidgets(
    'P21 a play press follows the screen paused flag while the player reports playing',
    (t) async {
      final d = P21Driver(t);
      await d.initialize();
      try {
        await d.mount(screen: P21Driver.screen());
        await d.f.finish(t, d.player.pause());
        await d.wait(100);
        d.playerReports(playing: true);
        d.observe(d.controls.onPlayPause);
        await d.wait(100);
        expect(d.count('play'), 1);
        expect(d.count('pause'), 1, reason: 'only the setup pause');
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );

  for (final screenPlaying in [true, false]) {
    testWidgets(
      'P21 TV the auto-hide ${screenPlaying ? 'hides a bar the screen sees playing' : 'holds a bar the screen sees paused'} whatever the player reports',
      (t) async {
        final d = await _mount(t, tv: true);
        try {
          if (!screenPlaying) {
            await d.f.finish(t, d.player.pause());
            await d.wait(50);
          }
          d.playerReports(playing: !screenPlaying);
          await d.key(LogicalKeyboardKey.arrowDown);
          expect(d.barUp, isTrue);
          await d.wait(3100);
          expect(d.barUp, !screenPlaying);
          await d.wait(6000);
          expect(d.barUp, !screenPlaying);
          expect(d.errors, isEmpty);
        } finally {
          await d.close();
        }
      },
    );
  }

  testWidgets(
    'P21 TV a progress-row scrub starts from the screen playhead and pauses and resumes by the screen playing flag',
    (t) async {
      final d = await _mount(t, tv: true);
      try {
        await _progressRow(d);
        d.playerReports(position: const Duration(seconds: 40), playing: false);
        await d.key(_left);
        expect(d.bar.scrubPreview, const Duration(seconds: 290));
        expect(d.count('pause'), 1, reason: 'the screen saw it playing');
        await d.key(LogicalKeyboardKey.select);
        expect(d.seeks, [const Duration(seconds: 290)]);
        expect(d.count('play'), 1, reason: 'it was playing at the begin');
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P21 TV a scrub begun while the screen sees a pause neither pauses nor resumes though the player reports playing',
    (t) async {
      final d = await _mount(t, tv: true);
      try {
        await d.f.finish(t, d.player.pause());
        await d.wait(50);
        await _progressRow(d);
        d.playerReports(playing: true);
        await d.key(_right);
        expect(d.bar.scrubPreview, const Duration(seconds: 310));
        expect(d.count('pause'), 1, reason: 'only the setup pause');
        await d.key(LogicalKeyboardKey.escape);
        expect(d.bar.scrubPreview, isNull);
        expect(d.count('play'), 0);
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );

  for (final longer in [true, false]) {
    testWidgets(
      'P21 TV scrub strides clamp to the screen length while the player reports a ${longer ? 'longer' : 'shorter'} one',
      (t) async {
        final d = await _mount(
          t,
          tv: true,
          at: longer
              ? const Duration(minutes: 19, seconds: 40)
              : const Duration(minutes: 9, seconds: 40),
        );
        try {
          d.playerReports(
            duration: longer
                ? const Duration(hours: 1)
                : const Duration(minutes: 10),
          );
          await _progressRow(d);
          for (var i = 0; i < 4; i++) {
            await d.key(_right);
          }
          // The screen's item is twenty minutes long.
          expect(
            d.bar.scrubPreview,
            longer
                ? const Duration(minutes: 20)
                : const Duration(minutes: 10, seconds: 20),
          );
          await d.key(LogicalKeyboardKey.select);
          expect(
            d.seeks.last,
            longer
                ? const Duration(minutes: 20)
                : const Duration(minutes: 10, seconds: 20),
          );
          expect(d.errors, isEmpty);
        } finally {
          await d.close();
        }
      },
    );
  }

  testWidgets(
    'P21 TV the hold enters a scrub when the screen knows the length though the player reports none',
    (t) async {
      final d = await _mount(t, tv: true);
      try {
        d.playerReports(duration: Duration.zero);
        for (var i = 0; i < 3; i++) {
          await d.key(_right);
        }
        expect(d.bar.scrubPreview, const Duration(seconds: 330));
        expect(d.seeks, hasLength(2));
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P21 a double tap seeks from the screen playhead and clamps to the screen length',
    (t) async {
      final d = await _mount(t);
      try {
        d.playerReports(
          position: const Duration(seconds: 40),
          duration: const Duration(minutes: 5),
        );
        await _doubleTap(d, const Offset(1000, 400));
        await d.wait(500);
        expect(d.seeks, [const Duration(seconds: 310)]);
        await d.at(const Duration(minutes: 19, seconds: 55));
        d.playerReports(duration: const Duration(minutes: 30));
        await _doubleTap(d, const Offset(1000, 400));
        await d.wait(500);
        await d.at(const Duration(seconds: 4));
        d.playerReports(position: const Duration(seconds: 100));
        await _doubleTap(d, const Offset(200, 400));
        expect(d.seeks, [
          const Duration(seconds: 310),
          const Duration(minutes: 20),
          Duration.zero,
        ]);
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P21 a seek pan measures from the screen playhead and maps and clamps by the screen length',
    (t) async {
      final d = await _mount(t);
      try {
        d.playerReports(
          position: const Duration(seconds: 40),
          duration: Duration.zero,
        );
        final hud = await _pan(
          d,
          const Offset(640, 400),
          const Offset(768, 400),
        );
        expect(hud, isNotNull, reason: 'the screen knows the length');
        expect(hud!.target, const Duration(seconds: 312));
        expect(hud.base, const Duration(seconds: 300));
        expect(hud.isForward, isTrue);
        await d.length(const Duration(seconds: 60));
        await d.at(const Duration(seconds: 10));
        d.playerReports(
          position: const Duration(seconds: 50),
          duration: const Duration(minutes: 20),
        );
        // Half the width of the screen's 60 s item is 30 s.
        final half = await _pan(
          d,
          const Offset(100, 400),
          const Offset(740, 400),
        );
        expect(half!.target, const Duration(seconds: 40));
        final end = await _pan(
          d,
          const Offset(100, 400),
          const Offset(1270, 400),
        );
        expect(end!.target, const Duration(seconds: 60));
        expect(d.seeks, [
          const Duration(seconds: 312),
          const Duration(seconds: 40),
          const Duration(seconds: 60),
        ]);
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P21 TV after a skip whose seek is still in flight a scrub starts from the skip target',
    (t) async {
      final d = P21Driver(t, tv: true);
      await d.initialize();
      final skip = SkipSegmentDriver(t, d.f);
      final landing = Completer<void>();
      try {
        await skip.configure();
        await d.mount(screen: skipScreen());
        await skip.tick();
        await d.wait(8000);
        skip.expectButton(true);
        d.player.delays['seek'] = landing;
        await d.key(LogicalKeyboardKey.select);
        d.player.delays.remove('seek');
        expect(d.seeks, [const Duration(seconds: 30)]);
        expect(d.player.state.position, const Duration(seconds: 15));
        await _progressRow(d);
        await d.key(_left);
        expect(d.bar.scrubPreview, const Duration(seconds: 20));
        await d.key(LogicalKeyboardKey.select);
        expect(d.seeks.last, const Duration(seconds: 20));
        expect(d.errors, isEmpty);
      } finally {
        if (!landing.isCompleted) landing.complete();
        skip.releaseAll();
        await d.close();
      }
    },
  );

  testWidgets(
    'P21 desktop an auto-hide countdown is unaffected by the player reported playing flag',
    (t) async {
      final d = await _mount(t);
      try {
        d.playerReports(playing: false);
        await d.hover();
        await d.wait(3100);
        expect(d.barUp, isFalse);
        expect(d.activeTimers(_hide), 0);
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );
}
