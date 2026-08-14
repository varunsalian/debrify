import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../../models/profiles/connection_resource.dart';
import '../../models/profiles/profile_policy.dart';
import '../../models/profiles/user_profile.dart';
import '../../utils/app_storage.dart';
import 'profile_lock_controller.dart';
import 'profile_runtime.dart';
import 'profile_scope.dart';
import 'tvos_profile_recovery_store.dart';

class ProfileRegistry {
  ProfileRegistry._(this._db);

  static const int schemaVersion = 3;
  final Database _db;
  Future<void> _recoveryCheckpoint = Future<void>.value();
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
      onCreate: (database, _) async => _createSchema(database),
      onUpgrade: (database, oldVersion, newVersion) async {
        if (oldVersion < 2) await _createPinIntegrityTriggers(database);
        if (oldVersion < 3) await _createRestoreResourceTable(database);
      },
    );
    return ProfileRegistry._(db);
  }

  static Future<void> _createSchema(DatabaseExecutor db) async {
    for (final statement in _schemaStatements) {
      await db.execute(statement);
    }
  }

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
  ];

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

  Future<String> exportRecoverySnapshot() async {
    final tables = <String, Object?>{};
    for (final table in _recoveryTables) {
      final rows = await _db.query(table);
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
    return jsonEncode(<String, Object?>{
      'version': 1,
      'schemaVersion': schemaVersion,
      'tables': tables,
      'preferences': await _exportTvOsRecoverablePreferences(),
    });
  }

  Future<void> importRecoverySnapshot(String source) async {
    final decoded = jsonDecode(source);
    if (decoded is! Map ||
        decoded['version'] != 1 ||
        decoded['schemaVersion'] != schemaVersion ||
        decoded['tables'] is! Map) {
      throw const FormatException('Unsupported profile recovery snapshot');
    }
    final tables = decoded['tables']! as Map;
    for (final table in _recoveryTables) {
      if (tables[table] is! List) {
        throw FormatException('Recovery snapshot is missing $table');
      }
    }
    await _db.transaction((txn) async {
      for (final table in _recoveryTables.reversed) {
        await txn.delete(table);
      }
      for (final table in _recoveryTables) {
        for (final raw in tables[table]! as List) {
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
    final result = <String, Object?>{};
    var encodedBytes = 0;
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
      final bytes = utf8.encode(jsonEncode(value)).length;
      if (bytes > 64 * 1024) continue;
      encodedBytes += utf8.encode(key).length + bytes;
      if (result.length >= 4096 || encodedBytes > 512 * 1024) {
        throw StateError('tvOS recoverable preferences exceed the bound');
      }
      result[key] = value;
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
      if (bytes > 64 * 1024 || encodedBytes > 512 * 1024) {
        throw const FormatException('tvOS recovery preferences exceed bounds');
      }
      normalized[key] = normalizedValue;
    }
    final prefs = await SharedPreferences.getInstance();
    for (final key in prefs.getKeys().where(
      (key) => _scopedPreferencePattern.hasMatch(key),
    )) {
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

  static bool _recoverablePreference(String logicalKey) =>
      !_nonRecoverablePreference.hasMatch(logicalKey);

  static final RegExp _scopedPreferencePattern = RegExp(
    r'^p\.[A-Za-z0-9][A-Za-z0-9._-]{0,95}\.g\.[1-9][0-9]*\.(.+)$',
  );
  static final RegExp _nonRecoverablePreference = RegExp(
    r'(history|resume|cache|recent|continue.?watching|watchlist|favorite|'
    r'playback.?position|epg|tvmaze|download|recording)',
    caseSensitive: false,
  );

  Future<void> checkpointTvOsRecovery() async {
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
  }

  Future<UserProfile> createProfile({
    required String name,
    required UserProfileRole role,
    ProfilePolicy? policy,
    String? avatarKey,
    String? id,
    bool setupComplete = false,
    bool disabled = false,
    UserProfileLifecycle lifecycle = UserProfileLifecycle.active,
    String? actingProfileId,
    int? actingAuthorizationRevision,
    int? actingSessionEpoch,
  }) async {
    final normalizedName = name.trim();
    if (normalizedName.isEmpty) throw ArgumentError.value(name, 'name');
    final profileId = id ?? _newId();
    if (!ProfileScope.isValidProfileId(profileId)) {
      throw ArgumentError.value(profileId, 'id', 'Unsafe profile ID');
    }
    await authorityWillChangeCallback?.call();
    final now = DateTime.now().millisecondsSinceEpoch;
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
        'lock_on_resume': 0,
        'created_at_ms': now,
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
    });
    await checkpointTvOsRecovery();
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

  Future<void> commitActivation({required String targetProfileId}) async {
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
      await txn.rawUpdate(
        '''UPDATE device_state
           SET active_profile_id = ?,
               activation_revision = activation_revision + 1,
               activation_state_json = NULL,
               updated_at_ms = ?
           WHERE singleton_id = 1''',
        <Object>[targetProfileId, now],
      );
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

  Future<void> deleteProfile(String id) async {
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
      await txn.delete(
        'user_profiles',
        where: 'id = ?',
        whereArgs: <Object>[id],
      );
    });
    await checkpointTvOsRecovery();
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
    await checkpointTvOsRecovery();
    return (await getProfile(id))!;
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
    await checkpointTvOsRecovery();
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
    await checkpointTvOsRecovery();
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
    await checkpointTvOsRecovery();
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
    await checkpointTvOsRecovery();
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

  /// Deletes a non-active profile only after the UI has chosen explicit
  /// dispositions. Shared resources and active jobs remain hard blockers.
  Future<void> deleteProfileWithDisposition({
    required String id,
    required bool deleteOwnedResources,
    required bool detachPublicArtifacts,
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
    await checkpointTvOsRecovery();
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
        'sealed_secret_payload': sealedSecretPayload,
        'secret_payload_version': secretPayloadVersion,
        'authorization_revision': resource.authorizationRevision,
        'created_at_ms': now,
        'updated_at_ms': now,
        'disabled_at_ms': resource.enabled ? null : now,
      });
      await txn.insert('profile_resource_grants', <String, Object?>{
        'profile_id': resource.ownerProfileId,
        'resource_id': resource.id,
        'permissions': ownerPermissions,
        'granted_by_profile_id': resource.ownerProfileId,
        'grant_origin_json': '{"origin":"owner"}',
        'created_at_ms': now,
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
    await checkpointTvOsRecovery();
  }

  Future<ConnectionResource?> getResource(String id) async {
    final rows = await _db.query(
      'connection_resources',
      where: 'id = ?',
      whereArgs: <Object>[id],
      limit: 1,
    );
    return rows.isEmpty ? null : _decodeResource(rows.single);
  }

  Future<SealedResourceSecretRecord?> getSealedResourceSecret(String id) async {
    final rows = await _db.query(
      'connection_resources',
      columns: const <String>[
        'id',
        'type',
        'owner_profile_id',
        'public_config_json',
        'sealed_secret_payload',
        'secret_payload_version',
      ],
      where: 'id = ? AND disabled_at_ms IS NULL',
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
      envelope: row['sealed_secret_payload']! as String,
    );
  }

  Future<void> updateResourceSecret({
    required String resourceId,
    required String sealedSecretPayload,
    required int secretPayloadVersion,
    String? actingProfileId,
    int? actingAuthorizationRevision,
    int? expectedResourceAuthorizationRevision,
  }) async {
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
               authorization_revision = authorization_revision + 1,
               updated_at_ms = ?
           WHERE id = ? AND disabled_at_ms IS NULL
             ${expectedResourceAuthorizationRevision == null ? '' : 'AND authorization_revision = ?'}''',
        <Object>[
          sealedSecretPayload,
          secretPayloadVersion,
          now,
          resourceId,
          if (expectedResourceAuthorizationRevision != null)
            expectedResourceAuthorizationRevision,
        ],
      );
      if (changed != 1) throw StateError('Resource is unavailable');
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
    await checkpointTvOsRecovery();
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
    await checkpointTvOsRecovery();
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
      await txn.rawInsert(
        '''INSERT INTO profile_resource_grants
           (profile_id, resource_id, permissions, granted_by_profile_id,
            grant_origin_json, created_at_ms)
           VALUES (?, ?, ?, ?, ?, ?)
           ON CONFLICT(profile_id, resource_id) DO UPDATE SET
             permissions = excluded.permissions,
             granted_by_profile_id = excluded.granted_by_profile_id,
             grant_origin_json = excluded.grant_origin_json''',
        <Object>[
          newOwnerProfileId,
          resourceId,
          ownerPermissions,
          transferredByProfileId,
          jsonEncode(<String, Object?>{
            'origin': 'ownershipTransfer',
            'previousOwnerProfileId': currentOwnerProfileId,
          }),
          now,
        ],
      );
      final changed = await txn.rawUpdate(
        '''UPDATE connection_resources
           SET owner_profile_id = ?, sealed_secret_payload = ?,
               secret_payload_version = ?,
               authorization_revision = authorization_revision + 1,
               updated_at_ms = ?
           WHERE id = ? AND owner_profile_id = ? AND disabled_at_ms IS NULL''',
        <Object>[
          newOwnerProfileId,
          resealedSecretPayload,
          secretPayloadVersion,
          now,
          resourceId,
          currentOwnerProfileId,
        ],
      );
      if (changed != 1) throw StateError('Connection ownership changed');
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
    await checkpointTvOsRecovery();
  }

  Future<void> unbindResource(String profileId, String slot) async {
    await authorityWillChangeCallback?.call();
    await _db.delete(
      'profile_connection_bindings',
      where: 'profile_id = ? AND slot = ?',
      whereArgs: <Object>[profileId, slot],
    );
    await checkpointTvOsRecovery();
  }

  Future<List<ConnectionResource>> listGrantedResources(
    String profileId,
  ) async {
    final rows = await _db.rawQuery(
      '''SELECT r.* FROM connection_resources r
         INNER JOIN profile_resource_grants g ON g.resource_id = r.id
         WHERE g.profile_id = ? AND r.disabled_at_ms IS NULL
         ORDER BY lower(r.label), r.id''',
      <Object>[profileId],
    );
    return rows.map(_decodeResource).toList(growable: false);
  }

  Future<List<ConnectionResource>> listAllResources() async {
    final rows = await _db.query(
      'connection_resources',
      where: 'disabled_at_ms IS NULL',
      orderBy: 'created_at_ms, id',
    );
    return rows.map(_decodeResource).toList(growable: false);
  }

  Future<List<Map<String, Object?>>> listAllResourceGrants() =>
      _db.query('profile_resource_grants', orderBy: 'profile_id, resource_id');

  Future<List<Map<String, Object?>>> listAllResourceBindings() =>
      _db.query('profile_connection_bindings', orderBy: 'profile_id, slot');

  /// Atomically replaces an owner's resources of [types]. This is used by
  /// legacy collection-shaped APIs (WebDAV, IPTV, addons, and indexers) so a
  /// crash can never expose a half-replaced list. Shared resources are never
  /// silently rewritten or deleted; callers must use an explicit share-aware
  /// management flow for those.
  Future<void> replaceOwnedResourceCollection({
    required String ownerProfileId,
    required Set<ConnectionResourceType> types,
    required List<PreparedConnectionResource> replacements,
    required int ownerPermissions,
    String? actingProfileId,
    int? actingAuthorizationRevision,
    ProfileFeature? actingFeature,
  }) async {
    if (types.isEmpty) throw ArgumentError.value(types, 'types');
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
      if (existing.any((row) => (row['borrower_count'] as int? ?? 0) > 0)) {
        throw StateError(
          'A shared connection must be changed in profile management',
        );
      }
      final existingById = <String, Map<String, Object?>>{
        for (final row in existing) row['id']! as String: row,
      };
      final replacementIds = <String>{};
      for (final replacement in replacements) {
        if (!replacementIds.add(replacement.resource.id)) {
          throw StateError('Replacement collection contains duplicate IDs');
        }
      }
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
            'sealed_secret_payload': replacement.sealedSecretPayload,
            'secret_payload_version': replacement.secretPayloadVersion,
            'authorization_revision': resource.authorizationRevision,
            'created_at_ms': now,
            'updated_at_ms': now,
          });
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
              'sealed_secret_payload': replacement.sealedSecretPayload,
              'secret_payload_version': replacement.secretPayloadVersion,
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
        }
        await txn.rawInsert(
          '''INSERT INTO profile_resource_grants
             (profile_id, resource_id, permissions, granted_by_profile_id,
              grant_origin_json, created_at_ms)
             VALUES (?, ?, ?, ?, ?, ?)
             ON CONFLICT(profile_id, resource_id) DO UPDATE SET
               permissions = excluded.permissions,
               granted_by_profile_id = excluded.granted_by_profile_id,
               grant_origin_json = excluded.grant_origin_json''',
          <Object>[
            ownerProfileId,
            resource.id,
            ownerPermissions,
            ownerProfileId,
            '{"origin":"ownerCollection"}',
            now,
          ],
        );
      }
      await txn.rawUpdate(
        '''UPDATE user_profiles
           SET authorization_revision = authorization_revision + 1,
               updated_at_ms = ? WHERE id = ? AND disabled_at_ms IS NULL''',
        <Object>[now, ownerProfileId],
      );
      await _assertAdminInvariant(txn);
    });
    await checkpointTvOsRecovery();
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
      await txn.rawInsert(
        '''INSERT INTO profile_resource_settings
           (profile_id, resource_id, enabled, settings_json)
           VALUES (?, ?, ?, ?)
           ON CONFLICT(profile_id, resource_id) DO UPDATE SET
             enabled = excluded.enabled,
             settings_json = excluded.settings_json''',
        <Object>[profileId, resourceId, enabled ? 1 : 0, encoded],
      );
    });
    await checkpointTvOsRecovery();
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
      await txn.rawInsert(
        '''INSERT INTO profile_resource_grants
           (profile_id, resource_id, permissions, granted_by_profile_id,
            grant_origin_json, created_at_ms)
           VALUES (?, ?, ?, ?, ?, ?)
           ON CONFLICT(profile_id, resource_id) DO UPDATE SET
             permissions = excluded.permissions,
             granted_by_profile_id = excluded.granted_by_profile_id,
             grant_origin_json = excluded.grant_origin_json''',
        <Object>[
          profileId,
          resourceId,
          permissions,
          grantedByProfileId,
          jsonEncode(origin),
          now,
        ],
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
    await checkpointTvOsRecovery();
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
      await checkpointTvOsRecovery();
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
    await checkpointTvOsRecovery();
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
    await checkpointTvOsRecovery();
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
    await checkpointTvOsRecovery();
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
    await _db.rawInsert(
      '''INSERT INTO job_ownership
         (backend, external_job_id, kind, owner_profile_id, resource_id,
          profile_authorization_revision, resource_authorization_revision,
          created_at_ms, terminal_at_ms)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
         ON CONFLICT(backend, external_job_id) DO UPDATE SET
           owner_profile_id = excluded.owner_profile_id,
           resource_id = excluded.resource_id,
           profile_authorization_revision = excluded.profile_authorization_revision,
           resource_authorization_revision = excluded.resource_authorization_revision,
           terminal_at_ms = excluded.terminal_at_ms''',
      <Object?>[
        backend,
        externalJobId,
        kind,
        ownerProfileId,
        resourceId,
        profileAuthorizationRevision,
        resourceAuthorizationRevision,
        DateTime.now().millisecondsSinceEpoch,
        terminalAtMs,
      ],
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
    final existing = await _db.query(
      'owned_artifacts',
      columns: const <String>['id'],
      where: 'kind = ? AND canonical_path = ?',
      whereArgs: <Object>[kind, canonicalPath],
      limit: 1,
    );
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.insert('owned_artifacts', <String, Object?>{
      'id': existing.isEmpty ? _newId() : existing.single['id'],
      'kind': kind,
      'owner_profile_id': ownerProfileId,
      'canonical_path': canonicalPath,
      'ownership_state': 'assigned',
      'detached_owner_token': null,
      'size_bytes': sizeBytes,
      'modified_at_ms': modifiedAtMs ?? now,
      'created_at_ms': now,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, Object?>>> listOwnedArtifacts(
    String ownerProfileId,
  ) => _db.query(
    'owned_artifacts',
    where: 'owner_profile_id = ?',
    whereArgs: <Object>[ownerProfileId],
    orderBy: 'created_at_ms, id',
  );

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

  Future<ProfilePinRecord?> getPinRecord(String profileId) async {
    final rows = await _db.query(
      'user_profiles',
      columns: const <String>[
        'pin_hash',
        'pin_salt',
        'pin_params_json',
        'failed_pin_attempts',
        'locked_until_ms',
        'pin_reset_required',
      ],
      where: 'id = ? AND disabled_at_ms IS NULL',
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
    );
  }

  Future<void> setPinRecord({
    required String profileId,
    required List<int>? hash,
    required List<int>? salt,
    required String? paramsJson,
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
    await checkpointTvOsRecovery();
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
      final exponent = (attempts - 5).clamp(0, 7);
      final lockSeconds = attempts < 5 ? 0 : min(3600, 30 * (1 << exponent));
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
    if (changed) await checkpointTvOsRecovery();
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
    if (changed) await checkpointTvOsRecovery();
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
  }) async {
    await authorityWillChangeCallback?.call();
    final now = DateTime.now().millisecondsSinceEpoch;
    final profileIds = stagedProfileIds.toSet();
    if (profileIds.length != stagedProfileIds.length) {
      throw ArgumentError('Duplicate staged profile ID');
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
          'sealed_secret_payload': item.sealedSecretPayload,
          'secret_payload_version': item.secretPayloadVersion,
          'authorization_revision': 1,
          'created_at_ms': now,
          'updated_at_ms': now,
        });
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
    await checkpointTvOsRecovery();
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
  }) async {
    if (!ProfileScope.isValidProfileId(resourceId)) {
      throw ArgumentError.value(resourceId, 'resourceId');
    }
    await _db.insert('profile_restore_resources', <String, Object?>{
      'restore_id': operationId,
      'resource_id': resourceId,
      'backup_id': backupId,
      'type': type.name,
      'label': label.trim(),
      'owner_profile_id': ownerProfileId,
      'public_config_json': jsonEncode(publicConfig),
      'sealed_secret_payload': sealedSecretPayload,
      'secret_payload_version': secretPayloadVersion,
      'permissions': permissions,
      'binding_slot': bindingSlot,
    });
    await checkpointTvOsRecovery();
  }

  Future<UserProfile> publishDataGeneration({
    required String profileId,
    required int baseGeneration,
    required int stagedGeneration,
    required String operationId,
    bool? profileSetupComplete,
  }) async {
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
        await txn.insert('connection_resources', <String, Object?>{
          'id': row['resource_id'],
          'type': row['type'],
          'label': row['label'],
          'owner_profile_id': row['owner_profile_id'],
          'public_config_json': row['public_config_json'],
          'sealed_secret_payload': row['sealed_secret_payload'],
          'secret_payload_version': row['secret_payload_version'],
          'authorization_revision': 1,
          'created_at_ms': now,
          'updated_at_ms': now,
        });
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
        });
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
    await checkpointTvOsRecovery();
    return (await getProfile(profileId))!;
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
    );
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
  final List<StagedGraphGrant> grants;
  final List<StagedGraphBinding> bindings;

  const StagedGraphResource({
    required this.id,
    required this.type,
    required this.label,
    required this.ownerProfileId,
    required this.publicConfig,
    required this.sealedSecretPayload,
    required this.secretPayloadVersion,
    required this.grants,
    required this.bindings,
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

  const ProfilePinRecord({
    this.hash,
    this.salt,
    this.paramsJson,
    this.failedAttempts = 0,
    this.lockedUntilMs,
    this.resetRequired = false,
  });

  bool get hasPin => hash != null && salt != null && paramsJson != null;
  bool get isCorrupt =>
      (hash != null || salt != null || paramsJson != null) && !hasPin;
}

extension<T> on List<T> {
  T? get singleOrNull => length == 1 ? single : null;
}
