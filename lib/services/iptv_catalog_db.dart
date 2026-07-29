import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import '../models/iptv_playlist.dart';

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
/// A catalog is identified by the SAME key string the legacy disk snapshot
/// cache used (`IptvCatalogCache.keyForPlaylist`: `xc|server|user|type` or
/// `m3u|url`) — so eligibility ("is this a cacheable catalog?") and
/// invalidation (settings edit/delete) keep their existing semantics
/// unchanged. Virtual playlists (favorites://, continue://, Stremio, local
/// files) have no key and stay materialized in memory, exactly as before.
///
/// Each ingest writes a NEW generation, flips the `catalogs` pointer and
/// deletes the old generation in ONE transaction — a reader either sees the
/// complete old catalog or the complete new one, never a mix, and a crash
/// mid-ingest leaves the old catalog untouched.
class IptvCatalogDb {
  IptvCatalogDb._();

  static const _dbFileName = 'iptv_catalog.db';
  // v2: added the `channels_fts` FTS5 index (+ sync triggers) so catalog
  // search is an index lookup instead of a `LIKE '%term%'` full scan on the
  // UI isolate. Bumping this triggers a one-time backfill in [open].
  static const _schemaVersion = 2;

  /// Tests point this at a temp directory; production resolves the app
  /// documents directory once in [open].
  @visibleForTesting
  static String? debugDirectoryOverride;

  static Database? _db;
  static String? _path;

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

  /// Opens (and on first run creates) the catalog database. Idempotent.
  /// Must complete on the UI isolate before any read; after that every read
  /// is synchronous.
  static Future<void> open() async {
    if (_db != null) return;
    final dir = debugDirectoryOverride ??
        (await getApplicationDocumentsDirectory()).path;
    final path = p.join(dir, _dbFileName);
    final db = _openConnection(path);
    // The on-disk version tells a fresh DB (null) from a pre-FTS one (v1).
    final priorVersion = _readSchemaVersion(db);
    _createSchema(db);
    if (priorVersion == null) {
      // Brand-new DB: schema is current, nothing to backfill.
      _writeSchemaVersion(db, _schemaVersion);
    } else if (priorVersion < 2) {
      // Pre-FTS catalog rows exist; the triggers only fire on future writes,
      // so the index must be backfilled once from the current rows. `rebuild`
      // trigram-tokenizes every stored row — potentially 100k+ across catalogs
      // and generations — so it runs on a WORKER isolate rather than freezing
      // the UI while the splash awaits open(). The version is stamped only
      // after it succeeds, so a failure is retried next launch.
      await compute(_rebuildFtsIndexJob, path);
      _writeSchemaVersion(db, _schemaVersion);
    }
    _db = db;
    _path = path;
  }

  /// The schema version recorded on disk, or null when the database is fresh
  /// (no `meta` table / no row yet). Read before [_createSchema] rewrites it.
  static int? _readSchemaVersion(Database db) {
    try {
      final rows = db.select(
        "SELECT value FROM meta WHERE key = 'schema_version'",
      );
      if (rows.isEmpty) return null;
      return int.tryParse(rows.first['value'] as String);
    } catch (_) {
      // meta table doesn't exist yet — brand-new database.
      return null;
    }
  }

  @visibleForTesting
  static void debugClose() {
    _db?.dispose();
    _db = null;
    _path = null;
  }

  /// Shared connection setup — reader (UI) and writer (worker) sides must
  /// agree on WAL and busy behavior or one of them fails under contention.
  static Database _openConnection(String path) {
    final db = sqlite3.open(path);
    db.execute('PRAGMA journal_mode=WAL');
    db.execute('PRAGMA synchronous=NORMAL');
    db.execute('PRAGMA busy_timeout=5000');
    return db;
  }

