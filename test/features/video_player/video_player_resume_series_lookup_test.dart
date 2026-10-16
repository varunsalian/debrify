import 'package:debrify/models/playback_resume_policy.dart';
import 'package:debrify/models/playlist_view_mode.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/storage/series_progress_storage.dart';
import 'package:debrify/services/storage/video_progress_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/fake_player.dart';
import 'support/video_player_environment.dart';

void main() {
  for (final shape in ['single episode', 'parsed playlist', 'raw playlist']) {
    for (final policy in PlaybackResumePolicy.values) {
      testWidgets(
        'Resume P14 $shape resolves episode versus exact video under $policy',
        (t) async {
          final f = VideoPlayerEnvironment(native: true);
          await t.runAsync(f.initialize);
          const title = 'P14 exact show', id = 'tt1415001';
          final playlist = shape == 'single episode'
              ? null
              : shape == 'parsed playlist'
              ? [
                  const PlaylistEntry(
                    url: 'https://player.test/p14-series.mp4',
                    title: 'P14.Exact.Show.S02E03.mkv',
                  ),
                  const PlaylistEntry(
                    url: 'https://player.test/p14-series-next.mp4',
                    title: 'P14.Exact.Show.S02E04.mkv',
                  ),
                ]
              : [
                  const PlaylistEntry(
                    url: 'https://player.test/p14-series.mp4',
                    title: 'Unparsed episode',
                  ),
                ];
          try {
            await f.finish(
              t,
              SeriesProgressStorage.saveSeriesPlaybackState(
                seriesTitle: title,
                imdbId: id,
                season: 2,
                episode: 3,
                positionMs: 240000,
                durationMs: 1200000,
                speed: 1.75,
                aspect: 'cinemaZoom',
              ),
            );
            if (shape == 'raw playlist') {
              await f.finish(
                t,
                VideoProgressStorage.saveVideoPlaybackState(
                  videoTitle: 'Unparsed episode'.hashCode.toString(),
                  videoUrl: playlist!.first.url,
                  imdbId: id,
                  positionMs: 120000,
                  durationMs: 1200000,
                  speed: 1.25,
                  aspect: 'cover',
                ),
              );
            }
            await f.mount(
              t,
              VideoPlayerScreen(
                videoUrl: 'https://player.test/p14-series.mp4',
                title: title,
                contentTitle: title,
                contentImdbId: id,
                contentType: 'series',
                contentSeason: 2,
                contentEpisode: 3,
                playlist: playlist,
                viewMode: shape == 'raw playlist' ? PlaylistViewMode.raw : null,
                resumePolicy: policy,
              ),
            );
            await f.actions.settle(t);
            final exact =
                shape == 'raw playlist' &&
                policy == PlaybackResumePolicy.sourceSpecific;
            expect(
              f.player.calls.where((c) => c.$1 == 'seek').map((c) => c.$2),
              contains(Duration(milliseconds: exact ? 120000 : 240000)),
            );
            expect(
              f.player.calls.where((c) => c.$1 == 'rate').map((c) => c.$2),
              contains(exact ? 1.25 : 1.75),
            );
            expect(
              (f.player.platform as FakeNativePlayer).properties['video-zoom'],
              exact ? '0.000000' : '0.415037',
            );
          } finally {
            await f.close(t);
          }
        },
      );
    }
  }
  for (final incomplete in [false, true]) {
    testWidgets(
      'Resume P14 canonical raw episode fallback uses its mirrored video row incomplete=$incomplete',
      (t) async {
        final f = VideoPlayerEnvironment(native: true);
        await t.runAsync(f.initialize);
        try {
          await f.finish(
            t,
            VideoProgressStorage.saveVideoPlaybackState(
              videoTitle: 'Unparsed episode'.hashCode.toString(),
              videoUrl: 'https://player.test/p14-series.mp4',
              positionMs: 180000,
              durationMs: 1200000,
              speed: 1.5,
              aspect: '4:3',
            ),
          );
          await f.mount(
            t,
            VideoPlayerScreen(
              videoUrl: 'https://player.test/p14-series.mp4',
              title: 'P14 empty series',
              contentType: 'series',
              contentImdbId: 'tt1415002',
              contentSeason: 2,
              contentEpisode: incomplete ? null : 3,
              playlist: const [
                PlaylistEntry(
                  url: 'https://player.test/p14-series.mp4',
                  title: 'Unparsed episode',
                ),
              ],
              viewMode: PlaylistViewMode.raw,
              resumePolicy: PlaybackResumePolicy.catalogCanonical,
            ),
          );
          await f.actions.settle(t);
          expect(
            f.player.calls.where((c) => c.$1 == 'seek').map((c) => c.$2),
            contains(const Duration(minutes: 3)),
          );
          expect(
            f.player.calls.where((c) => c.$1 == 'rate').map((c) => c.$2),
            contains(1.5),
          );
        } finally {
          await f.close(t);
        }
      },
    );
  }
}
