import 'support/iptv_storage_driver.dart';
import 'support/iptv_workflow_driver.dart';
import 'video_player_iptv_memory_test.dart' show iptvEpisode;
import 'package:debrify/screens/video_player/widgets/debrify_tv_banner.dart';

void main() {
  testWidgets(
    'P15 review2 guide dispatch publishes an explicit channel number over its ordinal',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      final channels = [
        iptvChannel(7, live: false),
        iptvChannel(900, live: false),
      ];
      try {
        await d.observe(
          () => d.f.mount(
            t,
            VideoPlayerScreen(
              videoUrl: channels.first.url,
              title: channels.first.name,
              iptvChannels: channels,
              iptvStartIndex: 0,
              showChannelName: true,
              channelName: 'Launch',
              channelNumber: 7,
            ),
          ),
        );
        await d.pick(channels, 1);
        final badges = t.widgetList<DebrifyTvBanner>(
          find.byType(DebrifyTvBanner),
        );
        expect(badges, isNotEmpty);
        expect(badges.map((v) => v.channelNumber), everyElement(900));
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P15 review2 a rendered guide button rechecks a cleared borrowed window',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      final channels = [iptvChannel(0)];
      try {
        await d.mount(channels);
        final guide = playerControls(t).onShowIptvChannels;
        expect(guide, isNotNull);
        expect(d.banners.where((v) => !v.flush), isNotEmpty);
        final hide = d.timed
            .lastWhere((v) => v.$1 == const Duration(milliseconds: 4500))
            .$2;
        channels.clear();
        d.observe(guide!);
        await d.advance(const Duration(milliseconds: 400));
        await d.settle();
        expect(find.byType(IptvChannelSheet), findsNothing);
        expect(
          hide.isActive,
          true,
          reason: 'A rejected guide dispatch cannot retire current feedback',
        );
        expect(d.banners.where((v) => !v.flush), isNotEmpty);
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );
  for (final forward in [false, true]) {
    testWidgets(
      'P15 review2 a pre-paint episode callback rechecks its ${forward ? 'upper' : 'lower'} bound',
      (t) async {
        final d = IptvWorkflowDriver(t);
        await d.initialize();
        final channels = [iptvEpisode(1), iptvEpisode(2)];
        final stop = IptvAwaitDelivery('switchToIptvChannel', (v) => v == null);
        Future<void>? tune;
        try {
          await d.mount(channels, index: forward ? 0 : 1);
          final controls = playerControls(t);
          final press = forward ? controls.onNext : controls.onPrevious;
          expect(press, isNotNull);
          final guide = await d.guide();
          tune = stop.run(
            () => d.observe(
              () => guide.onChannelSelected(channels, forward ? 1 : 0),
            ),
          );
          await d.f.until(t, () => stop.pending.isNotEmpty);
          stop.release();
          // The original switch commits its new index before the next frame.
          // The already-rendered button still has its old enabled callback;
          // its dispatch reads the new index and must validate it again.
          d.observe(press!);
          await d.f.finish(t, tune!);
          await d.settle();
          expect(d.errors, isEmpty);
          expect(d.playingUrl, channels[forward ? 1 : 0].url);
        } finally {
          stop.release();
          if (tune != null) await d.f.finish(t, tune);
          await d.close();
        }
      },
    );
  }

  testWidgets(
    'P15 review2 an invalid negative launch row reports the fallback channel name',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      try {
        await d.observe(
          () => d.f.mount(
            t,
            VideoPlayerScreen(
              videoUrl: 'https://p15.test/orphan.ts',
              title: 'Launch',
              iptvChannels: [iptvChannel(0)],
              iptvStartIndex: -1,
            ),
          ),
        );
        d.player.emit('error', 'broken input');
        await d.settle();
        expect(
          find.text("This channel didn't play — broken input"),
          findsOneWidget,
        );
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );
}
