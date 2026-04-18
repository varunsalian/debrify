import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../models/stremio_addon.dart';
import '../models/advanced_search_selection.dart';
import '../services/stremio_service.dart';
import '../services/trakt/trakt_service.dart';
import '../services/trakt/trakt_episode_model.dart';
import '../services/series_source_service.dart';
import '../services/storage_service.dart';
import '../screens/debrid_downloads_screen.dart';
import '../screens/torbox/torbox_downloads_screen.dart';
import '../screens/debrify_tv/widgets/tv_focus_scroll_wrapper.dart';
import '../screens/stremio_tv/widgets/stremio_tv_catalog_picker_dialog.dart';
import 'add_source_picker_dialog.dart';
import 'trakt/trakt_menu_helpers.dart';

/// A browsable catalog widget that shows content from Stremio addons.
///
/// Features:
/// - Two-level dropdown: Provider -> Catalog
/// - Dynamic filter dropdowns based on catalog extras (genre, etc.)
/// - Grid/list of content items
/// - Item selection triggers stream search callback
/// - Quick Play and Sources buttons for each item
class CatalogBrowser extends StatefulWidget {
  /// Callback when user selects an item to search streams for (Sources button)
  final void Function(AdvancedSearchSelection selection)? onItemSelected;

  /// Callback when user wants to quick play an item (Quick Play button)
  /// If null, Quick Play button will fallback to onItemSelected behavior
  final void Function(AdvancedSearchSelection selection)? onQuickPlay;

  /// Whether to show the Quick Play button (hide when PikPak is default provider)
  final bool showQuickPlay;

  /// Optional: Filter to show only this addon's catalogs
  /// If null, shows all available catalog addons
  final StremioAddon? filterAddon;

  /// Optional: Search query to filter catalog results
  /// If provided, searches within the addon's searchable catalogs
  final String? searchQuery;

  /// Callback when user navigates up from the top of the catalog browser
  final VoidCallback? onRequestFocusAbove;

  /// Optional: Default catalog ID to select on first load
  /// If set and found in the addon's catalogs, it will be auto-selected instead of the first catalog
  final String? defaultCatalogId;

  /// Callback when user selects "Select Source" for a series
  final void Function(StremioMeta show)? onSelectSource;

  /// Callback when user selects "Search Season Packs" for a series
  final void Function(StremioMeta show)? onSearchPacks;

  /// Callback when user exits episode drill-down mode (back button)
  final VoidCallback? onEpisodeModeExited;

  /// Whether running on Android TV (disables animations, shadows, clips for GPU perf)
  final bool isTelevision;

  const CatalogBrowser({
    super.key,
    this.onItemSelected,
    this.onQuickPlay,
    this.showQuickPlay = true,
    this.filterAddon,
    this.searchQuery,
    this.onRequestFocusAbove,
    this.defaultCatalogId,
    this.onSelectSource,
    this.onSearchPacks,
    this.onEpisodeModeExited,
    this.isTelevision = false,
  });

  @override
  State<CatalogBrowser> createState() => CatalogBrowserState();
}

class CatalogBrowserState extends State<CatalogBrowser> {
  // Service
  final StremioService _stremioService = StremioService.instance;

  // Available addons and catalogs
  List<StremioAddon> _addons = [];
  bool _isLoadingAddons = true;

  // Selected provider and catalog
  StremioAddon? _selectedAddon;
  StremioAddonCatalog? _selectedCatalog;

  // Filter state
  String? _selectedGenre;

  // Content state
  List<StremioMeta> _content = [];
  bool _isLoadingContent = false;
  bool _hasMoreContent = true;
  int _currentSkip = 0;
  static const int _pageSize = 20;

  // Search state
  bool _isSearchMode = false;
  String _lastSearchQuery = '';
  Timer? _searchDebouncer;

  // Scroll controller for pagination
  final ScrollController _scrollController = ScrollController();

  // Focus nodes for TV/DPAD navigation
  final FocusNode _providerDropdownFocusNode = FocusNode(
    debugLabel: 'provider_dropdown',
  );
  final FocusNode _catalogDropdownFocusNode = FocusNode(
    debugLabel: 'catalog_dropdown',
  );
  final FocusNode _genreDropdownFocusNode = FocusNode(
    debugLabel: 'genre_dropdown',
  );
  List<FocusNode> _contentFocusNodes = [];
  int _focusedContentIndex =
      -1; // Track last focused content item for sidebar navigation

  // Focus state trackers for visual indicators
  final ValueNotifier<bool> _providerDropdownFocused = ValueNotifier(false);
  final ValueNotifier<bool> _catalogDropdownFocused = ValueNotifier(false);
  final ValueNotifier<bool> _genreDropdownFocused = ValueNotifier(false);

  // Trakt integration
  bool _isTraktAuthenticated = false;

  // Bound sources for movies
  Map<String, List<SeriesSource>> _boundSources = {};

  // Episode drill-down mode
  StremioMeta? _pendingEpisodeShow; // Deferred until _loadAddons completes
  int? _pendingEpisodeSeason;
  int? _pendingEpisodeEpisode;
  int _episodeModeGeneration = 0;
  StremioMeta? _selectedShow;
  List<TraktSeason> _episodeSeasons = [];
  int _selectedSeasonNumber = 1;
  bool _isLoadingEpisodes = false;
  String? _episodeErrorMessage;
  Map<String, double> _episodeWatchProgress = {};
  List<FocusNode> _episodeFocusNodes = [];
  final ScrollController _episodeScrollController = ScrollController();
  final FocusNode _episodeBackButtonFocusNode = FocusNode(
    debugLabel: 'catalog-ep-back',
  );
  final FocusNode _episodeSeasonDropdownFocusNode = FocusNode(
    debugLabel: 'catalog-ep-season',
  );

  /// Public method to request focus on the first dropdown (catalog dropdown)
  /// Called from parent when navigating down from Sources
  void requestFocusOnFirstDropdown() {
    if (_selectedShow != null) {
      // Episode mode: catalog dropdown is not in tree — focus season dropdown or back button
      if (_episodeSeasons.isNotEmpty) {
        _episodeSeasonDropdownFocusNode.requestFocus();
      } else {
        _episodeBackButtonFocusNode.requestFocus();
      }
    } else {
      _catalogDropdownFocusNode.requestFocus();
    }
  }

  /// Public method to request focus on the last focused content item
  /// Called from parent when returning from sidebar navigation
  /// Returns true if focus was restored to a content item, false otherwise
  bool requestFocusOnLastItem() {
    // Episode mode: focus episode items
    if (_selectedShow != null) {
      if (_episodeFocusNodes.isNotEmpty) {
        _episodeFocusNodes.first.requestFocus();
        return true;
      }
      return false;
    }
    if (_focusedContentIndex >= 0 &&
        _focusedContentIndex < _contentFocusNodes.length) {
      _contentFocusNodes[_focusedContentIndex].requestFocus();
      return true;
    }
    // Fallback to first content item if available
    if (_contentFocusNodes.isNotEmpty) {
      _contentFocusNodes[0].requestFocus();
      return true;
    }
    return false;
  }

  /// Public: enter episode drill-down for a show (called from parent when switching from aggregated search)
  /// If _selectedAddon is not yet loaded (async), defers until _loadAddons completes.
  void enterEpisodeModeForShow(StremioMeta show, {int? season, int? episode}) {
    if (_selectedAddon != null) {
      _enterEpisodeMode(show, initialSeason: season, initialEpisode: episode);
    } else {
      _pendingEpisodeShow = show;
      _pendingEpisodeSeason = season;
      _pendingEpisodeEpisode = episode;
    }
  }

