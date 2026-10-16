import 'dart:async';
import 'support/iptv_workflow_driver.dart';
import 'support/local_completion_driver.dart';

void main() {
  for (final continues in [false, true]) {
    testWidgets(
      'P15 review2 category install publishes before recording stop continues=$continues',
      (t) async {
        final d = IptvWorkflowDriver(t);
        await d.initialize();
        final old = [for (var i = 0; i < 5; i++) iptvChannel(i)];
        final next = [
          iptvChannel(10, group: 'Sports'),
          iptvChannel(11, group: 'Sports'),
          old.last,
        ];
        final tail = Completer<Map<String, dynamic>?>();
        var delivered = false;
        d.provider = (r) {
          if (r.containsKey('anchorUrl')) {
            return iptvPage(old, categories: ['News', 'Sports']);
          }
          if (!delivered && r['category'] == 'Sports') {
            delivered = true;
            return iptvPage(
              next,
              offset: 40,
              total: continues ? 100 : 43,
              category: 'Sports',
              source: 'new-page',
              categories: ['News', 'Sports', 'Third'],
            );
          }
          return tail.future;
        };
        final stop = CompletionDelivery(
          'switchToIptvChannel',
          (v) => v == null,
        );
        try {
          await d.mount(old, index: 4, paged: true);
          await stop.run(() => d.zap(1));
          await d.f.until(t, () => stop.pending.isNotEmpty);
          final sheet = await d.guide();
          expect(sheet.currentIndex, 0);
          expect(sheet.channels.map((c) => c.url), next.map((c) => c.url));
          expect(sheet.selectedCategory, 'Sports');
          expect(sheet.categories, ['News', 'Sports', 'Third']);
          expect(d.playingUrl, old.last.url);
          expect(d.browse.last, {
            'action': 'zapPage',
            'sourceId': 'new-page',
            'contentType': 'live',
            'category': continues ? 'Sports' : 'Third',
            'query': '',
            'offset': continues ? 43 : 0,
            'limit': 1500,
            'fromEnd': false,
          });
          stop.release();
          await d.f.until(t, () => d.playingUrl == next.first.url);
          expect(d.errors, isEmpty);
        } finally {
          stop.release();
          if (!tail.isCompleted) {
            tail.complete(null);
          }
          await d.close();
        }
      },
    );
  }
}