  static void _createSchema(Database db) {
    db.execute('''
      CREATE TABLE IF NOT EXISTS meta (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
    db.execute('''
      CREATE TABLE IF NOT EXISTS catalogs (
        catalog_key TEXT PRIMARY KEY,
        generation INTEGER NOT NULL,
        channel_count INTEGER NOT NULL,
        content_digest TEXT NOT NULL,
        categories_json TEXT,
        epg_url TEXT,
        ingested_at INTEGER NOT NULL
      )
    ''');
    db.execute('''
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
        search_key TEXT NOT NULL
      )
    ''');
    // Every read filters on (catalog_key, generation); position makes the
    // windowed page an index walk, grp serves the category chips.
    db.execute('''
      CREATE INDEX IF NOT EXISTS idx_channels_page
      ON channels(catalog_key, generation, position)
    ''');
    db.execute('''
      CREATE INDEX IF NOT EXISTS idx_channels_grp
      ON channels(catalog_key, generation, grp)
    ''');
    // The EPG binding lookup resolves a channel URL to its tvg identity at
    // row-paint time — it has to be an index walk.
    db.execute('''
      CREATE INDEX IF NOT EXISTS idx_channels_url
      ON channels(catalog_key, generation, url)
    ''');
    // Full-text search over the same haystack `search_key` holds (lowercased
    // name + group). External-content FTS5 keyed to `channels.id` — the index
    // only, no duplicated text. The `trigram` tokenizer is deliberate: it
    // makes a MATCH behave like the old `LIKE '%term%'` — a case-insensitive
    // SUBSTRING match, mid-word included — but served from the index instead
    // of a full catalog scan on the UI isolate (that scan was the "Search all"
    // freeze). Substrings under 3 chars can't use a trigram index and fall
    // back to a scan, but those are the rare early-keystroke queries. The
    // triggers keep the index in lockstep with the generation rewrites: every
    // row INSERT indexes it, every DELETE (the old-generation prune) de-indexes
    // it, so a MATCH plus the catalog_key+generation filter is always
    // scoped-correct. Rows are only inserted or deleted, never updated, so no
    // update trigger.
    db.execute('''
      CREATE VIRTUAL TABLE IF NOT EXISTS channels_fts USING fts5(
        search_key,
        content='channels',
        content_rowid='id',
        tokenize="trigram"
      )
    ''');
    db.execute('''
      CREATE TRIGGER IF NOT EXISTS channels_fts_ai AFTER INSERT ON channels BEGIN
        INSERT INTO channels_fts(rowid, search_key)
        VALUES (new.id, new.search_key);
      END
    ''');
    db.execute('''
      CREATE TRIGGER IF NOT EXISTS channels_fts_ad AFTER DELETE ON channels BEGIN
        INSERT INTO channels_fts(channels_fts, rowid, search_key)
        VALUES ('delete', old.id, old.search_key);
      END
    ''');
    // XMLTV guide storage (one guide per md5(epgUrl) key): programme rows
    // queried per (guide, channel) at row-paint time, plus one metadata row
    // holding freshness and the name→id resolutions the parser made.
    db.execute('''
      CREATE TABLE IF NOT EXISTS epg_programmes (
        guide_key TEXT NOT NULL,
        channel_id TEXT NOT NULL,
        start_ms INTEGER NOT NULL,
        stop_ms INTEGER NOT NULL,
        title TEXT NOT NULL,
        description TEXT NOT NULL DEFAULT '',
        PRIMARY KEY (guide_key, channel_id, start_ms)
      )
    ''');
    db.execute('''
      CREATE TABLE IF NOT EXISTS epg_guides (
        guide_key TEXT PRIMARY KEY,
        epg_url TEXT NOT NULL,
        fetched_at INTEGER NOT NULL,
        saw_wanted INTEGER NOT NULL DEFAULT 0,
        channel_count INTEGER NOT NULL DEFAULT 0,
        name_to_id_json TEXT
      )
    ''');
    // NB: schema_version is NOT stamped here — [open] writes it only AFTER any
    // one-time FTS backfill succeeds, so a failed/interrupted migration is
    // retried on the next launch instead of being marked done.
  }

  static void _writeSchemaVersion(Database db, int version) {
    db.execute(
      "INSERT OR REPLACE INTO meta(key, value) VALUES ('schema_version', ?)",
      ['$version'],
    );
  }

  /// Worker-isolate entry ([compute]): rebuilds the whole FTS index from the
  /// current channel rows. Only the one-time v1→v2 backfill uses it, off the
  /// UI isolate so trigram-tokenizing a six-figure row set never blocks a
  /// frame. Opens its own connection (handles can't cross isolates).
  static void _rebuildFtsIndexJob(String dbPath) {
    withConnection(dbPath, (db) {
      // The UI connection already created channels_fts before dispatching this;
      // recreate defensively (IF NOT EXISTS) in case of WAL visibility skew.
      _createSchema(db);
      db.execute("INSERT INTO channels_fts(channels_fts) VALUES('rebuild')");
    });
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
          search_key
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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

  // ── Worker-side bulk readers ─────────────────────────────────────────────
  //
  // Whole-catalog scans (EPG filter sets, favorites reconcile) run on WORKER
  // isolates in DB mode — walking the paging facade on the UI isolate would
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
            final attrs =
                CatalogSnapshot._decodeStringMap(row['attributes_json']);
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
  static const _liveSql = '(CASE WHEN content_type IS NOT NULL '
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
        db.execute(
          'DELETE FROM epg_programmes WHERE guide_key = ?',
          [guideKey],
        );
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
      attributes:
          CatalogSnapshot._decodeStringMap(rows.first['attributes_json']),
    );
  }

  // ── Maintenance (UI isolate) ─────────────────────────────────────────────

  /// Settings edit/delete paths call this alongside the legacy snapshot
  /// cache invalidation; it opens the DB if this session hasn't yet (the
  /// user can delete a playlist without ever opening the IPTV page).
  static Future<void> removeCatalogsByKeys(Iterable<String> keys) async {
    await open();
    removeCatalogs(keys);
  }

  /// Drops the stored catalogs for [keys] (settings edit/delete paths — the
  /// same call sites that invalidate the legacy snapshot cache).
  static void removeCatalogs(Iterable<String> keys) {
    final db = _requireDb();
    db.execute('BEGIN');
    try {
      for (final key in keys) {
        db.execute('DELETE FROM channels WHERE catalog_key = ?', [key]);
        db.execute('DELETE FROM catalogs WHERE catalog_key = ?', [key]);
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

  // ── Worker-side snapshot access ──────────────────────────────────────────
  //
  // A CatalogSnapshot binds to a live [Database], which can't cross isolates.
  // A worker (e.g. the global-search isolate) opens its OWN connection from
  // [path] via [withConnection] and pins snapshots to it with [snapshotOn].

  /// Runs [body] with a throwaway connection opened on [dbPath], disposing it
  /// afterward. For worker isolates that were handed [IptvCatalogDb.path].
  static T withConnection<T>(String dbPath, T Function(Database db) body) {
    final db = _openConnection(dbPath);
    try {
      return body(db);
    } finally {
      db.dispose();
    }
  }

  /// A snapshot pinned to an explicit (catalogKey, generation) on [db] — for
  /// worker-side readers whose caller already resolved the generation on the
  /// UI connection. Only the fields the read path uses are populated; catalog
  /// metadata (channelCount, categories, epg, …) is left at defaults because
  /// search/count/page never touch it.
  static CatalogSnapshot snapshotOn(
    Database db,
    String catalogKey,
    int generation,
  ) =>
      CatalogSnapshot._(
        db: db,
        catalogKey: catalogKey,
        generation: generation,
        channelCount: 0,
        contentDigest: '',
        categories: const [],
        epgUrl: null,
        ingestedAt: 0,
      );
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

  static const _base =
      'FROM channels WHERE catalog_key = ? AND generation = ?';

  /// Exactly IptvChannel.isLive in SQL: an explicit content type decides;
  /// otherwise the M3U duration heuristic (-1 or absent = live).
  static const _isLiveSql = '(CASE WHEN content_type IS NOT NULL '
      "THEN content_type = 'live' "
      'ELSE (duration IS NULL OR duration = -1) END)';

  List<Object?> _args({
    String? group,
    int? beforePosition,
  }) =>
      [
        catalogKey,
        generation,
        if (group != null) group,
        if (beforePosition != null) beforePosition,
      ];

  String _where({
    String? group,
    bool? live,
    int? beforePosition,
  }) {
    final buf = StringBuffer(_base);
    if (group != null) buf.write(' AND grp = ?');
    if (live != null) buf.write(live ? ' AND $_isLiveSql' : ' AND NOT $_isLiveSql');
    if (beforePosition != null) buf.write(' AND position < ?');
    return buf.toString();
  }

  /// LIKE special characters in user input must match literally — searching
  /// for "100%" should not match everything. Used by the short-substring LIKE
  /// fallback and the name-prefix "lead" bucket in [searchPage].
  static String _escapeLike(String term) => term
      .replaceAll(r'\', r'\\')
      .replaceAll('%', r'\%')
      .replaceAll('_', r'\_');

  /// Wraps text as a single FTS5 string literal (`"..."`, inner quotes
  /// doubled). Under the trigram tokenizer a quoted phrase matches as a
  /// contiguous, case-insensitive substring — exactly what `LIKE '%text%'`
  /// did — and the quoting keeps `%`, `_`, `*`, `-`, `:` etc. literal so a
  /// channel name can't be read as an FTS operator.
  static String _ftsLiteral(String text) =>
      '"${text.toLowerCase().replaceAll('"', '""')}"';

  /// Trigram indexes 3-character windows, so a substring shorter than this
  /// can't use the index. Those (very common: "uk", "hd", "4k") fall back to
  /// a `LIKE '%x%'` predicate instead.
  static const _ftsMinChars = 3;

  /// Splits the substrings a search must AND-match into the FTS-indexable ones
  /// (≥ [_ftsMinChars], joined into one MATCH expression) and the short ones
  /// that need a LIKE scan. Returns null when nothing survives trimming — the
  /// caller then yields no rows rather than matching everything.
  static ({String? ftsMatch, List<String> likeTerms})? _planSearch(
    List<String> substrings,
  ) {
    final fts = <String>[];
    final short = <String>[];
    for (final s in substrings) {
      final t = s.trim().toLowerCase();
      if (t.isEmpty) continue;
      (t.length >= _ftsMinChars ? fts : short).add(t);
    }
    if (fts.isEmpty && short.isEmpty) return null;
    return (
      ftsMatch: fts.isEmpty ? null : fts.map(_ftsLiteral).join(' '),
      likeTerms: short,
    );
  }

  /// Builds the `FROM … WHERE …` core for a planned search plus its args. When
  /// the plan has an FTS part the query is driven off the index (join back to
  /// the row); otherwise it's a plain channels scan (all substrings were too
  /// short to index). `search_key` is the only column ambiguous across the
  /// join, so it alone is qualified via [col]; everything else is unambiguous.
  (String, List<Object?>) _searchCore(
    ({String? ftsMatch, List<String> likeTerms}) plan, {
    String? group,
    bool? live,
    int? beforePosition,
    bool? namePrefixLead,
    String? namePrefixTerm,
  }) {
    final col = plan.ftsMatch != null ? 'c.' : '';
    final buf = StringBuffer();
    final args = <Object?>[];
    if (plan.ftsMatch != null) {
      buf.write('FROM channels_fts f JOIN channels c ON c.id = f.rowid '
          'WHERE f.search_key MATCH ? AND catalog_key = ? AND generation = ?');
      args..add(plan.ftsMatch)..add(catalogKey)..add(generation);
    } else {
      buf.write(_base);
      args..add(catalogKey)..add(generation);
    }
    for (final t in plan.likeTerms) {
      buf.write(" AND ${col}search_key LIKE ? ESCAPE '\\'");
      args.add('%${_escapeLike(t)}%');
    }
    if (group != null) {
      buf.write(' AND grp = ?');
      args.add(group);
    }
    if (live != null) {
      buf.write(live ? ' AND $_isLiveSql' : ' AND NOT $_isLiveSql');
    }
    if (beforePosition != null) {
      buf.write(' AND position < ?');
      args.add(beforePosition);
    }
    if (namePrefixLead != null && namePrefixTerm != null) {
      buf.write(namePrefixLead
          ? " AND ${col}search_key LIKE ? ESCAPE '\\'"
          : " AND NOT (${col}search_key LIKE ? ESCAPE '\\')");
      args.add('${_escapeLike(namePrefixTerm)}%');
    }
    return (buf.toString(), args);
  }

  int count({String? group, String? search, bool? live, int? beforePosition}) {
    // The filter box treats the whole query as one substring (spaces and all),
    // preserving the old single `LIKE '%query%'`.
    if (search != null && search.isNotEmpty) {
      final plan = _planSearch([search]);
      // A query that is only whitespace matches nothing — never fall through
      // to an unfiltered count.
      if (plan == null) return 0;
      final (core, args) = _searchCore(plan,
          group: group, live: live, beforePosition: beforePosition);
      try {
        return _db.select('SELECT COUNT(*) AS c $core', args).first['c'] as int;
      } on SqliteException {
        return 0;
      }
    }
    final rows = _db.select(
      'SELECT COUNT(*) AS c ${_where(group: group, live: live, beforePosition: beforePosition)}',
      _args(group: group, beforePosition: beforePosition),
    );
    return rows.first['c'] as int;
  }

  /// Catalog position of the row matching url+name, or null. (Duplicate
  /// url+name pairs are legal in playlists — the first occurrence answers,
  /// which is where zapping should land anyway.)
  int? positionOf({required String url, required String name}) {
    final rows = _db.select(
      'SELECT position $_base AND url = ? AND name = ? '
      'ORDER BY position LIMIT 1',
      [catalogKey, generation, url, name],
    );
    return rows.isEmpty ? null : rows.first['position'] as int;
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
    if (search != null && search.isNotEmpty) {
      final plan = _planSearch([search]);
      if (plan == null) return const [];
      // With the FTS join `*` would pull in channels_fts's column too — select
      // the channel row explicitly. Plain scans keep bare `*`.
      final usesFts = plan.ftsMatch != null;
      final columns = usesFts ? 'c.*' : '*';
      final order = usesFts ? 'ORDER BY c.position' : 'ORDER BY position';
      final (core, args) = _searchCore(plan, group: group, live: live);
      try {
        final rows = _db.select(
          'SELECT $columns $core $order LIMIT ? OFFSET ?',
          [...args, limit, offset],
        );
        return [
          for (final row in rows)
            (position: row['position'] as int, channel: _channelFromRow(row)),
        ];
      } on SqliteException {
        return const [];
      }
    }
    final rows = _db.select(
      'SELECT * ${_where(group: group, live: live)} '
      'ORDER BY position LIMIT ? OFFSET ?',
      [..._args(group: group), limit, offset],
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

  // ── Multi-term search (global search) ────────────────────────────────────
  //
  // The cross-source search page uses AND-of-terms semantics with name-prefix
  // hits leading. Each term is one substring the row must contain: terms ≥3
  // chars go through the FTS index, shorter ones (e.g. "uk", "hd") are a LIKE
  // predicate ANDed on top. The name-prefix "lead" split stays a genuine
  // prefix LIKE on `search_key` (which starts with the lowercased name),
  // applied to the already-narrowed rows. Driving off the index is what keeps
  // this off the UI-isolate full scan the old `LIKE '%term%'` forced.

  /// The first non-empty term, lowercased — the one the name-prefix "lead"
  /// bucket keys on. Empty only when every term is blank (never, once the plan
  /// is non-null).
  static String _firstTerm(List<String> terms) => terms
      .map((t) => t.trim().toLowerCase())
      .firstWhere((t) => t.isNotEmpty, orElse: () => '');

  /// Matches for AND-of-[terms] (optionally restricted to live / non-live
  /// rows, for 'mixed' M3U catalogs).
  int searchCount(List<String> terms, {bool? live}) {
    final plan = _planSearch(terms);
    if (plan == null) return 0;
    final (core, args) = _searchCore(plan, live: live);
    try {
      return _db.select('SELECT COUNT(*) AS c $core', args).first['c'] as int;
    } on SqliteException {
      return 0;
    }
  }

  /// Up to [limit] matches in catalog order. [namePrefixLead] true returns
  /// only hits whose NAME starts with the first term (the "lead" bucket);
  /// false returns only the rest.
  List<IptvChannel> searchPage(
    List<String> terms, {
    bool? live,
    bool? namePrefixLead,
    required int limit,
  }) {
    if (limit <= 0) return const [];
    final plan = _planSearch(terms);
    if (plan == null) return const [];
    final columns = plan.ftsMatch != null ? 'c.*' : '*';
    final order = plan.ftsMatch != null ? 'c.position' : 'position';
    final (core, args) = _searchCore(plan,
        live: live,
        namePrefixLead: namePrefixLead,
        namePrefixTerm: namePrefixLead == null ? null : _firstTerm(terms));
    try {
      final rows = _db.select(
        'SELECT $columns $core ORDER BY $order LIMIT ?',
        [...args, limit],
      );
      return [for (final row in rows) _channelFromRow(row)];
    } on SqliteException {
      return const [];
    }
  }

  static IptvChannel _channelFromRow(Row row) {
    return IptvChannel(
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

/// compute() entry for the one-time legacy-snapshot import: the decoded
/// snapshot's channels are shipped to a worker which writes them into the
/// catalog DB, so the 55k inserts never run on the UI isolate. Returns the
/// ingested channel count.
int ingestLegacySnapshotJob(LegacySnapshotIngestJob job) {
  IptvCatalogDb.ingest(
    dbPath: job.dbPath,
    catalogKey: job.catalogKey,
    channels: job.channels,
    categories: job.categories,
    epgUrl: job.epgUrl,
  );
  return job.channels.length;
}

class LegacySnapshotIngestJob {
  final String dbPath;
  final String catalogKey;
  final List<IptvChannel> channels;
  final List<String> categories;
  final String? epgUrl;

  const LegacySnapshotIngestJob({
    required this.dbPath,
    required this.catalogKey,
    required this.channels,
    required this.categories,
    required this.epgUrl,
  });
}
