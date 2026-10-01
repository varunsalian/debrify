import 'dart:async';

import 'package:debrify/features/sources/application/source_candidate_checks.dart';
import 'package:debrify/models/quick_play_rules.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/services/iptv_source_search.dart';
import 'package:debrify/services/media_server_service.dart';
import 'package:debrify/services/source_priority.dart';
import 'package:debrify/services/startup_stream_policy.dart';
import 'package:debrify/utils/filter_ladder.dart';
import 'package:flutter/foundation.dart';

final class SourceCandidateRanking {
  const SourceCandidateRanking._();

  static int _qualityScore(Torrent torrent) {
    final name = torrent.name.toLowerCase();
    if (RegExp(r'\b(4320p|8k)\b').hasMatch(name)) return 5;
    if (RegExp(r'\b(2160p|4k|uhd)\b').hasMatch(name)) return 4;
    if (RegExp(r'\b(1080p|1080i|fhd)\b').hasMatch(name)) return 3;
    if (RegExp(r'\b(720p|720i|hd)\b').hasMatch(name)) return 2;
    if (RegExp(r'\b(480p|576p|sd)\b').hasMatch(name)) return 1;
    return 0;
  }

  /// Applies only the ordering/filtering explicitly selected by [rules].
  static List<Torrent> orderCandidatesForRules(
    List<Torrent> torrents, {
    required QuickPlayRules rules,
    FilterLadder? ladder,
  }) {
    var out = rules.allowDirectLinks
        ? List<Torrent>.from(torrents)
        : torrents.where((t) => t.streamType != StreamType.directUrl).toList();

    int compare(Torrent a, Torrent b) {
      switch (rules.ranking) {
        case QuickPlayRanking.debrify:
        case QuickPlayRanking.exactOrder:
          return 0;
        case QuickPlayRanking.quality:
          final q = _qualityScore(b).compareTo(_qualityScore(a));
          if (q != 0) return q;
          return b.seeders.compareTo(a.seeders);
        case QuickPlayRanking.smallest:
          if (a.sizeBytes == 0 && b.sizeBytes != 0) return 1;
          if (b.sizeBytes == 0 && a.sizeBytes != 0) return -1;
          return a.sizeBytes.compareTo(b.sizeBytes);
        case QuickPlayRanking.readyFirst:
          final ad = a.streamType == StreamType.directUrl ? 0 : 1;
          final bd = b.streamType == StreamType.directUrl ? 0 : 1;
          final d = ad.compareTo(bd);
          return d != 0 ? d : b.seeders.compareTo(a.seeders);
      }
    }

    if (rules.ranking != QuickPlayRanking.debrify &&
        rules.ranking != QuickPlayRanking.exactOrder) {
      // Dart's List.sort isn't documented stable. Carry original positions so
      // equal-ranked addon/engine results never shuffle unexpectedly.
      final indexed = out.indexed.toList();
      indexed.sort((a, b) {
        final d = compare(a.$2, b.$2);
        return d != 0 ? d : a.$1.compareTo(b.$1);
      });
      out = indexed.map((e) => e.$2).toList();
    }

    // Addon Priority is one flat order across engines and streaming addons.
    // With an empty saved list, the combined search's shipped provider order
    // remains intact.
    out = SourcePriority.order(
      out,
      rules.sourcePriority,
      aliases: _sourceAliases,
    );

    if (ladder != null && ladder.isActive) {
      if (!rules.relaxFilters) {
        // Filter before dedupe: two providers may describe the same hash
        // differently, and an ineligible higher-priority representation must
        // not erase an eligible lower-priority one.
        out = out.where((t) => ladder.tierOf(t) == 0).toList();
      } else if (rules.ranking == QuickPlayRanking.exactOrder) {
        // Addon Priority remains primary. Within each provider, prefer the
        // strongest filter tier while retaining non-matches as fallbacks.
        // With no active ladder this branch is skipped, preserving the exact
        // response order the provider returned.
        final providerOrder = <String>[];
        final byProvider = <String, List<Torrent>>{};
        for (final torrent in out) {
          final key = SourcePriority.keyForSource(
            torrent.source,
            aliases: _sourceAliases,
          );
          if (!byProvider.containsKey(key)) providerOrder.add(key);
          byProvider.putIfAbsent(key, () => <Torrent>[]).add(torrent);
        }
        out = [
          for (final key in providerOrder) ...ladder.order(byProvider[key]!),
        ];
      } else {
        // Stable ladder ordering makes filters primary while preserving the
        // selected ranking inside each tier.
        out = ladder.order(out);
      }
    }

    // Stable dedupe happens after strict eligibility is known. In relaxed or
    // unfiltered modes, the earlier provider still owns a shared hash.
    out = SourcePriority.dedupe(out);

    // "Prefer torrents" is a transport preference, not an engine/addon
    // preference. Walk every provider's torrent rows in Addon Priority order;
    // only after no torrent works do direct/external rows become fallbacks.
    // Turning it off leaves each provider's filter-adjusted transport order.
    if (rules.ranking == QuickPlayRanking.exactOrder &&
        prefersTorrentCandidates(rules)) {
      out = [
        ...out.where((t) => t.streamType == StreamType.torrent),
        ...out.where((t) => t.streamType != StreamType.torrent),
      ];
    }
    return out;
  }

