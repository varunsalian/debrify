import 'dart:async';
import 'dart:io';

import 'package:flutter_cache_manager/flutter_cache_manager.dart';

///Flutter Cache Manager
///Copyright (c) 2019 Rene Floor
///Released under MIT License.

class CacheStore {
  Duration cleanupRunMinInterval = const Duration(seconds: 10);

  final _futureCache = <String, Future<CacheObject?>>{};
  final _memCache = <String, CacheObject>{};

  FileSystem fileSystem;

  final Config _config;

  String get storeKey => _config.cacheKey;
  final Future<CacheInfoRepository> _cacheInfoRepository;

  int get _capacity => _config.maxNrOfCacheObjects;

  Duration get _maxAge => _config.stalePeriod;

  DateTime lastCleanupRun = DateTime.now();
  Timer? _scheduledCleanup;
  Future<void> _mutations = Future.value();
  bool _disposed = false;
  final _activeWrites = <String, int>{};
  final _activeRevalidations = <String, int>{};
  final _recentReads = <String, DateTime>{};

  /// Image decoders consume returned files asynchronously. Give them a short
  /// handoff window before background budget maintenance may evict the file.
  void protectFile(String relativePath) {
    _recentReads[relativePath] = DateTime.now();
  }

  Future<T> whileWriting<T>(String path, Future<T> Function() action) async {
    _activeWrites.update(path, (count) => count + 1, ifAbsent: () => 1);
    try {
      return await action();
    } finally {
      final remaining = _activeWrites[path]! - 1;
      if (remaining == 0) {
        _activeWrites.remove(path);
      } else {
        _activeWrites[path] = remaining;
      }
      _scheduleCleanup();
    }
  }

  /// Acquire the current entry and its eviction lease atomically. Protect the
  /// key (not only its old path) through HTTP headers, body and index commit.
  /// No mutation lock is held while waiting for the network.
  Stream<T> withRevalidation<T>(
      String key, Stream<T> Function(CacheObject? object) action) async* {
    final object = await _exclusive(() async {
      final provider = await _cacheInfoRepository;
      var current = await provider.get(key);
      // Non-persistent repositories (notably web) keep their only copy here.
      // Never revive a deleted persistent row from a stale in-memory ID.
      if (current == null && _memCache[key]?.id == null) {
        current = _memCache[key];
      }
      if (current != null && !await _fileExists(current)) {
        if (current.id != null) await provider.delete(current.id!);
        _memCache.remove(key);
        current = null;
      }
      if (current != null) {
        await provider.updateOrInsert(current);
        _memCache[key] = current;
      }
      _activeRevalidations.update(key, (count) => count + 1, ifAbsent: () => 1);
      return current;
    });
    try {
      yield* action(object);
    } finally {
      final remaining = _activeRevalidations[key]! - 1;
      if (remaining == 0) {
        _activeRevalidations.remove(key);
      } else {
        _activeRevalidations[key] = remaining;
      }
      _scheduleCleanup();
    }
  }

