/// Pure candidate ranking, probing budgets and Quick Play rule predicates for
/// [TorrentPlaybackService] — moved verbatim out of that file (lane T3). No
/// BuildContext, no widgets: everything here is a decision about which
/// candidate to try next and how many times.
///
/// The `@visibleForTesting` annotations the origin carried are dropped: the
/// playback service is now a different library and calls these directly.
library;

import '../../models/quick_play_rules.dart';
import '../../models/torrent.dart';
import '../../models/torrent_filter_state.dart';
import '../../utils/filter_ladder.dart';
import '../../utils/torrent_curation.dart';
import '../playback_service_dispatch.dart';
import '../source_priority.dart';
import '../startup_stream_policy.dart';
import '../storage/quick_play_policy_prefs.dart';

class PlaybackCandidateRanking {
  const PlaybackCandidateRanking._();

  /// True when [t] carries something we can turn into a magnet (real magnet,
  /// infohash, or a .torrent URL). Sync, for filtering candidate lists.
  static bool hasAcquisition(Torrent t) =>
      (t.magnetUrl?.startsWith('magnet:') ?? false) ||
      (t.hasRealInfoHash && t.infohash.isNotEmpty) ||
      (t.torrentUrl?.isNotEmpty ?? false);

  /// Selects the direct-URL stream to play instantly ([direct]) and the one
  /// kept as the dead-end rescue ([fallbackDirect]) — always the FIRST direct
  /// stream in [torrents] (tier-sorted when the ladder is active). [direct]
  /// is set only when no PLAYABLE candidate (probeable torrent or direct
  /// stream — external links and acquisition-less entries don't count)
  /// occupies a strictly better tier, so a full-match torrent beats a
  /// relaxed-tier direct link, but unplayable tier-0 noise can't suppress
  /// the instant play. Null/inactive ladder ⇒ legacy first-direct-wins.
  static (Torrent?, Torrent?) selectDirect(
    List<Torrent> torrents,
    FilterLadder? ladder,
  ) {
    final tiered = ladder != null && ladder.isActive;
    int? bestPlayableTier;
    for (final t in torrents) {
      final isDirect =
          t.streamType == StreamType.directUrl &&
          (t.directUrl?.isNotEmpty ?? false);
      final isProbeable =
          t.streamType != StreamType.externalUrl && hasAcquisition(t);
      if (!isDirect && !isProbeable) continue;
      if (tiered) bestPlayableTier ??= ladder.tierOf(t);
      if (!isDirect) continue;
      final direct = (!tiered || ladder.tierOf(t) == bestPlayableTier)
          ? t
          : null;
      return (direct, t);
    }
    return (null, null);
  }

  /// Probe budget for one play. PikPak is ALWAYS 1 — every probe queues a
  /// real download that can't be cheaply undone — and beats every floor.
  /// Otherwise the user's try-multiple setting (clamped 1–10 so a corrupted
  /// pref can never yield 0 probes), raised to [minAttempts] (the pack-top
  /// safety's 2-attempt floor).
  static int probeAttemptCount(
    String prov, {
    required bool tryMultiple,
    required int maxRetries,
    int minAttempts = 1,
  }) {
    if (PlaybackServiceDispatch.oneProbeSafety(prov)) return 1;
    final base = tryMultiple ? maxRetries.clamp(1, 10) : 1;
    return base < minAttempts ? minAttempts : base;
  }

  /// Pack coverage types — the only tops the pack-top safety rescues from.
  static const Set<String> _packCoverageTypes = {
    'seasonPack',
    'multiSeasonPack',
    'completeSeries',
  };

