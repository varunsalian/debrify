import 'package:debrify/screens/video_player/widgets/source_sheet.dart';
import 'package:debrify/screens/video_player/widgets/tv_controls.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:flutter/services.dart';
import 'support/iptv_workflow_driver.dart';
import 'video_player_iptv_memory_test.dart' show iptvEpisode;

void main() {
  for (final sourcePick in [false, true]) {
    testWidgets(
      'P15 review2 a media handoff removes the outgoing TV scrub preview sourcePick=$sourcePick',
      (t) async {
        final d = IptvWorkflowDriver(t);
        await d.initialize();
        PlatformUtil.debugSetAndroidTvCached(true);
        try {
          final addon = sourcePick ? await d.installAddon('vod-scrub') : null;
          final channels = sourcePick
              ? [iptvChannel(0, live: false, url: addon!.url)]
              : [iptvEpisode(1), iptvEpisode(2)];
          await d.mount(
            channels,
            initialUrl: sourcePick ? 'https://probe.test/first.ts' : null,
          );
          await d.advance(const Duration(seconds: 6));
          for (var i = 0; i < 3; i++) {
            await d.f.key(t, LogicalKeyboardKey.arrowRight);
          }
          await d.settle();
          final bar = t.widget<TvControls>(find.byType(TvControls));
          expect(bar.scrubPreview, isNotNull);
          final seeks = d.calls('seek').length;
          if (sourcePick) {
            expect(bar.onShowSources, isNotNull);
            bar.onShowSources!();
            await d.settle();
            final sheet = t.widget<SourceSheet>(find.byType(SourceSheet));
            d.probeMode();
            d.observe(
              () => sheet.onSourceSelected(1, 'https://probe.test/second.ts'),
            );
            await d.f.until(t, () => d.opened.length == 2);
            await d.probeEvent('width');
          } else {
            expect(bar.onShowIptvChannels, isNotNull);
            bar.onShowIptvChannels!();
            await d.settle();
            final sheet = t.widget<IptvChannelSheet>(
              find.byType(IptvChannelSheet),
            );
            await d.f.finish(
              t,
              d.observe(() => sheet.onChannelSelected(channels, 1)),
            );
          }
          await d.settle();
          expect(
            t.widget<TvControls>(find.byType(TvControls)).scrubPreview,
            isNull,
          );
          expect(d.calls('seek'), hasLength(seeks));
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
