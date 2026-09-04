import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:synchronized/synchronized.dart';

import '../../models/profiles/connection_resource.dart';
import '../../models/profiles/profile_policy.dart';
import '../../models/profiles/user_profile.dart';
import '../../utils/app_storage.dart';
import '../webdav_sync/webdav_sync_tombstones.dart';
import 'profile_lock_controller.dart';
import 'profile_preferences.dart';
import 'profile_runtime.dart';
import 'profile_scope.dart';
import 'tvos_profile_recovery_store.dart';
import 'tvos_recovery_limits.dart';

class ProfileRegistry {
  ProfileRegistry._(this._db);

  static const int schemaVersion = 8;
  final Database _db;
  Future<void> _recoveryCheckpoint = Future<void>.value();
  static final Lock _tombstoneOutboxDrainLock = Lock();
  Future<void> Function()? authorityWillChangeCallback;
  Future<void> Function()? authorityChangedCallback;

  static const List<String> _recoveryTables = <String>[
    'user_profiles',
    'device_state',
    'connection_resources',
    'profile_resource_grants',
    'profile_resource_settings',
    'profile_connection_bindings',
    'profile_migration_journal',
    'profile_data_generations',
    'profile_restore_journal',
    'profile_restore_resources',
    'webdav_sync_tombstone_outbox',
    // After their parents: the snapshot import replays inserts in list order
    // with foreign keys on.
    'resource_secret_chunks',
    'restore_secret_chunks',
  ];

  static Future<String> defaultPath() async =>
      p.join((await AppStorage.support()).path, 'profiles.db');

  static Future<bool> defaultRegistryExists() async =>
      File(await defaultPath()).exists();

  /// Read-only authority probe used before bootstrap is allowed to create or
  /// upgrade anything. A zero-byte/corrupt/WAL-lost file is not evidence that
  /// a previously committed install may safely mount legacy state.
  static Future<bool> defaultAuthorityIsCommitted() async {
    final path = await defaultPath();
    if (!await File(path).exists()) return false;
    Database? db;
    try {
      db = await openDatabase(path, readOnly: true, singleInstance: false);
      final rows = await db.query(
        'device_state',
        columns: const <String>['bootstrap_state', 'migration_state'],
        where: 'singleton_id = 1',
        limit: 1,
      );
      return rows.length == 1 &&
          rows.single['bootstrap_state'] == 'ready' &&
          rows.single['migration_state'] == 'committed';
    } catch (_) {
      return false;
    } finally {
      await db?.close();
    }
  }

  static Future<void> discardDefaultCacheProjection() async {
    final path = await defaultPath();
    for (final suffix in const <String>['', '-wal', '-shm', '-journal']) {
      final file = File('$path$suffix');
      if (await file.exists()) await file.delete();
    }
  }

  /// Moves an unusable registry family aside without destroying the only
  /// remaining forensic/recovery copy. Sidecars move before the main file so
  /// an interruption never leaves a newly-created database paired with an old
  /// WAL. The returned paths can be surfaced in diagnostics after recovery.
  static Future<List<String>> quarantineDefaultProjection() async {
    final path = await defaultPath();
    final stamp = DateTime.now().toUtc().microsecondsSinceEpoch;
    final moved = <String>[];
    for (final suffix in const <String>['-wal', '-shm', '-journal', '']) {
      final source = File('$path$suffix');
      if (!await source.exists()) continue;
      final destination = '$path.recovery-$stamp$suffix';
      await source.rename(destination);
      moved.add(destination);
    }
    return moved;
  }

  static Future<ProfileRegistry> open({String? path}) async {
    final dbPath = path ?? await defaultPath();
    final db = await openDatabase(
      dbPath,
      version: schemaVersion,
      onConfigure: (database) => database.execute('PRAGMA foreign_keys = ON'),
      onCreate: (database, _) async {
        await _createSchema(database);
        // Not in _schemaStatements, so spell it out: fresh installs went
        // WITHOUT these triggers from v2 until 2026-08 — only upgraded
        // installs ran the < 2 branch below. IF NOT EXISTS makes this safe
        // for both paths.
        await _createPinIntegrityTriggers(database);
      },
      onUpgrade: (database, oldVersion, newVersion) async {
        if (oldVersion < 2) await _createPinIntegrityTriggers(database);
        if (oldVersion < 3) await _createRestoreResourceTable(database);
        if (oldVersion < 4) {
          await _addPinRecoveryColumns(database);
          // Databases CREATED at v2/v3 never got the pin triggers (onCreate
          // omitted them until v4); repair that here.
          await _createPinIntegrityTriggers(database);
        }
        if (oldVersion < 5) {
          await _createSecretChunkTables(database);
          // Rows this size were written by v4 (writes never cross a
          // CursorWindow) and have been unreadable whole ever since. substr()
          // is the one door left: the window holds the RESULT row, not the
          // source, so the repair reads them out in slices.
          await _repairOversizedInlineEnvelopes(database);
        }
        if (oldVersion < 6) {
          await _addRestoreResourceSettingsColumns(database);
        }
        if (oldVersion < 7) await _addRegistrySyncColumns(database);
        if (oldVersion < 8) await _createWebDavSyncTombstoneOutbox(database);
      },
    );
    return ProfileRegistry._(db);
  }

  static Future<void> _createSchema(DatabaseExecutor db) async {
    for (final statement in _schemaStatements) {
      await db.execute(statement);
    }
  }

  /// v4: PIN recovery-code columns. Plain ADD COLUMN (works back to the
  /// SQLite 3.9 OS floor); the set-together invariant with the PIN trio is
  /// enforced in [setPinRecord] rather than a table CHECK, which ALTER
  /// cannot add.
  static Future<void> _addPinRecoveryColumns(DatabaseExecutor db) async {
    await db.execute('ALTER TABLE user_profiles ADD COLUMN recovery_hash BLOB');
    await db.execute('ALTER TABLE user_profiles ADD COLUMN recovery_salt BLOB');
    await db.execute(
      'ALTER TABLE user_profiles ADD COLUMN recovery_params_json TEXT',
    );
  }

  /// v6: profile-local enablement/presentation staged beside a restored
  /// connection, so a single-profile restore can publish both atomically.
  static Future<void> _addRestoreResourceSettingsColumns(
    DatabaseExecutor db,
  ) async {
    final columns = (await db.rawQuery(
      'PRAGMA table_info(profile_restore_resources)',
    )).map((row) => row['name']).whereType<String>().toSet();
    if (!columns.contains('profile_enabled')) {
      await db.execute(
        'ALTER TABLE profile_restore_resources ADD COLUMN profile_enabled INTEGER',
      );
    }
    if (!columns.contains('profile_settings_json')) {
      await db.execute(
        'ALTER TABLE profile_restore_resources ADD COLUMN profile_settings_json TEXT',
      );
    }
    if (!columns.contains('resource_enabled')) {
      await db.execute(
        'ALTER TABLE profile_restore_resources '
        'ADD COLUMN resource_enabled INTEGER NOT NULL DEFAULT 1',
      );
    }
  }

  /// v7: record-level WebDAV sync provenance and credential receiver state.
  /// Plain ADD COLUMN keeps this compatible with the Android SQLite 3.9
  /// floor. Grants are the only rows with a defensible historical stamp.
  static Future<void> _addRegistrySyncColumns(DatabaseExecutor db) async {
    await db.execute(
      'ALTER TABLE profile_resource_grants '
      'ADD COLUMN updated_at_ms INTEGER NOT NULL DEFAULT 0',
    );
    await db.execute(
      'UPDATE profile_resource_grants '
      'SET updated_at_ms = created_at_ms WHERE updated_at_ms = 0',
    );
    await db.execute(
      'ALTER TABLE profile_resource_settings '
      'ADD COLUMN updated_at_ms INTEGER NOT NULL DEFAULT 0',
    );
    await db.execute(
      'ALTER TABLE connection_resources '
      'ADD COLUMN secret_pending INTEGER NOT NULL DEFAULT 0',
    );
  }

  /// v8: committed registry deletions wait here until their file-backed
  /// WebDAV tombstones are durable. CREATE TABLE keeps the SQLite 3.9 floor.
  static Future<void> _createWebDavSyncTombstoneOutbox(
    DatabaseExecutor db,
  ) async {
    await db.execute(
      _schemaStatements.firstWhere(
        (statement) => statement.contains('webdav_sync_tombstone_outbox'),
      ),
    );
  }

  /// Test seam: lets the migration suite build an older-schema database (by
  /// stripping later columns) and prove the onUpgrade path against it.
  @visibleForTesting
  static List<String> get debugSchemaStatements => _schemaStatements;

  static const List<String> _schemaStatements = <String>[
    '''CREATE TABLE user_profiles (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL CHECK(length(trim(name)) > 0),
      avatar_key TEXT,
      role TEXT NOT NULL CHECK(role IN ('admin', 'member', 'child')),
      policy_json TEXT NOT NULL,
      policy_schema_version INTEGER NOT NULL,
      authorization_revision INTEGER NOT NULL DEFAULT 1,
      lifecycle_state TEXT NOT NULL DEFAULT 'active'
        CHECK(lifecycle_state IN ('staging', 'active')),
      visible_data_generation INTEGER NOT NULL DEFAULT 1,
      profile_setup_complete INTEGER NOT NULL DEFAULT 0,
      pin_reset_required INTEGER NOT NULL DEFAULT 0,
      pin_hash BLOB,
      pin_salt BLOB,
      pin_params_json TEXT,
      failed_pin_attempts INTEGER NOT NULL DEFAULT 0,
      locked_until_ms INTEGER,
      recovery_hash BLOB,
      recovery_salt BLOB,
      recovery_params_json TEXT,
      lock_on_resume INTEGER NOT NULL DEFAULT 0,
      inactivity_timeout_minutes INTEGER,
      created_at_ms INTEGER NOT NULL,
      updated_at_ms INTEGER NOT NULL,
      disabled_at_ms INTEGER
      ,CHECK (
        (pin_hash IS NULL AND pin_salt IS NULL AND pin_params_json IS NULL) OR
        (pin_hash IS NOT NULL AND pin_salt IS NOT NULL AND pin_params_json IS NOT NULL)
      )
    )''',
    '''CREATE TABLE device_state (
      singleton_id INTEGER PRIMARY KEY CHECK(singleton_id = 1),
      schema_version INTEGER NOT NULL,
      bootstrap_state TEXT NOT NULL,
      migration_state TEXT NOT NULL,
      active_profile_id TEXT,
      registry_generation INTEGER NOT NULL DEFAULT 1,
      activation_revision INTEGER NOT NULL DEFAULT 0,
      activation_state_json TEXT,
      updated_at_ms INTEGER NOT NULL,
      FOREIGN KEY(active_profile_id) REFERENCES user_profiles(id)
        ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED
    )''',
    '''CREATE TABLE connection_resources (
      id TEXT PRIMARY KEY,
      type TEXT NOT NULL,
      label TEXT NOT NULL,
      owner_profile_id TEXT NOT NULL,
      public_config_json TEXT NOT NULL,
      sealed_secret_payload TEXT,
      secret_payload_version INTEGER,
      secret_pending INTEGER NOT NULL DEFAULT 0,
      authorization_revision INTEGER NOT NULL DEFAULT 1,
      created_at_ms INTEGER NOT NULL,
      updated_at_ms INTEGER NOT NULL,
      disabled_at_ms INTEGER,
      FOREIGN KEY(owner_profile_id) REFERENCES user_profiles(id) ON DELETE RESTRICT
    )''',
    '''CREATE TABLE profile_resource_grants (
      profile_id TEXT NOT NULL,
      resource_id TEXT NOT NULL,
      permissions INTEGER NOT NULL,
      granted_by_profile_id TEXT,
      grant_origin_json TEXT NOT NULL,
      created_at_ms INTEGER NOT NULL,
      updated_at_ms INTEGER NOT NULL DEFAULT 0,
      PRIMARY KEY(profile_id, resource_id),
      FOREIGN KEY(profile_id) REFERENCES user_profiles(id) ON DELETE CASCADE,
      FOREIGN KEY(resource_id) REFERENCES connection_resources(id) ON DELETE CASCADE,
      FOREIGN KEY(granted_by_profile_id) REFERENCES user_profiles(id) ON DELETE SET NULL
    )''',
    '''CREATE TABLE profile_resource_settings (
      profile_id TEXT NOT NULL,
      resource_id TEXT NOT NULL,
      enabled INTEGER NOT NULL DEFAULT 1,
      settings_json TEXT NOT NULL,
      updated_at_ms INTEGER NOT NULL DEFAULT 0,
      PRIMARY KEY(profile_id, resource_id),
      FOREIGN KEY(profile_id, resource_id)
        REFERENCES profile_resource_grants(profile_id, resource_id) ON DELETE CASCADE
    )''',
    '''CREATE TABLE profile_connection_bindings (
      profile_id TEXT NOT NULL,
      slot TEXT NOT NULL,
      resource_id TEXT NOT NULL,
      created_at_ms INTEGER NOT NULL,
      updated_at_ms INTEGER NOT NULL,
      PRIMARY KEY(profile_id, slot),
      FOREIGN KEY(profile_id, resource_id)
        REFERENCES profile_resource_grants(profile_id, resource_id) ON DELETE CASCADE
    )''',
    '''CREATE TABLE profile_migration_journal (
      migration_id TEXT PRIMARY KEY,
      stage TEXT NOT NULL,
      payload_json TEXT NOT NULL,
      updated_at_ms INTEGER NOT NULL
    )''',
    '''CREATE TABLE IF NOT EXISTS webdav_sync_tombstone_outbox (
      id INTEGER PRIMARY KEY,
      namespace_id TEXT NOT NULL,
      origin_device_id TEXT NOT NULL,
      records_json TEXT NOT NULL,
      created_at_ms INTEGER NOT NULL
    )''',
    '''CREATE TABLE profile_data_generations (
      profile_id TEXT NOT NULL,
      generation INTEGER NOT NULL,
      state TEXT NOT NULL CHECK(state IN ('staging', 'visible', 'retired')),
      manifest_json TEXT NOT NULL,
      manifest_hash TEXT NOT NULL,
      created_at_ms INTEGER NOT NULL,
      updated_at_ms INTEGER NOT NULL,
      PRIMARY KEY(profile_id, generation),
      FOREIGN KEY(profile_id) REFERENCES user_profiles(id) ON DELETE CASCADE
    )''',
    '''CREATE UNIQUE INDEX one_visible_generation_per_profile
      ON profile_data_generations(profile_id) WHERE state = 'visible' ''',
    '''CREATE TABLE profile_restore_journal (
      restore_id TEXT PRIMARY KEY,
      mode TEXT NOT NULL CHECK(mode IN ('create', 'merge', 'registryReplace')),
      destination_profile_id TEXT,
      base_generation INTEGER,
      staged_generation INTEGER,
      stage TEXT NOT NULL,
      payload_json TEXT NOT NULL,
      updated_at_ms INTEGER NOT NULL,
      FOREIGN KEY(destination_profile_id) REFERENCES user_profiles(id) ON DELETE RESTRICT
    )''',
    '''CREATE TABLE profile_restore_resources (
      restore_id TEXT NOT NULL,
      resource_id TEXT NOT NULL,
      backup_id TEXT NOT NULL,
      type TEXT NOT NULL,
      label TEXT NOT NULL,
      owner_profile_id TEXT NOT NULL,
      public_config_json TEXT NOT NULL,
      sealed_secret_payload TEXT NOT NULL,
      secret_payload_version INTEGER NOT NULL,
      permissions INTEGER NOT NULL,
      binding_slot TEXT,
      profile_enabled INTEGER,
      profile_settings_json TEXT,
      resource_enabled INTEGER NOT NULL DEFAULT 1,
      PRIMARY KEY(restore_id, backup_id),
      UNIQUE(resource_id),
      FOREIGN KEY(restore_id) REFERENCES profile_restore_journal(restore_id)
        ON DELETE CASCADE,
      FOREIGN KEY(owner_profile_id) REFERENCES user_profiles(id) ON DELETE RESTRICT
    )''',
    '''CREATE TABLE job_ownership (
      backend TEXT NOT NULL,
      external_job_id TEXT NOT NULL,
      kind TEXT NOT NULL CHECK(kind IN ('download', 'recording', 'schedule', 'retry')),
      owner_profile_id TEXT,
      resource_id TEXT,
      profile_authorization_revision INTEGER NOT NULL,
      resource_authorization_revision INTEGER,
      created_at_ms INTEGER NOT NULL,
      terminal_at_ms INTEGER,
      detached_owner_token TEXT,
      PRIMARY KEY(backend, external_job_id),
      CHECK(owner_profile_id IS NOT NULL OR
        (terminal_at_ms IS NOT NULL AND detached_owner_token IS NOT NULL)),
      FOREIGN KEY(owner_profile_id) REFERENCES user_profiles(id) ON DELETE RESTRICT,
      FOREIGN KEY(resource_id) REFERENCES connection_resources(id) ON DELETE RESTRICT
    )''',
    '''CREATE TABLE owned_artifacts (
      id TEXT PRIMARY KEY,
      kind TEXT NOT NULL CHECK(kind IN ('download', 'recording')),
      owner_profile_id TEXT,
      canonical_path TEXT NOT NULL,
      ownership_state TEXT NOT NULL
        CHECK(ownership_state IN ('assigned', 'unassigned', 'detached')),
      detached_owner_token TEXT,
      size_bytes INTEGER,
      modified_at_ms INTEGER,
      created_at_ms INTEGER NOT NULL,
      UNIQUE(kind, canonical_path),
      CHECK((ownership_state = 'assigned' AND owner_profile_id IS NOT NULL) OR
        (ownership_state != 'assigned' AND owner_profile_id IS NULL)),
      FOREIGN KEY(owner_profile_id) REFERENCES user_profiles(id) ON DELETE RESTRICT
    )''',
    ..._secretChunkStatements,
  ];

  /// v5: sealed-payload overflow chunks.
  ///
  /// Android's OS SQLite delivers query results through a CursorWindow with a
  /// hard ~2MB per-ROW ceiling, and a file-imported IPTV playlist seals its
  /// whole M3U body — routinely tens of MB — into `sealed_secret_payload`.
  /// The write succeeds (writes don't cross a CursorWindow) and then EVERY
  /// read of the row throws, which took down not just that resource but any
  /// listing that materializes the column — one oversized playlist made every
  /// resource of the profile unreadable, and made migration fail its own
  /// read-back and strand the install in legacy mode (caught live via a
  /// photographed legacy-mode dialog).
  ///
  /// Envelopes above [_envelopeInlineMaxChars] are therefore split into
  /// chunk rows here, each far below the window, and the payload column holds
  /// a small `@chunks:v1:<n>` marker instead. Chunks rather than sidecar
  /// files on purpose: they ride inside the same transaction as their row,
  /// ON DELETE CASCADE cleans them wherever rows are deleted today, and a
  /// file-level copy of the database keeps them.
  ///
  /// tvOS is the one platform chunking does NOT rescue: its entire recovery
  /// snapshot must fit a bounded Keychain item, so an envelope this size can
  /// never be recoverable there no matter how it is stored — chunked rows
  /// inflate the snapshot exactly as inline ones did. tvOS therefore refuses
  /// oversized envelopes at the write APIs ([_guardTvOsEnvelopeBound]) instead
  /// of accepting one and poisoning every subsequent checkpoint.
  static const List<String> _secretChunkStatements = <String>[
    '''CREATE TABLE IF NOT EXISTS resource_secret_chunks (
      resource_id TEXT NOT NULL,
      seq INTEGER NOT NULL,
      chunk TEXT NOT NULL,
      PRIMARY KEY(resource_id, seq),
      FOREIGN KEY(resource_id) REFERENCES connection_resources(id) ON DELETE CASCADE
    )''',
    '''CREATE TABLE IF NOT EXISTS restore_secret_chunks (
      restore_id TEXT NOT NULL,
      backup_id TEXT NOT NULL,
      seq INTEGER NOT NULL,
      chunk TEXT NOT NULL,
      PRIMARY KEY(restore_id, backup_id, seq),
      FOREIGN KEY(restore_id, backup_id)
        REFERENCES profile_restore_resources(restore_id, backup_id)
        ON DELETE CASCADE
    )''',
  ];

  static Future<void> _createSecretChunkTables(DatabaseExecutor db) async {
    for (final statement in _secretChunkStatements) {
      await db.execute(statement);
    }
  }

  /// v5 repair: move every already-committed oversized INLINE envelope into
  /// its chunk table.
  ///
  /// These rows exist wherever a v4 install file-imported a large playlist:
  /// the INSERT succeeded and every whole-row read has thrown since. They
  /// cannot be read back normally even here — that read is the very crash —
  /// so each is pulled out through `substr()` slices, which fit the window
  /// because only the RESULT reaches it.
  static Future<void> _repairOversizedInlineEnvelopes(
    DatabaseExecutor db,
  ) async {
    Future<void> repair({
      required String sourceTable,
      required String chunkTable,
      required List<String> keyColumns,
      required Map<String, String> chunkKeyBySource,
    }) async {
      final keySelect = keyColumns.join(', ');
      final oversized = await db.rawQuery(
        '''SELECT $keySelect, length(sealed_secret_payload) AS payload_length
           FROM $sourceTable
           WHERE sealed_secret_payload IS NOT NULL
             AND length(sealed_secret_payload) > $_envelopeInlineMaxChars''',
      );
      for (final row in oversized) {
        final length = row['payload_length']! as int;
        final chunkCount =
            (length + _envelopeChunkChars - 1) ~/ _envelopeChunkChars;
        final where = keyColumns.map((c) => '$c = ?').join(' AND ');
        final whereArgs = [for (final c in keyColumns) row[c]!];
        final chunkKey = <String, Object?>{
          for (final entry in chunkKeyBySource.entries)
            entry.value: row[entry.key]!,
        };
        final chunkWhere = chunkKey.keys.map((c) => '$c = ?').join(' AND ');
        // One unrepairable row must not fail the whole upgrade. This runs
        // during bootstrap, so a throw here escapes to main() and the user
        // gets the startup-failure screen instead of an app — a total
        // lockout in exchange for a row that was ALREADY unreadable before
        // this repair existed. Leaving the payload inline is exactly the
        // state v4 shipped: still broken on Android's CursorWindow, still
        // perfectly readable everywhere else. Strictly better than refusing
        // to start, so each row is attempted independently.
        //
        // A skipped row is not stranded forever even though the schema
        // version does bump past this migration: every write path spills
        // through [_writeEnvelopeChunks], so the next rewrite of that
        // resource (a re-import, a credential rotation) chunks it properly.
        try {
          await _repairOneInlineEnvelope(
            db,
            sourceTable: sourceTable,
            chunkTable: chunkTable,
            chunkColumns: [...chunkKey.keys, 'seq', 'chunk'].join(', '),
            chunkKey: chunkKey,
            chunkWhere: chunkWhere,
            where: where,
            whereArgs: whereArgs,
            chunkCount: chunkCount,
          );
        } catch (error) {
          debugPrint(
            'ProfileRegistry: v5 chunk repair skipped a row in '
            '$sourceTable (${error.runtimeType})',
          );
          // The marker is written last, so the payload is still inline here.
          // Drop any chunks this attempt inserted, or the row would carry a
          // half-written body that no later read expects.
          try {
            await db.delete(
              chunkTable,
              where: chunkWhere,
              whereArgs: chunkKey.values.toList(growable: false),
            );
          } catch (_) {
            // The database itself is refusing writes; the upgrade will fail
            // on its own and retry next launch.
          }
        }
      }
    }

    await repair(
      sourceTable: 'connection_resources',
      chunkTable: 'resource_secret_chunks',
      keyColumns: const <String>['id'],
      chunkKeyBySource: const <String, String>{'id': 'resource_id'},
    );
    await repair(
      sourceTable: 'profile_restore_resources',
      chunkTable: 'restore_secret_chunks',
      keyColumns: const <String>['restore_id', 'backup_id'],
      chunkKeyBySource: const <String, String>{
        'restore_id': 'restore_id',
        'backup_id': 'backup_id',
      },
    );
  }

  /// Move ONE oversized inline envelope into [chunkTable]. Split out so the
  /// caller can attempt each row independently; see its call site for why a
  /// failure here is survivable.
  static Future<void> _repairOneInlineEnvelope(
    DatabaseExecutor db, {
    required String sourceTable,
    required String chunkTable,
    required String chunkColumns,
    required Map<String, Object?> chunkKey,
    required String chunkWhere,
    required String where,
    required List<Object> whereArgs,
    required int chunkCount,
  }) async {
    await db.delete(
      chunkTable,
      where: chunkWhere,
      whereArgs: chunkKey.values.toList(growable: false),
    );
    // ONE INSERT..SELECT per row, sliced by a recursive counter
    // (SQLite ≥ 3.8.3; the OS floor is 3.9). The slices are produced and
    // consumed natively — nothing here returns result rows, so nothing
    // crosses a CursorWindow OR the platform channel. Pulling the value
    // out slice-by-slice through rawQuery did the same repair with a
    // full re-materialization of the cell per round trip, which for the
    // motivating 50MB playlist was gigabytes of churn inside the
    // exclusive upgrade transaction — a first-boot hang for exactly the
    // stranded install this repair exists to rescue. substr() is 1-based.
    final keyPlaceholders = chunkKey.keys.map((_) => '?').join(', ');
    await db.execute(
      '''WITH RECURSIVE seq(i) AS (
           SELECT 0
           UNION ALL
           SELECT i + 1 FROM seq WHERE i + 1 < $chunkCount
         )
         INSERT INTO $chunkTable ($chunkColumns)
         SELECT $keyPlaceholders, i,
                substr((SELECT sealed_secret_payload FROM $sourceTable
                        WHERE $where),
                       i * $_envelopeChunkChars + 1, $_envelopeChunkChars)
         FROM seq''',
      <Object?>[...chunkKey.values, ...whereArgs],
    );
    // Last, so every earlier failure leaves the payload inline and the row
    // exactly as v4 left it (see the caller's recovery path).
    await db.rawUpdate(
      'UPDATE $sourceTable SET sealed_secret_payload = ? WHERE $where',
      <Object>['$_envelopeChunkMarkerPrefix$chunkCount', ...whereArgs],
    );
  }

  static Future<void> _createPinIntegrityTriggers(DatabaseExecutor db) async {
    for (final operation in const <String>['INSERT', 'UPDATE']) {
      await db.execute('''
        CREATE TRIGGER IF NOT EXISTS user_profiles_pin_all_or_none_${operation.toLowerCase()}
        BEFORE $operation ON user_profiles
        WHEN NOT (
          (NEW.pin_hash IS NULL AND NEW.pin_salt IS NULL AND NEW.pin_params_json IS NULL) OR
          (NEW.pin_hash IS NOT NULL AND NEW.pin_salt IS NOT NULL AND NEW.pin_params_json IS NOT NULL)
        )
        BEGIN
          SELECT RAISE(ABORT, 'profile PIN fields must be all-null or all-present');
        END
      ''');
    }
  }

  static Future<void> _createRestoreResourceTable(DatabaseExecutor db) async {
    await db.execute(
      _schemaStatements.firstWhere(
        (statement) =>
            statement.contains('CREATE TABLE profile_restore_resources'),
      ),
    );
  }

  Future<void> close() => _db.close();

  /// Drains only rows whose registry deletion transaction has committed.
  /// Recording is idempotent; a crash after the file write but before the row
  /// delete safely repeats the same tombstones on the next drain.
  Future<bool> drainWebDavSyncTombstoneOutbox() =>
      _tombstoneOutboxDrainLock.synchronized(() async {
        final rows = await _db.query(
          'webdav_sync_tombstone_outbox',
          orderBy: 'id',
        );
        for (final row in rows) {
          final decoded = jsonDecode(row['records_json']! as String);
          if (decoded is! List) {
            throw const FormatException(
              'Invalid registry tombstone outbox row',
            );
          }
          final records = decoded
              .map(WebDavSyncRegistryRecordId.fromJson)
              .toSet();
          await WebDavSyncTombstoneRecorder.drainRegistryOutboxBatch(
            target: WebDavSyncRegistryTombstoneOutboxTarget(
              namespaceId: row['namespace_id']! as String,
              deviceId: row['origin_device_id']! as String,
            ),
            records: records,
            timeMs: row['created_at_ms']! as int,
          );
          await _db.delete(
            'webdav_sync_tombstone_outbox',
            where: 'id = ?',
            whereArgs: <Object>[row['id']!],
          );
        }
        final remaining = Sqflite.firstIntValue(
          await _db.rawQuery(
            'SELECT COUNT(*) FROM webdav_sync_tombstone_outbox',
          ),
        );
        return remaining == 0;
      });

