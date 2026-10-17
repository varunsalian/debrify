import 'package:debrify/screens/video_player/widgets/debrify_tv_banner.dart';
import 'support/iptv_workflow_driver.dart';

void main() {
  testWidgets('P15 addendum visible dock blocks a floating zap banner', (
    t,
  ) async {
    final d = IptvWorkflowDriver(t);
    await d.initialize();
    try {
      await d.mount([iptvChannel(0), iptvChannel(1)]);
      await d.advance(const Duration(seconds: 6));
      await t.tapAt(const Offset(600, 300));
      await d.advance(const Duration(milliseconds: 400));
      expect(d.banners.where((b) => b.flush), isNotEmpty);
      expect(d.banners.where((b) => !b.flush), isEmpty);
      final before = d.timed
          .where((v) => v.$1 == const Duration(milliseconds: 4500))
          .length;
      await d.zap(1);
      expect(d.playingUrl, 'https://p15.test/1.ts');
      expect(d.banners.where((b) => b.flush), isNotEmpty);
      expect(d.banners.where((b) => !b.flush), isEmpty);
      expect(
        d.timed.where((v) => v.$1 == const Duration(milliseconds: 4500)).length,
        before,
      );
      expect(d.errors, isEmpty);
    } finally {
      await d.close();
    }
  });
  testWidgets(
    'P15 addendum recovery retune retains pill and real zap clears it',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      final live = await d.installAddon('survivor-recovery', urls: []);
      try {
        await d.mount([
          live,
          iptvChannel(1),
        ], initialUrl: 'https://p15.test/bootstrap.ts');
        d.player.emit('error', 'first disconnect');
        await d.settle();
        await d.f.until(t, () => d.calls('stop').isNotEmpty);
        await d.settle();
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 350)),
        );
        d.player.emit('error', 'second disconnect');
        await d.settle();
        expect(find.text('Reconnecting…'), findsOneWidget);
        final before = d.calls('stop').length;
        await d.advance(const Duration(seconds: 1));
        await d.f.until(t, () => d.calls('stop').length > before);
        await d.settle();
        expect(find.text('Reconnecting…'), findsOneWidget);
        await d.zap(1);
        expect(find.text('Reconnecting…'), findsNothing);
        expect(d.playingUrl, 'https://p15.test/1.ts');
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );
  for (final index in [0, 2]) {
    testWidgets(
      'P15 addendum unnumbered channel identity uses ordinal ${index + 1}',
      (t) async {
        final d = IptvWorkflowDriver(t);
        await d.initialize();
        final channels = [
          for (var i = 0; i < 3; i++)
            IptvChannel(
              name: 'Unnumbered $i',
              url: 'https://p15.test/unnumbered-$i.mp4',
              contentType: 'vod',
            ),
        ];
        try {
          await d.observe(
            () => d.f.mount(
              t,
              VideoPlayerScreen(
                videoUrl: channels[1].url,
                title: channels[1].name,
                iptvChannels: channels,
                iptvStartIndex: 1,
                showChannelName: true,
                channelName: 'Launch name',
              ),
            ),
          );
          await d.pick(channels, index);
          final badges = t.widgetList<DebrifyTvBanner>(
            find.byType(DebrifyTvBanner),
          );
          expect(badges, isNotEmpty);
          expect(badges.map((b) => b.channelNumber), everyElement(index + 1));
          expect(
            badges.map((b) => b.channelName),
            everyElement(channels[index].name),
          );
          expect(d.playingUrl, channels[index].url);
          expect(d.errors, isEmpty);
        } finally {
          await d.close();
        }
      },
    );
  }
}
