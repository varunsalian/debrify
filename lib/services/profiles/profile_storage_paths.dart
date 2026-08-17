import 'dart:io';

import 'package:path/path.dart' as p;

import '../../utils/app_storage.dart';
import 'profile_runtime.dart';

class ProfileStoragePaths {
  ProfileStoragePaths._();

  static Future<String> documentsFile(String relativePath) async =>
      _resolve(await AppStorage.documents(), 'documents', relativePath);

  static Future<String> supportFile(String relativePath) async =>
      _resolve(await AppStorage.support(), 'support', relativePath);

  static Future<String> cacheFile(String relativePath) async =>
      _resolve(await AppStorage.cache(), 'cache', relativePath);

  static Future<String> documentsDirectory() async {
    final root = await AppStorage.documents();
    if (ProfileRuntime.mode == ProfileRuntimeMode.legacyCompatibility) {
      return root.path;
    }
    final directory = ProfileRuntime.capture().storageDirectory(
      root,
      'documents',
    );
    await directory.create(recursive: true);
    return directory.path;
  }

  static Future<String> _resolve(
    Directory root,
    String area,
    String relativePath,
  ) async {
    final normalized = p.normalize(relativePath);
    if (p.isAbsolute(normalized) ||
        normalized == '..' ||
        normalized.startsWith('../')) {
      throw ArgumentError.value(relativePath, 'relativePath', 'Unsafe path');
    }
    if (ProfileRuntime.mode == ProfileRuntimeMode.legacyCompatibility) {
      return p.join(root.path, normalized);
    }
    final file = ProfileRuntime.capture().fileIn(root, area, normalized);
    await file.parent.create(recursive: true);
    return file.path;
  }
}
