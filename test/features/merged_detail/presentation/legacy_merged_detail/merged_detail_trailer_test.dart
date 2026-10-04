import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final name in [
    'configured original two-candidate trailer dialog cancels without resolving',
    'configured original rejects a stale trailer-candidate response',
  ]) {
    test(name, () async {
      final temp = await Directory.systemTemp.createTemp('merged_trailer_');
      try {
        final child = File(
          '${temp.path}/merged_detail_trailer_child_test.dart',
        );
        var source = File(
          'dev/tool/merged_detail_trailer_fixture.dart.txt',
        ).readAsStringSync();
        for (final helper in [
          'merged_detail_fixture.dart',
          'merged_detail_http_transport.dart',
        ]) {
          source = source.replaceAll(
            '../test/support/$helper',
            File('test/support/$helper').absolute.uri.toString(),
          );
        }
        await child.writeAsString(source);
        final result = await Process.run('flutter', [
          'test',
          '--dart-define=TMDB_READ_ACCESS_TOKEN=merged-original-fixture',
          '--reporter=json',
          child.path,
          '--plain-name',
          name,
        ], workingDirectory: Directory.current.path);
        final reporter = File('${temp.path}/reporter.jsonl');
        await reporter.writeAsString(result.stdout.toString());
        expect(
          result.exitCode,
          0,
          reason: '${result.stdout}\n${result.stderr}',
        );
        final tests = reporter
            .readAsLinesSync()
            .map((line) {
              try {
                return jsonDecode(line);
              } catch (_) {
                return null;
              }
            })
            .whereType<Map<String, dynamic>>()
            .where((e) => e['type'] == 'testDone' && e['hidden'] != true)
            .toList();
        expect(tests, hasLength(1));
        expect(
          tests.single['result'],
          'success',
          reason: reporter.readAsStringSync(),
        );
        expect(tests.single['skipped'], false);
      } finally {
        await temp.delete(recursive: true);
      }
    }, timeout: const Timeout(Duration(minutes: 2)));
  }
}
