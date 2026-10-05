import 'dart:convert';
import 'dart:io';

Map<String, dynamic>? _verified;

Map<String, dynamic> _debrifyTvVerifiedSource() {
  if (_verified != null) {
    return _verified!;
  }
  final result = Process.runSync('python3', [
    'dev/tool/debrify_tv_source_reader.py',
    '--json',
    if (const bool.fromEnvironment('DEBRIFY_TV_COMPLETE')) '--complete',
  ]);
  if (result.exitCode != 0) {
    throw StateError(
      'Debrify TV ORIGINAL source proof failed:\n${result.stderr}',
    );
  }
  return _verified =
      jsonDecode(result.stdout as String) as Map<String, dynamic>;
}

String debrifyTvOriginalSource() =>
    _debrifyTvVerifiedSource()['source'] as String;

Set<String> debrifyTvSourceFiles() =>
    (_debrifyTvVerifiedSource()['files'] as List).cast<String>().toSet();
