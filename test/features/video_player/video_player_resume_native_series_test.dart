import 'package:debrify/models/custom_series_identity.dart';
import 'package:debrify/models/playlist_view_mode.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/storage/series_progress_storage.dart';
import 'package:debrify/services/storage/video_progress_storage.dart';
import 'package:debrify/services/storage/video_resume_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/video_player_environment.dart';

void main() {
  for (final id in <String?>[
    null,
    'medialibrary:p14-series',
    const CustomSeriesIdentity('p14', 'series').id,
  ]) {
    for (final complete in [false, true]) {
      testWidgets(
        id == null
            ? 'Resume P14 raw series without catalog identity complete=$complete prefers the exact source'
            : 'Resume P14 native series $id complete=$complete never substitutes an exact raw video for episode identity',
        (t) async {
          final f = VideoPlayerEnvironment();
          await t.runAsync(f.initialize);
          const url = 'https://player.test/p14-native-series.mp4';
          final key = 'Native stream'.hashCode.toString();
          try {
            await f.finish(
              t,
              SeriesProgressStorage.saveSeriesPlaybackState(
                seriesTitle: 'P14 native series',
                imdbId: id,
                season: 2,
                episode: 3,
                positionMs: 240000,
                durationMs: 1200000,
                speed: 1.5,
                aspect: 'contain',
              ),
            );
            await f.finish(
              t,
              VideoProgressStorage.saveVideoPlaybackState(
                videoTitle: key,
                videoUrl: url,
                positionMs: 600000,
                durationMs: 1200000,
                speed: 1.75,
                aspect: 'cinemaZoom',
              ),
            );
            await f.finish(
              t,
              VideoResumeStorage.upsertVideoResume(key, {
                'positionMs': 900000,
                'speed': 2.0,
                'aspect': 'cover',
              }),
            );
            expect(
              (await f.finish(
                t,
                VideoProgressStorage.getVideoPlaybackState(videoTitle: key),
              ))?['positionMs'],
              600000,
              reason:
                  'The exact-source fixture must actually be addressable by its raw video key',
            );
            await f.mount(
              t,
              VideoPlayerScreen(
                videoUrl: url,
                title: 'P14 native series',
                contentTitle: 'P14 native series',
                contentType: 'series',
                contentImdbId: id,
                contentSeason: 2,
                contentEpisode: complete ? 3 : null,
                playlist: const [
                  PlaylistEntry(url: url, title: 'Native stream.mkv'),
                ],
                viewMode: PlaylistViewMode.raw,
              ),
            );
            await f.actions.settle(t);
            expect(
              f.player.calls.where((c) => c.$1 == 'seek').map((c) => c.$2),
              id == null
                  ? [const Duration(minutes: 10)]
                  : complete
                  ? [const Duration(minutes: 4)]
                  : isEmpty,
            );
            expect(
              f.player.calls.where((c) => c.$1 == 'rate').map((c) => c.$2),
              id == null
                  ? [1.75]
                  : complete
                  ? [1.5]
                  : isEmpty,
            );
            expect(
              (await f.finish(
                t,
                VideoResumeStorage.getVideoResume(key),
              ))?['positionMs'],
              900000,
            );
          } finally {
            await f.close(t);
          }
        },
      );
    }
  }
}