  Future<void> _finishRegistryDelete() async {
    try {
      await drainWebDavSyncTombstoneOutbox();
    } catch (error) {
      debugPrint(
        'WebDAV registry tombstone outbox drain deferred '
        '(${error.runtimeType})',
      );
    }
    await checkpointTvOsRecovery(webDavSyncRegistryChange: true);
  }

  Future<String> exportRecoverySnapshot() async {
    final tables = <String, Object?>{};
    // One transaction across every table: a secret's marker row and its
    // chunk rows live in different tables now, and a rotation committing
    // between two bare reads would snapshot one secret's marker with
    // another's body — a pairing the count check cannot always catch.
    await _db.transaction((txn) async {
      for (final table in _recoveryTables) {
        final rows = await txn.query(table);
        tables[table] = rows
            .map(
              (row) => row.map(
                (key, value) => MapEntry<String, Object?>(
                  key,
                  value is Uint8List
                      ? <String, Object?>{'blob': base64Encode(value)}
                      : value,
                ),
              ),
            )
            .toList(growable: false);
      }
    });
    return jsonEncode(<String, Object?>{
      'version': 1,
      'schemaVersion': schemaVersion,
      'tables': tables,
      'preferences': await _exportTvOsRecoverablePreferences(),
    });
  }

  /// Snapshot schema versions this build can ingest. The FLOOR matters as
  /// much as the ceiling: the Keychain snapshot on a device was written by
  /// whatever build ran last, and bootstrap imports it unconditionally on
  /// every launch — an exact-match check here turned every schema bump into
  /// a tvOS boot loop, because the first post-update launch met the previous
  /// build's snapshot, threw out of main(), and died before any checkpoint
  /// could republish a current one. Newer-than-us stays fatal: rows from a
  /// future schema may not fit these tables.
  static const int _minSupportedSnapshotSchema = 3;

  Future<void> importRecoverySnapshot(String source) async {
    final decoded = jsonDecode(source);
    final snapshotSchema = decoded is Map ? decoded['schemaVersion'] : null;
    if (decoded is! Map ||
        decoded['version'] != 1 ||
        snapshotSchema is! int ||
        snapshotSchema < _minSupportedSnapshotSchema ||
        snapshotSchema > schemaVersion ||
        decoded['tables'] is! Map) {
      throw const FormatException('Unsupported profile recovery snapshot');
    }
    final tables = decoded['tables']! as Map;
    for (final table in _recoveryTables) {
      if (tables[table] is List) continue;
      // A table this snapshot's schema had not grown yet is EMPTY, not
      // missing — the v4 snapshot on an updated device predates the chunk
      // tables and must still boot.
      if ((snapshotSchema < 5 &&
              const <String>{
                'resource_secret_chunks',
                'restore_secret_chunks',
              }.contains(table)) ||
          (snapshotSchema < 8 && table == 'webdav_sync_tombstone_outbox')) {
        continue;
      }
      throw FormatException('Recovery snapshot is missing $table');
    }
    await _db.transaction((txn) async {
      for (final table in _recoveryTables.reversed) {
        await txn.delete(table);
      }
      for (final table in _recoveryTables) {
        for (final raw in (tables[table] as List? ?? const <Object?>[])) {
          if (raw is! Map) throw const FormatException('Invalid recovery row');
          final row = <String, Object?>{};
          for (final entry in raw.entries) {
            final value = entry.value;
            row[entry.key as String] =
                value is Map && value.length == 1 && value['blob'] is String
                ? Uint8List.fromList(base64Decode(value['blob']! as String))
                : value;
          }
          await txn.insert(table, row);
        }
      }
      await _assertAdminInvariant(txn);
      // An older snapshot can carry envelopes as oversized INLINE columns
      // (that is exactly what v4 stored). Chunk them on the way in, so the
      // imported registry obeys the same invariant as a native v5 one.
      if (snapshotSchema < 5) {
        await _repairOversizedInlineEnvelopes(txn);
      }
    });
    await _importTvOsRecoverablePreferences(
      decoded['preferences'],
      tables['user_profiles']! as List,
    );
  }

