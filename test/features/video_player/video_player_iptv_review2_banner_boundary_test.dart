import 'support/iptv_workflow_driver.dart';

void main() {
  testWidgets(
    'P15 review2 hidden guide tune refreshes the rendered banner clock',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      final channels = [iptvChannel(0), iptvChannel(1)];
      try {
        await d.mount(channels);
        final sheet = await d.guide();
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
        final before = DateTime.now();
        await d.f.finish(
          t,
          d.observe(() => sheet.onChannelSelected(channels, 1)),
        );
        await d.closeGuide(sheet);
        await d.observe(() => t.tapAt(const Offset(600, 300)));
        await d.advance(const Duration(milliseconds: 400));
        expect(d.banners, isNotEmpty);
        expect(d.banners.first.channel.url, channels[1].url);
        expect(d.banners.first.now.isBefore(before), false);
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );
  testWidgets(
    'P15 review2 visible banner owns one ticker and publishes its real clock',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      int active() => d.periodic
          .where((v) => v.$1 == const Duration(seconds: 1) && v.$2.isActive)
          .length;
      try {
        await d.mount([iptvChannel(0)]);
        expect(active(), 1);
        await d.observe(() => t.tapAt(const Offset(600, 300)));
        await d.advance(const Duration(milliseconds: 100));
        expect(active(), 1);
        final before = DateTime.now();
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
        await d.advance(const Duration(seconds: 1));
        expect(d.banners, isNotEmpty);
        expect(d.banners.first.now.isBefore(before), false);
        expect(active(), 1);
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );
}
