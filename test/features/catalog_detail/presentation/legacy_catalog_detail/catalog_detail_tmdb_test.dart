import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final name in [
    'R O configured original TMDB credits success uses direct transport',
    'R O configured original TMDB recommendations success uses direct transport',
  ]) {
    test(name, () async {
      final temp = await Directory.systemTemp.createTemp('catalog_tmdb_');
      try {
        final child = File('${temp.path}/catalog_detail_tmdb_child_test.dart');
        var source = File(
          'dev/tool/catalog_detail_tmdb_fixture.dart.txt',
        ).readAsStringSync();
        for (final helper in [
          'catalog_detail_fixture.dart',
          'catalog_detail_http_transport.dart',
        ]) {
          source = source.replaceAll(
            '../test/support/$helper',
            File('test/support/$helper').absolute.uri.toString(),
          );
        }
        await child.writeAsString(source);
        final result = await Process.run('flutter', [
          'test',
          '--dart-define=TMDB_READ_ACCESS_TOKEN=catalog-original-fixture',
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
