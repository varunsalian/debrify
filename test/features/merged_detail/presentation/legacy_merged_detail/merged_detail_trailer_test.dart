import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final name in [
    'configured original two-candidate trailer dialog cancels without resolving',
    'configured original rejects a stale trailer-candidate response',
  ]) {
    test(name, () async {
      final child = File('.dart_tool/merged_detail_trailer_child_test.dart');
      await child.parent.create(recursive: true);
      await child.writeAsString(
        File(
          'dev/tool/merged_detail_trailer_fixture.dart.txt',
        ).readAsStringSync(),
      );
      final common = (await Process.run('git', [
        'rev-parse',
        '--git-common-dir',
      ])).stdout.toString().trim();
      final label =
          'merged_detail/trailer-configured-${DateTime.now().microsecondsSinceEpoch}';
      final result = await Process.run('python3', [
        'dev/tool/suite_evidence.py',
        'run',
        label,
        '--dart-define=TMDB_READ_ACCESS_TOKEN=merged-original-fixture',
        child.path,
        '--plain-name',
        name,
      ]);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      final evidence = File('$common/refactor-evidence/$label.jsonl');
      final events = evidence
          .readAsLinesSync()
          .map((line) {
            try {
              return jsonDecode(line);
            } catch (_) {
              return null;
            }
          })
          .whereType<Map<String, dynamic>>()
          .toList();
      final tests = events
          .where((e) => e['type'] == 'testDone' && e['hidden'] != true)
          .toList();
      expect(tests, hasLength(1));
      expect(
        tests.single['result'],
        'success',
        reason: '${result.stdout}\n${evidence.readAsStringSync()}',
      );
      expect(tests.single['skipped'], false);
      final env =
          jsonDecode(
                File(
                  '$common/refactor-evidence/$label.env.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      expect(env['tree_changed_during_run'], false);
      expect(env['sdk']['frameworkVersion'], '3.44.8');
    }, timeout: const Timeout(Duration(minutes: 2)));
  }
}
