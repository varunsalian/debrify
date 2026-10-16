import 'package:debrify/services/storage/iptv_audio_storage.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'support/iptv_workflow_driver.dart';
import 'video_player_iptv_memory_test.dart' show iptvEpisode;

void main() {
  testWidgets(
    'P15 review2 a sole matching audio row remains untouched after all twenty polls',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      try {
        await d.f.finish(
          t,
          IptvAudioStorage.setIptvSeriesAudioLanguage(
            'provider::series',
            'eng',
          ),
        );
        await d.mount([iptvEpisode(1), iptvEpisode(2)]);
        d.player.publishTracks(
          const mk.Tracks(audio: [mk.AudioTrack('1', 'English', 'eng')]),
        );
        await d.settle();
        final before = d.calls('audio').length;
        final timers = d.timed.length;
        await d.zap(1);
        for (var i = 0; i < 20; i++) {
          await d.advance(const Duration(milliseconds: 100));
        }
        await d.settle();
        expect(
          d.timed
              .skip(timers)
              .where(
                (v) =>
                    d.timerOwners[v.$2]!.contains('applyIptvAudioPreference'),
              ),
          hasLength(20),
        );
        expect(d.calls('audio'), hasLength(before));
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );
}
