import 'dart:async';

import 'package:debrify/features/sources/application/source_cache_ordering.dart';
import 'package:debrify/features/sources/application/source_candidate_checks.dart';
import 'package:debrify/features/sources/application/source_candidate_ranking.dart';
import 'package:debrify/features/sources/application/source_iptv_availability.dart';
import 'package:debrify/features/sources/application/source_probing.dart';
import 'package:debrify/features/sources/application/source_provider_config.dart';
import 'package:debrify/features/sources/data/automatic_source_bindings.dart';
import 'package:debrify/features/sources/data/source_binding_committer.dart';
import 'package:debrify/features/sources/presentation/legacy_playback/source_loading_overlays.dart';
import 'package:debrify/features/sources/presentation/legacy_playback/source_next_episode.dart';
import 'package:debrify/features/sources/presentation/legacy_playback/source_player_args.dart';
import 'package:debrify/features/sources/presentation/legacy_playback/source_player_launch.dart';
import 'package:debrify/features/sources/presentation/legacy_playback/source_provider_choice.dart';
import 'package:debrify/models/playback_meta.dart';
import 'package:debrify/models/quick_play_rules.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/services/direct_source_authorization.dart';
import 'package:debrify/services/iptv_source_search.dart';
import 'package:debrify/services/series_source_fetcher.dart';
import 'package:debrify/services/series_source_service.dart';
import 'package:debrify/services/source_selection_diagnostics.dart';
import 'package:debrify/services/stream_url_validator.dart';
import 'package:debrify/services/video_player_launcher.dart';
import 'package:debrify/utils/filter_ladder.dart';
import 'package:debrify/widgets/pipeline_loading_overlay.dart';
import 'package:flutter/material.dart';

final class AutomaticPlayBest {
  const AutomaticPlayBest._();

