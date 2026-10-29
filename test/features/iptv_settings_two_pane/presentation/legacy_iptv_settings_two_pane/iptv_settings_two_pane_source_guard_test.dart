import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'facade and entire feature add no playback persistence or wrapper responsibilities',
    () {
      final files = [
        File('lib/screens/settings/iptv_settings_two_pane.dart'),
        ...Directory('lib/features/iptv_settings_two_pane').existsSync()
            ? Directory('lib/features/iptv_settings_two_pane')
                  .listSync(recursive: true)
                  .whereType<File>()
                  .where((f) => f.path.endsWith('.dart'))
            : <File>[],
      ];
      for (final file in files) {
        expect(
          file.readAsStringSync(),
          isNot(
            matches(
              r'package:http|shared_preferences|sqflite|media_kit|player_launch|native_bridge|services/profiles/|AutomaticKeepAlive|IndexedStack|\bBuilder\(',
            ),
          ),
          reason: file.path,
        );
      }
    },
  );
}
