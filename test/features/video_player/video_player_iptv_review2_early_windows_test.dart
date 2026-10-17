import 'support/iptv_storage_driver.dart';
import 'support/iptv_workflow_driver.dart';

void main() {
  testWidgets(
    'P15 review2 an unpaged zap publishes a different group with the same directory',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      try {
        await d.mount([iptvChannel(0), iptvChannel(1, group: 'Sports')]);
        await d.zap(1);
        final sheet = await d.guide();
        expect(sheet.selectedCategory, 'Sports');
        expect(sheet.categories, isEmpty);
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );
  testWidgets(
    'P15 review2 return to live retires archive UI before recording stop',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      final live = iptvChannel(
        0,
        url: 'https://p15-return-early.test/live/u/p/123.ts',
        attributes: {'tv_archive': '1'},
      );
      d.response = iptvPanelReply;
      final stop = IptvAwaitDelivery('switchToIptvChannel', (v) => v == null);
      try {
        await d.mount([live]);
        final sheet = await d.guide();
        await d.f.finish(
          t,
          d.observe(
            () => sheet.onPlayProgramme!(live, iptvProgramme(airing: true)),
          ),
        );
        await d.closeGuide(sheet);
        expect(playerControls(t).liveEdgeActionActive, true);
        d.observe(playerControls(t).onToggleStartOverTimeline!);
        await d.settle();
        expect(playerControls(t).startOverTimelineVisible, true);
        final before = d.opened.length;
        stop.run(() => d.observe(playerControls(t).onLiveEdgeAction!));
        await d.f.until(t, () => stop.pending.isNotEmpty);
        expect(d.opened.length, before);
        expect(playerControls(t).liveEdgeActionActive, false);
        expect(playerControls(t).startOverTimelineVisible, false);
        stop.release();
        await d.f.until(t, () => d.opened.length == before + 1);
        await d.settle();
        expect(d.playingUrl, live.url);
        expect(d.errors, isEmpty);
      } finally {
        stop.release();
        await d.close();
      }
    },
  );
  testWidgets('P15 review2 whitespace group anchors an uncategorized guide', (
    t,
  ) async {
    final d = IptvWorkflowDriver(t);
    await d.initialize();
    try {
      await d.mount([iptvChannel(0, group: '  ')]);
      final sheet = await d.guide();
      expect(sheet.selectedCategory, isNull);
      expect(d.errors, isEmpty);
    } finally {
      await d.close();
    }
  });
  testWidgets(
    'P15 review2 an equal category preserves an explicit all-source context',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      try {
        await d.mount([iptvChannel(0), iptvChannel(1)]);
        final sheet = await d.guide();
        sheet.onContextChanged!(
          IptvGuideContext(
            categories: ['News'],
            sourceId: null,
            sourceName: 'All sources',
            selectedCategory: 'News',
            contentType: 'live',
          ),
        );
        await d.closeGuide(sheet);
        await d.zap(1);
        final reopened = await d.guide();
        expect(reopened.sourceId, isNull);
        expect(reopened.sourceName, 'All sources');
        expect(reopened.selectedCategory, 'News');
        expect(reopened.categories, ['News']);
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );
}
