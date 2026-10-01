import 'dart:async';

import 'package:debrify/features/sources/application/source_candidate_checks.dart';
import 'package:debrify/features/sources/application/source_candidate_ranking.dart';
import 'package:debrify/features/sources/application/source_curation.dart';
import 'package:debrify/features/sources/application/source_filter_ladder.dart';
import 'package:debrify/features/sources/application/source_iptv_availability.dart';
import 'package:debrify/features/sources/application/source_search_plans.dart';
import 'package:debrify/features/sources/data/automatic_source_bindings.dart';
import 'package:debrify/features/sources/data/curated_source_search.dart';
import 'package:debrify/features/sources/data/iptv_quick_play_search.dart';
import 'package:debrify/features/sources/data/source_movie_fetcher.dart';
import 'package:debrify/features/sources/data/source_series_fetcher.dart';
import 'package:debrify/features/sources/models/playback_cancel_token.dart';
import 'package:debrify/features/sources/models/resolved_source.dart';
import 'package:debrify/features/sources/presentation/legacy_playback/automatic_play_best.dart';
import 'package:debrify/features/sources/presentation/legacy_playback/source_loading_overlays.dart';
import 'package:debrify/features/sources/presentation/legacy_playback/source_player_launch.dart';
import 'package:debrify/models/playback_meta.dart';
import 'package:debrify/models/quick_play_rules.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/series_source_service.dart';
import 'package:debrify/services/stream_url_validator.dart';
import 'package:debrify/services/stremio_service.dart';
import 'package:debrify/services/torrent_service.dart';
import 'package:flutter/material.dart';

final class AddonStreamPlayback {
  const AddonStreamPlayback._();

