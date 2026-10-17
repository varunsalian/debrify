import 'dart:async';
import 'support/iptv_workflow_driver.dart';

void main() {
  const scenarios = [
    (
      name: 'forward positive-offset margin',
      offset: 100,
      index: 18,
      delta: 1,
      request: true,
    ),
    (
      name: 'forward before margin',
      offset: 0,
      index: 17,
      delta: 1,
      request: false,
    ),
    (
      name: 'backward start margin',
      offset: 0,
      index: 2,
      delta: -1,
      request: true,
    ),
    (
      name: 'backward before margin',
      offset: 0,
      index: 12,
      delta: -1,
      request: false,
    ),
  ];
  for (final s in scenarios) {
    testWidgets('P15 review2 category threshold ${s.name}', (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      final window = [for (var i = 0; i < 30; i++) iptvChannel(s.offset + i)];
      const categories = ['News', 'Sports'];
      final page = Completer<Map<String, dynamic>?>();
      d.provider = (r) => r.containsKey('anchorUrl')
          ? iptvPage(
              window,
              offset: s.offset,
              total: s.offset + 30,
              categories: categories,
            )
          : page.future;
      try {
        await d.mount(window, index: s.index, paged: true);
        await d.zap(s.delta);
        var requests = d.browse
            .where((r) => !r.containsKey('anchorUrl'))
            .toList();
        expect(requests, hasLength(s.request ? 1 : 0));
        if (s.request) {
          expect(requests.single['category'], 'Sports');
          expect(requests.single['fromEnd'], s.delta < 0);
          page.complete(
            iptvPage(
              [iptvChannel(99, group: 'Sports')],
              category: 'Sports',
              categories: categories,
            ),
          );
          await d.settle();
          await d.zap(s.delta);
          requests = d.browse
              .where((r) => !r.containsKey('anchorUrl'))
              .toList();
          expect(
            requests,
            hasLength(1),
            reason: 'The same-direction cache is reused before crossing',
          );
        } else {
          page.complete(null);
        }
        expect(d.errors, isEmpty);
      } finally {
        if (!page.isCompleted) page.complete(null);
        await d.close();
      }
    });
  }
}
