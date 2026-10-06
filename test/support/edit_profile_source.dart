import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

String editProfileOriginalSource() {
  final result = Process.runSync('python3', [
    'dev/tool/edit_profile_source_reader.py',
    '--json',
    '--parser-package',
    '${Directory.current.path}/.dart_tool/edit_profile_parser/source_reader/.dart_tool/package_config.json',
  ]);
  expect(
    result.exitCode,
    0,
    reason: 'Edit profile declaration/binding proof: ${result.stderr}',
  );
  return (jsonDecode(result.stdout as String) as Map)['source'] as String;
}
