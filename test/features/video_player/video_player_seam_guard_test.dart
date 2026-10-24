import 'dart:io';

import 'package:debrify/screens/video_player_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('S has only the frozen installer and once-only default paths', () {
    final result = Process.runSync('nice', [
      '-n',
      '19',
      'python3',
      'dev/tool/vplayer_seam_proof.py',
      '--parser-package',
      '${Directory.current.path}/.dart_tool/vplayer_parser/seam_guard/.dart_tool/package_config.json',
    ]);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    // P20: the relocated instance branch is active (resolution P1-2/R6).
    expect(result.stdout, contains('"p20_relocated_instance": true'));
  });

  test('installation requires the explicit test-only compile-time flag', () {
    if (const bool.fromEnvironment('DEBRIFY_VP_TEST_HOOKS')) {
      expect(() => VideoPlayerScreenTestHooks.install(null), returnsNormally);
    } else {
      expect(() => VideoPlayerScreenTestHooks.install(null), throwsStateError);
    }
  });
}
