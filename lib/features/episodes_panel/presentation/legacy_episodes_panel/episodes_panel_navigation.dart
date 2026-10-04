import 'dart:async';
import 'package:debrify/features/episodes_panel/models/episodes_panel_view.dart';
import 'package:debrify/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_deps.dart';
import 'package:debrify/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_progress.dart';
import 'package:debrify/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_resources.dart';
import 'package:debrify/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_view_state.dart';
import 'package:debrify/models/advanced_search_selection.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/stremio_service.dart';
import 'package:debrify/services/trakt/trakt_episode_model.dart';
import 'package:flutter/material.dart';

class EpisodesPanelNavigation {
  final EpisodesPanelDeps _deps;
  EpisodesPanelNavigation(this._deps);
  EpisodesPanelViewState get _s => _deps.parts.viewState;
  EpisodesPanelProgress get _p => _deps.parts.progress;
  EpisodesPanelResources get _r => _deps.parts.resources;
  bool get mounted => _deps.mounted();

  // ── Episode drill-down ──────────────────────────────────────────────────
  /// Fallback: dispatch series directly to torrent search (bypasses episode mode).
  void fallbackToDirectSearch(StremioMeta show) {
    if (!mounted) return;
    _deps.onBeforeTerminalDispatch()?.call();
    final selection = AdvancedSearchSelection(
      imdbId: show.progressId ?? show.id,
      isSeries: true,
      title: show.name,
      year: show.year,
      contentType: show.type,
      posterUrl: show.poster,
    );
    _deps.onItemSelected()?.call(selection);
  }

  void onSeasonChanged(int? seasonNumber) {
    if (seasonNumber == null || seasonNumber == _s.selectedSeasonNumber) return;

    for (final node in _r.episodeFocusNodes) {
      node.dispose();
    }
    _r.episodeFocusNodes.clear();

    final season = _s.episodeSeasons.firstWhere(
      (s) => s.number == seasonNumber,
      orElse: () => _s.episodeSeasons.first,
    );
    for (int i = 0; i < season.episodes.length; i++) {
      _r.episodeFocusNodes.add(FocusNode(debugLabel: 'catalog-ep-$i'));
    }

    if (!_deps.custom() && _r.episodeScrollController.hasClients) {
      _r.episodeScrollController.jumpTo(0);
    }

    _deps.setState(() {
      _s.selectedSeasonNumber = seasonNumber;
      _s.landing = season.episodes.firstOrNull;
      // The user is on the stepper — keep them there, as Classic does by
      // re-requesting the season dropdown.
      _s.focusIntent = EpisodeFocusIntent.seasonControl;
      _s.viewGeneration++;
    });
    unawaited(_deps.parts.metadata.loadSelectedEpisodeMetadata());
  }

  void onEpisodeTap(TraktEpisode episode) {
    // Direct-source mode: no sources flow exists — a tap plays outright, on
    // top of the page (no terminal dispatch/pop, like quick-play).
    if (_deps.onPlayEpisode() != null) {
      _deps.onPlayEpisode()!(episode);
      return;
    }
    final show = _s.selectedShow;
    if (show == null || _deps.onItemSelected() == null) return;

    var selection = AdvancedSearchSelection(
      imdbId: show.progressId ?? show.id,
      isSeries: true,
      title: show.name,
      year: show.year,
      season: episode.season,
      episode: episode.number,
      contentType: show.type,
      posterUrl: show.poster,
      // For Trakt-sourced items, carry the Trakt scrobble flag + resume
      // position so playback syncs to Trakt like the old home view.
      traktSource: _deps.isTraktSource(),
      traktProgressPercent: _deps.isTraktSource()
          ? _p.episodeWatchProgress['${episode.season}-${episode.number}']
          : null,
      mdblistSource: _deps.isMdblistSource(),
      mdblistProgressPercent: _deps.isMdblistSource()
          ? _p.episodeWatchProgress['${episode.season}-${episode.number}']
          : null,
      // Lets the host send the user back to this episode list (not the
      // catalog grid) when they back out of the torrent results.
      fromCatalogEpisodeDrillDown: true,
    );
    final videoId = episode.stremioVideoId?.trim();
    if (videoId != null &&
        videoId.isNotEmpty &&
        !StremioService.isCanonicalEpisodeId(
          selection.imdbId,
          videoId,
          episode.season,
          episode.number,
        )) {
      selection = selection.withStremioEpisodeIdentity(
        addonId: _deps.addon().id,
        addonKey: _deps.addon().sourceBindingKey,
        catalogId: show.id,
        videoId: videoId,
      );
    }
    _deps.onBeforeTerminalDispatch()?.call();
    _deps.onItemSelected()!(selection);
  }

  void onEpisodeQuickPlay(TraktEpisode episode) {
    if (_deps.onPlayEpisode() != null) {
      _deps.onPlayEpisode()!(episode);
      return;
    }
    final show = _s.selectedShow;
    if (show == null) return;

    var selection = AdvancedSearchSelection(
      imdbId: show.progressId ?? show.id,
      isSeries: true,
      title: show.name,
      year: show.year,
      season: episode.season,
      episode: episode.number,
      contentType: show.type,
      posterUrl: show.poster,
      traktSource: _deps.isTraktSource(),
      traktProgressPercent: _deps.isTraktSource()
          ? _p.episodeWatchProgress['${episode.season}-${episode.number}']
          : null,
      mdblistSource: _deps.isMdblistSource(),
      mdblistProgressPercent: _deps.isMdblistSource()
          ? _p.episodeWatchProgress['${episode.season}-${episode.number}']
          : null,
      fromCatalogEpisodeDrillDown: true,
    );

    final videoId = episode.stremioVideoId?.trim();
    if (videoId != null &&
        videoId.isNotEmpty &&
        !StremioService.isCanonicalEpisodeId(
          selection.imdbId,
          videoId,
          episode.season,
          episode.number,
        )) {
      selection = selection.withStremioEpisodeIdentity(
        addonId: _deps.addon().id,
        addonKey: _deps.addon().sourceBindingKey,
        catalogId: show.id,
        videoId: videoId,
      );
    }

    _deps.onBeforeTerminalDispatch()?.call();
    if (_deps.onQuickPlay() != null) {
      _deps.onQuickPlay()!(selection);
    } else if (_deps.onItemSelected() != null) {
      _deps.onItemSelected()!(selection);
    }
  }

  void stepSeason(int delta) {
    if (_s.episodeSeasons.isEmpty) return;
    final i = _deps.currentSeasonIndex();
    final ni = (i < 0 ? 0 : i) + delta;
    if (ni < 0 || ni >= _s.episodeSeasons.length) return;
    onSeasonChanged(_s.episodeSeasons[ni].number);
    // Stepping into the first/last season disables the chevron we're on, which
    // would drop primary focus into the void. Park focus on the always-present
    // season dropdown so the remote stays live.
    // Classic parks focus on its always-present dropdown; a custom arrangement
    // has no such node, and its own season control keeps focus already.
    if (_deps.custom()) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _r.episodeSeasonDropdownFocusNode.requestFocus();
    });
  }
}
