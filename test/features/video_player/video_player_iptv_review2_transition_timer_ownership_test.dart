import 'support/iptv_workflow_driver.dart';
import 'video_player_iptv_review2_resource_deadlines_test.dart'
    show PlayingDelivery;

void main() {
  for (final sourcePick in [false, true]) {
    testWidgets(
      'P15 review2 owner cleanup cancels both listener reveal timers sourcePick=$sourcePick',
      (t) async {
        final playing = PlayingDelivery();
        final d = IptvWorkflowDriver(
          t,
          configurePlayer: (p) => p.events['playing'] = playing,
        );
        await d.initialize();
        final live = sourcePick
            ? await d.installAddon('timer-ownership')
            : iptvChannel(1);
        try {
          await d.mount(
            sourcePick ? [live] : [iptvChannel(0), live],
            initialUrl: sourcePick ? 'https://probe.test/first.ts' : null,
          );
          playing.suppress = true;
          final gate = d.holdOperation('open');
          final before = d.timed.length;
          if (sourcePick) {
            final sources = await d.sources();
            d.probeMode();
            d.observe(
              () => sources.onSourceSelected(1, 'https://probe.test/second.ts'),
            );
          } else {
            await d.zap(1);
          }
          await d.f.until(t, () => d.opened.length == 2);
          playing.suppress = false;
          d.player.emit('playing', true);
          await d.settle();
          playing.suppress = true;
          final listenerTimers = d.timed
              .skip(before)
              .where(
                (v) =>
                    d.timerOwners[v.$2]!.contains(
                      'bindPlayerInstanceSubscriptions',
                    ) &&
                    [
                      const Duration(milliseconds: 1500),
                      const Duration(seconds: 3),
                    ].contains(v.$1),
              )
              .toList();
          expect(listenerTimers.map((v) => v.$1).toSet(), {
            const Duration(milliseconds: 1500),
            const Duration(seconds: 3),
          });
          expect(listenerTimers.every((v) => v.$2.isActive), true);
          gate.complete();
          await d.settle();
          if (sourcePick) await d.probeEvent('width');
          await d.settle();
          expect(
            listenerTimers.where((v) => v.$2.isActive),
            isEmpty,
            reason: 'The explicit owner replaces both listener timers',
          );
          expect(d.errors, isEmpty);
        } finally {
          playing.suppress = false;
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
