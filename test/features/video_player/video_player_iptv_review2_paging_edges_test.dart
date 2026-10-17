import 'dart:async';
import 'package:debrify/features/video_player/models/vp_iptv_zap_page.dart';
import 'support/iptv_storage_driver.dart';
import 'support/iptv_workflow_driver.dart';
import 'support/local_completion_driver.dart';

void main() {
  testWidgets('P15 review2 empty category walk has a bounded request budget', (
    t,
  ) async {
    final d = IptvWorkflowDriver(t);
    await d.initialize();
    final live = iptvChannel(0);
    var requests = 0;
    d.provider = (r) {
      if (r.containsKey('anchorUrl')) {
        return iptvPage([live], categories: ['News', 'Empty']);
      }
      // A bad attempt counter must finish with an assertion, rather than
      // starving the test runner with an unbounded asynchronous walk.
      expect(++requests, lessThanOrEqualTo(2));
      return iptvPage(
        [],
        category: r['category'] as String?,
        categories: ['News', 'Empty'],
      );
    };
    try {
      await d.mount([live], paged: true);
      await d.zap(1);
      expect(requests, 2);
      expect(
        d.browse
            .where((r) => !r.containsKey('anchorUrl'))
            .map((r) => r['category']),
        ['Empty', 'News'],
      );
      expect(d.opened, [live.url]);
      expect(d.errors, isEmpty);
    } finally {
      await d.close();
    }
  });

  for (final malformed in [false, true]) {
    testWidgets(
      'P15 review2 missing offset alone defaults to zero malformed=$malformed',
      (t) async {
        final d = IptvWorkflowDriver(t);
        await d.initialize();
        final news = iptvChannel(0);
        final sports = iptvChannel(8, group: 'Sports');
        final tail = Completer<Map<String, dynamic>?>();
        var returned = false;
        d.provider = (r) {
          if (r.containsKey('anchorUrl')) {
            return iptvPage([news], categories: ['News', 'Sports']);
          }
          if (returned) return tail.future;
          returned = true;
          final result = iptvPage(
            [sports],
            total: 20,
            category: 'Sports',
            categories: ['News', 'Sports'],
          );
          if (malformed) {
            result['pageOffset'] = 'not a number';
          } else {
            result.remove('pageOffset');
          }
          return result;
        };
        try {
          await d.mount([news], paged: true);
          await d.zap(1);
          expect(d.playingUrl, sports.url);
          expect(d.browse.last['category'], 'Sports');
          expect(d.browse.last['offset'], 1);
          expect(d.errors, isEmpty);
        } finally {
          if (!tail.isCompleted) tail.complete(null);
          await d.close();
        }
      },
    );
  }

  testWidgets(
    'P15 review2 bootstrap during a held switch leaves an index that merge clamps',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      final a = iptvChannel(0);
      final b = iptvChannel(1);
      final response = Completer<Map<String, dynamic>?>();
      final tail = Completer<Map<String, dynamic>?>();
      final stop = CompletionDelivery('switchToIptvChannel', (v) => v == null);
      var anchors = 0;
      var requests = 0;
      d.provider = (r) {
        if (r.containsKey('anchorUrl')) {
          return ++anchors == 1 ? null : iptvPage([a], total: 2);
        }
        return ++requests == 1 ? response.future : tail.future;
      };
      try {
        await d.mount([a, b], paged: true);
        await stop.run(() => d.zap(1));
        await d.f.until(t, () => stop.pending.isNotEmpty && anchors == 2);
        await d.zap(1);
        expect(requests, 1);
        stop.release();
        await d.f.until(t, () => d.playingUrl == b.url);
        final early = await d.guide();
        expect(early.channels.map((c) => c.url), [a.url]);
        expect(early.currentIndex, 1);
        await d.closeGuide(early);
        response.complete(iptvPage([a], total: 2));
        await d.settle();
        final merged = await d.guide();
        expect(merged.currentIndex, 0);
        expect(merged.channels.map((c) => c.url), [a.url]);
        expect(requests, 2);
        expect(d.playingUrl, b.url);
        expect(d.errors, isEmpty);
      } finally {
        stop.release();
        if (!response.isCompleted) response.complete(null);
        if (!tail.isCompleted) tail.complete(null);
        await d.close();
      }
    },
  );

  testWidgets(
    'P15 review2 late category install clears a cache from a newer ring',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      final old = iptvChannel(0);
      final other = [
        iptvChannel(10, group: 'Other'),
        iptvChannel(11, group: 'Other'),
      ];
      final late = iptvChannel(20, group: 'Sports');
      final delivery = IptvAwaitDelivery(
        'requestAdjacentIptvCategory',
        (v) => v is VpIptvZapPage,
      );
      final tail = Completer<Map<String, dynamic>?>();
      d.provider = (r) {
        if (r.containsKey('anchorUrl')) {
          return iptvPage(
            r['anchorUrl'] == old.url ? [old] : other,
            category: r['anchorUrl'] == old.url ? 'News' : 'Other',
            categories: ['News', 'Sports', 'Third', 'Other', 'Fresh'],
          );
        }
        if (r['category'] == 'Sports') {
          return iptvPage(
            [late],
            category: 'Sports',
            categories: ['News', 'Sports', 'Third', 'Other', 'Fresh'],
          );
        }
        if (r['category'] == 'Fresh') {
          return iptvPage([iptvChannel(30, group: 'Fresh')], category: 'Fresh');
        }
        return tail.future;
      };
      try {
        await d.mount([old], paged: true);
        await delivery.run(() => d.zap(1));
        await d.f.until(t, () => delivery.pending.isNotEmpty);
        await d.pick(other, 0);
        await d.zap(1);
        expect(d.browse.where((r) => r['category'] == 'Fresh'), hasLength(1));
        delivery.release();
        await d.f.until(t, () => d.playingUrl == late.url);
        expect(
          d.browse.where(
            (r) => !r.containsKey('anchorUrl') && r['category'] == 'Third',
          ),
          hasLength(1),
        );
        expect(d.errors, isEmpty);
      } finally {
        delivery.release();
        if (!tail.isCompleted) tail.complete(null);
        await d.close();
      }
    },
  );
}
