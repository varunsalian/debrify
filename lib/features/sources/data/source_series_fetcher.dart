import 'dart:async';

import 'package:debrify/features/sources/application/source_candidate_checks.dart';
import 'package:debrify/features/sources/application/source_candidate_ranking.dart';
import 'package:debrify/features/sources/application/source_filter_ladder.dart';
import 'package:debrify/features/sources/application/source_provider_config.dart';
import 'package:debrify/features/sources/application/source_search_plans.dart';
import 'package:debrify/features/sources/data/curated_source_search.dart';
import 'package:debrify/features/sources/data/iptv_quick_play_search.dart';
import 'package:debrify/features/sources/data/recovery_source_resolution.dart';
import 'package:debrify/features/sources/data/series_pack_search.dart';
import 'package:debrify/features/sources/data/source_engine_fetchers.dart';
import 'package:debrify/models/playback_meta.dart';
import 'package:debrify/models/quick_play_rules.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/services/direct_source_authorization.dart';
import 'package:debrify/services/iptv_source_search.dart';
import 'package:debrify/services/media_server_service.dart';
import 'package:debrify/services/native_series_metadata_service.dart';
import 'package:debrify/services/next_episode_service.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/series_source_fetcher.dart';
import 'package:debrify/services/series_source_service.dart';
import 'package:debrify/services/source_priority.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/services/stream_url_validator.dart';
import 'package:debrify/services/stremio_service.dart';
import 'package:debrify/services/torrent_service.dart';

final class SourceSeriesFetcher {
  const SourceSeriesFetcher._();

