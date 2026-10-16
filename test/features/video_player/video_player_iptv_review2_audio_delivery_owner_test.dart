import 'package:debrify/services/storage/iptv_audio_storage.dart';
import 'support/iptv_storage_driver.dart';
import 'support/iptv_workflow_driver.dart';
import 'video_player_iptv_memory_test.dart' show iptvEpisode, iptvAudioTracks;

void main() {
  for (final disposed in [false, true]) {
    testWidgets(
      'P15 review2 a delivered stored audio choice rechecks disposed=$disposed ownership',
      (t) async {
        final d = IptvWorkflowDriver(t);
        await d.initialize();
        final read = IptvAwaitDelivery(
          'applyIptvAudioPreference',
          (v) => v == 'fra',
        );
        try {
          await d.f.finish(
            t,
            IptvAudioStorage.setIptvSeriesAudioLanguage(
              'provider::series',
              'fra',
            ),
          );
          await d.mount([iptvEpisode(1), iptvEpisode(2)]);
          iptvAudioTracks(d);
          await d.settle();
          await read.run(() => d.zap(1));
          await d.f.until(t, () => read.pending.isNotEmpty);
          if (disposed) {
            await d.retire();
          } else {
            await d.pick([iptvChannel(90)], 0);
          }
          final before = d.calls('audio').length;
          read.release();
          await d.settle();
          expect(d.calls('audio'), hasLength(before));
          expect(d.errors, isEmpty);
        } finally {
          read.release();
          await d.close();
        }
      },
    );
  }
}
