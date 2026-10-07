import 'dart:convert';
import 'dart:io';

const recordingsComplete = bool.fromEnvironment('RECORDINGS_COMPLETE');
Map<String, dynamic>? _snapshot;

Map<String, dynamic> recordingsSource() => _snapshot ??= () {
  final result = Process.runSync('python3', [
    'dev/tool/recordings_source_reader.py',
    '--json',
    if (recordingsComplete) '--complete',
  ]);
  if (result.exitCode != 0) {
    throw StateError(
      'Recordings AST proof failed: ${result.stdout}${result.stderr}',
    );
  }
  return jsonDecode(result.stdout as String) as Map<String, dynamic>;
}();
