import 'support/iptv_workflow_driver.dart';

void main() {
  for (final scenario in [
    (name: 'null width', width: true, value: null, accepted: false),
    (name: 'zero width', width: true, value: 0, accepted: false),
    (name: 'one pixel width', width: true, value: 1, accepted: true),
    (name: 'zero position', width: false, value: 0, accepted: false),
    (name: 'negative position', width: false, value: -1, accepted: false),
    (name: 'positive position', width: false, value: 1, accepted: true),
  ]) {
    testWidgets(
      'P15 review2 candidate probe accepts only positive ${scenario.name}',
      (t) async {
        final d = IptvWorkflowDriver(t);
        await d.initialize();
        final live = await d.installAddon(
          'probe-edge-${scenario.name.replaceAll(' ', '-')}',
        );
        var completed = false;
        try {
          final channels = [iptvChannel(0), live];
          await d.mount(channels);
          d.probeMode();
          final guide = await d.guide();
          final tune = d.observe(
            () => guide
                .onChannelSelected(channels, 1)
                .then((_) => completed = true),
          );
          await d.f.until(t, () => d.opened.length == 2);
          await d.settle();
          if (scenario.width) {
            d.player.emit<int?>('width', scenario.value);
          } else {
            d.player.emit('position', Duration(microseconds: scenario.value!));
          }
          await d.settle();
          expect(completed, scenario.accepted);
          expect(
            StremioIptvService.instance.cachedWinner(live.url),
            scenario.accepted ? 'https://probe.test/first.ts' : isNull,
          );
          if (!scenario.accepted) await d.probeEvent('width');
          await d.f.finish(t, tune);
          expect(d.opened, hasLength(2));
          expect(d.errors, isEmpty);
        } finally {
          await d.close();
        }
      },
    );
  }

  testWidgets(
    'P15 review2 a source probe completed after disposal cannot mark its winner',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      final live = await d.installAddon('source-probe-dispose');
      try {
        await d.mount([live], initialUrl: 'https://probe.test/first.ts');
        final sources = await d.sources();
        d.probeMode();
        d.observe(
          () => sources.onSourceSelected(1, 'https://probe.test/second.ts'),
        );
        await d.f.until(t, () => d.opened.length == 2);
        await d.settle();
        await d.retire();
        d.player.emit<int?>('width', 1280);
        await d.settle();
        expect(StremioIptvService.instance.cachedWinner(live.url), isNull);
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );
}
