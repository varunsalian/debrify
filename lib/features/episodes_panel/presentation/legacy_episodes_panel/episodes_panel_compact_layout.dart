import 'package:debrify/features/episodes_panel/presentation/episodes_panel_season_step.dart';
import 'package:debrify/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_compact_row.dart';
import 'package:debrify/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_deps.dart';
import 'package:debrify/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_navigation.dart';
import 'package:debrify/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_progress.dart';
import 'package:debrify/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_resources.dart';
import 'package:debrify/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_view_state.dart';
import 'package:flutter/material.dart';

class EpisodesPanelCompactLayout {
  final EpisodesPanelDeps _deps;
  EpisodesPanelCompactLayout(this._deps);
  EpisodesPanelViewState get _s => _deps.parts.viewState;
  EpisodesPanelProgress get _p => _deps.parts.progress;
  EpisodesPanelResources get _r => _deps.parts.resources;
  EpisodesPanelNavigation get _n => _deps.parts.navigation;

  // ── Compact (Stremio) rendering ──────────────────────────────────────────
  int get currentSeasonIndex =>
      _s.episodeSeasons.indexWhere((s) => s.number == _s.selectedSeasonNumber);

  /// Pinned "‹ Prev · Season ▾ · Next ›" header — always visible above the list
  /// (this is what "the season dropdown isn't reachable" was about).
  Widget buildCompactSeasonHeader() {
    final i = currentSeasonIndex;
    final many = _s.episodeSeasons.length > 1;
    final current = (i >= 0) ? _s.episodeSeasons[i] : _s.episodeSeasons.first;
    final count = current.episodes.length;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
      ),
      child: Row(
        children: [
          if (many)
            EpisodesPanelSeasonStep(
              icon: Icons.chevron_left_rounded,
              enabled: i > 0,
              onTap: () => _n.stepSeason(-1),
            ),
          Expanded(
            child: Center(
              child: many
                  ? _deps.parts.classicChrome.buildEpisodeSeasonDropdown()
                  : Text(
                      current.displayLabel,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
          if (many)
            EpisodesPanelSeasonStep(
              icon: Icons.chevron_right_rounded,
              enabled: i < _s.episodeSeasons.length - 1,
              onTap: () => _n.stepSeason(1),
            ),
          const SizedBox(width: 8),
          Text(
            '$count',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.4),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (_deps.isTelevision()) ...[
            const SizedBox(width: 14),
            Text(
              'OK play · ▶ options',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.3),
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget buildCompactContent() {
    if (_s.isLoadingEpisodes) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_s.episodesUnavailable || _s.episodeSeasons.isEmpty) {
      return _deps.parts.classicContent.buildEpisodesUnavailable();
    }
    final currentSeason = _s.episodeSeasons.firstWhere(
      (s) => s.number == _s.selectedSeasonNumber,
      orElse: () => _s.episodeSeasons.first,
    );
    // The row centres itself on focus (`_CompactEpisodeRow.onFocusChange`), so
    // no TvFocusScrollWrapper is needed here (it would resolve no ancestor
    // scrollable and no-op anyway).
    return ListView.builder(
      controller: _r.episodeScrollController,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      itemCount: currentSeason.episodes.length,
      itemBuilder: (context, index) {
        final episode = currentSeason.episodes[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: EpisodesPanelCompactRow(
            episode: episode,
            showImageUrl: _s.selectedShow?.poster,
            isTelevision: _deps.isTelevision(),
            watchProgress:
                _p.episodeWatchProgress['${episode.season}-${episode.number}'],
            isNext:
                _s.nextEpisode != null &&
                _s.nextEpisode!.season == episode.season &&
                _s.nextEpisode!.episode == episode.number,
            focusNode: index < _r.episodeFocusNodes.length
                ? _r.episodeFocusNodes[index]
                : null,
            onPlay: () => _n.onEpisodeQuickPlay(episode),
            onOptions: () =>
                _deps.parts.episodeOptions.showEpisodeOptions(episode),
            onLeft: _deps.onFocusLeftEdge(),
          ),
        );
      },
    );
  }
}
