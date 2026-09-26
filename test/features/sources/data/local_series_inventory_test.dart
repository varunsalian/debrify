import 'dart:io';

import 'package:debrify/services/local_bound_source_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('local-series-fixture-');
  });
  tearDown(() async {
    await root.delete(recursive: true);
  });

  Future<File> write(String name, int size) async {
    final file = File('${root.path}/$name');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(List.filled(size, 0));
    return file;
  }

  test(
    'legacy series inventory sorts episodes and keeps the largest duplicate',
    () async {
      await write('Show.S02E01.mkv', 40);
      await write('Season 1/Show.S01E02.mkv', 30);
      await write('Show.S01E01.small.mkv', 10);
      final preferred = await write('Season 1/Show.S01E01.large.mkv', 60);
      await write('Show.S01E03.sample.mkv', 100);
      await write('Show.S01E04.txt', 100);
      await write('Unrelated.movie.mkv', 100);
      final modified = DateTime.utc(2025, 1, 2, 3, 4, 5);
      await preferred.setLastModified(modified);

      final episodes = await LocalBoundSourceService.scanSeriesFolder(
        root.path,
      );
      expect(episodes.map((e) => (e.season, e.episode)), [
        (1, 1),
        (1, 2),
        (2, 1),
      ]);
      expect(episodes.first.file.path, preferred.path);
      expect(episodes.first.fileName, 'Show.S01E01.large.mkv');
      expect(episodes.first.relativePath, 'Season 1/Show.S01E01.large.mkv');
      expect(episodes.first.sizeBytes, 60);
      expect(episodes.first.modifiedAt, modified.millisecondsSinceEpoch);
      // The compatibility entry point historically returns a caller-owned list.
      episodes.clear();
      expect(episodes, isEmpty);
    },
  );

  test('missing or empty series folder has no episode candidates', () async {
    expect(await LocalBoundSourceService.scanSeriesFolder(root.path), isEmpty);
    expect(
      await LocalBoundSourceService.scanSeriesFolder('${root.path}/missing'),
      isEmpty,
    );
  });

  test(
    'series inventory does not follow file or directory symlinks',
    () async {
      final outside = await Directory.systemTemp.createTemp(
        'outside-series-fixture-',
      );
      addTearDown(() => outside.delete(recursive: true));
      final file = await File(
        '${outside.path}/Show.S01E01.mkv',
      ).writeAsBytes([0]);
      await Link('${root.path}/Show.S01E01.mkv').create(file.path);
      await Link('${root.path}/Season 1').create(outside.path);
      expect(
        await LocalBoundSourceService.scanSeriesFolder(root.path),
        isEmpty,
      );
    },
    skip: Platform.isWindows
        ? 'Creating symlinks requires Windows host privileges.'
        : false,
  );
}
