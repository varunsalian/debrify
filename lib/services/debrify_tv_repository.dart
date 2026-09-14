import 'package:sqflite/sqflite.dart';

import '../models/debrify_tv_cache.dart';
import '../models/debrify_tv_channel_record.dart';
import 'debrify_tv_database.dart';
import 'webdav_sync/webdav_sync_library_models.dart';
import 'webdav_sync/webdav_sync_library_mutation.dart';

class DebrifyTvRepository {
  DebrifyTvRepository._();

  static final DebrifyTvRepository instance = DebrifyTvRepository._();

  Future<List<DebrifyTvChannelRecord>> fetchAllChannels() {
    return DebrifyTvDatabase.instance.runScoped((db) async {
      final channels = await db.query(
        'tv_channels',
        orderBy: 'channel_number ASC',
      );

      if (channels.isEmpty) {
        return const [];
      }

      // Keep the channel and keyword reads on one captured profile scope.
      final List<DebrifyTvChannelRecord> result = [];
      for (final row in channels) {
        final channelId = row['channel_id'] as String;
        final keywords = await _fetchChannelKeywords(db, channelId);

        result.add(
          DebrifyTvChannelRecord(
            channelId: channelId,
            name: row['name'] as String,
            keywords: keywords,
            avoidNsfw: (row['avoid_nsfw'] as int? ?? 1) == 1,
            channelNumber: (row['channel_number'] as int? ?? 0),
            createdAt: DateTime.fromMillisecondsSinceEpoch(
              row['created_at'] as int? ?? 0,
            ),
            updatedAt: DateTime.fromMillisecondsSinceEpoch(
              row['updated_at'] as int? ?? 0,
            ),
          ),
        );
      }

      return result;
    });
  }

  Future<List<String>> fetchChannelKeywords(String channelId) {
    return DebrifyTvDatabase.instance.runScoped(
      (db) => _fetchChannelKeywords(db, channelId),
    );
  }

  Future<List<String>> _fetchChannelKeywords(
    DatabaseExecutor db,
    String channelId,
  ) async {
    final rows = await db.query(
      'tv_channel_keywords',
      where: 'channel_id = ?',
      whereArgs: [channelId],
      orderBy: 'position ASC',
    );
    if (rows.isEmpty) {
      return const <String>[];
    }
    return rows
        .map((row) => (row['keyword'] as String?)?.trim() ?? '')
        .where((keyword) => keyword.isNotEmpty)
        .toList(growable: false);
  }

  Future<void> upsertChannel(
    DebrifyTvChannelRecord record, {
    WebDavSyncMutationOrigin origin = WebDavSyncMutationOrigin.user,
    Transaction? transaction,
  }) async {
    Future<void> write(Transaction txn) async {
      var channelNumber = record.channelNumber;

      if (channelNumber <= 0) {
        final existing = await txn.query(
          'tv_channels',
          columns: ['channel_number'],
          where: 'channel_id = ?',
          whereArgs: [record.channelId],
          limit: 1,
        );

        if (existing.isNotEmpty) {
          channelNumber = existing.first['channel_number'] as int? ?? 0;
        } else {
          final result = await txn.rawQuery(
            'SELECT MAX(channel_number) as max_channel FROM tv_channels',
          );
          final maxValue = (result.first['max_channel'] as int?) ?? 0;
          channelNumber = maxValue + 1;
        }
      }

      await txn.insert('tv_channels', {
        'channel_id': record.channelId,
        'name': record.name,
        'avoid_nsfw': record.avoidNsfw ? 1 : 0,
        'channel_number': channelNumber,
        'created_at': record.createdAt.millisecondsSinceEpoch,
        'updated_at': record.updatedAt.millisecondsSinceEpoch,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      await txn.delete(
        'tv_channel_keywords',
        where: 'channel_id = ?',
        whereArgs: [record.channelId],
      );

      for (var i = 0; i < record.keywords.length; i++) {
        await txn.insert('tv_channel_keywords', {
          'channel_id': record.channelId,
          'position': i,
          'keyword': record.keywords[i],
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }

      await txn.insert('tv_channel_cache_state', {
        'channel_id': record.channelId,
        'status': DebrifyTvCacheStatus.warming,
        'error_message': null,
        'fetched_at': 0,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      if (origin == WebDavSyncMutationOrigin.user) {
        final now = WebDavSyncLibraryMutation.nextTvStampMs();
        await txn.insert('webdav_sync_record_state', <String, Object?>{
          'kind': WebDavSyncLibraryKinds.tvChannels,
          'owner_key': record.channelId,
          'item_key': '',
          'updated_at_ms': now,
          'origin_device_id': WebDavSyncLibraryMutation.originDeviceId,
          'normalized': 0,
          'deleted': 0,
          'aux': null,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
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

  Future<void> deleteChannel(
    String channelId, {
    WebDavSyncMutationOrigin origin = WebDavSyncMutationOrigin.user,
  }) async {
    await DebrifyTvDatabase.instance.runTxn((txn) async {
      final deleted = await txn.delete(
        'tv_channels',
        where: 'channel_id = ?',
        whereArgs: [channelId],
      );
      if (deleted != 0 && origin == WebDavSyncMutationOrigin.user) {
        await _writeChannelTombstone(txn, channelId);
        await _incrementWebDavSyncRevision(txn);
        await DebrifyTvDatabase.markWebDavTvChangesPending(txn);
      }
    });
  }

  Future<void> clearAll({
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
      await txn.delete('tv_channel_keywords');
      await txn.delete('tv_channels');
      if (channelIds.isNotEmpty) {
        final now = WebDavSyncLibraryMutation.nextTvStampMs();
        for (final channelId in channelIds) {
          await _writeChannelTombstone(txn, channelId, updatedAtMs: now);
        }
        await _incrementWebDavSyncRevision(txn);
        await DebrifyTvDatabase.markWebDavTvChangesPending(txn);
      }
    });
  }
}

Future<void> _writeChannelTombstone(
  DatabaseExecutor db,
  String channelId, {
  int? updatedAtMs,
}) => db.insert('webdav_sync_record_state', <String, Object?>{
  'kind': WebDavSyncLibraryKinds.tvChannels,
  'owner_key': channelId,
  'item_key': '',
  'updated_at_ms': updatedAtMs ?? WebDavSyncLibraryMutation.nextTvStampMs(),
  'origin_device_id': WebDavSyncLibraryMutation.originDeviceId,
  'normalized': 0,
  'deleted': 1,
  'aux': null,
}, conflictAlgorithm: ConflictAlgorithm.replace);

Future<void> _incrementWebDavSyncRevision(DatabaseExecutor db) => db.execute('''
  UPDATE webdav_sync_meta
  SET value = CAST(CAST(value AS INTEGER) + 1 AS TEXT)
  WHERE key = 'mutation_revision'
''');
