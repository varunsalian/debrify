import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../models/debrify_tv_cache.dart';
import '../../models/debrify_tv_channel_record.dart';
import '../debrify_tv_cache_service.dart';
import '../debrify_tv_database.dart';
import '../debrify_tv_repository.dart';

/// A channel header followed by streamed torrent records. No keyword-based
/// filtering and no all-pool YAML/JSON object on either device. Imports use one
/// transaction, so a failed/truncated file cannot replace a working channel.
class RemoteChannelFile {
  static const _format = 'debrify-channel-records-v1';
  static const _pageSize = 500;
  static const _maxLineBytes = 1024 * 1024;

  static Future<void> export(String channelId, File destination) async {
    await DebrifyTvDatabase.instance.runTxn((txn) async {
      final rows = await txn.query(
        'tv_channels',
        where: 'channel_id = ?',
        whereArgs: [channelId],
      );
      if (rows.length != 1) throw StateError('Channel no longer exists');
      final channel = rows.single;
      final keywords = await txn.query(
        'tv_channel_keywords',
        where: 'channel_id = ?',
        whereArgs: [channelId],
        orderBy: 'position',
      );
      final stats = await txn.query(
        'tv_keyword_stats',
        where: 'channel_id = ?',
        whereArgs: [channelId],
      );
      final count =
          (await txn.rawQuery(
                'SELECT COUNT(*) AS n FROM tv_cached_torrents WHERE channel_id = ?',
                [channelId],
              )).single['n']
              as int;
      final sink = destination.openWrite();
      final compressed = gzip.encoder.startChunkedConversion(sink);
      void line(Map<String, Object?> value) {
        final bytes = utf8.encode('${jsonEncode(value)}\n');
        if (bytes.length > _maxLineBytes) {
          throw const FormatException('Channel record too large');
        }
        compressed.add(bytes);
      }

      try {
        line({
          'format': _format,
          'name': channel['name'],
          'avoidNsfw': channel['avoid_nsfw'] == 1,
          'keywords': keywords.map((r) => r['keyword']).toList(),
          'stats': {
            for (final row in stats)
              row['keyword'] as String: {
                'totalFetched': row['total_fetched'],
                'lastSearchedAt': row['last_searched_at'],
                'pagesPulled': row['pages_pulled'],
                'pirateBayHits': row['pirate_bay_hits'],
              },
          },
          'count': count,
        });
        String? lastHash;
        while (true) {
          final page = await txn.query(
            'tv_cached_torrents',
            where: lastHash == null
                ? 'channel_id = ?'
                : 'channel_id = ? AND infohash > ?',
            whereArgs: [channelId, if (lastHash != null) lastHash],
            orderBy: 'infohash',
            limit: _pageSize,
          );
          if (page.isEmpty) break;
          for (final row in page) {
            line({
              ...row,
              'keywords': jsonDecode(row['keywords_json'] as String),
              'sources': jsonDecode(row['sources_json'] as String),
            });
          }
          lastHash = page.last['infohash'] as String;
          await sink.flush();
        }
      } finally {
        compressed.close();
        await sink.close();
      }
    });
  }

  static Stream<Map<String, dynamic>> _records(File file) async* {
    var pendingLineBytes = 0;
    final stream = file
        .openRead()
        .transform(gzip.decoder)
        .map((bytes) {
          for (final byte in bytes) {
            if (byte == 10) {
              pendingLineBytes = 0;
            } else if (++pendingLineBytes > _maxLineBytes) {
              throw const FormatException('Channel record too large');
            }
          }
          return bytes;
        })
        .transform(utf8.decoder)
        .transform(const LineSplitter());
    await for (final line in stream) {
      yield jsonDecode(line) as Map<String, dynamic>;
    }
  }

  static Future<String> import(File source) async {
    final records = StreamIterator(_records(source));
    try {
      if (!await records.moveNext()) {
        throw const FormatException('Missing channel header');
      }
      final header = records.current;
      final name = header['name'];
      final keywords = header['keywords'];
      final expected = header['count'];
      if (header['format'] != _format ||
          name is! String ||
          name.trim().isEmpty ||
          keywords is! List ||
          keywords.isEmpty ||
          keywords.any((k) => k is! String || k.trim().isEmpty) ||
          expected is! int ||
          expected < 0 ||
          header['avoidNsfw'] is! bool) {
        throw const FormatException('Invalid channel header');
      }
      final now = DateTime.now();
      await DebrifyTvDatabase.instance.runTxn((txn) async {
        // SQLite LOWER only folds ASCII. Match the existing Dart import's
        // Unicode behavior without loading channel pools or other metadata.
        final candidates = await txn.query(
          'tv_channels',
          columns: ['channel_id', 'created_at', 'name'],
        );
        final foldedName = name.toLowerCase();
        final existing = candidates
            .where((row) => (row['name'] as String).toLowerCase() == foldedName)
            .take(1)
            .toList();
        final channelId = existing.isEmpty
            ? now.microsecondsSinceEpoch.toString()
            : existing.single['channel_id'] as String;
        final record = DebrifyTvChannelRecord(
          channelId: channelId,
          name: name,
          keywords: List<String>.from(keywords),
          avoidNsfw: header['avoidNsfw'] as bool,
          channelNumber: 0,
          createdAt: existing.isEmpty
              ? now
              : DateTime.fromMillisecondsSinceEpoch(
                  existing.single['created_at'] as int,
                ),
          updatedAt: now,
        );
        await DebrifyTvRepository.instance.upsertChannel(
          record,
          transaction: txn,
        );
        Stream<CachedTorrent> torrents() async* {
          var count = 0;
          String? previous;
          while (await records.moveNext()) {
            final row = records.current;
            final hash = row['infohash'];
            if (hash is! String ||
                hash.isEmpty ||
                (previous != null && hash.compareTo(previous) <= 0) ||
                ++count > expected) {
              throw const FormatException(
                'Invalid or duplicate torrent record',
              );
            }
            previous = hash;
            yield CachedTorrent.fromJson(row);
          }
          if (count != expected) {
            throw const FormatException('Incomplete torrent pool');
          }
        }

        final rawStats = header['stats'] as Map<String, dynamic>;
        final entry = DebrifyTvChannelCacheEntry(
          version: 1,
          channelId: channelId,
          normalizedKeywords: record.keywords
              .map((k) => k.toLowerCase())
              .toList(),
          fetchedAt: now.millisecondsSinceEpoch,
          status: DebrifyTvCacheStatus.ready,
          errorMessage: null,
          torrents: const [],
          keywordStats: {
            for (final e in rawStats.entries)
              e.key: KeywordStat.fromJson(
                Map<String, dynamic>.from(e.value as Map),
              ),
          },
        );
        await DebrifyTvCacheService.saveEntry(
          entry,
          transaction: txn,
          torrentStream: torrents(),
        );
      });
      return name;
    } finally {
      await records.cancel();
    }
  }
}
