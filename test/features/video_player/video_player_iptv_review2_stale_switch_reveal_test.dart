import 'package:debrify/screens/video_player/widgets/tv_controls.dart';
import 'package:debrify/utils/platform_util.dart';
import 'support/iptv_workflow_driver.dart';

void main() {
  testWidgets(
    'P15 review2 an older direct open cannot reveal a newer pending candidate probe',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      PlatformUtil.debugSetAndroidTvCached(true);
      final live = await d.installAddon('stale-reveal');
      final channels = [iptvChannel(0), iptvChannel(1), live];
      Future<void>? older;
      Future<void>? newer;
      final failures = <Object>[];
      try {
        await d.mount(channels);
        final bar = t.widget<TvControls>(find.byType(TvControls));
        expect(bar.onShowIptvChannels, isNotNull);
        bar.onShowIptvChannels!();
        await d.settle();
        final guide = t.widget<IptvChannelSheet>(find.byType(IptvChannelSheet));
        final held = d.holdOperation('open', url: channels[1].url);
        older = d.observe(
          () => guide
              .onChannelSelected(channels, 1)
              .then<void>(
                (_) {},
                onError: (Object error) {
                  failures.add(error);
                },
              ),
        );
        await d.f.until(t, () => d.opened.length == 2);
        d.probeMode();
        newer = d.observe(
          () => guide
              .onChannelSelected(channels, 2)
              .then<void>(
                (_) {},
                onError: (Object error) {
                  failures.add(error);
                },
              ),
        );
        await d.f.until(t, () => d.opened.length == 3);
        await d.settle();
        expect(
          t.widget<TvControls>(find.byType(TvControls)).isTransitioning,
          true,
        );
        held.complete();
        await d.f.finish(t, older!);
        await d.settle();
        expect(
          t.widget<TvControls>(find.byType(TvControls)).isTransitioning,
          true,
        );
        expect(failures, isEmpty);
        expect(d.errors, isEmpty);
      } finally {
        for (final gate in d.gates) {
          if (!gate.isCompleted) gate.complete();
        }
        await d.probeEvent('width');
        if (older != null) await d.f.finish(t, older);
        if (newer != null) await d.f.finish(t, newer);
        await d.close();
        PlatformUtil.debugSetAndroidTvCached(false);
      }
    },
  );
}
