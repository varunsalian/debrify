import 'package:debrify/services/storage/iptv_audio_storage.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'support/iptv_workflow_driver.dart';
import 'video_player_iptv_memory_test.dart' show iptvEpisode;

void main() {
  for (final mode in ['title', 'first', 'missing']) {
    testWidgets('P15 review2 series audio matching respects $mode metadata', (
      t,
    ) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      try {
        await d.f.finish(
          t,
          IptvAudioStorage.setIptvSeriesAudioLanguage(
            'provider::series',
            mode == 'missing' ? 'zul' : 'fra',
          ),
        );
        await d.mount([iptvEpisode(1), iptvEpisode(2)]);
        d.player.publishTracks(
          mk.Tracks(
            audio: [
              const mk.AudioTrack('auto', null, null),
              const mk.AudioTrack('no', null, null),
              const mk.AudioTrack('1', 'English', 'eng'),
              mk.AudioTrack('2', 'French', mode == 'title' ? 'deu' : 'fra'),
              const mk.AudioTrack('3', 'French', 'fra'),
            ],
          ),
        );
        await d.settle();
        final before = d.calls('audio').length;
        await d.zap(1);
        await d.settle();
        final picks = d
            .calls('audio')
            .skip(before)
            .map((c) => (c.$2 as mk.AudioTrack).id)
            .toList();
        expect(picks, mode == 'missing' ? isEmpty : isNotEmpty);
        if (mode != 'missing') expect(picks, everyElement('2'));
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    });
  }
}
