import 'support/iptv_workflow_driver.dart';

void main() {
  testWidgets(
    'P15 review2 a live-shaped VOD URL cannot borrow the live archive action',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      final live = iptvChannel(
        0,
        url: 'https://p15-capability-vod.test/live/u/p/123.ts',
        attributes: {'tv_archive': '1'},
      );
      final vod = iptvChannel(
        1,
        live: false,
        url: 'https://p15-capability-vod.test/live/u/p/124.ts',
        attributes: {'tv_archive': '1'},
      );
      d.response = iptvPanelReply;
      try {
        await d.mount([live, vod]);
        await d.f.until(t, () => playerControls(t).onLiveEdgeAction != null);
        await d.zap(1);
        expect(d.playingUrl, vod.url);
        expect(playerControls(t).onLiveEdgeAction, isNull);
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P15 review2 a retained live-edge callback rechecks archive capability',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      final attrs = <String, String>{'tv_archive': '1'};
      final live = iptvChannel(
        0,
        url: 'https://p15-capability-late.test/live/u/p/123.ts',
        attributes: attrs,
      );
      d.response = iptvPanelReply;
      try {
        await d.mount([live]);
        await d.f.until(t, () => playerControls(t).onLiveEdgeAction != null);
        final action = playerControls(t).onLiveEdgeAction!;
        attrs['tv_archive'] = '0';
        d.observe(action);
        await d.settle();
        expect(d.opened, [live.url]);
        expect(playerControls(t).liveEdgeActionLoading, false);
        await d.advance(const Duration(seconds: 1));
        expect(playerControls(t).onLiveEdgeAction, isNull);
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );
}
