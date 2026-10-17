import 'package:debrify/screens/video_player/widgets/buffering_indicator.dart';
import 'support/iptv_workflow_driver.dart';

void main() {
  for (final sourcePick in [false, true]) {
    testWidgets(
      'P15 review2 media handoff clears an outgoing buffering indicator before pause sourcePick=$sourcePick',
      (t) async {
        final d = IptvWorkflowDriver(t);
        await d.initialize();
        final live = sourcePick
            ? await d.installAddon('buffering-handoff')
            : iptvChannel(1);
        double opacity() => t
            .widget<AnimatedOpacity>(
              find
                  .ancestor(
                    of: find.byType(BufferingIndicator),
                    matching: find.byType(AnimatedOpacity),
                  )
                  .first,
            )
            .opacity;
        try {
          final channels = sourcePick ? [live] : [iptvChannel(0), live];
          await d.mount(
            channels,
            initialUrl: sourcePick ? 'https://probe.test/first.ts' : null,
          );
          d.player.state = d.player.state.copyWith(buffering: true);
          d.player.emit('buffering', true);
          await d.advance(const Duration(milliseconds: 900));
          await d.settle();
          expect(opacity(), 1);
          final pauseCalls = d.calls('pause').length;
          final pause = d.holdOperation('pause');
          if (sourcePick) {
            final sources = await d.sources();
            d.probeMode();
            d.observe(
              () => sources.onSourceSelected(1, 'https://probe.test/second.ts'),
            );
          } else {
            final guide = await d.guide();
            d.observe(() => guide.onChannelSelected(channels, 1));
          }
          await d.f.until(t, () => d.calls('pause').length > pauseCalls);
          await d.settle();
          expect(opacity(), 0);
          pause.complete();
          await d.settle();
          if (sourcePick) await d.probeEvent('width');
          expect(d.errors, isEmpty);
        } finally {
          for (final gate in d.gates) {
            if (!gate.isCompleted) gate.complete();
          }
          await d.settle();
          if (sourcePick) await d.probeEvent('width');
          await d.close();
        }
      },
    );
  }
}
