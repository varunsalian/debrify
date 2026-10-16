import 'package:debrify/models/playback_resume_policy.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/storage/playback_state_store.dart';
import 'package:debrify/services/storage/video_progress_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/video_player_environment.dart';

void main() {
  testWidgets(
    'Resume P14 single series without episode coordinates uses its mirrored title even under canonical policy',
    (t) async {
      final f = VideoPlayerEnvironment();
      await t.runAsync(f.initialize);
      const id = 'tt1415050', url = 'https://player.test/p14-series-legacy.mp4';
      try {
        for (final (title, pos, speed) in [
          ('P14 series legacy title', 180000, 1.5),
          ('Other mirrored episode', 360000, 1.75),
        ]) {
          await f.finish(
            t,
            VideoProgressStorage.saveVideoPlaybackState(
              videoTitle: title,
              videoUrl: url,
              imdbId: id,
              positionMs: pos,
              durationMs: 1200000,
              speed: speed,
              aspect: 'contain',
            ),
          );
        }
        final map = await f.finish(t, PlaybackStateStore.getPlaybackStateMap());
        for (final raw in map.values) {
          (raw as Map)['updatedAt'] = raw['title'] == 'P14 series legacy title'
              ? 100
              : 200;
        }
        await f.finish(t, PlaybackStateStore.savePlaybackStateMap(map));
        await f.mount(
          t,
          const VideoPlayerScreen(
            videoUrl: url,
            title: 'P14 series legacy title',
            contentType: 'series',
            contentImdbId: id,
            contentSeason: 2,
            resumePolicy: PlaybackResumePolicy.catalogCanonical,
          ),
        );
        await f.actions.settle(t);
        expect(f.player.calls.where((c) => c.$1 == 'seek').map((c) => c.$2), [
          const Duration(minutes: 3),
        ]);
        expect(f.player.calls.where((c) => c.$1 == 'rate').map((c) => c.$2), [
          1.5,
        ]);
      } finally {
        await f.close(t);
      }
    },
  );
}
