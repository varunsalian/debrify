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
      orderBy: 'channel_number ASC',
    );

    if (channels.isEmpty) {
      return const [];
    }

    // Load keywords for all channels
    final List<DebrifyTvChannelRecord> result = [];
    for (final row in channels) {
      final channelId = row['channel_id'] as String;
      final keywords = await fetchChannelKeywords(channelId);

      result.add(DebrifyTvChannelRecord(
        channelId: channelId,
        name: row['name'] as String,
        keywords: keywords,
        avoidNsfw: (row['avoid_nsfw'] as int? ?? 1) == 1,
        channelNumber: (row['channel_number'] as int? ?? 0),
        createdAt:
            DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int? ?? 0),
        updatedAt:
            DateTime.fromMillisecondsSinceEpoch(row['updated_at'] as int? ?? 0),
      ));
    }

    return result;
  }

  Future<List<String>> fetchChannelKeywords(String channelId) async {
    final db = await DebrifyTvDatabase.instance.database;
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

  Future<void> upsertChannel(DebrifyTvChannelRecord record) async {
    await DebrifyTvDatabase.instance.runTxn((txn) async {
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

      await txn.insert(
        'tv_channels',
        {
          'channel_id': record.channelId,
          'name': record.name,
          'avoid_nsfw': record.avoidNsfw ? 1 : 0,
          'channel_number': channelNumber,
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
