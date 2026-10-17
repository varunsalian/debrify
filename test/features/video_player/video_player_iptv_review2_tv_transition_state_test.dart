import 'package:debrify/screens/video_player/widgets/source_sheet.dart';
import 'package:debrify/screens/video_player/widgets/tv_controls.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:flutter/services.dart';
import 'support/iptv_workflow_driver.dart';

void main() {
  for (final mode in ['inactive', 'loading', 'focus']) {
    testWidgets(
      'P15 review2 timeline dispatch preserves $mode admission and focus',
      (t) async {
        final d = IptvWorkflowDriver(t);
        await d.initialize();
        final tv = mode == 'focus';
        PlatformUtil.debugSetAndroidTvCached(tv);
        final live = iptvChannel(
          0,
          url: 'https://p15-timeline-dispatch-$mode.test/live/u/p/123.ts',
          attributes: {'tv_archive': '1'},
        );
        d.response = iptvPanelReply;
        TvControls bar() => t.widget<TvControls>(find.byType(TvControls));
        VoidCallback? action() =>
            tv ? bar().onLiveEdgeAction : playerControls(t).onLiveEdgeAction;
        bool active() => tv
            ? bar().liveEdgeActionActive
            : playerControls(t).liveEdgeActionActive;
        try {
          await d.mount([live]);
          await d.f.until(t, () => action() != null);
          d.observe(action()!);
          await d.f.until(t, active);
          await d.f.key(t, LogicalKeyboardKey.arrowDown);
          await d.advance(const Duration(milliseconds: 400));
          final toggle = tv
              ? bar().onToggleStartOverTimeline
              : playerControls(t).onToggleStartOverTimeline;
          expect(toggle, isNotNull);
          if (mode == 'inactive') {
            d.observe(action()!);
            await d.f.until(t, () => !active());
            await d.settle();
            final before = d.timed.length;
            d.observe(toggle!);
            await d.settle();
            expect(
              d.timed
                  .skip(before)
                  .where(
                    (v) =>
                        v.$1 == const Duration(seconds: 3) &&
                        d.timerOwners[v.$2]!.contains('scheduleAutoHide'),
                  ),
              isEmpty,
            );
          } else if (mode == 'loading') {
            d.player.state = d.player.state.copyWith(duration: Duration.zero);
            d.player.emit('duration', Duration.zero);
            await d.settle();
            d.observe(toggle!);
            await d.settle();
            expect(find.text('Timeline is still loading'), findsOneWidget);
          } else {
            expect(bar().playPauseFocusNode.hasFocus, true);
            expect(bar().progressFocusNode.hasFocus, false);
            d.observe(toggle!);
            await d.settle();
            expect(bar().startOverTimelineVisible, true);
            expect(bar().progressFocusNode.hasFocus, true);
          }
          expect(d.errors, isEmpty);
        } finally {
          await d.close();
          PlatformUtil.debugSetAndroidTvCached(false);
        }
      },
    );
  }
  for (final sourcePick in [false, true]) {
    testWidgets(
      'P15 review2 television transport is inert only while its probe owns the switch sourcePick=$sourcePick',
      (t) async {
        final d = IptvWorkflowDriver(t);
        await d.initialize();
        PlatformUtil.debugSetAndroidTvCached(true);
        final live = await d.installAddon('tv-inert-$sourcePick');
        TvControls controls() => t.widget<TvControls>(find.byType(TvControls));
        Future<void>? tune;
        try {
          final channels = sourcePick ? [live] : [iptvChannel(0), live];
          await d.mount(
            channels,
            initialUrl: sourcePick ? 'https://probe.test/first.ts' : null,
          );
          expect(controls().isTransitioning, false);
          d.probeMode();
          if (sourcePick) {
            expect(controls().onShowSources, isNotNull);
            controls().onShowSources!();
            await d.advance(const Duration(milliseconds: 350));
            final sources = t.widget<SourceSheet>(find.byType(SourceSheet));
            d.observe(
              () => sources.onSourceSelected(1, 'https://probe.test/second.ts'),
            );
          } else {
            await d.observe(() => d.f.key(t, LogicalKeyboardKey.keyG));
            await d.advance(const Duration(milliseconds: 350));
            final guide = t.widget<IptvChannelSheet>(
              find.byType(IptvChannelSheet),
            );
            tune = d.observe(() => guide.onChannelSelected(channels, 1));
          }
          await d.f.until(t, () => d.opened.length == 2);
          await d.settle();
          expect(controls().isTransitioning, true);
          await d.probeEvent('width');
          if (tune != null) await d.f.finish(t, tune);
          await d.settle();
          expect(controls().isTransitioning, false);
          expect(d.errors, isEmpty);
        } finally {
          await d.probeEvent('width');
          await d.close();
          PlatformUtil.debugSetAndroidTvCached(false);
        }
      },
    );
  }
}
