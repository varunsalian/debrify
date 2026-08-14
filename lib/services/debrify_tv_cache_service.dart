import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../models/debrify_tv/channel_stats.dart';
import '../models/debrify_tv_cache.dart';
import 'debrify_tv_database.dart';

class DebrifyTvCacheService {
  /// Rail-cheap health for every channel, in three grouped queries — run once
  /// when the Spotlight rail loads. Never classifies a torrent name: the
  /// per-row quality pass belongs to the focused channel's stage stats only.
  static Future<Map<String, DebrifyTvRailHealth>> loadRailHealth() {
    return DebrifyTvDatabase.instance.runScoped((db) async {
      final pooledRows = await db.rawQuery(
        'SELECT channel_id, COUNT(*) AS n FROM tv_cached_torrents '
        'GROUP BY channel_id',
      );
      final deadRows = await db.rawQuery(
        'SELECT channel_id, COUNT(*) AS n FROM tv_keyword_stats '
        'WHERE total_fetched = 0 GROUP BY channel_id',
      );
      final stateRows = await db.query(
        'tv_channel_cache_state',
        columns: ['channel_id', 'status', 'fetched_at'],
      );

      final pooled = <String, int>{
        for (final r in pooledRows)
          r['channel_id'] as String: (r['n'] as int?) ?? 0,
      };
      final dead = <String, int>{
        for (final r in deadRows)
          r['channel_id'] as String: (r['n'] as int?) ?? 0,
      };

      final health = <String, DebrifyTvRailHealth>{};
      for (final r in stateRows) {
        final id = r['channel_id'] as String;
        health[id] = DebrifyTvRailHealth(
          pooled: pooled[id] ?? 0,
          deadKeywords: dead[id] ?? 0,
          status: (r['status'] as String?) ?? DebrifyTvCacheStatus.warming,
          fetchedAt: (r['fetched_at'] as int?) ?? 0,
        );
      }
      // A channel with pooled rows but no state row still gets a count.
      for (final id in pooled.keys) {
        health.putIfAbsent(
          id,
          () => DebrifyTvRailHealth(
            pooled: pooled[id]!,
            deadKeywords: dead[id] ?? 0,
            status: DebrifyTvCacheStatus.ready,
            fetchedAt: 0,
          ),
        );
      }
      return health;
    });
  }

  static Future<Map<String, DebrifyTvChannelCacheEntry>> loadAllEntries() {
    return DebrifyTvDatabase.instance.runScoped((db) async {
      final rows = await db.query(
        'tv_channel_cache_state',
        columns: ['channel_id'],
      );
      final Map<String, DebrifyTvChannelCacheEntry> entries = {};
      for (final row in rows) {
        final channelId = row['channel_id'] as String;
        final entry = await _getEntry(db, channelId);
        if (entry != null) {
          entries[channelId] = entry;
        }
      }
      return entries;
    });
  }

  static Future<DebrifyTvChannelCacheEntry?> getEntry(String channelId) {
    return DebrifyTvDatabase.instance.runScoped(
      (db) => _getEntry(db, channelId),
    );
  }

  static Future<DebrifyTvChannelCacheEntry?> _getEntry(
    DatabaseExecutor db,
    String channelId,
  ) async {
    final stateRows = await db.query(
      'tv_channel_cache_state',
      where: 'channel_id = ?',
      whereArgs: [channelId],
      limit: 1,
    );

    if (stateRows.isEmpty) {
      return null;
    }

    final state = stateRows.first;
    final status = (state['status'] as String?) ?? DebrifyTvCacheStatus.warming;
    final errorMessage = state['error_message'] as String?;
    final fetchedAt = state['fetched_at'] as int? ?? 0;

    final keywordRows = await db.query(
      'tv_channel_keywords',
      where: 'channel_id = ?',
      whereArgs: [channelId],
      orderBy: 'position ASC',
    );
    final normalizedKeywords = keywordRows
        .map((row) => (row['keyword'] as String).toLowerCase())
        .toList();

    final torrentRows = await db.query(
      'tv_cached_torrents',
      where: 'channel_id = ?',
      whereArgs: [channelId],
      orderBy: 'added_at DESC',
    );
    final torrents = torrentRows.map(_rowToCachedTorrent).toList();

    final statsRows = await db.query(
      'tv_keyword_stats',
      where: 'channel_id = ?',
      whereArgs: [channelId],
    );
    final Map<String, KeywordStat> keywordStats = {
      for (final row in statsRows)
        (row['keyword'] as String).toLowerCase(): KeywordStat(
          totalFetched: row['total_fetched'] as int? ?? 0,
          lastSearchedAt: row['last_searched_at'] as int? ?? 0,
          pagesPulled: row['pages_pulled'] as int? ?? 0,
          pirateBayHits: row['pirate_bay_hits'] as int? ?? 0,
        ),
    };

    return DebrifyTvChannelCacheEntry(
      version: 1,
      channelId: channelId,
      normalizedKeywords: normalizedKeywords,
      fetchedAt: fetchedAt,
      status: status,
      errorMessage: errorMessage,
      torrents: torrents,
      keywordStats: keywordStats,
    );
  }

