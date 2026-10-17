import 'support/iptv_workflow_driver.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:debrify/screens/video_player/widgets/tv_controls.dart';
import 'package:flutter/services.dart';

void main() {
  testWidgets(
    'P15 ended programme refresh uses real wall time and the one-second ticker',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      PlatformUtil.debugSetAndroidTvCached(true);
      final live = iptvChannel(
        0,
        url: 'https://p15-ended-programme.test/live/u/p/123.ts',
      );
      var refreshed = false;
      d.response = (r) => iptvPanelReply(
        r,
        title: refreshed ? 'New programme' : 'Ending programme',
        stop: refreshed ? null : DateTime.now().add(const Duration(seconds: 5)),
      );
      try {
        await d.mount([live]);
        expect(d.banners.first.epg?.now?.title, 'Ending programme');
        d.observe(
          () => t.widget<TvControls>(find.byType(TvControls)).onPlayPause(),
        );
        await d.settle();
        expect(d.player.state.playing, false);
        // FakeAsync advances Timer only; programme expiry still reads DateTime.now.
        await d.advance(const Duration(seconds: 6));
        expect(d.banners.first.epg?.now?.title, 'Ending programme');
        await d.observe(() => d.f.key(t, LogicalKeyboardKey.arrowDown));
        refreshed = true;
        IptvEpgService.instance.debugAgeNowNext(
          live.url,
          const Duration(minutes: 10),
        );
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5100)),
        );
        await d.advance(const Duration(seconds: 1));
        await d.settle();
        await d.f.until(
          t,
          () =>
              d.banners.isNotEmpty &&
              d.banners.first.epg?.now?.title == 'New programme',
        );
        expect(d.banners.first.epg?.now?.title, 'New programme');
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
        PlatformUtil.debugSetAndroidTvCached(false);
      }
    },
  );
}
