// The scanner over real temporary folders: what lands in which category,
// which profile and generation own a file, and which folders are walked.
import 'dart:io';

import 'package:debrify/features/storage_usage/data/storage_scanner.dart';
import 'package:debrify/features/storage_usage/models/storage_usage_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory sandbox;

  setUp(() => sandbox = Directory.systemTemp.createTempSync('storage_scan'));
  tearDown(() => sandbox.deleteSync(recursive: true));

  void write(String relative, int bytes) {
    final file = File(p.join(sandbox.path, relative));
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(List.filled(bytes, 0));
  }

  test('groups files by kind and by owning profile generation', () {
    write('data/app_flutter/profiles/alice/g/2/documents/iptv_catalog.db', 500);
    write(
      'data/app_flutter/profiles/alice/g/2/documents/iptv_catalog.db-wal',
      100,
    );
    write('data/app_flutter/profiles/alice/g/1/documents/iptv_catalog.db', 300);
    write('data/app_flutter/profiles/alice/avatars/a.png', 7);
    write('data/app_flutter/profiles/bob/g/1/documents/debrify_tv.db', 40);
    write('data/cache/debrifyImageCache/x.jpg', 60);
    write('data/databases/debrifyImageCache.db', 5);
    write('data/cache/image_manager_disk_cache/blob.0', 20);
    write('data/cache/xmltv_123.tmp', 80);
    write('data/files/epg_cache/guide.json', 9);
    write('data/files/diagnostics/log.jsonl', 3);
    write('data/shared_prefs/FlutterSharedPreferences.xml', 2);
    write('data/files/profiles.db', 4);
    write('data/files/engines/engine.yaml', 1);

    final scan = scanStorageRoots([
      StorageRoot(label: 'App data', path: p.join(sandbox.path, 'data')),
    ]);

    expect(scan.totalBytes, 1131);
    expect(scan.fileCount, 14);
    expect(scan.byCategory, {
      StorageCategory.iptvCatalogs: 900,
      StorageCategory.debrifyTv: 40,
      StorageCategory.imageCache: 85,
      StorageCategory.guideDownloads: 80,
      StorageCategory.guideCache: 9,
      StorageCategory.logs: 3,
      StorageCategory.preferences: 2,
      StorageCategory.otherDatabases: 4,
      // The avatar and the search engine file.
      StorageCategory.other: 8,
    });
    final byProfile = {
      for (final usage in scan.byProfile) usage.profileId: usage.byGeneration,
    };
    expect(byProfile, {
      'alice': {2: 600, 1: 300, null: 7},
      'bob': {1: 40},
    });
    expect(scan.unreadableFolders, 0);
  });

  test('keeps the largest files, largest first, with their owner', () {
    for (var i = 1; i <= kStorageLargestFiles + 5; i++) {
      write('root/f$i.bin', i * 10);
    }
    write('root/profiles/carol/g/4/documents/iptv_catalog.db', 1000);

    final scan = scanStorageRoots([
      StorageRoot(label: 'Docs', path: p.join(sandbox.path, 'root')),
    ]);

    expect(scan.largest, hasLength(kStorageLargestFiles));
    final top = scan.largest.first;
    expect(top.bytes, 1000);
    expect(
      top.displayPath,
      p.join(
        'Docs',
        'profiles',
        'carol',
        'g',
        '4',
        'documents',
        'iptv_catalog.db',
      ),
    );
    expect(top.profileId, 'carol');
    expect(top.generation, 4);
    expect(top.category, StorageCategory.iptvCatalogs);
    final sizes = scan.largest.map((file) => file.bytes).toList();
    expect(sizes, [...sizes]..sort((a, b) => b.compareTo(a)));
    // The smallest kept file beats every file left out.
    expect(sizes.last, 70);
  });

  test('a shared folder only counts the entries Debrify owns', () {
    write('shared/profiles/dave/g/1/documents/iptv_catalog.db', 50);
    write('shared/iptv_catalog.db', 30);
    write('shared/iptv_catalog.db-wal', 10);
    write('shared/Someone else/huge.mov', 9999);
    write('shared/notes.txt', 9999);

    final scan = scanStorageRoots([
      StorageRoot(
        label: 'Documents',
        path: p.join(sandbox.path, 'shared'),
        onlyEntries: const ['profiles', 'iptv_catalog.db*'],
      ),
    ]);

    expect(scan.totalBytes, 90);
    expect(scan.byCategory, {StorageCategory.iptvCatalogs: 90});
  });

  test('a nested entry walks only the folder it names', () {
    write('shared/profiles/profile-a1/g/1/documents/iptv_catalog.db', 50);
    write('shared/profiles/other-app/data.bin', 9999);

    final scan = scanStorageRoots([
      StorageRoot(
        label: 'Documents',
        path: p.join(sandbox.path, 'shared'),
        onlyEntries: const ['profiles/profile-a1', 'profiles/missing'],
      ),
    ]);

    expect(scan.totalBytes, 50);
    expect(scan.byProfile.single.profileId, 'profile-a1');
    expect(scan.unreadableFolders, 0);
  });

  test('a root inside another is not counted twice', () {
    write('data/app_flutter/a.bin', 10);
    write('data/cache/b.bin', 20);

    final scan = scanStorageRoots([
      StorageRoot(label: 'All', path: p.join(sandbox.path, 'data')),
      StorageRoot(
        label: 'Documents',
        path: p.join(sandbox.path, 'data', 'app_flutter'),
      ),
      // The same folder twice, spelled differently.
      StorageRoot(label: 'Again', path: p.join(sandbox.path, 'data', '.')),
    ]);

    expect(scan.totalBytes, 30);
    expect(scan.fileCount, 2);
  });

  test('the background scan matches the direct one', () async {
    write('data/profiles/p1/g/1/documents/iptv_catalog.db', 70);
    write('data/cache/xmltv_1.tmp', 30);
    final roots = [
      StorageRoot(label: 'App data', path: p.join(sandbox.path, 'data')),
    ];

    final scan = await scanStorageInBackground(roots);

    expect(scan.totalBytes, 100);
    expect(scan.byCategory, scanStorageRoots(roots).byCategory);
    expect(scan.largest.first.profileId, 'p1');
  });

  test('a cancelled background scan stops with StorageScanCancelled', () async {
    write('data/a.bin', 1);
    final cancellation = StorageScanCancellation()..cancel();

    await expectLater(
      scanStorageInBackground([
        StorageRoot(label: 'App data', path: p.join(sandbox.path, 'data')),
      ], cancellation: cancellation),
      throwsA(isA<StorageScanCancelled>()),
    );
  });

  test('cancelling a running scan kills its isolate', () async {
    // Enough folders that the walk is still going when it is cancelled.
    for (var i = 0; i < 400; i++) {
      write('data/d$i/e/f/g.bin', 1);
    }
    final cancellation = StorageScanCancellation();
    final result = scanStorageInBackground([
      StorageRoot(label: 'App data', path: p.join(sandbox.path, 'data')),
    ], cancellation: cancellation);
    cancellation.cancel();

    // Either the kill landed (cancelled) or the walk had already finished;
    // it must never hang or fail some other way.
    try {
      final scan = await result.timeout(const Duration(seconds: 20));
      expect(scan.fileCount, 400);
    } on StorageScanCancelled {
      // Expected outcome.
    }
  });

  test('a missing root holds nothing', () {
    final scan = scanStorageRoots([
      StorageRoot(label: 'Gone', path: p.join(sandbox.path, 'missing')),
    ]);

    expect(scan.totalBytes, 0);
    expect(scan.byCategory, isEmpty);
    expect(scan.unreadableFolders, 0);
  });

  test(
    'a linked folder is not followed',
    () {
      write('outside/big.bin', 500);
      write('data/real.bin', 5);
      Link(
        p.join(sandbox.path, 'data', 'lib'),
      ).createSync(p.join(sandbox.path, 'outside'));

      final scan = scanStorageRoots([
        StorageRoot(label: 'App data', path: p.join(sandbox.path, 'data')),
      ]);

      expect(scan.totalBytes, 5);
    },
    skip: Platform.isWindows ? 'links need privileges on Windows' : null,
  );

  group('classifyStoragePath', () {
    StorageCategory classify(String path) => classifyStoragePath(p.split(path));

    test('names its categories from the path', () {
      expect(classify('Recordings/show.ts'), StorageCategory.recordings);
      expect(
        classify('Debrify/Recordings/show.ts'),
        StorageCategory.recordings,
      );
      expect(classify('downloads/movie.mkv'), StorageCategory.downloads);
      expect(
        classify('cache/generated_downloads/1-movie.mkv'),
        StorageCategory.downloads,
      );
      expect(classify('libCachedImageData/a'), StorageCategory.imageCache);
      expect(
        classify('debrifyIptvLogoCache/logo.png'),
        StorageCategory.imageCache,
      );
      expect(classify('shared_preferences.json'), StorageCategory.preferences);
      expect(classify('x/other.sqlite'), StorageCategory.otherDatabases);
      expect(classify('x/readme.txt'), StorageCategory.other);
    });

    test('a guide download wins over the folder it sits in', () {
      expect(
        classify('Recordings/xmltv_9.tmp'),
        StorageCategory.guideDownloads,
      );
    });
  });

  group('profileOwnerOf', () {
    test('reads the profile and generation from the folder names', () {
      expect(profileOwnerOf(p.split('a/profiles/id1/g/3/documents/x.db')), (
        profileId: 'id1',
        generation: 3,
      ));
      expect(profileOwnerOf(p.split('profiles/id1/avatars/a.png')), (
        profileId: 'id1',
        generation: null,
      ));
    });

    test('ignores paths that only look like a profile folder', () {
      expect(profileOwnerOf(p.split('profiles.db')), isNull);
      expect(profileOwnerOf(p.split('profiles/stray.json')), isNull);
      expect(profileOwnerOf(p.split('engines/x.yaml')), isNull);
    });
  });
}
