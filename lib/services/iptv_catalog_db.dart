import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/open.dart' as sqlite_open;
import 'package:sqlite3/sqlite3.dart';

import '../models/iptv_playlist.dart';

/// Worker entry for cold catalog initialization. The native handle is opened
/// with FULLMUTEX because ownership moves to Flutter's isolate after this job;
/// no Dart [Database] wrapper is created here, so no worker finalizer can close
/// the transferred handle when the isolate exits.
_CatalogDbPreparation _prepareCatalogDb(String path) {
  final api = _NativeSqliteApi.open();
  final handleAddress = api.openPrepared(path);
  return _CatalogDbPreparation(
    handleAddress: handleAddress,
    isolateName: Isolate.current.debugName,
  );
}

void _closeTransferredCatalogDb(int handleAddress) {
  _NativeSqliteApi.open().closeHandle(handleAddress);
}

/// Worker entry for catalog deletion. `args[0]` is the database path, the rest
/// are catalog keys. Mass deletes belong off the UI isolate — see
/// [IptvCatalogDb.removeCatalogsByKeys].
void _removeCatalogsJob(List<String> args) {
  final db = IptvCatalogDb._openConnection(args.first);
  try {
    IptvCatalogDb.removeCatalogsOn(db, args.skip(1));
  } finally {
    db.dispose();
  }
}

/// Worker entry for [IptvCatalogDb.adoptNumbering] — a whole-catalog identity
/// pass, so it never runs on the UI isolate. Returns the corrected row count.
int _adoptNumberingJob(List<String> args) {
  final db = IptvCatalogDb._openConnection(args[0]);
  try {
    return IptvCatalogDb.adoptNumberingFromCatalog(
      db,
      catalogKey: args[1],
      sourceKey: args[2],
    );
  } finally {
    db.dispose();
  }
}

/// Worker entry for pending row-level migrations. Opens its OWN connection —
/// the UI isolate's handle stays untouched, and WAL lets it keep serving reads
/// from the pre-migration snapshot for the (now sub-second) duration of the
/// upgrade. Returns the resulting schema version.
int _migrateCatalogDb(String path) {
  final db = IptvCatalogDb._openConnection(path);
  try {
    return IptvCatalogDb._runPendingMigrations(db);
  } finally {
    db.dispose();
  }
}

class _CatalogDbPreparation {
  const _CatalogDbPreparation({
    required this.handleAddress,
    required this.isolateName,
  });

  final int handleAddress;
  final String? isolateName;
}

typedef _SqliteOpenNative =
    Int32 Function(Pointer<Utf8>, Pointer<Pointer<Void>>, Int32, Pointer<Utf8>);
typedef _SqliteOpenDart =
    int Function(Pointer<Utf8>, Pointer<Pointer<Void>>, int, Pointer<Utf8>);
typedef _SqliteExecNative =
    Int32 Function(
      Pointer<Void>,
      Pointer<Utf8>,
      Pointer<Void>,
      Pointer<Void>,
      Pointer<Pointer<Utf8>>,
    );
typedef _SqliteExecDart =
    int Function(
      Pointer<Void>,
      Pointer<Utf8>,
      Pointer<Void>,
      Pointer<Void>,
      Pointer<Pointer<Utf8>>,
    );
typedef _SqliteCloseNative = Int32 Function(Pointer<Void>);
typedef _SqliteCloseDart = int Function(Pointer<Void>);
typedef _SqliteFreeNative = Void Function(Pointer<Void>);
typedef _SqliteFreeDart = void Function(Pointer<Void>);
typedef _SqliteErrmsgNative = Pointer<Utf8> Function(Pointer<Void>);
typedef _SqliteErrmsgDart = Pointer<Utf8> Function(Pointer<Void>);
typedef _SqliteExtendedResultsNative = Int32 Function(Pointer<Void>, Int32);
typedef _SqliteExtendedResultsDart = int Function(Pointer<Void>, int);

/// Minimal native API used only to create a connection on a worker and
/// transfer its ownership. Normal queries continue through package:sqlite3's
/// safe Dart wrapper after [sqlite3.fromPointer] adopts this handle.
class _NativeSqliteApi {
  _NativeSqliteApi._(DynamicLibrary library)
    : _open = library
          .lookup<NativeFunction<_SqliteOpenNative>>('sqlite3_open_v2')
          .asFunction(),
      _exec = library
          .lookup<NativeFunction<_SqliteExecNative>>('sqlite3_exec')
          .asFunction(),
      _close = library
          .lookup<NativeFunction<_SqliteCloseNative>>('sqlite3_close_v2')
          .asFunction(),
      _free = library
          .lookup<NativeFunction<_SqliteFreeNative>>('sqlite3_free')
          .asFunction(),
      _errmsg = library
          .lookup<NativeFunction<_SqliteErrmsgNative>>('sqlite3_errmsg')
          .asFunction(),
      _extendedResults = library
          .lookup<NativeFunction<_SqliteExtendedResultsNative>>(
            'sqlite3_extended_result_codes',
          )
          .asFunction();

  factory _NativeSqliteApi.open() =>
      _NativeSqliteApi._(sqlite_open.open.openSqlite());

  // https://sqlite.org/c3ref/c_open_autoproxy.html
  static const _openReadWrite = 0x00000002;
  static const _openCreate = 0x00000004;
  static const _openFullMutex = 0x00010000;
  static const _ok = 0;

  final _SqliteOpenDart _open;
  final _SqliteExecDart _exec;
  final _SqliteCloseDart _close;
  final _SqliteFreeDart _free;
  final _SqliteErrmsgDart _errmsg;
  final _SqliteExtendedResultsDart _extendedResults;

  int openPrepared(String path) {
    final pathPtr = path.toNativeUtf8();
    final out = calloc<Pointer<Void>>();
    Pointer<Void> handle = nullptr;
    var transferred = false;
    try {
      final result = _open(
        pathPtr,
        out,
        _openReadWrite | _openCreate | _openFullMutex,
        nullptr,
      );
      handle = out.value;
      if (result != _ok || handle == nullptr) {
        final message = handle == nullptr
            ? 'SQLite returned code $result without a database handle'
            : _errmsg(handle).toDartString();
        throw StateError('Could not open IPTV catalog database: $message');
      }
      _extendedResults(handle, 1);

      for (final sql in IptvCatalogDb._connectionSetupSql) {
        _execute(handle, sql);
      }
      for (final sql in IptvCatalogDb._defensiveCleanupSql) {
        try {
          _execute(handle, sql);
        } catch (_) {
          // A malformed leftover must not prevent the clean schema from
          // opening, matching the previous _createSchema behavior.
        }
      }
      for (final sql in IptvCatalogDb._schemaSql) {
        _execute(handle, sql);
      }
      for (final sql in IptvCatalogDb._columnMigrationSql) {
        try {
          _execute(handle, sql);
        } catch (_) {
          // ALTER ADD COLUMN intentionally fails once an upgraded database
          // already has the column — the only outcome that matters here is
          // "the column exists".
        }
      }
      transferred = true;
      return handle.address;
    } finally {
      calloc.free(pathPtr);
      calloc.free(out);
      if (!transferred && handle != nullptr) {
        _close(handle);
      }
    }
  }

  void closeHandle(int address) {
    if (address == 0) return;
    _close(Pointer<Void>.fromAddress(address));
  }

  void _execute(Pointer<Void> handle, String sql) {
    final sqlPtr = sql.toNativeUtf8();
    final errorOut = calloc<Pointer<Utf8>>();
    try {
      final result = _exec(handle, sqlPtr, nullptr, nullptr, errorOut);
      if (result == _ok) return;
      final error = errorOut.value;
      final message = error == nullptr
          ? _errmsg(handle).toDartString()
          : error.toDartString();
      throw StateError('IPTV catalog SQL failed ($result): $message');
    } finally {
      final error = errorOut.value;
      if (error != nullptr) _free(error.cast());
      calloc.free(errorOut);
      calloc.free(sqlPtr);
    }
  }
}

