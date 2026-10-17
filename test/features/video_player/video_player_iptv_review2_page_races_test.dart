import 'dart:async';
import 'support/iptv_workflow_driver.dart';

void main() {
  for (final failure in ['null', 'throw']) {
    testWidgets(
      'P15 review2 failed $failure page releases mutex and discards queued backward presses',
      (t) async {
        final d = IptvWorkflowDriver(t);
        await d.initialize();
        final channels = [iptvChannel(10), iptvChannel(11)];
        final old = Completer<Map<String, dynamic>?>();
        var first = true;
        d.provider = (r) {
          if (r.containsKey('anchorUrl')) {
            return iptvPage(
              channels,
              offset: 10,
              total: 12,
              categories: ['News', 'Sports'],
            );
          }
          if (first) {
            first = false;
            return failure == 'throw'
                ? old.future.then<Map<String, dynamic>?>(
                    (_) => throw StateError('original handled page failure'),
                  )
                : old.future;
          }
          if (r['category'] == 'Sports') {
            return iptvPage(
              [iptvChannel(20, group: 'Sports')],
              category: 'Sports',
              categories: ['News', 'Sports'],
            );
          }
          return old.future;
        };
        try {
          await d.mount(channels, paged: true);
          await d.zap(-1);
          await d.zap(-1);
          expect(
            d.browse.where((r) => !r.containsKey('anchorUrl')),
            hasLength(1),
          );
          old.complete(null);
          await d.settle();
          await d.zap(1);
          await d.settle();
          expect(d.browse.any((r) => r['category'] == 'Sports'), true);
          expect(d.playingUrl, channels[1].url);
          final sheet = await d.guide();
          expect(sheet.currentIndex, 1);
          expect(sheet.channels.map((c) => c.url), channels.map((c) => c.url));
          expect(d.errors, isEmpty);
        } finally {
          if (!old.isCompleted) {
            old.complete(null);
          }
          await d.close();
        }
      },
    );
  }
  testWidgets(
    'P15 review2 sourceless ring uses new guide source when requesting another page',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      final channels = [for (var i = 0; i < 30; i++) iptvChannel(i)];
      final tail = Completer<Map<String, dynamic>?>();
      d.provider = (r) => r.containsKey('anchorUrl')
          ? iptvPage(channels, source: null, total: 60)
          : tail.future;
      try {
        await d.mount(channels, index: 18, paged: true, source: null);
        final sheet = await d.guide();
        sheet.onContextChanged!(
          IptvGuideContext(
            categories: ['News'],
            selectedCategory: 'News',
            sourceId: 'guide-origin',
            sourceName: 'Guide',
            contentType: 'live',
          ),
        );
        await d.closeGuide(sheet);
        await d.zap(1);
        expect(d.browse.last, {
          'action': 'zapPage',
          'sourceId': 'guide-origin',
          'contentType': 'live',
          'category': 'News',
          'query': '',
          'offset': 30,
          'limit': 1500,
          'fromEnd': false,
        });
        expect(d.playingUrl, channels[19].url);
        expect(d.errors, isEmpty);
      } finally {
        if (!tail.isCompleted) {
          tail.complete(null);
        }
        await d.close();
      }
    },
  );
  testWidgets(
    'P15 review2 later page drains after an earlier drain starts another request',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      final first = Completer<Map<String, dynamic>?>();
      final second = Completer<Map<String, dynamic>?>();
      var requests = 0;
      d.provider = (r) {
        if (r.containsKey('anchorUrl')) {
          return iptvPage([iptvChannel(0)], total: 3);
        }
        requests++;
        if (r['offset'] == 1) {
          return first.future;
        }
        if (r['offset'] == 2) {
          return second.future;
        }
        return iptvPage([iptvChannel(0)], total: 3);
      };
      try {
        await d.mount([iptvChannel(0)], paged: true);
        await d.zap(1);
        first.complete(iptvPage([iptvChannel(1)], offset: 1, total: 3));
        await d.f.until(
          t,
          () => d.playingUrl == iptvChannel(1).url && requests == 2,
        );
        await d.zap(1);
        second.complete(iptvPage([iptvChannel(2)], offset: 2, total: 3));
        await d.f.until(t, () => d.playingUrl == iptvChannel(2).url);
        expect(
          d.browse
              .where((r) => !r.containsKey('anchorUrl'))
              .map((r) => r['offset']),
          [1, 2, 0],
        );
        final sheet = await d.guide();
        expect(sheet.currentIndex, 2);
        expect(sheet.channels.map((c) => c.url), [
          for (var i = 0; i < 3; i++) iptvChannel(i).url,
        ]);
        expect(d.errors, isEmpty);
      } finally {
        if (!first.isCompleted) {
          first.complete(null);
        }
        if (!second.isCompleted) {
          second.complete(null);
        }
        await d.close();
      }
    },
  );
}