  static Future<bool> playAddonStream(
    BuildContext context,
    String id, {
    required bool isMovie,
    int? season,
    int? episode,
    required PlaybackMeta meta,
    required String label,
    required QuickPlayRules rules,
    // No-provider fast path: a `tt` title with no debrid configured. Search
    // addons ONLY (skip the torrent engines whose results couldn't play
    // anyway), and when nothing turns up point the user at Settings instead of
    // the generic "no stream" message — adding a provider is the real fix.
    bool noProvider = false,
    // Used by addon-leading profiles before a provider is selected. It keeps
    // this pass strictly on addons; when empty, addons-then-engines can dismiss
    // the neutral loader and continue into its engine fallback.
    bool forceAddonOnly = false,
    bool fallbackWhenEmpty = false,
    required AutomaticSourceBindings sourceBindings,
  }) async {
    final cancel = PlaybackCancelToken();
    // Direct addon/IPTV stream — the loader dismisses as soon as playBest opens
    // the direct stream. Neutral "Stream" identity (no debrid provider).
    final overlay = SourceLoadingOverlays.showPipeline(
      context,
      provider: 'stream',
      meta: meta,
      title: label,
      onCancel: () => cancel.cancelled = true,
    );
    void closeLoading() => overlay.dismiss();

    final addonTimeout = rules.addonTimeoutSeconds == 15
        ? null
        : Duration(seconds: rules.addonTimeoutSeconds);
    final engineTimeout = rules.searchTimeoutSeconds == 0
        ? null
        : Duration(seconds: rules.searchTimeoutSeconds);
    final exactAddonOrder = rules.ranking == QuickPlayRanking.exactOrder;
    final originVideoId = await CuratedSourceSearch.originEpisodeVideoId(
      meta,
      season,
      episode,
    );
    if (meta.hasStremioEpisodeIdentity && originVideoId == null) {
      closeLoading();
      if (context.mounted) {
        SourceLoadingOverlays.snack(
          context,
          'This episode is not available from its catalog.',
        );
      }
      return true;
    }
    final earlyScope = ProfileRuntime.scope.value;
    final early = Completer<Map<String, dynamic>>();
    final earlyLadder = await SourceFilterLadder.loadLadder(
      includeSize: isMovie,
      rules: rules,
    );
    String? leadingAddon;
    // An exact-order addon-only pass can decide as soon as its FIRST provider
    // answers. Global-quality and torrent-preferred searches need all results.
    if (!isMovie &&
        !meta.hasStremioEpisodeIdentity &&
        id.startsWith('tt') &&
        season != null &&
        episode != null &&
        rules.allowDirectLinks &&
        rules.tryNextOnFailure &&
        exactAddonOrder &&
        !SourceCandidateRanking.prefersTorrentCandidates(rules) &&
        (noProvider ||
            forceAddonOnly ||
            rules.sourceMode == QuickPlaySourceMode.addonsOnly)) {
      try {
        final addons = await StremioService.instance.applicableStreamingAddons(
          type: 'series',
          contentId: id,
        );
        leadingAddon = SourceCuration.leadingDirectAddonKey(
          addons,
          rules.sourcePriority,
        );
      } catch (_) {
        // Optional fast path: ordinary search still owns errors/retries.
      }
    }
    if (cancel.cancelled || (!context.mounted || !sourceBindings.isCurrent)) {
      closeLoading();
      return true;
    }
    void onDirectBatch(String source, List<Torrent> batch) {
      if (source != leadingAddon || early.isCompleted || cancel.cancelled)
        return;
      if (ProfileRuntime.scope.value != earlyScope) return;
      final selected = SourceCuration.earlyDirectCandidate(
        batch,
        rules: rules,
        ladder: earlyLadder,
      );
      if (selected == null) return;
      early.complete({
        'torrents': [selected],
        'earlyDirect': true,
      });
    }

    Future<Map<String, dynamic>> query(QuickPlaySourceMode stage) {
      switch (stage) {
        case QuickPlaySourceMode.addonsOnly:
          return TorrentService.searchStremioAddonsOnly(
            imdbId: id,
            isMovie: isMovie,
            season: season,
            episode: episode,
            contentType: meta.contentType,
            timeout: addonTimeout,
            preserveOrder: exactAddonOrder,
            onBatch: leadingAddon == null ? null : onDirectBatch,
            originAddonKey: meta.stremioAddonKey,
            originVideoId: originVideoId,
          );
        case QuickPlaySourceMode.torrentsOnly:
          return TorrentService.searchByImdb(
            id,
            isMovie: isMovie,
            season: season,
            episode: episode,
            timeout: engineTimeout,
            preserveSourceOrder: exactAddonOrder,
          );
        case QuickPlaySourceMode.together:
          return TorrentService.searchByImdbWithStremio(
            id,
            isMovie: isMovie,
            season: season,
            episode: episode,
            contentType: meta.contentType,
            engineTimeout: engineTimeout,
            stremioTimeout: addonTimeout,
            preserveSourceOrder: exactAddonOrder,
            originAddonKey: meta.stremioAddonKey,
            originVideoId: originVideoId,
          );
        case QuickPlaySourceMode.torrentsThenAddons:
        case QuickPlaySourceMode.addonsThenTorrents:
          throw StateError('Fallback source modes must be expanded first');
      }
    }

    Future<Map<String, dynamic>> search() async {
      final iptv = meta.hasStremioEpisodeIdentity
          ? Future.value(const <Torrent>[])
          : IptvQuickPlaySearch.searchIptvForQuickPlay(
              id,
              meta.title ?? label,
              meta.year,
              isMovie,
              season,
              episode,
              rules,
              () => cancel.cancelled,
            );
      final torrents = <Torrent>[];
      final engineErrors = <String, String>{};
      final addonErrors = <String, String>{};
      final addonStatuses = <AddonSearchStatus>[];
      final stages = meta.hasStremioEpisodeIdentity
          ? const [QuickPlaySourceMode.addonsOnly]
          : SourceSearchPlans.addonStreamSearchPlan(
              rules,
              noProvider: noProvider,
              forceAddonOnly: forceAddonOnly,
            );
      for (final stage in stages) {
        final result = await query(stage);
        final stageTorrents = (result['torrents'] as List).cast<Torrent>();
        torrents.addAll(stageTorrents);
        engineErrors.addAll(
          (result['engineErrors'] as Map?)?.cast<String, String>() ?? const {},
        );
        addonErrors.addAll(
          (result['addonErrors'] as Map?)?.cast<String, String>() ?? const {},
        );
        addonStatuses.addAll(
          (result['addonStatuses'] as List?)?.cast<AddonSearchStatus>() ??
              const [],
        );
        // Forced/no-provider searches are addon-only; mixed provider searches
        // are a single combined stage. Keep this guard for explicit one-stage
        // legacy modes and to avoid unnecessary future stages if added.
        final foundUsable = stageTorrents.any(
          (torrent) =>
              (rules.allowDirectLinks ||
                  torrent.streamType != StreamType.directUrl) &&
              SourceCandidateRanking.isAutoPlayableCandidate(torrent),
        );
        if (foundUsable) break;
      }
      return {
        'torrents': [...torrents, ...await iptv],
        'engineErrors': engineErrors,
        'addonErrors': addonErrors,
        'addonStatuses': addonStatuses,
      };
    }

    Map<String, dynamic> res;
    final fullSearch = search();
    try {
      res = await Future.any([fullSearch, early.future]);
    } catch (e) {
      if (cancel.cancelled) return true;
      closeLoading();
      if (fallbackWhenEmpty) return false;
      if (context.mounted) {
        SourceLoadingOverlays.snack(context, 'Search failed: $e');
      }
      return true;
    }
    if (res['earlyDirect'] == true) {
      final selected = (res['torrents'] as List<Torrent>).single;
      final alive =
          !rules.validateDirectLinks ||
          SourceCandidateRanking.directValidationBudgetForRules(rules) <= 0 ||
          !SourceCandidateRanking.shouldPreflightDirectStream(selected) ||
          await StreamUrlValidator.isPlayableVideoUrl(
            selected.directUrl!,
            minBytes: 10 * 1024 * 1024,
            lenient: true,
            headers: selected.httpHeaders,
          );
      if (cancel.cancelled ||
          (!context.mounted || !sourceBindings.isCurrent) ||
          ProfileRuntime.scope.value != earlyScope) {
        closeLoading();
        return true;
      }
      if (alive) {
        final remaining = fullSearch.then(
          (result) => SourceCandidateRanking.orderCandidatesForRules(
            (result['torrents'] as List).cast<Torrent>(),
            rules: rules,
            ladder: earlyLadder,
          ),
          onError: (Object _, StackTrace __) => <Torrent>[],
        );
        final fetcher = SourceSeriesFetcher.seriesFetcherFor(
          meta: meta,
          initialEpisodeSearch: remaining,
        );
        await SourcePlayerLaunch.launch(
          context,
          ResolvedSource(
            title: selected.displayTitle,
            playUrl: selected.directUrl,
            httpHeaders: selected.httpHeaders,
          ),
          selected.displayTitle,
          provider: SeriesSource.addonDirectService,
          meta: meta,
          sources: [selected],
          seriesFetcher: fetcher,
          overlay: overlay,
          startupFailoverEnabled: true,
          onStartupSourcesExhausted: () async {
            final recovery = SourceCuration.earlyDirectRecovery(
              await remaining,
              failed: selected,
              rules: rules,
            );
            if ((!context.mounted || !sourceBindings.isCurrent) ||
                cancel.cancelled ||
                ProfileRuntime.scope.value != earlyScope)
              return;
            await AutomaticPlayBest.playBest(
              context,
              recovery.sources,
              title: label,
              meta: meta,
              rules: recovery.rules,
              ladder: earlyLadder,
              seriesFetcher: fetcher,

              sourceBindings: sourceBindings,
            );
          },

          sourceBindings: sourceBindings,
        );
        return true;
      }
      // The early candidate failed preflight. Keep the normal complete-search
      // failure/retry path rather than discarding slower addon results.
      res = await fullSearch;
      res = {
        ...res,
        'torrents': (res['torrents'] as List)
            .cast<Torrent>()
            .where(
              (t) =>
                  SourceCandidateChecks.directValidationKey(t) !=
                  SourceCandidateChecks.directValidationKey(selected),
            )
            .toList(),
      };
    }
    if (cancel.cancelled) return true;
    if (!context.mounted || !sourceBindings.isCurrent) {
      closeLoading();
      return true;
    }
    // Addon errors ride along keyed by configuration-specific source id
    // (timeouts and upstream 5xx land here, not as a thrown exception). The
    // two searches
    // surface them under different keys: searchByImdbWithStremio folds addon +
    // engine errors together under 'engineErrors', while the noProvider path's
    // searchStremioAddonsOnly returns them raw under 'addonErrors'. Read both,
    // then keep only direct-provider keys — a flaky engine must not misblame
    // "didn't respond" on a title that simply has no stream.
    String failedAddonNamesOf(
      Map<String, dynamic> r,
      Map<String, String> errors,
    ) {
      final statuses =
          r['addonStatuses'] as List<AddonSearchStatus>? ?? const [];
      final names = <String>[
        for (final status in statuses)
          if (errors.containsKey(status.sourceKey)) status.name,
      ];
      if (names.isNotEmpty) return names.join(', ');
      return errors.keys
          .map((key) => key.replaceFirst('stremio:', ''))
          .join(', ');
    }

    var torrents = (res['torrents'] as List).cast<Torrent>();
    var errors = SourceCuration.directSearchErrors(res);
    // Empty ONLY because an addon errored is usually a transient upstream
    // blip — retry once before giving up.
    if (torrents.isEmpty && errors.isNotEmpty) {
      try {
        res = await search();
        torrents = (res['torrents'] as List).cast<Torrent>();
        errors = SourceCuration.directSearchErrors(res);
      } catch (_) {
        // Keep the first attempt's (empty) result — reported below.
      }
      if (cancel.cancelled) return true;
      if (!context.mounted || !sourceBindings.isCurrent) {
        closeLoading();
        return true;
      }
    }
    if (torrents.isEmpty) {
      closeLoading();
      if (fallbackWhenEmpty) return false;
      // An errored addon means "didn't respond", not "has no stream" — say
      // so, since a retry will usually succeed.
      if (errors.isNotEmpty) {
        final failed = failedAddonNamesOf(res, errors);
        final nativeErrors = errors.entries
            .where((entry) => entry.key.startsWith('mediaserver:'))
            .map((entry) => entry.value)
            .toSet();
        SourceLoadingOverlays.snack(
          context,
          nativeErrors.isEmpty
              ? '$failed didn\'t respond for "$label" — try again.'
              : '$failed: ${nativeErrors.join(' ')}',
        );
      } else {
        // noProvider: addons searched fine and returned nothing directly
        // playable. Torrent engines were skipped (they need a provider), so the
        // actionable next step is to add one — but don't claim the title has no
        // stream at all, only that none plays without a provider.
        SourceLoadingOverlays.snack(
          context,
          noProvider
              ? 'No direct stream for "$label". Add a debrid provider in Settings for more sources.'
              : 'No stream found for "$label".',
        );
      }
      return true;
    }
    // Reuse the same preference snapshot used for the early candidate.
    final ladder = earlyLadder;
    if (cancel.cancelled) return true; // Cancel during the prefs read
    if (!context.mounted || !sourceBindings.isCurrent) {
      closeLoading();
      return true;
    }
    torrents = SourceCandidateRanking.orderCandidatesForRules(
      torrents,
      rules: rules,
      ladder: ladder,
    );
    if (fallbackWhenEmpty) {
      torrents = await SourceIptvAvailability.confirmDeferredIptvAvailability(
        torrents,
        season: season,
        episode: episode,
        isCancelled: () => cancel.cancelled,
      );
      if (cancel.cancelled) return true;
      if (!context.mounted || !sourceBindings.isCurrent) {
        closeLoading();
        return true;
      }
      if (!torrents.any(SourceCandidateRanking.isAutoPlayableCandidate)) {
        closeLoading();
        return false;
      }
    }
    SourceLoadingOverlays.applyLadderNote(overlay, ladder, torrents);
    // playBest plays a direct addon stream instantly (no provider needed); if
    // there somehow isn't one it falls through to the normal provider path.
    await AutomaticPlayBest.playBest(
      context,
      torrents,
      title: label,
      meta: meta,
      overlay: overlay,
      isCancelled: () => cancel.cancelled,
      ladder: ladder,
      rules: rules,
      seriesFetcher: isMovie
          ? SourceMovieFetcher.movieFetcherFor(meta: meta)
          : SourceSeriesFetcher.seriesFetcherFor(
              meta: meta,
              episodesFetched: true,
            ),

      sourceBindings: sourceBindings,
    );
    return true;
  }
}
