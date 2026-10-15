import 'package:debrify/services/storage/tracking_source_storage.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/storage/tracker_episode_progress_storage.dart';
import 'package:debrify/services/storage/video_resume_storage.dart';
import 'package:debrify/services/tracking_source_policy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/local_completion_driver.dart';
import 'support/trakt_transport.dart';
import 'support/video_player_environment.dart';

void main() {
  TraktTestTransport.install();
  for (final localPolicy in [false, true]) {
    testWidgets(
      localPolicy
          ? 'Resume P14 rewatch arbitration loads the three policy-masked guide snapshots'
          : 'Resume P14 rewatch arbitration reuses the three resolved percent policy reads',
      (t) async {
        final f = VideoPlayerEnvironment();
        final d = LocalCompletionDriver(t, f);
        await d.initialize();
        if (localPolicy) {
          await f.finish(
            t,
            TrackingSourceStorage.setWatchProgressSource(
              WatchProgressSource.local,
            ),
          );
        }
        var policyReads = 0;
        var snapshotReads = 0;
        // Observe the real reader's policy completion through the shared barrier
        // harness, without holding/replacing its result or invoking private code.
        final reads = CompletionDelivery('currentEpisode', (value) {
          if (value is TrackingSourcePolicy) policyReads++;
          if (value is Map) snapshotReads++;
          return false;
        });
        const id = 'tt1419910',
            url = 'https://player.test/p14-reader-reuse.mp4';
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
            TrackerEpisodeProgressStorage.saveEpisodeMdblistProgress(
              imdbId: id,
              percents: {'2_3': 0},
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
            VideoResumeStorage.upsertVideoResume(url, {
              'positionMs': 1100000,
              'speed': 1.0,
              'aspect': 'contain',
            }),
          );
          await reads.run(
            () => f.mount(
              t,
              const VideoPlayerScreen(
                videoUrl: url,
                title: 'P14 reader reuse',
                contentImdbId: id,
                contentType: 'series',
                contentSeason: 2,
                contentEpisode: 3,
              ),
            ),
          );
          await f.actions.settle(t);
          expect(
            f.player.calls.where((c) => c.$1 == 'seek').map((c) => c.$2),
            localPolicy ? isEmpty : contains(const Duration(minutes: 4)),
          );
          expect(
            snapshotReads,
            3,
            reason:
                'Guide readers still load each actual snapshot before policy-masking its result',
          );
          expect(
            policyReads,
            3,
            reason:
                'Rewatch consumes the already resolved non-null provider percentages without an extra async policy read',
          );
        } finally {
          await d.close();
        }
      },
    );
  }
}
