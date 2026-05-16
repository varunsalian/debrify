import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/stremio_addon.dart';
import '../models/advanced_search_selection.dart';
import '../services/main_page_bridge.dart';
import '../services/stremio_service.dart';
import '../services/trakt/trakt_service.dart';
import '../services/trakt/trakt_episode_model.dart';
import '../services/local_bound_source_service.dart';
import '../services/series_source_service.dart';
import '../services/storage_service.dart';
import '../screens/debrid_downloads_screen.dart';
import '../screens/torbox/torbox_downloads_screen.dart';
import '../screens/debrify_tv/widgets/tv_focus_scroll_wrapper.dart';
import '../screens/stremio_tv/widgets/stremio_tv_catalog_picker_dialog.dart';
import 'add_source_picker_dialog.dart';
import 'catalog_item_tile.dart';
import 'episode_tile.dart';
import 'home/home_theme.dart';
import 'trakt/trakt_menu_helpers.dart';
import '../screens/catalog_item_detail_screen.dart';

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

  /// Callback when user selects "Keyword Search" from the add-source picker
  final void Function(StremioMeta show)? onKeywordSelectSource;

  /// Callback when user selects "Play Random Episode" for a series
  final Future<void> Function(StremioMeta show, StremioAddon? addon)?
  onPlayRandomEpisode;

  /// Callback when user selects "Search Season Packs" for a series
  final void Function(StremioMeta show)? onSearchPacks;

  /// Callback when user exits episode drill-down mode (back button)
  final VoidCallback? onEpisodeModeExited;

  /// Callback when user enters episode drill-down (opens a series).
  final VoidCallback? onEpisodeModeEntered;

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
    this.onKeywordSelectSource,
    this.onPlayRandomEpisode,
    this.onSearchPacks,
    this.onEpisodeModeExited,
    this.onEpisodeModeEntered,
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
    _refreshTraktAuthState();
    MainPageBridge.addIntegrationListener(_handleIntegrationChanged);
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

  Future<void> _refreshTraktAuthState() async {
    final auth = await TraktService.instance.isAuthenticated();
    if (!mounted) return;
    setState(() => _isTraktAuthenticated = auth);
  }

  void _handleIntegrationChanged() {
    _refreshTraktAuthState();
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
    MainPageBridge.removeIntegrationListener(_handleIntegrationChanged);
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

    final isMovie = item.type == 'movie';
    final supportsLocal = isMovie || item.type == 'series';
    if (!rdEnabled && !torboxEnabled && !supportsLocal) {
      widget.onSelectSource?.call(item);
      return;
    }

    await showAddSourcePickerDialog(
      context,
      onTorrentSearch: () => widget.onSelectSource?.call(item),
      onKeywordSearch: widget.onKeywordSelectSource != null
          ? () => widget.onKeywordSelectSource!.call(item)
          : null,
      onLocal: supportsLocal && !LocalBoundSourceService.isLocalBindingDisabled
          ? () => _pickAndSaveLocalSource(item, imdbId)
          : null,
      localDisabledReason: supportsLocal
          ? LocalBoundSourceService.localDisabledReason
          : null,
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

  Future<void> _pickAndSaveLocalSource(StremioMeta item, String imdbId) async {
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
    final updated = await SeriesSourceService.getSources(imdbId);
    if (!mounted) return;
    setState(() => _boundSources[imdbId] = updated);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Local source set: ${source.torrentName}'),
        backgroundColor: const Color(0xFF10B981),
      ),
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
                                _showAddSourcePicker(show, imdbId);
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
    // Hide the host bar as soon as the loading state is shown. Every
    // terminal failure path below restores it (via onEpisodeModeExited or
    // _fallbackToDirectSearch) so a failed entry can't leave it hidden.
    widget.onEpisodeModeEntered?.call();

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
        widget.onEpisodeModeExited?.call();
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

      // Resolve where to land. Explicit initialSeason/initialEpisode (deep
      // links, calendar) win; otherwise fall back to this show's last-played
      // episode. Catalog has no Trakt-style next-episode service, so without
      // this it always opens at S01E01. Mirrors _onQuickPlay's lookup.
      int? effectiveSeason = initialSeason;
      int? effectiveEpisode = initialEpisode;
      if (effectiveSeason == null || effectiveEpisode == null) {
        final imdbId = show.effectiveImdbId;
        if (imdbId != null) {
          final lastPlayed = await StorageService.getLastPlayedEpisodeByImdbId(
            imdbId,
          );
          if (!mounted || generation != _episodeModeGeneration) return;
          if (lastPlayed != null) {
            effectiveSeason ??= lastPlayed['season'] as int?;
            effectiveEpisode ??= lastPlayed['episode'] as int?;
          }
        }
        if (effectiveSeason == null || effectiveEpisode == null) {
          final byTitle = await StorageService.getLastPlayedEpisode(
            seriesTitle: show.name,
          );
          if (!mounted || generation != _episodeModeGeneration) return;
          if (byTitle != null) {
            effectiveSeason ??= byTitle['season'] as int?;
            effectiveEpisode ??= byTitle['episode'] as int?;
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
      debugPrint('CatalogBrowser: Episode fetch failed: $e');
      _fallbackToDirectSearch(show);
    }
  }

  /// Robustly brings episode [epIndex] into view and focuses it.
  ///
  /// The episode list is a lazy ListView with variable-height tiles, so a
  /// single fixed/proportional jump is unreliable — an off-screen target
  /// tile isn't built, leaving its FocusNode contextless. This re-reads
  /// scroll metrics each frame and converges (the builder's maxScrollExtent
  /// grows as more rows lay out), then once the tile exists just focuses it
  /// — EpisodeTile.onFocusChange centers it precisely. Bounded so it can
  /// never spin.
  void _scrollFocusEpisode(int epIndex, int episodeCount, int generation) {
    const int maxAttempts = 16;
    void attempt(int n) {
      if (!mounted || generation != _episodeModeGeneration) return;
      if (epIndex < 0 || epIndex >= _episodeFocusNodes.length) return;
      final node = _episodeFocusNodes[epIndex];
      if (node.context != null) {
        node.requestFocus();
        return;
      }
      if (n >= maxAttempts || !_episodeScrollController.hasClients) {
        node.requestFocus(); // best effort, then stop
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
              onPlay: () => _onEpisodeQuickPlay(episode),
              onSources: () => _onEpisodeTap(episode),
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

    return _buildContentGrid();
  }

  Widget _buildContentGrid() {
    final w = MediaQuery.of(context).size.width;
    final crossAxisCount =
        catalogGridColumnsFor(w, isTelevision: widget.isTelevision);
    final hPadding = w >= 900 ? 40.0 : 20.0;

    return GridView.builder(
      controller: _scrollController,
      padding: EdgeInsets.fromLTRB(hPadding, 16, hPadding, 40),
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        // Pure poster aspect (2:3) — title appears inside the poster on focus.
        childAspectRatio: 0.667,
        mainAxisSpacing: 24,
        crossAxisSpacing: 18,
      ),
      itemCount: _content.length + (_hasMoreContent ? crossAxisCount : 0),
      itemBuilder: (context, index) {
        if (index >= _content.length) {
          return const Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }

        final item = _content[index];
        return CatalogItemTile(
          item: item,
          isTelevision: widget.isTelevision,
          focusNode: index < _contentFocusNodes.length
              ? _contentFocusNodes[index]
              : null,
          hasBoundSource: _boundSources.containsKey(
            item.effectiveImdbId ?? item.id,
          ),
          onOpen: () => _openItemDetail(item),
        );
      },
    );
  }

  Future<void> _openItemDetail(StremioMeta item) async {
    final hasTrakt =
        item.hasValidImdbId ||
        (item.hasValidId &&
            (item.type == 'movie' || item.type == 'series'));
    final hasBoundSource =
        _boundSources.containsKey(item.effectiveImdbId ?? item.id);

    final traktItems = hasTrakt
        ? buildTraktAddOnlyMenuOptions(
            isSeries: item.type == 'series',
            isMovie: item.type == 'movie',
            hasBoundSource: hasBoundSource,
            isTraktAuthenticated: _isTraktAuthenticated,
          )
        : const <TraktMenuOption>[];

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CatalogItemDetailScreen(
          item: item,
          isTelevision: widget.isTelevision,
          showQuickPlay: widget.showQuickPlay,
          hasBoundSource: hasBoundSource,
          traktMenuOptions: traktItems,
          onTraktAction: (action) {
            // searchPacks/selectSource/stremioTv/random replace or leave
            // the host screen; the detail screen is pushed on top, so
            // close it first or the result happens invisibly behind it.
            const leaves = {
              TraktItemMenuAction.searchPacks,
              TraktItemMenuAction.selectSource,
              TraktItemMenuAction.addToStremioTv,
              TraktItemMenuAction.playRandomEpisode,
            };
            if (leaves.contains(action) &&
                Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            }
            handleTraktMenuAction(
              context,
              item,
              action,
              onSelectSource: widget.onSelectSource,
              onEditSource: _handleSelectSourceAction,
              onPlayRandomEpisode: (show) async {
                await widget.onPlayRandomEpisode?.call(show, _selectedAddon);
              },
              onSearchPacks: widget.onSearchPacks,
              onAddToStremioTv: _handleAddToStremioTv,
            );
          },
          onPlay: () => _onQuickPlay(item),
          onBrowse: () => _onItemTap(item),
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
