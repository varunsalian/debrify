import 'dart:async';
import 'package:debrify/features/episodes_panel/models/episodes_panel_view.dart';
import 'package:debrify/features/episodes_panel/presentation/episodes_panel_season_step.dart';
import 'package:debrify/features/episodes_panel/presentation/episodes_panel_source_button.dart';
import 'package:debrify/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_auth.dart';
import 'package:debrify/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_compact_row.dart';
import 'package:debrify/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_deps.dart';
import 'package:debrify/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_navigation.dart';
import 'package:debrify/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_parts.dart';
import 'package:debrify/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_progress.dart';
import 'package:debrify/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_resources.dart';
import 'package:debrify/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_services.dart';
import 'package:debrify/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_view_state.dart';
import 'package:debrify/models/advanced_search_selection.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/screens/debrify_tv/widgets/tv_focus_scroll_wrapper.dart';
import 'package:debrify/services/metadata_preferences_service.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/trakt/trakt_episode_model.dart';
import 'package:debrify/utils/episode_progress_merge.dart';
import 'package:debrify/utils/tv_keys.dart';
import 'package:debrify/widgets/detail/theme/detail_theme.dart';
import 'package:debrify/widgets/episode_tile.dart';
import 'package:debrify/widgets/season_action_region.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

export 'package:debrify/features/episodes_panel/models/episodes_panel_view.dart'
    show EpisodeFocusIntent, EpisodesPanelView;

class EpisodesPanel extends StatefulWidget {
  /// The series to browse.
  final StremioMeta show;

  /// Optional explicit season to land on (deep links / calendar).
  final int? initialSeason;

  /// Optional explicit episode to land on (deep links / calendar).
  final int? initialEpisode;

  /// The addon used to fetch series meta (replaces the host's selected addon).
  final StremioAddon addon;

  /// Whether running on Android TV (disables animations, changes focus flow).
  final bool isTelevision;

  /// Whether to show the Quick Play button on episode tiles.
  final bool showQuickPlay;

  /// Whether this series was opened from a Trakt context (e.g. Discover→Trakt).
  /// When true, episode Sources/Play carry the Trakt scrobble flag + Trakt
  /// resume position so playback syncs to Trakt exactly like the old home
  /// episode view. Left false for plain catalog/addon items so their scrobble
  /// stays governed by the user's Tracking scrobble selection.
  final bool isTraktSource;
  final bool isMdblistSource;

  /// Callback when user selects an episode (Sources) or the series falls back
  /// to a direct search.
  final void Function(AdvancedSearchSelection selection)? onItemSelected;

  /// Callback when user quick-plays an episode.
  final void Function(AdvancedSearchSelection selection)? onQuickPlay;

  /// Returns the number of bound sources for [show] (host-owned state).
  final int Function(StremioMeta show)? boundSourceCount;

  /// Callback when user taps the Select Source button. When null, the button
  /// is hidden. Returns a Future that completes when the source picker/editor
  /// closes, so the header's bound-source count can refresh in place.
  final Future<void> Function(StremioMeta show)? onSelectSource;

  /// Invoked when the built-in back affordance is activated. When null the back
  /// button still renders but does nothing (the host owns dismissal).
  final VoidCallback? onBack;

  /// Invoked immediately before a terminal [AdvancedSearchSelection] is
  /// dispatched (episode picked / quick-play / fallback search). The host uses
  /// this to pop its route stack down to where the result should appear and to
  /// mark that a selection — rather than a plain back-out — occurred.
  final VoidCallback? onBeforeTerminalDispatch;

  /// Whether to render the built-in filters bar (back button + title + season
  /// dropdown + Select Source). The standalone [EpisodesScreen] route keeps it
  /// (true). The merged series page supplies its own hero + source binding and
  /// hosts the panel chromeless (false) — only a slim season selector remains
  /// above the list when there is more than one season.
  final bool showChrome;

  /// Stremio-style compact mode (merged series page): render episodes as compact
  /// single-focus rows (thumbnail · number+title · date · watched) with a
  /// pinned "‹ Prev · Season ▾ · Next ›" header, instead of the large
  /// [EpisodeTile] cards + filters bar. A single focus target per row keeps DPAD
  /// clean in the two-pane layout — OK plays, Right opens the per-episode
  /// options menu (Sources / Watched / Rate), Left/Up/Down traverse normally.
  final bool compact;

