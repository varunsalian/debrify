import 'dart:async';
import 'dart:math';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/advanced_search_selection.dart';
import '../models/stremio_addon.dart';
import '../models/torrent.dart';
import '../models/torrent_filter_state.dart';
import '../services/engine/dynamic_engine.dart';
import '../services/engine/engine_registry.dart';
import '../services/engine/settings_manager.dart';
import '../services/local_bound_source_service.dart';
import '../services/main_page_bridge.dart';
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
import '../utils/dialog_tap_guard.dart';
import '../utils/torrent_filter_matcher.dart';
import '../utils/tv_keys.dart';
import '../widgets/add_source_picker_dialog.dart';
import '../widgets/home/home_theme.dart';
import '../widgets/torrent_filters_sheet.dart';
import '../widgets/torrent_result_row.dart';
import '../widgets/trakt/trakt_menu_helpers.dart';
import 'catalog_item_detail_screen.dart';
import 'debrid_downloads_screen.dart';
import 'episodes_screen.dart';
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

  const SearchScreen({super.key, this.isTelevision = false});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

enum _Mode { catalog, keyword }

class _SearchScreenState extends State<SearchScreen> {
  static const int _tabIndex = 15;

  final StremioService _stremio = StremioService.instance;

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode(debugLabel: 'search_field');

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
  final Map<String, double> _traktProgress = {}; // imdbId → 0..1
  final Map<String, String> _traktEpisode = {}; // imdbId → 'S2 · E5' (series)
  final Map<String, TraktContinueWatchingItem> _traktByImdb = {};
  final List<FocusNode> _traktMovieNodes = [];
  final List<FocusNode> _traktSeriesNodes = [];
  int _traktCwToken = 0;

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
          ),
        if (_traktMovies.isNotEmpty)
          _CwRow(
            title: 'Trakt Movies',
            tag: null,
            items: _traktMovies,
            nodes: _traktMovieNodes,
            progressOf: (m) => _traktProgress[m.imdbId],
            episodeOf: (_) => null,
            onOpen: _openTraktItem,
            onQuickPlay: _playTraktItem,
          ),
        if (_traktSeries.isNotEmpty)
          _CwRow(
            title: 'Trakt Shows',
            tag: null,
            items: _traktSeries,
            nodes: _traktSeriesNodes,
            progressOf: (m) => _traktProgress[m.imdbId],
            episodeOf: (m) => _traktEpisode[m.imdbId],
            onOpen: _openTraktItem,
            onQuickPlay: _playTraktItem,
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

  // Hero state. Driven by ValueNotifiers so focus-driven hero swaps rebuild
  // only the spotlight, never the whole board (important on low-power TVs).
  final ValueNotifier<StremioMeta?> _heroItem = ValueNotifier<StremioMeta?>(null);
  final ValueNotifier<StremioMeta?> _heroEnriched =
      ValueNotifier<StremioMeta?>(null);
  int _heroReqId = 0;
  Timer? _heroTimer;

  @override
  void initState() {
    super.initState();
    MainPageBridge.registerTvContentFocusHandler(_tabIndex, _focusContent);
    MainPageBridge.addIntegrationListener(_onIntegrationsChanged);
    _boardScroll.addListener(_onBoardScroll);
    _load();
    _loadContinueWatching();
    _loadTraktContinueWatching();
    _refreshTraktAuthState();
  }

  /// An integration (Trakt / a debrid provider) was connected or disconnected
  /// elsewhere while this tab stayed alive — refresh the state that gates the
  /// detail quick actions, the PikPak-only Play hiding, and the Trakt rows.
  void _onIntegrationsChanged() {
    _refreshTraktAuthState();
    _refreshPikpakOnly();
    _loadTraktContinueWatching();
  }

  Future<void> _refreshTraktAuthState() async {
    final auth = await TraktService.instance.isAuthenticated();
    if (!mounted || auth == _isTraktAuthenticated) return;
    setState(() => _isTraktAuthenticated = auth);
  }

  @override
  void dispose() {
    MainPageBridge.unregisterTvContentFocusHandler(_tabIndex, _focusContent);
    MainPageBridge.removeIntegrationListener(_onIntegrationsChanged);
    _catalogDebounce?.cancel();
    _heroTimer?.cancel();
    _heroItem.dispose();
    _heroEnriched.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _boardScroll.dispose();
    _disposeNodes();
    _disposeKwNodes();
    for (final n in [
      ..._cwMovieNodes,
      ..._cwSeriesNodes,
      ..._traktMovieNodes,
      ..._traktSeriesNodes,
    ]) {
      n.dispose();
    }
    _cwMovieNodes.clear();
    _cwSeriesNodes.clear();
    _traktMovieNodes.clear();
    _traktSeriesNodes.clear();
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
              if (!c.extras.any((e) => e.name == 'search' && e.isRequired))
                (a, c),
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
    final results = await Future.wait(slice.map((ref) async {
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
    }));
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
    setState(() => _boundCounts
      ..clear()
      ..addAll(counts));
  }

  /// PikPak is "only" when it's enabled and no add/resolve provider has a key.
  Future<void> _refreshPikpakOnly() async {
    final pikpak = await StorageService.getPikPakEnabled();
    final rd = await StorageService.getApiKey();
    final tb = await StorageService.getTorboxApiKey();
    final pm = await StorageService.getPremiumizeApiKey();
    final ad = await StorageService.getAllDebridApiKey();
    final anyOther = (rd != null && rd.isNotEmpty) ||
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
      items.add(StremioMeta(
        id: imdbId,
        imdbId: imdbId,
        type: type,
        name: (m['title'] as String?) ?? 'Untitled',
        poster: m['posterUrl'] as String?,
        year: m['year'] as String?,
      ));
      ids.add(imdbId);
      addonIds[imdbId] = m['addonId'] as String?;

      // Watched fraction — joined from the playback-state store, exactly like
      // HomeContinueWatchingSection (finished episodes count as 100%).
      double? pct;
      if (type == 'series') {
        final lastEp = await StorageService.getLastPlayedEpisodeByImdbId(imdbId);
        if (lastEp != null) {
          final finished = lastEp['finished'] == true;
          final posMs = lastEp['positionMs'] as int? ?? 0;
          final durMs = lastEp['durationMs'] as int? ?? 1;
          if (durMs > 0) {
            pct = finished ? 100.0 : (posMs / durMs * 100).clamp(0.0, 100.0);
          }
          final se = _seLabel(lastEp['season'] as int?, lastEp['episode'] as int?);
          if (se != null) episode[imdbId] = se;
        }
      } else {
        final state = await StorageService.getVideoPlaybackStateByImdbId(imdbId);
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
      ..addAll(List.generate(
        count,
        (i) => FocusNode(debugLabel: 'search_cw_${tag}_$i'),
      ));
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
  Future<void> _loadTraktContinueWatching() async {
    final token = ++_traktCwToken;
    final List<TraktContinueWatchingItem> movies;
    final List<TraktContinueWatchingItem> shows;
    try {
      final authed = await TraktService.instance.isAuthenticated();
      if (!mounted || token != _traktCwToken) return;
      if (!authed) {
        _syncCwNodes(_traktMovieNodes, 0, 'tmovie');
        _syncCwNodes(_traktSeriesNodes, 0, 'tseries');
        setState(() {
          _traktMovies = [];
          _traktSeries = [];
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
      // Leave any existing rows in place on a transient Trakt/network error.
      debugPrint('SearchScreen: Trakt continue-watching load failed: $e');
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
    _syncCwNodes(_traktMovieNodes, movieMetas.length, 'tmovie');
    _syncCwNodes(_traktSeriesNodes, showMetas.length, 'tseries');
    setState(() {
      _traktMovies = movieMetas;
      _traktSeries = showMetas;
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
    unawaited(_refreshBoundSources());
  }

  /// Open a Trakt Continue Watching title as a normal detail page.
  void _openTraktItem(StremioMeta item) {
    _openItem(item, _addonForContinue(item.sourceAddon?.id));
  }

  /// Resume a Trakt Continue Watching title — resolves the paused/next episode
  /// (an extra Trakt call for series) and plays.
  Future<void> _playTraktItem(StremioMeta item) async {
    final cwItem = _traktByImdb[_imdbOf(item)];
    if (cwItem == null) {
      _openTraktItem(item);
      return;
    }
    final sel = await TraktContinueWatchingService.instance
        .selectionForItem(cwItem);
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
      TraktItemMenuAction action, String imdbId) async {
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
    final first = sections.isNotEmpty && sections.first.items.isNotEmpty
        ? sections.first.items.first
        : null;
    _heroItem.value = first;
    _heroEnriched.value = null;
    // The hero is TV-only (see _buildBoard), so skip the backdrop fetch off-TV.
    if (first != null && widget.isTelevision) _enrichHero(first);
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
              final items =
                  await _stremio.searchSingleCatalog(addon, catalog, query);
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

  void _focusContent() {
    if (_mode == _Mode.keyword) {
      if (_kwNodes.isNotEmpty) {
        _kwNodes.first.requestFocus();
        return;
      }
      _searchFocusNode.requestFocus();
      return;
    }
    if (_cwVisible) {
      final rows = _cwRows;
      if (rows.isNotEmpty && rows.first.nodes.isNotEmpty) {
        rows.first.nodes.first.requestFocus();
        return;
      }
    }
    if (_rowNodes.isNotEmpty && _rowNodes.first.isNotEmpty) {
      _rowNodes.first.first.requestFocus();
      return;
    }
    _searchFocusNode.requestFocus();
  }

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

  void _setHero(StremioMeta item) {
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
    if (!needsBg && !needsDesc) return;
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
          _kwError = 'Search failed on all sources. Check your connection or '
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
  List<Torrent> get _kwSelectableResults =>
      _kwResults.where((t) => !t.isDirectStream && !t.isExternalStream).toList();

  void _enterKwSelection() {
    setState(() {
      _kwSelectionMode = true;
      _kwSelected.clear();
    });
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
    final chosen =
        _kwResults.where((t) => _kwSelected.contains(t.infohash)).toList();
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
        l.sort((a, b) =>
            a.displayTitle.toLowerCase().compareTo(b.displayTitle.toLowerCase()));
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
      final enabled = await StorageService.getTorboxCacheCheckEnabled() &&
          await StorageService.getTorboxIntegrationEnabled();
      if (enabled && tb != null && tb.isNotEmpty) {
        final cached =
            await TorboxService.checkCachedTorrents(apiKey: tb, infoHashes: hashes);
        for (final h in cached) {
          (map[h] ??= <String>[]).add('TB');
        }
      }
    } catch (_) {}
    try {
      final pm = await StorageService.getPremiumizeApiKey();
      final enabled = await StorageService.getPremiumizeCacheCheckEnabled() &&
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
    await showDialog<void>(
      context: context,
      builder: (_) => const _KeywordSourcesDialog(),
    );
    if (!mounted || _kwQuery.isEmpty) return;
    _runKeyword(_kwQuery); // re-search with the new enabled set
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

  void _openItem(StremioMeta item, StremioAddon addon) {
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
              onPlay: () => _onCatalogPlay(item, addon),
              onBrowse: () => _onCatalogBrowse(item, addon),
              traktMenuOptions: options,
              onTraktAction: (a) =>
                  _handleDetailQuickAction(item, addon, a, inCw: inCw, imdb: imdb),
              // "More Like This" rail + sparse-item meta backfill, matching the
              // catalog detail flow.
              recommendationsLoader: imdb != null
                  ? () =>
                      _stremio.getRecommendations(imdbId: imdb, type: item.type)
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
  }

  /// "Select/Edit Source" entry: edit dialog when a source is already bound,
  /// otherwise the add-source picker.
  Future<void> _handleEditOrSelectSource(StremioMeta item) async {
    final imdb = _imdbOf(item);
    final bound =
        imdb == null ? const <SeriesSource>[] : await SeriesSourceService.getSources(imdb);
    if (!mounted) return;
    if (bound.isNotEmpty) {
      await _showEditSourceDialog(item, bound);
    } else {
      _showAddSourcePicker(item);
    }
  }

  /// Manage the bound sources for [item]: list them, reorder by priority
  /// (series — first match wins), delete individually, Remove All, or add
  /// another via the picker. Ported from the catalog/aggregated detail flow.
  Future<void> _showEditSourceDialog(
      StremioMeta item, List<SeriesSource> initial) async {
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
        VoidCallback closeIfEmpty) async {
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
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: ConstrainedBox(
                constraints:
                    const BoxConstraints(maxWidth: 450, maxHeight: 500),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.link_rounded,
                              color: Color(0xFF60A5FA), size: 24),
                          const SizedBox(width: 8),
                          Text(
                            isMovie
                                ? 'Movie Source'
                                : 'Series Sources (${sources.length})',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                      if (!isMovie) ...[
                        const SizedBox(height: 4),
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'First match wins — reorder by priority',
                            style:
                                TextStyle(color: Colors.white38, fontSize: 11),
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
                                        imdbId, sources[index].torrentHash);
                                    await refreshInto(setDialogState, closeIfEmpty);
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
                                      imdbId, List.of(sources));
                                  _refreshBoundSources();
                                },
                                proxyDecorator: (child, index, animation) =>
                                    Material(
                                        color: Colors.transparent,
                                        elevation: 4,
                                        child: child),
                                itemBuilder: (context, index) =>
                                    _buildSourceListTile(
                                  key: ValueKey(sources[index].torrentHash),
                                  source: sources[index],
                                  index: index,
                                  onDelete: () async {
                                    await SeriesSourceService.removeSourceByHash(
                                        imdbId, sources[index].torrentHash);
                                    await refreshInto(setDialogState, closeIfEmpty);
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
                                  size: 18),
                              label:
                                  Text(isMovie ? 'Change Source' : 'Add Source'),
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF6366F1),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                          ),
                          if (!isMovie && sources.length > 1) ...[
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () async {
                                  await SeriesSourceService.removeAllSources(
                                      imdbId);
                                  await _refreshBoundSources();
                                  if (dialogContext.mounted) {
                                    Navigator.of(dialogContext).pop();
                                  }
                                },
                                icon: const Icon(Icons.delete_sweep_outlined,
                                    size: 18, color: Color(0xFFEF4444)),
                                label: const Text('Remove All',
                                    style: TextStyle(color: Color(0xFFEF4444))),
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(
                                      color: Color(0xFFEF4444), width: 1),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10)),
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
                                      imdbId);
                                  await _refreshBoundSources();
                                  if (dialogContext.mounted) {
                                    Navigator.of(dialogContext).pop();
                                  }
                                },
                                icon: const Icon(Icons.delete_outline_rounded,
                                    size: 18, color: Color(0xFFEF4444)),
                                label: const Text('Remove',
                                    style: TextStyle(color: Color(0xFFEF4444))),
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(
                                      color: Color(0xFFEF4444), width: 1),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10)),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        child: const Text('Close',
                            style: TextStyle(color: Colors.white54)),
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
          ? () => navigator.push(MaterialPageRoute(
                builder: (_) => DebridDownloadsScreen(
                  isPushedRoute: true,
                  initialSearchQuery: item.name,
                  selectSourceMode: true,
                  onSourceSelected: saveSource,
                ),
              ))
          : null,
      onTorbox: torboxEnabled
          ? () => navigator.push(MaterialPageRoute(
                builder: (_) => TorboxDownloadsScreen(
                  isPushedRoute: true,
                  initialSearchQuery: item.name,
                  selectSourceMode: true,
                  onSourceSelected: saveSource,
                ),
              ))
          : null,
    );
  }

  Future<void> _pickAndSaveLocalSource(StremioMeta item) async {
    final imdbId = _imdbOf(item);
    if (imdbId == null) return;
    final SeriesSource? source;
    if (item.type == 'series') {
      source = await LocalBoundSourceService.pickSeriesSource(context,
          title: item.name);
    } else {
      source = await LocalBoundSourceService.pickMovieSource(context,
          title: item.name, year: item.year);
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
                    fontWeight: FontWeight.w700),
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
                      fontWeight: FontWeight.w500),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: serviceColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    serviceLabel,
                    style: TextStyle(
                        color: serviceColor,
                        fontSize: 10,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded,
                size: 16, color: Color(0xFFEF4444)),
            onPressed: onDelete,
            tooltip: 'Remove source',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
          if (showDragHandle)
            const Icon(Icons.drag_handle_rounded,
                size: 18, color: Colors.white24),
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
    _browseSelection(AdvancedSearchSelection(
      imdbId: imdb,
      isSeries: true,
      title: item.name,
      year: item.year,
      contentType: item.type,
      posterUrl: item.poster,
    ));
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
      StremioMeta item, StremioAddon addon) async {
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
    _playSelection(AdvancedSearchSelection(
      imdbId: imdb,
      isSeries: true,
      title: item.name,
      year: item.year,
      season: pick.season,
      episode: pick.episode,
      contentType: item.type,
      posterUrl: item.poster,
    ));
  }

  // Catalog Play = auto-best in-tab; Sources = manual list in-tab. For a series
  // Play auto-plays the resume episode (last-played by imdbId → title, else
  // S01E01) — the Episodes button is the manual picker. Nothing jumps to Home.
  Future<void> _onCatalogPlay(StremioMeta item, StremioAddon addon) async {
    if (item.type != 'series') {
      // Keep the detail page underneath — the cinematic loading overlay covers
      // it, and after playback Back returns to the detail (like Home).
      _playSelection(_movieSelection(item));
      return;
    }

    _activeAddonId = addon.id;
    final imdbId = item.imdbId ?? (item.id.startsWith('tt') ? item.id : '');
    // Without an IMDb id we can't search torrents for a specific episode, so
    // fall back to the manual episode picker.
    if (imdbId.isEmpty) {
      _openEpisodes(item, addon);
      return;
    }

    // Resolve where to resume, mirroring EpisodesScreen's landing logic:
    // last-played episode for this show (by imdbId, then by title), else S01E01.
    int? season;
    int? episode;
    final byId = await StorageService.getLastPlayedEpisodeByImdbId(imdbId);
    season = byId?['season'] as int?;
    episode = byId?['episode'] as int?;
    if (season == null || episode == null) {
      final byTitle =
          await StorageService.getLastPlayedEpisode(seriesTitle: item.name);
      season ??= byTitle?['season'] as int?;
      episode ??= byTitle?['episode'] as int?;
    }
    season ??= 1;
    episode ??= 1;
    if (!mounted) return;

    _playSelection(AdvancedSearchSelection(
      imdbId: imdbId,
      isSeries: true,
      title: item.name,
      year: item.year,
      season: season,
      episode: episode,
      contentType: item.type,
      posterUrl: item.poster,
    ));
  }

  void _onCatalogBrowse(StremioMeta item, StremioAddon addon) {
    if (item.type == 'series') {
      _openEpisodes(item, addon);
    } else {
      _browseSelection(_movieSelection(item));
    }
  }

  AdvancedSearchSelection _movieSelection(StremioMeta item) =>
      AdvancedSearchSelection(
        // Keep the raw addon id ONLY for non-standard types (IPTV / TV / channel)
        // so playback/Sources can resolve the addon's own stream endpoint. A
        // movie/series without a `tt…` id (e.g. tmdb/kitsu-only) keeps '' so it
        // still shows the clear "No IMDb match" message instead of a doomed
        // torrent search — the isolated engine can't resolve those ids anyway.
        imdbId: item.effectiveImdbId ??
            (item.type == 'movie' || item.type == 'series' ? '' : item.id),
        isSeries: false,
        title: item.name,
        year: item.year,
        contentType: item.type,
        posterUrl: item.poster,
      );

  void _openEpisodes(StremioMeta item, StremioAddon addon) {
    _activeAddonId = addon.id;
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            settings: const RouteSettings(name: kEpisodesRouteName),
            builder: (_) => EpisodesScreen(
              show: item,
              addon: addon,
              isTelevision: widget.isTelevision,
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
      // Stremio-style indigo/purple glow: a soft purple bloom near the top
      // fading into deep near-black indigo.
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.75),
            radius: 1.35,
            colors: [
              Color(0xFF322A6B), // purple bloom
              Color(0xFF1A1734),
              Color(0xFF100E20),
              kStremioBg,
            ],
            stops: [0.0, 0.42, 0.72, 1.0],
          ),
        ),
        child: SafeArea(
          child: Column(
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
    );

    if (narrow) {
      return Padding(
        padding: EdgeInsets.fromLTRB(16, tv ? 16 : 12, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            field,
            const SizedBox(height: 10),
            toggle,
          ],
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
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.arrowDown) {
          _focusContent();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: _searchController,
        builder: (context, value, _) {
          final hasText = value.text.isNotEmpty;
          return TextField(
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
                      icon: Icon(Icons.close_rounded,
                          color: Colors.white.withValues(alpha: 0.55)),
                      onPressed: _clearQuery,
                    )
                  : Icon(Icons.search_rounded,
                      color: Colors.white.withValues(alpha: 0.4)),
              border: OutlineInputBorder(
                  borderRadius: radius, borderSide: BorderSide.none),
              enabledBorder: OutlineInputBorder(
                  borderRadius: radius, borderSide: BorderSide.none),
              focusedBorder: OutlineInputBorder(
                borderRadius: radius,
                borderSide: BorderSide(color: kStremioAccent.withValues(alpha: 0.6)),
              ),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.06),
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 20, vertical: tv ? 16 : 14),
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
    return _buildBoard();
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
                    final selectable =
                        !t.isDirectStream && !t.isExternalStream;
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
                        unawaited(TorrentPlaybackService.activateTorrent(
                            context, t,
                            searchKeyword: _kwQuery));
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
              Text('Sources',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface)),
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
    final filterCount = _kwFilters.qualities.length +
        _kwFilters.ripSources.length +
        _kwFilters.languages.length;

    Widget pill(IconData icon, String label, VoidCallback onTap,
        {bool active = false, bool compact = false}) {
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(999),
            child: Container(
              padding: compact
                  ? const EdgeInsets.all(10)
                  : const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
              decoration: BoxDecoration(
                color: active
                    ? scheme.primary.withValues(alpha: 0.16)
                    : scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: active
                      ? scheme.primary.withValues(alpha: 0.5)
                      : Colors.white.withValues(alpha: 0.10),
                ),
              ),
              child: compact
                  ? Icon(icon,
                      size: 18,
                      color: active ? scheme.primary : scheme.onSurfaceVariant)
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(icon, size: 15, color: scheme.onSurfaceVariant),
                        const SizedBox(width: 6),
                        Text(label,
                            style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: scheme.onSurface)),
                      ],
                    ),
            ),
          ),
        ),
      );
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
            pill(Icons.close_rounded, 'Cancel', _exitKwSelection),
            pill(
              allSelected ? Icons.deselect_rounded : Icons.select_all_rounded,
              allSelected ? 'None' : 'All',
              allSelected ? _deselectAllKw : _selectAllKw,
            ),
            pill(
              Icons.playlist_add_rounded,
              count > 0 ? 'Add · $count' : 'Add',
              count > 0 ? _openBulkAdd : () {},
              active: count > 0,
            ),
          ],
        ),
      );
    }

    final canSelect = _kwSelectableResults.isNotEmpty;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Row(
        children: [
          pill(Icons.sort_rounded, 'Sort · ${_sortLabel(_kwSort)}',
              _openKeywordSort,
              compact: floatingSelect),
          pill(
            Icons.filter_list_rounded,
            filterCount > 0 ? 'Filters · $filterCount' : 'Filters',
            _openKeywordFilters,
            active: filterCount > 0,
            compact: floatingSelect,
          ),
          pill(Icons.dns_rounded, 'Sources', _openKeywordSources,
              compact: floatingSelect),
          if (canSelect && !floatingSelect)
            pill(Icons.checklist_rounded, 'Select', _enterKwSelection),
        ],
      ),
    );
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
          child: const Icon(Icons.checklist_rounded,
              color: Colors.white, size: 20),
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
                    fontSize: 12),
              ),
              allSelected ? _deselectAllKw : _selectAllKw,
              Colors.white.withValues(alpha: 0.08),
            ),
            const SizedBox(width: 8),
            chip(
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.playlist_add_rounded,
                      color: count > 0 ? Colors.white : Colors.white38,
                      size: 16),
                  const SizedBox(width: 4),
                  Text('Add',
                      style: TextStyle(
                          color: count > 0 ? Colors.white : Colors.white38,
                          fontWeight: FontWeight.w700,
                          fontSize: 12)),
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

  Widget _buildBoard() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _message(
        Icons.error_outline_rounded,
        "Couldn't load catalogs",
        _error!,
      );
    }
    final showCw = _cwVisible;
    if (_sections.isEmpty && !showCw) {
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
    final heroH = tv ? 380.0 : (width >= 900 ? 300.0 : 196.0);

    return Column(
      children: [
        // The hero spotlight only changes as DPAD focus moves across tiles, so
        // it's meaningful on TV only. On phones/desktop (no DPAD) it would just
        // sit frozen on the first item and waste vertical space — hide it.
        if (tv)
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
                    isTelevision: tv,
                    height: heroH,
                  );
                },
              );
            },
          ),
        Expanded(
          child: Builder(builder: (context) {
            // Continue Watching rows (local, then Trakt) are the leading board
            // rows; the catalog sections follow, offset by the CW row count.
            final cwRows = showCw ? _cwRows : const <_CwRow>[];
            final cwCount = cwRows.length;
            // Footer spinner tracks the actual fetch, not just "more remain":
            // `_boardCursor` advances synchronously so the final in-flight batch
            // still shows it, and an idle board with more rows doesn't spin.
            final showFooter = _boardLoadingMore;
            return ListView.builder(
              controller: _boardScroll,
              padding: const EdgeInsets.only(top: 6, bottom: 32),
              cacheExtent: 2000,
              itemCount: _sections.length + cwCount + (showFooter ? 1 : 0),
              itemBuilder: (context, i) {
                if (i < cwCount) {
                  return _buildContinueWatchingRow(cwRows[i], i, cwCount);
                }
                final s = i - cwCount;
                if (s >= _sections.length) return _buildBoardFooter();
                return _buildRow(s);
              },
            );
          }),
        ),
      ],
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

  Widget _buildRow(int rowIndex) {
    final section = _sections[rowIndex];
    final nodes = _rowNodes[rowIndex];
    final tv = widget.isTelevision;
    final width = MediaQuery.of(context).size.width;
    // Bigger, roomier posters on desktop (Stremio-scale); smaller on phones.
    final posterW = tv ? 152.0 : (width >= 900 ? 162.0 : 118.0);
    final posterH = posterW * 3 / 2;
    // Cell = poster + gap + a 2-line title below. Size the title band from the
    // actual (accessibility-scaled) line height so a large system font can't
    // overflow the fixed cell.
    final titleH = MediaQuery.textScalerOf(context).scale(14) * 1.25 * 2;
    final cellH = posterH + 10 + titleH + 6;
    final rowH = cellH + 14; // headroom for the hover/focus lift
    final typeLabel = _sectionTypeLabel(section);

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
                  section.title,
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
              if (typeLabel != null) ...[
                const SizedBox(width: 10),
                _CategoryTag(typeLabel),
              ],
            ],
          ),
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
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              // Clip the horizontal viewport so scrolled-off cards don't paint
              // over the sidebar to the left. rowH has enough headroom that the
              // hover/focus lift still isn't clipped.
              clipBehavior: Clip.hardEdge,
              cacheExtent: 2000,
              padding: const EdgeInsets.symmetric(horizontal: 13),
              // +1 trailing cell for the paging spinner while more items load.
              itemCount: section.items.length + (section.loadingMore ? 1 : 0),
              itemBuilder: (context, col) {
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
                        onUp: rowIndex == 0
                            ? (_cwVisible
                                ? () => _focusCwRow(_cwRows.length - 1, col)
                                : () => _searchFocusNode.requestFocus())
                            : () => _focusRow(rowIndex - 1, col),
                        onDown: () => _focusRow(rowIndex + 1, col),
                        onOpen: () => _openItem(item, section.addon),
                        onNearEnd: () => _loadMoreRow(rowIndex),
                      ),
                    ),
                  ),
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
  Widget _buildContinueWatchingRow(_CwRow row, int cwIndex, int cwCount) {
    final tv = widget.isTelevision;
    final width = MediaQuery.of(context).size.width;
    final posterW = tv ? 152.0 : (width >= 900 ? 162.0 : 118.0);
    final posterH = posterW * 3 / 2;
    final titleH = MediaQuery.textScalerOf(context).scale(14) * 1.25 * 2;
    final cellH = posterH + 10 + titleH + 6;
    final rowH = cellH + 14;
    final items = row.items;
    final nodes = row.nodes;

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
                  row.title,
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
              if (row.tag != null) ...[
                const SizedBox(width: 10),
                _CategoryTag(row.tag!),
              ],
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
            itemCount: items.length,
            itemBuilder: (context, col) {
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
                      onQuickPlay:
                          _pikpakOnly ? null : () => row.onQuickPlay(item),
                      onFocused: () => _setHero(item),
                      // Up: previous CW row, or the search field from the first.
                      onUp: cwIndex == 0
                          ? () => _searchFocusNode.requestFocus()
                          : () => _focusCwRow(cwIndex - 1, col),
                      // Down: next CW row, or the first catalog row from the last.
                      onDown: cwIndex < cwCount - 1
                          ? () => _focusCwRow(cwIndex + 1, col)
                          : () => _focusRow(0, col),
                      onOpen: () => row.onOpen(item),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
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

  const _HeroSpotlight({
    required this.item,
    required this.background,
    required this.description,
    required this.isTelevision,
    required this.height,
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
        fit: StackFit.expand,
        children: [
          if (bg.isNotEmpty)
            CachedNetworkImage(
              imageUrl: bg,
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
              errorWidget: (_, __, ___) => const SizedBox.shrink(),
            ),
          // Left + bottom scrims for legibility.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  scheme.surface,
                  scheme.surface.withValues(alpha: 0.82),
                  scheme.surface.withValues(alpha: 0.15),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.34, 0.66, 1.0],
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [scheme.surface, Colors.transparent],
                stops: const [0.02, 0.5],
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomLeft,
            child: Padding(
              padding: EdgeInsets.fromLTRB(24, 0, 24, isTelevision ? 22 : 16),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: isTelevision ? 640 : 520,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.14)),
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
                    const SizedBox(height: 10),
                    Text(
                      item.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: isTelevision ? 40 : 26,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -1,
                        height: 1.04,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        if (item.imdbRating != null) ...[
                          const Icon(Icons.star_rounded,
                              size: 16, color: HomeTheme.focusGold),
                          const SizedBox(width: 4),
                          Text(
                            item.imdbRating!.toStringAsFixed(1),
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
                      const SizedBox(height: 10),
                      Text(
                        description!,
                        maxLines: isTelevision ? 3 : 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: isTelevision ? 14.5 : 13,
                          height: 1.45,
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
class _CategoryTag extends StatelessWidget {
  final String label;
  const _CategoryTag(this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: kStremioAccent.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: kStremioAccent.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFFB9A9FF),
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
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

  const _CwRow({
    required this.title,
    required this.tag,
    required this.items,
    required this.nodes,
    required this.progressOf,
    required this.episodeOf,
    required this.onOpen,
    required this.onQuickPlay,
  });
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
/// lifts on hover/focus, and the title centered BELOW the poster (2 lines).
/// Deliberately minimal (no MOVIE/rating chips) to mirror Stremio's board.
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
                    child: Icon(Icons.bookmark_rounded,
                        size: 18,
                        color: Colors.white,
                        shadows: [Shadow(color: Colors.black, blurRadius: 6)]),
                  ),
                // Subtle season/episode badge for a Continue Watching series
                // card — sits just above the progress bar, bottom-left.
                if (widget.episodeLabel != null)
                  Positioned(
                    left: 6,
                    bottom: widget.progress != null ? 11 : 6,
                    child: Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              posterCard,
              const SizedBox(height: 10),
              Text(
                item.name,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _active
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.92),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  height: 1.25,
                ),
              ),
            ],
          ),
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

/// Catalog / Keyword segmented toggle.
class _ModeToggle extends StatelessWidget {
  final _Mode mode;
  final bool isTelevision;

  /// When true the two segments split the full available width (used when the
  /// toggle is stacked below the search box on narrow screens).
  final bool fullWidth;
  final ValueChanged<_Mode> onChanged;

  const _ModeToggle({
    required this.mode,
    required this.isTelevision,
    required this.onChanged,
    this.fullWidth = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final catalog =
        _segment(context, _Mode.catalog, 'Catalog', Icons.grid_view_rounded);
    final keyword =
        _segment(context, _Mode.keyword, 'Keyword', Icons.bolt_rounded);
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

  Widget _segment(BuildContext context, _Mode value, String label, IconData icon) {
    final on = mode == value;
    return InkWell(
      onTap: () => onChanged(value),
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: EdgeInsets.symmetric(horizontal: isTelevision ? 16 : 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on ? kStremioAccent : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 16,
                color: on
                    ? Colors.white
                    : Theme.of(context).colorScheme.onSurfaceVariant),
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
    final bound =
        _imdbId.isEmpty ? <SeriesSource>[] : await SeriesSourceService.getSources(_imdbId);
    if (!mounted) return;
    setState(() => _bound = bound);
  }

  Future<void> _load() async {
    await _reloadBound();
    await _runSearch();
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
      final torrents = (res['torrents'] as List).cast<Torrent>();
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
    unawaited(TorrentPlaybackService.activateTorrent(
      context,
      t,
      meta: widget.meta,
      sources: _torrents,
      sourceIndex: i,
      searchKeyword: widget.selection.title,
    ));
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      behavior: SnackBarBehavior.floating,
    ));
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
              leading: const Icon(Icons.play_arrow_rounded, color: Colors.white),
              title: const Text('Play', style: TextStyle(color: Colors.white)),
              onTap: () {
                DialogTapGuard.markKeyAction();
                Navigator.of(sheetCtx).pop();
                _playNow(t, i);
              },
            ),
            ListTile(
              leading: Icon(bound ? Icons.link_off_rounded : Icons.link_rounded,
                  color: const Color(0xFFF59E0B)),
              title: Text(bound ? 'Unpin source' : 'Pin as source',
                  style: const TextStyle(color: Colors.white)),
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
              title: Text(external ? 'Open externally' : 'Play now',
                  style: const TextStyle(color: Colors.white)),
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
              title:
                  const Text('Copy URL', style: TextStyle(color: Colors.white)),
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
          if (_imdbId.isNotEmpty && TorrentPlaybackService.localBindingAvailable)
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
                              padding: const EdgeInsets.symmetric(vertical: 8),
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
        border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.link_rounded, color: Color(0xFFF59E0B), size: 16),
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
          ..._bound.map((s) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        s.torrentName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 12.5),
                      ),
                    ),
                    InkWell(
                      onTap: () => unawaited(_unpin(s.torrentHash)),
                      borderRadius: BorderRadius.circular(8),
                      child: const Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(Icons.close_rounded,
                            color: Colors.white70, size: 18),
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  Widget _centered(ColorScheme scheme, String text) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(text,
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant)),
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
                height: 80, child: Center(child: CircularProgressIndicator()))
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
