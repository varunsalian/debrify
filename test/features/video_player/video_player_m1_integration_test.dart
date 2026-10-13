import 'dart:convert';

import 'package:debrify/screens/video_player/services/playback_ui_clock.dart';
import 'package:debrify/screens/video_player/widgets/skip_segment_button.dart';
import 'package:debrify/screens/video_player/widgets/sleep_timer_sheet.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/storage/local_completion_storage.dart';
import 'package:debrify/services/storage/series_progress_storage.dart';
import 'package:debrify/services/storage/tracking_source_storage.dart';
import 'package:debrify/services/tracking_source_policy.dart';
import 'package:debrify/widgets/series_browser.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'support/display_mode_driver.dart';
import 'support/local_completion_driver.dart';
import 'support/pip_lifecycle_driver.dart';
import 'support/player_actions.dart';
import 'support/secondary_tracker_driver.dart';
import 'support/skip_segment_driver.dart';
import 'support/sleep_timer_driver.dart';
import 'support/trakt_transport.dart';
import 'support/video_player_environment.dart';

void main() {
  TraktTestTransport.install();
  testWidgets(
    'M1 single playback composes skip trackers speed completion sleep lifecycle and episode reset',
    (t) async {
      final f = VideoPlayerEnvironment();
      final tracking = LocalCompletionDriver(t, f);
      final pip = PipLifecycleDriver(t, f);
      final skip = SkipSegmentDriver(t, f);
      final display = DisplayModeDriver(t, f);
      await tracking.initialize(
        target: true,
        targets: {
          TrackingSource.trakt,
          TrackingSource.simkl,
          TrackingSource.mdblist,
        },
      );
      pip.installPlatform();
      try {
        await f.finish(
          t,
          TrackingSourceStorage.setWatchProgressSource(
            WatchProgressSource.local,
          ),
        );
        final policy = await f.finish(t, TrackingSourcePolicy.load());
        expect(policy.progressSource, WatchProgressSource.local);
        expect(policy.scrobbleTargets, {
          TrackingSource.local,
          TrackingSource.trakt,
          TrackingSource.simkl,
          TrackingSource.mdblist,
        });
        await tracking.thresholds(95, 95);
        await skip.configure();
        f.network.handler = (request) {
          if (request.url.host == 'api.skipdb.tv') {
            return skipReply(start: 900, end: 1100);
          }
          if (request.url.host == 'api.tvmaze.com') {
            return http.Response(
              jsonEncode(
                request.url.path.endsWith('/episodes')
                    ? [
                        for (var n = 1; n <= 2; n++)
                          {
                            'id': n,
                            'season': 1,
                            'number': n,
                            'name': 'Episode $n',
                          },
                      ]
                    : {
                        'id': 71,
                        'name': 'M1 Show',
                        'externals': {'imdb': 'tt7100000'},
                        'genres': <String>[],
                      },
              ),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          return secondaryReply(request);
        };
        const playlist = [
          PlaylistEntry(
            url: 'https://player.test/m1-one.mp4',
            title: 'M1.Show.S01E01.mkv',
          ),
          PlaylistEntry(
            url: 'https://player.test/m1-two.mp4',
            title: 'M1.Show.S01E02.mkv',
          ),
        ];
        await pip.observe(
          () => tracking.mount(
            completionScreen(
              type: 'series',
              playlist: playlist,
              season: 1,
              episode: 1,
              trakt: true,
              simkl: true,
              mdblist: true,
            ),
          ),
        );
        await f.until(
          t,
          () => pip.periodic.any((v) => v.$1 == const Duration(seconds: 6)),
        );
        final owner = t.state(find.byType(VideoPlayerScreen));
        final player = f.player;
        playerControls(t).onShowPlaylist();
        await f.until(
          t,
          () => find.byType(SeriesBrowser).evaluate().isNotEmpty,
        );
        final browser = t.widget<SeriesBrowser>(find.byType(SeriesBrowser));
        final seriesTitle = browser.seriesPlaylist.seriesTitle!;
        expect(browser.currentEpisodeIndex, 0);
        expect(browser.seriesPlaylist.allEpisodes, hasLength(2));
        f.navigator.currentState!.pop();
        await f.advance(t, const Duration(milliseconds: 350));
        await tracking.drain();

        // Persist a real speed selection before completion can suppress saves.
        await tracking.position(750000);
        await display.speed(1.5);
        await tracking.drain();
        final saved = await f.finish(
          t,
          SeriesProgressStorage.getSeriesPlaybackState(
            seriesTitle: seriesTitle,
            imdbId: 'tt7100000',
            season: 1,
            episode: 1,
          ),
        );
        expect(saved?['speed'], 1.5);
        expect(saved?['positionMs'], 750000);
        expect(display.rates, [1.5]);

        // Pause/play establishes the three heartbeat owners in caller order.
        playerControls(t).onPlayPause();
        await tracking.drain();
        expect(player.state.playing, isFalse);
        final firstTimer = tracking.heartbeats.length;
        playerControls(t).onPlayPause();
        await tracking.drain();
        expect(tracking.heartbeats, hasLength(firstTimer + 3));
        expect(
          tracking.heartbeats.skip(firstTimer).every((v) => v.isActive),
          isTrue,
        );
        await skip.tick(950);
        await tracking.drain();
        skip.expectButton(true);
        skip.expectQuery(id: 'tt7100000', season: 1, episode: 1);
        final clock = playerControls(t).clock as PlaybackUiClockController;
        if (!clock.visible) {
          await t.tapAt(const Offset(640, 400));
          await f.advance(t, const Duration(milliseconds: 350));
        }
        expect(clock.visible, isTrue);
        final beforeSeek = f.network.requests.length;
        tracking.cancellations.clear();
        t.widget<SkipSegmentButton>(find.byType(SkipSegmentButton)).onPressed();
        expect(
          playerControls(t).clock.value.position,
          const Duration(seconds: 1100),
        );
        expect(tracking.seeks.last, const Duration(seconds: 1100));
        // HTTP delivery is asynchronous. Timer cancellation pins the actual
        // synchronous fan-out order separately from observed delivery order.
        expect(tracking.cancellations, [
          firstTimer,
          firstTimer + 1,
          firstTimer + 2,
        ]);
        await tracking.drain();
        final stops = f.network.requests
            .skip(beforeSeek)
            .where((r) => r.url.path == '/scrobble/stop')
            .toList();
        expect(stops.map((r) => r.url.host), [
          'api.simkl.com',
          'api.trakt.tv',
          'api.mdblist.com',
        ]);
        for (final request in stops) {
          expect(request.method, 'POST');
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['show']['ids'], {'imdb': 'tt7100000'});
          expect(
            (body['progress'] as num).toDouble(),
            closeTo(1100 / 1200 * 100, .01),
          );
          if (request.url.host == 'api.mdblist.com') {
            expect(body['show']['season'], 1);
            expect(body['show']['episode'], 1);
          } else {
            expect(body['episode'], {'season': 1, 'number': 1});
          }
        }
        skip.expectButton(false);

        await tracking.percent(94.99);
        await tracking.drain();
        expect(
          await tracking.finishedEpisode(
            title: seriesTitle,
            season: 1,
            episode: 1,
          ),
          isNull,
        );
        final revision = LocalCompletionStorage.localCompletionRevision.value;
        await tracking.percent(95);
        await tracking.drain();
        expect(
          (await tracking.finishedEpisode(
            title: seriesTitle,
            season: 1,
            episode: 1,
          ))?['finishedAt'],
          isA<int>(),
        );
        expect(
          LocalCompletionStorage.localCompletionRevision.value,
          revision + 1,
        );
        await tracking.percent(96);
        await tracking.drain();
        expect(
          LocalCompletionStorage.localCompletionRevision.value,
          revision + 1,
        );

        await pickSleep(
          t,
          f,
          const SleepTimerSelection(SleepTimerMode.endOfItem),
        );
        expect(playerControls(t).sleepTimerLabel, 'Episode');
        for (final state in [
          AppLifecycleState.inactive,
          AppLifecycleState.hidden,
          AppLifecycleState.paused,
        ]) {
          await pip.lifecycle(state);
        }
        expect(player.state.playing, isFalse);
        final beforeEof = LocalCompletionStorage.localCompletionRevision.value;
        await tracking.eof();
        await f.until(
          t,
          () =>
              LocalCompletionStorage.localCompletionRevision.value > beforeEof,
          reason:
              'EOF completion must finish while background frames are paused',
        );
        await tracking.drain();
        expect(pip.operations('open'), hasLength(1));
        expect(player.state.playlist.medias.single.uri, playlist.first.url);
        final playsBeforeResume = pip.operations('play').length;
        for (final state in [
          AppLifecycleState.hidden,
          AppLifecycleState.inactive,
          AppLifecycleState.resumed,
        ]) {
          await pip.lifecycle(state);
        }
        await tracking.drain();
        expect(playerControls(t).sleepTimerLabel, isNull);
        expect(pip.operations('play'), hasLength(playsBeforeResume));
        expect(player.state.playing, isFalse);
        // Explicit play clears the latch; a new background/foreground cycle
        // must now resume, rather than merely observing that explicit play ran.
        playerControls(t).onPlayPause();
        await tracking.drain();
        expect(player.state.playing, isTrue);
        for (final state in [
          AppLifecycleState.inactive,
          AppLifecycleState.hidden,
          AppLifecycleState.paused,
          AppLifecycleState.hidden,
          AppLifecycleState.inactive,
          AppLifecycleState.resumed,
        ]) {
          await pip.lifecycle(state);
        }
        await tracking.drain();
        expect(pip.operations('play'), hasLength(playsBeforeResume + 2));
        expect(player.state.playing, isTrue);

        // Arm another stop so manual episode reset independently clears the
        // sleep latch. Incoming resume uses the speed actually persisted above,
        // against a different outgoing rate so a missing restore is observable.
        await display.speed(.75);
        await f.finish(
          t,
          SeriesProgressStorage.saveSeriesPlaybackState(
            seriesTitle: seriesTitle,
            imdbId: 'tt7100000',
            season: 1,
            episode: 2,
            positionMs: 120000,
            durationMs: 1200000,
            speed: saved!['speed'] as double,
          ),
        );
        await pickSleep(
          t,
          f,
          const SleepTimerSelection(SleepTimerMode.endOfItem),
        );
        await tracking.playing(false);
        await tracking.eof();
        await f.until(
          t,
          () => playerControls(t).sleepTimerLabel == null,
          reason: 'Second end-of-item stop must finish before manual reset',
        );
        expect(pip.operations('open'), hasLength(1));
        playerControls(t).onShowPlaylist();
        await f.until(
          t,
          () => find.byType(SeriesBrowser).evaluate().isNotEmpty,
        );
        final incoming = t.widget<SeriesBrowser>(find.byType(SeriesBrowser));
        final selection = f.actions.start<void>(
          'M1 incoming episode',
          () => incoming.onEpisodeSelected(1, 2),
        );
        await f.finish(t, selection.future);
        await tracking.drain();
        expect(selection.isCompleted, isTrue);
        expect(f.players, [player]);
        expect(t.state(find.byType(VideoPlayerScreen)), same(owner));
        expect(pip.operations('open'), hasLength(2));
        expect(player.state.playlist.medias.single.uri, playlist.last.url);
        expect(playerControls(t).speed, 1.5);
        expect(player.state.rate, 1.5);
        expect(display.rates, [1.5, .75, 1.5]);
        expect(tracking.seeks.last, const Duration(seconds: 120));
        expect(
          await tracking.finishedEpisode(
            title: seriesTitle,
            season: 1,
            episode: 2,
          ),
          isNull,
        );
        final playsBeforeResetResume = pip.operations('play').length;
        for (final state in [
          AppLifecycleState.inactive,
          AppLifecycleState.hidden,
          AppLifecycleState.paused,
          AppLifecycleState.hidden,
          AppLifecycleState.inactive,
          AppLifecycleState.resumed,
        ]) {
          await pip.lifecycle(state);
        }
        await tracking.drain();
        expect(pip.operations('play'), hasLength(playsBeforeResetResume + 1));
        expect(player.state.playing, isTrue);
        final incomingRevision =
            LocalCompletionStorage.localCompletionRevision.value;
        await tracking.percent(95);
        await tracking.drain();
        expect(
          (await tracking.finishedEpisode(
            title: seriesTitle,
            season: 1,
            episode: 2,
          ))?['finishedAt'],
          isA<int>(),
        );
        expect(
          LocalCompletionStorage.localCompletionRevision.value,
          incomingRevision + 1,
        );
        await tracking.percent(96);
        await tracking.drain();
        expect(
          LocalCompletionStorage.localCompletionRevision.value,
          incomingRevision + 1,
        );
        expect(tracking.uncaught, isEmpty);
        expect(pip.errors, isEmpty);
      } finally {
        tracking.cipher.releaseAll();
        await pip.close();
      }
      expect(pip.periodic.every((v) => !v.$2.isActive), isTrue);
      expect(pip.errors, isEmpty);
      expect(tracking.uncaught, isEmpty);
    },
  );
}