  /// Compact mode only: invoked when the user presses LEFT on an episode row, so
  /// the host can move focus to a stable target in its left pane (its Play /
  /// source button) instead of letting geometry pick a random mid-column item.
  final VoidCallback? onFocusLeftEdge;

  /// Direct-source mode (Xtream IPTV series): the sole season/episode source.
  /// When set, the Stremio-addon meta and Trakt season fetches are skipped
  /// entirely, along with every IMDb-keyed enrichment (TVMaze stills, Trakt
  /// ratings/next-episode, Trakt/Simkl episode menus) — these shows have no
  /// IMDb identity. Episodes are expected to carry [TraktEpisode.playbackUrl].
  final Future<List<TraktSeason>> Function()? seasonsLoader;

  /// Direct-source mode: play an episode outright (the host launches its
  /// player on top of the page, like quick-play). When set, episode taps and
  /// quick-plays route here instead of building an [AdvancedSearchSelection].
  final void Function(TraktEpisode episode)? onPlayEpisode;

  /// Direct-source mode: resolves the `'<season>-<episode>'` → percent (0-100)
  /// watch-progress map, replacing the IMDb-keyed local/Trakt/Simkl merge.
  final Future<Map<String, double>> Function()? watchProgressLoader;

  /// Publishes the merged next-to-watch coordinate and whether it represents
  /// real playback (rather than the default first episode) to the detail hero.
  /// [mutation] marks emissions caused by an explicit in-page user action
  /// (mark watched/unwatched) — the detail pill applies those after its
  /// loader has settled, while plain re-merge emissions (slower tracker
  /// fetches landing) must not late-flip a settled pill.
  final void Function(EpisodeResumeTarget next, {bool mutation})?
  onNextEpisodeChanged;
  final ValueChanged<bool>? onSeriesCompletedChanged;

  /// Alternate arrangement. Null (the default) keeps today's rendering exactly;
  /// when set, the panel renders ONLY what this returns — no chrome of its own —
  /// and suppresses its internal scroll/focus side effects, which target widgets
  /// that a custom tree does not contain.
  final Widget Function(BuildContext, EpisodesPanelView)? contentBuilder;

  const EpisodesPanel({
    super.key,
    required this.show,
    required this.addon,
    this.initialSeason,
    this.initialEpisode,
    this.isTelevision = false,
    this.showQuickPlay = true,
    this.isTraktSource = false,
    this.isMdblistSource = false,
    this.onItemSelected,
    this.onQuickPlay,
    this.boundSourceCount,
    this.onSelectSource,
    this.onBack,
    this.onBeforeTerminalDispatch,
    this.showChrome = true,
    this.compact = false,
    this.onFocusLeftEdge,
    this.seasonsLoader,
    this.onPlayEpisode,
    this.watchProgressLoader,
    this.onNextEpisodeChanged,
    this.onSeriesCompletedChanged,
    this.contentBuilder,
  });

  @override
  State<EpisodesPanel> createState() => EpisodesPanelState();
}

