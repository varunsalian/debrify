import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/storage/video_progress_storage.dart';
import 'package:debrify/services/storage/video_resume_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/player_actions.dart';
import 'support/video_player_environment.dart';

void main() {
  for (final type in ['movie', 'series']) {
    testWidgets(
      'Resume P14 empty $type title restores and saves the Unknown Video row',
      (t) async {
        final f = VideoPlayerEnvironment();
        await t.runAsync(f.initialize);
        const url = 'https://player.test/p14-empty-title.mp4';
        try {
          await f.finish(
            t,
            VideoProgressStorage.saveVideoPlaybackState(
              videoTitle: 'Unknown Video',
              videoUrl: url,
              positionMs: 180000,
              durationMs: 1200000,
              speed: 1.5,
              aspect: 'contain',
            ),
          );
          await f.mount(
            t,
            VideoPlayerScreen(videoUrl: url, title: '', contentType: type),
          );
          await f.actions.settle(t);
          expect(f.player.calls.where((c) => c.$1 == 'seek').map((c) => c.$2), [
            const Duration(minutes: 3),
          ]);
          expect(
            f.player.calls.where((c) => c.$1 == 'rate').map((c) => c.$2),
            contains(1.5),
          );
          f.player.state = f.player.state.copyWith(
            position: const Duration(minutes: 5),
          );
          f.player.emit('position', f.player.state.position);
          await f.advance(t);
          playerControls(t).onPlayPause();
          await f.actions.settle(t);
          expect(
            (await f.finish(
              t,
              VideoProgressStorage.getVideoPlaybackState(
                videoTitle: 'Unknown Video',
              ),
            ))?['positionMs'],
            300000,
          );
          expect(
            (await f.finish(
              t,
              VideoResumeStorage.getVideoResume(url),
            ))?['positionMs'],
            300000,
          );
        } finally {
          await f.close(t);
        }
      },
    );
  }
}
