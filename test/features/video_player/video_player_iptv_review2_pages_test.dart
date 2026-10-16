import 'dart:async';
import 'support/iptv_workflow_driver.dart';

void main() {
  testWidgets(
    'P15 review2 browse discards backward queue before a later adjacent landing',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      final channels = [iptvChannel(10), iptvChannel(11)];
      final oldPage = Completer<Map<String, dynamic>?>();
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
          return oldPage.future;
        }
        if (r['category'] == 'Sports') {
          return iptvPage(
            [iptvChannel(20, group: 'Sports')],
            category: 'Sports',
            categories: ['News', 'Sports'],
          );
        }
        return null;
      };
      try {
        await d.mount(channels, paged: true);
        await d.zap(-1);
        final sheet = await d.guide();
        sheet.onContextChanged!(
          IptvGuideContext(
            categories: ['Other'],
            selectedCategory: 'Other',
            sourceId: 'browsed',
            sourceName: 'Other',
            contentType: 'live',
          ),
        );
        await d.closeGuide(sheet);
        oldPage.complete(
          iptvPage([for (var i = 0; i < 10; i++) iptvChannel(i)], total: 12),
        );
        await d.settle();
        await d.zap(1);
        await d.settle();
        expect(d.browse.any((r) => r['category'] == 'Sports'), true);
        expect(d.playingUrl, channels[1].url);
        final current = await d.guide();
        expect(current.currentIndex, 1);
        expect(current.channels.length, 2);
        expect(d.errors, isEmpty);
      } finally {
        if (!oldPage.isCompleted) {
          oldPage.complete(null);
        }
        await d.close();
      }
    },
  );
  testWidgets(
    'P15 review2 installed page filters empty categories and retains absent source',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      final news = iptvChannel(0);
      final sports = iptvChannel(10, group: 'Sports');
      final tail = Completer<Map<String, dynamic>?>();
      d.provider = (r) {
        if (r.containsKey('anchorUrl')) {
          return iptvPage(
            [news],
            source: 'original-ring',
            categories: ['News', 'Sports'],
          );
        }
        if (r['category'] == 'Sports' && r['offset'] == 0) {
          return iptvPage(
            [sports],
            category: 'Sports',
            source: null,
            total: 2,
            categories: ['', 'News', 'Sports', ''],
          );
        }
        return tail.future;
      };
      try {
        await d.mount([news], paged: true);
        await d.zap(1);
        await d.f.until(
          t,
          () => d.browse.any(
            (r) => r['category'] == 'Sports' && r['offset'] == 1,
          ),
        );
        expect(d.browse.last['sourceId'], 'original-ring');
        expect(d.playingUrl, sports.url);
        final sheet = await d.guide();
        expect(sheet.categories, ['News', 'Sports']);
        expect(sheet.selectedCategory, 'Sports');
        expect(d.browse.where((r) => r['category'] == ''), isEmpty);
        expect(d.errors, isEmpty);
      } finally {
        if (!tail.isCompleted) {
          tail.complete(null);
        }
        await d.close();
      }
    },
  );
  testWidgets('P15 review2 wrong category touching page cannot merge', (
    t,
  ) async {
    final d = IptvWorkflowDriver(t);
    await d.initialize();
    final channels = [iptvChannel(0), iptvChannel(1)];
    d.provider = (r) => r.containsKey('anchorUrl')
        ? iptvPage(channels, total: 4)
        : iptvPage(
            [iptvChannel(2, group: 'Sports')],
            category: 'Sports',
            offset: 2,
            total: 4,
          );
    try {
      await d.mount(channels, paged: true);
      await d.zap(1);
      final sheet = await d.guide();
      expect(sheet.channels.map((c) => c.url), channels.map((c) => c.url));
      expect(sheet.currentIndex, 1);
      expect(d.playingUrl, channels[1].url);
      expect(d.errors, isEmpty);
    } finally {
      await d.close();
    }
  });
  testWidgets(
    'P15 review2 prepend shifts fallback index when overlap renames playing identity',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      final channels = [for (var i = 10; i < 25; i++) iptvChannel(i)];
      var requested = false;
      d.provider = (r) {
        if (r.containsKey('anchorUrl')) {
          return iptvPage(channels, offset: 10, total: 25);
        }
        if (requested) {
          return null;
        }
        requested = true;
        return iptvPage([
          for (var i = 0; i < 13; i++)
            IptvChannel(
              name: 'Refreshed $i',
              url: 'https://p15.test/$i.ts',
              group: 'News',
              contentType: 'live',
            ),
        ], total: 25);
      };
      try {
        await d.mount(channels, index: 2, paged: true);
        await d.zap(-1);
        expect(d.playingUrl, channels[1].url);
        final sheet = await d.guide();
        expect(sheet.channels.length, 25);
        expect(sheet.currentIndex, 11);
        expect(sheet.channels[sheet.currentIndex].name, 'Refreshed 11');
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );
  for (final offset in [0, 10]) {
    testWidgets(
      'P15 review2 undercounted total preserves window tail at offset $offset',
      (t) async {
        final d = IptvWorkflowDriver(t);
        await d.initialize();
        final channels = [for (var i = 0; i < 3; i++) iptvChannel(i)];
        d.provider = (r) => r.containsKey('anchorUrl')
            ? iptvPage(
                channels,
                offset: offset,
                total: 0,
                categories: ['News', 'Sports'],
              )
            : iptvPage(
                [iptvChannel(9, group: 'Sports')],
                category: 'Sports',
                categories: ['News', 'Sports'],
              );
        try {
          await d.mount(channels, index: 1, paged: true);
          await d.zap(1);
          expect(d.playingUrl, channels.last.url);
          await d.zap(1);
          expect(d.playingUrl, 'https://p15.test/9.ts');
          expect(
            d.browse
                .where((r) => !r.containsKey('anchorUrl'))
                .first['category'],
            'Sports',
          );
          expect(d.errors, isEmpty);
        } finally {
          await d.close();
        }
      },
    );
  }
}
