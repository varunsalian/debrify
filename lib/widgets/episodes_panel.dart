import 'dart:async';
import 'package:debrify/features/episodes_panel/models/episodes_panel_view.dart';
import 'package:debrify/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_auth.dart';
import 'package:debrify/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_deps.dart';
import 'package:debrify/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_parts.dart';
import 'package:debrify/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_progress.dart';
import 'package:debrify/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_resources.dart';
import 'package:debrify/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_services.dart';
import 'package:debrify/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_view_state.dart';
import 'package:debrify/models/advanced_search_selection.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/metadata_preferences_service.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/trakt/trakt_episode_model.dart';
import 'package:debrify/utils/episode_progress_merge.dart';
import 'package:debrify/widgets/episode_tile.dart';
import 'package:flutter/material.dart';

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
          _parts.classicChrome.handleEpisodeSeasonDropdownKeyEvent;
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

  /// Layouts call this after acting on [EpisodeFocusIntent], so a rebuild that
  /// isn't a data change doesn't yank the cursor a second time.
  void consumeFocusIntent() {
    if (_s.focusIntent == EpisodeFocusIntent.none) return;
    _s.focusIntent = EpisodeFocusIntent.none;
  }

  @override
  Widget build(BuildContext context) => _parts.rootLayout.build(context);
}