/// Public so a host that keeps this panel alive across playback (the merged
/// detail page plays on top of itself) can reach [refreshWatchProgress] via a
/// GlobalKey when the player pops back.
class EpisodesPanelState extends State<EpisodesPanel> {
  late final EpisodesPanelDeps _deps;
  late final EpisodesPanelParts _parts;
  EpisodesPanelState() {
    final services = EpisodesPanelServices();
    final viewState = EpisodesPanelViewState();
    _deps = EpisodesPanelDeps(
      context: () => context,
      mounted: () => mounted,
      setState: setState,
      refreshWatchProgress: refreshWatchProgress,
      show: () => widget.show,
      initialSeason: () => widget.initialSeason,
      initialEpisode: () => widget.initialEpisode,
      addon: () => widget.addon,
      isTelevision: () => widget.isTelevision,
      showQuickPlay: () => widget.showQuickPlay,
      isTraktSource: () => widget.isTraktSource,
      isMdblistSource: () => widget.isMdblistSource,
      onItemSelected: () => widget.onItemSelected,
      onQuickPlay: () => widget.onQuickPlay,
      boundSourceCount: () => widget.boundSourceCount,
      onSelectSource: () => widget.onSelectSource,
      onBack: () => widget.onBack,
      onBeforeTerminalDispatch: () => widget.onBeforeTerminalDispatch,
      showChrome: () => widget.showChrome,
      compact: () => widget.compact,
      onFocusLeftEdge: () => widget.onFocusLeftEdge,
      seasonsLoader: () => widget.seasonsLoader,
      onPlayEpisode: () => widget.onPlayEpisode,
      watchProgressLoader: () => widget.watchProgressLoader,
      onNextEpisodeChanged: () => widget.onNextEpisodeChanged,
      onSeriesCompletedChanged: () => widget.onSeriesCompletedChanged,
      contentBuilder: () => widget.contentBuilder,
      custom: () => _custom,
      currentSeasonIndex: () => _currentSeasonIndex,
    );
    final progress = EpisodesPanelProgress(_deps);
    final auth = EpisodesPanelAuth(_deps);
    final resources = EpisodesPanelResources();
    _parts = EpisodesPanelParts(
      _deps,
      services: services,
      viewState: viewState,
      progress: progress,
      auth: auth,
      resources: resources,
    );
    _deps.parts = _parts;
  }

  EpisodesPanelViewState get _s => _parts.viewState;
  EpisodesPanelProgress get _p => _parts.progress;
  EpisodesPanelAuth get _a => _parts.auth;
  EpisodesPanelResources get _r => _parts.resources;
  EpisodesPanelServices get _sv => _parts.services;
  EpisodesPanelNavigation get _n => _parts.navigation;

  /// True when a custom arrangement is driving. Gates every engine side effect
  /// that targets a widget only the classic tree contains.
  bool get _custom => widget.contentBuilder != null;

  @override
  void initState() {
    super.initState();
    MetadataPreferencesService.revision.addListener(
      _parts.metadata.episodePolicyChanged,
    );
    ProfileRuntime.scope.addListener(_parts.metadata.episodePolicyChanged);
    // The custom season-dropdown key handler deliberately traps Up/Left/Right
    // for the standalone route's single-row header. When hosted chromeless
    // (merged page), leave it to default directional focus so Up escapes to the
    // host's hero instead of dead-ending.
    if (widget.showChrome) {
      _r.episodeSeasonDropdownFocusNode.onKeyEvent =
          _handleEpisodeSeasonDropdownKeyEvent;
    }
    _a.resolveTraktAuth();
    _a.resolveSimklAuth();
    _a.resolveMdblistAuth();
    _sv.mdblistService.playbackRevision.addListener(
      _a.onMdblistPlaybackRevision,
    );
    _parts.mode.enterEpisodeMode(
      widget.show,
      initialSeason: widget.initialSeason,
      initialEpisode: widget.initialEpisode,
    );
  }

