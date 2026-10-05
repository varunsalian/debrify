import 'dart:async';

import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_bindings.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_owners.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_sections.dart';
import 'package:debrify/models/debrify_tv/cache_results.dart';
import 'package:debrify/models/debrify_tv/channel.dart';
import 'package:debrify/models/debrify_tv_cache.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/services/engine/dynamic_engine.dart';
import 'package:debrify/services/engine/engine_registry.dart';
import 'package:debrify/utils/nsfw_filter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class _TvEngineWarmResult {
  final DynamicEngine engine;
  final List<Torrent> torrents;
  final int pagesPulled;
  final String? failureMessage;

  const _TvEngineWarmResult({
    required this.engine,
    required this.torrents,
    required this.pagesPulled,
    this.failureMessage,
  });
}

class DebrifyTvChannelWarmup {
  final DebrifyTvDependencies _deps;
  DebrifyTvChannelWarmup(this._deps);
  DebrifyTvOwners get _owners => _deps.owners;
  DebrifyTvSections get _sections => _deps.sections;

  void _accumulateCachedTorrent({
    required Map<String, CachedTorrent> accumulator,
    required String infohash,
    required Torrent torrent,
    required String keyword,
    required String source,
  }) {
    if (infohash.isEmpty) {
      return;
    }
    final normalizedKeyword = keyword.toLowerCase();
    final normalizedSource = source.toLowerCase();
    final existing = accumulator[infohash];
    if (existing == null) {
      accumulator[infohash] = CachedTorrent.fromTorrent(
        torrent,
        keywords: [normalizedKeyword],
        sources: [normalizedSource],
      );
      return;
    }

    final shouldOverride = torrent.seeders > existing.seeders;
    accumulator[infohash] = existing.merge(
      keywords: [normalizedKeyword],
      sources: [normalizedSource],
      override: shouldOverride ? torrent : null,
    );
  }

  List<CachedTorrent> _sortedCachedTorrents(
    Map<String, CachedTorrent> accumulator,
  ) {
    final list = accumulator.values.toList();
    list.sort((a, b) {
      final seedCompare = b.seeders.compareTo(a.seeders);
      if (seedCompare != 0) {
        return seedCompare;
      }
      return b.completed.compareTo(a.completed);
    });
    return list;
  }

