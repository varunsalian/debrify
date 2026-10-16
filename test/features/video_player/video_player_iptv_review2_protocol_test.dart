import 'dart:async';
import 'support/iptv_workflow_driver.dart';

void main() {
  for (final direction in [-1, 1]) {
    testWidgets('P15 review2 complete page protocol direction=$direction', (
      t,
    ) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      final channels = [for (var i = 0; i < 30; i++) iptvChannel(i)];
      final reply = Completer<Map<String, dynamic>?>();
      d.provider = (r) => r.containsKey('anchorUrl')
          ? iptvPage(channels, offset: 20, total: 100, source: 'ring-origin')
          : reply.future;
      try {
        await d.mount(
          channels,
          index: direction > 0 ? 18 : 11,
          paged: true,
          source: 'launch-origin',
        );
        expect(d.browse.first, {
          'action': 'zapPage',
          'sourceId': 'launch-origin',
          'contentType': 'live',
          'category': 'News',
          'query': '',
          'anchorUrl': channels[direction > 0 ? 18 : 11].url,
          'anchorName': channels[direction > 0 ? 18 : 11].name,
          'offset': 0,
          'limit': 1500,
        });
        await d.zap(direction);
        expect(d.browse.last, {
          'action': 'zapPage',
          'sourceId': 'ring-origin',
          'contentType': 'live',
          'category': 'News',
          'query': '',
          'offset': direction > 0 ? 50 : 0,
          'limit': 1500,
          'fromEnd': false,
        });
        expect(d.playingUrl, channels[direction > 0 ? 19 : 10].url);
        expect(d.errors, isEmpty);
      } finally {
        if (!reply.isCompleted) {
          reply.complete(null);
        }
        await d.close();
      }
    });
  }
  for (final shape in ['typed', 'missing', 'blank', 'negative', 'fractional']) {
    testWidgets(
      'P15 review2 page decoding $shape keeps directory and subsequent request coordinates',
      (t) async {
        final d = IptvWorkflowDriver(t);
        await d.initialize();
        final news = iptvChannel(0);
        final sports = iptvChannel(10, group: 'Sports');
        final pending = Completer<Map<String, dynamic>?>();
        var responses = 0;
        d.provider = (r) {
          if (r.containsKey('anchorUrl')) {
            return iptvPage(
              [news],
              source: 'ring-origin',
              categories: ['News', 'Sports'],
            );
          }
          if (responses++ > 0) {
            return pending.future;
          }
          final page = iptvPage(
            [sports],
            source: '  page-origin  ',
            category: ' Sports ',
            categories: ['', 'News', 'Sports', ''],
            offset: 4,
            total: 20,
          );
          if (shape == 'missing') {
            page.remove('pageOffset');
            page.remove('totalChannels');
            page.remove('sourceId');
            page.remove('selectedCategory');
            page.remove('categories');
          }
          if (shape == 'blank') {
            page['sourceId'] = '  ';
            page['selectedCategory'] = ' ';
            page['categories'] = 'not a list';
            page['pageOffset'] = '4';
            page['totalChannels'] = '20';
          }
          if (shape == 'negative') {
            page['pageOffset'] = -4;
          }
          if (shape == 'fractional') {
            page['pageOffset'] = 4.9;
            page['totalChannels'] = 20.9;
          }
          return page;
        };
        try {
          await d.mount([news], paged: true);
          expect(playerControls(t).onNext, isNotNull);
          await d.zap(1);
          expect(d.playingUrl, sports.url);
          final sheet = await d.guide();
          expect(sheet.channels.map((c) => c.url), [sports.url]);
          expect(sheet.channels.single.name, sports.name);
          expect(sheet.currentIndex, 0);
          final normalized =
              shape == 'typed' || shape == 'negative' || shape == 'fractional';
          expect(sheet.selectedCategory, normalized ? 'Sports' : null);
          expect(
            sheet.categories,
            normalized ? ['News', 'Sports'] : ['News', 'Sports'],
          );
          await d.closeGuide(sheet);
          final requests = d.browse
              .where((r) => !r.containsKey('anchorUrl'))
              .toList();
          expect(requests.first['category'], 'Sports');
          if (normalized) {
            expect(requests, hasLength(2));
            expect(requests.last['sourceId'], 'page-origin');
            expect(requests.last['category'], 'Sports');
            expect(requests.last['offset'], shape == 'negative' ? 1 : 5);
            expect(requests.last['fromEnd'], false);
          }
          expect(d.errors, isEmpty);
        } finally {
          if (!pending.isCompleted) {
            pending.complete(null);
          }
          await d.close();
        }
      },
    );
  }
}