/// The IPTV catalog store: every channel of every loaded catalog as rows in
/// `iptv_catalog.db`, so the UI can page/search/count with SQL instead of
/// holding tens of thousands of [IptvChannel]s on the heap. This is what
/// makes catalog size stop mattering on low-RAM devices.
///
/// Deliberately raw `package:sqlite3`, NOT sqflite:
///  * ingest runs on the PARSE WORKER isolate (sqflite handles can't cross
///    isolates, and shipping a 55k-object graph back to the UI isolate is
///    exactly the copy this architecture exists to avoid);
///  * UI reads are synchronous FFI — a 30-row page or a COUNT is
///    sub-millisecond, cheaper than a platform-channel round trip, and
///    callable from build paths without async plumbing.
/// Reader and writer are separate connections on the same WAL file; the
/// generation protocol below makes refreshes invisible until they commit
/// (proven in test/catalog_ingest_spike_test.dart).
///
/// A catalog is identified by an [IptvCatalogKey] (`xc|server|user|type` or
/// `m3u|url`), so eligibility ("is this a cacheable catalog?") and
/// invalidation (settings edit/delete) ask the same question everywhere.
/// Virtual playlists (favorites://, continue://, Stremio, local files) have no
/// key and stay materialized in memory.
///
/// Each ingest writes a NEW generation, flips the `catalogs` pointer and
/// deletes the old generation in ONE transaction — a reader either sees the
/// complete old catalog or the complete new one, never a mix, and a crash
/// mid-ingest leaves the old catalog untouched.
class IptvCatalogDb {
  IptvCatalogDb._();

  static const _dbFileName = 'iptv_catalog.db';
  static const _schemaVersion = 2;
  static const _connectionSetupSql = [
    'PRAGMA journal_mode=WAL',
    'PRAGMA synchronous=NORMAL',
    'PRAGMA busy_timeout=5000',
  ];
  static const _defensiveCleanupSql = [
    'DROP TRIGGER IF EXISTS channels_fts_ai',
    'DROP TRIGGER IF EXISTS channels_fts_ad',
    'DROP TABLE IF EXISTS channels_fts',
  ];
  static const _schemaSql = [
    '''
      CREATE TABLE IF NOT EXISTS meta (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''',
    '''
      CREATE TABLE IF NOT EXISTS catalogs (
        catalog_key TEXT PRIMARY KEY,
        generation INTEGER NOT NULL,
        channel_count INTEGER NOT NULL,
        content_digest TEXT NOT NULL,
        categories_json TEXT,
        epg_url TEXT,
        ingested_at INTEGER NOT NULL
      )
    ''',
    '''
      CREATE TABLE IF NOT EXISTS channels (
        id INTEGER PRIMARY KEY,
        catalog_key TEXT NOT NULL,
        generation INTEGER NOT NULL,
        position INTEGER NOT NULL,
        name TEXT NOT NULL,
        url TEXT NOT NULL,
        logo_url TEXT,
        grp TEXT,
        duration INTEGER,
        content_type TEXT,
        attributes_json TEXT,
        http_headers_json TEXT,
        search_key TEXT NOT NULL,
        channel_number INTEGER
      )
    ''',
    '''
      CREATE INDEX IF NOT EXISTS idx_channels_page
      ON channels(catalog_key, generation, position)
    ''',
    '''
      CREATE INDEX IF NOT EXISTS idx_channels_grp
      ON channels(catalog_key, generation, grp)
    ''',
    '''
      CREATE INDEX IF NOT EXISTS idx_channels_url
      ON channels(catalog_key, generation, url)
    ''',
    '''
      CREATE TABLE IF NOT EXISTS channel_number_namespaces (
        namespace_id TEXT PRIMARY KEY,
        active_source_key TEXT,
        last_channel_count INTEGER NOT NULL DEFAULT 0,
        max_number INTEGER NOT NULL DEFAULT 0,
        updated_at INTEGER NOT NULL
      )
    ''',
    '''
      CREATE TABLE IF NOT EXISTS channel_number_aliases (
        source_key TEXT PRIMARY KEY,
        namespace_id TEXT NOT NULL,
        is_active INTEGER NOT NULL DEFAULT 1,
        updated_at INTEGER NOT NULL
      )
    ''',
    '''
      CREATE INDEX IF NOT EXISTS idx_channel_number_alias_namespace
      ON channel_number_aliases(namespace_id, is_active)
    ''',
    '''
      CREATE TABLE IF NOT EXISTS channel_number_assignments (
        namespace_id TEXT NOT NULL,
        identity_key TEXT NOT NULL,
        channel_number INTEGER NOT NULL,
        last_seen INTEGER NOT NULL,
        PRIMARY KEY(namespace_id, identity_key),
        UNIQUE(namespace_id, channel_number)
      )
    ''',
    '''
      CREATE TABLE IF NOT EXISTS epg_programmes (
        guide_key TEXT NOT NULL,
        channel_id TEXT NOT NULL,
        start_ms INTEGER NOT NULL,
        stop_ms INTEGER NOT NULL,
        title TEXT NOT NULL,
        description TEXT NOT NULL DEFAULT '',
        PRIMARY KEY (guide_key, channel_id, start_ms)
      )
    ''',
    '''
      CREATE TABLE IF NOT EXISTS epg_guides (
        guide_key TEXT PRIMARY KEY,
        epg_url TEXT NOT NULL,
        fetched_at INTEGER NOT NULL,
        saw_wanted INTEGER NOT NULL DEFAULT 0,
        channel_count INTEGER NOT NULL DEFAULT 0,
        name_to_id_json TEXT
      )
    ''',
  ];
  /// Metadata-only DDL: `ALTER TABLE ... ADD COLUMN` rewrites the schema
  /// header and never touches a row, so its cost is independent of catalog
  /// size and it can stay on the connection-preparation path. Everything that
  /// reads or writes rows belongs in [_runPendingMigrations] instead.
  static const _columnMigrationSql = [
    'ALTER TABLE channels ADD COLUMN channel_number INTEGER',
  ];

  /// The v2 backfill: give every pre-numbering live row a provisional number
  /// in catalog order.
  ///
  /// `UPDATE ... FROM` is load-bearing, not style. The obvious spelling —
  /// `SET channel_number = (SELECT ... FROM numbered WHERE numbered.id =
  /// channels.id)` — plans as a CORRELATED SCALAR SUBQUERY that re-scans the
  /// whole materialized CTE once per updated row: quadratic, and measured at
  /// 14 SECONDS for 50k channels on a fast desktop (minutes on the low-end TV
  /// boxes that carry those playlists, which is what made opening the IPTV
  /// page look like a hang). Joined against the CTE the same work is ~45ms.
  /// Any rewrite here must keep `EXPLAIN QUERY PLAN` free of a correlated
  /// subquery — iptv_catalog_db_test.dart asserts exactly that.
  static const _numberBackfillSql = '''
      WITH numbered AS (
        SELECT id,
               ROW_NUMBER() OVER (
                 PARTITION BY catalog_key, generation ORDER BY position
               ) AS assigned_number
        FROM channels
        WHERE channel_number IS NULL AND
          (CASE WHEN content_type IS NOT NULL
            THEN content_type = 'live'
            ELSE (duration IS NULL OR duration = -1)
          END)
      )
      UPDATE channels
      SET channel_number = numbered.assigned_number
      FROM numbered
      WHERE numbered.id = channels.id
    ''';

  /// The backfill statement, so the test suite can assert its query plan.
  @visibleForTesting
  static String get debugNumberBackfillSql => _numberBackfillSql;

  /// Built AFTER the backfill (inside the same transaction), never before it:
  /// maintaining it across a 50k-row mass update costs ~50% more than one
  /// linear build at the end, and writes an index page per row into the WAL.
  static const _numberIndexSql =
      'CREATE INDEX IF NOT EXISTS idx_channels_number '
      'ON channels(catalog_key, generation, channel_number)';

  /// Tests point this at a temp directory; production resolves the app
  /// documents directory once in [open].
  @visibleForTesting
  static String? debugDirectoryOverride;

  static Database? _db;
  static String? _path;
  static Future<void>? _opening;
  static Future<void>? _migrating;

  @visibleForTesting
  static String? debugLastPreparationIsolateName;

  @visibleForTesting
  static int debugPreparationCount = 0;

  /// How many times [ensureMigrations] found work to do. Stays at its initial
  /// value once a database is migrated — that is the property worth asserting.
  @visibleForTesting
  static int debugMigrationRunCount = 0;

  /// The resolved database path — worker isolates need it to open their own
  /// connection. Only valid after [open] has completed.
  static String get path {
    final resolved = _path;
    if (resolved == null) {
      throw StateError('IptvCatalogDb.open() has not completed yet');
    }
    return resolved;
  }

  static bool get isOpen => _db != null;

