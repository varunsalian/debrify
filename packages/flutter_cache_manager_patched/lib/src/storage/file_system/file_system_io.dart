import 'dart:io' as io;

import 'package:file/file.dart' hide FileSystem;
import 'package:file/local.dart';
import 'package:flutter_cache_manager/src/logger.dart';
import 'package:flutter_cache_manager/src/storage/file_system/file_system.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class IOFileSystem implements FileSystem {
  final Future<Directory> _fileDir;
  final String _cacheKey;

  IOFileSystem(this._cacheKey) : _fileDir = createDirectory(_cacheKey);

  static Future<Directory> createDirectory(String key) async {
    final baseDir = await getTemporaryDirectory();
    final path = p.join(baseDir.path, key);

    const fs = LocalFileSystem();
    final directory = fs.directory(path);
    await directory.create(recursive: true);
    return directory;
  }

  @override
  Future<File> createFile(String name) async {
    final directory = await _fileDir;
    if (!(await directory.exists())) {
      await createDirectory(_cacheKey);
    }
    return directory.childFile(name);
  }

  /// Names of files currently on disk, without reading contents or statting
  /// each file. Used only when metadata says eviction may be necessary.
  Future<Set<String>> cachedFilePaths() async {
    final directory = await _fileDir;
    final paths = <String>{};
    try {
      await for (final entity in directory.list(followLinks: false)) {
        if (entity is File) paths.add(p.basename(entity.path));
      }
    } on io.PathNotFoundException {
      // The OS may purge the whole cache directory while the app is running.
      return <String>{};
    }
    return paths;
  }

  /// Repairs files orphaned by the pre-patch relative-path eviction bug.
  /// Only this manager's flat directory is visited, without following links.
  /// A one-day grace period keeps unfinished downloads out of this sweep.
  Future<void> removeOrphanedFiles(Set<String> referencedPaths) async {
    final directory = await _fileDir;
    if (!await directory.exists()) return;
    final cutoff = DateTime.now().subtract(const Duration(days: 1));
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File ||
          referencedPaths.contains(p.basename(entity.path))) {
        continue;
      }
      try {
        if ((await entity.stat()).modified.isBefore(cutoff)) {
          await entity.delete();
        }
      } on io.PathNotFoundException {
        // The OS or another cleanup already removed it.
      } on io.FileSystemException catch (error) {
        // One inaccessible file must not prevent reclaiming the others.
        cacheLogger.log('Orphan removal failed (${error.runtimeType})',
            CacheManagerLogLevel.warning);
      }
    }
  }
}
