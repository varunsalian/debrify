import 'support/iptv_storage_driver.dart';
import 'support/iptv_workflow_driver.dart';

void main() {
  for (final archive in [false, true]) {
    testWidgets(
      'P15 review2 a visible dock metadata retry respects capability=$archive and its deadline',
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
        )..armed = false;
        final initial = IptvAwaitDelivery(
          'loadIptvZapBannerEpg',
          (v) => v is EpgNowNext,
        );
        d.response = (r) => iptvPanelReply(r, archive: archive);
        try {
          await read.run(() => initial.run(() => d.mount([live])));
          await d.f.until(t, () => initial.pending.isNotEmpty);
          expect(initial.pending, hasLength(1));
          // Warm UI may already report loading=false. Release the actual
          // enrichment return so its synchronous retry-deadline assignment
          // has run before checking the retry predicate.
          initial.release();
          await d.settle();
          await d.f.until(
            t,
            () => d.banners.any((v) => !v.epgLoading && v.epg?.now != null),
          );
          expect(d.banners.first.epg!.now!.hasArchive, archive);
          await read.run(
            () => d.observe(() => t.tapAt(const Offset(600, 300))),
          );
          await d.advance(const Duration(milliseconds: 400));
          expect(d.banners.any((v) => v.flush), true);
          expect(
            d.periodic.where(
              (v) => v.$1 == const Duration(seconds: 1) && v.$2.isActive,
            ),
            hasLength(1),
          );
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
          expect(
            d.periodic.where(
              (v) => v.$1 == const Duration(seconds: 1) && v.$2.isActive,
            ),
            hasLength(1),
          );
          // Timer callbacks retain their creation zone. Install the read
          // observer at mount/dock creation, then arm it for this tick.
          final requests = d.f.network.requests
              .where((r) => r.url.host == 'p15-retry-policy-$archive.test')
              .length;
          read.armed = true;
          await d.advance(const Duration(seconds: 1));
          await d.settle();
          expect(
            d.f.network.requests.where(
              (r) => r.url.host == 'p15-retry-policy-$archive.test',
            ),
            hasLength(requests),
            reason: 'A blocked retry must not issue another metadata request',
          );
          expect(read.pending, isEmpty);
          expect(d.banners.any((v) => v.epgLoading), false);
          expect(d.errors, isEmpty);
        } finally {
          initial.release();
          read.release();
          await d.close();
        }
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  }
}
