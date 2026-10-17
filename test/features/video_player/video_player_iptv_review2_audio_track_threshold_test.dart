import 'package:debrify/services/storage/iptv_audio_storage.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'support/iptv_workflow_driver.dart';
import 'video_player_iptv_memory_test.dart' show iptvEpisode;

void main() {
  for (final titleOnly in [false, true]) {
    testWidgets(
      'P15 review2 exactly two audio rows apply immediately titleOnly=$titleOnly',
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
            mk.Tracks(
              audio: [
                const mk.AudioTrack('1', 'English', 'eng'),
                mk.AudioTrack(
                  '2',
                  titleOnly ? 'French' : 'Commentary',
                  titleOnly ? 'deu' : 'fra',
                ),
              ],
            ),
          );
          await d.settle();
          final before = d.timed.length;
          await d.zap(1);
          await d.settle();
          expect(
            d.timed
                .skip(before)
                .where(
                  (v) =>
                      d.timerOwners[v.$2]!.contains('applyIptvAudioPreference'),
                ),
            isEmpty,
            reason:
                'Two rows already satisfy enumeration; no polling is needed',
          );
          expect(d.player.state.track.audio.id, '2');
          expect(d.errors, isEmpty);
        } finally {
          await d.close();
        }
      },
    );
  }
}
