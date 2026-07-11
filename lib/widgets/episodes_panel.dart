import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/stremio_addon.dart';
import '../models/advanced_search_selection.dart';
import '../services/stremio_service.dart';
import '../services/trakt/trakt_episode_model.dart';
import '../services/trakt/trakt_service.dart';
import '../services/tvmaze_service.dart';
import '../services/storage_service.dart';
import '../utils/tv_keys.dart';
import '../screens/debrify_tv/widgets/tv_focus_scroll_wrapper.dart';
import 'episode_tile.dart';
import 'trakt/trakt_menu_helpers.dart';
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

  const EpisodesPanel({
    super.key,
    required this.show,
    required this.addon,
    this.initialSeason,
    this.initialEpisode,
    this.isTelevision = false,
    this.showQuickPlay = true,
    this.isTraktSource = false,
    this.onItemSelected,
    this.onQuickPlay,
    this.boundSourceCount,
    this.onSelectSource,
    this.onBack,
    this.onBeforeTerminalDispatch,
    this.showChrome = true,
    this.compact = false,
    this.onFocusLeftEdge,
  });

  @override
  State<EpisodesPanel> createState() => _EpisodesPanelState();
}

class _EpisodesPanelState extends State<EpisodesPanel> {
  final StremioService _stremioService = StremioService.instance;
  final TraktService _traktService = TraktService.instance;

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

  /// The next episode to watch for the current show (from Trakt), used only to
  /// highlight the corresponding tile. Landing still prefers the last-played
  /// episode; this is purely a visual "up next" marker.
  ({int season, int episode})? _nextEpisode;