  /// Pack-top safety (QUICK_PLAY_FILTERS_PLAN.md §3.4b.3): when the ladder
  /// promoted a genuine PACK (torrent-typed, pack coverage metadata) above
  /// every exact-episode single, guarantee the best single still gets probed.
  /// Standard providers get it at index 1 plus a 2-attempt floor; PikPak —
  /// which probes exactly ONCE and each probe queues a real, possibly
  /// whole-pack download — gets the single moved to index 0 instead, so its
  /// lone probe is never spent on a pack. Guards (round-2 review): a top
  /// without pack coverage (episode-scoped addon streams, singles whose
  /// names lack S/E tokens) is NOT treated as a pack, and a cam-floored
  /// single is never hoisted (it would defeat §3.3c). Returns the (possibly
  /// copied) list and the minimum probe attempts.
  static (List<Torrent>, int) packTopSafety(
    List<Torrent> candidates, {
    required String provider,
    required FilterLadder ladder,
    int? season,
    int? episode,
  }) {
    if (season == null || episode == null || candidates.length < 2) {
      return (candidates, 1);
    }
    final top = candidates.first;
    if (top.streamType != StreamType.torrent ||
        !_packCoverageTypes.contains(top.coverageType) ||
        nameHasExactEpisode(top.name, season, episode)) {
      return (candidates, 1);
    }
    final singleIdx = candidates.indexWhere(
      (t) =>
          nameHasExactEpisode(t.name, season, episode) &&
          ladder.tierOf(t) < ladder.tierCount, // never hoist a cam-floor single
    );
    if (singleIdx <= 0) return (candidates, 1);
    final list = List.of(candidates);
    final single = list.removeAt(singleIdx);
    if (PlaybackServiceDispatch.oneProbeSafety(provider)) {
      list.insert(0, single);
      return (list, 1);
    }
    list.insert(1, single);
    return (list, 2);
  }

  /// Loads the quick-play ladder: inactive (a no-op) when the user disabled
  /// "Apply filters to Quick Play" or has no default filters saved.
  /// Public only for tests (the kill-switch gate).
  static Future<FilterLadder> loadLadder({
    bool includeSize = true,
    QuickPlayRules? rules,
  }) async {
    final useFilters =
        rules?.useFilters ??
        await QuickPlayPolicyPrefs.getQuickPlayHonorsFilters();
    if (!useFilters) {
      return FilterLadder(const TorrentFilterState.empty());
    }
    final ladder = await FilterLadder.fromSavedDefaults();
    // Size buckets only make sense for movies: addon packs report a single
    // episode's size, so honoring a size default on a series/episode play
    // would rank against a misleading number. Strip it for non-movies.
    if (includeSize) return ladder;
    return FilterLadder(ladder.filters.copyWith(sizes: const <SizeBucket>{}));
  }

  /// The loader narration line for what the ladder found (plan §3.5), or
  /// null when there is nothing to say (inactive ladder / empty list) — so
  /// filterless plays look exactly as before. Pure; public only for tests.
  static String? ladderNote(FilterLadder ladder, List<Torrent> ordered) {
    if (!ladder.isActive || ordered.isEmpty) return null;
    final summary = ladder.filterSummary();
    final best = ladder.tierOf(ordered.first);
    final n = ordered.where((t) => ladder.tierOf(t) == best).length;
    final plural = n == 1 ? 'source' : 'sources';
    if (best == 0) {
      return 'Matching your filters ($summary) · $n $plural';
    }
    if (best >= ladder.tierCount) {
      return 'Only cam-quality sources found — playing best available';
    }
    if (best == ladder.tierCount - 1) {
      return 'Nothing matches your filters ($summary) — playing best available';
    }
    return 'No full filter match — trying '
        '${ladder.describeTier(best) ?? 'any available source'} · $n $plural';
  }

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
  static List<Torrent> mergePreparedTorrentOrder(
    List<Torrent> sources,
    List<Torrent> preparedTorrents,
  ) {
    var nextTorrent = 0;
    return [
      for (final source in sources)
        if (source.streamType == StreamType.torrent && hasAcquisition(source))
          preparedTorrents[nextTorrent++]
        else
          source,
    ];
  }

  /// Indexer-manager engines stamp results with their display name; this maps
  /// it back to the engine id for the Addon Priority list. The async flows
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
    final run = SourcePriority.engineAliases()
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
  /// Keep this policy on source provenance as well as hostname: AIOStreams
  /// commonly returns a provider/CDN URL whose final host no longer contains
  /// "aiostreams", while the addon id/source still identifies the link as an
  /// IP-bound proxy result.
  static bool shouldPreflightDirectStream(Torrent torrent) {
    return !StartupStreamPolicy.isAioStreams(
      addonId: torrent.stremioAddonId,
      sourceName: torrent.source,
      url: torrent.directUrl,
    );
  }

  /// Whether direct-addon rows should be attempted before torrent acquisition.
  /// A torrent-first source plan tries the torrent twin first and retains the
  /// direct row as the existing no-provider/dead-end rescue.
  static bool shouldTryDirectBeforeTorrent(QuickPlayRules? rules) =>
      rules?.sourceMode != QuickPlaySourceMode.torrentsThenAddons &&
      rules?.sourceMode != QuickPlaySourceMode.torrentsOnly;

