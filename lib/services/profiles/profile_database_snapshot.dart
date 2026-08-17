import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
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

  /// Export-side budget for all database snapshots combined, deliberately
  /// tighter than the restore-side caps above: snapshot bytes are base64d
  /// into the package (x4/3), and the encrypted envelope base64s the whole
  /// ciphertext again (x4/3 = x16/9 net), so 64 MB raw is what actually fits
  /// under [PortableProfilePackage.maxEnvelopeBytes] with room for the rest
  /// of the package. Restore keeps accepting up to the looser caps.
  static const int maxExportRawBytes = 64 * 1024 * 1024;

  /// Test seam: shrinks [maxAttachmentBytes]/[maxExportRawBytes] so the
  /// skip-oversized path is exercisable without building a 64 MB database.
  @visibleForTesting
  static int? debugExportBudgetOverride;
  static const Set<String> databaseNames = <String>{
    'debrify_tv.db',
    'iptv_catalog.db',
  };

  /// Test seam: routes export through [_checkpointCopySnapshot] as if the OS
  /// SQLite predated VACUUM INTO. The test rig bundles a modern library, so
  /// the fallback — the exact code Android 7-9 devices run — would otherwise
  /// never execute in the suite.
  @visibleForTesting
  static bool debugForceCheckpointCopy = false;

  /// Snapshots every profile database that exists into base64 attachments.
  ///
  /// A database whose snapshot would not fit the export budget is SKIPPED and
  /// named in `skipped` (with its size) rather than failing the whole backup:
  /// a huge IPTV catalog must not make credentials and settings unbackupable.
  /// [databaseNames] iterates small-first, so the important small database
  /// still ships when the big one is dropped.
  static Future<({Map<String, Object?> attachments, List<String> skipped})>
  export(ProfileScope scope) async {
    final attachmentCap = debugExportBudgetOverride ?? maxAttachmentBytes;
    final budget = debugExportBudgetOverride ?? maxExportRawBytes;
    final documents = await AppStorage.documents();
    final support = await AppStorage.support();
    final scratch = Directory(p.join(support.path, 'profile-snapshot-tmp'));
    await scratch.create(recursive: true);
    final result = <String, Object?>{};
    final skipped = <String>[];
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
          if (debugForceCheckpointCopy) {
            await db.close();
            await _checkpointCopySnapshot(source, snapshot);
          } else {
            try {
              await db.execute("VACUUM INTO '$escaped'");
            } on DatabaseException catch (error) {
              // VACUUM INTO needs SQLite 3.27 (2019). sqflite links the OS
              // library, and Android ships 3.27+ only from 10 up — on the
              // Android 7-9 TV-box generation the statement fails to
              // COMPILE, which took profile backups down with it (same
              // class as the ON-CONFLICT upsert caught live on a Mi Box).
              // Fall back to a checkpoint-and-copy snapshot on exactly that
              // signature.
              if (!_looksLikeSyntaxError(error)) rethrow;
              await db.close();
              await _checkpointCopySnapshot(source, snapshot);
            }
          }
        } finally {
          if (db.isOpen) await db.close();
        }
        final length = await snapshot.length();
        if (length > attachmentCap || total + length > budget) {
          skipped.add('$name (${(length / (1024 * 1024)).ceil()} MB)');
          continue;
        }
        total += length;
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
    return (attachments: result, skipped: skipped);
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

  static bool _looksLikeSyntaxError(DatabaseException error) {
    final message = error.toString().toLowerCase();
    return message.contains('syntax error');
  }

  /// Pre-3.27 snapshot: checkpoint the WAL into the main file, byte-copy it,
  /// and prove the copy by integrity-checking it. VACUUM INTO's point-in-time
  /// guarantee is lost, so a concurrent writer surfaces as a failed check —
  /// retried a few times rather than silently exporting a torn image.
  static Future<void> _checkpointCopySnapshot(File source, File snapshot) async {
    StateError? lastFailure;
    for (var attempt = 0; attempt < 3; attempt++) {
      final db = await openDatabase(source.path, singleInstance: false);
      try {
        await db.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
      } finally {
        await db.close();
      }
      if (await snapshot.exists()) await snapshot.delete();
      await source.copy(snapshot.path);
      // A bare copy has no -wal/-shm companions, so validate via a
      // read/write open (SQLite may create empty companions) and drop them
      // after — the same shape the migration's snapshot validation uses.
      final copy = await openDatabase(snapshot.path, singleInstance: false);
      try {
        final integrity = await copy.rawQuery('PRAGMA integrity_check');
        if (_integrityOk(integrity)) return;
        lastFailure = StateError('snapshot failed integrity check');
      } finally {
        await copy.close();
        for (final suffix in const <String>['-wal', '-shm', '-journal']) {
          final companion = File('${snapshot.path}$suffix');
          if (await companion.exists()) await companion.delete();
        }
      }
    }
    throw lastFailure ?? StateError('could not take a consistent snapshot');
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
