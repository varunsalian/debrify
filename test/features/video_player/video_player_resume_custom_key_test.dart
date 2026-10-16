import 'package:debrify/models/custom_series_identity.dart';
import 'package:debrify/services/storage/movie_progress_storage.dart';
import 'package:debrify/services/storage/video_resume_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/local_completion_driver.dart';
import 'support/trakt_transport.dart';
import 'support/video_player_environment.dart';

void main() {
  TraktTestTransport.install();
  for (final coordinates in <(int?, int?)>[(null, null), (2, 3)]) {
    testWidgets(
      'Resume P14 custom key ${coordinates.$1}/${coordinates.$2} owns the completion cleanup bookmark',
      (t) async {
        final f = VideoPlayerEnvironment();
        final d = LocalCompletionDriver(t, f);
        await d.initialize();
        final id = const CustomSeriesIdentity('p14', 'catalog').id;
        final key = '$id:S${coordinates.$1}:E${coordinates.$2}';
        final screen = completionScreen(
          id: id,
          type: 'movie',
          title: 'P14 custom key',
          season: coordinates.$1,
          episode: coordinates.$2,
        );
        try {
          await f.finish(
            t,
            VideoResumeStorage.upsertVideoResume(key, {'positionMs': 111}),
          );
          await f.finish(
            t,
            VideoResumeStorage.upsertVideoResume(screen.videoUrl, {
              'positionMs': 222,
            }),
          );
          await d.mount(screen);
          expect(
            d.seeks,
            isEmpty,
            reason:
                'Custom local restore never inherits legacy URL or custom bookmark rows',
          );
          expect(
            (await f.finish(
              t,
              VideoResumeStorage.getVideoResume(key),
            ))?['positionMs'],
            111,
          );
          await d.percent(85);
          await f.until(
            t,
            () =>
                d.f.player.state.position ==
                const Duration(milliseconds: 1020000),
          );
          expect(
            await f.finish(t, MovieProgressStorage.isMovieFinished(id)),
            isTrue,
          );
          expect(
            await f.finish(t, VideoResumeStorage.getVideoResume(key)),
            isNull,
          );
          expect(
            (await f.finish(
              t,
              VideoResumeStorage.getVideoResume(screen.videoUrl),
            ))?['positionMs'],
            222,
          );
        } finally {
          await d.close();
        }
      },
    );
  }
}