  /// Builds the [SeriesSourceFetcher] a series play hands to the player: the
  /// "Load more sources" backend for the pack/episode source tabs. Returns
  /// null when the play isn't fetchable-series-shaped (movies, no concrete
  /// season+episode, non-`tt` ids the torrent engines can't search).
  /// [provider] is the launch's debrid provider; a non-debrid launch (bound
  /// 'local' source, addon 'stream') resolves the default configured provider
  /// at fetch time instead. Without one, episode fetches can still return
  /// direct addon links; torrent and pack fetches fail soft.
  static SeriesSourceFetcher? seriesFetcherFor({
    required PlaybackMeta? meta,
    String? provider,
    bool packsFetched = false,
    bool episodesFetched = false,
    Future<List<Torrent>>? initialEpisodeSearch,
  }) {
    final imdbId = meta?.imdbId ?? meta?.stremioCatalogId;
    final season = meta?.season;
    final episode = meta?.episode;
    if (meta == null ||
        imdbId == null ||
        (!imdbId.startsWith('tt') && !meta.hasStremioEpisodeIdentity) ||
        meta.contentType == 'movie' ||
        season == null ||
        episode == null) {
      return null;
    }
    final label = meta.title ?? '';
    Future<String?> effectiveProvider() =>
        SourceProviderConfig.effectiveFetchProvider(provider);
    final directValidationCache = <String, bool>{};
    final initialSearchTime = DateTime.now();
    final initialSearchScope = ProfileRuntime.scope.value;
    var initialSearchConsumed = false;

    return SeriesSourceFetcher(
      searchForRecovery: RecoverySourceResolution.recoverySearch(
        meta,
        provider,
      ),
      loadCustomEpisodeInventory: meta.hasStremioEpisodeIdentity
          ? () => StremioService.instance.customSeriesEpisodeInventory(
              addonKey: meta.stremioAddonKey!,
              addonId: meta.stremioAddonId,
              catalogId: meta.stremioCatalogId!,
            )
          : null,
      resolveAdjacentEpisode: meta.hasStremioEpisodeIdentity
          ? (s, e, direction) async {
              final target = await StremioService.instance
                  .resolveAdjacentSeriesEpisode(
                    addonKey: meta.stremioAddonKey!,
                    addonId: meta.stremioAddonId,
                    catalogId: meta.stremioCatalogId!,
                    season: s,
                    episode: e,
                    direction: direction,
                  );
              return target == null
                  ? null
                  : (season: target.season, episode: target.episode);
            }
          : (s, e, direction) => NextEpisodeService.findAdjacentEpisode(
              imdbId,
              s,
              e,
              direction: direction,
              reportGuideUnavailable: true,
              preferBuiltIn:
                  meta.addonId == NativeSeriesMetadataService.addon.id,
              catalogItem: meta.catalogItem,
              originAddonId: meta.addonId,
            ),
      season: season,
      episode: episode,
      pinnedDirectCandidates: (s, e, {onPreferredMissing}) async* {
        final originVideoId = await CuratedSourceSearch.originEpisodeVideoId(
          meta,
          s,
          e,
        );
        if (meta.hasStremioEpisodeIdentity && originVideoId == null) return;
        final List<SeriesSource> pins;
        try {
          pins = (await SeriesSourceService.getSources(imdbId))
              .where(
                (source) =>
                    SourceCandidateChecks.bindingMatchesMeta(source, meta),
              )
              .toList();
        } catch (_) {
          return; // Persistence failure must not prevent ordinary search.
        }
        for (final pin in pins) {
          // Existing pack handling retains precedence for a primary pack.
          if (!pin.isAddonDirect && !pin.isIptvDirect && !pin.isMediaServer)
            break;
          try {
            final fresh = pin.isMediaServer
                ? await MediaServerService.resolvePinned(
                    pin,
                    season: s,
                    episode: e,
                  )
                : pin.isIptvDirect
                ? await IptvSourceSearch.resolvePinned(
                    pin,
                    title: meta.title ?? label,
                    year: meta.year,
                    season: s,
                    episode: e,
                  )
                : await StremioService.instance.resolvePinnedDirectStream(
                    addonId: pin.addonId!,
                    addonKey: pin.addonKey!,
                    streamKey: pin.streamKey ?? '',
                    streamIndex: pin.streamIndex ?? 0,
                    bingeGroup: pin.bingeGroup,
                    originCatalogId: pin.addonCatalogId,
                    originVideoId: originVideoId,
                    type: 'series',
                    contentId: imdbId,
                    season: s,
                    episode: e,
                  );
            if (fresh != null) {
              yield fresh;
            } else if (identical(pin, pins.first)) {
              onPreferredMissing?.call();
            }
          } catch (_) {
            if (identical(pin, pins.first)) onPreferredMissing?.call();
            /* Try the next saved source. */
          }
        }
      },
      prepareNextDirectEpisode: (s, e, source) async {
        final scope = ProfileRuntime.scope.value;
        if (scope != initialSearchScope) return;
        final pins = (await SeriesSourceService.getSources(imdbId))
            .where((pin) => SourceCandidateChecks.bindingMatchesMeta(pin, meta))
            .toList();
        // Preserve primary torrent-pack precedence and prepare only the active
        // preferred direct identity, never a speculative replacement pin.
        if (pins.isEmpty ||
            !pins.first.matchesAddonDirect(
              candidateAddonKey: source.stremioAddonKey,
              candidateStreamKey: source.stremioStreamKey,
              candidateBingeGroup: source.stremioBingeGroup,
            )) {
          return;
        }
        final ({int season, int episode})? next;
        if (meta.hasStremioEpisodeIdentity) {
          final target = await StremioService.instance
              .resolveAdjacentSeriesEpisode(
                addonKey: meta.stremioAddonKey!,
                addonId: meta.stremioAddonId,
                catalogId: meta.stremioCatalogId!,
                season: s,
                episode: e,
                direction: 1,
              );
          next = target == null
              ? null
              : (season: target.season, episode: target.episode);
        } else {
          final target = await NextEpisodeService.findNextEpisode(
            imdbId,
            s,
            e,
            preferBuiltIn: meta.addonId == NativeSeriesMetadataService.addon.id,
            catalogItem: meta.catalogItem,
            originAddonId: meta.addonId,
          );
          next = target == null
              ? null
              : (season: target.season, episode: target.episode);
        }
        if (next == null || ProfileRuntime.scope.value != scope) return;
        final originVideoId = await CuratedSourceSearch.originEpisodeVideoId(
          meta,
          next.season,
          next.episode,
        );
        if (meta.hasStremioEpisodeIdentity && originVideoId == null) return;
        final pin = pins.first;
        await StremioService.instance.resolvePinnedDirectStream(
          addonId: pin.addonId!,
          addonKey: pin.addonKey!,
          streamKey: pin.streamKey ?? '',
          streamIndex: pin.streamIndex ?? 0,
          bingeGroup: pin.bingeGroup,
          originCatalogId: pin.addonCatalogId,
          originVideoId: originVideoId,
          type: 'series',
          contentId: imdbId,
          season: next.season,
          episode: next.episode,
          prepare: true,
        );
      },
      packsFetched: packsFetched,
      episodesFetched: episodesFetched,
      validateCandidate: (source) async {
        try {
          await DirectSourceAuthorization.authorize(source);
        } catch (_) {
          return false;
        }
        // Xtream rows intentionally have no episode URL until selected. The
        // source resolver performs the one-row episode lookup and is the
        // authoritative validation step for these descriptors.
        if (IptvSourceSearch.isDeferredXtreamSeries(source)) return true;
        if (source.streamType != StreamType.directUrl) return true;
        final url = source.directUrl;
        if (url == null || url.isEmpty) return false;
        final validationKey = SourceCandidateChecks.directValidationKey(source);
        final cached = directValidationCache[validationKey];
        if (cached != null) return cached;
        final rules = await StorageService.getQuickPlayRules(isMovie: false);
        if (!rules.validateDirectLinks) return true;
        if (!SourceCandidateRanking.shouldPreflightDirectStream(source)) {
          return true;
        }
        // Match initial series Quick Play: lenient HEAD validation rejects
        // positive evidence of death without penalising HEAD-hostile CDNs.
        final alive = await StreamUrlValidator.isPlayableVideoUrl(
          url,
          minBytes: 10 * 1024 * 1024,
          lenient: true,
          headers: source.httpHeaders,
        );
        directValidationCache[validationKey] = alive;
        return alive;
      },
      // The (s, e) the fetch passes in is the episode CURRENTLY playing — a
      // season-pack playlist auto-advances inside one player session, so the
      // launch episode captured above is only the fallback.
      searchPacks: (s, e) async {
        if (!imdbId.startsWith('tt') || meta.hasStremioEpisodeIdentity) {
          return const <Torrent>[];
        }
        final prov = await effectiveProvider();
        if (prov == null) return null;
        final rules = await StorageService.getQuickPlayRules(isMovie: false);
        if (rules.sourcePriority.isNotEmpty) {
          await SourceCandidateRanking.warmSourceAliases();
        }
        final ladder = await SourceFilterLadder.loadLadder(
          includeSize: false,
          rules: rules,
        );
        // This feeds the manual Sources drawer, not automatic selection. Keep
        // every candidate visible while retaining the user's ordering. Strict
        // filtering remains enforced by the actual Quick Play path.
        final manualRules = rules.copyWith(relaxFilters: true);
        return SeriesPackSearch.searchSeriesPackSources(
          imdbId: imdbId,
          label: label,
          season: s,
          provider: prov,
          ladder: ladder,
          rules: manualRules,
        );
      },
      searchEpisodes: (s, e) async {
        if (!initialSearchConsumed &&
            initialEpisodeSearch != null &&
            s == season &&
            e == episode &&
            DateTime.now().difference(initialSearchTime) <
                const Duration(minutes: 2)) {
          initialSearchConsumed = true;
          final results = await initialEpisodeSearch;
          return ProfileRuntime.scope.value == initialSearchScope
              ? results
              : null;
        }
        final rules = await StorageService.getQuickPlayRules(isMovie: false);
        if (rules.sourcePriority.isNotEmpty) {
          await SourceCandidateRanking.warmSourceAliases();
        }
        final ladder = await SourceFilterLadder.loadLadder(
          includeSize: false,
          rules: rules,
        );
        try {
          final prov = await effectiveProvider();
          final List<Torrent> list;
          if (prov == null) {
            // A direct-addon episode can launch without a Debrify debrid
            // provider. Keep that contract when Next crosses a one-entry
            // playlist: query the episode-scoped addon endpoints and retain
            // only links this provider-free resolver can actually open.
            if ((!SourceSearchPlans.allowsAddonSearch(rules) &&
                    !meta.hasStremioEpisodeIdentity) ||
                !rules.allowDirectLinks) {
              return const <Torrent>[];
            }
            final addonTimeout = rules.addonTimeoutSeconds == 15
                ? null
                : Duration(seconds: rules.addonTimeoutSeconds);
            final originVideoId =
                await CuratedSourceSearch.originEpisodeVideoId(meta, s, e);
            if (meta.hasStremioEpisodeIdentity && originVideoId == null) {
              return null; // Retryable metadata failure; never query IMDb here.
            }
            final result = await TorrentService.searchStremioAddonsOnly(
              imdbId: imdbId,
              isMovie: false,
              season: s,
              episode: e,
              timeout: addonTimeout,
              preserveOrder: rules.ranking == QuickPlayRanking.exactOrder,
              originAddonKey: meta.stremioAddonKey,
              originVideoId: originVideoId,
            );
            list = (result['torrents'] as List).cast<Torrent>().where((t) {
              return t.streamType == StreamType.directUrl &&
                  (t.directUrl?.isNotEmpty ?? false);
            }).toList();
            if (!meta.hasStremioEpisodeIdentity) {
              list.addAll(
                await IptvQuickPlaySearch.searchIptvForQuickPlay(
                  imdbId,
                  label,
                  meta.year,
                  false,
                  s,
                  e,
                  rules,
                  null,
                ),
              );
            }
            if (list.isEmpty &&
                ((result['addonErrors'] as Map?)?.isNotEmpty ?? false)) {
              // Addon failures are reported in-band. Keep the fetch retryable
              // when they leave this provider-free path no playable rows.
              return null;
            }
          } else {
            list = await CuratedSourceSearch.searchCuratedSources(
              imdbId: imdbId,
              label: label,
              year: meta.year,
              isMovie: false,
              season: s,
              episode: e,
              provider: prov,
              rules: rules,
              originMeta: meta,
            );
          }
          return SourceCandidateRanking.orderCandidatesForRules(
            list,
            rules: rules.copyWith(relaxFilters: true),
            ladder: ladder,
          );
        } catch (_) {
          // Source search failed — null keeps the tab's "Load more" for retry.
          return null;
        }
      },
      listAddons: () async => [
        if (!meta.hasStremioEpisodeIdentity)
          ...await SourceEngineFetchers.mediaServerSourceRefs(),
        for (final addon
            in await StremioService.instance.applicableStreamingAddons(
              type: 'series',
              contentId: imdbId,
              originAddonKey: meta.stremioAddonKey,
              originVideoId: await CuratedSourceSearch.originEpisodeVideoId(
                meta,
                season,
                episode,
              ),
            ))
          if (!SourcePriority.isRecommendationOnlyAddon(addon.id))
            SourceAddonRef(
              addon.id,
              addon.displayName,
              addonKey: addon.sourceBindingKey,
              resultSourceKey: addon.sourceKey,
            ),
      ],
      listEngines: imdbId.startsWith('tt') && !meta.hasStremioEpisodeIdentity
          ? SourceEngineFetchers.sourceEngineListing
          : () async => const <SourceEngineRef>[],
      fetchEngine: (engineId, s, e) =>
          imdbId.startsWith('tt') && !meta.hasStremioEpisodeIdentity
          ? SourceEngineFetchers.fetchOneEngine(
              engineId,
              imdbId: imdbId,
              isMovie: false,
              season: s,
              episode: e,
            )
          : Future<List<Torrent>?>.value(const <Torrent>[]),
      fetchAddonEpisodes: (addonId, s, e) async {
        try {
          if (addonId.startsWith('mediaserver:')) {
            if (meta.hasStremioEpisodeIdentity) return const <Torrent>[];
            return SourceEngineFetchers.fetchMediaServerSources(
              addonId,
              imdbId,
              false,
              s,
              e,
            );
          }
          final originVideoId = await CuratedSourceSearch.originEpisodeVideoId(
            meta,
            s,
            e,
          );
          if (meta.hasStremioEpisodeIdentity && originVideoId == null) {
            return null;
          }
          return await StremioService.instance.retryAddonStreams(
            addonId: addonId,
            type: 'series',
            imdbId: imdbId,
            season: s,
            episode: e,
            timeout: StremioService.manualRetryTimeout,
            originVideoId: originVideoId,
          );
        } catch (_) {
          // Null = fetch failed; the sheet keeps the Fetch row for a retry.
          return null;
        }
      },
      fetchAddonPacks: (addonId, s) async {
        if (addonId.startsWith('mediaserver:')) return const <Torrent>[];
        if (!imdbId.startsWith('tt') || meta.hasStremioEpisodeIdentity) {
          return const <Torrent>[];
        }
        try {
          return await StremioService.instance.fetchAddonSeasonPacks(
            addonId: addonId,
            imdbId: imdbId,
            season: s,
            timeout: StremioService.manualRetryTimeout,
          );
        } catch (_) {
          return null;
        }
      },
    );
  }
}
