import 'package:debrify/services/storage/iptv_audio_storage.dart';
import 'package:debrify/services/storage/subtitle_settings_storage.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'support/iptv_workflow_driver.dart';
import 'video_player_iptv_memory_test.dart' show iptvEpisode, iptvAudioTracks;

void main() {
  for (final stored in [null, 'eng']) {
    testWidgets('P15 addendum session audio beats differing storage $stored', (
      t,
    ) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      try {
        await d.f.finish(
          t,
          SubtitleSettingsStorage.setDefaultAudioLanguage('eng'),
        );
        await d.mount([iptvEpisode(1), iptvEpisode(2, series: 'other')]);
        iptvAudioTracks(d);
        await d.settle();
        final menu = await openPlayerMenu(t, d.f);
        await d.f.finish(t, menu.onAudioSelected('2', '1'));
        menu.onClose();
        await d.settle();
        expect(
          await d.f.finish(
            t,
            IptvAudioStorage.getIptvSeriesAudioLanguage('provider::series'),
          ),
          'fra',
        );
        if (stored != null) {
          await d.f.finish(
            t,
            IptvAudioStorage.setIptvSeriesAudioLanguage(
              'provider::other',
              stored,
            ),
          );
        }
        expect(
          await d.f.finish(
            t,
            IptvAudioStorage.getIptvSeriesAudioLanguage('provider::other'),
          ),
          stored,
        );
        final before = d.calls('audio').length;
        await d.zap(1);
        await d.settle();
        expect(
          d.calls('audio').skip(before).map((v) => (v.$2 as mk.AudioTrack).id),
          contains('2'),
        );
        expect(d.player.state.track.audio.id, '2');
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    });
  }
}
