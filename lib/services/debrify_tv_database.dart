import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:synchronized/synchronized.dart';

import 'profiles/profile_storage_paths.dart';
import 'profiles/profile_runtime.dart';
import 'profiles/profile_scope.dart';
import 'profiles/profile_database_adoption_gate.dart';

typedef _DatabaseScope = ({String key, ProfileScope? scope});

class DebrifyTvDatabase {
  DebrifyTvDatabase._();

  static final DebrifyTvDatabase instance = DebrifyTvDatabase._();

  /// Tests inject an in-memory database here (sqflite_common_ffi) so store
  /// logic runs against the real schema without path_provider.
  @visibleForTesting
  static Database? debugDatabaseOverride;

  /// Pauses an opened handle before it can become process-global. Race tests
  /// use this to put profile deactivation precisely inside the open window.
  @visibleForTesting
  static Future<void> Function(String scopeKey)? debugBeforeOpenPublish;

  Database? _db;
  String? _dbScopeKey;
  String? _openingScopeKey;
  final Set<String> _deactivatedScopeKeys = <String>{};
  final Lock _scopeLock = Lock();
  final Object _operationZoneKey = Object();
  int _activeOperations = 0;
  Completer<void>? _operationsDrained;

  /// Exposes a handle only for lifecycle tests and schema maintenance.
  /// Production reads must use [runScoped] so [closeScope] cannot close the
  /// handle while an operation is using it.
  @visibleForTesting
  Future<Database> get database async {
    final active = Zone.current[_operationZoneKey] as Database?;
    if (active != null) return active;
    await ProfileDatabaseAdoptionGate.waitUntilReleased();
    final override = debugDatabaseOverride;
    if (override != null) return override;
    final requested = _requestedScope();
    if (_deactivatedScopeKeys.contains(requested.key)) {
      throw StateError('Debrify TV database scope is deactivated');
    }
    final opened = _db;
    if (opened != null && _dbScopeKey == requested.key) {
      return opened;
    }
    return _scopeLock.synchronized(() => _databaseLocked(requested));
  }

  @visibleForTesting
  bool get debugInOperationZone => Zone.current[_operationZoneKey] is Database;

  Future<Database> _databaseLocked(_DatabaseScope requested) async {
    if (_deactivatedScopeKeys.contains(requested.key)) {
      throw StateError('Debrify TV database scope changed while opening');
    }

    final existing = _db;
    if (existing != null) {
      if (_dbScopeKey == requested.key) return existing;
      // A stale handle must never be silently adopted by the next profile.
      _db = null;
      _dbScopeKey = null;
      await existing.close();
    }

    _openingScopeKey = requested.key;
    try {
      return await _openAndPublishDatabase(requested);
    } finally {
      if (_openingScopeKey == requested.key) _openingScopeKey = null;
    }
  }

