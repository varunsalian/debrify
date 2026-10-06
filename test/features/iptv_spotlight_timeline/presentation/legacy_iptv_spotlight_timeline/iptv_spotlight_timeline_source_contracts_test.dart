import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import '../../../../support/iptv_spotlight_timeline_source.dart';

void main() {
  test(
    'real-config checker fixtures and source reader accept all steps and reject mutations',
    () {
      final result = Process.runSync('python3', [
        'dev/tool/iptv_spotlight_timeline_checker_test.py',
        '--parser-package',
        '.dart_tool/iptv_spotlight_timeline_parser/ci_checker/.dart_tool/package_config.json',
        if (const bool.fromEnvironment(
          'IPTV_SPOTLIGHT_TIMELINE_BROKEN_CHECKER',
        ))
          '--broken-fixture',
      ]);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      final config =
          jsonDecode(
                File(
                  'dev/tool/iptv_spotlight_timeline_checker_config.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      if ((config['completed_step'] as int) >= 1) {
        final architecture = Process.runSync('python3', [
          'dev/tool/iptv_spotlight_timeline_architecture_test.py',
        ]);
        expect(
          architecture.exitCode,
          0,
          reason: '${architecture.stdout}\n${architecture.stderr}',
        );
      }
    },
    timeout: const Timeout(Duration(minutes: 45)),
  );
  test(
    'row-height comments remain attached and unused builder contexts stay named',
    () {
      final files = [
        File('lib/widgets/iptv/spotlight/spotlight_live_timeline.dart'),
        if (Directory('lib/features/iptv_spotlight_timeline').existsSync())
          ...Directory('lib/features/iptv_spotlight_timeline')
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => f.path.endsWith('.dart')),
      ];
      final source = files.map((f) => f.readAsStringSync()).join('\n');
      expect(
        source,
        matches(
          r'// A two-line name and the subtitle both grow with accessibility text size\.\s+// Share the adjusted extent with painting, viewport loading and focus reveal\.\s+double get (?:_rowHeight|rowHeight)',
        ),
      );
      final build = timelineOriginalMember('_SpotlightLiveTimelineState.build');
      expect(build, contains('Widget build(BuildContext context)'));
      expect(build, contains('builder: (context, constraints)'));
      expect(build, contains('builder: (context, rowConstraints)'));
      expect(build, contains('itemBuilder: (context, index)'));
    },
  );
  final originals =
      jsonDecode(
            File(
              'test/features/iptv_spotlight_timeline/presentation/legacy_iptv_spotlight_timeline/iptv_spotlight_timeline_original_bodies.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  for (final entry in originals.entries) {
    test('complete original body and comments ${entry.key}', () {
      expect(
        () => timelineOriginalMember(entry.key),
        returnsNormally,
        reason:
            'the complete original declaration must pass its live source proof',
      );
      expect(timelineOriginalMember(entry.key), entry.value);
    });
  }
  test(
    'no playback, keep-alive or sibling-feature additions in facade or feature',
    () {
      final files = [
        File('lib/widgets/iptv/spotlight/spotlight_live_timeline.dart'),
        if (Directory('lib/features/iptv_spotlight_timeline').existsSync())
          ...Directory('lib/features/iptv_spotlight_timeline')
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => f.path.endsWith('.dart')),
      ];
      for (final file in files) {
        expect(
          file.readAsStringSync(),
          isNot(
            matches(
              r'KeepAlive|AutomaticKeepAliveClientMixin|IndexedStack|package:media_kit|video_player_launcher|features/player_launch|features/iptv/',
            ),
          ),
          reason: file.path,
        );
      }
    },
  );
}