  /// Check if content list has any items that can receive focus
  bool get hasContentItems => _contentFocusNodes.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _loadAddons();
    _scrollController.addListener(_onScroll);
    TraktService.instance.isAuthenticated().then((auth) {
      if (mounted) setState(() => _isTraktAuthenticated = auth);
    });
    // Set up focus listeners for visual indicators
    _providerDropdownFocusNode.addListener(() {
      _providerDropdownFocused.value = _providerDropdownFocusNode.hasFocus;
    });
    _catalogDropdownFocusNode.addListener(() {
      _catalogDropdownFocused.value = _catalogDropdownFocusNode.hasFocus;
    });
    _genreDropdownFocusNode.addListener(() {
      _genreDropdownFocused.value = _genreDropdownFocusNode.hasFocus;
    });
    // Set up key event handlers for arrow navigation
    _providerDropdownFocusNode.onKeyEvent = _handleProviderDropdownKeyEvent;
    _catalogDropdownFocusNode.onKeyEvent = _handleCatalogDropdownKeyEvent;
    _genreDropdownFocusNode.onKeyEvent = _handleGenreDropdownKeyEvent;
    _episodeSeasonDropdownFocusNode.onKeyEvent =
        _handleEpisodeSeasonDropdownKeyEvent;
  }

  /// Navigate down from top dropdowns: if in episode mode, go to season dropdown; otherwise content items.
  void _focusDownFromDropdowns() {
    if (_selectedShow != null) {
      // Episode mode: go to season dropdown (or back button if no seasons)
      if (_episodeSeasons.isNotEmpty) {
        _episodeSeasonDropdownFocusNode.requestFocus();
      } else {
        _episodeBackButtonFocusNode.requestFocus();
      }
    } else if (_contentFocusNodes.isNotEmpty) {
      _contentFocusNodes[0].requestFocus();
    }
  }

  KeyEventResult _handleProviderDropdownKeyEvent(
    FocusNode node,
    KeyEvent event,
  ) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    // Up arrow: navigate to Sources above
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      widget.onRequestFocusAbove?.call();
      return KeyEventResult.handled;
    }
    // Down arrow: navigate to episode filter bar or first content item
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _focusDownFromDropdowns();
      return KeyEventResult.handled;
    }
    // Right arrow: navigate to catalog dropdown
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      _catalogDropdownFocusNode.requestFocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _handleCatalogDropdownKeyEvent(
    FocusNode node,
    KeyEvent event,
  ) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    // Up arrow: navigate to Sources above
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      widget.onRequestFocusAbove?.call();
      return KeyEventResult.handled;
    }
    // Left arrow: no left target (provider dropdown removed)
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      return KeyEventResult.handled;
    }
    // Down arrow: navigate to episode filter bar or first content item
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _focusDownFromDropdowns();
      return KeyEventResult.handled;
    }
    // Right arrow: navigate to genre dropdown if available
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      if (_selectedCatalog?.supportsGenre ?? false) {
        _genreDropdownFocusNode.requestFocus();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _handleGenreDropdownKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    // Up arrow: navigate to Sources above
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      widget.onRequestFocusAbove?.call();
      return KeyEventResult.handled;
    }
    // Left arrow: navigate to catalog dropdown
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _catalogDropdownFocusNode.requestFocus();
      return KeyEventResult.handled;
    }
    // Down arrow: navigate to episode filter bar or first content item
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _focusDownFromDropdowns();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  void didUpdateWidget(CatalogBrowser oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Handle filterAddon changes (user switched addon in dropdown)
    if (widget.filterAddon != oldWidget.filterAddon) {
      // Exit episode mode if active
      if (_selectedShow != null) _exitEpisodeMode();
      // Reset state and reload with new addon
      setState(() {
        _selectedAddon = null;
        _selectedCatalog = null;
        _selectedGenre = null;
        _content = [];
        _isSearchMode = false;
        _lastSearchQuery = '';
      });
      _loadAddons();
      return; // Skip search query handling since we're reloading everything
    }

    // Handle search query changes
    final newQuery = widget.searchQuery?.trim() ?? '';
    final oldQuery = oldWidget.searchQuery?.trim() ?? '';

    if (newQuery != oldQuery) {
      // Cancel any pending search
      _searchDebouncer?.cancel();

      if (newQuery.isNotEmpty) {
        // Debounce search to avoid flooding API on every keystroke
        _searchDebouncer = Timer(const Duration(milliseconds: 400), () {
          _performSearch(newQuery);
        });
      } else if (_isSearchMode) {
        // Exit search mode - return to catalog browsing
        setState(() {
          _isSearchMode = false;
          _lastSearchQuery = '';
        });
        _loadContent();
      }
    }
  }

  @override
  void dispose() {
    _searchDebouncer?.cancel();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _episodeScrollController.dispose();
    _episodeBackButtonFocusNode.dispose();
    _episodeSeasonDropdownFocusNode.dispose();
    _providerDropdownFocusNode.dispose();
    _catalogDropdownFocusNode.dispose();
    _genreDropdownFocusNode.dispose();
    _providerDropdownFocused.dispose();
    _catalogDropdownFocused.dispose();
    _genreDropdownFocused.dispose();
    for (final node in _contentFocusNodes) {
      node.dispose();
    }
    for (final node in _episodeFocusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMoreContent();
    }
  }

  Future<void> _loadAddons() async {
    setState(() => _isLoadingAddons = true);
    try {
      List<StremioAddon> catalogAddons;

      // If filterAddon is provided, only show that addon
      if (widget.filterAddon != null) {
        catalogAddons = [widget.filterAddon!];
      } else {
        catalogAddons = await _stremioService.getCatalogAddons();
      }

      if (mounted) {
        setState(() {
          _addons = catalogAddons;
          _isLoadingAddons = false;
          // Auto-select first addon if available
          if (_addons.isNotEmpty && _selectedAddon == null) {
            _selectedAddon = _addons.first;
            // Auto-select catalog: use defaultCatalogId if provided and found, otherwise first
            // defaultCatalogId uses composite "type:id" format to handle addons with duplicate IDs across types
            if (_selectedAddon!.catalogs.isNotEmpty) {
              StremioAddonCatalog? defaultCatalog;
              if (widget.defaultCatalogId != null) {
                final parts = widget.defaultCatalogId!.split(':');
                if (parts.length == 2) {
                  defaultCatalog = _selectedAddon!.catalogs
                      .where((c) => c.type == parts[0] && c.id == parts[1])
                      .firstOrNull;
                }
              }
              _selectedCatalog =
                  defaultCatalog ?? _selectedAddon!.catalogs.first;
              _loadContent();
            }
          }

          // Consume pending episode drill-down (deferred from enterEpisodeModeForShow)
          final pending = _pendingEpisodeShow;
          if (pending != null && _selectedAddon != null) {
            final pendingSeason = _pendingEpisodeSeason;
            final pendingEpisode = _pendingEpisodeEpisode;
            _pendingEpisodeShow = null;
            _pendingEpisodeSeason = null;
            _pendingEpisodeEpisode = null;
            // Schedule after setState completes
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted)
                _enterEpisodeMode(
                  pending,
                  initialSeason: pendingSeason,
                  initialEpisode: pendingEpisode,
                );
            });
          }
        });
      }
    } catch (e) {
      debugPrint('CatalogBrowser: Error loading addons: $e');
      if (mounted) {
        setState(() => _isLoadingAddons = false);
      }
    }
  }

  Future<void> _loadContent() async {
    if (_selectedAddon == null || _selectedCatalog == null) return;

    // Reset focus nodes when loading fresh content (catalog/filter change)
    _resetContentFocusNodes();

    setState(() {
      _isLoadingContent = true;
      _content = [];
      _currentSkip = 0;
      _hasMoreContent = true;
    });

    await _fetchContent();
  }

  Future<void> _loadMoreContent() async {
    if (_isLoadingContent ||
        !_hasMoreContent ||
        _selectedAddon == null ||
        _selectedCatalog == null)
      return;
    // Set loading flag immediately to prevent race condition from rapid scroll events
    setState(() => _isLoadingContent = true);
    await _fetchContent();
  }

  Future<void> _fetchContent() async {
    if (_selectedAddon == null || _selectedCatalog == null) return;

    setState(() => _isLoadingContent = true);

    try {
      final items = await _stremioService.fetchCatalog(
        _selectedAddon!,
        _selectedCatalog!,
        skip: _currentSkip,
        genre: _selectedGenre,
      );

      if (mounted) {
        setState(() {
          if (_currentSkip == 0) {
            _content = items;
          } else {
            _content.addAll(items);
          }
          _currentSkip += items.length;
          _hasMoreContent = items.length >= _pageSize;
          _isLoadingContent = false;
          _refreshContentFocusNodes();
        });
        _loadBoundSources();
      }
    } catch (e) {
      debugPrint('CatalogBrowser: Error fetching content: $e');
      if (mounted) {
        setState(() {
          _isLoadingContent = false;
          _hasMoreContent = false;
        });
      }
    }
  }

  /// Perform search within the addon's catalogs
  Future<void> _performSearch(String query) async {
    if (_selectedAddon == null) return;

    setState(() {
      _isSearchMode = true;
      _lastSearchQuery = query;
      _isLoadingContent = true;
      _content = [];
      _hasMoreContent = false; // Search doesn't support pagination
    });

    try {
      final results = await _stremioService.searchAddonCatalogs(
        _selectedAddon!,
        query,
      );

      if (mounted) {
        setState(() {
          _content = results;
          _isLoadingContent = false;
          _refreshContentFocusNodes();
        });
        _loadBoundSources();
      }
    } catch (e) {
      debugPrint('CatalogBrowser: Error searching: $e');
      if (mounted) {
        setState(() {
          _isLoadingContent = false;
        });
      }
    }
  }

  void _refreshContentFocusNodes() {
    // Only add new focus nodes for new items (don't dispose existing ones during pagination)
    final currentCount = _contentFocusNodes.length;
    final neededCount = _content.length;

    if (neededCount > currentCount) {
      // Add focus nodes for new items only
      for (int i = currentCount; i < neededCount; i++) {
        final node = FocusNode(debugLabel: 'content_item_$i');
        // Track focused content index for sidebar navigation
        final capturedIndex = i;
        node.addListener(() {
          if (node.hasFocus && mounted) {
            _focusedContentIndex = capturedIndex;
          }
        });
        _contentFocusNodes.add(node);
      }
    } else if (neededCount < currentCount) {
      // Content was reset (new catalog/filter) - dispose extra nodes and trim list
      for (int i = neededCount; i < currentCount; i++) {
        _contentFocusNodes[i].dispose();
      }
      _contentFocusNodes = _contentFocusNodes.sublist(0, neededCount);
      // Reset focused index if it's now out of bounds
      if (_focusedContentIndex >= neededCount) {
        _focusedContentIndex = -1;
      }
    }
  }

  void _resetContentFocusNodes() {
    // Full reset - dispose all and create fresh (used when catalog/filter changes)
    for (final node in _contentFocusNodes) {
      node.dispose();
    }
    _contentFocusNodes = [];
  }

  void _onAddonChanged(StremioAddon? addon) {
    if (addon == null || addon == _selectedAddon) return;

    setState(() {
      _selectedAddon = addon;
      // Reset catalog and genre when addon changes
      _selectedCatalog = addon.catalogs.isNotEmpty
          ? addon.catalogs.first
          : null;
      _selectedGenre = null;
    });
    if (_selectedCatalog != null) {
      _loadContent();
    }
  }

  void _onCatalogChanged(StremioAddonCatalog? catalog) {
    if (catalog == null || catalog == _selectedCatalog) return;

    setState(() {
      _selectedCatalog = catalog;
      _selectedGenre = null; // Reset genre when catalog changes
    });
    _loadContent();
  }

  void _onGenreChanged(String? genre) {
    if (genre == _selectedGenre) return;

    setState(() {
      _selectedGenre = genre;
    });
    _loadContent();
  }

  void _onItemTap(StremioMeta item) {
    if (widget.onItemSelected == null) return;

    // For series, try episode drill-down if addon supports meta
    if (item.type == 'series' &&
        _selectedAddon != null &&
        _selectedAddon!.supportsMeta) {
      _enterEpisodeMode(item);
      return;
    }

    final selection = AdvancedSearchSelection(
      imdbId: item.effectiveImdbId ?? item.id,
      isSeries: item.type == 'series',
      title: item.name,
      year: item.year,
      contentType: item.type,
      posterUrl: item.poster,
    );

    widget.onItemSelected!(selection);
  }

  void _onQuickPlay(StremioMeta item) async {
    int? season;
    int? episode;

    // For series, look up last played episode to determine S/E
    // (analogous to Trakt's fetchNextEpisode)
    if (item.type == 'series') {
      // Try IMDB-based lookup first (reliable, no title guessing)
      final imdbId = item.effectiveImdbId;
      if (imdbId != null) {
        final lastPlayed = await StorageService.getLastPlayedEpisodeByImdbId(
          imdbId,
        );
        if (!mounted) return;
        if (lastPlayed != null) {
          season = lastPlayed['season'] as int?;
          episode = lastPlayed['episode'] as int?;
        }
      }

      // Fallback to title-based lookup (for existing data written before imdbId tracking)
      if (season == null || episode == null) {
        final byTitle = await StorageService.getLastPlayedEpisode(
          seriesTitle: item.name,
        );
        if (!mounted) return;
        if (byTitle != null) {
          season = byTitle['season'] as int?;
          episode = byTitle['episode'] as int?;
        }
      }

      // Default to S01E01 if no history at all
      season ??= 1;
      episode ??= 1;
    }

    final selection = AdvancedSearchSelection(
      imdbId: item.effectiveImdbId ?? item.id,
      isSeries: item.type == 'series',
      title: item.name,
      year: item.year,
      season: season,
      episode: episode,
      contentType: item.type,
      posterUrl: item.poster,
    );

    // Use onQuickPlay if available, otherwise fallback to onItemSelected
    if (widget.onQuickPlay != null) {
      widget.onQuickPlay!(selection);
    } else if (widget.onItemSelected != null) {
      widget.onItemSelected!(selection);
    }
  }

  Future<void> _handleAddToStremioTv(StremioMeta item) async {
    final result = await StremioTvCatalogPickerDialog.show(context, item: item);
    if (!mounted || result == null) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.message),
        backgroundColor: result.duplicate
            ? Colors.orange.shade700
            : const Color(0xFF34D399),
      ),
    );
  }

  KeyEventResult _handleContentItemKey(
    int index,
    KeyEvent event, {
    bool? isQuickPlayFocused,
  }) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    // List navigation (up/down only)
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (index == 0) {
        // Move to catalog dropdown (first dropdown in the row)
        _catalogDropdownFocusNode.requestFocus();
        return KeyEventResult.handled;
      }
      if (index > 0 && index - 1 < _contentFocusNodes.length) {
        FocusScope.of(context).requestFocus(_contentFocusNodes[index - 1]);
        return KeyEventResult.handled;
      }
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (index + 1 < _contentFocusNodes.length) {
        FocusScope.of(context).requestFocus(_contentFocusNodes[index + 1]);
        return KeyEventResult.handled;
      }
    }

    // Select/Enter is now handled within the card widget for button selection
    // This handler only handles navigation

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingAddons) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_addons.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.folder_off_rounded,
              size: 48,
              color: Colors.white.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 12),
            Text(
              'No catalog addons found',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Add a Stremio addon with catalog support',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    // Episode drill-down mode
    if (_selectedShow != null) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _exitEpisodeMode();
        },
        child: Column(
          children: [
            _buildEpisodeFiltersBar(),
            Expanded(child: _buildEpisodeContent()),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Filters row
        _buildFiltersRow(),
        const SizedBox(height: 12),
        // Content list
        Expanded(child: _buildContentList()),
      ],
    );
  }

  Widget _buildFiltersRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // On narrow screens (< 400px), stack dropdowns vertically
          final isNarrow = constraints.maxWidth < 400;

          if (isNarrow) {
            return Column(
              children: [
                // Catalog dropdown - full width
                _buildCatalogDropdown(),
                // Genre dropdown (if supported)
                if (_selectedCatalog?.supportsGenre ?? false) ...[
                  const SizedBox(height: 8),
                  _buildGenreDropdown(),
                ],
              ],
            );
          }

          // Wide screens - horizontal row
          return Row(
            children: [
              // Catalog dropdown
              Expanded(child: _buildCatalogDropdown()),
              // Genre dropdown (if supported)
              if (_selectedCatalog?.supportsGenre ?? false) ...[
                const SizedBox(width: 12),
                Expanded(child: _buildGenreDropdown()),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildProviderDropdown() {
    return ValueListenableBuilder<bool>(
      valueListenable: _providerDropdownFocused,
      builder: (context, isFocused, child) {
        return Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isFocused
                  ? const Color(0xFF3B82F6)
                  : Colors.white.withValues(alpha: 0.1),
              width: isFocused ? 2 : 1,
            ),
            boxShadow: isFocused
                ? [
                    BoxShadow(
                      color: const Color(0xFF3B82F6).withValues(alpha: 0.3),
                      blurRadius: 8,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<StremioAddon>(
              value: _selectedAddon,
              focusNode: _providerDropdownFocusNode,
              isExpanded: true,
              dropdownColor: const Color(0xFF1E293B),
              icon: Icon(
                Icons.keyboard_arrow_down_rounded,
                color: Colors.white.withValues(alpha: 0.7),
              ),
              hint: Text(
                'Select Provider',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
              ),
              items: _addons.map((addon) {
                return DropdownMenuItem(
                  value: addon,
                  child: Row(
                    children: [
                      _buildProviderIcon(addon),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          addon.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
              onChanged: _onAddonChanged,
            ),
          ),
        );
      },
    );
  }

  Widget _buildCatalogDropdown() {
    final catalogs = _selectedAddon?.catalogs ?? [];

    return ValueListenableBuilder<bool>(
      valueListenable: _catalogDropdownFocused,
      builder: (context, isFocused, child) {
        return Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isFocused
                  ? const Color(0xFF3B82F6)
                  : Colors.white.withValues(alpha: 0.1),
              width: isFocused ? 2 : 1,
            ),
            boxShadow: isFocused
                ? [
                    BoxShadow(
                      color: const Color(0xFF3B82F6).withValues(alpha: 0.3),
                      blurRadius: 8,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<StremioAddonCatalog>(
              value: _selectedCatalog,
              focusNode: _catalogDropdownFocusNode,
              isExpanded: true,
              dropdownColor: const Color(0xFF1E293B),
              icon: Icon(
                Icons.keyboard_arrow_down_rounded,
                color: Colors.white.withValues(alpha: 0.7),
              ),
              hint: Text(
                'Select Catalog',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
              ),
              items: catalogs.map((catalog) {
                return DropdownMenuItem(
                  value: catalog,
                  child: Row(
                    children: [
                      _buildTypeIcon(catalog.type),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          // Append type to distinguish catalogs with same name (e.g., "Popular Movies" vs "Popular Series")
                          catalog.type.isNotEmpty
                              ? '${catalog.name} (${catalog.type[0].toUpperCase()}${catalog.type.substring(1)})'
                              : catalog.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
              onChanged: _onCatalogChanged,
            ),
          ),
        );
      },
    );
  }

  Widget _buildGenreDropdown() {
    final genreOptions = _selectedCatalog?.genreOptions ?? [];
    if (genreOptions.isEmpty) return const SizedBox.shrink();

    return ValueListenableBuilder<bool>(
      valueListenable: _genreDropdownFocused,
      builder: (context, isFocused, child) {
        return Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isFocused
                  ? const Color(0xFF3B82F6)
                  : Colors.white.withValues(alpha: 0.1),
              width: isFocused ? 2 : 1,
            ),
            boxShadow: isFocused
                ? [
                    BoxShadow(
                      color: const Color(0xFF3B82F6).withValues(alpha: 0.3),
                      blurRadius: 8,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String?>(
              value: _selectedGenre,
              focusNode: _genreDropdownFocusNode,
              isExpanded: true,
              dropdownColor: const Color(0xFF1E293B),
              icon: Icon(
                Icons.keyboard_arrow_down_rounded,
                color: Colors.white.withValues(alpha: 0.7),
              ),
              hint: Text(
                'All Genres',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
              ),
              items: [
                DropdownMenuItem<String?>(
                  value: null,
                  child: Text(
                    'All Genres',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                    ),
                  ),
                ),
                ...genreOptions.map((genre) {
                  return DropdownMenuItem(
                    value: genre,
                    child: Text(
                      genre,
                      style: const TextStyle(color: Colors.white),
                    ),
                  );
                }),
              ],
              onChanged: _onGenreChanged,
            ),
          ),
        );
      },
    );
  }

  Widget _buildProviderIcon(StremioAddon addon) {
    // Determine icon and color based on addon name or types
    IconData icon;
    Color color;

    final name = addon.name.toLowerCase();
    if (name.contains('cinemeta')) {
      icon = Icons.movie_filter_rounded;
      color = const Color(0xFF60A5FA);
    } else if (name.contains('tv') || addon.types.contains('tv')) {
      icon = Icons.live_tv_rounded;
      color = const Color(0xFFF472B6);
    } else if (name.contains('anime')) {
      icon = Icons.animation_rounded;
      color = const Color(0xFFA78BFA);
    } else {
      icon = Icons.extension_rounded;
      color = const Color(0xFF34D399);
    }

    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Icon(icon, size: 16, color: color),
    );
  }

  Widget _buildTypeIcon(String type) {
    IconData icon;
    Color color;

    switch (type.toLowerCase()) {
      case 'movie':
        icon = Icons.movie_rounded;
        color = const Color(0xFF60A5FA);
        break;
      case 'series':
        icon = Icons.tv_rounded;
        color = const Color(0xFF34D399);
        break;
      case 'tv':
      case 'channel':
        icon = Icons.live_tv_rounded;
        color = const Color(0xFFF472B6);
        break;
      case 'anime':
        icon = Icons.animation_rounded;
        color = const Color(0xFFA78BFA);
        break;
      default:
        icon = Icons.folder_rounded;
        color = const Color(0xFFFBBF24);
    }

    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Icon(icon, size: 16, color: color),
    );
  }

  /// Public: refresh bound sources cache (call after Select Source completes).
  void refreshBoundSources() async {
    await _loadBoundSources();
    _loadBoundSourceForShow();
    if (_selectedShow != null) {
      _loadEpisodeWatchProgress(_selectedShow!);
    }
  }

  /// Load bound sources for all currently displayed series and movie items.
  Future<void> _loadBoundSources() async {
    final items = _content.where(
      (i) => i.type == 'movie' || i.type == 'series',
    );
    final contentImdbIds = <String>{};
    final sources = <String, List<SeriesSource>>{};
    for (final item in items) {
      final imdbId = item.effectiveImdbId ?? item.id;
      contentImdbIds.add(imdbId);
      final list = await SeriesSourceService.getSources(imdbId);
      if (list.isNotEmpty) sources[imdbId] = list;
    }
    if (mounted) {
      setState(() {
        // Remove stale entries for content items, then merge new ones
        // Preserves entries for the episode-mode show (not in _content)
        _boundSources.removeWhere(
          (k, _) => contentImdbIds.contains(k) && !sources.containsKey(k),
        );
        _boundSources.addAll(sources);
      });
    }
  }

  /// Load bound source for the currently selected show (episode mode).
  Future<void> _loadBoundSourceForShow() async {
    if (_selectedShow == null) return;
    final imdbId = _selectedShow!.effectiveImdbId ?? _selectedShow!.id;
    final list = await SeriesSourceService.getSources(imdbId);
    if (mounted) {
      setState(() {
        if (list.isNotEmpty) {
          _boundSources[imdbId] = list;
        } else {
          _boundSources.remove(imdbId);
        }
      });
    }
  }

  /// Load episode watch progress for the selected show.
  Future<void> _loadEpisodeWatchProgress(StremioMeta show) async {
    final imdbId = show.effectiveImdbId;
    if (imdbId == null) return;
    final progress = await StorageService.getEpisodeWatchProgressByImdbId(
      imdbId,
    );
    if (mounted) {
      setState(() => _episodeWatchProgress = progress);
    }
  }

  /// Handle select source action — show edit dialog if source exists, otherwise show picker.
  void _handleSelectSourceAction(StremioMeta item) {
    final imdbId = item.effectiveImdbId ?? item.id;
    if (_boundSources.containsKey(imdbId)) {
      _showEditSourceDialog(item);
    } else {
      _showAddSourcePicker(item, imdbId);
    }
  }

  /// Show the add-source picker (Torrent Search / Real-Debrid / TorBox).
  /// Skips the picker if no cloud providers are enabled.
  Future<void> _showAddSourcePicker(StremioMeta item, String imdbId) async {
    final rdKey = await StorageService.getApiKey();
    final torboxKey = await StorageService.getTorboxApiKey();
    final rdEnabled = rdKey != null && rdKey.isNotEmpty;
    final torboxEnabled = torboxKey != null && torboxKey.isNotEmpty;

    if (!mounted) return;

    // No cloud providers — skip picker, go straight to torrent search
    if (!rdEnabled && !torboxEnabled) {
      widget.onSelectSource?.call(item);
      return;
    }

    await showAddSourcePickerDialog(
      context,
      onTorrentSearch: () => widget.onSelectSource?.call(item),
      onRealDebrid: rdEnabled
          ? () => _pushDebridSelectSource(
              show: item,
              imdbId: imdbId,
              rdEnabled: true,
              torboxEnabled: false,
            )
          : null,
      onTorbox: torboxEnabled
          ? () => _pushDebridSelectSource(
              show: item,
              imdbId: imdbId,
              rdEnabled: false,
              torboxEnabled: true,
            )
          : null,
    );
  }

  /// Show "Edit Sources" dialog with list of bound sources and management options.
  Future<void> _showEditSourceDialog(StremioMeta show) async {
    final imdbId = show.effectiveImdbId ?? show.id;
    final isMovie = show.type == 'movie';
    var sources = List<SeriesSource>.of(
      _boundSources[imdbId] ?? await SeriesSourceService.getSources(imdbId),
    );
    if (sources.isEmpty || !mounted) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
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
                                itemBuilder: (context, index) {
                                  final source = sources[index];
                                  return _buildSourceListTile(
                                    key: ValueKey(source.torrentHash),
                                    source: source,
                                    index: index,
                                    showDragHandle: false,
                                    onDelete: () async {
                                      await SeriesSourceService.removeSourceByHash(
                                        imdbId,
                                        source.torrentHash,
                                      );
                                      final updated =
                                          await SeriesSourceService.getSources(
                                            imdbId,
                                          );
                                      setDialogState(() {
                                        sources.clear();
                                        sources.addAll(updated);
                                      });
                                      if (mounted) {
                                        setState(() {
                                          if (updated.isEmpty) {
                                            _boundSources.remove(imdbId);
                                          } else {
                                            _boundSources[imdbId] = updated;
                                          }
                                        });
                                      }
                                      if (updated.isEmpty &&
                                          dialogContext.mounted) {
                                        Navigator.of(dialogContext).pop();
                                      }
                                    },
                                  );
                                },
                              )
                            : ReorderableListView.builder(
                                shrinkWrap: true,
                                itemCount: sources.length,
                                onReorder: (oldIndex, newIndex) {
                                  if (newIndex > oldIndex) newIndex--;
                                  setDialogState(() {
                                    final item = sources.removeAt(oldIndex);
                                    sources.insert(newIndex, item);
                                  });
                                  SeriesSourceService.setSources(
                                    imdbId,
                                    List.of(sources),
                                  );
                                  setState(
                                    () => _boundSources[imdbId] = List.of(
                                      sources,
                                    ),
                                  );
                                },
                                proxyDecorator: (child, index, animation) {
                                  return Material(
                                    color: Colors.transparent,
                                    elevation: 4,
                                    child: child,
                                  );
                                },
                                itemBuilder: (context, index) {
                                  final source = sources[index];
                                  return _buildSourceListTile(
                                    key: ValueKey(source.torrentHash),
                                    source: source,
                                    index: index,
                                    onDelete: () async {
                                      await SeriesSourceService.removeSourceByHash(
                                        imdbId,
                                        source.torrentHash,
                                      );
                                      final updated =
                                          await SeriesSourceService.getSources(
                                            imdbId,
                                          );
                                      setDialogState(() {
                                        sources.clear();
                                        sources.addAll(updated);
                                      });
                                      if (mounted) {
                                        setState(() {
                                          if (updated.isEmpty) {
                                            _boundSources.remove(imdbId);
                                          } else {
                                            _boundSources[imdbId] = updated;
                                          }
                                        });
                                      }
                                      if (updated.isEmpty &&
                                          dialogContext.mounted) {
                                        Navigator.of(dialogContext).pop();
                                      }
                                    },
                                  );
                                },
                              ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: () {
                                Navigator.of(dialogContext).pop();
                                widget.onSelectSource?.call(show);
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
                                  if (mounted) {
                                    setState(
                                      () => _boundSources.remove(imdbId),
                                    );
                                  }
                                  if (dialogContext.mounted)
                                    Navigator.of(dialogContext).pop();
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
                                  if (mounted) {
                                    setState(
                                      () => _boundSources.remove(imdbId),
                                    );
                                  }
                                  if (dialogContext.mounted)
                                    Navigator.of(dialogContext).pop();
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
                      // Add from Debrid button
                      FutureBuilder<List<bool>>(
                        future: Future.wait([
                          StorageService.getApiKey().then(
                            (k) => k != null && k.isNotEmpty,
                          ),
                          StorageService.getTorboxApiKey().then(
                            (k) => k != null && k.isNotEmpty,
                          ),
                        ]),
                        builder: (context, snapshot) {
                          final rdEnabled = snapshot.data?[0] ?? false;
                          final torboxEnabled = snapshot.data?[1] ?? false;
                          if (!rdEnabled && !torboxEnabled)
                            return const SizedBox.shrink();

                          return Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: () {
                                  Navigator.of(dialogContext).pop();
                                  _pushDebridSelectSource(
                                    show: show,
                                    imdbId: imdbId,
                                    rdEnabled: rdEnabled,
                                    torboxEnabled: torboxEnabled,
                                  );
                                },
                                icon: const Icon(
                                  Icons.cloud_download_outlined,
                                  size: 18,
                                  color: Color(0xFF60A5FA),
                                ),
                                label: const Text(
                                  'Add from Debrid',
                                  style: TextStyle(color: Color(0xFF60A5FA)),
                                ),
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(
                                    color: Color(0xFF60A5FA),
                                    width: 1,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
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

  /// Push debrid downloads screen in select-source mode.
  /// If both providers enabled, shows a picker first.
  void _pushDebridSelectSource({
    required StremioMeta show,
    required String imdbId,
    required bool rdEnabled,
    required bool torboxEnabled,
  }) {
    final isMovie = show.type == 'movie';

    Future<void> saveSource(SeriesSource source) async {
      if (isMovie) {
        await SeriesSourceService.setSources(imdbId, [source]);
      } else {
        await SeriesSourceService.addSource(imdbId, source);
      }
      final updated = await SeriesSourceService.getSources(imdbId);
      if (mounted) {
        setState(() => _boundSources[imdbId] = updated);
      }
    }

    void pushRd() {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => DebridDownloadsScreen(
            isPushedRoute: true,
            initialSearchQuery: show.name,
            selectSourceMode: true,
            onSourceSelected: saveSource,
          ),
        ),
      );
    }

    void pushTorbox() {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => TorboxDownloadsScreen(
            isPushedRoute: true,
            initialSearchQuery: show.name,
            selectSourceMode: true,
            onSourceSelected: saveSource,
          ),
        ),
      );
    }

    // If only one provider, push directly
    if (rdEnabled && !torboxEnabled) {
      pushRd();
      return;
    }
    if (torboxEnabled && !rdEnabled) {
      pushTorbox();
      return;
    }

    // Both enabled — show picker
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Select Provider',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.cloud, color: Color(0xFF22C55E)),
              title: const Text(
                'Real-Debrid',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () {
                Navigator.of(sheetContext).pop();
                pushRd();
              },
            ),
            ListTile(
              leading: const Icon(Icons.cloud, color: Color(0xFF7C3AED)),
              title: const Text(
                'TorBox',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () {
                Navigator.of(sheetContext).pop();
                pushTorbox();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// Build a single source tile for the Edit Sources dialog.
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

  // ── Episode drill-down ──────────────────────────────────────────────────

  /// Fallback: dispatch series directly to torrent search (bypasses episode mode).
  void _fallbackToDirectSearch(StremioMeta show) {
    if (!mounted) return;
    _exitEpisodeModeInternal();
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

  void _enterEpisodeMode(
    StremioMeta show, {
    int? initialSeason,
    int? initialEpisode,
  }) async {
    final generation = ++_episodeModeGeneration;

    setState(() {
      _selectedShow = show;
      _isLoadingEpisodes = true;
      _episodeErrorMessage = null;
      _episodeSeasons = [];
      _selectedSeasonNumber = initialSeason ?? 1;
    });

    // Load bound sources and watch progress for this show
    _loadBoundSourceForShow();
    _loadEpisodeWatchProgress(show);

    for (final node in _episodeFocusNodes) {
      node.dispose();
    }
    _episodeFocusNodes.clear();

    try {
      // Fetch episodes from addon meta endpoint
      final addon = _selectedAddon;
      if (addon == null) {
        setState(() {
          _isLoadingEpisodes = false;
          _episodeErrorMessage = 'No addon selected';
        });
        return;
      }

      final videos = await _stremioService.fetchSeriesMeta(addon, show.id);
      if (!mounted || generation != _episodeModeGeneration) return;

      if (videos == null || videos.isEmpty) {
        _fallbackToDirectSearch(show);
        return;
      }

      // Group videos into seasons
      final seasonMap = <int, List<TraktEpisode>>{};
      for (final v in videos) {
        final seasonRaw = v['season'];
        final seasonNum = seasonRaw is int
            ? seasonRaw
            : (seasonRaw is num ? seasonRaw.toInt() : null);
        if (seasonNum == null || seasonNum <= 0) continue;

        final epRaw = v['number'] ?? v['episode'];
        final epNum = epRaw is int
            ? epRaw
            : (epRaw is num ? epRaw.toInt() : null);
        if (epNum == null) continue;

        final title = (v['title'] as String?) ?? (v['name'] as String?) ?? '';
        final overview = v['overview'] as String?;
        final released = v['released'] as String?;
        final thumbnail = v['thumbnail'] as String?;

        final episode = TraktEpisode(
          season: seasonNum,
          number: epNum,
          title: title,
          overview: overview,
          firstAired: released,
          thumbnailUrl: thumbnail,
        );

        seasonMap.putIfAbsent(seasonNum, () => []);
        seasonMap[seasonNum]!.add(episode);
      }

      if (seasonMap.isEmpty) {
        if (!mounted || generation != _episodeModeGeneration) return;
        _fallbackToDirectSearch(show);
        return;
      }

      // Sort seasons and episodes
      final seasons = seasonMap.entries.map((e) {
        final episodes = e.value..sort((a, b) => a.number.compareTo(b.number));
        return TraktSeason(
          number: e.key,
          episodeCount: episodes.length,
          episodes: episodes,
        );
      }).toList()..sort((a, b) => a.number.compareTo(b.number));

      // Pick the target season: prefer initialSeason if it exists in the data
      final targetSeason =
          (initialSeason != null &&
              seasons.any((s) => s.number == initialSeason))
          ? seasons.firstWhere((s) => s.number == initialSeason)
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

      // Scroll to the target episode and focus it
      final targetEpIndex = initialEpisode != null
          ? targetSeason.episodes.indexWhere((e) => e.number == initialEpisode)
          : -1;
      final focusIndex = targetEpIndex >= 0 ? targetEpIndex : 0;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || generation != _episodeModeGeneration) return;
        // Scroll to target episode if not at top
        if (focusIndex > 0 && _episodeScrollController.hasClients) {
          final offset = focusIndex * 128.0;
          _episodeScrollController.jumpTo(
            offset.clamp(
              0.0,
              _episodeScrollController.position.maxScrollExtent,
            ),
          );
        }
        // Focus the episode card after scroll
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || generation != _episodeModeGeneration) return;
          if (focusIndex < _episodeFocusNodes.length) {
            _episodeFocusNodes[focusIndex].requestFocus();
          }
        });
      });
    } catch (e) {
      if (!mounted || generation != _episodeModeGeneration) return;
      debugPrint('CatalogBrowser: Episode fetch failed: $e');
      _fallbackToDirectSearch(show);
    }
  }

  /// Exit episode mode and notify parent (used by back button, PopScope, addon switch)
  void _exitEpisodeMode() {
    _exitEpisodeModeInternal();
    widget.onEpisodeModeExited?.call();
  }

  /// Exit episode mode without notifying parent (used by _fallbackToDirectSearch
  /// which dispatches onItemSelected instead)
  void _exitEpisodeModeInternal() {
    for (final node in _episodeFocusNodes) {
      node.dispose();
    }
    _episodeFocusNodes.clear();
    setState(() {
      _selectedShow = null;
      _episodeSeasons = [];
      _selectedSeasonNumber = 1;
      _isLoadingEpisodes = false;
      _episodeErrorMessage = null;
      _episodeWatchProgress = {};
    });
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
    );
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
    );

    if (widget.onQuickPlay != null) {
      widget.onQuickPlay!(selection);
    } else if (widget.onItemSelected != null) {
      widget.onItemSelected!(selection);
    }
  }

  KeyEventResult _handleEpisodeCardKey(int index, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (index > 0) {
        _episodeFocusNodes[index - 1].requestFocus();
      } else {
        // First episode: go to season dropdown if available, else back button
        if (_episodeSeasons.isNotEmpty) {
          _episodeSeasonDropdownFocusNode.requestFocus();
        } else {
          _episodeBackButtonFocusNode.requestFocus();
        }
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (index < _episodeFocusNodes.length - 1) {
        _episodeFocusNodes[index + 1].requestFocus();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget _buildEpisodeFiltersBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF1A1A2E), _surfaceDark],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          borderRadius: BorderRadius.circular(10),
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
                  widget.onRequestFocusAbove?.call();
                  return KeyEventResult.handled;
                }
                if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
                  _episodeSeasonDropdownFocusNode.requestFocus();
                  return KeyEventResult.handled;
                }
                if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                  if (_episodeFocusNodes.isNotEmpty) {
                    _episodeFocusNodes.first.requestFocus();
                  }
                  return KeyEventResult.handled;
                }
                if (event.logicalKey == LogicalKeyboardKey.select ||
                    event.logicalKey == LogicalKeyboardKey.enter ||
                    event.logicalKey == LogicalKeyboardKey.escape ||
                    event.logicalKey == LogicalKeyboardKey.goBack) {
                  _exitEpisodeMode();
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: _episodeBackButtonFocusNode.hasFocus
                      ? Colors.white.withValues(alpha: 0.1)
                      : Colors.transparent,
                  border: _episodeBackButtonFocusNode.hasFocus
                      ? Border.all(color: const Color(0xFF60A5FA), width: 2)
                      : null,
                ),
                child: IconButton(
                  icon: const Icon(Icons.arrow_back_rounded),
                  onPressed: _exitEpisodeMode,
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
                  final imdbId =
                      _selectedShow!.effectiveImdbId ?? _selectedShow!.id;
                  final sourceCount = _boundSources[imdbId]?.length ?? 0;
                  return _CatalogSelectSourceButton(
                    hasBoundSource: sourceCount > 0,
                    sourceCount: sourceCount,
                    onTap: () => _handleSelectSourceAction(_selectedShow!),
                    onLeftFocus: _episodeSeasons.isNotEmpty
                        ? _episodeSeasonDropdownFocusNode
                        : _episodeBackButtonFocusNode,
                    onDownArrow: _episodeFocusNodes.isNotEmpty
                        ? () => _episodeFocusNodes.first.requestFocus()
                        : null,
                    onUpArrow: () => widget.onRequestFocusAbove?.call(),
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
      widget.onRequestFocusAbove?.call();
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
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: hasFocus
                  ? const Color(0xFF60A5FA)
                  : Theme.of(
                      context,
                    ).colorScheme.outline.withValues(alpha: 0.3),
              width: hasFocus ? 2.0 : 1.0,
            ),
            boxShadow: hasFocus
                ? [
                    BoxShadow(
                      color: const Color(0xFF60A5FA).withValues(alpha: 0.3),
                      blurRadius: 12,
                      spreadRadius: 0,
                    ),
                  ]
                : null,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              focusNode: _episodeSeasonDropdownFocusNode,
              focusColor: Colors.transparent,
              value: _selectedSeasonNumber,
              isDense: true,
              dropdownColor: const Color(0xFF1E293B),
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

  Widget _buildEpisodeContent() {
    if (_isLoadingEpisodes) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_episodeErrorMessage != null) {
      return Center(
        child: Text(
          _episodeErrorMessage!,
          style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
        ),
      );
    }

    if (_episodeSeasons.isEmpty) {
      return Center(
        child: Text(
          'No episodes found',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
        ),
      );
    }

    final currentSeason = _episodeSeasons.firstWhere(
      (s) => s.number == _selectedSeasonNumber,
      orElse: () => _episodeSeasons.first,
    );

    return TvFocusScrollWrapper(
      child: ListView.builder(
        controller: _episodeScrollController,
        padding: const EdgeInsets.only(top: 8, bottom: 16, left: 16, right: 16),
        itemCount: currentSeason.episodes.length,
        itemBuilder: (context, index) {
          final episode = currentSeason.episodes[index];
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _CatalogEpisodeCard(
              episode: episode,
              showPosterUrl: _selectedShow?.poster,
              focusNode: index < _episodeFocusNodes.length
                  ? _episodeFocusNodes[index]
                  : null,
              onBrowse: () => _onEpisodeTap(episode),
              onQuickPlay: () => _onEpisodeQuickPlay(episode),
              showQuickPlay: widget.showQuickPlay,
              watchProgress:
                  _episodeWatchProgress['${episode.season}-${episode.number}'],
              onKeyEvent: (event) => _handleEpisodeCardKey(index, event),
            ),
          );
        },
      ),
    );
  }

  Widget _buildContentList() {
    if (_isLoadingContent && _content.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_content.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off_rounded,
              size: 48,
              color: Colors.white.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 12),
            Text(
              'No content found',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 16,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _content.length + (_hasMoreContent ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= _content.length) {
          // Loading indicator at end
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }

        final item = _content[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _CatalogItemCard(
            item: item,
            isTelevision: widget.isTelevision,
            focusNode: index < _contentFocusNodes.length
                ? _contentFocusNodes[index]
                : null,
            onQuickPlay: () => _onQuickPlay(item),
            onSources: () => _onItemTap(item),
            onKeyEvent: (event, {bool? isQuickPlayFocused}) =>
                _handleContentItemKey(
                  index,
                  event,
                  isQuickPlayFocused: isQuickPlayFocused,
                ),
            showQuickPlay: widget.showQuickPlay,
            onTraktMenuAction:
                (item.hasValidImdbId ||
                    (item.hasValidId &&
                        (item.type == 'movie' || item.type == 'series')))
                ? (action) => handleTraktMenuAction(
                    context,
                    item,
                    action,
                    onSelectSource: widget.onSelectSource,
                    onEditSource: _handleSelectSourceAction,
                    onSearchPacks: widget.onSearchPacks,
                    onAddToStremioTv: _handleAddToStremioTv,
                  )
                : null,
            hasBoundSource: _boundSources.containsKey(
              item.effectiveImdbId ?? item.id,
            ),
            isTraktAuthenticated: _isTraktAuthenticated,
          ),
        );
      },
    );
  }
}

