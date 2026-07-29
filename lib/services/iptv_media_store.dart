import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../models/iptv_playlist.dart';
import '../utils/json_isolate.dart';
import 'debrify_tv_database.dart';
import 'iptv_catalog_db.dart';

/// SQLite-backed store for IPTV favorites, IPTV watch history and the shared
/// video-resume map.
///
/// All three used to live in SharedPreferences as single JSON blobs, which
/// made every mutation a read-modify-write of the whole store — racy against
/// concurrent writers (the reconcile scan yields mid-flight exactly so users
/// can star things while it runs) and increasingly expensive as they grow.
/// Rows in `debrify_tv.db` give each mutation row-level atomicity via
/// transactions instead. The legacy prefs blobs are imported once on first
/// use and then removed; the prefs keys are only deleted after a successful
/// import, so a failed import simply retries on the next call.
///
/// [StorageService] keeps its public API and delegates here — call sites are
/// unchanged.
/// compute() entry for [IptvMediaStore.reconcileFavoriteUrlsForCatalog]:
/// reads the catalog's current URLs from the DB and computes the
/// stored-URL → current-URL renames with the same canonical-match rules the
/// in-memory scan uses. Runs entirely on the worker; only the (tiny) rename
/// map crosses back.
Map<String, String> computeFavoriteRenamesJob(FavoriteRenameJob job) {
  final storedByCanonical = <String, String>{
    for (final url in job.storedUrls)
      IptvMediaStore.canonicalChannelKey(url): url,
  };
  // Cheap pre-filter, same as the in-memory scan: a channel can only match
  // a favorite on the same host.
  final favoriteHosts = <String>{
    for (final url in job.storedUrls)
      if (Uri.tryParse(url)?.host.isNotEmpty ?? false) Uri.parse(url).host,
  };
  final renames = <String, String>{};
  for (final url in IptvCatalogDb.catalogUrls(
    dbPath: job.dbPath,
    catalogKey: job.catalogKey,
  )) {
    if (storedByCanonical.isEmpty) break;
    if (!favoriteHosts.any(url.contains)) continue;
    final storedKey =
        storedByCanonical.remove(IptvMediaStore.canonicalChannelKey(url));
    if (storedKey != null && storedKey != url) {
      renames[storedKey] = url;
    }
  }
  return renames;
}

class FavoriteRenameJob {
  final String dbPath;
  final String catalogKey;
  final List<String> storedUrls;

  const FavoriteRenameJob({
    required this.dbPath,
    required this.catalogKey,
    required this.storedUrls,
  });
}

class IptvMediaStore {
  IptvMediaStore._();

  static const String _legacyFavoritesKey = 'iptv_favorite_channels_v1';
  static const String _legacyWatchHistoryKey = 'iptv_watch_history_v1';
  static const String _legacyVideoResumeKey = 'video_resume_v1';

  /// How many watched on-demand items to remember. A panel can list tens of
  /// thousands of movies, and this backs a short "pick up where you left off"
  /// shelf — not an archive.
  static const int _watchHistoryMax = 100;

  /// How long the reconcile scan may hold the isolate before yielding — a
  /// 50k-channel playlist would otherwise block input on the way in.
  static const _scanYieldBudget = Duration(milliseconds: 8);

  /// SQLite's default host-parameter limit is 999; stay comfortably under it
  /// when batching `IN (...)` lookups.
  static const int _inChunkSize = 500;

  static Future<void>? _migration;

  @visibleForTesting
  static void debugResetMigration() {
    _migration = null;
  }

  static Future<void> _ensureMigrated() {
    return _migration ??= _migrateFromPrefs().catchError((Object e) {
      // A failed import must never make favorites or resume unreadable —
      // clear the memo so the next call retries, and carry on with whatever
      // is already in the DB.
      _migration = null;
      debugPrint('IptvMediaStore: legacy prefs import failed: $e');
    });
  }

  static Future<void> _migrateFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final db = DebrifyTvDatabase.instance;

