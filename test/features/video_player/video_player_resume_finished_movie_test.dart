import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/storage/movie_progress_storage.dart';
import 'package:debrify/services/storage/video_progress_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/display_mode_driver.dart';
import 'support/fake_player.dart';
import 'support/video_player_environment.dart';

void main() {
  for (final launchPromise in [false, true]) {
    testWidgets(
      'Resume P14 finished movie skips local presentation while respecting explicit tracker launch=$launchPromise',
      (t) async {
        final f = VideoPlayerEnvironment(native: true);
        await t.runAsync(f.initialize);
        final display = DisplayModeDriver(t, f);
        const id = 'tt1419901', url = 'https://player.test/p14-finished.mp4';
        try {
          await display.defaults();
          await f.finish(t, MovieProgressStorage.markMovieAsFinished(id));
          await f.finish(
            t,
            VideoProgressStorage.saveVideoPlaybackState(
              videoTitle: 'P14 finished movie',
              videoUrl: url,
              imdbId: id,
              positionMs: 480000,
              durationMs: 1200000,
              speed: 1.5,
              aspect: 'cinemaZoom',
            ),
          );
          await f.mount(
            t,
            VideoPlayerScreen(
              videoUrl: url,
              title: 'P14 finished movie',
              contentImdbId: id,
              contentType: 'movie',
              traktProgressPercent: launchPromise ? 20 : null,
            ),
          );
          await f.actions.settle(t);
          final seeks = f.player.calls
              .where((c) => c.$1 == 'seek')
              .map((c) => c.$2);
          expect(
            seeks,
            launchPromise ? contains(const Duration(minutes: 4)) : isEmpty,
          );
          expect(f.player.calls.where((c) => c.$1 == 'rate'), isEmpty);
          expect(
            (f.player.platform as FakeNativePlayer).properties['video-zoom'],
            '0.000000',
          );
          expect(
            await f.finish(t, MovieProgressStorage.isMovieFinished(id)),
            isTrue,
          );
        } finally {
          await f.close(t);
        }
      },
    );
  }
}
