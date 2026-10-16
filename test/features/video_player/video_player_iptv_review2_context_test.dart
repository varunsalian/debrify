import 'support/iptv_workflow_driver.dart';

void main() {
  for (final contentType in ['series', 'vod']) {
    testWidgets(
      'P15 review2 category anchor retains explicit launch context $contentType',
      (t) async {
        final d = IptvWorkflowDriver(t);
        await d.initialize();
        final channel = iptvChannel(0);
        try {
          await d.observe(
            () => d.f.mount(
              t,
              VideoPlayerScreen(
                videoUrl: channel.url,
                title: channel.name,
                iptvChannels: [channel],
                iptvCategories: const ['News', 'Sports'],
                iptvSourceId: 'LaunchSource',
                iptvSourceName: 'Launch title',
                iptvContentType: contentType,
              ),
            ),
          );
          final sheet = await d.guide();
          expect(sheet.selectedCategory, 'News');
          expect(sheet.categories, ['News', 'Sports']);
          expect(sheet.sourceId, 'LaunchSource');
          expect(sheet.sourceName, 'Launch title');
          expect(sheet.contentType, contentType);
          expect(d.playingUrl, channel.url);
          expect(d.errors, isEmpty);
        } finally {
          await d.close();
        }
      },
    );
  }
}
