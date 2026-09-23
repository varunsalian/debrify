import 'dart:io';
import 'dart:async';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_cache_manager/src/cache_store.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class AuditPaths extends PathProviderPlatform {
  AuditPaths(this.root);
  final String root;
  @override
  Future<String?> getTemporaryPath() async => root;
}

class FixtureFileService extends FileService {
  FixtureFileService(this.body);
  final Stream<List<int>> Function() body;
  @override
  Future<FileServiceResponse> get(
    String url, {
    Map<String, String>? headers,
  }) async => HttpGetResponse(
    http.StreamedResponse(body(), 200, headers: {'content-type': 'image/jpeg'}),
  );
}

class DelayedFileService extends FileService {
  final started = Completer<void>();
  final response = Completer<FileServiceResponse>();
  @override
  Future<FileServiceResponse> get(String url, {Map<String, String>? headers}) {
    started.complete();
    return response.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  late Directory root;
  late CacheStore store;
  late CacheObjectProvider repo;
  late PathProviderPlatform previousPaths;
  setUp(() async {
    previousPaths = PathProviderPlatform.instance;
    root = await Directory.systemTemp.createTemp('debrify-cache-audit-');
    PathProviderPlatform.instance = AuditPaths(root.path);
    repo = CacheObjectProvider(path: '${root.path}/index.db');
    store = CacheStore(Config('artwork', repo: repo, maxNrOfCacheObjects: 1));
    store.cleanupRunMinInterval = const Duration(milliseconds: 10);
  });
  tearDown(() async {
    await store.dispose();
    await root.delete(recursive: true);
    PathProviderPlatform.instance = previousPaths;
  });
  Future<File> seed(String name) async {
    final physical = await store.fileSystem.createFile(name);
    await physical.writeAsBytes(List.filled(1024, 1));
    await store.putFile(
      CacheObject(
        'https://example.test/$name',
        relativePath: name,
        validTill: DateTime.now().add(const Duration(days: 1)),
        length: 1024,
      ),
    );
    return File(physical.path);
  }

  for (final status in [304, 200]) {
    test(
      'revalidation $status retains file and row through headers and body',
      () async {
        store.cleanupRunMinInterval = const Duration(days: 1);
        final original = await seed('revalidate.jpg');
        final service = DelayedFileService();
        final cache = CacheManager.custom(
          Config('artwork', repo: repo, fileService: service),
          cacheStore: store,
        );
        // Direct HTTP revalidation has no reader grace to mask eviction.
        final pending = cache.webHelper
            .downloadFile('https://example.test/revalidate.jpg')
            .toList();
        await service.started.future;
        await repo.db!.update('cacheObject', {
          'touched': DateTime.now()
              .subtract(const Duration(days: 40))
              .millisecondsSinceEpoch,
        });
        await store.cleanCache();
        final survivedHeaders = await original.exists();
        final rowSurvivedHeaders = await repo.getAllObjects();
        final bodyStarted = Completer<void>();
        final finishBody = Completer<void>();
        Stream<List<int>> body() async* {
          yield [7];
          bodyStarted.complete();
          await finishBody.future;
          yield [8, 9];
        }

        service.response.complete(
          HttpGetResponse(
            http.StreamedResponse(
              status == 200 ? body() : const Stream.empty(),
              status,
              headers: {'content-type': 'image/jpeg'},
            ),
          ),
        );
        if (status == 200) {
          await bodyStarted.future;
          await store.cleanCache();
          finishBody.complete();
        }
        final result = (await pending).whereType<FileInfo>().single;
        expect(survivedHeaders, isTrue);
        expect(rowSurvivedHeaders, hasLength(1));
        expect(await result.file.exists(), isTrue);
        expect(
          await result.file.readAsBytes(),
          status == 200 ? [7, 8, 9] : List.filled(1024, 1),
        );
        final row = await repo.get('https://example.test/revalidate.jpg');
        expect(row, isNotNull);
        expect(
          (await store.fileSystem.createFile(row!.relativePath)).path,
          result.file.path,
        );
        // Completion releases the lease, including the replacement's identity.
        await store.emptyCache();
        expect(await result.file.exists(), isFalse);
      },
    );
  }

  test('failed revalidation releases eviction protection', () async {
    store.cleanupRunMinInterval = const Duration(days: 1);
    final original = await seed('failed-revalidation.jpg');
    final service = DelayedFileService();
    final cache = CacheManager.custom(
      Config('artwork', repo: repo, fileService: service),
      cacheStore: store,
    );
    final pending = cache.webHelper
        .downloadFile('https://example.test/failed-revalidation.jpg')
        .toList();
    final expectation = expectLater(pending, throwsA(isA<SocketException>()));
    await service.started.future;
    service.response.completeError(const SocketException('fixture timeout'));
    await expectation;
    await store.emptyCache();
    expect(await original.exists(), isFalse);
    expect(await repo.getAllObjects(), isEmpty);
  });

  test(
    'overlapping leases release on cancellation without blocking other eviction',
    () async {
      store.cleanupRunMinInterval = const Duration(days: 1);
      final held = await seed('held.jpg');
      final other = await seed('other.jpg');
      final firstStarted = Completer<void>();
      final secondStarted = Completer<void>();
      final firstBody = StreamController<void>();
      final secondBody = StreamController<void>();
      final first = store
          .withRevalidation<void>('https://example.test/held.jpg', (_) {
            firstStarted.complete();
            return firstBody.stream;
          })
          .listen((_) {});
      final second = store
          .withRevalidation<void>('https://example.test/held.jpg', (_) {
            secondStarted.complete();
            return secondBody.stream;
          })
          .listen((_) {});
      await Future.wait([firstStarted.future, secondStarted.future]);
      await repo.db!.update('cacheObject', {
        'touched': DateTime.now()
            .subtract(const Duration(days: 40))
            .millisecondsSinceEpoch,
      });
      await store.cleanCache();
      expect(await held.exists(), isTrue);
      expect(await other.exists(), isFalse);
      await first.cancel();
      await store.cleanCache();
      expect(await held.exists(), isTrue);
      await second.cancel();
      await store.cleanCache();
      expect(await held.exists(), isFalse);
      await firstBody.close();
      await secondBody.close();
    },
  );

  test('revalidation retains memory-only repository entries', () async {
    final memoryStore = CacheStore(
      Config('memory-only', repo: NonStoringObjectProvider()),
    );
    final file = await memoryStore.fileSystem.createFile('cached.jpg');
    await file.writeAsBytes([1, 2]);
    await memoryStore.putFile(
      CacheObject(
        'https://example.test/memory.jpg',
        relativePath: 'cached.jpg',
        validTill: DateTime.now(),
        eTag: 'cached-etag',
      ),
    );
    try {
      final objects = await memoryStore
          .withRevalidation<CacheObject?>(
            'https://example.test/memory.jpg',
            (object) => Stream.value(object),
          )
          .toList();
      expect(objects.single?.eTag, 'cached-etag');
    } finally {
      await memoryStore.dispose();
    }
  });

  test('emptyCache removes actual cached artwork files', () async {
    final physical = await seed('poster.jpg');
    await store.emptyCache();
    expect(await repo.getAllObjects(), isEmpty);
    expect(
      await physical.exists(),
      isFalse,
      reason: 'An empty metadata index must not leave orphan image bytes',
    );
  });
  test('capacity eviction removes actual cached artwork files', () async {
    await seed('one.jpg');
    await seed('two.jpg');
    await seed('three.jpg');
    await repo.db!.update('cacheObject', {
      'touched': DateTime.now()
          .subtract(const Duration(days: 2))
          .millisecondsSinceEpoch,
    });
    await store.getFile('https://example.test/miss.jpg');
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect((await repo.getAllObjects()).length, 1);
    final files = await Directory('${root.path}/artwork').list().length;
    expect(
      files,
      1,
      reason: 'Only one cached file should survive capacity eviction',
    );
  });
  test(
    'Android cache count limit also constrains recently accessed images',
    () async {
      await seed('one.jpg');
      await seed('two.jpg');
      await seed('three.jpg');
      await store.getFile('https://example.test/miss.jpg');
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(
        (await repo.getAllObjects()).length,
        1,
        reason:
            'The configured one-object capacity should not retain three recent images',
      );
    },
  );

  test(
    'byte budget uses real sizes even when recorded lengths are missing',
    () async {
      await store.dispose();
      repo = CacheObjectProvider(path: '${root.path}/bytes.db');
      store = CacheStore(
        Config(
          'bytes',
          repo: repo,
          maxNrOfCacheObjects: 100,
          maxCacheSizeBytes: 1500,
        ),
      );
      await seed('one.jpg');
      await seed('two.jpg');
      await repo.db!.update('cacheObject', {'length': null});
      await store.cleanCache();
      expect((await repo.getAllObjects()).length, 1);
      expect(await Directory('${root.path}/bytes').list().length, 1);
    },
  );

  test(
    'active writer survives eviction and is eligible after it finishes',
    () async {
      final file = await seed('writing.jpg');
      final written = Completer<void>();
      final active = store.whileWriting('writing.jpg', () => written.future);
      await repo.db!.update('cacheObject', {
        'touched': DateTime.now()
            .subtract(const Duration(days: 40))
            .millisecondsSinceEpoch,
      });
      await store.cleanCache();
      expect(await file.exists(), isTrue);
      expect(await repo.getAllObjects(), hasLength(1));
      written.complete();
      await active;
      await store.cleanCache();
      expect(await file.exists(), isFalse);
      expect(await repo.getAllObjects(), isEmpty);
    },
  );

  test(
    'orphan recovery preserves indexed, recent, unrelated and linked files',
    () async {
      // Finish the automatic startup scan before arranging this scan fixture.
      await store.getFile('initialize');
      final fs = store.fileSystem as IOFileSystem;
      const orphanName = '11111111-1111-1111-1111-111111111111.jpg';
      const indexedName = '22222222-2222-2222-2222-222222222222.jpg';
      const recentName = '33333333-3333-3333-3333-333333333333.jpg';
      const linkName = '44444444-4444-4444-4444-444444444444.jpg';
      final orphan = await fs.createFile(orphanName);
      final indexed = await fs.createFile(indexedName);
      final recent = await fs.createFile(recentName);
      final unrelated = await fs.createFile('keep.txt');
      final old = DateTime.now().subtract(const Duration(days: 2));
      for (final file in [orphan, indexed, unrelated]) {
        await file.writeAsString('cache');
        await file.setLastModified(old);
      }
      await recent.writeAsString('downloading');
      final linkPath = (await fs.createFile(linkName)).path;
      await Link(linkPath).create(unrelated.path);
      await fs.removeOldOrphans({indexedName});
      expect(await orphan.exists(), isFalse);
      for (final file in [indexed, recent, unrelated]) {
        expect(await file.exists(), isTrue);
      }
      expect(await Link(linkPath).exists(), isTrue);
    },
  );

  test(
    'scheduled maintenance runs after writes without another lookup',
    () async {
      await seed('one.jpg');
      await seed('two.jpg');
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(await repo.getAllObjects(), hasLength(1));
      expect(await Directory('${root.path}/artwork').list().length, 1);
    },
  );

  test('dispose cancels pending maintenance', () async {
    await seed('keep.jpg');
    await store.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    // Reopen for the shared teardown, proving no timer touched the closed DB.
    repo = CacheObjectProvider(path: '${root.path}/index.db');
    store = CacheStore(Config('artwork', repo: repo));
    expect(await store.getFile('https://example.test/keep.jpg'), isNotNull);
  });

  test('failed network body removes partial image files', () async {
    Stream<List<int>> body() async* {
      yield [1, 2, 3];
      throw const SocketException('interrupted fixture');
    }

    final cache = CacheManager.custom(
      Config('artwork', repo: repo, fileService: FixtureFileService(body)),
      cacheStore: store,
    );
    await expectLater(
      cache.getSingleFile('https://example.test/broken.jpg'),
      throwsA(isA<SocketException>()),
    );
    expect(await Directory('${root.path}/artwork').list().length, 0);
    expect(await repo.getAllObjects(), isEmpty);
  });

  test('network success commits a usable file before returning it', () async {
    final cache = CacheManager.custom(
      Config(
        'artwork',
        repo: repo,
        fileService: FixtureFileService(() => Stream.value([1, 2, 3])),
      ),
      cacheStore: store,
    );
    final result = await cache.getSingleFile(
      'https://example.test/success.jpg',
    );
    expect(await result.readAsBytes(), [1, 2, 3]);
    expect(await repo.getAllObjects(), hasLength(1));
    await cache.removeFile('https://example.test/success.jpg');
    expect(await result.exists(), isFalse);
  });

  test('putFile commits bytes and index; disposal cancels its timer', () async {
    final cache = CacheManager.custom(
      Config('artwork', repo: repo),
      cacheStore: store,
    );
    final result = await cache.putFile(
      'https://example.test/put.jpg',
      Uint8List.fromList([4, 5]),
    );
    expect(await result.readAsBytes(), [4, 5]);
    expect(await repo.getAllObjects(), hasLength(1));
    await cache.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    repo = CacheObjectProvider(path: '${root.path}/index.db');
    store = CacheStore(Config('artwork', repo: repo));
  });

  test(
    'automatic eviction preserves decoder handoff; explicit clear still works',
    () async {
      final file = await seed('decoding.jpg');
      await store.getFile('https://example.test/decoding.jpg');
      await repo.db!.update('cacheObject', {
        'touched': DateTime.now()
            .subtract(const Duration(days: 40))
            .millisecondsSinceEpoch,
      });
      await store.cleanCache();
      expect(await file.exists(), isTrue);
      await store.emptyCache();
      expect(await file.exists(), isFalse);
    },
  );
}
