import 'package:debrify/screens/video_player_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('installation requires the explicit test-only compile-time flag', () {
    if (const bool.fromEnvironment('DEBRIFY_VP_TEST_HOOKS')) {
      expect(() => VideoPlayerScreenTestHooks.install(null), returnsNormally);
    } else {
      expect(() => VideoPlayerScreenTestHooks.install(null), throwsStateError);
    }
  });
}
