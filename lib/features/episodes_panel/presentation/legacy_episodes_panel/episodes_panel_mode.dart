import 'dart:async';
import 'package:debrify/features/episodes_panel/models/episodes_panel_view.dart';
import 'package:debrify/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_auth.dart';
import 'package:debrify/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_deps.dart';
import 'package:debrify/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_progress.dart';
import 'package:debrify/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_resources.dart';
import 'package:debrify/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_services.dart';
import 'package:debrify/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_view_state.dart';
import 'package:debrify/models/custom_series_identity.dart';
import 'package:debrify/models/media_identity.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/local_series_completion_service.dart';
import 'package:debrify/services/storage/episode_resume_storage.dart';
import 'package:debrify/services/tracking_source_policy.dart';
import 'package:debrify/services/trakt/trakt_episode_model.dart';
import 'package:flutter/material.dart';

class EpisodesPanelMode {
  final EpisodesPanelDeps _deps;
  EpisodesPanelMode(this._deps);
  EpisodesPanelViewState get _s => _deps.parts.viewState;
  EpisodesPanelProgress get _p => _deps.parts.progress;
  EpisodesPanelAuth get _a => _deps.parts.auth;
  EpisodesPanelResources get _r => _deps.parts.resources;
  EpisodesPanelServices get _sv => _deps.parts.services;
  bool get mounted => _deps.mounted();

