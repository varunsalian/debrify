import 'dart:async';

import 'package:debrify/features/sources/application/source_candidate_checks.dart';
import 'package:debrify/features/sources/application/source_candidate_ranking.dart';
import 'package:debrify/models/quick_play_rules.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/services/iptv_source_search.dart';
import 'package:debrify/services/source_priority.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/utils/filter_ladder.dart';
import 'package:debrify/utils/rd_blocked_filter.dart';
import 'package:debrify/utils/torrent_curation.dart';
import 'package:flutter/foundation.dart';

final class SourceCuration {
  const SourceCuration._();

  /// Curate torrent candidates before probing, mirroring the old Home engine:
  ///   1. drop torrents whose name doesn't match the title (unrelated packs),
  ///   2. keep + relevance-sort by the requested episode/season,
  ///   3. when RD is the provider and the user's "skip blocked" setting is on,
  ///      drop RD-blocked-keyword torrents.
  /// Every step falls back to the pre-step list if it would empty the set, so
  /// curation can never turn a non-empty result into a "no sources" failure.
  static Future<List<Torrent>> curateCandidates(
    List<Torrent> torrents, {
    required String label,
    required bool isMovie,
    int? season,
    int? episode,
    required String provider,
  }) async {
    var out = torrents;

    // 1. Title match (skip when we have no label to match against).
    if (label.trim().isNotEmpty) {
      final matched = out
          .where((t) => torrentMatchesTitle(t.name, label))
          .toList();
      if (matched.isNotEmpty) out = matched;
    }

    // 2. Episode relevance filter + sort (no-op for movies / missing S-E).
    out = curateEpisodeCandidates(
      out,
      isSeries: !isMovie,
      season: season,
      episode: episode,
    );

    // 3. RD blocked-keyword filter (RD provider + setting enabled).
    if (provider == 'debrid' &&
        await StorageService.getRdSkipBlockedTorrents()) {
      final unblocked = out.where((t) => !isRdBlockedTorrent(t.name)).toList();
      if (unblocked.isNotEmpty) out = unblocked;
    }

    return out;
  }

  /// Pack candidates for the series auto-pin pack-first play: torrent-type
  /// sources whose name matches the title and whose coverage spans [season],
  /// widest coverage first (complete series → multi-season → season pack),
  /// then more seasons, then seeders. STRICT — no fall-back-to-unfiltered like
  /// [_curateCandidates]: a wrong pack here would get PINNED, so when nothing
  /// qualifies the caller falls back to the normal episode search instead.
  static Future<List<Torrent>> curatePackCandidates(
    List<Torrent> torrents, {
    required String label,
    required int season,
    required String provider,
    QuickPlayPackPreference preference = QuickPlayPackPreference.widestFirst,
  }) async {
    var out = torrents
        .where(
          (t) =>
              t.streamType == StreamType.torrent &&
              SourceCandidateChecks.hasAcquisition(t) &&
              t.infohash.isNotEmpty,
        )
        .toList();

    if (label.trim().isNotEmpty) {
      out = out.where((t) => torrentMatchesTitle(t.name, label)).toList();
    }

    bool coversSeason(Torrent t) {
      switch (t.coverageType) {
        case 'completeSeries':
          return true;
        case 'multiSeasonPack':
          if (t.startSeason != null && t.endSeason != null) {
            return t.startSeason! <= season && t.endSeason! >= season;
          }
          return true; // unknown range — the probe validates episode presence
        case 'seasonPack':
          return t.seasonNumber == season;
        default:
          return false; // singles/unknown → the episode fallback handles them
      }
    }

    out = out.where(coversSeason).toList();

    if (provider == 'debrid' &&
        await StorageService.getRdSkipBlockedTorrents()) {
      out = out.where((t) => !isRdBlockedTorrent(t.name)).toList();
    }

    int tier(Torrent t) {
      if (preference == QuickPlayPackPreference.seasonFirst) {
        switch (t.coverageType) {
          case 'seasonPack':
            return 0;
          case 'multiSeasonPack':
            return 1;
          default: // completeSeries
            return 2;
        }
      }
      switch (t.coverageType) {
        case 'completeSeries':
          return 0;
        case 'multiSeasonPack':
          return 1;
        default: // seasonPack
          return 2;
      }
    }

    out.sort((a, b) {
      final d = tier(a) - tier(b);
      if (d != 0) return d;
      final s = b.seasonCount.compareTo(a.seasonCount); // more seasons first
      if (s != 0) return s;
      return b.seeders.compareTo(a.seeders);
    });
    return out;
  }

