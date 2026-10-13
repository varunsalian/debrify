import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/screens/video_player/widgets/stremio_tv_guide_sheet.dart';
import 'package:debrify/services/storage/local_completion_storage.dart';
import 'package:debrify/services/storage/movie_progress_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/local_completion_driver.dart';
import 'support/player_actions.dart';
import 'support/trakt_transport.dart';
import 'support/video_player_environment.dart';

void main() {
  TraktTestTransport.install();
  for (final type in ['movie', 'series']) {
    testWidgets(
      'Completion MagicTV next resets $type completion and rewatch flags on the existing State',
      (t) async {
        final f = VideoPlayerEnvironment();
        final d = LocalCompletionDriver(t, f);
        await d.initialize();
        var next = 0;
        try {
          await d.mount(
            completionScreen(
              type: type,
              requestMagicNext: () async {
                next++;
                return {
                  'url': 'https://player.test/magic-next.mp4',
                  'title': 'Incoming completion',
                };
              },
            ),
          );
          await d.percent(85);
          await d.drain();
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
          final revision = LocalCompletionStorage.localCompletionRevision.value;
          playerControls(t).onNext!();
          await f.until(
            t,
            () => f.player.calls.where((c) => c.$1 == 'open').length == 2,
          );
          await d.drain();
          expect(next, 1);
          if (type == 'movie') {
            expect(
              await f.finish(
                t,
                MovieProgressStorage.isMovieFinished('tt7100000'),
              ),
              isFalse,
            );
          }
          await d.percent(85);
          await d.drain();
          if (type == 'movie') {
            expect(
              await f.finish(
                t,
                MovieProgressStorage.isMovieFinished('tt7100000'),
              ),
              isTrue,
            );
            expect(
              LocalCompletionStorage.localCompletionRevision.value,
              greaterThanOrEqualTo(revision + 2),
            );
          } else {
            expect(
              LocalCompletionStorage.localCompletionRevision.value,
              revision + 1,
            );
          }
          expect(f.players, hasLength(1));
        } finally {
          await d.close();
        }
      },
    );
  }

  testWidgets(
    'Completion zero position after a MagicTV reset leaves the watched marker until real rewatch progress',
    (t) async {
      final f = VideoPlayerEnvironment();
      final d = LocalCompletionDriver(t, f);
      await d.initialize();
      try {
        await d.mount(
          completionScreen(
            requestMagicNext: () async => {
              'url': 'https://player.test/zero-next.mp4',
            },
          ),
        );
        await d.percent(85);
        await d.drain();
        expect(
          await f.finish(t, MovieProgressStorage.isMovieFinished('tt7100000')),
          isTrue,
        );
        f.player.framePosition = Duration.zero;
        playerControls(t).onNext!();
        await f.until(
          t,
          () => f.player.calls.where((c) => c.$1 == 'open').length == 2,
        );
        await d.drain();
        expect(
          await f.finish(t, MovieProgressStorage.isMovieFinished('tt7100000')),
          isTrue,
        );
        await d.percent(20);
        await d.drain();
        expect(
          await f.finish(t, MovieProgressStorage.isMovieFinished('tt7100000')),
          isFalse,
        );
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'Completion zero duration after a MagicTV reset cannot mark a positive position as infinite progress',
    (t) async {
      final f = VideoPlayerEnvironment();
      final d = LocalCompletionDriver(t, f);
      await d.initialize();
      try {
        await d.mount(
          completionScreen(
            requestMagicNext: () async => {
              'url': 'https://player.test/zero-duration.mp4',
            },
          ),
        );
        await d.percent(20);
        await d.drain();
        f.player.onOpen = () {
          f.player.publishFrame(duration: Duration.zero);
          f.controllers.last.publishFrame();
        };
        playerControls(t).onNext!();
        await f.until(
          t,
          () => f.player.calls.where((c) => c.$1 == 'open').length == 2,
        );
        await d.drain();
        expect(f.player.state.duration, Duration.zero);
        expect(
          await f.finish(t, MovieProgressStorage.getFinishedMovieIds()),
          isEmpty,
        );
        f.player.state = f.player.state.copyWith(
          duration: const Duration(minutes: 20),
        );
        f.player.emit('duration', f.player.state.duration);
        await d.percent(80);
        await d.drain();
        expect(
          await f.finish(t, MovieProgressStorage.isMovieFinished('tt7100000')),
          isTrue,
        );
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'Completion Stremio channel reset rearms episode position marking when the public guide input retires',
    (t) async {
      final f = VideoPlayerEnvironment();
      final d = LocalCompletionDriver(t, f);
      await d.initialize();
      try {
        final screen = VideoPlayerScreen(
          videoUrl: 'https://player.test/guide-a.mp4',
          title: 'Completion fallback',
          contentTitle: 'Completion title',
          contentImdbId: 'tt7100000',
          contentType: 'series',
          contentSeason: 2,
          contentEpisode: 3,
          stremioTvChannels: const [
            {'id': 'a', 'name': 'A'},
            {'id': 'b', 'name': 'B'},
          ],
          stremioTvCurrentChannelId: 'a',
          stremioTvChannelSwitchProvider: (id) async => null,
        );
        await d.mount(screen);
        await d.eof();
        await d.drain();
        expect(await d.finishedEpisode(), isNotNull);
        final revision = LocalCompletionStorage.localCompletionRevision.value;
        playerControls(t).onShowGuide!();
        await f.until(
          t,
          () => find.byType(StremioTvGuideSheet).evaluate().isNotEmpty,
        );
        final guide = t.widget<StremioTvGuideSheet>(
          find.byType(StremioTvGuideSheet),
        );
        guide.onChannelSwitched(
          'b',
          'https://player.test/guide-b.mp4',
          'Incoming show',
          contentImdbId: 'tt7100000',
          contentType: 'series',
          contentSeason: 4,
          contentEpisode: 5,
        );
        await f.until(
          t,
          () => f.player.calls.where((c) => c.$1 == 'open').length == 2,
        );
        await d.drain();
        await t.pumpWidget(
          MaterialApp(
            navigatorKey: f.navigator,
            theme: ThemeData.dark(),
            home: completionScreen(type: 'series'),
          ),
        );
        await d.percent(85);
        await d.drain();
        expect(
          LocalCompletionStorage.localCompletionRevision.value,
          revision + 1,
        );
        expect(
          await d.finishedEpisode(),
          isNotNull,
          reason:
              'Single-file mark uses original widget coordinates, not the channel override',
        );
        expect(await d.finishedEpisode(season: 4, episode: 5), isNull);
        expect(f.players, hasLength(1));
      } finally {
        await d.close();
      }
    },
  );
}
