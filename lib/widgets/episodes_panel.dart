import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/stremio_addon.dart';
import '../models/advanced_search_selection.dart';
import '../services/debrify_image_cache.dart';
import '../services/stremio_service.dart';
import '../services/trakt/trakt_episode_model.dart';
import '../services/trakt/trakt_service.dart';
import '../services/tvmaze_service.dart';
import '../services/storage_service.dart';
import '../services/local_series_completion_service.dart';
import '../utils/platform_util.dart';
import '../utils/episode_progress_merge.dart';
import '../utils/tv_keys.dart';
import '../screens/debrify_tv/widgets/tv_focus_scroll_wrapper.dart';
import '../theme/app_theme_scope.dart';
import 'detail/detail_style.dart';
import 'detail/theme/detail_theme.dart';
import 'episode_tile.dart';
import 'trakt/trakt_menu_helpers.dart';
import '../services/simkl/simkl_service.dart';
import '../services/simkl/simkl_menu_helpers.dart';
import '../services/mdblist/mdblist_service.dart';
import '../services/mdblist/mdblist_continue_watching_service.dart';
import '../services/mdblist/mdblist_models.dart';
import '../services/mdblist/mdblist_menu_helpers.dart';
import 'home/home_theme.dart';

/// The episode drill-down engine + UI, extracted out of `EpisodesScreen` so it
/// can be hosted both as a standalone route (the existing `EpisodesScreen`
/// wrapper) and inline inside the merged series page — without forking the
/// season-fetch / landing / playback-selection logic.
///
/// This widget is **navigation-agnostic**: it never pushes or pops routes.
/// Terminal actions (episode picked / quick-play / fallback-to-search) build an
/// [AdvancedSearchSelection] and, just before dispatching it, call
/// [onBeforeTerminalDispatch] so the host can tear its route stack down to
/// wherever the result should land. The back affordance calls [onBack].
/// What a custom arrangement should move focus to when the view generation
/// changes. Mirrors what Classic does implicitly.
enum EpisodeFocusIntent {
  /// Nothing should move (a rebuild that isn't a data change).
  none,

  /// A fresh load or deep link resolved — reveal and focus [EpisodesPanelView.landing].
  landing,

  /// The user stepped the season; their attention is on the stepper, so the
  /// layout re-focuses its own season control. Classic does the same thing by
  /// re-requesting `_episodeSeasonDropdownFocusNode`.
  seasonControl,
}

/// Everything a custom episode arrangement needs, so alternate layouts can be
/// drawn without forking the engine (season loading, the Trakt/Simkl watch
/// merge, enrichment, playback dispatch and the options sheet all stay here).
///
/// Handed to [EpisodesPanel.contentBuilder]. Layouts own their own FocusNodes —
/// they must NOT reach for the engine's, which are disposed and rebuilt on
/// every season change.
class EpisodesPanelView {
  final List<TraktSeason> seasons;
  final int selectedSeasonNumber;

  /// Episodes of the selected season. Empty while loading or on failure.
  final List<TraktEpisode> episodes;
  final bool loading;
  final bool unavailable;

  /// Poster fallback for episodes with no still of their own.
  final String? showImageUrl;

  /// Bumped when resolved episodes are PUBLISHED and on every season swap.
  ///
  /// Deliberately not the engine's internal load generation, which bumps when a
  /// load *starts* (and guards enrichment) — a layout first built during
  /// loading would then never see it change when the data actually landed.
  final int generation;

  /// The episode the engine resolved to land on — an explicit deep link, else
  /// Trakt next-up, else local last-played, else the season's first. Validated
  /// as a pair: a stored episode number is only honoured when its season is the
  /// season that was actually selected. Null while loading / when empty.
  final TraktEpisode? landing;

  final EpisodeFocusIntent focusIntent;

  /// 0..100, or null when the episode has no progress.
  final double? Function(TraktEpisode) progressOf;
  final bool Function(TraktEpisode) isNext;
  final void Function(TraktEpisode) play;
  final void Function(TraktEpisode) options;
  final void Function(int delta) stepSeason;
  final void Function(int seasonNumber) selectSeason;

  /// Host's stable LEFT-crossing target, when it supplied one.
  final VoidCallback? onLeftEdge;

  /// Failure terminals. [onSearchForSources] is null when the host gave no
  /// `onItemSelected` — direct-source shows have no torrent-search fallback.
  final VoidCallback onRetry;
  final VoidCallback? onSearchForSources;

  const EpisodesPanelView({
    required this.seasons,
    required this.selectedSeasonNumber,
    required this.episodes,
    required this.loading,
    required this.unavailable,
    required this.showImageUrl,
    required this.generation,
    required this.landing,
    required this.focusIntent,
    required this.progressOf,
    required this.isNext,
    required this.play,
    required this.options,
    required this.stepSeason,
    required this.selectSeason,
    required this.onLeftEdge,
    required this.onRetry,
    required this.onSearchForSources,
  });
}

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
  /// stays governed by the user's "Sync Catalog Items" setting.
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

  /// Publishes the merged next-to-watch coordinate to a hosting detail hero.
  final ValueChanged<EpisodeCoordinate>? onNextEpisodeChanged;

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
    this.contentBuilder,
  });

  @override
  State<EpisodesPanel> createState() => EpisodesPanelState();
}

/// Public so a host that keeps this panel alive across playback (the merged
/// detail page plays on top of itself) can reach [refreshWatchProgress] via a
/// GlobalKey when the player pops back.
class EpisodesPanelState extends State<EpisodesPanel> {
  final StremioService _stremioService = StremioService.instance;
  final TraktService _traktService = TraktService.instance;
  final SimklService _simklService = SimklService.instance;
  final MdblistService _mdblistService = MdblistService.instance;

  // Episode drill-down state
  int _episodeModeGeneration = 0;
  StremioMeta? _selectedShow;
  List<TraktSeason> _episodeSeasons = [];
  int _selectedSeasonNumber = 1;
  bool _isLoadingEpisodes = false;

  /// True when a season fetch yielded no episodes. Instead of auto-diverting to
  /// a whole-series torrent search (which a transient network blip could
  /// trigger, yanking the user out of the drill-down), we show an inline
  /// error+Retry panel — matching old home — with an explicit "Search for
  /// sources" action that preserves the catalog pack-search path on demand.
  bool _episodesUnavailable = false;
  Map<String, double> _episodeWatchProgress = {};
  Map<String, int> _episodeMdblistRatings = {};

  /// Bumped when resolved episodes are PUBLISHED and on every season swap —
  /// see [EpisodesPanelView.generation] for why this is not the load
  /// generation. Only read by custom arrangements.
  int _viewGeneration = 0;
  TraktEpisode? _landing;
  EpisodeFocusIntent _focusIntent = EpisodeFocusIntent.none;

  /// True when a custom arrangement is driving. Gates every engine side effect
  /// that targets a widget only the classic tree contains.
  bool get _custom => widget.contentBuilder != null;

  /// The next episode to watch for the current show. Trakt supplies the initial
  /// hint; merged local/Trakt/Simkl/MDBList progress reconciles the final badge.
  ({int season, int episode})? _nextEpisode;

  /// Whether a Trakt account is connected. This screen is reachable from
  /// Discover/catalog without Trakt, so the Trakt-only episode menu (mark
  /// watched/unwatched, rate) is only offered when this is true.
  bool _isTraktAuthenticated = false;

  /// Whether a Simkl account is connected — mirrors [_isTraktAuthenticated],
  /// gating the separate Simkl episode menu rows.
  bool _isSimklAuthenticated = false;
  bool _isMdblistAuthenticated = false;

  // MDBList can acknowledge a completed scrobble just before the player route
  // finishes popping, and its watched snapshot can trail that acknowledgement
  // briefly. Keep only the newest mutation refresh, wait until this panel's
  // route is visible, then perform one consistency retry. Without this, the
  // pre-stop refresh could leave a completed episode showing its old local
  // progress until the detail page was reopened.
  int _mdblistRefreshToken = 0;

  final List<FocusNode> _episodeFocusNodes = [];
  final ScrollController _episodeScrollController = ScrollController();
  final FocusNode _episodeBackButtonFocusNode = FocusNode(
    debugLabel: 'catalog-ep-back',
  );
  final FocusNode _episodeSeasonDropdownFocusNode = FocusNode(
    debugLabel: 'catalog-ep-season',
  );
  // Retry button in the "couldn't load episodes" panel, so the back button can
  // hand focus to it (the season dropdown / episode list aren't in the tree
  // in that state).
  final FocusNode _episodeRetryFocusNode = FocusNode(
    debugLabel: 'catalog-ep-retry',
  );

  @override
  void initState() {
    super.initState();
    // The custom season-dropdown key handler deliberately traps Up/Left/Right
    // for the standalone route's single-row header. When hosted chromeless
    // (merged page), leave it to default directional focus so Up escapes to the
    // host's hero instead of dead-ending.
    if (widget.showChrome) {
      _episodeSeasonDropdownFocusNode.onKeyEvent =
          _handleEpisodeSeasonDropdownKeyEvent;
    }
    _resolveTraktAuth();
    _resolveSimklAuth();
    _resolveMdblistAuth();
    _mdblistService.playbackRevision.addListener(_onMdblistPlaybackRevision);
    _enterEpisodeMode(
      widget.show,
      initialSeason: widget.initialSeason,
      initialEpisode: widget.initialEpisode,
    );
  }

