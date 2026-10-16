import 'dart:async';
import 'support/iptv_workflow_driver.dart';

void main() {
  testWidgets(
    'P15 review2 a drain leaves remaining presses for the page its first press requested',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      final first = Completer<Map<String, dynamic>?>();
      final second = Completer<Map<String, dynamic>?>();
      var requests = 0;
      d.provider = (r) => r.containsKey('anchorUrl')
          ? iptvPage([iptvChannel(0)], total: 4, category: null, categories: [])
          : ++requests == 1
          ? first.future
          : second.future;
      try {
        await d.mount([iptvChannel(0)], paged: true);
        for (var i = 0; i < 3; i++) {
          await d.zap(1);
        }
        first.complete(
          iptvPage(
            [iptvChannel(1), iptvChannel(2)],
            offset: 1,
            total: 4,
            category: null,
            categories: [],
          ),
        );
        await d.f.until(
          t,
          () => requests == 2 && d.playingUrl == iptvChannel(1).url,
        );
        second.complete(
          iptvPage(
            [iptvChannel(3)],
            offset: 3,
            total: 4,
            category: null,
            categories: [],
          ),
        );
        await d.settle();
        // Original same-turn drains share the old index; the two remaining
        // presses therefore coalesce at row two after the second page arrives.
        expect(d.playingUrl, iptvChannel(2).url);
        expect(
          d.browse
              .where((r) => !r.containsKey('anchorUrl'))
              .map((r) => r['offset']),
          [1, 3],
        );
        expect(d.errors, isEmpty);
      } finally {
        if (!first.isCompleted) first.complete(null);
        if (!second.isCompleted) second.complete(null);
        await d.close();
      }
    },
  );
  testWidgets(
    'P15 review2 a cached adjacent page suppresses duplicate prefetches inside the current window',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      final rows = [iptvChannel(0), iptvChannel(1), iptvChannel(2)];
      var requests = 0;
      d.provider = (r) {
        if (r.containsKey('anchorUrl')) {
          return iptvPage(rows, categories: ['News', 'Sports']);
        }
        requests++;
        return iptvPage(
          [iptvChannel(7, group: 'Sports'), iptvChannel(8, group: 'Sports')],
          category: 'Sports',
          categories: ['News', 'Sports'],
        );
      };
      try {
        await d.mount(rows, paged: true);
        await d.zap(1);
        await d.settle();
        expect(requests, 1);
        await d.zap(1);
        await d.settle();
        expect(d.playingUrl, rows.last.url);
        expect(requests, 1);
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );
}
