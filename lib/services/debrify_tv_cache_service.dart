import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../models/debrify_tv/channel_stats.dart';
import '../models/debrify_tv_cache.dart';
import 'debrify_tv_database.dart';
import 'webdav_sync/webdav_sync_library_models.dart';
import 'webdav_sync/webdav_sync_library_mutation.dart';

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

  /// Reads a complete portable snapshot, including legacy/recoverable child
  /// rows whose cache-state parent is missing. Normal cache consumers retain
  /// [getEntry]'s existing null-on-missing-state behavior.
  static Future<DebrifyTvChannelCacheEntry?> getEntryForPortableExport(
    String channelId,
  ) {
    return DebrifyTvDatabase.instance.runScoped(
      (db) => _getEntry(db, channelId, includeRowsWithoutState: true),
    );
  }

  static Future<DebrifyTvChannelCacheEntry?> _getEntry(
    DatabaseExecutor db,
    String channelId, {
    bool includeRowsWithoutState = false,
  }) async {
    final stateRows = await db.query(
      'tv_channel_cache_state',
      where: 'channel_id = ?',
      whereArgs: [channelId],
      limit: 1,
    );

    if (stateRows.isEmpty && !includeRowsWithoutState) {
      return null;
    }

    final state = stateRows.isEmpty ? null : stateRows.first;

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

    if (state == null &&
        keywordRows.isEmpty &&
        torrentRows.isEmpty &&
        statsRows.isEmpty) {
      return null;
    }

    final status =
        (state?['status'] as String?) ??
        (torrents.isNotEmpty
            ? DebrifyTvCacheStatus.ready
            : DebrifyTvCacheStatus.warming);
    final errorMessage = state?['error_message'] as String?;
    final fetchedAt = state?['fetched_at'] as int? ?? 0;

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

  static Future<void> saveEntry(
    DebrifyTvChannelCacheEntry entry, {
    WebDavSyncMutationOrigin origin = WebDavSyncMutationOrigin.user,
    Transaction? transaction,
    Stream<CachedTorrent>? torrentStream,
  }) async {
    String? generationId;
    Future<void> write(Transaction txn) async {
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

      {
        var batch = txn.batch();
        var pending = 0;
        var index = 0;
        final baseTimestamp = DateTime.now().millisecondsSinceEpoch;
        await for (final torrent
            in torrentStream ?? Stream.fromIterable(entry.torrents)) {
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
          index++;
          if (++pending >= 500) {
            await batch.commit(noResult: true);
            batch = txn.batch();
            pending = 0;
          }
        }
        if (pending > 0) await batch.commit(noResult: true);
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

      if (origin == WebDavSyncMutationOrigin.user) {
        final existing = await _poolGeneration(txn, entry.channelId);
        generationId = WebDavSyncLibraryMutation.mintTvGenerationId(
          differentFrom: existing,
        );
        await _writePoolGeneration(
          txn,
          entry.channelId,
          generationId!,
          WebDavSyncLibraryMutation.nextTvStampMs(),
        );
        await _incrementWebDavSyncRevision(txn);
        await DebrifyTvDatabase.markWebDavTvChangesPending(txn);
      }
    }

    if (transaction != null) {
      await write(transaction);
    } else {
      await DebrifyTvDatabase.instance.runTxn(write);
    }
  }

  static Future<void> removeEntry(
    String channelId, {
    WebDavSyncMutationOrigin origin = WebDavSyncMutationOrigin.user,
  }) async {
    await DebrifyTvDatabase.instance.runTxn((txn) async {
      final channelExists =
          origin == WebDavSyncMutationOrigin.user &&
          (await txn.query(
            'tv_channels',
            columns: const <String>['channel_id'],
            where: 'channel_id = ?',
            whereArgs: <Object?>[channelId],
            limit: 1,
          )).isNotEmpty;
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
      if (channelExists) {
        final existing = await _poolGeneration(txn, channelId);
        await _writePoolGeneration(
          txn,
          channelId,
          WebDavSyncLibraryMutation.mintTvGenerationId(differentFrom: existing),
          WebDavSyncLibraryMutation.nextTvStampMs(),
        );
        await _incrementWebDavSyncRevision(txn);
        await DebrifyTvDatabase.markWebDavTvChangesPending(txn);
      }
    });
  }

  static Future<void> clearAll({
    WebDavSyncMutationOrigin origin = WebDavSyncMutationOrigin.user,
  }) async {
    await DebrifyTvDatabase.instance.runTxn((txn) async {
      final channelIds = origin == WebDavSyncMutationOrigin.user
          ? (await txn.query(
                  'tv_channels',
                  columns: const <String>['channel_id'],
                ))
                .map((row) => row['channel_id']! as String)
                .toList(growable: false)
          : const <String>[];
      await txn.delete('tv_cached_torrents');
      await txn.delete('tv_keyword_stats');
      await txn.delete('tv_channel_cache_state');
      if (channelIds.isNotEmpty) {
        final now = WebDavSyncLibraryMutation.nextTvStampMs();
        for (final channelId in channelIds) {
          final existing = await _poolGeneration(txn, channelId);
          await _writePoolGeneration(
            txn,
            channelId,
            WebDavSyncLibraryMutation.mintTvGenerationId(
              differentFrom: existing,
            ),
            now,
          );
        }
        await _incrementWebDavSyncRevision(txn);
        await DebrifyTvDatabase.markWebDavTvChangesPending(txn);
      }
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

Future<void> _writePoolGeneration(
  DatabaseExecutor db,
  String channelId,
  String generationId,
  int updatedAtMs,
) => db.insert('webdav_sync_record_state', <String, Object?>{
  'kind': WebDavSyncLibraryKinds.tvPoolGeneration,
  'owner_key': channelId,
  'item_key': '',
  'updated_at_ms': updatedAtMs,
  'origin_device_id': WebDavSyncLibraryMutation.originDeviceId,
  'normalized': 0,
  'deleted': 0,
  'aux': generationId,
}, conflictAlgorithm: ConflictAlgorithm.replace);

Future<String?> _poolGeneration(DatabaseExecutor db, String channelId) async {
  final rows = await db.query(
    'webdav_sync_record_state',
    columns: const <String>['aux'],
    where: 'kind = ? AND owner_key = ? AND item_key = ?',
    whereArgs: <Object?>[
      WebDavSyncLibraryKinds.tvPoolGeneration,
      channelId,
      '',
    ],
    limit: 1,
  );
  return rows.isEmpty ? null : rows.single['aux'] as String?;
}

Future<void> _incrementWebDavSyncRevision(DatabaseExecutor db) => db.execute('''
  UPDATE webdav_sync_meta
  SET value = CAST(CAST(value AS INTEGER) + 1 AS TEXT)
  WHERE key = 'mutation_revision'
''');