  Future<Map<String, Object?>> _exportTvOsRecoverablePreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final profiles = await _db.query(
      'user_profiles',
      columns: const <String>['id', 'visible_data_generation'],
    );
    final allowedPrefixes = profiles
        .map((row) => 'p.${row['id']}.g.${row['visible_data_generation']}.')
        .toSet();
    // Everything eligible is gathered first, then packed smallest-first, so
    // scalar settings and credentials always fit and only the largest
    // collections fall out of a full envelope. Nothing throws here: every
    // checkpoint runs inside a preference write, so a thrown bound would fail
    // every subsequent save — and the import spares live keys the export had
    // to drop, so a skip is never a deletion, only "not checkpointed yet".
    final candidates = <({String key, Object? value, int bytes})>[];
    for (final key in prefs.getKeys()) {
      final match = _scopedPreferencePattern.firstMatch(key);
      if (match == null ||
          !allowedPrefixes.any(key.startsWith) ||
          !_recoverablePreference(match.group(1)!)) {
        continue;
      }
      final value = prefs.get(key);
      if (value is! bool &&
          value is! int &&
          value is! double &&
          value is! String &&
          value is! List<String>) {
        continue;
      }
      final bytes =
          utf8.encode(key).length + utf8.encode(jsonEncode(value)).length;
      candidates.add((key: key, value: value, bytes: bytes));
    }
    candidates.sort(
      (a, b) => a.bytes != b.bytes
          ? a.bytes.compareTo(b.bytes)
          : a.key.compareTo(b.key),
    );
    final result = <String, Object?>{};
    var encodedBytes = 0;
    var skipped = 0;
    for (final candidate in candidates) {
      if (candidate.bytes > TvOsRecoveryLimits.envelopeValueBytes ||
          result.length >= TvOsRecoveryLimits.envelopeMaxEntries ||
          encodedBytes + candidate.bytes >
              TvOsRecoveryLimits.envelopeTotalBytes) {
        skipped++;
        continue;
      }
      encodedBytes += candidate.bytes;
      result[candidate.key] = candidate.value;
    }
    if (skipped > 0) {
      debugPrint(
        'tvOS recovery envelope: $skipped preference value(s) too large to '
        'checkpoint; they stay local and are spared by the launch rebuild.',
      );
    }
    return result;
  }

  static Future<void> _importTvOsRecoverablePreferences(
    Object? source,
    List profileRows,
  ) async {
    if (source == null) return;
    if (source is! Map || source.length > 4096) {
      throw const FormatException('Invalid tvOS recovery preferences');
    }
    final allowedPrefixes = <String>{};
    for (final raw in profileRows) {
      if (raw is! Map ||
          raw['id'] is! String ||
          raw['visible_data_generation'] is! int) {
        throw const FormatException('Invalid tvOS recovery profile row');
      }
      allowedPrefixes.add(
        'p.${raw['id']}.g.${raw['visible_data_generation']}.',
      );
    }
    final normalized = <String, Object?>{};
    var encodedBytes = 0;
    for (final entry in source.entries) {
      final key = entry.key;
      final value = entry.value;
      if (key is! String ||
          !allowedPrefixes.any(key.startsWith) ||
          _scopedPreferencePattern.firstMatch(key) == null ||
          (value is! bool &&
              value is! int &&
              value is! double &&
              value is! String &&
              value is! List)) {
        throw const FormatException('Invalid tvOS recovery preference');
      }
      final Object normalizedValue;
      if (value is List) {
        if (value.any((item) => item is! String)) {
          throw const FormatException('Invalid tvOS recovery string list');
        }
        normalizedValue = value.cast<String>().toList(growable: false);
      } else {
        normalizedValue = value as Object;
      }
      final bytes = utf8.encode(jsonEncode(normalizedValue)).length;
      encodedBytes += utf8.encode(key).length + bytes;
      if (bytes > TvOsRecoveryLimits.envelopeValueBytes ||
          encodedBytes > TvOsRecoveryLimits.envelopeTotalBytes) {
        throw const FormatException('tvOS recovery preferences exceed bounds');
      }
      normalized[key] = normalizedValue;
    }
    final prefs = await SharedPreferences.getInstance();
    for (final key in prefs.getKeys().where(
      (key) => _scopedPreferencePattern.hasMatch(key),
    )) {
      // Live current-generation keys are never cleared: a key absent from the
      // envelope is either a droppable cache or something the export had to
      // skip (oversized value, full envelope), and an export skip must never
      // become an import deletion. Envelope keys are overwritten below
      // anyway. Only stale-generation keys — deleted profiles, superseded
      // generations — still clear.
      if (allowedPrefixes.any(key.startsWith)) continue;
      if (!await prefs.remove(key)) {
        throw StateError('Could not clear stale tvOS preference projection');
      }
    }
    for (final entry in normalized.entries) {
      final success = switch (entry.value) {
        bool value => await prefs.setBool(entry.key, value),
        int value => await prefs.setInt(entry.key, value),
        double value => await prefs.setDouble(entry.key, value),
        String value => await prefs.setString(entry.key, value),
        List<String> value => await prefs.setStringList(entry.key, value),
        _ => false,
      };
      if (!success) throw StateError('Could not rebuild tvOS preferences');
    }
  }

  /// Durable by default. Only explicitly named re-fetchable caches are kept
  /// out of the envelope — the previous name-pattern blocklist made
  /// durability an accident of naming and silently wiped user-authored data
  /// (My Watchlist, channel favorites, settings toggles whose names happened
  /// to contain `history`/`favorite`/`continue_watching`) on every tvOS
  /// launch. Over-including is safe: the size-ordered export skips the
  /// largest values when full, and the import never deletes a live key.
  static bool _recoverablePreference(String logicalKey) =>
      !_droppableCachePreference.hasMatch(logicalKey);

  static final RegExp _scopedPreferencePattern = RegExp(
    r'^p\.[A-Za-z0-9][A-Za-z0-9._-]{0,95}\.g\.[1-9][0-9]*\.(.+)$',
  );
  static final RegExp _droppableCachePreference = RegExp(
    r'(cache|^tvmaze_|^epg_|^trakt_continue_watching_)',
    caseSensitive: false,
  );

  Future<void> checkpointTvOsRecovery({
    bool webDavSyncRegistryChange = false,
  }) async {
    if (TvOsProfileRecoveryStore.supported) {
      final prior = _recoveryCheckpoint;
      final checkpoint = () async {
        try {
          await prior;
        } catch (_) {
          // A later complete snapshot can repair a failed publication.
        }
        await TvOsProfileRecoveryStore.publish(await exportRecoverySnapshot());
      }();
      _recoveryCheckpoint = checkpoint;
      await checkpoint;
    }
    await authorityChangedCallback?.call();
    if (webDavSyncRegistryChange) {
      final localProfileId =
          ProfileRuntime.isInitialized && ProfileRuntime.isProfileCommitted
          ? ProfileRuntime.capture().profileId
          : '';
      ProfilePreferences.notifyWebDavSyncLocalChange(
        localProfileId,
        ProfilePreferences.webDavSyncRegistryLogicalKey,
      );
    }
  }

  Future<UserProfile> createProfile({
    required String name,
    required UserProfileRole role,
    ProfilePolicy? policy,
    String? avatarKey,
    String? id,
    bool setupComplete = false,
    bool disabled = false,
    bool lockOnResume = false,
    int? inactivityTimeoutMinutes,
    // Original creation instant carried through backup restore / sync
    // adoption so the profile list keeps the seed device's order. Ignored
    // unless plausibly in the past; row bookkeeping still stamps `now`.
    int? createdAtMs,
    UserProfileLifecycle lifecycle = UserProfileLifecycle.active,
    String? actingProfileId,
    int? actingAuthorizationRevision,
    int? actingSessionEpoch,
  }) async {
    final normalizedName = name.trim();
    if (normalizedName.isEmpty) throw ArgumentError.value(name, 'name');
    _validateInactivityTimeout(inactivityTimeoutMinutes);
    final profileId = id ?? _newId();
    if (!ProfileScope.isValidProfileId(profileId)) {
      throw ArgumentError.value(profileId, 'id', 'Unsafe profile ID');
    }
    await authorityWillChangeCallback?.call();
    final now = DateTime.now().millisecondsSinceEpoch;
    final effectiveCreatedAt =
        (createdAtMs != null && createdAtMs > 0 && createdAtMs <= now)
        ? createdAtMs
        : now;
    final effectivePolicy = policy ?? ProfilePolicy.defaultsFor(role);
    await _db.transaction((txn) async {
      await _assertManagingActor(
        txn,
        actingProfileId,
        actingAuthorizationRevision,
        actingSessionEpoch,
      );
      await txn.insert('user_profiles', <String, Object?>{
        'id': profileId,
        'name': normalizedName,
        'avatar_key': avatarKey,
        'role': role.name,
        'policy_json': effectivePolicy.encode(),
        'policy_schema_version': effectivePolicy.schemaVersion,
        'authorization_revision': 1,
        'lifecycle_state': lifecycle.name,
        'visible_data_generation': 1,
        'profile_setup_complete': setupComplete ? 1 : 0,
        'pin_reset_required': 0,
        'lock_on_resume': lockOnResume ? 1 : 0,
        if (inactivityTimeoutMinutes != null)
          'inactivity_timeout_minutes': inactivityTimeoutMinutes,
        'created_at_ms': effectiveCreatedAt,
        'updated_at_ms': now,
        if (disabled) 'disabled_at_ms': now,
      });
      await txn.insert('profile_data_generations', <String, Object?>{
        'profile_id': profileId,
        'generation': 1,
        'state': 'visible',
        'manifest_json': '{}',
        'manifest_hash': '',
        'created_at_ms': now,
        'updated_at_ms': now,
      });
      await _seedDefaultGrantsForProfile(txn, profileId, now);
    });
    await checkpointTvOsRecovery(webDavSyncRegistryChange: true);
    return (await getProfile(profileId))!;
  }

  Future<List<UserProfile>> listProfiles({
    bool includeDisabled = false,
    bool includeStaging = false,
  }) async {
    final clauses = <String>[
      if (!includeDisabled) 'disabled_at_ms IS NULL',
      if (!includeStaging) "lifecycle_state = 'active'",
    ];
    final rows = await _db.query(
      'user_profiles',
      where: clauses.isEmpty ? null : clauses.join(' AND '),
      orderBy: 'created_at_ms, id',
    );
    return rows.map(_decodeProfile).toList(growable: false);
  }

  Future<UserProfile?> getProfile(String id) async {
    final rows = await _db.query(
      'user_profiles',
      where: 'id = ?',
      whereArgs: <Object>[id],
      limit: 1,
    );
    return rows.isEmpty ? null : _decodeProfile(rows.single);
  }

  Future<String?> getActiveProfileId() async {
    final rows = await _db.query(
      'device_state',
      columns: <String>['active_profile_id'],
      where: 'singleton_id = 1',
      limit: 1,
    );
    return rows.isEmpty ? null : rows.single['active_profile_id'] as String?;
  }

  Future<bool> activationInProgress() async {
    final rows = await _db.query(
      'device_state',
      columns: const <String>['activation_state_json'],
      where: 'singleton_id = 1',
      limit: 1,
    );
    return rows.isNotEmpty && rows.single['activation_state_json'] != null;
  }

  Future<void> initializeDeviceState({
    String? activeProfileId,
    required String bootstrapState,
    required String migrationState,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.insert('device_state', <String, Object?>{
      'singleton_id': 1,
      'schema_version': schemaVersion,
      'bootstrap_state': bootstrapState,
      'migration_state': migrationState,
      'active_profile_id': activeProfileId,
      'registry_generation': 1,
      'activation_revision': 0,
      'updated_at_ms': now,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    await checkpointTvOsRecovery();
  }

  Future<void> commitBootstrap({
    required String activeProfileId,
    required bool migratedLegacyInstall,
    Map<String, Object?> migrationPayload = const <String, Object?>{},
  }) async {
    await authorityWillChangeCallback?.call();
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.transaction((txn) async {
      final profileRows = await txn.rawQuery(
        '''SELECT p.role, p.policy_json, p.lifecycle_state,
                  p.visible_data_generation, g.generation
           FROM user_profiles p
           INNER JOIN profile_data_generations g
             ON g.profile_id = p.id
            AND g.generation = p.visible_data_generation
            AND g.state = 'visible'
           WHERE p.id = ? AND p.disabled_at_ms IS NULL''',
        <Object>[activeProfileId],
      );
      if (profileRows.isEmpty) throw StateError('Bootstrap profile is invalid');
      final role = UserProfileRole.values.byName(
        profileRows.single['role']! as String,
      );
      final policy = ProfilePolicy.decode(
        profileRows.single['policy_json']! as String,
        role,
      );
      if (role != UserProfileRole.admin ||
          !policy.allows(role, ProfileFeature.manageProfiles)) {
        throw StateError('Bootstrap profile must be a managing Admin');
      }
      await txn.update(
        'user_profiles',
        <String, Object?>{
          'lifecycle_state': UserProfileLifecycle.active.name,
          'updated_at_ms': now,
        },
        where: 'id = ?',
        whereArgs: <Object>[activeProfileId],
      );
      await txn.insert('device_state', <String, Object?>{
        'singleton_id': 1,
        'schema_version': schemaVersion,
        'bootstrap_state': 'ready',
        'migration_state': 'committed',
        'active_profile_id': activeProfileId,
        'registry_generation': 1,
        'activation_revision': 1,
        'updated_at_ms': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await txn.insert('profile_migration_journal', <String, Object?>{
        'migration_id': migratedLegacyInstall
            ? 'legacy-to-admin-v1'
            : 'fresh-install-v1',
        'stage': 'committed',
        'payload_json': jsonEncode(<String, Object?>{
          'profileId': activeProfileId,
          'legacyRetained': migratedLegacyInstall,
          ...migrationPayload,
        }),
        'updated_at_ms': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
    await checkpointTvOsRecovery();
  }

  Future<UserProfile?> activeProfile() async {
    final id = await getActiveProfileId();
    return id == null ? null : getProfile(id);
  }

  Future<Map<String, dynamic>?> migrationJournal(String migrationId) async {
    final rows = await _db.query(
      'profile_migration_journal',
      where: 'migration_id = ?',
      whereArgs: <Object>[migrationId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return <String, dynamic>{
      'stage': rows.single['stage'],
      'payload': jsonDecode(rows.single['payload_json']! as String),
      'updatedAtMs': rows.single['updated_at_ms'],
    };
  }

  Future<void> writeMigrationJournal({
    required String migrationId,
    required String stage,
    Map<String, dynamic> payload = const <String, dynamic>{},
  }) async {
    await _db.insert('profile_migration_journal', <String, Object?>{
      'migration_id': migrationId,
      'stage': stage,
      'payload_json': jsonEncode(payload),
      'updated_at_ms': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    await checkpointTvOsRecovery();
  }

  Future<void> setActiveProfile(String id) async {
    final profile = await getProfile(id);
    if (profile == null ||
        !profile.isEnabled ||
        profile.lifecycle != UserProfileLifecycle.active) {
      throw StateError('Profile is not eligible for activation');
    }
    await authorityWillChangeCallback?.call();
    final now = DateTime.now().millisecondsSinceEpoch;
    final changed = await _db.rawUpdate(
      '''UPDATE device_state
         SET active_profile_id = ?, activation_revision = activation_revision + 1,
             updated_at_ms = ? WHERE singleton_id = 1''',
      <Object>[id, now],
    );
    if (changed != 1) throw StateError('Device state is not initialized');
    await checkpointTvOsRecovery();
  }

  Future<void> beginActivation({
    required String previousProfileId,
    required String targetProfileId,
    required int nextSessionEpoch,
  }) async {
    await authorityWillChangeCallback?.call();
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.transaction((txn) async {
      final rows = await txn.query(
        'device_state',
        columns: const <String>['active_profile_id', 'activation_revision'],
        where: 'singleton_id = 1',
        limit: 1,
      );
      if (rows.isEmpty ||
          rows.single['active_profile_id'] != previousProfileId) {
        throw StateError('Active profile changed during activation');
      }
      final target = await txn.query(
        'user_profiles',
        columns: const <String>['id'],
        where:
            "id = ? AND disabled_at_ms IS NULL AND lifecycle_state = 'active'",
        whereArgs: <Object>[targetProfileId],
        limit: 1,
      );
      if (target.isEmpty) throw StateError('Target profile is unavailable');
      await txn.update('device_state', <String, Object?>{
        'activation_state_json': jsonEncode(<String, Object>{
          'previousProfileId': previousProfileId,
          'targetProfileId': targetProfileId,
          'nextSessionEpoch': nextSessionEpoch,
          'nextRevision': (rows.single['activation_revision']! as int) + 1,
          'stage': 'preparing',
        }),
        'updated_at_ms': now,
      }, where: 'singleton_id = 1');
    });
    await checkpointTvOsRecovery();
  }

  Future<void> commitActivation({
    required String targetProfileId,
    bool completeOnboarding = false,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.transaction((txn) async {
      final rows = await txn.query(
        'device_state',
        columns: const <String>['activation_state_json'],
        where: 'singleton_id = 1',
        limit: 1,
      );
      if (rows.isEmpty || rows.single['activation_state_json'] == null) {
        throw StateError('No activation is being prepared');
      }
      final state = jsonDecode(rows.single['activation_state_json']! as String);
      if (state is! Map || state['targetProfileId'] != targetProfileId) {
        throw StateError('Activation target does not match journal');
      }
      if (completeOnboarding) {
        final completed = await txn.update(
          'user_profiles',
          <String, Object?>{'profile_setup_complete': 1, 'updated_at_ms': now},
          where:
              "id = ? AND disabled_at_ms IS NULL AND lifecycle_state = 'active'",
          whereArgs: <Object>[targetProfileId],
        );
        if (completed != 1) {
          throw StateError('Activation target is unavailable');
        }
      }
      final activated = await txn.rawUpdate(
        '''UPDATE device_state
           SET active_profile_id = ?,
               activation_revision = activation_revision + 1,
               activation_state_json = NULL,
               updated_at_ms = ?
           WHERE singleton_id = 1''',
        <Object>[targetProfileId, now],
      );
      if (activated != 1) {
        throw StateError('Device state is not initialized');
      }
    });
    await checkpointTvOsRecovery();
  }

  Future<void> abortActivation() async {
    await _db.update('device_state', <String, Object?>{
      'activation_state_json': null,
      'updated_at_ms': DateTime.now().millisecondsSinceEpoch,
    }, where: 'singleton_id = 1');
    await checkpointTvOsRecovery();
  }

  /// A process death before commit leaves the previous active profile
  /// authoritative. Bootstrap discards only the incomplete preparation.
  Future<void> recoverInterruptedActivation() => abortActivation();

  Future<void> deleteProfile(
    String id, {
    Iterable<WebDavSyncRegistryRecordId> mergedBaselineRecords =
        const <WebDavSyncRegistryRecordId>[],
  }) async {
    await authorityWillChangeCallback?.call();
    await _db.transaction((txn) async {
      final activeRows = await txn.rawQuery(
        'SELECT active_profile_id FROM device_state WHERE singleton_id = 1',
      );
      final active = activeRows.isEmpty
          ? null
          : activeRows.single['active_profile_id'] as String?;
      if (active == id) throw StateError('Cannot delete the active profile');
      final row = (await txn.query(
        'user_profiles',
        columns: <String>['role', 'disabled_at_ms', 'lifecycle_state'],
        where: 'id = ?',
        whereArgs: <Object>[id],
      )).singleOrNull;
      if (row == null) return;
      final device = await txn.query(
        'device_state',
        columns: const <String>['migration_state'],
        where: 'singleton_id = 1',
        limit: 1,
      );
      if (device.isNotEmpty &&
          device.single['migration_state'] == 'committed' &&
          row['lifecycle_state'] != UserProfileLifecycle.staging.name) {
        throw StateError(
          'Committed profiles require an authorized deletion disposition',
        );
      }
      if (row['role'] == UserProfileRole.admin.name &&
          row['disabled_at_ms'] == null) {
        await _assertAdminInvariant(txn, excludingProfileId: id);
      }
      await _recordRegistryDeleteCascade(
        txn,
        profileIds: <String>{id},
        mergedBaselineRecords: mergedBaselineRecords,
      );
      await txn.delete(
        'user_profiles',
        where: 'id = ?',
        whereArgs: <Object>[id],
      );
    });
    await _finishRegistryDelete();
  }

  Future<UserProfile> updateProfile({
    required String id,
    String? name,
    String? avatarKey,
    UserProfileRole? role,
    ProfilePolicy? policy,
    bool? lockOnResume,
    int? inactivityTimeoutMinutes,
    bool clearInactivityTimeout = false,
    String? actingProfileId,
    int? actingAuthorizationRevision,
    int? actingSessionEpoch,
  }) async {
    if (name != null && name.trim().isEmpty) {
      throw ArgumentError.value(name, 'name');
    }
    _validateInactivityTimeout(inactivityTimeoutMinutes);
    await authorityWillChangeCallback?.call();
    await _db.transaction((txn) async {
      await _assertManagingActor(
        txn,
        actingProfileId,
        actingAuthorizationRevision,
        actingSessionEpoch,
      );
      final rows = await txn.query(
        'user_profiles',
        where: 'id = ? AND disabled_at_ms IS NULL',
        whereArgs: <Object>[id],
        limit: 1,
      );
      if (rows.isEmpty) throw StateError('Profile does not exist');
      final current = _decodeProfile(rows.single);
      final nextRole = role ?? current.role;
      final nextPolicy = policy ?? current.policy;
      await txn.update(
        'user_profiles',
        <String, Object?>{
          if (name != null) 'name': name.trim(),
          if (avatarKey != null) 'avatar_key': avatarKey,
          'role': nextRole.name,
          'policy_json': nextPolicy.encode(),
          'policy_schema_version': nextPolicy.schemaVersion,
          'authorization_revision': current.authorizationRevision + 1,
          if (lockOnResume != null) 'lock_on_resume': lockOnResume ? 1 : 0,
          if (clearInactivityTimeout) 'inactivity_timeout_minutes': null,
          if (!clearInactivityTimeout && inactivityTimeoutMinutes != null)
            'inactivity_timeout_minutes': inactivityTimeoutMinutes,
          'updated_at_ms': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: <Object>[id],
      );
      await _assertAdminInvariant(txn);
    });
    await checkpointTvOsRecovery(webDavSyncRegistryChange: true);
    return (await getProfile(id))!;
  }

  static void _validateInactivityTimeout(int? minutes) {
    if (minutes != null && !const <int>{5, 15, 30, 60}.contains(minutes)) {
      throw ArgumentError.value(
        minutes,
        'inactivityTimeoutMinutes',
        'Unsupported auto-lock interval',
      );
    }
  }

  Future<UserProfile> completeProfileSetup(
    String id, {
    String? actingProfileId,
    int? actingAuthorizationRevision,
    int? actingSessionEpoch,
  }) async {
    await authorityWillChangeCallback?.call();
    var changed = 0;
    await _db.transaction((txn) async {
      await _assertManagingActor(
        txn,
        actingProfileId,
        actingAuthorizationRevision,
        actingSessionEpoch,
      );
      changed = await txn.update(
        'user_profiles',
        <String, Object?>{
          'lifecycle_state': UserProfileLifecycle.active.name,
          'profile_setup_complete': 1,
          'updated_at_ms': DateTime.now().millisecondsSinceEpoch,
        },
        where:
            "id = ? AND disabled_at_ms IS NULL AND lifecycle_state = 'staging'",
        whereArgs: <Object>[id],
      );
    });
    if (changed != 1) throw StateError('Staging profile is unavailable');
    await checkpointTvOsRecovery(webDavSyncRegistryChange: true);
    return (await getProfile(id))!;
  }

  /// Updates onboarding readiness for the active profile itself.
  ///
  /// This is deliberately separate from [completeProfileSetup], which is an
  /// Admin operation that publishes a newly-created staging profile. Once a
  /// profile is active, finishing or skipping onboarding is a local session
  /// action and must not require the profile to be an Admin.
  Future<UserProfile> setActiveProfileSetupComplete({
    required String profileId,
    required bool setupComplete,
    required int actingAuthorizationRevision,
    required int actingSessionEpoch,
  }) async {
    var changed = 0;
    await _db.transaction((txn) async {
      await _assertActiveSessionActor(
        txn,
        profileId: profileId,
        authorizationRevision: actingAuthorizationRevision,
        sessionEpoch: actingSessionEpoch,
      );
      changed = await txn.update(
        'user_profiles',
        <String, Object?>{
          'profile_setup_complete': setupComplete ? 1 : 0,
          'updated_at_ms': DateTime.now().millisecondsSinceEpoch,
        },
        where:
            "id = ? AND disabled_at_ms IS NULL AND lifecycle_state = 'active'",
        whereArgs: <Object>[profileId],
      );
    });
    if (changed != 1) throw StateError('Active profile is unavailable');
    await checkpointTvOsRecovery(webDavSyncRegistryChange: true);
    return (await getProfile(profileId))!;
  }

  /// Changes only the unlocked active profile's display identity.
  ///
  /// This deliberately does not share [updateProfile]: that method is an
  /// Admin boundary capable of changing roles, policy and lock behavior. A
  /// self-service caller cannot name another target, and name/avatar changes
  /// do not bump the authorization revision because they grant no authority.
  Future<UserProfile> updateActiveProfileIdentity({
    required String profileId,
    required String name,
    required String? avatarKey,
    required int actingAuthorizationRevision,
    required int actingSessionEpoch,
  }) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty || trimmedName.length > 40) {
      throw ArgumentError.value(
        name,
        'name',
        'Name must contain 1–40 characters',
      );
    }
    var changed = 0;
    await _db.transaction((txn) async {
      await _assertActiveSessionActor(
        txn,
        profileId: profileId,
        authorizationRevision: actingAuthorizationRevision,
        sessionEpoch: actingSessionEpoch,
      );
      changed = await txn.update(
        'user_profiles',
        <String, Object?>{
          'name': trimmedName,
          'avatar_key': avatarKey,
          'updated_at_ms': DateTime.now().millisecondsSinceEpoch,
        },
        where:
            "id = ? AND disabled_at_ms IS NULL AND lifecycle_state = 'active'",
        whereArgs: <Object>[profileId],
      );
    });
    if (changed != 1) throw StateError('Active profile is unavailable');
    await checkpointTvOsRecovery(webDavSyncRegistryChange: true);
    return (await getProfile(profileId))!;
  }

  Future<void> disableProfile(
    String id, {
    String? actingProfileId,
    int? actingAuthorizationRevision,
    int? actingSessionEpoch,
  }) async {
    await authorityWillChangeCallback?.call();
    await _db.transaction((txn) async {
      await _assertManagingActor(
        txn,
        actingProfileId,
        actingAuthorizationRevision,
        actingSessionEpoch,
      );
      final activeRows = await txn.query(
        'device_state',
        columns: const <String>['active_profile_id'],
        where: 'singleton_id = 1',
        limit: 1,
      );
      if (activeRows.isNotEmpty &&
          activeRows.single['active_profile_id'] == id) {
        throw StateError('Cannot disable the active profile');
      }
      final now = DateTime.now().millisecondsSinceEpoch;
      final changed = await txn.update(
        'user_profiles',
        <String, Object?>{'disabled_at_ms': now, 'updated_at_ms': now},
        where: 'id = ? AND disabled_at_ms IS NULL',
        whereArgs: <Object>[id],
      );
      if (changed != 1) throw StateError('Profile does not exist');
      await _assertAdminInvariant(txn);
    });
    await checkpointTvOsRecovery(webDavSyncRegistryChange: true);
  }

  Future<void> enableProfile(
    String id, {
    String? actingProfileId,
    int? actingAuthorizationRevision,
    int? actingSessionEpoch,
  }) async {
    await authorityWillChangeCallback?.call();
    var changed = 0;
    await _db.transaction((txn) async {
      await _assertManagingActor(
        txn,
        actingProfileId,
        actingAuthorizationRevision,
        actingSessionEpoch,
      );
      changed = await txn.rawUpdate(
        '''UPDATE user_profiles SET disabled_at_ms = NULL,
             authorization_revision = authorization_revision + 1,
             updated_at_ms = ? WHERE id = ? AND disabled_at_ms IS NOT NULL''',
        <Object>[DateTime.now().millisecondsSinceEpoch, id],
      );
    });
    if (changed != 1) throw StateError('Disabled profile does not exist');
    await checkpointTvOsRecovery(webDavSyncRegistryChange: true);
  }

  Future<ProfileDeletionDependencies> deletionDependencies(String id) async {
    final jobs =
        Sqflite.firstIntValue(
          await _db.rawQuery(
            '''SELECT COUNT(DISTINCT j.backend || ':' || j.external_job_id)
               FROM job_ownership j
               LEFT JOIN connection_resources r ON r.id = j.resource_id
               WHERE (j.owner_profile_id = ? OR r.owner_profile_id = ?)
                 AND j.terminal_at_ms IS NULL''',
            <Object>[id, id],
          ),
        ) ??
        0;
    final resources =
        Sqflite.firstIntValue(
          await _db.rawQuery(
            'SELECT COUNT(*) FROM connection_resources WHERE owner_profile_id = ?',
            <Object>[id],
          ),
        ) ??
        0;
    final sharedResources =
        Sqflite.firstIntValue(
          await _db.rawQuery(
            '''SELECT COUNT(DISTINCT r.id) FROM connection_resources r
               INNER JOIN profile_resource_grants g ON g.resource_id = r.id
               WHERE r.owner_profile_id = ? AND g.profile_id != ?''',
            <Object>[id, id],
          ),
        ) ??
        0;
    final artifacts =
        Sqflite.firstIntValue(
          await _db.rawQuery(
            'SELECT COUNT(*) FROM owned_artifacts WHERE owner_profile_id = ?',
            <Object>[id],
          ),
        ) ??
        0;
    return ProfileDeletionDependencies(
      activeJobs: jobs,
      ownedResources: resources,
      sharedResources: sharedResources,
      publicArtifacts: artifacts,
    );
  }

  /// Revokes every grant and binding OTHER profiles hold on resources owned
  /// by [ownerProfileId]. This is the deletion dialog's "revoke shared
  /// access" path — a managing-Admin convenience equal to editing each
  /// borrower by hand, which unblocks retiring a profile whose only shares
  /// are auto-seeded defaults (the post-restore scaffold admin). Borrowers'
  /// authorization revisions are bumped so their live sessions revalidate.
  Future<int> revokeGrantsOnOwnedResources({
    required String ownerProfileId,
    Iterable<WebDavSyncRegistryRecordId> mergedBaselineRecords =
        const <WebDavSyncRegistryRecordId>[],
    String? actingProfileId,
    int? actingAuthorizationRevision,
    int? actingSessionEpoch,
  }) async {
    await authorityWillChangeCallback?.call();
    var revoked = 0;
    await _db.transaction((txn) async {
      await _assertManagingActor(
        txn,
        actingProfileId,
        actingAuthorizationRevision,
        actingSessionEpoch,
      );
      final borrowers = await txn.rawQuery(
        '''SELECT DISTINCT g.profile_id FROM profile_resource_grants g
           INNER JOIN connection_resources r ON r.id = g.resource_id
           WHERE r.owner_profile_id = ? AND g.profile_id != ?''',
        <Object>[ownerProfileId, ownerProfileId],
      );
      await _recordRegistryBorrowerRevocation(
        txn,
        ownerProfileId: ownerProfileId,
        mergedBaselineRecords: mergedBaselineRecords,
      );
      await txn.rawDelete(
        '''DELETE FROM profile_connection_bindings
           WHERE profile_id != ? AND resource_id IN
             (SELECT id FROM connection_resources WHERE owner_profile_id = ?)''',
        <Object>[ownerProfileId, ownerProfileId],
      );
      revoked = await txn.rawDelete(
        '''DELETE FROM profile_resource_grants
           WHERE profile_id != ? AND resource_id IN
             (SELECT id FROM connection_resources WHERE owner_profile_id = ?)''',
        <Object>[ownerProfileId, ownerProfileId],
      );
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      for (final row in borrowers) {
        await txn.rawUpdate(
          '''UPDATE user_profiles
             SET authorization_revision = authorization_revision + 1,
                 updated_at_ms = ?
             WHERE id = ?''',
          <Object>[nowMs, row['profile_id']! as String],
        );
      }
    });
    await _finishRegistryDelete();
    return revoked;
  }

  /// Deletes a non-active profile only after the UI has chosen explicit
  /// dispositions. Shared resources and active jobs remain hard blockers.
  Future<void> deleteProfileWithDisposition({
    required String id,
    required bool deleteOwnedResources,
    required bool detachPublicArtifacts,
    Iterable<WebDavSyncRegistryRecordId> mergedBaselineRecords =
        const <WebDavSyncRegistryRecordId>[],
    String? actingProfileId,
    int? actingAuthorizationRevision,
    int? actingSessionEpoch,
  }) async {
    await authorityWillChangeCallback?.call();
    await _db.transaction((txn) async {
      await _assertManagingActor(
        txn,
        actingProfileId,
        actingAuthorizationRevision,
        actingSessionEpoch,
      );
      final activeRows = await txn.query(
        'device_state',
        columns: const <String>['active_profile_id'],
        where: 'singleton_id = 1',
        limit: 1,
      );
      if (activeRows.isNotEmpty &&
          activeRows.single['active_profile_id'] == id) {
        throw StateError('Switch away before deleting this profile');
      }
      final rows = await txn.query(
        'user_profiles',
        columns: const <String>['role', 'disabled_at_ms'],
        where: 'id = ?',
        whereArgs: <Object>[id],
        limit: 1,
      );
      if (rows.isEmpty) return;
      if (rows.single['role'] == UserProfileRole.admin.name &&
          rows.single['disabled_at_ms'] == null) {
        await _assertAdminInvariant(txn, excludingProfileId: id);
      }

      final activeJobs =
          Sqflite.firstIntValue(
            await txn.rawQuery(
              '''SELECT COUNT(*) FROM job_ownership j
                 LEFT JOIN connection_resources r ON r.id = j.resource_id
                 WHERE (j.owner_profile_id = ? OR r.owner_profile_id = ?)
                   AND j.terminal_at_ms IS NULL''',
              <Object>[id, id],
            ),
          ) ??
          0;
      if (activeJobs != 0) {
        throw StateError('Active jobs must finish or be cancelled first');
      }
      final shared =
          Sqflite.firstIntValue(
            await txn.rawQuery(
              '''SELECT COUNT(DISTINCT r.id) FROM connection_resources r
                 INNER JOIN profile_resource_grants g ON g.resource_id = r.id
                 WHERE r.owner_profile_id = ? AND g.profile_id != ?''',
              <Object>[id, id],
            ),
          ) ??
          0;
      if (shared != 0) {
        throw StateError('Shared connections must be transferred or revoked');
      }
      final owned =
          Sqflite.firstIntValue(
            await txn.rawQuery(
              'SELECT COUNT(*) FROM connection_resources WHERE owner_profile_id = ?',
              <Object>[id],
            ),
          ) ??
          0;
      if (owned != 0 && !deleteOwnedResources) {
        throw StateError('Owned connections need an explicit disposition');
      }
      final artifacts =
          Sqflite.firstIntValue(
            await txn.rawQuery(
              'SELECT COUNT(*) FROM owned_artifacts WHERE owner_profile_id = ?',
              <Object>[id],
            ),
          ) ??
          0;
      if (artifacts != 0 && !detachPublicArtifacts) {
        throw StateError('Public files need an explicit retention choice');
      }

      await _recordRegistryDeleteCascade(
        txn,
        profileIds: <String>{id},
        mergedBaselineRecords: mergedBaselineRecords,
      );

      final detachedToken = _newId();
      await txn.update(
        'job_ownership',
        <String, Object?>{
          'owner_profile_id': null,
          'resource_id': null,
          'detached_owner_token': detachedToken,
        },
        where: 'owner_profile_id = ? AND terminal_at_ms IS NOT NULL',
        whereArgs: <Object>[id],
      );
      await txn.rawUpdate(
        '''UPDATE job_ownership SET resource_id = NULL
           WHERE terminal_at_ms IS NOT NULL AND resource_id IN
             (SELECT id FROM connection_resources WHERE owner_profile_id = ?)''',
        <Object>[id],
      );
      if (artifacts != 0) {
        await txn.update(
          'owned_artifacts',
          <String, Object?>{
            'owner_profile_id': null,
            'ownership_state': 'detached',
            'detached_owner_token': detachedToken,
          },
          where: 'owner_profile_id = ?',
          whereArgs: <Object>[id],
        );
      }
      if (owned != 0) {
        await txn.delete(
          'connection_resources',
          where: 'owner_profile_id = ?',
          whereArgs: <Object>[id],
        );
      }
      await txn.delete(
        'user_profiles',
        where: 'id = ?',
        whereArgs: <Object>[id],
      );
    });
    await _finishRegistryDelete();
  }

  /// Connection kinds that are PERSONAL and therefore excluded from the
  /// default-on sharing seed: watch history is one person's, and a shared
  /// tracker would interleave two people's scrobbles. Sharing one stays a
  /// deliberate act (the sources editor / service.grant).
  static const Set<ConnectionResourceType> personalResourceTypes =
      <ConnectionResourceType>{
        ConnectionResourceType.trakt,
        ConnectionResourceType.simkl,
        ConnectionResourceType.mdblist,
        ConnectionResourceType.reddit,
      };

  /// The default-share permission mask: usable for playback and downloads,
  /// nothing that exposes or moves the credential. Everything stronger stays
  /// owner-only or an explicit grant.
  static final int defaultShareMask =
      ResourcePermission.use.bit | ResourcePermission.download.bit;

  /// Everything on this device starts enabled for every profile — except the
  /// personal kinds. Seeds a use+download grant for [profileId] on every
  /// existing shareable resource it doesn't already have one for. Runs inside
  /// the caller's transaction; INSERT OR IGNORE keeps it idempotent. Seeding
  /// fires only from createProfile/insertResource — a resource or profile
  /// that is disabled at that moment and re-enabled later stays unseeded
  /// until an admin shares it explicitly (accepted gap; profiles are
  /// unshipped, so no installs exist to backfill).
  Future<void> _seedDefaultGrantsForProfile(
    DatabaseExecutor txn,
    String profileId,
    int nowMs,
  ) async {
    final resources = await txn.query(
      'connection_resources',
      columns: const <String>['id', 'type', 'owner_profile_id'],
      where: 'disabled_at_ms IS NULL',
    );
    for (final row in resources) {
      final type = ConnectionResourceType.values
          .where((value) => value.name == row['type'])
          .firstOrNull;
      if (type == null || personalResourceTypes.contains(type)) continue;
      if (row['owner_profile_id'] == profileId) continue;
      await txn.insert('profile_resource_grants', <String, Object?>{
        'profile_id': profileId,
        'resource_id': row['id'],
        'permissions': defaultShareMask,
        'granted_by_profile_id': row['owner_profile_id'],
        'grant_origin_json': '{"origin":"defaultSeed"}',
        'created_at_ms': nowMs,
        'updated_at_ms': nowMs,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  /// The other direction of the same default: a NEW shareable resource is
  /// granted to every existing enabled profile except its owner.
  Future<void> _seedDefaultGrantsForResource(
    DatabaseExecutor txn,
    ConnectionResource resource,
    int nowMs,
  ) async {
    if (personalResourceTypes.contains(resource.type)) return;
    // Mirror the profile-side filter: a resource inserted disabled is not
    // shareable, so it seeds nothing (see _seedDefaultGrantsForProfile's
    // doc for the re-enable gap).
    if (!resource.enabled) return;
    final profiles = await txn.query(
      'user_profiles',
      columns: const <String>['id'],
      where: "disabled_at_ms IS NULL AND lifecycle_state = 'active'",
    );
    for (final row in profiles) {
      final profileId = row['id'] as String;
      if (profileId == resource.ownerProfileId) continue;
      await txn.insert('profile_resource_grants', <String, Object?>{
        'profile_id': profileId,
        'resource_id': resource.id,
        'permissions': defaultShareMask,
        'granted_by_profile_id': resource.ownerProfileId,
        'grant_origin_json': '{"origin":"defaultSeed"}',
        'created_at_ms': nowMs,
        'updated_at_ms': nowMs,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  Future<void> insertResource({
    required ConnectionResource resource,
    required String sealedSecretPayload,
    required int secretPayloadVersion,
    required int ownerPermissions,
    String? bindingSlot,
    String? actingProfileId,
    int? actingAuthorizationRevision,
    int? actingSessionEpoch,
  }) async {
    _guardTvOsEnvelopeBound(sealedSecretPayload);
    await authorityWillChangeCallback?.call();
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.transaction((txn) async {
      if (actingProfileId != null || actingAuthorizationRevision != null) {
        if (actingProfileId == null || actingAuthorizationRevision == null) {
          throw ArgumentError('Incomplete resource-creation authority');
        }
        await _assertFeatureActor(
          txn,
          profileId: actingProfileId,
          authorizationRevision: actingAuthorizationRevision,
          feature: ProfileFeature.manageConnections,
        );
        if (actingProfileId != resource.ownerProfileId) {
          throw StateError('Resource owner changed before creation');
        }
      }
      await txn.insert('connection_resources', <String, Object?>{
        'id': resource.id,
        'type': resource.type.name,
        'label': resource.label,
        'owner_profile_id': resource.ownerProfileId,
        'public_config_json': jsonEncode(resource.publicConfig),
        'sealed_secret_payload': _encodeEnvelopeColumn(sealedSecretPayload),
        'secret_payload_version': secretPayloadVersion,
        'secret_pending': 0,
        'authorization_revision': resource.authorizationRevision,
        'created_at_ms': now,
        'updated_at_ms': now,
        'disabled_at_ms': resource.enabled ? null : now,
      });
      await _writeEnvelopeChunks(
        txn,
        'resource_secret_chunks',
        <String, Object?>{'resource_id': resource.id},
        sealedSecretPayload,
      );
      await txn.insert('profile_resource_grants', <String, Object?>{
        'profile_id': resource.ownerProfileId,
        'resource_id': resource.id,
        'permissions': ownerPermissions,
        'granted_by_profile_id': resource.ownerProfileId,
        'grant_origin_json': '{"origin":"owner"}',
        'created_at_ms': now,
        'updated_at_ms': now,
      });
      if (bindingSlot != null) {
        if (bindingSlot.trim().isEmpty) {
          throw ArgumentError.value(bindingSlot, 'bindingSlot');
        }
        await txn.insert(
          'profile_connection_bindings',
          <String, Object?>{
            'profile_id': resource.ownerProfileId,
            'slot': bindingSlot,
            'resource_id': resource.id,
            'created_at_ms': now,
            'updated_at_ms': now,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await _seedDefaultGrantsForResource(txn, resource, now);
      final revision = await _profileAuthorizationRevision(
        txn,
        resource.ownerProfileId,
      );
      await txn.update(
        'user_profiles',
        <String, Object?>{
          'authorization_revision': revision + 1,
          'updated_at_ms': now,
        },
        where: 'id = ?',
        whereArgs: <Object>[resource.ownerProfileId],
      );
    });
    await checkpointTvOsRecovery(webDavSyncRegistryChange: true);
  }

  /// Columns [_decodeResource] needs — everything EXCEPT the sealed payload.
  ///
  /// Deliberate, not an optimization: `SELECT *` materializes the payload
  /// column into Android's CursorWindow even when the caller never reads it,
  /// and one legacy oversized inline envelope (pre-chunking rows) is enough
  /// to abort every such query. Reads that want the envelope go through
  /// [getSealedResourceSecret], which is chunk-aware.
  static const List<String> _resourceRowColumns = <String>[
    'id',
    'type',
    'label',
    'owner_profile_id',
    'public_config_json',
    'secret_pending',
    'authorization_revision',
    'disabled_at_ms',
  ];

  Future<ConnectionResource?> getResource(String id) async {
    final rows = await _db.query(
      'connection_resources',
      columns: _resourceRowColumns,
      where: 'id = ?',
      whereArgs: <Object>[id],
      limit: 1,
    );
    return rows.isEmpty ? null : _decodeResource(rows.single);
  }

  Future<SealedResourceSecretRecord?> getSealedResourceSecret(
    String id, {
    bool includeDisabled = false,
  }) async {
    // One transaction for the marker and its chunks: a rotation landing
    // between two bare reads could pair one secret's marker with another's
    // body. The count check in [_loadEnvelope] catches most torn pairs, but
    // a same-size rotation would pass it — atomicity, not detection, is the
    // guarantee a SECRET read needs.
    return _db.transaction((txn) async {
      final rows = await txn.query(
        'connection_resources',
        columns: const <String>[
          'id',
          'type',
          'owner_profile_id',
          'public_config_json',
          'sealed_secret_payload',
          'secret_payload_version',
        ],
        where: includeDisabled ? 'id = ?' : 'id = ? AND disabled_at_ms IS NULL',
        whereArgs: <Object>[id],
        limit: 1,
      );
      if (rows.isEmpty || rows.single['sealed_secret_payload'] == null) {
        return null;
      }
      final row = rows.single;
      final publicConfig = Map<String, dynamic>.from(
        jsonDecode(row['public_config_json']! as String) as Map,
      );
      return SealedResourceSecretRecord(
        resourceId: row['id']! as String,
        type: ConnectionResourceType.values.byName(row['type']! as String),
        ownerProfileId: row['owner_profile_id']! as String,
        publicSchemaVersion: publicConfig['schemaVersion']! as int,
        payloadVersion: row['secret_payload_version']! as int,
        envelope: await _loadEnvelope(
          txn,
          'resource_secret_chunks',
          <String, Object?>{'resource_id': id},
          row['sealed_secret_payload']! as String,
        ),
      );
    });
  }

  Future<void> updateResourceSecret({
    required String resourceId,
    required String sealedSecretPayload,
    required int secretPayloadVersion,
    String? actingProfileId,
    int? actingAuthorizationRevision,
    int? expectedResourceAuthorizationRevision,
  }) async {
    _guardTvOsEnvelopeBound(sealedSecretPayload);
    await authorityWillChangeCallback?.call();
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.transaction((txn) async {
      if (actingProfileId != null ||
          actingAuthorizationRevision != null ||
          expectedResourceAuthorizationRevision != null) {
        if (actingProfileId == null ||
            actingAuthorizationRevision == null ||
            expectedResourceAuthorizationRevision == null) {
          throw ArgumentError('Incomplete resource mutation authority');
        }
        await _assertResourceActor(
          txn,
          profileId: actingProfileId,
          authorizationRevision: actingAuthorizationRevision,
          feature: ProfileFeature.manageConnections,
          resourceId: resourceId,
          resourceAuthorizationRevision: expectedResourceAuthorizationRevision,
          permission: ResourcePermission.manage,
        );
      }
      final changed = await txn.rawUpdate(
        '''UPDATE connection_resources
           SET sealed_secret_payload = ?, secret_payload_version = ?,
               secret_pending = 0,
               authorization_revision = authorization_revision + 1,
               updated_at_ms = ?
           WHERE id = ? AND disabled_at_ms IS NULL
             ${expectedResourceAuthorizationRevision == null ? '' : 'AND authorization_revision = ?'}''',
        <Object>[
          _encodeEnvelopeColumn(sealedSecretPayload),
          secretPayloadVersion,
          now,
          resourceId,
          if (expectedResourceAuthorizationRevision != null)
            expectedResourceAuthorizationRevision,
        ],
      );
      if (changed != 1) throw StateError('Resource is unavailable');
      // After the guard: a refused rotation must not touch the old chunks.
      await _writeEnvelopeChunks(
        txn,
        'resource_secret_chunks',
        <String, Object?>{'resource_id': resourceId},
        sealedSecretPayload,
      );
      final profiles = await txn.query(
        'profile_resource_grants',
        columns: const <String>['profile_id'],
        where: 'resource_id = ?',
        whereArgs: <Object>[resourceId],
      );
      for (final row in profiles) {
        await txn.rawUpdate(
          '''UPDATE user_profiles
             SET authorization_revision = authorization_revision + 1,
                 updated_at_ms = ? WHERE id = ?''',
          <Object>[now, row['profile_id']!],
        );
      }
    });
    await checkpointTvOsRecovery(webDavSyncRegistryChange: true);
  }

  /// Deletes an owned connection as one disposition transaction. Active jobs
  /// and borrowers are explicit blockers unless the caller has selected the
  /// corresponding destructive disposition. Terminal job history is detached
  /// from the credential before deletion so it can remain attributable without
  /// retaining a dead resource foreign key.
  Future<void> deleteOwnedResource({
    required String resourceId,
    required String ownerProfileId,
    required bool revokeBorrowers,
    Iterable<WebDavSyncRegistryRecordId> mergedBaselineRecords =
        const <WebDavSyncRegistryRecordId>[],
    String? actingProfileId,
    int? actingAuthorizationRevision,
    int? expectedResourceAuthorizationRevision,
  }) async {
    await authorityWillChangeCallback?.call();
    await _db.transaction((txn) async {
      if (actingProfileId != null ||
          actingAuthorizationRevision != null ||
          expectedResourceAuthorizationRevision != null) {
        if (actingProfileId == null ||
            actingAuthorizationRevision == null ||
            expectedResourceAuthorizationRevision == null) {
          throw ArgumentError('Incomplete resource deletion authority');
        }
        await _assertResourceActor(
          txn,
          profileId: actingProfileId,
          authorizationRevision: actingAuthorizationRevision,
          feature: ProfileFeature.manageConnections,
          resourceId: resourceId,
          resourceAuthorizationRevision: expectedResourceAuthorizationRevision,
          permission: ResourcePermission.manage,
        );
      }
      final rows = await txn.query(
        'connection_resources',
        columns: const <String>['owner_profile_id'],
        where: 'id = ? AND disabled_at_ms IS NULL',
        whereArgs: <Object>[resourceId],
        limit: 1,
      );
      if (rows.isEmpty) return;
      if (rows.single['owner_profile_id'] != ownerProfileId) {
        throw StateError('Only the connection owner can delete it');
      }
      final activeJobs =
          Sqflite.firstIntValue(
            await txn.rawQuery(
              '''SELECT COUNT(*) FROM job_ownership
                 WHERE resource_id = ? AND terminal_at_ms IS NULL''',
              <Object>[resourceId],
            ),
          ) ??
          0;
      if (activeJobs != 0) {
        throw StateError('Active jobs must finish or be cancelled first');
      }
      final grantedRows = await txn.query(
        'profile_resource_grants',
        columns: const <String>['profile_id'],
        where: 'resource_id = ?',
        whereArgs: <Object>[resourceId],
      );
      final grantedProfileIds = grantedRows
          .map((row) => row['profile_id']! as String)
          .toSet();
      final borrowerCount = grantedProfileIds
          .where((profileId) => profileId != ownerProfileId)
          .length;
      if (borrowerCount != 0 && !revokeBorrowers) {
        throw StateError(
          'This connection is shared; revoke or transfer it explicitly',
        );
      }

      await _recordRegistryDeleteCascade(
        txn,
        resourceIds: <String>{resourceId},
        mergedBaselineRecords: mergedBaselineRecords,
      );

      await txn.update(
        'job_ownership',
        <String, Object?>{'resource_id': null},
        where: 'resource_id = ? AND terminal_at_ms IS NOT NULL',
        whereArgs: <Object>[resourceId],
      );
      final changed = await txn.delete(
        'connection_resources',
        where:
            'id = ? ${expectedResourceAuthorizationRevision == null ? '' : 'AND authorization_revision = ?'}',
        whereArgs: <Object>[
          resourceId,
          if (expectedResourceAuthorizationRevision != null)
            expectedResourceAuthorizationRevision,
        ],
      );
      if (changed != 1) throw StateError('Connection deletion failed');
      final now = DateTime.now().millisecondsSinceEpoch;
      for (final profileId in grantedProfileIds) {
        await txn.rawUpdate(
          '''UPDATE user_profiles
             SET authorization_revision = authorization_revision + 1,
                 updated_at_ms = ? WHERE id = ?''',
          <Object>[now, profileId],
        );
      }
    });
    await _finishRegistryDelete();
  }

  /// Atomically changes resource ownership together with the secret envelope
  /// re-sealed for the new owner-bound AAD. Existing grants remain explicit;
  /// the destination receives the full owner grant.
  Future<void> transferResourceOwnership({
    required String resourceId,
    required String currentOwnerProfileId,
    required String newOwnerProfileId,
    required String resealedSecretPayload,
    required int secretPayloadVersion,
    required int ownerPermissions,
    required String transferredByProfileId,
    String? actingProfileId,
    int? actingAuthorizationRevision,
    int? expectedResourceAuthorizationRevision,
    int? expectedTargetAuthorizationRevision,
  }) async {
    if (currentOwnerProfileId == newOwnerProfileId) return;
    _guardTvOsEnvelopeBound(resealedSecretPayload);
    await authorityWillChangeCallback?.call();
    await _db.transaction((txn) async {
      if (actingProfileId != null ||
          actingAuthorizationRevision != null ||
          expectedResourceAuthorizationRevision != null ||
          expectedTargetAuthorizationRevision != null) {
        if (actingProfileId == null ||
            actingAuthorizationRevision == null ||
            expectedResourceAuthorizationRevision == null ||
            expectedTargetAuthorizationRevision == null) {
          throw ArgumentError('Incomplete ownership-transfer authority');
        }
        await _assertFeatureActor(
          txn,
          profileId: actingProfileId,
          authorizationRevision: actingAuthorizationRevision,
          feature: ProfileFeature.manageProfiles,
          requireAdmin: true,
        );
      }
      final rows = await txn.query(
        'connection_resources',
        columns: const <String>['owner_profile_id', 'authorization_revision'],
        where: 'id = ? AND disabled_at_ms IS NULL',
        whereArgs: <Object>[resourceId],
        limit: 1,
      );
      if (rows.isEmpty) throw StateError('Connection is unavailable');
      if (rows.single['owner_profile_id'] != currentOwnerProfileId) {
        throw StateError('Connection ownership changed');
      }
      if (expectedResourceAuthorizationRevision != null &&
          rows.single['authorization_revision'] !=
              expectedResourceAuthorizationRevision) {
        throw StateError('Connection authorization changed');
      }
      final target = await txn.query(
        'user_profiles',
        columns: const <String>['id', 'authorization_revision'],
        where: 'id = ? AND disabled_at_ms IS NULL',
        whereArgs: <Object>[newOwnerProfileId],
        limit: 1,
      );
      if (target.isEmpty) throw StateError('New owner is unavailable');
      if (expectedTargetAuthorizationRevision != null &&
          target.single['authorization_revision'] !=
              expectedTargetAuthorizationRevision) {
        throw StateError('New owner authorization changed');
      }
      final now = DateTime.now().millisecondsSinceEpoch;
      await _compatUpsert(
        txn,
        table: 'profile_resource_grants',
        insert: <String, Object?>{
          'profile_id': newOwnerProfileId,
          'resource_id': resourceId,
          'permissions': ownerPermissions,
          'granted_by_profile_id': transferredByProfileId,
          'grant_origin_json': jsonEncode(<String, Object?>{
            'origin': 'ownershipTransfer',
            'previousOwnerProfileId': currentOwnerProfileId,
          }),
          'created_at_ms': now,
          'updated_at_ms': now,
        },
        update: <String, Object?>{
          'permissions': ownerPermissions,
          'granted_by_profile_id': transferredByProfileId,
          'grant_origin_json': jsonEncode(<String, Object?>{
            'origin': 'ownershipTransfer',
            'previousOwnerProfileId': currentOwnerProfileId,
          }),
          'updated_at_ms': now,
        },
        key: <String, Object?>{
          'profile_id': newOwnerProfileId,
          'resource_id': resourceId,
        },
      );
      final changed = await txn.rawUpdate(
        '''UPDATE connection_resources
           SET owner_profile_id = ?, sealed_secret_payload = ?,
               secret_payload_version = ?, secret_pending = 0,
               authorization_revision = authorization_revision + 1,
               updated_at_ms = ?
           WHERE id = ? AND owner_profile_id = ? AND disabled_at_ms IS NULL''',
        <Object>[
          newOwnerProfileId,
          _encodeEnvelopeColumn(resealedSecretPayload),
          secretPayloadVersion,
          now,
          resourceId,
          currentOwnerProfileId,
        ],
      );
      if (changed != 1) throw StateError('Connection ownership changed');
      await _writeEnvelopeChunks(
        txn,
        'resource_secret_chunks',
        <String, Object?>{'resource_id': resourceId},
        resealedSecretPayload,
      );
      final grantedRows = await txn.query(
        'profile_resource_grants',
        columns: const <String>['profile_id'],
        where: 'resource_id = ?',
        whereArgs: <Object>[resourceId],
      );
      for (final row in grantedRows) {
        await txn.rawUpdate(
          '''UPDATE user_profiles
             SET authorization_revision = authorization_revision + 1,
                 updated_at_ms = ? WHERE id = ?''',
          <Object>[now, row['profile_id']!],
        );
      }
    });
    await checkpointTvOsRecovery(webDavSyncRegistryChange: true);
  }

  Future<void> unbindResource(
    String profileId,
    String slot, {
    Iterable<WebDavSyncRegistryRecordId> mergedBaselineRecords =
        const <WebDavSyncRegistryRecordId>[],
  }) async {
    await authorityWillChangeCallback?.call();
    await _db.transaction((txn) async {
      await _recordRegistryDeleteCascade(
        txn,
        bindingKeys: <String>{_registryBindingKey(profileId, slot)},
        mergedBaselineRecords: mergedBaselineRecords,
      );
      await txn.delete(
        'profile_connection_bindings',
        where: 'profile_id = ? AND slot = ?',
        whereArgs: <Object>[profileId, slot],
      );
    });
    await _finishRegistryDelete();
  }

  Future<List<ConnectionResource>> listGrantedResources(
    String profileId,
  ) async {
    final columns = _resourceRowColumns.map((c) => 'r.$c').join(', ');
    final rows = await _db.rawQuery(
      '''SELECT $columns FROM connection_resources r
         INNER JOIN profile_resource_grants g ON g.resource_id = r.id
         WHERE g.profile_id = ? AND r.disabled_at_ms IS NULL
         ORDER BY lower(r.label), r.id''',
      <Object>[profileId],
    );
    return rows.map(_decodeResource).toList(growable: false);
  }

  /// Backup inventory for one profile. Disabled resources stay invisible to
  /// provider/runtime callers but must remain recoverable in an encrypted
  /// package, with their disabled state preserved.
  Future<List<ConnectionResource>> listGrantedResourcesIncludingDisabled(
    String profileId,
  ) async {
    final columns = _resourceRowColumns.map((c) => 'r.$c').join(', ');
    final rows = await _db.rawQuery(
      '''SELECT $columns FROM connection_resources r
         INNER JOIN profile_resource_grants g ON g.resource_id = r.id
         WHERE g.profile_id = ?
         ORDER BY lower(r.label), r.id''',
      <Object>[profileId],
    );
    return rows.map(_decodeResource).toList(growable: false);
  }

  Future<List<ConnectionResource>> listAllResources() async {
    final rows = await _db.query(
      'connection_resources',
      columns: _resourceRowColumns,
      where: 'disabled_at_ms IS NULL',
      orderBy: 'created_at_ms, id',
    );
    return rows.map(_decodeResource).toList(growable: false);
  }

  /// Complete graph inventory, including disabled/quarantined resources.
  /// Ordinary provider and settings reads must keep using [listAllResources].
  Future<List<ConnectionResource>> listAllResourcesIncludingDisabled() async {
    final rows = await _db.query(
      'connection_resources',
      columns: _resourceRowColumns,
      orderBy: 'created_at_ms, id',
    );
    return rows.map(_decodeResource).toList(growable: false);
  }

  /// Every resource a profile owns, INCLUDING disabled ones.
  ///
  /// [listAllResources] hides disabled rows, but the delete-time owned-resource
  /// count does not — so any caller deciding whether a profile is disposable
  /// must look through this, or it will classify a profile as owning nothing
  /// of value and then delete a disabled credential it never saw.
  Future<List<ConnectionResource>> listOwnedResourcesIncludingDisabled(
    String ownerProfileId,
  ) async {
    final rows = await _db.query(
      'connection_resources',
      columns: _resourceRowColumns,
      where: 'owner_profile_id = ?',
      whereArgs: <Object>[ownerProfileId],
      orderBy: 'created_at_ms, id',
    );
    return rows.map(_decodeResource).toList(growable: false);
  }

  Future<List<Map<String, Object?>>> listAllResourceGrants() =>
      _db.query('profile_resource_grants', orderBy: 'profile_id, resource_id');

  Future<List<Map<String, Object?>>> listAllResourceBindings() =>
      _db.query('profile_connection_bindings', orderBy: 'profile_id, slot');

  Future<List<Map<String, Object?>>> listAllResourceSettings() => _db.query(
    'profile_resource_settings',
    orderBy: 'profile_id, resource_id',
  );

  /// Transactionally consistent profile fields used by the circle-level
  /// profiles document. Authentication churn may change [updatedAtMs], so the
  /// document builder must still preserve its prior stamp when these
  /// serialized fields are byte-identical.
  Future<List<RegistrySyncProfileProjection>> readProfileSyncProjection() =>
      _db.transaction(_readProfileSyncProjection);

  /// One transactionally consistent registry projection for the circle-level
  /// sync document builder. Operational models deliberately remain free of
  /// database provenance; the timestamps live only on these sync rows.
  Future<RegistrySyncProjection> readRegistrySyncProjection() =>
      _db.transaction(_readRegistrySyncProjection);

  /// The exact registry snapshot used for circle publication, together with
  /// the outbox state from that same SQL transaction.
  Future<RegistryCircleSyncProjection> readCircleSyncProjection() =>
      _db.transaction((txn) async {
        final profiles = await _readProfileSyncProjection(txn);
        final registry = await _readRegistrySyncProjection(txn);
        final outboxRowCount = Sqflite.firstIntValue(
          await txn.rawQuery(
            'SELECT COUNT(*) FROM webdav_sync_tombstone_outbox',
          ),
        );
        return RegistryCircleSyncProjection(
          profiles: profiles,
          registry: registry,
          outboxRowCount: outboxRowCount ?? 0,
        );
      });

  Future<List<RegistrySyncProfileProjection>> _readProfileSyncProjection(
    DatabaseExecutor db,
  ) async {
    final rows = await db.query('user_profiles', orderBy: 'id');
    return rows
        .map(
          (row) => RegistrySyncProfileProjection(
            profile: _decodeProfile(row),
            pin: ProfilePinRecord(
              hash: row['pin_hash'] as Uint8List?,
              salt: row['pin_salt'] as Uint8List?,
              paramsJson: row['pin_params_json'] as String?,
              resetRequired: row['pin_reset_required'] == 1,
              recoveryHash: row['recovery_hash'] as Uint8List?,
              recoverySalt: row['recovery_salt'] as Uint8List?,
              recoveryParamsJson: row['recovery_params_json'] as String?,
            ),
            updatedAtMs: row['updated_at_ms']! as int,
          ),
        )
        .toList(growable: false);
  }

  Future<RegistrySyncProjection> _readRegistrySyncProjection(
    DatabaseExecutor db,
  ) async {
    final resources = await db.query(
      'connection_resources',
      columns: <String>[..._resourceRowColumns, 'updated_at_ms'],
      orderBy: 'id',
    );
    final grants = await db.query(
      'profile_resource_grants',
      columns: const <String>[
        'profile_id',
        'resource_id',
        'permissions',
        'updated_at_ms',
      ],
      orderBy: 'profile_id, resource_id',
    );
    final settings = await db.query(
      'profile_resource_settings',
      columns: const <String>[
        'profile_id',
        'resource_id',
        'enabled',
        'settings_json',
        'updated_at_ms',
      ],
      orderBy: 'profile_id, resource_id',
    );
    final bindings = await db.query(
      'profile_connection_bindings',
      columns: const <String>[
        'profile_id',
        'slot',
        'resource_id',
        'updated_at_ms',
      ],
      orderBy: 'profile_id, slot',
    );
    return RegistrySyncProjection(
      resources: resources
          .map(
            (row) => RegistrySyncResourceProjection(
              resource: _decodeResource(row),
              updatedAtMs: row['updated_at_ms']! as int,
            ),
          )
          .toList(growable: false),
      grants: grants
          .map(
            (row) => RegistrySyncGrantProjection(
              profileId: row['profile_id']! as String,
              resourceId: row['resource_id']! as String,
              permissions: row['permissions']! as int,
              updatedAtMs: row['updated_at_ms']! as int,
            ),
          )
          .toList(growable: false),
      settings: settings
          .map(
            (row) => RegistrySyncSettingsProjection(
              profileId: row['profile_id']! as String,
              resourceId: row['resource_id']! as String,
              enabled: row['enabled'] == 1,
              settings: Map<String, dynamic>.from(
                jsonDecode(row['settings_json']! as String) as Map,
              ),
              updatedAtMs: row['updated_at_ms']! as int,
            ),
          )
          .toList(growable: false),
      bindings: bindings
          .map(
            (row) => RegistrySyncBindingProjection(
              profileId: row['profile_id']! as String,
              slot: row['slot']! as String,
              resourceId: row['resource_id']! as String,
              updatedAtMs: row['updated_at_ms']! as int,
            ),
          )
          .toList(growable: false),
    );
  }

  /// Applies a fully merged circle-registry delta without staged-graph or
  /// restore journals. The caller supplies merge provenance; this writer owns
  /// relational ordering, local authorization revisions, and secret storage.
  Future<SyncedRegistryApplyResult> applySyncedRegistryDelta(
    SyncedRegistryDelta delta,
  ) async {
    for (final item in delta.resources) {
      final payload = item.sealedSecretPayload;
      if ((payload == null) != (item.secretPayloadVersion == null)) {
        throw ArgumentError('Synced secret payload is incomplete');
      }
      if (item.clearSecret && payload != null) {
        throw ArgumentError('Synced secret cannot be set and cleared');
      }
      if (payload != null) _guardTvOsEnvelopeBound(payload);
    }
    await authorityWillChangeCallback?.call();
    final now = DateTime.now().millisecondsSinceEpoch;
    final result = await _db.transaction((txn) async {
      if (!await _syncedDeltaMatchesObservedState(txn, delta)) {
        return SyncedRegistryApplyResult.conflict;
      }
      final activeRows = await txn.query(
        'device_state',
        columns: const <String>['active_profile_id'],
        where: 'singleton_id = 1',
        limit: 1,
      );
      final activeProfileId = activeRows.isEmpty
          ? null
          : activeRows.single['active_profile_id'] as String?;
      final deletedProfileIds = delta.deletes
          .where(
            (item) => item.record.kind == WebDavSyncRegistryRecordKind.profile,
          )
          .map((item) => item.record.profileId!)
          .toSet();
      if (activeProfileId != null &&
          deletedProfileIds.contains(activeProfileId)) {
        throw StateError('Cannot delete the active profile');
      }

      final affectedProfileIds = <String>{};
      final createdProfileIds = <String>{};

      // Parents first. A remote create intentionally does not seed grants;
      // the merged resources section is authoritative for those leaves.
      for (final item in delta.profiles) {
        _validateSyncedProfile(item);
        final existing = await txn.query(
          'user_profiles',
          columns: const <String>['id', 'avatar_key', 'authorization_revision'],
          where: 'id = ?',
          whereArgs: <Object>[item.id],
          limit: 1,
        );
        final isCreate = existing.isEmpty;
        final existingAvatar = isCreate
            ? null
            : existing.single['avatar_key'] as String?;
        final avatarKey =
            item.avatarKey ??
            (existingAvatar?.startsWith('file:') == true
                ? existingAvatar
                : null);
        final pin = item.pin;
        final insert = <String, Object?>{
          'id': item.id,
          'name': item.name.trim(),
          'avatar_key': avatarKey,
          'role': item.role.name,
          'policy_json': item.policy.encode(),
          'policy_schema_version': item.policy.schemaVersion,
          'authorization_revision': 1,
          'lifecycle_state': item.lifecycle.name,
          'visible_data_generation': 1,
          'profile_setup_complete': item.setupComplete ? 1 : 0,
          'pin_reset_required': pin.resetRequired ? 1 : 0,
          'pin_hash': pin.hash,
          'pin_salt': pin.salt,
          'pin_params_json': pin.paramsJson,
          'failed_pin_attempts': 0,
          'locked_until_ms': null,
          'recovery_hash': pin.recoveryHash,
          'recovery_salt': pin.recoverySalt,
          'recovery_params_json': pin.recoveryParamsJson,
          'lock_on_resume': item.lockOnResume ? 1 : 0,
          'inactivity_timeout_minutes': item.inactivityTimeoutMinutes,
          'created_at_ms': now,
          'updated_at_ms': item.updatedAtMs,
          'disabled_at_ms': item.enabled ? null : item.updatedAtMs,
        };
        final update = <String, Object?>{
          'name': item.name.trim(),
          'avatar_key': avatarKey,
          'role': item.role.name,
          'policy_json': item.policy.encode(),
          'policy_schema_version': item.policy.schemaVersion,
          'lifecycle_state': item.lifecycle.name,
          'profile_setup_complete': item.setupComplete ? 1 : 0,
          if (item.applyPin) 'pin_reset_required': pin.resetRequired ? 1 : 0,
          if (item.applyPin) 'pin_hash': pin.hash,
          if (item.applyPin) 'pin_salt': pin.salt,
          if (item.applyPin) 'pin_params_json': pin.paramsJson,
          if (item.applyPin) 'failed_pin_attempts': 0,
          if (item.applyPin) 'locked_until_ms': null,
          if (item.applyPin) 'recovery_hash': pin.recoveryHash,
          if (item.applyPin) 'recovery_salt': pin.recoverySalt,
          if (item.applyPin) 'recovery_params_json': pin.recoveryParamsJson,
          'lock_on_resume': item.lockOnResume ? 1 : 0,
          'inactivity_timeout_minutes': item.inactivityTimeoutMinutes,
          'updated_at_ms': item.updatedAtMs,
          'disabled_at_ms': item.enabled ? null : item.updatedAtMs,
        };
        await _compatUpsert(
          txn,
          table: 'user_profiles',
          insert: insert,
          update: update,
          key: <String, Object?>{'id': item.id},
        );
        await txn.insert('profile_data_generations', <String, Object?>{
          'profile_id': item.id,
          'generation': 1,
          'state': 'visible',
          'manifest_json': '{}',
          'manifest_hash': '',
          'created_at_ms': now,
          'updated_at_ms': now,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
        if (isCreate) {
          createdProfileIds.add(item.id);
        } else {
          affectedProfileIds.add(item.id);
        }
      }

      for (final item in delta.resources) {
        _validateSyncedTimestamp(item.updatedAtMs);
        if (!ProfileScope.isValidProfileId(item.resource.id) ||
            !ProfileScope.isValidProfileId(item.resource.ownerProfileId)) {
          throw ArgumentError('Invalid synced resource ID');
        }
        final encodedConfig = jsonEncode(item.resource.publicConfig);
        final schema = item.resource.publicConfig['schemaVersion'];
        if (schema is! int) {
          throw ArgumentError('Synced resource schema is missing');
        }
        final existing = await txn.query(
          'connection_resources',
          columns: const <String>[
            'authorization_revision',
            'sealed_secret_payload',
            'type',
            'owner_profile_id',
            'public_config_json',
          ],
          where: 'id = ?',
          whereArgs: <Object>[item.resource.id],
          limit: 1,
        );
        final existingPublicSchema = existing.isEmpty
            ? null
            : (jsonDecode(existing.single['public_config_json']! as String)
                      as Map)['schemaVersion']
                  as int?;
        final hasLocalSecret =
            !item.clearSecret &&
            existing.isNotEmpty &&
            existing.single['sealed_secret_payload'] != null &&
            existing.single['type'] == item.resource.type.name &&
            existing.single['owner_profile_id'] ==
                item.resource.ownerProfileId &&
            existingPublicSchema == schema;
        final payload = item.sealedSecretPayload;
        final nextRevision = existing.isEmpty
            ? 1
            : (existing.single['authorization_revision']! as int) + 1;
        final pending = payload == null && !hasLocalSecret;
        final insert = <String, Object?>{
          'id': item.resource.id,
          'type': item.resource.type.name,
          'label': item.resource.label,
          'owner_profile_id': item.resource.ownerProfileId,
          'public_config_json': encodedConfig,
          'sealed_secret_payload': payload == null
              ? null
              : _encodeEnvelopeColumn(payload),
          'secret_payload_version': item.secretPayloadVersion,
          'secret_pending': pending ? 1 : 0,
          'authorization_revision': nextRevision,
          'created_at_ms': now,
          'updated_at_ms': item.updatedAtMs,
          'disabled_at_ms': item.resource.enabled ? null : item.updatedAtMs,
        };
        final update = <String, Object?>{
          'type': item.resource.type.name,
          'label': item.resource.label,
          'owner_profile_id': item.resource.ownerProfileId,
          'public_config_json': encodedConfig,
          if (payload != null || !hasLocalSecret)
            'sealed_secret_payload': payload == null
                ? null
                : _encodeEnvelopeColumn(payload),
          if (payload != null || !hasLocalSecret)
            'secret_payload_version': item.secretPayloadVersion,
          'secret_pending': pending ? 1 : 0,
          'authorization_revision': nextRevision,
          'updated_at_ms': item.updatedAtMs,
          'disabled_at_ms': item.resource.enabled ? null : item.updatedAtMs,
        };
        await _compatUpsert(
          txn,
          table: 'connection_resources',
          insert: insert,
          update: update,
          key: <String, Object?>{'id': item.resource.id},
        );
        if (payload != null) {
          await _writeEnvelopeChunks(
            txn,
            'resource_secret_chunks',
            <String, Object?>{'resource_id': item.resource.id},
            payload,
          );
        } else if (!hasLocalSecret) {
          await txn.delete(
            'resource_secret_chunks',
            where: 'resource_id = ?',
            whereArgs: <Object>[item.resource.id],
          );
        }
      }

      for (final item in delta.grants) {
        _validateSyncedTimestamp(item.updatedAtMs);
        final knownPermissions = ResourcePermission.values.fold<int>(
          0,
          (mask, permission) => mask | permission.bit,
        );
        if (item.permissions < 0 || item.permissions & ~knownPermissions != 0) {
          throw ArgumentError('Synced grant permissions are invalid');
        }
        await _compatUpsert(
          txn,
          table: 'profile_resource_grants',
          insert: <String, Object?>{
            'profile_id': item.profileId,
            'resource_id': item.resourceId,
            'permissions': item.permissions,
            'granted_by_profile_id': null,
            'grant_origin_json': '{"origin":"webDavSync"}',
            'created_at_ms': now,
            'updated_at_ms': item.updatedAtMs,
          },
          update: <String, Object?>{
            'permissions': item.permissions,
            'granted_by_profile_id': null,
            'grant_origin_json': '{"origin":"webDavSync"}',
            'updated_at_ms': item.updatedAtMs,
          },
          key: <String, Object?>{
            'profile_id': item.profileId,
            'resource_id': item.resourceId,
          },
        );
        affectedProfileIds.add(item.profileId);
      }

      for (final item in delta.settings) {
        _validateSyncedTimestamp(item.updatedAtMs);
        final encoded = jsonEncode(item.settings);
        if (encoded.length > 64 * 1024) {
          throw StateError('Synced resource settings are too large');
        }
        await _compatUpsert(
          txn,
          table: 'profile_resource_settings',
          insert: <String, Object?>{
            'profile_id': item.profileId,
            'resource_id': item.resourceId,
            'enabled': item.enabled ? 1 : 0,
            'settings_json': encoded,
            'updated_at_ms': item.updatedAtMs,
          },
          update: <String, Object?>{
            'enabled': item.enabled ? 1 : 0,
            'settings_json': encoded,
            'updated_at_ms': item.updatedAtMs,
          },
          key: <String, Object?>{
            'profile_id': item.profileId,
            'resource_id': item.resourceId,
          },
        );
      }

      for (final item in delta.bindings) {
        _validateSyncedTimestamp(item.updatedAtMs);
        if (item.slot.trim().isEmpty) {
          throw ArgumentError.value(item.slot, 'slot');
        }
        await _compatUpsert(
          txn,
          table: 'profile_connection_bindings',
          insert: <String, Object?>{
            'profile_id': item.profileId,
            'slot': item.slot,
            'resource_id': item.resourceId,
            'created_at_ms': now,
            'updated_at_ms': item.updatedAtMs,
          },
          update: <String, Object?>{
            'resource_id': item.resourceId,
            'updated_at_ms': item.updatedAtMs,
          },
          key: <String, Object?>{
            'profile_id': item.profileId,
            'slot': item.slot,
          },
        );
      }

      final deletedResourceIds = delta.deletes
          .where(
            (item) => item.record.kind == WebDavSyncRegistryRecordKind.resource,
          )
          .map((item) => item.record.resourceId!)
          .toSet();
      for (final resourceId in <String>{
        ...delta.resources.map((item) => item.resource.id),
        ...deletedResourceIds,
      }) {
        final grants = await txn.query(
          'profile_resource_grants',
          columns: const <String>['profile_id'],
          where: 'resource_id = ?',
          whereArgs: <Object>[resourceId],
        );
        affectedProfileIds.addAll(
          grants.map((row) => row['profile_id']! as String),
        );
      }

      // Child-first physical removal keeps this explicit and works even if a
      // future schema tightens one of today's cascading foreign keys.
      for (final item in delta.deletes.where(
        (item) => item.record.kind == WebDavSyncRegistryRecordKind.binding,
      )) {
        final record = item.record;
        await txn.delete(
          'profile_connection_bindings',
          where: 'profile_id = ? AND slot = ?',
          whereArgs: <Object>[record.profileId!, record.slot!],
        );
      }
      for (final item in delta.deletes.where(
        (item) => item.record.kind == WebDavSyncRegistryRecordKind.setting,
      )) {
        final record = item.record;
        await txn.delete(
          'profile_resource_settings',
          where: 'profile_id = ? AND resource_id = ?',
          whereArgs: <Object>[record.profileId!, record.resourceId!],
        );
      }
      for (final item in delta.deletes.where(
        (item) => item.record.kind == WebDavSyncRegistryRecordKind.grant,
      )) {
        final record = item.record;
        affectedProfileIds.add(record.profileId!);
        await txn.delete(
          'profile_resource_grants',
          where: 'profile_id = ? AND resource_id = ?',
          whereArgs: <Object>[record.profileId!, record.resourceId!],
        );
      }
      for (final resourceId in deletedResourceIds) {
        await txn.delete(
          'connection_resources',
          where: 'id = ?',
          whereArgs: <Object>[resourceId],
        );
      }
      for (final profileId in deletedProfileIds) {
        await txn.delete(
          'user_profiles',
          where: 'id = ?',
          whereArgs: <Object>[profileId],
        );
      }

      affectedProfileIds.removeAll(createdProfileIds);
      affectedProfileIds.removeAll(deletedProfileIds);
      for (final profileId in affectedProfileIds) {
        await txn.rawUpdate(
          '''UPDATE user_profiles
             SET authorization_revision = authorization_revision + 1,
                 updated_at_ms = ? WHERE id = ?''',
          <Object>[now, profileId],
        );
      }
      final foreignKeyFailures = await txn.rawQuery('PRAGMA foreign_key_check');
      if (foreignKeyFailures.isNotEmpty) {
        throw StateError('Synced registry delta violates foreign keys');
      }
      await _assertAdminInvariant(txn);
      return SyncedRegistryApplyResult.applied;
    });
    await checkpointTvOsRecovery();
    return result;
  }

  static Future<bool> _syncedDeltaMatchesObservedState(
    DatabaseExecutor db,
    SyncedRegistryDelta delta,
  ) async {
    Future<bool> matches(
      String table,
      String where,
      List<Object> whereArgs,
      int? expectedUpdatedAtMs,
    ) async {
      final rows = await db.query(
        table,
        columns: const <String>['updated_at_ms'],
        where: where,
        whereArgs: whereArgs,
        limit: 1,
      );
      return expectedUpdatedAtMs == null
          ? rows.isEmpty
          : rows.length == 1 &&
                rows.single['updated_at_ms'] == expectedUpdatedAtMs;
    }

    for (final item in delta.profiles) {
      if (!await matches('user_profiles', 'id = ?', <Object>[
        item.id,
      ], item.expectedPriorUpdatedAtMs)) {
        return false;
      }
    }
    for (final item in delta.resources) {
      if (!await matches('connection_resources', 'id = ?', <Object>[
        item.resource.id,
      ], item.expectedPriorUpdatedAtMs)) {
        return false;
      }
    }
    for (final item in delta.grants) {
      if (!await matches(
        'profile_resource_grants',
        'profile_id = ? AND resource_id = ?',
        <Object>[item.profileId, item.resourceId],
        item.expectedPriorUpdatedAtMs,
      )) {
        return false;
      }
    }
    for (final item in delta.settings) {
      if (!await matches(
        'profile_resource_settings',
        'profile_id = ? AND resource_id = ?',
        <Object>[item.profileId, item.resourceId],
        item.expectedPriorUpdatedAtMs,
      )) {
        return false;
      }
    }
    for (final item in delta.bindings) {
      if (!await matches(
        'profile_connection_bindings',
        'profile_id = ? AND slot = ?',
        <Object>[item.profileId, item.slot],
        item.expectedPriorUpdatedAtMs,
      )) {
        return false;
      }
    }
    for (final item in delta.deletes) {
      final record = item.record;
      final matched = switch (record.kind) {
        WebDavSyncRegistryRecordKind.profile => await matches(
          'user_profiles',
          'id = ?',
          <Object>[record.profileId!],
          item.expectedPriorUpdatedAtMs,
        ),
        WebDavSyncRegistryRecordKind.resource => await matches(
          'connection_resources',
          'id = ?',
          <Object>[record.resourceId!],
          item.expectedPriorUpdatedAtMs,
        ),
        WebDavSyncRegistryRecordKind.grant => await matches(
          'profile_resource_grants',
          'profile_id = ? AND resource_id = ?',
          <Object>[record.profileId!, record.resourceId!],
          item.expectedPriorUpdatedAtMs,
        ),
        WebDavSyncRegistryRecordKind.setting => await matches(
          'profile_resource_settings',
          'profile_id = ? AND resource_id = ?',
          <Object>[record.profileId!, record.resourceId!],
          item.expectedPriorUpdatedAtMs,
        ),
        WebDavSyncRegistryRecordKind.binding => await matches(
          'profile_connection_bindings',
          'profile_id = ? AND slot = ?',
          <Object>[record.profileId!, record.slot!],
          item.expectedPriorUpdatedAtMs,
        ),
      };
      if (!matched) return false;
    }
    return true;
  }

  static void _validateSyncedProfile(SyncedRegistryProfileRecord item) {
    if (!ProfileScope.isValidProfileId(item.id) || item.name.trim().isEmpty) {
      throw ArgumentError('Invalid synced profile');
    }
    _validateInactivityTimeout(item.inactivityTimeoutMinutes);
    _validateSyncedTimestamp(item.updatedAtMs);
    if (item.avatarKey?.startsWith('file:') == true) {
      throw ArgumentError('Synced profiles cannot introduce file avatars');
    }
    final pin = item.pin;
    if (pin.isCorrupt ||
        (pin.recoveryHash == null) != (pin.recoverySalt == null) ||
        (pin.recoveryHash == null) != (pin.recoveryParamsJson == null) ||
        (pin.hasRecoveryCode && !pin.hasPin)) {
      throw ArgumentError('Synced PIN record is incomplete');
    }
  }

  static void _validateSyncedTimestamp(int value) {
    if (value < 0) throw ArgumentError.value(value, 'updatedAtMs');
  }

  /// Atomically replaces an owner's resources of [types]. This is used by
  /// legacy collection-shaped APIs (WebDAV, IPTV, addons, and indexers) so a
  /// crash can never expose a half-replaced list. Shared resources are never
  /// silently deleted; [revokeBorrowers] must reflect an explicit,
  /// share-aware confirmation from the owner.
  Future<void> replaceOwnedResourceCollection({
    required String ownerProfileId,
    required Set<ConnectionResourceType> types,
    required List<PreparedConnectionResource> replacements,
    required int ownerPermissions,
    bool revokeBorrowers = false,
    Iterable<WebDavSyncRegistryRecordId> mergedBaselineRecords =
        const <WebDavSyncRegistryRecordId>[],
    String? actingProfileId,
    int? actingAuthorizationRevision,
    ProfileFeature? actingFeature,
  }) async {
    if (types.isEmpty) throw ArgumentError.value(types, 'types');
    for (final replacement in replacements) {
      _guardTvOsEnvelopeBound(replacement.sealedSecretPayload);
    }
    await authorityWillChangeCallback?.call();
    final typeNames = types.map((type) => type.name).toList(growable: false);
    if (replacements.any(
      (item) =>
          item.resource.ownerProfileId != ownerProfileId ||
          !types.contains(item.resource.type),
    )) {
      throw ArgumentError('Replacement resource does not match collection');
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.transaction((txn) async {
      if (actingProfileId != null ||
          actingAuthorizationRevision != null ||
          actingFeature != null) {
        if (actingProfileId == null ||
            actingAuthorizationRevision == null ||
            actingFeature == null) {
          throw ArgumentError('Incomplete collection mutation authority');
        }
        await _assertFeatureActor(
          txn,
          profileId: actingProfileId,
          authorizationRevision: actingAuthorizationRevision,
          feature: actingFeature,
        );
        if (actingProfileId != ownerProfileId) {
          throw StateError('Collection owner changed');
        }
      }
      final placeholders = List.filled(typeNames.length, '?').join(',');
      final existing = await txn.rawQuery(
        '''SELECT r.id, r.authorization_revision,
                  SUM(CASE WHEN g.profile_id != r.owner_profile_id THEN 1 ELSE 0 END)
                    AS borrower_count
           FROM connection_resources r
           LEFT JOIN profile_resource_grants g ON g.resource_id = r.id
           WHERE r.owner_profile_id = ? AND r.type IN ($placeholders)
           GROUP BY r.id''',
        <Object>[ownerProfileId, ...typeNames],
      );
      final existingById = <String, Map<String, Object?>>{
        for (final row in existing) row['id']! as String: row,
      };
      final replacementIds = <String>{};
      for (final replacement in replacements) {
        if (!replacementIds.add(replacement.resource.id)) {
          throw StateError('Replacement collection contains duplicate IDs');
        }
      }
      final removedIds = existing
          .map((row) => row['id']! as String)
          .where((id) => !replacementIds.contains(id))
          .toSet();
      if (existing.any(
        (row) =>
            (row['borrower_count'] as int? ?? 0) > 0 &&
            removedIds.contains(row['id']) &&
            !revokeBorrowers,
      )) {
        throw StateError(
          'A shared connection must be removed in profile management',
        );
      }
      final revokedBorrowerIds = <String>{};
      if (revokeBorrowers && removedIds.isNotEmpty) {
        final removedPlaceholders = List.filled(
          removedIds.length,
          '?',
        ).join(',');
        final grants = await txn.rawQuery(
          '''SELECT DISTINCT profile_id FROM profile_resource_grants
             WHERE resource_id IN ($removedPlaceholders)
               AND profile_id != ?''',
          <Object>[...removedIds, ownerProfileId],
        );
        revokedBorrowerIds.addAll(
          grants.map((row) => row['profile_id']! as String),
        );
      }
      await _recordRegistryDeleteCascade(
        txn,
        resourceIds: removedIds,
        mergedBaselineRecords: mergedBaselineRecords,
      );
      for (final row in existing) {
        if (replacementIds.contains(row['id'])) continue;
        await txn.delete(
          'connection_resources',
          where: 'id = ?',
          whereArgs: <Object>[row['id']!],
        );
      }
      for (final replacement in replacements) {
        final resource = replacement.resource;
        final prior = existingById[resource.id];
        if (prior == null) {
          if (resource.authorizationRevision != 1) {
            throw StateError('Replacement source is unavailable');
          }
          await txn.insert('connection_resources', <String, Object?>{
            'id': resource.id,
            'type': resource.type.name,
            'label': resource.label,
            'owner_profile_id': ownerProfileId,
            'public_config_json': jsonEncode(resource.publicConfig),
            'sealed_secret_payload': _encodeEnvelopeColumn(
              replacement.sealedSecretPayload,
            ),
            'secret_payload_version': replacement.secretPayloadVersion,
            'secret_pending': 0,
            'authorization_revision': resource.authorizationRevision,
            'created_at_ms': now,
            'updated_at_ms': now,
          });
          await _writeEnvelopeChunks(
            txn,
            'resource_secret_chunks',
            <String, Object?>{'resource_id': resource.id},
            replacement.sealedSecretPayload,
          );
        } else {
          final priorRevision = prior['authorization_revision']! as int;
          if (resource.authorizationRevision != priorRevision + 1) {
            throw StateError('Replacement source authority changed');
          }
          final changed = await txn.update(
            'connection_resources',
            <String, Object?>{
              'type': resource.type.name,
              'label': resource.label,
              'public_config_json': jsonEncode(resource.publicConfig),
              'sealed_secret_payload': _encodeEnvelopeColumn(
                replacement.sealedSecretPayload,
              ),
              'secret_payload_version': replacement.secretPayloadVersion,
              'secret_pending': 0,
              'authorization_revision': resource.authorizationRevision,
              'updated_at_ms': now,
              'disabled_at_ms': null,
            },
            where:
                'id = ? AND owner_profile_id = ? AND authorization_revision = ?',
            whereArgs: <Object>[resource.id, ownerProfileId, priorRevision],
          );
          if (changed != 1) {
            throw StateError('Replacement source authority changed');
          }
          await _writeEnvelopeChunks(
            txn,
            'resource_secret_chunks',
            <String, Object?>{'resource_id': resource.id},
            replacement.sealedSecretPayload,
          );
        }
        await _compatUpsert(
          txn,
          table: 'profile_resource_grants',
          insert: <String, Object?>{
            'profile_id': ownerProfileId,
            'resource_id': resource.id,
            'permissions': ownerPermissions,
            'granted_by_profile_id': ownerProfileId,
            'grant_origin_json': '{"origin":"ownerCollection"}',
            'created_at_ms': now,
            'updated_at_ms': now,
          },
          update: <String, Object?>{
            'permissions': ownerPermissions,
            'granted_by_profile_id': ownerProfileId,
            'grant_origin_json': '{"origin":"ownerCollection"}',
            'updated_at_ms': now,
          },
          key: <String, Object?>{
            'profile_id': ownerProfileId,
            'resource_id': resource.id,
          },
        );
      }
      await txn.rawUpdate(
        '''UPDATE user_profiles
           SET authorization_revision = authorization_revision + 1,
               updated_at_ms = ? WHERE id = ? AND disabled_at_ms IS NULL''',
        <Object>[now, ownerProfileId],
      );
      for (final profileId in revokedBorrowerIds) {
        await txn.rawUpdate(
          '''UPDATE user_profiles
             SET authorization_revision = authorization_revision + 1,
                 updated_at_ms = ? WHERE id = ?''',
          <Object>[now, profileId],
        );
      }
      await _assertAdminInvariant(txn);
    });
    await _finishRegistryDelete();
  }

  Future<ProfileResourceGrant?> getGrant(
    String profileId,
    String resourceId,
  ) async {
    final rows = await _db.query(
      'profile_resource_grants',
      where: 'profile_id = ? AND resource_id = ?',
      whereArgs: <Object>[profileId, resourceId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return ProfileResourceGrant(
      profileId: profileId,
      resourceId: resourceId,
      permissions: rows.single['permissions']! as int,
    );
  }

  Future<int> countResourceBorrowers({
    required String resourceId,
    required String ownerProfileId,
  }) async =>
      Sqflite.firstIntValue(
        await _db.rawQuery(
          '''SELECT COUNT(*) FROM profile_resource_grants
             WHERE resource_id = ? AND profile_id != ?''',
          <Object>[resourceId, ownerProfileId],
        ),
      ) ??
      0;

  Future<ProfileResourceSettings?> getProfileResourceSettings(
    String profileId,
    String resourceId,
  ) async {
    final rows = await _db.query(
      'profile_resource_settings',
      where: 'profile_id = ? AND resource_id = ?',
      whereArgs: <Object>[profileId, resourceId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final row = rows.single;
    return ProfileResourceSettings(
      profileId: profileId,
      resourceId: resourceId,
      enabled: row['enabled'] == 1,
      settings: Map<String, dynamic>.from(
        jsonDecode(row['settings_json']! as String) as Map,
      ),
    );
  }

  /// Writes profile-local presentation/enablement without changing the
  /// shared resource or any other borrower's view of it.
  Future<void> setProfileResourceSettings({
    required String profileId,
    required String resourceId,
    required bool enabled,
    required Map<String, dynamic> settings,
    required int actingAuthorizationRevision,
    required int expectedResourceAuthorizationRevision,
    required ProfileFeature feature,
  }) async {
    final encoded = jsonEncode(settings);
    if (encoded.length > 64 * 1024) {
      throw ArgumentError.value(settings, 'settings', 'Settings are too large');
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.transaction((txn) async {
      await _assertResourceActor(
        txn,
        profileId: profileId,
        authorizationRevision: actingAuthorizationRevision,
        feature: feature,
        resourceId: resourceId,
        resourceAuthorizationRevision: expectedResourceAuthorizationRevision,
        permission: ResourcePermission.use,
      );
      await _compatUpsert(
        txn,
        table: 'profile_resource_settings',
        insert: <String, Object?>{
          'profile_id': profileId,
          'resource_id': resourceId,
          'enabled': enabled ? 1 : 0,
          'settings_json': encoded,
          'updated_at_ms': now,
        },
        update: <String, Object?>{
          'enabled': enabled ? 1 : 0,
          'settings_json': encoded,
          'updated_at_ms': now,
        },
        key: <String, Object?>{
          'profile_id': profileId,
          'resource_id': resourceId,
        },
      );
    });
    await checkpointTvOsRecovery(webDavSyncRegistryChange: true);
  }

  Future<void> upsertGrant({
    required String profileId,
    required String resourceId,
    required int permissions,
    required String grantedByProfileId,
    required Map<String, dynamic> origin,
    String? bindingSlot,
    String? actingProfileId,
    int? actingAuthorizationRevision,
    int? expectedResourceAuthorizationRevision,
    int? expectedTargetAuthorizationRevision,
  }) async {
    final normalizedBindingSlot = bindingSlot?.trim();
    if (bindingSlot != null && normalizedBindingSlot!.isEmpty) {
      throw ArgumentError.value(bindingSlot, 'bindingSlot');
    }
    if (normalizedBindingSlot != null &&
        permissions & ResourcePermission.use.bit == 0) {
      throw ArgumentError(
        'A singleton credential binding requires use permission',
      );
    }
    await authorityWillChangeCallback?.call();
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.transaction((txn) async {
      if (actingProfileId != null ||
          actingAuthorizationRevision != null ||
          expectedResourceAuthorizationRevision != null ||
          expectedTargetAuthorizationRevision != null) {
        if (actingProfileId == null ||
            actingAuthorizationRevision == null ||
            expectedResourceAuthorizationRevision == null ||
            expectedTargetAuthorizationRevision == null) {
          throw ArgumentError('Incomplete resource-sharing authority');
        }
        await _assertResourceActor(
          txn,
          profileId: actingProfileId,
          authorizationRevision: actingAuthorizationRevision,
          feature: ProfileFeature.manageProfiles,
          resourceId: resourceId,
          resourceAuthorizationRevision: expectedResourceAuthorizationRevision,
          permission: ResourcePermission.share,
        );
      }
      final targetRows = await txn.query(
        'user_profiles',
        columns: const <String>['role', 'authorization_revision'],
        where: 'id = ? AND disabled_at_ms IS NULL',
        whereArgs: <Object>[profileId],
        limit: 1,
      );
      if (targetRows.isEmpty) {
        throw StateError('Target profile is unavailable');
      }
      if (expectedTargetAuthorizationRevision != null &&
          targetRows.single['authorization_revision'] !=
              expectedTargetAuthorizationRevision) {
        throw StateError('Target profile authorization changed');
      }
      if (normalizedBindingSlot != null) {
        final resourceRows = await txn.query(
          'connection_resources',
          columns: const <String>['type'],
          where: 'id = ? AND disabled_at_ms IS NULL',
          whereArgs: <Object>[resourceId],
          limit: 1,
        );
        if (resourceRows.isEmpty) {
          throw StateError('Connection is unavailable');
        }
        final type = ConnectionResourceType.values.byName(
          resourceRows.single['type']! as String,
        );
        if (type.singletonCredentialBindingSlot != normalizedBindingSlot) {
          throw StateError('Connection type does not fit binding slot');
        }
      }
      final targetRole = UserProfileRole.values.byName(
        targetRows.single['role']! as String,
      );
      if (targetRole == UserProfileRole.child &&
          permissions &
                  ~(ResourcePermission.use.bit |
                      ResourcePermission.download.bit) !=
              0) {
        throw StateError('Child resource permission ceiling exceeded');
      }
      await _compatUpsert(
        txn,
        table: 'profile_resource_grants',
        insert: <String, Object?>{
          'profile_id': profileId,
          'resource_id': resourceId,
          'permissions': permissions,
          'granted_by_profile_id': grantedByProfileId,
          'grant_origin_json': jsonEncode(origin),
          'created_at_ms': now,
          'updated_at_ms': now,
        },
        update: <String, Object?>{
          'permissions': permissions,
          'granted_by_profile_id': grantedByProfileId,
          'grant_origin_json': jsonEncode(origin),
          'updated_at_ms': now,
        },
        key: <String, Object?>{
          'profile_id': profileId,
          'resource_id': resourceId,
        },
      );
      if (normalizedBindingSlot != null) {
        await txn.insert(
          'profile_connection_bindings',
          <String, Object?>{
            'profile_id': profileId,
            'slot': normalizedBindingSlot,
            'resource_id': resourceId,
            'created_at_ms': now,
            'updated_at_ms': now,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      final revision = await _profileAuthorizationRevision(txn, profileId);
      await txn.update(
        'user_profiles',
        <String, Object?>{
          'authorization_revision': revision + 1,
          'updated_at_ms': now,
        },
        where: 'id = ?',
        whereArgs: <Object>[profileId],
      );
    });
    await checkpointTvOsRecovery(webDavSyncRegistryChange: true);
  }

  /// Repairs grants written by profile builds that shared singleton
  /// credentials without writing the compatibility binding. A slot is only
  /// repaired when the profile already has use permission and exactly one
  /// enabled candidate, so this never grants access or guesses between
  /// multiple accounts.
  Future<int> repairUnambiguousSingletonBindings() async {
    final candidates = await _db.rawQuery(
      '''SELECT g.profile_id, g.resource_id, r.type
         FROM profile_resource_grants g
         INNER JOIN connection_resources r ON r.id = g.resource_id
         INNER JOIN user_profiles p ON p.id = g.profile_id
         WHERE r.disabled_at_ms IS NULL
           AND p.disabled_at_ms IS NULL
           AND p.lifecycle_state = ?
           AND (g.permissions & ?) = ?
         ORDER BY g.profile_id, r.type, g.resource_id''',
      <Object>[
        UserProfileLifecycle.active.name,
        ResourcePermission.use.bit,
        ResourcePermission.use.bit,
      ],
    );
    final byProfileAndSlot = <String, List<String>>{};
    final profileAndSlot = <String, ({String profileId, String slot})>{};
    for (final row in candidates) {
      final type = ConnectionResourceType.values.byName(row['type']! as String);
      final slot = type.singletonCredentialBindingSlot;
      if (slot == null) continue;
      final profileId = row['profile_id']! as String;
      final key = '$profileId\u0000$slot';
      byProfileAndSlot
          .putIfAbsent(key, () => <String>[])
          .add(row['resource_id']! as String);
      profileAndSlot[key] = (profileId: profileId, slot: slot);
    }
    final repairs = byProfileAndSlot.entries
        .where((entry) => entry.value.length == 1)
        .toList(growable: false);
    if (repairs.isEmpty) return 0;

    await authorityWillChangeCallback?.call();
    final now = DateTime.now().millisecondsSinceEpoch;
    final repaired = await _db.transaction((txn) async {
      var count = 0;
      for (final repair in repairs) {
        final target = profileAndSlot[repair.key]!;
        final existing = await txn.query(
          'profile_connection_bindings',
          columns: const <String>['resource_id'],
          where: 'profile_id = ? AND slot = ?',
          whereArgs: <Object>[target.profileId, target.slot],
          limit: 1,
        );
        if (existing.isNotEmpty) continue;
        final stillEligible = await txn.rawQuery(
          '''SELECT r.id
             FROM profile_resource_grants g
             INNER JOIN connection_resources r ON r.id = g.resource_id
             INNER JOIN user_profiles p ON p.id = g.profile_id
             WHERE g.profile_id = ? AND r.type = ?
               AND r.disabled_at_ms IS NULL
               AND p.disabled_at_ms IS NULL
               AND p.lifecycle_state = ?
               AND (g.permissions & ?) = ?
             ORDER BY r.id''',
          <Object>[
            target.profileId,
            ConnectionResourceType.values
                .firstWhere(
                  (type) => type.singletonCredentialBindingSlot == target.slot,
                )
                .name,
            UserProfileLifecycle.active.name,
            ResourcePermission.use.bit,
            ResourcePermission.use.bit,
          ],
        );
        if (stillEligible.length != 1 ||
            stillEligible.single['id'] != repair.value.single) {
          continue;
        }
        await txn.insert('profile_connection_bindings', <String, Object?>{
          'profile_id': target.profileId,
          'slot': target.slot,
          'resource_id': repair.value.single,
          'created_at_ms': now,
          'updated_at_ms': now,
        });
        count++;
      }
      return count;
    });
    if (repaired != 0) {
      await checkpointTvOsRecovery(webDavSyncRegistryChange: true);
    } else {
      // Balance the pre-mutation fail-closed callback when a concurrent
      // change made every preflight repair unnecessary or ambiguous.
      await authorityChangedCallback?.call();
    }
    return repaired;
  }

  Future<void> revokeGrant(
    String profileId,
    String resourceId, {
    Iterable<WebDavSyncRegistryRecordId> mergedBaselineRecords =
        const <WebDavSyncRegistryRecordId>[],
    String? actingProfileId,
    int? actingAuthorizationRevision,
    int? expectedResourceAuthorizationRevision,
  }) async {
    await authorityWillChangeCallback?.call();
    await _db.transaction((txn) async {
      if (actingProfileId != null ||
          actingAuthorizationRevision != null ||
          expectedResourceAuthorizationRevision != null) {
        if (actingProfileId == null ||
            actingAuthorizationRevision == null ||
            expectedResourceAuthorizationRevision == null) {
          throw ArgumentError('Incomplete grant-revocation authority');
        }
        await _assertResourceActor(
          txn,
          profileId: actingProfileId,
          authorizationRevision: actingAuthorizationRevision,
          feature: ProfileFeature.manageProfiles,
          resourceId: resourceId,
          resourceAuthorizationRevision: expectedResourceAuthorizationRevision,
          permission: ResourcePermission.share,
          requireAdmin: true,
        );
      }
      await _recordRegistryDeleteCascade(
        txn,
        grantKeys: <String>{_registryGrantKey(profileId, resourceId)},
        mergedBaselineRecords: mergedBaselineRecords,
      );
      await txn.delete(
        'profile_connection_bindings',
        where: 'profile_id = ? AND resource_id = ?',
        whereArgs: <Object>[profileId, resourceId],
      );
      await txn.delete(
        'profile_resource_grants',
        where: 'profile_id = ? AND resource_id = ?',
        whereArgs: <Object>[profileId, resourceId],
      );
      final revision = await _profileAuthorizationRevision(txn, profileId);
      await txn.update(
        'user_profiles',
        <String, Object?>{
          'authorization_revision': revision + 1,
          'updated_at_ms': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: <Object>[profileId],
      );
    });
    await _finishRegistryDelete();
  }

  /// Atomically lets the active borrower reduce its own authority. This is
  /// separate from Admin revocation so disconnect remains available even if
  /// the associated product feature has just been disabled, while still
  /// binding the operation to the exact active profile/resource revisions.
  Future<void> detachBorrowedResource({
    required String profileId,
    required int authorizationRevision,
    required String resourceId,
    required int expectedResourceAuthorizationRevision,
    Iterable<WebDavSyncRegistryRecordId> mergedBaselineRecords =
        const <WebDavSyncRegistryRecordId>[],
  }) async {
    await authorityWillChangeCallback?.call();
    await _db.transaction((txn) async {
      final active = await txn.query(
        'device_state',
        columns: const <String>['active_profile_id'],
        where: 'singleton_id = 1',
        limit: 1,
      );
      final profiles = await txn.query(
        'user_profiles',
        columns: const <String>['authorization_revision'],
        where: 'id = ? AND disabled_at_ms IS NULL',
        whereArgs: <Object>[profileId],
        limit: 1,
      );
      final resources = await txn.query(
        'connection_resources',
        columns: const <String>['owner_profile_id', 'authorization_revision'],
        where: 'id = ? AND disabled_at_ms IS NULL',
        whereArgs: <Object>[resourceId],
        limit: 1,
      );
      final grants = await txn.query(
        'profile_resource_grants',
        columns: const <String>['profile_id'],
        where: 'profile_id = ? AND resource_id = ?',
        whereArgs: <Object>[profileId, resourceId],
        limit: 1,
      );
      if (active.isEmpty ||
          active.single['active_profile_id'] != profileId ||
          profiles.isEmpty ||
          profiles.single['authorization_revision'] != authorizationRevision ||
          resources.isEmpty ||
          resources.single['owner_profile_id'] == profileId ||
          resources.single['authorization_revision'] !=
              expectedResourceAuthorizationRevision ||
          grants.isEmpty) {
        throw StateError('Borrowed connection authorization changed');
      }
      await _recordRegistryDeleteCascade(
        txn,
        grantKeys: <String>{_registryGrantKey(profileId, resourceId)},
        mergedBaselineRecords: mergedBaselineRecords,
      );
      await txn.delete(
        'profile_connection_bindings',
        where: 'profile_id = ? AND resource_id = ?',
        whereArgs: <Object>[profileId, resourceId],
      );
      await txn.delete(
        'profile_resource_grants',
        where: 'profile_id = ? AND resource_id = ?',
        whereArgs: <Object>[profileId, resourceId],
      );
      await txn.rawUpdate(
        '''UPDATE user_profiles
           SET authorization_revision = authorization_revision + 1,
               updated_at_ms = ? WHERE id = ?''',
        <Object>[DateTime.now().millisecondsSinceEpoch, profileId],
      );
    });
    await _finishRegistryDelete();
  }

  Future<void> bindResource({
    required String profileId,
    required String slot,
    required String resourceId,
    int? actingAuthorizationRevision,
    int? expectedResourceAuthorizationRevision,
    ProfileFeature? actingFeature,
  }) async {
    if (slot.trim().isEmpty) throw ArgumentError.value(slot, 'slot');
    await authorityWillChangeCallback?.call();
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.transaction((txn) async {
      if (actingAuthorizationRevision != null ||
          expectedResourceAuthorizationRevision != null ||
          actingFeature != null) {
        if (actingAuthorizationRevision == null ||
            expectedResourceAuthorizationRevision == null ||
            actingFeature == null) {
          throw ArgumentError('Incomplete resource-binding authority');
        }
        await _assertResourceActor(
          txn,
          profileId: profileId,
          authorizationRevision: actingAuthorizationRevision,
          feature: actingFeature,
          resourceId: resourceId,
          resourceAuthorizationRevision: expectedResourceAuthorizationRevision,
          permission: ResourcePermission.use,
        );
      }
      await txn.insert(
        'profile_connection_bindings',
        <String, Object?>{
          'profile_id': profileId,
          'slot': slot,
          'resource_id': resourceId,
          'created_at_ms': now,
          'updated_at_ms': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
    await checkpointTvOsRecovery(webDavSyncRegistryChange: true);
  }

  Future<String?> getBoundResourceId(String profileId, String slot) async {
    final rows = await _db.query(
      'profile_connection_bindings',
      columns: const <String>['resource_id'],
      where: 'profile_id = ? AND slot = ?',
      whereArgs: <Object>[profileId, slot],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.single['resource_id']! as String;
  }

  Future<void> upsertJobOwnership({
    required String backend,
    required String externalJobId,
    required String kind,
    required String ownerProfileId,
    String? resourceId,
    required int profileAuthorizationRevision,
    int? resourceAuthorizationRevision,
    int? terminalAtMs,
  }) async {
    if (!const <String>{
      'download',
      'recording',
      'schedule',
      'retry',
    }.contains(kind)) {
      throw ArgumentError.value(kind, 'kind');
    }
    // Wrapped in a transaction: this is the one upsert not already inside
    // one, and the two-statement compat form must stay as atomic as the
    // single statement it replaced.
    await _db.transaction(
      (txn) => _compatUpsert(
        txn,
        table: 'job_ownership',
        insert: <String, Object?>{
          'backend': backend,
          'external_job_id': externalJobId,
          'kind': kind,
          'owner_profile_id': ownerProfileId,
          'resource_id': resourceId,
          'profile_authorization_revision': profileAuthorizationRevision,
          'resource_authorization_revision': resourceAuthorizationRevision,
          'created_at_ms': DateTime.now().millisecondsSinceEpoch,
          'terminal_at_ms': terminalAtMs,
        },
        // The original DO UPDATE SET deliberately left `kind` and
        // created_at_ms untouched on conflict — preserved here.
        update: <String, Object?>{
          'owner_profile_id': ownerProfileId,
          'resource_id': resourceId,
          'profile_authorization_revision': profileAuthorizationRevision,
          'resource_authorization_revision': resourceAuthorizationRevision,
          'terminal_at_ms': terminalAtMs,
        },
        key: <String, Object?>{
          'backend': backend,
          'external_job_id': externalJobId,
        },
      ),
    );
  }

  Future<List<Map<String, Object?>>> listJobOwnership({
    String? ownerProfileId,
    bool includeTerminal = true,
  }) async {
    final clauses = <String>[
      if (ownerProfileId != null) 'owner_profile_id = ?',
      if (!includeTerminal) 'terminal_at_ms IS NULL',
    ];
    return _db.query(
      'job_ownership',
      where: clauses.isEmpty ? null : clauses.join(' AND '),
      whereArgs: ownerProfileId == null ? null : <Object>[ownerProfileId],
      orderBy: 'created_at_ms, backend, external_job_id',
    );
  }

  Future<void> markJobTerminal({
    required String backend,
    required String externalJobId,
  }) async {
    await _db.update(
      'job_ownership',
      <String, Object?>{
        'terminal_at_ms': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'backend = ? AND external_job_id = ?',
      whereArgs: <Object>[backend, externalJobId],
    );
  }

  Future<void> markMissingJobsTerminal({
    required String backend,
    required String ownerProfileId,
    required Set<String> presentExternalJobIds,
  }) async {
    final rows = await _db.query(
      'job_ownership',
      columns: const <String>['external_job_id'],
      where: 'backend = ? AND owner_profile_id = ? AND terminal_at_ms IS NULL',
      whereArgs: <Object>[backend, ownerProfileId],
    );
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final row in rows) {
      final id = row['external_job_id']! as String;
      if (presentExternalJobIds.contains(id)) continue;
      await _db.update(
        'job_ownership',
        <String, Object?>{'terminal_at_ms': now},
        where: 'backend = ? AND external_job_id = ?',
        whereArgs: <Object>[backend, id],
      );
    }
  }

  Future<void> upsertOwnedArtifact({
    required String kind,
    required String ownerProfileId,
    required String canonicalPath,
    int? sizeBytes,
    int? modifiedAtMs,
  }) async {
    if (!const <String>{'download', 'recording'}.contains(kind)) {
      throw ArgumentError.value(kind, 'kind');
    }
    if (canonicalPath.trim().isEmpty || canonicalPath.length > 16 * 1024) {
      throw ArgumentError.value(canonicalPath, 'canonicalPath');
    }
    await _db.transaction((txn) async {
      final existing = await txn.query(
        'owned_artifacts',
        columns: const <String>[
          'id',
          'owner_profile_id',
          'ownership_state',
          'created_at_ms',
        ],
        where: 'kind = ? AND canonical_path = ?',
        whereArgs: <Object>[kind, canonicalPath],
        limit: 1,
      );
      if (existing.isNotEmpty &&
          existing.single['ownership_state'] == 'assigned' &&
          existing.single['owner_profile_id'] != ownerProfileId) {
        throw StateError('Artifact is already owned by another profile');
      }
      final now = DateTime.now().millisecondsSinceEpoch;
      await txn.insert('owned_artifacts', <String, Object?>{
        'id': existing.isEmpty ? _newId() : existing.single['id'],
        'kind': kind,
        'owner_profile_id': ownerProfileId,
        'canonical_path': canonicalPath,
        'ownership_state': 'assigned',
        'detached_owner_token': null,
        'size_bytes': sizeBytes,
        'modified_at_ms': modifiedAtMs ?? now,
        'created_at_ms': existing.isEmpty
            ? now
            : existing.single['created_at_ms'],
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  /// Records a scan-only public file without guessing which profile owns it.
  /// Existing assigned/detached rows always win: merely opening an Admin
  /// recovery view must never transfer another profile's artifact.
  Future<void> recordUnassignedArtifact({
    required String kind,
    required String canonicalPath,
    int? sizeBytes,
    int? modifiedAtMs,
  }) async {
    if (!const <String>{'download', 'recording'}.contains(kind)) {
      throw ArgumentError.value(kind, 'kind');
    }
    if (canonicalPath.trim().isEmpty || canonicalPath.length > 16 * 1024) {
      throw ArgumentError.value(canonicalPath, 'canonicalPath');
    }
    await _db.transaction((txn) async {
      final existing = await txn.query(
        'owned_artifacts',
        columns: const <String>['id'],
        where: 'kind = ? AND canonical_path = ?',
        whereArgs: <Object>[kind, canonicalPath],
        limit: 1,
      );
      if (existing.isNotEmpty) return;
      final now = DateTime.now().millisecondsSinceEpoch;
      await txn.insert('owned_artifacts', <String, Object?>{
        'id': _newId(),
        'kind': kind,
        'owner_profile_id': null,
        'canonical_path': canonicalPath,
        'ownership_state': 'unassigned',
        'detached_owner_token': null,
        'size_bytes': sizeBytes,
        'modified_at_ms': modifiedAtMs ?? now,
        'created_at_ms': now,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    });
  }

  Future<List<Map<String, Object?>>> listOwnedArtifacts(
    String ownerProfileId,
  ) => _db.query(
    'owned_artifacts',
    where: 'owner_profile_id = ?',
    whereArgs: <Object>[ownerProfileId],
    orderBy: 'created_at_ms, id',
  );

  Future<List<Map<String, Object?>>> listUnassignedArtifacts() => _db.query(
    'owned_artifacts',
    where: "ownership_state = 'unassigned'",
    orderBy: 'created_at_ms, id',
  );

  Future<void> removeArtifactRecord({
    required String kind,
    required String canonicalPath,
  }) async {
    if (!const <String>{'download', 'recording'}.contains(kind)) {
      throw ArgumentError.value(kind, 'kind');
    }
    await _db.delete(
      'owned_artifacts',
      where: 'kind = ? AND canonical_path = ?',
      whereArgs: <Object>[kind, canonicalPath],
    );
  }

  Future<void> removeOwnedArtifactRecords({
    required String ownerProfileId,
    required String actingProfileId,
    required int actingAuthorizationRevision,
    required int actingSessionEpoch,
  }) async {
    await _db.transaction((txn) async {
      await _assertManagingActor(
        txn,
        actingProfileId,
        actingAuthorizationRevision,
        actingSessionEpoch,
      );
      await txn.delete(
        'owned_artifacts',
        where: 'owner_profile_id = ?',
        whereArgs: <Object>[ownerProfileId],
      );
    });
    await checkpointTvOsRecovery();
  }

  Future<ProfilePinRecord?> getPinRecord(
    String profileId, {
    bool includeDisabled = false,
  }) async {
    final rows = await _db.query(
      'user_profiles',
      columns: const <String>[
        'pin_hash',
        'pin_salt',
        'pin_params_json',
        'failed_pin_attempts',
        'locked_until_ms',
        'pin_reset_required',
        'recovery_hash',
        'recovery_salt',
        'recovery_params_json',
      ],
      where: includeDisabled ? 'id = ?' : 'id = ? AND disabled_at_ms IS NULL',
      whereArgs: <Object>[profileId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final row = rows.single;
    return ProfilePinRecord(
      hash: row['pin_hash'] as Uint8List?,
      salt: row['pin_salt'] as Uint8List?,
      paramsJson: row['pin_params_json'] as String?,
      failedAttempts: row['failed_pin_attempts']! as int,
      lockedUntilMs: row['locked_until_ms'] as int?,
      resetRequired: row['pin_reset_required'] == 1,
      recoveryHash: row['recovery_hash'] as Uint8List?,
      recoverySalt: row['recovery_salt'] as Uint8List?,
      recoveryParamsJson: row['recovery_params_json'] as String?,
    );
  }

  Future<void> setPinRecord({
    required String profileId,
    required List<int>? hash,
    required List<int>? salt,
    required String? paramsJson,
    List<int>? recoveryHash,
    List<int>? recoverySalt,
    String? recoveryParamsJson,
    bool resetRequired = false,
    String? actingProfileId,
    int? actingAuthorizationRevision,
    int? actingSessionEpoch,
  }) async {
    await authorityWillChangeCallback?.call();
    if ((hash == null) != (salt == null) ||
        (hash == null) != (paramsJson == null)) {
      throw ArgumentError(
        'PIN hash, salt, and parameters must be set together',
      );
    }
    if ((recoveryHash == null) != (recoverySalt == null) ||
        (recoveryHash == null) != (recoveryParamsJson == null) ||
        (recoveryHash != null && hash == null)) {
      throw ArgumentError(
        'A recovery code must be complete and accompany a PIN',
      );
    }
    var changed = 0;
    await _db.transaction((txn) async {
      await _assertManagingActor(
        txn,
        actingProfileId,
        actingAuthorizationRevision,
        actingSessionEpoch,
      );
      changed = await txn.update(
        'user_profiles',
        <String, Object?>{
          'pin_hash': hash == null ? null : Uint8List.fromList(hash),
          'pin_salt': salt == null ? null : Uint8List.fromList(salt),
          'pin_params_json': paramsJson,
          // The recovery code lives and dies with the PIN it can reset:
          // setting a PIN without one, or clearing the PIN, clears it.
          'recovery_hash': recoveryHash == null
              ? null
              : Uint8List.fromList(recoveryHash),
          'recovery_salt': recoverySalt == null
              ? null
              : Uint8List.fromList(recoverySalt),
          'recovery_params_json': recoveryParamsJson,
          'pin_reset_required': resetRequired ? 1 : 0,
          'failed_pin_attempts': 0,
          'locked_until_ms': null,
          'updated_at_ms': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'id = ? AND disabled_at_ms IS NULL',
        whereArgs: <Object>[profileId],
      );
    });
    if (changed != 1) throw StateError('Profile does not exist');
    await checkpointTvOsRecovery(webDavSyncRegistryChange: true);
  }

  /// Replaces the unlocked active profile's PIN only when the credential the
  /// caller confirmed is still current. The target is necessarily the actor;
  /// Admin reset of another profile remains on [setPinRecord].
  Future<void> setActiveProfilePinRecordIfUnchanged({
    required String profileId,
    required ProfilePinRecord expected,
    required List<int>? hash,
    required List<int>? salt,
    required String? paramsJson,
    required List<int>? recoveryHash,
    required List<int>? recoverySalt,
    required String? recoveryParamsJson,
    required int actingAuthorizationRevision,
    required int actingSessionEpoch,
  }) async {
    if ((hash == null) != (salt == null) ||
        (hash == null) != (paramsJson == null) ||
        (recoveryHash == null) != (recoverySalt == null) ||
        (recoveryHash == null) != (recoveryParamsJson == null) ||
        (recoveryHash != null && hash == null)) {
      throw ArgumentError('Incomplete PIN or recovery credential');
    }
    try {
      await authorityWillChangeCallback?.call();
      var changed = false;
      await _db.transaction((txn) async {
        await _assertActiveSessionActor(
          txn,
          profileId: profileId,
          authorizationRevision: actingAuthorizationRevision,
          sessionEpoch: actingSessionEpoch,
        );
        final rows = await txn.query(
          'user_profiles',
          columns: const <String>[
            'pin_hash',
            'pin_salt',
            'pin_params_json',
            'pin_reset_required',
            'recovery_hash',
            'recovery_salt',
            'recovery_params_json',
          ],
          where:
              "id = ? AND disabled_at_ms IS NULL AND lifecycle_state = 'active'",
          whereArgs: <Object>[profileId],
          limit: 1,
        );
        if (rows.isEmpty ||
            !_pinAndRecoveryRecordMatches(rows.single, expected)) {
          return;
        }
        final count = await txn.update(
          'user_profiles',
          <String, Object?>{
            'pin_hash': hash == null ? null : Uint8List.fromList(hash),
            'pin_salt': salt == null ? null : Uint8List.fromList(salt),
            'pin_params_json': paramsJson,
            'recovery_hash': recoveryHash == null
                ? null
                : Uint8List.fromList(recoveryHash),
            'recovery_salt': recoverySalt == null
                ? null
                : Uint8List.fromList(recoverySalt),
            'recovery_params_json': recoveryParamsJson,
            'pin_reset_required': 0,
            'failed_pin_attempts': 0,
            'locked_until_ms': null,
            'updated_at_ms': DateTime.now().millisecondsSinceEpoch,
          },
          where: 'id = ?',
          whereArgs: <Object>[profileId],
        );
        changed = count == 1;
      });
      if (!changed) throw StateError('PIN authorization changed');
      await checkpointTvOsRecovery(webDavSyncRegistryChange: true);
    } catch (error, stackTrace) {
      // `authorityWillChangeCallback` denies native readers before the
      // transaction. Any rejection or publication failure must republish the
      // currently active authority, not leave a stale session's denial live.
      try {
        await authorityChangedCallback?.call();
      } catch (_) {
        // Preserve the initiating failure. A later lifecycle publication can
        // retry, while callers still resolve whether their DB write committed.
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  /// Records a failed attempt only if the PIN credential observed by the
  /// verifier is still current. An Admin reset racing the KDF must not lock
  /// the replacement credential.
  Future<ProfilePinRecord?> recordPinFailureIfUnchanged({
    required String profileId,
    required int nowMs,
    required ProfilePinRecord expected,
  }) async {
    final record = await _db.transaction((txn) async {
      final rows = await txn.query(
        'user_profiles',
        columns: const <String>[
          'pin_hash',
          'pin_salt',
          'pin_params_json',
          'pin_reset_required',
          'failed_pin_attempts',
        ],
        where: 'id = ? AND disabled_at_ms IS NULL',
        whereArgs: <Object>[profileId],
        limit: 1,
      );
      if (rows.isEmpty) throw StateError('Profile does not exist');
      if (!_pinRecordMatches(rows.single, expected)) return null;
      final attempts = (rows.single['failed_pin_attempts']! as int) + 1;
      // Household-lenient throttle (2026-08 product call): a family fumbling
      // a shared remote gets 100 free attempts; only after that does the
      // 30s-doubling lock (capped 1h) engage to keep scripted guessing out.
      final exponent = (attempts - 100).clamp(0, 7);
      final lockSeconds = attempts < 100 ? 0 : min(3600, 30 * (1 << exponent));
      final lockedUntil = lockSeconds == 0 ? null : nowMs + lockSeconds * 1000;
      await txn.update(
        'user_profiles',
        <String, Object?>{
          'failed_pin_attempts': attempts,
          'locked_until_ms': lockedUntil,
          'updated_at_ms': nowMs,
        },
        where: 'id = ?',
        whereArgs: <Object>[profileId],
      );
      return ProfilePinRecord(
        failedAttempts: attempts,
        lockedUntilMs: lockedUntil,
      );
    });
    if (record != null) await checkpointTvOsRecovery();
    return record;
  }

  /// One-shot self-service PIN removal proven by the recovery code. Clears
  /// the PIN, the (now spent) recovery code, the throttle state, and any
  /// pending reset flag in one conditional write — the caller has already
  /// verified the code against exactly [expected], so a concurrent Admin
  /// change makes this a no-op instead of erasing a newer credential.
  Future<bool> clearPinViaRecoveryIfUnchanged({
    required String profileId,
    required ProfilePinRecord expected,
  }) async {
    await authorityWillChangeCallback?.call();
    var changed = false;
    await _db.transaction((txn) async {
      final rows = await txn.query(
        'user_profiles',
        columns: const <String>[
          'pin_hash',
          'pin_salt',
          'pin_params_json',
          'pin_reset_required',
        ],
        where: 'id = ? AND disabled_at_ms IS NULL',
        whereArgs: <Object>[profileId],
        limit: 1,
      );
      if (rows.isEmpty) throw StateError('Profile does not exist');
      if (!_pinRecordMatches(rows.single, expected)) return;
      changed =
          await txn.update(
            'user_profiles',
            <String, Object?>{
              'pin_hash': null,
              'pin_salt': null,
              'pin_params_json': null,
              'recovery_hash': null,
              'recovery_salt': null,
              'recovery_params_json': null,
              'pin_reset_required': 0,
              'failed_pin_attempts': 0,
              'locked_until_ms': null,
              'updated_at_ms': DateTime.now().millisecondsSinceEpoch,
            },
            where: 'id = ?',
            whereArgs: <Object>[profileId],
          ) ==
          1;
    });
    if (changed) {
      await checkpointTvOsRecovery(webDavSyncRegistryChange: true);
    }
    return changed;
  }

  Future<bool> normalizePinLockIfUnchanged({
    required String profileId,
    required int lockedUntilMs,
    required ProfilePinRecord expected,
  }) async {
    var changed = false;
    await _db.transaction((txn) async {
      final rows = await txn.query(
        'user_profiles',
        columns: const <String>[
          'pin_hash',
          'pin_salt',
          'pin_params_json',
          'pin_reset_required',
        ],
        where: 'id = ? AND disabled_at_ms IS NULL',
        whereArgs: <Object>[profileId],
        limit: 1,
      );
      if (rows.isEmpty || !_pinRecordMatches(rows.single, expected)) return;
      changed =
          await txn.update(
            'user_profiles',
            <String, Object?>{
              'locked_until_ms': lockedUntilMs,
              'updated_at_ms': DateTime.now().millisecondsSinceEpoch,
            },
            where: 'id = ? AND disabled_at_ms IS NULL',
            whereArgs: <Object>[profileId],
          ) ==
          1;
    });
    if (changed) await checkpointTvOsRecovery();
    return changed;
  }

  /// Completes successful verification only against the exact credential that
  /// was checked. Optional replacement values perform an atomic KDF upgrade.
  Future<bool> completePinVerificationIfUnchanged({
    required String profileId,
    required ProfilePinRecord expected,
    List<int>? replacementHash,
    List<int>? replacementSalt,
    String? replacementParamsJson,
  }) async {
    final replacing = replacementHash != null;
    if (replacing != (replacementSalt != null) ||
        replacing != (replacementParamsJson != null)) {
      throw ArgumentError('Replacement PIN fields must be set together');
    }
    var changed = false;
    await _db.transaction((txn) async {
      final rows = await txn.query(
        'user_profiles',
        columns: const <String>[
          'pin_hash',
          'pin_salt',
          'pin_params_json',
          'pin_reset_required',
        ],
        where: 'id = ? AND disabled_at_ms IS NULL',
        whereArgs: <Object>[profileId],
        limit: 1,
      );
      if (rows.isEmpty || !_pinRecordMatches(rows.single, expected)) return;
      changed =
          await txn.update(
            'user_profiles',
            <String, Object?>{
              if (replacing) 'pin_hash': Uint8List.fromList(replacementHash),
              if (replacing) 'pin_salt': Uint8List.fromList(replacementSalt!),
              if (replacing) 'pin_params_json': replacementParamsJson,
              'failed_pin_attempts': 0,
              'locked_until_ms': null,
              'updated_at_ms': DateTime.now().millisecondsSinceEpoch,
            },
            where: 'id = ? AND disabled_at_ms IS NULL',
            whereArgs: <Object>[profileId],
          ) ==
          1;
    });
    if (changed) {
      await checkpointTvOsRecovery(webDavSyncRegistryChange: replacing);
    }
    return changed;
  }

  /// Fail-closed integrity repair. This path cannot choose a new PIN and is
  /// conditional on the corrupt record still being current, so it cannot
  /// overwrite a concurrent Admin reset.
  Future<bool> markPinResetRequiredIfUnchanged({
    required String profileId,
    required ProfilePinRecord expected,
  }) async {
    var changed = false;
    await _db.transaction((txn) async {
      final rows = await txn.query(
        'user_profiles',
        columns: const <String>[
          'pin_hash',
          'pin_salt',
          'pin_params_json',
          'pin_reset_required',
        ],
        where: 'id = ? AND disabled_at_ms IS NULL',
        whereArgs: <Object>[profileId],
        limit: 1,
      );
      if (rows.isEmpty || !_pinRecordMatches(rows.single, expected)) return;
      changed =
          await txn.update(
            'user_profiles',
            <String, Object?>{
              'pin_hash': null,
              'pin_salt': null,
              'pin_params_json': null,
              // The recovery code dies with the PIN it could reset — an
              // Admin-forced reset must not leave a code that could undo it.
              'recovery_hash': null,
              'recovery_salt': null,
              'recovery_params_json': null,
              'pin_reset_required': 1,
              'failed_pin_attempts': 0,
              'locked_until_ms': null,
              'updated_at_ms': DateTime.now().millisecondsSinceEpoch,
            },
            where: 'id = ? AND disabled_at_ms IS NULL',
            whereArgs: <Object>[profileId],
          ) ==
          1;
    });
    if (changed) {
      await checkpointTvOsRecovery(webDavSyncRegistryChange: true);
    }
    return changed;
  }

  Future<bool> isMigrationCommitted() async {
    final rows = await _db.query(
      'device_state',
      columns: <String>['migration_state'],
      where: 'singleton_id = 1',
      limit: 1,
    );
    return rows.isNotEmpty && rows.single['migration_state'] == 'committed';
  }

  Future<void> beginProfileGraphRestore({
    required String operationId,
    required List<String> stagedProfileIds,
  }) async {
    if (stagedProfileIds.isEmpty ||
        stagedProfileIds.any((id) => !ProfileScope.isValidProfileId(id))) {
      throw ArgumentError.value(stagedProfileIds, 'stagedProfileIds');
    }
    await _db.insert('profile_restore_journal', <String, Object?>{
      'restore_id': operationId,
      'mode': 'registryReplace',
      'stage': 'staging',
      'payload_json': jsonEncode(<String, Object?>{
        'schemaVersion': 1,
        'stagedProfileIds': stagedProfileIds,
      }),
      'updated_at_ms': DateTime.now().millisecondsSinceEpoch,
    });
    await checkpointTvOsRecovery();
  }

  Future<void> verifyProfileGraphRestore(String operationId) async {
    await _db.transaction((txn) async {
      final journal = await txn.query(
        'profile_restore_journal',
        columns: const <String>['payload_json'],
        where:
            "restore_id = ? AND mode = 'registryReplace' AND stage = 'staging'",
        whereArgs: <Object>[operationId],
        limit: 1,
      );
      if (journal.isEmpty) {
        throw StateError('Profile graph restore is unavailable');
      }
      final payload = jsonDecode(journal.single['payload_json']! as String);
      final ids = payload is Map
          ? (payload['stagedProfileIds'] as List?)?.whereType<String>().toList()
          : null;
      if (ids == null || ids.isEmpty) {
        throw StateError('Profile graph restore has no staged profiles');
      }
      final rows = await txn.rawQuery(
        '''SELECT g.profile_id, g.manifest_json, g.manifest_hash
           FROM profile_data_generations g
           INNER JOIN user_profiles p ON p.id = g.profile_id
           WHERE g.generation = 1 AND p.lifecycle_state = 'staging'
             AND g.profile_id IN (${List.filled(ids.length, '?').join(',')})''',
        ids,
      );
      if (rows.length != ids.length ||
          rows.any(
            (row) =>
                row['manifest_json'] == '{}' ||
                (row['manifest_hash'] as String? ?? '').isEmpty,
          )) {
        throw StateError('Profile graph generation is not finalized');
      }
      final changed = await txn.update(
        'profile_restore_journal',
        <String, Object?>{
          'stage': 'verified',
          'updated_at_ms': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'restore_id = ? AND stage = ?',
        whereArgs: <Object>[operationId, 'staging'],
      );
      if (changed != 1) {
        throw StateError('Profile graph restore is unavailable');
      }
    });
    await checkpointTvOsRecovery();
  }

  Future<void> finalizeGraphProfileGeneration({
    required String operationId,
    required String profileId,
    required Map<String, dynamic> manifest,
    required String manifestHash,
  }) async {
    if (manifest.isEmpty || manifestHash.isEmpty) {
      throw ArgumentError('Graph generation manifest is empty');
    }
    final changed = await _db.rawUpdate(
      '''UPDATE profile_data_generations
         SET manifest_json = ?, manifest_hash = ?, updated_at_ms = ?
         WHERE profile_id = ? AND generation = 1
           AND EXISTS (
             SELECT 1 FROM user_profiles p
             WHERE p.id = profile_data_generations.profile_id
               AND p.lifecycle_state = 'staging'
           )
           AND EXISTS (
             SELECT 1 FROM profile_restore_journal j
             WHERE j.restore_id = ? AND j.mode = 'registryReplace'
               AND j.stage = 'staging'
           )''',
      <Object>[
        jsonEncode(manifest),
        manifestHash,
        DateTime.now().millisecondsSinceEpoch,
        profileId,
        operationId,
      ],
    );
    if (changed != 1) {
      throw StateError('Graph profile generation is unavailable');
    }
    await checkpointTvOsRecovery();
  }

  Future<({Map<String, dynamic> manifest, String hash})>
  stagedGraphProfileGeneration({
    required String operationId,
    required String profileId,
  }) async {
    final rows = await _db.rawQuery(
      '''SELECT g.manifest_json, g.manifest_hash
         FROM profile_data_generations g
         INNER JOIN user_profiles p ON p.id = g.profile_id
         WHERE g.profile_id = ? AND g.generation = 1
           AND p.lifecycle_state = 'staging'
           AND EXISTS (
             SELECT 1 FROM profile_restore_journal j
             WHERE j.restore_id = ? AND j.mode = 'registryReplace'
               AND j.stage IN ('staging', 'verified')
           )''',
      <Object>[profileId, operationId],
    );
    if (rows.length != 1) {
      throw StateError('Graph profile generation is unavailable');
    }
    final decoded = jsonDecode(rows.single['manifest_json']! as String);
    final hash = rows.single['manifest_hash'] as String? ?? '';
    if (decoded is! Map || hash.isEmpty) {
      throw StateError('Graph profile generation is not finalized');
    }
    return (manifest: Map<String, dynamic>.from(decoded), hash: hash);
  }

  /// Returns the integrity evidence for an already-known generation. This is
  /// intentionally read-only and never treats a manifest as visibility
  /// authority; callers must still resolve the profile's visible generation.
  Future<({Map<String, dynamic> manifest, String hash})?>
  profileGenerationManifest({
    required String profileId,
    required int generation,
  }) async {
    if (!ProfileScope.isValidProfileId(profileId) || generation < 1) {
      throw ArgumentError('Invalid profile generation');
    }
    final rows = await _db.query(
      'profile_data_generations',
      columns: const <String>['manifest_json', 'manifest_hash'],
      where: 'profile_id = ? AND generation = ?',
      whereArgs: <Object>[profileId, generation],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final decoded = jsonDecode(rows.single['manifest_json']! as String);
    final hash = rows.single['manifest_hash'] as String? ?? '';
    if (decoded is! Map || hash.isEmpty) return null;
    return (manifest: Map<String, dynamic>.from(decoded), hash: hash);
  }

  /// Publishes only rows that have already been staged under lifecycle
  /// `staging`. The active/recovery Admin remains untouched. Imported
  /// resources, grants, bindings and profile visibility become visible in
  /// this single registry transaction.
  Future<void> publishProfileGraphRestore({
    required String operationId,
    required List<String> stagedProfileIds,
    required List<StagedGraphResource> resources,
    List<GraphRestoreDefaultGrantPrune> redundantDefaultAddonGrants =
        const <GraphRestoreDefaultGrantPrune>[],
    Iterable<WebDavSyncRegistryRecordId> mergedBaselineRecords =
        const <WebDavSyncRegistryRecordId>[],
  }) async {
    for (final item in resources) {
      _guardTvOsEnvelopeBound(item.sealedSecretPayload);
    }
    await authorityWillChangeCallback?.call();
    final now = DateTime.now().millisecondsSinceEpoch;
    final profileIds = stagedProfileIds.toSet();
    if (profileIds.length != stagedProfileIds.length) {
      throw ArgumentError('Duplicate staged profile ID');
    }
    final pruneKeys = <String>{};
    for (final prune in redundantDefaultAddonGrants) {
      if (!profileIds.contains(prune.profileId) ||
          !pruneKeys.add('${prune.profileId}\u0000${prune.resourceId}')) {
        throw ArgumentError('Invalid redundant default addon grant');
      }
    }
    await _db.transaction((txn) async {
      final journal = await txn.query(
        'profile_restore_journal',
        columns: const <String>['stage', 'payload_json'],
        where: "restore_id = ? AND mode = 'registryReplace'",
        whereArgs: <Object>[operationId],
        limit: 1,
      );
      if (journal.isEmpty || journal.single['stage'] != 'verified') {
        throw StateError('Profile graph has not been verified');
      }
      final journalPayload = jsonDecode(
        journal.single['payload_json']! as String,
      );
      final recordedIds = journalPayload is Map
          ? (journalPayload['stagedProfileIds'] as List?)
                ?.whereType<String>()
                .toSet()
          : null;
      if (recordedIds == null ||
          recordedIds.length != profileIds.length ||
          !recordedIds.containsAll(profileIds)) {
        throw StateError('Profile graph journal does not match publication');
      }
      final stagedRows = await txn.query(
        'user_profiles',
        columns: const <String>['id'],
        where:
            "lifecycle_state = 'staging' AND id IN (${List.filled(profileIds.length, '?').join(',')})",
        whereArgs: profileIds.toList(growable: false),
      );
      if (stagedRows.length != profileIds.length) {
        throw StateError('One or more imported profiles are unavailable');
      }
      // Profile staging normally inherits existing shareable resources. When
      // the imported graph supplies the same configured addon, retaining that
      // defaultSeed grant exposes two indistinguishable addons to the profile.
      // Prune only the preflighted default grants, in this publication
      // transaction; receiver-only resources remain inherited.
      for (final prune in redundantDefaultAddonGrants) {
        final rows = await txn.rawQuery(
          '''SELECT g.grant_origin_json, r.type, r.authorization_revision
             FROM profile_resource_grants g
             INNER JOIN connection_resources r ON r.id = g.resource_id
             WHERE g.profile_id = ? AND g.resource_id = ?''',
          <Object>[prune.profileId, prune.resourceId],
        );
        if (rows.length != 1 ||
            rows.single['type'] != ConnectionResourceType.stremioAddon.name ||
            rows.single['authorization_revision'] !=
                prune.expectedResourceAuthorizationRevision ||
            !_isDefaultSeedGrantOrigin(rows.single['grant_origin_json'])) {
          throw StateError('Redundant default addon grant changed');
        }
        await _recordRegistryDeleteCascade(
          txn,
          grantKeys: <String>{
            _registryGrantKey(prune.profileId, prune.resourceId),
          },
          mergedBaselineRecords: mergedBaselineRecords,
        );
        final deleted = await txn.delete(
          'profile_resource_grants',
          where: 'profile_id = ? AND resource_id = ?',
          whereArgs: <Object>[prune.profileId, prune.resourceId],
        );
        if (deleted != 1) {
          throw StateError('Redundant default addon grant changed');
        }
      }
      for (final item in resources) {
        if (!profileIds.contains(item.ownerProfileId)) {
          throw StateError('Imported resource owner is not staged');
        }
        await txn.insert('connection_resources', <String, Object?>{
          'id': item.id,
          'type': item.type.name,
          'label': item.label,
          'owner_profile_id': item.ownerProfileId,
          'public_config_json': jsonEncode(item.publicConfig),
          'sealed_secret_payload': _encodeEnvelopeColumn(
            item.sealedSecretPayload,
          ),
          'secret_payload_version': item.secretPayloadVersion,
          'secret_pending': 0,
          'authorization_revision': 1,
          'created_at_ms': now,
          'updated_at_ms': now,
          'disabled_at_ms': item.enabled ? null : now,
        });
        await _writeEnvelopeChunks(
          txn,
          'resource_secret_chunks',
          <String, Object?>{'resource_id': item.id},
          item.sealedSecretPayload,
        );
        for (final grant in item.grants) {
          if (!profileIds.contains(grant.profileId)) {
            throw StateError('Imported grant target is not staged');
          }
          await txn.insert('profile_resource_grants', <String, Object?>{
            'profile_id': grant.profileId,
            'resource_id': item.id,
            'permissions': grant.permissions,
            'granted_by_profile_id': item.ownerProfileId,
            'grant_origin_json': jsonEncode(<String, Object?>{
              'origin': 'deviceGraphRestore',
              'restoreId': operationId,
            }),
            'created_at_ms': now,
            'updated_at_ms': now,
          });
        }
        for (final settings in item.settings) {
          if (!item.grants.any(
            (grant) => grant.profileId == settings.profileId,
          )) {
            throw StateError(
              'Imported resource settings have no matching grant',
            );
          }
          final encoded = jsonEncode(settings.values);
          if (encoded.length > 64 * 1024) {
            throw StateError('Imported resource settings are too large');
          }
          await txn.insert('profile_resource_settings', <String, Object?>{
            'profile_id': settings.profileId,
            'resource_id': item.id,
            'enabled': settings.enabled ? 1 : 0,
            'settings_json': encoded,
            'updated_at_ms': now,
          });
        }
        for (final binding in item.bindings) {
          if (!item.grants.any(
            (grant) => grant.profileId == binding.profileId,
          )) {
            throw StateError('Imported binding has no matching grant');
          }
          await txn.insert('profile_connection_bindings', <String, Object?>{
            'profile_id': binding.profileId,
            'slot': binding.slot,
            'resource_id': item.id,
            'created_at_ms': now,
            'updated_at_ms': now,
          });
        }
      }
      await txn.update(
        'user_profiles',
        <String, Object?>{
          'lifecycle_state': UserProfileLifecycle.active.name,
          'updated_at_ms': now,
        },
        where: "id IN (${List.filled(profileIds.length, '?').join(',')})",
        whereArgs: profileIds.toList(growable: false),
      );
      await txn.update(
        'profile_restore_journal',
        <String, Object?>{'stage': 'published', 'updated_at_ms': now},
        where: 'restore_id = ?',
        whereArgs: <Object>[operationId],
      );
      await _assertAdminInvariant(txn);
    });
    await _finishRegistryDelete();
  }

  static bool _isDefaultSeedGrantOrigin(Object? encoded) {
    if (encoded is! String) return false;
    try {
      final value = jsonDecode(encoded);
      return value is Map && value['origin'] == 'defaultSeed';
    } on FormatException {
      return false;
    }
  }

  /// Resolves the commit ambiguity of [publishProfileGraphRestore]. Its journal
  /// stage changes in the same transaction as profile visibility/resources, so
  /// `published` is authoritative even when the later recovery checkpoint
  /// throws.
  Future<bool> profileGraphRestorePublished(String operationId) async {
    final rows = await _db.query(
      'profile_restore_journal',
      columns: const <String>['stage'],
      where: "restore_id = ? AND mode = 'registryReplace'",
      whereArgs: <Object>[operationId],
      limit: 1,
    );
    return rows.isNotEmpty && rows.single['stage'] == 'published';
  }

  Future<int> reserveDataGeneration({
    required String profileId,
    required String operationId,
    required String mode,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final generation = await _db.transaction((txn) async {
      final profileRows = await txn.query(
        'user_profiles',
        columns: const <String>['visible_data_generation', 'lifecycle_state'],
        where: 'id = ? AND disabled_at_ms IS NULL',
        whereArgs: <Object>[profileId],
        limit: 1,
      );
      if (profileRows.isEmpty) throw StateError('Destination unavailable');
      final base = profileRows.single['visible_data_generation']! as int;
      final rows = await txn.rawQuery(
        'SELECT COALESCE(MAX(generation), 0) AS max_generation '
        'FROM profile_data_generations WHERE profile_id = ?',
        <Object>[profileId],
      );
      final next = (rows.single['max_generation']! as int) + 1;
      await txn.insert('profile_data_generations', <String, Object?>{
        'profile_id': profileId,
        'generation': next,
        'state': 'staging',
        'manifest_json': '{}',
        'manifest_hash': '',
        'created_at_ms': now,
        'updated_at_ms': now,
      });
      await txn.insert('profile_restore_journal', <String, Object?>{
        'restore_id': operationId,
        'mode': mode,
        'destination_profile_id': profileId,
        'base_generation': base,
        'staged_generation': next,
        'stage': 'staging',
        'payload_json': '{}',
        'updated_at_ms': now,
      });
      return next;
    });
    await checkpointTvOsRecovery();
    return generation;
  }

  Future<void> updateStagedGenerationManifest({
    required String profileId,
    required int generation,
    required String operationId,
    required Map<String, dynamic> manifest,
    required String manifestHash,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.transaction((txn) async {
      final changed = await txn.update(
        'profile_data_generations',
        <String, Object?>{
          'manifest_json': jsonEncode(manifest),
          'manifest_hash': manifestHash,
          'updated_at_ms': now,
        },
        where: "profile_id = ? AND generation = ? AND state = 'staging'",
        whereArgs: <Object>[profileId, generation],
      );
      if (changed != 1) throw StateError('Staged generation is unavailable');
      await txn.update(
        'profile_restore_journal',
        <String, Object?>{
          'stage': 'verified',
          'payload_json': jsonEncode(<String, Object?>{
            'manifestHash': manifestHash,
          }),
          'updated_at_ms': now,
        },
        where: 'restore_id = ? AND staged_generation = ?',
        whereArgs: <Object>[operationId, generation],
      );
    });
    await checkpointTvOsRecovery();
  }

  Future<void> stageRestoreResource({
    required String operationId,
    required String backupId,
    required String resourceId,
    required ConnectionResourceType type,
    required String label,
    required String ownerProfileId,
    required Map<String, dynamic> publicConfig,
    required String sealedSecretPayload,
    required int secretPayloadVersion,
    required int permissions,
    String? bindingSlot,
    bool? profileEnabled,
    Map<String, dynamic>? profileSettings,
    bool resourceEnabled = true,
  }) async {
    if (!ProfileScope.isValidProfileId(resourceId)) {
      throw ArgumentError.value(resourceId, 'resourceId');
    }
    if ((profileEnabled == null) != (profileSettings == null)) {
      throw ArgumentError('Incomplete restored profile resource settings');
    }
    final encodedSettings = profileSettings == null
        ? null
        : jsonEncode(profileSettings);
    if (encodedSettings != null && encodedSettings.length > 64 * 1024) {
      throw ArgumentError.value(
        profileSettings,
        'profileSettings',
        'Settings are too large',
      );
    }
    _guardTvOsEnvelopeBound(sealedSecretPayload);
    // One transaction: the chunk rows and the marker that promises them must
    // land together, and this method previously wrote outside any txn.
    await _db.transaction((txn) async {
      await txn.insert('profile_restore_resources', <String, Object?>{
        'restore_id': operationId,
        'resource_id': resourceId,
        'backup_id': backupId,
        'type': type.name,
        'label': label.trim(),
        'owner_profile_id': ownerProfileId,
        'public_config_json': jsonEncode(publicConfig),
        'sealed_secret_payload': _encodeEnvelopeColumn(sealedSecretPayload),
        'secret_payload_version': secretPayloadVersion,
        'permissions': permissions,
        'binding_slot': bindingSlot,
        'profile_enabled': profileEnabled == null
            ? null
            : (profileEnabled ? 1 : 0),
        'profile_settings_json': encodedSettings,
        'resource_enabled': resourceEnabled ? 1 : 0,
      });
      await _writeEnvelopeChunks(
        txn,
        'restore_secret_chunks',
        <String, Object?>{'restore_id': operationId, 'backup_id': backupId},
        sealedSecretPayload,
      );
    });
    await checkpointTvOsRecovery();
  }

  Future<UserProfile> publishDataGeneration({
    required String profileId,
    required int baseGeneration,
    required int stagedGeneration,
    required String operationId,
    bool? profileSetupComplete,
    bool? profileLockOnResume,
    bool updateInactivityTimeout = false,
    int? profileInactivityTimeoutMinutes,
  }) async {
    if (updateInactivityTimeout) {
      _validateInactivityTimeout(profileInactivityTimeoutMinutes);
    }
    await authorityWillChangeCallback?.call();
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.transaction((txn) async {
      final profileRows = await txn.query(
        'user_profiles',
        columns: const <String>['visible_data_generation'],
        where: 'id = ? AND disabled_at_ms IS NULL',
        whereArgs: <Object>[profileId],
        limit: 1,
      );
      if (profileRows.isEmpty ||
          profileRows.single['visible_data_generation'] != baseGeneration) {
        throw StateError('Destination changed before publication');
      }
      final staged = await txn.query(
        'profile_data_generations',
        columns: const <String>['manifest_hash'],
        where:
            "profile_id = ? AND generation = ? AND state = 'staging' "
            "AND length(manifest_hash) > 0",
        whereArgs: <Object>[profileId, stagedGeneration],
        limit: 1,
      );
      if (staged.isEmpty) throw StateError('Generation is not verified');
      final stagedResources = await txn.query(
        'profile_restore_resources',
        where: 'restore_id = ?',
        whereArgs: <Object>[operationId],
      );
      for (final row in stagedResources) {
        // Marker-aware on BOTH sides: the staged row may hold a marker whose
        // body lives in restore_secret_chunks, and the live copy re-chunks it
        // under the resource's own key.
        final envelope = await _loadEnvelope(
          txn,
          'restore_secret_chunks',
          <String, Object?>{
            'restore_id': operationId,
            'backup_id': row['backup_id'],
          },
          row['sealed_secret_payload']! as String,
        );
        await txn.insert('connection_resources', <String, Object?>{
          'id': row['resource_id'],
          'type': row['type'],
          'label': row['label'],
          'owner_profile_id': row['owner_profile_id'],
          'public_config_json': row['public_config_json'],
          'sealed_secret_payload': _encodeEnvelopeColumn(envelope),
          'secret_payload_version': row['secret_payload_version'],
          'secret_pending': 0,
          'authorization_revision': 1,
          'created_at_ms': now,
          'updated_at_ms': now,
          'disabled_at_ms': row['resource_enabled'] == 0 ? now : null,
        });
        await _writeEnvelopeChunks(
          txn,
          'resource_secret_chunks',
          <String, Object?>{'resource_id': row['resource_id']},
          envelope,
        );
        await txn.insert('profile_resource_grants', <String, Object?>{
          'profile_id': row['owner_profile_id'],
          'resource_id': row['resource_id'],
          'permissions': row['permissions'],
          'granted_by_profile_id': row['owner_profile_id'],
          'grant_origin_json': jsonEncode(<String, Object?>{
            'origin': 'restore',
            'restoreId': operationId,
          }),
          'created_at_ms': now,
          'updated_at_ms': now,
        });
        final profileEnabled = row['profile_enabled'];
        final profileSettingsJson = row['profile_settings_json'];
        if (profileEnabled != null || profileSettingsJson != null) {
          if (profileEnabled is! int || profileSettingsJson is! String) {
            throw StateError('Staged profile resource settings are incomplete');
          }
          await txn.insert('profile_resource_settings', <String, Object?>{
            'profile_id': row['owner_profile_id'],
            'resource_id': row['resource_id'],
            'enabled': profileEnabled == 0 ? 0 : 1,
            'settings_json': profileSettingsJson,
            'updated_at_ms': now,
          });
        }
        if (row['binding_slot'] != null) {
          await txn.insert(
            'profile_connection_bindings',
            <String, Object?>{
              'profile_id': row['owner_profile_id'],
              'slot': row['binding_slot'],
              'resource_id': row['resource_id'],
              'created_at_ms': now,
              'updated_at_ms': now,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }
      await txn.update(
        'profile_data_generations',
        <String, Object?>{'state': 'retired', 'updated_at_ms': now},
        where: "profile_id = ? AND generation = ? AND state = 'visible'",
        whereArgs: <Object>[profileId, baseGeneration],
      );
      await txn.delete(
        'profile_restore_resources',
        where: 'restore_id = ?',
        whereArgs: <Object>[operationId],
      );
      final published = await txn.update(
        'profile_data_generations',
        <String, Object?>{'state': 'visible', 'updated_at_ms': now},
        where: "profile_id = ? AND generation = ? AND state = 'staging'",
        whereArgs: <Object>[profileId, stagedGeneration],
      );
      if (published != 1) throw StateError('Generation publication failed');
      await txn.update(
        'user_profiles',
        <String, Object?>{
          'visible_data_generation': stagedGeneration,
          'authorization_revision':
              (await _profileAuthorizationRevision(txn, profileId)) + 1,
          if (profileSetupComplete != null)
            'profile_setup_complete': profileSetupComplete ? 1 : 0,
          if (profileLockOnResume != null)
            'lock_on_resume': profileLockOnResume ? 1 : 0,
          if (updateInactivityTimeout)
            'inactivity_timeout_minutes': profileInactivityTimeoutMinutes,
          'updated_at_ms': now,
        },
        where: 'id = ?',
        whereArgs: <Object>[profileId],
      );
      await txn.update(
        'profile_restore_journal',
        <String, Object?>{'stage': 'published', 'updated_at_ms': now},
        where: 'restore_id = ? AND staged_generation = ?',
        whereArgs: <Object>[operationId, stagedGeneration],
      );
    });
    await checkpointTvOsRecovery(webDavSyncRegistryChange: true);
    return (await getProfile(profileId))!;
  }

  /// Resolves a thrown post-transaction checkpoint from
  /// [publishDataGeneration]. Both predicates are written by its publication
  /// transaction; neither a directory nor an in-memory flag is authority.
  Future<bool> dataGenerationPublished({
    required String operationId,
    required String profileId,
    required int generation,
  }) async {
    final rows = await _db.rawQuery(
      '''SELECT 1
         FROM profile_restore_journal j
         INNER JOIN user_profiles p ON p.id = j.destination_profile_id
         WHERE j.restore_id = ? AND j.stage = 'published'
           AND p.id = ? AND p.visible_data_generation = ?
         LIMIT 1''',
      <Object>[operationId, profileId, generation],
    );
    return rows.isNotEmpty;
  }

  Future<List<Map<String, Object?>>> interruptedRestores() =>
      _db.query('profile_restore_journal', where: "stage != 'cleaned'");

  /// Describes crash-interrupted restore cleanup without first deleting its
  /// durable registry authority. Bootstrap removes the physical bytes and
  /// only then calls [completeInterruptedRestoreRecovery]. A crash at any
  /// boundary therefore retries idempotently instead of orphaning private
  /// data with no remaining tombstone.
  Future<List<InterruptedRestoreRecovery>> recoverInterruptedRestores() async {
    final rows = await _db.query(
      'profile_restore_journal',
      where: "stage != 'cleaned'",
    );
    final recoveries = <InterruptedRestoreRecovery>[];
    for (final row in rows) {
      final operationId = row['restore_id']! as String;
      final stage = row['stage']! as String;
      final mode = row['mode']! as String;
      final abandoned = <AbandonedProfileGeneration>[];
      if (mode == 'registryReplace' && stage != 'published') {
        final payload = jsonDecode(row['payload_json']! as String);
        final stagedIds = payload is Map
            ? (payload['stagedProfileIds'] as List?)?.whereType<String>()
            : null;
        if (stagedIds != null) {
          for (final stagedId in stagedIds) {
            final stagedProfile = await _db.query(
              'user_profiles',
              columns: const <String>['visible_data_generation'],
              where: "id = ? AND lifecycle_state = 'staging'",
              whereArgs: <Object>[stagedId],
              limit: 1,
            );
            // Imported profiles always begin at generation 1. Retain that
            // cleanup authority even if an older build (or an interrupted
            // catch path) already deleted the staging row before deleting its
            // preference/file tree.
            abandoned.add(
              AbandonedProfileGeneration(
                stagedId,
                stagedProfile.isEmpty
                    ? 1
                    : stagedProfile.single['visible_data_generation']! as int,
              ),
            );
          }
        }
      }
      final profileId = row['destination_profile_id'] as String?;
      final generation = row['staged_generation'] as int?;
      if (stage != 'published' && profileId != null && generation != null) {
        final item = AbandonedProfileGeneration(profileId, generation);
        if (!abandoned.any(
          (candidate) =>
              candidate.profileId == item.profileId &&
              candidate.generation == item.generation,
        )) {
          abandoned.add(item);
        }
      }
      recoveries.add(
        InterruptedRestoreRecovery(
          operationId: operationId,
          published: stage == 'published',
          abandoned: abandoned,
        ),
      );
    }
    return recoveries;
  }

  Future<void> completeInterruptedRestoreRecovery(
    InterruptedRestoreRecovery recovery,
  ) async {
    await _db.transaction((txn) async {
      if (!recovery.published) {
        await txn.delete(
          'profile_restore_resources',
          where: 'restore_id = ?',
          whereArgs: <Object>[recovery.operationId],
        );
        for (final item in recovery.abandoned) {
          await txn.delete(
            'profile_data_generations',
            where: "profile_id = ? AND generation = ? AND state = 'staging'",
            whereArgs: <Object>[item.profileId, item.generation],
          );
          await txn.delete(
            'user_profiles',
            where: "id = ? AND lifecycle_state = 'staging'",
            whereArgs: <Object>[item.profileId],
          );
        }
      }
      await txn.delete(
        'profile_restore_journal',
        where: 'restore_id = ?',
        whereArgs: <Object>[recovery.operationId],
      );
    });
    await checkpointTvOsRecovery();
  }

  Future<void> markRestoreCleaned(String operationId) async {
    await _db.delete(
      'profile_restore_journal',
      where: 'restore_id = ?',
      whereArgs: <Object>[operationId],
    );
    await checkpointTvOsRecovery();
  }

  Future<List<AbandonedProfileGeneration>> retiredGenerationsEligibleForGc({
    required int olderThanMs,
    int retainedPerProfile = 2,
  }) async {
    final rows = await _db.query(
      'profile_data_generations',
      columns: const <String>['profile_id', 'generation', 'updated_at_ms'],
      where: "state = 'retired'",
      orderBy: 'profile_id, updated_at_ms DESC, generation DESC',
    );
    final result = <AbandonedProfileGeneration>[];
    for (final row in rows) {
      final profileId = row['profile_id']! as String;
      final expired = (row['updated_at_ms']! as int) <= olderThanMs;
      // Age is the recovery contract. A positional cap must never erase a
      // young generation before that window has elapsed.
      if (expired) {
        result.add(
          AbandonedProfileGeneration(profileId, row['generation']! as int),
        );
      }
    }
    return result;
  }

  Future<void> forgetRetiredGeneration(String profileId, int generation) async {
    await _db.delete(
      'profile_data_generations',
      where: "profile_id = ? AND generation = ? AND state = 'retired'",
      whereArgs: <Object>[profileId, generation],
    );
    await checkpointTvOsRecovery();
  }

  /// Counts and state labels safe to copy into a support report. This method
  /// deliberately never returns profile/resource IDs, names, PIN state,
  /// content, paths, URLs, or secret-bearing payloads.
  Future<Map<String, Object?>> privacySafeDiagnostics() async {
    Future<int> count(String table, [String? where]) async {
      final rows = await _db.rawQuery(
        'SELECT COUNT(*) AS value FROM $table${where == null ? '' : ' WHERE $where'}',
      );
      return (rows.single['value'] as num).toInt();
    }

    final deviceRows = await _db.query(
      'device_state',
      columns: const <String>[
        'bootstrap_state',
        'migration_state',
        'registry_generation',
      ],
      where: 'singleton_id = 1',
      limit: 1,
    );
    final migrationRows = await _db.query(
      'profile_migration_journal',
      columns: const <String>['stage'],
      orderBy: 'updated_at_ms DESC',
      limit: 1,
    );
    final integrity = await _db.rawQuery('PRAGMA quick_check');
    final generationRows = await _db.rawQuery(
      'SELECT state, COUNT(*) AS value FROM profile_data_generations '
      'GROUP BY state',
    );
    final generationCounts = <String, int>{
      for (final row in generationRows)
        row['state']! as String: (row['value']! as num).toInt(),
    };
    final device = deviceRows.isEmpty
        ? const <String, Object?>{}
        : deviceRows.single;
    return <String, Object?>{
      'registrySchemaVersion': schemaVersion,
      'registryHealth':
          integrity.isNotEmpty && integrity.first.values.first == 'ok'
          ? 'healthy'
          : 'unhealthy',
      'bootstrapState': device['bootstrap_state'] ?? 'uninitialized',
      'migrationState': device['migration_state'] ?? 'notStarted',
      'migrationStage': migrationRows.isEmpty
          ? 'none'
          : migrationRows.single['stage'],
      'registryGeneration': device['registry_generation'] ?? 0,
      'profiles': <String, int>{
        'total': await count('user_profiles'),
        'enabled': await count('user_profiles', 'disabled_at_ms IS NULL'),
        'disabled': await count('user_profiles', 'disabled_at_ms IS NOT NULL'),
        'staging': await count('user_profiles', "lifecycle_state = 'staging'"),
      },
      'resources': <String, int>{
        'total': await count('connection_resources'),
        'disabled': await count(
          'connection_resources',
          'disabled_at_ms IS NOT NULL',
        ),
      },
      'jobs': <String, int>{
        'total': await count('job_ownership'),
        'active': await count('job_ownership', 'terminal_at_ms IS NULL'),
        'ownerless': await count('job_ownership', 'owner_profile_id IS NULL'),
      },
      'restoreJournals': await count('profile_restore_journal'),
      'generationCounts': generationCounts,
    };
  }

  static UserProfile _decodeProfile(Map<String, Object?> row) {
    final role = UserProfileRole.values.byName(row['role']! as String);
    return UserProfile(
      id: row['id']! as String,
      name: row['name']! as String,
      avatarKey: row['avatar_key'] as String?,
      role: role,
      policy: ProfilePolicy.decode(row['policy_json']! as String, role),
      authorizationRevision: row['authorization_revision']! as int,
      lifecycle: UserProfileLifecycle.values.byName(
        row['lifecycle_state']! as String,
      ),
      visibleDataGeneration: row['visible_data_generation']! as int,
      setupComplete: row['profile_setup_complete'] == 1,
      pinResetRequired: row['pin_reset_required'] == 1,
      hasPin: row['pin_hash'] != null,
      lockOnResume: row['lock_on_resume'] == 1,
      inactivityTimeoutMinutes: row['inactivity_timeout_minutes'] as int?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        row['created_at_ms']! as int,
      ),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        row['updated_at_ms']! as int,
      ),
      disabledAt: row['disabled_at_ms'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(row['disabled_at_ms']! as int),
    );
  }

  /// tvOS ceiling for ONE envelope, enforced BEFORE anything commits.
  ///
  /// The whole registry snapshot must fit the recovery store's 768KB
  /// Keychain bound. An envelope past this cannot be made recoverable by any
  /// storage scheme — and if one were allowed to commit, the write would
  /// succeed, the post-commit checkpoint would throw, and EVERY subsequent
  /// checkpoint from every mutation would keep throwing while the Keychain
  /// snapshot went stale — which the next boot would then restore, silently
  /// rolling the registry back. Refusing the one oversized item up front is
  /// the honest failure. Android/desktop have no such bound and take the
  /// chunked path instead.
  static const int _tvOsEnvelopeBoundChars = 256 * 1024;

  static void _guardTvOsEnvelopeBound(String envelope) {
    if (!TvOsProfileRecoveryStore.supported) return;
    if (envelope.length <= _tvOsEnvelopeBoundChars) return;
    throw StateError(
      'This connection is too large for Apple TV recovery storage '
      '(${envelope.length} chars; limit $_tvOsEnvelopeBoundChars)',
    );
  }

  /// Envelopes longer than this leave the row for a chunk table. Half the
  /// 2MB CursorWindow ceiling, so the row keeps generous headroom for its
  /// other columns and the chunk rows themselves never approach the limit.
  static const int _envelopeInlineMaxChars = 512 * 1024;
  static const int _envelopeChunkChars = 512 * 1024;
  static const String _envelopeChunkMarkerPrefix = '@chunks:v1:';

  /// Whether [envelope] must live in a chunk table.
  ///
  /// Size is the normal reason. The marker-prefix clause is defensive: real
  /// envelopes are `native1:`-prefixed ciphertext and can never start with
  /// the marker, but a crafted backup or remote payload could — stored
  /// inline, it would be MISPARSED as a marker at read. Spilling it makes
  /// the column a genuine marker whose chunks hold the impostor as data.
  static bool _envelopeMustSpill(String envelope) =>
      envelope.length > _envelopeInlineMaxChars ||
      envelope.startsWith(_envelopeChunkMarkerPrefix);

  /// The column value for [envelope]: itself when small, a marker when its
  /// body belongs in a chunk table. Callers that get a marker back MUST also
  /// call [_writeEnvelopeChunks] inside the same transaction — the marker
  /// carries the chunk count so a torn pair is detectable at read.
  static String _encodeEnvelopeColumn(String envelope) {
    if (!_envelopeMustSpill(envelope)) return envelope;
    final chunks =
        (envelope.length + _envelopeChunkChars - 1) ~/ _envelopeChunkChars;
    return '$_envelopeChunkMarkerPrefix${chunks < 1 ? 1 : chunks}';
  }

  static bool _isEnvelopeChunkMarker(String? value) =>
      value != null && value.startsWith(_envelopeChunkMarkerPrefix);

  /// Replaces [key]'s chunk rows with [envelope]'s body when it spills, and
  /// just clears them when it fits inline. Always run AFTER the parent row
  /// write (the chunk tables' foreign keys point at it) and inside its
  /// transaction.
  static Future<void> _writeEnvelopeChunks(
    DatabaseExecutor db,
    String table,
    Map<String, Object?> key,
    String envelope,
  ) async {
    final where = key.keys.map((k) => '$k = ?').join(' AND ');
    final args = key.values.toList(growable: false);
    await db.delete(table, where: where, whereArgs: args);
    if (!_envelopeMustSpill(envelope)) return;
    var seq = 0;
    // A spilled marker-lookalike can be shorter than one chunk; the loop
    // below still writes its single chunk because the empty envelope is
    // unreachable (sealing always produces ciphertext).
    for (var i = 0; i < envelope.length; i += _envelopeChunkChars) {
      final end = i + _envelopeChunkChars < envelope.length
          ? i + _envelopeChunkChars
          : envelope.length;
      await db.insert(table, <String, Object?>{
        ...key,
        'seq': seq++,
        'chunk': envelope.substring(i, end),
      });
    }
  }

  /// The full envelope behind a stored column value — the value itself for
  /// inline rows, reassembled chunks for markers.
  static Future<String> _loadEnvelope(
    DatabaseExecutor db,
    String table,
    Map<String, Object?> key,
    String stored,
  ) async {
    if (!_isEnvelopeChunkMarker(stored)) return stored;
    final expected = int.tryParse(
      stored.substring(_envelopeChunkMarkerPrefix.length),
    );
    if (expected != null && expected < 1) {
      // '@chunks:v1:0' would otherwise "round-trip" as an EMPTY envelope —
      // zero rows equals zero expected — and an absent credential is the one
      // corruption worse than a loud one.
      throw StateError('Sealed payload marker is invalid ($stored) for $key');
    }
    final where = key.keys.map((k) => '$k = ?').join(' AND ');
    final rows = await db.query(
      table,
      columns: const <String>['chunk'],
      where: where,
      whereArgs: key.values.toList(growable: false),
      orderBy: 'seq',
    );
    if (expected == null || rows.length != expected) {
      // Transactions make a torn pair unreachable; if one appears anyway,
      // serving a truncated secret would decrypt to garbage or worse.
      throw StateError(
        'Sealed payload chunks are incomplete '
        '(${rows.length}/${expected ?? '?'}) for $key',
      );
    }
    final buffer = StringBuffer();
    for (final row in rows) {
      buffer.write(row['chunk'] as String);
    }
    return buffer.toString();
  }

  static ConnectionResource _decodeResource(Map<String, Object?> row) {
    return ConnectionResource(
      id: row['id']! as String,
      type: ConnectionResourceType.values.byName(row['type']! as String),
      label: row['label']! as String,
      ownerProfileId: row['owner_profile_id']! as String,
      publicConfig: Map<String, dynamic>.from(
        jsonDecode(row['public_config_json']! as String) as Map,
      ),
      publicSchemaVersion:
          (jsonDecode(row['public_config_json']! as String)
                  as Map)['schemaVersion']
              as int? ??
          1,
      authorizationRevision: row['authorization_revision']! as int,
      enabled: row['disabled_at_ms'] == null,
      secretPending: row['secret_pending'] == 1,
    );
  }

  static String _registryGrantKey(String profileId, String resourceId) =>
      '$profileId\u0000$resourceId';

  static String _registryBindingKey(String profileId, String slot) =>
      '$profileId\u0000$slot';

  /// Enqueues the complete deletion cascade in the same SQL transaction as
  /// the rows it describes. Unbound registries skip the outbox; once bound,
  /// an INSERT failure aborts the deletion transaction.
  static Future<void> _recordRegistryDeleteCascade(
    DatabaseExecutor db, {
    Set<String> profileIds = const <String>{},
    Set<String> resourceIds = const <String>{},
    Set<String> grantKeys = const <String>{},
    Set<String> bindingKeys = const <String>{},
    Iterable<WebDavSyncRegistryRecordId> mergedBaselineRecords =
        const <WebDavSyncRegistryRecordId>[],
  }) async {
    if (profileIds.isEmpty &&
        resourceIds.isEmpty &&
        grantKeys.isEmpty &&
        bindingKeys.isEmpty) {
      return;
    }
    final target = await WebDavSyncTombstoneRecorder.registryOutboxTarget();
    if (target == null) return;
    final records = <WebDavSyncRegistryRecordId>{
      ...await _registryRecordInventory(db),
      ...mergedBaselineRecords,
    };
    final expandedResourceIds = <String>{...resourceIds};
    for (final record in records) {
      if (record.kind == WebDavSyncRegistryRecordKind.resource &&
          profileIds.contains(record.ownerProfileId)) {
        expandedResourceIds.add(record.resourceId!);
      }
    }
    final selected = records
        .where((record) {
          final profileId = record.profileId;
          final resourceId = record.resourceId;
          final grantKey = profileId == null || resourceId == null
              ? null
              : _registryGrantKey(profileId, resourceId);
          return switch (record.kind) {
            WebDavSyncRegistryRecordKind.profile => profileIds.contains(
              profileId,
            ),
            WebDavSyncRegistryRecordKind.resource =>
              expandedResourceIds.contains(resourceId),
            WebDavSyncRegistryRecordKind.grant ||
            WebDavSyncRegistryRecordKind.setting =>
              profileIds.contains(profileId) ||
                  expandedResourceIds.contains(resourceId) ||
                  grantKeys.contains(grantKey),
            WebDavSyncRegistryRecordKind.binding =>
              profileIds.contains(profileId) ||
                  expandedResourceIds.contains(resourceId) ||
                  grantKeys.contains(grantKey) ||
                  bindingKeys.contains(
                    _registryBindingKey(profileId!, record.slot!),
                  ),
          };
        })
        .toList(growable: false);
    await _enqueueRegistryTombstones(db, target, selected);
  }

  static Future<void> _recordRegistryBorrowerRevocation(
    DatabaseExecutor db, {
    required String ownerProfileId,
    Iterable<WebDavSyncRegistryRecordId> mergedBaselineRecords =
        const <WebDavSyncRegistryRecordId>[],
  }) async {
    final target = await WebDavSyncTombstoneRecorder.registryOutboxTarget();
    if (target == null) return;
    final records = <WebDavSyncRegistryRecordId>{
      ...await _registryRecordInventory(db),
      ...mergedBaselineRecords,
    };
    final ownedResourceIds = records
        .where(
          (record) =>
              record.kind == WebDavSyncRegistryRecordKind.resource &&
              record.ownerProfileId == ownerProfileId,
        )
        .map((record) => record.resourceId!)
        .toSet();
    final revokedGrantKeys = records
        .where(
          (record) =>
              record.kind == WebDavSyncRegistryRecordKind.grant &&
              ownedResourceIds.contains(record.resourceId) &&
              record.profileId != ownerProfileId,
        )
        .map(
          (record) => _registryGrantKey(record.profileId!, record.resourceId!),
        )
        .toSet();
    final selected = records
        .where((record) {
          final profileId = record.profileId;
          final resourceId = record.resourceId;
          if (profileId == null || resourceId == null) return false;
          return revokedGrantKeys.contains(
            _registryGrantKey(profileId, resourceId),
          );
        })
        .toList(growable: false);
    await _enqueueRegistryTombstones(db, target, selected);
  }

  static Future<void> _enqueueRegistryTombstones(
    DatabaseExecutor db,
    WebDavSyncRegistryTombstoneOutboxTarget target,
    List<WebDavSyncRegistryRecordId> records,
  ) async {
    if (records.isEmpty) return;
    await db.insert('webdav_sync_tombstone_outbox', <String, Object?>{
      'namespace_id': target.namespaceId,
      'origin_device_id': target.deviceId,
      'records_json': jsonEncode(
        records.map((record) => record.toJson()).toList(growable: false),
      ),
      'created_at_ms': DateTime.now().millisecondsSinceEpoch,
    });
  }

  static Future<List<WebDavSyncRegistryRecordId>> _registryRecordInventory(
    DatabaseExecutor db,
  ) async {
    final profiles = await db.query(
      'user_profiles',
      columns: const <String>['id'],
    );
    final resources = await db.query(
      'connection_resources',
      columns: const <String>['id', 'owner_profile_id'],
    );
    final grants = await db.query(
      'profile_resource_grants',
      columns: const <String>['profile_id', 'resource_id'],
    );
    final settings = await db.query(
      'profile_resource_settings',
      columns: const <String>['profile_id', 'resource_id'],
    );
    final bindings = await db.query(
      'profile_connection_bindings',
      columns: const <String>['profile_id', 'slot', 'resource_id'],
    );
    return <WebDavSyncRegistryRecordId>[
      for (final row in profiles)
        WebDavSyncRegistryRecordId.profile(row['id']! as String),
      for (final row in resources)
        WebDavSyncRegistryRecordId.resource(
          row['id']! as String,
          ownerProfileId: row['owner_profile_id']! as String,
        ),
      for (final row in grants)
        WebDavSyncRegistryRecordId.grant(
          row['profile_id']! as String,
          row['resource_id']! as String,
        ),
      for (final row in settings)
        WebDavSyncRegistryRecordId.setting(
          row['profile_id']! as String,
          row['resource_id']! as String,
        ),
      for (final row in bindings)
        WebDavSyncRegistryRecordId.binding(
          row['profile_id']! as String,
          row['slot']! as String,
          resourceId: row['resource_id']! as String,
        ),
    ];
  }

  static Future<int> _profileAuthorizationRevision(
    DatabaseExecutor db,
    String profileId,
  ) async {
    final rows = await db.query(
      'user_profiles',
      columns: const <String>['authorization_revision'],
      where: 'id = ? AND disabled_at_ms IS NULL',
      whereArgs: <Object>[profileId],
      limit: 1,
    );
    if (rows.isEmpty) throw StateError('Profile does not exist');
    return rows.single['authorization_revision']! as int;
  }

  /// UPSERT that works on the OS SQLite of every supported Android version.
  ///
  /// `INSERT … ON-CONFLICT DO UPDATE` needs SQLite 3.24 (2018); Android only
  /// ships that from 10 up, and minSdk is 24 — the Mi Box class of TV
  /// hardware runs Android 8/9 (SQLite 3.18/3.22), where the statement fails
  /// to COMPILE ("near \"ON\": syntax error"). sqflite uses the OS library,
  /// so the modern form must never appear in registry SQL; the IPTV catalog
  /// DB is immune because it links its own SQLite via package:sqlite3. A
  /// source-guard test pins this.
  ///
  /// Two statements replace it: INSERT OR IGNORE keeps the original row's
  /// immutable columns (created_at_ms), then UPDATE overwrites exactly the
  /// columns the old DO UPDATE SET listed — the same end state on both the
  /// fresh-insert and conflict paths. Callers run inside a transaction for
  /// the same atomicity the single statement had.
  static Future<void> _compatUpsert(
    DatabaseExecutor db, {
    required String table,
    required Map<String, Object?> insert,
    required Map<String, Object?> update,
    required Map<String, Object?> key,
  }) async {
    await db.rawInsert(
      'INSERT OR IGNORE INTO $table (${insert.keys.join(', ')}) '
      'VALUES (${List.filled(insert.length, '?').join(', ')})',
      insert.values.toList(),
    );
    await db.rawUpdate(
      'UPDATE $table SET ${update.keys.map((c) => '$c = ?').join(', ')} '
      'WHERE ${key.keys.map((c) => '$c = ?').join(' AND ')}',
      <Object?>[...update.values, ...key.values],
    );
  }

  static Future<void> _assertAdminInvariant(
    DatabaseExecutor db, {
    String? excludingProfileId,
  }) async {
    final rows = await db.query(
      'user_profiles',
      columns: const <String>['id', 'policy_json'],
      where: "disabled_at_ms IS NULL AND role = 'admin'",
    );
    final hasManagingAdmin = rows.any((row) {
      if (row['id'] == excludingProfileId) return false;
      final policy = ProfilePolicy.decode(
        row['policy_json']! as String,
        UserProfileRole.admin,
      );
      return policy.allows(
        UserProfileRole.admin,
        ProfileFeature.manageProfiles,
      );
    });
    if (!hasManagingAdmin) {
      throw StateError('At least one enabled managing Admin is required');
    }
  }

  static bool _pinRecordMatches(
    Map<String, Object?> row,
    ProfilePinRecord expected,
  ) {
    return _bytesEqual(row['pin_hash'] as Uint8List?, expected.hash) &&
        _bytesEqual(row['pin_salt'] as Uint8List?, expected.salt) &&
        row['pin_params_json'] == expected.paramsJson &&
        (row['pin_reset_required'] == 1) == expected.resetRequired;
  }

  static bool _pinAndRecoveryRecordMatches(
    Map<String, Object?> row,
    ProfilePinRecord expected,
  ) {
    return _pinRecordMatches(row, expected) &&
        _bytesEqual(
          row['recovery_hash'] as Uint8List?,
          expected.recoveryHash,
        ) &&
        _bytesEqual(
          row['recovery_salt'] as Uint8List?,
          expected.recoverySalt,
        ) &&
        row['recovery_params_json'] == expected.recoveryParamsJson;
  }

  static bool _bytesEqual(List<int>? first, List<int>? second) {
    if (identical(first, second)) return true;
    if (first == null || second == null || first.length != second.length) {
      return false;
    }
    var difference = 0;
    for (var index = 0; index < first.length; index++) {
      difference |= first[index] ^ second[index];
    }
    return difference == 0;
  }

  /// Transaction-local proof that a profile is still the unlocked active
  /// session. Onboarding completion is not a feature capability, so Members
  /// and Children may finish their own explicitly requested setup without
  /// receiving an unrelated management permission.
  static Future<void> _assertActiveSessionActor(
    DatabaseExecutor db, {
    required String profileId,
    required int authorizationRevision,
    required int sessionEpoch,
  }) async {
    final runtimeScope = ProfileRuntime.scope.value;
    if (!ProfileRuntime.isInitialized ||
        !ProfileRuntime.isProfileCommitted ||
        ProfileLockController.instance.lockedProfileId.value != null ||
        runtimeScope?.profileId != profileId ||
        runtimeScope?.sessionEpoch != sessionEpoch) {
      throw StateError('Active profile session has ended');
    }
    final active = await db.query(
      'device_state',
      columns: const <String>['active_profile_id'],
      where: 'singleton_id = 1',
      limit: 1,
    );
    final profiles = await db.query(
      'user_profiles',
      columns: const <String>['authorization_revision', 'lifecycle_state'],
      where: 'id = ? AND disabled_at_ms IS NULL',
      whereArgs: <Object>[profileId],
      limit: 1,
    );
    if (active.isEmpty ||
        active.single['active_profile_id'] != profileId ||
        profiles.isEmpty ||
        profiles.single['authorization_revision'] != authorizationRevision ||
        profiles.single['lifecycle_state'] !=
            UserProfileLifecycle.active.name) {
      throw StateError('Active profile authorization changed');
    }
    if (ProfileLockController.instance.lockedProfileId.value != null ||
        ProfileRuntime.scope.value?.profileId != profileId ||
        ProfileRuntime.scope.value?.sessionEpoch != sessionEpoch) {
      throw StateError('Active profile session has ended');
    }
  }

  /// Conditional authorization checked inside the same SQLite transaction as
  /// an Admin mutation. This closes the dialog/KDF/callback race where an
  /// initiating Admin is switched, disabled, or demoted after an earlier UI
  /// check but before the durable write.
  static Future<void> _assertManagingActor(
    DatabaseExecutor db,
    String? profileId,
    int? authorizationRevision,
    int? sessionEpoch,
  ) async {
    if (profileId == null &&
        authorizationRevision == null &&
        sessionEpoch == null) {
      final device = await db.query(
        'device_state',
        columns: const <String>['migration_state'],
        where: 'singleton_id = 1',
        limit: 1,
      );
      if (device.isNotEmpty &&
          device.single['migration_state'] == 'committed') {
        throw StateError('Committed profile mutations require an Admin actor');
      }
      return;
    }
    if (profileId == null ||
        authorizationRevision == null ||
        sessionEpoch == null) {
      throw ArgumentError('Incomplete managing-actor authority');
    }
    final runtimeScope = ProfileRuntime.scope.value;
    if (!ProfileRuntime.isInitialized ||
        !ProfileRuntime.isProfileCommitted ||
        ProfileLockController.instance.lockedProfileId.value != null ||
        runtimeScope?.profileId != profileId ||
        runtimeScope?.sessionEpoch != sessionEpoch) {
      throw StateError('Managing profile session has ended');
    }
    final active = await db.query(
      'device_state',
      columns: const <String>['active_profile_id'],
      where: 'singleton_id = 1',
      limit: 1,
    );
    if (active.isEmpty || active.single['active_profile_id'] != profileId) {
      throw StateError('Managing profile is no longer active');
    }
    final rows = await db.query(
      'user_profiles',
      columns: const <String>['role', 'policy_json', 'authorization_revision'],
      where: 'id = ? AND disabled_at_ms IS NULL',
      whereArgs: <Object>[profileId],
      limit: 1,
    );
    if (rows.isEmpty ||
        rows.single['authorization_revision'] != authorizationRevision ||
        rows.single['role'] != UserProfileRole.admin.name) {
      throw StateError('Managing profile authorization changed');
    }
    final policy = ProfilePolicy.decode(
      rows.single['policy_json']! as String,
      UserProfileRole.admin,
    );
    if (!policy.allows(UserProfileRole.admin, ProfileFeature.manageProfiles)) {
      throw StateError('Profile management is not authorized');
    }
    if (ProfileLockController.instance.lockedProfileId.value != null ||
        ProfileRuntime.scope.value?.profileId != profileId ||
        ProfileRuntime.scope.value?.sessionEpoch != sessionEpoch) {
      throw StateError('Managing profile session has ended');
    }
  }

  static Future<void> _assertFeatureActor(
    DatabaseExecutor db, {
    required String profileId,
    required int authorizationRevision,
    required ProfileFeature feature,
    bool requireAdmin = false,
  }) async {
    final active = await db.query(
      'device_state',
      columns: const <String>['active_profile_id'],
      where: 'singleton_id = 1',
      limit: 1,
    );
    if (active.isEmpty || active.single['active_profile_id'] != profileId) {
      throw StateError('Acting profile is no longer active');
    }
    final rows = await db.query(
      'user_profiles',
      columns: const <String>['role', 'policy_json', 'authorization_revision'],
      where: 'id = ? AND disabled_at_ms IS NULL',
      whereArgs: <Object>[profileId],
      limit: 1,
    );
    if (rows.isEmpty ||
        rows.single['authorization_revision'] != authorizationRevision) {
      throw StateError('Acting profile authorization changed');
    }
    final role = UserProfileRole.values.byName(rows.single['role']! as String);
    final policy = ProfilePolicy.decode(
      rows.single['policy_json']! as String,
      role,
    );
    if ((requireAdmin && role != UserProfileRole.admin) ||
        !policy.allows(role, feature)) {
      throw StateError('Acting profile feature is not authorized');
    }
  }

  static Future<void> _assertResourceActor(
    DatabaseExecutor db, {
    required String profileId,
    required int authorizationRevision,
    required ProfileFeature feature,
    required String resourceId,
    required int resourceAuthorizationRevision,
    required ResourcePermission permission,
    bool requireAdmin = false,
  }) async {
    await _assertFeatureActor(
      db,
      profileId: profileId,
      authorizationRevision: authorizationRevision,
      feature: feature,
      requireAdmin: requireAdmin,
    );
    final resources = await db.query(
      'connection_resources',
      columns: const <String>['authorization_revision'],
      where: 'id = ? AND disabled_at_ms IS NULL',
      whereArgs: <Object>[resourceId],
      limit: 1,
    );
    final grants = await db.query(
      'profile_resource_grants',
      columns: const <String>['permissions'],
      where: 'profile_id = ? AND resource_id = ?',
      whereArgs: <Object>[profileId, resourceId],
      limit: 1,
    );
    if (resources.isEmpty ||
        resources.single['authorization_revision'] !=
            resourceAuthorizationRevision ||
        grants.isEmpty ||
        (grants.single['permissions']! as int) & permission.bit == 0) {
      throw StateError('Connection authorization changed');
    }
  }

  static String _newId() {
    final random = Random.secure();
    final bytes = List<int>.generate(12, (_) => random.nextInt(256));
    final suffix = base64UrlEncode(bytes).replaceAll('=', '');
    return 'profile-$suffix';
  }
}

enum SyncedRegistryApplyResult { applied, conflict }

class SyncedRegistryDelta {
  final List<SyncedRegistryProfileRecord> profiles;
  final List<SyncedRegistryResourceRecord> resources;
  final List<SyncedRegistryGrantRecord> grants;
  final List<SyncedRegistrySettingsRecord> settings;
  final List<SyncedRegistryBindingRecord> bindings;
  final List<SyncedRegistryDeleteRecord> deletes;

  const SyncedRegistryDelta({
    this.profiles = const <SyncedRegistryProfileRecord>[],
    this.resources = const <SyncedRegistryResourceRecord>[],
    this.grants = const <SyncedRegistryGrantRecord>[],
    this.settings = const <SyncedRegistrySettingsRecord>[],
    this.bindings = const <SyncedRegistryBindingRecord>[],
    this.deletes = const <SyncedRegistryDeleteRecord>[],
  });
}

class SyncedRegistryDeleteRecord {
  final WebDavSyncRegistryRecordId record;
  final int? expectedPriorUpdatedAtMs;

  const SyncedRegistryDeleteRecord({
    required this.record,
    this.expectedPriorUpdatedAtMs,
  });
}

class SyncedRegistryProfileRecord {
  final String id;
  final String name;
  final String? avatarKey;
  final UserProfileRole role;
  final ProfilePolicy policy;
  final bool enabled;
  final bool lockOnResume;
  final int? inactivityTimeoutMinutes;
  final bool setupComplete;
  final UserProfileLifecycle lifecycle;
  final ProfilePinRecord pin;

  /// False for a metadata-only profile update so local failure/lockout state
  /// remains device-local when the singular wire credential is unchanged.
  final bool applyPin;
  final int updatedAtMs;
  final int? expectedPriorUpdatedAtMs;

  const SyncedRegistryProfileRecord({
    required this.id,
    required this.name,
    this.avatarKey,
    required this.role,
    required this.policy,
    required this.enabled,
    required this.lockOnResume,
    this.inactivityTimeoutMinutes,
    required this.setupComplete,
    this.lifecycle = UserProfileLifecycle.active,
    this.pin = const ProfilePinRecord(),
    this.applyPin = true,
    required this.updatedAtMs,
    this.expectedPriorUpdatedAtMs,
  });
}

class SyncedRegistryResourceRecord {
  final ConnectionResource resource;
  final int updatedAtMs;
  final String? sealedSecretPayload;
  final int? secretPayloadVersion;
  final bool clearSecret;
  final int? expectedPriorUpdatedAtMs;

  const SyncedRegistryResourceRecord({
    required this.resource,
    required this.updatedAtMs,
    this.sealedSecretPayload,
    this.secretPayloadVersion,
    this.clearSecret = false,
    this.expectedPriorUpdatedAtMs,
  });
}

class SyncedRegistryGrantRecord {
  final String profileId;
  final String resourceId;
  final int permissions;
  final int updatedAtMs;
  final int? expectedPriorUpdatedAtMs;

  const SyncedRegistryGrantRecord({
    required this.profileId,
    required this.resourceId,
    required this.permissions,
    required this.updatedAtMs,
    this.expectedPriorUpdatedAtMs,
  });
}

class SyncedRegistrySettingsRecord {
  final String profileId;
  final String resourceId;
  final bool enabled;
  final Map<String, dynamic> settings;
  final int updatedAtMs;
  final int? expectedPriorUpdatedAtMs;

  const SyncedRegistrySettingsRecord({
    required this.profileId,
    required this.resourceId,
    required this.enabled,
    this.settings = const <String, dynamic>{},
    required this.updatedAtMs,
    this.expectedPriorUpdatedAtMs,
  });
}

class SyncedRegistryBindingRecord {
  final String profileId;
  final String slot;
  final String resourceId;
  final int updatedAtMs;
  final int? expectedPriorUpdatedAtMs;

  const SyncedRegistryBindingRecord({
    required this.profileId,
    required this.slot,
    required this.resourceId,
    required this.updatedAtMs,
    this.expectedPriorUpdatedAtMs,
  });
}

class RegistrySyncProjection {
  final List<RegistrySyncResourceProjection> resources;
  final List<RegistrySyncGrantProjection> grants;
  final List<RegistrySyncSettingsProjection> settings;
  final List<RegistrySyncBindingProjection> bindings;

  const RegistrySyncProjection({
    required this.resources,
    required this.grants,
    required this.settings,
    required this.bindings,
  });
}

class RegistryCircleSyncProjection {
  final List<RegistrySyncProfileProjection> profiles;
  final RegistrySyncProjection registry;
  final int outboxRowCount;

  const RegistryCircleSyncProjection({
    required this.profiles,
    required this.registry,
    required this.outboxRowCount,
  });
}

class RegistrySyncProfileProjection {
  final UserProfile profile;
  final ProfilePinRecord pin;
  final int updatedAtMs;

  const RegistrySyncProfileProjection({
    required this.profile,
    required this.pin,
    required this.updatedAtMs,
  });
}

class RegistrySyncResourceProjection {
  final ConnectionResource resource;
  final int updatedAtMs;

  const RegistrySyncResourceProjection({
    required this.resource,
    required this.updatedAtMs,
  });
}

class RegistrySyncGrantProjection {
  final String profileId;
  final String resourceId;
  final int permissions;
  final int updatedAtMs;

  const RegistrySyncGrantProjection({
    required this.profileId,
    required this.resourceId,
    required this.permissions,
    required this.updatedAtMs,
  });
}

class RegistrySyncSettingsProjection {
  final String profileId;
  final String resourceId;
  final bool enabled;
  final Map<String, dynamic> settings;
  final int updatedAtMs;

  const RegistrySyncSettingsProjection({
    required this.profileId,
    required this.resourceId,
    required this.enabled,
    required this.settings,
    required this.updatedAtMs,
  });
}

class RegistrySyncBindingProjection {
  final String profileId;
  final String slot;
  final String resourceId;
  final int updatedAtMs;

  const RegistrySyncBindingProjection({
    required this.profileId,
    required this.slot,
    required this.resourceId,
    required this.updatedAtMs,
  });
}

class SealedResourceSecretRecord {
  final String resourceId;
  final ConnectionResourceType type;
  final String ownerProfileId;
  final int publicSchemaVersion;
  final int payloadVersion;
  final String envelope;

  const SealedResourceSecretRecord({
    required this.resourceId,
    required this.type,
    required this.ownerProfileId,
    required this.publicSchemaVersion,
    required this.payloadVersion,
    required this.envelope,
  });
}

class PreparedConnectionResource {
  final ConnectionResource resource;
  final String sealedSecretPayload;
  final int secretPayloadVersion;

  const PreparedConnectionResource({
    required this.resource,
    required this.sealedSecretPayload,
    required this.secretPayloadVersion,
  });
}

class StagedGraphResource {
  final String id;
  final ConnectionResourceType type;
  final String label;
  final String ownerProfileId;
  final Map<String, dynamic> publicConfig;
  final String sealedSecretPayload;
  final int secretPayloadVersion;
  final bool enabled;
  final List<StagedGraphGrant> grants;
  final List<StagedGraphBinding> bindings;
  final List<StagedGraphSettings> settings;

  const StagedGraphResource({
    required this.id,
    required this.type,
    required this.label,
    required this.ownerProfileId,
    required this.publicConfig,
    required this.sealedSecretPayload,
    required this.secretPayloadVersion,
    this.enabled = true,
    required this.grants,
    required this.bindings,
    this.settings = const <StagedGraphSettings>[],
  });
}

/// An existing receiver addon grant inherited while an imported profile was
/// staged, proven redundant by an exact configured-manifest match in the
/// imported graph. Publication accepts only grants whose origin is still the
/// automatic `defaultSeed`; explicit user sharing is never pruned.
class GraphRestoreDefaultGrantPrune {
  final String profileId;
  final String resourceId;
  final int expectedResourceAuthorizationRevision;

  const GraphRestoreDefaultGrantPrune({
    required this.profileId,
    required this.resourceId,
    required this.expectedResourceAuthorizationRevision,
  });
}

class StagedGraphGrant {
  final String profileId;
  final int permissions;

  const StagedGraphGrant({required this.profileId, required this.permissions});
}

class StagedGraphBinding {
  final String profileId;
  final String slot;

  const StagedGraphBinding({required this.profileId, required this.slot});
}

class StagedGraphSettings {
  final String profileId;
  final bool enabled;
  final Map<String, dynamic> values;

  const StagedGraphSettings({
    required this.profileId,
    required this.enabled,
    this.values = const <String, dynamic>{},
  });
}

class ProfileDeletionDependencies {
  final int activeJobs;
  final int ownedResources;
  final int sharedResources;
  final int publicArtifacts;

  const ProfileDeletionDependencies({
    required this.activeJobs,
    required this.ownedResources,
    required this.sharedResources,
    required this.publicArtifacts,
  });

  bool get isEmpty =>
      activeJobs == 0 && ownedResources == 0 && publicArtifacts == 0;
}

class AbandonedProfileGeneration {
  final String profileId;
  final int generation;

  const AbandonedProfileGeneration(this.profileId, this.generation);
}

class InterruptedRestoreRecovery {
  final String operationId;
  final bool published;
  final List<AbandonedProfileGeneration> abandoned;

  const InterruptedRestoreRecovery({
    required this.operationId,
    required this.published,
    required this.abandoned,
  });
}

class ProfilePinRecord {
  final Uint8List? hash;
  final Uint8List? salt;
  final String? paramsJson;
  final int failedAttempts;
  final int? lockedUntilMs;
  final bool resetRequired;
  final Uint8List? recoveryHash;
  final Uint8List? recoverySalt;
  final String? recoveryParamsJson;

  const ProfilePinRecord({
    this.hash,
    this.salt,
    this.paramsJson,
    this.failedAttempts = 0,
    this.lockedUntilMs,
    this.resetRequired = false,
    this.recoveryHash,
    this.recoverySalt,
    this.recoveryParamsJson,
  });

  bool get hasPin => hash != null && salt != null && paramsJson != null;
  bool get isCorrupt =>
      (hash != null || salt != null || paramsJson != null) && !hasPin;
  bool get hasRecoveryCode =>
      recoveryHash != null &&
      recoverySalt != null &&
      recoveryParamsJson != null;
}

extension<T> on List<T> {
  T? get singleOrNull => length == 1 ? single : null;
}
