import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import '../../../../support/stremio_tv_tuner_source.dart';

void main() {
  test('dial ignores nested scroll-end notifications', () {
    final files = [
      File('lib/screens/stremio_tv/widgets/stremio_tv_tuner.dart'),
      if (Directory('lib/features/stremio_tv_tuner').existsSync())
        ...Directory('lib/features/stremio_tv_tuner')
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart')),
    ];
    expect(
      files.map((f) => f.readAsStringSync()).join('\n'),
      matches(r'n\.depth == 0 && n is ScrollEndNotification'),
      reason: 'dial scroll-end handling keeps its depth-zero source guard',
    );
  });

  test(
    'real-config checker fixtures and source reader accept all steps and reject mutations',
    () {
      final result = Process.runSync('python3', [
        'dev/tool/stremio_tv_tuner_checker_test.py',
        '--parser-package',
        '.dart_tool/stremio_tv_tuner_parser/ci_checker/.dart_tool/package_config.json',
        if (const bool.fromEnvironment('STREMIO_TV_TUNER_BROKEN_CHECKER'))
          '--broken-fixture',
      ]);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      final config =
          jsonDecode(
                File(
                  'dev/tool/stremio_tv_tuner_checker_config.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      if ((config['completed_step'] as int) >= 1) {
        final architecture = Process.runSync('python3', [
          'dev/tool/stremio_tv_tuner_architecture_test.py',
        ]);
        expect(
          architecture.exitCode,
          0,
          reason: '${architecture.stdout}\n${architecture.stderr}',
        );
      }
    },
    timeout: const Timeout(Duration(minutes: 15)),
  );
  final originals =
      jsonDecode(
            File(
              'test/features/stremio_tv_tuner/presentation/legacy_stremio_tv_tuner/stremio_tv_tuner_original_bodies.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  for (final entry in originals.entries) {
    test('complete original body and comments ${entry.key}', () {
      expect(tunerOriginalMember(entry.key), entry.value);
    });
  }
  test(
    'no playback, keep-alive or sibling-feature additions in facade or feature',
    () {
      final files = [
        File('lib/screens/stremio_tv/widgets/stremio_tv_tuner.dart'),
        if (Directory('lib/features/stremio_tv_tuner').existsSync())
          ...Directory('lib/features/stremio_tv_tuner')
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => f.path.endsWith('.dart')),
      ];
      for (final file in files) {
        expect(
          file.readAsStringSync(),
          isNot(
            matches(
              r'KeepAlive|AutomaticKeepAliveClientMixin|IndexedStack|package:media_kit|hero_trailer_backdrop|video_player_launcher|features/player_launch|features/stremio_tv/|features/stremio_tv_catalogs/',
            ),
          ),
          reason: file.path,
        );
      }
    },
  );
}