  /// Replace only torrent/acquisition slots with [preparedTorrents]. Direct
  /// and external rows retain their exact positions. This lets cache checks
  /// and episode-pack safety reorder the torrent walk without silently
  /// changing the user's transport order when "Prefer torrents" is off.
  @visibleForTesting
  static List<Torrent> mergePreparedTorrentOrder(
    List<Torrent> sources,
    List<Torrent> preparedTorrents,
  ) {
    var nextTorrent = 0;
    return [
      for (final source in sources)
        if (source.streamType == StreamType.torrent &&
            SourceCandidateChecks.hasAcquisition(source))
          preparedTorrents[nextTorrent++]
        else
          source,
    ];
  }

  /// Maps legacy/display source identities back to stable priority entries.
  /// The async flows
  /// AWAIT [warmSourceAliases] before ordering (a sync getter alone would
  /// leave the first playback after startup alias-less, silently ignoring an
  /// indexer-manager row's position in the priority list).
  static Map<String, String>? _cachedSourceAliases;
  static Future<void>? _sourceAliasWarmup;

  static Map<String, String> get _sourceAliases =>
      _cachedSourceAliases ?? const {};

  /// Resolves once the alias map is loaded. Single-flight, but NOT memoized
  /// forever: each prioritized play re-reads (cheap — the engine registry is
  /// cached and indexer configs are a prefs read), so adding or renaming an
  /// indexer manager mid-session is picked up on the next play, not the next
  /// app restart.
  static Future<void> warmSourceAliases() {
    final inFlight = _sourceAliasWarmup;
    if (inFlight != null) return inFlight;
    final run = SourcePriority.sourceAliases()
        .then((m) {
          _cachedSourceAliases = m;
        })
        .catchError((_) {
          _cachedSourceAliases ??= const <String, String>{};
        })
        .whenComplete(() {
          _sourceAliasWarmup = null;
        });
    _sourceAliasWarmup = run;
    return run;
  }

  /// Restores rule/filter ordering after `_cacheFirst` has stably partitioned
  /// cached hits ahead of misses. `readyFirst` treats that partition as the
  /// primary readiness signal, so only the filter ladder may group it further;
  /// sorting by seeders again would incorrectly promote an uncached torrent.
  @visibleForTesting
  static List<Torrent> orderCacheCheckedCandidatesForRules(
    List<Torrent> torrents, {
    required QuickPlayRules rules,
    FilterLadder? ladder,
  }) {
    // Exact-order candidates were already provider/filter ordered before the
    // cache lookup. `_cacheFirst` is a stable partition, so retaining its
    // output makes cached availability primary without scrambling either the
    // cached or uncached half.
    if (rules.ranking == QuickPlayRanking.exactOrder) {
      return List<Torrent>.from(torrents);
    }
    if (rules.ranking != QuickPlayRanking.readyFirst) {
      return orderCandidatesForRules(torrents, rules: rules, ladder: ladder);
    }

    var out = List<Torrent>.from(torrents);
    if (ladder != null && ladder.isActive) {
      out = rules.relaxFilters
          ? ladder.order(out)
          : out.where((t) => ladder.tierOf(t) == 0).toList();
    }
    return out;
  }

  /// Direct-link validation historically inspected five links regardless of
  /// the torrent retry preference. Keep those independent: migrating a legacy
  /// retry count must not change direct-link behavior.
  static int directValidationBudgetForRules(QuickPlayRules? _) => 5;

  /// Whether a direct stream may safely be touched by Dart before the player.
  ///
  /// IPTV providers commonly reject HEAD while serving the same URL to a real
  /// media client. Let the decoder-backed startup gate validate those streams.
  /// Keep the AIOStreams policy on source provenance as well as hostname: its
  /// final CDN host may no longer identify the link as an IP-bound proxy.
  static bool shouldPreflightDirectStream(Torrent torrent) {
    return !IptvSourceSearch.owns(torrent) &&
        !MediaServerService.owns(torrent) &&
        !StartupStreamPolicy.isAioStreams(
          addonId: torrent.stremioAddonId,
          sourceName: torrent.source,
          url: torrent.directUrl,
        );
  }

  /// Whether direct-addon rows should be attempted before torrent acquisition.
  /// A torrent-first source plan tries the torrent twin first and retains the
  /// direct row as the existing no-provider/dead-end rescue.
  @visibleForTesting
  static bool shouldTryDirectBeforeTorrent(QuickPlayRules? rules) =>
      rules?.sourceMode != QuickPlaySourceMode.torrentsThenAddons &&
      rules?.sourceMode != QuickPlaySourceMode.torrentsOnly;

  /// Whether Quick Play should exhaust provider-ordered torrent candidates
  /// before falling back to direct links.
  @visibleForTesting
  static bool prefersTorrentCandidates(QuickPlayRules rules) =>
      rules.sourceMode != QuickPlaySourceMode.addonsThenTorrents &&
      rules.sourceMode != QuickPlaySourceMode.addonsOnly;

  /// Whether a Quick Play result can be attempted automatically. External
  /// links are useful in a manual source list but cannot satisfy an addon-first
  /// auto-play search, so they must not suppress the engine fallback.
  @visibleForTesting
  static bool isAutoPlayableCandidate(Torrent torrent) =>
      SourceCandidateChecks.isDirectCandidate(torrent) ||
      (torrent.streamType != StreamType.externalUrl &&
          SourceCandidateChecks.hasAcquisition(torrent));
}
