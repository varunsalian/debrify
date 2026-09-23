import 'package:file/file.dart' hide FileSystem;
import 'package:file/local.dart';
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

  /// Recover UUID files whose index entries were lost by older eviction code.
  /// Only this cache's immediate files are inspected, never links or folders.
  /// A grace period also protects recent unindexed downloads from another
  /// manager using the same cache key.
  Future<void> removeOldOrphans(Set<String> indexedPaths) async {
    final directory = await _fileDir;
    if (!await directory.exists()) return;
    final cutoff = DateTime.now().subtract(const Duration(days: 1));
    final generatedName = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}(?:\.[^/\\]+)?$',
    );
    await for (final entity in directory.list(followLinks: false)) {
      final name = p.basename(entity.path);
      if (entity is! File ||
          !generatedName.hasMatch(name) ||
          indexedPaths.contains(name)) {
        continue;
      }
      try {
        if ((await entity.stat()).modified.isBefore(cutoff)) {
          await entity.delete();
        }
      } on FileSystemException {
        // A cache file may have disappeared or be in use; retry next startup.
      }
    }
  }
}
