import 'package:debrify/features/episodes_panel/models/episodes_panel_view.dart';
import 'package:debrify/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_auth.dart';
import 'package:debrify/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_deps.dart';
import 'package:debrify/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_navigation.dart';
import 'package:debrify/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_progress.dart';
import 'package:debrify/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_view_state.dart';
import 'package:flutter/material.dart';

class EpisodesPanelRootLayout {
  final EpisodesPanelDeps _deps;
  EpisodesPanelRootLayout(this._deps);
  EpisodesPanelViewState get _s => _deps.parts.viewState;
  EpisodesPanelProgress get _p => _deps.parts.progress;
  EpisodesPanelAuth get _a => _deps.parts.auth;
  EpisodesPanelNavigation get _n => _deps.parts.navigation;

  /// True when a custom arrangement is driving. Gates every engine side effect
  /// that targets a widget only the classic tree contains.
  bool get custom => _deps.contentBuilder() != null;

  Widget build(BuildContext context) {
    final custom = _deps.contentBuilder();
    if (custom != null) return custom(context, buildView());
    if (_deps.compact()) {
      return Column(
        children: [
          if (!_s.isLoadingEpisodes &&
              !_s.episodesUnavailable &&
              _s.episodeSeasons.isNotEmpty)
            _deps.parts.compactLayout.buildCompactSeasonHeader(),
          Expanded(child: _deps.parts.compactLayout.buildCompactContent()),
        ],
      );
    }
    return Column(
      children: [
        if (_deps.showChrome())
          _deps.parts.classicChrome.buildEpisodeFiltersBar()
        else if (_s.episodeSeasons.length > 1)
          _deps.parts.classicChrome.buildSlimSeasonRow(),
        Expanded(child: _deps.parts.classicContent.buildEpisodeContent()),
      ],
    );
  }

  /// Snapshot handed to a custom arrangement. Cheap — it closes over state
  /// rather than copying it, and is rebuilt with the panel.
  EpisodesPanelView buildView() {
    final season = _s.episodeSeasons
        .where((s) => s.number == _s.selectedSeasonNumber)
        .firstOrNull;
    final episodes =
        season?.episodes ?? _s.episodeSeasons.firstOrNull?.episodes ?? const [];
    final show = _s.selectedShow ?? _deps.show();
    return EpisodesPanelView(
      seasons: _s.episodeSeasons,
      selectedSeasonNumber: _s.selectedSeasonNumber,
      episodes: episodes,
      loading: _s.isLoadingEpisodes,
      unavailable: _s.episodesUnavailable,
      showImageUrl: show.poster,
      generation: _s.viewGeneration,
      landing: _s.landing,
      focusIntent: _s.focusIntent,
      progressOf: (e) => _p.episodeWatchProgress['${e.season}-${e.number}'],
      isNext: (e) =>
          _s.nextEpisode != null &&
          _s.nextEpisode!.season == e.season &&
          _s.nextEpisode!.episode == e.number,
      play: _n.onEpisodeQuickPlay,
      options: _deps.parts.episodeOptions.showEpisodeOptions,
      stepSeason: _n.stepSeason,
      selectSeason: (n) => _n.onSeasonChanged(n),
      seasonOptions: _a.isDirectSource
          ? null
          : _deps.parts.seasonOptions.showSeasonOptions,
      onLeftEdge: _deps.onFocusLeftEdge(),
      onRetry: () => _deps.parts.mode.enterEpisodeMode(
        show,
        initialSeason: _deps.initialSeason(),
        initialEpisode: _deps.initialEpisode(),
      ),
      // Mirrors the classic failure UI: no torrent-search fallback exists for
      // direct-source shows, so the offer is withheld rather than dead.
      onSearchForSources: _deps.onItemSelected() != null
          ? () => _n.fallbackToDirectSearch(show)
          : null,
    );
  }
}
