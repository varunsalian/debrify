import 'support/iptv_workflow_driver.dart';

void main() {
  for (final direction in [-1, 1]) {
    testWidgets(
      'P15 review2 singleton category reverses a prefetched cache direction=$direction',
      (t) async {
        final d = IptvWorkflowDriver(t);
        await d.initialize();
        final categories = ['Previous', 'News', 'Sports', 'After'];
        final channels = {
          for (var i = 0; i < categories.length; i++)
            categories[i]: iptvChannel(i, group: categories[i]),
        };
        d.provider = (r) => iptvPage(
          [channels[r['category']]!],
          category: r['category'] as String?,
          categories: categories,
        );
        try {
          await d.mount([channels['News']!], paged: true);
          await d.zap(direction);
          final chosen = direction > 0 ? 'Sports' : 'Previous';
          await d.f.until(t, () => d.playingUrl == channels[chosen]!.url);
          await d.settle();
          expect(d.browse.any((r) => r['category'] == 'After'), true);
          await d.zap(-direction);
          await d.settle();
          expect(d.playingUrl, channels['News']!.url);
          expect(
            d.browse.where(
              (r) => !r.containsKey('anchorUrl') && r['category'] == 'News',
            ),
            isNotEmpty,
          );
          expect(d.errors, isEmpty);
        } finally {
          await d.close();
        }
      },
    );
  }
}
