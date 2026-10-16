import 'support/iptv_storage_driver.dart';
import 'support/iptv_workflow_driver.dart';

void main() {
  for (final archive in [false, true]) {
    testWidgets(
      'P15 review2 archive metadata retry respects capability=$archive and its deadline',
      (t) async {
        final d = IptvWorkflowDriver(t);
        await d.initialize();
        final live = iptvChannel(
          0,
          url: 'https://p15-retry-policy-$archive.test/live/u/p/123.ts',
        );
        final read = IptvAwaitDelivery(
          'loadIptvZapBannerEpg',
          (v) => v is EpgNowNext,
        );
        d.response = (r) => iptvPanelReply(r, archive: archive);
        try {
          await d.mount([live]);
          await d.f.until(
            t,
            () => d.banners.any((v) => !v.epgLoading && v.epg?.now != null),
          );
          expect(d.banners.first.epg!.now!.hasArchive, archive);
          if (archive) {
            // An available archive does not need the missing-capability retry,
            // even after its real 60-second deadline. Programme expiry is far
            // later, so only that retry predicate could start another read.
            await t.runAsync(
              () => Future<void>.delayed(const Duration(seconds: 61)),
            );
          }
          IptvEpgService.instance.debugAgeNowNext(
            live.url,
            const Duration(minutes: 10),
          );
          await read.run(() => d.advance(const Duration(seconds: 1)));
          await d.settle();
          expect(read.pending, isEmpty);
          expect(d.banners.any((v) => v.epgLoading), false);
          expect(d.errors, isEmpty);
        } finally {
          read.release();
          await d.close();
        }
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  }
}
