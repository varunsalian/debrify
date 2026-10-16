import 'package:debrify/services/storage/iptv_last_channel_storage.dart';
import 'support/iptv_storage_driver.dart';
import 'support/iptv_workflow_driver.dart';

void main() {
  for (final live in [false, true]) {
    testWidgets(
      'P15 review2 an old settle timer cannot remember an adopted unplayed row live=$live',
      (t) async {
        final d = IptvWorkflowDriver(t);
        await d.initialize();
        final old = iptvChannel(0);
        final incoming = iptvChannel(1, live: live, url: live ? null : old.url);
        final stop = IptvAwaitDelivery('switchToIptvChannel', (v) => v == null);
        Future<void>? tune;
        try {
          await d.mount([old]);
          await d.f.finish(
            t,
            IptvLastChannelStorage.clearIptvLastLiveChannel(),
          );
          d.observe(() => d.player.emit('playing', true));
          await d.settle();
          final timer = d.timed
              .lastWhere(
                (v) => d.timerOwners[v.$2]!.contains('noteLiveChannelPlaying'),
              )
              .$2;
          expect(timer.isActive, true);
          final guide = await d.guide();
          tune = stop.run(
            () => d.observe(() => guide.onChannelSelected([incoming], 0)),
          );
          await d.f.until(t, () => stop.pending.isNotEmpty);
          expect(d.opened, [old.url]);
          await d.timerAge(timer, const Duration(seconds: 1));
          await d.settle();
          expect(
            await d.f.finish(
              t,
              IptvLastChannelStorage.getIptvLastLiveChannel(),
            ),
            isNull,
          );
          expect(d.opened, [old.url]);
          expect(d.errors, isEmpty);
          stop.release();
          await d.f.finish(t, tune!);
        } finally {
          stop.release();
          if (tune != null) await d.f.finish(t, tune);
          await d.close();
        }
      },
    );
  }
}
