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
  static const _schemaVersion = 1;

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
    _createSchema(db);
    _db = db;
    _path = path;
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
    // Defensive cleanup: a previous build shipped an FTS5 `channels_fts` index
    // (plus these triggers) that crashed on devices whose bundled SQLite lacks
    // the trigram tokenizer. Drop any leftovers so their triggers can't fire on
    // ingest and break catalog writes. Wrapped so a missing or corrupt object
    // can never abort schema setup; a clean database no-ops through it.
    try {
      db.execute('DROP TRIGGER IF EXISTS channels_fts_ai');
      db.execute('DROP TRIGGER IF EXISTS channels_fts_ad');
      db.execute('DROP TABLE IF EXISTS channels_fts');
    } catch (_) {}

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
    db.execute(
      "INSERT OR REPLACE INTO meta(key, value) VALUES ('schema_version', ?)",
      ['$_schemaVersion'],
    );
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
    String? search,
    int? beforePosition,
  }) =>
      [
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
    if (live != null) buf.write(live ? ' AND $_isLiveSql' : ' AND NOT $_isLiveSql');
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