  @override
  void dispose() {
    MetadataPreferencesService.revision.removeListener(
      _parts.metadata.episodePolicyChanged,
    );
    ProfileRuntime.scope.removeListener(_parts.metadata.episodePolicyChanged);
    _a.mdblistRefreshToken++;
    _sv.mdblistService.playbackRevision.removeListener(
      _a.onMdblistPlaybackRevision,
    );
    _r.episodeScrollController.dispose();
    _r.episodeBackButtonFocusNode.dispose();
    _r.episodeSeasonDropdownFocusNode.dispose();
    _r.episodeRetryFocusNode.dispose();
    for (final node in _r.episodeFocusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  /// Re-read watch progress (local + Trakt) for the current show. Called by the
  /// merged detail host when the player pops back onto it, so the just-watched
  /// episode's tick/progress bar updates without leaving the list.
  Future<void> refreshWatchProgress() async {
    final show = _s.selectedShow;
    if (show == null) return;
    await _p.loadEpisodeWatchProgress(show, _s.episodeModeGeneration);
  }

  Widget _buildEpisodeFiltersBar() {
    final t = DetailThemeScope.maybeOf(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.08),
            width: 0.5,
          ),
        ),
        child: Row(
          children: [
            // Back button — Focus-wrapped with blue accent border like Trakt
            Focus(
              focusNode: _r.episodeBackButtonFocusNode,
              onFocusChange: (focused) => setState(() {}),
              onKeyEvent: (node, event) {
                if (event is! KeyDownEvent) return KeyEventResult.ignored;
                if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                  // Top of a standalone route — nothing above to focus
                  // (the host is covered). Swallow so focus stays put.
                  return KeyEventResult.handled;
                }
                if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
                  if (_s.episodesUnavailable) {
                    _r.episodeRetryFocusNode.requestFocus();
                  } else {
                    _r.episodeSeasonDropdownFocusNode.requestFocus();
                  }
                  return KeyEventResult.handled;
                }
                if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                  if (_s.episodesUnavailable) {
                    _r.episodeRetryFocusNode.requestFocus();
                  } else if (_r.episodeFocusNodes.isNotEmpty) {
                    _r.episodeFocusNodes.first.requestFocus();
                  }
                  return KeyEventResult.handled;
                }
                if (isActivateKey(event.logicalKey) ||
                    event.logicalKey == LogicalKeyboardKey.escape ||
                    event.logicalKey == LogicalKeyboardKey.goBack) {
                  widget.onBack?.call();
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _r.episodeBackButtonFocusNode.hasFocus
                      ? Colors.white.withValues(alpha: 0.16)
                      : Colors.white.withValues(alpha: 0.06),
                  border: Border.all(
                    color: _r.episodeBackButtonFocusNode.hasFocus
                        ? t.focus
                        : Colors.white.withValues(alpha: 0.14),
                    width: _r.episodeBackButtonFocusNode.hasFocus ? 2 : 1,
                  ),
                ),
                child: IconButton(
                  padding: EdgeInsets.zero,
                  iconSize: 20,
                  color: Colors.white,
                  icon: const Icon(Icons.arrow_back_rounded),
                  onPressed: () => widget.onBack?.call(),
                  tooltip: 'Back to shows',
                ),
              ),
            ),
            const SizedBox(width: 8),

