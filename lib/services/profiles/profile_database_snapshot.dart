import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../../utils/app_storage.dart';
import '../../utils/streamed_file_copy.dart';
import '../iptv_catalog_key.dart';
import 'profile_scope.dart';

class DebrifyTvBackupOmission {
  static const String key = 'debrifyTvChannelsOmitted';

  final int channels;
  final int savedHashes;
  final int profilesAffected;

  const DebrifyTvBackupOmission({
    required this.channels,
    required this.savedHashes,
    required this.profilesAffected,
  });

  const DebrifyTvBackupOmission.none()
    : channels = 0,
      savedHashes = 0,
      profilesAffected = 0;

  bool get isEmpty => channels == 0 && savedHashes == 0;

  String get contentsLabel {
    final channelLabel = channels == 1 ? '1 channel' : '$channels channels';
    final hashLabel = savedHashes == 1
        ? '1 saved torrent hash'
        : '$savedHashes saved torrent hashes';
    return '$channelLabel containing $hashLabel';
  }

  DebrifyTvBackupOmission operator +(DebrifyTvBackupOmission other) =>
      DebrifyTvBackupOmission(
        channels: channels + other.channels,
        savedHashes: savedHashes + other.savedHashes,
        profilesAffected: profilesAffected + other.profilesAffected,
      );

  Map<String, int> toJson() => <String, int>{
    'channels': channels,
    'savedHashes': savedHashes,
    'profilesAffected': profilesAffected,
  };

  static DebrifyTvBackupOmission? fromOmissions(
    Map<String, dynamic> omissions,
  ) {
    final value = omissions[key];
    if (value is! Map) return null;
    final channels = value['channels'];
    final savedHashes = value['savedHashes'];
    final profilesAffected = value['profilesAffected'];
    if (channels is! num || savedHashes is! num || profilesAffected is! num) {
      return null;
    }
    if (channels != channels.toInt() ||
        savedHashes != savedHashes.toInt() ||
        profilesAffected != profilesAffected.toInt()) {
      return null;
    }
    final result = DebrifyTvBackupOmission(
      channels: channels.toInt(),
      savedHashes: savedHashes.toInt(),
      profilesAffected: profilesAffected.toInt(),
    );
    if (result.isEmpty ||
        result.channels < 0 ||
        result.savedHashes < 0 ||
        result.profilesAffected <= 0) {
      return null;
    }
    return result;
  }
}

class ProfileDatabaseSnapshotExport {
  final Map<String, Object?> attachments;
  final List<String> compacted;
  final DebrifyTvBackupOmission debrifyTvOmission;

  const ProfileDatabaseSnapshotExport({
    required this.attachments,
    required this.compacted,
    required this.debrifyTvOmission,
  });
}

class _DatabaseCompactionResult {
  final int removedRows;
  final DebrifyTvBackupOmission debrifyTvOmission;

  const _DatabaseCompactionResult({
    required this.removedRows,
    this.debrifyTvOmission = const DebrifyTvBackupOmission.none(),
  });
}

/// Receives ownership of a finished snapshot file during a file-backed export
/// and returns the opaque entry reference the package record should carry.
/// The sink must move or copy the file; the snapshot scratch copy is deleted
/// afterwards if it still exists.
typedef ProfileDatabaseSnapshotFileSink =
    Future<String> Function(
      String databaseName,
      File snapshot, {
      required int bytes,
      required String sha256,
    });

/// Maps a file-backed attachment's entry reference to the staged file that
/// restore should copy from. Returning null rejects the attachment.
typedef ProfileDatabaseFileResolver = File? Function(String entry);

/// Consistent, bounded SQLite snapshots used by profile backup/restore.
/// Imported SQL is never executed: only complete SQLite images for known
/// profile database filenames are accepted, then integrity-checked while the
/// destination generation is still invisible.
class ProfileDatabaseSnapshot {
  ProfileDatabaseSnapshot._();

