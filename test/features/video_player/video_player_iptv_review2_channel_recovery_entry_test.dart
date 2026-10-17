import 'support/iptv_storage_driver.dart';
import 'support/iptv_workflow_driver.dart';

void main() {
  testWidgets(
    'P15 review2 a real channel zap retires active Start Over state',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      final live = iptvChannel(
        0,
        url: 'https://p15-zap-archive.test/live/u/p/123.ts',
        attributes: {'tv_archive': '1'},
      );
      final channels = [live, iptvChannel(1)];
      d.response = iptvPanelReply;
      try {
        await d.mount(channels);
        final sheet = await d.guide();
        await d.f.finish(
          t,
          d.observe(
            () => sheet.onPlayProgramme!(live, iptvProgramme(airing: true)),
          ),
        );
        expect(playerControls(t).liveEdgeActionActive, true);
        await d.zap(1);
        expect(d.playingUrl, channels.last.url);
        expect(playerControls(t).liveEdgeActionActive, false);
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );
  testWidgets(
    'P15 review2 a channel zap retires recovery before recording stop delivers',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      final live = await d.installAddon('channel-recovery-entry');
      final stop = IptvAwaitDelivery('switchToIptvChannel', (v) => v == null);
      try {
        await d.mount([
          live,
          iptvChannel(1),
        ], initialUrl: 'https://probe.test/first.ts');
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
        expect(pending.isActive, true);
        await stop.run(() => d.zap(1));
        await d.f.until(t, () => stop.pending.isNotEmpty);
        expect(pending.isActive, false);
        expect(find.text('Reconnecting…'), findsNothing);
        stop.release();
        await d.settle();
        expect(d.errors, isEmpty);
      } finally {
        stop.release();
        await d.probeEvent('width');
        await d.close();
      }
    },
  );
}