  /// Prepares and opens the catalog database. Idempotent and shared across
  /// concurrent callers.
  ///
  /// Cold file opening, WAL negotiation, defensive cleanup and every schema /
  /// index statement run on a worker isolate. The UI isolate only attaches a
  /// connection to the already-prepared file afterwards; all subsequent reads
  /// stay synchronous because the paging facade faults tiny windows from build
  /// paths.
  ///
  /// Cost here is bounded and independent of channel count: only DDL runs.
  /// Row-touching upgrades live in [ensureMigrations], which callers that need
  /// migrated data await separately.
  static Future<void> open() {
    if (_db != null) return Future.value();
    return _opening ??= _open().whenComplete(() => _opening = null);
  }

  /// Applies any pending row-level schema migration, on a worker isolate.
  ///
  /// Free once applied — the gate is a single-page `PRAGMA user_version` read
  /// on the already-open connection, so the steady state costs one synchronous
  /// query and never spawns an isolate. Concurrent callers share one run.
  ///
  /// The migration is one transaction covering the backfill, the index build
  /// AND the version stamp, all three of which SQLite rolls back together. A
  /// device that dies mid-upgrade (which a 50k-channel box genuinely did)
  /// therefore reopens on an untouched v1 database and simply retries — there
  /// is no half-migrated state to detect or resume from.
  /// Tail of the global heavy-work queue. Process-wide on purpose: see
  /// [runExclusive].
  static Future<void> _maintenanceQueue = Future<void>.value();

  /// How many jobs [runExclusive] has admitted. Tests assert that overlapping
  /// callers do not overlap.
  @visibleForTesting
  static int debugMaintenanceRunCount = 0;

