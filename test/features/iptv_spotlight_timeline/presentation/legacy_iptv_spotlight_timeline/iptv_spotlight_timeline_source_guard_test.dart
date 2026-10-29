import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'no playback, keep-alive or sibling-feature additions in facade or feature',
    () {
      final files = [
        File('lib/widgets/iptv/spotlight/spotlight_live_timeline.dart'),
        if (Directory('lib/features/iptv_spotlight_timeline').existsSync())
          ...Directory('lib/features/iptv_spotlight_timeline')
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => f.path.endsWith('.dart')),
      ];
      for (final file in files) {
        expect(
          file.readAsStringSync(),
          isNot(
            matches(
              r'KeepAlive|AutomaticKeepAliveClientMixin|IndexedStack|package:media_kit|video_player_launcher|features/player_launch|features/iptv/',
            ),
          ),
          reason: file.path,
        );
      }
    },
  );
}
