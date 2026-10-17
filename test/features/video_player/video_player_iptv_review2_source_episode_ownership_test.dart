import 'support/iptv_storage_driver.dart';
import 'support/iptv_workflow_driver.dart';

void main() {
  testWidgets(
    'P15 review2 a manual source pick cancels the recovery episode and clears its pill',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      final live = await d.installAddon('source-episode');
      try {
        await d.mount([live], initialUrl: 'https://probe.test/first.ts');
        d.probeMode();
        d.player.emit('error', 'first disconnect');
        await d.f.until(t, () => d.opened.length == 2);
        await d.probeEvent('width');
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 350)),
        );
        d.player.emit('error', 'second disconnect');
        await d.settle();
        expect(find.text('Reconnecting…'), findsOneWidget);
        final pending = d.timed
            .lastWhere(
              (v) =>
                  v.$1 == const Duration(seconds: 1) &&
                  d.timerOwners[v.$2]!.contains('IptvLiveRecovery'),
            )
            .$2;
        final watchdog = d.timed
            .lastWhere(
              (v) =>
                  v.$1 == const Duration(seconds: 20) &&
                  d.timerOwners[v.$2]!.contains('IptvLiveRecovery'),
            )
            .$2;
        final sources = await d.sources();
        expect(pending.isActive, true);
        expect(watchdog.isActive, true);
        d.observe(
          () => sources.onSourceSelected(1, 'https://probe.test/second.ts'),
        );
        expect(pending.isActive, false);
        expect(watchdog.isActive, false);
        await d.f.until(t, () => d.opened.length == 3);
        await d.settle();
        expect(find.text('Reconnecting…'), findsNothing);
        await d.probeEvent('width');
        expect(d.errors, isEmpty);
      } finally {
        await d.probeEvent('width');
        await d.close();
      }
    },
  );

  testWidgets(
    'P15 review2 a late older source pick cannot overwrite the newer winner',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      final live = await d.installAddon('source-generation');
      final older = IptvAwaitDelivery('switchToIptvSource', (v) => v is bool);
      try {
        await d.mount([live], initialUrl: 'https://probe.test/first.ts');
        d.probeMode();
        final first = await d.sources();
        older.run(
          () => d.observe(
            () => first.onSourceSelected(1, 'https://probe.test/second.ts'),
          ),
        );
        await d.f.until(t, () => d.opened.length == 2);
        await d.settle();
        final second = await d.sources();
        d.observe(
          () => second.onSourceSelected(0, 'https://probe.test/first.ts'),
        );
        await d.f.until(t, () => d.opened.length == 3);
        await d.probeEvent('width');
        await d.f.until(t, () => older.pending.isNotEmpty);
        await d.settle();
        expect(
          StremioIptvService.instance.cachedWinner(live.url),
          'https://probe.test/first.ts',
        );
        older.release();
        await d.settle();
        expect(
          StremioIptvService.instance.cachedWinner(live.url),
          'https://probe.test/first.ts',
        );
        expect(d.playingUrl, 'https://probe.test/first.ts');
        expect(d.errors, isEmpty);
      } finally {
        older.release();
        await d.probeEvent('width');
        await d.close();
      }
    },
  );
}