  /// Whether Quick Play should exhaust provider-ordered torrent candidates
  /// before falling back to direct links.
  static bool prefersTorrentCandidates(QuickPlayRules rules) =>
      rules.sourceMode != QuickPlaySourceMode.addonsThenTorrents &&
      rules.sourceMode != QuickPlaySourceMode.addonsOnly;

  /// Whether a Quick Play result can be attempted automatically. External
  /// links are useful in a manual source list but cannot satisfy an addon-first
  /// auto-play search, so they must not suppress the engine fallback.
  static bool isAutoPlayableCandidate(Torrent torrent) =>
      (torrent.streamType == StreamType.directUrl &&
          (torrent.directUrl?.isNotEmpty ?? false)) ||
      (torrent.streamType != StreamType.externalUrl && hasAcquisition(torrent));

  /// An explicit addon-only profile can search before opening the provider
  /// picker. Mixed modes must include engines and addons before applying the
  /// shared Addon Priority, so they stay on the provider-backed route.
  static bool shouldSearchAddonsBeforeProvider(
    QuickPlayRules rules, {
    required bool isMovie,
    bool hasPreferredProvider = false,
  }) {
    if (hasPreferredProvider) return false;
    final addonLeading = rules.sourceMode == QuickPlaySourceMode.addonsOnly;
    final exactEpisodeRoute =
        isMovie ||
        !rules.preferSeriesPacks ||
        rules.packPreference == QuickPlayPackPreference.exactEpisodeOnly;
    return addonLeading && exactEpisodeRoute;
  }

  /// Whether the selected source profile permits any Stremio/addon request.
  /// Fast paths must consult this before using a direct addon stream; otherwise
  /// `torrentsOnly` silently behaves like an addon-enabled profile.
  static bool allowsAddonSearch(QuickPlayRules rules) =>
      rules.sourceMode != QuickPlaySourceMode.torrentsOnly;

  /// Search stages used by the direct-stream/auto-advance flow. Forced and
  /// provider-free calls stay addon-only. Mixed modes query both families at
  /// once; Addon Priority, not network completion or family, chooses first.
  static List<QuickPlaySourceMode> addonStreamSearchPlan(
    QuickPlayRules rules, {
    bool noProvider = false,
    bool forceAddonOnly = false,
  }) {
    if (noProvider || forceAddonOnly) {
      return const [QuickPlaySourceMode.addonsOnly];
    }
    switch (rules.sourceMode) {
      case QuickPlaySourceMode.torrentsThenAddons:
      case QuickPlaySourceMode.addonsThenTorrents:
      case QuickPlaySourceMode.together:
        return const [QuickPlaySourceMode.together];
      case QuickPlaySourceMode.torrentsOnly:
        return const [QuickPlaySourceMode.torrentsOnly];
      case QuickPlaySourceMode.addonsOnly:
        return const [QuickPlaySourceMode.addonsOnly];
    }
  }

  /// Search services report per-engine/addon failures in-band. An empty pack
  /// result with one of these errors is inconclusive and must not be written to
  /// the multi-hour no-pack cache.
  static bool packSearchReportedErrors(
    Map<String, dynamic> result,
    QuickPlaySourceMode stage,
  ) {
    final errors = stage == QuickPlaySourceMode.addonsOnly
        ? result['addonErrors'] as Map?
        : result['engineErrors'] as Map?;
    return errors?.isNotEmpty ?? false;
  }

  /// Mixed source modes keep the whole-series bare-ID and season-probing
  /// search combined. Pack curation remains torrent-only; Addon Priority is
  /// applied after probing to choose between engine and addon packs.
  static List<QuickPlaySourceMode> seriesPackSearchPlan(QuickPlayRules rules) {
    return switch (rules.sourceMode) {
      QuickPlaySourceMode.torrentsThenAddons ||
      QuickPlaySourceMode.addonsThenTorrents ||
      QuickPlaySourceMode.together => const [QuickPlaySourceMode.together],
      QuickPlaySourceMode.torrentsOnly => const [
        QuickPlaySourceMode.torrentsOnly,
      ],
      QuickPlaySourceMode.addonsOnly => const [QuickPlaySourceMode.addonsOnly],
    };
  }
}
