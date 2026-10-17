import 'package:debrify/screens/video_player/widgets/tv_controls.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:flutter/services.dart';
import 'support/iptv_workflow_driver.dart';

void main() {
  testWidgets(
    'P15 review2 a desktop timeline reveal cannot preclaim later TV focus',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      PlatformUtil.debugSetAndroidTvCached(false);
      final live = iptvChannel(
        0,
        url: 'https://p15-visible-late-tv.test/live/u/p/123.ts',
        attributes: {'tv_archive': '1'},
      );
      d.response = iptvPanelReply;
      try {
        await d.mount([live]);
        await d.f.until(t, () => playerControls(t).onLiveEdgeAction != null);
        d.observe(playerControls(t).onLiveEdgeAction!);
        await d.f.until(t, () => playerControls(t).liveEdgeActionActive);
        // The desktop keyboard action opens the dock synchronously. A tap is
        // delayed by the double-tap recognizer and would hide this distinction.
        await d.f.key(t, LogicalKeyboardKey.arrowDown);
        await d.advance(const Duration(milliseconds: 400));
        d.observe(playerControls(t).onToggleStartOverTimeline!);
        await d.settle();
        PlatformUtil.debugSetAndroidTvCached(true);
        d.player.emit('duration', const Duration(minutes: 21));
        await d.settle();
        final bar = t.widget<TvControls>(find.byType(TvControls));
        expect(bar.startOverTimelineVisible, true);
        expect(bar.progressFocusable, true);
        expect(bar.progressFocusNode.hasFocus, false);
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );
}
