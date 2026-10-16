import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
// Existing fixture transport, no application dependency change.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'support/local_completion_driver.dart';
import 'support/video_player_environment.dart';

void main() {
  testWidgets(
    'Resume P14 periodic six second checkpoint persists playback without explicit notification and stops on disposal',
    (t) async {
      final f = VideoPlayerEnvironment();
      await t.runAsync(f.initialize);
      var checkpoints = 0;
      void checkpoint() => checkpoints++;
      MainPageBridge.addPlaybackCheckpointListener(checkpoint);
      const url = 'https://player.test/p14-auto.mp4';
      try {
        final scope = ProfileRuntime.capture();
        await f.mount(
          t,
          const VideoPlayerScreen(videoUrl: url, title: 'P14 autosave'),
        );
        f.player.state = f.player.state.copyWith(
          position: const Duration(minutes: 5),
        );
        f.player.emit('position', f.player.state.position);
        await f.advance(t, const Duration(seconds: 6));
        await f.actions.settle(t);
        final raw = (await t.runAsync(
          SharedPreferencesStorePlatform.instance.getAll,
        ))!['flutter.${scope.preferenceKey('playback_state_v1')}'];
        expect(
          raw,
          isNotNull,
          reason: 'The periodic callback creates its physical playback map',
        );
        expect(
          decodeCompletionPhysical(raw)['video_p14_autosave'],
          containsPair('positionMs', 300000),
        );
        final row = await t.runAsync(
          () => completionPhysicalResume(f, scope, url),
        );
        expect(row?['position_ms'], 300000);
        expect(checkpoints, 0);
        await t.pumpWidget(const SizedBox.shrink());
        await f.until(t, () => f.player.disposed.isCompleted);
        await f.actions.settle(t);
        expect(
          checkpoints,
          1,
          reason: 'Disposal issues the single explicit exit checkpoint',
        );
        await f.advance(t, const Duration(seconds: 12));
        await f.actions.settle(t);
        expect(checkpoints, 1);
      } finally {
        MainPageBridge.removePlaybackCheckpointListener(checkpoint);
        await f.close(t);
      }
    },
  );
}
