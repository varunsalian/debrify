import 'support/iptv_storage_driver.dart';
import 'support/iptv_workflow_driver.dart';

void main() {
  testWidgets(
    'P15 review2 a retune retires source rows before resolve and initially highlights row zero',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      final live = await d.installAddon('candidate-row-handoff');
      final delivery = IptvAwaitDelivery(
        'switchToIptvChannel',
        (v) => v is List<StremioIptvCandidate>,
      );
      Future<void>? tune;
      try {
        await d.mount([live], initialUrl: 'https://probe.test/first.ts');
        expect(playerControls(t).onShowStremioSources, isNotNull);
        final stops = d.calls('stop').length;
        final guide = await d.guide();
        d.probeMode();
        tune = delivery.run(
          () => d.observe(() => guide.onChannelSelected([live], 0)),
        );
        await d.f.until(t, () => delivery.pending.isNotEmpty);
        await d.settle();
        expect(playerControls(t).onShowStremioSources, isNull);
        expect(d.calls('stop'), hasLength(stops + 1));
        expect(d.opened, hasLength(1));
        delivery.release();
        await d.f.until(t, () => d.opened.length == 2);
        await d.settle();
        final sources = await d.sources();
        expect(
          sources.currentSourceIndex,
          0,
          reason: 'The first pending candidate owns the initial highlight',
        );
        expect(sources.sources, hasLength(2));
        sources.onClose();
        await d.probeEvent('width');
        await d.f.finish(t, tune!);
        expect(d.errors, isEmpty);
      } finally {
        delivery.release();
        await d.probeEvent('width');
        if (tune != null) await d.f.finish(t, tune);
        await d.close();
      }
    },
  );
}