/// Horizontal card widget for displaying a catalog item (movie/series/channel)
/// Features Quick Play and Sources buttons with DPAD navigation support
class _CatalogItemCard extends StatefulWidget {
  final StremioMeta item;
  final FocusNode? focusNode;
  final VoidCallback onQuickPlay;
  final VoidCallback onSources;
  final KeyEventResult Function(KeyEvent, {bool? isQuickPlayFocused})
  onKeyEvent;
  final bool showQuickPlay;
  final void Function(TraktItemMenuAction action)? onTraktMenuAction;
  final bool hasBoundSource;
  final bool isTraktAuthenticated;
  final bool isTelevision;

  const _CatalogItemCard({
    required this.item,
    this.focusNode,
    required this.onQuickPlay,
    required this.onSources,
    required this.onKeyEvent,
    this.showQuickPlay = true,
    this.onTraktMenuAction,
    this.hasBoundSource = false,
    this.isTraktAuthenticated = false,
    this.isTelevision = false,
  });

  @override
  State<_CatalogItemCard> createState() => _CatalogItemCardState();
}

class _CatalogItemCardState extends State<_CatalogItemCard> {
  bool _isFocused = false;
  int _focusedButtonIndex = 0;
  final GlobalKey<PopupMenuButtonState<TraktItemMenuAction>> _menuKey =
      GlobalKey();

