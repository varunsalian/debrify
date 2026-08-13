import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../../utils/app_storage.dart';
import 'profile_scope.dart';

/// Consistent, bounded SQLite snapshots used by profile backup/restore.
/// Imported SQL is never executed: only complete SQLite images for known
/// profile database filenames are accepted, then integrity-checked while the
/// destination generation is still invisible.
class ProfileDatabaseSnapshot {
  ProfileDatabaseSnapshot._();

  static const int maxAttachmentBytes = 64 * 1024 * 1024;
  static const int maxTotalBytes = 128 * 1024 * 1024;
  static const Set<String> databaseNames = <String>{
    'debrify_tv.db',
    'iptv_catalog.db',
  };

  static Future<Map<String, Object?>> export(ProfileScope scope) async {
    final documents = await AppStorage.documents();
    final support = await AppStorage.support();
    final scratch = Directory(p.join(support.path, 'profile-snapshot-tmp'));
    await scratch.create(recursive: true);
    final result = <String, Object?>{};
    var total = 0;
    for (final name in databaseNames) {
      final source = scope.fileIn(documents, 'documents', name);
      if (!await source.exists()) continue;
      final token = _token();
      final snapshot = File(p.join(scratch.path, '$token-$name'));
      try {
        final db = await openDatabase(
          source.path,
          readOnly: true,
          singleInstance: false,
        );
        try {
          final integrity = await db.rawQuery('PRAGMA integrity_check');
          if (!_integrityOk(integrity)) {
            throw StateError('$name failed export integrity check');
          }
          final escaped = snapshot.path.replaceAll("'", "''");
          await db.execute("VACUUM INTO '$escaped'");
        } finally {
          await db.close();
        }
        final length = await snapshot.length();
        total += length;
        if (length > maxAttachmentBytes || total > maxTotalBytes) {
          throw StateError('Profile database backup exceeds attachment limit');
        }
        final bytes = await snapshot.readAsBytes();
        result[name] = <String, Object?>{
          'encoding': 'base64',
          'bytes': bytes.length,
          'sha256': await _hashBytes(bytes),
          'data': base64Encode(bytes),
        };
      } finally {
        if (await snapshot.exists()) await snapshot.delete();
      }
    }
    try {
      if (await scratch.exists() && await scratch.list().isEmpty) {
        await scratch.delete();
      }
    } catch (_) {
      // A concurrent export may still own the shared scratch directory.
    }
    return result;
  }

  static Future<int> restore(
    ProfileScope scope,
    Map<Object?, Object?> attachments,
  ) async {
    final documents = await AppStorage.documents();
    var total = 0;
    var restored = 0;
    for (final entry in attachments.entries) {
      final name = entry.key;
      final record = entry.value;
      if (name is! String ||
          !databaseNames.contains(name) ||
          record is! Map ||
          record['encoding'] != 'base64' ||
          record['bytes'] is! num ||
          record['sha256'] is! String ||
          record['data'] is! String) {
        throw const FormatException('Invalid profile database attachment');
      }
      final claimedBytes = (record['bytes'] as num).toInt();
      if (claimedBytes < 0 || claimedBytes > maxAttachmentBytes) {
        throw const FormatException('Database attachment exceeds limit');
      }
      final encoded = record['data'] as String;
      if (encoded.length > ((maxAttachmentBytes + 2) ~/ 3) * 4) {
        throw const FormatException('Encoded database attachment is too large');
      }
      final bytes = base64Decode(encoded);
      total += bytes.length;
      if (bytes.length != claimedBytes || total > maxTotalBytes) {
        throw const FormatException('Database attachment size mismatch');
      }
      if (await _hashBytes(bytes) != record['sha256']) {
        throw const FormatException('Database attachment digest mismatch');
      }

      final destination = scope.fileIn(documents, 'documents', name);
      await destination.parent.create(recursive: true);
      final temp = File('${destination.path}.restore.tmp');
      if (await temp.exists()) await temp.delete();
      try {
        await temp.writeAsBytes(bytes, flush: true);
        final db = await openDatabase(
          temp.path,
          readOnly: true,
          singleInstance: false,
        );
        try {
          final integrity = await db.rawQuery('PRAGMA integrity_check');
          if (!_integrityOk(integrity)) {
            throw const FormatException('Restored database is corrupt');
          }
        } finally {
          await db.close();
        }
        for (final suffix in const <String>['', '-wal', '-shm', '-journal']) {
          final member = File('${destination.path}$suffix');
          if (await member.exists()) await member.delete();
        }
        await temp.rename(destination.path);
        restored++;
      } finally {
        if (await temp.exists()) await temp.delete();
      }
    }
    return restored;
  }

  static bool _integrityOk(List<Map<String, Object?>> rows) =>
      rows.isNotEmpty && rows.first.values.first == 'ok';

  static Future<String> _hashBytes(List<int> bytes) async =>
      base64UrlEncode((await Sha256().hash(bytes)).bytes).replaceAll('=', '');

  static String _token() {
    final random = Random.secure();
    final bytes = List<int>.generate(12, (_) => random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }
}
