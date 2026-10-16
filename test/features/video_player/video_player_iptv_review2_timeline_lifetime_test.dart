import 'package:debrify/screens/video_player/widgets/tv_controls.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:flutter/services.dart';
import 'support/iptv_workflow_driver.dart';

void main() {
  for (final retire in ['hide', 'dispose', 'idle', 'late-tv']) {
    testWidgets(
      'P15 review2 timeline callback preserves $retire focus lifetime',
      (t) async {
        final d = IptvWorkflowDriver(t);
        await d.initialize();
        final tv = retire == 'hide' || retire == 'dispose';
        PlatformUtil.debugSetAndroidTvCached(tv);
        final live = iptvChannel(
          0,
          url: 'https://p15-timeline-lifetime-$retire.test/live/u/p/123.ts',
          attributes: {'tv_archive': '1'},
        );
        d.response = iptvPanelReply;
        try {
          await d.mount([live, iptvChannel(1, live: false)]);
          TvControls bar() => t.widget<TvControls>(find.byType(TvControls));
          await d.f.until(
            t,
            () =>
                (tv
                    ? bar().onLiveEdgeAction
                    : playerControls(t).onLiveEdgeAction) !=
                null,
          );
          (tv ? bar().onLiveEdgeAction : playerControls(t).onLiveEdgeAction)!();
          await d.f.until(
            t,
            () => tv
                ? bar().liveEdgeActionActive
                : playerControls(t).liveEdgeActionActive,
          );
          if (tv) {
            await d.f.key(t, LogicalKeyboardKey.arrowDown);
          } else {
            await d.observe(() => t.tapAt(const Offset(600, 300)));
            await d.settle();
          }
          final toggle = (tv
              ? bar().onToggleStartOverTimeline
              : playerControls(t).onToggleStartOverTimeline)!;
          if (retire == 'idle') {
            await d.advance(const Duration(seconds: 1));
            final before = d.timed.length;
            d.observe(toggle);
            await d.settle();
            expect(
              d.timed
                  .skip(before)
                  .where(
                    (v) =>
                        v.$1 == const Duration(seconds: 3) &&
                        d.timerOwners[v.$2]!.contains('scheduleAutoHide') &&
                        v.$2.isActive,
                  ),
              hasLength(1),
            );
          } else if (retire == 'dispose') {
            d.observe(toggle);
            await d.retire();
            expect(t.takeException(), isNull);
          } else if (retire == 'late-tv') {
            d.observe(toggle);
            await d.settle();
            // A failed startup probe is deliberately not cached. Its later
            // successful TV answer can change the mounted route's layout.
            PlatformUtil.debugSetAndroidTvCached(true);
            d.player.emit('duration', const Duration(minutes: 21));
            await d.settle();
            expect(bar().startOverTimelineVisible, true);
            expect(bar().progressFocusable, true);
            expect(bar().progressFocusNode.hasFocus, false);
          } else {
            d.observe(() {
              toggle();
              toggle();
            });
            await d.settle();
            expect(bar().startOverTimelineVisible, false);
            bar().onNext!();
            await d.settle();
            expect(bar().isLive, false);
            expect(bar().progressFocusable, true);
            expect(bar().progressFocusNode.hasFocus, false);
          }
          expect(d.errors, isEmpty);
        } finally {
          await d.close();
          PlatformUtil.debugSetAndroidTvCached(false);
        }
      },
    );
  }
}
