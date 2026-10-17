import 'dart:async';
import 'support/iptv_workflow_driver.dart';

void main() {
  for (final source in [null, 'Chosen source']) {
    testWidgets(
      'P15 review2 reanchor captures guide source and retains a missing page origin $source',
      (t) async {
        final d = IptvWorkflowDriver(t);
        await d.initialize();
        final channels = [iptvChannel(0), iptvChannel(1)];
        d.provider = (r) => r.containsKey('anchorUrl')
            ? iptvPage([channels.first], total: 2, source: null)
            : iptvPage([channels.last], offset: 1, total: 2, source: null);
        try {
          await d.mount(channels, paged: true);
          final sheet = await d.guide();
          sheet.onContextChanged!(
            IptvGuideContext(
              categories: ['News'],
              sourceId: source,
              sourceName: 'Chosen label',
              selectedCategory: 'News',
              contentType: 'live',
            ),
          );
          final before = d.browse.length;
          await d.f.finish(
            t,
            d.observe(() => sheet.onChannelSelected(channels, 0)),
          );
          await d.f.until(t, () => d.browse.length > before);
          await d.settle();
          final origin = source ?? 'launch-source';
          expect(d.browse.last['sourceId'], origin);
          await d.zap(1);
          await d.f.until(
            t,
            () => d.browse.any((r) => !r.containsKey('anchorUrl')),
          );
          expect(d.browse.last['sourceId'], origin);
          expect(d.playingUrl, channels.last.url);
          expect(d.errors, isEmpty);
        } finally {
          await d.close();
        }
      },
    );
  }
  testWidgets('P15 review2 reanchor requests null for a whitespace group', (
    t,
  ) async {
    final d = IptvWorkflowDriver(t);
    await d.initialize();
    final live = iptvChannel(0, group: '  ');
    d.provider = (r) => iptvPage([live], category: null);
    try {
      await d.mount([live], paged: true);
      expect(d.browse.single['category'], isNull);
      expect(d.errors, isEmpty);
    } finally {
      await d.close();
    }
  });
  for (final changed in ['name', 'url']) {
    testWidgets(
      'P15 review2 bootstrap rereads the borrowed launch list $changed identity',
      (t) async {
        final d = IptvWorkflowDriver(t);
        await d.initialize();
        final target = iptvChannel(0);
        final channels = [target, iptvChannel(1)];
        final page = Completer<Map<String, dynamic>?>();
        d.provider = (r) => page.future;
        try {
          await d.mount(channels, paged: true);
          expect(d.browse, hasLength(1));
          // The public constructor borrows this legacy input list until an
          // override is installed. Change the caller's alias, never State.
          final replacement = changed == 'name'
              ? iptvChannel(9, url: target.url)
              : iptvChannel(0, url: 'https://p15-input.test/replaced.ts');
          channels[0] = replacement;
          page.complete(iptvPage([target, iptvChannel(2)]));
          await d.settle();
          final sheet = await d.guide();
          expect(sheet.channels.first.name, replacement.name);
          expect(sheet.channels.first.url, replacement.url);
          expect(sheet.channels.last.url, channels.last.url);
          expect(d.errors, isEmpty);
        } finally {
          if (!page.isCompleted) page.complete(null);
          await d.close();
        }
      },
    );
  }
}
