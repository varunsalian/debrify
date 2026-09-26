import 'dart:io';

import 'package:debrify/features/sources/data/local_source_files.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  setUp(
    () async => root = await Directory.systemTemp.createTemp('folder-lookup-'),
  );
  tearDown(() => root.delete(recursive: true));

  test('matching picked folder wins over matching children', () async {
    final folder = await Directory('${root.path}/Office').create();
    await Directory('${folder.path}/The Office').create();
    final result = await lookupLocalSeriesFolders(
      folder.path,
      title: 'The Office',
    );
    expect(result!.direct!.path, folder.path);
    expect(result.candidates, isEmpty);
  });

  test(
    'unmatched parent returns ordered immutable direct-child choices',
    () async {
      for (final name in [
        'Office',
        'The Office',
        'Other',
        'Nested/The Office',
      ]) {
        await Directory('${root.path}/$name').create(recursive: true);
      }
      final result = await lookupLocalSeriesFolders(
        root.path,
        title: 'The Office',
      );
      expect(result!.direct, isNull);
      expect(result.candidates.map((candidate) => candidate.folderName), [
        'The Office',
        'Office',
      ]);
      expect(() => result.candidates.clear(), throwsUnsupportedError);
    },
  );

  test('missing folder is unavailable even when its name matches', () async {
    expect(
      await lookupLocalSeriesFolders(
        '${root.path}/The Office',
        title: 'The Office',
      ),
      isNull,
    );
  });

  test('existing unmatched empty folder remains eligible for help', () async {
    final result = await lookupLocalSeriesFolders(
      root.path,
      title: 'The Office',
    );
    expect(result, isNotNull);
    expect(result!.direct, isNull);
    expect(result.candidates, isEmpty);
  });

  test('retirement during existence check rejects direct match', () async {
    final folder = await Directory('${root.path}/The Office').create();
    var active = true;
    final pending = lookupLocalSeriesFolders(
      folder.path,
      title: 'The Office',
      canContinue: () => active,
    );
    active = false;
    expect(await pending, isNull);
  });
}
