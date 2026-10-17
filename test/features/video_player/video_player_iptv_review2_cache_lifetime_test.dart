import 'dart:async';
import 'package:debrify/features/video_player/models/vp_iptv_zap_page.dart';
import 'support/iptv_storage_driver.dart';
import 'support/iptv_workflow_driver.dart';

void main() {
  testWidgets(
    'P15 review2 a parsed prefetch cannot cache across a different ring origin',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      final news = [iptvChannel(0), iptvChannel(1)];
      final movies = [
        iptvChannel(8, group: 'Movies'),
        iptvChannel(9, group: 'Movies'),
      ];
      final sports = iptvChannel(7, group: 'Sports');
      final categories = ['News', 'Sports', 'Movies'];
      final response = Completer<Map<String, dynamic>?>();
      final tail = Completer<Map<String, dynamic>?>();
      final delivery = IptvAwaitDelivery(
        'prefetchAdjacentIptvCategory',
        (v) => v is VpIptvZapPage,
      );
      d.provider = (r) {
        if (r.containsKey('anchorUrl')) {
          return iptvPage(
            r['anchorUrl'] == movies.first.url ? movies : news,
            category: r['anchorUrl'] == movies.first.url ? 'Movies' : 'News',
            categories: categories,
          );
        }
        return r['category'] == 'Sports' ? response.future : tail.future;
      };
      try {
        await d.mount(news, paged: true);
        await delivery.run(() => d.zap(1));
        response.complete(
          iptvPage([sports], category: 'Sports', categories: categories),
        );
        await d.f.until(t, () => delivery.pending.isNotEmpty);
        await d.pick(movies, 0);
        await d.f.until(
          t,
          () => d.browse.any((r) => r['anchorUrl'] == movies.first.url),
        );
        await d.settle();
        delivery.release();
        await d.settle();
        await d.zap(1);
        expect(d.playingUrl, movies.last.url);
        expect(
          d.browse
              .where((r) => !r.containsKey('anchorUrl'))
              .map((r) => r['category']),
          ['Sports', 'News'],
        );
        expect(d.errors, isEmpty);
      } finally {
        delivery.release();
        if (!response.isCompleted) response.complete(null);
        if (!tail.isCompleted) tail.complete(null);
        await d.close();
      }
    },
  );

  testWidgets(
    'P15 review2 empty adjacent prefetch visits each category only once',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      final channels = [iptvChannel(0), iptvChannel(1)];
      d.provider = (r) => r.containsKey('anchorUrl')
          ? iptvPage(channels, categories: ['News', 'Empty'])
          : iptvPage(
              [],
              category: r['category'] as String?,
              categories: ['News', 'Empty'],
            );
      try {
        await d.mount(channels, paged: true);
        await d.zap(1);
        await d.settle();
        expect(d.playingUrl, channels.last.url);
        expect(
          d.browse
              .where((r) => !r.containsKey('anchorUrl'))
              .map((r) => r['category']),
          ['Empty', 'News'],
        );
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );
}
