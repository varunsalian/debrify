import 'dart:async';
import 'package:debrify/screens/video_player/widgets/player_menu_panel.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/debrify_tv_database.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/storage/movie_progress_storage.dart';
import 'package:debrify/services/storage/video_resume_storage.dart';
import 'package:flutter_test/flutter_test.dart';
// Existing resolved transport, unchanged application dependencies.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'support/display_mode_driver.dart';
import 'support/local_completion_driver.dart';
import 'support/player_actions.dart';
import 'support/video_player_environment.dart';
import 'support/trakt_transport.dart';
import 'support/physical_resume_store.dart';

void main() {
  TraktTestTransport.install();
  for (final target in [959999, 960000]) {
    testWidgets(
      'Resume P14 save target $target pins the exact 80 percent guard exemption',
      (t) async {
        final f = VideoPlayerEnvironment(
          configurePlayer: (p) => p.seekAcknowledgementPosition = Duration.zero,
        );
        await t.runAsync(f.initialize);
        final display = DisplayModeDriver(t, f);
        const url = 'https://player.test/p14-guard.mp4';
        try {
          await display.defaults();
          await f.finish(
            t,
            VideoResumeStorage.upsertVideoResume(url, {
              'positionMs': target,
              'speed': 1.0,
              'aspect': 'contain',
            }),
          );
          await f.mount(
            t,
            const VideoPlayerScreen(videoUrl: url, title: 'P14 guard'),
          );
          expect(
            f.player.calls
                .where((c) => c.$1 == 'seek')
                .map((c) => (c.$2 as Duration).inMilliseconds),
            contains(target),
          );
          expect(f.player.state.position, Duration.zero);
          final menu = await display.menu(PlayerMenuSection.speed);
          menu.onSpeedSelected(1.5);
          Map<String, dynamic>? saved;
          await f.until(t, () => f.player.state.rate == 1.5);
          for (var i = 0; i < 20; i++) {
            saved = await f.finish(t, VideoResumeStorage.getVideoResume(url));
            if (saved?['speed'] == 1.5) break;
            await f.advance(t);
          }
          expect(saved?['speed'], 1.5);
          expect(saved?['positionMs'], target == 960000 ? 0 : 959999);
          expect(saved?['durationMs'], 1200000);
        } finally {
          await f.close(t);
        }
      },
    );
  }
  for (final transientSeconds in [200, 300]) {
    testWidgets(
      'Resume P14 held target at transient duration $transientSeconds skips the entire write then recovers and releases on user seek',
      (t) async {
        final f = VideoPlayerEnvironment(
          configurePlayer: (p) => p.seekAcknowledgementPosition = Duration.zero,
        );
        await t.runAsync(f.initialize);
        final display = DisplayModeDriver(t, f);
        const url = 'https://player.test/p14-guard.mp4';
        var checkpoints = 0;
        void checkpoint() => checkpoints++;
        MainPageBridge.addPlaybackCheckpointListener(checkpoint);
        try {
          await display.defaults();
          await f.finish(
            t,
            VideoResumeStorage.upsertVideoResume(url, {
              'positionMs': 300000,
              'speed': 1.0,
              'aspect': 'contain',
            }),
          );
          await f.mount(
            t,
            const VideoPlayerScreen(videoUrl: url, title: 'P14 guard'),
          );
          f.player.state = f.player.state.copyWith(
            duration: Duration(seconds: transientSeconds),
          );
          f.player.emit('duration', f.player.state.duration);
          await f.advance(t);
          final menu = await display.menu(PlayerMenuSection.speed);
          checkpoints = 0;
          menu.onSpeedSelected(1.5);
          await f.actions.settle(t);
          expect(checkpoints, 0);
          final untouched = await f.finish(
            t,
            VideoResumeStorage.getVideoResume(url),
          );
          expect(untouched?['positionMs'], 300000);
          expect(untouched?['speed'], 1.0);
          expect(
            (await f.finish(
              t,
              PhysicalResumeStore.getPlaybackStateMap(),
            ))['video_p14_guard'],
            isNull,
          );
          f.player.state = f.player.state.copyWith(
            duration: const Duration(minutes: 20),
          );
          f.player.emit('duration', f.player.state.duration);
          await f.advance(t);
          menu.onSpeedSelected(1.75);
          await f.until(t, () => checkpoints == 1);
          final held = await f.finish(
            t,
            VideoResumeStorage.getVideoResume(url),
          );
          expect(held?['positionMs'], 300000);
          expect(held?['speed'], 1.75);
          expect(held?['durationMs'], 1200000);
          f.player.seekAcknowledgementPosition = null;
          final controls = playerControls(t);
          controls.onSeekBarChanged(0.2);
          controls.onSeekBarChangeEnd();
          await f.until(t, () => checkpoints == 2);
          expect(
            (await f.finish(
              t,
              VideoResumeStorage.getVideoResume(url),
            ))?['positionMs'],
            240000,
          );
        } finally {
          MainPageBridge.removePlaybackCheckpointListener(checkpoint);
          await f.close(t);
        }
      },
    );
  }
  testWidgets(
    'Resume P14 zero duration skips maps rows and checkpoint notification',
    (t) async {
      final f = VideoPlayerEnvironment();
      await t.runAsync(f.initialize);
      final display = DisplayModeDriver(t, f);
      var checkpoints = 0;
      void checkpoint() => checkpoints++;
      MainPageBridge.addPlaybackCheckpointListener(checkpoint);
      try {
        await display.defaults();
        await f.mount(
          t,
          const VideoPlayerScreen(
            videoUrl: 'https://player.test/p14-guard.mp4',
            title: 'P14 guard',
          ),
        );
        f.player.state = f.player.state.copyWith(duration: Duration.zero);
        f.player.emit('duration', Duration.zero);
        await f.advance(t);
        final menu = await display.menu(PlayerMenuSection.speed);
        checkpoints = 0;
        menu.onSpeedSelected(1.5);
        await f.actions.settle(t);
        expect(f.player.state.rate, 1.5);
        expect(
          await f.finish(
            t,
            VideoResumeStorage.getVideoResume(
              'https://player.test/p14-guard.mp4',
            ),
          ),
          isNull,
        );
        expect(
          (await f.finish(
            t,
            PhysicalResumeStore.getPlaybackStateMap(),
          ))['video_p14_guard'],
          isNull,
        );
        expect(checkpoints, 0);
      } finally {
        f.player.state = f.player.state.copyWith(
          duration: const Duration(minutes: 20),
        );
        f.player.emit('duration', f.player.state.duration);
        await f.advance(t);
        MainPageBridge.removePlaybackCheckpointListener(checkpoint);
        await f.close(t);
      }
    },
  );
  for (final failing in ['enhanced', 'legacy']) {
    testWidgets(
      'Resume P14 $failing failure pins physical partial write error propagation and lock recovery',
      (t) async {
        final f = VideoPlayerEnvironment();
        await t.runAsync(f.initialize);
        final display = DisplayModeDriver(t, f);
        final old = SharedPreferencesStorePlatform.instance;
        final errors = <Object>[];
        CompletionWrites? store;
        var checkpoints = 0;
        void checkpoint() => checkpoints++;
        MainPageBridge.addPlaybackCheckpointListener(checkpoint);
        try {
          await display.defaults();
          await f.mount(
            t,
            const VideoPlayerScreen(
              videoUrl: 'https://player.test/p14-guard.mp4',
              title: 'P14 guard',
            ),
          );
          store = await t.runAsync(CompletionWrites.install);
          final scope = ProfileRuntime.capture();
          final db = await f.finish(t, DebrifyTvDatabase.instance.database);
          if (failing == 'enhanced') {
            store!.reject = (key) => key.endsWith('playback_state_v1');
          }
          if (failing == 'legacy') {
            await f.finish(
              t,
              db.execute(
                "CREATE TRIGGER p14_fail_resume BEFORE INSERT ON video_resume BEGIN SELECT RAISE(ABORT, 'p14 legacy'); END",
              ),
            );
          }
          f.player.state = f.player.state.copyWith(
            position: const Duration(minutes: 3),
          );
          f.player.emit('position', f.player.state.position);
          await f.advance(t);
          final menu = await display.menu(PlayerMenuSection.speed);
          checkpoints = 0;
          runZoned(
            () => menu.onSpeedSelected(1.5),
            zoneSpecification: ZoneSpecification(
              handleUncaughtError: (self, parent, zone, error, stack) =>
                  errors.add(error),
            ),
          );
          await f.until(
            t,
            () => failing == 'enhanced' ? checkpoints == 1 : errors.isNotEmpty,
          );
          final raw = decodeCompletionPhysical(
            await store!.physical(scope, 'playback_state_v1'),
          );
          if (failing == 'enhanced') {
            expect(errors, isEmpty);
            expect(raw['video_p14_guard'], isNull);
            expect(
              (await f.finish(
                t,
                VideoResumeStorage.getVideoResume(
                  'https://player.test/p14-guard.mp4',
                ),
              ))?['speed'],
              1.5,
            );
          } else {
            expect(errors, hasLength(1));
            expect(errors.single.toString(), contains('p14 legacy'));
            expect(raw['video_p14_guard'], containsPair('speed', 1.5));
            expect(
              await f.finish(
                t,
                VideoResumeStorage.getVideoResume(
                  'https://player.test/p14-guard.mp4',
                ),
              ),
              isNull,
            );
            expect(checkpoints, 0);
            await f.finish(t, db.execute('DROP TRIGGER p14_fail_resume'));
          }
          store.reject = null;
          final previous = checkpoints;
          menu.onSpeedSelected(1.75);
          await f.until(t, () => checkpoints == previous + 1);
          expect(
            (await f.finish(
              t,
              VideoResumeStorage.getVideoResume(
                'https://player.test/p14-guard.mp4',
              ),
            ))?['speed'],
            1.75,
          );
          expect(
            decodeCompletionPhysical(
              await store.physical(scope, 'playback_state_v1'),
            )['video_p14_guard'],
            containsPair('speed', 1.75),
          );
        } finally {
          if (store != null) store.reject = null;
          final db = await f.finish(t, DebrifyTvDatabase.instance.database);
          await f.finish(
            t,
            db.execute('DROP TRIGGER IF EXISTS p14_fail_resume'),
          );
          MainPageBridge.removePlaybackCheckpointListener(checkpoint);
          await f.close(t);
          SharedPreferencesStorePlatform.instance = old;
        }
      },
    );
  }
  testWidgets(
    'Resume P14 completion after save admission preserves the original late row recreation',
    (t) async {
      final f = VideoPlayerEnvironment();
      final d = LocalCompletionDriver(t, f);
      await d.initialize();
      final display = DisplayModeDriver(t, f);
      final old = SharedPreferencesStorePlatform.instance;
      CompletionWrites? store;
      final read = CompletionDelivery(
        'saveVideoPlaybackState',
        (v) => v is Map<String, dynamic>,
      );
      read.armed = false;
      var checkpoints = 0;
      void checkpoint() => checkpoints++;
      MainPageBridge.addPlaybackCheckpointListener(checkpoint);
      const id = 'tt1417777';
      const url = 'https://player.test/completion.mp4';
      try {
        await display.defaults();
        await d.mount(
          completionScreen(
            id: id,
            title: 'P14 completion',
            contentTitle: 'P14 completion',
          ),
        );
        await d.thresholds(80, 80);
        await f.finish(
          t,
          PhysicalResumeStore.savePlaybackStateMap({
            'video_p14_completion': {
              'type': 'video',
              'title': 'P14 completion',
              'imdbId': id,
              'positionMs': 60000,
            },
          }),
        );
        await f.finish(
          t,
          VideoResumeStorage.upsertVideoResume(url, {'positionMs': 111}),
        );
        store = await t.runAsync(CompletionWrites.install);
        final scope = ProfileRuntime.capture();
        await d.position(300000);
        final menu = await display.menu(PlayerMenuSection.speed);
        checkpoints = 0;
        read.armed = true;
        read.run(() => menu.onSpeedSelected(1.5));
        await f.until(t, () => read.pending.isNotEmpty);
        expect(checkpoints, 0);
        await d.percent(85);
        expect(
          await f.finish(t, MovieProgressStorage.isMovieFinished(id)),
          isTrue,
        );
        expect(
          await f.finish(t, VideoResumeStorage.getVideoResume(url)),
          isNull,
        );
        expect(
          decodeCompletionPhysical(
            await store!.physical(scope, 'playback_state_v1'),
          ).values.where((v) => v is Map && v['imdbId'] == id),
          isEmpty,
        );
        read.release();
        await f.until(t, () => checkpoints == 1);
        final physical = decodeCompletionPhysical(
          await store.physical(scope, 'playback_state_v1'),
        );
        expect(
          physical['video_p14_completion'],
          containsPair('positionMs', 300000),
        );
        expect(physical['video_p14_completion'], containsPair('speed', 1.5));
        expect(
          (await f.finish(
            t,
            VideoResumeStorage.getVideoResume(url),
          ))?['positionMs'],
          300000,
        );
        expect(
          await f.finish(t, MovieProgressStorage.isMovieFinished(id)),
          isTrue,
        );
        final writes = store.writes.length;
        await d.tick(const Duration(seconds: 6));
        expect(
          store.writes.length,
          writes,
          reason:
              'The next callback sees the already marked completion; the admitted save was checked earlier',
        );
      } finally {
        read.release();
        MainPageBridge.removePlaybackCheckpointListener(checkpoint);
        await d.close();
        SharedPreferencesStorePlatform.instance = old;
      }
    },
  );
}
