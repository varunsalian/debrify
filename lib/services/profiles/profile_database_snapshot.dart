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
  /// compact/fail path is exercisable without building a 64 MB database.
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
  /// Full images are preferred. If the images do not fit the package budget,
  /// only explicitly rebuildable cache tables are pruned and all images are
  /// measured again. Durable channels, playlists, favorites, watch history,
  /// resume state, hidden groups, and channel numbering are never silently
  /// skipped: if that compact set still cannot fit, the export fails visibly.
  static Future<({Map<String, Object?> attachments, List<String> compacted})>
  export(ProfileScope scope, {bool compact = false}) async {
    final attachmentCap = debugExportBudgetOverride ?? maxAttachmentBytes;
    final budget = debugExportBudgetOverride ?? maxExportRawBytes;
    final documents = await AppStorage.documents();
    final support = await AppStorage.support();
    final scratch = Directory(p.join(support.path, 'profile-snapshot-tmp'));
    await scratch.create(recursive: true);
    final snapshots = <String, File>{};
    final compacted = <String>[];
    try {
      for (final name in databaseNames) {
        final source = scope.fileIn(documents, 'documents', name);
        if (!await source.exists()) continue;
        final snapshot = File(p.join(scratch.path, '${_token()}-$name'));
        snapshots[name] = snapshot;
        await _createConsistentSnapshot(source, snapshot, name);
      }

      var lengths = await _snapshotLengths(snapshots);
      final fullFits = _fitsBudget(lengths, attachmentCap, budget);
      if (compact || !fullFits) {
        for (final entry in snapshots.entries) {
          if (await _compactSnapshot(entry.key, entry.value)) {
            compacted.add(entry.key);
          }
        }
        lengths = await _snapshotLengths(snapshots);
      }
      if (!_fitsBudget(lengths, attachmentCap, budget)) {
        final total = lengths.values.fold<int>(0, (sum, value) => sum + value);
        throw StateError(
          'Portable user library data is too large to back up '
          '(${(total / (1024 * 1024)).ceil()} MB)',
        );
      }

      final result = <String, Object?>{};
      for (final entry in snapshots.entries) {
        final bytes = await entry.value.readAsBytes();
        result[entry.key] = <String, Object?>{
          'encoding': 'base64',
          'bytes': bytes.length,
          'sha256': await _hashBytes(bytes),
          'data': base64Encode(bytes),
        };
      }
      return (
        attachments: result,
        compacted: List<String>.unmodifiable(compacted),
      );
    } finally {
      for (final snapshot in snapshots.values) {
        if (await snapshot.exists()) await snapshot.delete();
        await _removeCompanions(snapshot);
      }
      try {
        if (await scratch.exists() && await scratch.list().isEmpty) {
          await scratch.delete();
        }
      } catch (_) {
        // A concurrent export may still own the shared scratch directory.
      }
    }
  }

  static Future<void> _createConsistentSnapshot(
    File source,
    File snapshot,
    String name,
  ) async {
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
          // VACUUM INTO needs SQLite 3.27 (2019). Android 7-9 falls back to a
          // checkpointed copy, which is validated before it is accepted.
          if (!_looksLikeSyntaxError(error)) rethrow;
          await db.close();
          await _checkpointCopySnapshot(source, snapshot);
        }
      }
    } finally {
      if (db.isOpen) await db.close();
    }
  }

  static Future<Map<String, int>> _snapshotLengths(
    Map<String, File> snapshots,
  ) async => <String, int>{
    for (final entry in snapshots.entries)
      entry.key: await entry.value.length(),
  };

  static bool _fitsBudget(
    Map<String, int> lengths,
    int attachmentCap,
    int totalBudget,
  ) =>
      lengths.values.every((length) => length <= attachmentCap) &&
      lengths.values.fold<int>(0, (sum, length) => sum + length) <= totalBudget;

  static Future<bool> _compactSnapshot(String name, File snapshot) async {
    final cacheTables = switch (name) {
      'debrify_tv.db' => const <String>{
        'tv_channel_cache_state',
        'tv_cached_torrents',
        'tv_keyword_stats',
      },
      'iptv_catalog.db' => const <String>{
        'meta',
        'catalogs',
        'channels',
        'epg_programmes',
        'epg_guides',
      },
      _ => const <String>{},
    };
    final db = await openDatabase(snapshot.path, singleInstance: false);
    var removedRows = 0;
    try {
      final rows = await db.query(
        'sqlite_master',
        columns: const <String>['name'],
        where: "type = 'table'",
      );
      final existing = rows
          .map((row) => row['name'])
          .whereType<String>()
          .toSet();
      await db.transaction((txn) async {
        for (final table in cacheTables.where(existing.contains)) {
          removedRows += await txn.delete(table);
        }
      });
      await db.execute('VACUUM');
      final integrity = await db.rawQuery('PRAGMA integrity_check');
      if (!_integrityOk(integrity)) {
        throw StateError('$name failed compact snapshot integrity check');
      }
    } finally {
      await db.close();
      await _removeCompanions(snapshot);
    }
    return removedRows > 0;
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

  /// Rewrites durable references to connection-resource IDs after restore has
  /// minted destination IDs. Cache identities are URL-based and need no
  /// rewrite; playlist memberships and channel-number namespaces do.
  static Future<void> remapResourceReferences(
    ProfileScope scope,
    Map<String, String> resourceIds,
  ) async {
    if (resourceIds.isEmpty) return;
    final documents = await AppStorage.documents();
    for (final name in databaseNames) {
      final file = scope.fileIn(documents, 'documents', name);
      if (!await file.exists()) continue;
      final db = await openDatabase(file.path, singleInstance: false);
      try {
        final tables = (await db.query(
          'sqlite_master',
          columns: const <String>['name'],
          where: "type = 'table'",
        )).map((row) => row['name']).whereType<String>().toSet();
        await db.transaction((txn) async {
          for (final entry in resourceIds.entries) {
            if (name == 'debrify_tv.db') {
              for (final table in const <String>{
                'iptv_list_channels',
                'iptv_watch_history',
              }.where(tables.contains)) {
                await txn.update(
                  table,
                  <String, Object?>{'playlist_id': entry.value},
                  where: 'playlist_id = ?',
                  whereArgs: <Object>[entry.key],
                );
              }
            } else if (name == 'iptv_catalog.db') {
              if (tables.contains('channel_number_aliases')) {
                await txn.update(
                  'channel_number_aliases',
                  <String, Object?>{'source_key': entry.value},
                  where: 'source_key = ?',
                  whereArgs: <Object>[entry.key],
                );
              }
              if (tables.contains('channel_number_namespaces')) {
                await txn.update(
                  'channel_number_namespaces',
                  <String, Object?>{'active_source_key': entry.value},
                  where: 'active_source_key = ?',
                  whereArgs: <Object>[entry.key],
                );
              }
            }
          }
        });
        await db.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
        final integrity = await db.rawQuery('PRAGMA integrity_check');
        if (!_integrityOk(integrity)) {
          throw const FormatException('Remapped database is corrupt');
        }
      } finally {
        await db.close();
        await _removeCompanions(file);
      }
    }
  }

  static bool _looksLikeSyntaxError(DatabaseException error) {
    final message = error.toString().toLowerCase();
    return message.contains('syntax error');
  }

  static Future<void> _removeCompanions(File database) async {
    for (final suffix in const <String>['-wal', '-shm', '-journal']) {
      final companion = File('${database.path}$suffix');
      if (await companion.exists()) await companion.delete();
    }
  }

  /// Pre-3.27 snapshot: checkpoint the WAL into the main file, byte-copy it,
  /// and prove the copy by integrity-checking it. VACUUM INTO's point-in-time
  /// guarantee is lost, so a concurrent writer surfaces as a failed check —
  /// retried a few times rather than silently exporting a torn image.
  static Future<void> _checkpointCopySnapshot(
    File source,
    File snapshot,
  ) async {
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
