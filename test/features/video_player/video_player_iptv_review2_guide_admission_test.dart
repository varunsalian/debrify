import 'support/iptv_workflow_driver.dart';

void main() {
  testWidgets(
    'P15 review2 opening the IPTV guide retires a bare floating banner',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      try {
        await d.mount([iptvChannel(0)]);
        final hide = d.timed
            .lastWhere((v) => v.$1 == const Duration(milliseconds: 4500))
            .$2;
        expect(hide.isActive, true);
        expect(d.banners.where((b) => !b.flush), isNotEmpty);
        await d.guide();
        expect(hide.isActive, false);
        await d.advance(const Duration(milliseconds: 350));
        expect(d.banners.where((b) => !b.flush), isEmpty);
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );
  testWidgets(
    'P15 review2 a retained guide action rejects an emptied public launch list',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      final live = iptvChannel(0);
      final channels = [live];
      try {
        await d.mount(channels);
        final show = playerControls(t).onShowIptvChannels!;
        channels.clear();
        d.observe(show);
        await d.settle();
        channels.add(live);
        d.player.emit('duration', const Duration(minutes: 21));
        await d.settle();
        expect(find.byType(IptvChannelSheet), findsNothing);
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );
}
