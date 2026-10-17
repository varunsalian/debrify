import 'support/iptv_storage_driver.dart';
import 'support/iptv_workflow_driver.dart';

void main() {
  testWidgets(
    'P15 review2 a non-live zap retires the floating identity after its fade',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      try {
        await d.mount([iptvChannel(0), iptvChannel(1, live: false)]);
        expect(d.banners.where((v) => !v.flush), isNotEmpty);
        await d.zap(1);
        await d.advance(const Duration(milliseconds: 400));
        expect(d.banners.where((v) => !v.flush), isEmpty);
        expect(
          d.timed.where(
            (v) => v.$1 == const Duration(milliseconds: 4500) && v.$2.isActive,
          ),
          isEmpty,
        );
        expect(
          d.periodic.where(
            (v) => v.$1 == const Duration(seconds: 1) && v.$2.isActive,
          ),
          isEmpty,
        );
        expect(d.playingUrl, 'https://p15.test/1.ts');
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );
  testWidgets(
    'P15 review2 warm incoming banner clears an outgoing loading state before metadata delivery',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      final old = iptvChannel(
        0,
        url: 'https://p15-loading-old.test/live/u/p/123.ts',
      );
      final warm = iptvChannel(
        1,
        url: 'https://p15-loading-warm.test/live/u/p/124.ts',
      );
      d.response = (r) => iptvPanelReply(
        r,
        title: r.url.host.contains('warm') ? 'Warm guide' : 'Old guide',
      );
      final first = IptvAwaitDelivery(
        'loadIptvZapBannerEpg',
        (v) => v is EpgNowNext,
      );
      final second = IptvAwaitDelivery(
        'loadIptvZapBannerEpg',
        (v) => v is EpgNowNext,
      );
      try {
        await d.f.finish(
          t,
          IptvEpgService.instance.nowNextWithCatchupMetadata(warm.url),
        );
        await first.run(() => d.mount([old, warm]));
        await d.f.until(t, () => first.pending.isNotEmpty);
        expect(
          d.banners
              .where((v) => v.channel.url == old.url)
              .every((v) => v.epgLoading),
          true,
        );
        await second.run(() => d.zap(1));
        await d.f.until(t, () => second.pending.isNotEmpty);
        var incoming = d.banners
            .where((v) => v.channel.url == warm.url)
            .toList();
        expect(incoming, isNotEmpty);
        expect(incoming.every((v) => !v.epgLoading), true);
        first.release();
        await d.settle();
        incoming = d.banners.where((v) => v.channel.url == warm.url).toList();
        expect(incoming.every((v) => v.epg?.now?.title == 'Warm guide'), true);
        second.release();
        await d.settle();
        expect(d.errors, isEmpty);
      } finally {
        first.release();
        second.release();
        await d.close();
      }
    },
  );

  testWidgets(
    'P15 review2 a first live identity starts its clock when the dock already owns the screen',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      final movie = iptvChannel(0, live: false);
      final live = iptvChannel(1);
      final stop = IptvAwaitDelivery('switchToIptvChannel', (v) => v == null);
      Future<void>? tune;
      try {
        await d.mount([movie]);
        final guide = await d.guide();
        tune = stop.run(
          () => d.observe(() => guide.onChannelSelected([live], 0)),
        );
        await d.f.until(t, () => stop.pending.isNotEmpty);
        await d.closeGuide(guide);
        await d.observe(() => t.tapAt(const Offset(600, 300)));
        await d.advance(const Duration(milliseconds: 400));
        expect(
          d.periodic.where(
            (v) => v.$1 == const Duration(seconds: 1) && v.$2.isActive,
          ),
          isEmpty,
        );
        stop.release();
        await d.f.finish(t, tune!);
        await d.settle();
        expect(d.banners.where((v) => v.flush), isNotEmpty);
        expect(d.banners.where((v) => !v.flush), isEmpty);
        expect(
          d.periodic.where(
            (v) => v.$1 == const Duration(seconds: 1) && v.$2.isActive,
          ),
          hasLength(1),
        );
        expect(d.errors, isEmpty);
      } finally {
        stop.release();
        if (tune != null) await d.f.finish(t, tune);
        await d.close();
      }
    },
  );

  testWidgets(
    'P15 review2 a quiet Stremio recovery cannot re-raise the expired floating banner',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      final live = await d.installAddon('quiet-banner');
      try {
        await d.mount([live], initialUrl: 'https://probe.test/first.ts');
        await d.advance(const Duration(seconds: 5));
        await d.advance(const Duration(milliseconds: 400));
        expect(d.banners.where((v) => !v.flush), isEmpty);
        d.probeMode();
        d.player.emit('error', 'network connection reset');
        await d.f.until(t, () => d.opened.length == 2);
        await d.settle();
        expect(d.banners.where((v) => !v.flush), isEmpty);
        await d.probeEvent('width');
        await d.settle();
        expect(d.banners.where((v) => !v.flush), isEmpty);
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );
}
