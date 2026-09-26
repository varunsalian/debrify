import 'dart:async';
import 'dart:io';

import 'package:debrify/features/sources/data/local_source_files.dart';
import 'package:debrify/models/series_source.dart';
import 'package:flutter_test/flutter_test.dart';

class PendingFolder extends Fake implements Directory {
  PendingFolder(this.path);
  @override
  final String path;
  final metadata = Completer<FileStat>();
  int reads = 0;
  @override
  Future<FileStat> stat() {
    reads++;
    return metadata.future;
  }
}

void main() {
  late Directory root;
  late FileStat metadata;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('series-binding-');
    metadata = await root.stat();
  });
  tearDown(() => root.delete(recursive: true));

  test(
    'folder binding preserves path metadata and episode-count size',
    () async {
      final folder = await Directory('${root.path}/A Show').create();
      final stat = await folder.stat();
      final before = DateTime.now().millisecondsSinceEpoch;
      final source = await localSourceFromSeriesFolder(
        folder,
        title: 'Fallback',
        episodeCount: 7,
      );
      final after = DateTime.now().millisecondsSinceEpoch;
      expect(source!.torrentHash, SeriesSource.localSourceHash(folder.path));
      expect(source.torrentName, 'A Show');
      expect(source.debridService, SeriesSource.localService);
      expect(source.debridTorrentId, folder.path);
      expect(source.localPath, folder.path);
      expect(source.localUri, Uri.directory(folder.path).toString());
      expect(source.localKind, SeriesSource.localKindSeriesFolder);
      expect(source.localSizeBytes, 7);
      expect(source.localModifiedAt, stat.modified.millisecondsSinceEpoch);
      expect(source.boundAt, inInclusiveRange(before, after));
    },
  );

  test('empty path label falls back to the supplied title', () async {
    final folder = PendingFolder('/');
    final pending = localSourceFromSeriesFolder(
      folder,
      title: 'Fallback',
      episodeCount: 1,
    );
    folder.metadata.complete(metadata);
    final source = await pending;
    expect(source!.torrentName, 'Fallback');
    expect(source.localPath, '/');
    expect(source.localUri, Uri.directory('/').toString());
    expect(folder.reads, 1);
  });

  test('retirement during folder stat prevents binding publication', () async {
    final folder = PendingFolder('/fixture/Show');
    var active = true;
    final pending = localSourceFromSeriesFolder(
      folder,
      title: 'Show',
      episodeCount: 2,
      canContinue: () => active,
    );
    expect(folder.reads, 1);
    active = false;
    folder.metadata.complete(metadata);
    expect(await pending, isNull);
  });

  for (final retired in [false, true]) {
    test('stat errors retain propagation after retirement=$retired', () async {
      final folder = PendingFolder('/fixture/Show');
      var active = true;
      final pending = localSourceFromSeriesFolder(
        folder,
        title: 'Show',
        episodeCount: 2,
        canContinue: () => active,
      );
      final failure = FileSystemException('fixture failure');
      final checked = expectLater(pending, throwsA(same(failure)));
      if (retired) active = false;
      folder.metadata.completeError(failure);
      await checked;
      expect(folder.reads, 1);
    });
  }
}
