import 'package:debrify/screens/video_player/widgets/transition_overlay.dart';
import 'support/iptv_workflow_driver.dart';
import 'video_player_iptv_review2_resource_deadlines_test.dart'
    show PlayingDelivery;

void main() {
  for (final sourcePick in [false, true]) {
    testWidgets(
      'P15 review2 reveal cleanup stops its borrowed animation sourcePick=$sourcePick',
      (t) async {
        final playing = PlayingDelivery();
        final d = IptvWorkflowDriver(
          t,
          configurePlayer: (p) => p.events['playing'] = playing,
        );
        await d.initialize();
        try {
          final live = sourcePick
              ? await d.installAddon('reveal-owner')
              : iptvChannel(1);
          await d.mount(
            sourcePick ? [live] : [iptvChannel(0), live],
            initialUrl: sourcePick ? 'https://probe.test/first.ts' : null,
          );
          playing.suppress = true;
          if (sourcePick) {
            final sheet = await d.sources();
            d.probeMode();
            d.observe(
              () => sheet.onSourceSelected(1, 'https://probe.test/second.ts'),
            );
            await d.f.until(t, () => d.opened.length == 2);
            await d.probeEvent('width');
            await d.settle();
          } else {
            await d.zap(1);
          }
          final owner = sourcePick
              ? 'switchToIptvSource'
              : 'switchToIptvChannel';
          final deadline = d.timed
              .lastWhere(
                (v) =>
                    v.$1 == const Duration(milliseconds: 1500) &&
                    d.timerOwners[v.$2]!.contains(owner),
              )
              .$2;
          final animation = t
              .widget<TransitionOverlay>(find.byType(TransitionOverlay))
              .rainbowController;
          expect(animation.isAnimating, true);
          await d.timerAge(deadline, const Duration(milliseconds: 1499));
          expect(animation.isAnimating, true);
          expect(find.byType(TransitionOverlay), findsOneWidget);
          await d.timerAge(deadline, const Duration(milliseconds: 1500));
          expect(animation.isAnimating, false);
          expect(find.byType(TransitionOverlay), findsNothing);
          final before = d.timed.length;
          playing.suppress = false;
          d.player.emit('playing', true);
          await d.settle();
          expect(
            d.timed
                .skip(before)
                .where((v) => v.$1 == const Duration(seconds: 3)),
            isEmpty,
          );
          expect(d.errors, isEmpty);
        } finally {
          await d.close();
        }
      },
    );
  }
}