  /// Whether a Trakt account is connected. This screen is reachable from
  /// Discover/catalog without Trakt, so the Trakt-only episode menu (mark
  /// watched/unwatched, rate) is only offered when this is true.
  bool _isTraktAuthenticated = false;

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
    _enterEpisodeMode(
      widget.show,
      initialSeason: widget.initialSeason,
      initialEpisode: widget.initialEpisode,
    );
  }

  @override
  void dispose() {
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
  Future<void> _loadEpisodeWatchProgress(StremioMeta show, int generation) async {
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

    if (mounted && generation == _episodeModeGeneration) {
      setState(() => _episodeWatchProgress = merged);
    }
  }

  /// Resolve whether a Trakt account is connected (gates the episode menu).
  Future<void> _resolveTraktAuth() async {
    final authed = await _traktService.isAuthenticated();
    if (mounted && authed != _isTraktAuthenticated) {
      setState(() => _isTraktAuthenticated = authed);
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
                .where((s) =>
                    s.number >= 0 && s.episodes.isNotEmpty && seen.add(s.number))
                .toList()
              ..sort(_seasonsSpecialsLast);
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
  List<TraktSeason> _groupVideosIntoSeasons(List<Map<String, dynamic>>? videos) {
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
      final thumbnail = v['thumbnail'] as String?;
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
    }).toList()..sort(_seasonsSpecialsLast);
  }

  /// Sort seasons ascending, but with Specials (season 0) at the very end —
  /// matching old home so a "Specials" entry sits after the real seasons.
  static int _seasonsSpecialsLast(TraktSeason a, TraktSeason b) {
    if (a.number == 0 && b.number != 0) return 1;
    if (a.number != 0 && b.number == 0) return -1;
    return a.number.compareTo(b.number);
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
      _selectedSeasonNumber = initialSeason ?? 1;
      _nextEpisode = null;
    });

    // Load watch progress (non-blocking; generation-guarded). The "up next"
    // marker is resolved inline below since it also drives where we land.
    _loadEpisodeWatchProgress(show, generation);

    for (final node in _episodeFocusNodes) {
      node.dispose();
    }
    _episodeFocusNodes.clear();

    try {
      final seasons = await _fetchSeasons(show);
      if (!mounted || generation != _episodeModeGeneration) return;

      if (seasons.isEmpty) {
        setState(() {
          _isLoadingEpisodes = false;
          _episodesUnavailable = true;
        });
        return;
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

      // 2. Trakt "next episode". Also drives the up-next tile highlight. This
      //    is instant/null without a Trakt account (no token → no request).
      //    Guarded so a Trakt failure can never bubble to the outer catch and
      //    drop us to torrent search — the episode list is already loaded.
      ({int season, int episode})? nextEpisode;
      try {
        nextEpisode = await _traktService.fetchNextEpisode(
          show.effectiveImdbId ?? show.id,
        );
      } catch (e) {
        debugPrint('EpisodesPanel: next-episode fetch failed: $e');
      }
      if (!mounted || generation != _episodeModeGeneration) return;
      // Keep the raw value for the up-next highlight (it self-limits to a
      // displayed tile). Only adopt it as the landing target when its season is
      // actually present, so we never scroll to the wrong episode in season 1.
      _nextEpisode = nextEpisode;
      if (effectiveSeason == null &&
          effectiveEpisode == null &&
          nextEpisode != null &&
          seasons.any((s) => s.number == nextEpisode!.season)) {
        effectiveSeason = nextEpisode.season;
        effectiveEpisode = nextEpisode.episode;
      }

      // 3. Last-played (local) fallback — by IMDb id, then by title.
      if (effectiveSeason == null && effectiveEpisode == null) {
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

      setState(() {
        _episodeSeasons = seasons;
        _selectedSeasonNumber = targetSeason.number;
        _isLoadingEpisodes = false;
      });

      // Fill in per-episode thumbnails from TVMaze for any episode that didn't
      // come with one (Trakt-sourced items have none; addon items keep theirs).
      // Non-blocking — tiles render immediately with the show-poster fallback.
      _enrichEpisodeThumbnails(show, seasons, generation);

      // Scroll to (and focus) the target episode once its tile is built.
      // Robust against variable EpisodeTile height + lazy ListView building
      // (the old fixed focusIndex*128 estimate is wrong for the new tile).
      final targetEpIndex = effectiveEpisode != null
          ? targetSeason.episodes.indexWhere((e) => e.number == effectiveEpisode)
          : -1;
      _scrollFocusEpisode(
        targetEpIndex < 0 ? 0 : targetEpIndex,
        targetSeason.episodes.length,
        generation,
      );
    } catch (e) {
      if (!mounted || generation != _episodeModeGeneration) return;
      debugPrint('EpisodesPanel: Episode fetch failed: $e');
      setState(() {
        _isLoadingEpisodes = false;
        _episodesUnavailable = true;
      });
    }
  }

  /// Fill in per-episode thumbnails from TVMaze, keyed off the show's IMDb id.
  ///
  /// Only episodes that arrived without a thumbnail are touched, so addon
  /// meta-provided stills are preserved and Trakt-sourced episodes (which have
  /// none) get filled. Best-effort: any failure leaves the show-poster
  /// fallback in place.
  Future<void> _enrichEpisodeThumbnails(
    StremioMeta show,
    List<TraktSeason> seasons,
    int generation,
  ) async {
    final imdbId = show.effectiveImdbId;
    if (imdbId == null) return;
    // Nothing to do if every episode already has a thumbnail (addon path).
    final needsThumbnails = seasons.any(
      (s) => s.episodes.any(
        (e) => e.thumbnailUrl == null || e.thumbnailUrl!.isEmpty,
      ),
    );
    if (!needsThumbnails) return;

    try {
      final showData = await TVMazeService.lookupByImdbId(imdbId);
      if (!mounted || generation != _episodeModeGeneration) return;
      final tvmazeId = showData?['id'] as int?;
      if (tvmazeId == null) return;

      final tvmazeEpisodes = await TVMazeService.getEpisodes(tvmazeId);
      if (!mounted || generation != _episodeModeGeneration) return;
      if (tvmazeEpisodes.isEmpty) return;

      // Build lookup: "S-E" → image URL.
      final imageMap = <String, String>{};
      for (final ep in tvmazeEpisodes) {
        final s = ep['season'] as int?;
        final e = ep['number'] as int?;
        final image = ep['image'] as Map<String, dynamic>?;
        final url = image?['medium'] as String? ?? image?['original'] as String?;
        if (s != null && e != null && url != null) {
          imageMap['$s-$e'] = url;
        }
      }
      if (imageMap.isEmpty) return;

      var changed = false;
      for (final season in seasons) {
        for (final episode in season.episodes) {
          if (episode.thumbnailUrl != null &&
              episode.thumbnailUrl!.isNotEmpty) {
            continue;
          }
          final url = imageMap['${episode.season}-${episode.number}'];
          if (url != null) {
            episode.thumbnailUrl = url;
            changed = true;
          }
        }
      }

      if (changed && mounted && generation == _episodeModeGeneration) {
        setState(() {});
      }
    } catch (e) {
      debugPrint('EpisodesPanel: TVMaze thumbnail enrichment failed: $e');
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
      if (node.context != null) {
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

    if (_episodeScrollController.hasClients) {
      _episodeScrollController.jumpTo(0);
    }

    setState(() => _selectedSeasonNumber = seasonNumber);
  }

  void _onEpisodeTap(TraktEpisode episode) {
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
      // Lets the host send the user back to this episode list (not the
      // catalog grid) when they back out of the torrent results.
      fromCatalogEpisodeDrillDown: true,
    );
    widget.onBeforeTerminalDispatch?.call();
    widget.onItemSelected!(selection);
  }

  void _onEpisodeQuickPlay(TraktEpisode episode) {
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
                        ? HomeTheme.focusGold
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
                  color: Colors.white,
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
    return ListenableBuilder(
      listenable: _episodeSeasonDropdownFocusNode,
      builder: (context, _) {
        final hasFocus = _episodeSeasonDropdownFocusNode.hasFocus;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: hasFocus ? 0.12 : 0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: hasFocus
                  ? HomeTheme.focusGold
                  : Colors.white.withValues(alpha: 0.10),
              width: hasFocus ? 2.0 : 1.0,
            ),
            boxShadow: hasFocus
                ? [
                    BoxShadow(
                      color: HomeTheme.focusGold.withValues(alpha: 0.32),
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
                    style: const TextStyle(color: Colors.white, fontSize: 13),
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
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
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
                          ? const BorderSide(
                              color: HomeTheme.focusGold, width: 2)
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
                OutlinedButton.icon(
                  style: ButtonStyle(
                    side: WidgetStateProperty.resolveWith(
                      (states) => states.contains(WidgetState.focused)
                          ? const BorderSide(
                              color: HomeTheme.focusGold, width: 2)
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
              watchProgress: _episodeWatchProgress[
                  '${episode.season}-${episode.number}'],
              isNext: _nextEpisode != null &&
                  _nextEpisode!.season == episode.season &&
                  _nextEpisode!.episode == episode.number,
              onPlay: () => _onEpisodeQuickPlay(episode),
              onSources: () => _onEpisodeTap(episode),
              onMenuAction: _isTraktAuthenticated
                  ? (action) => _onEpisodeMenuAction(episode, action)
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
                        color: Colors.white,
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
            isNext: _nextEpisode != null &&
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
      backgroundColor: const Color(0xFF141019),
      showDragHandle: true,
      builder: (sheetCtx) {
        Widget tile(IconData icon, String label, VoidCallback onTap,
            {Color? color, bool autofocus = false}) {
          return ListTile(
            autofocus: autofocus,
            // Default focus overlay is invisible on the dark sheet — make the
            // DPAD cursor obvious.
            focusColor: Colors.white.withValues(alpha: 0.12),
            leading: Icon(icon, color: color ?? Colors.white),
            title: Text(label,
                style: TextStyle(color: color ?? Colors.white)),
            onTap: () {
              Navigator.of(sheetCtx).pop();
              onTap();
            },
          );
        }

        return SafeArea(
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
              // Autofocus Play on TV so the sheet opens with a live target.
              tile(Icons.play_arrow_rounded, 'Play',
                  () => _onEpisodeQuickPlay(episode),
                  autofocus: widget.isTelevision),
              tile(Icons.layers_rounded, 'Sources',
                  () => _onEpisodeTap(episode)),
              if (_isTraktAuthenticated) ...[
                if (!watched)
                  tile(Icons.check_circle_rounded, 'Mark as Watched',
                      () => _onEpisodeMenuAction(
                          episode, TraktEpisodeMenuAction.markWatched)),
                if (watched)
                  tile(Icons.visibility_off_rounded, 'Mark as Unwatched',
                      () => _onEpisodeMenuAction(
                          episode, TraktEpisodeMenuAction.markUnwatched)),
                tile(Icons.star_rounded, 'Rate on Trakt',
                    () => _onEpisodeMenuAction(
                        episode, TraktEpisodeMenuAction.rate)),
              ],
            ],
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
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: widget.hasBoundSource
                ? HomeTheme.focusGold.withValues(alpha: 0.14)
                : Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _isFocused
                  ? HomeTheme.focusGold
                  : widget.hasBoundSource
                  ? HomeTheme.focusGold.withValues(alpha: 0.45)
                  : Colors.white.withValues(alpha: 0.14),
              width: _isFocused ? 2 : 1,
            ),
            boxShadow: _isFocused
                ? [
                    BoxShadow(
                      color: HomeTheme.focusGold.withValues(alpha: 0.32),
                      blurRadius: 12,
                    ),
                  ]
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
                    ? HomeTheme.focusGold
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
                      ? HomeTheme.focusGold
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
    return IconButton(
      visualDensity: VisualDensity.compact,
      style: ButtonStyle(
        side: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.focused)
              ? const BorderSide(color: HomeTheme.focusGold, width: 2)
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
    final subtitle = (e.overview?.isNotEmpty ?? false)
        ? e.overview!
        : (e.firstAired ?? '');

    return Focus(
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
            duration: const Duration(milliseconds: 140),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _focused
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.white.withValues(alpha: 0.02),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _focused
                    ? HomeTheme.focusGold
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
                            errorWidget: (_, __, ___) =>
                                Container(color: const Color(0xFF1A1622)),
                          )
                        else
                          Container(color: const Color(0xFF1A1622)),
                        if (watched)
                          Container(
                            color: Colors.black.withValues(alpha: 0.45),
                            alignment: Alignment.center,
                            child: const Icon(
                              Icons.check_circle_rounded,
                              color: HomeTheme.focusGold,
                              size: 24,
                            ),
                          ),
                        if (widget.isNext && !watched)
                          Positioned(
                            top: 5,
                            left: 5,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: HomeTheme.focusGold,
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
                                child: Container(color: HomeTheme.focusGold),
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
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          height: 1.2,
                        ),
                      ),
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
                      const Icon(Icons.check_circle_rounded,
                          color: HomeTheme.focusGold, size: 18)
                    else if (partial)
                      Text(
                        '${progress.round()}%',
                        style: const TextStyle(
                          color: HomeTheme.focusGold,
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
                        color: Colors.white
                            .withValues(alpha: _focused ? 0.9 : 0.35),
                      )
                    else
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: Icon(Icons.more_vert_rounded,
                            color: Colors.white.withValues(alpha: 0.6),
                            size: 20),
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
  }
}
