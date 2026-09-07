import 'dart:async';
import 'dart:io';

import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:clock/clock.dart';

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
  Future<void>? _cleanup;
  bool _disposed = false;
  DateTime? _lastOrphanSweep;
  final _lastAccess = <String, DateTime>{};
  final _busy = <String, int>{};
  final _removals = <String, Future<void>>{};
  final _legacyLengths = <String, int>{};

  void beginFileOperation(String key) {
    _busy[key] = (_busy[key] ?? 0) + 1;
    _lastAccess[key] = clock.now();
  }

  void endFileOperation(String key) {
    final remaining = (_busy[key] ?? 1) - 1;
    if (remaining == 0) {
      _busy.remove(key);
    } else {
      _busy[key] = remaining;
    }
    _lastAccess[key] = clock.now();
    _scheduleCleanup();
  }

  /// Schedule maintenance without blocking the caller or first frame.
  void scheduleCleanup() => _scheduleCleanup();

  CacheStore(Config config)
      : _config = config,
        fileSystem = config.fileSystem,
        _cacheInfoRepository = config.repo.open().then((value) => config.repo);

  Future<FileInfo?> getFile(String key, {bool ignoreMemCache = false}) async {
    final cacheObject =
        await retrieveCacheData(key, ignoreMemCache: ignoreMemCache);
    if (cacheObject == null) {
      return null;
    }
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

  Future<void> putFile(CacheObject cacheObject) async {
    _lastAccess[cacheObject.key] = clock.now();
    _memCache[cacheObject.key] = cacheObject;
    final dynamic out = await _updateCacheDataInDatabase(cacheObject);

    _scheduleCleanup();

    // We update the cache object with the id if returned by the repository
    if (out is CacheObject && out.id != null) {
      _memCache[cacheObject.key] = cacheObject.copyWith(id: out.id);
    }
  }

  Future<void> _waitForRemoval(String key) async {
    try {
      await _removals[key];
    } on FileSystemException {
      // A failed eviction does not prove that the file is unreadable. Let
      // readers recheck their own cache source after the removal has settled.
      // Errors from the actual read are still propagated normally.
    }
  }

  Future<CacheObject?> retrieveCacheData(String key,
      {bool ignoreMemCache = false}) async {
    await _waitForRemoval(key);
    _lastAccess[key] = clock.now();
    _scheduleCleanup();
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
    await _waitForRemoval(key);
    _lastAccess[key] = clock.now();
    final cacheObject = _memCache[key];
    if (cacheObject == null) {
      return null;
    }
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
      _updateCacheDataInDatabase(data!);
    }
    _scheduleCleanup();
    return data;
  }

  void _scheduleCleanup({Duration? delay}) {
    if (_disposed || _scheduledCleanup != null) {
      return;
    }
    _scheduledCleanup = Timer(delay ?? cleanupRunMinInterval, () {
      _scheduledCleanup = null;
      unawaited(cleanup().catchError((Object error) {
        cacheLogger.log('Cache maintenance failed (${error.runtimeType})',
            CacheManagerLogLevel.warning);
      }));
    });
  }

  Future<dynamic> _updateCacheDataInDatabase(CacheObject cacheObject) async {
    final provider = await _cacheInfoRepository;
    return provider.updateOrInsert(cacheObject);
  }

  /// Single-flight maintenance. Public so disk behavior can be tested directly.
  Future<void> cleanup() {
    if (_disposed) return Future.value();
    return _cleanup ??= _cleanupCache().whenComplete(() => _cleanup = null);
  }

  Future<void> _cleanupCache() async {
    final provider = await _cacheInfoRepository;
    final all = await provider.getAllObjects();
    final fs = fileSystem;
    if (fs is IOFileSystem &&
        (_lastOrphanSweep == null ||
            clock.now().difference(_lastOrphanSweep!) >=
                const Duration(days: 1))) {
      try {
        await fs.removeOrphanedFiles(all.map((e) => e.relativePath).toSet());
      } on FileSystemException catch (error) {
        // Directory enumeration can fail too. Orphan repair is best effort;
        // it must not disable the regular count/age/byte policy below.
        cacheLogger.log('Orphan sweep failed (${error.runtimeType})',
            CacheManagerLogLevel.warning);
      }
      // Throttle failed sweeps as well, instead of retrying every ten seconds.
      _lastOrphanSweep = clock.now();
    }

    if (_config.maxCacheBytes == null) {
      // Preserve the repository's existing age/count policy for other clients.
      final toRemove = <int>[];
      for (final object in await provider.getObjectsOverCapacity(_capacity)) {
        await _removeCachedFile(object, toRemove);
      }
      for (final object in await provider.getOldObjects(_maxAge)) {
        await _removeCachedFile(object, toRemove);
      }
      await provider.deleteAll(toRemove);
      _lastAccess.clear();
      return;
    }

    // Online downloads already record their actual byte count. Backfill only
    // legacy/direct writes without a length; do not stat every image each pass.
    var totalBytes = 0;
    final sizes = <String, int>{};
    final inaccessible = <String>{};
    for (final object in all) {
      var length = object.length ?? _legacyLengths[object.relativePath];
      if (length == null && _config.maxCacheBytes != null) {
        try {
          final file = await fileSystem.createFile(object.relativePath);
          length = await file.length();
          _legacyLengths[object.relativePath] = length;
        } on PathNotFoundException {
          length = 0;
        } on FileSystemException catch (error) {
          // Unknown bytes are not zero-byte files. Retain this entry and retry
          // later, while applying the budget to the files we can account for.
          inaccessible.add(object.key);
          length = 0;
          cacheLogger.log('Cache size lookup failed (${error.runtimeType})',
              CacheManagerLogLevel.warning);
        }
      }
      sizes[object.key] = length ?? 0;
      totalBytes += length ?? 0;
    }
    DateTime touched(CacheObject object) =>
        _lastAccess[object.key] ?? object.touched ?? DateTime(1970);
    final maxBytes = _config.maxCacheBytes!;
    final staleBefore = clock.now().subtract(_maxAge);
    final recentBefore = clock.now().subtract(const Duration(minutes: 1));
    final missing = <String>{};
    if (totalBytes > maxBytes ||
        all.length > _capacity ||
        all.any((object) => touched(object).isBefore(staleBefore))) {
      // Metadata survives OS cache purges. Reconcile only when a deletion
      // would otherwise occur, so warm, under-budget reads do no extra I/O.
      // A native directory listing avoids one stat call per recorded image.
      Set<String>? paths;
      if (fs is IOFileSystem) {
        try {
          paths = await fs.cachedFilePaths();
        } on FileSystemException catch (error) {
          // A directory may not be enumerable while known files remain
          // accessible. Fall back to per-file checks for this pass.
          cacheLogger.log('Cache inventory failed (${error.runtimeType})',
              CacheManagerLogLevel.warning);
        }
      }
      for (final object in all) {
        if (inaccessible.contains(object.key)) continue;
        bool exists;
        try {
          exists = paths != null
              ? paths.contains(object.relativePath)
              : await (await fs.createFile(object.relativePath)).exists();
        } on FileSystemException catch (error) {
          // An unreadable entry is not proven missing. Preserve its metadata
          // and exclude its unverified bytes from this pass's eviction target.
          inaccessible.add(object.key);
          totalBytes -= sizes[object.key] ?? 0;
          sizes[object.key] = 0;
          cacheLogger.log('Cache existence check failed (${error.runtimeType})',
              CacheManagerLogLevel.warning);
          continue;
        }
        if (!exists) {
          missing.add(object.key);
          totalBytes -= sizes[object.key] ?? 0;
          sizes[object.key] = 0;
        }
      }
    }
    all.sort((a, b) => touched(a).compareTo(touched(b)));
    final trimBytes = totalBytes > maxBytes ? (maxBytes * .9).floor() : null;
    var count = all.length - missing.length - inaccessible.length;
    var deferred = inaccessible.isNotEmpty;
    for (final object in all) {
      if (_disposed) return;
      if (inaccessible.contains(object.key)) continue;
      if (!missing.contains(object.key) &&
          count <= _capacity &&
          !touched(object).isBefore(staleBefore) &&
          (trimBytes == null || totalBytes <= trimBytes)) {
        continue;
      }
      if (_busy.containsKey(object.key) ||
          !touched(object).isBefore(recentBefore)) {
        deferred = true;
        continue;
      }
      // A refresh may have replaced this snapshot while we were awaiting I/O.
      final current = _memCache[object.key];
      if (current != null && current.relativePath != object.relativePath) {
        deferred = true;
        continue;
      }
      try {
        await removeCachedFile(object);
      } on FileSystemException catch (error) {
        cacheLogger.log('Cache file removal failed (${error.runtimeType})',
            CacheManagerLogLevel.warning);
        deferred = true;
        continue;
      }
      totalBytes -= sizes[object.key] ?? 0;
      if (!missing.contains(object.key)) count--;
      // Yield between deletions on slow TV flash.
      await Future<void>.delayed(Duration.zero);
    }
    final keys = all.map((e) => e.key).toSet();
    _lastAccess.removeWhere(
        (key, value) => !keys.contains(key) && !_busy.containsKey(key));
    final paths = all.map((e) => e.relativePath).toSet();
    _legacyLengths.removeWhere((path, _) => !paths.contains(path));
    if (deferred) _scheduleCleanup(delay: const Duration(minutes: 1));
  }

  Future<void> emptyCache() async {
    final provider = await _cacheInfoRepository;
    final toRemove = <int>[];
    final allObjects = await provider.getAllObjects();
    var futures = <Future>[];
    for (final cacheObject in allObjects) {
      futures.add(_removeCachedFile(cacheObject, toRemove));
    }
    await Future.wait(futures);
    await provider.deleteAll(toRemove);
  }

  void emptyMemoryCache() {
    _memCache.clear();
  }

  Future<void> removeCachedFile(CacheObject cacheObject) {
    return _removals.putIfAbsent(cacheObject.key, () async {
      try {
        final provider = await _cacheInfoRepository;
        final toRemove = <int>[];
        await _removeCachedFile(cacheObject, toRemove);
        await provider.deleteAll(toRemove);
      } finally {
        _removals.remove(cacheObject.key);
      }
    });
  }

  Future<void> _removeCachedFile(
      CacheObject cacheObject, List<int> toRemove) async {
    if (toRemove.contains(cacheObject.id)) return;

    toRemove.add(cacheObject.id!);
    if (_memCache.containsKey(cacheObject.key)) {
      _memCache.remove(cacheObject.key);
    }
    if (_futureCache.containsKey(cacheObject.key)) {
      await _futureCache.remove(cacheObject.key);
    }
    final file = await fileSystem.createFile(cacheObject.relativePath);

    if (await file.exists()) {
      try {
        await file.delete();
        // ignore: unused_catch_clause
      } on PathNotFoundException catch (e) {
        // File has already been deleted. Do nothing #184
      }
    }
  }

  bool memoryCacheContainsKey(String key) {
    return _memCache.containsKey(key);
  }

  Future<void> dispose() async {
    _disposed = true;
    _scheduledCleanup?.cancel();
    await _cleanup;
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