    final favoritesRaw = prefs.getString(_legacyFavoritesKey);
    if (favoritesRaw != null) {
      final favorites = await _decodeLegacyMap(favoritesRaw);
      await db.runTxn((txn) async {
        for (final entry in favorites.entries) {
          await txn.insert(
            'iptv_favorites',
            _favoriteRowFromLegacy(entry.key, entry.value),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      });
      await prefs.remove(_legacyFavoritesKey);
    }

    final historyRaw = prefs.getString(_legacyWatchHistoryKey);
    if (historyRaw != null) {
      final history = await _decodeLegacyMap(historyRaw);
      await db.runTxn((txn) async {
        for (final entry in history.entries) {
          await txn.insert(
            'iptv_watch_history',
            _historyRowFromLegacy(entry.key, entry.value),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      });
      await prefs.remove(_legacyWatchHistoryKey);
    }

    final resumeRaw = prefs.getString(_legacyVideoResumeKey);
    if (resumeRaw != null) {
      final resume = await _decodeLegacyMap(resumeRaw);
      await db.runTxn((txn) async {
        for (final entry in resume.entries) {
          final value = entry.value;
          if (value is! Map) continue;
          await txn.insert(
            'video_resume',
            _resumeRow(entry.key, Map<String, dynamic>.from(value)),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      });
      await prefs.remove(_legacyVideoResumeKey);
    }
  }

  /// Decoded off the UI isolate: the resume blob in particular can have
  /// grown large, and this runs exactly when the user first opens IPTV.
  static Future<Map<String, dynamic>> _decodeLegacyMap(String raw) async {
    try {
      final decoded = await decodeJsonAsync(raw);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {
      // A corrupt legacy blob read as empty before the migration too;
      // importing nothing preserves that.
    }
    return {};
  }

  // ── Canonical identity ────────────────────────────────────────────────────

  /// Canonical comparison key for an IPTV channel URL. Xtream Codes stream
  /// URL formats have changed over time (optional /live/ prefix,
  /// percent-encoded credentials, .m3u8 vs .ts extension), so favorites are
  /// matched on a format-insensitive key rather than the raw string.
  static String canonicalChannelKey(String url) {
    // Stremio-addon channel keys (stremio-tv://addon/meta) are already
    // stable synthetic identities — never normalize them (Uri would
    // lowercase the addon-id "host" and decode the meta id).
    if (url.startsWith('stremio-tv://')) return url;
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) return url;
    // pathSegments are percent-decoded, which normalizes credential encoding.
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    // Drop the /live/ prefix only for URLs shaped like Xtream live streams
    // (.../live/<user>/<pass>/<numeric id>.<ext>) — not arbitrary /live/
    // paths, which belong to ordinary playlists where the segment is
    // significant.
    final xtreamLeaf = RegExp(r'^\d+\.\w+$');
    var isXtreamLive = false;
    if (segments.length >= 4 &&
        segments[segments.length - 4] == 'live' &&
        xtreamLeaf.hasMatch(segments.last)) {
      segments.removeAt(segments.length - 4);
      isXtreamLive = true;
    } else if (segments.length == 3 && xtreamLeaf.hasMatch(segments.last)) {
      // Legacy un-prefixed form: /<user>/<pass>/<numeric id>.<ext>.
      isXtreamLive = true;
    }
    // For Xtream live URLs the extension is presentation, not identity: the
    // same channel is served as .m3u8 on HLS panels and .ts on HLS-off ones
    // (VOD /movie/ URLs keep theirs — the container is real there).
    if (isXtreamLive) {
      final leaf = segments.last;
      segments[segments.length - 1] = leaf.substring(0, leaf.indexOf('.'));
    }
    final port = uri.hasPort ? ':${uri.port}' : '';
    // Keep the query: distinct channels can differ only by query params.
    final query = uri.hasQuery ? '?${uri.query}' : '';
    return '${uri.scheme}://${uri.host}$port/${segments.join('/')}$query';
  }

  // ── Favorites ─────────────────────────────────────────────────────────────

  /// Rewrite stored favorite URLs to the current format when a fetched
  /// channel matches an existing favorite canonically but not literally
  /// (e.g. favorites saved before the Xtream /live/ URL fix).
  static Future<void> reconcileFavoriteUrls(List<IptvChannel> channels) async {
    await _ensureMigrated();
    final db = await DebrifyTvDatabase.instance.database;
    final urlRows = await db.query('iptv_favorites', columns: ['url']);
    if (urlRows.isEmpty) return;
    final storedUrls = [for (final row in urlRows) row['url'] as String];

    final storedByCanonical = <String, String>{
      for (final url in storedUrls) canonicalChannelKey(url): url,
    };

    // Cheap pre-filter: a channel can only match a favorite on the same
    // host, and canonicalizing tens of thousands of URLs on the UI isolate
    // is not free.
    final favoriteHosts = <String>{
      for (final url in storedUrls)
        if (Uri.tryParse(url)?.host.isNotEmpty ?? false) Uri.parse(url).host,
    };

    // The scan yields to the event loop, so a concurrent star/un-star can
    // land mid-flight. Renames are collected against locals only and applied
    // in one transaction that re-checks each source row — an entry un-starred
    // during the scan stays gone instead of being resurrected.
    final renames = <String, String>{}; // stored URL → current URL
    final chunk = Stopwatch()..start();
    for (final channel in channels) {
      if (storedByCanonical.isEmpty) break;
      if (chunk.elapsedMicroseconds >= _scanYieldBudget.inMicroseconds) {
        await Future<void>.delayed(Duration.zero);
        chunk.reset();
      }
      if (!favoriteHosts.any(channel.url.contains)) continue;
      // Consume the mapping so a second canonically-equal channel can't
      // re-move an already-migrated entry.
      final storedKey = storedByCanonical.remove(
        canonicalChannelKey(channel.url),
      );
      if (storedKey != null && storedKey != channel.url) {
        renames[storedKey] = channel.url;
      }
    }
    if (renames.isEmpty) return;
    await _applyFavoriteRenames(renames);
  }

  /// DB-catalog variant of [reconcileFavoriteUrls]: the fresh URLs are read
  /// straight from the catalog rows on a WORKER isolate — walking a paging
  /// facade here would keep the scan's cost on the UI isolate, which is
  /// tens of near-saturated seconds on a big playlist.
  static Future<void> reconcileFavoriteUrlsForCatalog(
    String catalogKey,
  ) async {
    await _ensureMigrated();
    if (!IptvCatalogDb.isOpen) return;
    final db = await DebrifyTvDatabase.instance.database;
    final urlRows = await db.query('iptv_favorites', columns: ['url']);
    if (urlRows.isEmpty) return;

    final renames = await compute(
      computeFavoriteRenamesJob,
      FavoriteRenameJob(
        dbPath: IptvCatalogDb.path,
        catalogKey: catalogKey,
        storedUrls: [for (final row in urlRows) row['url'] as String],
      ),
    );
    if (renames.isEmpty) return;
    await _applyFavoriteRenames(renames);
  }

  /// Apply stored-URL → current-URL renames in one transaction that
  /// re-checks each source row — an entry un-starred while the scan ran
  /// stays gone instead of being resurrected.
  static Future<void> _applyFavoriteRenames(
    Map<String, String> renames,
  ) async {
    await DebrifyTvDatabase.instance.runTxn((txn) async {
      for (final entry in renames.entries) {
        final rows = await txn.query(
          'iptv_favorites',
          where: 'url = ?',
          whereArgs: [entry.key],
        );
        if (rows.isEmpty) continue; // un-starred during the scan
        final row = Map<String, Object?>.from(rows.first);
        row['url'] = entry.value;
        await txn.delete(
          'iptv_favorites',
          where: 'url = ?',
          whereArgs: [entry.key],
        );
        await txn.insert(
          'iptv_favorites',
          row,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  static Future<void> setChannelFavorited(
    String channelUrl,
    bool isFavorited, {
    String? channelName,
    String? logoUrl,
    String? group,
    String? playlistId,
    Map<String, String>? httpHeaders,
  }) async {
    await _ensureMigrated();
    final canonical = canonicalChannelKey(channelUrl);
    await DebrifyTvDatabase.instance.runTxn((txn) async {
      // Match older stored URL formats too, so toggling can't leave stale
      // duplicates behind. Favorites number in the dozens, so scanning the
      // URLs inside the transaction is cheap.
      final rows = await txn.query('iptv_favorites', columns: ['url']);
      for (final row in rows) {
        final url = row['url'] as String;
        if (canonicalChannelKey(url) == canonical) {
          await txn.delete(
            'iptv_favorites',
            where: 'url = ?',
            whereArgs: [url],
          );
        }
      }
      if (isFavorited) {
        await txn.insert('iptv_favorites', {
          'url': channelUrl,
          'name': channelName ?? '',
          'logo_url': logoUrl ?? '',
          'channel_group': group ?? '',
          'playlist_id': playlistId ?? '',
          // The favorites view rebuilds channels from this metadata alone
          // (no re-fetch), so a channel that needs a specific UA/Referer has
          // to carry it here or it would play from the playlist but not from
          // Favorites. Omitted when empty — most channels declare none.
          'http_headers_json': (httpHeaders != null && httpHeaders.isNotEmpty)
              ? jsonEncode(httpHeaders)
              : null,
          'added_at': DateTime.now().millisecondsSinceEpoch,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  static Future<void> removeFavoritesByPlaylistId(String playlistId) async {
    await _ensureMigrated();
    final db = await DebrifyTvDatabase.instance.database;
    await db.delete(
      'iptv_favorites',
      where: 'playlist_id = ?',
      whereArgs: [playlistId],
    );
  }

  /// All favorites, url → metadata, in the same map shape the prefs store
  /// used ('name'/'logoUrl'/'group'/'playlistId'/'httpHeaders'/'addedAt'),
  /// oldest-starred first (the prefs map's insertion order).
  static Future<Map<String, Map<String, dynamic>>> favoriteChannels() async {
    await _ensureMigrated();
    final db = await DebrifyTvDatabase.instance.database;
    final rows = await db.query(
      'iptv_favorites',
      orderBy: 'added_at ASC, url ASC',
    );
    return {
      for (final row in rows) row['url'] as String: _favoriteMeta(row),
    };
  }

  // ── Watch history ─────────────────────────────────────────────────────────

  static Future<void> recordWatch(
    String channelUrl, {
    String? channelName,
    String? logoUrl,
    String? group,
    String? playlistId,
    Map<String, String>? httpHeaders,
    String? seriesId,
    String? seriesName,
    int? season,
    int? episode,
    bool? hasNextEpisode,
  }) async {
    if (channelUrl.isEmpty) return;
    await _ensureMigrated();
    await DebrifyTvDatabase.instance.runTxn((txn) async {
      await txn.insert('iptv_watch_history', {
        'url': channelUrl,
        'name': channelName ?? '',
        'logo_url': logoUrl ?? '',
        'channel_group': group ?? '',
        'playlist_id': playlistId ?? '',
        'http_headers_json': (httpHeaders != null && httpHeaders.isNotEmpty)
            ? jsonEncode(httpHeaders)
            : null,
        'series_id': (seriesId != null && seriesId.isNotEmpty) ? seriesId : null,
        'series_name':
            (seriesName != null && seriesName.isNotEmpty) ? seriesName : null,
        'season': season,
        'episode': episode,
        'has_next': hasNextEpisode == null ? null : (hasNextEpisode ? 1 : 0),
        'last_played_at': DateTime.now().millisecondsSinceEpoch,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await txn.execute(
        '''
        DELETE FROM iptv_watch_history
        WHERE url NOT IN (
          SELECT url FROM iptv_watch_history
          ORDER BY last_played_at DESC
          LIMIT ?
        )
        ''',
        [_watchHistoryMax],
      );
    });
  }

  static Future<void> removeWatchHistoryByPlaylistId(String playlistId) async {
    await _ensureMigrated();
    final db = await DebrifyTvDatabase.instance.database;
    await db.delete(
      'iptv_watch_history',
      where: 'playlist_id = ?',
      whereArgs: [playlistId],
    );
  }

  /// All remembered on-demand items, url → metadata, oldest-played first.
  static Future<Map<String, Map<String, dynamic>>> watchHistory() async {
    await _ensureMigrated();
    final db = await DebrifyTvDatabase.instance.database;
    final rows = await db.query(
      'iptv_watch_history',
      orderBy: 'last_played_at ASC, url ASC',
    );
    return {
      for (final row in rows) row['url'] as String: _historyMeta(row),
    };
  }

  // ── Video resume ──────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>?> videoResume(String key) async {
    await _ensureMigrated();
    final db = await DebrifyTvDatabase.instance.database;
    final rows = await db.query(
      'video_resume',
      where: 'resume_key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _resumeMeta(rows.first);
  }

  /// Persists the known resume fields
  /// (positionMs/durationMs/speed/aspect/updatedAt) for [key].
  static Future<void> upsertVideoResume(
    String key,
    Map<String, dynamic> entry,
  ) async {
    await _ensureMigrated();
    final db = await DebrifyTvDatabase.instance.database;
    await db.insert(
      'video_resume',
      _resumeRow(key, entry),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Stored resume entries for whichever of [keys] exist. Batched `IN`
  /// lookups — callers pass up to thousands of playlist URLs.
  static Future<Map<String, Map<String, dynamic>>> resumeEntries(
    Iterable<String> keys,
  ) async {
    await _ensureMigrated();
    final wanted = keys.where((k) => k.isNotEmpty).toSet().toList();
    if (wanted.isEmpty) return {};
    final db = await DebrifyTvDatabase.instance.database;
    final result = <String, Map<String, dynamic>>{};
    for (var i = 0; i < wanted.length; i += _inChunkSize) {
      final chunk = wanted.sublist(
        i,
        math.min(i + _inChunkSize, wanted.length),
      );
      final placeholders = List.filled(chunk.length, '?').join(',');
      final rows = await db.query(
        'video_resume',
        where: 'resume_key IN ($placeholders)',
        whereArgs: chunk,
      );
      for (final row in rows) {
        result[row['resume_key'] as String] = _resumeMeta(row);
      }
    }
    return result;
  }

  static Future<void> clearVideoResume() async {
    await _ensureMigrated();
    final db = await DebrifyTvDatabase.instance.database;
    await db.delete('video_resume');
  }

  // ── Row/meta mapping ──────────────────────────────────────────────────────

  static Map<String, Object?> _favoriteRowFromLegacy(String url, Object? meta) {
    final map = meta is Map ? meta : const <String, dynamic>{};
    return {
      'url': url,
      'name': map['name']?.toString() ?? '',
      'logo_url': map['logoUrl']?.toString() ?? '',
      'channel_group': map['group']?.toString() ?? '',
      'playlist_id': map['playlistId']?.toString() ?? '',
      'http_headers_json': _headersJson(map['httpHeaders']),
      'added_at': (map['addedAt'] as num?)?.toInt() ?? 0,
    };
  }

  static Map<String, Object?> _historyRowFromLegacy(String url, Object? meta) {
    final map = meta is Map ? meta : const <String, dynamic>{};
    final seriesId = map['seriesId']?.toString();
    final seriesName = map['seriesName']?.toString();
    final hasNext = map['hasNext'];
    return {
      'url': url,
      'name': map['name']?.toString() ?? '',
      'logo_url': map['logoUrl']?.toString() ?? '',
      'channel_group': map['group']?.toString() ?? '',
      'playlist_id': map['playlistId']?.toString() ?? '',
      'http_headers_json': _headersJson(map['httpHeaders']),
      'series_id': (seriesId != null && seriesId.isNotEmpty) ? seriesId : null,
      'series_name':
          (seriesName != null && seriesName.isNotEmpty) ? seriesName : null,
      'season': (map['season'] as num?)?.toInt(),
      'episode': (map['episode'] as num?)?.toInt(),
      'has_next': hasNext is bool ? (hasNext ? 1 : 0) : null,
      'last_played_at': (map['lastPlayedAt'] as num?)?.toInt() ?? 0,
    };
  }

  static String? _headersJson(Object? raw) {
    if (raw is! Map || raw.isEmpty) return null;
    final headers = <String, String>{};
    raw.forEach((key, value) {
      if (key is String && value != null) headers[key] = value.toString();
    });
    return headers.isEmpty ? null : jsonEncode(headers);
  }

  static Map<String, String>? _decodeHeaders(Object? json) {
    if (json is! String || json.isEmpty) return null;
    try {
      final decoded = jsonDecode(json);
      if (decoded is Map) {
        return decoded.map(
          (key, value) => MapEntry(key.toString(), value.toString()),
        );
      }
    } catch (_) {}
    return null;
  }

  static Map<String, dynamic> _favoriteMeta(Map<String, Object?> row) {
    final headers = _decodeHeaders(row['http_headers_json']);
    return {
      'name': row['name'] ?? '',
      'logoUrl': row['logo_url'] ?? '',
      'group': row['channel_group'] ?? '',
      'playlistId': row['playlist_id'] ?? '',
      if (headers != null) 'httpHeaders': headers,
      'addedAt': (row['added_at'] as num?)?.toInt() ?? 0,
    };
  }

  static Map<String, dynamic> _historyMeta(Map<String, Object?> row) {
    final headers = _decodeHeaders(row['http_headers_json']);
    final seriesId = row['series_id'];
    final seriesName = row['series_name'];
    final season = row['season'];
    final episode = row['episode'];
    final hasNext = row['has_next'];
    return {
      'name': row['name'] ?? '',
      'logoUrl': row['logo_url'] ?? '',
      'group': row['channel_group'] ?? '',
      'playlistId': row['playlist_id'] ?? '',
      if (headers != null) 'httpHeaders': headers,
      if (seriesId is String && seriesId.isNotEmpty) 'seriesId': seriesId,
      if (seriesName is String && seriesName.isNotEmpty)
        'seriesName': seriesName,
      if (season is num) 'season': season.toInt(),
      if (episode is num) 'episode': episode.toInt(),
      if (hasNext is num) 'hasNext': hasNext != 0,
      'lastPlayedAt': (row['last_played_at'] as num?)?.toInt() ?? 0,
    };
  }

  static Map<String, Object?> _resumeRow(
    String key,
    Map<String, dynamic> entry,
  ) {
    return {
      'resume_key': key,
      'position_ms': (entry['positionMs'] as num?)?.toInt() ?? 0,
      'duration_ms': (entry['durationMs'] as num?)?.toInt() ?? 0,
      'speed': (entry['speed'] as num?)?.toDouble() ?? 1.0,
      'aspect': entry['aspect']?.toString() ?? 'contain',
      'updated_at': (entry['updatedAt'] as num?)?.toInt() ?? 0,
    };
  }

  static Map<String, dynamic> _resumeMeta(Map<String, Object?> row) {
    final updatedAt = (row['updated_at'] as num?)?.toInt() ?? 0;
    return {
      'positionMs': (row['position_ms'] as num?)?.toInt() ?? 0,
      'durationMs': (row['duration_ms'] as num?)?.toInt() ?? 0,
      'speed': (row['speed'] as num?)?.toDouble() ?? 1.0,
      'aspect': row['aspect']?.toString() ?? 'contain',
      // 0 means the legacy entry never carried a timestamp; omit the key so
      // Continue Watching's fallback to the watch-history timestamp still
      // fires instead of sorting the item to 1970.
      if (updatedAt != 0) 'updatedAt': updatedAt,
    };
  }
}