  Future<DebrifyTvChannelCacheEntry> computeChannelCacheEntry(
    DebrifyTvChannel channel,
    List<String> normalizedKeywords, {
    DebrifyTvChannelCacheEntry? baseline,
    Set<String>? keywordsToSearch,
  }) async {
    // The channel's own NSFW setting, FLOORED by the viewer: filtering is
    // role-locked for a child profile no matter who authored the channel or
    // what its stored flag says (the rail is viewer-scoped, evaluated at
    // search/play — never only at creation).
    final channelAvoidNsfw =
        channel.avoidNsfw || _owners.settings.viewerForcesNsfw;
    final registry = EngineRegistry.instance;
    await registry.initialize();
    final enabledTvEngines = _sections.engines.enabledTvKeywordEngines(
      registry,
    );
    final now = DateTime.now().millisecondsSinceEpoch;

    final accumulator = <String, CachedTorrent>{};
    final stats = <String, KeywordStat>{};

    if (baseline != null) {
      for (final cached in _sections.warmup._filterCachedTorrentsForKeywords(
        baseline,
        normalizedKeywords,
      )) {
        final normalizedHash = _sections.filters.normalizeInfohash(
          cached.infohash,
        );
        if (normalizedHash.isEmpty) {
          continue;
        }
        accumulator[normalizedHash] = cached;
      }
      stats.addAll(
        _sections.warmup._filterKeywordStats(
          baseline.keywordStats,
          normalizedKeywords,
        ),
      );
      debugPrint(
        'DebrifyTV: Starting incremental warm for "${channel.name}" – seeded cache with ${accumulator.length} torrent(s).',
      );
    }

    final Set<String> keywordsToWarm = keywordsToSearch != null
        ? keywordsToSearch.map((kw) => kw.toLowerCase()).toSet()
        : normalizedKeywords.toSet();

    if (keywordsToWarm.isEmpty) {
      debugPrint('DebrifyTV: No keywords to warm for "${channel.name}".');
    }
    if (enabledTvEngines.isEmpty && keywordsToWarm.isNotEmpty) {
      debugPrint(
        'DebrifyTV: No enabled TV search engines for "${channel.name}".',
      );
    }

    bool anySuccess = accumulator.isNotEmpty;
    String? failureMessage;

    List<String> pendingKeywords = List<String>.from(keywordsToWarm);
    while (pendingKeywords.isNotEmpty) {
      final batch = pendingKeywords
          .take(_owners.settings.channelBatchSize)
          .toList();
      pendingKeywords = pendingKeywords.skip(batch.length).toList();

      final futures = batch.map((keyword) async {
        return await _sections.warmup._warmKeyword(
          keyword: keyword,
          enabledEngines: enabledTvEngines,
          accumulator: accumulator,
          stats: stats,
          now: now,
          totalKeywords: normalizedKeywords.length,
          avoidNsfw: channelAvoidNsfw, // Use channel's NSFW setting
          minTorrentsPerKeyword: _owners.settings.minTorrentsPerKeyword,
        );
      }).toList();

      final results = await Future.wait(futures);

      for (final result in results) {
        if (result == null) {
          continue;
        }
        final keyword = result.keyword;
        debugPrint(
          'DebrifyTV: Warmed keyword "$keyword" – added ${result.addedHashes.length} new torrent(s).',
        );
        anySuccess = anySuccess || result.addedHashes.isNotEmpty;
        stats[keyword] = result.stat;
        failureMessage ??= result.failureMessage;
      }
    }

    if (keywordsToWarm.isEmpty) {
      anySuccess = accumulator.isNotEmpty;
    }

    if (anySuccess) {
      return DebrifyTvChannelCacheEntry(
        version: 1,
        channelId: channel.id,
        normalizedKeywords: normalizedKeywords,
        fetchedAt: DateTime.now().millisecondsSinceEpoch,
        status: DebrifyTvCacheStatus.ready,
        errorMessage: null,
        torrents: _sections.warmup._sortedCachedTorrents(accumulator),
        keywordStats: Map<String, KeywordStat>.from(stats),
      );
    }

    failureMessage ??= 'No torrents found for these keywords yet.';
    return DebrifyTvChannelCacheEntry(
      version: 1,
      channelId: channel.id,
      normalizedKeywords: normalizedKeywords,
      fetchedAt: DateTime.now().millisecondsSinceEpoch,
      status: DebrifyTvCacheStatus.failed,
      errorMessage: failureMessage,
      torrents: const <CachedTorrent>[],
      keywordStats: Map<String, KeywordStat>.from(stats),
    );
  }

