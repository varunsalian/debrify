import 'support/iptv_workflow_driver.dart';
import 'support/iptv_storage_driver.dart';

void main() {
  testWidgets(
    'P15 review2 archive metadata retries after sixty real seconds without programme expiry',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      final live = iptvChannel(
        0,
        url: 'https://p15-retry-clock.test/live/u/p/123.ts',
      );
      final delivery = IptvAwaitDelivery(
        'loadIptvZapBannerEpg',
        (v) => v is EpgNowNext,
      );
      var retry = false;
      d.response = (r) => iptvPanelReply(
        r,
        archive: false,
        title: retry ? 'Retry result' : 'Original result',
        stop: DateTime.now().add(const Duration(days: 1)),
      );
      try {
        await d.f.finish(t, IptvEpgService.instance.nowNext(live.url));
        await delivery.run(() => d.mount([live]));
        await d.f.until(t, () => delivery.pending.isNotEmpty);
        await d.observe(() => t.tapAt(const Offset(600, 300)));
        await d.advance(const Duration(milliseconds: 400));
        // A warm programme must not retry before the first upgrade completes.
        await d.advance(const Duration(seconds: 1));
        expect(delivery.pending, hasLength(1));
        expect(d.banners.any((b) => b.epgLoading), false);
        delivery.release();
        await d.settle();
        // Wait from completed delivery, which is later than the production
        // deadline write. Scheduler delays can only move this tick farther
        // past the deadline; they cannot invalidate a one-second test window.
        final delivered = DateTime.now();
        delivery.armed = true;
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 60200)),
        );
        expect(
          DateTime.now().difference(delivered),
          greaterThanOrEqualTo(const Duration(seconds: 60)),
        );
        retry = true;
        IptvEpgService.instance.debugAgeNowNext(
          live.url,
          const Duration(minutes: 10),
        );
        await d.advance(const Duration(seconds: 1));
        // Poll I/O without advancing fake time, so only the observed tick can
        // admit this retry. Exact 60-versus-61-second discrimination remains
        // device-pending: a loaded host cannot promise that narrow window.
        for (var i = 0; i < 100 && delivery.pending.isEmpty; i++) {
          await t.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await t.pump();
        }
        expect(delivery.pending, isNotEmpty);
        expect(d.banners.any((b) => b.epgLoading), true);
        delivery.release();
        await d.settle();
        // The service's enriched cache still owns the title at this boundary.
        expect(d.banners.first.epg?.now?.title, 'Original result');
        expect(d.banners.any((b) => b.epgLoading), false);
        expect(d.errors, isEmpty);
      } finally {
        delivery.release();
        await d.close();
      }
    },
    timeout: const Timeout(Duration(minutes: 15)),
  );
}
