import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/stremio_addon.dart';
import '../../services/main_page_bridge.dart';
import '../../services/stremio_service.dart';
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
    this.seedItems = const [],
    this.seedNextSkip = 0,
    this.isTelevision = false,
    this.onQuickPlay,
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
  // The empty-state Retry button — the only recovery affordance when a filter
  // yields nothing, so it must be DPAD-reachable.
  final FocusNode _retryNode = FocusNode(debugLabel: 'seeall_retry');

  @override
  void initState() {
    super.initState();
    _type = widget.initialCatalog.type;
    _catalog = widget.initialCatalog;
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
    _retryNode.dispose();
    super.dispose();
  }

  // ── Derived options ────────────────────────────────────────────────────────

  List<String> get _types {
    final seen = <String>{};
    final out = <String>[];
    for (final c in widget.addon.catalogs) {
      // Only offer types that have a browsable catalog — a search-only catalog
      // returns empty when browsed, and changing Type must never land on one.
      if (c.isBrowsable && seen.add(c.type)) out.add(c.type);
    }
    return out;
  }

  List<StremioAddonCatalog> _catalogsForType(String type) => widget.addon.catalogs
      .where((c) => c.type == type && c.isBrowsable)
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
      final page = await _stremio.fetchCatalog(
        widget.addon,
        _catalog,
        skip: 0,
        genre: _genre,
        onRawCount: (c) => rawCount = c,
      );
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
      final page = await _stremio.fetchCatalog(
        widget.addon,
        _catalog,
        skip: _nextSkip,
        genre: _genre,
        onRawCount: (c) => rawCount = c,
      );
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

  // ── TV filter-bar focus wiring ─────────────────────────────────────────────

  List<FocusNode> get _filterNodes => [
        if (widget.leadingNode != null) widget.leadingNode!,
        _typeNode,
        _catalogNode,
        if (_catalog.supportsGenre) _genreNode,
      ];

  /// Whether the empty-state (with the Retry button) is currently shown instead
  /// of the grid.
  bool get _showingEmpty => !_loadingInitial && _items.isEmpty;

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
              subtitle: 'Browse catalog',
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
        padding: const EdgeInsets.fromLTRB(24, 10, 24, 12),
        child: Wrap(
          spacing: 12,
          runSpacing: 10,
          children: [
            if (widget.leading != null) widget.leading!,
            StremioDropdown<String>(
              label: 'Type',
              value: _type,
              isTelevision: widget.isTelevision,
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
                focusNode: _genreNode,
                options: [
                  const StremioDropdownOption<String>('', 'All'),
                  for (final g in _catalog.genreOptions)
                    StremioDropdownOption<String>(g, g),
                ],
                onSelected: (g) => _onGenreChanged(g.isEmpty ? null : g),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loadingInitial) {
      return const Center(
        child: SizedBox(
          width: 26,
          height: 26,
          child: CircularProgressIndicator(
            strokeWidth: 2.4,
            valueColor: AlwaysStoppedAnimation<Color>(kSeeAllAccent),
          ),
        ),
      );
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
                'Nothing in this catalog',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                // fetchCatalog swallows errors and returns [], so an empty
                // result can also be a transient failure — offer a retry rather
                // than dead-ending (re-selecting the same filter is a no-op).
                'This may be empty, or the addon failed to respond.',
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
      items: _items,
      isTelevision: widget.isTelevision,
      loadingMore: _loadingMore,
      exhausted: _exhausted,
      onOpen: widget.onOpenItem,
      onQuickPlay: widget.onQuickPlay,
      isBound: widget.isBound,
      onLoadMore: _loadMore,
      onExitTop: widget.isTelevision ? () => _typeNode.requestFocus() : null,
      // Embedded: Left at grid column 0 escapes to the TV sidebar.
      onExitLeft: widget.embedded ? () => MainPageBridge.focusTvSidebar?.call() : null,
    );
  }
}
