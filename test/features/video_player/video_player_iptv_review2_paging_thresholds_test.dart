import 'dart:async';
import 'support/iptv_workflow_driver.dart';

void main() {
  const scenarios = [
    (
      name: 'backward boundary at offset one',
      offset: 1,
      index: 0,
      delta: -1,
      queued: true,
      requestOffset: 0,
    ),
    (
      name: 'backward prefetch at offset one',
      offset: 1,
      index: 1,
      delta: -1,
      queued: false,
      requestOffset: 0,
    ),
    (
      name: 'backward prefetch beyond page size',
      offset: 1501,
      index: 1,
      delta: -1,
      queued: false,
      requestOffset: 1,
    ),
    (
      name: 'forward final unloaded row',
      offset: 0,
      index: 1,
      delta: 1,
      queued: true,
      requestOffset: 2,
    ),
  ];
  for (final s in scenarios) {
    testWidgets('P15 review2 paging threshold ${s.name}', (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      final window = [iptvChannel(s.offset), iptvChannel(s.offset + 1)];
      final total = s.delta > 0 ? 3 : s.offset + window.length;
      final response = Completer<Map<String, dynamic>?>();
      const categories = ['News', 'Sports'];
      d.provider = (r) => r.containsKey('anchorUrl')
          ? iptvPage(
              window,
              offset: s.offset,
              total: total,
              categories: categories,
            )
          : r['category'] == 'News'
          ? response.future
          : iptvPage(
              [iptvChannel(99, group: 'Sports')],
              category: 'Sports',
              categories: categories,
            );
      try {
        await d.mount(window, index: s.index, paged: true);
        await d.zap(s.delta);
        final requests = d.browse
            .where((r) => !r.containsKey('anchorUrl'))
            .toList();
        expect(requests, isNotEmpty);
        expect(requests.first['category'], 'News');
        expect(requests.first['offset'], s.requestOffset);
        expect(requests.first['fromEnd'], false);
        // A local step opens before its prefetch returns. An actual boundary
        // press remains queued until the requested page exists.
        expect(d.playingUrl, window[s.queued ? s.index : 0].url);
        final page = s.delta > 0
            ? [iptvChannel(2)]
            : [for (var i = s.requestOffset; i < s.offset; i++) iptvChannel(i)];
        response.complete(
          iptvPage(
            page,
            offset: s.requestOffset,
            total: total,
            categories: categories,
          ),
        );
        await d.settle();
        if (s.queued) {
          expect(
            d.playingUrl,
            s.delta > 0 ? 'https://p15.test/2.ts' : 'https://p15.test/0.ts',
          );
        }
        expect(d.errors, isEmpty);
      } finally {
        if (!response.isCompleted) response.complete(null);
        await d.close();
      }
    });
  }
}