  Future<Database> _openAndPublishDatabase(_DatabaseScope requested) async {
    final dbPath = requested.scope == null
        ? await ProfileStoragePaths.documentsFile('debrify_tv.db')
        : await ProfileRuntime.withCapturedScope(
            requested.scope!,
            () => ProfileStoragePaths.documentsFile('debrify_tv.db'),
          );

    final opened = await openDatabase(
      dbPath,
      version: 6,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      // Without this, sqflite THROWS on a version decrease (sideloading an
      // older APK — routine on TV boxes) — and the throw surfaced inside
      // IptvMediaStore._ensureMigrated, which swallows it and retries
      // forever: favorites/history silently never load. This DB is
      // favorites/history/resume bookkeeping, so rebuilding it from scratch
      // beats a permanently wedged store.
      onDowngrade: onDatabaseDowngradeDelete,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE tv_channels (
            channel_id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            avoid_nsfw INTEGER NOT NULL DEFAULT 1,
            channel_number INTEGER NOT NULL UNIQUE,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE tv_channel_keywords (
            channel_id TEXT NOT NULL,
            position INTEGER NOT NULL,
            keyword TEXT NOT NULL,
            PRIMARY KEY (channel_id, position),
            FOREIGN KEY (channel_id) REFERENCES tv_channels(channel_id) ON DELETE CASCADE
          )
        ''');

        await db.execute('''
          CREATE TABLE tv_channel_cache_state (
            channel_id TEXT PRIMARY KEY,
            status TEXT NOT NULL DEFAULT 'warming',
            error_message TEXT,
            fetched_at INTEGER NOT NULL DEFAULT 0,
            FOREIGN KEY (channel_id) REFERENCES tv_channels(channel_id) ON DELETE CASCADE
          )
        ''');

        await db.execute('''
          CREATE TABLE tv_cached_torrents (
            channel_id TEXT NOT NULL,
            infohash TEXT NOT NULL,
            name TEXT NOT NULL,
            size_bytes INTEGER NOT NULL,
            created_unix INTEGER NOT NULL,
            seeders INTEGER NOT NULL,
            leechers INTEGER NOT NULL,
            completed INTEGER NOT NULL,
            scraped_date INTEGER NOT NULL,
            keywords_json TEXT NOT NULL,
            sources_json TEXT NOT NULL,
            added_at INTEGER NOT NULL,
            PRIMARY KEY (channel_id, infohash),
            FOREIGN KEY (channel_id) REFERENCES tv_channels(channel_id) ON DELETE CASCADE
          )
        ''');

        await db.execute('''
          CREATE INDEX idx_tv_cached_torrents_channel_added
          ON tv_cached_torrents(channel_id, added_at)
        ''');

        await db.execute('''
          CREATE TABLE tv_keyword_stats (
            channel_id TEXT NOT NULL,
            keyword TEXT NOT NULL,
            total_fetched INTEGER NOT NULL,
            last_searched_at INTEGER NOT NULL,
            pages_pulled INTEGER NOT NULL,
            pirate_bay_hits INTEGER NOT NULL,
            PRIMARY KEY (channel_id, keyword),
            FOREIGN KEY (channel_id) REFERENCES tv_channels(channel_id) ON DELETE CASCADE
          )
        ''');

        await createIptvStoreTables(db);
      },
      onUpgrade: runUpgrade,
    );

    // Ensure index exists for fresh creates (onCreate already runs for v2 DB)
    await opened.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_tv_channels_channel_number ON tv_channels(channel_number)',
    );
    await debugBeforeOpenPublish?.call(requested.key);

    // closeScope marks the authoritative owner and any in-flight captured
    // scope synchronously, before it waits for this lock. Captured staging
    // scopes are valid, but a deactivated session can never publish late.
    if (_deactivatedScopeKeys.contains(requested.key)) {
      await opened.close();
      throw StateError('Debrify TV database scope changed while opening');
    }

    _db = opened;
    _dbScopeKey = requested.key;
    return opened;
  }

  Future<void> closeScope([ProfileScope? deactivatingScope]) async {
    final owner = deactivatingScope == null
        ? (ProfileRuntime.isInitialized ? _requestedScope() : null)
        : _scopeOf(deactivatingScope);
    // Set this before awaiting the lock: callers arriving while an open or
    // transaction drains must be denied, not queued to reopen the old scope.
    if (owner != null) _deactivatedScopeKeys.add(owner.key);
    final opening = _openingScopeKey;
    if (opening != null) _deactivatedScopeKeys.add(opening);
    final openedScope = _dbScopeKey;
    if (openedScope != null) _deactivatedScopeKeys.add(openedScope);
    while (true) {
      final drain = await _scopeLock.synchronized<Completer<void>?>(() async {
        if (_activeOperations > 0) {
          return _operationsDrained ??= Completer<void>();
        }
        final opened = _db;
        _db = null;
        _dbScopeKey = null;
        if (opened != null) await opened.close();
        return null;
      });
      if (drain == null) return;
      await drain.future;
    }
  }

  /// Re-enables the authoritative scope after a failed switch rolls back to
  /// it. Successful switches naturally have a different scope key, but call
  /// this too so the lifecycle contract stays explicit.
  void activateScope(ProfileScope scope) {
    if (ProfileRuntime.scope.value != scope) {
      throw StateError('Cannot activate a non-authoritative database scope');
    }
    final key = _scopeOf(scope).key;
    _deactivatedScopeKeys.remove(key);
  }

  /// Runs one complete logical operation against the scope captured at
  /// admission. Operations may overlap, but profile deactivation waits for
  /// every admitted operation to drain before closing the handle. Nested
  /// calls reuse the captured handle so an await can never redirect the
  /// second half of a read/modify/write operation into a newer profile.
  Future<T> runScoped<T>(Future<T> Function(Database db) action) async {
    final active = Zone.current[_operationZoneKey] as Database?;
    if (active != null) return action(active);

    await ProfileDatabaseAdoptionGate.waitUntilReleased();
    final override = debugDatabaseOverride;
    if (override != null) {
      return runZoned(
        () => action(override),
        zoneValues: <Object, Object>{_operationZoneKey: override},
      );
    }
    final requested = _requestedScope();
    late final Database admitted;
    await _scopeLock.synchronized(() async {
      admitted = await _databaseLocked(requested);
      _activeOperations += 1;
    });
    try {
      return await runZoned(
        () => action(admitted),
        zoneValues: <Object, Object>{_operationZoneKey: admitted},
      );
    } finally {
      await _scopeLock.synchronized(() {
        _activeOperations -= 1;
        if (_activeOperations == 0) {
          final drained = _operationsDrained;
          _operationsDrained = null;
          if (drained != null && !drained.isCompleted) drained.complete();
        }
      });
    }
  }

  Future<T> runTxn<T>(Future<T> Function(Transaction txn) action) {
    return runScoped((db) => db.transaction(action, exclusive: false));
  }

  _DatabaseScope _requestedScope() {
    if (!ProfileRuntime.isInitialized) {
      throw StateError('Profile runtime is not initialized');
    }
    if (!ProfileRuntime.isProfileCommitted) {
      return (key: 'legacy', scope: null);
    }
    final scope = ProfileRuntime.capture();
    return _scopeOf(scope);
  }

  _DatabaseScope _scopeOf(ProfileScope scope) => (
    key: '${scope.profileId}:${scope.dataGeneration}:${scope.sessionEpoch}',
    scope: scope,
  );

  @visibleForTesting
  Future<void> debugResetScopeState() => _scopeLock.synchronized(() async {
    final opened = _db;
    _db = null;
    _dbScopeKey = null;
    _openingScopeKey = null;
    _deactivatedScopeKeys.clear();
    debugBeforeOpenPublish = null;
    if (opened != null) await opened.close();
  });

  /// Schema migrations. Named (rather than an inline closure) so migration
  /// tests can drive it against a database opened at an older version.
  @visibleForTesting
  static Future<void> runUpgrade(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 2) {
      await db.execute(
        'ALTER TABLE tv_channels ADD COLUMN channel_number INTEGER',
      );

      final rows = await db.query(
        'tv_channels',
        columns: ['channel_id'],
        orderBy: 'updated_at DESC',
      );

      var channelNumber = 1;
      for (final row in rows) {
        final channelId = row['channel_id'] as String?;
        if (channelId == null || channelId.isEmpty) {
          continue;
        }
        await db.update(
          'tv_channels',
          {'channel_number': channelNumber},
          where: 'channel_id = ?',
          whereArgs: [channelId],
        );
        channelNumber += 1;
      }

      await db.execute(
        'CREATE UNIQUE INDEX IF NOT EXISTS idx_tv_channels_channel_number ON tv_channels(channel_number)',
      );
    }

    if (oldVersion < 3) {
      await createIptvStoreTables(db);
    }
    // Only a GENUINE v3 database has an iptv_favorites table predating
    // channel_number. v1/v2 databases got their IPTV tables from the call
    // above, which since v5 doesn't create iptv_favorites at all — hence the
    // `== 3` rather than `< 4`, and hence the existence check in the v5 step.
    if (oldVersion == 3) {
      await db.execute(
        'ALTER TABLE iptv_favorites ADD COLUMN channel_number INTEGER',
      );
    }

    if (oldVersion < 5) {
      await migrateFavoritesToLists(db);
    }

    if (oldVersion < 6 && newVersion >= 6) {
      await migrateIptvChannelOrder(db);
    }
  }

  /// v6: channels inside Favorites/custom lists gain an explicit position,
  /// and imported-file categories gain their durable order table.
  ///
  /// Existing list rows are backfilled in their former case-insensitive A-Z
  /// presentation order so upgrading cannot visibly reshuffle a user's lists.
  static Future<void> migrateIptvChannelOrder(DatabaseExecutor db) async {
    await createIptvStoreTables(db);
    final columns = await db.rawQuery('PRAGMA table_info(iptv_list_channels)');
    final hasPosition = columns.any((row) => row['name'] == 'position');
    if (!hasPosition) {
      await db.execute(
        'ALTER TABLE iptv_list_channels '
        'ADD COLUMN position INTEGER NOT NULL DEFAULT 0',
      );
    }

    final lists = await db.query('iptv_lists', columns: ['id']);
    for (final list in lists) {
      final listId = list['id'] as String;
      final rows = await db.query(
        'iptv_list_channels',
        columns: ['url', 'name'],
        where: 'list_id = ?',
        whereArgs: [listId],
        orderBy: 'name COLLATE NOCASE ASC, url ASC',
      );
      for (var position = 0; position < rows.length; position++) {
        await db.update(
          'iptv_list_channels',
          {'position': position},
          where: 'list_id = ? AND url = ?',
          whereArgs: [listId, rows[position]['url']],
        );
      }
    }
  }

  /// v5: favorites stop being their own table and become the built-in list
  /// inside the custom-lists schema.
  ///
  /// The `sqlite_master` probe is load-bearing: on a v1/v2 database
  /// [createIptvStoreTables] has already run with the CURRENT schema, so
  /// `iptv_favorites` never existed on that path and a blind `SELECT` from it
  /// would throw mid-upgrade. It also makes a half-completed previous attempt
  /// (tables created, drop not reached) resumable.
  static Future<void> migrateFavoritesToLists(DatabaseExecutor db) async {
    await createIptvStoreTables(db);

    final legacy = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
      ['iptv_favorites'],
    );
    if (legacy.isEmpty) return;

    // content_type / duration have no legacy counterpart — they stay NULL and
    // are backfilled by the reconcile pass the first time each playlist is
    // opened (IptvMediaStore). Until then a migrated VOD favorite keeps
    // presenting as live, exactly as it did before this migration.
    await db.execute(
      '''
      INSERT OR IGNORE INTO iptv_list_channels
        (list_id, url, name, logo_url, channel_group, playlist_id,
         channel_number, content_type, duration, http_headers_json, added_at)
      SELECT ?, url, name, logo_url, channel_group, playlist_id,
             channel_number, NULL, NULL, http_headers_json, added_at
      FROM iptv_favorites
    ''',
      [favoritesListId],
    );

    await db.execute('DROP TABLE iptv_favorites');
  }

  /// Reserved id of the built-in Favorites list: always present, never
  /// renamed, never deleted, and the destination of every legacy favorite.
  static const String favoritesListId = 'favorites';

  /// IPTV lists / watch history / video resume tables (schema v6), used by
  /// IptvMediaStore. `IF NOT EXISTS` so it's safe from both onCreate and
  /// onUpgrade, and callable directly by tests on an in-memory database.
  static Future<void> createIptvStoreTables(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS iptv_lists (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        position INTEGER NOT NULL,
        is_builtin INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS iptv_list_channels (
        list_id TEXT NOT NULL,
        url TEXT NOT NULL,
        name TEXT NOT NULL DEFAULT '',
        logo_url TEXT NOT NULL DEFAULT '',
        channel_group TEXT NOT NULL DEFAULT '',
        playlist_id TEXT NOT NULL DEFAULT '',
        channel_number INTEGER,
        content_type TEXT,
        duration INTEGER,
        http_headers_json TEXT,
        added_at INTEGER NOT NULL DEFAULT 0,
        position INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (list_id, url),
        FOREIGN KEY (list_id) REFERENCES iptv_lists(id) ON DELETE CASCADE
      )
    ''');

    // CREATE TABLE IF NOT EXISTS does not evolve an existing v5 table. Keep
    // this shape repair next to the table definition so the order index below
    // is never attempted before its column exists (including v1→v6 jumps).
    final listChannelColumns = await db.rawQuery(
      'PRAGMA table_info(iptv_list_channels)',
    );
    if (!listChannelColumns.any((row) => row['name'] == 'position')) {
      await db.execute(
        'ALTER TABLE iptv_list_channels '
        'ADD COLUMN position INTEGER NOT NULL DEFAULT 0',
      );
    }

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_iptv_list_channels_playlist
      ON iptv_list_channels(playlist_id)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_iptv_list_channels_url
      ON iptv_list_channels(url)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_iptv_list_channels_order
      ON iptv_list_channels(list_id, position)
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS iptv_category_channel_orders (
        source_id TEXT NOT NULL,
        channel_group TEXT NOT NULL,
        url TEXT NOT NULL,
        name TEXT NOT NULL,
        occurrence INTEGER NOT NULL,
        position INTEGER NOT NULL,
        PRIMARY KEY (source_id, channel_group, url, name, occurrence)
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_iptv_category_channel_order
      ON iptv_category_channel_orders(source_id, channel_group, position)
    ''');

    await seedBuiltinList(db);

    await db.execute('''
      CREATE TABLE IF NOT EXISTS iptv_watch_history (
        url TEXT PRIMARY KEY,
        name TEXT NOT NULL DEFAULT '',
        logo_url TEXT NOT NULL DEFAULT '',
        channel_group TEXT NOT NULL DEFAULT '',
        playlist_id TEXT NOT NULL DEFAULT '',
        http_headers_json TEXT,
        series_id TEXT,
        series_name TEXT,
        season INTEGER,
        episode INTEGER,
        has_next INTEGER,
        last_played_at INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_iptv_watch_history_last_played
      ON iptv_watch_history(last_played_at)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_iptv_watch_history_playlist
      ON iptv_watch_history(playlist_id)
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS video_resume (
        resume_key TEXT PRIMARY KEY,
        position_ms INTEGER NOT NULL DEFAULT 0,
        duration_ms INTEGER NOT NULL DEFAULT 0,
        speed REAL NOT NULL DEFAULT 1.0,
        aspect TEXT NOT NULL DEFAULT 'contain',
        updated_at INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }

  /// Insert the built-in Favorites row if it isn't already there.
  ///
  /// MUST be `INSERT OR IGNORE`, never `OR REPLACE`. The database opens with
  /// `PRAGMA foreign_keys = ON`, and REPLACE resolves a conflict by DELETEing
  /// the conflicting row with foreign-key actions firing — which would
  /// cascade through `iptv_list_channels` and wipe every favorite. This runs
  /// from [createIptvStoreTables], i.e. on every open, so that would be a
  /// data-loss-on-launch bug rather than an edge case.
  static Future<void> seedBuiltinList(DatabaseExecutor db) async {
    await db.execute(
      'INSERT OR IGNORE INTO iptv_lists '
      '(id, name, position, is_builtin, created_at, updated_at) '
      'VALUES (?, ?, 0, 1, 0, 0)',
      [favoritesListId, 'Favorites'],
    );
  }
}
