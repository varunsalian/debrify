import 'dart:async';
import 'support/iptv_workflow_driver.dart';

void main() {
  for (final queued in [false, true]) {
    testWidgets(
      'P15 review2 a fetched category starts its next prefetch and drains queued=$queued input',
      (t) async {
        final d = IptvWorkflowDriver(t);
        await d.initialize();
        final live = iptvChannel(0);
        final sports = [
          iptvChannel(7, group: 'Sports'),
          iptvChannel(8, group: 'Sports'),
        ];
        final page = Completer<Map<String, dynamic>?>();
        final tail = Completer<Map<String, dynamic>?>();
        const categories = ['News', 'Sports'];
        var requests = 0;
        d.provider = (r) => r.containsKey('anchorUrl')
            ? iptvPage([live], categories: categories)
            : ++requests == 1
            ? page.future
            : tail.future;
        try {
          await d.mount([live], paged: true);
          await d.zap(1);
          if (queued) await d.zap(1);
          page.complete(
            iptvPage(sports, category: 'Sports', categories: categories),
          );
          await d.settle();
          expect(
            d.browse
                .where((r) => !r.containsKey('anchorUrl'))
                .map((r) => r['category']),
            ['Sports', 'News'],
          );
          expect(d.playingUrl, sports[queued ? 1 : 0].url);
          expect(d.errors, isEmpty);
        } finally {
          if (!page.isCompleted) page.complete(null);
          if (!tail.isCompleted) tail.complete(null);
          await d.close();
        }
      },
    );
  }
  testWidgets(
    'P15 review2 an exhausted empty category walk cannot replay its queue on a fresh landing',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      final live = iptvChannel(0);
      final sports = [
        iptvChannel(7, group: 'Sports'),
        iptvChannel(8, group: 'Sports'),
      ];
      final first = Completer<Map<String, dynamic>?>();
      final tail = Completer<Map<String, dynamic>?>();
      const categories = ['News', 'Sports'];
      var requests = 0;
      d.provider = (r) {
        if (r.containsKey('anchorUrl')) {
          return iptvPage([live], categories: categories);
        }
        return switch (++requests) {
          1 => first.future,
          2 => iptvPage([], category: 'News', categories: categories),
          3 => iptvPage(sports, category: 'Sports', categories: categories),
          _ => tail.future,
        };
      };
      try {
        await d.mount([live], paged: true);
        await d.zap(1);
        await d.zap(1);
        first.complete(
          iptvPage([], category: 'Sports', categories: categories),
        );
        await d.settle();
        expect(requests, 2);
        expect(d.playingUrl, live.url);
        await d.zap(1);
        await d.settle();
        expect(d.playingUrl, sports.first.url);
        expect(d.errors, isEmpty);
      } finally {
        if (!first.isCompleted) first.complete(null);
        if (!tail.isCompleted) tail.complete(null);
        await d.close();
      }
    },
  );
}
