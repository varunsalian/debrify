import 'dart:async';
import 'package:debrify/features/video_player/models/vp_iptv_zap_page.dart';
import 'support/iptv_storage_driver.dart';
import 'support/iptv_workflow_driver.dart';

void main() {
  testWidgets(
    'P15 review2 a positive-offset prepend preserves fallback and next request coordinates',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      final window = [for (var i = 20; i < 35; i++) iptvChannel(i)];
      final tail = Completer<Map<String, dynamic>?>();
      var requests = 0;
      d.provider = (r) {
        if (r.containsKey('anchorUrl')) {
          return iptvPage(window, offset: 20, total: 100);
        }
        if (++requests > 1) return tail.future;
        return iptvPage(
          [
            for (var i = 10; i < 24; i++)
              IptvChannel(
                name: 'Fresh $i',
                url: 'https://p15.test/$i.ts',
                group: 'News',
                contentType: 'live',
              ),
          ],
          offset: 10,
          total: 100,
        );
      };
      try {
        await d.mount(window, index: 2, paged: true);
        await d.zap(-1);
        final sheet = await d.guide();
        expect(sheet.currentIndex, 11);
        expect(sheet.channels[sheet.currentIndex].name, 'Fresh 21');
        expect(d.playingUrl, window[1].url);
        await d.closeGuide(sheet);
        for (var i = 0; i < 3; i++) {
          await d.zap(1);
        }
        expect(d.browse.last['offset'], 35);
        expect(d.browse.last['category'], 'News');
        expect(requests, 2);
        expect(d.errors, isEmpty);
      } finally {
        if (!tail.isCompleted) tail.complete(null);
        await d.close();
      }
    },
  );

  testWidgets('P15 review2 a merge can move the playing identity to row zero', (
    t,
  ) async {
    final d = IptvWorkflowDriver(t);
    await d.initialize();
    final a = iptvChannel(0);
    final b = iptvChannel(1);
    final tail = Completer<Map<String, dynamic>?>();
    var requests = 0;
    d.provider = (r) => r.containsKey('anchorUrl')
        ? iptvPage([a, b], total: 100)
        : ++requests == 1
        ? iptvPage([b, a], total: 100)
        : tail.future;
    try {
      await d.mount([a, b], paged: true);
      await d.zap(1);
      final sheet = await d.guide();
      expect(sheet.channels.map((c) => c.url), [b.url, a.url]);
      expect(sheet.currentIndex, 0);
      expect(d.playingUrl, b.url);
      expect(d.errors, isEmpty);
    } finally {
      if (!tail.isCompleted) tail.complete(null);
      await d.close();
    }
  });

  testWidgets(
    'P15 review2 an already parsed same-category page cannot merge after paging retires',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      final window = [for (var i = 0; i < 30; i++) iptvChannel(i)];
      final movie = iptvChannel(80, live: false);
      final reply = Completer<Map<String, dynamic>?>();
      final delivery = IptvAwaitDelivery(
        '_prefetchIptvZapPage',
        (v) => v is VpIptvZapPage,
      );
      d.provider = (r) => r.containsKey('anchorUrl')
          ? iptvPage(window, total: 60, category: null, categories: [])
          : reply.future;
      try {
        await d.mount(window, index: 18, paged: true);
        await delivery.run(() => d.zap(1));
        reply.complete(
          iptvPage([iptvChannel(99)], category: null, categories: []),
        );
        await d.f.until(t, () => delivery.pending.isNotEmpty);
        await d.pick([movie], 0);
        delivery.release();
        await d.settle();
        final sheet = await d.guide();
        expect(sheet.channels.map((c) => c.url), [movie.url]);
        expect(d.playingUrl, movie.url);
        expect(playerControls(t).onNext, isNull);
        expect(d.errors, isEmpty);
      } finally {
        delivery.release();
        if (!reply.isCompleted) reply.complete(null);
        await d.close();
      }
    },
  );

  testWidgets(
    'P15 review2 airing programme in row zero switches from another row before Start Over',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      final target = iptvChannel(
        0,
        url: 'https://p15-airing-zero.test/live/u/p/123.ts',
      );
      final old = iptvChannel(1);
      d.response = iptvPanelReply;
      try {
        await d.mount([target, old], index: 1);
        final sheet = await d.guide();
        await d.f.finish(
          t,
          d.observe(
            () => sheet.onPlayProgramme!(target, iptvProgramme(airing: true)),
          ),
        );
        expect(d.opened, hasLength(3));
        expect(d.opened[1], target.url);
        expect(d.playingUrl, contains('/timeshift/'));
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P15 review2 an unlisted airing pick does not await an invalid switch before a queued guide pick',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      final old = iptvChannel(0);
      final target = iptvChannel(
        9,
        url: 'https://p15-unlisted-airing.test/live/u/p/123.ts',
      );
      d.response = iptvPanelReply;
      Future<void>? queued;
      try {
        await d.mount([old]);
        final sheet = await d.guide();
        scheduleMicrotask(() {
          queued = d.observe(() => sheet.onChannelSelected([target], 0));
        });
        await d.f.finish(
          t,
          d.observe(
            () => sheet.onPlayProgramme!(target, iptvProgramme(airing: true)),
          ),
        );
        await d.f.until(t, () => queued != null);
        await d.f.finish(t, queued!);
        await d.settle();
        expect(d.opened, hasLength(2));
        expect(d.playingUrl, target.url);
        expect(
          d.f.network.requests.where((r) => r.url.path.contains('/timeshift/')),
          isEmpty,
        );
        expect(d.errors, isEmpty);
      } finally {
        if (queued != null) await d.f.finish(t, queued!);
        await d.close();
      }
    },
  );
}
