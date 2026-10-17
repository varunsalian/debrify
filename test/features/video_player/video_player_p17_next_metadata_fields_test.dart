import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/screens/video_player/widgets/debrify_tv_banner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/tv_episode_driver.dart';

void main() {
  for (final field in ['name', 'number', 'id', 'none']) {
    testWidgets(
      'P17 next independently publishes $field metadata and retains omitted identity fields',
      (t) async {
        final d = TvEpisodeDriver(t);
        await d.initialize();
        try {
          await d.mount(
            screen: VideoPlayerScreen(
              videoUrl: 'https://player.test/a.mp4',
              title: 'A',
              channelDirectory: tvDirectory,
              requestChannelById: (id) async => null,
              showChannelName: true,
              channelName: 'Alpha',
              channelNumber: 7,
              requestNextChannel: () async => {
                'url': 'https://player.test/b.mp4',
                if (field == 'name') 'channelName': 'Reported',
                if (field == 'number') 'channelNumber': '12',
                if (field == 'id') 'channelId': 'reported',
              },
            ),
          );
          await d.nextChannel();
          expect(
            d.player.state.playlist.medias.single.uri,
            'https://player.test/b.mp4',
          );
          final guide = await d.debrifyGuide();
          expect(guide.currentChannelId, field == 'id' ? 'reported' : 'a');
          expect(guide.currentChannelNumber, field == 'number' ? 12 : 7);
          guide.onClose();
          await d.f.advance(t);
          expect(find.byType(DebrifyTvBanner), findsWidgets);
          final plates = t.widgetList<DebrifyTvBanner>(
            find.byType(DebrifyTvBanner),
          );
          expect(
            plates.map((p) => p.channelName),
            everyElement(field == 'name' ? 'Reported' : 'Alpha'),
          );
          expect(
            plates.map((p) => p.channelNumber),
            everyElement(field == 'number' ? 12 : 7),
          );
          expect(d.errors, isEmpty);
        } finally {
          await d.close();
        }
      },
    );
  }
}