            // Show title
            Expanded(
              child: Text(
                _s.selectedShow?.name ?? '',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),

            // Season dropdown — Trakt-style with blue accent border
            if (_s.episodeSeasons.isNotEmpty) ...[
              const SizedBox(width: 8),
              _buildEpisodeSeasonDropdown(),
            ],

            // Select Source button
            if (_s.selectedShow != null && widget.onSelectSource != null) ...[
              const SizedBox(width: 8),
              Builder(
                builder: (context) {
                  final sourceCount =
                      widget.boundSourceCount?.call(_s.selectedShow!) ?? 0;
                  return EpisodesPanelSourceButton(
                    hasBoundSource: sourceCount > 0,
                    sourceCount: sourceCount,
                    // Await the picker so the bound-source count updates in
                    // place when it closes (no need to leave and re-enter).
                    onTap: () async {
                      await widget.onSelectSource!(_s.selectedShow!);
                      if (mounted) setState(() {});
                    },
                    onLeftFocus: _s.episodeSeasons.isNotEmpty
                        ? _r.episodeSeasonDropdownFocusNode
                        : _r.episodeBackButtonFocusNode,
                    onDownArrow: _r.episodeFocusNodes.isNotEmpty
                        ? () => _r.episodeFocusNodes.first.requestFocus()
                        : null,
                    // Top row of a standalone route — swallow Up (a non-null
                    // no-op makes the button report the key handled).
                    onUpArrow: () {},
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  KeyEventResult _handleEpisodeSeasonDropdownKeyEvent(
    FocusNode node,
    KeyEvent event,
  ) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      // Top row of a standalone route — swallow (nothing above).
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (_r.episodeFocusNodes.isNotEmpty) {
        _r.episodeFocusNodes.first.requestFocus();
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _r.episodeBackButtonFocusNode.requestFocus();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      if (widget.onSelectSource != null) {
        node.nextFocus();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget _buildEpisodeSeasonDropdown() {
    // Resolved OUTSIDE the ListenableBuilder: the callback re-runs on every
    // focus change, and an inherited-widget lookup there would re-subscribe
    // per DPAD move on the weak TV GPU.
    final t = DetailThemeScope.maybeOf(context);
    return SeasonActionRegion(
      onOptions: _a.isDirectSource
          ? null
          : () =>
                _parts.seasonOptions.showSeasonOptions(_s.selectedSeasonNumber),
      onTap: () async {
        final number = await showModalBottomSheet<int>(
          context: context,
          builder: (ctx) => TvHeldKeyGuard(
            child: SafeArea(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final season in _s.episodeSeasons)
                    ListTile(
                      title: Text('Season ${season.number}'),
                      onTap: () => Navigator.pop(ctx, season.number),
                    ),
                ],
              ),
            ),
          ),
        );
        if (mounted && number != null) _n.onSeasonChanged(number);
      },
      child: ListenableBuilder(
        listenable: _r.episodeSeasonDropdownFocusNode,
        builder: (context, _) {
          final hasFocus = _r.episodeSeasonDropdownFocusNode.hasFocus;
          return AnimatedContainer(
            // TV: snap the focus ring and skip the blurred glow — the animated
            // blur shadow re-rasters every frame of the fade on the weak GPU.
            duration: widget.isTelevision
                ? Duration.zero
                : const Duration(milliseconds: 150),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: hasFocus ? 0.12 : 0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: hasFocus
                    ? t.focus
                    : Colors.white.withValues(alpha: 0.10),
                width: hasFocus ? 2.0 : 1.0,
              ),
              boxShadow: (hasFocus && !widget.isTelevision)
                  ? [
                      BoxShadow(
                        color: t.fade(t.focus, 0.32),
                        blurRadius: 14,
                        spreadRadius: 0,
                      ),
                    ]
                  : null,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                focusNode: _r.episodeSeasonDropdownFocusNode,
                focusColor: Colors.transparent,
                value: _s.selectedSeasonNumber,
                isDense: true,
                borderRadius: BorderRadius.circular(12),
                dropdownColor: const Color(0xFF14141C),
                icon: Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 20,
                  color: hasFocus
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.7),
                ),
                items: _s.episodeSeasons.map((s) {
                  return DropdownMenuItem(
                    value: s.number,
                    child: Text(
                      s.displayLabel,
                      // Explicit color: dropdown menu items render outside the
                      // page's DefaultTextStyle. onSurface follows the
                      // Appearance → Text Brightness preset.
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontSize: 13,
                      ),
                    ),
                  );
                }).toList(),
                onChanged: _n.onSeasonChanged,
              ),
            ),
          );
        },
      ),
    );
  }

  /// Inline "couldn't load episodes" panel with Retry (recovers a transient
  /// failure without leaving the drill-down) and an explicit "Search for
  /// sources" action (the old auto-fallback, now opt-in).
  Widget _buildEpisodesUnavailable() {
    final show = _s.selectedShow ?? widget.show;
    // Hoisted: the WidgetStateProperty resolvers below are closures the button
    // re-evaluates on every state change, not build-time code.
    final t = DetailThemeScope.maybeOf(context);
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
                  autofocus: widget.isTelevision,
                  // Default focus overlay is faint on dark — gold ring on focus
                  // like every other DPAD target in the drill-down.
                  style: ButtonStyle(
                    side: WidgetStateProperty.resolveWith(
                      (states) => states.contains(WidgetState.focused)
                          ? BorderSide(color: t.focus, width: 2)
                          : null,
                    ),
                  ),
                  onPressed: () => _parts.mode.enterEpisodeMode(
                    show,
                    initialSeason: widget.initialSeason,
                    initialEpisode: widget.initialEpisode,
                  ),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Retry'),
                ),
                // No torrent-search fallback exists for direct-source shows —
                // Retry is the only honest offer there.
                if (widget.onItemSelected != null)
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

  Widget _buildEpisodeContent() {
    if (_s.isLoadingEpisodes) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_s.episodesUnavailable || _s.episodeSeasons.isEmpty) {
      return _buildEpisodesUnavailable();
    }

    final currentSeason = _s.episodeSeasons.firstWhere(
      (s) => s.number == _s.selectedSeasonNumber,
      orElse: () => _s.episodeSeasons.first,
    );

    final w = MediaQuery.of(context).size.width;
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
              isTelevision: widget.isTelevision,
              showQuickPlay: widget.showQuickPlay,
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
                  ? (action) => _parts.watchedActions.onEpisodeMenuAction(
                      episode,
                      action,
                    )
                  : null,
              onTrackerOptions:
                  _a.isSimklAuthenticated || _a.isMdblistAuthenticated
                  ? () => _parts.episodeOptions.showEpisodeOptions(episode)
                  : null,
            ),
          );
        },
      ),
    );
  }

  /// Chromeless header: just a left-aligned season selector (when there is more
  /// than one season). Used by the merged series page, which owns the back
  /// button, title and source binding in its own hero.
  Widget _buildSlimSeasonRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: _buildEpisodeSeasonDropdown(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final custom = widget.contentBuilder;
    if (custom != null) return custom(context, _buildView());
    if (widget.compact) {
      return Column(
        children: [
          if (!_s.isLoadingEpisodes &&
              !_s.episodesUnavailable &&
              _s.episodeSeasons.isNotEmpty)
            _buildCompactSeasonHeader(),
          Expanded(child: _buildCompactContent()),
        ],
      );
    }
    return Column(
      children: [
        if (widget.showChrome)
          _buildEpisodeFiltersBar()
        else if (_s.episodeSeasons.length > 1)
          _buildSlimSeasonRow(),
        Expanded(child: _buildEpisodeContent()),
      ],
    );
  }

  /// Snapshot handed to a custom arrangement. Cheap — it closes over state
  /// rather than copying it, and is rebuilt with the panel.
  EpisodesPanelView _buildView() {
    final season = _s.episodeSeasons
        .where((s) => s.number == _s.selectedSeasonNumber)
        .firstOrNull;
    final episodes =
        season?.episodes ?? _s.episodeSeasons.firstOrNull?.episodes ?? const [];
    final show = _s.selectedShow ?? widget.show;
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
      options: _parts.episodeOptions.showEpisodeOptions,
      stepSeason: _n.stepSeason,
      selectSeason: (n) => _n.onSeasonChanged(n),
      seasonOptions: _a.isDirectSource
          ? null
          : _parts.seasonOptions.showSeasonOptions,
      onLeftEdge: widget.onFocusLeftEdge,
      onRetry: () => _parts.mode.enterEpisodeMode(
        show,
        initialSeason: widget.initialSeason,
        initialEpisode: widget.initialEpisode,
      ),
      // Mirrors the classic failure UI: no torrent-search fallback exists for
      // direct-source shows, so the offer is withheld rather than dead.
      onSearchForSources: widget.onItemSelected != null
          ? () => _n.fallbackToDirectSearch(show)
          : null,
    );
  }

  /// Layouts call this after acting on [EpisodeFocusIntent], so a rebuild that
  /// isn't a data change doesn't yank the cursor a second time.
  void consumeFocusIntent() {
    if (_s.focusIntent == EpisodeFocusIntent.none) return;
    _s.focusIntent = EpisodeFocusIntent.none;
  }

  // ── Compact (Stremio) rendering ──────────────────────────────────────────
  int get _currentSeasonIndex =>
      _s.episodeSeasons.indexWhere((s) => s.number == _s.selectedSeasonNumber);

  /// Pinned "‹ Prev · Season ▾ · Next ›" header — always visible above the list
  /// (this is what "the season dropdown isn't reachable" was about).
  Widget _buildCompactSeasonHeader() {
    final i = _currentSeasonIndex;
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
                  ? _buildEpisodeSeasonDropdown()
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
          if (widget.isTelevision) ...[
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

  Widget _buildCompactContent() {
    if (_s.isLoadingEpisodes) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_s.episodesUnavailable || _s.episodeSeasons.isEmpty) {
      return _buildEpisodesUnavailable();
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
            isTelevision: widget.isTelevision,
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
            onOptions: () => _parts.episodeOptions.showEpisodeOptions(episode),
            onLeft: widget.onFocusLeftEdge,
          ),
        );
      },
    );
  }
}
