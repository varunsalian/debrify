import 'package:flutter/material.dart';

import '../models/debrify_tv_cache.dart';
import '../models/rd_torrent.dart';
import '../models/torrent.dart';
import '../models/torbox_torrent.dart';
import '../widgets/channel_picker_dialog.dart';
import 'debrify_tv_cache_service.dart';
import 'debrify_tv_repository.dart';

class DebrifyTvChannelAddException implements Exception {
  const DebrifyTvChannelAddException(this.message);

  final String message;

  @override
  String toString() => message;
}

class DebrifyTvChannelAddResult {
  const DebrifyTvChannelAddResult({
    required this.channelId,
    required this.channelName,
    required this.isNewChannel,
    required this.totalCount,
    required this.addedCount,
    required this.updatedCount,
  });

  final String channelId;
  final String channelName;
  final bool isNewChannel;
  final int totalCount;
  final int addedCount;
  final int updatedCount;

  String get successMessage {
    final noun = totalCount == 1 ? '1 torrent' : '$totalCount torrents';
    if (isNewChannel) {
      return 'Channel "$channelName" created with $noun';
    }
    if (addedCount == 0) {
      final updatedNoun = updatedCount == 1
          ? 'Torrent'
          : '$updatedCount torrents';
      return '$updatedNoun updated in "$channelName"';
    }
    return '$noun added to "$channelName"';
  }
}

class DebrifyTvChannelAddService {
  const DebrifyTvChannelAddService._();

  static Future<DebrifyTvChannelAddResult?> addTorrentsToChannel(
    BuildContext context, {
    required List<Torrent> torrents,
    required String searchKeyword,
  }) async {
    final trimmedKeyword = searchKeyword.trim();

    final filteredTorrents = torrents
        .where(
          (torrent) =>
              !torrent.isDirectStream &&
              !torrent.isExternalStream &&
              torrent.infohash.trim().isNotEmpty,
        )
        .map(_normalizeTorrent)
        .toList();
    if (filteredTorrents.isEmpty) {
      throw const DebrifyTvChannelAddException(
        'No supported torrents to add to channel',
      );
    }

    final pickerResult = await showDialog<ChannelPickerResult>(
      context: context,
      builder: (ctx) => ChannelPickerDialog(searchKeyword: trimmedKeyword),
    );

    if (pickerResult == null || !context.mounted) {
      return null;
    }

    final repo = DebrifyTvRepository.instance;
    final channel = (await repo.fetchAllChannels()).firstWhere(
      (ch) => ch.channelId == pickerResult.channelId,
      orElse: () =>
          throw const DebrifyTvChannelAddException('Channel no longer exists'),
    );

    final sanitizedChannelKeywords = channel.keywords
        .map((keyword) => keyword.trim())
        .where((keyword) => keyword.isNotEmpty)
        .toList();

    var cacheEntry = await DebrifyTvCacheService.getEntry(
      pickerResult.channelId,
    );
    cacheEntry ??= DebrifyTvChannelCacheEntry.empty(
      channelId: pickerResult.channelId,
      normalizedKeywords: sanitizedChannelKeywords
          .map((keyword) => keyword.toLowerCase())
          .toList(),
      status: DebrifyTvCacheStatus.warming,
    );

    final channelKeywords = List<String>.from(sanitizedChannelKeywords);
    final String effectiveKeyword;
    if (trimmedKeyword.isNotEmpty) {
      effectiveKeyword = trimmedKeyword;
    } else if (channelKeywords.isNotEmpty) {
      effectiveKeyword = channelKeywords.first;
    } else {
      effectiveKeyword = pickerResult.channelName.trim();
    }

    final normalizedKeyword = effectiveKeyword.toLowerCase();
    final hasKeyword = normalizedKeyword.isNotEmpty;
    final keywordPayload = hasKeyword
        ? <String>[normalizedKeyword]
        : const <String>[];

    final updatedTorrents = List<CachedTorrent>.from(cacheEntry.torrents);
    final infohashIndex = <String, int>{
      for (var i = 0; i < updatedTorrents.length; i++)
        updatedTorrents[i].infohash.trim().toLowerCase(): i,
    };
    final newTorrents = <CachedTorrent>[];
    var addedCount = 0;
    var updatedCount = 0;

    for (final torrent in filteredTorrents) {
      final sourcePayload = torrent.source.isNotEmpty
          ? <String>[torrent.source]
          : const <String>[];
      final cachedTorrent = CachedTorrent.fromTorrent(
        torrent,
        keywords: keywordPayload,
        sources: sourcePayload,
      );

      final existingIndex = infohashIndex[cachedTorrent.infohash];
      if (existingIndex == null) {
        newTorrents.add(cachedTorrent);
        infohashIndex[cachedTorrent.infohash] = -1;
        addedCount++;
      } else if (existingIndex >= 0) {
        updatedTorrents[existingIndex] = updatedTorrents[existingIndex].merge(
          keywords: keywordPayload,
          sources: sourcePayload,
        );
        infohashIndex[cachedTorrent.infohash] = -1;
        updatedCount++;
      }
    }

    if (newTorrents.isNotEmpty) {
      updatedTorrents.insertAll(0, newTorrents);
    }

    if (hasKeyword) {
      final keywordExists = channelKeywords.any(
        (keyword) => keyword.toLowerCase() == normalizedKeyword,
      );
      if (!keywordExists) {
        channelKeywords.add(effectiveKeyword);
        await repo.upsertChannel(
          channel.copyWith(
            keywords: channelKeywords,
            updatedAt: DateTime.now(),
          ),
        );
      }
    }

    final updatedEntry = cacheEntry.copyWith(
      torrents: updatedTorrents,
      normalizedKeywords: channelKeywords
          .map((keyword) => keyword.toLowerCase())
          .toList(),
      status: DebrifyTvCacheStatus.ready,
    );
    await DebrifyTvCacheService.saveEntry(updatedEntry);

    return DebrifyTvChannelAddResult(
      channelId: pickerResult.channelId,
      channelName: pickerResult.channelName,
      isNewChannel: pickerResult.isNewChannel,
      totalCount: filteredTorrents.length,
      addedCount: addedCount,
      updatedCount: updatedCount,
    );
  }