  /// Select within a completed highest-priority addon batch only. Callers
  /// must establish that no pending provider can outrank this batch.
  @visibleForTesting
  static Torrent? earlyDirectCandidate(
    List<Torrent> batch, {
    required QuickPlayRules rules,
    FilterLadder? ladder,
  }) {
    if (!rules.allowDirectLinks ||
        !rules.tryNextOnFailure ||
        rules.maxAttempts < 2 ||
        rules.ranking != QuickPlayRanking.exactOrder ||
        // ignore: invalid_use_of_visible_for_testing_member
        SourceCandidateRanking.prefersTorrentCandidates(rules)) {
      return null;
    }
    final candidates =
        SourceCandidateRanking.orderCandidatesForRules(
          batch,
          rules: rules,
          ladder: ladder,
        ).where(
          (source) =>
              // ignore: invalid_use_of_visible_for_testing_member
              SourceCandidateRanking.isAutoPlayableCandidate(source) &&
              !IptvSourceSearch.isDeferredXtreamSeries(source),
        );
    if (candidates.isEmpty ||
        candidates.first.streamType != StreamType.directUrl) {
      return null;
    }
    return candidates.first;
  }

  /// A failed early direct launch consumes no debrid acquisition attempt.
  /// Leave candidate skipping and acquisition limits to [playBest]; slicing
  /// this list can hide a working direct link behind unusable torrent rows.
  @visibleForTesting
  static ({List<Torrent> sources, QuickPlayRules rules}) earlyDirectRecovery(
    List<Torrent> sources, {
    required Torrent failed,
    required QuickPlayRules rules,
  }) => (
    sources: sources
        .where(
          (t) =>
              SourceCandidateChecks.directValidationKey(t) !=
              SourceCandidateChecks.directValidationKey(failed),
        )
        .toList(),
    rules: rules,
  );

  /// Returns the configuration-specific key whose completed batch may launch
  /// before the rest of an exact-order addon search. A legacy name priority
  /// cannot distinguish duplicate configurations, so retain the old behavior
  /// of waiting for the full search until the user saves an explicit order.
  @visibleForTesting
  static String? leadingDirectAddonKey(
    List<StremioAddon> addons,
    List<String> priority,
  ) {
    // This shortcut sees only Stremio batches, not native-library/IPTV batches.
    // A saved native priority therefore requires the complete ordered search.
    if (priority.any(
      (key) => key.startsWith('iptv:') || key.startsWith('mediaserver:'),
    )) {
      return null;
    }
    if (addons.isEmpty) return null;
    final aliases = <String, String>{
      for (final addon in addons) addon.sourceKey: addon.legacySourceKey,
    };
    final ordered = SourcePriority.orderBy(
      addons,
      (addon) => addon.sourceKey,
      priority,
      aliases: aliases,
    );
    final first = ordered.first;
    if (ordered.where((addon) => addon.sourceKey == first.sourceKey).length !=
        1) {
      return null;
    }
    final duplicateLegacyName =
        ordered
            .where((addon) => addon.legacySourceKey == first.legacySourceKey)
            .length >
        1;
    if (duplicateLegacyName && !priority.contains(first.sourceKey)) {
      return null;
    }
    return first.sourceKey;
  }

  /// Search transports use either error map. Only direct-provider failures
  /// should trigger this path's retry/connection feedback, not torrent engines.
  @visibleForTesting
  static Map<String, String> directSearchErrors(Map<String, dynamic> result) {
    final errors = <String, String>{
      ...?(result['engineErrors'] as Map?)?.cast<String, String>(),
      ...?(result['addonErrors'] as Map?)?.cast<String, String>(),
    };
    return {
      for (final entry in errors.entries)
        if (entry.key.startsWith('stremio:') ||
            entry.key.startsWith('mediaserver:'))
          entry.key: entry.value,
    };
  }
}
