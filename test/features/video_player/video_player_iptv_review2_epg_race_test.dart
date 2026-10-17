import 'support/iptv_storage_driver.dart';
import 'support/iptv_workflow_driver.dart';

void main() {
  testWidgets(
    'P15 review2 an expired warm EPG upgrade cannot clear a newer refresh loading flag',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      final live = iptvChannel(
        0,
        url: 'https://p15-epg-loading-race.test/live/u/p/123.ts',
        attributes: {'tv_archive': '1'},
      );
      d.response = (r) => iptvPanelReply(
        r,
        stop: DateTime.now().add(const Duration(seconds: 6)),
      );
      final delivery = IptvAwaitDelivery(
        'loadIptvZapBannerEpg',
        (v) => v is EpgNowNext,
      );
      try {
        final known = await d.f.finish(
          t,
          IptvEpgService.instance.nowNext(live.url),
        );
        expect(known.now, isNotNull);
        await delivery.run(() => d.mount([live]));
        await d.f.until(t, () => delivery.pending.length == 1);
        expect(d.banners.first.epgLoading, false);
        final wait =
            known.now!.stop.difference(DateTime.now()) +
            const Duration(milliseconds: 100);
        if (wait.isNegative) {
          throw StateError('Original warm EPG window already expired');
        }
        await t.runAsync(() => Future<void>.delayed(wait));
        delivery.armed = true;
        await d.advance(const Duration(seconds: 1));
        await d.f.until(t, () => delivery.pending.length == 2);
        expect(d.banners.first.epgLoading, true);
        delivery.pending.removeAt(0)();
        await d.settle();
        expect(
          d.banners.first.epgLoading,
          true,
          reason:
              'The newer refresh still owns loading while its delivery is held',
        );
        delivery.release();
        await d.settle();
        expect(d.banners.first.epgLoading, false);
        expect(d.errors, isEmpty);
      } finally {
        delivery.release();
        await d.close();
      }
    },
  );
}
