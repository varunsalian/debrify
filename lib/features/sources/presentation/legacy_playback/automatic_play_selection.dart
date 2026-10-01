import 'dart:async';

import 'package:debrify/features/sources/application/source_candidate_checks.dart';
import 'package:debrify/features/sources/application/source_candidate_ranking.dart';
import 'package:debrify/features/sources/application/source_filter_ladder.dart';
import 'package:debrify/features/sources/application/source_iptv_availability.dart';
import 'package:debrify/features/sources/application/source_probing.dart';
import 'package:debrify/features/sources/application/source_provider_config.dart';
import 'package:debrify/features/sources/application/source_search_plans.dart';
import 'package:debrify/features/sources/data/automatic_source_bindings.dart';
import 'package:debrify/features/sources/data/curated_source_search.dart';
import 'package:debrify/features/sources/data/iptv_quick_play_search.dart';
import 'package:debrify/features/sources/data/series_pack_search.dart';
import 'package:debrify/features/sources/data/source_series_fetcher.dart';
import 'package:debrify/features/sources/models/playback_cancel_token.dart';
import 'package:debrify/features/sources/presentation/legacy_playback/addon_stream_playback.dart';
import 'package:debrify/features/sources/presentation/legacy_playback/automatic_play_best.dart';
import 'package:debrify/features/sources/presentation/legacy_playback/bound_source_playback.dart';
import 'package:debrify/features/sources/presentation/legacy_playback/source_loading_overlays.dart';
import 'package:debrify/features/sources/presentation/legacy_playback/source_player_launch.dart';
import 'package:debrify/features/sources/presentation/legacy_playback/source_provider_choice.dart';
import 'package:debrify/models/playback_meta.dart';
import 'package:debrify/models/quick_play_rules.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/services/direct_source_authorization.dart';
import 'package:debrify/services/iptv_source_search.dart';
import 'package:debrify/services/series_source_service.dart';
import 'package:debrify/services/source_selection_diagnostics.dart';
import 'package:debrify/services/storage/quick_play_storage.dart';
import 'package:debrify/services/stream_url_validator.dart';
import 'package:debrify/widgets/pipeline_loading_overlay.dart';
import 'package:flutter/material.dart';

final class AutomaticPlaySelection {
  const AutomaticPlaySelection._();

  /// Series-auto-pin negative cache: "imdbId:season" → when to allow
  /// re-searching packs. A pack-first attempt that finds no instantly-playable
  /// pack records an entry so subsequent episodes of the SAME season (a binge,
  /// or an ongoing show with no pack yet) skip the expensive whole-series pack
  /// search instead of repeating it every play. Season remains part of the key
  /// because "no pack for S1" must not suppress an S7 pack; provider and the
  /// complete rules profile are also included so a settings/provider change
  /// takes effect immediately. In-memory + TTL means a newly-released pack is
  /// still picked up after the window (or an app restart).
  static final Map<String, DateTime> _noPackUntil = {};

  static String _noPackKey(
    String imdbId,
    int season,
    String provider,
    QuickPlayRules rules,
  ) => '$imdbId:$season:$provider:${rules.hashCode}';

  static bool _recentlyNoPack(
    String imdbId,
    int season,
    String provider,
    QuickPlayRules rules,
  ) {
    // "Do not remember" must take effect immediately, including for entries
    // recorded before the user changed this setting.
    if (rules.failedPackCacheHours <= 0) return false;
    final key = _noPackKey(imdbId, season, provider, rules);
    final until = _noPackUntil[key];
    if (until == null) return false;
    if (!DateTime.now().isBefore(until)) {
      _noPackUntil.remove(key);
      return false;
    }
    return true;
  }

  static void _markNoPack(
    String imdbId,
    int season,
    String provider,
    QuickPlayRules rules,
    Duration ttl,
  ) {
    if (ttl <= Duration.zero) return;
    // Bound the map so a long session browsing many shows can't grow it
    // without limit; drop expired entries first, then the oldest.
    final now = DateTime.now();
    _noPackUntil.removeWhere((_, until) => !now.isBefore(until));
    const cap = 200;
    if (_noPackUntil.length >= cap) {
      final oldest = _noPackUntil.entries
          .reduce((a, b) => a.value.isBefore(b.value) ? a : b)
          .key;
      _noPackUntil.remove(oldest);
    }
    _noPackUntil[_noPackKey(imdbId, season, provider, rules)] = now.add(ttl);
  }

