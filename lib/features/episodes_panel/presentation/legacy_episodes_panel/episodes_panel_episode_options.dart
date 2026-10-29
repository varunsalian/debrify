import 'package:debrify/features/episodes_panel/application/earlier_episodes.dart';
import 'package:debrify/features/episodes_panel/application/episodes_panel_policies.dart';
import 'package:debrify/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_auth.dart';
import 'package:debrify/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_deps.dart';
import 'package:debrify/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_navigation.dart';
import 'package:debrify/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_progress.dart';
import 'package:debrify/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_view_state.dart';
import 'package:debrify/services/mdblist/mdblist_menu_helpers.dart';
import 'package:debrify/services/trakt/trakt_episode_model.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/utils/tv_keys.dart';
import 'package:debrify/widgets/trakt/trakt_menu_helpers.dart';
import 'package:flutter/material.dart';

class EpisodesPanelEpisodeOptions {
  final EpisodesPanelDeps _deps;
  EpisodesPanelEpisodeOptions(this._deps);
  EpisodesPanelProgress get _p => _deps.parts.progress;
  EpisodesPanelAuth get _a => _deps.parts.auth;
  EpisodesPanelNavigation get _n => _deps.parts.navigation;
  EpisodesPanelViewState get _s => _deps.parts.viewState;

  /// Per-episode options menu (opened with Right / the ⋮ button): Play, Sources,
  /// a single Mark Watched/Unwatched that acts on local storage plus every
  /// connected tracker, and supported per-tracker Rate rows. Simkl ratings are
  /// title-only, so its episode menu deliberately has no rating action.
  void showEpisodeOptions(TraktEpisode episode) {
    final key = '${episode.season}-${episode.number}';
    final watched = (_p.episodeWatchProgress[key] ?? 0) >= 100;
    showModalBottomSheet<void>(
      context: _deps.context(),
      backgroundColor: AppThemeScope.of(_deps.context()).sheetSurface,
      showDragHandle: true,
      // With multiple trackers connected the menu can grow taller than
      // the default sheet cap (9/16 of screen height) on portrait phones, and
      // on TV the clipped rows stayed DPAD-focusable while invisible. Let the
      // sheet grow and scroll instead (same pattern as the merged-screen
      // quick-actions sheets).
      isScrollControlled: true,
      builder: (sheetCtx) {
        Widget tile(
          IconData icon,
          String label,
          VoidCallback onTap, {
          Color? color,
          bool autofocus = false,
          String? subtitle,
        }) {
          return ListTile(
            autofocus: autofocus,
            // Default focus overlay is invisible on the dark sheet — make the
            // DPAD cursor obvious.
            focusColor: Colors.white.withValues(alpha: 0.12),
            leading: Icon(icon, color: color ?? Colors.white),
            title: Text(
              label,
              style: TextStyle(
                color: color ?? Theme.of(sheetCtx).colorScheme.onSurface,
              ),
            ),
            subtitle: subtitle == null
                ? null
                : Text(
                    subtitle,
                    style: TextStyle(
                      color: Theme.of(
                        sheetCtx,
                      ).colorScheme.onSurface.withValues(alpha: 0.55),
                      fontSize: 12.5,
                      height: 1.3,
                    ),
                  ),
            onTap: () {
              Navigator.of(sheetCtx).pop();
              onTap();
            },
          );
        }

        // Batch shortcut next to the single-episode toggle: mark every
        // aired episode before this one watched (local + every tracker a
        // normal watched-write would touch). Only for the merged-union
        // ticks — direct sources have no watched storage to write.
        final earlier = !_a.isDirectSource
            ? earlierEpisodes(
                _s.episodeSeasons,
                season: episode.season,
                episode: episode.number,
                now: DateTime.now(),
              )
            : const <EpisodeRef>[];

        final tiles = <Widget>[
          // Autofocus Play on TV so the sheet opens with a live target.
          tile(
            Icons.play_arrow_rounded,
            'Play',
            () => _n.onEpisodeQuickPlay(episode),
            autofocus: _deps.isTelevision(),
          ),
          // Direct-source episodes ARE the source — no torrent list to open.
          if (_deps.onPlayEpisode() == null)
            tile(
              Icons.layers_rounded,
              'Sources',
              () => _n.onEpisodeTap(episode),
            ),
          // ONE watched toggle, not one per tracker: the tick is an OR-union
          // of local + every tracker, so a per-provider action leaves the
          // others watched and the tick resurrects on the next re-merge.
          // [_setEpisodeWatchedEverywhere] fans out to all of them (and to
          // local playback storage), so it is offered even with no tracker
          // connected — a locally-finished episode needs it too. The subtitle
          // names every destination up front, so the fan-out is the row's
          // stated contract rather than a surprise.
          if (!watched && !_a.isDirectSource)
            tile(
              Icons.check_circle_rounded,
              'Mark as Watched',
              () => _deps.parts.watchedActions.setEpisodeWatchedEverywhere(
                episode,
                watched: true,
              ),
              subtitle:
                  _deps.parts.watchedActions
                          .watchedSyncTargets(watched: true)
                          .length >
                      1
                  ? 'On ${EpisodesPanelPolicies.joinNames(_deps.parts.watchedActions.watchedSyncTargets(watched: true))}'
                  : null,
            ),
          if (earlier.isNotEmpty)
            tile(
              Icons.done_all_rounded,
              'Mark earlier episodes watched',
              () => _deps.parts.watchedActions.markEarlierWatched(episode),
              subtitle: earlier.length == 1
                  ? '1 episode before this one'
                  : '${earlier.length} episodes before this one',
            ),
          if (watched && !_a.isDirectSource)
            tile(
              Icons.visibility_off_rounded,
              'Mark as Unwatched',
              () => _deps.parts.watchedActions.setEpisodeWatchedEverywhere(
                episode,
                watched: false,
              ),
              subtitle:
                  _deps.parts.watchedActions
                          .watchedSyncTargets(watched: false)
                          .length >
                      1
                  ? 'Clears it on '
                        '${EpisodesPanelPolicies.joinNames(_deps.parts.watchedActions.watchedSyncTargets(watched: false))} — '
                        'all at once, so the tick can\'t come back'
                  : null,
            ),
          if (_a.isTraktAuthenticated)
            tile(
              Icons.star_rounded,
              'Rate on Trakt',
              () => _deps.parts.watchedActions.onEpisodeMenuAction(
                episode,
                TraktEpisodeMenuAction.rate,
              ),
            ),
          if (_a.isMdblistAuthenticated) ...[
            if (_p.episodeMdblistRatings[key] == null)
              tile(
                Icons.star_rounded,
                'Rate on MDBList',
                () => _deps.parts.watchedActions.onEpisodeMdblistMenuAction(
                  episode,
                  MdblistEpisodeMenuAction.rate,
                ),
              ),
            if (_p.episodeMdblistRatings[key] != null)
              tile(
                Icons.star_outline_rounded,
                'Remove MDBList rating (${_p.episodeMdblistRatings[key]}/10)',
                () => _deps.parts.watchedActions.onEpisodeMdblistMenuAction(
                  episode,
                  MdblistEpisodeMenuAction.removeRating,
                ),
              ),
          ],
        ];

        // Opened by a HELD OK, and it autofocuses Play below — so it
        // arrives under a key that is still repeating. Without this the
        // next repeat activates Play and the sheet closes on the very
        // press that opened it.
        return TvHeldKeyGuard(
          child: SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(sheetCtx).size.height * 0.8,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'S${episode.season} · E${episode.number}  ${episode.title}',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      padding: const EdgeInsets.only(bottom: 8),
                      children: tiles,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
