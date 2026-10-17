import 'support/iptv_workflow_driver.dart';

IptvChannel identityChannel(String name, String url) =>
    IptvChannel(name: name, url: url, group: 'News', contentType: 'live');

void main() {
  testWidgets(
    'P15 review2 merge identity needs both URL and name among duplicates',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      const url = 'https://p15.test/shared.ts';
      final channels = [
        identityChannel('Wrong', url),
        identityChannel('Target', url),
        iptvChannel(4),
      ];
      var sent = false;
      d.provider = (r) {
        if (r.containsKey('anchorUrl')) {
          return iptvPage(channels, offset: 2, total: 5);
        }
        if (sent) {
          return null;
        }
        sent = true;
        return iptvPage([
          identityChannel('Target', 'https://p15.test/different.ts'),
          iptvChannel(1),
          identityChannel('Wrong', url),
        ], total: 5);
      };
      try {
        await d.mount(channels, index: 2, paged: true);
        await d.zap(-1);
        expect(d.playingUrl, url);
        final sheet = await d.guide();
        expect(sheet.currentIndex, 3);
        expect(sheet.channels[sheet.currentIndex].name, 'Target');
        expect(sheet.channels[sheet.currentIndex].url, url);
        expect(sheet.channels.first.name, 'Target');
        expect(sheet.channels[2].url, url);
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );
  testWidgets(
    'P15 review2 reanchor finds named URL after two partial identity matches',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      final target = identityChannel('Target', 'https://p15.test/target.ts');
      final page = [
        identityChannel('Target', 'https://p15.test/different.ts'),
        identityChannel('Wrong', target.url),
        target,
      ];
      d.provider = (r) => iptvPage(page);
      try {
        await d.mount([iptvChannel(0)], paged: true);
        await d.pick([target], 0);
        final sheet = await d.guide();
        expect(sheet.currentIndex, 2);
        expect(sheet.channels.map((c) => c.name), [
          'Target',
          'Wrong',
          'Target',
        ]);
        expect(d.playingUrl, target.url);
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );
}
