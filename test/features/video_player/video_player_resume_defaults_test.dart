import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/screens/video_player/models/gesture_state.dart';
import 'package:debrify/services/storage/playback_state_store.dart';
import 'package:debrify/services/storage/video_resume_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/display_mode_driver.dart';
import 'support/fake_player.dart';
import 'support/player_actions.dart';
import 'support/video_player_environment.dart';

void main() {
  testWidgets(
    'Resume P14 older enhanced row without presentation fields restores contain and skips rate 1',
    (t) async {
      final f = VideoPlayerEnvironment(native: true);
      await t.runAsync(f.initialize);
      final display = DisplayModeDriver(t, f);
      const url = 'https://player.test/p14-default-fields.mp4';
      try {
        await display.defaults(aspect: AspectMode.cinemaZoom.index);
        await f.finish(
          t,
          PlaybackStateStore.savePlaybackStateMap({
            'video_p14_default_fields': {
              'type': 'video',
              'title': 'P14 default fields',
              'positionMs': 180000,
              'durationMs': 1200000,
            },
          }),
        );
        await f.mount(
          t,
          const VideoPlayerScreen(videoUrl: url, title: 'P14 default fields'),
        );
        await f.actions.settle(t);
        expect(
          f.player.calls.where((c) => c.$1 == 'seek').map((c) => c.$2),
          contains(const Duration(minutes: 3)),
        );
        expect(f.player.calls.where((c) => c.$1 == 'rate'), isEmpty);
        expect(
          (f.player.platform as FakeNativePlayer).properties['video-zoom'],
          '0.000000',
        );
        playerControls(t).onPlayPause();
        await f.actions.settle(t);
        final row = await f.finish(t, VideoResumeStorage.getVideoResume(url));
        expect(row?['speed'], 1.0);
        expect(row?['aspect'], 'contain');
        expect(row?['positionMs'], 180000);
      } finally {
        await f.close(t);
      }
    },
  );
}
