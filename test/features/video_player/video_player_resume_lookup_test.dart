import 'package:debrify/models/playback_resume_policy.dart';
import 'package:debrify/models/custom_series_identity.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/storage/playback_state_store.dart';
import 'package:debrify/services/storage/video_progress_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/fake_player.dart';
import 'support/video_player_environment.dart';
import 'support/resume_driver.dart';

void main() {
  for (final shape in [
    'single',
    'one playlist entry',
    'two playlist entries',
  ]) {
    for (final policy in PlaybackResumePolicy.values) {
      testWidgets(
        'Resume P14 $shape lookup obeys $policy while retaining exact presentation',
        (t) async {
          final f = VideoPlayerEnvironment(native: true);
          await t.runAsync(f.initialize);
          final diagnostics = ResumeVerifierDriver(t, f)..captureLogs();
          final playlist = shape == 'single'
              ? null
              : [
                  const PlaylistEntry(
                    url: 'https://player.test/p14-exact.mp4',
                    title: 'Exact movie.mkv',
                  ),
                  if (shape == 'two playlist entries')
                    const PlaylistEntry(
                      url: 'https://player.test/p14-second.mp4',
                      title: 'Second movie.mkv',
                    ),
                ];
          final exact = shape == 'single'
              ? 'Exact movie'
              : 'Exact movie'.hashCode.toString();
          const id = 'tt1414001';
          try {
            await f.finish(
              t,
              VideoProgressStorage.saveVideoPlaybackState(
                videoTitle: exact,
                videoUrl: 'https://player.test/p14-exact.mp4',
                imdbId: id,
                positionMs: 120000,
                durationMs: 1200000,
                speed: 1.25,
                aspect: 'cover',
              ),
            );
            await f.finish(
              t,
              VideoProgressStorage.saveVideoPlaybackState(
                videoTitle: 'Other canonical source',
                videoUrl: 'https://player.test/p14-other.mp4',
                imdbId: id,
                positionMs: 240000,
                durationMs: 1200000,
                speed: 1.75,
                aspect: 'cinemaZoom',
              ),
            );
            final map = await f.finish(
              t,
              PlaybackStateStore.getPlaybackStateMap(),
            );
            for (final row in map.values) {
              (row as Map)['updatedAt'] = row['title'] == exact ? 100 : 200;
            }
            await f.finish(t, PlaybackStateStore.savePlaybackStateMap(map));
            await f.mount(
              t,
              VideoPlayerScreen(
                videoUrl: 'https://player.test/p14-exact.mp4',
                title: 'Exact movie',
                contentType: 'movie',
                contentImdbId: id,
                playlist: playlist,
                resumePolicy: policy,
              ),
            );
            await f.actions.settle(t);
            final canonical =
                policy == PlaybackResumePolicy.catalogCanonical &&
                shape != 'two playlist entries';
            expect(
              diagnostics.logs,
              contains(
                'Resume Load: fetching state for resumeId=$exact policy=${canonical ? 'catalogCanonical' : 'sourceSpecific'}',
              ),
            );
            expect(
              diagnostics.logs,
              contains(
                'Resume Load: found state for resumeId=$exact updatedAt=${canonical ? 200 : 100}',
              ),
            );
            expect(
              f.player.calls.where((c) => c.$1 == 'seek').map((c) => c.$2),
              contains(Duration(milliseconds: canonical ? 240000 : 120000)),
            );
            expect(
              f.player.calls.where((c) => c.$1 == 'rate').map((c) => c.$2),
              contains(1.25),
            );
            expect(
              (f.player.platform as FakeNativePlayer).properties['video-zoom'],
              '0.000000',
            );
          } finally {
            diagnostics.restoreLogs();
            await f.close(t);
          }
        },
      );
    }
  }
  for (final id in [
    'medialibrary:p14',
    const CustomSeriesIdentity('p14', 'catalog').id,
  ]) {
    testWidgets(
      'Resume P14 native identity $id reads its latest canonical row and never inherits the URL bookmark',
      (t) async {
        final f = VideoPlayerEnvironment(native: true);
        await t.runAsync(f.initialize);
        final diagnostics = ResumeVerifierDriver(t, f)..captureLogs();
        try {
          await f.finish(
            t,
            VideoProgressStorage.saveVideoPlaybackState(
              videoTitle: 'Exact movie',
              videoUrl: 'https://player.test/p14-native.mp4',
              imdbId: id,
              positionMs: 120000,
              durationMs: 1200000,
              speed: 1.25,
              aspect: 'cover',
            ),
          );
          await f.finish(
            t,
            VideoProgressStorage.saveVideoPlaybackState(
              videoTitle: 'Other native source',
              videoUrl: 'https://player.test/p14-other.mp4',
              imdbId: id,
              positionMs: 240000,
              durationMs: 1200000,
              speed: 1.75,
              aspect: 'cinemaZoom',
            ),
          );
          final map = await f.finish(
            t,
            PlaybackStateStore.getPlaybackStateMap(),
          );
          for (final row in map.values) {
            (row as Map)['updatedAt'] = row['title'] == 'Exact movie'
                ? 100
                : 200;
          }
          await f.finish(t, PlaybackStateStore.savePlaybackStateMap(map));
          await f.mount(
            t,
            VideoPlayerScreen(
              videoUrl: 'https://player.test/p14-native.mp4',
              title: 'Exact movie',
              contentType: 'movie',
              contentImdbId: id,
            ),
          );
          await f.actions.settle(t);
          expect(
            diagnostics.logs,
            contains(
              'Resume Load: fetching state for resumeId=Exact movie policy=sourceSpecific',
            ),
          );
          expect(
            diagnostics.logs,
            contains(
              'Resume Load: found state for resumeId=Exact movie updatedAt=200',
            ),
          );
          expect(
            f.player.calls.where((c) => c.$1 == 'seek').map((c) => c.$2),
            contains(const Duration(minutes: 4)),
          );
          expect(
            f.player.calls.where((c) => c.$1 == 'rate').map((c) => c.$2),
            contains(1.75),
          );
          expect(
            (f.player.platform as FakeNativePlayer).properties['video-zoom'],
            '0.415037',
          );
        } finally {
          diagnostics.restoreLogs();
          await f.close(t);
        }
      },
    );
  }
}
