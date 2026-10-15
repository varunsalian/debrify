import 'dart:async';
import 'dart:convert';
import 'package:debrify/screens/video_player/models/gesture_state.dart';
import 'package:debrify/screens/video_player/widgets/player_menu_panel.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/storage/playback_state_store.dart';
import 'package:debrify/services/storage/video_resume_storage.dart';
import 'package:flutter_test/flutter_test.dart';
// Existing resolved transport, not an application dependency change.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'support/display_mode_driver.dart';
import 'support/local_completion_driver.dart';
import 'support/player_actions.dart';
import 'support/sleep_timer_driver.dart';
import 'support/video_player_environment.dart';

List<Map<String, dynamic>> resumeQueueWrites(SleepResumeWrites store) => [
  for (final (key, value) in store.writes)
    if (key.endsWith('playback_state_v1'))
      (jsonDecode(value as String) as Map<String, dynamic>)['video_p14_queue']
          as Map<String, dynamic>,
];

void main() {
  testWidgets(
    'Resume P14 queue samples current fields at admission preserves explicit override and drops periodic backlog',
    (t) async {
      final f = VideoPlayerEnvironment();
      await t.runAsync(f.initialize);
      final display = DisplayModeDriver(t, f);
      final old = SharedPreferencesStorePlatform.instance;
      SleepResumeWrites? store;
      var checkpoints = 0;
      void checkpoint() => checkpoints++;
      MainPageBridge.addPlaybackCheckpointListener(checkpoint);
      try {
        await display.defaults();
        await f.mount(
          t,
          const VideoPlayerScreen(
            videoUrl: 'https://player.test/p14-queue.mp4',
            title: 'P14 queue',
          ),
        );
        await display.aspect(AspectMode.aspect4_3);
        f.player.state = f.player.state.copyWith(
          position: const Duration(minutes: 3),
        );
        f.player.emit('position', f.player.state.position);
        await f.advance(t);
        store = await t.runAsync(SleepResumeWrites.install);
        store!.barrier = Completer<void>();
        checkpoints = 0;
        final menu = await display.menu(PlayerMenuSection.speed);
        menu.onSpeedSelected(1.25);
        await f.until(t, () => store!.entered);
        expect(
          resumeQueueWrites(store).single,
          containsPair('positionMs', 180000),
        );
        expect(resumeQueueWrites(store).single, containsPair('speed', 1.25));
        expect(resumeQueueWrites(store).single, containsPair('aspect', '4:3'));
        f.player.state = f.player.state.copyWith(
          position: const Duration(minutes: 4),
        );
        f.player.emit('position', f.player.state.position);
        await f.advance(t);
        playerControls(t).onPlayPause();
        await f.advance(t);
        f.player.state = f.player.state.copyWith(
          position: const Duration(minutes: 5),
          duration: const Duration(minutes: 30),
        );
        f.player.emit('position', f.player.state.position);
        f.player.emit('duration', f.player.state.duration);
        await f.advance(t);
        menu.onAspectSelected(AspectMode.aspect16_9);
        menu.onSpeedSelected(1.75);
        await f.advance(t, const Duration(seconds: 12));
        expect(resumeQueueWrites(store), hasLength(1));
        expect(checkpoints, 0);
        store.release();
        await f.until(t, () => checkpoints == 4);
        final rows = resumeQueueWrites(store);
        expect(
          rows,
          hasLength(4),
          reason:
              'Two dropped autosave ticks must never queue additional writes',
        );
        expect(rows.map((v) => v['positionMs']), [
          180000,
          240000,
          300000,
          300000,
        ]);
        expect(
          rows.skip(1).map((v) => (v['durationMs'], v['speed'], v['aspect'])),
          everyElement((1800000, 1.75, '16:9')),
        );
        final legacy = await f.finish(
          t,
          VideoResumeStorage.getVideoResume(
            'https://player.test/p14-queue.mp4',
          ),
        );
        expect(legacy?['positionMs'], 300000);
        expect(legacy?['durationMs'], 1800000);
        expect(legacy?['speed'], 1.75);
        expect(legacy?['aspect'], '16:9');
      } finally {
        store?.release();
        MainPageBridge.removePlaybackCheckpointListener(checkpoint);
        await f.close(t);
        SharedPreferencesStorePlatform.instance = old;
      }
    },
  );

  for (final held in ['resume physical write', 'track preference read']) {
    testWidgets(
      'Resume P14 $held overlaps public audio menu persistence and pins the lost write',
      (t) async {
        final f = VideoPlayerEnvironment();
        await t.runAsync(f.initialize);
        final display = DisplayModeDriver(t, f);
        final old = SharedPreferencesStorePlatform.instance;
        SleepResumeWrites? store;
        final read = CompletionDelivery(
          'saveVideoTrackPreferences',
          (v) => v is Map<String, dynamic>,
        );
        read.armed = false;
        var checkpoints = 0;
        void checkpoint() => checkpoints++;
        MainPageBridge.addPlaybackCheckpointListener(checkpoint);
        try {
          await display.defaults();
          await f.mount(
            t,
            const VideoPlayerScreen(
              videoUrl: 'https://player.test/p14-queue.mp4',
              title: 'P14 queue',
            ),
          );
          await f.finish(
            t,
            PlaybackStateStore.savePlaybackStateMap({
              'video_p14_queue': {
                'type': 'video',
                'title': 'P14 queue',
                'positionMs': 60000,
                'durationMs': 1200000,
                'speed': 1.0,
                'aspect': 'contain',
              },
            }),
          );
          final scope = ProfileRuntime.capture();
          f.player.state = f.player.state.copyWith(
            position: const Duration(minutes: 3),
          );
          f.player.emit('position', f.player.state.position);
          await f.advance(t);
          final menu = await display.menu(PlayerMenuSection.speed);
          checkpoints = 0;
          late Future<void> audio;
          if (held == 'resume physical write') {
            store = await t.runAsync(SleepResumeWrites.install);
            store!.barrier = Completer<void>();
            var writes = 0;
            store.block = (key) =>
                key.endsWith('playback_state_v1') && ++writes == 1;
            menu.onSpeedSelected(1.5);
            await f.until(t, () => store!.entered);
            audio = menu.onAudioSelected('1', 'no');
            await f.finish(t, audio);
            expect(checkpoints, 0);
            final raw = (await t.runAsync(
              store.getAll,
            ))!['flutter.${scope.preferenceKey('playback_state_v1')}'];
            expect(
              decodeCompletionPhysical(
                raw,
              )['video_p14_queue']['trackPreferences'],
              containsPair('audioTrackId', '1'),
            );
            store.release();
          } else {
            read.armed = true;
            audio = read.run(() => menu.onAudioSelected('1', 'no'));
            await f.until(t, () => read.pending.isNotEmpty);
            menu.onSpeedSelected(1.5);
            await f.until(t, () => checkpoints == 1);
            expect(
              (await f.finish(
                t,
                PlaybackStateStore.getPlaybackStateMap(),
              ))['video_p14_queue']['positionMs'],
              180000,
            );
            read.release();
            await f.finish(t, audio);
          }
          await f.until(t, () => checkpoints == 1);
          final raw = (await t.runAsync(
            SharedPreferencesStorePlatform.instance.getAll,
          ))!['flutter.${scope.preferenceKey('playback_state_v1')}'];
          final row = decodeCompletionPhysical(raw)['video_p14_queue'] as Map;
          if (held == 'resume physical write') {
            expect(row['positionMs'], 180000);
            expect(row['speed'], 1.5);
            expect(
              row,
              isNot(contains('trackPreferences')),
              reason:
                  'Original resume replaces the row and its held physical write removes the preference payload',
            );
          } else {
            expect(row['positionMs'], 60000);
            expect(row['speed'], 1.0);
            expect(row['trackPreferences'], containsPair('audioTrackId', '1'));
            expect(
              row['trackPreferences'],
              containsPair('subtitleTrackId', 'no'),
            );
          }
          expect(f.player.state.track.audio.id, '1');
          final legacy = await f.finish(
            t,
            VideoResumeStorage.getVideoResume(
              'https://player.test/p14-queue.mp4',
            ),
          );
          expect(legacy?['positionMs'], 180000);
          expect(legacy?['speed'], 1.5);
        } finally {
          read.release();
          store?.release();
          MainPageBridge.removePlaybackCheckpointListener(checkpoint);
          await f.close(t);
          SharedPreferencesStorePlatform.instance = old;
        }
      },
    );
  }
}
