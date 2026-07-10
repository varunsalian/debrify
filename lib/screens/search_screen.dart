import 'dart:async';
import 'dart:math';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/advanced_search_selection.dart';
import '../models/debrify_tv/channel.dart';
import '../models/iptv_playlist.dart';
import '../models/playlist_view_mode.dart';
import '../models/stremio_addon.dart';
import '../models/stremio_tv/stremio_tv_channel.dart';
import '../models/stremio_tv/stremio_tv_now_playing.dart';
import '../models/torrent.dart';
import '../models/torrent_filter_state.dart';
import '../services/debrify_tv_repository.dart';
import '../services/engine/dynamic_engine.dart';
import '../services/engine/engine_registry.dart';
import '../services/engine/settings_manager.dart';
import '../services/local_bound_source_service.dart';
import '../services/main_page_bridge.dart';
import '../services/playlist_player_service.dart';
import '../services/premiumize_service.dart';
import '../services/series_source_service.dart';
import '../services/stremio_service.dart';
import '../services/storage_service.dart';
import '../services/torbox_service.dart';
import '../services/torrent_bulk_add_service.dart';
import '../services/torrent_playback_service.dart';
import '../services/torrent_service.dart';
import '../services/trakt/trakt_continue_watching_service.dart';
import '../services/trakt/trakt_service.dart';
import '../services/video_player_launcher.dart';
import '../utils/dialog_tap_guard.dart';
import '../utils/torrent_filter_matcher.dart';
import '../utils/tv_keys.dart';
import '../widgets/add_source_picker_dialog.dart';
import '../widgets/home/home_theme.dart';
import '../widgets/skeleton_poster.dart';
import '../widgets/torrent_filters_sheet.dart';
import '../widgets/torrent_result_row.dart';
import 'playlist_content_view_screen.dart';
import 'see_all/catalog_see_all_screen.dart';
import 'see_all/continue_watching_see_all_screen.dart';
import 'see_all/trakt_see_all_screen.dart';
import '../widgets/see_all/stremio_dropdown.dart';
import '../widgets/trakt/trakt_menu_helpers.dart';
import 'catalog_item_detail_screen.dart';
import 'merged_series_detail_screen.dart';
import 'debrid_downloads_screen.dart';
import 'episodes_screen.dart';
import 'stremio_tv/stremio_tv_service.dart';
import 'stremio_tv/widgets/stremio_tv_catalog_picker_dialog.dart';
import 'torbox/torbox_downloads_screen.dart';

/// Stremio-style palette for the Search tab: an indigo/purple accent and a deep
/// near-black indigo base behind the poster board.
const Color kStremioAccent = Color(0xFF7B5CFF);
const Color kStremioBg = Color(0xFF0D0B1A);

/// Continue Watching progress-bar fill (Stremio shows a white line; we use red).
const Color _kCwProgressRed = Color(0xFFE50914);

/// Board (homepage) infinite scroll: how many catalog rows to fetch per batch as
/// the user scrolls, and how many items to keep per row. Enumerating catalogs is
/// free (manifest metadata) — only fetching each row's items costs a call — so we
/// list every catalog up front and lazily pull batches on scroll (Stremio-style)
/// instead of a hard global row cap.
const int _kBoardBatchSize = 8;

/// When a row's horizontal scroll gets within this many pixels of the end, the
/// next page for that catalog is fetched (Stremio-style unlimited rows).
const double _kRowLoadMoreThreshold = 900;

/// Format a season/episode as a compact 'S2 · E5' label, or null when unknown.
String? _seLabel(int? season, int? episode) {
  if (season == null || episode == null || season <= 0 || episode <= 0) {
    return null;
  }
  return 'S$season · E$episode';
}

/// Dedicated Search tab.
///
/// * CATALOG mode — a Stremio-style board (one horizontal row per addon
///   catalog) with a hero spotlight that reflects the focused title; typing a
///   query searches every searchable addon and shows one horizontal row of
///   results per addon (same board layout).
/// * KEYWORD mode — raw torrent search → tap a result to add/play.
///
/// All playback (catalog auto-best, sources list, keyword) runs in-tab through
/// the isolated [TorrentPlaybackService]; the Home engine is never invoked.
class SearchScreen extends StatefulWidget {
  final bool isTelevision;

  /// Dedicated-search-tab mode (TV only). When true the screen is *only* the
  /// search field + Catalog/Keyword toggle over a blank prompt until the user
  /// types — no hero/board. When false it's the "Home New" board (chrome-free on
  /// TV; persistent search bar on desktop/mobile).
  final bool searchMode;

  /// Discover-tab mode. A single browsable grid with a "Source" dropdown
  /// (Continue Watching / Trakt / …) instead of the board's stacked rails —
  /// reuses this screen's item-open/play handlers and cached CW/Trakt rows.
  final bool discoverMode;

  const SearchScreen({
    super.key,
    this.isTelevision = false,
    this.searchMode = false,
    this.discoverMode = false,
  });

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

enum _Mode { catalog, keyword }

/// Fixed Discover sources; installed addons are appended dynamically (key
/// 'a:{addonId}').
const String _discCw = 'cw';
const String _discTrakt = 'trakt';
const String _discAddonPrefix = 'a:';

// Metrics for the inline caption under an [_ArtPoster] (the favourites rails).
// Kept as the single source of truth so anything reserving vertical space for
// the caption (the cell height, the hero's row-reserve budget) can't drift from
// the widget's own layout.
const double _kArtTitleGap = 10;
const double _kArtTitleFontSize = 14;
const double _kArtTitleHeight = 1.25;
const int _kArtTitleMaxLines = 2;

/// Height of the caption band under an [_ArtPoster]: the gap plus its up-to-two
/// lines at the current text scale.
double _artPosterCaptionBand(BuildContext context) =>
    _kArtTitleGap +
    MediaQuery.textScalerOf(context).scale(_kArtTitleFontSize) *
        _kArtTitleHeight *
        _kArtTitleMaxLines;

/// Intent for a left-arrow on the search field, remapped (via a [Shortcuts]
/// override closer than the default text-editing shortcuts) so an empty field
/// escapes to the sidebar instead of the EditableText silently eating the key.
class _SearchLeftIntent extends Intent {
  const _SearchLeftIntent();
}

/// Escapes an *empty* TV search field to the sidebar on left-arrow. It disables
/// itself the moment there's text, so [Shortcuts] falls through to the default
/// caret/selection handling — meaning the wrapper can stay mounted at all times
/// (a stable subtree root) without the action ever swallowing a real caret move.
class _EmptyFieldLeftAction extends Action<_SearchLeftIntent> {
  _EmptyFieldLeftAction(this._controller, this._onEscape);

  final TextEditingController _controller;
  final VoidCallback _onEscape;

  @override
  bool isEnabled(_SearchLeftIntent intent) => _controller.text.isEmpty;

  @override
  Object? invoke(_SearchLeftIntent intent) {
    _onEscape();
    return null;
  }
}

class _SearchScreenState extends State<SearchScreen> {
  // Which nav tab this instance backs, for the TV content-focus handler: the
  // dedicated Search tab (17) or the Home-New board (15).
  int get _tabIndex =>
      widget.searchMode ? 17 : (widget.discoverMode ? 18 : 15);

  final StremioService _stremio = StremioService.instance;

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode(debugLabel: 'search_field');
  // DPAD focus targets for the Catalog / Keyword toggle (TV only), so the
  // toggle is reachable with a remote (arrow-up from the search field).
  final FocusNode _modeCatalogNode = FocusNode(debugLabel: 'mode_catalog');
  final FocusNode _modeKeywordNode = FocusNode(debugLabel: 'mode_keyword');

  _Mode _mode = _Mode.catalog;

  /// Committed catalog query (drives per-addon catalog search). Empty = board.
  String _catalogQuery = '';
  Timer? _catalogDebounce;

  /// The addon that produced the item currently being played/browsed, threaded
  /// into playback so Continue Watching can route resume / next-episode back to
  /// it (matching Home's `addonId`). Set whenever we open a catalog item.
  String? _activeAddonId;

  // Keyword torrent-search state (submit-based).
  bool _kwLoading = false;
  String? _kwError;
  String _kwQuery = '';
  List<Torrent> _kwAll = []; // unfiltered results from the last search
  List<Torrent> _kwResults = []; // filtered + sorted view actually rendered
  final List<FocusNode> _kwNodes = [];
  // Keyboard/DPAD focus targets for the keyword toolbar pills (Sort / Filters /
  // Sources / Select). A fixed pool of 4 covers the most pills ever shown.
  final List<FocusNode> _kwToolbarNodes = List.generate(
    4,
    (i) => FocusNode(debugLabel: 'kw_tb_$i'),
  );
  TorrentFilterState _kwFilters = const TorrentFilterState.empty();
  String _kwSort = 'relevance';
  Map<String, List<String>> _kwCache = {}; // infohash(lower) → ['TB','PM']

  // Bulk-selection state for keyword results (mirrors Home's multi-select).
  bool _kwSelectionMode = false;
  final Set<String> _kwSelected = {}; // selected torrent infohashes

  /// Monotonic token so a slow earlier keyword search can't clobber a newer one.
  int _kwSearchToken = 0;

  /// True when PikPak is the ONLY configured provider. PikPak can't quick-play
  /// (it queues a cloud download), so catalog "Play" is hidden — matching Home.
  bool _pikpakOnly = false;

  /// Experimental flag: route series taps to the merged detail+episodes page.
  /// Loaded once on init; movies and the flag-off path keep the existing flow.
  bool _mergedSeriesPage = false;

  /// imdbId → number of pinned (bound) sources — drives the board tile badge,
  /// detail Sources tint, and the Episodes "Source(s)" button count.
  final Map<String, int> _boundCounts = {};

  // Board state. [_homeSections] is the homepage cache; [_sections] is whatever
  // is currently shown (homepage OR per-addon catalog search results). Both the
  // board and catalog search render through the same horizontal-row layout.
  bool _loading = true;
  String? _error;
  List<CatalogSection> _homeSections = [];
  List<CatalogSection> _sections = [];
  final List<List<FocusNode>> _rowNodes = [];
  bool _catalogSearching = false;
  int _catalogSearchToken = 0;

  // Board infinite scroll. Every (addon, catalog) pair is enumerated up front in
  // [_boardRefs] (cheap — manifest metadata, no network), then fetched in batches
  // as the user nears the bottom. [_boardCursor] is the next ref to load; it
  // persists across a search detour so returning to the board keeps its place.
  final List<(StremioAddon, StremioAddonCatalog)> _boardRefs = [];
  int _boardCursor = 0;
  bool _boardLoadingMore = false;
  final ScrollController _boardScroll = ScrollController();

  /// Whether more board rows remain to lazily load (board mode only — never
  /// during a catalog search, which fetches all its rows in one shot).
  bool get _boardHasMore =>
      _catalogQuery.isEmpty &&
      !_catalogSearching &&
      _boardCursor < _boardRefs.length;

  // LOCAL Continue Watching rows. Reads the SAME local store Home writes to
  // (StorageService `continue_watching_v1`) — read-only here, so Home is never
  // affected. Split into two recency-ordered rows (Movies, then Series), each
  // shown as a leading board row when non-empty. Removal happens only from the
  // detail screen's action.
  bool _cwEnabled = true;
  List<StremioMeta> _cwMovies = [];
  List<StremioMeta> _cwSeries = [];
  // Movies + series merged in last-watched order (newest first) — the source
  // for the Continue Watching "See All" grid, which filters by type itself.
  List<StremioMeta> _cwAll = [];
  final Map<String, double> _cwProgress = {}; // imdbId → 0..1 watched fraction
  final Map<String, String> _cwEpisode = {}; // imdbId → 'S2 · E5' (series only)
  final Set<String> _cwIds = {}; // imdbIds currently in Continue Watching
  final Map<String, String?> _cwAddonId = {}; // imdbId → source addon id
  final List<FocusNode> _cwMovieNodes = [];
  final List<FocusNode> _cwSeriesNodes = [];

  /// Monotonic guard so an earlier, slower Continue Watching load (which does
  /// one SharedPreferences round-trip per item) can't finish after a newer one
  /// and dispose the focus nodes / state the newer run just installed.
  int _cwLoadToken = 0;

  // TRAKT Continue Watching rows ("Trakt Movies" / "Trakt Shows"), fetched live
  // from the Trakt account (no local store). Shown after the local rows when
  // connected + non-empty. Network-loaded once on init / integration change and
  // cached in memory (the shows fetch is heavy: ~2 + N calls).
  List<StremioMeta> _traktMovies = [];
  List<StremioMeta> _traktSeries = [];
  // Trakt movies + shows merged in last-watched (paused_at) order — the source
  // for the Trakt Continue Watching "See All" grid.
  List<StremioMeta> _traktAll = [];
  final Map<String, double> _traktProgress = {}; // imdbId → 0..1
  final Map<String, String> _traktEpisode = {}; // imdbId → 'S2 · E5' (series)
  final Map<String, TraktContinueWatchingItem> _traktByImdb = {};
  final List<FocusNode> _traktMovieNodes = [];
  final List<FocusNode> _traktSeriesNodes = [];

  // Debrify TV favourites — a leading "Debrify TV" row of the user's starred
  // keyword channels, shown between Continue Watching and the catalog rows.
  // Channels have no artwork, so they render as Stremio-shaped cards with a
  // gradient + glyph placeholder (see [_ArtPoster]).
  List<DebrifyTvChannel> _tvFavChannels = [];
  final List<FocusNode> _tvFavNodes = [];

  // Stremio TV favourites — a leading row of the user's starred Stremio
  // "channels" (catalogs treated as TV channels). Each card shows the channel's
  // current now-playing item poster (same time-based rotation as the Home /
  // Stremio TV screens); tapping opens the channel. Loaded once on init.
  List<StremioTvChannel> _stvFavChannels = [];
  final List<FocusNode> _stvFavNodes = [];
  int _stvRotationMinutes = 90;
  int _stvSeriesRotationMinutes = 45;

  // IPTV favourites — a leading row of the user's starred live IPTV channels.
  // Cards show the channel logo (glyph fallback); tapping plays the stream
  // directly via VideoPlayerLauncher (no tab switch). Loaded once on init.
  List<IptvChannel> _iptvFavChannels = [];
  final List<FocusNode> _iptvFavNodes = [];

  // Playlist favourites — a leading row of the user's saved playlist items
  // (movies / collections added from search or cloud). Cards show the item
  // poster with resume progress; tapping opens a full action menu (play / play
  // random / view files / favorite / clear progress / launch-on-startup /
  // delete), so this row is a complete playlist manager on its own now that the
  // Home playlist section is being phased out. Loaded once on init.
  List<Map<String, dynamic>> _playlistItems = [];
  final List<FocusNode> _playlistFavNodes = [];
  Map<String, Map<String, dynamic>> _playlistProgress = {};
  Set<String> _playlistFavKeys = {};
  // Guards against launching a second concurrent playback while the first is
  // still resolving links (the menu closes immediately, giving no other cue).
  bool _playlistLaunching = false;

  int _traktCwToken = 0;

  /// Whether a Trakt Continue Watching fetch is currently in flight for a
  /// connected account. While true — and there are no real Trakt rows to show
  /// yet — the Trakt slot is held open with skeleton placeholders (see
  /// [_traktReserving]) so the real rows fill in place instead of inserting
  /// mid-board and shoving everything below them down. Set at the start of each
  /// load and cleared on every terminal path, so a mid-session connect (which
  /// re-runs the load) reserves the slot again.
  bool _traktCwLoading = false;

  /// TV auto-focus "settle to the top" state. On arrival the board focuses the
  /// best card available immediately (an addon row if the Trakt rows above it
  /// are still loading), remembering that node in [_autoFocusedNode]. As higher
  /// rows load (Trakt, local Continue Watching), focus slides up to the new top
  /// card — but only while the user is idle (focus still sits on the node we
  /// placed). The instant the user moves focus themselves, [_autoFocusSettled]
  /// latches and we never touch focus again.
  FocusNode? _autoFocusedNode;
  bool _autoFocusSettled = false;

  /// Coalesces auto-focus passes: multiple content loads finishing in one frame
  /// schedule a single post-frame placement (which reads the final top after all
  /// their setStates apply), instead of racing several callbacks whose
  /// primaryFocus reads haven't caught up to each other's requestFocus.
  bool _autoFocusScheduled = false;

  /// Whether Trakt is connected — gates the Trakt-syncing detail quick actions
  /// (watchlist / collection / watched / rate / list). App actions (Select
  /// Source, Add to Stremio TV, Search Packs) show regardless.
  bool _isTraktAuthenticated = false;
  // Addons that produced homepage rows, indexed by id, so a Continue Watching
  // tap can route back through the right addon (for Episodes / next-episode).
  final Map<String, StremioAddon> _addonsById = {};

  /// The leading Continue Watching rows to render, in order: local Movies /
  /// Series (when enabled), then Trakt Movies / Shows (when connected). Only
  /// non-empty groups are included. Each row carries its own progress lookup
  /// and open / quick-play handlers so local and Trakt sources coexist.
  List<_CwRow> get _cwRows => [
    if (_cwEnabled && _cwMovies.isNotEmpty)
      _CwRow(
        title: 'Continue Watching',
        tag: 'Movies',
        items: _cwMovies,
        nodes: _cwMovieNodes,
        progressOf: (m) => _cwProgress[m.imdbId],
        episodeOf: (_) => null,
        onOpen: _openContinueItem,
        onQuickPlay: _onContinuePlay,
        onSeeAll: () => _openContinueWatchingSeeAll('movie'),
      ),
    if (_cwEnabled && _cwSeries.isNotEmpty)
      _CwRow(
        title: 'Continue Watching',
        tag: 'Series',
        items: _cwSeries,
        nodes: _cwSeriesNodes,
        progressOf: (m) => _cwProgress[m.imdbId],
        episodeOf: (m) => _cwEpisode[m.imdbId],
        onOpen: _openContinueItem,
        onQuickPlay: _onContinuePlay,
        onSeeAll: () => _openContinueWatchingSeeAll('series'),
      ),
    if (_traktMovies.isNotEmpty)
      _CwRow(
        title: 'Trakt Continue Watching',
        tag: 'Movies',
        items: _traktMovies,
        nodes: _traktMovieNodes,
        progressOf: (m) => _traktProgress[m.imdbId],
        episodeOf: (_) => null,
        onOpen: _openTraktItem,
        onQuickPlay: _playTraktItem,
        onSeeAll: () => _openTraktSeeAll('movie'),
      ),
    if (_traktSeries.isNotEmpty)
      _CwRow(
        title: 'Trakt Continue Watching',
        tag: 'Shows',
        items: _traktSeries,
        nodes: _traktSeriesNodes,
        progressOf: (m) => _traktProgress[m.imdbId],
        episodeOf: (m) => _traktEpisode[m.imdbId],
        onOpen: _openTraktItem,
        onQuickPlay: _playTraktItem,
        onSeeAll: () => _openTraktSeeAll('series'),
      ),
  ];

  /// Whether any Continue Watching row is currently on-screen (drives focus
  /// wiring between it and the first catalog row). Uses allocation-free field
  /// checks (not `_cwRows`) since it's read on the per-card build hot path.
  bool get _cwVisible =>
      ((_cwEnabled && (_cwMovies.isNotEmpty || _cwSeries.isNotEmpty)) ||
          _traktMovies.isNotEmpty ||
          _traktSeries.isNotEmpty) &&
      _catalogQuery.isEmpty &&
      !_catalogSearching;

  /// Whether the Trakt rows should be held open with skeleton placeholders: the
  /// account is connected, its (slow, network) Continue Watching fetch is in
  /// flight, and there are no real Trakt rows on-screen yet. Reserving the slot
  /// keeps the row count stable so the real rows fill in place — nothing below
  /// reflows, and the auto-focus anchor stays put.
  ///
  /// Shown on every platform (the placeholder header omits the phone/desktop
  /// See-All link, which pops in harmlessly when the real row loads). Only on
  /// the homepage board (not the dedicated Search / Discover tabs, and not while
  /// a catalog search is showing its own results). Requiring the real rows to be
  /// empty means a refresh that already has data updates in place — no skeletons
  /// stacked on top of live rows.
  bool get _traktReserving =>
      !widget.searchMode &&
      !widget.discoverMode &&
      _isTraktAuthenticated &&
      _traktCwLoading &&
      _traktMovies.isEmpty &&
      _traktSeries.isEmpty &&
      _catalogQuery.isEmpty &&
      !_catalogSearching;

  /// How many skeleton Trakt rows to reserve while [_traktReserving]. Two —
  /// Movies then Shows — matches the shape most connected accounts resolve to,
  /// so the common case fills in with zero layout shift. (A connected account
  /// with fewer real rows collapses the extras once, early, before the user is
  /// deep in the board — far less jarring than a mid-navigation insert.)
  int get _traktSkeletonRowCount => _traktReserving ? 2 : 0;

  // Hero state. Driven by ValueNotifiers so focus-driven hero swaps rebuild
  // only the spotlight, never the whole board (important on low-power TVs).
  final ValueNotifier<StremioMeta?> _heroItem = ValueNotifier<StremioMeta?>(
    null,
  );
  final ValueNotifier<StremioMeta?> _heroEnriched = ValueNotifier<StremioMeta?>(
    null,
  );
  int _heroReqId = 0;
  Timer? _heroTimer;

  // Discover tab: the active source key ('cw' | 'trakt' | 'a:{addonId}') + its
  // DPAD focus node (the "Source" dropdown is the leading filter of whichever
  // embedded See-All panel is shown). [_discAddons] is the browsable addon list
  // appended to the Source dropdown.
  String _discSource = _discCw;
  List<StremioAddon> _discAddons = const [];
  final FocusNode _discSourceNode = FocusNode(debugLabel: 'disc_source');

  @override
  void initState() {
    super.initState();
    MainPageBridge.registerTvContentFocusHandler(_tabIndex, _focusContent);
    if (widget.searchMode) {
      MainPageBridge.registerTabBackHandler('search', _handleSearchBack);
    }
    MainPageBridge.addIntegrationListener(_onIntegrationsChanged);
    _boardScroll.addListener(_onBoardScroll);
    _refreshTraktAuthState();
    _loadMergedSeriesFlag();
    // The dedicated Search tab only shows a field + blank prompt until a query,
    // so it skips the whole board pipeline (home catalogs, Continue Watching,
    // Trakt, favourites) — catalog search fetches its addons on demand. It also
    // never runs _load(), which is what clears _loading, so clear it here or the
    // results grid (_buildBoard) would sit on its initial spinner forever.
    if (widget.searchMode) {
      _loading = false;
    } else if (widget.discoverMode) {
      // Discover browses one source at a time via the Source dropdown, so it
      // skips the board's catalog pipeline and just primes the Continue Watching
      // + Trakt rows its first two sources draw from. _refreshPikpakOnly gates the
      // Quick-Play affordance the same way the board does.
      _loading = false;
      _refreshPikpakOnly();
      _loadDiscoverAddons();
      _primeDiscoverRows();
    } else {
      // Kick off every leading-content load. Auto-focus settles to the top as
      // these complete; once they've ALL settled the arrival window is over and
      // re-anchoring latches off (see [_settleAutoFocusAfter]), so a later
      // background reload or a return from playback never yanks focus.
      _settleAutoFocusAfter([
        _load(),
        _loadContinueWatching(),
        _loadTraktContinueWatching(),
        _loadTvFavorites(),
        _loadStremioTvFavorites(),
        _loadIptvFavorites(),
        _loadPlaylistFavorites(),
      ]);
    }
  }

