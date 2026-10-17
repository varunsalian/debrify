import 'package:debrify/screens/video_player_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/tv_episode_driver.dart';
import 'support/player_actions.dart';

void main() {
  for (final leading in [false, true]) {
    testWidgets(
      'P17 directory adopts the first flagged row with leading=$leading',
      (t) async {
        final d = TvEpisodeDriver(t);
        await d.initialize();
        try {
          await d.mount(
            screen: VideoPlayerScreen(
              videoUrl: 'https://player.test/a.mp4',
              title: 'Directory',
              channelDirectory: [
                if (leading)
                  {'id': 'before', 'name': 'Before', 'channelNumber': 3},
                {
                  'id': 'first',
                  'name': 'First',
                  'channelNumber': 7,
                  'isCurrent': true,
                },
                {
                  'id': 'second',
                  'name': 'Second',
                  'channelNumber': 9,
                  'isCurrent': true,
                },
              ],
              requestChannelById: (id) async => null,
            ),
          );
          expect(playerControls(t).onShowGuide, isNotNull);
          final guide = await d.debrifyGuide();
          expect(guide.currentChannelId, 'first');
          expect(guide.currentChannelNumber, 7);
          expect(
            guide.channels.map((v) => v.order),
            leading ? [0, 1, 2] : [0, 1],
          );
          expect(guide.channels.where((v) => v.isCurrent).map((v) => v.id), [
            'first',
            'second',
          ]);
          expect(d.errors, isEmpty);
        } finally {
          await d.close();
        }
      },
    );
  }
}
