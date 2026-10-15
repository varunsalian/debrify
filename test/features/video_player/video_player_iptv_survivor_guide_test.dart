import 'dart:async';
import 'support/iptv_workflow_driver.dart';

void main() {
  for (final contentType in ['series', 'vod']) {
    testWidgets(
      'P15 addendum same category publishes changed list and preserves $contentType override',
      (t) async {
        final d = IptvWorkflowDriver(t);
        await d.initialize();
        final channels = [iptvChannel(0), iptvChannel(1)];
        var refreshed = false;
        d.provider = (r) => iptvPage(
          channels,
          categories: refreshed ? ['News', 'New category'] : ['News'],
        );
        try {
          await d.mount(channels, paged: true);
          final sheet = await d.guide();
          sheet.onContextChanged!(
            IptvGuideContext(
              categories: ['News'],
              selectedCategory: 'News',
              contentType: contentType,
              sourceId: 'persisted-source',
              sourceName: 'Persisted',
            ),
          );
          refreshed = true;
          await d.f.finish(t, sheet.onChannelSelected(channels, 1));
          await d.settle();
          final reopened = await d.guide();
          expect(reopened.selectedCategory, 'News');
          expect(reopened.categories, ['News', 'New category']);
          expect(reopened.contentType, contentType);
          expect(reopened.sourceId, 'persisted-source');
          expect(d.playingUrl, channels[1].url);
          expect(d.errors, isEmpty);
        } finally {
          await d.close();
        }
      },
    );
  }
  testWidgets('P15 addendum idle catchup cancel preserves unrelated snackbar', (
    t,
  ) async {
    final d = IptvWorkflowDriver(t);
    await d.initialize();
    try {
      await d.mount([iptvChannel(0), iptvChannel(1)]);
      final sheet = await d.guide();
      ScaffoldMessenger.of(
        t.element(find.byType(VideoPlayerScreen)),
      ).showSnackBar(
        const SnackBar(
          content: Text('Unrelated feedback'),
          duration: Duration(seconds: 30),
        ),
      );
      await d.advance(const Duration(milliseconds: 300));
      expect(find.text('Unrelated feedback'), findsOneWidget);
      await d.closeGuide(sheet);
      await d.advance(const Duration(milliseconds: 300));
      expect(find.text('Unrelated feedback'), findsOneWidget);
      expect(d.opened.length, 1);
      expect(d.errors, isEmpty);
    } finally {
      await d.close();
    }
  });
  testWidgets(
    'P15 addendum reset strands page even after same-category reanchor',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      final channels = [iptvChannel(0), iptvChannel(1)];
      final page = Completer<Map<String, dynamic>?>();
      d.provider = (r) => r.containsKey('anchorUrl')
          ? iptvPage(channels, total: 4)
          : page.future;
      try {
        await d.mount(channels, paged: true);
        await d.zap(1);
        expect(d.browse.where((r) => !r.containsKey('anchorUrl')).length, 1);
        await d.pick(channels, 0);
        expect(d.browse.where((r) => r.containsKey('anchorUrl')).length, 2);
        page.complete(
          iptvPage([iptvChannel(2), iptvChannel(3)], offset: 2, total: 4),
        );
        await d.settle();
        final sheet = await d.guide();
        expect(sheet.channels.map((c) => c.url), channels.map((c) => c.url));
        expect(sheet.currentIndex, 0);
        expect(d.playingUrl, channels[0].url);
        expect(d.errors, isEmpty);
      } finally {
        if (!page.isCompleted) page.complete(null);
        await d.close();
      }
    },
  );
  testWidgets(
    'P15 addendum backward window boundary queues previous page before category wrap',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      final channels = [iptvChannel(10), iptvChannel(11)];
      final page = Completer<Map<String, dynamic>?>();
      d.provider = (r) => r.containsKey('anchorUrl')
          ? iptvPage(
              channels,
              offset: 10,
              total: 12,
              categories: ['Sports', 'News'],
            )
          : page.future;
      try {
        await d.mount(channels, paged: true);
        await d.zap(-1);
        final request = d.browse.singleWhere(
          (r) => !r.containsKey('anchorUrl'),
        );
        expect(request['category'], 'News');
        expect(request['offset'], 0);
        expect(request['fromEnd'], false);
        expect(d.opened.length, 1);
        page.complete(
          iptvPage([for (var i = 0; i < 10; i++) iptvChannel(i)], total: 12),
        );
        await d.settle();
        expect(d.playingUrl, 'https://p15.test/9.ts');
        final sheet = await d.guide();
        expect(sheet.channels.length, 12);
        expect(sheet.currentIndex, 9);
        expect(sheet.selectedCategory, 'News');
        expect(d.errors, isEmpty);
      } finally {
        if (!page.isCompleted) page.complete(null);
        await d.close();
      }
    },
  );
}
