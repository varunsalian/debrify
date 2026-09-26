import 'dart:io';

import 'package:debrify/features/sources/data/local_source_files.dart';
import 'package:debrify/models/series_source.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('local-files-fixture-');
  });
  tearDown(() async {
    await root.delete(recursive: true);
  });
  Future<File> write(String name, int size) async {
    final file = File('${root.path}/$name');
    await file.parent.create(recursive: true);
    return file.writeAsBytes(List.filled(size, 0));
  }

  test(
    'video scan recursively orders by size and publishes immutable metadata',
    () async {
      await write('small.mkv', 10);
      await write('nested/large.MP4', 30);
      await write('readme.txt', 100);
      await Directory('${root.path}/empty.mkv').create();
      final files = await scanLocalVideoFolder(root.path);
      expect(files.map((f) => f.fileName), ['large.MP4', 'small.mkv']);
      expect(files.map((f) => f.sizeBytes), [30, 10]);
      expect(() => files.clear(), throwsUnsupportedError);
      expect(await scanLocalVideoFolder('${root.path}/missing'), isEmpty);
    },
  );

  test('series scan publishes an immutable episode inventory', () async {
    await write('Show.S01E01.mkv', 10);
    final episodes = await scanLocalSeriesFolder(root.path);
    expect(episodes.single.episode, 1);
    expect(() => episodes.clear(), throwsUnsupportedError);
  });

  test(
    'matching series folders are direct children ordered by score and name',
    () async {
      for (final name in [
        'Office Z',
        'Office A',
        'The Office US',
        'Office',
        'The Office',
        'Other',
        'Parent/The Office',
      ]) {
        await Directory('${root.path}/$name').create(recursive: true);
      }
      await write('The Office.txt', 10);
      final matches = await matchingLocalSeriesFolders(
        root.path,
        title: 'The Office',
      );
      expect(matches.map((f) => f.folderName), [
        'The Office',
        'Office',
        'The Office US',
        'Office A',
        'Office Z',
      ]);
      expect(matches.map((f) => f.score), [130, 120, 90, 80, 80]);
      expect(() => matches.clear(), throwsUnsupportedError);
      expect(
        await matchingLocalSeriesFolders(
          '${root.path}/missing',
          title: 'The Office',
        ),
        isEmpty,
      );
    },
  );

  test(
    'local movie source retains path, URI, hash, size and timestamps',
    () async {
      final file = await write('Movie name.mkv', 42);
      final modified = DateTime.utc(2025, 2, 3, 4, 5, 6);
      await file.setLastModified(modified);
      final before = DateTime.now().millisecondsSinceEpoch;
      final source = (await localSourceFromFile(file))!;
      final after = DateTime.now().millisecondsSinceEpoch;
      expect(source.torrentHash, SeriesSource.localSourceHash(file.path));
      expect(source.torrentName, 'Movie name.mkv');
      expect(source.debridService, SeriesSource.localService);
      expect(source.debridTorrentId, file.path);
      expect(source.localPath, file.path);
      expect(source.localUri, Uri.file(file.path).toString());
      expect(source.localKind, SeriesSource.localKindMovieFile);
      expect(source.localSizeBytes, 42);
      expect(source.localModifiedAt, modified.millisecondsSinceEpoch);
      expect(source.boundAt, inInclusiveRange(before, after));
    },
  );

  test('missing and non-video files do not create sources', () async {
    expect(await localSourceFromFile(File('${root.path}/missing.mkv')), isNull);
    expect(await localSourceFromFile(await write('readme.txt', 10)), isNull);
  });
}