  /// Await the initial board content loads, then end the auto-focus "arrival
  /// window": one final placement pass, then latch [_autoFocusSettled] so
  /// re-anchoring never fires again (a background CW/Trakt refresh, or focus
  /// restoration after returning from playback, must not move the user's focus).
  Future<void> _settleAutoFocusAfter(List<Future<void>> loads) async {
    await Future.wait(loads.map((f) => f.catchError((_) {})));
    if (!mounted) return;
    _maybeAutoFocusBoard();
    // Latch on the following frame so the placement pass above runs first.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _autoFocusSettled = true;
    });
  }

  /// Back on the dedicated Search tab: clear an in-progress search (returning to
  /// the blank prompt) first; a second Back with nothing to clear falls through
  /// to leave the tab. Registered only in [SearchScreen.searchMode].
  bool _handleSearchBack() {
    final hasQuery =
        _searchController.text.isNotEmpty ||
        _catalogQuery.isNotEmpty ||
        _kwQuery.isNotEmpty;
    if (!hasQuery) return false;
    // Back also drops out of Keyword mode, so the tab returns to its default
    // Catalog prompt (matches the old overlay-close behaviour). _clearQuery
    // rebuilds, so setting the field first is enough.
    _mode = _Mode.catalog;
    _clearQuery();
    if (widget.isTelevision) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _searchFocusNode.requestFocus();
      });
    }
    return true;
  }

  /// An integration (Trakt / a debrid provider) was connected or disconnected
  /// elsewhere while this tab stayed alive — refresh the state that gates the
  /// detail quick actions, the PikPak-only Play hiding, and the Trakt rows.
  void _onIntegrationsChanged() {
    _refreshTraktAuthState();
    _refreshPikpakOnly();
    // Trakt Continue Watching rows are never rendered on the dedicated Search
    // tab, so don't refetch them there.
    if (!widget.searchMode) _loadTraktContinueWatching();
  }

  Future<void> _refreshTraktAuthState() async {
    final auth = await TraktService.instance.isAuthenticated();
    if (!mounted || auth == _isTraktAuthenticated) return;
    setState(() => _isTraktAuthenticated = auth);
  }

  @override
  void dispose() {
    MainPageBridge.unregisterTvContentFocusHandler(_tabIndex, _focusContent);
    if (widget.searchMode) {
      MainPageBridge.unregisterTabBackHandler('search', _handleSearchBack);
    }
    MainPageBridge.removeIntegrationListener(_onIntegrationsChanged);
    _catalogDebounce?.cancel();
    _heroTimer?.cancel();
    _heroItem.dispose();
    _heroEnriched.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _modeCatalogNode.dispose();
    _modeKeywordNode.dispose();
    _discSourceNode.dispose();
    _boardScroll.dispose();
    _disposeNodes();
    _disposeKwNodes();
    for (final n in [
      ..._cwMovieNodes,
      ..._cwSeriesNodes,
      ..._traktMovieNodes,
      ..._traktSeriesNodes,
      ..._tvFavNodes,
      ..._stvFavNodes,
      ..._iptvFavNodes,
      ..._playlistFavNodes,
      ..._kwToolbarNodes, // fixed pool — only disposed here, not in _disposeKwNodes
    ]) {
      n.dispose();
    }
    _cwMovieNodes.clear();
    _cwSeriesNodes.clear();
    _traktMovieNodes.clear();
    _traktSeriesNodes.clear();
    _tvFavNodes.clear();
    _stvFavNodes.clear();
    _iptvFavNodes.clear();
    _playlistFavNodes.clear();
    super.dispose();
  }

  void _disposeNodes() {
    for (final row in _rowNodes) {
      for (final node in row) {
        node.dispose();
      }
    }
    _rowNodes.clear();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    unawaited(_refreshPikpakOnly());
    try {
      final addons = await _stremio.getCatalogAddons();
      if (!mounted) return;
      // Enumerate every BROWSABLE catalog across all addons — no global row cap.
      // This is cheap (manifest data); items are pulled lazily in batches on
      // scroll. Catalogs that require a `search` extra are search-only: browsing
      // them without a query just returns empty after a wasted round trip, so
      // skip them here (they still power the Keyword/catalog search path).
      _boardRefs
        ..clear()
        ..addAll([
          for (final a in addons)
            for (final c in a.catalogs)
              if (c.isBrowsable) (a, c),
        ]);
      _boardCursor = 0;
      _addonsById.clear();
      for (final a in addons) {
        _addonsById.putIfAbsent(a.id, () => a);
      }
      // First batch is blocking so the board isn't empty on first paint; skip
      // runs of empty catalogs so we always land on some visible rows.
      final first = await _fetchBoardBatchUntilNonEmpty();
      if (!mounted) return;
      _homeSections = first;
      setState(() => _loading = false);
      _applySections(first);
      _maybeAutoFocusBoard();
      _maybeAutoFillBoard();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  /// Fetch the next batch of catalog rows from [_boardCursor], skipping over any
  /// runs of empty catalogs, and return the non-empty sections (advancing the
  /// cursor as it goes). Empty result ⇒ the board is exhausted.
  Future<List<CatalogSection>> _fetchBoardBatchUntilNonEmpty() async {
    while (_boardCursor < _boardRefs.length) {
      final batch = await _fetchBoardBatch(_kBoardBatchSize);
      if (batch.isNotEmpty) return batch;
    }
    return const [];
  }

  /// Fetch exactly one batch of up to [n] catalog rows in parallel, advancing
  /// [_boardCursor], and return the non-empty ones (order preserved).
  Future<List<CatalogSection>> _fetchBoardBatch(int n) async {
    final end = (_boardCursor + n).clamp(0, _boardRefs.length);
    final slice = _boardRefs.sublist(_boardCursor, end);
    _boardCursor = end;
    final results = await Future.wait(
      slice.map((ref) async {
        final (addon, catalog) = ref;
        try {
          var rawCount = 0;
          final items = await _stremio.fetchCatalog(
            addon,
            catalog,
            onRawCount: (c) => rawCount = c,
          );
          if (items.isEmpty) return null;
          return CatalogSection(
            title: '${addon.name}: ${catalog.name}',
            addon: addon,
            catalog: catalog,
            // Keep the whole first page; more pages stream in on horizontal scroll.
            items: items.toList(),
            // Next page starts past the addon's raw first window (not the smaller
            // post-filter count), keeping paging aligned from the very first fetch.
            nextSkip: rawCount > 0 ? rawCount : items.length,
          );
        } catch (_) {
          return null;
        }
      }),
    );
    return results.whereType<CatalogSection>().toList();
  }

  /// After a batch lands, if the board still doesn't fill the viewport (so the
  /// user can't scroll to trigger more) keep pulling batches until it does or
  /// the board is exhausted. No-ops outside board mode (search sets no cursor).
  void _maybeAutoFillBoard() {
    if (!_boardHasMore || _boardLoadingMore) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_boardHasMore || _boardLoadingMore) return;
      if (!_boardScroll.hasClients) return;
      final pos = _boardScroll.position;
      if (pos.maxScrollExtent <= 0 || pos.pixels >= pos.maxScrollExtent - 600) {
        _loadMoreBoard();
      }
    });
  }

  /// Fire off the next batch as the user nears the bottom of the board.
  void _onBoardScroll() {
    if (!_boardHasMore || _boardLoadingMore) return;
    if (!_boardScroll.hasClients) return;
    final pos = _boardScroll.position;
    if (pos.pixels >= pos.maxScrollExtent - 600) {
      _loadMoreBoard();
    }
  }

  /// Load and append the next batch of board rows (deduped against re-entry).
  Future<void> _loadMoreBoard() async {
    if (_boardLoadingMore || _boardCursor >= _boardRefs.length) return;
    setState(() => _boardLoadingMore = true);
    try {
      final more = await _fetchBoardBatchUntilNonEmpty();
      if (!mounted) return;
      if (more.isNotEmpty) {
        // Always keep the board cache growing so nothing is lost…
        _homeSections = [..._homeSections, ...more];
        // …but only fold into the live view when the board is still what's
        // shown. If a catalog search started while this batch was in flight,
        // `_sections`/`_rowNodes` now hold search results — appending board rows
        // there would corrupt the search view. They'll reappear on _restoreHome.
        if (_catalogQuery.isEmpty && !_catalogSearching) {
          _appendSections(more);
        }
      }
    } finally {
      if (mounted) setState(() => _boardLoadingMore = false);
      _maybeAutoFillBoard();
    }
  }

  /// Append newly-loaded board rows without disturbing the rows already shown:
  /// grow the per-row focus nodes in lockstep with [_sections].
  void _appendSections(List<CatalogSection> more) {
    for (final section in more) {
      _rowNodes.add(
        List.generate(
          section.items.length,
          (i) => FocusNode(debugLabel: 'search_r${_rowNodes.length}_c$i'),
        ),
      );
    }
    setState(() => _sections = [..._sections, ...more]);
    unawaited(_refreshBoundSources());
  }

  /// Fetch the next page for a single catalog row and append it in place, so
  /// rows grow without bound as the user scrolls right (Stremio-style). Only
  /// board rows paginate; search-result rows are single-shot. Safe to call
  /// repeatedly — [CatalogSection.loadingMore]/[CatalogSection.exhausted] guard
  /// re-entrancy and the end of the catalog.
  Future<void> _loadMoreRow(int rowIndex) async {
    // While a catalog search is active, `_sections` holds search results, which
    // don't paginate — leave them alone.
    if (_catalogQuery.isNotEmpty || _catalogSearching) return;
    if (rowIndex < 0 || rowIndex >= _sections.length) return;
    final section = _sections[rowIndex];
    if (section.loadingMore || section.exhausted) return;
    setState(() => section.loadingMore = true);
    try {
      // Advance `skip` by the addon's RAW returned count (via onRawCount), not
      // the post-filter `page.length`, so we stay aligned with the addon's own
      // paging window and don't slowly under-advance into a false "exhausted".
      var rawCount = 0;
      final page = await _stremio.fetchCatalog(
        section.addon,
        section.catalog,
        skip: section.nextSkip,
        onRawCount: (c) => rawCount = c,
      );
      if (!mounted) return;
      // The row may have been swapped out (a search started) while in flight.
      if (rowIndex >= _sections.length ||
          !identical(_sections[rowIndex], section)) {
        return;
      }
      if (page.isEmpty) {
        section.exhausted = true;
        return;
      }
      // Dedup against what we already have; some addons return valid ids but
      // repeat entries, and some ignore `skip` entirely.
      final seen = section.items.map((m) => m.id).toSet();
      final fresh = page.where((m) => seen.add(m.id)).toList();
      // Advance by the raw window size (falls back to the filtered count only
      // if the addon somehow didn't report), so the next skip lands past what
      // this window already covered.
      section.nextSkip += rawCount > 0 ? rawCount : page.length;
      if (fresh.isEmpty) {
        // Addon returned only duplicates (or ignores skip) — nothing new to add.
        section.exhausted = true;
        return;
      }
      // Grow this row's focus nodes in lockstep with the new items.
      final nodes = _rowNodes[rowIndex];
      final base = nodes.length;
      for (var i = 0; i < fresh.length; i++) {
        nodes.add(FocusNode(debugLabel: 'search_r${rowIndex}_c${base + i}'));
      }
      setState(() => section.items.addAll(fresh));
      unawaited(_refreshBoundSources());
    } catch (_) {
      // Transient fetch failure — leave the row as-is so a later scroll retries.
    } finally {
      if (mounted) {
        setState(() => section.loadingMore = false);
      } else {
        section.loadingMore = false;
      }
    }
  }

  /// IMDb id for a catalog item, or null when it isn't a `tt…` id.
  String? _imdbOf(StremioMeta item) {
    final id = item.imdbId ?? (item.id.startsWith('tt') ? item.id : null);
    return (id != null && id.isNotEmpty) ? id : null;
  }

  bool _isBound(StremioMeta item) {
    final id = _imdbOf(item);
    return id != null && (_boundCounts[id] ?? 0) > 0;
  }

  int _boundCountFor(StremioMeta item) {
    final id = _imdbOf(item);
    return id == null ? 0 : (_boundCounts[id] ?? 0);
  }

  /// Re-read how many pinned sources each currently-displayed title has. Called
  /// after sections load and after any bind/unbind/playback.
  Future<void> _refreshBoundSources() async {
    final counts = <String, int>{};
    final seen = <String>{};
    // Cover every on-screen tile that renders a bound badge: catalog sections
    // AND the Continue Watching rows (whose titles may not appear in any
    // section, so editing their sources must still refresh the CW card badge).
    final items = [
      for (final section in _sections) ...section.items,
      ..._cwMovies,
      ..._cwSeries,
      ..._traktMovies,
      ..._traktSeries,
    ];
    for (final item in items) {
      final imdb = _imdbOf(item);
      if (imdb == null || !seen.add(imdb)) continue;
      final n = (await SeriesSourceService.getSources(imdb)).length;
      if (n > 0) counts[imdb] = n;
    }
    if (!mounted) return;
    setState(
      () => _boundCounts
        ..clear()
        ..addAll(counts),
    );
  }

  /// PikPak is "only" when it's enabled and no add/resolve provider has a key.
  Future<void> _refreshPikpakOnly() async {
    final pikpak = await StorageService.getPikPakEnabled();
    final rd = await StorageService.getApiKey();
    final tb = await StorageService.getTorboxApiKey();
    final pm = await StorageService.getPremiumizeApiKey();
    final ad = await StorageService.getAllDebridApiKey();
    final anyOther =
        (rd != null && rd.isNotEmpty) ||
        (tb != null && tb.isNotEmpty) ||
        (pm != null && pm.isNotEmpty) ||
        (ad != null && ad.isNotEmpty);
    final onlyPikpak = pikpak && !anyOther;
    if (mounted && onlyPikpak != _pikpakOnly) {
      setState(() => _pikpakOnly = onlyPikpak);
    }
  }

  /// Load the Continue Watching row from the shared local store. Mirrors
  /// Home's join (item list + per-title playback progress) but is read-only —
  /// it never writes, so Home's row is untouched. Safe to call repeatedly
  /// (e.g. after returning from a detail/playback).
  Future<void> _loadContinueWatching() async {
    final token = ++_cwLoadToken;
    final enabled = await StorageService.getHomeContinueWatchingEnabled();
    if (!mounted || token != _cwLoadToken) return;
    if (!enabled) {
      // Free the focus nodes too — otherwise they linger allocated until
      // dispose while the rows are hidden.
      _syncCwNodes(_cwMovieNodes, 0, 'movie');
      _syncCwNodes(_cwSeriesNodes, 0, 'series');
      setState(() {
        _cwEnabled = false;
        _cwMovies = [];
        _cwSeries = [];
        _cwAll = [];
        _cwIds.clear();
        _cwProgress.clear();
        _cwEpisode.clear();
        _cwAddonId.clear();
      });
      return;
    }

    final raw = await StorageService.getContinueWatchingItems();
    final items = <StremioMeta>[];
    final progress = <String, double>{};
    final episode = <String, String>{};
    final ids = <String>{};
    final addonIds = <String, String?>{};
    for (final m in raw) {
      final imdbId = m['imdbId'] as String?;
      if (imdbId == null || imdbId.isEmpty) continue;
      final type = (m['contentType'] as String?) ?? 'movie';
      items.add(
        StremioMeta(
          id: imdbId,
          imdbId: imdbId,
          type: type,
          name: (m['title'] as String?) ?? 'Untitled',
          poster: m['posterUrl'] as String?,
          year: m['year'] as String?,
        ),
      );
      ids.add(imdbId);
      addonIds[imdbId] = m['addonId'] as String?;

      // Watched fraction — joined from the playback-state store, exactly like
      // HomeContinueWatchingSection (finished episodes count as 100%).
      double? pct;
      if (type == 'series') {
        final lastEp = await StorageService.getLastPlayedEpisodeByImdbId(
          imdbId,
        );
        if (lastEp != null) {
          final finished = lastEp['finished'] == true;
          final posMs = lastEp['positionMs'] as int? ?? 0;
          final durMs = lastEp['durationMs'] as int? ?? 1;
          if (durMs > 0) {
            pct = finished ? 100.0 : (posMs / durMs * 100).clamp(0.0, 100.0);
          }
          final se = _seLabel(
            lastEp['season'] as int?,
            lastEp['episode'] as int?,
          );
          if (se != null) episode[imdbId] = se;
        }
      } else {
        final state = await StorageService.getVideoPlaybackStateByImdbId(
          imdbId,
        );
        if (state != null) {
          final posMs = state['positionMs'] as int? ?? 0;
          final durMs = state['durationMs'] as int? ?? 1;
          if (durMs > 0) pct = (posMs / durMs * 100).clamp(0.0, 100.0);
        }
      }
      if (pct != null) progress[imdbId] = pct / 100.0;
    }

    // Bail if a newer load superseded this one while we were awaiting — never
    // dispose/replace nodes or state a later run already committed.
    if (!mounted || token != _cwLoadToken) return;

    // Split into two recency-ordered rows; `items` is already most-recent-first.
    final movies = items.where((m) => m.type != 'series').toList();
    final series = items.where((m) => m.type == 'series').toList();
    // Keep each row's focus-node list length in sync with its item count. Only
    // rebuild when the count changes (a plain refresh keeps the same nodes so
    // an active TV focus isn't dropped).
    _syncCwNodes(_cwMovieNodes, movies.length, 'movie');
    _syncCwNodes(_cwSeriesNodes, series.length, 'series');

    setState(() {
      _cwEnabled = true;
      _cwMovies = movies;
      _cwSeries = series;
      _cwAll = items;
      _cwIds
        ..clear()
        ..addAll(ids);
      _cwProgress
        ..clear()
        ..addAll(progress);
      _cwEpisode
        ..clear()
        ..addAll(episode);
      _cwAddonId
        ..clear()
        ..addAll(addonIds);
    });
    _maybeAutoFocusBoard();
  }

  /// Resize a Continue Watching row's focus-node list to [count], reusing the
  /// existing nodes when the length already matches.
  void _syncCwNodes(List<FocusNode> nodes, int count, String tag) {
    if (nodes.length == count) return;
    for (final n in nodes) {
      n.dispose();
    }
    nodes
      ..clear()
      ..addAll(
        List.generate(
          count,
          (i) => FocusNode(debugLabel: 'search_cw_${tag}_$i'),
        ),
      );
  }

  /// Focus a card in the Continue Watching row at [cwIndex] (index into the
  /// visible CW rows), clamping the column to that row's length.
  void _focusCwRow(int cwIndex, int column) {
    final rows = _cwRows;
    if (cwIndex < 0 || cwIndex >= rows.length) return;
    final nodes = rows[cwIndex].nodes;
    if (nodes.isEmpty) return;
    nodes[column.clamp(0, nodes.length - 1)].requestFocus();
  }

  // The leading favourites rows (between Continue Watching and the catalog) are
  // only shown on the board, never over search results — same gate as
  // [_cwVisible]. Each has its own visibility so an empty source just drops out.
  bool get _iptvFavVisible =>
      _iptvFavChannels.isNotEmpty &&
      _catalogQuery.isEmpty &&
      !_catalogSearching;
  bool get _tvFavVisible =>
      _tvFavChannels.isNotEmpty && _catalogQuery.isEmpty && !_catalogSearching;
  bool get _stvFavVisible =>
      _stvFavChannels.isNotEmpty && _catalogQuery.isEmpty && !_catalogSearching;
  bool get _playlistFavVisible =>
      _playlistItems.isNotEmpty && _catalogQuery.isEmpty && !_catalogSearching;

  /// The visible favourites rows in render order: Playlist, Debrify TV, Stremio
  /// TV, then IPTV. This is the single source of truth for both rendering
  /// ([_buildBoard]) and the index-based DPAD focus wiring below, so the two
  /// never drift out of sync.
  List<_FavKind> get _favRowKinds => [
    if (_playlistFavVisible) _FavKind.playlist,
    if (_tvFavVisible) _FavKind.debrify,
    if (_stvFavVisible) _FavKind.stremio,
    if (_iptvFavVisible) _FavKind.iptv,
  ];

  int get _favRowCount => _favRowKinds.length;
  bool get _anyFavVisible => _favRowKinds.isNotEmpty;

  /// The focus-node list backing a favourites row of the given [kind].
  List<FocusNode> _favNodesFor(_FavKind kind) {
    switch (kind) {
      case _FavKind.iptv:
        return _iptvFavNodes;
      case _FavKind.debrify:
        return _tvFavNodes;
      case _FavKind.stremio:
        return _stvFavNodes;
      case _FavKind.playlist:
        return _playlistFavNodes;
    }
  }

  /// Focus a card in the favourites row at [favIndex] (index into the visible
  /// favourites rows), clamping the column to that row's length.
  void _focusFavRowAt(int favIndex, int column) {
    final kinds = _favRowKinds;
    if (favIndex < 0 || favIndex >= kinds.length) return;
    final nodes = _favNodesFor(kinds[favIndex]);
    if (nodes.isEmpty) return;
    nodes[column.clamp(0, nodes.length - 1)].requestFocus();
  }

  /// DPAD-up target for a favourites row: the previous favourites row, else the
  /// last Continue Watching row, else off the top of the board (to the sidebar).
  VoidCallback _favRowOnUp(int favIndex, int cwCount, int column) =>
      favIndex > 0
      ? () => _focusFavRowAt(favIndex - 1, column)
      : (cwCount > 0
            ? () => _focusCwRow(cwCount - 1, column)
            : () => _leaveBoardTop());

  /// DPAD-down target for a favourites row: the next favourites row, else the
  /// first catalog row (a no-op if none have loaded yet).
  VoidCallback _favRowOnDown(int favIndex, int column) =>
      favIndex < _favRowCount - 1
      ? () => _focusFavRowAt(favIndex + 1, column)
      : () => _focusRow(0, column);

  /// Load the user's starred Debrify TV channels for the leading favourites row.
  /// Silently leaves the row empty on any error (it just won't render).
  Future<void> _loadTvFavorites() async {
    try {
      final ids = await StorageService.getDebrifyTvFavoriteChannelIds();
      if (ids.isEmpty) {
        if (!mounted) return;
        setState(() => _tvFavChannels = const []);
        _syncTvFavNodes();
        return;
      }
      final records = await DebrifyTvRepository.instance.fetchAllChannels();
      // fetchAllChannels() is already ordered by channel number; preserve that
      // order (matching the Home row) rather than a redundant, non-stable
      // re-sort that could shuffle channels sharing channelNumber 0.
      final favs = records
          .map(DebrifyTvChannel.fromRecord)
          .where((c) => ids.contains(c.id))
          .toList();
      if (!mounted) return;
      setState(() => _tvFavChannels = favs);
      _syncTvFavNodes();
      _maybeAutoFocusBoard();
    } catch (_) {
      // Favourites row just stays hidden.
    }
  }

  /// Grow/shrink the favourites row's focus nodes to match the channel count.
  void _syncTvFavNodes() {
    while (_tvFavNodes.length < _tvFavChannels.length) {
      _tvFavNodes.add(
        FocusNode(debugLabel: 'search_tvfav_${_tvFavNodes.length}'),
      );
    }
    while (_tvFavNodes.length > _tvFavChannels.length) {
      _tvFavNodes.removeLast().dispose();
    }
  }

  /// Launch a Debrify TV channel (same path the Home screen uses): hand off to
  /// the live player if it's mounted, else queue an auto-play and switch tabs.
  void _playChannel(DebrifyTvChannel channel) {
    if (MainPageBridge.watchDebrifyTvChannel != null) {
      MainPageBridge.watchDebrifyTvChannel!(channel.id);
      return;
    }
    MainPageBridge.notifyDebrifyTvChannelToAutoPlay(channel.id);
    MainPageBridge.switchTab?.call(3); // 3 = Debrify TV (see main.dart _pages)
  }

  /// Load the user's starred Stremio TV channels for the leading favourites row.
  /// Mirrors the Home section: discover all channels, keep the favourited ones
  /// (preserving discovery order), then fetch their items so each card can show
  /// a now-playing poster. Silently leaves the row empty on any error.
  Future<void> _loadStremioTvFavorites() async {
    try {
      final ids = await StorageService.getStremioTvFavoriteChannelIds();
      if (ids.isEmpty) {
        if (!mounted) return;
        setState(() => _stvFavChannels = const []);
        _syncStvFavNodes();
        return;
      }
      final rotations = await Future.wait([
        StorageService.getStremioTvRotationMinutes(),
        StorageService.getStremioTvSeriesRotationMinutes(),
      ]);
      final rotation = rotations[0];
      final seriesRotation = rotations[1];
      final all = await StremioTvService.instance.discoverChannels();
      final favs = all.where((c) => ids.contains(c.id)).toList();
      await StremioTvService.instance.loadAllChannelItems(favs);
      if (!mounted) return;
      setState(() {
        _stvRotationMinutes = rotation;
        _stvSeriesRotationMinutes = seriesRotation;
        _stvFavChannels = favs;
      });
      _syncStvFavNodes();
      _maybeAutoFocusBoard();
    } catch (_) {
      // Favourites row just stays hidden.
    }
  }

  void _syncStvFavNodes() {
    while (_stvFavNodes.length < _stvFavChannels.length) {
      _stvFavNodes.add(
        FocusNode(debugLabel: 'search_stvfav_${_stvFavNodes.length}'),
      );
    }
    while (_stvFavNodes.length > _stvFavChannels.length) {
      _stvFavNodes.removeLast().dispose();
    }
  }

  /// First of [a], [b] that is a non-empty string, else null.
  String? _firstNonEmpty(String? a, String? b) {
    if (a != null && a.isNotEmpty) return a;
    if (b != null && b.isNotEmpty) return b;
    return null;
  }

  /// The now-playing item for a Stremio TV channel, using the same time-based
  /// rotation as the Home / Stremio TV screens (series rotate on their own
  /// cadence). Null when the channel has no loaded items.
  StremioTvNowPlaying? _stvNowPlaying(StremioTvChannel channel) {
    return StremioTvService.instance.getNowPlaying(
      channel,
      rotationMinutes: channel.type == 'series'
          ? _stvSeriesRotationMinutes
          : _stvRotationMinutes,
    );
  }

  /// Open a Stremio TV channel (same path the Home screen uses): hand off to the
  /// live player if it's mounted, else queue an auto-play and switch tabs.
  void _playStremioTvChannel(StremioTvChannel channel) {
    if (MainPageBridge.watchStremioTvChannel != null) {
      MainPageBridge.watchStremioTvChannel!(channel.id);
      return;
    }
    MainPageBridge.notifyStremioTvChannelToAutoPlay(channel.id);
    MainPageBridge.switchTab?.call(9); // 9 = Stremio TV (see main.dart _pages)
  }

  /// Load the user's starred IPTV channels for the leading favourites row.
  /// Favourites are stored as a url → {name, logoUrl, group} map, so rebuild
  /// [IptvChannel] objects from it (mirroring the Home section). Sorted by name.
  Future<void> _loadIptvFavorites() async {
    try {
      final map = await StorageService.getIptvFavoriteChannels();
      if (map.isEmpty) {
        if (!mounted) return;
        setState(() => _iptvFavChannels = const []);
        _syncIptvFavNodes();
        return;
      }
      final favs =
          map.entries.map((e) {
            final meta = e.value;
            return IptvChannel(
              name: meta['name'] as String? ?? 'Unknown Channel',
              url: e.key,
              logoUrl: meta['logoUrl'] as String?,
              group: meta['group'] as String?,
              duration: -1, // live stream
              attributes: const {},
            );
          }).toList()..sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          );
      if (!mounted) return;
      setState(() => _iptvFavChannels = favs);
      _syncIptvFavNodes();
      _maybeAutoFocusBoard();
    } catch (_) {
      // Favourites row just stays hidden.
    }
  }

  void _syncIptvFavNodes() {
    while (_iptvFavNodes.length < _iptvFavChannels.length) {
      _iptvFavNodes.add(
        FocusNode(debugLabel: 'search_iptvfav_${_iptvFavNodes.length}'),
      );
    }
    while (_iptvFavNodes.length > _iptvFavChannels.length) {
      _iptvFavNodes.removeLast().dispose();
    }
  }

  /// Play an IPTV favourite. Unlike the TV channels there's no bridge/tab
  /// handoff — the stream launches directly in the player (same as Home).
  void _playIptvChannel(IptvChannel channel) {
    VideoPlayerLauncher.push(
      context,
      VideoPlayerLaunchArgs(
        videoUrl: channel.url,
        title: channel.name,
        subtitle: channel.group ?? 'IPTV',
        viewMode: PlaylistViewMode.sorted,
      ),
    );
  }

  /// Load the user's saved playlist items for the leading Playlist row. Applies
  /// poster overrides and resume progress (same as the Home playlist section),
  /// newest first. Silently leaves the row empty on any error.
  Future<void> _loadPlaylistFavorites() async {
    try {
      final results = await Future.wait([
        StorageService.getPlaylistItemsRaw(),
        StorageService.getPlaylistFavoriteKeys(),
        StorageService.getAllPlaylistPosterOverrides(),
      ]);
      final items = results[0] as List<Map<String, dynamic>>;
      final favKeys = results[1] as Set<String>;
      final overrides = results[2] as Map<String, String>;

      // Newest first (by addedAt), matching the Home playlist section.
      items.sort((a, b) {
        final at = a['addedAt'] as int? ?? 0;
        final bt = b['addedAt'] as int? ?? 0;
        return bt.compareTo(at);
      });
      // Apply any per-item poster override in a single pass.
      for (final item in items) {
        final key = StorageService.getPlaylistItemUniqueKey(item);
        final ov = overrides[key];
        if (ov != null && ov.isNotEmpty) item['posterUrl'] = ov;
      }

      final progress = await StorageService.buildPlaylistProgressMap(items);
      if (!mounted) return;
      setState(() {
        _playlistItems = items;
        _playlistProgress = progress;
        _playlistFavKeys = favKeys;
      });
      _syncPlaylistFavNodes();
      _maybeAutoFocusBoard();
    } catch (_) {
      // Row just stays hidden.
    }
  }

  void _syncPlaylistFavNodes() {
    while (_playlistFavNodes.length < _playlistItems.length) {
      _playlistFavNodes.add(
        FocusNode(debugLabel: 'search_playlistfav_${_playlistFavNodes.length}'),
      );
    }
    while (_playlistFavNodes.length > _playlistItems.length) {
      final removed = _playlistFavNodes.removeLast();
      // Unlike the other fav rows, this one deletes items in-row — so the card
      // being trimmed can be the one that currently holds DPAD focus (delete the
      // focused last card). Disposing a focused node strands focus on a disposed
      // object; hand it to the new last card first (or let it fall out cleanly
      // when the row is now empty).
      final hadFocus = removed.hasFocus;
      removed.dispose();
      if (hadFocus && _playlistFavNodes.isNotEmpty) {
        _playlistFavNodes.last.requestFocus();
      }
    }
  }

  /// Resume fraction (0..1) for a playlist item, or null if it has no progress.
  /// [StorageService.buildPlaylistProgressMap] emits `positionMs`/`durationMs`
  /// (the Home section reads `position`/`duration`, which are never present — so
  /// its bar silently never draws; read the real keys here so ours works).
  double? _playlistProgressFor(Map<String, dynamic> item) {
    final key = StorageService.computePlaylistDedupeKey(item);
    final p = _playlistProgress[key];
    if (p == null) return null;
    final position = (p['positionMs'] as num?)?.toInt();
    final duration = (p['durationMs'] as num?)?.toInt();
    if (position == null || duration == null || duration <= 0) return null;
    return (position / duration).clamp(0.0, 1.0);
  }

  /// The full action menu for a playlist item — the same set of actions as the
  /// Home playlist section (Home is being phased out, so this row is a complete
  /// playlist manager on its own).
  Future<void> _onPlaylistItemTap(Map<String, dynamic> item) async {
    if (!mounted) return;
    final dedupeKey = StorageService.computePlaylistDedupeKey(item);
    final isFavorited = _playlistFavKeys.contains(dedupeKey);
    final hasProgress = _playlistProgress.containsKey(dedupeKey);
    final isCollection = (item['kind'] as String?) != 'single';
    final title = (item['title'] as String?) ?? 'Unknown';
    final tv = widget.isTelevision;

    final choice = await showDialog<String>(
      context: context,
      builder: (dialogContext) => Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 380),
            decoration: BoxDecoration(
              color: const Color(0xFF141824),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Divider(height: 1, color: Colors.white.withValues(alpha: 0.06)),
                _PlaylistMenuItem(
                  icon: Icons.play_circle_filled_rounded,
                  label: 'Play',
                  subtitle: 'Start playback',
                  color: const Color(0xFF10B981),
                  autofocus: true,
                  isTelevision: tv,
                  onTap: () => Navigator.pop(dialogContext, 'play'),
                ),
                if (isCollection)
                  _PlaylistMenuItem(
                    icon: Icons.shuffle_rounded,
                    label: 'Play Random',
                    subtitle: 'Start a random file from this collection',
                    color: const Color(0xFFA78BFA),
                    isTelevision: tv,
                    onTap: () => Navigator.pop(dialogContext, 'play_random'),
                  ),
                _PlaylistMenuItem(
                  icon: Icons.folder_open_rounded,
                  label: 'View Files',
                  subtitle: 'Browse folder contents',
                  color: const Color(0xFF818CF8),
                  isTelevision: tv,
                  onTap: () => Navigator.pop(dialogContext, 'view_files'),
                ),
                _PlaylistMenuItem(
                  icon: isFavorited
                      ? Icons.star_rounded
                      : Icons.star_border_rounded,
                  label: isFavorited
                      ? 'Remove from Favorites'
                      : 'Add to Favorites',
                  subtitle: isFavorited
                      ? 'Remove from your favorites list'
                      : 'Add to your favorites list',
                  color: const Color(0xFFFFD700),
                  isTelevision: tv,
                  onTap: () => Navigator.pop(dialogContext, 'favorite'),
                ),
                if (hasProgress)
                  _PlaylistMenuItem(
                    icon: Icons.replay_rounded,
                    label: 'Clear Progress',
                    subtitle: 'Reset playback progress',
                    color: const Color(0xFF60A5FA),
                    isTelevision: tv,
                    onTap: () => Navigator.pop(dialogContext, 'clear_progress'),
                  ),
                _PlaylistMenuItem(
                  icon: Icons.launch_rounded,
                  label: 'Launch on Startup',
                  subtitle: 'Auto-play this item when Debrify opens',
                  color: const Color(0xFFEF4444),
                  subtitleColor: const Color(0xFFFCA5A5),
                  isTelevision: tv,
                  onTap: () =>
                      Navigator.pop(dialogContext, 'launch_on_startup'),
                ),
                Divider(height: 1, color: Colors.white.withValues(alpha: 0.06)),
                _PlaylistMenuItem(
                  icon: Icons.delete_outline_rounded,
                  label: 'Delete',
                  subtitle: 'Remove from playlist',
                  color: const Color(0xFFEF4444),
                  isTelevision: tv,
                  onTap: () => Navigator.pop(dialogContext, 'delete'),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );

    if (choice == null || !mounted) return;
    switch (choice) {
      case 'play':
        _playPlaylistItem(item);
        break;
      case 'play_random':
        _playPlaylistItem(item, playRandom: true);
        break;
      case 'view_files':
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => PlaylistContentViewScreen(playlistItem: item),
          ),
        );
        // Progress / poster may have changed while browsing.
        _loadPlaylistFavorites();
        break;
      case 'favorite':
        await StorageService.setPlaylistItemFavorited(item, !isFavorited);
        HapticFeedback.mediumImpact();
        _loadPlaylistFavorites();
        break;
      case 'clear_progress':
        // Empty (not 'Unknown') fallback so a null-titled item clears nothing
        // instead of fuzzy-matching the literal word 'unknown' and wiping an
        // unrelated item's resume point — matches the Home section.
        await StorageService.clearPlaylistProgress(
          title: (item['title'] as String?) ?? '',
        );
        HapticFeedback.mediumImpact();
        _loadPlaylistFavorites();
        break;
      case 'launch_on_startup':
        await _setPlaylistLaunchOnStartup(item, dedupeKey);
        break;
      case 'delete':
        await _confirmDeletePlaylistItem(item);
        break;
    }
  }

  Future<void> _playPlaylistItem(
    Map<String, dynamic> item, {
    bool playRandom = false,
  }) async {
    if (_playlistLaunching) return;
    _playlistLaunching = true;
    try {
      await PlaylistPlayerService.play(context, item, playRandom: playRandom);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to play: $e')));
    } finally {
      if (mounted) _playlistLaunching = false;
    }
  }

  Future<void> _setPlaylistLaunchOnStartup(
    Map<String, dynamic> item,
    String dedupeKey,
  ) async {
    await Future.wait([
      StorageService.setStartupAutoLaunchEnabled(true),
      StorageService.setStartupMode('playlist'),
      StorageService.setStartupPlaylistItemId(dedupeKey),
    ]);
    if (!mounted) return;
    final title = (item['title'] as String?) ?? 'Playlist item';
    HapticFeedback.mediumImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('"$title" will launch automatically on startup')),
    );
  }

  Future<void> _confirmDeletePlaylistItem(Map<String, dynamic> item) async {
    final title = (item['title'] as String?) ?? 'this item';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete?'),
        content: Text('Remove "$title" from your playlist?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: HomeTheme.danger),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      final dedupeKey = StorageService.computePlaylistDedupeKey(item);
      await StorageService.removePlaylistItemByKey(dedupeKey);
      HapticFeedback.mediumImpact();
      _loadPlaylistFavorites();
    }
  }

  /// Resolve the addon that a Continue Watching title should route through.
  /// Prefers the stored source addon; falls back to any homepage addon, then a
  /// minimal placeholder so Play still works even if the addon is gone.
  StremioAddon _addonForContinue(String? addonId) {
    if (addonId != null && _addonsById.containsKey(addonId)) {
      return _addonsById[addonId]!;
    }
    if (_homeSections.isNotEmpty) return _homeSections.first.addon;
    return StremioAddon(
      id: addonId ?? 'continue_watching',
      name: 'Continue Watching',
      manifestUrl: '',
      baseUrl: '',
    );
  }

  /// Open a Continue Watching title as a normal detail page (no Home-style
  /// list menu). The detail's action row + a "Remove from Continue Watching"
  /// action are wired via [_openItem] (which detects membership in [_cwIds]).
  void _openContinueItem(StremioMeta item) {
    _openItem(item, _addonForContinue(_cwAddonId[item.imdbId]));
  }

  /// Long-press quick-play for a Continue Watching title — resumes directly
  /// (series resume the last-played episode) without opening the detail.
  void _onContinuePlay(StremioMeta item) {
    _onCatalogPlay(item, _addonForContinue(_cwAddonId[item.imdbId]));
  }

  // ── Trakt Continue Watching ───────────────────────────────────────────────

  /// Fetch the Trakt "Continue Watching" rows (in-progress movies + up-next
  /// episodes) from the connected account. Network-heavy (the shows path is
  /// ~2 + N calls), so this runs once on init / integration change and caches
  /// in memory — never on every rebuild. Token-guarded against overlap; hides
  /// the rows when Trakt isn't connected.
  /// [refreshBound] runs a bound-source refresh at the end; pass false when the
  /// caller already refreshes bound sources itself (avoids a double pass).
  Future<void> _loadTraktContinueWatching({bool refreshBound = true}) async {
    final token = ++_traktCwToken;
    // Mark the fetch in flight so the skeleton slot reserves while it runs (only
    // reserves when there are no real rows yet — see [_traktReserving]). Plain
    // assignment, not setState: the sync prefix runs during initState on cold
    // start, and the first build reads the field anyway.
    _traktCwLoading = true;
    final List<TraktContinueWatchingItem> movies;
    final List<TraktContinueWatchingItem> shows;
    try {
      final authed = await TraktService.instance.isAuthenticated();
      if (!mounted || token != _traktCwToken) return;
      if (!authed) {
        _syncCwNodes(_traktMovieNodes, 0, 'tmovie');
        _syncCwNodes(_traktSeriesNodes, 0, 'tseries');
        setState(() {
          _traktCwLoading = false;
          _traktMovies = [];
          _traktSeries = [];
          _traktAll = [];
          _traktProgress.clear();
          _traktEpisode.clear();
          _traktByImdb.clear();
        });
        return;
      }
      final cw = TraktContinueWatchingService.instance;
      movies = await cw.fetchMovies();
      shows = await cw.fetchShows();
    } catch (e) {
      // Leave any existing rows in place on a transient Trakt/network error,
      // but stop reserving the skeleton slot so it doesn't shimmer forever.
      debugPrint('SearchScreen: Trakt continue-watching load failed: $e');
      if (mounted && token == _traktCwToken) {
        setState(() => _traktCwLoading = false);
      }
      return;
    }
    if (!mounted || token != _traktCwToken) return;

    final movieMetas = <StremioMeta>[];
    final showMetas = <StremioMeta>[];
    final progress = <String, double>{};
    final episode = <String, String>{};
    final byImdb = <String, TraktContinueWatchingItem>{};
    void ingest(List<TraktContinueWatchingItem> items, List<StremioMeta> into) {
      for (final it in items) {
        final id = it.id;
        if (id.isEmpty || byImdb.containsKey(id)) continue; // dedup by imdbId
        into.add(it.meta);
        byImdb[id] = it;
        final p = it.progress;
        if (p != null) progress[id] = (p / 100).clamp(0.0, 1.0);
        final se = _seLabel(it.season, it.episode);
        if (se != null) episode[id] = se;
      }
    }

    ingest(movies, movieMetas);
    ingest(shows, showMetas);
    // Merge into one last-watched-ordered list for the See-All grid: sort by
    // Trakt's paused_at (newest first), items without a paused_at (recent-shows
    // augmentation) sort last. Ties (incl. two null paused_ats) fall back to the
    // original movies-then-shows order so the sort is deterministic (Dart's
    // List.sort isn't stable).
    final allMetas = [...movieMetas, ...showMetas];
    final origIndex = <StremioMeta, int>{
      for (var i = 0; i < allMetas.length; i++) allMetas[i]: i,
    };
    allMetas.sort((a, b) {
      final pa = byImdb[a.imdbId]?.pausedAtMs;
      final pb = byImdb[b.imdbId]?.pausedAtMs;
      if (pa != null && pb != null) {
        final c = pb.compareTo(pa);
        if (c != 0) return c;
      } else if (pa == null && pb != null) {
        return 1;
      } else if (pa != null && pb == null) {
        return -1;
      }
      return origIndex[a]!.compareTo(origIndex[b]!);
    });
    _syncCwNodes(_traktMovieNodes, movieMetas.length, 'tmovie');
    _syncCwNodes(_traktSeriesNodes, showMetas.length, 'tseries');
    setState(() {
      _traktCwLoading = false;
      _traktMovies = movieMetas;
      _traktSeries = showMetas;
      _traktAll = allMetas;
      _traktProgress
        ..clear()
        ..addAll(progress);
      _traktEpisode
        ..clear()
        ..addAll(episode);
      _traktByImdb
        ..clear()
        ..addAll(byImdb);
    });
    _maybeAutoFocusBoard();
    if (refreshBound) unawaited(_refreshBoundSources());
  }

  /// Open a Trakt Continue Watching title as a normal detail page.
  void _openTraktItem(StremioMeta item) {
    _openItem(
      item,
      _addonForContinue(item.sourceAddon?.id),
      isTraktSource: true,
    );
  }

  /// Resume a Trakt Continue Watching title — resolves the paused/next episode
  /// (an extra Trakt call for series) and plays.
  Future<void> _playTraktItem(StremioMeta item) async {
    final cwItem = _traktByImdb[_imdbOf(item)];
    if (cwItem == null) {
      _openTraktItem(item);
      return;
    }
    final sel = await TraktContinueWatchingService.instance.selectionForItem(
      cwItem,
    );
    if (!mounted) return;
    if (sel == null) {
      _snack("Couldn't resolve where to resume \"${item.name}\".");
      return;
    }
    _playSelection(sel);
  }

  /// Detail-screen action for a Continue Watching title. Only handles removal;
  /// pops the detail and lets the push's `.then` refresh the row.
  Future<void> _handleContinueDetailAction(
    TraktItemMenuAction action,
    String imdbId,
  ) async {
    if (action != TraktItemMenuAction.removeFromPlayback) return;
    await StorageService.removeContinueWatchingItem(imdbId);
    await StorageService.clearPlaybackStateByImdbId(imdbId);
    if (!mounted) return;
    Navigator.of(context).pop(); // close the detail; `.then` reloads the row
    _snack('Removed from Continue Watching');
  }

  /// Swap the displayed sections (homepage or search results): rebuild the
  /// per-row focus nodes and reset the hero to the first item.
  void _applySections(List<CatalogSection> sections) {
    _disposeNodes();
    for (final section in sections) {
      _rowNodes.add(
        List.generate(
          section.items.length,
          (i) => FocusNode(debugLabel: 'search_r${_rowNodes.length}_c$i'),
        ),
      );
    }
    setState(() => _sections = sections);
    unawaited(_refreshBoundSources());
    // Seed the hero with the first item so it isn't blank before DPAD focus
    // lands (see [_heroActive] for when the hero is shown).
    if (_heroActive) {
      final first = sections.isNotEmpty && sections.first.items.isNotEmpty
          ? sections.first.items.first
          : null;
      _heroItem.value = first;
      _heroEnriched.value = null;
      if (first != null) _enrichHero(first);
    }
  }

  /// Cross-addon catalog search, grouped as one horizontal row per addon so it
  /// matches the board (not a merged grid).
  Future<void> _runCatalogSearch(String query) async {
    final token = ++_catalogSearchToken;
    setState(() {
      _catalogQuery = query;
      _catalogSearching = true;
    });
    try {
      final addons = (await _stremio.getBrowseableOrSearchableAddons())
          .where((a) => a.hasSearchableCatalogs)
          .toList();
      // One row PER searchable catalog (so Movies and Series land in separate
      // categorised rows, like Stremio) instead of one merged row per addon.
      final tasks = <Future<CatalogSection?>>[];
      for (final addon in addons) {
        for (final catalog in addon.catalogs.where((c) => c.supportsSearch)) {
          tasks.add(() async {
            try {
              final items = await _stremio.searchSingleCatalog(
                addon,
                catalog,
                query,
              );
              if (items.isEmpty) return null;
              return CatalogSection(
                title: '${addon.name}: ${catalog.name}',
                addon: addon,
                catalog: catalog,
                items: items,
              );
            } catch (_) {
              return null;
            }
          }());
        }
      }
      final raw = await Future.wait(tasks);
      if (!mounted || token != _catalogSearchToken) return;
      setState(() => _catalogSearching = false);
      _applySections(raw.whereType<CatalogSection>().toList());
    } catch (_) {
      if (!mounted || token != _catalogSearchToken) return;
      setState(() => _catalogSearching = false);
      // Clear the previous query's rows + hero so a failed search doesn't leave
      // stale results (and now a stale hero) mismatching the current query —
      // same reset as a successful-but-empty search.
      _applySections(const []);
    }
  }

  /// Cancel any pending search and return to the homepage board.
  void _restoreHome() {
    _catalogSearchToken++;
    setState(() {
      _catalogQuery = '';
      _catalogSearching = false;
    });
    _applySections(_homeSections);
    _maybeAutoFillBoard();
  }

  // ── Focus entry ──────────────────────────────────────────────────────────

  /// Place — or re-anchor — the board's auto-focus after content loads, so
  /// arriving on the Home tab lands on a card (no stray arrow press) and then
  /// *settles to the top*: focus the best card available now, and as higher rows
  /// arrive (Trakt filling its reserved slot, local Continue Watching) slide up
  /// to the new top card while the user is idle. See [_autoFocusedNode] /
  /// [_autoFocusSettled] for the state machine.
  ///
  /// TV-only, homepage board only. Deferred a frame so the target row is mounted.
  void _maybeAutoFocusBoard() {
    if (_autoFocusSettled || _autoFocusScheduled) return;
    if (!widget.isTelevision) return;
    if (widget.searchMode || widget.discoverMode) return;
    _autoFocusScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Coalesced pass: reads the final top after every same-frame load's
      // setState has applied, so multiple loads don't race.
      _autoFocusScheduled = false;
      if (!mounted || _autoFocusSettled) return;
      if (widget.searchMode || widget.discoverMode) return;
      // Only when this is the tab the user is actually looking at. During the
      // ~350ms tab cross-fade the outgoing board is still mounted and shares the
      // ModalRoute, so isCurrent can't tell them apart — the active-tab index
      // can. (main.dart keeps it in lock-step with the rendered tab.)
      if (MainPageBridge.activeTvTabIndex != _tabIndex) return;
      // Don't grab focus if the board isn't the top route — e.g. the user
      // opened a detail page or player and a slow CW/Trakt load only just
      // finished. Stealing focus here would yank it off the pushed screen onto
      // the hidden board below.
      final route = ModalRoute.of(context);
      if (route != null && !route.isCurrent) return;
      if (MainPageBridge.isTvSidebarFocused?.call() ?? false) return;

      final primary = FocusManager.instance.primaryFocus;
      final boardFocused = _boardHasFocus();
      if (_autoFocusedNode == null) {
        // Never placed focus yet. If the user already reached a board card on
        // their own, leave it and latch — nothing to auto-place.
        if (boardFocused) {
          _autoFocusSettled = true;
          return;
        }
      } else if (boardFocused && primary != _autoFocusedNode) {
        // We placed focus earlier and it now sits on a *different* board card —
        // the user has taken control. Stop re-anchoring so we never fight them.
        // (Guarded by boardFocused so our own just-applied requestFocus, or a
        // transient null primaryFocus between loads, can't false-trigger this.)
        _autoFocusSettled = true;
        return;
      }

      final top = _topBoardFocusNode();
      if (top == null) return; // nothing focusable yet — retry on the next load
      if (top == _autoFocusedNode) return; // already anchored to the current top
      top.requestFocus();
      _autoFocusedNode = top;
    });
  }

  /// Whether any focusable element on this screen currently holds focus. Used to
  /// avoid stealing focus from the user in [_maybeAutoFocusBoard].
  bool _boardHasFocus() {
    bool anyOf(List<FocusNode> ns) => ns.any((n) => n.hasFocus);
    if (_searchFocusNode.hasFocus ||
        _modeCatalogNode.hasFocus ||
        _modeKeywordNode.hasFocus ||
        _discSourceNode.hasFocus) {
      return true;
    }
    if (anyOf(_cwMovieNodes) ||
        anyOf(_cwSeriesNodes) ||
        anyOf(_traktMovieNodes) ||
        anyOf(_traktSeriesNodes) ||
        anyOf(_tvFavNodes) ||
        anyOf(_stvFavNodes) ||
        anyOf(_iptvFavNodes) ||
        anyOf(_playlistFavNodes)) {
      return true;
    }
    for (final row in _rowNodes) {
      if (anyOf(row)) return true;
    }
    return false;
  }

  /// The focus node for the board's current top card — the same target
  /// [_focusContent] would pick on the board path (Continue Watching →
  /// favourites → catalog rows), or null if nothing is focusable yet. Skeleton
  /// Trakt rows carry no nodes, so they're naturally skipped: while Trakt is
  /// reserving, the top is whatever real row sits below the skeletons, and once
  /// the real Trakt rows land they become the top. Drives the "settle to the
  /// top" re-anchor in [_maybeAutoFocusBoard].
  FocusNode? _topBoardFocusNode() {
    if (_cwVisible) {
      final rows = _cwRows;
      if (rows.isNotEmpty && rows.first.nodes.isNotEmpty) {
        return rows.first.nodes.first;
      }
    }
    if (_anyFavVisible) {
      final favNodes = _favNodesFor(_favRowKinds.first);
      if (favNodes.isNotEmpty) return favNodes.first;
    }
    if (_rowNodes.isNotEmpty && _rowNodes.first.isNotEmpty) {
      return _rowNodes.first.first;
    }
    return null;
  }

  /// DPAD-up from the top row. On the dedicated Search tab the field sits above
  /// the results, so land there; on the Home-New board there's nothing above, so
  /// hand focus to the sidebar.
  void _leaveBoardTop() {
    if (widget.searchMode) {
      _searchFocusNode.requestFocus();
    } else {
      MainPageBridge.focusTvSidebar?.call();
    }
  }

  void _focusContent() {
    // Discover tab: enter on the Source dropdown (the leading filter); Down from
    // there drops into the grid.
    if (widget.discoverMode) {
      _discSourceNode.requestFocus();
      return;
    }
    // Dedicated Search tab: land on the results when they're on-screen, else the
    // field (the blank prompt has nothing focusable below it). Only focus board
    // rows when a query is actually showing them — otherwise their nodes aren't
    // mounted and focus would be stranded.
    if (widget.searchMode) {
      if (_mode == _Mode.keyword) {
        if (_kwToolbarVisible) {
          _kwToolbarNodes.first.requestFocus();
        } else {
          _searchFocusNode.requestFocus();
        }
        return;
      }
      // Only when results are actually mounted — not mid-search (the spinner is
      // up and _rowNodes still holds the previous/stale set).
      if (_catalogQuery.isNotEmpty &&
          !_catalogSearching &&
          _rowNodes.isNotEmpty &&
          _rowNodes.first.isNotEmpty) {
        _rowNodes.first.first.requestFocus();
      } else {
        _searchFocusNode.requestFocus();
      }
      return;
    }
    if (_mode == _Mode.keyword) {
      // Toolbar + result rows render together, so entering the content lands on
      // the toolbar first (Down then reaches the rows). When it isn't visible
      // (loading / error / pre-search) nothing below is focusable, so keep the
      // search field rather than a stale, detached result node.
      if (_kwToolbarVisible) {
        _kwToolbarNodes.first.requestFocus();
      } else {
        _searchFocusNode.requestFocus();
      }
      return;
    }
    // Same top-of-board target the auto-focus "settle to the top" uses, so
    // remote entry and auto-focus always agree on the landing card.
    final top = _topBoardFocusNode();
    if (top != null) {
      top.requestFocus();
      return;
    }
    // Board tab with nothing focusable (empty catalogs). The search field is in
    // the tree on desktop/mobile (persistent bar) but not on the chrome-free TV
    // board — bounce to the sidebar there so the remote never lands nowhere.
    if (!widget.isTelevision) {
      _searchFocusNode.requestFocus();
    } else {
      MainPageBridge.focusTvSidebar?.call();
    }
  }

  /// Focus the Catalog/Keyword toggle, landing on the segment for the current
  /// mode so its highlight lines up with where the remote cursor sits.
  void _focusModeToggle() {
    (_mode == _Mode.keyword ? _modeKeywordNode : _modeCatalogNode)
        .requestFocus();
  }

  /// Return focus to the search field with the caret at the end of the text, so
  /// leaving the toggle leftward and pressing right again jumps straight back.
  void _focusSearchFieldAtEnd() {
    _searchFocusNode.requestFocus();
    _searchController.selection = TextSelection.collapsed(
      offset: _searchController.text.length,
    );
  }

  /// Whether the keyword results toolbar (Sort/Filters/Sources/…) is on-screen,
  /// so focus can route into it between the search field and the result rows.
  bool get _kwToolbarVisible =>
      _mode == _Mode.keyword &&
      !_kwLoading &&
      _kwError == null &&
      _kwQuery.isNotEmpty;

  void _focusRow(int row, int column) {
    if (row >= _rowNodes.length) {
      // DPAD-down past the last loaded row on TV: pull the next board batch.
      if (_boardHasMore) _loadMoreBoard();
      return;
    }
    if (row < 0) return;
    final nodes = _rowNodes[row];
    if (nodes.isEmpty) return;
    nodes[column.clamp(0, nodes.length - 1)].requestFocus();
  }

  // ── Hero ─────────────────────────────────────────────────────────────────

  /// Whether the hero spotlight is live for the current tab/state: TV-only, on
  /// the board always and on the dedicated Search tab once there are results
  /// (hidden on the blank "type to search" prompt). Single source of truth for
  /// seeding ([_applySections]), focus tracking ([_setHero]) and rendering
  /// ([_buildBoard]) so they can't drift.
  bool get _heroActive =>
      widget.isTelevision && (!widget.searchMode || _catalogQuery.isNotEmpty);

  void _setHero(StremioMeta item) {
    // Off-TV / blank search prompt the hero isn't rendered, so don't track focus
    // or fire the per-item backdrop-enrichment /meta fetch behind it.
    if (!_heroActive) return;
    if (_heroItem.value?.id == item.id) return;
    _heroItem.value = item;
    _heroEnriched.value = null;
    _enrichHero(item);
  }

  /// Debounced backdrop/description enrichment. Catalog list items usually
  /// omit `background`/`description` (they come from the /meta endpoint), so
  /// fetch them lazily — cached in [StremioService], and guarded against the
  /// focus moving on (req id) so a slow fetch never clobbers a newer hero.
  void _enrichHero(StremioMeta item) {
    _heroTimer?.cancel();
    final needsBg = item.background == null || item.background!.isEmpty;
    final needsDesc = item.description == null || item.description!.isEmpty;
    final needsRating = item.imdbRating == null;
    if (!needsBg && !needsDesc && !needsRating) return;
    final imdb = item.imdbId ?? (item.id.startsWith('tt') ? item.id : null);
    if (imdb == null) return;
    final reqId = ++_heroReqId;
    _heroTimer = Timer(const Duration(milliseconds: 300), () async {
      final details = await _stremio.fetchMetaDetails(
        imdbId: imdb,
        type: item.type,
      );
      if (!mounted || reqId != _heroReqId || details == null) return;
      _heroEnriched.value = details;
    });
  }

  // ── Search field ─────────────────────────────────────────────────────────

  void _onQueryChanged(String value) {
    if (_mode != _Mode.catalog) return;
    _catalogDebounce?.cancel();
    _catalogDebounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      final q = value.trim();
      if (q == _catalogQuery) return;
      if (q.isEmpty) {
        _restoreHome();
      } else {
        _runCatalogSearch(q);
      }
    });
  }

  void _onQuerySubmitted(String value) {
    _catalogDebounce?.cancel();
    final q = value.trim();
    if (_mode == _Mode.keyword) {
      _runKeyword(q);
    } else if (q.isEmpty) {
      _restoreHome();
    } else {
      _runCatalogSearch(q);
    }
  }

  void _clearQuery() {
    _catalogDebounce?.cancel();
    _searchController.clear();
    _disposeKwNodes();
    setState(() {
      _kwQuery = '';
      _kwAll = [];
      _kwResults = [];
      _kwCache = {};
      _kwError = null;
    });
    _restoreHome();
  }

  Future<void> _runKeyword(String query) async {
    if (query.isEmpty) return;
    final token = ++_kwSearchToken;
    setState(() {
      _kwLoading = true;
      _kwError = null;
      _kwQuery = query;
      _kwCache = {};
      _kwSelectionMode = false;
      _kwSelected.clear();
    });
    try {
      final result = await TorrentService.searchAllEngines(query);
      // Drop stale results if a newer search started while this was in flight.
      if (!mounted || token != _kwSearchToken) return;
      final torrents = (result['torrents'] as List).cast<Torrent>();
      final engineErrors = result['engineErrors'];
      // Every source errored and nothing came back → surface the failure
      // instead of a misleading "No results" (searchAllEngines fails soft).
      if (torrents.isEmpty && engineErrors is Map && engineErrors.isNotEmpty) {
        setState(() {
          _kwError =
              'Search failed on all sources. Check your connection or '
              'enabled sources and try again.';
          _kwLoading = false;
        });
        return;
      }
      _kwAll = torrents;
      setState(() => _kwLoading = false);
      _recomputeKeyword();
      unawaited(_checkKeywordCache(_kwAll, token));
    } catch (e) {
      if (!mounted || token != _kwSearchToken) return;
      setState(() {
        _kwError = e.toString();
        _kwLoading = false;
      });
    }
  }

  // ── Bulk selection (keyword results) ──────────────────────────────────────
  /// Torrents eligible for bulk actions (excludes direct/external streams).
  List<Torrent> get _kwSelectableResults => _kwResults
      .where((t) => !t.isDirectStream && !t.isExternalStream)
      .toList();

  void _enterKwSelection() {
    // Entering selection swaps the toolbar to 3 pills; if DPAD focus was on the
    // now-gone "Select" pill (index 3), pull it back to the new first pill so
    // the remote doesn't lose focus.
    final refocusToolbar = _kwToolbarNodes.any((n) => n.hasFocus);
    setState(() {
      _kwSelectionMode = true;
      _kwSelected.clear();
    });
    if (refocusToolbar) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _kwToolbarNodes.first.requestFocus();
      });
    }
  }

  void _exitKwSelection() {
    setState(() {
      _kwSelectionMode = false;
      _kwSelected.clear();
    });
  }

  void _toggleKwSelection(Torrent t) {
    setState(() {
      if (_kwSelected.contains(t.infohash)) {
        _kwSelected.remove(t.infohash);
      } else {
        _kwSelected.add(t.infohash);
      }
    });
  }

  void _selectAllKw() {
    setState(() {
      _kwSelected
        ..clear()
        ..addAll(_kwSelectableResults.map((t) => t.infohash));
    });
  }

  /// Clear the selection but stay in selection mode (matches Home's "None").
  void _deselectAllKw() {
    setState(() => _kwSelected.clear());
  }

  bool _kwBulkBusy = false;

  Future<void> _openBulkAdd() async {
    if (_kwBulkBusy) return;
    final chosen = _kwResults
        .where((t) => _kwSelected.contains(t.infohash))
        .toList();
    if (chosen.isEmpty) return;
    _kwBulkBusy = true;
    bool chose = false;
    try {
      chose = await TorrentBulkAddService.showBulkAddDialog(
        context,
        torrents: chosen,
        keyword: _kwQuery,
      );
    } finally {
      _kwBulkBusy = false;
    }
    // Stay in selection mode if the user just dismissed the chooser.
    if (mounted && chose && _kwSelectionMode) _exitKwSelection();
  }

  /// Re-apply filters + sort to the last search's results and rebuild nodes.
  void _recomputeKeyword() {
    final filtered = TorrentFilterMatcher.apply(_kwAll, _kwFilters);
    final sorted = _sortKeyword(filtered);
    _disposeKwNodes();
    for (var i = 0; i < sorted.length; i++) {
      _kwNodes.add(FocusNode(debugLabel: 'kw_$i'));
    }
    setState(() => _kwResults = sorted);
  }

  List<Torrent> _sortKeyword(List<Torrent> list) {
    final l = [...list];
    switch (_kwSort) {
      case 'seeders':
        l.sort((a, b) => b.seeders.compareTo(a.seeders));
        break;
      case 'size':
        l.sort((a, b) => b.sizeBytes.compareTo(a.sizeBytes));
        break;
      case 'date':
        l.sort((a, b) => b.createdUnix.compareTo(a.createdUnix));
        break;
      case 'name':
        l.sort(
          (a, b) => a.displayTitle.toLowerCase().compareTo(
            b.displayTitle.toLowerCase(),
          ),
        );
        break;
      default: // 'relevance' — keep the engine (seeder-deduped) order
        break;
    }
    return l;
  }

  /// Cache-check the results against TorBox/Premiumize (the only providers that
  /// support it) and stamp TB/PM badges onto the rows.
  Future<void> _checkKeywordCache(List<Torrent> torrents, int token) async {
    final hashes = torrents
        .map((t) => t.infohash.toLowerCase())
        .where((h) => h.isNotEmpty)
        .toList();
    if (hashes.isEmpty) return;
    final map = <String, List<String>>{};
    // Only check a provider when the user has cache-checking enabled AND the
    // integration is on AND a key is saved (matches Home's gating).
    try {
      final tb = await StorageService.getTorboxApiKey();
      final enabled =
          await StorageService.getTorboxCacheCheckEnabled() &&
          await StorageService.getTorboxIntegrationEnabled();
      if (enabled && tb != null && tb.isNotEmpty) {
        final cached = await TorboxService.checkCachedTorrents(
          apiKey: tb,
          infoHashes: hashes,
        );
        for (final h in cached) {
          (map[h] ??= <String>[]).add('TB');
        }
      }
    } catch (_) {}
    try {
      final pm = await StorageService.getPremiumizeApiKey();
      final enabled =
          await StorageService.getPremiumizeCacheCheckEnabled() &&
          await StorageService.getPremiumizeIntegrationEnabled();
      if (enabled && pm != null && pm.isNotEmpty) {
        final res = await PremiumizeService.checkCache(pm, hashes);
        for (var i = 0; i < hashes.length && i < res.length; i++) {
          if (res[i]) (map[hashes[i]] ??= <String>[]).add('PM');
        }
      }
    } catch (_) {}
    // Drop badges from a superseded search.
    if (!mounted || token != _kwSearchToken) return;
    setState(() => _kwCache = map);
  }

  Future<void> _openKeywordFilters() async {
    final result = await showDialog<TorrentFilterState>(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        child: TorrentFiltersSheet(initialState: _kwFilters),
      ),
    );
    if (result == null || !mounted) return;
    _kwFilters = result;
    _recomputeKeyword();
  }

  Future<void> _openKeywordSort() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        final scheme = Theme.of(dialogContext).colorScheme;
        Widget tile(String value, String label) => ListTile(
          title: Text(label),
          trailing: _kwSort == value
              ? Icon(Icons.check_rounded, color: scheme.primary)
              : null,
          onTap: () => Navigator.of(dialogContext).pop(value),
        );
        return AlertDialog(
          backgroundColor: scheme.surfaceContainerHigh,
          title: const Text('Sort by'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              tile('relevance', 'Relevance'),
              tile('seeders', 'Seeders'),
              tile('size', 'Size'),
              tile('date', 'Date added'),
              tile('name', 'Name'),
            ],
          ),
        );
      },
    );
    if (choice == null || !mounted) return;
    _kwSort = choice;
    _recomputeKeyword();
  }

  Future<void> _openKeywordSources() async {
    // If the remote was on the toolbar, the re-search below unmounts it (loading
    // spinner) and would strand DPAD focus — so restore it once results return.
    final fromToolbar = _kwToolbarNodes.any((n) => n.hasFocus);
    await showDialog<void>(
      context: context,
      builder: (_) => const _KeywordSourcesDialog(),
    );
    if (!mounted || _kwQuery.isEmpty) return;
    await _runKeyword(_kwQuery); // re-search with the new enabled set
    if (fromToolbar && mounted && _kwToolbarVisible) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _kwToolbarNodes.first.requestFocus();
      });
    }
  }

  void _disposeKwNodes() {
    for (final n in _kwNodes) {
      n.dispose();
    }
    _kwNodes.clear();
  }

  void _switchMode(_Mode mode) {
    if (_mode == mode) return;
    setState(() {
      _mode = mode;
      // Leaving the keyword list drops any in-progress multi-selection.
      _kwSelectionMode = false;
      _kwSelected.clear();
    });
    // Carry the typed query across: if there's text in the box, run the target
    // mode's search immediately instead of showing the empty state.
    final query = _searchController.text.trim();
    if (query.isEmpty) return;
    if (mode == _Mode.keyword) {
      if (query != _kwQuery) _runKeyword(query);
    } else {
      if (query != _catalogQuery) _runCatalogSearch(query);
    }
  }

  // ── Playback / detail delegation ───────────────────────────────────────────

  /// Load the experimental merged-series-page flag once on init.
  Future<void> _loadMergedSeriesFlag() async {
    final on = await StorageService.getMergedSeriesPageEnabled();
    if (mounted && on != _mergedSeriesPage) {
      setState(() => _mergedSeriesPage = on);
    }
  }

  void _openItem(
    StremioMeta item,
    StremioAddon addon, {
    bool isTraktSource = false,
  }) {
    _activeAddonId = addon.id;
    final imdb = _imdbOf(item);
    // Show a "Remove from Continue Watching" action when this title is on the
    // Continue Watching row (regardless of which row opened it).
    final inCw = imdb != null && _cwIds.contains(imdb);

    // Full quick-actions menu, mirroring the catalog/aggregated detail screens:
    // app actions (Select Source, Add to Stremio TV, Search Packs, Random
    // Episode) always, Trakt-syncing actions only when connected — plus Remove
    // for Continue Watching titles.
    final options = <TraktMenuOption>[
      ...buildTraktAddOnlyMenuOptions(
        isSeries: item.type == 'series',
        isMovie: item.type == 'movie',
        hasBoundSource: _isBound(item),
        // The Trakt-syncing actions key off the IMDb id, so only offer them for
        // titles that have one (otherwise the sync call fails with an error).
        isTraktAuthenticated: _isTraktAuthenticated && imdb != null,
      ),
      if (inCw)
        const TraktMenuOption(
          action: TraktItemMenuAction.removeFromPlayback,
          icon: Icons.delete_sweep_rounded,
          color: Color(0xFFEF4444),
          label: 'Remove from Continue Watching',
          caption: 'Remove',
        ),
    ];

    // Experimental: series route to the merged detail+episodes page. Movies and
    // the flag-off path fall through to the existing CatalogItemDetailScreen.
    if ((item.type == 'series' || item.type == 'movie') && _mergedSeriesPage) {
      Navigator.of(context)
          .push(
            MaterialPageRoute(
              settings: const RouteSettings(name: kCatalogDetailRouteName),
              builder: (_) => MergedDetailScreen(
                item: item,
                addon: addon,
                isTelevision: widget.isTelevision,
                showQuickPlay: !_pikpakOnly,
                isTraktSource: isTraktSource,
                onResume: () => _onCatalogPlay(
                  item,
                  addon,
                  isTraktSource: isTraktSource,
                  skipEpisodeFallback: true,
                ),
                // Movie only: the Sources (manual list) button.
                onBrowse: item.type == 'movie'
                    ? () => _onCatalogBrowse(item, addon,
                        isTraktSource: isTraktSource)
                    : null,
                onItemSelected: _browseSelection,
                onQuickPlay: _playSelection,
                boundSourceCount: _boundCountFor,
                onSelectSource: _handleEditOrSelectSource,
                traktMenuOptions: options,
                onTraktAction: (a) => _handleDetailQuickAction(
                  item,
                  addon,
                  a,
                  inCw: inCw,
                  imdb: imdb,
                ),
                recommendationsLoader: imdb != null
                    ? () => _stremio.getRecommendations(
                        imdbId: imdb,
                        type: item.type,
                      )
                    : null,
                onRecommendationTap: imdb != null
                    ? (rec) => _openItem(rec, rec.sourceAddon ?? addon)
                    : null,
                metaEnricher: (id, type) =>
                    _stremio.fetchMetaDetails(imdbId: id, type: type),
              ),
            ),
          )
          .then((_) {
            _refreshBoundSources();
            _loadContinueWatching();
            _refreshTraktAuthState();
          });
      return;
    }

    Navigator.of(context)
        .push(
          MaterialPageRoute(
            settings: const RouteSettings(name: kCatalogDetailRouteName),
            builder: (_) => CatalogItemDetailScreen(
              item: item,
              isTelevision: widget.isTelevision,
              // Hide "Play" when PikPak is the only provider — no quick-play.
              showQuickPlay: !_pikpakOnly,
              // Gold-tint the Sources button when a source is already pinned.
              hasBoundSource: _isBound(item),
              onPlay: () =>
                  _onCatalogPlay(item, addon, isTraktSource: isTraktSource),
              onBrowse: () =>
                  _onCatalogBrowse(item, addon, isTraktSource: isTraktSource),
              traktMenuOptions: options,
              onTraktAction: (a) => _handleDetailQuickAction(
                item,
                addon,
                a,
                inCw: inCw,
                imdb: imdb,
              ),
              // "More Like This" rail + sparse-item meta backfill, matching the
              // catalog detail flow.
              recommendationsLoader: imdb != null
                  ? () => _stremio.getRecommendations(
                      imdbId: imdb,
                      type: item.type,
                    )
                  : null,
              onRecommendationTap: imdb != null
                  ? (rec) => _openItem(rec, rec.sourceAddon ?? addon)
                  : null,
              metaEnricher: (id, type) =>
                  _stremio.fetchMetaDetails(imdbId: id, type: type),
            ),
          ),
        )
        // A bind/unbind may have happened inside the detail flow; playback may
        // also have changed Continue Watching progress.
        .then((_) {
          _refreshBoundSources();
          _loadContinueWatching();
          _refreshTraktAuthState();
        });
  }

  /// Dispatch a detail-screen quick action. Reuses the shared
  /// [handleTraktMenuAction] for the standard actions and handles the
  /// Continue-Watching removal locally. The detail page stays underneath (like
  /// Play/Sources), so Back returns to it.
  Future<void> _handleDetailQuickAction(
    StremioMeta item,
    StremioAddon addon,
    TraktItemMenuAction action, {
    required bool inCw,
    String? imdb,
  }) async {
    if (action == TraktItemMenuAction.removeFromPlayback) {
      if (imdb != null) await _handleContinueDetailAction(action, imdb);
      return;
    }
    await handleTraktMenuAction(
      context,
      item,
      action,
      // "Select Source" when nothing is bound → straight to the picker; when a
      // source is already bound → the rich edit dialog (list / reorder / remove
      // / add). Matches the catalog/aggregated detail flow.
      onSelectSource: _openBindSources,
      onEditSource: _handleEditOrSelectSource,
      onPlayRandomEpisode: (m) => _playRandomEpisodeFromDetail(m, addon),
      onSearchPacks: _searchPacksFromDetail,
      onAddToStremioTv: _addToStremioTvFromDetail,
    );
    // A Trakt watched-state change moves a title in/out of Continue Watching,
    // so reload the board's Trakt rows — otherwise the board is stale when the
    // user backs out of the detail (old home reloads its list after these).
    // Skipped on the dedicated Search tab, which never renders those rows.
    if (mounted &&
        !widget.searchMode &&
        (action == TraktItemMenuAction.markWatched ||
            action == TraktItemMenuAction.markUnwatched)) {
      _loadTraktContinueWatching(refreshBound: false);
    }
  }

  /// "Select/Edit Source" entry: edit dialog when a source is already bound,
  /// otherwise the add-source picker.
  Future<void> _handleEditOrSelectSource(StremioMeta item) async {
    final imdb = _imdbOf(item);
    final bound = imdb == null
        ? const <SeriesSource>[]
        : await SeriesSourceService.getSources(imdb);
    if (!mounted) return;
    if (bound.isNotEmpty) {
      await _showEditSourceDialog(item, bound);
    } else {
      await _showAddSourcePicker(item);
    }
  }

  /// Manage the bound sources for [item]: list them, reorder by priority
  /// (series — first match wins), delete individually, Remove All, or add
  /// another via the picker. Ported from the catalog/aggregated detail flow.
  Future<void> _showEditSourceDialog(
    StremioMeta item,
    List<SeriesSource> initial,
  ) async {
    final imdbId = _imdbOf(item);
    if (imdbId == null) return;
    final isMovie = item.type == 'movie';
    final sources = List<SeriesSource>.of(initial);
    if (sources.isEmpty) return;

    // [closeIfEmpty] pops the dialog via its OWN route (passed in from the
    // builder) when the last source is removed — robust to nested navigators,
    // and a callback (not a BuildContext) so it's safe across the awaits here.
    Future<void> refreshInto(
      void Function(void Function()) setDialogState,
      VoidCallback closeIfEmpty,
    ) async {
      final updated = await SeriesSourceService.getSources(imdbId);
      if (!mounted) return;
      setDialogState(() {
        sources
          ..clear()
          ..addAll(updated);
      });
      await _refreshBoundSources();
      if (updated.isEmpty) closeIfEmpty();
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            void closeIfEmpty() {
              if (dialogContext.mounted) Navigator.of(dialogContext).pop();
            }

            return Dialog(
              backgroundColor: const Color(0xFF1E293B),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 450,
                  maxHeight: 500,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.link_rounded,
                            color: Color(0xFF60A5FA),
                            size: 24,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            isMovie
                                ? 'Movie Source'
                                : 'Series Sources (${sources.length})',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      if (!isMovie) ...[
                        const SizedBox(height: 4),
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'First match wins — reorder by priority',
                            style: TextStyle(
                              color: Colors.white38,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Flexible(
                        child: isMovie
                            ? ListView.builder(
                                shrinkWrap: true,
                                itemCount: sources.length,
                                itemBuilder: (context, index) =>
                                    _buildSourceListTile(
                                      key: ValueKey(sources[index].torrentHash),
                                      source: sources[index],
                                      index: index,
                                      showDragHandle: false,
                                      onDelete: () async {
                                        await SeriesSourceService.removeSourceByHash(
                                          imdbId,
                                          sources[index].torrentHash,
                                        );
                                        await refreshInto(
                                          setDialogState,
                                          closeIfEmpty,
                                        );
                                      },
                                    ),
                              )
                            : ReorderableListView.builder(
                                shrinkWrap: true,
                                itemCount: sources.length,
                                onReorder: (oldIndex, newIndex) {
                                  if (newIndex > oldIndex) newIndex--;
                                  setDialogState(() {
                                    final moved = sources.removeAt(oldIndex);
                                    sources.insert(newIndex, moved);
                                  });
                                  SeriesSourceService.setSources(
                                    imdbId,
                                    List.of(sources),
                                  );
                                  _refreshBoundSources();
                                },
                                proxyDecorator: (child, index, animation) =>
                                    Material(
                                      color: Colors.transparent,
                                      elevation: 4,
                                      child: child,
                                    ),
                                itemBuilder: (context, index) =>
                                    _buildSourceListTile(
                                      key: ValueKey(sources[index].torrentHash),
                                      source: sources[index],
                                      index: index,
                                      onDelete: () async {
                                        await SeriesSourceService.removeSourceByHash(
                                          imdbId,
                                          sources[index].torrentHash,
                                        );
                                        await refreshInto(
                                          setDialogState,
                                          closeIfEmpty,
                                        );
                                      },
                                    ),
                              ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: () {
                                Navigator.of(dialogContext).pop();
                                _showAddSourcePicker(item);
                              },
                              icon: Icon(
                                isMovie
                                    ? Icons.swap_horiz_rounded
                                    : Icons.add_rounded,
                                size: 18,
                              ),
                              label: Text(
                                isMovie ? 'Change Source' : 'Add Source',
                              ),
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF6366F1),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                          ),
                          if (!isMovie && sources.length > 1) ...[
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () async {
                                  await SeriesSourceService.removeAllSources(
                                    imdbId,
                                  );
                                  await _refreshBoundSources();
                                  if (dialogContext.mounted) {
                                    Navigator.of(dialogContext).pop();
                                  }
                                },
                                icon: const Icon(
                                  Icons.delete_sweep_outlined,
                                  size: 18,
                                  color: Color(0xFFEF4444),
                                ),
                                label: const Text(
                                  'Remove All',
                                  style: TextStyle(color: Color(0xFFEF4444)),
                                ),
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(
                                    color: Color(0xFFEF4444),
                                    width: 1,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                              ),
                            ),
                          ],
                          if (isMovie) ...[
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () async {
                                  await SeriesSourceService.removeAllSources(
                                    imdbId,
                                  );
                                  await _refreshBoundSources();
                                  if (dialogContext.mounted) {
                                    Navigator.of(dialogContext).pop();
                                  }
                                },
                                icon: const Icon(
                                  Icons.delete_outline_rounded,
                                  size: 18,
                                  color: Color(0xFFEF4444),
                                ),
                                label: const Text(
                                  'Remove',
                                  style: TextStyle(color: Color(0xFFEF4444)),
                                ),
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(
                                    color: Color(0xFFEF4444),
                                    width: 1,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        child: const Text(
                          'Close',
                          style: TextStyle(color: Colors.white54),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// Add-source picker: Torrent Search (imdb) / Keyword Search (free-text) /
  /// Local file / Real-Debrid / TorBox.
  Future<void> _showAddSourcePicker(StremioMeta item) async {
    final imdbId = _imdbOf(item);
    if (imdbId == null) {
      _snack('No IMDb match to pin a source for "${item.name}".');
      return;
    }
    // Capture the navigator before the awaits so the RD/TorBox push closures
    // don't reference `context` across an async gap.
    final navigator = Navigator.of(context);
    final rdKey = await StorageService.getApiKey();
    final torboxKey = await StorageService.getTorboxApiKey();
    final rdEnabled = rdKey != null && rdKey.isNotEmpty;
    final torboxEnabled = torboxKey != null && torboxKey.isNotEmpty;
    if (!mounted) return;

    final isMovie = item.type == 'movie';
    final supportsLocal = !LocalBoundSourceService.isLocalBindingDisabled;

    Future<void> saveSource(SeriesSource source) async {
      if (isMovie) {
        await SeriesSourceService.setSources(imdbId, [source]);
      } else {
        await SeriesSourceService.addSource(imdbId, source);
      }
      await _refreshBoundSources();
    }

    // No cloud providers and no local option → go straight to torrent search.
    if (!rdEnabled && !torboxEnabled && !supportsLocal) {
      _openBindSources(item);
      return;
    }

    await showAddSourcePickerDialog(
      context,
      onTorrentSearch: () => _openBindSources(item),
      onKeywordSearch: () => _openKeywordBind(item),
      onLocal: supportsLocal ? () => _pickAndSaveLocalSource(item) : null,
      localDisabledReason: LocalBoundSourceService.localDisabledReason,
      onRealDebrid: rdEnabled
          ? () => navigator.push(
              MaterialPageRoute(
                builder: (_) => DebridDownloadsScreen(
                  isPushedRoute: true,
                  initialSearchQuery: item.name,
                  selectSourceMode: true,
                  onSourceSelected: saveSource,
                ),
              ),
            )
          : null,
      onTorbox: torboxEnabled
          ? () => navigator.push(
              MaterialPageRoute(
                builder: (_) => TorboxDownloadsScreen(
                  isPushedRoute: true,
                  initialSearchQuery: item.name,
                  selectSourceMode: true,
                  onSourceSelected: saveSource,
                ),
              ),
            )
          : null,
    );
  }

  Future<void> _pickAndSaveLocalSource(StremioMeta item) async {
    final imdbId = _imdbOf(item);
    if (imdbId == null) return;
    final SeriesSource? source;
    if (item.type == 'series') {
      source = await LocalBoundSourceService.pickSeriesSource(
        context,
        title: item.name,
      );
    } else {
      source = await LocalBoundSourceService.pickMovieSource(
        context,
        title: item.name,
        year: item.year,
      );
    }
    if (source == null) return;
    if (item.type == 'series') {
      await SeriesSourceService.addSource(imdbId, source);
    } else {
      await SeriesSourceService.setSources(imdbId, [source]);
    }
    await _refreshBoundSources();
    if (!mounted) return;
    _snack('Local source set: ${source.torrentName}');
  }

  /// One bound-source row for the edit dialog (index badge, name, provider
  /// chip, delete). Ported from the catalog/aggregated detail flow.
  Widget _buildSourceListTile({
    required Key key,
    required SeriesSource source,
    required int index,
    required VoidCallback onDelete,
    bool showDragHandle = true,
  }) {
    Color serviceColor;
    String serviceLabel;
    switch (source.debridService) {
      case 'rd':
        serviceColor = const Color(0xFF10B981);
        serviceLabel = 'Real-Debrid';
      case 'torbox':
        serviceColor = const Color(0xFF3B82F6);
        serviceLabel = 'TorBox';
      case 'pikpak':
        serviceColor = const Color(0xFFF59E0B);
        serviceLabel = 'PikPak';
      case 'premiumize':
        serviceColor = const Color(0xFFFB923C);
        serviceLabel = 'Premiumize';
      case 'alldebrid':
        serviceColor = const Color(0xFF26A69A);
        serviceLabel = 'AllDebrid';
      case SeriesSource.localService:
        serviceColor = const Color(0xFF60A5FA);
        serviceLabel = 'Local';
      default:
        serviceColor = Colors.white54;
        serviceLabel = source.debridService;
    }

    return Container(
      key: key,
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          if (showDragHandle) ...[
            Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFF60A5FA).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '${index + 1}',
                style: const TextStyle(
                  color: Color(0xFF60A5FA),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  source.torrentName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: serviceColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    serviceLabel,
                    style: TextStyle(
                      color: serviceColor,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(
              Icons.close_rounded,
              size: 16,
              color: Color(0xFFEF4444),
            ),
            onPressed: onDelete,
            tooltip: 'Remove source',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
          if (showDragHandle)
            const Icon(
              Icons.drag_handle_rounded,
              size: 18,
              color: Colors.white24,
            ),
        ],
      ),
    );
  }

  Future<void> _addToStremioTvFromDetail(StremioMeta item) async {
    final result = await StremioTvCatalogPickerDialog.show(context, item: item);
    if (!mounted || result == null) return;
    _snack(result.message);
  }

  void _searchPacksFromDetail(StremioMeta item) {
    final imdb = _imdbOf(item);
    if (imdb == null) {
      _snack('No IMDb match to find packs for "${item.name}".');
      return;
    }
    _browseSelection(
      AdvancedSearchSelection(
        imdbId: imdb,
        isSeries: true,
        title: item.name,
        year: item.year,
        contentType: item.type,
        posterUrl: item.poster,
      ),
    );
  }

  /// Resolve a meta-capable addon (for episode listings): the preferred addon
  /// if it serves meta, otherwise the first enabled addon that does.
  Future<StremioAddon?> _metaAddonFor(StremioAddon preferred) async {
    if (preferred.resources.contains('meta') && preferred.baseUrl.isNotEmpty) {
      return preferred;
    }
    for (final a in await _stremio.getEnabledAddons()) {
      if (a.resources.contains('meta') && a.baseUrl.isNotEmpty) return a;
    }
    return null;
  }

  Future<void> _playRandomEpisodeFromDetail(
    StremioMeta item,
    StremioAddon addon,
  ) async {
    final imdb = _imdbOf(item);
    if (imdb == null) {
      _snack('No IMDb match to pick an episode for "${item.name}".');
      return;
    }
    final metaAddon = await _metaAddonFor(addon);
    // If we fell back to a different meta addon than the item's origin, its
    // content id won't match — query by IMDb id instead of the origin's id.
    final contentId = (metaAddon != null && metaAddon.id == addon.id)
        ? item.id
        : imdb;
    final videos = metaAddon == null
        ? null
        : await _stremio.fetchSeriesMeta(metaAddon, contentId);
    if (!mounted) return;

    final episodes = <({int season, int episode})>[];
    for (final v in videos ?? const <Map<String, dynamic>>[]) {
      final sRaw = v['season'];
      final s = sRaw is num ? sRaw.toInt() : null;
      if (s == null || s <= 0) continue; // skip specials (season 0)
      final eRaw = v['number'] ?? v['episode'];
      final e = eRaw is num ? eRaw.toInt() : null;
      if (e == null) continue;
      episodes.add((season: s, episode: e));
    }
    if (episodes.isEmpty) {
      _snack("Couldn't load episodes for \"${item.name}\".");
      return;
    }

    final pick = episodes[Random().nextInt(episodes.length)];
    _playSelection(
      AdvancedSearchSelection(
        imdbId: imdb,
        isSeries: true,
        title: item.name,
        year: item.year,
        season: pick.season,
        episode: pick.episode,
        contentType: item.type,
        posterUrl: item.poster,
      ),
    );
  }

  // Catalog Play = auto-best in-tab; Sources = manual list in-tab. For a series
  // Play auto-plays the resume episode (last-played by imdbId → title, else
  // S01E01) — the Episodes button is the manual picker. Nothing jumps to Home.
  Future<void> _onCatalogPlay(
    StremioMeta item,
    StremioAddon addon, {
    bool isTraktSource = false,
    // Merged series page: episodes are already shown inline, so a no-IMDb
    // series must NOT fall back to pushing a standalone EpisodesScreen (that
    // would stack a duplicate episode list on top). It resolves the resume
    // episode against the raw catalog id and plays via the addon /stream path.
    bool skipEpisodeFallback = false,
  }) async {
    // Set the active addon before any early return so a movie play carries the
    // right addon id into meta.addonId (addon-stream resume/next), instead of a
    // stale one left over from a previously-browsed series.
    _activeAddonId = addon.id;
    if (item.type != 'series') {
      // Keep the detail page underneath — the cinematic loading overlay covers
      // it, and after playback Back returns to the detail (like Home).
      _playSelection(_movieSelection(item, isTraktSource: isTraktSource));
      return;
    }

    final ttId = item.imdbId ?? (item.id.startsWith('tt') ? item.id : '');
    // Without an IMDb id we can't search torrents for a specific episode, so
    // fall back to the manual episode picker — except from the merged page
    // (episodes are inline there), where we play via the raw id's addon stream.
    if (ttId.isEmpty && !skipEpisodeFallback) {
      _openEpisodes(item, addon, isTraktSource: isTraktSource);
      return;
    }
    // Play id: the `tt…` id when present (torrent-resolvable); otherwise the raw
    // catalog id, which playFromSelection routes to the addon /stream endpoint.
    final playId = ttId.isNotEmpty ? ttId : (item.effectiveImdbId ?? item.id);

    // Resolve where to resume, mirroring EpisodesScreen's landing logic:
    // last-played episode for this show (by imdbId, then by title), else S01E01.
    int? season;
    int? episode;
    final byId = await StorageService.getLastPlayedEpisodeByImdbId(playId);
    season = byId?['season'] as int?;
    episode = byId?['episode'] as int?;
    if (season == null || episode == null) {
      final byTitle = await StorageService.getLastPlayedEpisode(
        seriesTitle: item.name,
      );
      season ??= byTitle?['season'] as int?;
      episode ??= byTitle?['episode'] as int?;
    }
    season ??= 1;
    episode ??= 1;
    if (!mounted) return;

    _playSelection(
      AdvancedSearchSelection(
        imdbId: playId,
        isSeries: true,
        title: item.name,
        year: item.year,
        season: season,
        episode: episode,
        contentType: item.type,
        posterUrl: item.poster,
        traktSource: isTraktSource,
      ),
    );
  }

  void _onCatalogBrowse(
    StremioMeta item,
    StremioAddon addon, {
    bool isTraktSource = false,
  }) {
    if (item.type == 'series') {
      _openEpisodes(item, addon, isTraktSource: isTraktSource);
    } else {
      _browseSelection(_movieSelection(item, isTraktSource: isTraktSource));
    }
  }

  AdvancedSearchSelection _movieSelection(
    StremioMeta item, {
    bool isTraktSource = false,
  }) => AdvancedSearchSelection(
    // Keep the raw catalog id when there's no `tt…` id — for IPTV/TV channels
    // AND tmdb/kitsu-only movies — so playback/Sources resolve the addon's own
    // /stream endpoint, matching old home (which passed effectiveImdbId ?? id).
    // The torrent engines can't resolve a non-`tt` id, but the addon stream can
    // (playFromSelection routes any non-`tt` id to _playAddonStream), so this
    // plays instead of dead-ending on "No IMDb match".
    imdbId: item.effectiveImdbId ?? item.id,
    isSeries: false,
    title: item.name,
    year: item.year,
    contentType: item.type,
    posterUrl: item.poster,
    // Trakt-sourced movies scrobble to Trakt like the old home view; catalog
    // movies leave this false so scrobble follows the "Sync Catalog Items"
    // setting.
    traktSource: isTraktSource,
  );

  void _openEpisodes(
    StremioMeta item,
    StremioAddon addon, {
    bool isTraktSource = false,
  }) {
    _activeAddonId = addon.id;
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            settings: const RouteSettings(name: kEpisodesRouteName),
            builder: (_) => EpisodesScreen(
              show: item,
              addon: addon,
              isTelevision: widget.isTelevision,
              isTraktSource: isTraktSource,
              // EpisodesScreen pops itself (and the detail route) before firing
              // these, so we're back on the Search screen when they run.
              onQuickPlay: _playSelection,
              onItemSelected: _browseSelection,
              // "Select Source" button: manage/pin sources via the same picker
              // the detail screen uses (edit dialog when already bound, else the
              // Torrent Search / Local / RD / TorBox picker) for a consistent
              // entry point.
              boundSourceCount: _boundCountFor,
              onSelectSource: _handleEditOrSelectSource,
            ),
          ),
        )
        .then((_) => _refreshBoundSources());
  }

  /// Open the source picker (bind mode) to pin a source for [show]. For a series
  /// this searches season/complete packs (no episode), matching Home.
  void _openBindSources(StremioMeta show) {
    final imdb = _imdbOf(show);
    if (imdb == null) {
      _snack('No IMDb match to pin a source for "${show.name}".');
      return;
    }
    final sel = AdvancedSearchSelection(
      imdbId: imdb,
      isSeries: show.type == 'series',
      title: show.name,
      year: show.year,
      contentType: show.type,
      posterUrl: show.poster,
    );
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => _SourcesScreen(
              selection: sel,
              meta: _metaFor(sel),
              isTelevision: widget.isTelevision,
              bindMode: true,
            ),
          ),
        )
        .then((_) => _refreshBoundSources());
  }

  /// Free-text keyword bind: push the sources screen seeded with a pack query
  /// (series → `name complete`, movie → `name year`), where tapping a result
  /// pins it as [show]'s bound source. The query is editable.
  void _openKeywordBind(StremioMeta show) {
    final imdb = _imdbOf(show);
    if (imdb == null) {
      _snack('No IMDb match to pin a source for "${show.name}".');
      return;
    }
    final isSeries = show.type == 'series';
    final seed = isSeries
        ? '${show.name} complete'
        : (show.year != null && show.year!.isNotEmpty
              ? '${show.name} ${show.year}'
              : show.name);
    final sel = AdvancedSearchSelection(
      imdbId: imdb,
      isSeries: isSeries,
      title: show.name,
      year: show.year,
      contentType: show.type,
      posterUrl: show.poster,
    );
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => _SourcesScreen(
              selection: sel,
              meta: _metaFor(sel),
              isTelevision: widget.isTelevision,
              bindMode: true,
              keywordSeed: seed,
            ),
          ),
        )
        .then((_) => _refreshBoundSources());
  }

  /// Auto-best in-tab play: search torrents for the selection, pick the best
  /// instantly-playable source, and play — never leaving the Search tab.
  PlaybackMeta _metaFor(AdvancedSearchSelection sel) => PlaybackMeta(
    // Only a real IMDb id here — the launcher's Trakt auto-sync + local
    // Continue Watching must never fire on an empty or non-IMDb (IPTV) id,
    // even though the search itself still uses sel.imdbId (the addon id).
    imdbId: sel.imdbId.startsWith('tt') ? sel.imdbId : null,
    contentType: sel.contentType ?? (sel.isSeries ? 'series' : 'movie'),
    season: sel.season,
    episode: sel.episode,
    title: sel.title,
    posterUrl: sel.posterUrl,
    year: sel.year,
    addonId: _activeAddonId,
    traktProgressPercent: sel.traktProgressPercent,
    // Trakt-row plays scrobble to Trakt instead of saving a duplicate local
    // Continue Watching entry (mirrors Home passing selection.traktSource).
    traktScrobble: sel.traktSource,
  );

  /// Catalog auto-best play — the service picks the provider, shows the real
  /// cinematic overlay, searches, and plays (with source list + content
  /// metadata so the in-player Sources switcher + Continue Watching work).
  Future<void> _playSelection(AdvancedSearchSelection sel) =>
      TorrentPlaybackService.playFromSelection(
        context,
        imdbId: sel.imdbId,
        isMovie: !sel.isSeries,
        season: sel.season,
        episode: sel.episode,
        meta: _metaFor(sel),
      );

  /// Manual sources list in-tab — the screen searches itself (own loading) and
  /// each tap plays with the full source list + content metadata.
  void _browseSelection(AdvancedSearchSelection sel) {
    if (sel.imdbId.isEmpty) {
      _snack('No IMDb match to find sources for "${sel.title}".');
      return;
    }
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => _SourcesScreen(
              selection: sel,
              meta: _metaFor(sel),
              isTelevision: widget.isTelevision,
            ),
          ),
        )
        // A long-press pin/unpin may have happened in the sources list.
        .then((_) => _refreshBoundSources());
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kStremioBg,
      // A restrained indigo bloom near the top fading fast into near-black —
      // toned down from a saturated purple so the posters carry the colour
      // (Stremio's home grid is nearly monochrome).
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.75),
            radius: 1.35,
            colors: [
              Color(0xFF241E44), // dim indigo bloom
              Color(0xFF161327),
              Color(0xFF0F0D1D),
              kStremioBg,
            ],
            stops: [0.0, 0.38, 0.68, 1.0],
          ),
        ),
        child: SafeArea(
          // Three layouts:
          //  • Dedicated Search tab (searchMode) — the field + Catalog/Keyword
          //    toggle over a blank prompt until the user types (TV only).
          //  • Home-New board on TV — chrome-free hero + rows, no search bar
          //    (search lives in its own tab).
          //  • Home-New board on desktop/mobile — keeps a persistent search bar
          //    above the board (no separate Search tab there).
          child: widget.discoverMode
              ? _buildDiscover()
              : (widget.isTelevision && !widget.searchMode)
                  ? _buildBoard()
                  : Column(
                      children: [
                        _buildHeader(),
                        Expanded(child: _buildBody()),
                      ],
                    ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final tv = widget.isTelevision;
    // On narrow phones the search box + Catalog/Keyword toggle crowd each other
    // in one row, so stack the toggle underneath. Wide/TV keeps them inline.
    final narrow = !tv && MediaQuery.of(context).size.width < 620;

    final field = _buildSearchField(tv);
    final toggle = _ModeToggle(
      mode: _mode,
      isTelevision: tv,
      fullWidth: narrow,
      onChanged: _switchMode,
      // Keyboard/DPAD wiring (both desktop + TV): the two segments are
      // focusable; up/left leave back to the search field, down drops into the
      // content, select switches mode.
      catalogNode: _modeCatalogNode,
      keywordNode: _modeKeywordNode,
      onLeaveToField: _focusSearchFieldAtEnd,
      onLeaveToContent: _focusContent,
    );

    if (narrow) {
      return Padding(
        padding: EdgeInsets.fromLTRB(16, tv ? 16 : 12, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [field, const SizedBox(height: 10), toggle],
        ),
      );
    }

    // Wide/TV: a centered pill search (Stremio-style) with the mode toggle
    // pinned to the right. A left spacer matching the toggle keeps the search
    // truly centered.
    return Padding(
      padding: EdgeInsets.fromLTRB(20, tv ? 18 : 14, 20, 10),
      child: Row(
        children: [
          const SizedBox(width: 172),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: field,
              ),
            ),
          ),
          const SizedBox(width: 12),
          toggle,
        ],
      ),
    );
  }

  /// Centered translucent pill search — mirrors Stremio's search bar (rounded
  /// pill, centered text, a search glyph on the right that becomes a clear ✕).
  Widget _buildSearchField(bool tv) {
    final scheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(26);
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
          _focusContent();
          return KeyEventResult.handled;
        }
        // Arrow-up jumps to the Catalog/Keyword toggle (top-right). Works on
        // both TV (DPAD) and desktop (keyboard) — up is safe to intercept, a
        // single-line field doesn't use it for the cursor and nothing sits
        // above the search field.
        if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
          _focusModeToggle();
          return KeyEventResult.handled;
        }
        // Arrow-right reaches the toggle too — its natural spatial direction —
        // but only once the caret is at the very end of the text, so right
        // still moves the cursor through what you've typed first. A blank field
        // (or caret already at the end) jumps to the toggle immediately.
        if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
          final text = _searchController.text;
          final sel = _searchController.selection;
          final atEnd =
              text.isEmpty ||
              sel.baseOffset < 0 ||
              (sel.isCollapsed && sel.baseOffset >= text.length);
          if (atEnd) {
            _focusModeToggle();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored; // let the caret move right first
        }
        // Arrow-left is handled via a Shortcuts override on the field (below),
        // not here — an EditableText consumes left-at-start for the caret before
        // an ancestor Focus.onKeyEvent can see it.
        return KeyEventResult.ignored;
      },
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: _searchController,
        builder: (context, value, _) {
          final hasText = value.text.isNotEmpty;
          final field = TextField(
            controller: _searchController,
            focusNode: _searchFocusNode,
            onChanged: _onQueryChanged,
            onSubmitted: _onQuerySubmitted,
            textInputAction: TextInputAction.search,
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.onSurface, fontSize: tv ? 16 : 15),
            decoration: InputDecoration(
              hintText: _mode == _Mode.catalog
                  ? 'Search or paste link'
                  : 'Search torrents by keyword',
              hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.32)),
              suffixIcon: hasText
                  ? IconButton(
                      icon: Icon(
                        Icons.close_rounded,
                        color: Colors.white.withValues(alpha: 0.55),
                      ),
                      onPressed: _clearQuery,
                    )
                  : Icon(
                      Icons.search_rounded,
                      color: Colors.white.withValues(alpha: 0.4),
                    ),
              border: OutlineInputBorder(
                borderRadius: radius,
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: radius,
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: radius,
                borderSide: BorderSide(
                  color: kStremioAccent.withValues(alpha: 0.6),
                ),
              ),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.06),
              contentPadding: EdgeInsets.symmetric(
                horizontal: 20,
                vertical: tv ? 16 : 14,
              ),
            ),
          );
          // TV: wrap the field so left-arrow on an EMPTY field escapes to the
          // sidebar (the intuitive direction) — the text editor would otherwise
          // silently eat it. The wrapper is ALWAYS present (a stable subtree root,
          // so typing/clearing never tears the EditableText down); the action
          // disables itself once there's text, so the framework's own caret and
          // selection handling takes over untouched.
          if (!tv) return field;
          return Shortcuts(
            shortcuts: const <ShortcutActivator, Intent>{
              SingleActivator(LogicalKeyboardKey.arrowLeft):
                  _SearchLeftIntent(),
            },
            child: Actions(
              actions: <Type, Action<Intent>>{
                _SearchLeftIntent: _EmptyFieldLeftAction(
                  _searchController,
                  () => MainPageBridge.focusTvSidebar?.call(),
                ),
              },
              child: field,
            ),
          );
        },
      ),
    );
  }

  Widget _buildBody() {
    if (_mode == _Mode.keyword) return _buildKeyword();
    if (_catalogSearching) {
      return const Center(child: CircularProgressIndicator());
    }
    // Dedicated Search tab: blank prompt until there's a query (no hero/board).
    if (widget.searchMode && _catalogQuery.isEmpty) {
      return _buildSearchPrompt();
    }
    return _buildBoard();
  }

  /// Empty state for the dedicated Search tab before the user types.
  Widget _buildSearchPrompt() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search_rounded,
              size: 54,
              color: Colors.white.withValues(alpha: 0.22),
            ),
            const SizedBox(height: 16),
            Text(
              'Search movies & shows',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.8),
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            // Only reached in Catalog mode — _buildBody routes Keyword mode to
            // _buildKeyword (which has its own empty state) before it gets here.
            Text(
              'Type a title to search your catalogs, or switch to Keyword to '
              'search torrents directly.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 13.5,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKeyword() {
    if (_kwLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_kwError != null) {
      return _message(Icons.error_outline_rounded, 'Search failed', _kwError!);
    }
    if (_kwQuery.isEmpty) {
      // Surface Sources before searching so users can enable/disable the
      // trackers that get queried up front.
      return Column(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: _kwSourcesButton(),
            ),
          ),
          Expanded(
            child: _message(
              Icons.bolt_rounded,
              'Keyword torrent search',
              'Type a title and press search to find torrents across your '
                  'enabled sources, then tap one to play. Use Sources to choose '
                  'which trackers are queried.',
            ),
          ),
        ],
      );
    }
    final narrow =
        !widget.isTelevision && MediaQuery.of(context).size.width < 600;
    final content = Column(
      children: [
        _buildKeywordToolbar(floatingSelect: narrow),
        Expanded(
          child: _kwResults.isEmpty
              ? _message(
                  Icons.search_off_rounded,
                  _kwAll.isEmpty ? 'No results' : 'No matches',
                  _kwAll.isEmpty
                      ? 'Nothing found for "$_kwQuery". Try different keywords '
                            'or enable more sources.'
                      : 'No results match your filters. Adjust or clear them.',
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  cacheExtent: 1200,
                  itemCount: _kwResults.length,
                  itemBuilder: (context, i) {
                    final t = _kwResults[i];
                    final selectable = !t.isDirectStream && !t.isExternalStream;
                    return TorrentResultRow(
                      key: ValueKey(
                        '${t.infohash}_${_kwSelectionMode}_${_kwSelected.contains(t.infohash)}',
                      ),
                      torrent: t,
                      index: i,
                      focusNode: _kwNodes[i],
                      isTelevision: widget.isTelevision,
                      qualityTier: t.qualityTier,
                      cacheLabels:
                          _kwCache[t.infohash.toLowerCase()] ?? const [],
                      isSelectionMode: _kwSelectionMode && selectable,
                      isSelected: _kwSelected.contains(t.infohash),
                      onTap: () {
                        if (_kwSelectionMode && selectable) {
                          _toggleKwSelection(t);
                          return;
                        }
                        // Swallow a SELECT that leaks through as a toolbar
                        // dialog (sort/filter/sources) closes on TV.
                        if (DialogTapGuard.shouldIgnoreTap()) return;
                        unawaited(
                          TorrentPlaybackService.activateTorrent(
                            context,
                            t,
                            searchKeyword: _kwQuery,
                          ),
                        );
                      },
                      onLongPress: !_kwSelectionMode && selectable
                          ? () {
                              _enterKwSelection();
                              _toggleKwSelection(t);
                            }
                          : null,
                      onNavigateUp: () {
                        if (i > 0) {
                          _kwNodes[i - 1].requestFocus();
                        } else if (_kwToolbarVisible) {
                          // From the top row, Up lands on the toolbar (Sort…),
                          // not straight back to the search field.
                          _kwToolbarNodes.first.requestFocus();
                        } else {
                          _searchFocusNode.requestFocus();
                        }
                      },
                      onNavigateDown: () {
                        if (i < _kwNodes.length - 1) {
                          _kwNodes[i + 1].requestFocus();
                        }
                      },
                    );
                  },
                ),
        ),
      ],
    );

    if (!narrow) return content;
    // Small screens: Home-style floating select FAB / selection bar overlaid
    // on the results, instead of the toolbar "Select" pill.
    final canSelect = _kwSelectableResults.isNotEmpty;
    return Stack(
      children: [
        Positioned.fill(child: content),
        if (canSelect)
          _kwSelectionMode ? _buildKwSelectionBar() : _buildKwSelectFab(),
      ],
    );
  }

  /// Standalone "Sources" pill shown in the pre-search keyword state so users
  /// can pick which trackers are queried before typing a query.
  Widget _kwSourcesButton() {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _openKeywordSources,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.dns_rounded, size: 16, color: scheme.onSurfaceVariant),
              const SizedBox(width: 8),
              Text(
                'Sources',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// [floatingSelect] true on small screens where the multi-select entry is a
  /// floating FAB + bar (Home-style) rather than a toolbar pill — so the
  /// toolbar stays Sort/Filters/Sources and never swaps to selection controls.
  Widget _buildKeywordToolbar({bool floatingSelect = false}) {
    final scheme = Theme.of(context).colorScheme;
    final filterCount =
        _kwFilters.qualities.length +
        _kwFilters.ripSources.length +
        _kwFilters.languages.length;

    // [navIndex]/[navTotal], when provided, make the pill keyboard/DPAD
    // focusable at that position in the toolbar (left/right between pills, up to
    // the search field, down into the results, select to activate).
    Widget pill(
      IconData icon,
      String label,
      VoidCallback onTap, {
      bool active = false,
      bool compact = false,
      int? navIndex,
      int navTotal = 0,
    }) {
      Widget body(bool focused) => Container(
        padding: compact
            ? const EdgeInsets.all(10)
            : const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
        decoration: BoxDecoration(
          color: active
              ? scheme.primary.withValues(alpha: 0.16)
              : scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(999),
          // Always 2px so focus never shifts layout: white ring when
          // focused, else the active/idle border.
          border: Border.all(
            color: focused
                ? Colors.white.withValues(alpha: 0.9)
                : active
                ? scheme.primary.withValues(alpha: 0.5)
                : Colors.white.withValues(alpha: 0.10),
            width: 2,
          ),
        ),
        child: compact
            ? Icon(
                icon,
                size: 18,
                color: active ? scheme.primary : scheme.onSurfaceVariant,
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 15, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface,
                    ),
                  ),
                ],
              ),
      );

      final Widget tappable = navIndex == null
          ? Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(999),
                child: body(false),
              ),
            )
          : Focus(
              focusNode: _kwToolbarNodes[navIndex],
              onKeyEvent: (n, event) =>
                  _handleKwToolbarKey(navIndex, navTotal, onTap, event),
              child: Builder(
                builder: (context) {
                  final focused = Focus.of(context).hasFocus;
                  return Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: onTap,
                      borderRadius: BorderRadius.circular(999),
                      canRequestFocus: false,
                      child: body(focused),
                    ),
                  );
                },
              ),
            );

      return Padding(padding: const EdgeInsets.only(right: 8), child: tappable);
    }

    if (_kwSelectionMode && !floatingSelect) {
      final selectable = _kwSelectableResults.length;
      final count = _kwSelected.length;
      final allSelected = count > 0 && count == selectable;
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
        child: Row(
          children: [
            pill(
              Icons.close_rounded,
              'Cancel',
              _exitKwSelection,
              navIndex: 0,
              navTotal: 3,
            ),
            pill(
              allSelected ? Icons.deselect_rounded : Icons.select_all_rounded,
              allSelected ? 'None' : 'All',
              allSelected ? _deselectAllKw : _selectAllKw,
              navIndex: 1,
              navTotal: 3,
            ),
            pill(
              Icons.playlist_add_rounded,
              count > 0 ? 'Add · $count' : 'Add',
              count > 0 ? _openBulkAdd : () {},
              active: count > 0,
              navIndex: 2,
              navTotal: 3,
            ),
          ],
        ),
      );
    }

    final canSelect = _kwSelectableResults.isNotEmpty;
    final showSelect = canSelect && !floatingSelect;
    final total = showSelect ? 4 : 3;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Row(
        children: [
          pill(
            Icons.sort_rounded,
            'Sort · ${_sortLabel(_kwSort)}',
            _openKeywordSort,
            compact: floatingSelect,
            navIndex: 0,
            navTotal: total,
          ),
          pill(
            Icons.filter_list_rounded,
            filterCount > 0 ? 'Filters · $filterCount' : 'Filters',
            _openKeywordFilters,
            active: filterCount > 0,
            compact: floatingSelect,
            navIndex: 1,
            navTotal: total,
          ),
          pill(
            Icons.dns_rounded,
            'Sources',
            _openKeywordSources,
            compact: floatingSelect,
            navIndex: 2,
            navTotal: total,
          ),
          if (showSelect)
            pill(
              Icons.checklist_rounded,
              'Select',
              _enterKwSelection,
              navIndex: 3,
              navTotal: total,
            ),
        ],
      ),
    );
  }

  /// DPAD/keyboard handling for a focused keyword-toolbar pill: select fires the
  /// pill, left/right move between pills, up returns to the search field, down
  /// drops into the first result row.
  KeyEventResult _handleKwToolbarKey(
    int index,
    int total,
    VoidCallback onTap,
    KeyEvent event,
  ) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (isActivateKey(key) || key == LogicalKeyboardKey.space) {
      onTap();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _focusSearchFieldAtEnd();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      if (_kwNodes.isNotEmpty) _kwNodes.first.requestFocus();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      if (index > 0) {
        _kwToolbarNodes[index - 1].requestFocus();
      } else {
        MainPageBridge.focusTvSidebar?.call();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      if (index < total - 1) _kwToolbarNodes[index + 1].requestFocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Floating checklist FAB (bottom-left) that enters multi-select on small
  /// screens — ported from Home's torrent-search layout.
  Widget _buildKwSelectFab() {
    return Positioned(
      left: 16,
      bottom: 16,
      child: GestureDetector(
        onTap: _enterKwSelection,
        child: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: const Color(0xFF334155),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Icon(
            Icons.checklist_rounded,
            color: Colors.white,
            size: 20,
          ),
        ),
      ),
    );
  }

  /// Floating multi-select bar (bottom) — Home-style. Right-inset so it clears
  /// the mobile floating "Menu" nav.
  Widget _buildKwSelectionBar() {
    final selectable = _kwSelectableResults.length;
    final count = _kwSelected.length;
    final allSelected = count > 0 && count == selectable;
    final bottomPad = MediaQuery.of(context).padding.bottom;

    Widget chip(Widget child, VoidCallback? onTap, Color bg) => GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(8),
        ),
        child: child,
      ),
    );

    return Positioned(
      left: 12,
      right: 108, // clear the bottom-right "Menu" FAB
      bottom: 12 + bottomPad,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: kStremioAccent.withValues(alpha: 0.45)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            chip(
              const Icon(Icons.close_rounded, color: Colors.white70, size: 18),
              _exitKwSelection,
              Colors.white.withValues(alpha: 0.1),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                '$count selected',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: count > 0 ? kStremioAccent : Colors.white54,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(width: 8),
            chip(
              Text(
                allSelected ? 'None' : 'All',
                style: const TextStyle(
                  color: Colors.white70,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
              allSelected ? _deselectAllKw : _selectAllKw,
              Colors.white.withValues(alpha: 0.08),
            ),
            const SizedBox(width: 8),
            chip(
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.playlist_add_rounded,
                    color: count > 0 ? Colors.white : Colors.white38,
                    size: 16,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Add',
                    style: TextStyle(
                      color: count > 0 ? Colors.white : Colors.white38,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              count > 0 ? _openBulkAdd : null,
              count > 0
                  ? kStremioAccent
                  : kStremioAccent.withValues(alpha: 0.3),
            ),
          ],
        ),
      ),
    );
  }

  String _sortLabel(String s) =>
      const {
        'relevance': 'Relevance',
        'seeders': 'Seeders',
        'size': 'Size',
        'date': 'Date',
        'name': 'Name',
      }[s] ??
      s;

  /// Poster width for a board rail. On TV the logical canvas can be as short as
  /// 540px (a 1080p panel at density 320 → devicePixelRatio 2.0), where a poster
  /// tuned for a 720-logical canvas leaves no room for a row (plus its header and
  /// the next row's header) under the hero. So scale the poster with the screen
  /// height.
  double _railPosterW(BuildContext context) {
    if (!widget.isTelevision) {
      return MediaQuery.of(context).size.width >= 900 ? 162.0 : 118.0;
    }
    return (MediaQuery.of(context).size.height * 0.17).clamp(92.0, 140.0);
  }

  /// Height to reserve for one board row in the TV hero budget. Sized to the
  /// TALLEST row type — a favourites rail, whose poster carries an inline 2-line
  /// caption — so whichever row sits directly below the hero (a favourites rail
  /// when Continue Watching is empty, else a titleless catalog/CW row that's a
  /// little shorter) always stays fully visible.
  double _railRowH(BuildContext context) =>
      _railPosterW(context) * 3 / 2 + _artPosterCaptionBand(context) + 14;

  /// Approximate height of a rail's header (title row). Matches the padding +
  /// line height in [_railHeader]; used only to budget the hero so a row header
  /// (current and next) stays visible.
  double get _railHeaderH => widget.isTelevision ? 44.0 : 52.0;

  // ── Discover tab ────────────────────────────────────────────────────────────

  /// Load Continue Watching + Trakt rows, then refresh the pinned-source badge
  /// counts once. The board's `_load` does this via `_refreshBoundSources`; the
  /// Trakt loader only refreshes bound counts when Trakt is connected, so
  /// non-Trakt users would otherwise never get badges in Discover.
  Future<void> _primeDiscoverRows() async {
    await Future.wait([
      _loadContinueWatching(),
      _loadTraktContinueWatching(refreshBound: false),
    ]);
    if (mounted) await _refreshBoundSources();
  }

  /// Fetch the installed catalog addons (cheap manifest data — no catalog fetch).
  /// Addons with at least one browsable catalog become Source-dropdown options;
  /// ALL of them are cached in [_addonsById] so item-open can resolve the owning
  /// addon (matching the board, which caches every catalog addon).
  Future<void> _loadDiscoverAddons() async {
    List<StremioAddon> addons;
    try {
      addons = await _stremio.getCatalogAddons();
    } catch (_) {
      return;
    }
    if (!mounted) return;
    setState(() {
      _discAddons = [
        for (final a in addons)
          if (a.catalogs.any((c) => c.isBrowsable)) a,
      ];
      for (final a in addons) {
        _addonsById.putIfAbsent(a.id, () => a);
      }
    });
  }

  /// The Discover tab: a "Source" dropdown over a single browsable grid. Each
  /// source is rendered by the matching See-All panel in [embedded] mode (no
  /// Scaffold/back header), with the Source dropdown injected as its leading
  /// filter so DPAD walks Source → the panel's own filters → grid. All item
  /// open/play/bound wiring is this screen's existing board handlers.
  Widget _buildDiscover() {
    final source = StremioDropdown<String>(
      label: 'Source',
      value: _discSource,
      isTelevision: widget.isTelevision,
      focusNode: _discSourceNode,
      options: [
        const StremioDropdownOption(_discCw, 'Continue Watching'),
        const StremioDropdownOption(_discTrakt, 'Trakt'),
        for (final a in _discAddons)
          StremioDropdownOption('$_discAddonPrefix${a.id}', a.name),
      ],
      onSelected: (s) {
        if (s == _discSource) return;
        setState(() => _discSource = s);
        // The swap re-mounts the embedded panel (new ValueKey), which re-attaches
        // this shared node; pin the DPAD ring back on the Source dropdown so it
        // isn't lost in the dispose/reattach.
        if (widget.isTelevision) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _discSourceNode.requestFocus();
          });
        }
      },
    );

    if (_discSource == _discTrakt) {
      return TraktSeeAllScreen(
        key: const ValueKey('disc_trakt'),
        cwItems: _traktAll,
        cwProgress: _traktProgress,
        onOpen: _openTraktItem,
        onQuickPlay: _pikpakOnly ? null : _playTraktItem,
        isBound: _isBound,
        isTelevision: widget.isTelevision,
        embedded: true,
        leading: source,
        leadingNode: _discSourceNode,
      );
    }

    // An installed addon catalog source.
    if (_discSource.startsWith(_discAddonPrefix)) {
      final addon = _addonsById[_discSource.substring(_discAddonPrefix.length)];
      final catalog = addon?.catalogs.cast<StremioAddonCatalog?>().firstWhere(
            (c) => c != null && c.isBrowsable,
            orElse: () => null,
          );
      if (addon != null && catalog != null) {
        return CatalogSeeAllScreen(
          key: ValueKey('disc_${addon.id}'),
          addon: addon,
          initialCatalog: catalog,
          isTelevision: widget.isTelevision,
          onOpenItem: (item) => _openItem(item, addon),
          onQuickPlay:
              _pikpakOnly ? null : (item) => _onCatalogPlay(item, addon),
          embedded: true,
          leading: source,
          leadingNode: _discSourceNode,
        );
      }
      // Addon vanished (uninstalled) — fall through to Continue Watching.
    }

    // Default: Continue Watching.
    return ContinueWatchingSeeAllScreen(
      key: const ValueKey('disc_cw'),
      title: 'Continue Watching',
      items: _cwAll,
      progressOf: (m) => _cwProgress[m.imdbId],
      onOpen: _openContinueItem,
      onQuickPlay: _pikpakOnly ? null : _onContinuePlay,
      isBound: _isBound,
      isTelevision: widget.isTelevision,
      embedded: true,
      leading: source,
      leadingNode: _discSourceNode,
      // Re-fetch when a detail/player route pops back so finished titles drop out
      // (the quick-play path doesn't reload _cwAll on its own).
      onReload: () async {
        await _loadContinueWatching();
        if (!mounted) return const <StremioMeta>[];
        return List<StremioMeta>.of(_cwAll);
      },
    );
  }

  Widget _buildBoard() {
    if (_loading) {
      // Shimmer rails while the first batch loads, instead of a bare spinner —
      // so rows shimmer in rather than popping out of nowhere (all platforms).
      return SkeletonRailList(
        posterWidth: _railPosterW(context),
        isTelevision: widget.isTelevision,
      );
    }
    if (_error != null) {
      return _message(
        Icons.error_outline_rounded,
        "Couldn't load catalogs",
        _error!,
      );
    }
    final showCw = _cwVisible;
    // Don't fall through to the empty-state message while Trakt rows are being
    // reserved — the skeletons below are the board's content until the fetch
    // settles, and showing "No catalogs yet" first would flip to rows with the
    // exact reflow the reservation exists to prevent.
    if (_sections.isEmpty && !showCw && !_anyFavVisible && !_traktReserving) {
      if (_catalogQuery.isNotEmpty) {
        return _message(
          Icons.search_off_rounded,
          'No catalog matches',
          'Nothing in your catalogs for "$_catalogQuery". Try different '
              'keywords, or switch to Keyword to search torrents directly.',
        );
      }
      return _message(
        Icons.travel_explore_rounded,
        'No catalogs yet',
        'Install a catalog add-on (e.g. Cinemeta) from Addons to browse '
            'movies and shows here.',
      );
    }

    final tv = widget.isTelevision;
    final width = MediaQuery.of(context).size.width;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Size the hero from the board's own height (below the search header) so a
        // full poster row plus the current + next row headers always stay on
        // screen. On a short-canvas TV (~540 logical) the hero shrinks; tall
        // canvases keep it large and reveal more rows.
        //
        // On the dedicated Search tab it's a compact strip, not a full spotlight:
        // the search field above it already eats vertical space, and results —
        // not a cinematic hero — should dominate, so cap it well below the board's
        // so the first result row isn't squeezed.
        final heroH = tv
            ? (constraints.maxHeight - _railRowH(context) - _railHeaderH * 2)
                  .clamp(
                    150.0,
                    widget.searchMode ? 180.0 : 380.0,
                  )
            : (width >= 900 ? 300.0 : 196.0);

        return Column(
          children: [
            // The hero spotlight only changes as DPAD focus moves across tiles, so
            // it's meaningful on TV only. On phones/desktop (no DPAD) it would just
            // sit frozen on the first item and waste vertical space — hide it.
            // On the dedicated Search tab it shows once there are results (to help
            // disambiguate similarly-named titles) but stays hidden on the blank
            // prompt. See [_heroActive].
            if (_heroActive)
              ValueListenableBuilder<StremioMeta?>(
                valueListenable: _heroItem,
                builder: (context, item, _) {
                  if (item == null) return const SizedBox.shrink();
                  return ValueListenableBuilder<StremioMeta?>(
                    valueListenable: _heroEnriched,
                    builder: (context, enriched, __) {
                      return _HeroSpotlight(
                        item: item,
                        background: item.background?.isNotEmpty == true
                            ? item.background
                            : enriched?.background,
                        description: item.description?.isNotEmpty == true
                            ? item.description
                            : enriched?.description,
                        // Catalog list items usually omit the rating; fall back
                        // to the enriched /meta details.
                        rating: item.imdbRating ?? enriched?.imdbRating,
                        compact: widget.searchMode,
                        isTelevision: tv,
                        height: heroH,
                      );
                    },
                  );
                },
              ),
            Expanded(
              child: Builder(
                builder: (context) {
                  // Leading board rows, in order: Continue Watching (local, then
                  // Trakt), then the favourites rows (IPTV, Debrify TV, Stremio TV —
                  // matching the Home screen); the catalog sections follow, offset by
                  // the total leading row count.
                  final cwRows = showCw ? _cwRows : const <_CwRow>[];
                  final cwCount = cwRows.length;
                  // Skeleton Trakt rows, held open in the Trakt slot (right after
                  // the local Continue Watching rows) while the slow fetch is in
                  // flight, so the real rows fill in place instead of inserting
                  // and shoving everything below them down. Non-focusable — the
                  // DPAD wiring skips straight over them (see `down`/`up` in
                  // [_buildContinueWatchingRow]).
                  final skelCount = _traktSkeletonRowCount;
                  final favKinds = _favRowKinds;
                  final favCount = favKinds.length;
                  final leadingCount = cwCount + skelCount + favCount;
                  // Footer spinner tracks the actual fetch, not just "more remain":
                  // `_boardCursor` advances synchronously so the final in-flight batch
                  // still shows it, and an idle board with more rows doesn't spin.
                  final showFooter = _boardLoadingMore;
                  return ListView.builder(
                    controller: _boardScroll,
                    padding: const EdgeInsets.only(top: 6, bottom: 32),
                    cacheExtent: 2000,
                    itemCount:
                        _sections.length + leadingCount + (showFooter ? 1 : 0),
                    itemBuilder: (context, i) {
                      if (i < cwCount) {
                        return _buildContinueWatchingRow(
                          cwRows[i],
                          i,
                          cwCount,
                          favCount,
                        );
                      }
                      if (i < cwCount + skelCount) {
                        return _buildTraktSkeletonRow(i - cwCount);
                      }
                      if (i < leadingCount) {
                        final favIndex = i - cwCount - skelCount;
                        return _buildFavRow(
                          favKinds[favIndex],
                          favIndex,
                          cwCount,
                        );
                      }
                      final s = i - leadingCount;
                      if (s >= _sections.length) return _buildBoardFooter();
                      return _buildRow(s);
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  /// "Movies" / "Series" (etc.) tag for a catalog row, so two "Popular" rows
  /// (one movies, one series) are distinguishable. Null for unknown types.
  String? _sectionTypeLabel(CatalogSection section) {
    switch (section.catalog.type.toLowerCase()) {
      case 'movie':
        return 'Movies';
      case 'series':
        return 'Series';
      case 'tv':
        return 'TV';
      case 'channel':
        return 'Channels';
      default:
        return null;
    }
  }

  /// Open the full-screen Stremio-styled catalog browser for a rail. Seeds the
  /// grid with the rail's already-loaded items + paging cursor so it continues
  /// where the rail left off; item taps route back through [_openItem] so the
  /// existing detail flow (Trakt actions, recommendations) is reused unchanged.
  void _openCatalogSeeAll(CatalogSection section) {
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => CatalogSeeAllScreen(
              addon: section.addon,
              initialCatalog: section.catalog,
              seedItems: List<StremioMeta>.of(section.items),
              seedNextSkip: section.nextSkip,
              isTelevision: widget.isTelevision,
              onOpenItem: (item) => _openItem(item, section.addon),
              onQuickPlay: _pikpakOnly
                  ? null
                  : (item) => _onCatalogPlay(item, section.addon),
              // Bound-source badges are intentionally omitted here: _isBound only
              // tracks rail/CW items (not See-All paged items) and wouldn't
              // reactively update in a pushed screen, so a badge would be a false
              // negative more often than not. Revisit with a per-item lookup.
            ),
          ),
        )
        .then((_) => _afterSeeAllReturn());
  }

  /// Refresh state that a See-All screen may have changed (Continue Watching
  /// progress/removal, bound sources) when it pops back to the board. Reload
  /// first, THEN refresh bound sources — _refreshBoundSources scans the CW lists
  /// that _loadContinueWatching replaces, so running them concurrently would
  /// count against the pre-reload item set.
  Future<void> _afterSeeAllReturn() async {
    // Fire-and-forget from route .then/onReturn callbacks, so guard against a
    // transient storage error becoming an unhandled async exception (a stale
    // refresh is recoverable; a crash-log isn't warranted).
    try {
      await _loadContinueWatching();
      await _refreshBoundSources();
    } catch (e) {
      debugPrint('SearchScreen: See-All return refresh failed: $e');
    }
  }

  /// Shared push for the Continue Watching "See All" grid (local + Trakt). The
  /// two sources differ only in title/items/callbacks/onReload and what to
  /// refresh on return.
  void _pushCwSeeAll({
    required String title,
    required String initialCategory,
    required List<StremioMeta> items,
    required double? Function(StremioMeta) progressOf,
    required void Function(StremioMeta) onOpen,
    required void Function(StremioMeta)? onQuickPlay,
    required Future<List<StremioMeta>> Function()? onReload,
    VoidCallback? onReturn,
  }) {
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => ContinueWatchingSeeAllScreen(
              title: title,
              initialCategory: initialCategory,
              items: List<StremioMeta>.of(items),
              progressOf: progressOf,
              onOpen: onOpen,
              onQuickPlay: onQuickPlay,
              onReload: onReload,
              // CW items are all rail-loaded, so _boundCounts covers them.
              isBound: _isBound,
              isTelevision: widget.isTelevision,
            ),
          ),
        )
        .then((_) => onReturn?.call());
  }

  /// Local Continue Watching "See All", pre-filtered to [initialCategory]
  /// ('movie' / 'series') of the row the user came from. Re-fetches (via
  /// onReload) whenever a detail/player route pops back onto it, so finished
  /// titles drop out and progress stays fresh.
  void _openContinueWatchingSeeAll([String initialCategory = 'all']) {
    _pushCwSeeAll(
      title: 'Continue Watching',
      initialCategory: initialCategory,
      items: _cwAll,
      progressOf: (m) => _cwProgress[m.imdbId],
      onOpen: _openContinueItem,
      onQuickPlay: _pikpakOnly ? null : _onContinuePlay,
      // Reload CW + refresh bound sources (sequenced), then hand the grid the
      // fresh list. This runs on every detail/player return AND keeps the board
      // beneath fresh, so no separate onReturn is needed (it would double the
      // reload when a detail-close is immediately followed by a board-return).
      onReload: () async {
        await _afterSeeAllReturn();
        return List<StremioMeta>.of(_cwAll);
      },
    );
  }

  /// Trakt "See All". Opens on Continue Watching (the row the user came from,
  /// handed in already-loaded) and lets them switch to any standard Trakt list
  /// — Watchlist, History, Collection, Ratings, Recommendations, Trending,
  /// Popular, Anticipated — from the in-screen "List" dropdown; those are
  /// fetched on demand inside [TraktSeeAllScreen].
  ///
  /// The Continue Watching grid keeps its snapshot (no per-return reload): a
  /// Trakt refresh is ~2+N API calls, so the board's rows refresh once when the
  /// screen pops. [_loadTraktContinueWatching] runs first (no bound pass), then
  /// [_afterSeeAllReturn] reloads local CW and runs the single bound-source
  /// refresh against both now-fresh lists (it swallows its own errors, so the
  /// bound refresh still happens even if the Trakt fetch fails).
  void _openTraktSeeAll([String initialCategory = 'all']) {
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => TraktSeeAllScreen(
              initialCategory: initialCategory,
              cwItems: List<StremioMeta>.of(_traktAll),
              // Pass the live progress map (read-only in the screen) so resume
              // bars reflect any refresh while the screen is open, matching the
              // old live-closure behaviour; items stay a snapshot so the grid
              // doesn't shift under the user.
              cwProgress: _traktProgress,
              onOpen: _openTraktItem,
              onQuickPlay: _pikpakOnly ? null : _playTraktItem,
              // CW items are all rail-loaded, so _boundCounts covers them.
              isBound: _isBound,
              isTelevision: widget.isTelevision,
            ),
          ),
        )
        .then((_) async {
          await _loadTraktContinueWatching(refreshBound: false);
          await _afterSeeAllReturn();
        });
  }

  /// Shared header for a board rail: a plain "Popular · Movies"-style title
  /// (Stremio keeps the type as quiet suffix text, not a coloured pill). The
  /// "See All" link is a mouse/tap affordance shown on desktop only — TV keeps
  /// the rail chrome-free and paginates as the user scrolls.
  Widget _railHeader({
    required String title,
    String? tag,
    VoidCallback? onSeeAll,
  }) {
    final tv = widget.isTelevision;
    return Padding(
      // Tighter vertically on TV so the current row's header + a peek of the
      // next row fit under the hero on short-canvas panels.
      padding: EdgeInsets.fromLTRB(24, tv ? 14 : 22, 24, tv ? 10 : 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text.rich(
              TextSpan(
                text: title,
                children: [
                  if (tag != null)
                    TextSpan(
                      text: '  ·  $tag',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.34),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              // Poppins for the rail titles too, so headings share one display
              // face; loosened from the old -0.2 tracking for the airier look.
              style: GoogleFonts.poppins(
                fontSize: tv ? 18 : 17,
                fontWeight: FontWeight.w600,
                letterSpacing: 0,
                color: Colors.white.withValues(alpha: 0.92),
              ),
            ),
          ),
          if (onSeeAll != null && !tv) _SeeAllLink(onTap: onSeeAll),
        ],
      ),
    );
  }

  Widget _buildRow(int rowIndex) {
    final section = _sections[rowIndex];
    final nodes = _rowNodes[rowIndex];
    final tv = widget.isTelevision;
    // Bigger, roomier posters on desktop (Stremio-scale); smaller on phones.
    final posterW = _railPosterW(context);
    final posterH = posterW * 3 / 2;
    // Titleless cells (Stremio-style) — just the 2:3 poster + a little headroom
    // for the hover/focus lift.
    final cellH = posterH;
    final rowH = cellH + 14;
    final typeLabel = _sectionTypeLabel(section);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _railHeader(
          title: section.title,
          tag: typeLabel,
          onSeeAll: () => _openCatalogSeeAll(section),
        ),
        SizedBox(
          height: rowH,
          child: NotificationListener<ScrollNotification>(
            onNotification: (n) {
              // Pull the next page as the row nears its right edge. Only this
              // row's horizontal scroll reaches here (the vertical board list is
              // an ancestor, so its notifications don't bubble down).
              if (n.metrics.axis == Axis.horizontal &&
                  n.metrics.pixels >=
                      n.metrics.maxScrollExtent - _kRowLoadMoreThreshold) {
                _loadMoreRow(rowIndex);
              }
              return false;
            },
            child: Builder(
              builder: (context) {
                // Rows start straight on the first poster (Stremio-style, no
                // leading See-All tile). DPAD-up from row 0 leaves the board;
                // col-0 DPAD-left drops to the sidebar (handled in _BoardCell
                // when onLeftEdge is null).
                VoidCallback up(int col) => rowIndex == 0
                    ? (_anyFavVisible
                          ? () => _focusFavRowAt(_favRowCount - 1, col)
                          : (_cwVisible
                                ? () => _focusCwRow(_cwRows.length - 1, col)
                                : () => _leaveBoardTop()))
                    : () => _focusRow(rowIndex - 1, col);
                VoidCallback down(int col) =>
                    () => _focusRow(rowIndex + 1, col);
                return ListView.builder(
                  scrollDirection: Axis.horizontal,
                  // Clip the horizontal viewport so scrolled-off cards don't paint
                  // over the sidebar to the left. rowH has enough headroom that the
                  // hover/focus lift still isn't clipped.
                  clipBehavior: Clip.hardEdge,
                  cacheExtent: 2000,
                  padding: const EdgeInsets.symmetric(horizontal: 13),
                  // +1 trailing paging spinner.
                  itemCount:
                      section.items.length + (section.loadingMore ? 1 : 0),
                  itemBuilder: (context, index) {
                    final col = index;
                    if (col >= section.items.length) {
                      return SizedBox(
                        width: 52,
                        height: cellH,
                        child: const Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      );
                    }
                    final item = section.items[col];
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 11),
                      child: Center(
                        child: SizedBox(
                          width: posterW,
                          height: cellH,
                          child: _BoardCell(
                            item: item,
                            isTelevision: tv,
                            focusNode: nodes[col],
                            column: col,
                            rowNodes: nodes,
                            hasBoundSource: _isBound(item),
                            onQuickPlay: _pikpakOnly
                                ? null
                                : () => _onCatalogPlay(item, section.addon),
                            onFocused: () => _setHero(item),
                            onUp: up(col),
                            onDown: down(col),
                            onOpen: () => _openItem(item, section.addon),
                            onNearEnd: () => _loadMoreRow(rowIndex),
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  /// Bottom-of-board loading indicator shown while more catalog rows stream in.
  Widget _buildBoardFooter() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 28),
      child: Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }

  /// A leading Continue Watching row (local or Trakt) — same poster cards as the
  /// catalog rows, plus a bottom progress bar and an optional type tag.
  /// [cwIndex] is this row's position among the visible CW rows and [cwCount]
  /// the total, so DPAD up/down can move between CW rows and into the catalog.
  /// [favCount] is the number of favourites rows just below, so the last CW
  /// row's DPAD-down lands on the first of them instead of the first catalog row.
  Widget _buildContinueWatchingRow(
    _CwRow row,
    int cwIndex,
    int cwCount,
    int favCount,
  ) {
    final tv = widget.isTelevision;
    final posterW = _railPosterW(context);
    final posterH = posterW * 3 / 2;
    final cellH = posterH;
    final rowH = cellH + 14;
    final items = row.items;
    final nodes = row.nodes;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _railHeader(title: row.title, tag: row.tag, onSeeAll: row.onSeeAll),
        SizedBox(
          height: rowH,
          child: Builder(
            builder: (context) {
              // Rows start on the first poster (no leading See-All tile). DPAD-up
              // from the first CW row leaves the board; col-0 DPAD-left drops to
              // the sidebar (handled in _BoardCell when onLeftEdge is null).
              VoidCallback up(int col) => cwIndex == 0
                  ? () => _leaveBoardTop()
                  : () => _focusCwRow(cwIndex - 1, col);
              VoidCallback down(int col) => cwIndex < cwCount - 1
                  ? () => _focusCwRow(cwIndex + 1, col)
                  : (favCount > 0
                        ? () => _focusFavRowAt(0, col)
                        : () => _focusRow(0, col));
              return ListView.builder(
                scrollDirection: Axis.horizontal,
                clipBehavior: Clip.hardEdge,
                cacheExtent: 2000,
                padding: const EdgeInsets.symmetric(horizontal: 13),
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final col = index;
                  final item = items[col];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 11),
                    child: Center(
                      child: SizedBox(
                        width: posterW,
                        height: cellH,
                        child: _BoardCell(
                          item: item,
                          isTelevision: tv,
                          focusNode: nodes[col],
                          column: col,
                          rowNodes: nodes,
                          hasBoundSource: _isBound(item),
                          progress: row.progressOf(item),
                          episodeLabel: row.episodeOf(item),
                          onQuickPlay: _pikpakOnly
                              ? null
                              : () => row.onQuickPlay(item),
                          onFocused: () => _setHero(item),
                          onUp: up(col),
                          onDown: down(col),
                          onOpen: () => row.onOpen(item),
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  /// A skeleton Trakt Continue Watching row shown while the account's fetch is
  /// still in flight (see [_traktReserving]). Sized identically to a real CW row
  /// — same header, poster width and cell height — so when the data arrives and
  /// replaces it there's zero layout shift. Purely decorative: no focus nodes,
  /// so the DPAD skips over it entirely. [idx] is 0 (Movies) or 1 (Shows).
  Widget _buildTraktSkeletonRow(int idx) {
    final posterW = _railPosterW(context);
    final cellH = posterW * 3 / 2;
    final rowH = cellH + 14;
    return _TraktSkeletonRow(
      header: _railHeader(
        title: 'Trakt Continue Watching',
        tag: idx == 0 ? 'Movies' : 'Shows',
      ),
      posterW: posterW,
      cellH: cellH,
      rowH: rowH,
    );
  }

  /// Dispatch to the right favourites-row builder for [kind]. [favIndex] is the
  /// row's position among the visible favourites rows and [cwCount] the number
  /// of Continue Watching rows above them (both drive the DPAD up/down wiring).
  Widget _buildFavRow(_FavKind kind, int favIndex, int cwCount) {
    switch (kind) {
      case _FavKind.iptv:
        return _buildIptvFavRow(favIndex, cwCount);
      case _FavKind.debrify:
        return _buildTvFavRow(favIndex, cwCount);
      case _FavKind.stremio:
        return _buildStremioTvFavRow(favIndex, cwCount);
      case _FavKind.playlist:
        return _buildPlaylistFavRow(favIndex, cwCount);
    }
  }

  /// Shared scaffold for a favourites row: a header (title + tag pills) above a
  /// horizontal strip of poster-shaped cards, sized exactly like the catalog
  /// rows so the whole board reads as one grid. [cellBuilder] gets the poster
  /// width and full cell height (poster + title band) for each column.
  Widget _buildFavRowShell({
    required String title,
    required List<Widget> tags,
    required int itemCount,
    required Widget Function(int col, double posterW, double cellH) cellBuilder,
  }) {
    final tv = widget.isTelevision;
    final posterW = _railPosterW(context);
    final posterH = posterW * 3 / 2;
    // Reserve the inline caption band so a long title — e.g. a full release-name
    // playlist item — doesn't overflow the cell into the next section's header.
    final cellH = posterH + _artPosterCaptionBand(context);
    final rowH = cellH + 14;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: tv ? 20 : 19,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
              for (final t in tags) ...[const SizedBox(width: 6), t],
            ],
          ),
        ),
        SizedBox(
          height: rowH,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.hardEdge,
            cacheExtent: 2000,
            padding: const EdgeInsets.symmetric(horizontal: 13),
            itemCount: itemCount,
            itemBuilder: (context, col) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 11),
                child: Center(
                  child: SizedBox(
                    width: posterW,
                    height: cellH,
                    child: cellBuilder(col, posterW, cellH),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// The "Debrify TV" row of favourited keyword channels, styled to match the
  /// catalog rows (same poster-shaped cards + title below).
  Widget _buildTvFavRow(int favIndex, int cwCount) {
    final tv = widget.isTelevision;
    return _buildFavRowShell(
      title: 'Debrify TV',
      tags: const [
        _CategoryTag('Channels'),
        // Make it explicit this row is the user's STARRED channels, not every
        // channel — otherwise people expect all channels here.
        _CategoryTag('Favorites', icon: Icons.star_rounded),
      ],
      itemCount: _tvFavChannels.length,
      cellBuilder: (col, posterW, cellH) {
        final channel = _tvFavChannels[col];
        final number = channel.channelNumber > 0
            ? channel.channelNumber
            : col + 1;
        return _FavArtCell(
          isTelevision: tv,
          column: col,
          rowNodes: _tvFavNodes,
          onUp: _favRowOnUp(favIndex, cwCount, col),
          onDown: _favRowOnDown(favIndex, col),
          // Debrify channels have no artwork — the glyph fallback + channel
          // number badge is the intended look.
          child: _ArtPoster(
            imageUrl: null,
            title: channel.name,
            badge: '$number',
            isTelevision: tv,
            focusNode: _tvFavNodes[col],
            onOpen: () => _playChannel(channel),
          ),
        );
      },
    );
  }

  /// The "Stremio TV" row of favourited channels. Each card shows the channel's
  /// current now-playing item poster (rotating on the same schedule as the Home
  /// / Stremio TV screens); tapping opens the channel.
  Widget _buildStremioTvFavRow(int favIndex, int cwCount) {
    final tv = widget.isTelevision;
    return _buildFavRowShell(
      title: 'Stremio TV',
      tags: const [
        _CategoryTag('Channels'),
        _CategoryTag('Favorites', icon: Icons.star_rounded),
      ],
      itemCount: _stvFavChannels.length,
      cellBuilder: (col, posterW, cellH) {
        final channel = _stvFavChannels[col];
        final item = _stvNowPlaying(channel)?.item;
        // Prefer the 2:3 poster for this poster-shaped tile; fall back to the
        // (landscape) background so channels whose now-playing meta lacks a
        // poster still show art instead of a blank glyph.
        final art = _firstNonEmpty(item?.poster, item?.background);
        return _FavArtCell(
          isTelevision: tv,
          column: col,
          rowNodes: _stvFavNodes,
          onUp: _favRowOnUp(favIndex, cwCount, col),
          onDown: _favRowOnDown(favIndex, col),
          child: _ArtPoster(
            imageUrl: art,
            title: channel.displayName,
            live: true,
            isTelevision: tv,
            focusNode: _stvFavNodes[col],
            onOpen: () => _playStremioTvChannel(channel),
          ),
        );
      },
    );
  }

  /// The "IPTV" row of favourited live channels. Cards show the channel logo
  /// (glyph fallback); tapping plays the stream directly.
  Widget _buildIptvFavRow(int favIndex, int cwCount) {
    final tv = widget.isTelevision;
    return _buildFavRowShell(
      title: 'IPTV',
      tags: const [
        _CategoryTag('Live'),
        _CategoryTag('Favorites', icon: Icons.star_rounded),
      ],
      itemCount: _iptvFavChannels.length,
      cellBuilder: (col, posterW, cellH) {
        final channel = _iptvFavChannels[col];
        return _FavArtCell(
          isTelevision: tv,
          column: col,
          rowNodes: _iptvFavNodes,
          onUp: _favRowOnUp(favIndex, cwCount, col),
          onDown: _favRowOnDown(favIndex, col),
          child: _ArtPoster(
            imageUrl: channel.logoUrl,
            title: channel.name,
            // Logos are usually square/wide, not 2:3 — contain so they aren't
            // cropped; the gradient shows around them.
            imageFit: BoxFit.contain,
            isTelevision: tv,
            focusNode: _iptvFavNodes[col],
            onOpen: () => _playIptvChannel(channel),
          ),
        );
      },
    );
  }

  /// The "Playlist" row of the user's saved items. Cards show the item poster
  /// with a resume-progress bar; tapping opens the full action menu
  /// ([_onPlaylistItemTap]) — this row is a complete playlist manager on its own.
  Widget _buildPlaylistFavRow(int favIndex, int cwCount) {
    final tv = widget.isTelevision;
    return _buildFavRowShell(
      title: 'Playlist',
      tags: const [_CategoryTag('Saved')],
      itemCount: _playlistItems.length,
      cellBuilder: (col, posterW, cellH) {
        final item = _playlistItems[col];
        final posterUrl = item['posterUrl'] as String?;
        final title = (item['title'] as String?) ?? 'Unknown';
        return _FavArtCell(
          isTelevision: tv,
          column: col,
          rowNodes: _playlistFavNodes,
          onUp: _favRowOnUp(favIndex, cwCount, col),
          onDown: _favRowOnDown(favIndex, col),
          child: _ArtPoster(
            imageUrl: posterUrl,
            title: title,
            progress: _playlistProgressFor(item),
            isTelevision: tv,
            focusNode: _playlistFavNodes[col],
            onOpen: () => _onPlaylistItemTap(item),
          ),
        );
      },
    );
  }

  Widget _message(IconData icon, String title, String body) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: scheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(
              title,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              body,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.5, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

/// The Stremio-style spotlight. Reflects the currently focused board title —
/// backdrop bleeding in from the right behind a left/bottom scrim, with title,
/// meta line and a short synopsis.
class _HeroSpotlight extends StatelessWidget {
  final StremioMeta item;
  final String? background;
  final String? description;
  final bool isTelevision;
  final double height;

  /// IMDb rating to show in the meta line (resolved by the host from the item
  /// or its enriched /meta details, since catalog list items often omit it).
  final double? rating;

  /// Compact layout for the Search tab: smaller title, single-line plot and
  /// tighter spacing so the whole spotlight fits a short strip without pushing
  /// the results off-screen.
  final bool compact;

  const _HeroSpotlight({
    required this.item,
    required this.background,
    required this.description,
    required this.isTelevision,
    required this.height,
    this.rating,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = (background != null && background!.isNotEmpty)
        ? background!
        : (item.poster ?? '');
    final metaParts = <String>[
      if (item.year != null && item.year!.isNotEmpty) item.year!,
      if (item.genres != null && item.genres!.isNotEmpty)
        item.genres!.take(2).join(' · '),
    ];

    return SizedBox(
      height: height,
      width: double.infinity,
      child: Stack(
        // Clip so a long title/plot can never bleed out of the hero into the
        // row header below it (the overflow bug on the compact Search hero).
        clipBehavior: Clip.hardEdge,
        fit: StackFit.expand,
        children: [
          if (bg.isNotEmpty)
            // Fade the backdrop's lower third to transparent so it melts into
            // the page's own gradient instead of ending on a hard horizontal
            // edge (the "seam"). The board rows then read as one surface with
            // the hero rather than two stacked boxes.
            ShaderMask(
              shaderCallback: (rect) => const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.white, Colors.white, Colors.transparent],
                stops: [0.0, 0.55, 1.0],
              ).createShader(rect),
              blendMode: BlendMode.dstIn,
              child: CachedNetworkImage(
                imageUrl: bg,
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
                errorWidget: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          // Left scrim for title/description legibility (vertical bands, so it
          // adds no horizontal seam). The bottom is handled by the image fade
          // above, letting the page background show through.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  scheme.surface.withValues(alpha: 0.92),
                  scheme.surface.withValues(alpha: 0.66),
                  scheme.surface.withValues(alpha: 0.10),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.34, 0.66, 1.0],
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomLeft,
            child: Padding(
              padding: EdgeInsets.fromLTRB(24, 0, 24, isTelevision ? 22 : 16),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: isTelevision ? 640 : 520),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.14),
                        ),
                      ),
                      child: Text(
                        item.type == 'series' ? 'SERIES' : 'MOVIE',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.6,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    SizedBox(height: compact ? 7 : 10),
                    Text(
                      item.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      // Poppins (rounded geometric) for the display title, airier
                      // and lighter than Inter-w800/-1 tracking — closer to
                      // Stremio's hero. Body/metadata stay on the Inter theme.
                      style: GoogleFonts.poppins(
                        fontSize: compact
                            ? (isTelevision ? 24 : 20)
                            : (isTelevision ? 38 : 26),
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0,
                        height: 1.06,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(height: compact ? 6 : 8),
                    Row(
                      children: [
                        if (rating != null) ...[
                          const Icon(
                            Icons.star_rounded,
                            size: 16,
                            color: HomeTheme.focusGold,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            rating!.toStringAsFixed(1),
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                          if (metaParts.isNotEmpty) _dot(),
                        ],
                        Flexible(
                          child: Text(
                            metaParts.join('   ·   '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.white.withValues(alpha: 0.82),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (description != null && description!.isNotEmpty) ...[
                      SizedBox(height: compact ? 6 : 10),
                      Text(
                        description!,
                        maxLines: compact ? 1 : (isTelevision ? 3 : 2),
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: compact ? 12.5 : (isTelevision ? 14.5 : 13),
                          height: compact ? 1.3 : 1.45,
                          color: Colors.white.withValues(alpha: 0.72),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dot() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 9),
    child: Container(
      width: 3,
      height: 3,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.4),
        shape: BoxShape.circle,
      ),
    ),
  );
}

/// Small pill next to a catalog-row header marking it as Movies / Series / etc.
/// An optional leading [icon] lets a pill carry meaning beyond the label (e.g.
/// a star on the Debrify TV "Favorites" pill).
class _CategoryTag extends StatelessWidget {
  final String label;
  final IconData? icon;
  const _CategoryTag(this.label, {this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: kStremioAccent.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: kStremioAccent.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: const Color(0xFFB9A9FF)),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFFB9A9FF),
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

/// A leading "Continue Watching" board row (local or Trakt). Carries its own
/// header, focus nodes, per-item progress lookup, and open / quick-play
/// handlers so the local and Trakt sources render through one row builder.
class _CwRow {
  final String title; // e.g. 'Continue Watching' or 'Trakt Movies'
  final String? tag; // 'Movies' / 'Series' pill, or null
  final List<StremioMeta> items;
  final List<FocusNode> nodes;
  final double? Function(StremioMeta) progressOf;

  /// Subtle 'S2 · E5' label for series cards (null for movies / when unknown).
  final String? Function(StremioMeta) episodeOf;
  final void Function(StremioMeta) onOpen;
  final void Function(StremioMeta) onQuickPlay;

  /// Opens the "See All" grid for this row's source, or null to hide the link.
  final VoidCallback? onSeeAll;

  const _CwRow({
    required this.title,
    required this.tag,
    required this.items,
    required this.nodes,
    required this.progressOf,
    required this.episodeOf,
    required this.onOpen,
    required this.onQuickPlay,
    this.onSeeAll,
  });
}

/// A reserved-but-not-yet-loaded Trakt row: a header above a strip of shimmer
/// poster placeholders (see [_SearchScreenState._buildTraktSkeletonRow]). Owns a
/// single repeating controller that drives every poster in the row, so a pair of
/// these reserves the Trakt slot with 2 tickers total — not one per poster —
/// which matters on the weak TV hardware this board targets.
class _TraktSkeletonRow extends StatefulWidget {
  final Widget header;
  final double posterW;
  final double cellH;
  final double rowH;

  const _TraktSkeletonRow({
    required this.header,
    required this.posterW,
    required this.cellH,
    required this.rowH,
  });

  @override
  State<_TraktSkeletonRow> createState() => _TraktSkeletonRowState();
}

class _TraktSkeletonRowState extends State<_TraktSkeletonRow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        widget.header,
        SizedBox(
          height: widget.rowH,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.hardEdge,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 13),
            itemCount: 6,
            itemBuilder: (context, index) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 11),
                child: Center(
                  child: _SkeletonPoster(
                    width: widget.posterW,
                    height: widget.cellH,
                    animation: _controller,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// A poster-shaped shimmer placeholder driven by a shared [animation], matching
/// the board's poster radius. Thin wrapper that sizes the shared [ShimmerBox].
class _SkeletonPoster extends StatelessWidget {
  final double width;
  final double height;
  final Animation<double> animation;

  const _SkeletonPoster({
    required this.width,
    required this.height,
    required this.animation,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: ShimmerBox(animation: animation),
    );
  }
}

/// [_StremioCard] plus DPAD arrow navigation. The card owns SELECT, its
/// focus visuals and ensureVisible; this ancestor [Focus] catches the arrows
/// the card ignores (left/right within the row, up/down to adjacent rows or
/// the search field) and reports focus to drive the hero.
class _BoardCell extends StatelessWidget {
  final StremioMeta item;
  final bool isTelevision;
  final FocusNode focusNode;
  final int column;
  final List<FocusNode> rowNodes;
  final bool hasBoundSource;

  /// 0..1 watched fraction — draws a bottom progress bar when non-null (used by
  /// the Continue Watching row). Null on regular catalog rows.
  final double? progress;

  /// Subtle 'S2 · E5' badge for a Continue Watching series card, or null.
  final String? episodeLabel;

  /// Long-press quick-play (mobile/desktop). Null hides the shortcut — used to
  /// mirror the catalog tiles' long-press-to-play when quick-play is available.
  final VoidCallback? onQuickPlay;
  final VoidCallback onFocused;
  final VoidCallback onUp;
  final VoidCallback onDown;
  final VoidCallback onOpen;

  /// Called when DPAD-right focus nears this row's last card, so the next page
  /// can be prefetched before the user runs out of cards. Null on rows that
  /// don't paginate (e.g. Continue Watching).
  final VoidCallback? onNearEnd;

  const _BoardCell({
    required this.item,
    required this.isTelevision,
    required this.focusNode,
    required this.column,
    required this.rowNodes,
    required this.hasBoundSource,
    this.progress,
    this.episodeLabel,
    this.onQuickPlay,
    required this.onFocused,
    required this.onUp,
    required this.onDown,
    required this.onOpen,
    this.onNearEnd,
  });

  KeyEventResult _handleArrows(FocusNode node, KeyEvent event) {
    if (!isTelevision || event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowLeft) {
      if (column > 0) {
        rowNodes[column - 1].requestFocus();
      } else {
        // First card in the row — leave to the sidebar (no leading tile now).
        MainPageBridge.focusTvSidebar?.call();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      // Prefetch the next page a few cards before the end so DPAD users never
      // hit a wall on a catalog that still has more.
      if (column >= rowNodes.length - 6) onNearEnd?.call();
      if (column < rowNodes.length - 1) {
        rowNodes[column + 1].requestFocus();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      onUp();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      onDown();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (has) {
        if (has) onFocused();
      },
      onKeyEvent: _handleArrows,
      child: _StremioCard(
        item: item,
        isTelevision: isTelevision,
        focusNode: focusNode,
        hasBoundSource: hasBoundSource,
        progress: progress,
        episodeLabel: episodeLabel,
        onQuickPlay: onQuickPlay,
        onOpen: onOpen,
      ),
    );
  }
}

/// Stremio-style poster card: clean rounded poster with a soft shadow that
/// lifts on hover/focus. Deliberately minimal — no title band, no MOVIE/rating
/// chips — so the artwork carries the rail exactly like Stremio's board.
class _StremioCard extends StatefulWidget {
  final StremioMeta item;
  final bool isTelevision;
  final FocusNode focusNode;
  final bool hasBoundSource;

  /// 0..1 watched fraction — draws a bottom progress bar when non-null.
  final double? progress;

  /// Subtle 'S2 · E5' badge for a Continue Watching series card, or null.
  final String? episodeLabel;

  /// Long-press quick-play (mobile/desktop). Null hides the shortcut.
  final VoidCallback? onQuickPlay;
  final VoidCallback onOpen;

  const _StremioCard({
    required this.item,
    required this.isTelevision,
    required this.focusNode,
    required this.hasBoundSource,
    this.progress,
    this.episodeLabel,
    this.onQuickPlay,
    required this.onOpen,
  });

  @override
  State<_StremioCard> createState() => _StremioCardState();
}

class _StremioCardState extends State<_StremioCard> {
  bool _focused = false;
  bool _hovered = false;
  bool _keyDown = false;
  bool get _active => _focused || _hovered;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final poster = item.poster;
    final fx = widget.isTelevision
        ? Duration.zero
        : const Duration(milliseconds: 160);

    final posterCard = AnimatedScale(
      duration: fx,
      curve: Curves.easeOutCubic,
      scale: _active ? 1.05 : 1.0,
      child: AspectRatio(
        aspectRatio: 2 / 3,
        child: AnimatedContainer(
          duration: fx,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: _active ? 0.6 : 0.35),
                blurRadius: _active ? 28 : 12,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (poster != null && poster.isNotEmpty)
                  CachedNetworkImage(
                    imageUrl: poster,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => _placeholder(item.name),
                    errorWidget: (_, __, ___) => _placeholder(item.name),
                  )
                else
                  _placeholder(item.name),
                if (widget.hasBoundSource)
                  const Positioned(
                    top: 8,
                    right: 8,
                    child: Icon(
                      Icons.bookmark_rounded,
                      size: 18,
                      color: Colors.white,
                      shadows: [Shadow(color: Colors.black, blurRadius: 6)],
                    ),
                  ),
                // Subtle season/episode badge for a Continue Watching series
                // card — sits just above the progress bar, bottom-left.
                if (widget.episodeLabel != null)
                  Positioned(
                    left: 6,
                    bottom: widget.progress != null ? 11 : 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.66),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        widget.episodeLabel!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                  ),
                // Continue Watching progress — a red bar pinned to the bottom of
                // the poster (Stremio-style, clipped to the rounded corners). A
                // faint dark track keeps it readable on bright posters.
                if (widget.progress != null)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      height: 5,
                      color: Colors.black.withValues(alpha: 0.45),
                      child: FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: widget.progress!.clamp(0.0, 1.0),
                        heightFactor: 1,
                        child: const ColoredBox(color: _kCwProgressRed),
                      ),
                    ),
                  ),
                // Selection ring — accent on TV focus, subtle white on hover.
                if (_active)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: widget.isTelevision
                                ? kStremioAccent
                                : Colors.white.withValues(alpha: 0.6),
                            width: widget.isTelevision ? 2.5 : 1.5,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );

    return Focus(
      focusNode: widget.focusNode,
      onFocusChange: (f) {
        setState(() => _focused = f);
        if (!f) _keyDown = false;
        if (f) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            Scrollable.ensureVisible(
              context,
              alignment: 0.5,
              alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
              duration: widget.isTelevision
                  ? Duration.zero
                  : const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
            );
          });
        }
      },
      onKeyEvent: (node, event) {
        if (isActivateKey(event.logicalKey) ||
            event.logicalKey == LogicalKeyboardKey.space) {
          if (event is KeyDownEvent) {
            _keyDown = true;
            return KeyEventResult.handled;
          } else if (event is KeyUpEvent) {
            if (_keyDown) widget.onOpen();
            _keyDown = false;
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: MouseRegion(
        onEnter: (_) {
          if (mounted) setState(() => _hovered = true);
        },
        onExit: (_) {
          if (mounted) setState(() => _hovered = false);
        },
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onOpen,
          onLongPress: widget.onQuickPlay,
          behavior: HitTestBehavior.opaque,
          // No title beneath the poster — Stremio lets the artwork carry the
          // rail; the title lives on the hero (focused) and the detail page.
          child: posterCard,
        ),
      ),
    );
  }

  Widget _placeholder(String title) {
    return Container(
      color: const Color(0xFF15151F),
      alignment: Alignment.center,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Text(
          title,
          textAlign: TextAlign.center,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.5),
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/// The "See All ›" affordance in a rail header — a mouse/tap entry to the
/// full-screen See-All screen, shown on desktop only. Kept understated (quiet
/// grey that brightens on hover, no accent fill) so it doesn't compete with the
/// posters. TV rails are chrome-free and paginate on scroll instead.
class _SeeAllLink extends StatefulWidget {
  final VoidCallback onTap;
  const _SeeAllLink({required this.onTap});

  @override
  State<_SeeAllLink> createState() => _SeeAllLinkState();
}

class _SeeAllLinkState extends State<_SeeAllLink> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final color = _hover ? Colors.white : Colors.white.withValues(alpha: 0.5);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
          decoration: BoxDecoration(
            color: _hover
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'See All',
                style: TextStyle(
                  color: color,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right_rounded, size: 17, color: color),
            ],
          ),
        ),
      ),
    );
  }
}

/// The kinds of leading favourites rows. Render order (Playlist, Debrify TV,
/// Stremio TV, IPTV) is defined by [_SearchScreenState._favRowKinds], the single
/// source of truth for both rendering and the index-based DPAD focus wiring.
enum _FavKind { iptv, debrify, stremio, playlist }

/// Generic DPAD arrow-handling wrapper for a favourites-row card — the arrow
/// counterpart to [_BoardCell] for the IPTV / Debrify TV / Stremio TV rows.
/// Holds no focus itself — the inner [_ArtPoster] does; this only routes
/// left/right within the row and up/down out of it, matching the catalog
/// cards' navigation exactly.
class _FavArtCell extends StatelessWidget {
  final bool isTelevision;
  final int column;
  final List<FocusNode> rowNodes;
  final VoidCallback onUp;
  final VoidCallback onDown;
  final Widget child;

  const _FavArtCell({
    required this.isTelevision,
    required this.column,
    required this.rowNodes,
    required this.onUp,
    required this.onDown,
    required this.child,
  });

  KeyEventResult _handleArrows(FocusNode node, KeyEvent event) {
    if (!isTelevision || event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowLeft) {
      if (column > 0) {
        rowNodes[column - 1].requestFocus();
      } else {
        MainPageBridge.focusTvSidebar?.call();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      if (column < rowNodes.length - 1) {
        rowNodes[column + 1].requestFocus();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      onUp();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      onDown();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _handleArrows,
      child: child,
    );
  }
}

/// Stremio-shaped artwork card for a favourite that has a real image (a Stremio
/// TV channel's now-playing poster, or an IPTV channel's logo). Shows the image
/// over a purple gradient — with a live-TV glyph fallback when it's missing or
/// fails to load — and the title below, matching [_StremioCard]'s size, corner
/// radius, hover/focus lift and selection ring so the row reads as one board.
class _ArtPoster extends StatefulWidget {
  final String? imageUrl;
  final String title;

  /// How the image fills the 2:3 tile — cover for posters, contain for logos.
  final BoxFit imageFit;

  /// Optional top-left badge text (e.g. a channel number) drawn over the tile.
  final String? badge;

  /// When true, a red "LIVE" pill is drawn top-right — signalling that this is a
  /// channel and the artwork is what's playing on it right now.
  final bool live;

  /// Optional resume-progress fraction (0..1). When set, a thin progress bar is
  /// drawn along the bottom edge of the poster (used by the Playlist row).
  final double? progress;
  final bool isTelevision;
  final FocusNode focusNode;
  final VoidCallback onOpen;

  const _ArtPoster({
    required this.imageUrl,
    required this.title,
    required this.isTelevision,
    required this.focusNode,
    required this.onOpen,
    this.imageFit = BoxFit.cover,
    this.badge,
    this.live = false,
    this.progress,
  });

  @override
  State<_ArtPoster> createState() => _ArtPosterState();
}

class _ArtPosterState extends State<_ArtPoster> {
  bool _focused = false;
  bool _hovered = false;
  bool _keyDown = false;
  bool get _active => _focused || _hovered;

  Widget _glyph() {
    return Center(
      child: Icon(
        Icons.live_tv_rounded,
        size: 40,
        color: kStremioAccent.withValues(alpha: _active ? 1 : 0.85),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fx = widget.isTelevision
        ? Duration.zero
        : const Duration(milliseconds: 160);
    final url = widget.imageUrl;
    final hasImage = url != null && url.isNotEmpty;

    final posterCard = AnimatedScale(
      duration: fx,
      curve: Curves.easeOutCubic,
      scale: _active ? 1.05 : 1.0,
      child: AspectRatio(
        aspectRatio: 2 / 3,
        child: AnimatedContainer(
          duration: fx,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: _active ? 0.6 : 0.35),
                blurRadius: _active ? 28 : 12,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Base gradient — the fallback backdrop and the ground behind
                // any letterboxed (contain-fit) logo.
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0xFF2A1D5C),
                        Color(0xFF1A1440),
                        Color(0xFF0D0B1A),
                      ],
                      stops: [0.0, 0.55, 1.0],
                    ),
                  ),
                ),
                if (hasImage)
                  Padding(
                    padding: widget.imageFit == BoxFit.contain
                        ? const EdgeInsets.all(12)
                        : EdgeInsets.zero,
                    child: CachedNetworkImage(
                      imageUrl: url,
                      fit: widget.imageFit,
                      placeholder: (_, __) => _glyph(),
                      errorWidget: (_, __, ___) => _glyph(),
                    ),
                  )
                else
                  _glyph(),
                // Optional channel-number badge, top-left.
                if (widget.badge != null)
                  Positioned(
                    top: 10,
                    left: 10,
                    child: Text(
                      widget.badge!,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                // "LIVE" pill, top-right — marks this as a channel currently
                // playing the shown artwork.
                if (widget.live)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: _kCwProgressRed,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Text(
                            'LIVE',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.6,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                // Resume-progress bar along the bottom edge (Playlist row).
                if (widget.progress != null && widget.progress! > 0)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: SizedBox(
                      height: 4,
                      child: Stack(
                        children: [
                          Container(color: Colors.black.withValues(alpha: 0.4)),
                          FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor: widget.progress!,
                            child: Container(color: _kCwProgressRed),
                          ),
                        ],
                      ),
                    ),
                  ),
                // Selection ring — accent on TV focus, subtle white on hover.
                if (_active)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: widget.isTelevision
                                ? kStremioAccent
                                : Colors.white.withValues(alpha: 0.6),
                            width: widget.isTelevision ? 2.5 : 1.5,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );

    return Focus(
      focusNode: widget.focusNode,
      onFocusChange: (f) {
        setState(() => _focused = f);
        if (!f) _keyDown = false;
        if (f) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            Scrollable.ensureVisible(
              context,
              alignment: 0.5,
              alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
              duration: widget.isTelevision
                  ? Duration.zero
                  : const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
            );
          });
        }
      },
      onKeyEvent: (node, event) {
        if (isActivateKey(event.logicalKey) ||
            event.logicalKey == LogicalKeyboardKey.space) {
          if (event is KeyDownEvent) {
            _keyDown = true;
            return KeyEventResult.handled;
          } else if (event is KeyUpEvent) {
            if (_keyDown) widget.onOpen();
            _keyDown = false;
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: MouseRegion(
        onEnter: (_) {
          if (mounted) setState(() => _hovered = true);
        },
        onExit: (_) {
          if (mounted) setState(() => _hovered = false);
        },
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onOpen,
          behavior: HitTestBehavior.opaque,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              posterCard,
              const SizedBox(height: _kArtTitleGap),
              Text(
                widget.title,
                textAlign: TextAlign.center,
                maxLines: _kArtTitleMaxLines,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _active
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.92),
                  fontSize: _kArtTitleFontSize,
                  fontWeight: FontWeight.w600,
                  height: _kArtTitleHeight,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A single row in the playlist item action menu ([_onPlaylistItemTap]). Ported
/// from the Home playlist section so the Search Playlist row is a self-contained
/// manager; keyboard/DPAD focusable with a highlight on focus.
class _PlaylistMenuItem extends StatefulWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final Color? subtitleColor;
  final VoidCallback onTap;
  final bool autofocus;
  final bool isTelevision;

  const _PlaylistMenuItem({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.onTap,
    this.subtitleColor,
    this.autofocus = false,
    this.isTelevision = false,
  });

  @override
  State<_PlaylistMenuItem> createState() => _PlaylistMenuItemState();
}

class _PlaylistMenuItemState extends State<_PlaylistMenuItem> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      autofocus: widget.autofocus,
      canRequestFocus: true,
      onTap: widget.onTap,
      onFocusChange: (f) => setState(() => _focused = f),
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: Duration(milliseconds: widget.isTelevision ? 0 : 150),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: _focused
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: widget.color.withValues(alpha: _focused ? 0.2 : 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(widget.icon, size: 18, color: widget.color),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.label,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    widget.subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color:
                          widget.subtitleColor ??
                          Colors.white.withValues(alpha: 0.4),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Catalog / Keyword segmented toggle.
class _ModeToggle extends StatelessWidget {
  final _Mode mode;
  final bool isTelevision;

  /// When true the two segments split the full available width (used when the
  /// toggle is stacked below the search box on narrow screens).
  final bool fullWidth;
  final ValueChanged<_Mode> onChanged;

  /// TV-only DPAD focus nodes for the two segments (null off-TV, where the
  /// InkWell handles pointer taps and normal Tab traversal instead).
  final FocusNode? catalogNode;
  final FocusNode? keywordNode;

  /// Leave the toggle back to the search field (arrow-up, or arrow-left off the
  /// leftmost segment) / down into the board content.
  final VoidCallback? onLeaveToField;
  final VoidCallback? onLeaveToContent;

  const _ModeToggle({
    required this.mode,
    required this.isTelevision,
    required this.onChanged,
    this.fullWidth = false,
    this.catalogNode,
    this.keywordNode,
    this.onLeaveToField,
    this.onLeaveToContent,
  });

  /// DPAD handling for a focused segment: select switches mode, arrows move
  /// between the segments and out to the field (up/left) or content (down).
  KeyEventResult _handleSegmentKey(_Mode value, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (isActivateKey(key) || key == LogicalKeyboardKey.space) {
      onChanged(value);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      onLeaveToField?.call();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      onLeaveToContent?.call();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      if (value == _Mode.keyword) {
        catalogNode?.requestFocus();
      } else {
        onLeaveToField?.call();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      if (value == _Mode.catalog) keywordNode?.requestFocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final catalog = _segment(
      context,
      _Mode.catalog,
      'Catalog',
      Icons.grid_view_rounded,
    );
    final keyword = _segment(
      context,
      _Mode.keyword,
      'Keyword',
      Icons.bolt_rounded,
    );
    return Container(
      height: isTelevision ? 54 : 48,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        mainAxisSize: fullWidth ? MainAxisSize.max : MainAxisSize.min,
        children: fullWidth
            ? [Expanded(child: catalog), Expanded(child: keyword)]
            : [catalog, keyword],
      ),
    );
  }

  Widget _segment(
    BuildContext context,
    _Mode value,
    String label,
    IconData icon,
  ) {
    final on = mode == value;
    final node = value == _Mode.catalog ? catalogNode : keywordNode;

    Widget content(bool focused) => AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: EdgeInsets.symmetric(horizontal: isTelevision ? 16 : 12),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: on ? kStremioAccent : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        // A white ring shows the remote's DPAD position. Drawn whenever the
        // segment is focused — including the selected one, since focus lands
        // there first (its accent fill alone wouldn't signal focus moved).
        border: Border.all(
          color: focused
              ? Colors.white.withValues(alpha: 0.9)
              : Colors.transparent,
          width: 2,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 16,
            color: on
                ? Colors.white
                : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: isTelevision ? 14 : 13,
              fontWeight: FontWeight.w700,
              color: on
                  ? Colors.white
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );

    if (node == null) {
      return InkWell(
        onTap: () => onChanged(value),
        borderRadius: BorderRadius.circular(10),
        child: content(false),
      );
    }

    // The wrapping Focus owns the keyboard/DPAD focus node; the InkWell stays
    // pointer-only (canRequestFocus:false) so it doesn't compete for focus.
    return Focus(
      focusNode: node,
      onKeyEvent: (n, event) => _handleSegmentKey(value, event),
      child: Builder(
        builder: (context) {
          final focused = Focus.of(context).hasFocus;
          return InkWell(
            onTap: () => onChanged(value),
            borderRadius: BorderRadius.circular(10),
            canRequestFocus: false,
            child: content(focused),
          );
        },
      ),
    );
  }
}

/// A pushable manual sources list for a catalog title/episode. Searches its own
/// torrent sources (own loading), renders them as [TorrentResultRow]s, and on
/// tap plays via the isolated service with the FULL source list + content
/// metadata (so the in-player Sources switcher + Continue Watching both work).
class _SourcesScreen extends StatefulWidget {
  final AdvancedSearchSelection selection;
  final PlaybackMeta meta;
  final bool isTelevision;

  /// When true the screen is a source PICKER: tapping a row pins it as the
  /// bound source and pops (used by the "Select Source" entry points). When
  /// false it's the normal Sources list: tap plays, long-press pins/unpins.
  final bool bindMode;

  /// When non-null the screen searches TORRENTS BY FREE-TEXT KEYWORD (seeded
  /// with this query, editable) instead of by the selection's IMDb id — used by
  /// the "Keyword Search" add-source option. Implies [bindMode]. The selection
  /// still supplies the pin target (imdbId / movie-vs-series).
  final String? keywordSeed;

  const _SourcesScreen({
    required this.selection,
    required this.meta,
    required this.isTelevision,
    this.bindMode = false,
    this.keywordSeed,
  });

  @override
  State<_SourcesScreen> createState() => _SourcesScreenState();
}

class _SourcesScreenState extends State<_SourcesScreen> {
  bool _loading = true;
  String? _error;
  List<Torrent> _torrents = [];
  final List<FocusNode> _nodes = [];
  List<SeriesSource> _bound = [];

  /// Free-text keyword-bind mode: an editable query that seeds a pack search.
  bool get _keywordMode => widget.keywordSeed != null;
  late final TextEditingController _kwCtrl;
  String _query = '';

  /// Monotonic guard so a slow earlier search can't clobber a newer one.
  int _searchToken = 0;

  String get _imdbId => widget.selection.imdbId;
  bool get _isMovie => !widget.selection.isSeries;
  Set<String> get _boundHashes => _bound.map((s) => s.torrentHash).toSet();

  @override
  void initState() {
    super.initState();
    _query = widget.keywordSeed ?? '';
    _kwCtrl = TextEditingController(text: _query);
    _load();
  }

  @override
  void dispose() {
    _kwCtrl.dispose();
    for (final n in _nodes) {
      n.dispose();
    }
    super.dispose();
  }

  Future<void> _reloadBound() async {
    final bound = _imdbId.isEmpty
        ? <SeriesSource>[]
        : await SeriesSourceService.getSources(_imdbId);
    if (!mounted) return;
    setState(() => _bound = bound);
  }

  Future<void> _load() async {
    await _reloadBound();
    await _runSearch();
  }

  /// Series pack/bind post-filter — ported verbatim from the old Home
  /// ([TorrentSearchScreen]) so this Sources list matches it. For a series with
  /// no specific episode: (1) drop direct-link (single-episode) streams — they
  /// can't be a season/series pack; (2) when a season is requested but no
  /// episode, keep only torrents that cover that season.
  List<Torrent> _filterSeriesPacks(
    List<Torrent> torrents,
    AdvancedSearchSelection sel,
  ) {
    var filtered = torrents;

    // Direct links are individual episode streams that can't be added as a
    // season/series pack. Movies are single files, so they're left alone.
    if (sel.isSeries && sel.episode == null) {
      filtered = filtered
          .where((torrent) => torrent.streamType == StreamType.torrent)
          .toList(growable: false);
    }

    // Filter by season when a season is specified but no episode, so only
    // torrents that include the requested season remain.
    if (sel.isSeries && sel.season != null && sel.episode == null) {
      final requestedSeason = sel.season!;
      filtered = filtered
          .where((torrent) {
            switch (torrent.coverageType) {
              case 'completeSeries':
                // Always include complete series (they include all seasons).
                return true;
              case 'multiSeasonPack':
                // Include if the requested season is within the range.
                if (torrent.startSeason != null && torrent.endSeason != null) {
                  return torrent.startSeason! <= requestedSeason &&
                      torrent.endSeason! >= requestedSeason;
                }
                // If season range data is missing, exclude to be safe.
                return false;
              case 'seasonPack':
                // Include only if it matches the requested season exactly.
                return torrent.seasonNumber == requestedSeason;
              case 'singleEpisode':
                // Keep only if the name resolves to the requested season.
                final name = torrent.name.toUpperCase();
                final seasonPadded =
                    requestedSeason.toString().padLeft(2, '0');
                final seasonPatterns = [
                  'S$seasonPadded', // S04
                  'S$requestedSeason', // S4
                  'SEASON $requestedSeason', // Season 4
                  'SEASON$requestedSeason', // Season4
                  '${requestedSeason}X', // 4x (for 4x01 format)
                ];
                for (final pattern in seasonPatterns) {
                  if (name.contains(pattern)) return true;
                }
                // If we can't determine the season, exclude the single episode.
                return false;
              default:
                // Unknown coverage type — keep it to avoid over-filtering.
                return true;
            }
          })
          .toList(growable: false);
    }
    return filtered;
  }

  /// Order a series pack search exactly like the old Home's default "relevance"
  /// sort: coverage priority ascending (completeSeries → multiSeason →
  /// seasonPack → singleEpisode), then season count descending, then the search
  /// service's existing seeders-descending order (preserved via a stable index
  /// tiebreak). Only applies to a series search with no specific episode.
  List<Torrent> _sortSeriesPacks(
    List<Torrent> torrents,
    AdvancedSearchSelection sel,
  ) {
    if (!(sel.isSeries && sel.episode == null) || torrents.length < 2) {
      return torrents;
    }
    final indexed = [
      for (var i = 0; i < torrents.length; i++) (i, torrents[i]),
    ];
    indexed.sort((a, b) {
      final c = a.$2.coveragePriority.compareTo(b.$2.coveragePriority);
      if (c != 0) return c;
      final s = b.$2.seasonCount.compareTo(a.$2.seasonCount); // more seasons first
      if (s != 0) return s;
      return a.$1.compareTo(b.$1); // stable → keeps seeders-desc within a tier
    });
    return [for (final e in indexed) e.$2];
  }

  /// Run the source search (free-text keyword pack search in keyword-bind mode,
  /// otherwise the IMDb-exact search) and rebuild the row focus nodes. Guarded
  /// by a token so a slow earlier re-search can't clobber a newer one's results
  /// or leak its focus nodes.
  Future<void> _runSearch() async {
    final token = ++_searchToken;
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    for (final n in _nodes) {
      n.dispose();
    }
    _nodes.clear();
    try {
      final sel = widget.selection;
      // Match Home's Sources list: the Stremio-aware search returns BOTH torrents
      // AND addon direct-link streams for movies/series, and resolves IPTV/non-IMDb
      // items straight from the addon (it skips the on-device torrent engines for
      // non-standard content types by contentType). Previously this path was
      // torrent-only, so addon direct links never appeared in the Search tab's
      // Sources list even though Home showed them.
      final res = _keywordMode
          ? await TorrentService.searchAllEngines(_query)
          : await TorrentService.searchByImdbWithStremio(
              sel.imdbId,
              isMovie: !sel.isSeries,
              season: sel.season,
              episode: sel.episode,
              contentType: sel.contentType,
            );
      if (!mounted || token != _searchToken) return;
      final rawTorrents = (res['torrents'] as List).cast<Torrent>();
      // Series pack/bind post-processing — ported from the old Home
      // (torrent_search_screen) so this list matches: for a series with no
      // specific episode, drop direct-link (single-episode) streams, season-
      // filter when a season is requested, then float season/complete packs to
      // the top (coverage priority).
      final torrents = _sortSeriesPacks(
        _filterSeriesPacks(rawTorrents, sel),
        sel,
      );
      for (var i = 0; i < torrents.length; i++) {
        _nodes.add(FocusNode(debugLabel: 'src_$i'));
      }
      setState(() {
        _torrents = torrents;
        _loading = false;
      });
      // On TV the list is the only content — give the D-pad an anchor to move
      // from, otherwise the remote has nothing focused and can't select a row.
      if (widget.isTelevision && _nodes.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _nodes.first.requestFocus();
        });
      }
    } catch (e) {
      if (!mounted || token != _searchToken) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _submitKeyword(String q) {
    final trimmed = q.trim();
    if (trimmed.isEmpty || trimmed == _query) return;
    _query = trimmed;
    _runSearch();
  }

  bool _pinning = false;

  void _play(Torrent t, int i) {
    // Swallow a SELECT that leaks through as the row menu / provider picker
    // closes on TV (armed via DialogTapGuard.markKeyAction in the menu).
    if (DialogTapGuard.shouldIgnoreTap()) return;
    _playNow(t, i);
  }

  void _playNow(Torrent t, int i) {
    unawaited(
      TorrentPlaybackService.activateTorrent(
        context,
        t,
        meta: widget.meta,
        sources: _torrents,
        sourceIndex: i,
        searchKeyword: widget.selection.title,
      ),
    );
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _pin(Torrent t) async {
    // Direct / external streams have no infohash/magnet to bind as a reusable
    // source — reject rather than store a broken pin.
    if (t.isDirectStream || t.isExternalStream) {
      _snack("Direct streams can't be pinned as a source.");
      return;
    }
    if (_pinning) return; // guard concurrent binds (double-tap on TV)
    _pinning = true;
    try {
      final ok = await TorrentPlaybackService.bindSource(
        context,
        t,
        imdbId: _imdbId,
        isMovie: _isMovie,
      );
      if (!mounted) return;
      if (ok) {
        await _reloadBound();
        if (widget.bindMode && mounted) Navigator.of(context).pop();
      }
    } finally {
      _pinning = false;
    }
  }

  Future<void> _unpin(String hash) async {
    await SeriesSourceService.removeSourceByHash(_imdbId, hash);
    await _reloadBound();
  }

  Future<void> _pinLocal() async {
    if (_pinning) return;
    _pinning = true;
    try {
      final ok = await TorrentPlaybackService.bindLocalSource(
        context,
        imdbId: _imdbId,
        isMovie: _isMovie,
        title: widget.selection.title,
        year: widget.selection.year,
      );
      if (!mounted) return;
      if (ok) {
        await _reloadBound();
        if (widget.bindMode && mounted) Navigator.of(context).pop();
      }
    } finally {
      _pinning = false;
    }
  }

  void _showRowMenu(Torrent t, int i) {
    // Direct / external addon streams have no infohash to pin — offer the
    // stream-appropriate actions (play/open + copy link), mirroring Home's
    // direct-stream action sheet.
    if (t.isDirectStream || t.isExternalStream) {
      _showStreamRowMenu(t, i);
      return;
    }
    final bound = _boundHashes.contains(t.infohash);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF0F172A),
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(
                Icons.play_arrow_rounded,
                color: Colors.white,
              ),
              title: const Text('Play', style: TextStyle(color: Colors.white)),
              onTap: () {
                DialogTapGuard.markKeyAction();
                Navigator.of(sheetCtx).pop();
                _playNow(t, i);
              },
            ),
            ListTile(
              leading: Icon(
                bound ? Icons.link_off_rounded : Icons.link_rounded,
                color: const Color(0xFFF59E0B),
              ),
              title: Text(
                bound ? 'Unpin source' : 'Pin as source',
                style: const TextStyle(color: Colors.white),
              ),
              subtitle: Text(
                bound
                    ? 'Stop reusing this source'
                    : 'Reuse this source for instant playback',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
              ),
              onTap: () {
                DialogTapGuard.markKeyAction();
                Navigator.of(sheetCtx).pop();
                if (bound) {
                  unawaited(_unpin(t.infohash));
                } else {
                  unawaited(_pin(t));
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Options sheet for a direct / external addon stream: play (in-app) or open
  /// (external), plus copy the stream URL. No "Pin as source" — streams have no
  /// infohash to bind.
  void _showStreamRowMenu(Torrent t, int i) {
    final external = t.isExternalStream;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF0F172A),
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(
                external ? Icons.open_in_new_rounded : Icons.play_arrow_rounded,
                color: Colors.white,
              ),
              title: Text(
                external ? 'Open externally' : 'Play now',
                style: const TextStyle(color: Colors.white),
              ),
              subtitle: Text(
                external
                    ? 'Open this link in your browser'
                    : 'Stream directly — no debrid needed',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
              ),
              onTap: () {
                DialogTapGuard.markKeyAction();
                Navigator.of(sheetCtx).pop();
                _playNow(t, i);
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy_rounded, color: Color(0xFFF59E0B)),
              title: const Text(
                'Copy URL',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () async {
                DialogTapGuard.markKeyAction();
                Navigator.of(sheetCtx).pop();
                final url = t.directUrl ?? '';
                if (url.isEmpty) {
                  _snack('No stream URL available.');
                  return;
                }
                await Clipboard.setData(ClipboardData(text: url));
                _snack('URL copied to clipboard');
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        title: Text(
          _keywordMode
              ? 'Find a source for ${widget.selection.title}'
              : widget.bindMode
              ? 'Pick a source for ${widget.selection.title}'
              : widget.selection.formattedLabel,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          // Pin an on-device file/folder as the source. Desktop only — hidden on
          // Android/iOS (incl. Android TV) where local binding is unavailable, so
          // it's never a dead-end D-pad stop.
          if (_imdbId.isNotEmpty &&
              TorrentPlaybackService.localBindingAvailable)
            IconButton(
              tooltip: 'Pin an on-device file or folder',
              icon: const Icon(Icons.folder_open_rounded),
              onPressed: () => unawaited(_pinLocal()),
            ),
        ],
      ),
      body: Column(
        children: [
          if (_keywordMode) _keywordSearchField(scheme),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? _centered(scheme, 'Search failed.\n$_error')
                : Column(
                    children: [
                      if (_bound.isNotEmpty) _pinnedBanner(),
                      Expanded(
                        child: _torrents.isEmpty
                            ? _centered(scheme, 'No sources found.')
                            : ListView.builder(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                ),
                                cacheExtent: 1200,
                                itemCount: _torrents.length,
                                itemBuilder: (context, i) {
                                  final t = _torrents[i];
                                  return TorrentResultRow(
                                    torrent: t,
                                    index: i,
                                    focusNode: _nodes[i],
                                    isTelevision: widget.isTelevision,
                                    qualityTier: t.qualityTier,
                                    onTap: () {
                                      if (widget.bindMode) {
                                        unawaited(_pin(t));
                                      } else {
                                        _play(t, i);
                                      }
                                    },
                                    onLongPress: () => _showRowMenu(t, i),
                                    onNavigateUp: () {
                                      if (i > 0) _nodes[i - 1].requestFocus();
                                    },
                                    onNavigateDown: () {
                                      if (i < _nodes.length - 1) {
                                        _nodes[i + 1].requestFocus();
                                      }
                                    },
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  /// Editable free-text search box shown at the top of the keyword-bind screen.
  Widget _keywordSearchField(ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      child: TextField(
        controller: _kwCtrl,
        textInputAction: TextInputAction.search,
        onSubmitted: _submitKeyword,
        style: TextStyle(color: scheme.onSurface),
        decoration: InputDecoration(
          hintText: 'Search torrents by keyword',
          prefixIcon: const Icon(Icons.search_rounded),
          suffixIcon: IconButton(
            tooltip: 'Search',
            icon: const Icon(Icons.arrow_forward_rounded),
            onPressed: () => _submitKeyword(_kwCtrl.text),
          ),
          filled: true,
          fillColor: scheme.surfaceContainerHighest,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  Widget _pinnedBanner() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFF59E0B).withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.link_rounded,
                color: Color(0xFFF59E0B),
                size: 16,
              ),
              const SizedBox(width: 6),
              Text(
                _bound.length == 1 ? 'Pinned source' : 'Pinned sources',
                style: const TextStyle(
                  color: Color(0xFFF59E0B),
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ..._bound.map(
            (s) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      s.torrentName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: () => unawaited(_unpin(s.torrentHash)),
                    borderRadius: BorderRadius.circular(8),
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(
                        Icons.close_rounded,
                        color: Colors.white70,
                        size: 18,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _centered(ColorScheme scheme, String text) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(color: scheme.onSurfaceVariant),
      ),
    ),
  );
}

/// Active-sources checklist for keyword search: toggle which torrent engines
/// are queried. Backed by [SettingsManager] (same store Home uses), so changes
/// persist and apply to the next search.
class _KeywordSourcesDialog extends StatefulWidget {
  const _KeywordSourcesDialog();

  @override
  State<_KeywordSourcesDialog> createState() => _KeywordSourcesDialogState();
}

class _KeywordSourcesDialogState extends State<_KeywordSourcesDialog> {
  final SettingsManager _settings = SettingsManager();
  List<DynamicEngine> _engines = [];
  final Map<String, bool> _enabled = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final engines = EngineRegistry.instance.getKeywordSearchEngines();
    for (final e in engines) {
      _enabled[e.name] = await _settings.getEnabled(e.name, true);
    }
    if (!mounted) return;
    setState(() {
      _engines = engines;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      backgroundColor: scheme.surfaceContainerHigh,
      title: const Text('Active sources'),
      content: SizedBox(
        width: 360,
        child: _loading
            ? const SizedBox(
                height: 80,
                child: Center(child: CircularProgressIndicator()),
              )
            : _engines.isEmpty
            ? const Text('No search sources installed.')
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: _engines.map((e) {
                    final on = _enabled[e.name] ?? true;
                    return SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text(e.displayName),
                      value: on,
                      onChanged: (v) {
                        setState(() => _enabled[e.name] = v);
                        _settings.setEnabled(e.name, v);
                      },
                    );
                  }).toList(),
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ],
    );
  }
}
