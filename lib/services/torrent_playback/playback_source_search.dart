/// The source-search fetchers behind Quick Play and the in-player "Load more
/// sources" drawer — moved verbatim out of [TorrentPlaybackService] (lane T3).
/// Network + prefs only; no BuildContext, no widgets. Ordering decisions stay
/// in [PlaybackCandidateRanking], which this unit calls.
library;

import '../../models/indexer_manager_config.dart';
import '../../models/quick_play_rules.dart';
import '../../models/torrent.dart';
import '../../utils/filter_ladder.dart';
import '../../utils/rd_blocked_filter.dart';
import '../../utils/torrent_curation.dart';
import '../cloud/playback_cache_first.dart';
import '../playback_service_dispatch.dart';
import '../series_source_fetcher.dart';
import '../storage/provider_credential_prefs.dart';
import '../torrent_service.dart';
import 'playback_candidate_ranking.dart';

class PlaybackSourceSearch {
  const PlaybackSourceSearch._();

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
    for (final stage in PlaybackCandidateRanking.seriesPackSearchPlan(
      activeRules,
    )) {
      if (isCancelled?.call() ?? false) return packs;
      late final List<Torrent> raw;
      try {
        final packRes = await query(stage);
        raw = (packRes['torrents'] as List).cast<Torrent>();
        // Both engine and addon services report failures in-band instead of
        // throwing. A timed-out empty response is unknown, not proof that no
        // pack exists, so it must not poison the negative cache.
        final stageHadErrors =
            PlaybackCandidateRanking.packSearchReportedErrors(packRes, stage);
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
      packs = await _curatePackCandidates(
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
    packs = PlaybackCandidateRanking.orderCandidatesForRules(
      packs,
      rules: activeRules,
      ladder: ladder,
    );
    if (isCancelled?.call() ?? false) return packs;
    if (packs.isNotEmpty && PlaybackServiceDispatch.hasCacheCheck(provider)) {
      onCacheCheck?.call();
      packs = await PlaybackCacheFirst.reorder(provider, packs);
      // Exact/provider-order profiles keep cached hits globally first. Other
      // rankings retain their existing post-cache rule/filter behavior.
      packs = PlaybackCandidateRanking.orderCacheCheckedCandidatesForRules(
        packs,
        rules: activeRules,
        ladder: ladder,
      );
    }
    return packs;
  }

  /// Exact-title search chain: engine search → curation → the Stremio
  /// addon-only fallback when the engines come up dry. Shared by
  /// [playFromSelection]'s episode/movie fallback and the in-player "Load
  /// more sources" episode fetch. Engine-search failures PROPAGATE (callers
  /// own the error surface); the addon fallback fails silently to an empty
  /// list, matching the play flow. [onResults] fires with the count each time
  /// a search produced candidates (loader stage narration).
  static Future<List<Torrent>> searchCuratedSources({
    required String imdbId,
    required String label,
    required bool isMovie,
    int? season,
    int? episode,
    required String provider,
    QuickPlayRules? rules,
    bool Function()? isCancelled,
    void Function(int count)? onResults,
  }) async {
    final activeRules =
        rules ?? QuickPlayRules.debrifyDefault(isMovie: isMovie);
    final engineTimeout = activeRules.searchTimeoutSeconds == 0
        ? null
        : Duration(seconds: activeRules.searchTimeoutSeconds);
    final addonTimeout = activeRules.addonTimeoutSeconds == 15
        ? null
        : Duration(seconds: activeRules.addonTimeoutSeconds);

    Future<List<Torrent>> engines() async {
      final res = await TorrentService.searchByImdb(
        imdbId,
        isMovie: isMovie,
        season: season,
        episode: episode,
        timeout: engineTimeout,
        preserveSourceOrder: activeRules.ranking == QuickPlayRanking.exactOrder,
      );
      var found = (res['torrents'] as List).cast<Torrent>();
      if (isCancelled?.call() ?? false) return found;
      if (found.isNotEmpty) {
        onResults?.call(found.length);
        // Curate candidates so the RIGHT torrent is probed first (mirrors old
        // home): drop unrelated titles, keep/relevance-sort by the requested
        // episode/season, then drop RD-blocked keywords when RD is the provider.
        // Without this the raw seeder-ranked list can lead with wrong-episode/
        // other-season packs that resolve fine but get rejected by
        // _resolvedHasEpisode, burning the probes.
        found = await _curateCandidates(
          found,
          label: label,
          isMovie: isMovie,
          season: season,
          episode: episode,
          provider: provider,
        );
      }
      return found;
    }

    Future<List<Torrent>> addons() async {
      // Addon streams are already id/episode-scoped by the /stream endpoint;
      // their labels are quality descriptions rather than titles, so engine
      // title curation must not be applied to them.
      try {
        final addonRes = await TorrentService.searchStremioAddonsOnly(
          imdbId: imdbId,
          isMovie: isMovie,
          season: season,
          episode: episode,
          timeout: addonTimeout,
          preserveOrder: activeRules.ranking == QuickPlayRanking.exactOrder,
        );
        final found = (addonRes['torrents'] as List).cast<Torrent>();
        final allowed = activeRules.allowDirectLinks
            ? found
            : found.where((t) => t.streamType != StreamType.directUrl).toList();
        if (allowed.isNotEmpty) onResults?.call(allowed.length);
        return allowed;
      } catch (_) {
        return const [];
      }
    }

    List<Torrent> torrents;
    switch (activeRules.sourceMode) {
      case QuickPlaySourceMode.torrentsThenAddons:
      case QuickPlaySourceMode.addonsThenTorrents:
      case QuickPlaySourceMode.together:
        final batches = await Future.wait([engines(), addons()]);
        // Both families start together, but Future.wait preserves this fixed
        // batch order. Provider priority and stable dedupe run afterwards.
        torrents = [...batches[0], ...batches[1]];
        break;
      case QuickPlaySourceMode.torrentsOnly:
        torrents = await engines();
        break;
      case QuickPlaySourceMode.addonsOnly:
        torrents = await addons();
        break;
    }
    if (isCancelled?.call() ?? false) return torrents;
    return torrents;
  }

  static Future<List<SourceEngineRef>> sourceEngineListing() async {
    final engines = await TorrentService.getImdbSearchEngines();
    final refs = <SourceEngineRef>[];
    for (final engine in engines) {
      if (!await TorrentService.isEngineEnabled(engine.name)) continue;
      final source = IndexerManagerConfig.isIndexerManagerEngine(engine.name)
          ? engine.displayName
          : engine.name;
      refs.add(
        SourceEngineRef(engine.name, engine.displayName, source.toLowerCase()),
      );
    }
    return refs;
  }

  static Future<List<Torrent>?> fetchOneEngine(
    String engineId, {
    required String imdbId,
    required bool isMovie,
    int? season,
    int? episode,
  }) async {
    try {
      final engines = await TorrentService.getImdbSearchEngines();
      final states = <String, bool>{for (final e in engines) e.name: false};
      states[engineId] = true;
      final result = await TorrentService.searchByImdb(
        imdbId,
        engineStates: states,
        isMovie: isMovie,
        season: season,
        episode: episode,
      );
      final errors = result['engineErrors'] as Map<String, String>? ?? const {};
      if (errors.containsKey(engineId)) return null;
      return result['torrents'] as List<Torrent>? ?? const <Torrent>[];
    } catch (_) {
      return null;
    }
  }

  /// Curate torrent candidates before probing, mirroring the old Home engine:
  ///   1. drop torrents whose name doesn't match the title (unrelated packs),
  ///   2. keep + relevance-sort by the requested episode/season,
  ///   3. when RD is the provider and the user's "skip blocked" setting is on,
  ///      drop RD-blocked-keyword torrents.
  /// Every step falls back to the pre-step list if it would empty the set, so
  /// curation can never turn a non-empty result into a "no sources" failure.
  static Future<List<Torrent>> _curateCandidates(
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
    if (PlaybackServiceDispatch.isDebrid(provider) &&
        await ProviderCredentialPrefs.getRdSkipBlockedTorrents()) {
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
  static Future<List<Torrent>> _curatePackCandidates(
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
              PlaybackCandidateRanking.hasAcquisition(t) &&
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

    if (PlaybackServiceDispatch.isDebrid(provider) &&
        await ProviderCredentialPrefs.getRdSkipBlockedTorrents()) {
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
}
