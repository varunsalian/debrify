import 'package:debrify/screens/video_player/models/gesture_state.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/storage/video_resume_storage.dart';
import 'package:flutter_test/flutter_test.dart';
// Existing preferences transport, without changing application dependencies.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'support/display_mode_driver.dart';
import 'support/local_completion_driver.dart';
import 'support/player_actions.dart';
import 'support/video_player_environment.dart';

void main() {
  testWidgets(
    'Resume P14 checkpoint during temporary 2x writes pre-hold speed to both physical stores',
    (t) async {
      final f = VideoPlayerEnvironment();
      await t.runAsync(f.initialize);
      final display = DisplayModeDriver(t, f);
      try {
        await display.defaults();
        await f.mount(t, displayScreen());
        await display.speed(1.5);
        await display.startHold();
        expect(playerControls(t).speed, 2.0);
        // The real aspect-menu caller checkpoints while the hold is active.
        await display.aspect(AspectMode.cover);
        await f.actions.settle(t);
        final scope = ProfileRuntime.capture();
        final raw = (await t.runAsync(
          SharedPreferencesStorePlatform.instance.getAll,
        ))!['flutter.${scope.preferenceKey('playback_state_v1')}'];
        final rows = decodeCompletionPhysical(raw);
        final row = rows.values.single as Map;
        expect(row['speed'], 1.5);
        expect(row['aspect'], 'cover');
        final legacy = await f.finish(
          t,
          VideoResumeStorage.getVideoResume('https://player.test/display.mp4'),
        );
        expect(legacy?['speed'], 1.5);
        expect(legacy?['aspect'], 'cover');
        expect(playerControls(t).speed, 2.0);
        expect(f.player.state.rate, 2.0);
        await display.endHold();
        expect(playerControls(t).speed, 1.5);
      } finally {
        await f.close(t);
      }
    },
  );
}
