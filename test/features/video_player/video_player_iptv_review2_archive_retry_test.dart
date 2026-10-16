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
        final before = DateTime.now();
        delivery.release();
        await d.settle();
        final after = DateTime.now();
        if (after.difference(before) >= const Duration(seconds: 1)) {
          throw StateError(
            'CLOCK_WINDOW_PRECONDITION: initial result delivery took too long',
          );
        }
        delivery.armed = true;
        final target = DateTime.fromMicrosecondsSinceEpoch(
          (after.add(const Duration(seconds: 60)).microsecondsSinceEpoch +
                  before
                      .add(const Duration(seconds: 61))
                      .microsecondsSinceEpoch) ~/
              2,
        );
        await t.runAsync(() async {
          await Future<void>.delayed(const Duration(seconds: 59));
          final remaining = target.difference(DateTime.now());
          if (remaining > Duration.zero) {
            await Future<void>.delayed(remaining);
          }
        });
        retry = true;
        IptvEpgService.instance.debugAgeNowNext(
          live.url,
          const Duration(minutes: 10),
        );
        final tick = DateTime.now();
        await d.advance(const Duration(seconds: 1));
        final tickEnd = DateTime.now();
        if (!tick.isAfter(after.add(const Duration(seconds: 60))) ||
            !tickEnd.isBefore(before.add(const Duration(seconds: 61)))) {
          throw StateError(
            'CLOCK_WINDOW_PRECONDITION: ticker missed the 60-to-61 second window',
          );
        }
        // Poll I/O with zero fake-time advancement: a 61-second mutant must
        // not get another ticker opportunity while this assertion is pending.
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
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
