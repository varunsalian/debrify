import 'dart:async';

import 'package:debrify/features/sources/application/source_cache_ordering.dart';
import 'package:debrify/features/sources/application/source_candidate_ranking.dart';
import 'package:debrify/features/sources/application/source_curation.dart';
import 'package:debrify/features/sources/application/source_search_plans.dart';
import 'package:debrify/models/quick_play_rules.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/services/torrent_service.dart';
import 'package:debrify/utils/filter_ladder.dart';

final class SeriesPackSearch {
  const SeriesPackSearch._();

  /// Season/series-pack search chain: whole-series search (seeded with
  /// [season] so any season's pack tier is probed) → strict pack curation →
  /// ladder order (→ provider cache-first pass + stable re-sort). Shared by
  /// the auto-pin pack-first play and the in-player "Load more sources" fetch
  /// so both produce identically ranked lists. Returns null when the SEARCH
  /// itself failed (transient network) — distinct from "no packs exist" — so
  /// callers don't negative-cache a transient failure. [isCancelled] short-
  /// circuits the chain early; callers re-check it on return. [onCacheCheck]
  /// fires just before the cache-status pass actually runs (loader stage).
  static Future<List<Torrent>?> searchSeriesPackSources({
    required String imdbId,
    required String label,
    required int season,
    required String provider,
    required FilterLadder ladder,
    QuickPlayRules? rules,
    bool Function()? isCancelled,
    void Function()? onCacheCheck,
    bool preserveRepresentations = false,
  }) async {
    final activeRules = rules ?? QuickPlayRules.debrifyDefault(isMovie: false);
    final engineTimeout = activeRules.searchTimeoutSeconds == 0
        ? null
        : Duration(seconds: activeRules.searchTimeoutSeconds);
    final addonTimeout = activeRules.addonTimeoutSeconds == 15
        ? null
        : Duration(seconds: activeRules.addonTimeoutSeconds);

    Future<Map<String, dynamic>> query(QuickPlaySourceMode stage) {
      switch (stage) {
        case QuickPlaySourceMode.torrentsOnly:
          return TorrentService.searchByImdb(
            imdbId,
            isMovie: false,
            availableSeasons: [season],
            timeout: engineTimeout,
            preserveSourceOrder:
                activeRules.ranking == QuickPlayRanking.exactOrder,
          );
        case QuickPlaySourceMode.addonsOnly:
          return TorrentService.searchStremioAddonsOnly(
            imdbId: imdbId,
            isMovie: false,
            availableSeasons: [season],
            contentType: 'series',
            timeout: addonTimeout,
            preserveOrder: activeRules.ranking == QuickPlayRanking.exactOrder,
          );
        case QuickPlaySourceMode.together:
          return TorrentService.searchByImdbWithStremio(
            imdbId,
            isMovie: false,
            contentType: 'series',
            // No season/episode → the whole-series smart-fallback path. Seed
            // the probe so a pack for any requested season can be found.
            availableSeasons: [season],
            engineTimeout: engineTimeout,
            stremioTimeout: addonTimeout,
            preserveSourceOrder:
                activeRules.ranking == QuickPlayRanking.exactOrder,
          );
        case QuickPlaySourceMode.torrentsThenAddons:
        case QuickPlaySourceMode.addonsThenTorrents:
          throw StateError(
            'Fallback modes must be expanded into search stages',
          );
      }
    }

    var anySearchSucceeded = false;
    var allSearchesSucceeded = true;
    var packs = <Torrent>[];
    // ignore: invalid_use_of_visible_for_testing_member
    for (final stage in SourceSearchPlans.seriesPackSearchPlan(activeRules)) {
      if (isCancelled?.call() ?? false) return packs;
      late final List<Torrent> raw;
      try {
        final packRes = await query(stage);
        raw = (packRes['torrents'] as List).cast<Torrent>();
        // Both engine and addon services report failures in-band instead of
        // throwing. A timed-out empty response is unknown, not proof that no
        // pack exists, so it must not poison the negative cache.
        // ignore: invalid_use_of_visible_for_testing_member
        final stageHadErrors = SourceSearchPlans.packSearchReportedErrors(
          packRes,
          stage,
        );
        if (stageHadErrors) allSearchesSucceeded = false;
        if (raw.isNotEmpty || !stageHadErrors) {
          anySearchSucceeded = true;
        }
      } catch (_) {
        // A later fallback stage may still find a usable pack, but an otherwise
        // empty result remains indeterminate and must not be negative-cached.
        allSearchesSucceeded = false;
        continue;
      }
      if (isCancelled?.call() ?? false) return packs;
      // Keep curation outside the network catch. The compatibility path used
      // to propagate a curation/storage failure, so it must not be reclassified
      // as a successful empty search and written into the negative cache.
      packs = await SourceCuration.curatePackCandidates(
        raw,
        label: label,
        season: season,
        provider: provider,
        preference: activeRules.packPreference,
      );
      // Fallback means "try the next source family when this one did not
      // produce a usable pack", not merely when its raw response was empty.
      if (packs.isNotEmpty) break;
    }
    // A usable pack is safe to return even if another source family failed.
    // An empty result is cacheable only when every requested stage completed;
    // otherwise it means "unknown", not "this season has no pack".
    if (packs.isEmpty && (!anySearchSucceeded || !allSearchesSucceeded)) {
      return null;
    }
    // Ladder tier is the PRIMARY pack sort key (stable over the coverage/
    // seeders order): the winning pack gets PINNED by auto-bind, so it must
    // be one the user's filters approve of when any such pack exists.
    if (preserveRepresentations) return packs;
    packs = SourceCandidateRanking.orderCandidatesForRules(
      packs,
      rules: activeRules,
      ladder: ladder,
    );
    if (isCancelled?.call() ?? false) return packs;
    if (packs.isNotEmpty &&
        (provider == 'torbox' || provider == 'premiumize')) {
      onCacheCheck?.call();
      packs = await SourceCacheOrdering.cacheFirst(provider, packs);
      // Exact/provider-order profiles keep cached hits globally first. Other
      // rankings retain their existing post-cache rule/filter behavior.
      // ignore: invalid_use_of_visible_for_testing_member
      packs = SourceCandidateRanking.orderCacheCheckedCandidatesForRules(
        packs,
        rules: activeRules,
        ladder: ladder,
      );
    }
    return packs;
  }
}
