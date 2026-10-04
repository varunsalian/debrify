import 'dart:io';

/// Read only after AST equality and physical context guards prove the body.
/// The isolated parser lives inside this worktree, including on CI.
String spotlightOriginalMember(String originalName) {
  final result = Process.runSync('python3', [
    'dev/tool/spotlight_board_source_reader.py',
    originalName,
    '--parser-package',
    '.dart_tool/spotlight_board/parser/.dart_tool/package_config.json',
  ]);
  if (result.exitCode != 0) {
    throw StateError(
      'Original Spotlight body guard failed: $originalName\n'
      '${result.stderr}\n${result.stdout}',
    );
  }
  return (result.stdout as String).trim();
}
