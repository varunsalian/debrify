import 'dart:io' as io;
import 'dart:async';

import 'package:clock/clock.dart';
import 'package:file/file.dart' show File;
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_cache_manager/src/cache_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late io.Directory temp;
  late Config config;
  late CacheStore store;
  var now = DateTime.now();

  setUp(() async {
    now = DateTime.now();
    temp = await io.Directory.systemTemp.createTemp('cache-budget-test-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (_) async => temp.path);
    config = Config('artwork',
        maxCacheBytes: 100,
        maxNrOfCacheObjects: 10,
        repo: JsonCacheInfoRepository.withFile(
            io.File('${temp.path}/metadata.json')));
    store = CacheStore(config);
    store.cleanupRunMinInterval = const Duration(days: 1);
    await store.getCacheSize(); // Wait for the repository to open.
  });

  tearDown(() async {
    await store.dispose();
    await temp.delete(recursive: true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'), null);
  });

  Future<CacheObject> seed(String key, int bytes, int ageMinutes,
      {bool unknownLength = false}) async {
    final file = await config.fileSystem.createFile('$key.jpg');
    await file.writeAsBytes(List.filled(bytes, 1));
    return config.repo.insert(
        CacheObject('https://example.test/$key',
            key: key,
            relativePath: '$key.jpg',
            length: unknownLength ? null : bytes,
            touched: now.subtract(Duration(minutes: ageMinutes)),
            validTill: now.add(const Duration(days: 1))),
        setTouchedToNow: false);
  }

  Future<bool> exists(String key) async =>
      (await config.fileSystem.createFile('$key.jpg')).exists();

  test('eviction deletes the real cache file and metadata', () async {
    final object = await seed('old', 40, 120);
    await store.removeCachedFile(object);
    expect(await exists('old'), isFalse);
    expect(await config.repo.get('old'), isNull);
  });

  test('byte budget evicts oldest first and trims below the high-water mark',
      () async {
    await seed('old', 40, 120);
    await seed('middle', 40, 90);
    await seed('new', 40, 60);
    await store.cleanup();
    expect(await exists('old'), isFalse);
    expect(await exists('middle'), isTrue);
    expect(await exists('new'), isTrue);
    expect(await store.getCacheSize(), 80);
  });

  test('under-budget cache stays warm', () async {
    await seed('one', 45, 120);
    await seed('two', 45, 90);
    await store.cleanup();
    expect(await exists('one'), isTrue);
    expect(await exists('two'), isTrue);
  });

  test('memory hits update LRU and protect images being decoded', () async {
    await seed('old-but-used', 60, 120);
    await seed('unused', 60, 60);
    await withClock(Clock(() => now), () => store.getFile('old-but-used'));
    now = now.add(const Duration(minutes: 2));
    await withClock(
        Clock(() => now), () => store.getFileFromMemory('old-but-used'));
    await withClock(Clock(() => now), store.cleanup);
    expect(await exists('old-but-used'), isTrue);
    expect(await exists('unused'), isFalse);
  });

  test('oversized recent file is deferred then evicted when idle', () async {
    await seed('large', 150, 0);
    await withClock(Clock(() => now), store.cleanup);
    expect(await exists('large'), isTrue);
    now = now.add(const Duration(minutes: 2));
    await withClock(Clock(() => now), store.cleanup);
    expect(await exists('large'), isFalse);
  });

  test('in-flight refresh remains protected beyond the recent-use grace',
      () async {
    await seed('refresh', 150, 120);
    withClock(Clock(() => now), () => store.beginFileOperation('refresh'));
    now = now.add(const Duration(minutes: 5));
    await withClock(Clock(() => now), store.cleanup);
    expect(await exists('refresh'), isTrue);
    withClock(Clock(() => now), () => store.endFileOperation('refresh'));
    now = now.add(const Duration(minutes: 2));
    await withClock(Clock(() => now), store.cleanup);
    expect(await exists('refresh'), isFalse);
  });

  test('legacy entries without byte lengths count toward the budget', () async {
    await seed('old', 70, 120, unknownLength: true);
    await seed('new', 50, 60, unknownLength: true);
    await store.cleanup();
    expect(await exists('old'), isFalse);
    expect(await exists('new'), isTrue);
  });

  test(
      'restart repairs old orphans without touching referenced or recent files',
      () async {
    await seed('keep', 40, 120);
    final old = await config.fileSystem.createFile('orphan.jpg');
    await old.writeAsBytes(List.filled(200, 1));
    await old.setLastModified(now.subtract(const Duration(days: 2)));
    final recent = await config.fileSystem.createFile('downloading.jpg');
    await recent.writeAsBytes([1, 2, 3]);
    final outside = io.File('${temp.path}/outside.jpg');
    await outside.writeAsBytes([1]);
    await outside.setLastModified(now.subtract(const Duration(days: 2)));
    await store.cleanup();
    expect(await old.exists(), isFalse);
    expect(await recent.exists(), isTrue);
    expect(await outside.exists(), isTrue);
    expect(await exists('keep'), isTrue);
  });

  test('OS-purged files do not break maintenance or subsequent cache lookup',
      () async {
    await seed('missing', 150, 120);
    await (await config.fileSystem.createFile('missing.jpg')).delete();
    await store.cleanup();
    expect(await store.getFile('missing'), isNull);
  });

  test('concurrent cleanup calls share one pass', () async {
    await seed('large', 150, 120);
    final first = store.cleanup();
    final second = store.cleanup();
    expect(identical(first, second), isTrue);
    await Future.wait([first, second]);
    expect(await exists('large'), isFalse);
  });

  test('direct writes and streamed writes record actual byte lengths',
      () async {
    final manager = CacheManager.custom(config, cacheStore: store);
    await manager.putFile('https://example.test/direct', Uint8List(25),
        key: 'direct');
    await manager.putFileStream(
        'https://example.test/stream', Stream.value(List.filled(35, 1)),
        key: 'stream');
    expect((await config.repo.get('direct'))!.length, 25);
    expect((await config.repo.get('stream'))!.length, 35);
  });

  test('slow direct stream writes cannot be evicted mid-write', () async {
    await seed('slow', 150, 120);
    final manager = CacheManager.custom(config, cacheStore: store);
    final started = Completer<void>();
    final release = Completer<void>();
    Stream<List<int>> bytes() async* {
      yield [1, 2];
      started.complete();
      await release.future;
      yield [3, 4];
    }

    final write = withClock(
        Clock(() => now),
        () => manager.putFileStream('https://example.test/slow', bytes(),
            key: 'slow'));
    await started.future;
    now = now.add(const Duration(minutes: 5));
    await withClock(Clock(() => now), store.cleanup);
    expect(await exists('slow'), isTrue);
    release.complete();
    final file = await write;
    expect(await file.readAsBytes(), [1, 2, 3, 4]);
    expect((await config.repo.get('slow'))!.length, 4);
  });

  test('count and stale limits still reclaim real files below byte budget',
      () async {
    for (var i = 0; i < 11; i++) {
      await seed('image-$i', 1, 120 - i);
    }
    await seed('stale', 1, 60 * 24 * 31);
    await store.cleanup();
    expect(await exists('stale'), isFalse);
    expect(await exists('image-0'), isFalse);
    expect((await config.repo.getAllObjects()).length, 10);
  });

  test('later maintenance reclaims orphans that were initially too recent',
      () async {
    final orphan = await config.fileSystem.createFile('interrupted.jpg');
    await orphan.writeAsBytes([1]);
    await withClock(Clock(() => now), store.cleanup);
    expect(await orphan.exists(), isTrue);
    await orphan
        .setLastModified(DateTime.now().subtract(const Duration(days: 2)));
    now = now.add(const Duration(days: 2));
    await withClock(Clock(() => now), store.cleanup);
    expect(await orphan.exists(), isFalse);
  });
  test('missing newer files must not evict healthy older artwork', () async {
    await seed('healthy', 60, 120);
    await seed('already-purged', 150, 60);
    await (await config.fileSystem.createFile('already-purged.jpg')).delete();
    await store.cleanup();
    expect(await exists('healthy'), isTrue,
        reason: 'Only 60 bytes exist on disk, below the 100-byte budget');
  });

  test('orphan repair failure must not disable byte eviction', () async {
    await seed('old', 150, 120);
    final fs = _FailingOrphanFileSystem('artwork');
    store.fileSystem = fs;
    await store.cleanup();
    expect(await exists('old'), isFalse,
        reason:
            'A failed orphan sweep should not prevent regular byte eviction');
    await seed('another', 150, 120);
    await store.cleanup();
    expect(await exists('another'), isFalse);
    expect(fs.sweeps, 1, reason: 'Failed orphan sweeps are throttled');
  });

  test('under-budget cleanup avoids inventory scans and clears ghost metadata',
      () async {
    final fs = _CountingFileSystem('artwork');
    store.fileSystem = fs;
    await seed('healthy', 90, 120);
    await store.cleanup();
    expect(fs.inventories, 0);
    await seed('missing', 50, 60);
    await (await config.fileSystem.createFile('missing.jpg')).delete();
    await store.cleanup();
    expect(fs.inventories, 1);
    expect(await exists('healthy'), isTrue);
    expect(await config.repo.get('missing'), isNull);
    await store.cleanup();
    expect(fs.inventories, 1);
  });

  test('an inaccessible eviction candidate does not block other deletions',
      () async {
    await seed('locked', 80, 120);
    await seed('evictable', 80, 60);
    store.fileSystem = _LockedFileSystem('artwork');
    await store.cleanup();
    expect(await exists('locked'), isTrue);
    expect(await exists('evictable'), isFalse);
    expect(await config.repo.get('locked'), isNotNull);
  });

  test('unreadable legacy size does not block eviction and is retried',
      () async {
    await seed('locked', 150, 120, unknownLength: true);
    await seed('evictable', 150, 60);
    store.fileSystem = _LockedFileSystem('artwork');
    await store.cleanup();
    expect(await exists('evictable'), isFalse);
    expect(await exists('locked'), isTrue);
    expect((await config.repo.get('locked'))!.length, isNull);
    store.fileSystem = config.fileSystem;
    await store.cleanup();
    expect(await exists('locked'), isFalse);
  });

  test('failed directory inventory falls back to individual file checks',
      () async {
    await seed('healthy', 60, 120);
    await seed('missing', 150, 60);
    await (await config.fileSystem.createFile('missing.jpg')).delete();
    store.fileSystem = _FailedInventoryFileSystem('artwork');
    await store.cleanup();
    expect(await exists('healthy'), isTrue);
    expect(await config.repo.get('missing'), isNull);
    await seed('oversized', 150, 180);
    await store.cleanup();
    expect(await exists('oversized'), isFalse);
    expect(await exists('healthy'), isTrue);
  });

  test('failed fallback file check preserves metadata and continues eviction',
      () async {
    await seed('locked', 150, 120);
    await seed('evictable', 150, 60);
    store.fileSystem = _FailedInventoryAndFileSystem('artwork');
    await store.cleanup();
    expect(await exists('evictable'), isFalse);
    expect(await exists('locked'), isTrue);
    expect(await config.repo.get('locked'), isNotNull);
    store.fileSystem = config.fileSystem;
    await store.cleanup();
    expect(await exists('locked'), isFalse);
  });

  for (final failRemoval in [true, false]) {
    for (final memoryOnly in [true, false]) {
      test(
          'waiting ${memoryOnly ? "memory" : "disk"} read rechecks after '
          '${failRemoval ? "failed" : "successful"} eviction', () async {
        await seed('old', 150, 120);
        expect(await store.getFile('old'), isNotNull);
        now = now.add(const Duration(minutes: 2));
        final fs = _PausedRemovalFileSystem('artwork', fail: failRemoval);
        store.fileSystem = fs;
        final cleanup = withClock(Clock(() => now), store.cleanup);
        await fs.removing.future;
        final read =
            memoryOnly ? store.getFileFromMemory('old') : store.getFile('old');
        // Eviction invalidates the memory entry. A memory-only lookup may
        // return a miss; a disk lookup must recover the surviving image.
        final check = expectLater(
            read, completion(failRemoval && !memoryOnly ? isNotNull : isNull));
        fs.release.complete();
        await cleanup;
        await check;
        expect(await exists('old'), failRemoval);
      });
    }
  }

  test('a cache hit during directory inventory remains protected', () async {
    await seed('used', 60, 120);
    await seed('unused', 60, 60);
    final fs = _PausedInventoryFileSystem('artwork');
    store.fileSystem = fs;
    final cleanup = store.cleanup();
    await fs.listing.future;
    expect(await store.getFile('used'), isNotNull);
    fs.release.complete();
    await cleanup;
    expect(await exists('used'), isTrue);
    expect(await exists('unused'), isFalse);
  });
}

class _FailingOrphanFileSystem extends IOFileSystem {
  _FailingOrphanFileSystem(super.cacheKey);
  int sweeps = 0;

  @override
  Future<void> removeOrphanedFiles(Set<String> referencedPaths) async {
    sweeps++;
    throw const io.FileSystemException('Access denied during orphan cleanup');
  }
}

class _CountingFileSystem extends IOFileSystem {
  _CountingFileSystem(super.cacheKey);
  int inventories = 0;

  @override
  Future<Set<String>> cachedFilePaths() {
    inventories++;
    return super.cachedFilePaths();
  }
}

class _LockedFileSystem extends IOFileSystem {
  _LockedFileSystem(super.cacheKey);

  @override
  Future<File> createFile(String name) async {
    if (name == 'locked.jpg') {
      throw const io.FileSystemException('Access denied');
    }
    return super.createFile(name);
  }
}

class _FailedInventoryFileSystem extends IOFileSystem {
  _FailedInventoryFileSystem(super.cacheKey);

  @override
  Future<Set<String>> cachedFilePaths() async {
    throw const io.FileSystemException('Directory enumeration failed');
  }
}

class _FailedInventoryAndFileSystem extends _FailedInventoryFileSystem {
  _FailedInventoryAndFileSystem(super.cacheKey);

  @override
  Future<File> createFile(String name) async {
    if (name == 'locked.jpg') {
      throw const io.FileSystemException('Access denied');
    }
    return super.createFile(name);
  }
}

class _PausedRemovalFileSystem extends IOFileSystem {
  _PausedRemovalFileSystem(super.cacheKey, {required this.fail});
  final bool fail;
  final removing = Completer<void>();
  final release = Completer<void>();
  bool pauseOnce = true;

  @override
  Future<File> createFile(String name) async {
    if (pauseOnce && name == 'old.jpg') {
      pauseOnce = false;
      removing.complete();
      await release.future;
      if (fail) {
        throw const io.FileSystemException('Cannot delete cache file');
      }
    }
    return super.createFile(name);
  }
}

class _PausedInventoryFileSystem extends IOFileSystem {
  _PausedInventoryFileSystem(super.cacheKey);
  final listing = Completer<void>();
  final release = Completer<void>();

  @override
  Future<Set<String>> cachedFilePaths() async {
    final paths = await super.cachedFilePaths();
    listing.complete();
    await release.future;
    return paths;
  }
}
