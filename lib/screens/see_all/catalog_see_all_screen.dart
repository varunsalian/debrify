import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/stremio_addon.dart';
import '../../services/analytics_service.dart';
import '../../services/main_page_bridge.dart';
import '../../widgets/skeleton_poster.dart';
import '../../services/stremio_service.dart';
import '../../widgets/see_all/see_all_filter_bar.dart';
import '../../widgets/see_all/see_all_filter_focus.dart';
import '../../widgets/see_all/see_all_header.dart';
import '../../widgets/see_all/see_all_poster_grid.dart';
import '../../widgets/see_all/see_all_theme.dart';
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
  final StremioAddonCatalog initialCatalog;

  /// When set, this See-All is a SEARCH result: reload / load-more query the
  /// catalog's `search=` endpoint (paged) instead of browsing it, so the grid
  /// shows *all* matches for the query rather than getting muddied with
  /// non-matching browse items. Filter changes stay in search mode — switching
  /// Type/Catalog re-runs the query on the new catalog, Genre narrows it.
  final String? query;

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
    required this.initialCatalog,
    required this.onOpenItem,
    this.query,
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
    if (widget.seedItems.isNotEmpty) {
      _items.addAll(widget.seedItems);
      _nextSkip = widget.seedNextSkip;
      _loadingInitial = false;
      // Embedded (Discover): the host focuses the Source dropdown; a source swap
      // re-mounts this panel, so don't steal the DPAD ring into the grid.
      if (widget.isTelevision && !widget.embedded) {
        WidgetsBinding.instance.addPostFrameCallback(
            (_) => _gridKey.currentState?.focusFirst());
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

  List<StremioAddonCatalog> _catalogsForType(String type) => widget.addon.catalogs
      .where((c) => c.type == type && _usable(c))
      .toList();

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
      _loadingMore = false;
    });
    try {
      var rawCount = 0;
      final page = await _fetchPage(0, (c) => rawCount = c);
      if (!mounted || token != _reqToken) return;
      setState(() {
        _items.addAll(page);
        _nextSkip = rawCount > 0 ? rawCount : page.length;
        _exhausted = page.isEmpty;
        _loadingInitial = false;
      });
      if (autoFocus && widget.isTelevision && page.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback(
            (_) => _gridKey.currentState?.focusFirst());
      }
    } catch (_) {
      if (!mounted || token != _reqToken) return;
      setState(() {
        _loadingInitial = false;
        _exhausted = true;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingInitial || _loadingMore || _exhausted) return;
    final token = _reqToken;
    setState(() => _loadingMore = true);
    try {
      var rawCount = 0;
      final page = await _fetchPage(_nextSkip, (c) => rawCount = c);
      if (!mounted || token != _reqToken) return;
      if (page.isEmpty) {
        setState(() {
          _exhausted = true;
          _loadingMore = false;
        });
        return;
      }
      final seen = _items.map((m) => m.id).toSet();
      final fresh = page.where((m) => seen.add(m.id)).toList();
      setState(() {
        _nextSkip += rawCount > 0 ? rawCount : page.length;
        if (fresh.isEmpty) {
          _exhausted = true;
        } else {
          _items.addAll(fresh);
        }
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted || token != _reqToken) return;
      setState(() => _loadingMore = false);
    }
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
    // type/catalog/genre edits (it's a preference, not a filter).
    setState(() => _sort = sort);
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
      ];

  /// Whether the empty-state (with the Retry button) is currently shown instead
  /// of the grid.
  bool get _showingEmpty => !_loadingInitial && _items.isEmpty;

  /// Discover TV styling: quiet text-segment filters on the glass stage, no
  /// per-poster rating chips (the detail rail carries that information).
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
      onLeftEdge: widget.embedded ? () => MainPageBridge.focusTvSidebar?.call() : null,
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
      backgroundColor: kSeeAllBg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SeeAllHeader(
              title: widget.addon.name,
              subtitle: _searching ? 'Results for “$_searchQuery”' : 'Browse catalog',
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
          activeCount: (_genre != null ? 1 : 0) + (_sort != _sortDefault ? 1 : 0),
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
                StremioDropdownOption(_sortImdbDesc, 'IMDb Rating · High → Low'),
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
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.movie_filter_rounded,
                  size: 44, color: Colors.white.withValues(alpha: 0.25)),
              const SizedBox(height: 14),
              Text(
                _searching ? 'No matches for “$_searchQuery”' : 'Nothing in this catalog',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                // fetch swallows errors and returns [], so an empty result can
                // also be a transient failure — offer a retry rather than
                // dead-ending (re-selecting the same filter is a no-op).
                _searching
                    ? 'No results for this query — try another catalog or genre.'
                    : 'This may be empty, or the addon failed to respond.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.4),
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
                  onPressed: () => _reload(autoFocus: true),
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Retry'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: BorderSide(color: kSeeAllAccentBorder),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(11),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return SeeAllPosterGrid(
      key: _gridKey,
      items: _sortedItems,
      isTelevision: widget.isTelevision,
      loadingMore: _loadingMore,
      exhausted: _exhausted,
      onOpen: widget.onOpenItem,
      onQuickPlay: widget.onQuickPlay,
      onItemFocused: widget.onItemFocused,
      // Discover on TV has the detail rail naming the type and carrying the
      // rating — drop both badges there.
      showTypeBadge: !_quiet,
      showRatingBadge: !_quiet,
      isBound: widget.isBound,
      onLoadMore: _loadMore,
      onExitTop: widget.isTelevision ? () => _typeNode.requestFocus() : null,
      // Embedded: Left at grid column 0 escapes to the TV sidebar.
      onExitLeft: widget.embedded ? () => MainPageBridge.focusTvSidebar?.call() : null,
    );
  }
}
