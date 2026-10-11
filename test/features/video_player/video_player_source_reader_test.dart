import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/vp_source_reader.dart';

void main() {
  test(
    'declaration reader validates current ownership and chains repeated relocation',
    () {
      final result = Process.runSync('nice', [
        '-n',
        '19',
        'python3',
        'dev/tool/vplayer_source_reader.py',
        '--self-test',
        '--parser-package',
        '${Directory.current.path}/.dart_tool/vplayer_parser/reader_fixture/.dart_tool/package_config.json',
      ]);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      expect(
        vpSourceDeclaration('_VideoPlayerScreenState._generateFilenameHash'),
        contains('nameWithoutExt.hashCode.toString()'),
      );
    },
  );
}
