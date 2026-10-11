import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Current declaration text only, after exhaustive ownership/body/binding
/// validation and manifest relocation. Historical text never satisfies tests.
String vpSourceDeclaration(String identity) {
  final result = Process.runSync('nice', [
    '-n',
    '19',
    'python3',
    'dev/tool/vplayer_source_reader.py',
    '--declaration',
    identity,
    '--parser-package',
    '${Directory.current.path}/.dart_tool/vplayer_parser/source_reader/.dart_tool/package_config.json',
  ]);
  expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  return (jsonDecode(result.stdout as String) as Map)['source'] as String;
}