  static Future<void> saveEntry(DebrifyTvChannelCacheEntry entry) async {
    await DebrifyTvDatabase.instance.runTxn((txn) async {
      await txn.insert('tv_channel_cache_state', {
        'channel_id': entry.channelId,
        'status': entry.status,
        'error_message': entry.errorMessage,
        'fetched_at': entry.fetchedAt,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      await txn.delete(
        'tv_cached_torrents',
        where: 'channel_id = ?',
        whereArgs: [entry.channelId],
      );

      if (entry.torrents.isNotEmpty) {
        final batch = txn.batch();
        final baseTimestamp = DateTime.now().millisecondsSinceEpoch;
        for (var index = 0; index < entry.torrents.length; index++) {
          final torrent = entry.torrents[index];
          batch.insert('tv_cached_torrents', {
            'channel_id': entry.channelId,
            'infohash': torrent.infohash,
            'name': torrent.name,
            'size_bytes': torrent.sizeBytes,
            'created_unix': torrent.createdUnix,
            'seeders': torrent.seeders,
            'leechers': torrent.leechers,
            'completed': torrent.completed,
            'scraped_date': torrent.scrapedDate,
            'keywords_json': jsonEncode(torrent.keywords),
            'sources_json': jsonEncode(torrent.sources),
            'added_at': baseTimestamp + index,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
        await batch.commit(noResult: true);
      }

      await txn.delete(
        'tv_keyword_stats',
        where: 'channel_id = ?',
        whereArgs: [entry.channelId],
      );

      if (entry.keywordStats.isNotEmpty) {
        final statsBatch = txn.batch();
        entry.keywordStats.forEach((keyword, stat) {
          statsBatch.insert('tv_keyword_stats', {
            'channel_id': entry.channelId,
            'keyword': keyword,
            'total_fetched': stat.totalFetched,
            'last_searched_at': stat.lastSearchedAt,
            'pages_pulled': stat.pagesPulled,
            'pirate_bay_hits': stat.pirateBayHits,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        });
        await statsBatch.commit(noResult: true);
      }
    });
  }

  static Future<void> removeEntry(String channelId) async {
    await DebrifyTvDatabase.instance.runTxn((txn) async {
      await txn.delete(
        'tv_cached_torrents',
        where: 'channel_id = ?',
        whereArgs: [channelId],
      );
      await txn.delete(
        'tv_keyword_stats',
        where: 'channel_id = ?',
        whereArgs: [channelId],
      );
      await txn.delete(
        'tv_channel_cache_state',
        where: 'channel_id = ?',
        whereArgs: [channelId],
      );
    });
  }

  static Future<void> clearAll() async {
    await DebrifyTvDatabase.instance.runTxn((txn) async {
      await txn.delete('tv_cached_torrents');
      await txn.delete('tv_keyword_stats');
      await txn.delete('tv_channel_cache_state');
    });
  }

  static CachedTorrent _rowToCachedTorrent(Map<String, Object?> row) {
    return CachedTorrent(
      rowid: 0,
      infohash: (row['infohash'] as String?) ?? '',
      name: (row['name'] as String?) ?? '',
      sizeBytes: row['size_bytes'] as int? ?? 0,
      createdUnix: row['created_unix'] as int? ?? 0,
      seeders: row['seeders'] as int? ?? 0,
      leechers: row['leechers'] as int? ?? 0,
      completed: row['completed'] as int? ?? 0,
      scrapedDate: row['scraped_date'] as int? ?? 0,
      keywords: _decodeStringList(row['keywords_json']),
      sources: _decodeStringList(row['sources_json']),
    );
  }

  static List<String> _decodeStringList(Object? value) {
    if (value is String && value.isNotEmpty) {
      // Corrupt or old-format column values must not break the whole cache
      // read — treat them as empty.
      try {
        final raw = jsonDecode(value);
        if (raw is! List) return const <String>[];
        return raw
            .map((e) => e?.toString() ?? '')
            .where((e) => e.isNotEmpty)
            .toList();
      } on FormatException {
        return const <String>[];
      }
    }
    return const <String>[];
  }
}
