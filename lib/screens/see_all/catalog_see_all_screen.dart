import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/stremio_addon.dart';
import '../../services/analytics_service.dart';
import '../../services/discover_prefs.dart';
import '../../services/filtered_catalog_pager.dart';
import '../../services/main_page_bridge.dart';
import '../../services/watched_filter.dart';
import '../../theme/app_theme_scope.dart';
import '../../widgets/skeleton_poster.dart';
import '../../services/stremio_service.dart';
import '../../widgets/see_all/see_all_filter_bar.dart';
import '../../widgets/see_all/see_all_filter_focus.dart';
import '../../widgets/see_all/see_all_header.dart';
import '../../widgets/see_all/see_all_poster_grid.dart';
import '../../widgets/see_all/see_all_random_button.dart';
import '../../widgets/see_all/stremio_dropdown.dart';

/// Full-screen Stremio-styled catalog browser — the "See All" destination for a
/// catalog rail on the Search board. Reuses the board's own catalog fetch
/// ([StremioService.fetchCatalog]) and id-dedup paging; opening an item calls
/// back to [onOpenItem] (the host's `_openItem`) so the existing detail flow —
/// Trakt actions, recommendations, meta backfill — is reused unchanged.
///
/// Type and Catalog are derived from the addon's own catalogs (type is baked
/// into each [StremioAddonCatalog]); Genre comes from the catalog's manifest
/// `extra`. The addon itself is fixed to the originating rail.
class CatalogSeeAllScreen extends StatefulWidget {
  final StremioAddon addon;

  /// Optional catalog transport for deterministic pagination tests.
  final PageFetch? fetchPage;
  final StremioAddonCatalog initialCatalog;

  /// When set, this See-All is a SEARCH result: reload / load-more query the
  /// catalog's `search=` endpoint (paged) instead of browsing it, so the grid
  /// shows *all* matches for the query rather than getting muddied with
  /// non-matching browse items. Filter changes stay in search mode — switching
  /// Type/Catalog re-runs the query on the new catalog, Genre narrows it.
  final String? query;

  /// Genre to open on (a collection folder's list carries one). Only applied
  /// when the catalog supports the `genre` extra; the dropdown reflects it.
  final String? initialGenre;

  /// Items already loaded on the rail — used to seed the grid without a refetch.
  final List<StremioMeta> seedItems;

  /// The rail's paging cursor, so the first "load more" continues where the
  /// rail left off.
  final int seedNextSkip;

  final bool isTelevision;

  /// Open the detail page for an item (host binds the originating addon).
  final void Function(StremioMeta item) onOpenItem;

  /// Optional Quick Play (long-press) straight from the grid.
  final void Function(StremioMeta item)? onQuickPlay;

  /// Fires when a grid tile gains focus — drives the Discover detail rail.
  final void Function(StremioMeta item)? onItemFocused;

  /// Optional "has a pinned source" flag per item.
  final bool Function(StremioMeta item)? isBound;

  /// Embedded mode (e.g. inside the Discover tab): drops the Scaffold + back
  /// header so the host provides the chrome, and prepends [leading] (a Source
  /// dropdown) to the filter bar with [leadingNode] in the DPAD focus row.
  final bool embedded;
  final Widget? leading;
  final FocusNode? leadingNode;

  const CatalogSeeAllScreen({
    super.key,
    required this.addon,
    this.fetchPage,
    required this.initialCatalog,
    required this.onOpenItem,
    this.query,
    this.initialGenre,
    this.seedItems = const [],
    this.seedNextSkip = 0,
    this.isTelevision = false,
    this.onQuickPlay,
    this.onItemFocused,
    this.isBound,
    this.embedded = false,
    this.leading,
    this.leadingNode,
  });

  @override
  State<CatalogSeeAllScreen> createState() => _CatalogSeeAllScreenState();
}

class _CatalogSeeAllScreenState extends State<CatalogSeeAllScreen> {
  final StremioService _stremio = StremioService.instance;
  final GlobalKey<SeeAllPosterGridState> _gridKey = GlobalKey();

  late String _type;
  late StremioAddonCatalog _catalog;
  String? _genre; // null = All genres