  Future<KeywordWarmResult?> _warmKeyword({
    required String keyword,
    required List<DynamicEngine> enabledEngines,
    required Map<String, CachedTorrent> accumulator,
    required Map<String, KeywordStat> stats,
    required int now,
    required int totalKeywords,
    required bool avoidNsfw, // Use channel's NSFW setting
    required int minTorrentsPerKeyword,
  }) async {
    final searchResults = await Future.wait(
      enabledEngines.map((engine) async {
        final maxResults = _sections.engines.tvChannelMaxResultsForEngine(
          engine,
          totalKeywords,
        );
        try {
          final torrents = await engine.executeSearch(
            query: keyword,
            maxResults: maxResults,
          );
          return _TvEngineWarmResult(
            engine: engine,
            torrents: torrents,
            pagesPulled: _sections.engines.estimatePagesPulledForEngine(
              engine,
              torrents.length,
            ),
          );
        } catch (e) {
          debugPrint(
            'DebrifyTV: Cache warm ${engine.displayName} failed for "$keyword": $e',
          );
          return _TvEngineWarmResult(
            engine: engine,
            torrents: const <Torrent>[],
            pagesPulled: 0,
            failureMessage:
                '${engine.displayName} search failed. Some torrents may be missing.',
          );
        }
      }),
    );

    // Apply NSFW filter to search results before caching
    final filteredByEngine = <DynamicEngine, List<Torrent>>{};
    int totalBefore = 0;
    int totalAfter = 0;
    int pagesPulled = 0;
    final failureMessages = <String>[];

    for (final result in searchResults) {
      pagesPulled += result.pagesPulled;
      if (result.failureMessage != null) {
        failureMessages.add(result.failureMessage!);
      }

      final before = result.torrents.length;
      totalBefore += before;
      if (avoidNsfw) {
        final filtered = result.torrents.where((torrent) {
          if (NsfwFilter.shouldFilter(torrent.category, torrent.name)) {
            return false;
          }
          return true;
        }).toList();
        totalAfter += filtered.length;
        filteredByEngine[result.engine] = filtered;
      } else {
        totalAfter += before;
        filteredByEngine[result.engine] = result.torrents;
      }
    }

    if (avoidNsfw && totalBefore != totalAfter) {
      debugPrint(
        'DebrifyTV: Cache NSFW filter for "$keyword": $totalBefore → $totalAfter torrents',
      );
    }

    // Check minimum torrents per keyword threshold
    final totalTorrents = filteredByEngine.values.fold<int>(
      0,
      (total, torrents) => total + torrents.length,
    );
    if (totalTorrents < minTorrentsPerKeyword) {
      debugPrint(
        'DebrifyTV: Skipping keyword "$keyword" – only $totalTorrents torrent(s), minimum is $minTorrentsPerKeyword',
      );
      final stat = (stats[keyword] ?? KeywordStat.initial())
          .copyWith(
            totalFetched: 0,
            lastSearchedAt: now,
            pagesPulled: pagesPulled,
          )
          .clearLegacySourceHits();
      return KeywordWarmResult(
        keyword: keyword,
        addedHashes: const <String>{},
        stat: stat,
        failureMessage: enabledEngines.isEmpty
            ? 'No enabled TV search engines.'
            : 'Too few torrents for "$keyword" (found $totalTorrents, need $minTorrentsPerKeyword)',
      );
    }

    final keywordHashes = <String>{};

    for (final entry in filteredByEngine.entries) {
      final source = entry.key.name;
      for (final torrent in entry.value) {
        final hash = _sections.filters.normalizeInfohash(torrent.infohash);
        if (hash.isEmpty) {
          continue;
        }
        keywordHashes.add(hash);
        _sections.warmup._accumulateCachedTorrent(
          accumulator: accumulator,
          infohash: hash,
          torrent: torrent,
          keyword: keyword,
          source: source,
        );
      }
    }

    final updatedStats = stats[keyword] ?? KeywordStat.initial();
    final stat = updatedStats
        .copyWith(
          totalFetched: keywordHashes.length,
          lastSearchedAt: now,
          pagesPulled: pagesPulled,
        )
        .clearLegacySourceHits();

    String? failureMessage;
    if (failureMessages.isNotEmpty) {
      failureMessage = failureMessages.first;
    } else if (filteredByEngine.values.every((torrents) => torrents.isEmpty)) {
      failureMessage = 'No torrents found for "$keyword" yet.';
    }

    return KeywordWarmResult(
      keyword: keyword,
      addedHashes: keywordHashes,
      stat: stat,
      failureMessage: failureMessage,
    );
  }

  List<CachedTorrent> _filterCachedTorrentsForKeywords(
    DebrifyTvChannelCacheEntry entry,
    List<String> normalizedKeywords,
  ) {
    if (entry.torrents.isEmpty) {
      return const <CachedTorrent>[];
    }
    final allowed = normalizedKeywords.toSet();
    final filtered = <CachedTorrent>[];
    for (final cached in entry.torrents) {
      final matching = cached.keywords.where(allowed.contains).toList();
      if (matching.isEmpty) {
        continue;
      }
      filtered.add(cached.merge(keywords: matching));
    }
    return filtered;
  }

  Map<String, KeywordStat> _filterKeywordStats(
    Map<String, KeywordStat> stats,
    List<String> normalizedKeywords,
  ) {
    if (stats.isEmpty) {
      return const <String, KeywordStat>{};
    }
    final allowed = normalizedKeywords.toSet();
    final filtered = <String, KeywordStat>{};
    for (final entry in stats.entries) {
      if (allowed.contains(entry.key)) {
        filtered[entry.key] = entry.value;
      }
    }
    return filtered;
  }
}
