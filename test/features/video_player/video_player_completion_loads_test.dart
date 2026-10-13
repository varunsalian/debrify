import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/services/storage/local_completion_storage.dart';
import 'package:debrify/services/storage/movie_progress_storage.dart';
import 'package:debrify/services/storage/tracking_source_storage.dart';
import 'package:debrify/services/tracking_source_policy.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/local_completion_driver.dart';
import 'support/trakt_transport.dart';
import 'support/video_player_environment.dart';

void main() {
  TraktTestTransport.install();
  for (var flags = 0; flags < 8; flags++) {
    for (final local in [false, true]) {
      testWidgets('Completion policy truth table flags=$flags local=$local', (
        t,
      ) async {
        final f = VideoPlayerEnvironment();
        final d = LocalCompletionDriver(t, f);
        await d.initialize();
        try {
          await f.finish(
            t,
            TrackingSourceStorage.setWatchProgressSource(
              local ? WatchProgressSource.local : WatchProgressSource.smart,
            ),
          );
          await d.mount(
            completionScreen(
              trakt: flags & 1 != 0,
              simkl: flags & 2 != 0,
              mdblist: flags & 4 != 0,
            ),
          );
          await d.percent(85);
          await d.drain();
          expect(
            await f.finish(
              t,
              MovieProgressStorage.isMovieFinished('tt7100000'),
            ),
            local || flags == 0,
          );
          await d.eof();
          await d.drain();
          expect(
            await f.finish(
              t,
              MovieProgressStorage.isMovieFinished('tt7100000'),
            ),
            local || flags == 0,
            reason: 'The direct EOF movie caller retains the tracking gate',
          );
          expect(d.requests, isEmpty);
          expect(d.forTracker('simkl'), isEmpty);
          expect(d.forTracker('mdblist'), isEmpty);
        } finally {
          await d.close();
        }
      });
    }
  }

  for (final identity in ['tmdb:movie:7100000', 'medialibrary:fixture-movie']) {
    testWidgets(
      'Completion content policy forces the native local owner for $identity despite tracker intent',
      (t) async {
        final f = VideoPlayerEnvironment();
        final d = LocalCompletionDriver(t, f);
        await d.initialize();
        try {
          await d.mount(completionScreen(id: identity, trakt: true));
          await d.percent(85);
          await d.drain();
          expect(
            await f.finish(t, MovieProgressStorage.getFinishedMovieIds()),
            {identity},
          );
          expect(d.requests, isEmpty);
        } finally {
          await d.close();
        }
      },
    );
  }

  for (final channelMode in ['IPTV', 'Stremio']) {
    testWidgets(
      'Completion forced local still excludes $channelMode channels',
      (t) async {
        final f = VideoPlayerEnvironment();
        final d = LocalCompletionDriver(t, f);
        await d.initialize();
        try {
          await f.finish(
            t,
            TrackingSourceStorage.setWatchProgressSource(
              WatchProgressSource.local,
            ),
          );
          await d.mount(
            completionScreen(
              trakt: true,
              iptv: channelMode == 'IPTV'
                  ? [
                      IptvChannel(
                        name: 'Completion VOD',
                        url: 'https://player.test/completion.mp4',
                        contentType: 'vod',
                        duration: 1200,
                      ),
                    ]
                  : null,
              tv: channelMode == 'Stremio' ? [] : null,
            ),
          );
          await d.percent(85);
          await d.drain();
          expect(
            await f.finish(t, MovieProgressStorage.getFinishedMovieIds()),
            isEmpty,
          );
          expect(await d.finishedEpisode(), isNull);
        } finally {
          await d.close();
        }
      },
    );
  }

  for (final type in ['movie', 'series']) {
    for (final threshold in [50, 90]) {
      testWidgets(
        'Completion early $type default 80 then $threshold re-evaluates while paused without another clock tick',
        (t) async {
          final f = VideoPlayerEnvironment();
          final d = LocalCompletionDriver(t, f);
          await d.initialize();
          final reads = CompletionDelivery(
            'loadLocalCompletionThresholds',
            (v) => v is List<int> && v.length == 2,
          );
          try {
            await d.thresholds(threshold, threshold);
            await d.observe(
              () => reads.run(() => f.mount(t, completionScreen(type: type))),
            );
            await f.until(t, () => reads.pending.isNotEmpty);
            expect(reads.values.single, [threshold, threshold]);
            expect(
              f.players,
              hasLength(1),
              reason:
                  'Only completion delivery is held; defaults/player proceed',
            );
            expect(f.player.state.duration, const Duration(minutes: 20));
            if (type == 'movie' && threshold == 90) {
              await d.percent(1);
              await d.drain();
              await d.percent(1);
              await d.drain();
            }
            await d.percent(threshold == 90 ? 85 : 60);
            await d.drain();
            await d.playing(false);
            final already = threshold == 90;
            if (type == 'movie') {
              expect(
                await f.finish(
                  t,
                  MovieProgressStorage.isMovieFinished('tt7100000'),
                ),
                already,
              );
            } else {
              expect(await d.finishedEpisode(), already ? isNotNull : isNull);
            }
            final position = f.player.state.position;
            final revision =
                LocalCompletionStorage.localCompletionRevision.value;
            reads.release();
            await d.drain();
            expect(f.player.state.position, position);
            expect(f.player.state.playing, isFalse);
            if (type == 'movie') {
              expect(
                await f.finish(
                  t,
                  MovieProgressStorage.isMovieFinished('tt7100000'),
                ),
                isTrue,
              );
            } else {
              expect(await d.finishedEpisode(), isNotNull);
            }
            if (already) {
              expect(
                LocalCompletionStorage.localCompletionRevision.value,
                revision,
              );
            } else {
              expect(
                LocalCompletionStorage.localCompletionRevision.value,
                revision + 1,
              );
            }
          } finally {
            reads.release();
            await d.close();
          }
        },
      );
    }
  }

  for (final threshold in [70, 90]) {
    for (final order in ['policy', 'threshold']) {
      testWidgets(
        'Completion independent $order-first loader delivery with configured $threshold pins the early mark and late rewatch',
        (t) async {
          final f = VideoPlayerEnvironment();
          final d = LocalCompletionDriver(t, f);
          await d.initialize();
          final reads = CompletionDelivery(
            'loadLocalCompletionThresholds',
            (v) => v is List<int> && v.length == 2,
          );
          final policy = CompletionDelivery(
            'loadTrackingPolicy',
            (v) => v is TrackingSourcePolicy,
          );
          try {
            await d.thresholds(threshold, threshold);
            await f.finish(
              t,
              TrackingSourceStorage.setWatchProgressSource(
                WatchProgressSource.local,
              ),
            );
            await d.observe(
              () => reads.run(
                () =>
                    policy.run(() => f.mount(t, completionScreen(trakt: true))),
              ),
            );
            await f.until(
              t,
              () => reads.pending.isNotEmpty && policy.pending.isNotEmpty,
            );
            await d.percent(85);
            await d.drain();
            await d.playing(false);
            expect(
              await f.finish(t, MovieProgressStorage.getFinishedMovieIds()),
              isEmpty,
            );
            if (order == 'policy') {
              policy.release();
            } else {
              reads.release();
            }
            await d.drain();
            expect(
              await f.finish(
                t,
                MovieProgressStorage.isMovieFinished('tt7100000'),
              ),
              order == 'policy',
            );
            final middleRevision =
                LocalCompletionStorage.localCompletionRevision.value;
            reads.release();
            policy.release();
            await d.drain();
            expect(
              await f.finish(
                t,
                MovieProgressStorage.isMovieFinished('tt7100000'),
              ),
              threshold == 70,
            );
            if (threshold == 90 && order == 'policy') {
              expect(
                LocalCompletionStorage.localCompletionRevision.value,
                middleRevision + 1,
              );
            }
          } finally {
            reads.release();
            policy.release();
            await d.close();
          }
        },
      );
    }
  }

  testWidgets(
    'Completion early direct movie jump can be unmarked by a higher threshold while the completion guard remains spent',
    (t) async {
      final f = VideoPlayerEnvironment(
        configurePlayer: (p) => p.framePosition = Duration.zero,
      );
      final d = LocalCompletionDriver(t, f);
      await d.initialize();
      final reads = CompletionDelivery(
        'loadLocalCompletionThresholds',
        (v) => v is List<int> && v.length == 2,
      );
      try {
        await d.thresholds(90, 90);
        await d.observe(() => reads.run(() => f.mount(t, completionScreen())));
        await f.until(t, () => reads.pending.isNotEmpty);
        // First positive dispatch releases startup validation. No position below
        // the default threshold is delivered before the next eligible dispatch.
        await d.percent(85);
        await d.drain();
        for (
          var frame = 0;
          frame < 20 &&
              !await f.finish(
                t,
                MovieProgressStorage.isMovieFinished('tt7100000'),
              );
          frame++
        ) {
          await d.percent(85);
          await d.drain();
        }
        expect(
          await f.finish(t, MovieProgressStorage.isMovieFinished('tt7100000')),
          isTrue,
        );
        final revision = LocalCompletionStorage.localCompletionRevision.value;
        reads.release();
        await d.drain();
        expect(
          await f.finish(t, MovieProgressStorage.isMovieFinished('tt7100000')),
          isFalse,
        );
        expect(
          LocalCompletionStorage.localCompletionRevision.value,
          revision + 1,
        );
      } finally {
        reads.release();
        await d.close();
      }
    },
  );

  for (final loader in ['policy', 'threshold']) {
    testWidgets(
      'Completion $loader result delivered after disposal cannot mark the retained position',
      (t) async {
        final f = VideoPlayerEnvironment();
        final d = LocalCompletionDriver(t, f);
        await d.initialize();
        final reads = CompletionDelivery(
          loader == 'policy'
              ? 'loadTrackingPolicy'
              : 'loadLocalCompletionThresholds',
          (v) => loader == 'policy'
              ? v is TrackingSourcePolicy
              : v is List<int> && v.length == 2,
        );
        try {
          await d.thresholds(50, 50);
          await f.finish(
            t,
            TrackingSourceStorage.setWatchProgressSource(
              WatchProgressSource.local,
            ),
          );
          await d.observe(
            () => reads.run(
              () => f.mount(t, completionScreen(trakt: loader == 'policy')),
            ),
          );
          await f.until(t, () => reads.pending.isNotEmpty);
          await d.percent(loader == 'policy' ? 85 : 60);
          await d.drain();
          expect(
            await f.finish(t, MovieProgressStorage.getFinishedMovieIds()),
            isEmpty,
          );
          await d.retired();
          final revision = LocalCompletionStorage.localCompletionRevision.value;
          reads.release();
          await d.drain();
          expect(
            await f.finish(t, MovieProgressStorage.getFinishedMovieIds()),
            isEmpty,
          );
          expect(
            LocalCompletionStorage.localCompletionRevision.value,
            revision,
          );
        } finally {
          reads.release();
          await d.close();
        }
      },
    );
  }
}
