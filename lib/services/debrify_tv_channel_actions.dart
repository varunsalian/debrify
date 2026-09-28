import 'package:sqflite/sqflite.dart';
import '../models/debrify_tv_cache.dart';
import '../models/debrify_tv_channel_action.dart';
import '../models/debrify_tv_channel_record.dart';
import '../models/rd_torrent.dart';
import '../models/torrent.dart';
import '../models/torbox_torrent.dart';
import 'debrify_tv_database.dart';
import 'debrify_tv_cache_service.dart';
import 'debrify_tv_repository.dart';
import 'profiles/profile_runtime.dart';
import 'profiles/profile_session_memory.dart';

/// Channel actions retain their originating profile through picker callbacks.
/// A retired transaction rolls back channel/cache/sync metadata together.
class DebrifyTvChannelActions {
  const DebrifyTvChannelActions({
    required this.owner,
    required this.canContinue,
  });
  final ProfileSessionOwner owner;
  final bool Function() canContinue;
  bool get isCurrent =>
      owner == ProfileSessionMemory.captureOwner() && canContinue();
  void _check() {
    if (!isCurrent) {
      throw StateError('Channel action retired');
    }
  }

  Future<T> _owned<T>(Future<T> Function() action) async {
    _check();
    final scope = owner.scope;
    return scope == null
        ? ProfileRuntime.withoutCapturedScope(action)
        : ProfileRuntime.withCapturedScope(scope, action);
  }

  Future<void> _write(Future<void> Function(Transaction) action) =>
      DebrifyTvDatabase.instance.runTxn((txn) async {
        _check();
        await action(txn);
        _check();
      });

  Future<List<DebrifyTvChannelRecord>> loadChannels() => _owned(() async {
    final channels = await DebrifyTvRepository.instance.fetchAllChannels();
    _check();
    return channels;
  });

  Future<ChannelPickerResult> createChannel(
    String name,
    String searchKeyword, {
    bool Function()? canContinue,
  }) => _owned(() async {
    void checkPicker() {
      _check();
      if (canContinue?.call() == false) {
        throw StateError('Channel picker retired');
      }
    }

    checkPicker();
    final now = DateTime.now();
    final channelId = now.microsecondsSinceEpoch.toString();
    final channel = DebrifyTvChannelRecord(
      channelId: channelId,
      name: name,
      keywords: [searchKeyword],
      avoidNsfw: true,
      channelNumber: 0,
      createdAt: now,
      updatedAt: now,
    );
    final cacheEntry = DebrifyTvChannelCacheEntry.empty(
      channelId: channelId,
      normalizedKeywords: [searchKeyword.toLowerCase()],
      status: DebrifyTvCacheStatus.warming,
    );
    await _write((txn) async {
      checkPicker();
      await DebrifyTvRepository.instance.upsertChannel(
        channel,
        transaction: txn,
      );
      checkPicker();
      await DebrifyTvCacheService.saveEntry(cacheEntry, transaction: txn);
      checkPicker();
    });
    return ChannelPickerResult(
      channelId: channelId,
      channelName: name,
      isNewChannel: true,
    );
  });

  static List<Torrent> prepare(List<Torrent> torrents) {
    final supported = torrents
        .where(
          (torrent) =>
              !torrent.isDirectStream &&
              !torrent.isExternalStream &&
              torrent.infohash.trim().isNotEmpty,
        )
        .map(_normalizeTorrent)
        .toList();
    if (supported.isEmpty) {
      throw const DebrifyTvChannelAddException(
        'No supported torrents to add to channel',
      );
    }
    return supported;
  }

  Future<DebrifyTvChannelAddResult> add(
    ChannelPickerResult pickerResult,
    List<Torrent> filteredTorrents,
    String trimmedKeyword,
  ) => _owned(() async {
    final repo = DebrifyTvRepository.instance;
    final channels = await repo.fetchAllChannels();
    _check();
    final channel = channels.firstWhere(
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
    _check();
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

    final needsKeyword =
        hasKeyword &&
        !channelKeywords.any(
          (keyword) => keyword.toLowerCase() == normalizedKeyword,
        );
    if (needsKeyword) channelKeywords.add(effectiveKeyword);

    final updatedEntry = cacheEntry.copyWith(
      torrents: updatedTorrents,
      normalizedKeywords: channelKeywords
          .map((keyword) => keyword.toLowerCase())
          .toList(),
      status: DebrifyTvCacheStatus.ready,
    );
    await _write((txn) async {
      if (needsKeyword) {
        await repo.upsertChannel(
          channel.copyWith(
            keywords: channelKeywords,
            updatedAt: DateTime.now(),
          ),
          transaction: txn,
        );
      }
      _check();
      await DebrifyTvCacheService.saveEntry(updatedEntry, transaction: txn);
    });

    return DebrifyTvChannelAddResult(
      channelId: pickerResult.channelId,
      channelName: pickerResult.channelName,
      isNewChannel: pickerResult.isNewChannel,
      totalCount: filteredTorrents.length,
      addedCount: addedCount,
      updatedCount: updatedCount,
    );
  });

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
