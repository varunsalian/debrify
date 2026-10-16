import 'dart:async';
import 'package:debrify/features/video_player/models/vp_iptv_zap_page.dart';
import 'support/iptv_storage_driver.dart';
import 'support/iptv_workflow_driver.dart';

void main() {
  testWidgets(
    'P15 review2 queued live presses stop when their first page lands on demand',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      final initial = iptvChannel(0);
      final movie = iptvChannel(1, live: false);
      final tail = iptvChannel(2);
      final first = Completer<Map<String, dynamic>?>();
      final second = Completer<Map<String, dynamic>?>();
      var requests = 0;
      d.provider = (r) => r.containsKey('anchorUrl')
          ? iptvPage([initial], total: 3)
          : ++requests == 1
          ? first.future
          : requests == 2
          ? second.future
          : null;
      try {
        await d.mount([initial], paged: true);
        await d.zap(1);
        await d.zap(1);
        first.complete(iptvPage([movie], offset: 1, total: 3));
        await d.f.until(t, () => d.playingUrl == movie.url && requests == 2);
        await d.settle();
        expect(playerControls(t).onNext, isNull);
        second.complete(iptvPage([tail], offset: 2, total: 3));
        await d.settle();
        expect(d.playingUrl, movie.url);
        expect(d.opened, [initial.url, movie.url]);
        expect(d.errors, isEmpty);
      } finally {
        if (!first.isCompleted) first.complete(null);
        if (!second.isCompleted) second.complete(null);
        await d.close();
      }
    },
  );
  for (final delta in [-1, 1]) {
    testWidgets(
      'P15 review2 an empty parsed prefetch rechecks a new same-category window delta=$delta',
      (t) async {
        final d = IptvWorkflowDriver(t);
        await d.initialize();
        final initial = [iptvChannel(0), iptvChannel(1)];
        final incoming = [iptvChannel(7), iptvChannel(8)];
        const categories = ['News', 'Sports', 'Movies'];
        final parsed = IptvAwaitDelivery(
          'prefetchAdjacentIptvCategory',
          (v) => v is VpIptvZapPage && v.channels.isEmpty,
        );
        var requests = 0;
        d.provider = (r) {
          if (r.containsKey('anchorUrl')) {
            final first = r['anchorUrl'] != incoming.first.url;
            return iptvPage(
              first ? initial : incoming,
              offset: first || delta > 0 ? 0 : 5,
              total: first ? 2 : 10,
              categories: categories,
            );
          }
          requests++;
          return requests == 1
              ? iptvPage(
                  [],
                  category: r['category'] as String?,
                  categories: categories,
                )
              : null;
        };
        try {
          await d.mount(initial, index: delta > 0 ? 0 : 1, paged: true);
          await parsed.run(() => d.zap(delta));
          await d.f.until(t, () => parsed.pending.isNotEmpty);
          expect(requests, 1);
          await d.pick(incoming, 0);
          expect(d.playingUrl, incoming.first.url);
          final before = requests;
          parsed.release();
          await d.settle();
          expect(
            requests,
            before,
            reason:
                'A stale empty-category retry must respect the new page bounds',
          );
          expect(d.errors, isEmpty);
        } finally {
          parsed.release();
          await d.close();
        }
      },
    );
  }

  testWidgets(
    'P15 review2 adjacent prefetch delivery drains a boundary press queued while it loaded',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      final initial = [iptvChannel(0), iptvChannel(1)];
      final sports = [
        iptvChannel(8, group: 'Sports'),
        iptvChannel(9, group: 'Sports'),
      ];
      final page = Completer<Map<String, dynamic>?>();
      const categories = ['News', 'Sports'];
      d.provider = (r) => r.containsKey('anchorUrl')
          ? iptvPage(initial, categories: categories)
          : r['category'] == 'Sports'
          ? page.future
          : null;
      try {
        await d.mount(initial, paged: true);
        await d.zap(1);
        await d.zap(1);
        expect(d.playingUrl, initial.last.url);
        page.complete(
          iptvPage(sports, category: 'Sports', categories: categories),
        );
        await d.settle();
        expect(d.playingUrl, sports.first.url);
        expect(d.errors, isEmpty);
      } finally {
        if (!page.isCompleted) page.complete(null);
        await d.close();
      }
    },
  );
}
