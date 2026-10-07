import 'dart:convert';
import 'dart:io';

Map<String, dynamic>? _source;
Map<String, dynamic> timelineVerifiedSource() {
  if (_source != null) {
    return _source!;
  }
  final result = Process.runSync('python3', [
    'dev/tool/iptv_spotlight_timeline_source_reader.py',
    '--json',
    '--parser-package',
    '.dart_tool/iptv_spotlight_timeline_parser/source_reader/.dart_tool/package_config.json',
  ]);
  if (result.exitCode != 0) {
    throw StateError(
      'Timeline ORIGINAL source proof failed: ${result.stdout}\n${result.stderr}',
    );
  }
  return _source = jsonDecode(result.stdout as String) as Map<String, dynamic>;
}

String timelineOriginalMember(String name) =>
    (timelineVerifiedSource()['members'] as Map<String, dynamic>)[name]
        as String;
