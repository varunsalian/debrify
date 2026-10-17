import 'dart:async';
import 'support/iptv_workflow_driver.dart';

void main() {
  for (final direction in [-1, 1]) {
    testWidgets(
      'P15 review2 merge preserves playing extreme after reversing pending direction=$direction',
      (t) async {
        final d = IptvWorkflowDriver(t);
        await d.initialize();
        final all = [for (var i = 0; i < 4; i++) iptvChannel(i)];
        final window = direction > 0 ? all.sublist(0, 2) : all.sublist(2);
        final page = Completer<Map<String, dynamic>?>();
        d.provider = (r) => r.containsKey('anchorUrl')
            ? iptvPage(window, offset: direction > 0 ? 0 : 2, total: 4)
            : page.future;
        try {
          final initial = direction > 0 ? 0 : 1;
          await d.mount(window, index: initial, paged: true);
          await d.zap(direction);
          await d.zap(-direction);
          expect(d.playingUrl, window[initial].url);
          page.complete(
            iptvPage(
              direction > 0 ? all.sublist(2) : all.sublist(0, 2),
              offset: direction > 0 ? 2 : 0,
              total: 4,
            ),
          );
          await d.settle();
          final sheet = await d.guide();
          expect(sheet.channels.map((c) => c.url), all.map((c) => c.url));
          expect(sheet.currentIndex, direction > 0 ? 0 : 3);
          expect(sheet.channels[sheet.currentIndex].url, d.playingUrl);
          expect(d.errors, isEmpty);
        } finally {
          if (!page.isCompleted) {
            page.complete(null);
          }
          await d.close();
        }
      },
    );
  }
  for (final continues in [false, true]) {
    testWidgets(
      'P15 review2 merged directory carries total and refreshed categories continues=$continues',
      (t) async {
        final d = IptvWorkflowDriver(t);
        await d.initialize();
        final window = [for (var i = 0; i < 30; i++) iptvChannel(i)];
        final tail = Completer<Map<String, dynamic>?>();
        var delivered = false;
        d.provider = (r) {
          if (r.containsKey('anchorUrl')) {
            return iptvPage(
              window,
              total: 100,
              source: 'ring-origin',
              categories: ['News', 'Old'],
            );
          }
          if (!delivered) {
            delivered = true;
            return iptvPage(
              [iptvChannel(30), iptvChannel(31)],
              offset: 30,
              total: continues ? 100 : 32,
              source: 'ignored-on-merge',
              categories: ['News', 'New'],
            );
          }
          return tail.future;
        };
        try {
          await d.mount(window, index: 18, paged: true);
          await d.zap(1);
          final sheet = await d.guide();
          expect(sheet.channels, hasLength(32));
          await d.closeGuide(sheet);
          await d.zap(1);
          await d.zap(1);
          expect(d.playingUrl, window[21].url);
          expect(d.browse.last, {
            'action': 'zapPage',
            'sourceId': 'ring-origin',
            'contentType': 'live',
            'category': continues ? 'News' : 'New',
            'query': '',
            'offset': continues ? 32 : 0,
            'limit': 1500,
            'fromEnd': false,
          });
          expect(d.errors, isEmpty);
        } finally {
          if (!tail.isCompleted) {
            tail.complete(null);
          }
          await d.close();
        }
      },
    );
  }
  for (final raw in [null, '', '  ', ' normalized ']) {
    testWidgets(
      'P15 review2 source normalization independently preserves request origin $raw',
      (t) async {
        final d = IptvWorkflowDriver(t);
        await d.initialize();
        final news = iptvChannel(0);
        final sports = iptvChannel(10, group: 'Sports');
        final tail = Completer<Map<String, dynamic>?>();
        var delivered = false;
        d.provider = (r) {
          if (r.containsKey('anchorUrl')) {
            return iptvPage(
              [news],
              source: 'ring-origin',
              categories: ['News', 'Sports'],
            );
          }
          if (!delivered) {
            delivered = true;
            return iptvPage(
              [sports],
              total: 2,
              category: 'Sports',
              source: raw,
              categories: ['News', 'Sports'],
            );
          }
          return tail.future;
        };
        try {
          await d.mount([news], paged: true);
          await d.zap(1);
          expect(d.playingUrl, sports.url);
          expect(d.browse.last, {
            'action': 'zapPage',
            'sourceId': raw?.trim().isNotEmpty == true
                ? 'normalized'
                : 'ring-origin',
            'contentType': 'live',
            'category': 'Sports',
            'query': '',
            'offset': 1,
            'limit': 1500,
            'fromEnd': false,
          });
          expect(d.errors, isEmpty);
        } finally {
          if (!tail.isCompleted) {
            tail.complete(null);
          }
          await d.close();
        }
      },
    );
  }
}
