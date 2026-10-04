import 'package:debrify/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_auth.dart';
import 'package:debrify/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_deps.dart';
import 'package:debrify/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_navigation.dart';
import 'package:debrify/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_progress.dart';
import 'package:debrify/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_resources.dart';
import 'package:debrify/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_view_state.dart';
import 'package:debrify/screens/debrify_tv/widgets/tv_focus_scroll_wrapper.dart';
import 'package:debrify/widgets/detail/theme/detail_theme.dart';
import 'package:debrify/widgets/episode_tile.dart';
import 'package:flutter/material.dart';

class EpisodesPanelClassicContent {
  final EpisodesPanelDeps _deps;
  EpisodesPanelClassicContent(this._deps);
  EpisodesPanelViewState get _s => _deps.parts.viewState;
  EpisodesPanelProgress get _p => _deps.parts.progress;
  EpisodesPanelAuth get _a => _deps.parts.auth;
  EpisodesPanelResources get _r => _deps.parts.resources;
  EpisodesPanelNavigation get _n => _deps.parts.navigation;

  /// Inline "couldn't load episodes" panel with Retry (recovers a transient
  /// failure without leaving the drill-down) and an explicit "Search for
  /// sources" action (the old auto-fallback, now opt-in).
  Widget buildEpisodesUnavailable() {
    final show = _s.selectedShow ?? _deps.show();
    // Hoisted: the WidgetStateProperty resolvers below are closures the button
    // re-evaluates on every state change, not build-time code.
    final t = DetailThemeScope.maybeOf(_deps.context());
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.tv_off_rounded,
              size: 48,
              color: Colors.white.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 14),
            const Text(
              "Couldn't load episodes",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              'The episode list is unavailable right now.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.center,
              children: [
                ElevatedButton.icon(
                  focusNode: _r.episodeRetryFocusNode,
                  autofocus: _deps.isTelevision(),
                  // Default focus overlay is faint on dark — gold ring on focus
                  // like every other DPAD target in the drill-down.
                  style: ButtonStyle(
                    side: WidgetStateProperty.resolveWith(
                      (states) => states.contains(WidgetState.focused)
                          ? BorderSide(color: t.focus, width: 2)
                          : null,
                    ),
                  ),
                  onPressed: () => _deps.parts.mode.enterEpisodeMode(
                    show,
                    initialSeason: _deps.initialSeason(),
                    initialEpisode: _deps.initialEpisode(),
                  ),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Retry'),
                ),
                // No torrent-search fallback exists for direct-source shows —
                // Retry is the only honest offer there.
                if (_deps.onItemSelected() != null)
                  OutlinedButton.icon(
                    style: ButtonStyle(
                      side: WidgetStateProperty.resolveWith(
                        (states) => states.contains(WidgetState.focused)
                            ? BorderSide(color: t.focus, width: 2)
                            : const BorderSide(color: Colors.white24),
                      ),
                    ),
                    onPressed: () => _n.fallbackToDirectSearch(show),
                    icon: const Icon(Icons.search_rounded),
                    label: const Text('Search for sources'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget buildEpisodeContent() {
    if (_s.isLoadingEpisodes) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_s.episodesUnavailable || _s.episodeSeasons.isEmpty) {
      return buildEpisodesUnavailable();
    }

    final currentSeason = _s.episodeSeasons.firstWhere(
      (s) => s.number == _s.selectedSeasonNumber,
      orElse: () => _s.episodeSeasons.first,
    );

    final w = MediaQuery.of(_deps.context()).size.width;
    final hPad = w >= 900 ? 40.0 : 16.0;

    return TvFocusScrollWrapper(
      child: ListView.builder(
        controller: _r.episodeScrollController,
        padding: EdgeInsets.fromLTRB(hPad, 10, hPad, 28),
        itemCount: currentSeason.episodes.length,
        itemBuilder: (context, index) {
          final episode = currentSeason.episodes[index];
          return Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: EpisodeTile(
              episode: episode,
              showImageUrl: _s.selectedShow?.poster,
              isTelevision: _deps.isTelevision(),
              showQuickPlay: _deps.showQuickPlay(),
              focusNode: index < _r.episodeFocusNodes.length
                  ? _r.episodeFocusNodes[index]
                  : null,
              watchProgress: _p
                  .episodeWatchProgress['${episode.season}-${episode.number}'],
              isNext:
                  _s.nextEpisode != null &&
                  _s.nextEpisode!.season == episode.season &&
                  _s.nextEpisode!.episode == episode.number,
              onPlay: () => _n.onEpisodeQuickPlay(episode),
              onSources: () => _n.onEpisodeTap(episode),
              onMenuAction: _a.isTraktAuthenticated
                  ? (action) => _deps.parts.watchedActions.onEpisodeMenuAction(
                      episode,
                      action,
                    )
                  : null,
              onTrackerOptions:
                  _a.isSimklAuthenticated || _a.isMdblistAuthenticated
                  ? () => _deps.parts.episodeOptions.showEpisodeOptions(episode)
                  : null,
            ),
          );
        },
      ),
    );
  }
}
