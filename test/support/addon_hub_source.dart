import 'dart:convert';
import 'dart:io';

Map<String, dynamic>? _bodies;
List<dynamic> addonHubOriginalTokens(String original) {
  if (_bodies == null) {
    final result = Process.runSync('python3', [
      'dev/tool/addon_hub_source_probe.py',
      '--parser-package',
      '${Directory.current.path}/.dart_tool/addon_hub/source_parser/.dart_tool/package_config.json',
    ]);
    if (result.exitCode != 0) {
      throw StateError('Addon hub source parser failed: ${result.stderr}');
    }
    _bodies = jsonDecode(result.stdout as String) as Map<String, dynamic>;
  }
  return _bodies![original] as List<dynamic>;
}
