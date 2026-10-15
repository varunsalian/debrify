import 'dart:async';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/models/playlist_view_mode.dart';
import 'package:debrify/services/storage/tracking_source_storage.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/storage/video_resume_storage.dart';
import 'package:debrify/services/storage/movie_progress_storage.dart';
import 'package:debrify/services/storage/tracker_episode_progress_storage.dart';
import 'package:debrify/services/tracking_source_policy.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/display_mode_driver.dart';
import 'support/fake_player.dart';
import 'support/local_completion_driver.dart';
import 'support/resume_driver.dart';
import 'support/video_player_environment.dart';

void main() {
  for (final stage in [
    'policy',
    'duration',
    'local state',
    'tracker snapshot',
    'completion',
    'rate',
    'zoom',
    'seek',
  ]) {
    for (final crossing in ['profile', 'dispose']) {
      testWidgets(
        'Resume P14 held $stage across $crossing preserves original late reads and effects',
        (t) async {
          final gate = Completer<void>();
          var operationEntered = false;
          final f = VideoPlayerEnvironment(
            native: true,
            configurePlayer: (p) {
              p.heldOperation = (name, value) =>
                  stage == 'rate' && name == 'rate' && value == 1.5 ||
                  stage == 'seek' && name == 'seek';
              p.beforeOperation = (name, value) async {
                if (stage == 'rate' && name == 'rate' && value == 1.5 ||
                    stage == 'seek' && name == 'seek') {
                  operationEntered = true;
                  await gate.future;
                }
              };
              final native = p.platform as FakeNativePlayer;
              native.heldOperation = (name, value) =>
                  stage == 'zoom' &&
                  name == 'setProperty' &&
                  value == ('video-zoom', '0.415037');
              native.beforeOperation = (name, value) async {
                if (stage == 'zoom' &&
                    name == 'setProperty' &&
                    value == ('video-zoom', '0.415037')) {
                  operationEntered = true;
                  await gate.future;
                }
              };
            },
          );
          await t.runAsync(f.initialize);
          final display = DisplayModeDriver(t, f);
          final verifier = ResumeVerifierDriver(t, f);
          final read = CompletionDelivery(
            'maybeRestoreResume',
            (v) => switch (stage) {
              'policy' => v is TrackingSourcePolicy,
              'duration' => v == null,
              'local state' => v is Map<String, dynamic>,
              'tracker snapshot' => v is double,
              'completion' => v is bool,
              _ => false,
            },
          );
          const bookmark = 'pikpak_p14-restore';
          try {
            final a = ProfileRuntime.capture();
            final b = await completionIncomingProfile(t, f);
            await f.finish(
              t,
              TrackingSourceStorage.setWatchProgressSource(
                WatchProgressSource.local,
              ),
            );
            await f.finish(
              t,
              VideoResumeStorage.upsertVideoResume(bookmark, {
                'positionMs': 420000,
                'speed': 1.75,
                'aspect': '4:3',
              }),
            );
            if (stage == 'completion') {
              await f.finish(
                t,
                MovieProgressStorage.markMovieAsFinished('tt1412001'),
              );
            }
            await completionActivate(t, f, a);
            await display.defaults();
            await f.finish(
              t,
              TrackingSourceStorage.setWatchProgressSource(
                WatchProgressSource.smart,
              ),
            );
            await f.finish(
              t,
              VideoResumeStorage.upsertVideoResume(bookmark, {
                'positionMs': 180000,
                'speed': 1.5,
                'aspect': 'cinemaZoom',
              }),
            );
            if (stage == 'tracker snapshot') {
              await f.finish(
                t,
                TrackerEpisodeProgressStorage.saveEpisodeTraktProgress(
                  imdbId: 'tt1412001',
                  percents: {'2_3': 25},
                ),
              );
            }
            const entry = PlaylistEntry(
              url: 'https://player.test/p14-restore.mp4',
              title: 'P14 restore.mkv',
              provider: 'pikpak',
              pikpakFileId: 'p14-restore',
            );
            await verifier.observe(
              () => read.run(
                () => f.mount(
                  t,
                  VideoPlayerScreen(
                    videoUrl: 'https://player.test/p14-restore.mp4',
                    title: 'P14 restore',
                    playlist: [entry],
                    traktProgressPercent: stage == 'tracker snapshot'
                        ? null
                        : 20,
                    contentType: stage == 'completion'
                        ? 'movie'
                        : stage == 'tracker snapshot'
                        ? 'series'
                        : null,
                    contentImdbId:
                        stage == 'completion' || stage == 'tracker snapshot'
                        ? 'tt1412001'
                        : null,
                    viewMode: stage == 'tracker snapshot'
                        ? PlaylistViewMode.raw
                        : null,
                    contentSeason: 2,
                    contentEpisode: 3,
                  ),
                ),
              ),
            );
            await f.until(t, () => read.pending.isNotEmpty || operationEntered);
            expect(gate.isCompleted, isFalse);
            final original = f.player;
            final native = original.platform as FakeNativePlayer;
            final beforeSeeks = original.calls
                .where((c) => c.$1 == 'seek')
                .length;
            if (crossing == 'profile') {
              await completionActivate(t, f, b);
            } else {
              await f.until(
                t,
                () => verifier.periodic.any(
                  (v) => v.$1 == const Duration(seconds: 6),
                ),
                reason:
                    'PikPak registers autosave before its deferred restore continuation',
              );
              await t.pumpWidget(const SizedBox.shrink());
              await f.until(t, () => original.disposed.isCompleted);
            }
            read.release();
            gate.complete();
            await f.until(
              t,
              () =>
                  original.state.position ==
                  Duration(
                    milliseconds: stage == 'tracker snapshot'
                        ? (crossing == 'profile' ? 420000 : 300000)
                        : 240000,
                  ),
            );
            await f.advance(t, const Duration(milliseconds: 800));
            await verifier.drain();
            final beforeLocal =
                stage == 'policy' ||
                stage == 'duration' ||
                stage == 'tracker snapshot' ||
                stage == 'completion';
            final bWasRead = crossing == 'profile' && beforeLocal;
            final exitWasRead = crossing == 'dispose' && beforeLocal;
            final rates = original.calls
                .where((c) => c.$1 == 'rate')
                .map((c) => c.$2);
            expect(
              rates,
              exitWasRead ? isEmpty : contains(bWasRead ? 1.75 : 1.5),
            );
            expect(
              native.properties['video-zoom'],
              bWasRead || exitWasRead ? '0.000000' : '0.415037',
            );
            if (crossing == 'dispose') {
              final saved = await f.finish(
                t,
                VideoResumeStorage.getVideoResume(bookmark),
              );
              expect(
                saved?['speed'],
                stage == 'zoom' || stage == 'seek' ? 1.5 : 1.0,
              );
            }
            expect(
              original.calls.where((c) => c.$1 == 'seek').map((c) => c.$2),
              contains(
                Duration(
                  milliseconds: stage == 'tracker snapshot'
                      ? (crossing == 'profile' ? 420000 : 300000)
                      : 240000,
                ),
              ),
            );
            if (crossing == 'dispose') {
              expect(original.disposed.isCompleted, isTrue);
              expect(
                original.calls.where((c) => c.$1 == 'seek').length,
                stage == 'seek' ? beforeSeeks : beforeSeeks + 1,
                reason:
                    'Original restore lacks an internal mounted guard and can seek after dispose',
              );
            }
          } finally {
            read.release();
            if (!gate.isCompleted) gate.complete();
            await t.pumpWidget(const SizedBox.shrink());
            await f.advance(t, const Duration(milliseconds: 800));
            await verifier.drain();
            await f.close(t);
          }
        },
      );
    }
  }
}
