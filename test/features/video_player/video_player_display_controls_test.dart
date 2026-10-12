import 'package:debrify/screens/video_player/models/gesture_state.dart';
import 'package:debrify/screens/video_player/widgets/player_menu_panel.dart';
import 'package:debrify/screens/video_player/widgets/controls.dart';
import 'package:debrify/screens/video_player/widgets/tv_controls.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/display_mode_driver.dart';
import 'support/fake_player.dart';
import 'support/player_actions.dart';
import 'support/video_player_environment.dart';

void main() {
  testWidgets(
    'display defaults seed cinema framing and record the loaded aspect diagnostic',
    (t) async {
      final f = VideoPlayerEnvironment(native: true);
      await t.runAsync(f.initialize);
      final d = DisplayModeDriver(t, f);
      final oldPrint = debugPrint;
      final logs = <String>[];
      try {
        await d.defaults(aspect: 10);
        debugPrint = (message, {wrapWidth}) => logs.add(message ?? '');
        await f.mount(t, displayScreen());
        d.expectAspect(AspectMode.cinemaZoom, BoxFit.contain, null);
        expect(
          (f.player.platform as FakeNativePlayer).properties['video-zoom'],
          '0.415037',
        );
        expect(
          logs.where(
            (s) =>
                s ==
                'VideoPlayer: Loaded defaults - aspect=AspectMode.cinemaZoom',
          ),
          hasLength(1),
        );
        expect(playerControls(t).speed, 1.0);
      } finally {
        debugPrint = oldPrint;
        await f.close(t);
      }
    },
  );

  testWidgets(
    'display TV dock dispatches speed and aspect menus with live selected values and key A',
    (t) async {
      final f = VideoPlayerEnvironment();
      await t.runAsync(f.initialize);
      final d = DisplayModeDriver(t, f);
      try {
        await d.defaults();
        PlatformUtil.debugSetAndroidTvCached(true);
        await f.mount(t, displayScreen());
        TvControls controls() => t.widget<TvControls>(find.byType(TvControls));
        expect(controls().speed, 1.0);
        expect(controls().aspectMode, AspectMode.contain);
        final speed = await d.menu(PlayerMenuSection.speed);
        expect(speed.speed, 1.0);
        speed.onSpeedSelected(1.75);
        await f.advance(t);
        await d.closeMenu();
        expect(controls().speed, 1.75);
        expect(d.rates, [1.75]);
        final aspect = await d.menu(PlayerMenuSection.aspect);
        expect(aspect.aspectMode, AspectMode.contain);
        expect(aspect.speed, 1.75);
        aspect.onAspectSelected(AspectMode.aspect5_4);
        await f.advance(t);
        await d.closeMenu();
        expect(controls().aspectMode, AspectMode.aspect5_4);
        await t.sendKeyEvent(LogicalKeyboardKey.keyA);
        await f.advance(t);
        expect(controls().aspectMode, AspectMode.cinemaZoom);
      } finally {
        await f.close(t);
      }
    },
  );

  testWidgets(
    'display styled dock forwards current speed aspect and orientation actions',
    (t) async {
      final f = VideoPlayerEnvironment();
      await t.runAsync(f.initialize);
      final d = DisplayModeDriver(t, f);
      try {
        await d.defaults(dock: 'tiers');
        await f.mount(t, displayScreen());
        await d.speed(1.25);
        await d.aspect(AspectMode.aspect3_2);
        expect(playerControls(t).speed, 1.25);
        d.expectAspect(AspectMode.aspect3_2, BoxFit.cover, 3 / 2);
        final speed = await d.menu(PlayerMenuSection.speed);
        expect(speed.speed, 1.25);
        expect(speed.aspectMode, AspectMode.aspect3_2);
        await d.closeMenu();
        final o = DisplayOrientationDriver(f);
        await o.toggle(playerControls(t));
        await f.advance(t);
        expect(playerControls(t).isLandscape, isFalse);
        expect(o.orientations, [
          ['DeviceOrientation.portraitUp'],
        ]);
      } finally {
        await f.close(t);
      }
    },
  );

  testWidgets(
    'display aspect cycle rearms controls auto-hide from the action time',
    (t) async {
      final f = VideoPlayerEnvironment();
      await t.runAsync(f.initialize);
      final d = DisplayModeDriver(t, f);
      try {
        await d.defaults();
        await f.mount(t, displayScreen());
        double opacity() => t
            .widget<AnimatedOpacity>(
              find
                  .ancestor(
                    of: find.byType(Controls),
                    matching: find.byType(AnimatedOpacity),
                  )
                  .first,
            )
            .opacity;
        expect(opacity(), 1.0);
        await f.advance(t, const Duration(milliseconds: 2000));
        await t.sendKeyEvent(LogicalKeyboardKey.keyA);
        await f.advance(t);
        await f.advance(t, const Duration(milliseconds: 1100));
        expect(opacity(), 1.0);
        await f.advance(t, const Duration(milliseconds: 1900));
        expect(opacity(), 0.0);
      } finally {
        await f.close(t);
      }
    },
  );
}
