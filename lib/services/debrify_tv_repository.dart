import 'package:sqflite/sqflite.dart';

import '../models/debrify_tv_cache.dart';
import '../models/debrify_tv_channel_record.dart';
import 'debrify_tv_database.dart';

class DebrifyTvRepository {
  DebrifyTvRepository._();

  static final DebrifyTvRepository instance = DebrifyTvRepository._();

  Future<List<DebrifyTvChannelRecord>> fetchAllChannels() async {
    final db = await DebrifyTvDatabase.instance.database;

    final channels = await db.query(
      'tv_channels',
      orderBy: 'updated_at DESC',
    );

    if (channels.isEmpty) {
      return const [];
    }

    final keywordRows = await db.query(
      'tv_channel_keywords',
      orderBy: 'channel_id ASC, position ASC',
    );

    final Map<String, List<String>> keywordMap = {};
    for (final row in keywordRows) {
      final channelId = row['channel_id'] as String;
      final keyword = row['keyword'] as String;
      keywordMap.putIfAbsent(channelId, () => <String>[]).add(keyword);
    }

    return channels.map((row) {
      final channelId = row['channel_id'] as String;
      return DebrifyTvChannelRecord(
        channelId: channelId,
        name: row['name'] as String,
        keywords: keywordMap[channelId] ?? const <String>[],
        avoidNsfw: (row['avoid_nsfw'] as int? ?? 1) == 1,
        createdAt:
            DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int? ?? 0),
        updatedAt:
            DateTime.fromMillisecondsSinceEpoch(row['updated_at'] as int? ?? 0),
      );
    }).toList();
  }

  Future<void> upsertChannel(DebrifyTvChannelRecord record) async {
    await DebrifyTvDatabase.instance.runTxn((txn) async {
      await txn.insert(
        'tv_channels',
        {
          'channel_id': record.channelId,
          'name': record.name,
          'avoid_nsfw': record.avoidNsfw ? 1 : 0,
          'created_at': record.createdAt.millisecondsSinceEpoch,
          'updated_at': record.updatedAt.millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      await txn.delete(
        'tv_channel_keywords',
        where: 'channel_id = ?',
        whereArgs: [record.channelId],
      );

      for (var i = 0; i < record.keywords.length; i++) {
        await txn.insert(
          'tv_channel_keywords',
          {
            'channel_id': record.channelId,
            'position': i,
            'keyword': record.keywords[i],
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      await txn.insert(
        'tv_channel_cache_state',
        {
          'channel_id': record.channelId,
          'status': DebrifyTvCacheStatus.warming,
          'error_message': null,
          'fetched_at': 0,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }

  Future<void> deleteChannel(String channelId) async {
    await DebrifyTvDatabase.instance.runTxn((txn) async {
      await txn.delete(
        'tv_channels',
        where: 'channel_id = ?',
        whereArgs: [channelId],
      );
    });
  }

  Future<void> clearAll() async {
    await DebrifyTvDatabase.instance.runTxn((txn) async {
      await txn.delete('tv_cached_torrents');
      await txn.delete('tv_keyword_stats');
      await txn.delete('tv_channel_keywords');
      await txn.delete('tv_channels');
    });
  }
}