  int get _buttonCount {
    int count = 1; // Browse
    if (widget.showQuickPlay) count++;
    if (widget.onTraktMenuAction != null) count++;
    return count;
  }

  int? get _quickPlayIndex => widget.showQuickPlay ? 1 : null;
  int? get _moreIndex =>
      widget.onTraktMenuAction != null ? _buttonCount - 1 : null;

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      if (_focusedButtonIndex > 0) {
        setState(() => _focusedButtonIndex--);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      if (_focusedButtonIndex < _buttonCount - 1) {
        setState(() => _focusedButtonIndex++);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    if (event.logicalKey == LogicalKeyboardKey.select ||
        event.logicalKey == LogicalKeyboardKey.enter) {
      if (_focusedButtonIndex == 0) {
        widget.onSources();
      } else if (_focusedButtonIndex == _quickPlayIndex) {
        widget.onQuickPlay();
      } else if (_focusedButtonIndex == _moreIndex) {
        _menuKey.currentState?.showButtonMenu();
      }
      return KeyEventResult.handled;
    }

    return widget.onKeyEvent(
      event,
      isQuickPlayFocused: _focusedButtonIndex == _quickPlayIndex,
    );
  }

  /// Strip HTML tags from description text
  String _stripHtml(String text) {
    return text.replaceAll(RegExp(r'<[^>]*>'), '');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Focus(
      focusNode: widget.focusNode,
      onFocusChange: (focused) {
        setState(() {
          _isFocused = focused;
          if (focused) {
            _focusedButtonIndex = 0;
          }
        });
        if (focused) {
          Scrollable.ensureVisible(
            context,
            alignment: 0.5,
            duration: const Duration(milliseconds: 200),
          );
        }
      },
      onKeyEvent: _handleKeyEvent,
      child: GestureDetector(
        onTap: widget.onSources,
        child: widget.isTelevision
            ? Container(
                clipBehavior: Clip.hardEdge,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: _isFocused
                        ? Colors.white.withValues(alpha: 0.35)
                        : Colors.white.withValues(alpha: 0.06),
                    width: _isFocused ? 1.5 : 1,
                  ),
                ),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: _buildBackdropImage(
                        widget.item.background ?? widget.item.poster,
                      ),
                    ),
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                            colors: [
                              Colors.black.withValues(alpha: 0.95),
                              Colors.black.withValues(alpha: 0.8),
                              Colors.black.withValues(alpha: 0.5),
                            ],
                            stops: const [0.0, 0.5, 1.0],
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final useVerticalLayout = constraints.maxWidth < 500;
                          return useVerticalLayout
                              ? _buildVerticalLayout(theme, colorScheme)
                              : _buildHorizontalLayout(theme, colorScheme);
                        },
                      ),
                    ),
                  ],
                ),
              )
            : AnimatedScale(
                scale: _isFocused ? 1.02 : 1.0,
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: _isFocused
                          ? Colors.white.withValues(alpha: 0.35)
                          : Colors.white.withValues(alpha: 0.06),
                      width: _isFocused ? 1.5 : 1,
                    ),
                    boxShadow: _isFocused
                        ? [
                            BoxShadow(
                              color: Colors.white.withValues(alpha: 0.1),
                              blurRadius: 16,
                              spreadRadius: 0,
                            ),
                          ]
                        : null,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: _buildBackdropImage(
                            widget.item.background ?? widget.item.poster,
                          ),
                        ),
                        Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.centerLeft,
                                end: Alignment.centerRight,
                                colors: [
                                  Colors.black.withValues(alpha: 0.95),
                                  Colors.black.withValues(alpha: 0.8),
                                  Colors.black.withValues(alpha: 0.5),
                                ],
                                stops: const [0.0, 0.5, 1.0],
                              ),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final useVerticalLayout =
                                  constraints.maxWidth < 500;
                              return useVerticalLayout
                                  ? _buildVerticalLayout(theme, colorScheme)
                                  : _buildHorizontalLayout(theme, colorScheme);
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  /// Horizontal layout for wide screens - thumbnail, details, and buttons in a row
  Widget _buildHorizontalLayout(ThemeData theme, ColorScheme colorScheme) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 80,
            height: 120,
            child: _buildPoster(colorScheme),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.item.name,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  shadows: widget.isTelevision
                      ? null
                      : [const Shadow(blurRadius: 8, color: Colors.black)],
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              _buildMetadataRow(theme, colorScheme),
              if (widget.item.genres != null &&
                  widget.item.genres!.isNotEmpty) ...[
                const SizedBox(height: 6),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: widget.item.genres!.take(3).map((genre) {
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.15),
                        ),
                      ),
                      child: Text(
                        genre,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.8),
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
              if (widget.item.description != null &&
                  widget.item.description!.isNotEmpty &&
                  _stripHtml(widget.item.description!).trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  _stripHtml(widget.item.description!),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.45),
                    fontSize: 11,
                    height: 1.4,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 8),
        _buildActionButton(
          icon: Icons.list_rounded,
          label: widget.item.type == 'series' ? 'Episodes' : 'Sources',
          color: _accentPurple,
          isHighlighted: _isFocused && _focusedButtonIndex == 0,
          onTap: widget.onSources,
        ),
        if (widget.showQuickPlay) ...[
          const SizedBox(width: 6),
          _buildActionButton(
            icon: Icons.play_arrow_rounded,
            label: 'Play',
            color: _accentRed,
            isHighlighted: _isFocused && _focusedButtonIndex == _quickPlayIndex,
            onTap: widget.onQuickPlay,
          ),
        ],
        if (widget.onTraktMenuAction != null) ...[
          const SizedBox(width: 4),
          buildTraktAddOnlyOverflowMenu(
            isHighlighted: _isFocused && _focusedButtonIndex == _moreIndex,
            menuKey: _menuKey,
            onSelected: (action) => widget.onTraktMenuAction?.call(action),
            isMovie: widget.item.type == 'movie',
            isSeries: widget.item.type == 'series',
            hasBoundSource: widget.hasBoundSource,
            isTraktAuthenticated: widget.isTraktAuthenticated,
          ),
        ],
      ],
    );
  }

  /// Vertical layout for narrow screens - content stacked with buttons below
  Widget _buildVerticalLayout(ThemeData theme, ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 60,
                height: 85,
                child: _buildPoster(colorScheme),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.item.name,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      shadows: widget.isTelevision
                          ? null
                          : [const Shadow(blurRadius: 8, color: Colors.black)],
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  _buildMetadataRow(theme, colorScheme),
                  if (widget.item.genres != null &&
                      widget.item.genres!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: widget.item.genres!.take(3).map((genre) {
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.15),
                            ),
                          ),
                          child: Text(
                            genre,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.8),
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        if (widget.item.description != null &&
            widget.item.description!.isNotEmpty &&
            _stripHtml(widget.item.description!).trim().isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            _stripHtml(widget.item.description!),
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.45),
              fontSize: 11,
              height: 1.4,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _buildActionButton(
                icon: Icons.list_rounded,
                label: widget.item.type == 'series' ? 'Episodes' : 'Sources',
                color: _accentPurple,
                isHighlighted: _isFocused && _focusedButtonIndex == 0,
                onTap: widget.onSources,
              ),
            ),
            if (widget.showQuickPlay) ...[
              const SizedBox(width: 8),
              Expanded(
                child: _buildActionButton(
                  icon: Icons.play_arrow_rounded,
                  label: 'Play',
                  color: _accentRed,
                  isHighlighted:
                      _isFocused && _focusedButtonIndex == _quickPlayIndex,
                  onTap: widget.onQuickPlay,
                ),
              ),
            ],
            if (widget.onTraktMenuAction != null) ...[
              const SizedBox(width: 4),
              buildTraktAddOnlyOverflowMenu(
                isHighlighted: _isFocused && _focusedButtonIndex == _moreIndex,
                menuKey: _menuKey,
                onSelected: (action) => widget.onTraktMenuAction?.call(action),
                isMovie: widget.item.type == 'movie',
                isSeries: widget.item.type == 'series',
                hasBoundSource: widget.hasBoundSource,
                isTraktAuthenticated: widget.isTraktAuthenticated,
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildMetadataRow(ThemeData theme, ColorScheme colorScheme) {
    return Row(
      children: [
        _buildTypeBadge(widget.item.type),
        if (widget.item.year != null) ...[
          const SizedBox(width: 8),
          Text(
            widget.item.year!,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 12,
            ),
          ),
        ],
        if (widget.item.imdbRating != null) ...[
          const SizedBox(width: 8),
          Icon(Icons.star_rounded, size: 14, color: const Color(0xFFFBBF24)),
          const SizedBox(width: 2),
          Text(
            widget.item.imdbRating!.toStringAsFixed(1),
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required bool isHighlighted,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedScale(
        scale: isHighlighted ? 1.08 : 1.0,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isHighlighted ? color : Colors.black.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isHighlighted ? color : color.withValues(alpha: 0.6),
              width: 1,
            ),
            boxShadow: isHighlighted
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.4),
                      blurRadius: 12,
                      spreadRadius: 0,
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 15,
                color: isHighlighted
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.9),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    color: isHighlighted
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.9),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPoster(ColorScheme colorScheme) {
    if (widget.item.poster != null && widget.item.poster!.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: widget.item.poster!,
        memCacheWidth: 200,
        fit: BoxFit.cover,
        placeholder: (context, url) => Container(
          color: colorScheme.surfaceContainerHighest,
          child: Center(
            child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: colorScheme.primary,
              ),
            ),
          ),
        ),
        errorWidget: (context, url, error) => _buildPlaceholder(colorScheme),
      );
    }
    return _buildPlaceholder(colorScheme);
  }

  Widget _buildPlaceholder(ColorScheme colorScheme) {
    return Container(
      color: colorScheme.surfaceContainerHighest,
      child: Center(
        child: Icon(
          _getTypeIcon(widget.item.type),
          size: 24,
          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
        ),
      ),
    );
  }

  Widget _buildTypeBadge(String type) {
    Color color;
    String label;

    switch (type.toLowerCase()) {
      case 'movie':
        color = const Color(0xFF60A5FA);
        label = 'Movie';
        break;
      case 'series':
        color = const Color(0xFF34D399);
        label = 'Series';
        break;
      case 'tv':
      case 'channel':
        color = Colors.pink;
        label = 'TV';
        break;
      case 'anime':
        color = Colors.deepPurple;
        label = 'Anime';
        break;
      default:
        color = Colors.teal;
        label = type;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  IconData _getTypeIcon(String type) {
    switch (type.toLowerCase()) {
      case 'movie':
        return Icons.movie_rounded;
      case 'series':
        return Icons.tv_rounded;
      case 'tv':
      case 'channel':
        return Icons.live_tv_rounded;
      case 'anime':
        return Icons.animation_rounded;
      default:
        return Icons.folder_rounded;
    }
  }
}

// ─── Shared helpers ─────────────────────────────────────────────────────────

const _surfaceDark = Color(0xFF06080F);
const _placeholderGradient = BoxDecoration(
  gradient: LinearGradient(colors: [Color(0xFF1A1A2E), _surfaceDark]),
);

Widget _buildBackdropImage(String? imageUrl) {
  if (imageUrl == null || imageUrl.isEmpty) {
    return Container(decoration: _placeholderGradient);
  }
  return CachedNetworkImage(
    imageUrl: imageUrl,
    memCacheWidth: 600,
    fit: BoxFit.cover,
    placeholder: (_, __) => Container(decoration: _placeholderGradient),
    errorWidget: (_, __, ___) => Container(decoration: _placeholderGradient),
  );
}

// ─── Episode card for catalog browser ───────────────────────────────────────

const _accentPurple = Color(0xFF8B5CF6);
const _accentRed = Color(0xFFED1C24);

class _CatalogEpisodeCard extends StatefulWidget {
  final TraktEpisode episode;
  final String? showPosterUrl;
  final FocusNode? focusNode;
  final VoidCallback onBrowse;
  final VoidCallback onQuickPlay;
  final bool showQuickPlay;
  final double? watchProgress;
  final KeyEventResult Function(KeyEvent) onKeyEvent;

  const _CatalogEpisodeCard({
    required this.episode,
    this.showPosterUrl,
    this.focusNode,
    required this.onBrowse,
    required this.onQuickPlay,
    this.showQuickPlay = true,
    this.watchProgress,
    required this.onKeyEvent,
  });

  @override
  State<_CatalogEpisodeCard> createState() => _CatalogEpisodeCardState();
}

class _CatalogEpisodeCardState extends State<_CatalogEpisodeCard> {
  bool _isFocused = false;
  int _focusedButtonIndex = 0;

  int get _buttonCount => widget.showQuickPlay ? 2 : 1;
  int? get _quickPlayIndex => widget.showQuickPlay ? 1 : null;

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      if (_focusedButtonIndex > 0) {
        setState(() => _focusedButtonIndex--);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      if (_focusedButtonIndex < _buttonCount - 1) {
        setState(() => _focusedButtonIndex++);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    if (event.logicalKey == LogicalKeyboardKey.select ||
        event.logicalKey == LogicalKeyboardKey.enter) {
      if (_focusedButtonIndex == 0) {
        widget.onBrowse();
      } else if (_focusedButtonIndex == _quickPlayIndex) {
        widget.onQuickPlay();
      }
      return KeyEventResult.handled;
    }

    return widget.onKeyEvent(event);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Focus(
      focusNode: widget.focusNode,
      onFocusChange: (focused) {
        setState(() {
          _isFocused = focused;
          _focusedButtonIndex = 0;
        });
        if (focused) {
          Scrollable.ensureVisible(
            context,
            alignment: 0.5,
            duration: const Duration(milliseconds: 200),
          );
        }
      },
      onKeyEvent: _handleKeyEvent,
      child: GestureDetector(
        onTap: widget.onBrowse,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _isFocused
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.white.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _isFocused
                  ? Colors.white.withValues(alpha: 0.3)
                  : Colors.white.withValues(alpha: 0.06),
              width: _isFocused ? 1.5 : 1,
            ),
            boxShadow: _isFocused
                ? [
                    BoxShadow(
                      color: Colors.white.withValues(alpha: 0.08),
                      blurRadius: 16,
                      spreadRadius: 0,
                    ),
                  ]
                : null,
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              return constraints.maxWidth < 500
                  ? _buildVerticalLayout(theme)
                  : _buildHorizontalLayout(theme);
            },
          ),
        ),
      ),
    );
  }

  Widget _buildHorizontalLayout(ThemeData theme) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Episode thumbnail with progress bar
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 155,
            height: 88,
            child: Stack(
              fit: StackFit.expand,
              children: [
                _buildBackdropImage(
                  widget.episode.thumbnailUrl ?? widget.showPosterUrl,
                ),
                if (widget.watchProgress != null && widget.watchProgress! > 0)
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: (widget.watchProgress! / 100).clamp(
                          0.0,
                          1.0,
                        ),
                        child: Container(
                          height: 3,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                _accentRed,
                                _accentRed.withValues(alpha: 0.7),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 14),
        // Episode details
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.episode.displayTitle,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              _buildMetadataRow(),
              if (widget.episode.overview != null &&
                  widget.episode.overview!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  widget.episode.overview!,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.45),
                    fontSize: 11,
                    height: 1.4,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 8),
        _buildActionButton(
          icon: Icons.list_rounded,
          label: 'Sources',
          color: _accentPurple,
          isHighlighted: _isFocused && _focusedButtonIndex == 0,
          onTap: widget.onBrowse,
        ),
        if (widget.showQuickPlay) ...[
          const SizedBox(width: 6),
          _buildActionButton(
            icon: Icons.play_arrow_rounded,
            label: 'Play',
            color: _accentRed,
            isHighlighted: _isFocused && _focusedButtonIndex == _quickPlayIndex,
            onTap: widget.onQuickPlay,
          ),
        ],
      ],
    );
  }

  Widget _buildVerticalLayout(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 120,
                height: 68,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _buildBackdropImage(
                      widget.episode.thumbnailUrl ?? widget.showPosterUrl,
                    ),
                    if (widget.watchProgress != null &&
                        widget.watchProgress! > 0)
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: FractionallySizedBox(
                            widthFactor: (widget.watchProgress! / 100).clamp(
                              0.0,
                              1.0,
                            ),
                            child: Container(
                              height: 3,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    _accentRed,
                                    _accentRed.withValues(alpha: 0.7),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.episode.displayTitle,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  _buildMetadataRow(),
                ],
              ),
            ),
          ],
        ),
        if (widget.episode.overview != null &&
            widget.episode.overview!.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            widget.episode.overview!,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.45),
              fontSize: 11,
              height: 1.4,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _buildActionButton(
                icon: Icons.list_rounded,
                label: 'Sources',
                color: _accentPurple,
                isHighlighted: _isFocused && _focusedButtonIndex == 0,
                onTap: widget.onBrowse,
              ),
            ),
            if (widget.showQuickPlay) ...[
              const SizedBox(width: 8),
              Expanded(
                child: _buildActionButton(
                  icon: Icons.play_arrow_rounded,
                  label: 'Play',
                  color: _accentRed,
                  isHighlighted:
                      _isFocused && _focusedButtonIndex == _quickPlayIndex,
                  onTap: widget.onQuickPlay,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildMetadataRow() {
    final ep = widget.episode;
    final progress = widget.watchProgress;
    final seasonLabel = ep.season.toString().padLeft(2, '0');
    final epLabel = ep.number.toString().padLeft(2, '0');

    return Wrap(
      spacing: 6,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: const Color(0xFF34D399).withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            'S${seasonLabel}E$epLabel',
            style: const TextStyle(
              color: Color(0xFF34D399),
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (ep.formattedAirDate != null)
          Text(
            ep.formattedAirDate!,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 11,
            ),
          ),
        if (ep.runtime != null)
          Text(
            '${ep.runtime} min',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 11,
            ),
          ),
        if (ep.rating != null)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.star_rounded,
                size: 13,
                color: Color(0xFFFBBF24),
              ),
              const SizedBox(width: 2),
              Text(
                ep.rating!.toStringAsFixed(1),
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        if (progress != null && progress > 0)
          Text(
            progress >= 100.0 ? 'Watched' : '${progress.round()}%',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.45),
              fontSize: 11,
            ),
          ),
      ],
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required bool isHighlighted,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedScale(
        scale: isHighlighted ? 1.08 : 1.0,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isHighlighted ? color : Colors.black.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isHighlighted ? color : color.withValues(alpha: 0.6),
              width: 1,
            ),
            boxShadow: isHighlighted
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.4),
                      blurRadius: 12,
                      spreadRadius: 0,
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 15,
                color: isHighlighted
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.9),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    color: isHighlighted
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.9),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
            ],
          ),
        ),
      ),
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
        if (event.logicalKey == LogicalKeyboardKey.select ||
            event.logicalKey == LogicalKeyboardKey.enter) {
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
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: widget.hasBoundSource
                ? const Color(0xFF60A5FA).withValues(alpha: 0.15)
                : Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _isFocused
                  ? const Color(0xFF60A5FA)
                  : widget.hasBoundSource
                  ? const Color(0xFF60A5FA).withValues(alpha: 0.4)
                  : Colors.white.withValues(alpha: 0.15),
              width: _isFocused ? 2 : 1,
            ),
            boxShadow: _isFocused
                ? [
                    BoxShadow(
                      color: const Color(0xFF60A5FA).withValues(alpha: 0.3),
                      blurRadius: 8,
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
                    ? const Color(0xFF60A5FA)
                    : Colors.white.withValues(alpha: 0.6),
              ),
              const SizedBox(width: 4),
              Text(
                widget.hasBoundSource
                    ? (widget.sourceCount > 1
                          ? 'Sources (${widget.sourceCount})'
                          : 'Source')
                    : 'Select Source',
                style: TextStyle(
                  color: widget.hasBoundSource
                      ? const Color(0xFF60A5FA)
                      : Colors.white.withValues(alpha: 0.6),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
