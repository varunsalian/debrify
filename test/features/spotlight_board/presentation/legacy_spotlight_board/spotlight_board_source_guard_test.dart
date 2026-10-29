import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('no playback engine or keep-alive addition in facade or feature', () {
    final files = <File>[
      File('lib/widgets/home/spotlight_board.dart'),
      ...Directory('lib/features')
          .listSync(recursive: true)
          .whereType<File>()
          .where(
            (f) =>
                f.path.startsWith('lib/features/spotlight_board/') &&
                f.path.endsWith('.dart'),
          ),
    ];
    for (final file in files) {
      expect(
        file.readAsStringSync(),
        isNot(
          matches(
            r'KeepAlive|AutomaticKeepAliveClientMixin|IndexedStack|package:media_kit|hero_trailer_backdrop|video_player_launcher|features/player_launch',
          ),
        ),
        reason: file.path,
      );
    }
  });
}