  /// Runs [job] with no other catalog maintenance running anywhere in the
  /// process, queueing behind whatever is already in flight.
  ///
  /// Serializing inside one page was not enough. A page's in-flight workers
  /// cannot be cancelled when it goes away, so leaving and reopening IPTV,
  /// switching providers, or any second load would start a fresh pipeline
  /// alongside the orphaned one — two whole-catalog scans grinding over the
  /// same rows and contending for the write lock, which is the low-end-device
  /// overload this whole effort exists to remove. [ensureMigrations] was
  /// already globally shared through its own future; nothing else was.
  ///
  /// Re-entrant. A job that is already holding the gate runs nested work
  /// inline instead of queueing behind a slot it owns, which would deadlock —
  /// and nesting is easy to reach without noticing, since a coarse caller
  /// (the settings refresh) legitimately contains finer-grained gated
  /// operations (catalog deletion). Callers re-check their own preconditions
  /// inside, so a second pipeline for work the first already finished costs a
  /// couple of indexed reads instead of a duplicate scan.
  static Future<T> runExclusive<T>(Future<T> Function() job) {
    if (Zone.current[#iptvCatalogMaintenance] == true) return job();
    final result = _maintenanceQueue.then((_) {
      debugMaintenanceRunCount++;
      return runZoned(job, zoneValues: {#iptvCatalogMaintenance: true});
    });
    // The queue must survive a failed job, and must not carry its error into
    // the next one.
    _maintenanceQueue = result.then((_) {}, onError: (_) {});
    return result;
  }

  /// Returns true when this call actually applied an upgrade — the caller uses
  /// that to refresh rows it may have already rendered unnumbered.
  static Future<bool> ensureMigrations() async {
    await open();
    if (_schemaVersionOf(_requireDb()) >= _schemaVersion) return false;
    // Counted where the run is actually created, so concurrent callers that
    // share one migration are one run, not several.
    if (_migrating == null) debugMigrationRunCount++;
    await (_migrating ??=
        compute(
          _migrateCatalogDb,
          path,
          debugLabel: 'iptv-catalog-db-migrate',
        ).whenComplete(() => _migrating = null));
    return true;
  }

  /// The applied-migration level. Deliberately `PRAGMA user_version` and not
  /// the `meta` row: it lives in the database header (no table read), and it
  /// is transactional, which is what makes the migration atomic.
  static int _schemaVersionOf(Database db) {
    final rows = db.select('PRAGMA user_version');
    if (rows.isEmpty) return 0;
    return (rows.first.values.first as int?) ?? 0;
  }

  /// Runs every migration the database has not applied yet. Safe to call on
  /// any connection (UI, prepare worker, ingest worker) — a database already
  /// at [_schemaVersion] returns after one header read.
  static int _runPendingMigrations(Database db) {
    final current = _schemaVersionOf(db);
    if (current >= _schemaVersion) return current;

    // The column may already be there (prepared by this build, or a v2
    // database whose stamp predates version gating); all that matters is that
    // the backfill below can write to it.
    for (final sql in _columnMigrationSql) {
      try {
        db.execute(sql);
      } catch (_) {}
    }

    db.execute('BEGIN IMMEDIATE');
    try {
      db.execute(_numberBackfillSql);
      db.execute(_numberIndexSql);
      db.execute('PRAGMA user_version = $_schemaVersion');
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
    return _schemaVersion;
  }

  static Future<void> _open() async {
    final dir =
        debugDirectoryOverride ??
        (await getApplicationDocumentsDirectory()).path;
    final path = p.join(dir, _dbFileName);

    final prepared = await compute(
      _prepareCatalogDb,
      path,
      debugLabel: 'iptv-catalog-db-init',
    );
    debugPreparationCount++;
    debugLastPreparationIsolateName = prepared.isolateName;

    // Another caller may have completed while this isolate job was queued.
    if (_db != null) {
      await compute(_closeTransferredCatalogDb, prepared.handleAddress);
      return;
    }

    // Wrapping an existing FULLMUTEX handle is pure Dart allocation: no
    // sqlite3_open_v2, filesystem access, WAL negotiation or schema SQL runs
    // on Flutter's isolate. This wrapper takes sole ownership and closes the
    // native handle from debugClose / its finalizer.
    try {
      _db = sqlite3.fromPointer(
        Pointer<Void>.fromAddress(prepared.handleAddress),
      );
      _path = path;
    } catch (_) {
      await compute(_closeTransferredCatalogDb, prepared.handleAddress);
      rethrow;
    }
  }

  @visibleForTesting
  static void debugClose() {
    _db?.dispose();
    _db = null;
    _path = null;
    _opening = null;
    _migrating = null;
    debugLastPreparationIsolateName = null;
    debugPreparationCount = 0;
    debugMigrationRunCount = 0;
    debugMaintenanceRunCount = 0;
    _maintenanceQueue = Future<void>.value();
  }

  /// Shared connection setup — reader (UI) and writer (worker) sides must
  /// agree on WAL and busy behavior or one of them fails under contention.
  static Database _openConnection(String path) {
    final db = sqlite3.open(path);
    for (final sql in _connectionSetupSql) {
      db.execute(sql);
    }
    return db;
  }

  static void _createSchema(Database db) {
    // Defensive cleanup: a DEVELOPMENT build (never a release — the FTS
    // experiment was reverted before any tag) created an FTS5 `channels_fts`
    // index plus these triggers, and it crashed on devices whose bundled
    // SQLite lacks the trigram tokenizer. Drop any leftovers so their triggers
    // can't fire on ingest and break catalog writes. Wrapped so a missing or
    // corrupt object can never abort schema setup; a clean database no-ops
    // through it. Removable once every development install has opened a build
    // containing this cleanup.
    for (final sql in _defensiveCleanupSql) {
      try {
        db.execute(sql);
      } catch (_) {}
    }
    for (final sql in _schemaSql) {
      db.execute(sql);
    }
    for (final sql in _columnMigrationSql) {
      try {
        db.execute(sql);
      } catch (_) {
        // See the native preparation path above: duplicate-column is the
        // expected result after the first successful v2 migration.
      }
    }
    // Deliberately NOT _runPendingMigrations: this runs before EVERY ingest,
    // and an ordinary background refresh has no business carrying a one-time
    // upgrade of unrelated catalogs. Schema shape is all ingest needs; the
    // backfill is [ensureMigrations]' job, once, on its own worker.
  }

  // ── Ingest (worker isolate) ──────────────────────────────────────────────

  /// Replaces the catalog stored under [catalogKey] with [channels],
  /// atomically. Returns the content digest of what was written.
  ///
  /// Called from the PARSE WORKER isolate with the [dbPath] handed over in
  /// the job — this opens its own connection and never touches [_db].
  ///
  /// [categories] is the provider's own category list — the chips today show
  /// it verbatim (its order, including categories no channel references), so
  /// it can't be derived from the channel rows and is stored alongside them.
  /// The [epgUrl] is the playlist-declared XMLTV url (M3U only).
  static String ingest({
    required String dbPath,
    required String catalogKey,
    required List<IptvChannel> channels,
    List<String> categories = const [],
    String? epgUrl,
    String? numberingSourceKey,
  }) {
    final digest = contentDigest(channels);
    final db = _openConnection(dbPath);
    try {
      // Idempotent; covers the first-ever ingest racing ahead of the UI-side
      // open().
      _createSchema(db);
      final insert = db.prepare('''
        INSERT INTO channels(
          catalog_key, generation, position, name, url, logo_url, grp,
          duration, content_type, attributes_json, http_headers_json,
          search_key, channel_number
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''');
      // IMMEDIATE takes the write lock up front, which is what makes the
      // generation allocation below safe: two overlapping ingests of the
      // SAME key (a revalidate racing a fresh load) serialize here instead
      // of both reading the same current generation and interleaving two
      // row-sets under one generation number. The second writer blocks
      // (busy_timeout) until the first commits, then correctly reads the
      // bumped generation.
      db.execute('BEGIN IMMEDIATE');
      try {
        final generation = _nextGeneration(db, catalogKey);
        final channelNumbers = numberingSourceKey == null
            ? const <int, int>{}
            : _assignChannelNumbers(
                db,
                sourceKey: numberingSourceKey,
                channels: channels,
              );
        for (var i = 0; i < channels.length; i++) {
          final c = channels[i];
          insert.execute([
            catalogKey,
            generation,
            i,
            c.name,
            c.url,
            c.logoUrl,
            c.group,
            c.duration,
            c.contentType,
            c.attributes.isEmpty ? null : jsonEncode(c.attributes),
            c.httpHeaders.isEmpty ? null : jsonEncode(c.httpHeaders),
            // Same haystack IptvChannel.searchKey builds — search behavior
            // must not change when the query moves into SQL.
            '${c.name.toLowerCase()}\n${c.group?.toLowerCase() ?? ''}',
            channelNumbers[i],
          ]);
        }
        db.execute(
          'INSERT OR REPLACE INTO catalogs'
          '(catalog_key, generation, channel_count, content_digest, '
          'categories_json, epg_url, ingested_at) '
          'VALUES (?, ?, ?, ?, ?, ?, ?)',
          [
            catalogKey,
            generation,
            channels.length,
            digest,
            categories.isEmpty ? null : jsonEncode(categories),
            epgUrl,
            DateTime.now().millisecondsSinceEpoch,
          ],
        );
        // Keep ONE previous generation alive: the UI holds a CatalogSnapshot
        // pinned to it while this refresh commits, and sweeping it here would
        // blank the rows on screen mid-scroll. The view re-pins to the new
        // generation right after every refresh, so by the time a THIRD
        // generation lands nobody can still be reading the first.
        db.execute(
          'DELETE FROM channels WHERE catalog_key = ? AND generation < ?',
          [catalogKey, generation - 1],
        );
        db.execute('COMMIT');
      } catch (_) {
        db.execute('ROLLBACK');
        rethrow;
      } finally {
        insert.dispose();
      }
      return digest;
    } finally {
      db.dispose();
    }
  }

  /// Order-sensitive digest of a channel list. The revalidate path compares
  /// the fresh ingest's digest with the served snapshot's to decide between
  /// "Up to date" (no UI swap at all) and a real refresh — replacing the old
  /// object-identity reconcile, which has no meaning once rows live in SQL.
  static String contentDigest(List<IptvChannel> channels) {
    // FNV-1a over the identity-bearing fields. Not cryptographic — it only
    // gates a cosmetic "did anything change" decision.
    var h1 = 0x811c9dc5;
    void mix(String s) {
      for (var i = 0; i < s.length; i++) {
        h1 = 0x01000193 * (h1 ^ s.codeUnitAt(i)) & 0xFFFFFFFF;
      }
      h1 = 0x01000193 * (h1 ^ 0x1f) & 0xFFFFFFFF;
    }

    for (final c in channels) {
      mix(c.name);
      mix(c.url);
      mix(c.logoUrl ?? '');
      mix(c.group ?? '');
      mix('${c.duration ?? ''}');
      mix(c.contentType ?? '');
      if (c.attributes.isNotEmpty) mix(jsonEncode(c.attributes));
      if (c.httpHeaders.isNotEmpty) mix(jsonEncode(c.httpHeaders));
    }
    return '${channels.length}:${h1.toRadixString(16)}';
  }

  static int _nextGeneration(Database db, String catalogKey) {
    final rows = db.select(
      'SELECT generation FROM catalogs WHERE catalog_key = ?',
      [catalogKey],
    );
    if (rows.isEmpty) return 1;
    return (rows.first['generation'] as int) + 1;
  }

  /// Assigns live channels a stable number within one provider namespace.
  ///
  /// Identity preference is tvg-id, then normalized name+group. Duplicate
  /// identities receive a deterministic occurrence suffix. Removed channels
  /// keep their assignment as a tombstone, so refreshes never renumber the
  /// surviving lineup and newly added channels always append.
  static Map<int, int> _assignChannelNumbers(
    Database db, {
    required String sourceKey,
    required List<IptvChannel> channels,
  }) {
    final identities = <int, String>{};
    final occurrences = <String, int>{};
    for (var i = 0; i < channels.length; i++) {
      final channel = channels[i];
      if (!channel.isLive) continue;
      identities[i] = _numberIdentity(
        tvgId: channel.tvgId,
        name: channel.name,
        group: channel.group,
        occurrences: occurrences,
      );
    }
    return _commitNumberAssignments(
      db,
      sourceKey: sourceKey,
      identities: identities,
    );
  }

  /// The identity a live row is numbered under: tvg-id when it has one, else
  /// normalized name+group, plus a deterministic occurrence suffix so two rows
  /// that look identical still receive distinct numbers.
  ///
  /// [occurrences] is the running per-base tally for ONE ordered pass and is
  /// mutated here — callers must walk rows in catalog order sharing a single
  /// map, or duplicate channels drift between passes.
  ///
  /// Shared verbatim by the ingest path and [adoptNumberingFromCatalog]: both
  /// must derive the same identity from the same channel, or adopting a stored
  /// catalog locally would hand out different numbers than the next provider
  /// refresh does.
  static String _numberIdentity({
    required String? tvgId,
    required String name,
    required String? group,
    required Map<String, int> occurrences,
  }) {
    final id = tvgId?.trim();
    final base = id != null && id.isNotEmpty
        ? 'tvg:${_normalizeNumberIdentity(id)}'
        : 'name:${_normalizeNumberIdentity(name)}'
              '\u001fgroup:${_normalizeNumberIdentity(group ?? '')}';
    final occurrence = (occurrences[base] ?? 0) + 1;
    occurrences[base] = occurrence;
    return '$base\u001f$occurrence';
  }

  /// Resolves the provider's namespace and turns an ordered identity map into
  /// durable numbers: identities already on record keep the number they hold,
  /// new ones append. Keyed by whatever the caller keyed [identities] by —
  /// channel index for ingest, row id for adoption.
  static Map<K, int> _commitNumberAssignments<K>(
    Database db, {
    required String sourceKey,
    required Map<K, String> identities,
  }) {
    if (identities.isEmpty) return const {};
    final now = DateTime.now().millisecondsSinceEpoch;

    String namespaceId;
    final alias = db.select(
      'SELECT namespace_id FROM channel_number_aliases WHERE source_key = ?',
      [sourceKey],
    );
    if (alias.isNotEmpty) {
      namespaceId = alias.first['namespace_id'] as String;
    } else {
      namespaceId =
          _archivedNamespaceMatch(db, identities.values.toSet()) ??
          'source:$sourceKey:$now';
    }

    db.execute(
      'INSERT OR IGNORE INTO channel_number_namespaces('
      'namespace_id, active_source_key, last_channel_count, max_number, '
      'updated_at) VALUES (?, ?, 0, 0, ?)',
      [namespaceId, sourceKey, now],
    );
    db.execute(
      'INSERT INTO channel_number_aliases('
      'source_key, namespace_id, is_active, updated_at) VALUES (?, ?, 1, ?) '
      'ON CONFLICT(source_key) DO UPDATE SET '
      'namespace_id = excluded.namespace_id, is_active = 1, '
      'updated_at = excluded.updated_at',
      [sourceKey, namespaceId, now],
    );

    final existingRows = db.select(
      'SELECT identity_key, channel_number FROM channel_number_assignments '
      'WHERE namespace_id = ?',
      [namespaceId],
    );
    final existing = <String, int>{
      for (final row in existingRows)
        row['identity_key'] as String: row['channel_number'] as int,
    };
    final namespaceRows = db.select(
      'SELECT max_number FROM channel_number_namespaces '
      'WHERE namespace_id = ?',
      [namespaceId],
    );
    var nextNumber = namespaceRows.isEmpty
        ? 0
        : namespaceRows.first['max_number'] as int;
    final upsert = db.prepare(
      'INSERT INTO channel_number_assignments('
      'namespace_id, identity_key, channel_number, last_seen) '
      'VALUES (?, ?, ?, ?) '
      'ON CONFLICT(namespace_id, identity_key) DO UPDATE SET '
      'last_seen = excluded.last_seen',
    );
    final result = <K, int>{};
    try {
      for (final entry in identities.entries) {
        final number = existing[entry.value] ?? ++nextNumber;
        result[entry.key] = number;
        upsert.execute([namespaceId, entry.value, number, now]);
      }
    } finally {
      upsert.dispose();
    }
    db.execute(
      'UPDATE channel_number_namespaces SET active_source_key = ?, '
      'last_channel_count = ?, max_number = ?, updated_at = ? '
      'WHERE namespace_id = ?',
      [sourceKey, identities.length, nextNumber, now, namespaceId],
    );
    return result;
  }

  /// Rows read per pass by [adoptNumberingFromCatalog]. Big enough that a 50k
  /// catalog is ten queries, small enough that no pass materializes a
  /// meaningful slice of the catalog.
  static const _adoptionChunkSize = 5000;

  /// Gives an ALREADY-STORED catalog a durable numbering namespace, built from
  /// the rows in this database — no network, no provider fetch.
  ///
  /// This is what a catalog ingested before channel numbering existed needs.
  /// The alternative it replaces was to refetch the entire provider catalog
  /// purely to establish the alias: for a 50k-channel panel that meant a full
  /// download and decode, 50k channel objects, a second 50k-row generation
  /// held alongside the first, and a pile of WAL — repeated on every visit
  /// until one refresh finally succeeded. Every input it needed was already
  /// on disk.
  ///
  /// Walks the live rows of the served generation in catalog order, in
  /// [_adoptionChunkSize] chunks, deriving each row's identity with the same
  /// [_numberIdentity] the ingest path uses — so the numbers this hands out
  /// are the numbers the next real refresh will confirm, not a placeholder set
  /// that shifts under the user later.
  ///
  /// Memory, precisely — this is bounded, not constant. No catalog ROWS are
  /// held: a chunk is dropped once read, and nothing here builds an
  /// [IptvChannel]. The derived identity strings ARE held, because an ordered
  /// identity map is what numbering needs and the occurrence tally has to span
  /// the whole pass or duplicate channels would renumber. So it scales with
  /// channel count, at a small fraction of the ~50k live channel objects the
  /// provider refresh this replaces had to materialize.
  /// iptv_catalog_db_test.dart measures the resident-set cost of a 50k pass
  /// rather than trusting that description.
  ///
  /// One transaction: assignments, the alias and the row numbers commit
  /// together or not at all, so an interrupted run leaves the catalog exactly
  /// as unadopted as it was and the next open simply retries.
  ///
  /// Returns how many rows had their stored number corrected — 0 means the
  /// provisional numbers were already right and the UI needs no rebuild.
  /// Called on a WORKER isolate (see [_adoptNumberingJob]).
  static int adoptNumberingFromCatalog(
    Database db, {
    required String catalogKey,
    required String sourceKey,
  }) {
    final catalogRows = db.select(
      'SELECT generation FROM catalogs WHERE catalog_key = ?',
      [catalogKey],
    );
    if (catalogRows.isEmpty) return 0;
    final generation = catalogRows.first['generation'] as int;

    // Read phase, deliberately OUTSIDE any transaction. This is the long part
    // (every live row, two unicode normalizations each), and holding the write
    // lock across it would make anything else that writes wait on it — the UI
    // isolate's own metadata writes among them, which block synchronously up
    // to busy_timeout. WAL gives consistent reads here without a lock.
    final identities = <int, String>{};
    final occurrences = <String, int>{};
    final page = db.prepare(
      'SELECT id, name, grp, attributes_json '
      'FROM channels WHERE catalog_key = ? AND generation = ? '
      'AND $_liveSql ORDER BY position LIMIT ? OFFSET ?',
    );
    try {
      for (var offset = 0; ; offset += _adoptionChunkSize) {
        final rows = page.select([
          catalogKey,
          generation,
          _adoptionChunkSize,
          offset,
        ]);
        if (rows.isEmpty) break;
        for (final row in rows) {
          final id = row['id'] as int;
          identities[id] = _numberIdentity(
            tvgId: CatalogSnapshot._decodeStringMap(
              row['attributes_json'],
            )['tvg-id'],
            name: row['name'] as String,
            group: row['grp'] as String?,
            occurrences: occurrences,
          );
        }
        if (rows.length < _adoptionChunkSize) break;
      }
    } finally {
      page.dispose();
    }
    if (identities.isEmpty) return 0;

    db.execute('BEGIN IMMEDIATE');
    try {
      // An ingest may have committed a new generation while the read ran, in
      // which case these numbers describe rows that no longer exist. Drop the
      // whole attempt rather than write them; the next visit adopts the
      // generation that actually won.
      final current = db.select(
        'SELECT generation FROM catalogs WHERE catalog_key = ?',
        [catalogKey],
      );
      if (current.isEmpty || current.first['generation'] as int != generation) {
        db.execute('ROLLBACK');
        return 0;
      }

      final numbers = _commitNumberAssignments(
        db,
        sourceKey: sourceKey,
        identities: identities,
      );

      // Only rows whose stored number is actually wrong are rewritten, and the
      // WHERE clause decides that rather than a 50k-entry map of the numbers
      // read earlier. After the v2 backfill it is normally none of them: the
      // backfill numbers live rows in catalog order and so does this, so they
      // agree unless the namespace relinked to an archived provider.
      var corrected = 0;
      final update = db.prepare(
        'UPDATE channels SET channel_number = ? WHERE id = ? AND '
        '(channel_number IS NULL OR channel_number != ?)',
      );
      try {
        for (final entry in numbers.entries) {
          update.execute([entry.value, entry.key, entry.value]);
          corrected += db.updatedRows;
        }
      } finally {
        update.dispose();
      }
      db.execute('COMMIT');
      return corrected;
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  /// Relinks only to an explicitly archived provider and only when the
  /// lineups are overwhelmingly the same. Active providers are excluded so
  /// two reseller logins with identical catalogs remain independently
  /// numbered.
  static String? _archivedNamespaceMatch(
    Database db,
    Set<String> incomingIdentities,
  ) {
    db.execute(
      'CREATE TEMP TABLE IF NOT EXISTS incoming_channel_identities('
      'identity_key TEXT PRIMARY KEY)',
    );
    db.execute('DELETE FROM incoming_channel_identities');
    final insert = db.prepare(
      'INSERT OR IGNORE INTO incoming_channel_identities(identity_key) '
      'VALUES (?)',
    );
    try {
      for (final identity in incomingIdentities) {
        insert.execute([identity]);
      }
    } finally {
      insert.dispose();
    }
    final candidates = db.select('''
      SELECT a.namespace_id AS namespace_id,
             COUNT(*) AS overlap_count,
             n.last_channel_count AS previous_count
      FROM channel_number_assignments a
      JOIN incoming_channel_identities i
        ON i.identity_key = a.identity_key
      JOIN channel_number_namespaces n
        ON n.namespace_id = a.namespace_id
      WHERE NOT EXISTS (
        SELECT 1 FROM channel_number_aliases active
        WHERE active.namespace_id = a.namespace_id
          AND active.is_active = 1
      )
      GROUP BY a.namespace_id
      ORDER BY overlap_count DESC
      LIMIT 2
    ''');
    if (candidates.isEmpty) return null;
    final best = candidates.first;
    final overlap = best['overlap_count'] as int;
    final previous = best['previous_count'] as int;
    final incoming = incomingIdentities.length;
    final smaller = incoming < previous ? incoming : previous;
    final larger = incoming > previous ? incoming : previous;
    if (overlap < 20 ||
        smaller == 0 ||
        overlap / smaller < 0.85 ||
        overlap / larger < 0.70) {
      return null;
    }
    // If two archived lineups score equally, choosing one would make channel
    // restoration nondeterministic. Start a clean namespace instead.
    if (candidates.length > 1 &&
        candidates[1]['overlap_count'] as int == overlap) {
      return null;
    }
    return best['namespace_id'] as String;
  }

  static String _normalizeNumberIdentity(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  // ── Worker-side bulk readers ─────────────────────────────────────────────
  //
  // Whole-catalog scans (EPG filter sets, favorites reconcile) run on WORKER
  // isolates — walking the paging facade on the UI isolate would
  // saturate it for tens of seconds on a big playlist even with yields.
  // These open their own connection from [dbPath] and return plain sendable
  // data.

  /// Every live channel's display name + tvg attributes for the current
  /// generation of [catalogKey].
  static List<({String name, String? tvgId, String? tvgName})> liveTvgRows({
    required String dbPath,
    required String catalogKey,
  }) {
    final db = _openConnection(dbPath);
    try {
      final gen = db.select(
        'SELECT generation FROM catalogs WHERE catalog_key = ?',
        [catalogKey],
      );
      if (gen.isEmpty) return const [];
      final rows = db.select(
        'SELECT name, attributes_json FROM channels '
        'WHERE catalog_key = ? AND generation = ? AND $_liveSql',
        [catalogKey, gen.first['generation'] as int],
      );
      return [
        for (final row in rows)
          () {
            final attrs = CatalogSnapshot._decodeStringMap(
              row['attributes_json'],
            );
            return (
              name: row['name'] as String,
              tvgId: attrs['tvg-id'],
              tvgName: attrs['tvg-name'],
            );
          }(),
      ];
    } finally {
      db.dispose();
    }
  }

  /// Every channel URL in the current generation of [catalogKey], in
  /// catalog order.
  static List<String> catalogUrls({
    required String dbPath,
    required String catalogKey,
  }) {
    final db = _openConnection(dbPath);
    try {
      final gen = db.select(
        'SELECT generation FROM catalogs WHERE catalog_key = ?',
        [catalogKey],
      );
      if (gen.isEmpty) return const [];
      final rows = db.select(
        'SELECT url FROM channels '
        'WHERE catalog_key = ? AND generation = ? ORDER BY position',
        [catalogKey, gen.first['generation'] as int],
      );
      return [for (final row in rows) row['url'] as String];
    } finally {
      db.dispose();
    }
  }

  /// Mirrors [CatalogSnapshot._isLiveSql] for the static readers above.
  static const _liveSql =
      '(CASE WHEN content_type IS NOT NULL '
      "THEN content_type = 'live' "
      'ELSE (duration IS NULL OR duration = -1) END)';

  // ── EPG guide storage ────────────────────────────────────────────────────

  /// Replace the stored guide under [guideKey] with the parser's filtered
  /// index, atomically. Called from the PARSE ISOLATE (own connection via
  /// [dbPath]) — the index dies with the isolate instead of living on the UI
  /// heap. Rows are `[startMs, stopMs, title, desc]`, exactly the parser's
  /// output shape.
  ///
  /// Callers must not pass an empty [byId] — the "an empty parse never wipes
  /// a still-useful stale guide" rule lives in XmltvEpgSource, which simply
  /// skips this call then.
  static void ingestEpgGuide({
    required String dbPath,
    required String guideKey,
    required String epgUrl,
    required Map<String, List<List<Object?>>> byId,
    required Map<String, String> nameToId,
    required bool sawWanted,
    // Legacy-snapshot imports pass the FILE's fetch time so a stale file
    // doesn't buy itself a fresh TTL.
    int? fetchedAtMs,
  }) {
    final db = _openConnection(dbPath);
    try {
      _createSchema(db);
      final insert = db.prepare('''
        INSERT OR REPLACE INTO epg_programmes(
          guide_key, channel_id, start_ms, stop_ms, title, description
        ) VALUES (?, ?, ?, ?, ?, ?)
      ''');
      // IMMEDIATE for the same reason as the catalog ingest: overlapping
      // writers for one guide serialize cleanly (delete-all + insert makes
      // last-writer-wins correct once they can't interleave).
      db.execute('BEGIN IMMEDIATE');
      try {
        db.execute('DELETE FROM epg_programmes WHERE guide_key = ?', [
          guideKey,
        ]);
        for (final entry in byId.entries) {
          for (final row in entry.value) {
            insert.execute([
              guideKey,
              entry.key,
              row[0] as int,
              row[1] as int,
              row[2] as String,
              row[3] as String,
            ]);
          }
        }
        db.execute(
          'INSERT OR REPLACE INTO epg_guides'
          '(guide_key, epg_url, fetched_at, saw_wanted, channel_count, '
          'name_to_id_json) VALUES (?, ?, ?, ?, ?, ?)',
          [
            guideKey,
            epgUrl,
            fetchedAtMs ?? DateTime.now().millisecondsSinceEpoch,
            sawWanted ? 1 : 0,
            byId.length,
            nameToId.isEmpty ? null : jsonEncode(nameToId),
          ],
        );
        db.execute('COMMIT');
      } catch (_) {
        db.execute('ROLLBACK');
        rethrow;
      } finally {
        insert.dispose();
      }
    } finally {
      db.dispose();
    }
  }

  /// Negative-cache marker: the guide parsed but matched nothing, and no
  /// better data exists. Writes ONLY the metadata row (fetched_at gates the
  /// short empty-TTL) — never touches programme rows.
  static void markEpgGuideEmpty({
    required String guideKey,
    required String epgUrl,
    required bool sawWanted,
  }) {
    final db = _requireDb();
    db.execute(
      'INSERT OR REPLACE INTO epg_guides'
      '(guide_key, epg_url, fetched_at, saw_wanted, channel_count, '
      'name_to_id_json) VALUES (?, ?, ?, ?, 0, NULL)',
      [
        guideKey,
        epgUrl,
        DateTime.now().millisecondsSinceEpoch,
        sawWanted ? 1 : 0,
      ],
    );
  }

  /// Stored guide metadata, or null if this guide was never ingested.
  static EpgGuideInfo? epgGuideInfo(String guideKey) {
    final db = _requireDb();
    final rows = db.select(
      'SELECT fetched_at, saw_wanted, channel_count, name_to_id_json '
      'FROM epg_guides WHERE guide_key = ?',
      [guideKey],
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    final namesRaw = row['name_to_id_json'];
    final nameToId = <String, String>{};
    if (namesRaw is String && namesRaw.isNotEmpty) {
      try {
        final decoded = jsonDecode(namesRaw);
        if (decoded is Map) {
          decoded.forEach((k, v) => nameToId['$k'] = '$v');
        }
      } catch (_) {}
    }
    return EpgGuideInfo(
      fetchedAt: row['fetched_at'] as int,
      sawWanted: (row['saw_wanted'] as int) != 0,
      channelCount: row['channel_count'] as int,
      nameToId: nameToId,
    );
  }

  /// Programme rows for one guide channel, sorted — `[startMs, stopMs,
  /// title, desc]`, same shape the parser emits. Synchronous: called at
  /// row-paint time, and the (guide_key, channel_id, start_ms) PK makes it
  /// an index walk over at most ~80 rows.
  static List<List<Object?>> epgProgrammes(String guideKey, String channelId) {
    final db = _requireDb();
    final rows = db.select(
      'SELECT start_ms, stop_ms, title, description FROM epg_programmes '
      'WHERE guide_key = ? AND channel_id = ? ORDER BY start_ms',
      [guideKey, channelId],
    );
    return [
      for (final row in rows)
        [
          row['start_ms'] as int,
          row['stop_ms'] as int,
          row['title'] as String,
          row['description'] as String,
        ],
    ];
  }

  /// The tvg identity of the catalog row serving [url]: its display name and
  /// attributes (tvg-id / tvg-name). Used by the EPG service to bind a
  /// channel URL to guide data without holding a url→id map for the whole
  /// playlist. First match wins (duplicate URLs are legal in playlists).
  static ({String name, Map<String, String> attributes})? channelTvgIdentity({
    required String catalogKey,
    required String url,
  }) {
    final db = _db;
    if (db == null) return null;
    final gen = db.select(
      'SELECT generation FROM catalogs WHERE catalog_key = ?',
      [catalogKey],
    );
    if (gen.isEmpty) return null;
    final rows = db.select(
      'SELECT name, attributes_json FROM channels '
      'WHERE catalog_key = ? AND generation = ? AND url = ? '
      'ORDER BY position LIMIT 1',
      [catalogKey, gen.first['generation'] as int, url],
    );
    if (rows.isEmpty) return null;
    return (
      name: rows.first['name'] as String,
      attributes: CatalogSnapshot._decodeStringMap(
        rows.first['attributes_json'],
      ),
    );
  }

  // ── Maintenance (UI isolate) ─────────────────────────────────────────────

  /// Settings edit/delete paths call this alongside the in-memory
  /// cache invalidation; it opens the DB if this session hasn't yet (the
  /// user can delete a playlist without ever opening the IPTV page).
  /// Deletes catalogs on a WORKER, behind the maintenance gate.
  ///
  /// Deleting a provider means deleting its channel rows, and for a 50k-channel
  /// panel that is a mass delete — it froze the settings screen for as long as
  /// it took, because it ran synchronously on the UI isolate. It is also
  /// whole-catalog write work, so it queues with migration, adoption, ingest
  /// and refresh rather than racing whatever the IPTV page left running.
  static Future<void> removeCatalogsByKeys(Iterable<String> keys) async {
    final list = keys.toList(growable: false);
    if (list.isEmpty) return;
    await open();
    await runExclusive(() => compute(_removeCatalogsJob, [path, ...list]));
  }

  /// Marks a removed playlist's numbering namespace as eligible for a future
  /// conservative lineup match. Assignments are intentionally retained.
  static Future<void> archiveNumberingSource(String sourceKey) async {
    await open();
    final db = _requireDb();
    final now = DateTime.now().millisecondsSinceEpoch;
    db.execute(
      'UPDATE channel_number_aliases SET is_active = 0, updated_at = ? '
      'WHERE source_key = ?',
      [now, sourceKey],
    );
    db.execute(
      'UPDATE channel_number_namespaces SET active_source_key = NULL, '
      'updated_at = ? WHERE namespace_id IN ('
      'SELECT namespace_id FROM channel_number_aliases WHERE source_key = ?)',
      [now, sourceKey],
    );
    clearAdoptionFailure(sourceKey);
  }

  /// Whether this saved playlist has committed its durable identity mapping.
  /// How long a failed adoption is left alone. A failure is almost always
  /// environmental (no disk, a locked database); retrying it on every single
  /// visit would burn a whole-catalog pass each time for the same result.
  static const _adoptionRetryBackoff = Duration(hours: 6);

  static String _adoptionFailureKey(String sourceKey) =>
      'numbering_adopt_failed:$sourceKey';

  /// True when a recent adoption attempt for [sourceKey] failed and its
  /// backoff has not expired. Synchronous single-row read — cheap enough for
  /// the page-load path.
  static bool adoptionRecentlyFailed(String sourceKey) {
    final rows = _requireDb().select(
      'SELECT value FROM meta WHERE key = ?',
      [_adoptionFailureKey(sourceKey)],
    );
    if (rows.isEmpty) return false;
    final at = int.tryParse(rows.first['value'] as String);
    if (at == null) return false;
    final age = DateTime.now().millisecondsSinceEpoch - at;
    return age < _adoptionRetryBackoff.inMilliseconds;
  }

  /// Builds [sourceKey]'s numbering namespace from the stored rows of
  /// [catalogKey], on a worker isolate. See [adoptNumberingFromCatalog].
  ///
  /// Returns the number of rows whose stored number changed, so the caller
  /// knows whether the visible list needs rebuilding. Failures are recorded
  /// for [adoptionRecentlyFailed] and rethrown.
  static Future<int> adoptNumbering({
    required String catalogKey,
    required String sourceKey,
  }) async {
    await open();
    try {
      final corrected = await compute(_adoptNumberingJob, [
        path,
        catalogKey,
        sourceKey,
      ], debugLabel: 'iptv-catalog-adopt-numbering');
      clearAdoptionFailure(sourceKey);
      return corrected;
    } catch (_) {
      // Bookkeeping must never replace the failure it is recording: if the
      // database is unusable enough to fail the adoption, this write can fail
      // too, and throwing from a catch block would swallow the real cause.
      try {
        _requireDb().execute(
          'INSERT OR REPLACE INTO meta(key, value) VALUES (?, ?)',
          [
            _adoptionFailureKey(sourceKey),
            '${DateTime.now().millisecondsSinceEpoch}',
          ],
        );
      } catch (_) {}
      rethrow;
    }
  }

  /// How long an interrupted catalog refresh suppresses the next automatic
  /// one. Long enough that a device which dies mid-refresh gets working page
  /// opens instead of retrying the job that killed it; short enough that a
  /// genuinely stale catalog still catches up on its own.
  static const _revalidateRetryBackoff = Duration(hours: 6);

  static String _revalidateStartedKey(String catalogKey) =>
      'catalog_revalidate_started:$catalogKey';

  /// Records that an automatic refresh of [catalogKey] is starting.
  ///
  /// Paired with [markRevalidateFinished], which the refresh calls on EVERY
  /// outcome it can observe — success, failure, or being superseded. A marker
  /// therefore survives exactly one situation: the process died mid-refresh.
  /// That is the signal [revalidateInterrupted] reads.
  static void markRevalidateStarted(String catalogKey) {
    _requireDb().execute(
      'INSERT OR REPLACE INTO meta(key, value) VALUES (?, ?)',
      [
        _revalidateStartedKey(catalogKey),
        '${DateTime.now().millisecondsSinceEpoch}',
      ],
    );
  }

  static void markRevalidateFinished(String catalogKey) {
    _requireDb().execute('DELETE FROM meta WHERE key = ?', [
      _revalidateStartedKey(catalogKey),
    ]);
  }

  /// True when the last automatic refresh of [catalogKey] never finished and
  /// its backoff has not expired.
  ///
  /// This is the crash-loop breaker. Refreshing a 50k-channel catalog is the
  /// heaviest thing the page does — a full download, decode and ingest — and
  /// a device that cannot survive it would otherwise be handed the same job on
  /// every single visit, because a stale catalog stays stale until a refresh
  /// completes. Backing off leaves the saved catalog on screen and working,
  /// with the refresh chip still there for anyone who wants to force it.
  static bool revalidateInterrupted(String catalogKey) {
    final rows = _requireDb().select(
      'SELECT value FROM meta WHERE key = ?',
      [_revalidateStartedKey(catalogKey)],
    );
    if (rows.isEmpty) return false;
    final at = int.tryParse(rows.first['value'] as String);
    if (at == null) return false;
    final age = DateTime.now().millisecondsSinceEpoch - at;
    return age < _revalidateRetryBackoff.inMilliseconds;
  }

  /// Drops any recorded adoption failure for [sourceKey], so the next visit
  /// retries immediately. Called on success and when a provider is archived —
  /// a playlist that was deleted and re-added must not inherit the backoff of
  /// the entry it replaced.
  static void clearAdoptionFailure(String sourceKey) {
    _requireDb().execute('DELETE FROM meta WHERE key = ?', [
      _adoptionFailureKey(sourceKey),
    ]);
  }

  /// Whether [sourceKey] already owns a durable numbering namespace.
  ///
  /// Existing v1 catalog rows receive provisional position-based numbers
  /// during migration; this distinguishes those from a fully persistent v2
  /// assignment, so the view knows to adopt one in the background.
  static bool hasNumberingSource(String sourceKey) {
    final db = _requireDb();
    return db.select(
      'SELECT 1 FROM channel_number_aliases WHERE source_key = ? LIMIT 1',
      [sourceKey],
    ).isNotEmpty;
  }

  /// Drops the stored catalogs for [keys] (settings edit/delete paths — the
  /// same call sites that invalidate the services' in-memory caches).
  /// Synchronous deletion against the caller's own connection. Worker-side
  /// entry point for [removeCatalogsByKeys]; UI callers must use that instead,
  /// so a 50k-row delete never lands on this isolate.
  static void removeCatalogsOn(Database db, Iterable<String> keys) {
    db.execute('BEGIN');
    try {
      for (final key in keys) {
        db.execute('DELETE FROM channels WHERE catalog_key = ?', [key]);
        db.execute('DELETE FROM catalogs WHERE catalog_key = ?', [key]);
        // The catalog's bookkeeping goes with it. Narrow but real: a delete
        // and re-add inside the backoff window would otherwise inherit the old
        // entry's suppressed refresh.
        db.execute('DELETE FROM meta WHERE key = ?', [
          _revalidateStartedKey(key),
        ]);
      }
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  // ── Reads (UI isolate, synchronous) ──────────────────────────────────────

  static Database _requireDb() {
    final db = _db;
    if (db == null) {
      throw StateError('IptvCatalogDb.open() must complete before reads');
    }
    return db;
  }

  /// The committed catalog snapshot for [catalogKey], or null if never
  /// ingested. All page/count/group reads go through the snapshot so they're
  /// pinned to one generation even if a background refresh commits
  /// mid-scroll.
  static CatalogSnapshot? snapshot(String catalogKey) {
    final db = _requireDb();
    final rows = db.select(
      'SELECT generation, channel_count, content_digest, categories_json, '
      'epg_url, ingested_at FROM catalogs WHERE catalog_key = ?',
      [catalogKey],
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    return CatalogSnapshot._(
      db: db,
      catalogKey: catalogKey,
      generation: row['generation'] as int,
      channelCount: row['channel_count'] as int,
      contentDigest: row['content_digest'] as String,
      categories: _decodeStringList(row['categories_json']),
      epgUrl: row['epg_url'] as String?,
      ingestedAt: row['ingested_at'] as int,
    );
  }

  static List<String> _decodeStringList(Object? json) {
    if (json is! String || json.isEmpty) return const [];
    try {
      final decoded = jsonDecode(json);
      if (decoded is List) return [for (final e in decoded) e.toString()];
    } catch (_) {}
    return const [];
  }
}

/// A read view pinned to one committed generation of one catalog.
///
/// Holding a snapshot does NOT hold memory or locks — it's just the
/// generation number; every call is a fresh sub-millisecond query. After a
/// refresh replaces this generation, [isStale] flips and reads return empty;
/// the view re-snapshots and treats it as "refresh arrived".
class CatalogSnapshot {
  CatalogSnapshot._({
    required Database db,
    required this.catalogKey,
    required this.generation,
    required this.channelCount,
    required this.contentDigest,
    required this.categories,
    required this.epgUrl,
    required this.ingestedAt,
  }) : _db = db;

  final Database _db;
  final String catalogKey;
  final int generation;
  final int channelCount;
  final String contentDigest;

  /// The provider's category list, verbatim — what the chips render today.
  final List<String> categories;

  final String? epgUrl;
  final int ingestedAt;

  /// True when a newer generation has been committed for this catalog.
  bool get isStale {
    final rows = _db.select(
      'SELECT generation FROM catalogs WHERE catalog_key = ?',
      [catalogKey],
    );
    return rows.isEmpty || (rows.first['generation'] as int) != generation;
  }

  static const _base = 'FROM channels WHERE catalog_key = ? AND generation = ?';

  /// Exactly IptvChannel.isLive in SQL: an explicit content type decides;
  /// otherwise the M3U duration heuristic (-1 or absent = live).
  static const _isLiveSql =
      '(CASE WHEN content_type IS NOT NULL '
      "THEN content_type = 'live' "
      'ELSE (duration IS NULL OR duration = -1) END)';

  List<Object?> _args({String? group, String? search, int? beforePosition}) => [
    catalogKey,
    generation,
    if (group != null) group,
    if (search != null && search.isNotEmpty)
      '%${_escapeLike(search.toLowerCase())}%',
    if (beforePosition != null) beforePosition,
  ];

  String _where({
    String? group,
    String? search,
    bool? live,
    int? beforePosition,
  }) {
    final buf = StringBuffer(_base);
    if (group != null) buf.write(' AND grp = ?');
    if (search != null && search.isNotEmpty) {
      buf.write(" AND search_key LIKE ? ESCAPE '\\'");
    }
    if (live != null) {
      buf.write(live ? ' AND $_isLiveSql' : ' AND NOT $_isLiveSql');
    }
    if (beforePosition != null) buf.write(' AND position < ?');
    return buf.toString();
  }

  /// LIKE special characters in user input must match literally — searching
  /// for "100%" should not match everything.
  static String _escapeLike(String term) => term
      .replaceAll(r'\', r'\\')
      .replaceAll('%', r'\%')
      .replaceAll('_', r'\_');

  int count({String? group, String? search, bool? live, int? beforePosition}) {
    final rows = _db.select(
      'SELECT COUNT(*) AS c ${_where(group: group, search: search, live: live, beforePosition: beforePosition)}',
      _args(group: group, search: search, beforePosition: beforePosition),
    );
    return rows.first['c'] as int;
  }

  /// Whether this generation contains at least one live channel.
  ///
  /// This avoids treating VOD-only catalogs as missing a durable live-channel
  /// numbering assignment and repeatedly revalidating them on every visit.
  bool get hasLiveChannels {
    return _db
        .select(
          'SELECT 1 $_base AND $_isLiveSql LIMIT 1',
          [catalogKey, generation],
        )
        .isNotEmpty;
  }

  /// Catalog position of the row matching url+name, or null. (Duplicate
  /// url+name pairs are legal in playlists — the first occurrence answers,
  /// which is where zapping should land anyway.)
  int? positionOf({
    required String url,
    required String name,
    String? group,
    bool? live,
  }) {
    final rows = _db.select(
      'SELECT position ${_where(group: group, live: live)} '
      'AND url = ? AND name = ? '
      'ORDER BY position LIMIT 1',
      [..._args(group: group), url, name],
    );
    return rows.isEmpty ? null : rows.first['position'] as int;
  }

  /// Catalog position of an assigned live-channel number.
  int? positionOfChannelNumber(int channelNumber) {
    final rows = _db.select(
      'SELECT position $_base AND channel_number = ? '
      'ORDER BY position LIMIT 1',
      [catalogKey, generation, channelNumber],
    );
    return rows.isEmpty ? null : rows.first['position'] as int;
  }

  /// Assigned channel and catalog position, used by native-player numeric
  /// tuning without scanning or materializing the provider catalog.
  ({int position, IptvChannel channel})? entryForChannelNumber(
    int channelNumber,
  ) {
    final rows = _db.select(
      'SELECT * $_base AND channel_number = ? '
      'ORDER BY position LIMIT 1',
      [catalogKey, generation, channelNumber],
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    return (position: row['position'] as int, channel: _channelFromRow(row));
  }

  /// One page of channels in catalog order, filtered like [count]. This is
  /// the ONLY place rows materialize into [IptvChannel]s — a page at a time,
  /// not 55k.
  List<IptvChannel> page({
    required int offset,
    required int limit,
    String? group,
    String? search,
    bool? live,
  }) {
    return [
      for (final e in pageEntries(
        offset: offset,
        limit: limit,
        group: group,
        search: search,
        live: live,
      ))
        e.channel,
    ];
  }

  /// Like [page] but pairs each row with its catalog position. The paging
  /// facade keys its instance cache on that position — it's unique within a
  /// generation, so re-faulting the same catalog row across filter
  /// recomputes returns the SAME [IptvChannel] instance (stable ObjectKeys →
  /// no row rebuild), and two duplicate-URL rows still get distinct instances
  /// (distinct positions), never a shared focus node.
  List<({int position, IptvChannel channel})> pageEntries({
    required int offset,
    required int limit,
    String? group,
    String? search,
    bool? live,
  }) {
    final rows = _db.select(
      'SELECT * ${_where(group: group, search: search, live: live)} '
      'ORDER BY position LIMIT ? OFFSET ?',
      [..._args(group: group, search: search), limit, offset],
    );
    return [
      for (final row in rows)
        (position: row['position'] as int, channel: _channelFromRow(row)),
    ];
  }

  /// Distinct groups with counts, in first-appearance (catalog) order — the
  /// order the category chips show today. Channels without a group come back
  /// as a null-named entry.
  List<CatalogGroup> groups() {
    final rows = _db.select(
      'SELECT grp, COUNT(*) AS c, MIN(position) AS first_pos $_base '
      'GROUP BY grp ORDER BY first_pos',
      [catalogKey, generation],
    );
    return [
      for (final row in rows)
        CatalogGroup(row['grp'] as String?, row['c'] as int),
    ];
  }

  static IptvChannel _channelFromRow(Row row) {
    return IptvChannel(
      channelNumber: row['channel_number'] as int?,
      name: row['name'] as String,
      url: row['url'] as String,
      logoUrl: row['logo_url'] as String?,
      group: row['grp'] as String?,
      duration: row['duration'] as int?,
      contentType: row['content_type'] as String?,
      attributes: _decodeStringMap(row['attributes_json']),
      httpHeaders: _decodeStringMap(row['http_headers_json']),
    );
  }

  static Map<String, String> _decodeStringMap(Object? json) {
    if (json is! String || json.isEmpty) return const {};
    try {
      final decoded = jsonDecode(json);
      if (decoded is Map) {
        return decoded.map((k, v) => MapEntry(k.toString(), v.toString()));
      }
    } catch (_) {}
    return const {};
  }
}

class CatalogGroup {
  const CatalogGroup(this.name, this.count);

  /// Null for channels that declared no group (M3U rows without group-title).
  final String? name;
  final int count;
}

class EpgGuideInfo {
  final int fetchedAt;
  final bool sawWanted;
  final int channelCount;
  final Map<String, String> nameToId;

  const EpgGuideInfo({
    required this.fetchedAt,
    required this.sawWanted,
    required this.channelCount,
    required this.nameToId,
  });
}
