import 'dart:async';
import 'dart:io';

import 'package:debrify/features/sources/data/local_source_files.dart';
import 'package:flutter_test/flutter_test.dart';

class PendingFile extends Fake implements File {
  final existence = Completer<bool>();
  final metadata = Completer<FileStat>();
  final statStarted = Completer<void>();
  var existsCalls = 0;
  var statCalls = 0;

  @override
  String get path => '/fixture/movie.mkv';

  @override
  Future<bool> exists() {
    existsCalls++;
    return existence.future;
  }

  @override
  Future<FileStat> stat() {
    statCalls++;
    statStarted.complete();
    return metadata.future;
  }
}

void main() {
  late Directory root;
  late FileStat stat;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('local-retirement-data-');
    final folder = await Directory('${root.path}/Fixture Show').create();
    final file = await File(
      '${folder.path}/Fixture.Show.S01E01.mkv',
    ).writeAsBytes([1, 2, 3]);
    stat = await file.stat();
  });
  tearDown(() => root.delete(recursive: true));

  final scans =
      <String, Future<List<Object>> Function(String, bool Function())>{
        'video': (path, active) =>
            scanLocalVideoFolder(path, canContinue: active),
        'episodes': (path, active) =>
            scanLocalSeriesFolder(path, canContinue: active),
        'folders': (path, active) => matchingLocalSeriesFolders(
          path,
          title: 'Fixture Show',
          canContinue: active,
        ),
      };
  for (final entry in scans.entries) {
    test('${entry.key} scan retains active results', () async {
      expect(await entry.value(root.path, () => true), hasLength(1));
    });
    test('${entry.key} scan rejects an already retired action', () async {
      expect(await entry.value(root.path, () => false), isEmpty);
    });
    test('${entry.key} scan discards results after retirement', () async {
      var active = true;
      final pending = entry.value(root.path, () => active);
      active = false;
      expect(await pending, isEmpty);
    });
  }

  test('retired file action performs no existence or metadata read', () async {
    final file = PendingFile();
    expect(await localSourceFromFile(file, canContinue: () => false), isNull);
    expect(file.existsCalls, 0);
    expect(file.statCalls, 0);
  });

  test('retirement during existence read prevents metadata read', () async {
    final file = PendingFile();
    var active = true;
    final pending = localSourceFromFile(file, canContinue: () => active);
    expect(file.existsCalls, 1);
    active = false;
    file.existence.complete(true);
    expect(await pending, isNull);
    expect(file.statCalls, 0);
  });

  test('retirement during metadata read prevents source publication', () async {
    final file = PendingFile();
    var active = true;
    final pending = localSourceFromFile(file, canContinue: () => active);
    file.existence.complete(true);
    await file.statStarted.future;
    active = false;
    file.metadata.complete(stat);
    expect(await pending, isNull);
  });

  test('active file action returns source after both reads', () async {
    final file = PendingFile();
    final pending = localSourceFromFile(file, canContinue: () => true);
    file.existence.complete(true);
    await file.statStarted.future;
    file.metadata.complete(stat);
    final source = await pending;
    expect(source?.localPath, file.path);
    expect(source?.localSizeBytes, 3);
    expect(file.existsCalls, 1);
    expect(file.statCalls, 1);
  });
}