  static const String debrifyTvDatabaseName = 'debrify_tv.db';
  static const int maxAttachmentBytes = 64 * 1024 * 1024;
  static const int maxTotalBytes = 128 * 1024 * 1024;

  /// Disk-oriented cap for one file-backed database in a local archive. It
  /// bounds staging space, not memory: file-backed restore streams the copy.
  static const int maxFileBackedAttachmentBytes = 4 * 1024 * 1024 * 1024 - 1;

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
    debrifyTvDatabaseName,
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
  /// IPTV catalog caches are pruned and Debrify TV is omitted as a complete
  /// feature: channel definitions never travel without their saved hashes.
  /// Durable IPTV playlists, favorites, watch history, resume state, hidden
  /// groups, manual category order, and channel numbering are never silently
  /// skipped. If that compact set still cannot fit, the export fails visibly.
  static Future<ProfileDatabaseSnapshotExport> export(
    ProfileScope scope, {
    bool compact = false,
    Map<String, String> resourceIdProjection = const <String, String>{},
    ProfileDatabaseSnapshotFileSink? fileSink,
    bool pruneRebuildableCaches = false,
  }) async {
    if (fileSink != null && compact) {
      throw ArgumentError(
        'File-backed exports never omit Debrify TV; use '
        'pruneRebuildableCaches instead of compact',
      );
    }
    if (pruneRebuildableCaches && fileSink == null) {
      throw ArgumentError(
        'pruneRebuildableCaches is only supported for file-backed exports',
      );
    }
    final attachmentCap = debugExportBudgetOverride ?? maxAttachmentBytes;
    final budget = debugExportBudgetOverride ?? maxExportRawBytes;
    final documents = await AppStorage.documents();
    final support = await AppStorage.support();
    final scratch = Directory(p.join(support.path, 'profile-snapshot-tmp'));
    await scratch.create(recursive: true);
    final snapshots = <String, File>{};
    final compacted = <String>[];
    var debrifyTvOmission = const DebrifyTvBackupOmission.none();
    try {
      for (final name in databaseNames) {
        final source = scope.fileIn(documents, 'documents', name);
        if (!await source.exists()) continue;
        final snapshot = File(p.join(scratch.path, '${_token()}-$name'));
        snapshots[name] = snapshot;
        await _createConsistentSnapshot(source, snapshot, name);
      }

      if (fileSink != null) {
        // Local archives carry whole databases as files, so the base64
        // package budget does not apply. Only rebuildable IPTV caches may be
        // dropped, and only on request; Debrify TV is never omitted here.
        if (pruneRebuildableCaches) {
          for (final entry in snapshots.entries) {
            if (await _pruneRebuildableCaches(entry.key, entry.value) > 0) {
              compacted.add(entry.key);
            }
          }
        }
      } else {
        var lengths = await _snapshotLengths(snapshots);
        final fullFits = _fitsBudget(lengths, attachmentCap, budget);
        if (compact || !fullFits) {
          for (final entry in snapshots.entries) {
            final result = await _compactSnapshot(entry.key, entry.value);
            if (result.removedRows > 0) {
              compacted.add(entry.key);
            }
            debrifyTvOmission += result.debrifyTvOmission;
          }
          lengths = await _snapshotLengths(snapshots);
        }
        if (!_fitsBudget(lengths, attachmentCap, budget)) {
          final total = lengths.values.fold<int>(
            0,
            (sum, value) => sum + value,
          );
          throw StateError(
            'Portable user library data is too large to back up '
            '(${(total / (1024 * 1024)).ceil()} MB)',
          );
        }
      }

      if (resourceIdProjection.isNotEmpty) {
        for (final entry in snapshots.entries) {
          await _remapDatabaseFile(
            entry.value,
            entry.key,
            resourceIdProjection,
          );
        }
      }

      final result = <String, Object?>{};
      for (final entry in snapshots.entries) {
        if (fileSink != null) {
          final bytes = await entry.value.length();
          final sha256 = await _hashFile(entry.value);
          final reference = await fileSink(
            entry.key,
            entry.value,
            bytes: bytes,
            sha256: sha256,
          );
          result[entry.key] = <String, Object?>{
            'encoding': 'file',
            'entry': reference,
            'bytes': bytes,
            'sha256': sha256,
          };
          continue;
        }
        final bytes = await entry.value.readAsBytes();
        result[entry.key] = <String, Object?>{
          'encoding': 'base64',
          'bytes': bytes.length,
          'sha256': await _hashBytes(bytes),
          'data': base64Encode(bytes),
        };
      }
      return ProfileDatabaseSnapshotExport(
        attachments: result,
        compacted: List<String>.unmodifiable(compacted),
        debrifyTvOmission: debrifyTvOmission,
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

  /// Durable IPTV catalog tables that every local archive keeps. Any table
  /// in the catalog database that is neither here nor in
  /// [rebuildableCatalogTables] fails the export: a new table must be
  /// classified deliberately rather than silently kept or dropped.
  static const Set<String> durableCatalogTables = <String>{
    'category_default_selections',
    'category_manual_orders',
    'channel_manual_orders',
    'channel_number_aliases',
    'channel_number_assignments',
    'channel_number_namespaces',
    'hidden_groups',
    'webdav_sync_meta',
    'webdav_sync_record_state',
  };

  /// Provider catalog and guide caches that refresh from the network after a
  /// restore. Dropped from local archives on request.
  static const Set<String> rebuildableCatalogTables = <String>{
    'meta',
    'catalogs',
    'channels',
    'epg_programmes',
    'epg_guides',
  };

  /// Removes rebuildable cache rows from an `iptv_catalog.db` snapshot and
  /// leaves every other database untouched. Returns the rows removed.
  static Future<int> _pruneRebuildableCaches(String name, File snapshot) async {
    if (name != 'iptv_catalog.db') return 0;
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
          .where((table) => !table.startsWith('sqlite_'))
          .where((table) => table != 'android_metadata')
          .toSet();
      final unclassified =
          existing
              .where(
                (table) =>
                    !durableCatalogTables.contains(table) &&
                    !rebuildableCatalogTables.contains(table),
              )
              .toList()
            ..sort();
      if (unclassified.isNotEmpty) {
        throw StateError(
          'IPTV catalog tables are not classified for local backup: '
          '${unclassified.join(', ')}',
        );
      }
      await db.transaction((txn) async {
        for (final table in rebuildableCatalogTables.where(existing.contains)) {
          removedRows += await txn.delete(table);
        }
      });
      if (removedRows > 0) await db.execute('VACUUM');
      final integrity = await db.rawQuery('PRAGMA integrity_check');
      if (!_integrityOk(integrity)) {
        throw StateError('$name failed pruned snapshot integrity check');
      }
    } finally {
      await db.close();
      await _removeCompanions(snapshot);
    }
    return removedRows;
  }

  static Future<_DatabaseCompactionResult> _compactSnapshot(
    String name,
    File snapshot,
  ) async {
    final compactedTables = switch (name) {
      // The pool contains the hashes that make a Debrify TV channel usable.
      // Omit the complete feature rather than restoring empty channel shells.
      debrifyTvDatabaseName => const <String>[
        'tv_cached_torrents',
        'tv_keyword_stats',
        'tv_channel_cache_state',
        'tv_channel_keywords',
        'tv_channels',
      ],
      // Same classification as the local archive's cache-only prune.
      'iptv_catalog.db' => rebuildableCatalogTables.toList(growable: false),
      _ => const <String>[],
    };
    final db = await openDatabase(snapshot.path, singleInstance: false);
    var removedRows = 0;
    var omission = const DebrifyTvBackupOmission.none();
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
      if (name == debrifyTvDatabaseName) {
        final channels = existing.contains('tv_channels')
            ? await _tableCount(db, 'tv_channels')
            : 0;
        final savedHashes = existing.contains('tv_cached_torrents')
            ? await _tableCount(db, 'tv_cached_torrents')
            : 0;
        if (channels > 0 || savedHashes > 0) {
          omission = DebrifyTvBackupOmission(
            channels: channels,
            savedHashes: savedHashes,
            profilesAffected: 1,
          );
        }
      }
      await db.transaction((txn) async {
        for (final table in compactedTables.where(existing.contains)) {
          removedRows += await txn.delete(table);
        }
        // Omitted physical rows must take their sync sidecar stamps with
        // them: a joiner that adopts stamps without rows would treat the
        // matching remote records as already applied and never backfill.
        if (name == debrifyTvDatabaseName &&
            existing.contains('webdav_sync_record_state')) {
          await txn.delete(
            'webdav_sync_record_state',
            where: 'kind IN (?, ?)',
            whereArgs: const <Object>['tv_channels', 'tv_pool_generation'],
          );
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
    return _DatabaseCompactionResult(
      removedRows: removedRows,
      debrifyTvOmission: omission,
    );
  }

  static Future<int> _tableCount(Database db, String table) async {
    final rows = await db.rawQuery('SELECT COUNT(*) AS row_count FROM $table');
    return (rows.single['row_count'] as int?) ?? 0;
  }

  static Future<int> restore(
    ProfileScope scope,
    Map<Object?, Object?> attachments, {
    ProfileDatabaseFileResolver? fileResolver,
  }) async {
    final documents = await AppStorage.documents();
    var total = 0;
    var restored = 0;
    for (final entry in attachments.entries) {
      final name = entry.key;
      final record = entry.value;
      if (name is! String || !databaseNames.contains(name) || record is! Map) {
        throw const FormatException('Invalid profile database attachment');
      }
      final fileBacked = record['encoding'] == 'file';
      if (fileBacked) {
        if (fileResolver == null) {
          throw const FormatException(
            'File-backed database attachments need a staged archive',
          );
        }
        if (record['entry'] is! String ||
            record['bytes'] is! num ||
            record['sha256'] is! String) {
          throw const FormatException('Invalid profile database attachment');
        }
      } else if (record['encoding'] != 'base64' ||
          record['bytes'] is! num ||
          record['sha256'] is! String ||
          record['data'] is! String) {
        throw const FormatException('Invalid profile database attachment');
      }
      final claimedBytes = (record['bytes'] as num).toInt();
      File? stagedSource;
      Uint8List? bytes;
      if (fileBacked) {
        if (claimedBytes < 0 || claimedBytes > maxFileBackedAttachmentBytes) {
          throw const FormatException('Database attachment exceeds limit');
        }
        final staged = fileResolver!(record['entry'] as String);
        if (staged == null || !await staged.exists()) {
          throw const FormatException('Database attachment is missing');
        }
        if (await staged.length() != claimedBytes) {
          throw const FormatException('Database attachment size mismatch');
        }
        // Verify the staged copy itself: a hash carried in the manifest only
        // proves what the exporter saw, not what reached this device.
        if (await _hashFile(staged) != record['sha256']) {
          throw const FormatException('Database attachment digest mismatch');
        }
        stagedSource = staged;
      } else {
        if (claimedBytes < 0 || claimedBytes > maxAttachmentBytes) {
          throw const FormatException('Database attachment exceeds limit');
        }
        final encoded = record['data'] as String;
        if (encoded.length > ((maxAttachmentBytes + 2) ~/ 3) * 4) {
          throw const FormatException(
            'Encoded database attachment is too large',
          );
        }
        bytes = base64Decode(encoded);
        total += bytes.length;
        if (bytes.length != claimedBytes || total > maxTotalBytes) {
          throw const FormatException('Database attachment size mismatch');
        }
        if (await _hashBytes(bytes) != record['sha256']) {
          throw const FormatException('Database attachment digest mismatch');
        }
      }

      final destination = scope.fileIn(documents, 'documents', name);
      await destination.parent.create(recursive: true);
      final temp = File('${destination.path}.restore.tmp');
      if (await temp.exists()) await temp.delete();
      try {
        if (stagedSource != null) {
          await _copyFile(stagedSource, temp);
        } else {
          await temp.writeAsBytes(bytes!, flush: true);
        }
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
      await _remapDatabaseFile(file, name, resourceIds);
    }
  }

  static Future<void> _remapDatabaseFile(
    File file,
    String name,
    Map<String, String> resourceIds,
  ) async {
    final db = await openDatabase(file.path, singleInstance: false);
    try {
      final tables = (await db.query(
        'sqlite_master',
        columns: const <String>['name'],
        where: "type = 'table'",
      )).map((row) => row['name']).whereType<String>().toSet();
      await db.transaction((txn) async {
        for (final entry in resourceIds.entries) {
          if (name == debrifyTvDatabaseName) {
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
            if (tables.contains('iptv_category_channel_orders')) {
              await txn.update(
                'iptv_category_channel_orders',
                <String, Object?>{'source_id': entry.value},
                where: 'source_id = ?',
                whereArgs: <Object>[entry.key],
              );
            }
            if (tables.contains('video_resume')) {
              final columns = await txn.rawQuery(
                'PRAGMA table_info(video_resume)',
              );
              if (columns.any((row) => row['name'] == 'source_id')) {
                await txn.update(
                  'video_resume',
                  <String, Object?>{'source_id': entry.value},
                  where: 'source_id = ?',
                  whereArgs: <Object>[entry.key],
                );
              }
            }
            if (tables.contains('webdav_sync_record_state')) {
              await txn.update(
                'webdav_sync_record_state',
                <String, Object?>{'owner_key': entry.value},
                where: 'owner_key = ? AND kind IN (?, ?, ?)',
                whereArgs: <Object>[
                  entry.key,
                  'iptv_category_channel_orders',
                  'iptv_watch_history',
                  'video_resume',
                ],
              );
            }
          } else if (name == 'iptv_catalog.db') {
            if (tables.contains('category_manual_orders')) {
              await txn.update(
                'category_manual_orders',
                <String, Object?>{
                  'catalog_key': IptvCatalogKey.forLocalCategoryOrder(
                    entry.value,
                  ),
                },
                where: 'catalog_key = ?',
                whereArgs: <Object>[
                  IptvCatalogKey.forLocalCategoryOrder(entry.key),
                ],
              );
            }
            if (tables.contains('webdav_sync_record_state')) {
              await txn.update(
                'webdav_sync_record_state',
                <String, Object?>{
                  'owner_key': IptvCatalogKey.forLocalCategoryOrder(
                    entry.value,
                  ),
                },
                where: 'owner_key = ? AND kind = ?',
                whereArgs: <Object>[
                  IptvCatalogKey.forLocalCategoryOrder(entry.key),
                  'category_manual_orders',
                ],
              );
            }
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

  /// Streams a file through SHA-256 in fixed chunks; the digest shape matches
  /// [_hashBytes] so file-backed and base64 records compare directly.
  static Future<String> _hashFile(File file) async {
    final sink = Sha256().newHashSink();
    final input = await file.open();
    try {
      while (true) {
        final chunk = await input.read(_fileChunkBytes);
        if (chunk.isEmpty) break;
        sink.add(chunk);
      }
    } finally {
      await input.close();
    }
    sink.close();
    return base64UrlEncode((await sink.hash()).bytes).replaceAll('=', '');
  }

  static Future<void> _copyFile(File source, File destination) =>
      copyFileStreamed(source, destination, chunkSize: _fileChunkBytes);

  static const int _fileChunkBytes = 256 * 1024;

  static String _token() {
    final random = Random.secure();
    final bytes = List<int>.generate(12, (_) => random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }
}