  // Serialize index/file eviction with completed writes. A cleanup snapshot
  // must not remove the index of a replacement committed under the same key.
  Future<T> _exclusive<T>(Future<T> Function() action) {
    final result = _mutations.then((_) => action());
    _mutations =
        result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  CacheStore(Config config)
      : _config = config,
        fileSystem = config.fileSystem,
        _cacheInfoRepository = _openRepository(config);

  static Future<CacheInfoRepository> _openRepository(Config config) async {
    await config.repo.open();
    if (config.fileSystem is IOFileSystem) {
      try {
        final objects = await config.repo.getAllObjects();
        await (config.fileSystem as IOFileSystem).removeOldOrphans(
          objects.map((object) => object.relativePath).toSet(),
        );
      } on FileSystemException {
        // Cache recovery is best effort; an unavailable disk must not prevent
        // normal repository access or future maintenance attempts.
      }
    }
    return config.repo;
  }

  Future<FileInfo?> getFile(String key, {bool ignoreMemCache = false}) async {
    final cacheObject =
        await retrieveCacheData(key, ignoreMemCache: ignoreMemCache);
    if (cacheObject == null) {
      return null;
    }
    protectFile(cacheObject.relativePath);
    final file = await fileSystem.createFile(cacheObject.relativePath);
    cacheLogger.log(
        'CacheManager: Loaded $key from cache', CacheManagerLogLevel.verbose);

    return FileInfo(
      file,
      FileSource.Cache,
      cacheObject.validTill,
      cacheObject.url,
    );
  }

  Future<void> putFile(CacheObject cacheObject) => _exclusive(() async {
        _memCache[cacheObject.key] = cacheObject;
        final dynamic out = await _updateCacheDataInDatabase(cacheObject);

        // We update the cache object with the id if returned by the repository
        if (out is CacheObject && out.id != null) {
          _memCache[cacheObject.key] = cacheObject.copyWith(id: out.id);
        }
        _scheduleCleanup();
      });

  Future<CacheObject?> retrieveCacheData(String key,
      {bool ignoreMemCache = false}) async {
    if (!ignoreMemCache && _memCache.containsKey(key)) {
      if (await _fileExists(_memCache[key])) {
        return _memCache[key];
      }
    }
    if (!_futureCache.containsKey(key)) {
      final completer = Completer<CacheObject?>();
      _getCacheDataFromDatabase(key).then((cacheObject) async {
        if (cacheObject?.id != null && !await _fileExists(cacheObject)) {
          final provider = await _cacheInfoRepository;
          await provider.delete(cacheObject!.id!);
          cacheObject = null;
        }

        if (cacheObject == null) {
          _memCache.remove(key);
        } else {
          _memCache[key] = cacheObject;
        }
        completer.complete(cacheObject);
        _futureCache.remove(key);
      });
      _futureCache[key] = completer.future;
    }
    return _futureCache[key];
  }

  Future<FileInfo?> getFileFromMemory(String key) async {
    final cacheObject = _memCache[key];
    if (cacheObject == null) {
      return null;
    }
    protectFile(cacheObject.relativePath);
    final file = await fileSystem.createFile(cacheObject.relativePath);
    return FileInfo(
        file, FileSource.Cache, cacheObject.validTill, cacheObject.url);
  }

  Future<bool> _fileExists(CacheObject? cacheObject) async {
    if (cacheObject == null) {
      return false;
    }
    final file = await fileSystem.createFile(cacheObject.relativePath);
    return file.exists();
  }

  Future<CacheObject?> _getCacheDataFromDatabase(String key) async {
    final provider = await _cacheInfoRepository;
    final data = await provider.get(key);
    if (await _fileExists(data)) {
      // Touch only an existing record. An asynchronous upsert here can
      // resurrect a record removed by maintenance while the lookup ran.
      await _exclusive(() async {
        final current = await provider.get(key);
        if (current != null) await provider.updateOrInsert(current);
      });
    }
    _scheduleCleanup();
    return data;
  }

  void _scheduleCleanup() {
    if (_disposed || _scheduledCleanup != null) {
      return;
    }
    _scheduledCleanup = Timer(cleanupRunMinInterval, () {
      _scheduledCleanup = null;
      cleanCache().catchError((Object error) {
        cacheLogger.log(
            'Cache maintenance failed: $error', CacheManagerLogLevel.warning);
      });
    });
  }

  Future<dynamic> _updateCacheDataInDatabase(CacheObject cacheObject) async {
    final provider = await _cacheInfoRepository;
    return provider.updateOrInsert(cacheObject);
  }

  /// Enforce both count and byte targets, including files touched today.
  Future<void> cleanCache() => _exclusive(() async {
        final toRemove = <int>[];
        final provider = await _cacheInfoRepository;
        final objects = await provider.getAllObjects();
        objects.sort((a, b) => (b.touched ?? DateTime(1970))
            .compareTo(a.touched ?? DateTime(1970)));
        final cutoff = DateTime.now().subtract(_maxAge);
        _recentReads.removeWhere((_, time) =>
            DateTime.now().difference(time) >= const Duration(seconds: 30));
        var count = 0;
        var bytes = 0;
        for (final object in objects) {
          final file = await fileSystem.createFile(object.relativePath);
          final length = await file.exists() ? await file.length() : 0;
          if ((object.touched ?? DateTime(1970)).isBefore(cutoff) ||
              count >= _capacity ||
              bytes + length > _config.maxCacheSizeBytes) {
            await _removeCachedFile(object, toRemove, protectReaders: true);
          } else {
            count++;
            bytes += length;
          }
        }
        await provider.deleteAll(toRemove);
      });

  Future<void> emptyCache() => _exclusive(() async {
        final provider = await _cacheInfoRepository;
        final toRemove = <int>[];
        final allObjects = await provider.getAllObjects();
        var futures = <Future>[];
        for (final cacheObject in allObjects) {
          futures.add(_removeCachedFile(cacheObject, toRemove));
        }
        await Future.wait(futures);
        await provider.deleteAll(toRemove);
      });

  void emptyMemoryCache() {
    _memCache.clear();
  }

  Future<void> removeCachedFile(CacheObject cacheObject) =>
      _exclusive(() async {
        final provider = await _cacheInfoRepository;
        final toRemove = <int>[];
        await _removeCachedFile(cacheObject, toRemove);
        await provider.deleteAll(toRemove);
      });

  Future<void> _removeCachedFile(CacheObject cacheObject, List<int> toRemove,
      {bool protectReaders = false}) async {
    if (toRemove.contains(cacheObject.id)) return;
    if (_activeRevalidations.containsKey(cacheObject.key)) return;
    if (_activeWrites.containsKey(cacheObject.relativePath)) return;

    final file = await fileSystem.createFile(cacheObject.relativePath);
    if (_activeRevalidations.containsKey(cacheObject.key)) return;
    if (_activeWrites.containsKey(cacheObject.relativePath)) return;
    if (protectReaders && _recentReads.containsKey(cacheObject.relativePath)) {
      _scheduleCleanup();
      return;
    }
    if (_memCache.containsKey(cacheObject.key)) {
      _memCache.remove(cacheObject.key);
    }
    if (_futureCache.containsKey(cacheObject.key)) {
      _futureCache.remove(cacheObject.key);
    }

    if (file.existsSync()) {
      try {
        await file.delete();
        // ignore: unused_catch_clause
      } on PathNotFoundException catch (e) {
        // File has already been deleted. Do nothing #184
      }
    }
    // Keep the record if deletion failed, so a later cleanup can retry.
    if (cacheObject.id != null) toRemove.add(cacheObject.id!);
    _recentReads.remove(cacheObject.relativePath);
  }

  bool memoryCacheContainsKey(String key) {
    return _memCache.containsKey(key);
  }

  Future<void> dispose() async {
    _disposed = true;
    _scheduledCleanup?.cancel();
    await _mutations;
    final provider = await _cacheInfoRepository;
    await provider.close();
  }

  Future<int> getCacheSize() async {
    final provider = await _cacheInfoRepository;
    final allObjects = await provider.getAllObjects();
    int total = 0;
    for (var cacheObject in allObjects) {
      total += cacheObject.length ?? 0;
    }
    return total;
  }
}