  @override
  void dispose() {
    _mdblistRefreshToken++;
    _mdblistService.playbackRevision.removeListener(_onMdblistPlaybackRevision);
    _episodeScrollController.dispose();
    _episodeBackButtonFocusNode.dispose();
    _episodeSeasonDropdownFocusNode.dispose();
    _episodeRetryFocusNode.dispose();
    for (final node in _episodeFocusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  /// Load episode watch progress for the selected show.
  ///
  /// Merges two sources so both local (in-app, offline) and Trakt-tracked
  /// watches are reflected — the old inline Trakt episode view only read Trakt,
  /// the old catalog view only read local storage; a series opened from
  /// Discover→Trakt needs both. All three sources key episodes as
  /// `'<season>-<episode>'`, so they merge directly.
  Future<void> _loadEpisodeWatchProgress(
    StremioMeta show,
    int generation,
  ) async {
    // Direct-source mode: the host owns progress (URL-keyed player positions
    // mapped to S-E), and none of the IMDb-keyed sources below can know these
    // episodes.
    final progressLoader = widget.watchProgressLoader;
    if (progressLoader != null) {
      try {
        final map = await progressLoader();
        if (!mounted || generation != _episodeModeGeneration) return;
        setState(() => _episodeWatchProgress = map);
      } catch (e) {
        debugPrint('EpisodesPanel: direct progress fetch failed: $e');
      }
      return;
    }

    final imdbId = show.effectiveImdbId;
    if (imdbId == null) return;

    // Local in-app playback progress (works without a Trakt account).
    final merged = <String, double>{
      ...await StorageService.getEpisodeWatchProgressByImdbId(imdbId),
    };
    if (!mounted || generation != _episodeModeGeneration) return;

    // Overlay Trakt state when connected (these are no-ops / empty when not).
    try {
      final watched = await _traktService.fetchWatchedShowEpisodes(imdbId);
      if (!mounted || generation != _episodeModeGeneration) return;
      final playback = await _traktService.fetchEpisodePlaybackProgress(imdbId);
      if (!mounted || generation != _episodeModeGeneration) return;

      // Fully-watched episodes win outright.
      for (final key in watched) {
        merged[key] = 100.0;
      }
      // Partial playback overlays, but never downgrades a completed episode and
      // only when it's meaningful and higher than what we already have.
      for (final entry in playback.entries) {
        final existing = merged[entry.key] ?? 0;
        if (existing >= 100.0) continue;
        if (entry.value > 5.0 && entry.value > existing) {
          merged[entry.key] = entry.value;
        }
      }
    } catch (e) {
      debugPrint('EpisodesPanel: Trakt episode progress fetch failed: $e');
    }

    // Overlay Simkl state — a third source, same merge rules as Trakt's
    // (watched wins outright, partials only raise). Skipped entirely when
    // Simkl isn't connected so disconnected users pay zero extra calls.
    //
    // Asked FRESH rather than read off [_isSimklAuthenticated]: that field is
    // resolved concurrently from initState, and this loader used to win the
    // race against it — silently skipping the Simkl overlay on first open.
    // It only STARTED losing when the profiles/at-rest-encryption work turned
    // the token read from one SharedPreferences hop into ProfilePreferences +
    // SecretVault, which is exactly when "no ticks on a fresh install with
    // only Simkl history" was reported (2026-08-16). Nothing re-runs this
    // loader when the field flips later, so losing the race wasn't a delay —
    // it was a miss. One storage read here keeps the no-API-when-disconnected
    // intent without racing anybody; the field keeps gating the episode MENU
    // rows, where by open-time it has long settled.
    if (await _simklService.isAuthenticated()) {
      try {
        final watched = await _simklService.fetchWatchedShowEpisodes(imdbId);
        if (!mounted || generation != _episodeModeGeneration) return;
        final playback = await _simklService.fetchEpisodePlaybackProgress(
          imdbId,
        );
        if (!mounted || generation != _episodeModeGeneration) return;

        for (final key in watched) {
          merged[key] = 100.0;
        }
        for (final entry in playback.entries) {
          final existing = merged[entry.key] ?? 0;
          if (existing >= 100.0) continue;
          if (entry.value > 5.0 && entry.value > existing) {
            merged[entry.key] = entry.value;
          }
        }
      } catch (e) {
        debugPrint('EpisodesPanel: Simkl episode progress fetch failed: $e');
      }
    }

    if (await _mdblistService.isAuthenticated()) {
      try {
        final result = await _mdblistService.fetchShowEpisodeProgress(imdbId);
        if (!mounted || generation != _episodeModeGeneration) return;
        if (result.isUsable) {
          for (final entry in result.data!.entries) {
            final existing = merged[entry.key] ?? 0;
            if (entry.value >= 100 || entry.value > existing) {
              merged[entry.key] = entry.value;
            }
          }
        }
      } catch (e) {
        debugPrint('EpisodesPanel: MDBList episode progress fetch failed: $e');
      }
      try {
        final result = await _mdblistService.fetchShowEpisodeRatings(imdbId);
        if (!mounted || generation != _episodeModeGeneration) return;
        if (result.isUsable) {
          _episodeMdblistRatings = result.data!;
        }
      } catch (e) {
        debugPrint('EpisodesPanel: MDBList episode ratings fetch failed: $e');
      }
    }

    if (mounted && generation == _episodeModeGeneration) {
      final next = _mergedUpNext(merged, _nextEpisode);
      setState(() {
        _episodeWatchProgress = merged;
        _nextEpisode = next;
      });
      if (next != null) widget.onNextEpisodeChanged?.call(next);
    }
  }

  ({int season, int episode})? _mergedUpNext(
    Map<String, double> progress,
    ({int season, int episode})? trackerNext,
  ) => mergedEpisodeUpNext(
    episodes: [
      for (final season in _episodeSeasons)
        for (final episode in season.episodes)
          (season: episode.season, episode: episode.number),
    ],
    progress: progress,
    trackerNext: trackerNext,
  );

  void _onMdblistPlaybackRevision() {
    if (!mounted || _isDirectSource) return;
    MdblistContinueWatchingService.instance.invalidate();
    final token = ++_mdblistRefreshToken;
    unawaited(_refreshAfterMdblistMutation(token));
  }

  Future<void> _refreshAfterMdblistMutation(int token) async {
    // A successful stop is reported while the player route may still cover the
    // detail page. Do not discard that notification; wait for the pop instead.
    for (var attempt = 0; attempt < 20; attempt++) {
      if (!mounted || token != _mdblistRefreshToken) return;
      if (ModalRoute.of(context)?.isCurrent ?? true) break;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    if (!mounted || token != _mdblistRefreshToken) return;
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;

    await refreshWatchProgress();
    if (!mounted || token != _mdblistRefreshToken) return;

    // MDBList's /scrobble/stop response can precede /sync/watched becoming
    // readable. A sequential retry also prevents an older concurrent refresh
    // from being the final state painted by this panel.
    await Future<void>.delayed(const Duration(milliseconds: 750));
    if (!mounted || token != _mdblistRefreshToken) return;
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
    await refreshWatchProgress();
  }

  /// Re-read watch progress (local + Trakt) for the current show. Called by the
  /// merged detail host when the player pops back onto it, so the just-watched
  /// episode's tick/progress bar updates without leaving the list.
  Future<void> refreshWatchProgress() async {
    final show = _selectedShow;
    if (show == null) return;
    await _loadEpisodeWatchProgress(show, _episodeModeGeneration);
  }

  /// Direct-source mode (see [EpisodesPanel.seasonsLoader]) — episodes are
  /// playable URLs with no IMDb identity, so every IMDb-keyed pathway is off.
  bool get _isDirectSource => widget.seasonsLoader != null;

  /// Resolve whether a Trakt account is connected (gates the episode menu).
  Future<void> _resolveTraktAuth() async {
    if (_isDirectSource) return; // no IMDb id — the Trakt menu can't act
    final authed = await _traktService.isAuthenticated();
    if (mounted && authed != _isTraktAuthenticated) {
      setState(() => _isTraktAuthenticated = authed);
    }
  }

  /// Resolve whether a Simkl account is connected — mirrors [_resolveTraktAuth].
  Future<void> _resolveSimklAuth() async {
    if (_isDirectSource) return; // mirrors _resolveTraktAuth
    final authed = await _simklService.isAuthenticated();
    if (mounted && authed != _isSimklAuthenticated) {
      setState(() => _isSimklAuthenticated = authed);
    }
  }

  Future<void> _resolveMdblistAuth() async {
    if (_isDirectSource) return;
    final authed = await _mdblistService.isAuthenticated();
    if (mounted && authed != _isMdblistAuthenticated) {
      setState(() => _isMdblistAuthenticated = authed);
    }
  }

  /// Handle the episode long-press menu (mark watched/unwatched, rate) against
  /// Trakt, mirroring the inline Trakt view. Watched-state changes are
  /// reflected locally in [_episodeWatchProgress] so the tile updates at once.
  Future<void> _onEpisodeMenuAction(
    TraktEpisode episode,
    TraktEpisodeMenuAction action,
  ) async {
    final show = _selectedShow;
    if (show == null) return;
    final showImdbId = show.effectiveImdbId ?? show.id;
    final key = '${episode.season}-${episode.number}';
    bool success = false;
    String actionLabel = '';

    switch (action) {
      case TraktEpisodeMenuAction.markWatched:
        actionLabel = 'Marked as Watched';
        success = await _traktService.markEpisodeWatched(
          showImdbId,
          episode.season,
          episode.number,
        );
        if (success && mounted) {
          setState(() => _episodeWatchProgress[key] = 100.0);
        }
      case TraktEpisodeMenuAction.markUnwatched:
        actionLabel = 'Marked as Unwatched';
        success = await _traktService.markEpisodeUnwatched(
          showImdbId,
          episode.season,
          episode.number,
        );
        if (success && mounted) {
          setState(() => _episodeWatchProgress.remove(key));
        }
      case TraktEpisodeMenuAction.rate:
        if (!mounted) return;
        final rating = await showTraktRatingDialog(context);
        if (rating == null) return;
        actionLabel = 'Rated $rating/10';
        success = await _traktService.rateEpisode(
          showImdbId,
          episode.season,
          episode.number,
          rating,
        );
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(success ? actionLabel : 'Failed: $actionLabel'),
        backgroundColor: success
            ? const Color(0xFF34D399)
            : const Color(0xFFEF4444),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// Handle the episode long-press menu against Simkl — mirrors
  /// [_onEpisodeMenuAction], including the immediate local tick/bar update on
  /// a successful watched-state change (a later refresh re-merges the truth
  /// from all three sources).
  Future<void> _onEpisodeSimklMenuAction(
    TraktEpisode episode,
    SimklEpisodeMenuAction action,
  ) async {
    final show = _selectedShow;
    if (show == null) return;
    final showImdbId = show.effectiveImdbId ?? show.id;
    final key = '${episode.season}-${episode.number}';
    bool success = false;
    String actionLabel = '';

    switch (action) {
      case SimklEpisodeMenuAction.markWatched:
        actionLabel = 'Marked as Watched on Simkl';
        success = await _simklService.markEpisodeWatched(
          showImdbId,
          episode.season,
          episode.number,
        );
        if (success) {
          // Finishing this episode also clears its paused session, so the show
          // stops lingering in Continue Watching at this episode (and can
          // surface as "up next" for the following one). Best-effort.
          await _simklService.deletePlaybackForEpisode(
            showImdbId,
            episode.season,
            episode.number,
          );
          if (mounted) {
            setState(() => _episodeWatchProgress[key] = 100.0);
          }
        }
      case SimklEpisodeMenuAction.markUnwatched:
        actionLabel = 'Marked as Unwatched on Simkl';
        success = await _simklService.markEpisodeUnwatched(
          showImdbId,
          episode.season,
          episode.number,
        );
        if (success && mounted) {
          setState(() => _episodeWatchProgress.remove(key));
        }
      case SimklEpisodeMenuAction.rate:
        if (!mounted) return;
        final rating = await showSimklRatingDialog(context);
        if (rating == null) return;
        actionLabel = 'Rated $rating/10 on Simkl';
        success = await _simklService.rateEpisode(
          showImdbId,
          episode.season,
          episode.number,
          rating,
        );
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(success ? actionLabel : 'Failed: $actionLabel'),
        backgroundColor: success
            ? const Color(0xFF34D399)
            : const Color(0xFFEF4444),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _onEpisodeMdblistMenuAction(
    TraktEpisode episode,
    MdblistEpisodeMenuAction action,
  ) async {
    final show = _selectedShow;
    if (show == null) return;
    final imdb = show.effectiveImdbId ?? show.id;
    if (!imdb.startsWith('tt')) return;
    final ids = MdblistMediaIds(imdb: imdb);
    final key = '${episode.season}-${episode.number}';
    bool success;
    String label;
    switch (action) {
      case MdblistEpisodeMenuAction.markWatched:
        success = await _mdblistService.markWatched(
          ids,
          'episode',
          season: episode.season,
          episode: episode.number,
        );
        label = 'Marked watched on MDBList';
        if (success && mounted) {
          MdblistContinueWatchingService.instance.invalidate();
          setState(() {
            _episodeWatchProgress[key] = 100;
            _nextEpisode = _mergedUpNext(_episodeWatchProgress, _nextEpisode);
          });
          final next = _nextEpisode;
          if (next != null) widget.onNextEpisodeChanged?.call(next);
        }
      case MdblistEpisodeMenuAction.markUnwatched:
        success = await _mdblistService.markUnwatched(
          ids,
          'episode',
          season: episode.season,
          episode: episode.number,
        );
        label = 'Marked unwatched on MDBList';
        if (success && mounted) {
          MdblistContinueWatchingService.instance.invalidate();
          setState(() {
            _episodeWatchProgress.remove(key);
            _nextEpisode = _mergedUpNext(_episodeWatchProgress, _nextEpisode);
          });
          final next = _nextEpisode;
          if (next != null) widget.onNextEpisodeChanged?.call(next);
        }
      case MdblistEpisodeMenuAction.rate:
        if (!mounted) return;
        final rating = await showMdblistRatingDialog(context);
        if (rating == null) return;
        success = await _mdblistService.rateTitle(
          ids,
          'episode',
          rating,
          season: episode.season,
          episode: episode.number,
        );
        label = 'Rated $rating/10 on MDBList';
        if (success && mounted) {
          setState(() => _episodeMdblistRatings[key] = rating);
        }
      case MdblistEpisodeMenuAction.removeRating:
        success = await _mdblistService.removeRating(
          ids,
          'episode',
          season: episode.season,
          episode: episode.number,
        );
        label = 'Removed rating from MDBList';
        if (success && mounted) {
          setState(() => _episodeMdblistRatings.remove(key));
        }
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(success ? label : 'Failed: $label'),
        backgroundColor: success
            ? const Color(0xFF34D399)
            : const Color(0xFFEF4444),
      ),
    );
  }

  // ── Episode drill-down ──────────────────────────────────────────────────

  /// Fallback: dispatch series directly to torrent search (bypasses episode mode).
  void _fallbackToDirectSearch(StremioMeta show) {
    if (!mounted) return;
    widget.onBeforeTerminalDispatch?.call();
    final selection = AdvancedSearchSelection(
      imdbId: show.effectiveImdbId ?? show.id,
      isSeries: true,
      title: show.name,
      year: show.year,
      contentType: show.type,
      posterUrl: show.poster,
    );
    widget.onItemSelected?.call(selection);
  }

  /// Build the season list for [show], preferring the addon's meta endpoint
  /// (real Stremio/catalog addons) and falling back to Trakt's public seasons
  /// API. Discover→Trakt items carry a stub addon with no `baseUrl`, so their
  /// addon meta fetch returns nothing — Trakt is the only source that has their
  /// episodes. Returns an empty list only if neither source yields episodes.
  Future<List<TraktSeason>> _fetchSeasons(StremioMeta show) async {
    // 0) Direct-source mode: the loader is the only season source — a failure
    //    surfaces the retry panel rather than falling through to fetchers
    //    that cannot know this show.
    final directLoader = widget.seasonsLoader;
    if (directLoader != null) {
      try {
        return await directLoader();
      } catch (e) {
        debugPrint('EpisodesPanel: direct seasons fetch failed: $e');
        return [];
      }
    }

    // 1) Addon meta endpoint — skip when the addon is a stub (no base URL),
    //    which is the case for Trakt-sourced items.
    if (widget.addon.baseUrl.isNotEmpty ||
        widget.addon.manifestUrl.isNotEmpty) {
      try {
        final videos = await _stremioService.fetchSeriesMeta(
          widget.addon,
          show.id,
        );
        final seasons = _groupVideosIntoSeasons(videos);
        if (seasons.isNotEmpty) return seasons;
      } catch (e) {
        debugPrint('EpisodesPanel: addon meta fetch failed: $e');
      }
    }

    // 2) Trakt public seasons API (no auth required; keyed off the IMDb id).
    final traktId = show.effectiveImdbId ?? show.id;
    if (traktId.isNotEmpty) {
      try {
        final raw = await _traktService.fetchShowSeasons(traktId);
        // Dedupe by season number: a malformed response can yield >1 season
        // that both default to number 0, which would give the season dropdown
        // two items with the same value and trip its assertion. seen.add()
        // returns false for a number already present, dropping the duplicate.
        final seen = <int>{};
        final seasons =
            raw
                .map((s) => TraktSeason.fromJson(s))
                // Keep Specials (season 0); drop negatives and duplicate numbers.
                .where(
                  (s) =>
                      s.number >= 0 &&
                      s.episodes.isNotEmpty &&
                      seen.add(s.number),
                )
                .toList()
              ..sort(seasonsSpecialsLast);
        if (seasons.isNotEmpty) return seasons;
      } catch (e) {
        debugPrint('EpisodesPanel: Trakt seasons fetch failed: $e');
      }
    }

    return [];
  }

  /// Group raw Stremio addon meta `videos` into seasons, sorted by season then
  /// episode with Specials (season 0) last. Returns an empty list when there is
  /// nothing usable (null/empty input).
  List<TraktSeason> _groupVideosIntoSeasons(
    List<Map<String, dynamic>>? videos,
  ) {
    if (videos == null || videos.isEmpty) return [];

    final seasonMap = <int, List<TraktEpisode>>{};
    for (final v in videos) {
      final seasonRaw = v['season'];
      final seasonNum = seasonRaw is int
          ? seasonRaw
          : (seasonRaw is num ? seasonRaw.toInt() : null);
      // Keep Specials (season 0); drop only invalid/negative season numbers.
      if (seasonNum == null || seasonNum < 0) continue;

      final epRaw = v['number'] ?? v['episode'];
      final epNum = epRaw is int
          ? epRaw
          : (epRaw is num ? epRaw.toInt() : null);
      if (epNum == null) continue;

      final title = (v['title'] as String?) ?? (v['name'] as String?) ?? '';
      final overview = v['overview'] as String?;
      final released = v['released'] as String?;
      final thumbnail = _downsizeMetahubThumb(v['thumbnail'] as String?);
      final ratingRaw = v['imdbRating'] ?? v['rating'];
      final rating = ratingRaw is num
          ? ratingRaw.toDouble()
          : (ratingRaw is String ? double.tryParse(ratingRaw) : null);

      final episode = TraktEpisode(
        season: seasonNum,
        number: epNum,
        title: title,
        overview: overview,
        firstAired: released,
        thumbnailUrl: thumbnail,
        rating: rating,
      );

      seasonMap.putIfAbsent(seasonNum, () => []);
      seasonMap[seasonNum]!.add(episode);
    }

    if (seasonMap.isEmpty) return [];

    return seasonMap.entries.map((e) {
      final episodes = e.value..sort((a, b) => a.number.compareTo(b.number));
      return TraktSeason(
        number: e.key,
        episodeCount: episodes.length,
        episodes: episodes,
      );
    }).toList()..sort(seasonsSpecialsLast);
  }

  /// Cinemeta episode stills come as episodes.metahub.space/…/w780.jpg — a 301
  /// to the full-width TMDB image (~50 KB) for a 124-logical-px row thumb. The
  /// size token maps straight to TMDB sizes, so ask for w300 (~11 KB) instead;
  /// on TV-grade WiFi that's the difference between a snap and a trickle.
  static String? _downsizeMetahubThumb(String? url) {
    if (url == null || !url.contains('episodes.metahub.space')) return url;
    return url.replaceFirst(RegExp(r'/w\d+\.jpg$'), '/w300.jpg');
  }

  void _enterEpisodeMode(
    StremioMeta show, {
    int? initialSeason,
    int? initialEpisode,
  }) async {
    final generation = ++_episodeModeGeneration;

    setState(() {
      _selectedShow = show;
      _isLoadingEpisodes = true;
      _episodesUnavailable = false;
      _episodeSeasons = [];
      _episodeMdblistRatings = {};
      _selectedSeasonNumber = initialSeason ?? 1;
      _nextEpisode = null;
    });

    // Load watch progress (non-blocking; generation-guarded). The "up next"
    // marker is resolved inline below since it also drives where we land.
    // Direct-source mode awaits this future before landing — progress is its
    // only resume signal (there is no Trakt next-episode for these shows).
    final progressFuture = _loadEpisodeWatchProgress(show, generation);

    for (final node in _episodeFocusNodes) {
      node.dispose();
    }
    _episodeFocusNodes.clear();

    try {
      // The seasons fetch, Trakt's "next episode" lookup, and (on the Trakt
      // path) the TVMaze thumbnail map are independent — fire all of them now
      // instead of serializing three network round trips before content shows.
      // Each side future swallows its own errors so a failure can neither
      // bubble to the outer catch nor go unhandled if we bail on a stale
      // generation before awaiting it.
      final seasonsFuture = _fetchSeasons(show);

      // Trakt "next episode" — drives the up-next tile highlight and the
      // landing target. Instant/null without a Trakt account (no token → no
      // request). Direct-source shows have no Trakt identity — skip outright
      // rather than fire a request keyed on a sentinel id.
      final nextEpisodeFuture = _isDirectSource
          ? Future<({int season, int episode})?>.value(null)
          : _traktService
                .fetchNextEpisode(show.effectiveImdbId ?? show.id)
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
          widget.addon.baseUrl.isNotEmpty ||
          widget.addon.manifestUrl.isNotEmpty;
      final prefetchedThumbs = (addonHasMeta || _isDirectSource)
          ? null
          : _fetchTvmazeThumbMap(show.effectiveImdbId);

      final seasons = await seasonsFuture;
      if (!mounted || generation != _episodeModeGeneration) return;

      if (seasons.isEmpty) {
        setState(() {
          _isLoadingEpisodes = false;
          _episodesUnavailable = true;
        });
        return;
      }

      final imdbId = show.effectiveImdbId;
      if (!_isDirectSource && imdbId != null && imdbId.isNotEmpty) {
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
      if (!mounted || generation != _episodeModeGeneration) return;
      // Keep the raw value for the up-next highlight (it self-limits to a
      // displayed tile). Only adopt it as the landing target when its season is
      // actually present, so we never scroll to the wrong episode in season 1.
      _nextEpisode = nextEpisode;
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
      if (_isDirectSource &&
          effectiveSeason == null &&
          effectiveEpisode == null) {
        await progressFuture;
        if (!mounted || generation != _episodeModeGeneration) return;
        final target = _directLandingTarget(seasons);
        if (target != null) {
          effectiveSeason = target.season;
          effectiveEpisode = target.episode;
        }
      }

      // 3. Last-played (local) fallback — by IMDb id, then by title.
      if (!_isDirectSource &&
          effectiveSeason == null &&
          effectiveEpisode == null) {
        final imdbId = show.effectiveImdbId;
        if (imdbId != null) {
          final lastPlayed = await StorageService.getLastPlayedEpisodeByImdbId(
            imdbId,
          );
          if (!mounted || generation != _episodeModeGeneration) return;
          if (lastPlayed != null) {
            effectiveSeason = lastPlayed['season'] as int?;
            effectiveEpisode = lastPlayed['episode'] as int?;
          }
        }
        if (effectiveSeason == null && effectiveEpisode == null) {
          final byTitle = await StorageService.getLastPlayedEpisode(
            seriesTitle: show.name,
          );
          if (!mounted || generation != _episodeModeGeneration) return;
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
        _episodeFocusNodes.add(FocusNode(debugLabel: 'catalog-ep-$i'));
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

      setState(() {
        _episodeSeasons = seasons;
        _nextEpisode = _mergedUpNext(_episodeWatchProgress, _nextEpisode);
        _selectedSeasonNumber = targetSeason.number;
        _isLoadingEpisodes = false;
        _landing = landingEpisode ?? targetSeason.episodes.firstOrNull;
        _focusIntent = EpisodeFocusIntent.landing;
        _viewGeneration++;
      });
      final mergedNext = _nextEpisode;
      if (mergedNext != null) {
        widget.onNextEpisodeChanged?.call(mergedNext);
      }

      // Fill in per-episode thumbnails from TVMaze for any episode that didn't
      // come with one (Trakt-sourced items have none; addon items keep theirs).
      // Non-blocking — and on the Trakt path the map was prefetched alongside
      // the seasons, so stills usually land within a frame of first paint.
      // Both enrichments are IMDb-keyed, so direct-source shows skip them.
      if (!_isDirectSource) {
        _enrichEpisodeThumbnails(
          show,
          seasons,
          generation,
          prefetched: prefetchedThumbs,
        );

        // Backfill per-episode ratings from Trakt when the addon didn't supply
        // real ones (Cinemeta sends rating:0). Non-blocking — ratings pop in.
        _enrichEpisodeRatings(show, seasons, generation);
      }

      // Scroll to (and focus) the target episode once its tile is built.
      // Robust against variable EpisodeTile height + lazy ListView building
      // (the old fixed focusIndex*128 estimate is wrong for the new tile).
      // A custom arrangement owns its own scrollable and FocusNodes, so the
      // engine's reveal would target widgets that do not exist there. The
      // layout reveals `view.landing` itself, driven by `focusIntent`.
      if (!_custom) {
        final targetEpIndex = effectiveEpisode != null
            ? targetSeason.episodes.indexWhere(
                (e) => e.number == effectiveEpisode,
              )
            : -1;
        _scrollFocusEpisode(
          targetEpIndex < 0 ? 0 : targetEpIndex,
          targetSeason.episodes.length,
          generation,
        );
      }
    } catch (e) {
      if (!mounted || generation != _episodeModeGeneration) return;
      debugPrint('EpisodesPanel: Episode fetch failed: $e');
      setState(() {
        _isLoadingEpisodes = false;
        _episodesUnavailable = true;
      });
    }
  }

  /// Direct-source landing: the last episode (in season/episode order, with
  /// the same Specials-last rule the list renders in) that has any progress —
  /// advanced to the next episode when it's essentially finished (≥95%). Null
  /// when nothing has been started, leaving the default first-episode landing.
  ({int season, int episode})? _directLandingTarget(List<TraktSeason> seasons) {
    final flat = [for (final s in seasons) ...s.episodes];
    int lastStarted = -1;
    for (var i = 0; i < flat.length; i++) {
      final p =
          _episodeWatchProgress['${flat[i].season}-${flat[i].number}'] ?? 0;
      if (p > 0) lastStarted = i;
    }
    if (lastStarted < 0) return null;
    final p =
        _episodeWatchProgress['${flat[lastStarted].season}-${flat[lastStarted].number}'] ??
        0;
    final target = (p >= 95 && lastStarted + 1 < flat.length)
        ? flat[lastStarted + 1]
        : flat[lastStarted];
    return (season: target.season, episode: target.number);
  }

  /// Backfill per-episode ratings from Trakt's public seasons API, keyed off
  /// the show's IMDb id. Runs only when NO episode already has a real rating —
  /// i.e. an addon like Cinemeta returned `rating: 0` for everything. This is
  /// exactly the rating source the Trakt fallback path uses, applied on top of
  /// the addon's richer metadata (thumbnails, overviews, air dates). Best-effort
  /// and non-blocking: any failure just leaves ratings unshown.
  Future<void> _enrichEpisodeRatings(
    StremioMeta show,
    List<TraktSeason> seasons,
    int generation,
  ) async {
    // Nothing to do if the episodes already carry real ratings.
    final hasRealRating = seasons.any(
      (s) => s.episodes.any((e) => (e.rating ?? 0) > 0),
    );
    if (hasRealRating) return;

    final imdbId = show.effectiveImdbId ?? show.id;
    if (imdbId.isEmpty) return;

    try {
      final raw = await _traktService.fetchShowSeasons(imdbId);
      if (!mounted || generation != _episodeModeGeneration) return;

      // Build lookup: "S-E" → rating (only real, >0 ratings).
      final ratingMap = <String, double>{};
      for (final s in raw.map((s) => TraktSeason.fromJson(s))) {
        for (final e in s.episodes) {
          final r = e.rating;
          if (r != null && r > 0) ratingMap['${e.season}-${e.number}'] = r;
        }
      }
      if (ratingMap.isEmpty) return;

      var changed = false;
      for (final season in seasons) {
        for (final episode in season.episodes) {
          if ((episode.rating ?? 0) > 0) continue;
          final r = ratingMap['${episode.season}-${episode.number}'];
          if (r != null) {
            episode.rating = r;
            changed = true;
          }
        }
      }

      if (changed && mounted && generation == _episodeModeGeneration) {
        setState(() {});
      }
    } catch (e) {
      debugPrint('EpisodesPanel: Trakt rating enrichment failed: $e');
    }
  }

  /// Fetch the TVMaze `"S-E"` → still-URL map for [imdbId]. Never throws —
  /// resolves to null when TVMaze doesn't know the show or the fetch fails,
  /// so it's safe to fire-and-forget before its consumer exists.
  Future<Map<String, String>?> _fetchTvmazeThumbMap(String? imdbId) async {
    if (imdbId == null) return null;
    try {
      final showData = await TVMazeService.lookupByImdbId(imdbId);
      final tvmazeId = showData?['id'] as int?;
      if (tvmazeId == null) return null;

      final tvmazeEpisodes = await TVMazeService.getEpisodes(tvmazeId);
      if (tvmazeEpisodes.isEmpty) return null;

      final imageMap = <String, String>{};
      for (final ep in tvmazeEpisodes) {
        final s = ep['season'] as int?;
        final e = ep['number'] as int?;
        final image = ep['image'] as Map<String, dynamic>?;
        final url =
            image?['medium'] as String? ?? image?['original'] as String?;
        if (s != null && e != null && url != null) {
          imageMap['$s-$e'] = url;
        }
      }
      return imageMap.isEmpty ? null : imageMap;
    } catch (e) {
      debugPrint('EpisodesPanel: TVMaze thumbnail fetch failed: $e');
      return null;
    }
  }

  /// Fill in per-episode thumbnails from TVMaze, keyed off the show's IMDb id.
  ///
  /// Only episodes that arrived without a thumbnail are touched, so addon
  /// meta-provided stills are preserved and Trakt-sourced episodes (which have
  /// none) get filled. Best-effort: any failure leaves the show-poster
  /// fallback in place. [prefetched] is the map fired alongside the seasons
  /// fetch on the Trakt path; when absent (addon path that still came up
  /// short) the fetch happens here.
  Future<void> _enrichEpisodeThumbnails(
    StremioMeta show,
    List<TraktSeason> seasons,
    int generation, {
    Future<Map<String, String>?>? prefetched,
  }) async {
    // Nothing to do if every episode already has a thumbnail (addon path).
    final needsThumbnails = seasons.any(
      (s) => s.episodes.any(
        (e) => e.thumbnailUrl == null || e.thumbnailUrl!.isEmpty,
      ),
    );
    if (!needsThumbnails) return;

    final imageMap =
        await (prefetched ?? _fetchTvmazeThumbMap(show.effectiveImdbId));
    if (imageMap == null) return;
    if (!mounted || generation != _episodeModeGeneration) return;

    var changed = false;
    for (final season in seasons) {
      for (final episode in season.episodes) {
        if (episode.thumbnailUrl != null && episode.thumbnailUrl!.isNotEmpty) {
          continue;
        }
        final url = imageMap['${episode.season}-${episode.number}'];
        if (url != null) {
          episode.thumbnailUrl = url;
          changed = true;
        }
      }
    }

    if (changed) {
      setState(() {});
    }
  }

  /// Robustly brings episode [epIndex] into view.
  ///
  /// The episode list is a lazy ListView with variable-height tiles, so a
  /// single fixed/proportional jump is unreliable — an off-screen target
  /// tile isn't built, leaving its FocusNode contextless. This re-reads
  /// scroll metrics each frame and converges (the builder's maxScrollExtent
  /// grows as more rows lay out). Once the tile exists: on TV focus it (the
  /// tile self-centers via EpisodeTile.onFocusChange and shows the focus
  /// border for the remote); on mobile/desktop just scroll it into view
  /// without focusing — an auto-applied golden focus border there looks out
  /// of place. Bounded so it can never spin.
  void _scrollFocusEpisode(int epIndex, int episodeCount, int generation) {
    const int maxAttempts = 16;
    void attempt(int n) {
      if (!mounted || generation != _episodeModeGeneration) return;
      if (epIndex < 0 || epIndex >= _episodeFocusNodes.length) return;
      final node = _episodeFocusNodes[epIndex];
      // Once a tile has been built and scrolled back out, the node keeps a
      // stale context; treating that as "present" would stop converging and
      // focus/scroll a defunct element.
      if (detailNodeMounted(node)) {
        if (widget.isTelevision) {
          node.requestFocus();
        } else {
          Scrollable.ensureVisible(
            node.context!,
            alignment: 0.5,
            alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
          );
        }
        return;
      }
      if (n >= maxAttempts || !_episodeScrollController.hasClients) {
        if (widget.isTelevision) node.requestFocus(); // best effort, then stop
        return;
      }
      final pos = _episodeScrollController.position;
      final ratio = episodeCount > 1 ? epIndex / (episodeCount - 1) : 0.0;
      final target = (pos.maxScrollExtent * ratio).clamp(
        0.0,
        pos.maxScrollExtent,
      );
      if ((target - pos.pixels).abs() > 1.0) {
        _episodeScrollController.jumpTo(target);
      }
      WidgetsBinding.instance.addPostFrameCallback((_) => attempt(n + 1));
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => attempt(0));
  }

  void _onSeasonChanged(int? seasonNumber) {
    if (seasonNumber == null || seasonNumber == _selectedSeasonNumber) return;

    for (final node in _episodeFocusNodes) {
      node.dispose();
    }
    _episodeFocusNodes.clear();

    final season = _episodeSeasons.firstWhere(
      (s) => s.number == seasonNumber,
      orElse: () => _episodeSeasons.first,
    );
    for (int i = 0; i < season.episodes.length; i++) {
      _episodeFocusNodes.add(FocusNode(debugLabel: 'catalog-ep-$i'));
    }

    if (!_custom && _episodeScrollController.hasClients) {
      _episodeScrollController.jumpTo(0);
    }

    setState(() {
      _selectedSeasonNumber = seasonNumber;
      _landing = season.episodes.firstOrNull;
      // The user is on the stepper — keep them there, as Classic does by
      // re-requesting the season dropdown.
      _focusIntent = EpisodeFocusIntent.seasonControl;
      _viewGeneration++;
    });
  }

  void _onEpisodeTap(TraktEpisode episode) {
    // Direct-source mode: no sources flow exists — a tap plays outright, on
    // top of the page (no terminal dispatch/pop, like quick-play).
    if (widget.onPlayEpisode != null) {
      widget.onPlayEpisode!(episode);
      return;
    }
    final show = _selectedShow;
    if (show == null || widget.onItemSelected == null) return;

    final selection = AdvancedSearchSelection(
      imdbId: show.effectiveImdbId ?? show.id,
      isSeries: true,
      title: show.name,
      year: show.year,
      season: episode.season,
      episode: episode.number,
      contentType: show.type,
      posterUrl: show.poster,
      // For Trakt-sourced items, carry the Trakt scrobble flag + resume
      // position so playback syncs to Trakt like the old home view.
      traktSource: widget.isTraktSource,
      traktProgressPercent: widget.isTraktSource
          ? _episodeWatchProgress['${episode.season}-${episode.number}']
          : null,
      mdblistSource: widget.isMdblistSource,
      mdblistProgressPercent: widget.isMdblistSource
          ? _episodeWatchProgress['${episode.season}-${episode.number}']
          : null,
      // Lets the host send the user back to this episode list (not the
      // catalog grid) when they back out of the torrent results.
      fromCatalogEpisodeDrillDown: true,
    );
    widget.onBeforeTerminalDispatch?.call();
    widget.onItemSelected!(selection);
  }

  void _onEpisodeQuickPlay(TraktEpisode episode) {
    if (widget.onPlayEpisode != null) {
      widget.onPlayEpisode!(episode);
      return;
    }
    final show = _selectedShow;
    if (show == null) return;

    final selection = AdvancedSearchSelection(
      imdbId: show.effectiveImdbId ?? show.id,
      isSeries: true,
      title: show.name,
      year: show.year,
      season: episode.season,
      episode: episode.number,
      contentType: show.type,
      posterUrl: show.poster,
      traktSource: widget.isTraktSource,
      traktProgressPercent: widget.isTraktSource
          ? _episodeWatchProgress['${episode.season}-${episode.number}']
          : null,
      mdblistSource: widget.isMdblistSource,
      mdblistProgressPercent: widget.isMdblistSource
          ? _episodeWatchProgress['${episode.season}-${episode.number}']
          : null,
      fromCatalogEpisodeDrillDown: true,
    );

    widget.onBeforeTerminalDispatch?.call();
    if (widget.onQuickPlay != null) {
      widget.onQuickPlay!(selection);
    } else if (widget.onItemSelected != null) {
      widget.onItemSelected!(selection);
    }
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
              focusNode: _episodeBackButtonFocusNode,
              onFocusChange: (focused) => setState(() {}),
              onKeyEvent: (node, event) {
                if (event is! KeyDownEvent) return KeyEventResult.ignored;
                if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                  // Top of a standalone route — nothing above to focus
                  // (the host is covered). Swallow so focus stays put.
                  return KeyEventResult.handled;
                }
                if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
                  if (_episodesUnavailable) {
                    _episodeRetryFocusNode.requestFocus();
                  } else {
                    _episodeSeasonDropdownFocusNode.requestFocus();
                  }
                  return KeyEventResult.handled;
                }
                if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                  if (_episodesUnavailable) {
                    _episodeRetryFocusNode.requestFocus();
                  } else if (_episodeFocusNodes.isNotEmpty) {
                    _episodeFocusNodes.first.requestFocus();
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
                  color: _episodeBackButtonFocusNode.hasFocus
                      ? Colors.white.withValues(alpha: 0.16)
                      : Colors.white.withValues(alpha: 0.06),
                  border: Border.all(
                    color: _episodeBackButtonFocusNode.hasFocus
                        ? t.focus
                        : Colors.white.withValues(alpha: 0.14),
                    width: _episodeBackButtonFocusNode.hasFocus ? 2 : 1,
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
                _selectedShow?.name ?? '',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),

            // Season dropdown — Trakt-style with blue accent border
            if (_episodeSeasons.isNotEmpty) ...[
              const SizedBox(width: 8),
              _buildEpisodeSeasonDropdown(),
            ],

            // Select Source button
            if (_selectedShow != null && widget.onSelectSource != null) ...[
              const SizedBox(width: 8),
              Builder(
                builder: (context) {
                  final sourceCount =
                      widget.boundSourceCount?.call(_selectedShow!) ?? 0;
                  return _CatalogSelectSourceButton(
                    hasBoundSource: sourceCount > 0,
                    sourceCount: sourceCount,
                    // Await the picker so the bound-source count updates in
                    // place when it closes (no need to leave and re-enter).
                    onTap: () async {
                      await widget.onSelectSource!(_selectedShow!);
                      if (mounted) setState(() {});
                    },
                    onLeftFocus: _episodeSeasons.isNotEmpty
                        ? _episodeSeasonDropdownFocusNode
                        : _episodeBackButtonFocusNode,
                    onDownArrow: _episodeFocusNodes.isNotEmpty
                        ? () => _episodeFocusNodes.first.requestFocus()
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
      if (_episodeFocusNodes.isNotEmpty) {
        _episodeFocusNodes.first.requestFocus();
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _episodeBackButtonFocusNode.requestFocus();
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
    return ListenableBuilder(
      listenable: _episodeSeasonDropdownFocusNode,
      builder: (context, _) {
        final hasFocus = _episodeSeasonDropdownFocusNode.hasFocus;
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
              color: hasFocus ? t.focus : Colors.white.withValues(alpha: 0.10),
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
              focusNode: _episodeSeasonDropdownFocusNode,
              focusColor: Colors.transparent,
              value: _selectedSeasonNumber,
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
              items: _episodeSeasons.map((s) {
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
              onChanged: _onSeasonChanged,
            ),
          ),
        );
      },
    );
  }

  /// Inline "couldn't load episodes" panel with Retry (recovers a transient
  /// failure without leaving the drill-down) and an explicit "Search for
  /// sources" action (the old auto-fallback, now opt-in).
  Widget _buildEpisodesUnavailable() {
    final show = _selectedShow ?? widget.show;
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
                  focusNode: _episodeRetryFocusNode,
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
                  onPressed: () => _enterEpisodeMode(
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
                    onPressed: () => _fallbackToDirectSearch(show),
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
    if (_isLoadingEpisodes) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_episodesUnavailable || _episodeSeasons.isEmpty) {
      return _buildEpisodesUnavailable();
    }

    final currentSeason = _episodeSeasons.firstWhere(
      (s) => s.number == _selectedSeasonNumber,
      orElse: () => _episodeSeasons.first,
    );

    final w = MediaQuery.of(context).size.width;
    final hPad = w >= 900 ? 40.0 : 16.0;

    return TvFocusScrollWrapper(
      child: ListView.builder(
        controller: _episodeScrollController,
        padding: EdgeInsets.fromLTRB(hPad, 10, hPad, 28),
        itemCount: currentSeason.episodes.length,
        itemBuilder: (context, index) {
          final episode = currentSeason.episodes[index];
          return Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: EpisodeTile(
              episode: episode,
              showImageUrl: _selectedShow?.poster,
              isTelevision: widget.isTelevision,
              showQuickPlay: widget.showQuickPlay,
              focusNode: index < _episodeFocusNodes.length
                  ? _episodeFocusNodes[index]
                  : null,
              watchProgress:
                  _episodeWatchProgress['${episode.season}-${episode.number}'],
              isNext:
                  _nextEpisode != null &&
                  _nextEpisode!.season == episode.season &&
                  _nextEpisode!.episode == episode.number,
              onPlay: () => _onEpisodeQuickPlay(episode),
              onSources: () => _onEpisodeTap(episode),
              onMenuAction: _isTraktAuthenticated
                  ? (action) => _onEpisodeMenuAction(episode, action)
                  : null,
              onTrackerOptions: _isSimklAuthenticated || _isMdblistAuthenticated
                  ? () => _showEpisodeOptions(episode)
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
          if (!_isLoadingEpisodes &&
              !_episodesUnavailable &&
              _episodeSeasons.isNotEmpty)
            _buildCompactSeasonHeader(),
          Expanded(child: _buildCompactContent()),
        ],
      );
    }
    return Column(
      children: [
        if (widget.showChrome)
          _buildEpisodeFiltersBar()
        else if (_episodeSeasons.length > 1)
          _buildSlimSeasonRow(),
        Expanded(child: _buildEpisodeContent()),
      ],
    );
  }

  /// Snapshot handed to a custom arrangement. Cheap — it closes over state
  /// rather than copying it, and is rebuilt with the panel.
  EpisodesPanelView _buildView() {
    final season = _episodeSeasons
        .where((s) => s.number == _selectedSeasonNumber)
        .firstOrNull;
    final episodes =
        season?.episodes ?? _episodeSeasons.firstOrNull?.episodes ?? const [];
    final show = _selectedShow ?? widget.show;
    return EpisodesPanelView(
      seasons: _episodeSeasons,
      selectedSeasonNumber: _selectedSeasonNumber,
      episodes: episodes,
      loading: _isLoadingEpisodes,
      unavailable: _episodesUnavailable,
      showImageUrl: show.poster,
      generation: _viewGeneration,
      landing: _landing,
      focusIntent: _focusIntent,
      progressOf: (e) => _episodeWatchProgress['${e.season}-${e.number}'],
      isNext: (e) =>
          _nextEpisode != null &&
          _nextEpisode!.season == e.season &&
          _nextEpisode!.episode == e.number,
      play: _onEpisodeQuickPlay,
      options: _showEpisodeOptions,
      stepSeason: _stepSeason,
      selectSeason: (n) => _onSeasonChanged(n),
      onLeftEdge: widget.onFocusLeftEdge,
      onRetry: () => _enterEpisodeMode(
        show,
        initialSeason: widget.initialSeason,
        initialEpisode: widget.initialEpisode,
      ),
      // Mirrors the classic failure UI: no torrent-search fallback exists for
      // direct-source shows, so the offer is withheld rather than dead.
      onSearchForSources: widget.onItemSelected != null
          ? () => _fallbackToDirectSearch(show)
          : null,
    );
  }

  /// Layouts call this after acting on [EpisodeFocusIntent], so a rebuild that
  /// isn't a data change doesn't yank the cursor a second time.
  void consumeFocusIntent() {
    if (_focusIntent == EpisodeFocusIntent.none) return;
    _focusIntent = EpisodeFocusIntent.none;
  }

  // ── Compact (Stremio) rendering ──────────────────────────────────────────

  int get _currentSeasonIndex =>
      _episodeSeasons.indexWhere((s) => s.number == _selectedSeasonNumber);

  void _stepSeason(int delta) {
    if (_episodeSeasons.isEmpty) return;
    final i = _currentSeasonIndex;
    final ni = (i < 0 ? 0 : i) + delta;
    if (ni < 0 || ni >= _episodeSeasons.length) return;
    _onSeasonChanged(_episodeSeasons[ni].number);
    // Stepping into the first/last season disables the chevron we're on, which
    // would drop primary focus into the void. Park focus on the always-present
    // season dropdown so the remote stays live.
    // Classic parks focus on its always-present dropdown; a custom arrangement
    // has no such node, and its own season control keeps focus already.
    if (_custom) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _episodeSeasonDropdownFocusNode.requestFocus();
    });
  }

  /// Pinned "‹ Prev · Season ▾ · Next ›" header — always visible above the list
  /// (this is what "the season dropdown isn't reachable" was about).
  Widget _buildCompactSeasonHeader() {
    final i = _currentSeasonIndex;
    final many = _episodeSeasons.length > 1;
    final current = (i >= 0) ? _episodeSeasons[i] : _episodeSeasons.first;
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
            _SeasonStepButton(
              icon: Icons.chevron_left_rounded,
              enabled: i > 0,
              onTap: () => _stepSeason(-1),
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
            _SeasonStepButton(
              icon: Icons.chevron_right_rounded,
              enabled: i < _episodeSeasons.length - 1,
              onTap: () => _stepSeason(1),
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
    if (_isLoadingEpisodes) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_episodesUnavailable || _episodeSeasons.isEmpty) {
      return _buildEpisodesUnavailable();
    }
    final currentSeason = _episodeSeasons.firstWhere(
      (s) => s.number == _selectedSeasonNumber,
      orElse: () => _episodeSeasons.first,
    );
    // The row centres itself on focus (`_CompactEpisodeRow.onFocusChange`), so
    // no TvFocusScrollWrapper is needed here (it would resolve no ancestor
    // scrollable and no-op anyway).
    return ListView.builder(
      controller: _episodeScrollController,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      itemCount: currentSeason.episodes.length,
      itemBuilder: (context, index) {
        final episode = currentSeason.episodes[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _CompactEpisodeRow(
            episode: episode,
            showImageUrl: _selectedShow?.poster,
            isTelevision: widget.isTelevision,
            watchProgress:
                _episodeWatchProgress['${episode.season}-${episode.number}'],
            isNext:
                _nextEpisode != null &&
                _nextEpisode!.season == episode.season &&
                _nextEpisode!.episode == episode.number,
            focusNode: index < _episodeFocusNodes.length
                ? _episodeFocusNodes[index]
                : null,
            onPlay: () => _onEpisodeQuickPlay(episode),
            onOptions: () => _showEpisodeOptions(episode),
            onLeft: widget.onFocusLeftEdge,
          ),
        );
      },
    );
  }

  /// Per-episode options menu (opened with Right / the ⋮ button): Play, Sources,
  /// and — when a Trakt account is connected — Mark Watched/Unwatched + Rate.
  void _showEpisodeOptions(TraktEpisode episode) {
    final key = '${episode.season}-${episode.number}';
    final watched = (_episodeWatchProgress[key] ?? 0) >= 100;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppThemeScope.of(context).sheetSurface,
      showDragHandle: true,
      // With both Trakt and Simkl connected the menu is 7 tiles — taller than
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
            onTap: () {
              Navigator.of(sheetCtx).pop();
              onTap();
            },
          );
        }

        final tiles = <Widget>[
          // Autofocus Play on TV so the sheet opens with a live target.
          tile(
            Icons.play_arrow_rounded,
            'Play',
            () => _onEpisodeQuickPlay(episode),
            autofocus: widget.isTelevision,
          ),
          // Direct-source episodes ARE the source — no torrent list to open.
          if (widget.onPlayEpisode == null)
            tile(Icons.layers_rounded, 'Sources', () => _onEpisodeTap(episode)),
          if (_isTraktAuthenticated) ...[
            if (!watched)
              tile(
                Icons.check_circle_rounded,
                'Mark as Watched',
                () => _onEpisodeMenuAction(
                  episode,
                  TraktEpisodeMenuAction.markWatched,
                ),
              ),
            if (watched)
              tile(
                Icons.visibility_off_rounded,
                'Mark as Unwatched',
                () => _onEpisodeMenuAction(
                  episode,
                  TraktEpisodeMenuAction.markUnwatched,
                ),
              ),
            tile(
              Icons.star_rounded,
              'Rate on Trakt',
              () => _onEpisodeMenuAction(episode, TraktEpisodeMenuAction.rate),
            ),
          ],
          // Simkl's own rows — separate from Trakt's above, not merged.
          // No live per-episode Simkl watched state is tracked, so both
          // Mark Watched and Mark Unwatched are always offered.
          if (_isSimklAuthenticated) ...[
            tile(
              Icons.check_circle_rounded,
              'Mark as Watched (Simkl)',
              () => _onEpisodeSimklMenuAction(
                episode,
                SimklEpisodeMenuAction.markWatched,
              ),
            ),
            tile(
              Icons.visibility_off_rounded,
              'Mark as Unwatched (Simkl)',
              () => _onEpisodeSimklMenuAction(
                episode,
                SimklEpisodeMenuAction.markUnwatched,
              ),
            ),
            tile(
              Icons.star_rounded,
              'Rate on Simkl',
              () => _onEpisodeSimklMenuAction(
                episode,
                SimklEpisodeMenuAction.rate,
              ),
            ),
          ],
          if (_isMdblistAuthenticated) ...[
            if (!watched)
              tile(
                Icons.check_circle_rounded,
                'Mark as Watched (MDBList)',
                () => _onEpisodeMdblistMenuAction(
                  episode,
                  MdblistEpisodeMenuAction.markWatched,
                ),
              ),
            if (watched)
              tile(
                Icons.visibility_off_rounded,
                'Mark as Unwatched (MDBList)',
                () => _onEpisodeMdblistMenuAction(
                  episode,
                  MdblistEpisodeMenuAction.markUnwatched,
                ),
              ),
            if (_episodeMdblistRatings[key] == null)
              tile(
                Icons.star_rounded,
                'Rate on MDBList',
                () => _onEpisodeMdblistMenuAction(
                  episode,
                  MdblistEpisodeMenuAction.rate,
                ),
              ),
            if (_episodeMdblistRatings[key] != null)
              tile(
                Icons.star_outline_rounded,
                'Remove MDBList rating (${_episodeMdblistRatings[key]}/10)',
                () => _onEpisodeMdblistMenuAction(
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

// ─── Select Source Button for catalog episode browser ────────────────────────

class _CatalogSelectSourceButton extends StatefulWidget {
  final bool hasBoundSource;
  final int sourceCount;
  final VoidCallback onTap;
  final FocusNode? onLeftFocus;
  final VoidCallback? onDownArrow;
  final VoidCallback? onUpArrow;

  const _CatalogSelectSourceButton({
    required this.hasBoundSource,
    this.sourceCount = 0,
    required this.onTap,
    this.onLeftFocus,
    this.onDownArrow,
    this.onUpArrow,
  });

  @override
  State<_CatalogSelectSourceButton> createState() =>
      _CatalogSelectSourceButtonState();
}

class _CatalogSelectSourceButtonState
    extends State<_CatalogSelectSourceButton> {
  final FocusNode _focusNode = FocusNode(
    debugLabel: 'catalog-select-source-btn',
  );
  bool _isFocused = false;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = DetailThemeScope.maybeOf(context);
    return Focus(
      focusNode: _focusNode,
      onFocusChange: (focused) => setState(() => _isFocused = focused),
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (isActivateKey(event.logicalKey)) {
          widget.onTap();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
          widget.onUpArrow?.call();
          return widget.onUpArrow != null
              ? KeyEventResult.handled
              : KeyEventResult.ignored;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowLeft &&
            widget.onLeftFocus != null) {
          widget.onLeftFocus!.requestFocus();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
          return KeyEventResult.handled; // rightmost button
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
          widget.onDownArrow?.call();
          return widget.onDownArrow != null
              ? KeyEventResult.handled
              : KeyEventResult.ignored;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: PlatformUtil.isTelevision
              ? Duration.zero
              : const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: widget.hasBoundSource
                ? t.fade(t.focus, 0.14)
                : Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _isFocused
                  ? t.focus
                  : widget.hasBoundSource
                  ? t.fade(t.focus, 0.45)
                  : Colors.white.withValues(alpha: 0.14),
              width: _isFocused ? 2 : 1,
            ),
            boxShadow: (_isFocused && !PlatformUtil.isTelevision)
                ? [BoxShadow(color: t.fade(t.focus, 0.32), blurRadius: 12)]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.hasBoundSource
                    ? Icons.link_rounded
                    : Icons.link_off_rounded,
                size: 16,
                color: widget.hasBoundSource
                    ? t.focus
                    : Colors.white.withValues(alpha: 0.85),
              ),
              const SizedBox(width: 6),
              Text(
                widget.hasBoundSource
                    ? (widget.sourceCount > 1
                          ? 'Sources (${widget.sourceCount})'
                          : 'Source')
                    : 'Select Source',
                style: TextStyle(
                  color: widget.hasBoundSource
                      ? t.focus
                      : Colors.white.withValues(alpha: 0.85),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Season stepper (compact header ‹ ›) ─────────────────────────────────────

class _SeasonStepButton extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  const _SeasonStepButton({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // IconButton (not a bare InkWell) so the disabled state at the first/last
    // season keeps its button semantics for screen readers; the state-resolved
    // style adds the gold DPAD focus ring the default overlay lacks.
    // Hoisted out of the resolver closure, which is not build-time code.
    final t = DetailThemeScope.maybeOf(context);
    return IconButton(
      visualDensity: VisualDensity.compact,
      style: ButtonStyle(
        side: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.focused)
              ? BorderSide(color: t.focus, width: 2)
              : null,
        ),
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.focused)
              ? Colors.white.withValues(alpha: 0.10)
              : null,
        ),
      ),
      icon: Icon(
        icon,
        color: enabled ? Colors.white : Colors.white.withValues(alpha: 0.22),
      ),
      onPressed: enabled ? onTap : null,
    );
  }
}

// ─── Compact Stremio-style episode row (merged series page) ───────────────────

class _CompactEpisodeRow extends StatefulWidget {
  final TraktEpisode episode;
  final String? showImageUrl;
  final bool isTelevision;
  final double? watchProgress; // 0..100
  final bool isNext;
  final FocusNode? focusNode;
  final VoidCallback onPlay;
  final VoidCallback onOptions;
  final VoidCallback? onLeft;

  const _CompactEpisodeRow({
    required this.episode,
    required this.showImageUrl,
    required this.isTelevision,
    required this.watchProgress,
    required this.isNext,
    required this.focusNode,
    required this.onPlay,
    required this.onOptions,
    this.onLeft,
  });

  @override
  State<_CompactEpisodeRow> createState() => _CompactEpisodeRowState();
}

class _CompactEpisodeRowState extends State<_CompactEpisodeRow> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final e = widget.episode;
    final progress = (widget.watchProgress ?? 0).clamp(0.0, 100.0);
    final watched = progress >= 100;
    final partial = progress > 5 && progress < 100;
    final thumbUrl = (e.thumbnailUrl?.isNotEmpty ?? false)
        ? e.thumbnailUrl
        : widget.showImageUrl;
    // The air date now has its own formatted meta line below the title, so the
    // description no longer falls back to the raw date string — it's overview
    // or nothing.
    final subtitle = (e.overview?.isNotEmpty ?? false) ? e.overview! : '';
    final airDate = e.formattedAirDate;
    // Some addons (e.g. Cinemeta) send `imdbRating: 0` for episodes that have no
    // rating rather than omitting it — treat 0/negative as "no rating" so we
    // don't render a meaningless ★ 0.0 on every episode.
    final rating = (e.rating != null && e.rating! > 0) ? e.rating : null;
    final hasMeta = (airDate != null && airDate.isNotEmpty) || rating != null;
    final t = DetailThemeScope.maybeOf(context);

    final row = Focus(
      focusNode: widget.focusNode,
      onFocusChange: (f) {
        if (mounted) setState(() => _focused = f);
        if (f && widget.isTelevision && context.mounted) {
          Scrollable.ensureVisible(
            context,
            alignment: 0.5,
            alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
          );
        }
      },
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final k = event.logicalKey;
        if (isActivateKey(k) || k == LogicalKeyboardKey.space) {
          widget.onPlay();
          return KeyEventResult.handled;
        }
        // Episodes are the right-most pane, so Right is free — use it for the
        // per-episode options menu.
        if (k == LogicalKeyboardKey.arrowRight) {
          widget.onOptions();
          return KeyEventResult.handled;
        }
        // Left crosses to the host's info column — send it to a stable target
        // (the host's Play/source button) instead of a geometry-picked item.
        if (k == LogicalKeyboardKey.arrowLeft && widget.onLeft != null) {
          widget.onLeft!();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored; // Up/Down → directional focus
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onPlay,
          onLongPress: widget.onOptions,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            // Snap the focus ring on TV (house idiom) — held-DPAD scrolling
            // otherwise animates two rows' fills/borders on every step.
            duration: widget.isTelevision
                ? Duration.zero
                : const Duration(milliseconds: 140),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _focused
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.white.withValues(alpha: 0.02),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _focused
                    ? t.focus
                    : Colors.white.withValues(alpha: 0.06),
                width: _focused ? 2 : 1,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Thumbnail
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 124,
                    height: 70,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (thumbUrl != null && thumbUrl.isNotEmpty)
                          CachedNetworkImage(
                            imageUrl: thumbUrl,
                            fit: BoxFit.cover,
                            // Long-lived shared cache — the 200-object default
                            // evicts these within one TV browsing session,
                            // forcing a re-download on every visit.
                            cacheManager: DebrifyImageCache.manager,
                            // 124-logical-px thumb — the show-poster fallback
                            // is a full-size poster; never decode it full-res
                            // for a row thumbnail (×N rows on a 2 GB box).
                            memCacheWidth: 300,
                            fadeInDuration: HomeTheme.imageFadeIn(
                              widget.isTelevision,
                            ),
                            fadeOutDuration: HomeTheme.imageFadeOut(
                              widget.isTelevision,
                            ),
                            // Solid fill while loading — without it the tile
                            // is a transparent hole until the bytes land.
                            placeholder: (_, __) =>
                                Container(color: const Color(0xFF1A1622)),
                            errorWidget: (_, __, ___) =>
                                Container(color: const Color(0xFF1A1622)),
                          )
                        else
                          Container(color: const Color(0xFF1A1622)),
                        if (watched)
                          Container(
                            color: Colors.black.withValues(alpha: 0.45),
                            alignment: Alignment.center,
                            child: Icon(
                              Icons.check_circle_rounded,
                              color: t.focus,
                              size: 24,
                            ),
                          ),
                        if (widget.isNext && !watched)
                          Positioned(
                            top: 5,
                            left: 5,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: t.focus,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'UP NEXT',
                                style: TextStyle(
                                  color: Color(0xFF2A1E02),
                                  fontSize: 8,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.4,
                                ),
                              ),
                            ),
                          ),
                        if (partial)
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: Container(
                              height: 3,
                              color: Colors.black.withValues(alpha: 0.5),
                              child: FractionallySizedBox(
                                widthFactor: progress / 100,
                                alignment: Alignment.centerLeft,
                                child: Container(color: t.focus),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Title + subtitle
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        e.title.trim().isEmpty
                            ? 'Episode ${e.number}'
                            : '${e.number}. ${e.title}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          height: 1.2,
                        ),
                      ),
                      // IMDb rating + air date, mirroring the series-level meta
                      // bar in the left pane so each episode reads at a glance.
                      if (hasMeta) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            if (rating != null) ...[
                              const Icon(
                                Icons.star_rounded,
                                size: 12,
                                color: Color(0xFFFACC15),
                              ),
                              const SizedBox(width: 3),
                              Text(
                                rating.toStringAsFixed(1),
                                style: const TextStyle(
                                  color: Color(0xFFFACC15),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                            if (rating != null &&
                                airDate != null &&
                                airDate.isNotEmpty)
                              Text(
                                '  ·  ',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.4),
                                  fontSize: 11,
                                ),
                              ),
                            if (airDate != null && airDate.isNotEmpty)
                              Text(
                                airDate,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.55),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                          ],
                        ),
                      ],
                      if (subtitle.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Trailing: watch state + a PERSISTENT options affordance (so
                // even watched/in-progress rows still advertise ▶ = Options).
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (watched)
                      Icon(Icons.check_circle_rounded, color: t.focus, size: 18)
                    else if (partial)
                      Text(
                        '${progress.round()}%',
                        style: TextStyle(
                          color: t.focus,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    if (watched || partial) const SizedBox(width: 8),
                    if (widget.isTelevision)
                      // Brightens when the row is focused to hint "press ▶".
                      Icon(
                        Icons.more_vert_rounded,
                        size: 20,
                        color: Colors.white.withValues(
                          alpha: _focused ? 0.9 : 0.35,
                        ),
                      )
                    else
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: Icon(
                          Icons.more_vert_rounded,
                          color: Colors.white.withValues(alpha: 0.6),
                          size: 20,
                        ),
                        onPressed: widget.onOptions,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    // RepaintBoundary: a focus move repaints only the two rows whose ring
    // changed, not the whole episode column (thumbnails, scrims and all).
    return RepaintBoundary(child: row);
  }
}
