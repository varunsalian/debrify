import 'support/iptv_workflow_driver.dart';

void main() {
  testWidgets(
    'P15 review2 a category landing without a directory preserves the guide directory',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      final news = iptvChannel(0);
      final sports = iptvChannel(8, group: 'Sports');
      const categories = ['News', 'Sports'];
      d.provider = (r) => r.containsKey('anchorUrl')
          ? iptvPage([news], categories: categories)
          : r['category'] == 'Sports'
          ? iptvPage([sports], category: 'Sports', categories: [])
          : null;
      try {
        await d.mount([news], paged: true);
        await d.zap(1);
        expect(d.playingUrl, sports.url);
        final guide = await d.guide();
        expect(guide.selectedCategory, 'Sports');
        expect(guide.categories, categories);
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );

  for (final delta in [-1, 1]) {
    testWidgets(
      'P15 review2 consuming a same-category cache allows its next fresh prefetch delta=$delta',
      (t) async {
        final d = IptvWorkflowDriver(t);
        await d.initialize();
        final initial = [iptvChannel(0), iptvChannel(1)];
        var requests = 0;
        d.provider = (r) {
          if (r.containsKey('anchorUrl')) return iptvPage(initial);
          requests++;
          return iptvPage([
            iptvChannel(requests * 2),
            iptvChannel(requests * 2 + 1),
          ]);
        };
        try {
          await d.mount(initial, index: delta > 0 ? 0 : 1, paged: true);
          await d.zap(delta);
          expect(requests, 1);
          await d.zap(delta);
          expect(d.playingUrl, 'https://p15.test/${delta > 0 ? 2 : 3}.ts');
          expect(
            requests,
            2,
            reason:
                'A consumed page cannot keep blocking fresh same-category prefetch',
          );
          expect(d.errors, isEmpty);
        } finally {
          await d.close();
        }
      },
    );
  }
}
