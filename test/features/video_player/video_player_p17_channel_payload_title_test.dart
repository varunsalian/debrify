import 'package:debrify/screens/video_player_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/player_actions.dart';
import 'support/tv_episode_driver.dart';

void main() {
  for (final route in ['next', 'by id']) {
    for (final kind in [
      'primary',
      'fallback',
      'blank primary',
      'invalid primary',
    ]) {
      testWidgets(
        'P17 $route payload title $kind reaches Debrify TV controls without generic next dispatch',
        (t) async {
          final d = TvEpisodeDriver(t);
          await d.initialize();
          var magicCalls = 0;
          final payload = <String, dynamic>{
            'url': 'https://player.test/b.mp4',
            if (kind != 'fallback')
              'firstTitle': kind == 'primary'
                  ? 'Primary'
                  : kind == 'blank primary'
                  ? ''
                  : false,
            'title': 'Fallback',
          };
          try {
            await d.mount(
              screen: VideoPlayerScreen(
                videoUrl: 'https://player.test/a.mp4',
                title: 'Launch',
                requestMagicNext: () async {
                  magicCalls++;
                  return null;
                },
                channelDirectory: tvDirectory,
                requestChannelById: (id) async => payload,
                requestNextChannel: () async => payload,
              ),
            );
            if (route == 'next') {
              await d.nextChannel();
            } else {
              final guide = await d.debrifyGuide();
              await d.byId(guide, guide.channels.last);
            }
            expect(
              d.player.state.playlist.medias.single.uri,
              'https://player.test/b.mp4',
            );
            expect(
              playerControls(t).title,
              kind == 'primary'
                  ? 'Primary'
                  : kind == 'fallback'
                  ? 'Fallback'
                  : 'Launch',
            );
            expect(magicCalls, 0);
            expect(d.errors, isEmpty);
          } finally {
            await d.close();
          }
        },
      );
    }
  }
}