  /// Active search query. Non-empty → search mode (see [CatalogSeeAllScreen.query]).
  /// Fixed for the life of the screen; filter changes re-search rather than
  /// clear it (browse mode is entered only when opened with no query).
  late String _searchQuery;
  bool get _searching => _searchQuery.isNotEmpty;

  // Client-side sort over the loaded items. 'default' preserves the addon's
  // own order (Popular/Trending etc.); the IMDb options re-order what's been
  // fetched so far (unrated items sink to the end either way).
  static const String _sortDefault = 'default';
  static const String _sortImdbDesc = 'imdbDesc';
  static const String _sortImdbAsc = 'imdbAsc';
  String _sort = _sortDefault;

  final List<StremioMeta> _items = [];
  int _nextSkip = 0;
  bool _loadingInitial = true;
  bool _loadingMore = false;
  bool _exhausted = false;
  bool _pagingPaused = false;

  // Random (Discover): true while the random-page probe is in flight — the
  // button shows a spinner and further presses are ignored.
  bool _randomBusy = false;
  final Random _random = Random();

  // Bumped on every reset so an in-flight page from a stale catalog/genre is
  // discarded when it returns.
  int _reqToken = 0;

  // TV DPAD focus for the filter bar (arrows walk the dropdowns; Down enters the
  // grid, Up returns to the back button).
  final FocusNode _backNode = FocusNode(debugLabel: 'seeall_back');
  final FocusNode _typeNode = FocusNode(debugLabel: 'seeall_type');
  final FocusNode _catalogNode = FocusNode(debugLabel: 'seeall_catalog');
  final FocusNode _genreNode = FocusNode(debugLabel: 'seeall_genre');
  final FocusNode _sortNode = FocusNode(debugLabel: 'seeall_sort');
  final FocusNode _randomNode = FocusNode(debugLabel: 'seeall_random');
  // The empty-state Retry button — the only recovery affordance when a filter
  // yields nothing, so it must be DPAD-reachable.
  final FocusNode _retryNode = FocusNode(debugLabel: 'seeall_retry');

