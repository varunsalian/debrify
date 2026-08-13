import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:path/path.dart' as p;

import '../../utils/app_storage.dart';
import 'profile_scope.dart';

/// Allowlisted portable files. Device assets, caches, executable paths, OS
/// grants, downloads, and recordings deliberately never enter this codec.
class ProfilePortableFiles {
  ProfilePortableFiles._();

  static const int maxFileBytes = 4 * 1024 * 1024;
  static const int maxTotalBytes = 64 * 1024 * 1024;

  static Future<Map<String, Object?>> export(ProfileScope scope) async {
    final root = await AppStorage.documents();
    final documents = scope.storageDirectory(root, 'documents');
    final engines = Directory(p.join(documents.path, 'engines'));
    if (!await engines.exists()) return const <String, Object?>{};
    final result = <String, Object?>{};
    var total = 0;
    await for (final entity in engines.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is Link) throw StateError('Portable files contain a symlink');
      if (entity is! File) continue;
      final relative = p
          .relative(entity.path, from: documents.path)
          .replaceAll(r'\', '/');
      if (!_allowed(relative)) continue;
      final length = await entity.length();
      total += length;
      if (length > maxFileBytes || total > maxTotalBytes) {
        throw StateError('Portable profile files exceed the backup limit');
      }
      final bytes = await entity.readAsBytes();
      result[relative] = <String, Object?>{
        'encoding': 'base64',
        'bytes': bytes.length,
        'sha256': await _hash(bytes),
        'data': base64Encode(bytes),
      };
    }
    return result;
  }

  static Future<int> restore(
    ProfileScope scope,
    Map<Object?, Object?> attachments,
  ) async {
    final root = await AppStorage.documents();
    var total = 0;
    var restored = 0;
    for (final entry in attachments.entries) {
      final relative = entry.key;
      final record = entry.value;
      if (relative is! String ||
          !_allowed(relative) ||
          record is! Map ||
          record['encoding'] != 'base64' ||
          record['bytes'] is! num ||
          record['sha256'] is! String ||
          record['data'] is! String) {
        throw const FormatException('Invalid portable profile file');
      }
      final claimed = (record['bytes'] as num).toInt();
      if (claimed < 0 || claimed > maxFileBytes) {
        throw const FormatException('Portable profile file exceeds limit');
      }
      final encoded = record['data'] as String;
      if (encoded.length > ((maxFileBytes + 2) ~/ 3) * 4) {
        throw const FormatException('Encoded portable file exceeds limit');
      }
      final bytes = base64Decode(encoded);
      total += bytes.length;
      if (bytes.length != claimed || total > maxTotalBytes) {
        throw const FormatException('Portable profile file size mismatch');
      }
      if (await _hash(bytes) != record['sha256']) {
        throw const FormatException('Portable profile file digest mismatch');
      }
      final destination = scope.fileIn(
        root,
        'documents',
        p.joinAll(relative.split('/')),
      );
      await destination.parent.create(recursive: true);
      final temp = File('${destination.path}.restore.tmp');
      if (await temp.exists()) await temp.delete();
      try {
        await temp.writeAsBytes(bytes, flush: true);
        if (await destination.exists()) await destination.delete();
        await temp.rename(destination.path);
        restored++;
      } finally {
        if (await temp.exists()) await temp.delete();
      }
    }
    return restored;
  }

  static bool _allowed(String relative) {
    final normalized = p.posix.normalize(relative);
    if (p.posix.isAbsolute(normalized) ||
        RegExp(r'^[A-Za-z]:').hasMatch(normalized) ||
        normalized == '..' ||
        normalized.startsWith('../') ||
        !normalized.startsWith('engines/')) {
      return false;
    }
    final extension = p.posix.extension(normalized).toLowerCase();
    return extension == '.yaml' || extension == '.yml' || extension == '.json';
  }

  static Future<String> _hash(List<int> bytes) async =>
      base64UrlEncode((await Sha256().hash(bytes)).bytes).replaceAll('=', '');
}
