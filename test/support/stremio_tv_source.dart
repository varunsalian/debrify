import 'dart:convert';
import 'dart:io';

Map<String, dynamic>? _verified;
Map<String, dynamic> _stremioTvVerifiedSource() {
  if (_verified != null) {
    return _verified!;
  }
  final result = Process.runSync('python3', [
    'dev/tool/stremio_tv_source_reader.py',
    '--json',
    if (const bool.fromEnvironment('STREMIO_TV_COMPLETE')) '--complete',
  ]);
  if (result.exitCode != 0) {
    throw StateError(
      'Stremio TV ORIGINAL source proof failed:\n${result.stderr}',
    );
  }
  return _verified =
      jsonDecode(result.stdout as String) as Map<String, dynamic>;
}

String stremioTvOriginalSource() =>
    _stremioTvVerifiedSource()['source'] as String;
String stremioTvCurrentSource() =>
    _stremioTvVerifiedSource()['current_source'] as String;
Set<String> stremioTvSourceFiles() =>
    (_stremioTvVerifiedSource()['files'] as List).cast<String>().toSet();
