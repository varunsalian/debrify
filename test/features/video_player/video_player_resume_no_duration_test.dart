import 'package:debrify/services/storage/tracking_source_storage.dart';
import 'package:debrify/services/tracking_source_policy.dart';
import 'support/local_completion_driver.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/storage/video_resume_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/fake_player.dart';
import 'support/video_player_environment.dart';

void main() {
  testWidgets(
    'Resume P14 unavailable duration restores presentation but never issues a resume seek',
    (t) async {
      late final VideoPlayerEnvironment f;
      f = VideoPlayerEnvironment(
        native: true,
        configurePlayer: (p) {
          p.onOpen = () {
            p.publishFrame(duration: Duration.zero);
            f.controllers.last.publishFrame();
          };
        },
      );
      await t.runAsync(f.initialize);
      await f.finish(
        t,
        TrackingSourceStorage.setWatchProgressSource(WatchProgressSource.smart),
      );
      var percentPolicyReads = 0;
      final reads = CompletionDelivery('currentEpisode', (value) {
        if (value is TrackingSourcePolicy) percentPolicyReads++;
        return false;
      });
      const url = 'https://player.test/p14-no-duration.mp4';
      try {
        await f.finish(
          t,
          VideoResumeStorage.upsertVideoResume(url, {
            'positionMs': 180000,
            'speed': 1.5,
            'aspect': 'cinemaZoom',
          }),
        );
        await reads.run(
          () => f.mount(
            t,
            const VideoPlayerScreen(videoUrl: url, title: 'P14 no duration'),
          ),
        );
        for (var i = 0; i < 180; i++) {
          await f.advance(t, const Duration(milliseconds: 100));
        }
        expect(
          f.player.calls.where((c) => c.$1 == 'rate'),
          isEmpty,
          reason:
              'The original duration wait still blocks presentation restoration while duration is unavailable',
        );
        for (
          var i = 0;
          i < 170 && !f.player.calls.any((c) => c.$1 == 'rate' && c.$2 == 1.5);
          i++
        ) {
          await f.advance(t, const Duration(milliseconds: 100));
        }
        await f.actions.settle(t);
        expect(
          f.player.calls.where((c) => c.$1 == 'rate').map((c) => c.$2),
          contains(1.5),
        );
        expect(f.player.state.duration, Duration.zero);
        expect(
          percentPolicyReads,
          3,
          reason:
              'A zero-duration restore exits before the finished-window guide fallback can read each policy again',
        );
        expect(f.player.calls.where((c) => c.$1 == 'seek'), isEmpty);
        expect(
          (f.player.platform as FakeNativePlayer).properties['video-zoom'],
          '0.415037',
        );
        expect(
          (await f.finish(
            t,
            VideoResumeStorage.getVideoResume(url),
          ))?['positionMs'],
          180000,
        );
      } finally {
        await f.close(t);
      }
    },
  );
}
