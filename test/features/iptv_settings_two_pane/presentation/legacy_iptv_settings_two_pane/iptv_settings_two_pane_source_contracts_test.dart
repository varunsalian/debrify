import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import '../../../../support/iptv_settings_two_pane_source.dart';

void main() {
  test(
    'real-config checker fixtures reject mutations and source reader accepts steps',
    () {
      final args = [
        'dev/tool/iptv_settings_two_pane_checker_test.py',
        '--parser-package',
        '.dart_tool/iptv_settings_two_pane_parser/ci_checker/.dart_tool/package_config.json',
      ];
      final result = Process.runSync('python3', [
        ...args,
        if (const bool.fromEnvironment('IPTV_SETTINGS_TWO_PANE_BROKEN_CHECKER'))
          '--broken-fixture',
      ]);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      final control = Process.runSync('python3', [...args, '--broken-fixture']);
      expect(
        control.exitCode,
        isNot(0),
        reason: 'broken fixture must fail the checker runner',
      );
      expect(
        control.stderr,
        contains('deliberately broken checker fixture positive control'),
      );
      final config =
          jsonDecode(
                File(
                  'dev/tool/iptv_settings_two_pane_checker_config.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      if ((config['completed_step'] as int) >= 1) {
        final architecture = Process.runSync('python3', [
          'dev/tool/iptv_settings_two_pane_architecture_test.py',
        ]);
        expect(
          architecture.exitCode,
          0,
          reason: '${architecture.stdout}\n${architecture.stderr}',
        );
      }
    },
    timeout: const Timeout(Duration(minutes: 30)),
  );
  final originals =
      jsonDecode(
            File(
              'test/features/iptv_settings_two_pane/presentation/legacy_iptv_settings_two_pane/iptv_settings_two_pane_original_bodies.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  for (final entry in originals.entries) {
    test('complete original body and comments ${entry.key}', () {
      expect(twoPaneOriginalMember(entry.key), entry.value);
    });
  }
  test(
    'facade and entire feature add no playback persistence or wrapper responsibilities',
    () {
      final files = [
        File('lib/screens/settings/iptv_settings_two_pane.dart'),
        ...Directory('lib/features/iptv_settings_two_pane').existsSync()
            ? Directory('lib/features/iptv_settings_two_pane')
                  .listSync(recursive: true)
                  .whereType<File>()
                  .where((f) => f.path.endsWith('.dart'))
            : <File>[],
      ];
      for (final file in files) {
        expect(
          file.readAsStringSync(),
          isNot(
            matches(
              r'package:http|shared_preferences|sqflite|media_kit|player_launch|native_bridge|services/profiles/|AutomaticKeepAlive|IndexedStack|\bBuilder\(',
            ),
          ),
          reason: file.path,
        );
      }
    },
  );
}
