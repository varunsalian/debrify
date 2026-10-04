import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../../../support/spotlight_board_source.dart';

void main() {
  test(
    'AST reader accepts correct moves and rejects executable/comment mutations',
    () {
      final result = Process.runSync('python3', [
        'dev/tool/spotlight_board_source_reader_test.py',
        '--parser-package',
        '.dart_tool/spotlight_board/parser/.dart_tool/package_config.json',
      ]);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    },
  );
  final originals =
      jsonDecode(
            File(
              'test/features/spotlight_board/presentation/legacy_spotlight_board/spotlight_board_original_bodies.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  for (final entry in originals.entries) {
    test('complete original body and comments ${entry.key}', () {
      expect(spotlightOriginalMember(entry.key), entry.value);
    });
  }
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