  @override
  void initState() {
    super.initState();
    AnalyticsService.screenView('catalog_see_all');
    _type = widget.initialCatalog.type;
    _catalog = widget.initialCatalog;
    _searchQuery = widget.query?.trim() ?? '';
    final genre = widget.initialGenre?.trim();
    if (genre != null && genre.isNotEmpty) _genre = genre;
    // Discover only: reopen on the order the user last picked. Ignore a stored
    // id that is no longer one of the three options.
    if (widget.embedded) {
      final saved = DiscoverPrefs.sortFor(DiscoverPrefs.catalog);
      if (saved == _sortDefault ||
          saved == _sortImdbDesc ||
          saved == _sortImdbAsc) {
        _sort = saved!;
      }
    }
    if (widget.seedItems.isNotEmpty || widget.seedNextSkip > 0) {
      _items.addAll(WatchedFilter.apply(widget.seedItems));
      _pagingPaused = _items.isEmpty;
      _nextSkip = widget.seedNextSkip;
      _loadingInitial = false;
      // Embedded (Discover): the host focuses the Source dropdown; a source swap
      // re-mounts this panel, so don't steal the DPAD ring into the grid.
      if (widget.isTelevision && !widget.embedded) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _gridKey.currentState?.focusFirst(),
        );
      }
    } else {
      _reload(autoFocus: !widget.embedded);
    }
  }

  @override
  void dispose() {
    _backNode.dispose();
    _typeNode.dispose();
    _catalogNode.dispose();
    _genreNode.dispose();
    _sortNode.dispose();
    _randomNode.dispose();
    _retryNode.dispose();
    super.dispose();
  }

  // ── Derived options ────────────────────────────────────────────────────────

  /// Only offer catalogs that work in the current mode: searchable ones while
  /// searching (so switching Type/Catalog re-runs the search rather than
  /// browsing a search-only catalog, which returns empty), browsable ones
  /// otherwise. Keeps the current catalog present in its own dropdown too.
  bool _usable(StremioAddonCatalog c) =>
      _searching ? c.supportsSearch : c.isBrowsable;

  List<String> get _types {
    final seen = <String>{};
    final out = <String>[];
    for (final c in widget.addon.catalogs) {
      if (_usable(c) && seen.add(c.type)) out.add(c.type);
    }
    return out;
  }

  List<StremioAddonCatalog> _catalogsForType(String type) =>
      widget.addon.catalogs.where((c) => c.type == type && _usable(c)).toList();

  /// Matches `search_screen._sectionTypeLabel` so the Type filter reads the same
  /// as the rail tag the user came from ("Movies", not "Movie").
  static String typeLabel(String type) {
    switch (type.toLowerCase()) {
      case 'movie':
        return 'Movies';
      case 'series':
        return 'Series';
      case 'tv':
        return 'TV';
      case 'channel':
        return 'Channels';
      default:
        return type.isEmpty
            ? 'All'
            : '${type[0].toUpperCase()}${type.substring(1)}';
    }
  }

  // ── Fetch / paging ─────────────────────────────────────────────────────────

  /// Fetch one page: the catalog's paged `search=` endpoint while [_searching],
  /// otherwise a plain browse. Same shape either way so paging/dedup is shared.
  Future<List<StremioMeta>> _fetchPage(
    int skip,
    void Function(int rawCount) onRawCount,
  ) {
    final fetch = widget.fetchPage;
    if (fetch != null) return fetch(skip, onRawCount);
    if (_searching) {
      return _stremio.searchSingleCatalog(
        widget.addon,
        _catalog,
        _searchQuery,
        skip: skip,
        genre: _genre,
        onRawCount: onRawCount,
      );
    }
    return _stremio.fetchCatalog(
      widget.addon,
      _catalog,
      skip: skip,
      genre: _genre,
      onRawCount: onRawCount,
    );
  }

  /// [autoFocus] moves DPAD focus into the grid once the page loads — only the
  /// first (initial) load should; a filter-triggered reload must leave focus on
  /// the filter bar so the user can chain edits.
  Future<void> _reload({bool autoFocus = false}) async {
    final token = ++_reqToken;
    setState(() {
      _loadingInitial = true;
      _items.clear();
      _nextSkip = 0;
      _exhausted = false;
      _pagingPaused = false;
      _loadingMore = false;
    });
    try {
      final page = await fetchFilteredPage(
        _fetchPage,
        skip: 0,
        hides: WatchedFilter.predicate,
      );
      if (!mounted || token != _reqToken) return;
      setState(() {
        _items.addAll(page.items);
        _nextSkip = page.nextSkip;
        _exhausted = page.exhausted;
        _pagingPaused = !page.exhausted && page.items.isEmpty;
        _loadingInitial = false;
      });
      if (autoFocus && widget.isTelevision && page.items.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _gridKey.currentState?.focusFirst(),
        );
      }
    } catch (_) {
      if (!mounted || token != _reqToken) return;
      setState(() {
        _loadingInitial = false;
        _exhausted = true;
      });
    }
  }

  Future<void> _loadMore({bool resume = false}) async {
    if (_pagingPaused && !resume) return;
    if (_loadingInitial || _loadingMore || _exhausted) return;
    final token = _reqToken;
    setState(() => _loadingMore = true);
    try {
      final seen = _items.map((m) => m.id).toSet();
      final page = await fetchFilteredPage(
        _fetchPage,
        skip: _nextSkip,
        hides: WatchedFilter.predicate,
        seenIds: seen,
      );
      if (!mounted || token != _reqToken) return;
      setState(() {
        _nextSkip = page.nextSkip;
        _items.addAll(page.items);
        _exhausted = page.exhausted;
        _pagingPaused = !page.exhausted && page.items.isEmpty;
        _loadingMore = false;
      });
      if (resume && widget.isTelevision && page.items.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _gridKey.currentState?.focusFirst();
        });
      }
    } catch (_) {
      if (!mounted || token != _reqToken) return;
      setState(() => _loadingMore = false);
    }
  }

  // ── Random (Discover) ──────────────────────────────────────────────────────

  /// The Random button is a Discover affordance: only the embedded host wires
  /// Quick Play (and hides it in PikPak-only mode by passing null).
  bool get _showRandom => widget.embedded && widget.onQuickPlay != null;

  /// Pick a random item honouring the current Type/Catalog/Genre selection and
  /// Quick-Play it. Sampling only the loaded pages would bias every press
  /// toward the catalog's head, so probe a random offset through [_fetchPage]
  /// (which bakes the filters in): catalog depth is unknowable up front, so a
  /// deep probe first, then a shallow one for addons that don't page that far,
  /// then the already-loaded items as the last resort. Addons that ignore
  /// `skip` just return their first page — the in-page pick still randomizes.
  Future<void> _playRandom() async {
    if (_randomBusy || _loadingInitial || _items.isEmpty) return;
    final play = widget.onQuickPlay;
    if (play == null) return;
    AnalyticsService.trackInBackground('discover_random_play', {
      'source': 'catalog',
    });
    final token = _reqToken;
    setState(() => _randomBusy = true);
    StremioMeta? pick;
    try {
      for (final depth in const [400, 60]) {
        final page = WatchedFilter.apply(
          await _fetchPage(_random.nextInt(depth), (_) {}),
        );
        // A filter changed mid-probe — the page (and any fallback below) no
        // longer matches what's on screen, so drop the press entirely.
        if (!mounted || token != _reqToken) return;
        if (page.isNotEmpty) {
          pick = page[_random.nextInt(page.length)];
          break;
        }
      }
      pick ??= _items.isEmpty ? null : _items[_random.nextInt(_items.length)];
    } catch (_) {
      if (!mounted || token != _reqToken) return;
      pick = _items.isEmpty ? null : _items[_random.nextInt(_items.length)];
    } finally {
      if (mounted) setState(() => _randomBusy = false);
    }
    if (pick != null) play(pick);
  }

  // ── Handlers ───────────────────────────────────────────────────────────────

  // Filter changes stay in the current mode: while searching, switching
  // Type/Catalog re-runs the query against the new (search-capable) catalog and
  // Genre narrows the search; while browsing they browse. _reload → _fetchPage
  // picks search vs browse off [_searching], so no mode flip is needed here.
  void _onTypeChanged(String type) {
    if (type == _type) return;
    setState(() {
      _type = type;
      _catalog = _catalogsForType(type).first;
      _genre = null;
    });
    _reload();
  }

  void _onCatalogChanged(StremioAddonCatalog cat) {
    if (identical(cat, _catalog)) return;
    setState(() {
      _catalog = cat;
      _genre = null;
    });
    _reload();
  }

  void _onGenreChanged(String? genre) {
    if (genre == _genre) return;
    setState(() => _genre = genre);
    _reload();
  }

  void _onSortChanged(String sort) {
    if (sort == _sort) return;
    // Pure view change — re-orders what's loaded, no refetch. Persists across
    // type/catalog/genre edits (it's a preference, not a filter) — and, in
    // Discover, across source swaps and app restarts too, for the same reason:
    // one standing preference shared by every addon catalog.
    setState(() => _sort = sort);
    if (widget.embedded) {
      unawaited(DiscoverPrefs.setSort(DiscoverPrefs.catalog, sort));
    }
  }

  /// The grid's items in the selected order. Default = addon order (the list
  /// itself); IMDb sorts are computed on demand over the loaded pages, with
  /// unrated items always sinking to the end so they never bury rated ones.
  List<StremioMeta> get _sortedItems {
    if (_sort == _sortDefault) return _items;
    final sorted = List<StremioMeta>.of(_items);
    final asc = _sort == _sortImdbAsc;
    sorted.sort((a, b) {
      final ra = a.imdbRating, rb = b.imdbRating;
      if (ra == null && rb == null) return 0;
      if (ra == null) return 1; // unrated last, both directions
      if (rb == null) return -1;
      return asc ? ra.compareTo(rb) : rb.compareTo(ra);
    });
    return sorted;
  }

  // ── TV filter-bar focus wiring ─────────────────────────────────────────────

  List<FocusNode> get _filterNodes => [
    if (widget.leadingNode != null) widget.leadingNode!,
    _typeNode,
    _catalogNode,
    if (_catalog.supportsGenre) _genreNode,
    _sortNode,
    if (_showRandom) _randomNode,
  ];

  /// Whether the empty-state (with the Retry button) is currently shown instead
  /// of the grid.
  bool get _showingEmpty => !_loadingInitial && _items.isEmpty;

  /// Discover TV styling: quiet text-segment filters on the glass stage.
  /// Poster details are governed independently by the Discover card scope.
  bool get _quiet => widget.embedded && widget.isTelevision;

  KeyEventResult _handleFilterKeys(FocusNode _, KeyEvent event) {
    if (!widget.isTelevision) return KeyEventResult.ignored;
    return handleSeeAllFilterArrows(
      event,
      _filterNodes,
      // Down enters the grid, or the Retry button when the grid is empty (the
      // grid isn't mounted, so focusFirst would be a no-op).
      onDown: () => _showingEmpty
          ? _retryNode.requestFocus()
          : _gridKey.currentState?.focusFirst(),
      // Embedded (Discover) has no back button above the bar, so up-from-filters
      // stays put; the standalone screen returns to it.
      onUp: () {
        if (!widget.embedded) _backNode.requestFocus();
      },
      // Embedded: Left off the leading Source dropdown escapes to the TV sidebar.
      onLeftEdge: widget.embedded
          ? () => MainPageBridge.focusTvSidebar?.call()
          : null,
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Embedded (Discover tab): the host supplies the Scaffold + chrome, so render
    // just the filter bar (with the leading Source dropdown) over the grid.
    if (widget.embedded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildFilterBar(),
          Expanded(child: _buildBody()),
        ],
      );
    }
    return Scaffold(
      backgroundColor: AppThemeScope.of(context).seeAll.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SeeAllHeader(
              title: widget.addon.name,
              subtitle: _searching
                  ? 'Results for “$_searchQuery”'
                  : 'Browse catalog',
              isTelevision: widget.isTelevision,
              backNode: _backNode,
              onFilterDown: () => _typeNode.requestFocus(),
            ),
            _buildFilterBar(),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterBar() {
    final catalogs = _catalogsForType(_type);
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _handleFilterKeys,
      child: Padding(
        padding: _quiet
            ? const EdgeInsets.fromLTRB(24, 16, 24, 10)
            : const EdgeInsets.fromLTRB(24, 10, 24, 12),
        child: SeeAllFilterBar(
          isTelevision: widget.isTelevision,
          leading: widget.leading,
          quiet: _quiet,
          activeCount:
              (_genre != null ? 1 : 0) + (_sort != _sortDefault ? 1 : 0),
          trailing: _showRandom
              ? SeeAllRandomButton(
                  quiet: _quiet,
                  enabled: !_loadingInitial && _items.isNotEmpty,
                  busy: _randomBusy,
                  focusNode: _randomNode,
                  onPressed: _playRandom,
                )
              : null,
          buildChips: () => [
            StremioDropdown<String>(
              label: 'Type',
              value: _type,
              isTelevision: widget.isTelevision,
              quiet: _quiet,
              focusNode: _typeNode,
              options: [
                for (final t in _types) StremioDropdownOption(t, typeLabel(t)),
              ],
              onSelected: _onTypeChanged,
            ),
            StremioDropdown<StremioAddonCatalog>(
              label: 'Catalog',
              value: _catalog,
              isTelevision: widget.isTelevision,
              quiet: _quiet,
              focusNode: _catalogNode,
              options: [
                for (final c in catalogs) StremioDropdownOption(c, c.name),
              ],
              onSelected: _onCatalogChanged,
            ),
            if (_catalog.supportsGenre)
              StremioDropdown<String>(
                label: 'Genre',
                // '' is the sentinel for "All" (the menu can't return null as a
                // real selection — null means dismissed).
                value: _genre ?? '',
                isTelevision: widget.isTelevision,
                quiet: _quiet,
                focusNode: _genreNode,
                options: [
                  const StremioDropdownOption<String>('', 'All'),
                  for (final g in _catalog.genreOptions)
                    StremioDropdownOption<String>(g, g),
                ],
                onSelected: (g) => _onGenreChanged(g.isEmpty ? null : g),
              ),
            StremioDropdown<String>(
              label: 'Sort',
              value: _sort,
              isTelevision: widget.isTelevision,
              quiet: _quiet,
              focusNode: _sortNode,
              options: const [
                StremioDropdownOption(_sortDefault, 'Default'),
                StremioDropdownOption(
                  _sortImdbDesc,
                  'IMDb Rating · High → Low',
                ),
                StremioDropdownOption(_sortImdbAsc, 'IMDb Rating · Low → High'),
              ],
              onSelected: _onSortChanged,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loadingInitial) {
      return SkeletonPosterGrid(isTelevision: widget.isTelevision);
    }
    if (_items.isEmpty) {
      final app = AppThemeScope.of(context);
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.movie_filter_rounded,
                size: 44,
                color: app.fade(app.core.tx, 0.25),
              ),
              const SizedBox(height: 14),
              Text(
                !_exhausted
                    ? 'No new titles loaded yet'
                    : _searching
                    ? 'No matches for “$_searchQuery”'
                    : 'Nothing in this catalog',
                style: TextStyle(
                  color: app.fade(app.core.tx, 0.7),
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                // fetch swallows errors and returns [], so an empty result can
                // also be a transient failure — offer a retry rather than
                // dead-ending (re-selecting the same filter is a no-op).
                !_exhausted
                    ? 'Continue browsing to check more titles.'
                    : _searching
                    ? 'No results for this query — try another catalog or genre.'
                    : 'This may be empty, or the addon failed to respond.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: app.fade(app.core.tx, 0.4),
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 18),
              // DPAD-up leaves Retry back to the filter bar so it isn't a focus
              // trap; the button's own focus node handles SELECT (via onPressed).
              Focus(
                onKeyEvent: (_, event) {
                  if (widget.isTelevision &&
                      event is KeyDownEvent &&
                      event.logicalKey == LogicalKeyboardKey.arrowUp) {
                    _typeNode.requestFocus();
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: OutlinedButton.icon(
                  focusNode: _retryNode,
                  onPressed: _loadingMore
                      ? null
                      : () => _exhausted
                            ? _reload(autoFocus: true)
                            : _loadMore(resume: true),
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: Text(
                    _loadingMore
                        ? 'Loading…'
                        : _exhausted
                        ? 'Retry'
                        : 'Continue loading',
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: app.core.tx,
                    side: BorderSide(color: app.seeAll.accentBorder),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: app.shape.br(11),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    final grid = SeeAllPosterGrid(
      key: _gridKey,
      items: _sortedItems,
      isTelevision: widget.isTelevision,
      loadingMore: _loadingMore,
      exhausted: _exhausted || _pagingPaused,
      onOpen: widget.onOpenItem,
      onQuickPlay: widget.onQuickPlay,
      onItemFocused: widget.onItemFocused,
      isBound: widget.isBound,
      onLoadMore: () => _loadMore(),
      onExitBottom: _pagingPaused ? _retryNode.requestFocus : null,
      onExitTop: widget.isTelevision ? () => _typeNode.requestFocus() : null,
      // Embedded: Left at grid column 0 escapes to the TV sidebar.
      onExitLeft: widget.embedded
          ? () => MainPageBridge.focusTvSidebar?.call()
          : null,
    );
    return Column(
      children: [
        Expanded(child: grid),
        if (_pagingPaused)
          SafeArea(
            top: false,
            child: Focus(
              onKeyEvent: (_, event) {
                if (event is KeyDownEvent &&
                    event.logicalKey == LogicalKeyboardKey.arrowUp) {
                  _gridKey.currentState?.focusFirst();
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: TextButton(
                focusNode: _retryNode,
                onPressed: _loadingMore ? null : () => _loadMore(resume: true),
                child: Text(_loadingMore ? 'Loading…' : 'Continue loading'),
              ),
            ),
          ),
      ],
    );
  }
}
