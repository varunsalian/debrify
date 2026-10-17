import 'support/iptv_storage_driver.dart';
import 'support/iptv_workflow_driver.dart';

void main() {
  testWidgets('P15 review2 first archive upgrade has no retry deadline yet', (
    t,
  ) async {
    final d = IptvWorkflowDriver(t);
    await d.initialize();
    final live = iptvChannel(
      0,
      url: 'https://p15-first-upgrade.test/live/u/p/123.ts',
    );
    final delivery = IptvAwaitDelivery(
      'loadIptvZapBannerEpg',
      (v) => v is EpgNowNext,
    );
    d.response = (r) => iptvPanelReply(r, archive: false);
    try {
      await d.f.finish(t, IptvEpgService.instance.nowNext(live.url));
      await delivery.run(() => d.mount([live]));
      await d.f.until(t, () => delivery.pending.isNotEmpty);
      delivery.armed = true;
      await d.observe(() => t.tapAt(const Offset(600, 300)));
      await d.advance(const Duration(milliseconds: 400));
      await d.advance(const Duration(seconds: 1));
      await d.settle();
      expect(delivery.pending, hasLength(1));
      expect(d.banners.any((b) => b.epgLoading), false);
      expect(d.errors, isEmpty);
    } finally {
      delivery.release();
      await d.close();
    }
  });

  testWidgets(
    'P15 review2 an expired programme refresh has only one metadata read',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      final live = iptvChannel(
        0,
        url: 'https://p15-expired-read.test/live/u/p/123.ts',
      );
      final delivery = IptvAwaitDelivery(
        'loadIptvZapBannerEpg',
        (v) => v is EpgNowNext,
        skip: 1,
      );
      d.response = (r) => iptvPanelReply(
        r,
        stop: DateTime.now().add(const Duration(seconds: 5)),
      );
      try {
        await delivery.run(() => d.mount([live]));
        await d.observe(() => t.tapAt(const Offset(600, 300)));
        await d.advance(const Duration(milliseconds: 400));
        IptvEpgService.instance.debugAgeNowNext(
          live.url,
          const Duration(minutes: 10),
        );
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5100)),
        );
        await d.advance(const Duration(seconds: 1));
        await d.f.until(t, () => delivery.pending.isNotEmpty);
        expect(d.banners.any((b) => b.epgLoading), true);
        delivery.armed = true;
        await d.advance(const Duration(seconds: 1));
        await d.settle();
        expect(delivery.pending, hasLength(1));
        expect(d.errors, isEmpty);
      } finally {
        delivery.release();
        await d.close();
      }
    },
  );
}
