import 'package:debrify/models/playlist_view_mode.dart';
import 'package:debrify/models/tracking_source.dart';
import 'package:debrify/screens/video_player/widgets/sleep_timer_sheet.dart';
import 'package:debrify/services/storage/local_completion_storage.dart';
import 'package:debrify/services/storage/movie_progress_storage.dart';
import 'package:debrify/services/storage/tracking_source_storage.dart';
import 'package:debrify/services/storage/video_resume_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/local_completion_driver.dart';
import 'support/sleep_timer_driver.dart';
import 'support/trakt_transport.dart';
import 'support/video_player_environment.dart';
import 'video_player_trakt_snapshots_test.dart' show traktPlaylist;

void main() {
  TraktTestTransport.install();
  for (final tracked in [false, true]) {
    testWidgets(
      'Completion series EOF ignores local enablement and position one-shot tracked=$tracked',
      (t) async {
        final f = VideoPlayerEnvironment();
        final d = LocalCompletionDriver(t, f);
        await d.initialize(
          target: tracked,
          targets: tracked ? {TrackingSource.trakt} : {},
        );
        try {
          await d.mount(completionScreen(type: 'series', trakt: tracked));
          await d.percent(85);
          await d.drain();
          final before = await d.finishedEpisode();
          expect(before, tracked ? isNull : isNotNull);
          final revision = LocalCompletionStorage.localCompletionRevision.value;
          await d.eof();
          await d.drain();
          final first = await d.finishedEpisode();
          expect(first?['finishedAt'], isA<int>());
          if (before != null) {
            expect(
              first!['finishedAt'] as int,
              greaterThan(before['finishedAt'] as int),
            );
          }
          expect(
            LocalCompletionStorage.localCompletionRevision.value,
            revision + 1,
          );
          await d.eof();
          await d.drain();
          final second = await d.finishedEpisode();
          expect(
            second!['finishedAt'] as int,
            greaterThan(first!['finishedAt'] as int),
          );
          expect(
            LocalCompletionStorage.localCompletionRevision.value,
            revision + 2,
          );
          if (tracked) {
            expect(d.actions, ['start', 'stop']);
            d.expectRequest(1, 'stop', 85, id: 'tt7100000');
          }
        } finally {
          await d.close();
        }
      },
    );
  }

  for (final type in ['movie', null, 'collection']) {
    for (final tracked in [true, false]) {
      testWidgets(
        'Completion EOF does not invent an episode for non-series type $type${tracked ? '' : ' local'}',
        (t) async {
          final f = VideoPlayerEnvironment();
          final d = LocalCompletionDriver(t, f);
          await d.initialize();
          try {
            final screen = completionScreen(type: type, trakt: tracked);
            await d.mount(screen);
            await d.percent(25);
            await f.finish(
              t,
              VideoResumeStorage.upsertVideoResume(screen.videoUrl, {
                'positionMs': 123,
                'durationMs': 1200000,
              }),
            );
            await d.eof();
            await d.drain();
            expect(await d.finishedEpisode(), isNull);
            expect(
              await f.finish(t, MovieProgressStorage.getFinishedMovieIds()),
              !tracked && type == 'movie' ? {'tt7100000'} : isEmpty,
            );
            expect(
              await f.finish(
                t,
                VideoResumeStorage.getVideoResume(screen.videoUrl),
              ),
              !tracked && type == 'movie' ? isNull : isNotNull,
            );
          } finally {
            await d.close();
          }
        },
      );
    }
  }

  testWidgets(
    'Completion overlapping EOFs each write and an older completion can overwrite the newer timestamp',
    (t) async {
      final f = VideoPlayerEnvironment();
      final d = LocalCompletionDriver(t, f);
      await d.initialize();
      final reads = CompletionDelivery(
        'markEpisodeAsFinished',
        (v) => v is Map<String, dynamic>,
      );
      reads.armed = false;
      reads.multiple = true;
      try {
        await d.observe(
          () => reads.run(() => f.mount(t, completionScreen(type: 'series'))),
        );
        await d.position(1000);
        await d.drain();
        await d.position(1000);
        await d.drain();
        await pickSleep(
          t,
          f,
          const SleepTimerSelection(SleepTimerMode.endOfItem),
        );
        reads.armed = true;
        await d.eof();
        await f.until(t, () => reads.pending.length == 1);
        final firstMax = DateTime.now().millisecondsSinceEpoch;
        await d.eof();
        await f.until(t, () => reads.pending.length == 2);
        final secondMax = DateTime.now().millisecondsSinceEpoch;
        expect(secondMax, greaterThan(firstMax));
        expect(await d.finishedEpisode(), isNull);
        final revision = LocalCompletionStorage.localCompletionRevision.value;
        reads.armed = false;
        reads.releaseAt(1);
        await d.drain();
        final newer = await d.finishedEpisode();
        expect(newer?['finishedAt'], inInclusiveRange(firstMax, secondMax));
        expect(
          LocalCompletionStorage.localCompletionRevision.value,
          revision + 1,
        );
        reads.releaseAt(0);
        await d.drain();
        final older = await d.finishedEpisode();
        expect(older?['finishedAt'], lessThan(newer!['finishedAt'] as int));
        expect(
          LocalCompletionStorage.localCompletionRevision.value,
          revision + 2,
        );
      } finally {
        reads.release();
        await d.close();
      }
    },
  );

  testWidgets(
    'Completion EOF fanout awaits episode then movie cleanup before the end-of-item stop',
    (t) async {
      final f = VideoPlayerEnvironment();
      final d = LocalCompletionDriver(t, f);
      await d.initialize(
        target: true,
        targets: {
          TrackingSource.trakt,
          TrackingSource.simkl,
          TrackingSource.mdblist,
        },
      );
      final episode = CompletionDelivery(
        'markEpisodeAsFinished',
        (v) => v is Map<String, dynamic>,
      );
      final movie = CompletionDelivery(
        'markMovieAsFinished',
        (v) => v is Set<String>,
      );
      episode.armed = false;
      movie.armed = false;
      try {
        await f.finish(
          t,
          TrackingSourceStorage.setWatchProgressSource(
            WatchProgressSource.local,
          ),
        );
        await d.observe(
          () => episode.run(
            () => movie.run(
              () => f.mount(
                t,
                completionScreen(
                  type: 'movie',
                  trakt: true,
                  simkl: true,
                  mdblist: true,
                  playlist: traktPlaylist,
                  viewMode: PlaylistViewMode.series,
                ),
              ),
            ),
          ),
        );
        await d.position(1000);
        await d.drain();
        await d.position(1000);
        await d.drain();
        await d.waitCheckpoint('trakt', 1);
        await d.waitCheckpoint('mdblist', 1);
        await d.percent(25);
        await d.drain();
        await pickSleep(
          t,
          f,
          const SleepTimerSelection(SleepTimerMode.endOfItem),
        );
        final starts = d.requests.length;
        final simklBefore = d.forTracker('simkl').length;
        final mdBefore = d.forTracker('mdblist').length;
        episode.armed = true;
        movie.armed = true;
        await d.eof();
        await f.until(t, () => episode.pending.isNotEmpty);
        await d.waitCheckpoint('trakt', starts + 1);
        await d.waitCheckpoint('simkl', simklBefore + 1);
        await d.waitCheckpoint('mdblist', mdBefore + 1);
        expect(d.actions.last, 'stop');
        expect(d.trackerActions('simkl').last, 'stop');
        expect(d.trackerActions('mdblist').last, 'stop');
        expect(d.heartbeats.where((timer) => timer.isActive), isEmpty);
        expect(movie.pending, isEmpty);
        expect(find.text('Sleep timer — stopping here'), findsNothing);
        episode.release();
        await f.until(t, () => movie.pending.isNotEmpty);
        expect(find.text('Sleep timer — stopping here'), findsNothing);
        expect(
          await f.finish(t, MovieProgressStorage.getFinishedMovieIds()),
          isEmpty,
        );
        movie.release();
        await d.drain();
        expect(await f.finish(t, MovieProgressStorage.getFinishedMovieIds()), {
          'tt7100000',
        });
        await waitSleepToast(t, f, 'Sleep timer — stopping here');
        expect((await sleepMenu(t, f)).sleepMode, SleepTimerMode.off);
        expect(f.player.calls.where((c) => c.$1 == 'open'), hasLength(1));
      } finally {
        episode.release();
        movie.release();
        await d.close();
      }
    },
  );
}
