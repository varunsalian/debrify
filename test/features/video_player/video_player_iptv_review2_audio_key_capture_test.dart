import 'package:debrify/services/storage/iptv_audio_storage.dart';
import 'package:debrify/services/storage/subtitle_settings_storage.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'support/iptv_storage_driver.dart';
import 'support/iptv_workflow_driver.dart';
import 'video_player_iptv_memory_test.dart' show iptvEpisode;

void main() {
  testWidgets(
    'P15 review2 an empty manual audio language cannot shadow stored series language',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      try {
        await d.f.finish(
          t,
          IptvAudioStorage.setIptvSeriesAudioLanguage(
            'provider::series',
            'fra',
          ),
        );
        await d.mount([iptvEpisode(1), iptvEpisode(2)]);
        d.player.publishTracks(
          const mk.Tracks(
            audio: [
              mk.AudioTrack('1', 'Unlabelled', ''),
              mk.AudioTrack('2', 'French', 'fra'),
            ],
          ),
        );
        await d.settle();
        final menu = await openPlayerMenu(t, d.f);
        await d.f.finish(t, menu.onAudioSelected('1', 'no'));
        await d.settle();
        expect(d.player.state.track.audio.id, '1');
        await d.zap(1);
        await d.settle();
        expect(d.player.state.track.audio.id, '2');
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );
  for (final live in [false, true]) {
    testWidgets(
      'P15 review2 audio key is read after track wait from a changed borrowed row live=$live',
      (t) async {
        final d = IptvWorkflowDriver(t);
        await d.initialize();
        final channels = [iptvEpisode(1), iptvEpisode(2)];
        final delay = IptvAwaitDelivery(
          'applyIptvAudioPreference',
          (v) => v == null,
        );
        try {
          await d.f.finish(
            t,
            SubtitleSettingsStorage.setDefaultAudioLanguage('eng'),
          );
          await d.f.finish(
            t,
            IptvAudioStorage.setIptvSeriesAudioLanguage(
              live ? 'provider::series' : 'provider::',
              'fra',
            ),
          );
          await d.mount(channels);
          await delay.run(() => d.zap(1));
          await d.f.until(t, () => delay.pending.isNotEmpty);
          // The launch list is borrowed by the original screen. Change its
          // public row while track enumeration waits, without another tune.
          channels[1] = iptvChannel(
            2,
            live: live,
            attributes: {
              'series_id': live ? 'series' : '',
              'series_playlist_id': 'provider',
            },
          );
          d.player.publishTracks(
            const mk.Tracks(
              audio: [
                mk.AudioTrack('1', 'English', 'eng'),
                mk.AudioTrack('2', 'French', 'fra'),
              ],
            ),
          );
          await d.settle();
          delay.release();
          await d.settle();
          expect(
            d.player.state.track.audio.id,
            '1',
            reason: 'Live or unkeyed rows use the global language fallback',
          );
          expect(d.errors, isEmpty);
        } finally {
          delay.release();
          await d.close();
        }
      },
    );
  }
}