  /// Catalog "Play" — auto-pick the best instantly-playable source and play it.
  /// Cache-first ordering for TorBox/Premiumize; the resolve loop cleans up any
  /// uncached torrent it probes on RD/AllDebrid so the account isn't polluted.
  static Future<void> playBest(
    BuildContext context,
    List<Torrent> torrents, {
    String? provider,
    String? title,
    PlaybackMeta? meta,
    // Non-null when the search flow already put a loader up (the search phase);
    // null for a standalone play (e.g. the catalog board), which creates one.
    PipelineLoadingOverlay? overlay,
    bool Function()? isCancelled,
    // Quick-play filter ladder (QUICK_PLAY_FILTERS_PLAN.md): ranks candidates
    // by filter strictness. Null/inactive ⇒ byte-identical legacy behavior.
    FilterLadder? ladder,
    QuickPlayRules? rules,
    // "Load more sources" backend for the player's series source tabs; rides
    // through to the launch untouched. Null ⇒ flat source list (unchanged).
    SeriesSourceFetcher? seriesFetcher,
    AutomaticSourceBindings? sourceBindings,
  }) async {
    final bindingOwner = sourceBindings ?? AutomaticSourceBindings.capture();
    if (!context.mounted || !bindingOwner.isCurrent) {
      overlay?.dismiss();
      return;
    }
    if (rules != null) {
      torrents = SourceCandidateRanking.orderCandidatesForRules(
        torrents,
        rules: rules,
        ladder: ladder,
      );
    } else if (ladder != null && ladder.isActive) {
      // Legacy callers without a profile retain their historical ordering.
      torrents = ladder.order(torrents);
    }
    final rootNav = Navigator.of(context, rootNavigator: true);
    // The play loader handle: passed in by the search flow, or created below
    // for a standalone play (e.g. the catalog board). Dismissed exactly once.
    var ov = overlay;
    void closeLoading() {
      if (ov != null) {
        ov.dismiss();
      } else if (rootNav.canPop()) {
        rootNav.pop();
      }
    }

    bool cancelled() {
      if (!context.mounted || !bindingOwner.isCurrent) {
        ov?.dismiss();
        return true;
      }
      return isCancelled?.call() ?? false;
    }

    // Plays a direct-URL addon stream instantly (no debrid needed). Content
    // metadata and the Sources switcher ride along (matching Home's
    // _playDirectStream) so series streams get Continue Watching, subtitles,
    // source switching, and the Next Episode hand-back. The advance reuses
    // [provider] when the caller resolved one (torrent chain); otherwise it
    // stays on the bound-sources → addon-stream path this play came from.
    Future<void> playDirect(Torrent direct) async {
      logSourceSelection(
        'quick_play_direct_selected',
        source: direct,
        index: torrents.indexOf(direct),
        season: meta?.season,
        episode: meta?.episode,
      );
      // The loader (when one is up) stays through the launch prep; the
      // launcher dismisses it the moment the player takes the screen, and
      // guarantees the dismissal on failure so it can never linger. The
      // finally only covers a throw BEFORE push() takes the callback (args
      // built up front for exactly that reason) — after which the launcher
      // owns the dismissal.
      final loader = ov;
      var handedToLauncher = false;
      SourceBindingCommitter? committer;
      try {
        await DirectSourceAuthorization.authorize(direct);
        final resolverProvider =
            provider ??
            await SourceProviderConfig.defaultConfiguredProvider(
              canContinue: () => context.mounted && bindingOwner.isCurrent,
            );
        if (!context.mounted || !bindingOwner.isCurrent) return;
        committer = SourcePlayerLaunch.validatedLaunchCommitter(
          resolverProvider ?? SeriesSource.addonDirectService,
          meta,
          sourceBindings: bindingOwner,
        );
        final args = SourcePlayerArgs.playerArgs(
          videoUrl: direct.directUrl!,
          httpHeaders: direct.httpHeaders,
          title: direct.displayTitle,
          subtitle: direct.source.isNotEmpty ? direct.source : null,
          stremioSources: torrents,
          stremioCurrentSourceIndex: torrents.indexOf(direct),
          resolveSourceToPlaylist:
              (torrents.length > 1 || seriesFetcher != null)
              ? (resolverProvider == null
                    ? SourcePlayerLaunch.lazyProviderResolver(committer)
                    : SourcePlayerLaunch.resolverFor(
                        resolverProvider,
                        committer,
                      ))
              : null,
          startupFailoverEnabled: true,
          startupResolverProvider: resolverProvider,
          onStremioSourceCommitted: committer.call,
          seriesSourceFetcher: seriesFetcher,
          meta: meta,
        );
        final nextEpisodeHandler = SourceNextEpisode.nextEpisodeHandlerFor(
          context,
          meta,
          provider: provider,

          sourceBindings: bindingOwner,
        );
        handedToLauncher = loader != null;
        await VideoPlayerLauncher.push(
          context,
          args,
          retainSourceSession: committer.retain,
          sourceOwner: committer.bindings.owner,
          canContinue: () => committer!.isCurrent,
          onPlayerHandoff: loader?.dismiss,
          onQuickPlayNextEpisode: nextEpisodeHandler,
        );
      } finally {
        committer?.close();
        if (!handedToLauncher) loader?.dismiss();
      }
    }

    // Direct links carry no implicit validation (a torrent's debrid resolve
    // IS its probe), and dead hosts love serving tiny placeholder videos with
    // a 200 — so every direct play below runs through a HEAD check first
    // (same validator Stremio TV always used) and steps to the next candidate
    // on failure. VOD ONLY: live channels (non-movie/series catalog plays)
    // routinely stream without a content-length and would all read as dead —
    // they keep the unvalidated instant play. The budget bounds worst-case
    // added latency; once spent, remaining candidates play unvalidated (the
    // pre-validation behavior), so validation can only ever improve a play,
    // never lose one.
    final validatableVod =
        meta?.contentType == 'movie' || meta?.contentType == 'series';
    // Real sub-50MB episodes exist (480p / anime shorts) — the movie floor
    // would false-negative them; genuine error-placeholders are under ~5MB.
    final minStreamBytes = meta?.contentType == 'series'
        ? 10 * 1024 * 1024
        : StreamUrlValidator.minContentBytes;
    final deadDirectUrls = <String>{};
    var validationBudget =
        SourceCandidateRanking.directValidationBudgetForRules(rules);
    final lazyIptvResolutions = <String, Future<IptvEpisodeResolution>>{};
    final lazyIptvDeadline = DateTime.now().add(
      SourceIptvAvailability.iptvQuickPlaySearchTimeout,
    );
    Future<Torrent?> resolveDirect(Torrent t) async {
      if (!IptvSourceSearch.isDeferredXtreamSeries(t)) return t;
      final resolution = await lazyIptvResolutions.putIfAbsent(t.infohash, () {
        final remaining = lazyIptvDeadline.difference(DateTime.now());
        if (remaining <= Duration.zero) {
          return Future.value(
            const IptvEpisodeResolution(
              IptvEpisodeResolutionStatus.unavailable,
            ),
          );
        }
        return IptvSourceSearch.resolveXtreamSeriesEpisode(
          t,
          season: meta?.season,
          episode: meta?.episode,
        ).timeout(
          remaining,
          onTimeout: () => const IptvEpisodeResolution(
            IptvEpisodeResolutionStatus.unavailable,
          ),
        );
      });
      final resolved = resolution.source;
      if (resolved == null) {
        logIptvSourceEvent(
          'quick_play_candidate_rejected',
          source: t,
          stage: 'episode_resolution',
          outcome: resolution.status.name,
          season: meta?.season,
          episode: meta?.episode,
        );
        return null;
      }
      final index = torrents.indexOf(t);
      if (index >= 0) torrents[index] = resolved;
      return resolved;
    }

    Future<Torrent?> directLooksAlive(Torrent candidate) async {
      final t = await resolveDirect(candidate);
      if (t == null) return null;
      try {
        await DirectSourceAuthorization.authorize(t);
      } catch (_) {
        return null;
      }
      logSourceSelection(
        'quick_play_direct_candidate',
        source: t,
        index: torrents.indexOf(t),
        season: meta?.season,
        episode: meta?.episode,
      );
      if (rules?.validateDirectLinks == false) return t;
      if (!validatableVod) return t;
      // AIOStreams/debrid proxy URLs can be single-use or bind themselves to
      // the address family of the first request. Probing one through Dart's
      // HTTP stack and then opening it through media-kit/ExoPlayer can turn a
      // healthy link into a provider-generated "Wrong IP" slate (IPv6 HEAD,
      // IPv4 playback). These URLs must be opened first by the real player;
      // its startup gate owns failure detection and candidate failover.
      if (!SourceCandidateRanking.shouldPreflightDirectStream(t)) {
        final bypassReason = IptvSourceSearch.owns(t)
            ? 'iptv_player_validation'
            : 'ip_bound_addon';
        debugPrint(
          '[StartupFailover] event=preflight_bypass platform=flutter '
          'reason=$bypassReason addon=${t.stremioAddonId ?? '-'}',
        );
        return t;
      }
      final url = t.directUrl!;
      if (deadDirectUrls.contains(
        SourceCandidateChecks.directValidationKey(t),
      )) {
        debugPrint(
          '[StartupFailover] event=preflight_result platform=flutter '
          'ok=false reason=known_dead',
        );
        return null;
      }
      if (validationBudget <= 0) {
        debugPrint(
          '[StartupFailover] event=preflight_bypass platform=flutter '
          'reason=budget_exhausted',
        );
        return t; // budget spent — trust it
      }
      validationBudget--;
      debugPrint(
        '[StartupFailover] event=preflight_begin platform=flutter '
        'remainingBudget=$validationBudget minBytes=$minStreamBytes',
      );
      // Lenient: only positive evidence of death rejects — HEAD-refusing
      // hosts and length-less 2xx responses give no signal and whole CDNs
      // fail them identically, which would kill every candidate at once.
      final alive = await StreamUrlValidator.isPlayableVideoUrl(
        url,
        minBytes: minStreamBytes,
        lenient: true,
        headers: t.httpHeaders,
      );
      logSourceSelection(
        'quick_play_direct_preflight',
        source: t,
        reason: alive ? 'accepted_for_player_validation' : 'rejected',
      );
      debugPrint(
        '[StartupFailover] event=preflight_result platform=flutter '
        'ok=$alive remainingBudget=$validationBudget',
      );
      if (!alive) {
        deadDirectUrls.add(SourceCandidateChecks.directValidationKey(t));
        ov?.setNote('Skipped a dead stream link — trying the next source…');
      }
      return alive ? t : null;
    }

    // Walks every direct stream in (tier-ordered) list order and plays the
    // first one that validates. Returns true when it handled the play (or the
    // user cancelled mid-walk); false when no direct stream survived.
    Future<bool> playFirstAliveDirect() async {
      for (final t in torrents) {
        final isDirect = SourceCandidateChecks.isDirectCandidate(t);
        if (!isDirect) continue;
        if (cancelled()) return true; // overlay dismissed by the Cancel tap
        final playable = await directLooksAlive(t);
        if (playable != null) {
          if (cancelled()) return true;
          await playDirect(playable);
          return true;
        }
      }
      return false;
    }

    final bool tiered = ladder != null && ladder.isActive;

    // Exact-order is deliberately isolated from the legacy/direct-first path:
    // walk the provider/transport-ordered list and attempt each playable entry
    // in place. Provider-specific torrent preparation happens when the walk
    // first reaches a torrent, so a leading direct stream still plays without
    // prompting for (or waiting on) a debrid provider.
    if (rules?.ranking == QuickPlayRanking.exactOrder) {
      var exactSources = List<Torrent>.from(torrents);
      var strictProvider = provider;
      var providerWasChecked = provider != null;
      var providerUnavailable = false;
      var providerPrepared = false;
      var pikPakTorrentProbed = false;
      var attempts = 0;
      var limit = rules!.tryNextOnFailure ? rules.maxAttempts : 1;
      for (
        var candidateIndex = 0;
        candidateIndex < exactSources.length;
        candidateIndex++
      ) {
        final source = exactSources[candidateIndex];
        if (cancelled()) break;
        if (source.streamType == StreamType.externalUrl) continue;
        final isDirect = SourceCandidateChecks.isDirectCandidate(source);
        final isTorrent = SourceCandidateChecks.hasAcquisition(source);
        if (!isDirect && !isTorrent) continue;

        if (isDirect) {
          final playable = await directLooksAlive(source);
          if (playable != null) {
            if (cancelled()) return;
            await playDirect(playable);
            return;
          }
          continue;
        }

        if (!context.mounted || !bindingOwner.isCurrent) {
          if (ov != null) closeLoading();
          return;
        }
        if (!providerWasChecked) {
          strictProvider = await SourceProviderChoice.pickProvider(
            context,
            canContinue: () => context.mounted && bindingOwner.isCurrent,
          );
          providerWasChecked = true;
          providerUnavailable = strictProvider == null;
        }
        if (!context.mounted || !bindingOwner.isCurrent) {
          if (ov != null) closeLoading();
          return;
        }
        if (strictProvider == SourceProviderConfig.cancelled) {
          if (ov != null) closeLoading();
          return;
        }
        // A torrent that cannot be attempted is not a failed source and must
        // not consume the result budget or hide a provider-free direct link
        // later in the exact returned order.
        if (strictProvider == null) continue;

        if (!providerPrepared) {
          var preparedTorrents = exactSources
              .where(
                (t) =>
                    t.streamType == StreamType.torrent &&
                    SourceCandidateChecks.hasAcquisition(t),
              )
              .toList();
          if (strictProvider == 'torbox' || strictProvider == 'premiumize') {
            ov ??= SourceLoadingOverlays.showPipeline(
              context,
              provider: strictProvider,
              meta: meta,
              title: title ?? source.displayTitle,
            );
            ov.setStage(
              PlayLoadStage.searching,
              sourceCount: preparedTorrents.length,
            );
            ov.setStage(PlayLoadStage.cacheCheck);
            preparedTorrents = await SourceCacheOrdering.cacheFirst(
              strictProvider,
              preparedTorrents,
            );
            preparedTorrents =
                SourceCandidateRanking.orderCacheCheckedCandidatesForRules(
                  preparedTorrents,
                  rules: rules,
                  ladder: ladder,
                );
            if (!context.mounted || !bindingOwner.isCurrent) {
              closeLoading();
              return;
            }
            if (cancelled()) return;
          }
          if (tiered) {
            final (safeTorrents, safeAttempts) = SourceProbing.packTopSafety(
              preparedTorrents,
              provider: strictProvider,
              ladder: ladder,
              season: meta?.season,
              episode: meta?.episode,
            );
            preparedTorrents = safeTorrents;
            if (safeAttempts > limit) limit = safeAttempts;
          }
          exactSources = SourceCandidateRanking.mergePreparedTorrentOrder(
            exactSources,
            preparedTorrents,
          );
          torrents = exactSources;
          providerPrepared = true;
          // Cache-first and PikPak safety may have changed the first torrent.
          // Restart so the prepared order, including any leading direct rows,
          // is the only order consumed by the attempt budget.
          candidateIndex = -1;
          continue;
        }

        // maxAttempts caps debrid acquisition attempts. Keep walking past the
        // cap so a provider-free direct stream later in the returned order can
        // still rescue playback, as it does in the legacy selection path.
        if (attempts >= limit) continue;
        // PikPak's one-probe safety is per PLAY, not per `_probeCandidates`
        // invocation. Keep walking so a later direct link can still play, but
        // never queue a second cloud download during this exact-order pass.
        if (strictProvider == 'pikpak' && pikPakTorrentProbed) continue;
        attempts++;
        if (strictProvider == 'pikpak') pikPakTorrentProbed = true;
        ov ??= SourceLoadingOverlays.showPipeline(
          context,
          provider: strictProvider,
          meta: meta,
          title: title ?? source.displayTitle,
        );
        ov.setStage(PlayLoadStage.preparing);
        final (resolved, winner) = await SourceProbing.probeCandidates(
          strictProvider,
          [source],
          sourceBindings: bindingOwner,
          season: meta?.season,
          episode: meta?.episode,
          rules: rules.copyWith(tryNextOnFailure: false, maxAttempts: 1),
          isCancelled: cancelled,
        );
        if (!context.mounted || !bindingOwner.isCurrent) {
          closeLoading();
          return;
        }
        if (resolved == null || winner == null) continue;
        if (cancelled()) return;
        ov.setStage(PlayLoadStage.starting);
        await SourcePlayerLaunch.launch(
          context,
          resolved,
          winner.displayTitle,
          provider: strictProvider,
          meta: meta,
          sources: torrents,
          sourceIndex: torrents.indexOf(winner),
          seriesFetcher: seriesFetcher,
          overlay: ov,
          startupFailoverEnabled: true,

          sourceBindings: bindingOwner,
        );
        return;
      }
      if (ov != null) closeLoading();
      if (context.mounted) {
        SourceLoadingOverlays.snack(
          context,
          providerUnavailable
              ? 'No direct stream played. Add a debrid provider in Settings for torrent sources.'
              : 'No source in the selected order was instantly playable.',
        );
      }
      return;
    }

    // A direct-URL addon stream, if present, is the cheapest instant play — and
    // needs no debrid provider, so play it before prompting for one. This is the
    // IPTV / non-IMDb catalog path (streams come straight from the addon).
    // With an active ladder, it plays NOW only from the best PLAYABLE tier
    // (a full-match torrent beats a relaxed-tier direct link, plan §3.4) —
    // while relaxed-tier direct links rescue every torrent-path dead end
    // below (playFirstAliveDirect), so the ladder can only ever reorder,
    // never lose the instant play the pre-ladder flow guaranteed. A direct
    // that fails validation is dropped and the selection re-runs: the next
    // pick may be another direct (instant play again) or a torrent now
    // holding the best playable tier (falls through to the probe path).
    if (SourceCandidateRanking.shouldTryDirectBeforeTorrent(rules)) {
      var selectable = torrents;
      var direct = SourceProbing.selectDirect(selectable, ladder).$1;
      while (direct != null) {
        if (cancelled()) return; // e.g. Cancel during a caller's await
        final playable = await directLooksAlive(direct);
        if (playable != null) {
          if (cancelled()) return;
          await playDirect(playable);
          return;
        }
        final dead = direct;
        selectable = selectable.where((t) => !identical(t, dead)).toList();
        direct = SourceProbing.selectDirect(selectable, ladder).$1;
      }
    }

    // Every direct link VALIDATED dead and nothing probeable exists: a
    // provider prompt (or "no provider" snack) would be nonsense — the play
    // failed because the stream links are down, say so. Budget-exhausted
    // directs are NOT in the dead set, so when unvalidated candidates remain
    // this can't fire and the trust-play rescue below still runs.
    if (deadDirectUrls.isNotEmpty &&
        !torrents.any(
          (t) =>
              t.streamType != StreamType.externalUrl &&
              SourceCandidateChecks.hasAcquisition(t),
        ) &&
        !torrents.any(
          (t) =>
              SourceCandidateChecks.isDirectCandidate(t) &&
              !deadDirectUrls.contains(
                SourceCandidateChecks.directValidationKey(t),
              ),
        )) {
      if (ov != null) closeLoading();
      if (context.mounted) {
        SourceLoadingOverlays.snack(
          context,
          "This title's stream links appear to be offline. Open Sources to try one manually.",
        );
      }
      return;
    }

    final prov =
        provider ??
        await SourceProviderChoice.pickProvider(
          context,
          canContinue: () => context.mounted && bindingOwner.isCurrent,
        );
    // These bail-outs are reachable when the caller passed no provider (the
    // non-IMDb addon-stream path with only torrent results). Dismiss the
    // caller's overlay on each, or it stays stuck full-screen (both overlays
    // are non-dismissable by the system back button).
    if (!context.mounted || !bindingOwner.isCurrent) {
      if (ov != null) closeLoading();
      return;
    }
    if (prov == SourceProviderConfig.cancelled) {
      if (ov != null) closeLoading(); // user dismissed the picker
      return;
    }
    if (prov == null) {
      // Without a provider no torrent can play — a relaxed-tier direct link
      // is still the guaranteed instant play (pre-ladder behavior).
      if (await playFirstAliveDirect()) return;
      if (ov != null) closeLoading();
      SourceLoadingOverlays.snack(
        context,
        'No debrid provider configured. Add one in Settings.',
      );
      return;
    }

    var candidates = torrents
        .where(
          (t) =>
              t.streamType != StreamType.externalUrl &&
              SourceCandidateChecks.hasAcquisition(t),
        )
        .toList();
    if (candidates.isEmpty) {
      if (await playFirstAliveDirect()) return;
      if (ov != null) closeLoading();
      SourceLoadingOverlays.snack(
        context,
        'No playable sources found for this title.',
      );
      return;
    }
    // Standalone play (no loader passed by the search flow): show one now.
    ov ??= SourceLoadingOverlays.showPipeline(
      context,
      provider: prov,
      meta: meta,
      title: title ?? candidates.first.displayTitle,
    );
    final loader = ov;
    loader.setStage(PlayLoadStage.searching, sourceCount: candidates.length);
    if (prov == 'torbox' || prov == 'premiumize') {
      loader.setStage(PlayLoadStage.cacheCheck);
      candidates = await SourceCacheOrdering.cacheFirst(prov, candidates);
      // One cache call for the whole list, then a stable tier re-sort:
      // filters dominate cachedness, cached-first survives WITHIN each tier
      // (plan §3.4, "cache-first demoted to within-tier").
      if (rules != null) {
        candidates = SourceCandidateRanking.orderCacheCheckedCandidatesForRules(
          candidates,
          rules: rules,
          ladder: ladder,
        );
      } else if (tiered) {
        candidates = ladder.order(candidates);
      }
      if (!context.mounted || !bindingOwner.isCurrent) {
        // Screen went away mid cache-check — dismiss so the loader can't get
        // stuck covering the next screen.
        closeLoading();
        return;
      }
    }
    if (cancelled()) return; // user tapped Cancel during the cache-check

    // Base tier for probe narration — captured BEFORE the pack-top safety,
    // so a hoisted relaxed-tier single still triggers the tier-crossing note.
    final int probeBaseTier = tiered && candidates.isNotEmpty
        ? ladder.tierOf(candidates.first)
        : 0;
    // Pack-top safety (§3.4b.3), applied AFTER every ladder/cache re-sort so
    // no later ordering can undo it: if the ladder promoted a pack over every
    // exact-episode single, guarantee the best single still gets probed.
    var minAttempts = 1;
    if (tiered) {
      final (safeList, safeAttempts) = SourceProbing.packTopSafety(
        candidates,
        provider: prov,
        ladder: ladder,
        season: meta?.season,
        episode: meta?.episode,
      );
      candidates = safeList;
      minAttempts = safeAttempts;
    }

    loader.setStage(PlayLoadStage.preparing);
    final (res, winner) = await SourceProbing.probeCandidates(
      prov,
      candidates,
      sourceBindings: bindingOwner,
      season: meta?.season,
      episode: meta?.episode,
      rules: rules,
      isCancelled: cancelled,
      minAttempts: minAttempts,
      onCandidate: !tiered
          ? null
          : (t) {
              // Narrate tier crossings while probing (try-multiple / the
              // pack-top safety attempt).
              final tier = ladder.tierOf(t);
              if (tier > probeBaseTier) {
                loader.setNote(
                  "Filtered match wasn't playable — trying "
                  '${ladder.describeTier(tier) ?? 'any available source'}',
                );
              }
            },
    );
    if (cancelled()) return; // dismissed by the Cancel tap; nothing more to do
    loader.setStage(PlayLoadStage.starting);
    if (!context.mounted || !bindingOwner.isCurrent) {
      closeLoading();
      return;
    }
    if (res == null) {
      // Every probe failed — a ladder-demoted direct link still guarantees
      // the play the pre-ladder flow would have delivered (playDirect keeps
      // the loader up and hands its dismissal to the launcher).
      if (await playFirstAliveDirect()) return;
      closeLoading();
      SourceLoadingOverlays.snack(
        context,
        'No instantly-playable source found. Open Sources to pick or download one.',
      );
      return;
    }
    final idx = torrents.indexOf(winner!);
    await SourcePlayerLaunch.launch(
      context,
      res,
      winner.displayTitle,
      provider: prov,
      meta: meta,
      sources: torrents,
      sourceIndex: idx < 0 ? 0 : idx,
      seriesFetcher: seriesFetcher,
      overlay: loader,
      startupFailoverEnabled: true,

      sourceBindings: bindingOwner,
    );
  }
}
