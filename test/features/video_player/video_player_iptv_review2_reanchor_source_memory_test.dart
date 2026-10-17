import 'support/iptv_workflow_driver.dart';

void main() {
  for (final source in [null, 'Chosen source']) {
    testWidgets(
      'P15 review2 a missing page source latches reanchor origin across later browsing $source',
      (t) async {
        final d = IptvWorkflowDriver(t);
        await d.initialize();
        final channels = [iptvChannel(0), iptvChannel(1)];
        d.provider = (r) => r.containsKey('anchorUrl')
            ? iptvPage([channels.first], total: 2, source: null)
            : iptvPage([channels.last], offset: 1, total: 2, source: null);
        try {
          await d.mount(channels, paged: true);
          final first = await d.guide();
          first.onContextChanged!(
            IptvGuideContext(
              categories: ['News'],
              sourceId: source,
              sourceName: 'Original context',
              selectedCategory: 'News',
              contentType: 'live',
            ),
          );
          await d.f.finish(
            t,
            d.observe(() => first.onChannelSelected(channels, 0)),
          );
          await d.settle();
          final browse = await d.guide();
          browse.onContextChanged!(
            IptvGuideContext(
              categories: ['News'],
              sourceId: 'Browsed later',
              sourceName: 'Later context',
              selectedCategory: 'News',
              contentType: 'live',
            ),
          );
          await d.closeGuide(browse);
          await d.zap(1);
          final requests = d.browse
              .where((r) => !r.containsKey('anchorUrl'))
              .toList();
          expect(requests, isNotEmpty);
          expect(requests.first['sourceId'], source ?? 'launch-source');
          expect(d.playingUrl, channels.last.url);
          expect(d.errors, isEmpty);
        } finally {
          await d.close();
        }
      },
    );
  }
}