  void enterEpisodeMode(
    StremioMeta show, {
    int? initialSeason,
    int? initialEpisode,
  }) async {
    final generation = ++_s.episodeModeGeneration;
    try {
      show = await _sv.stremioService.scopeSeriesProgress(show, _deps.addon());
    } on StateError {
      if (mounted && generation == _s.episodeModeGeneration) {
        ScaffoldMessenger.of(_deps.context()).showSnackBar(
          const SnackBar(
            content: Text('Could not verify series episodes. Please retry.'),
          ),
        );
      }
      return;
    }
    final trackingPolicy = (await TrackingSourcePolicy.load()).forContent(
      show.progressId,
    );
    if (!mounted || generation != _s.episodeModeGeneration) return;
    _p.trackingPolicy = trackingPolicy;

    _deps.setState(() {
      _s.selectedShow = show;
      _s.isLoadingEpisodes = true;
      _s.episodesUnavailable = false;
      _s.episodeSeasons = [];
      _p.episodeMdblistRatings = {};
      _s.selectedSeasonNumber = initialSeason ?? 1;
      _s.nextEpisode = null;
      _s.trackerNextRaw = null;
    });

    // Load watch progress (non-blocking; generation-guarded). The "up next"
    // marker is resolved inline below since it also drives where we land.
    // Direct-source mode awaits this future before landing — progress is its
    // only resume signal (there is no Trakt next-episode for these shows).
    final progressFuture = _p.loadEpisodeWatchProgress(show, generation);

    for (final node in _r.episodeFocusNodes) {
      node.dispose();
    }
    _r.episodeFocusNodes.clear();

    try {
      // The seasons fetch, Trakt's "next episode" lookup, and (on the Trakt
      // path) the TVMaze thumbnail map are independent — fire all of them now
      // instead of serializing three network round trips before content shows.
      // Each side future swallows its own errors so a failure can neither
      // bubble to the outer catch nor go unhandled if we bail on a stale
      // generation before awaiting it.
      final seasonsFuture = _deps.parts.seasons.fetchSeasons(show);

      // Trakt "next episode" — drives the up-next tile highlight and the
      // landing target. Instant/null without a Trakt account (no token → no
      // request). Direct-source shows have no Trakt identity — skip outright
      // rather than fire a request keyed on a sentinel id.
      final nextEpisodeFuture =
          _a.isDirectSource ||
              !trackingPolicy.progressFrom(TrackingSource.trakt)
          ? Future<({int season, int episode})?>.value(null)
          : _sv.traktService
                .fetchNextEpisode(show.progressId ?? show.id)
                .catchError((Object e) {
                  debugPrint('EpisodesPanel: next-episode fetch failed: $e');
                  return null;
                });

      // Trakt-sourced items carry a stub addon (no base URL) and their
      // episodes arrive without stills — warm the TVMaze map alongside the
      // seasons fetch so tiles can show real stills at (or right after) first
      // paint instead of swapping in seconds later. Direct-source episodes
      // bring their own stills (or none) — TVMaze can't know them.
      final addonHasMeta =
          _deps.addon().baseUrl.isNotEmpty ||
          _deps.addon().manifestUrl.isNotEmpty;
      final prefetchedThumbs = (addonHasMeta || _a.isDirectSource)
          ? null
          : _deps.parts.enrichment.fetchTvmazeThumbMap(show.effectiveImdbId);

      final seasons = await seasonsFuture;
      if (!mounted || generation != _s.episodeModeGeneration) return;

      if (seasons.isEmpty) {
        _deps.setState(() {
          _s.isLoadingEpisodes = false;
          _s.episodesUnavailable = true;
        });
        return;
      }

      final imdbId = show.progressId;
      if (!_a.isDirectSource && imdbId != null && imdbId.isNotEmpty) {
        unawaited(
          LocalSeriesCompletionService.instance.recordEpisodeInventory(
            imdbId: imdbId,
            seriesTitle: show.name,
            seasons: seasons,
          ),
        );
      }

      // Resolve where to land (season + episode to auto-switch and scroll to),
      // mirroring the old home episode view. Priority:
      //   1. explicit initialSeason/initialEpisode (deep links, calendar)
      //   2. Trakt's "next episode" — the cross-device resume point
      //   3. this device's last-played episode (local storage)
      //   4. first season, first episode
      // Each tier supplies both fields together so season/episode never mix
      // across sources.
      int? effectiveSeason = initialSeason;
      int? effectiveEpisode = initialEpisode;

      // 2. Trakt "next episode" — already in flight (fired alongside the
      //    seasons fetch above); errors resolve to null there, so this await
      //    can never bubble to the outer catch and drop us to torrent search.
      final nextEpisode = await nextEpisodeFuture;
      if (!mounted || generation != _s.episodeModeGeneration) return;
      // Keep the raw value for the up-next highlight (it self-limits to a
      // displayed tile). Only adopt it as the landing target when its season is
      // actually present, so we never scroll to the wrong episode in season 1.
      _s.nextEpisode = nextEpisode;
      _s.trackerNextRaw = nextEpisode;
      if (effectiveSeason == null &&
          effectiveEpisode == null &&
          nextEpisode != null &&
          seasons.any((s) => s.number == nextEpisode.season)) {
        effectiveSeason = nextEpisode.season;
        effectiveEpisode = nextEpisode.episode;
      }

      // 3a. Direct-source resume — from the host's progress map (the only
      //     signal these shows have): land on the last started episode, or
      //     the one after it when it's essentially finished.
      if (_a.isDirectSource &&
          effectiveSeason == null &&
          effectiveEpisode == null) {
        await progressFuture;
        if (!mounted || generation != _s.episodeModeGeneration) return;
        final target = directLandingTarget(seasons);
        if (target != null) {
          effectiveSeason = target.season;
          effectiveEpisode = target.episode;
        }
      }

      // 3. Last-played (local) fallback — by IMDb id, then by title.
      if (!_a.isDirectSource &&
          trackingPolicy.progressFrom(TrackingSource.local) &&
          effectiveSeason == null &&
          effectiveEpisode == null) {
        final imdbId = show.progressId;
        if (imdbId != null) {
          final lastPlayed =
              await EpisodeResumeStorage.getLastPlayedEpisodeByImdbId(imdbId);
          if (!mounted || generation != _s.episodeModeGeneration) return;
          if (lastPlayed != null) {
            effectiveSeason = lastPlayed['season'] as int?;
            effectiveEpisode = lastPlayed['episode'] as int?;
          }
        }
        if (!MediaIdentity.isNative(show.progressId) &&
            !CustomSeriesIdentity.isCustom(show.imdbId) &&
            effectiveSeason == null &&
            effectiveEpisode == null) {
          final byTitle = await EpisodeResumeStorage.getLastPlayedEpisode(
            seriesTitle: show.name,
          );
          if (!mounted || generation != _s.episodeModeGeneration) return;
          if (byTitle != null) {
            effectiveSeason = byTitle['season'] as int?;
            effectiveEpisode = byTitle['episode'] as int?;
          }
        }
      }

      // Pick the target season: prefer the resolved season if it exists
      final targetSeason =
          (effectiveSeason != null &&
              seasons.any((s) => s.number == effectiveSeason))
          ? seasons.firstWhere((s) => s.number == effectiveSeason)
          : seasons.first;

      // Build focus nodes for target season
      for (int i = 0; i < targetSeason.episodes.length; i++) {
        _r.episodeFocusNodes.add(FocusNode(debugLabel: 'catalog-ep-$i'));
      }

      // The stored/next-up episode number is only meaningful inside the season
      // it came from. When the resolved season fell back to `seasons.first`
      // (because the remembered one no longer exists), carrying the episode
      // number across would land on an unrelated episode of season 1.
      final landedInTargetSeason =
          effectiveSeason == null || effectiveSeason == targetSeason.number;
      final landingEpisode = (landedInTargetSeason && effectiveEpisode != null)
          ? targetSeason.episodes
                .where((e) => e.number == effectiveEpisode)
                .firstOrNull
          : null;

      _deps.setState(() {
        _s.episodeSeasons = seasons;
        _s.nextEpisode = _p.mergedUpNext(
          _p.episodeWatchProgress,
          _s.trackerNextRaw,
        );
        _s.selectedSeasonNumber = targetSeason.number;
        _s.isLoadingEpisodes = false;
        _s.landing = landingEpisode ?? targetSeason.episodes.firstOrNull;
        _s.focusIntent = EpisodeFocusIntent.landing;
        _s.viewGeneration++;
      });
      _deps.parts.metadata.episodeMetadataBaselines
        ..clear()
        ..addEntries(seasons.map((season) => MapEntry(season.number, season)));
      unawaited(_deps.parts.metadata.loadSelectedEpisodeMetadata());
      final mergedNext = _s.nextEpisode;
      _p.publishSeriesCompletion();
      if (mergedNext != null) {
        _p.publishNextEpisode(mergedNext);
      }

      // Fill in per-episode thumbnails from TVMaze for any episode that didn't
      // come with one (Trakt-sourced items have none; addon items keep theirs).
      // Non-blocking — and on the Trakt path the map was prefetched alongside
      // the seasons, so stills usually land within a frame of first paint.
      // Both enrichments are IMDb-keyed, so direct-source shows skip them.
      if (!_a.isDirectSource) {
        _deps.parts.enrichment.enrichEpisodeThumbnails(
          show,
          seasons,
          generation,
          prefetched: prefetchedThumbs,
        );

        // Backfill per-episode ratings from Trakt when the addon didn't supply
        // real ones (Cinemeta sends rating:0). Non-blocking — ratings pop in.
        _deps.parts.enrichment.enrichEpisodeRatings(show, seasons, generation);
      }

      // Scroll to (and focus) the target episode once its tile is built.
      // Robust against variable EpisodeTile height + lazy ListView building
      // (the old fixed focusIndex*128 estimate is wrong for the new tile).
      // A custom arrangement owns its own scrollable and FocusNodes, so the
      // engine's reveal would target widgets that do not exist there. The
      // layout reveals `view.landing` itself, driven by `focusIntent`.
      if (!_deps.parts.rootLayout.custom) {
        final targetEpIndex = effectiveEpisode != null
            ? targetSeason.episodes.indexWhere(
                (e) => e.number == effectiveEpisode,
              )
            : -1;
        _deps.parts.enrichment.scrollFocusEpisode(
          targetEpIndex < 0 ? 0 : targetEpIndex,
          targetSeason.episodes.length,
          generation,
        );
      }
    } catch (e) {
      if (!mounted || generation != _s.episodeModeGeneration) return;
      debugPrint('EpisodesPanel: Episode fetch failed: $e');
      _deps.setState(() {
        _s.isLoadingEpisodes = false;
        _s.episodesUnavailable = true;
      });
    }
  }

  /// Direct-source landing: the last episode (in season/episode order, with
  /// the same Specials-last rule the list renders in) that has any progress —
  /// advanced to the next episode when it's essentially finished (≥95%). Null
  /// when nothing has been started, leaving the default first-episode landing.
  ({int season, int episode})? directLandingTarget(List<TraktSeason> seasons) {
    final flat = [for (final s in seasons) ...s.episodes];
    int lastStarted = -1;
    for (var i = 0; i < flat.length; i++) {
      final p =
          _p.episodeWatchProgress['${flat[i].season}-${flat[i].number}'] ?? 0;
      if (p > 0) lastStarted = i;
    }
    if (lastStarted < 0) return null;
    final p =
        _p.episodeWatchProgress['${flat[lastStarted].season}-${flat[lastStarted].number}'] ??
        0;
    final target = (p >= 95 && lastStarted + 1 < flat.length)
        ? flat[lastStarted + 1]
        : flat[lastStarted];
    return (season: target.season, episode: target.number);
  }
}
