import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('settings dialogs never bypass the TV-safe text field', () {
    final paths = [
      File('lib/screens/settings_screen.dart'),
      File('lib/screens/settings/external_player_settings_page.dart'),
      if (Directory('lib/features/playback_settings').existsSync())
        ...Directory('lib/features/playback_settings')
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('.dart')),
      ...Directory('lib/features/settings')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart')),
    ];
    final source = paths.map((file) => file.readAsStringSync()).join('\n');

    // A raw TextField can strand DPAD-only users on TVs affected by
    // flutter/flutter#177360. TvTextField retains the ordinary mobile/desktop
    // path while supplying the in-app keyboard on television platforms.
    expect(RegExp(r'\bTextField\(').hasMatch(source), isFalse);
    expect(RegExp(r'\bTvTextField\(').allMatches(source), isNotEmpty);
  });
}
