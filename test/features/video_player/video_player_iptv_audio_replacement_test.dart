import 'package:debrify/models/android_video_renderer_mode.dart';
import 'package:debrify/services/storage/player_settings_storage.dart';
import 'package:debrify/services/storage/iptv_audio_storage.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'support/iptv_workflow_driver.dart';
import 'support/local_completion_driver.dart';
import 'video_player_iptv_memory_test.dart' show iptvEpisode;

void main() {
  testWidgets(
    'P15 audio storage held across renderer replacement applies old captured tracks through the live player',
    (t) async {
      var created = 0;
      final d = IptvWorkflowDriver(
        t,
        native: true,
        configurePlayer: (p) {
          p.publishTracks(
            mk.Tracks(
              subtitle: const [mk.SubtitleTrack('1', 'English', 'eng')],
              audio: ++created == 1
                  ? const [
                      mk.AudioTrack('1', 'English', 'eng'),
                      mk.AudioTrack('2', 'French', 'fra'),
                    ]
                  : const [mk.AudioTrack('9', 'German', 'deu')],
            ),
          );
        },
      );
      await d.initialize();
      VpS2Hooks.install(VpS2Hooks(android: () => true, ios: () => false));
      final held = CompletionDelivery(
        'applyIptvAudioPreference',
        (v) => v == 'fra',
      );
      try {
        await d.f.finish(
          t,
          PlayerSettingsStorage.setAndroidVideoRendererMode(
            AndroidVideoRendererMode.directSurface,
          ),
        );
        await d.f.finish(
          t,
          IptvAudioStorage.setIptvSeriesAudioLanguage(
            'provider::series',
            'fra',
          ),
        );
        await d.mount([iptvEpisode(1), iptvEpisode(2)]);
        final old = d.player;
        final s = await d.guide();
        await d.f.finish(
          t,
          d.observe(
            () => held.run(
              () => s.onChannelSelected([iptvEpisode(1), iptvEpisode(2)], 1),
            ),
          ),
        );
        await d.f.until(t, () => held.pending.isNotEmpty);
        old.state = old.state.copyWith(position: Duration.zero);
        old.emit('position', Duration.zero);
        old.emit('error', 'synthetic MediaCodec video output failure');
        await d.f.until(t, () => d.f.players.length == 2);
        d.player.deliverReady();
        await d.f.until(t, () => d.calls('open').isNotEmpty);
        await d.settle();
        expect(old.disposed.isCompleted, true);
        expect(
          d.player.state.tracks.audio.map((a) => a.id),
          isNot(contains('2')),
        );
        held.release();
        await d.settle();
        expect(
          d.calls('audio').any((c) => (c.$2 as mk.AudioTrack).id == '2'),
          true,
        );
        expect(d.errors, isEmpty);
      } finally {
        held.release();
        await d.close();
        VpS2Hooks.install(null);
      }
    },
  );
}
