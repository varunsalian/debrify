import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/storage/tracker_episode_progress_storage.dart';
import 'package:debrify/services/storage/video_resume_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/trakt_transport.dart';
import 'support/video_player_environment.dart';

void main() {
  TraktTestTransport.install();
  testWidgets(
    'Resume P14 Trakt rewatch migrates a local bookmark at the exact 90 percent boundary',
    (t) async {
      final f = VideoPlayerEnvironment();
      await t.runAsync(f.initialize);
      const id = 'tt1419920', url = 'https://player.test/p14-rewatch-edge.mp4';
      try {
        await f.finish(
          t,
          TrackerEpisodeProgressStorage.saveEpisodeTraktProgress(
            imdbId: id,
            percents: {'2_3': 20},
          ),
        );
        await f.finish(
          t,
          TrackerEpisodeProgressStorage.saveEpisodeSimklProgress(
            imdbId: id,
            percents: {'2_3': 0},
          ),
        );
        await f.finish(
          t,
          TrackerEpisodeProgressStorage.saveEpisodeMdblistProgress(
            imdbId: id,
            percents: {'2_3': 0},
          ),
        );
        await f.finish(
          t,
          VideoResumeStorage.upsertVideoResume(url, {
            'positionMs': 1080000,
            'speed': 1.0,
            'aspect': 'contain',
          }),
        );
        await f.mount(
          t,
          const VideoPlayerScreen(
            videoUrl: url,
            title: 'P14 rewatch edge',
            contentImdbId: id,
            contentType: 'series',
            contentSeason: 2,
            contentEpisode: 3,
          ),
        );
        await f.actions.settle(t);
        expect(f.player.calls.where((c) => c.$1 == 'seek').map((c) => c.$2), [
          const Duration(minutes: 4),
        ]);
        expect(
          (await f.finish(
            t,
            VideoResumeStorage.getVideoResume(url),
          ))?['positionMs'],
          1080000,
          reason: 'Rewatch migration is in-memory until an explicit save',
        );
      } finally {
        await f.close(t);
      }
    },
  );
}
