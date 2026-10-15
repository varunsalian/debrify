import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/storage/iptv_audio_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/subtitle_apply_driver.dart';

void main() {
  for (final action in ['audio', 'subtitle-off']) {
    testWidgets(
      'p13 menu $action remembers the chosen IPTV series audio language',
      (t) async {
        final d = SubtitleApplyDriver(t);
        await d.initialize();
        const key = 'p13-playlist::p13-series';
        try {
          await d.mount(
            screen: VideoPlayerScreen(
              videoUrl: 'https://player.test/series-audio.mp4',
              title: 'IPTV manual audio',
              iptvChannels: [
                IptvChannel(
                  name: 'Series episode',
                  url: 'https://player.test/series-audio.mp4',
                  contentType: 'vod',
                  attributes: const {
                    'series_id': 'p13-series',
                    'series_playlist_id': 'p13-playlist',
                  },
                ),
              ],
            ),
          );
          expect(
            await d.f.finish(
              t,
              IptvAudioStorage.getIptvSeriesAudioLanguage(key),
            ),
            isNull,
          );
          final menu = await d.menu();
          if (action == 'audio') {
            await d.f.finish(t, menu.onAudioSelected('2', '1'));
            expect(d.player.state.track.audio.id, '2');
          } else {
            expect(await d.f.finish(t, menu.onSubtitlesOff('2')), isTrue);
          }
          await d.f.actions.settle(t);
          expect(
            await d.f.finish(
              t,
              IptvAudioStorage.getIptvSeriesAudioLanguage(key),
            ),
            'spa',
          );
          expect(d.errors, isEmpty);
        } finally {
          await d.close();
        }
      },
    );
  }
}
