import 'package:debrify/models/android_video_renderer_mode.dart';
import 'package:debrify/screens/video_player/widgets/player_menu_panel.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/storage/player_settings_storage.dart';
import 'package:debrify/services/storage/video_resume_storage.dart';
import 'package:flutter_test/flutter_test.dart';
// Existing resolved transport; application dependencies unchanged.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'support/display_mode_driver.dart';
import 'support/local_completion_driver.dart';
import 'support/pip_lifecycle_driver.dart';
import 'support/video_player_environment.dart';

void main() {
  for (final stage in ['map delivery', 'physical write']) {
    testWidgets(
      'Resume P14 $stage survives same-State renderer replacement with captured save values',
      (t) async {
        final f = VideoPlayerEnvironment(native: true);
        final lifecycle = PipLifecycleDriver(t, f);
        await lifecycle.initialize();
        final display = DisplayModeDriver(t, f);
        final old = SharedPreferencesStorePlatform.instance;
        CompletionWrites? store;
        final read = CompletionDelivery(
          stage == 'map delivery'
              ? 'saveVideoPlaybackState'
              : 'saveResumeLocked',
          (v) =>
              stage == 'map delivery' ? v is Map<String, dynamic> : v == null,
        );
        read.armed = false;
        var checkpoints = 0;
        void checkpoint() => checkpoints++;
        MainPageBridge.addPlaybackCheckpointListener(checkpoint);
        const url = 'https://player.test/p14-renderer.mp4';
        try {
          await display.defaults();
          await f.finish(
            t,
            PlayerSettingsStorage.setAndroidVideoRendererMode(
              AndroidVideoRendererMode.directSurface,
            ),
          );
          await lifecycle.mount(
            const VideoPlayerScreen(videoUrl: url, title: 'P14 renderer'),
          );
          final owner = t.state(find.byType(VideoPlayerScreen));
          final original = f.player;
          original.state = original.state.copyWith(
            position: const Duration(minutes: 5),
          );
          original.emit('position', original.state.position);
          await f.advance(t);
          store = await t.runAsync(CompletionWrites.install);
          final scope = ProfileRuntime.capture();
          final menu = await display.menu(PlayerMenuSection.speed);
          checkpoints = 0;
          read.armed = true;
          read.run(() => menu.onSpeedSelected(1.5));
          await f.until(t, () => read.pending.isNotEmpty);
          expect(checkpoints, 0);
          original.state = original.state.copyWith(position: Duration.zero);
          original.emit('position', Duration.zero);
          await f.advance(t);
          original.emit('error', 'synthetic MediaCodec video output failure');
          await f.until(t, () => f.players.length == 2);
          final fresh = f.player;
          fresh.deliverReady();
          await f.until(t, () => fresh.calls.any((c) => c.$1 == 'open'));
          await lifecycle.settle();
          expect(t.state(find.byType(VideoPlayerScreen)), same(owner));
          expect(original.disposed.isCompleted, isTrue);
          expect(fresh.state.position, const Duration(milliseconds: 80));
          expect(checkpoints, 0);
          read.release();
          await f.until(t, () => checkpoints > 0);
          expect(
            decodeCompletionPhysical(
              await store!.physical(scope, 'playback_state_v1'),
            )['video_p14_renderer'],
            containsPair('positionMs', 300000),
          );
          final row = await f.finish(t, VideoResumeStorage.getVideoResume(url));
          expect(row?['positionMs'], 300000);
          expect(row?['speed'], 1.5);
          expect(row?['durationMs'], 1200000);
        } finally {
          read.release();
          MainPageBridge.removePlaybackCheckpointListener(checkpoint);
          await lifecycle.close();
          SharedPreferencesStorePlatform.instance = old;
        }
      },
    );
  }
}