  /// Full catalog-play flow: pick provider, show the cinematic overlay (with the
  /// real provider name), search torrents for the title, and auto-play the best
  /// — all under ONE overlay. Used by the Search tab's catalog Play button.
  static Future<void> playFromSelection(
    BuildContext context, {
    required String imdbId,
    required bool isMovie,
    int? season,
    int? episode,
    required PlaybackMeta meta,
    // Skip the provider picker and use this provider directly — set by the
    // next-episode auto-advance so a binge never re-prompts mid-chain.
    String? preferredProvider,
    // A player-level failure has already exhausted the applicable saved
    // sources. Recovery re-enters below the binding gate so the same failed
    // source cannot launch again in a loop.
    bool skipBoundSources = false,
    // Hands the user the manual source list for THIS selection instead of
    // auto-picking. Supplying it is what opts a call site into the user's
    // "Play button opens" preference (see [StorageService.getPlayButtonMode]):
    // only a real Play press passes an opener, so binge auto-advance and
    // post-failure recovery keep their existing no-prompt contract for free.
    VoidCallback? openSourcePicker,
    AutomaticSourceBindings? sourceBindings,
  }) async {
    final bindingOwner = sourceBindings ?? AutomaticSourceBindings.capture();
    if (!context.mounted || !bindingOwner.isCurrent) return;
    logSourceSelection(
      'play_selection_start',
      season: season,
      episode: episode,
      reason: skipBoundSources
          ? 'recovery_skip_saved'
          : 'saved_then_quick_play',
    );
    final label = meta.title ?? '';
    if (imdbId.isEmpty) {
      SourceLoadingOverlays.snack(
        context,
        'No IMDb match to find sources for "$label".',
      );
      return;
    }
    var cancelled = false;
    final resolving = SourceLoadingOverlays.showResolvingOverlay(
      context,
      meta: meta,
      title: label,
      onCancel: () => cancelled = true,
    );
    late final QuickPlayRules rules;
    // 'quick' (the default) leaves every path below exactly as it shipped. Read
    // under the overlay, next to the rules, so the default path's time-to-overlay
    // is unchanged.
    var playMode = 'quick';
    try {
      rules = await QuickPlayStorage.getQuickPlayRules(isMovie: isMovie);
      if (openSourcePicker != null) {
        playMode = await QuickPlayStorage.getPlayButtonMode();
      }
      if (rules.sourcePriority.isNotEmpty) {
        await SourceCandidateRanking.warmSourceAliases();
      }
    } catch (_) {
      resolving.dismiss();
      rethrow;
    }
    // "Always ask" wants the list regardless of what is pinned, so it enters
    // below the binding gate the same way failure-recovery does.
    final skipBound = skipBoundSources || playMode == 'always';
    // True when this press has been handed to the manual source list and the
    // caller must stop. Reads the callback through a local so neither hand-off
    // site needs a `!`, which would be a latent trap if [playMode] ever gained
    // another writer.
    final opener = openSourcePicker;
    bool handedToPicker() {
      if (playMode == 'quick' || opener == null) return false;
      // The last link in the [SeriesResume] chain: whatever episode arrives
      // here is the one the manual list opens on. Compare against the
      // `play-launch` line — if they differ, the selection was rebuilt between
      // the two; if they agree but disagree with `label-resolve-result`, the
      // label and the press reconciled to different answers.
      debugPrint(
        '[SeriesResume] picker-handoff title="$label" mode=$playMode '
        'target=S${season}E$episode metaTarget=S${meta.season}E${meta.episode}',
      );
      resolving.dismiss();
      if (context.mounted && !cancelled) opener();
      return true;
    }

    var activeRules = rules;
    if ((!context.mounted || !bindingOwner.isCurrent) || cancelled) {
      resolving.dismiss();
      return;
    }

    // Any non-`tt` id can't be resolved by the torrent engines — they key on
    // `tt…` ids — so addon-enabled profiles resolve these through the addon's
    // own /stream endpoint. This covers IPTV/TV channels AND kitsu/tmdb-only
    // movie & series catalogs, and matches old home, whose quick-play always ran
    // the Stremio-inclusive search. An explicit torrents-only profile fails
    // clearly instead of silently querying addons. A `tt…` id — even a
    // non-standard type like some anime catalogs — keeps the normal torrent
    // search below so the on-device engines still run. (imdbId.isEmpty is
    // already handled above.)
    if (!imdbId.startsWith('tt')) {
      if (!SourceSearchPlans.allowsAddonSearch(rules)) {
        resolving.dismiss();
        SourceLoadingOverlays.snack(
          context,
          'Torrent engines can’t search "$label" without an IMDb ID. Choose a source mode that allows addons.',
        );
        return;
      }
      // Kitsu/tmdb-only catalogs are a real slice of the library, so the picker
      // modes have to apply here too — otherwise "Always show sources" silently
      // does nothing for anime. The manual list handles a non-`tt` id fine: it
      // passes the id straight to searchByImdbWithStremio, whose addon half
      // accepts it (the engine half just returns nothing). Handing over BEFORE
      // the addon auto-play costs no pinned-source reuse — this branch already
      // returns above the binding gate, so non-`tt` ids never had any. The
      // torrents-only guard stays ahead of this: an empty picker would be a
      // worse answer than the explicit message.
      if (handedToPicker()) return;
      resolving.dismiss();
      await AddonStreamPlayback.playAddonStream(
        context,
        imdbId,
        isMovie: isMovie,
        season: season,
        episode: episode,
        meta: meta,
        label: label,
        rules: rules,
        forceAddonOnly: true,

        sourceBindings: bindingOwner,
      );
      return;
    }

    // Bound-source reuse: if the user pinned a source for this title, play it
    // directly and skip the torrent search entirely. A series binding is only
    // usable when a concrete season+episode is requested (to land in the pack).
    if (!skipBound) {
      late final List<SeriesSource> bound;
      try {
        bound = (await SeriesSourceService.getSources(imdbId))
            .where(
              (source) =>
                  SourceCandidateChecks.bindingMatchesMeta(source, meta),
            )
            .toList();
      } catch (_) {
        resolving.dismiss();
        rethrow;
      }
      if ((!context.mounted || !bindingOwner.isCurrent) || cancelled) {
        resolving.dismiss();
        return;
      }
      // A series binding needs a concrete season+episode to land inside the
      // pack. Gate on the same fields _launch forwards to the player (meta.*),
      // so the requested episode reaches the existing exact-episode checks.
      final boundUsable =
          bound.isNotEmpty &&
          (isMovie || (meta.season != null && meta.episode != null));
      if (boundUsable) {
        resolving.dismiss();
        final played = await BoundSourcePlayback.playViaBound(
          context,
          imdbId,
          bound,
          label: label,
          meta: meta,
          preferredProvider: preferredProvider,

          sourceBindings: bindingOwner,
        );
        if (played) return;
        if (!context.mounted || !bindingOwner.isCurrent) return;
        // Bound source unplayable → fall through to a normal search below.
      }
    }

    // Everything above this line is the pinned-source contract; everything below
    // it auto-picks. Both non-default modes stop here and hand the user the list
    // instead — reaching this point already means "no pinned source played",
    // whether because none was pinned, the pin didn't cover this episode, or the
    // pin was dead. That makes the branch correct by construction: it needs no
    // separate notion of pin eligibility, which a title-level count could not
    // have answered for a series pinned only as single episodes.
    if (handedToPicker()) return;

    // A custom Stremio episode ID describes content that IMDb torrent/IPTV
    // sources cannot safely substitute (for example, a fan edit). Query its
    // protocol ID directly before provider selection, regardless of the
    // ordinary torrent-vs-addon preference for canonical titles.
    if (meta.hasStremioEpisodeIdentity) {
      resolving.dismiss();
      await AddonStreamPlayback.playAddonStream(
        context,
        imdbId,
        isMovie: isMovie,
        season: season,
        episode: episode,
        meta: meta,
        label: label,
        rules: rules,
        forceAddonOnly: true,

        sourceBindings: bindingOwner,
      );
      return;
    }

    // Addon-leading, exact-episode routes search addons before asking the user
    // to choose a debrid provider. Direct addon links need no provider at all;
    // addon torrents still trigger the picker lazily inside playBest. Series
    // pack-first routes keep their existing provider-first contract because a
    // reusable torrent pack must be cache-probed before an episode fallback.
    var addonFallbackAlreadySearched = false;
    if (SourceSearchPlans.shouldSearchAddonsBeforeProvider(
      rules,
      isMovie: isMovie,
      hasPreferredProvider: preferredProvider != null,
    )) {
      resolving.dismiss();
      final fallBackToEngines =
          rules.sourceMode == QuickPlaySourceMode.addonsThenTorrents;
      final handled = await AddonStreamPlayback.playAddonStream(
        context,
        imdbId,
        isMovie: isMovie,
        season: season,
        episode: episode,
        meta: meta,
        label: label,
        rules: rules,
        forceAddonOnly: true,
        fallbackWhenEmpty: fallBackToEngines,

        sourceBindings: bindingOwner,
      );
      if ((!context.mounted || !bindingOwner.isCurrent) || handled) return;
      addonFallbackAlreadySearched = true;
      // The addon stage has already completed empty. Continue with only the
      // engine half instead of querying the same addons a second time.
      activeRules = rules.copyWith(
        sourceMode: QuickPlaySourceMode.torrentsOnly,
        preserveLegacyCombinedPackSearch: false,
      );
    }

    resolving.dismiss();
    final provider =
        preferredProvider ??
        await SourceProviderChoice.pickProvider(
          context,
          canContinue: () => context.mounted && bindingOwner.isCurrent,
        );
    if (!context.mounted || !bindingOwner.isCurrent) return;
    if (provider == SourceProviderConfig.cancelled) return;
    if (provider == null) {
      if (addonFallbackAlreadySearched) {
        SourceLoadingOverlays.snack(
          context,
          'No direct stream for "$label". Add a debrid provider in Settings for more sources.',
        );
        return;
      }
      if (!SourceSearchPlans.allowsAddonSearch(activeRules)) {
        SourceLoadingOverlays.snack(
          context,
          'No debrid provider configured. Add one in Settings to use torrent-only Quick Play.',
        );
        return;
      }
      // No debrid provider — but some titles still have a direct addon stream
      // that plays without one. Run an addon-only search and let playBest open
      // a direct link; if there's none it shows the "add a provider" snack.
      await AddonStreamPlayback.playAddonStream(
        context,
        imdbId,
        isMovie: isMovie,
        season: season,
        episode: episode,
        meta: meta,
        label: label,
        noProvider: true,
        rules: activeRules,

        sourceBindings: bindingOwner,
      );
      return;
    }
    // The Pipeline loader spans search → cache-check → prepare → start; its
    // checklist advances via setStage as this flow progresses.
    final cancel = PlaybackCancelToken();
    final overlay = SourceLoadingOverlays.showPipeline(
      context,
      provider: provider,
      meta: meta,
      title: label,
      onCancel: () => cancel.cancelled = true,
    );
    void closeLoading() => overlay.dismiss();

    // Quick-play filter ladder: saved default filters as a tiered preference
    // (full match → relax language → relax rip → anything). Inactive when no
    // filters are set or the Filter Settings toggle is off — then every
    // ladder call below is a no-op and behavior is unchanged. Size buckets are
    // movie-only (pack sizes are per-episode), so they're stripped for series.
    final ladder = await SourceFilterLadder.loadLadder(
      includeSize: isMovie,
      rules: activeRules,
    );
    if (cancel.cancelled) return; // Cancel during the prefs read
    if (!context.mounted || !bindingOwner.isCurrent) {
      closeLoading();
      return;
    }

    // Series auto-pin (on by default, toggle in Quick Play settings): with no
    // usable pinned source, search PACKS
    // first — the whole-series search with season probing, same as the
    // Sources screen's "Show Season Packs" — and play the widest pack that
    // actually contains the requested episode (complete series → multi-season
    // → season pack). _launch's auto-bind then pins the winner, so every later
    // play of this series goes straight through the bound path. When no pack
    // qualifies or none is instantly playable, fall through to the normal
    // episode search below (whose winner also gets pinned).
    // PikPak is excluded: it has no cache check, so each pack probe queues a
    // real (large) offline download to the user's account that can't be
    // cheaply cleaned up — pack-first there would be actively harmful.
    // The series pack route, shared by pack-FIRST (preferSeriesPacks on) and
    // pack-FALLBACK (off, episode search found nothing). Returns true when a
    // pack launched, false to continue, null when the flow must stop
    // (cancelled / unmounted).
    Future<bool?> tryPackRoute() async {
      // null = the SEARCH failed (transient network) — the episode search
      // still runs, and we DON'T poison the negative cache so the next
      // episode retries rather than deferring for the whole TTL.
      final packResult = await SeriesPackSearch.searchSeriesPackSources(
        imdbId: imdbId,
        label: label,
        season: season!,
        provider: provider,
        ladder: ladder,
        rules: activeRules,
        isCancelled: () =>
            cancel.cancelled || !context.mounted || !bindingOwner.isCurrent,
        onCacheCheck: () => overlay.setStage(PlayLoadStage.cacheCheck),
      );
      final searchOk = packResult != null;
      final packs = packResult ?? const <Torrent>[];
      if (cancel.cancelled) return null;
      if (!context.mounted || !bindingOwner.isCurrent) {
        closeLoading();
        return null;
      }
      SourceLoadingOverlays.applyLadderNote(overlay, ladder, packs);
      if (cancel.cancelled) return null;
      if (!context.mounted || !bindingOwner.isCurrent) {
        closeLoading();
        return null;
      }
      if (packs.isNotEmpty) {
        overlay.setStage(PlayLoadStage.preparing);
        final (packResolved, packWinner) = await SourceProbing.probeCandidates(
          provider,
          packs,
          sourceBindings: bindingOwner,
          season: season,
          episode: episode,
          rules: activeRules,
          isCancelled: () =>
              cancel.cancelled || !context.mounted || !bindingOwner.isCurrent,
        );
        if (cancel.cancelled) return null;
        if (!context.mounted || !bindingOwner.isCurrent) {
          closeLoading();
          return null;
        }
        if (packResolved != null && packWinner != null) {
          overlay.setStage(PlayLoadStage.starting);
          // No closeLoading here: the loader stays up through the launch prep
          // and _launch has it dismissed when the player takes the screen.
          final idx = packs.indexOf(packWinner);
          await SourcePlayerLaunch.launch(
            context,
            packResolved,
            packWinner.displayTitle,
            provider: provider,
            meta: meta,
            sources: packs,
            sourceIndex: idx < 0 ? 0 : idx,
            seriesFetcher: SourceSeriesFetcher.seriesFetcherFor(
              meta: meta,
              provider: provider,
              packsFetched: true,
            ),
            overlay: overlay,
            startupFailoverEnabled: true,

            sourceBindings: bindingOwner,
          );
          return true;
        }
        // No pack was instantly playable — fall through to the episode search.
      }
      // Reached only when no pack played (cancel / unmount paths returned
      // above). Remember it — but only when the search actually SUCCEEDED with
      // no playable pack (not a transient failure) — so the next episode of
      // this season skips the pack search until the TTL lapses.
      if (searchOk) {
        _markNoPack(
          imdbId,
          season,
          provider,
          activeRules,
          Duration(hours: activeRules.failedPackCacheHours),
        );
      }
      return false;
    }

    final packRouteAllowed =
        !isMovie &&
        !meta.hasStremioEpisodeIdentity &&
        season != null &&
        episode != null &&
        provider != 'pikpak' &&
        !_recentlyNoPack(imdbId, season, provider, activeRules) &&
        activeRules.packPreference != QuickPlayPackPreference.exactEpisodeOnly;

    final iptvFirst =
        activeRules.allowDirectLinks &&
        SourceSearchPlans.allowsAddonSearch(activeRules) &&
        activeRules.sourcePriority.isNotEmpty &&
        activeRules.sourcePriority.first.startsWith('iptv:');
    if (packRouteAllowed && activeRules.preferSeriesPacks) {
      if (iptvFirst) {
        final prioritizedPlaylistId = activeRules.sourcePriority.first
            .substring('iptv:'.length);
        logIptvSourceEvent(
          'quick_play_priority_probe_started',
          playlistId: prioritizedPlaylistId,
          catalogType: 'series',
          season: season,
          episode: episode,
        );
        final matches = await IptvQuickPlaySearch.searchIptvForQuickPlay(
          imdbId,
          meta.title ?? label,
          meta.year,
          isMovie,
          season,
          episode,
          activeRules,
          () => cancel.cancelled,
        );
        final prioritized = SourceCandidateRanking.orderCandidatesForRules(
          matches
              .where((t) => t.source == activeRules.sourcePriority.first)
              .toList(),
          rules: activeRules,
          ladder: ladder,
        );
        logIptvSourceEvent(
          'quick_play_priority_probe_candidates',
          playlistId: prioritizedPlaylistId,
          catalogType: 'series',
          season: season,
          episode: episode,
          resultCount: prioritized.length,
          outcome: prioritized.isEmpty ? 'no_match' : 'matched',
        );
        final iptvPriorityDeadline = DateTime.now().add(
          SourceIptvAvailability.iptvQuickPlaySearchTimeout,
        );
        for (final descriptor in prioritized.take(
          SourceCandidateRanking.directValidationBudgetForRules(activeRules),
        )) {
          if (cancel.cancelled ||
              (!context.mounted || !bindingOwner.isCurrent)) {
            return;
          }
          try {
            var source = descriptor;
            if (IptvSourceSearch.isDeferredXtreamSeries(source)) {
              final remaining = iptvPriorityDeadline.difference(DateTime.now());
              if (remaining <= Duration.zero) break;
              final resolution =
                  await IptvSourceSearch.resolveXtreamSeriesEpisode(
                    source,
                    season: season,
                    episode: episode,
                  ).timeout(
                    remaining,
                    onTimeout: () => const IptvEpisodeResolution(
                      IptvEpisodeResolutionStatus.unavailable,
                    ),
                  );
              if (resolution.source == null) continue;
              source = resolution.source!;
            }
            await DirectSourceAuthorization.authorize(source);
            final alive =
                !activeRules.validateDirectLinks ||
                !SourceCandidateRanking.shouldPreflightDirectStream(source) ||
                await StreamUrlValidator.isPlayableVideoUrl(
                  source.directUrl!,
                  minBytes: 10 * 1024 * 1024,
                  lenient: true,
                  headers: source.httpHeaders,
                );
            if (!alive) {
              logIptvSourceEvent(
                'quick_play_candidate_rejected',
                source: source,
                stage: 'preflight',
                outcome: 'unplayable',
                season: season,
                episode: episode,
              );
              continue;
            }
            if (cancel.cancelled ||
                (!context.mounted || !bindingOwner.isCurrent)) {
              return;
            }
            logIptvSourceEvent(
              'quick_play_candidate_selected',
              source: source,
              outcome: 'priority_winner',
              season: season,
              episode: episode,
            );
            await AutomaticPlayBest.playBest(
              context,
              [source],
              provider: provider,
              title: label,
              meta: meta,
              overlay: overlay,
              isCancelled: () =>
                  cancel.cancelled ||
                  !context.mounted ||
                  !bindingOwner.isCurrent,
              ladder: ladder,
              rules: activeRules.copyWith(validateDirectLinks: false),
              seriesFetcher: SourceSeriesFetcher.seriesFetcherFor(
                meta: meta,
                provider: provider,
              ),

              sourceBindings: bindingOwner,
            );
            return;
          } catch (error) {
            // Revoked or unusable IPTV must not disable the preferred pack route.
            logIptvSourceEvent(
              'quick_play_candidate_rejected',
              source: descriptor,
              stage: 'authorization_or_probe',
              outcome: 'failed',
              season: season,
              episode: episode,
              error: error,
            );
          }
        }
      }
      if (cancel.cancelled || (!context.mounted || !bindingOwner.isCurrent)) {
        return;
      }
      final packed = await tryPackRoute();
      if (packed != false) return;
    }

    List<Torrent> torrents;
    try {
      torrents = await CuratedSourceSearch.searchCuratedSources(
        imdbId: imdbId,
        label: label,
        year: meta.year,
        isMovie: isMovie,
        season: season,
        episode: episode,
        provider: provider,
        rules: activeRules,
        originMeta: meta,
        isCancelled: () =>
            cancel.cancelled || !context.mounted || !bindingOwner.isCurrent,
        onResults: (n) =>
            overlay.setStage(PlayLoadStage.searching, sourceCount: n),
      );
    } catch (e) {
      if (cancel.cancelled) return; // overlay already dismissed by Cancel
      closeLoading();
      if (context.mounted) {
        SourceLoadingOverlays.snack(context, 'Search failed: $e');
      }
      return;
    }
    if (cancel.cancelled) return;
    if (!context.mounted || !bindingOwner.isCurrent) {
      closeLoading();
      return;
    }
    // Apply the same Addon Priority/filter ordering that [playBest] will use
    // before probing lazy IPTV rows. Otherwise catalog order can make a slow
    // lower-priority playlist consume the deadline ahead of the user's first
    // choice.
    torrents = SourceCandidateRanking.orderCandidatesForRules(
      torrents,
      rules: activeRules,
      ladder: ladder,
    );
    if (packRouteAllowed &&
        !activeRules.preferSeriesPacks &&
        torrents.any(IptvSourceSearch.isDeferredXtreamSeries)) {
      torrents = await SourceIptvAvailability.confirmDeferredIptvAvailability(
        torrents,
        season: season,
        episode: episode,
        isCancelled: () =>
            cancel.cancelled || !context.mounted || !bindingOwner.isCurrent,
      );
      if (cancel.cancelled) return;
      if (!context.mounted || !bindingOwner.isCurrent) {
        closeLoading();
        return;
      }
    }
    if (!torrents.any(SourceCandidateRanking.isAutoPlayableCandidate)) {
      // Episode-first route (Prefer season packs off): packs are the
      // FALLBACK when the episode search comes up dry, so a show that only
      // exists as packs still plays. Deferred IPTV title matches count only
      // after one of them resolves the requested episode.
      if (packRouteAllowed && !activeRules.preferSeriesPacks) {
        final packed = await tryPackRoute();
        if (packed != false) return;
      }
      closeLoading();
      SourceLoadingOverlays.snack(context, 'No sources found for "$label".');
      return;
    }

    // The list was ranked before lazy IPTV probing so the fallback gate and
    // automatic playback agree on which provider comes first. [playBest]
    // performs its own final defensive ordering before selection.
    if (torrents.isEmpty) {
      closeLoading();
      SourceLoadingOverlays.snack(
        context,
        'No sources match your Quick Play rules for "$label".',
      );
      return;
    }
    SourceLoadingOverlays.applyLadderNote(overlay, ladder, torrents);
    await AutomaticPlayBest.playBest(
      context,
      torrents,
      provider: provider,
      title: label,
      meta: meta,
      overlay: overlay,
      isCancelled: () =>
          cancel.cancelled || !context.mounted || !bindingOwner.isCurrent,
      ladder: ladder,
      rules: activeRules,
      // The dedicated episode fetch just ran; the pack tab stays fetchable
      // even when the pack-first search ran earlier — its results were
      // discarded (nothing instantly playable), so "Load more" re-lists
      // them for a manual pick.
      seriesFetcher: SourceSeriesFetcher.seriesFetcherFor(
        meta: meta,
        provider: provider,
        episodesFetched: true,
      ),

      sourceBindings: bindingOwner,
    );
  }
}
