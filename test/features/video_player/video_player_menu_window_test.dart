import 'package:debrify/screens/video_player/widgets/iptv_zap_banner.dart';
import 'package:debrify/screens/video_player/widgets/controls.dart';
import 'package:debrify/screens/video_player/widgets/player_menu_panel.dart';
import 'package:debrify/screens/video_player/widgets/tv_controls.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/player_actions.dart';
import 'support/recording_driver.dart';

void main() {
  testWidgets('p13 menu opening cancels the pending transport hide timer', (
    t,
  ) async {
    final d = RecordingDriver(t);
    await d.setup();
    try {
      await d.mountRecording();
      d.observe(
        () => t
            .widgetList<MouseRegion>(find.byType(MouseRegion))
            .lastWhere((widget) => widget.onHover != null)
            .onHover!(const PointerHoverEvent()),
      );
      await t.pump();
      expect(
        t
            .widget<AnimatedOpacity>(
              find
                  .ancestor(
                    of: find.byType(Controls),
                    matching: find.byType(AnimatedOpacity),
                  )
                  .first,
            )
            .opacity,
        1,
        reason: 'the menu must hide controls that were visible at admission',
      );
      final hideTimers = d.timers
          .where(
            (entry) =>
                entry.timer.isActive &&
                // Un-prefixed: matches the facade frame and, after phase 21,
                // the moved VpControlsRuntime.scheduleAutoHide frame.
                entry.stack.contains('scheduleAutoHide'),
          )
          .toList();
      expect(hideTimers, isNotEmpty);
      d.observe(() => playerControls(t).onShowTracks());
      await d.f.advance(t);
      expect(find.byType(PlayerMenuPanel), findsOneWidget);
      final controls = find.byType(Controls);
      expect(
        t
            .widget<AnimatedOpacity>(
              find
                  .ancestor(
                    of: controls,
                    matching: find.byType(AnimatedOpacity),
                  )
                  .first,
            )
            .opacity,
        0,
      );
      expect(
        t
            .widget<IgnorePointer>(
              find
                  .ancestor(of: controls, matching: find.byType(IgnorePointer))
                  .first,
            )
            .ignoring,
        isTrue,
      );
      expect(hideTimers.every((entry) => !entry.timer.isActive), isTrue);
      expect(d.errors, isEmpty);
    } finally {
      await d.close();
    }
  });
  testWidgets(
    'p13 TV menu opening releases root focus before the panel frame',
    (t) async {
      final d = RecordingDriver(t);
      await d.setup();
      try {
        PlatformUtil.debugSetAndroidTvCached(true);
        await d.mountRecording();
        final root = t
            .widget<Focus>(
              find.byWidgetPredicate(
                (widget) =>
                    widget is Focus &&
                    widget.focusNode?.debugLabel == 'tvPlayerRoot',
              ),
            )
            .focusNode!;
        root.requestFocus();
        await t.idle();
        expect(FocusManager.instance.primaryFocus, same(root));
        d.observe(
          () => t.widget<TvControls>(find.byType(TvControls)).onShowTracks(),
        );
        await t.idle();
        expect(
          find.byType(PlayerMenuPanel),
          findsNothing,
          reason: 'no menu frame has run',
        );
        expect(FocusManager.instance.primaryFocus, isNot(same(root)));
        await d.f.advance(t, const Duration(milliseconds: 350));
        expect(find.byType(PlayerMenuPanel), findsOneWidget);
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
        PlatformUtil.debugSetAndroidTvCached(false);
      }
    },
  );
  testWidgets('p13 menu opening retires a floating live zap banner', (t) async {
    final d = RecordingDriver(t);
    await d.setup();
    final floating = find.byWidgetPredicate(
      (widget) => widget is IptvZapBanner && !widget.flush,
    );
    try {
      await d.mountRecording();
      await d.f.advance(t, const Duration(seconds: 5));
      await d.zap();
      expect(floating, findsOneWidget);
      d.observe(() => playerControls(t).onShowTracks());
      await d.f.advance(t, const Duration(milliseconds: 350));
      final panel = t.widget<PlayerMenuPanel>(find.byType(PlayerMenuPanel));
      expect(floating, findsNothing);
      panel.onClose();
      await d.f.advance(t, const Duration(milliseconds: 350));
      expect(floating, findsNothing);
      expect(d.errors, isEmpty);
    } finally {
      await d.close();
    }
  });
}
