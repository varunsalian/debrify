import 'package:debrify/screens/video_player/widgets/player_menu_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/p21_controls_driver.dart';

const _hide = Duration(seconds: 3);

/// Phase 21 Step 0: the controls runtime's inactivity auto-hide, the
/// television bar raise/lower, the tap toggle and the desktop pointer wake,
/// pinned on the original through the real screen.
void main() {
  p21Timeouts();
  group('desktop', () {
    testWidgets(
      'P21 desktop a pointer wake raises the dock and hides it after exactly three seconds',
      (t) async {
        final d = P21Driver(t);
        await d.initialize();
        try {
          await d.mount(screen: P21Driver.screen());
          await d.wait(4000);
          expect(d.barUp, isFalse);
          await d.hover();
          expect(d.barUp, isTrue);
          await d.wait(2950);
          expect(d.barUp, isTrue);
          await d.wait(100);
          expect(d.barUp, isFalse);
          // A lowered desktop dock leaves no countdown behind.
          expect(d.activeTimers(_hide), 0);
          expect(d.errors, isEmpty);
        } finally {
          await d.close();
        }
      },
    );

    testWidgets(
      'P21 desktop each pointer wake restarts the countdown and leaves one timer',
      (t) async {
        final d = P21Driver(t);
        await d.initialize();
        try {
          await d.mount(screen: P21Driver.screen());
          await d.wait(4000);
          await d.hover();
          await d.wait(2000);
          await d.hover();
          expect(d.activeTimers(_hide), 1);
          await d.wait(1500);
          expect(d.barUp, isTrue, reason: 'the first countdown was cancelled');
          await d.wait(1400);
          expect(d.barUp, isTrue);
          await d.wait(200);
          expect(d.barUp, isFalse);
          // Hovering over raised controls keeps them up and re-arms.
          await d.hover();
          await d.wait(1000);
          await d.hover();
          await d.wait(2500);
          expect(d.barUp, isTrue);
          expect(d.errors, isEmpty);
        } finally {
          await d.close();
        }
      },
    );

    testWidgets(
      'P21 desktop a pointer wake under the open menu neither raises the dock nor arms a countdown',
      (t) async {
        final d = P21Driver(t);
        await d.initialize();
        try {
          await d.mount(screen: P21Driver.screen());
          d.observe(() => d.controls.onShowTracks());
          await d.wait(350);
          expect(find.byType(PlayerMenuPanel), findsOneWidget);
          expect(d.barUp, isFalse);
          final before = d.timers.where((v) => v.duration == _hide).length;
          await d.hover();
          await d.wait(100);
          expect(d.barUp, isFalse);
          expect(d.timers.where((v) => v.duration == _hide).length, before);
          expect(d.activeTimers(_hide), 0);
          // The cursor stays visible over the open menu.
          final region = d.pointerRegion;
          expect(region.cursor, MouseCursor.defer);
          expect(d.errors, isEmpty);
        } finally {
          await d.close();
        }
      },
    );

    testWidgets(
      'P21 desktop a tap raises hidden controls with a countdown and a second tap lowers them without one',
      (t) async {
        final d = P21Driver(t);
        await d.initialize();
        try {
          await d.mount(screen: P21Driver.screen());
          await d.wait(4000);
          expect(d.barUp, isFalse);
          final region = d.pointerRegion;
          expect(region.cursor, SystemMouseCursors.none);
          await d.observe(() => t.tapAt(const Offset(640, 400)));
          await d.wait(320);
          expect(d.barUp, isTrue);
          final armed = d.timers.where((v) => v.duration == _hide).length;
          expect(d.activeTimers(_hide), 1);
          // The single tap lands after the double-tap window (300 ms).
          await d.wait(2900);
          expect(d.barUp, isTrue);
          await d.wait(150);
          expect(d.barUp, isFalse);
          await d.observe(() => t.tapAt(const Offset(640, 400)));
          await d.wait(320);
          expect(d.barUp, isTrue);
          // Raised controls keep the centre for their own buttons.
          await d.observe(() => t.tapAt(const Offset(640, 400)));
          await d.wait(320);
          expect(d.barUp, isTrue);
          await d.observe(() => t.tapAt(const Offset(150, 400)));
          await d.wait(320);
          expect(d.barUp, isFalse);
          // Raising armed one countdown; lowering armed none and left the
          // raise's countdown running.
          expect(d.timers.where((v) => v.duration == _hide).length, armed + 1);
          expect(d.activeTimers(_hide), 1);
          expect(d.errors, isEmpty);
        } finally {
          await d.close();
        }
      },
    );
  });

  group('television', () {
    testWidgets(
      'P21 TV a raised bar focuses Play/Pause and hides after three seconds with focus on the root',
      (t) async {
        final d = P21Driver(t, tv: true);
        await d.initialize();
        try {
          await d.mount(screen: P21Driver.screen());
          await d.wait(4000);
          expect(d.barUp, isFalse);
          expect(d.focused, 'tvPlayerRoot');
          await d.key(LogicalKeyboardKey.arrowDown);
          expect(d.barUp, isTrue);
          expect(d.focused, 'tvPlayPause');
          await d.wait(2900);
          expect(d.barUp, isTrue);
          await d.wait(150);
          expect(d.barUp, isFalse);
          expect(d.focused, 'tvPlayerRoot');
          // Nothing left to dismiss: the countdown lapses, it does not poll.
          await d.wait(9000);
          expect(d.activeTimers(_hide), 0);
          expect(d.barUp, isFalse);
          expect(d.errors, isEmpty);
        } finally {
          await d.close();
        }
      },
    );

    testWidgets(
      'P21 TV a paused bar stays up and the first playing poll grants a fresh full interval',
      (t) async {
        final d = P21Driver(t, tv: true);
        await d.initialize();
        try {
          await d.mount(screen: P21Driver.screen());
          await d.wait(4000);
          await d.key(LogicalKeyboardKey.arrowDown);
          await d.f.finish(t, d.player.pause());
          await d.wait(450);
          // Polls at 3 s and 6 s find it paused and re-arm.
          await d.wait(6500);
          expect(d.barUp, isTrue);
          expect(d.activeTimers(_hide), 1);
          await d.f.finish(t, d.player.play());
          await d.wait(50);
          // The 9 s poll finds the blocker gone and re-arms for 12 s.
          await d.wait(4800);
          expect(d.barUp, isTrue);
          await d.wait(300);
          expect(d.barUp, isFalse);
          expect(d.focused, 'tvPlayerRoot');
          expect(d.errors, isEmpty);
        } finally {
          await d.close();
        }
      },
    );

    testWidgets(
      'P21 TV a route over the player holds the bar and its pop restarts the interval',
      (t) async {
        final d = P21Driver(t, tv: true);
        await d.initialize();
        try {
          await d.mount(screen: P21Driver.screen());
          await d.wait(4000);
          await d.key(LogicalKeyboardKey.arrowDown);
          d.f.navigator.currentState!.push(
            MaterialPageRoute<void>(builder: (_) => const SizedBox()),
          );
          await d.wait(500);
          await d.wait(4000);
          expect(d.barUp, isTrue);
          d.f.navigator.currentState!.pop();
          await d.wait(500);
          // Popped at 4.5 s: the 6 s poll grants a fresh interval to 9 s.
          await d.wait(3800);
          expect(d.barUp, isTrue);
          await d.wait(300);
          expect(d.barUp, isFalse);
          expect(d.errors, isEmpty);
        } finally {
          await d.close();
        }
      },
    );

    testWidgets(
      'P21 TV a fresh raise forgets an earlier block and hides on the first poll',
      (t) async {
        final d = P21Driver(t, tv: true);
        await d.initialize();
        try {
          await d.mount(screen: P21Driver.screen());
          await d.wait(4000);
          await d.key(LogicalKeyboardKey.arrowDown);
          await d.f.finish(t, d.player.pause());
          await d.wait(3500);
          expect(d.barUp, isTrue);
          await d.f.finish(t, d.player.play());
          // BACK lowers the bar while the block is still remembered.
          await d.key(LogicalKeyboardKey.escape);
          expect(d.barUp, isFalse);
          expect(d.focused, 'tvPlayerRoot');
          await d.key(LogicalKeyboardKey.arrowDown);
          expect(d.barUp, isTrue);
          await d.wait(2900);
          expect(d.barUp, isTrue);
          await d.wait(150);
          expect(d.barUp, isFalse);
          expect(d.errors, isEmpty);
        } finally {
          await d.close();
        }
      },
    );
  });
}