  static Torrent fromRealDebridTorrent(RDTorrent torrent) {
    return Torrent(
      rowid: 0,
      infohash: torrent.hash.trim().toLowerCase(),
      name: torrent.filename.trim().isNotEmpty
          ? torrent.filename.trim()
          : torrent.hash,
      sizeBytes: torrent.bytes,
      createdUnix: _dateStringToUnix(torrent.added),
      seeders: torrent.seeders ?? 0,
      leechers: 0,
      completed: 0,
      scrapedDate: _nowUnix(),
      source: 'real_debrid',
    );
  }

  static Torrent fromTorboxTorrent(TorboxTorrent torrent) {
    return Torrent(
      rowid: torrent.id,
      infohash: torrent.hash.trim().toLowerCase(),
      name: torrent.name.trim().isNotEmpty ? torrent.name.trim() : torrent.hash,
      sizeBytes: torrent.size,
      createdUnix: torrent.createdAt.millisecondsSinceEpoch ~/ 1000,
      seeders: torrent.seeds,
      leechers: torrent.peers,
      completed: 0,
      scrapedDate: torrent.updatedAt.millisecondsSinceEpoch ~/ 1000,
      source: 'torbox',
    );
  }

  static Torrent _normalizeTorrent(Torrent torrent) {
    return Torrent(
      rowid: torrent.rowid,
      infohash: torrent.infohash.trim().toLowerCase(),
      name: torrent.name,
      sizeBytes: torrent.sizeBytes,
      createdUnix: torrent.createdUnix,
      seeders: torrent.seeders,
      leechers: torrent.leechers,
      completed: torrent.completed,
      scrapedDate: torrent.scrapedDate,
      category: torrent.category,
      source: torrent.source,
      streamType: torrent.streamType,
      directUrl: torrent.directUrl,
      magnetUrl: torrent.magnetUrl,
      torrentUrl: torrent.torrentUrl,
      hasRealInfoHash: torrent.hasRealInfoHash,
      coverageType: torrent.coverageType,
      startSeason: torrent.startSeason,
      endSeason: torrent.endSeason,
      seasonNumber: torrent.seasonNumber,
      transformedTitle: torrent.transformedTitle,
      episodeIdentifier: torrent.episodeIdentifier,
    );
  }

  static int _dateStringToUnix(String value) {
    if (value.trim().isEmpty) {
      return _nowUnix();
    }
    final parsed = DateTime.tryParse(value);
    if (parsed == null) {
      return _nowUnix();
    }
    return parsed.millisecondsSinceEpoch ~/ 1000;
  }

  static int _nowUnix() => DateTime.now().millisecondsSinceEpoch ~/ 1000;
}
