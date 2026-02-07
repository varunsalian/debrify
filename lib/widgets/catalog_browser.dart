import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../models/stremio_addon.dart';
import '../models/advanced_search_selection.dart';
import '../services/stremio_service.dart';

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

  const CatalogBrowser({
    super.key,
    this.onItemSelected,
    this.onQuickPlay,
    this.showQuickPlay = true,
    this.filterAddon,
    this.searchQuery,
    this.onRequestFocusAbove,
    this.defaultCatalogId,
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
  final FocusNode _providerDropdownFocusNode = FocusNode(debugLabel: 'provider_dropdown');
  final FocusNode _catalogDropdownFocusNode = FocusNode(debugLabel: 'catalog_dropdown');
  final FocusNode _genreDropdownFocusNode = FocusNode(debugLabel: 'genre_dropdown');
  List<FocusNode> _contentFocusNodes = [];
  int _focusedContentIndex = -1; // Track last focused content item for sidebar navigation

  // Focus state trackers for visual indicators
  final ValueNotifier<bool> _providerDropdownFocused = ValueNotifier(false);
  final ValueNotifier<bool> _catalogDropdownFocused = ValueNotifier(false);
  final ValueNotifier<bool> _genreDropdownFocused = ValueNotifier(false);

  /// Public method to request focus on the first dropdown (provider dropdown)
  /// Called from parent when navigating down from Sources
  void requestFocusOnFirstDropdown() {
    _providerDropdownFocusNode.requestFocus();
  }

  /// Public method to request focus on the last focused content item
  /// Called from parent when returning from sidebar navigation
  /// Returns true if focus was restored to a content item, false otherwise
  bool requestFocusOnLastItem() {
    if (_focusedContentIndex >= 0 && _focusedContentIndex < _contentFocusNodes.length) {
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

  /// Check if content list has any items that can receive focus
  bool get hasContentItems => _contentFocusNodes.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _loadAddons();
    _scrollController.addListener(_onScroll);
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
  }

  KeyEventResult _handleProviderDropdownKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    // Up arrow: navigate to Sources above
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      widget.onRequestFocusAbove?.call();
      return KeyEventResult.handled;
    }
    // Down arrow: navigate to first content item
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (_contentFocusNodes.isNotEmpty) {
        _contentFocusNodes[0].requestFocus();
      }
      return KeyEventResult.handled;
    }
    // Right arrow: navigate to catalog dropdown
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      _catalogDropdownFocusNode.requestFocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _handleCatalogDropdownKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    // Up arrow: navigate to Sources above
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      widget.onRequestFocusAbove?.call();
      return KeyEventResult.handled;
    }
    // Left arrow: navigate to provider dropdown
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _providerDropdownFocusNode.requestFocus();
      return KeyEventResult.handled;
    }
    // Down arrow: navigate to first content item
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (_contentFocusNodes.isNotEmpty) {
        _contentFocusNodes[0].requestFocus();
      }
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
    // Down arrow: navigate to first content item
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (_contentFocusNodes.isNotEmpty) {
        _contentFocusNodes[0].requestFocus();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  void didUpdateWidget(CatalogBrowser oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Handle filterAddon changes (user switched addon in dropdown)
    if (widget.filterAddon != oldWidget.filterAddon) {
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
    _providerDropdownFocusNode.dispose();
    _catalogDropdownFocusNode.dispose();
    _genreDropdownFocusNode.dispose();
    _providerDropdownFocused.dispose();
    _catalogDropdownFocused.dispose();
    _genreDropdownFocused.dispose();
    for (final node in _contentFocusNodes) {
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
              _selectedCatalog = defaultCatalog ?? _selectedAddon!.catalogs.first;
              _loadContent();
            }
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
    if (_isLoadingContent || !_hasMoreContent || _selectedAddon == null || _selectedCatalog == null) return;
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
      final results = await _stremioService.searchAddonCatalogs(_selectedAddon!, query);

      if (mounted) {
        setState(() {
          _content = results;
          _isLoadingContent = false;
          _refreshContentFocusNodes();
        });
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
      _selectedCatalog = addon.catalogs.isNotEmpty ? addon.catalogs.first : null;
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

    final selection = AdvancedSearchSelection(
      imdbId: item.id,
      isSeries: item.type == 'series',
      title: item.name,
      year: item.year,
      contentType: item.type,
      posterUrl: item.poster,
    );

    widget.onItemSelected!(selection);
  }

  void _onQuickPlay(StremioMeta item) {
    final selection = AdvancedSearchSelection(
      imdbId: item.id,
      isSeries: item.type == 'series',
      title: item.name,
      year: item.year,
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

  KeyEventResult _handleContentItemKey(int index, KeyEvent event, {bool? isQuickPlayFocused}) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    // List navigation (up/down only)
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (index == 0) {
        // Move to provider dropdown (first dropdown in the row)
        _providerDropdownFocusNode.requestFocus();
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
      return const Center(
        child: CircularProgressIndicator(),
      );
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

    return Column(
      children: [
        // Filters row
        _buildFiltersRow(),
        const SizedBox(height: 12),
        // Content list
        Expanded(
          child: _buildContentList(),
        ),
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
                // Provider dropdown - full width
                _buildProviderDropdown(),
                const SizedBox(height: 8),
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
              // Provider dropdown
              Expanded(
                child: _buildProviderDropdown(),
              ),
              const SizedBox(width: 12),
              // Catalog dropdown
              Expanded(
                child: _buildCatalogDropdown(),
              ),
              // Genre dropdown (if supported)
              if (_selectedCatalog?.supportsGenre ?? false) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: _buildGenreDropdown(),
                ),
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
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                ),
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
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                ),
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
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                ),
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

  Widget _buildContentList() {
    if (_isLoadingContent && _content.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(),
      );
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
            focusNode: index < _contentFocusNodes.length
                ? _contentFocusNodes[index]
                : null,
            onQuickPlay: () => _onQuickPlay(item),
            onSources: () => _onItemTap(item),
            onKeyEvent: (event, {bool? isQuickPlayFocused}) =>
                _handleContentItemKey(index, event, isQuickPlayFocused: isQuickPlayFocused),
            showQuickPlay: widget.showQuickPlay,
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
  final KeyEventResult Function(KeyEvent, {bool? isQuickPlayFocused}) onKeyEvent;
  final bool showQuickPlay;

  const _CatalogItemCard({
    required this.item,
    this.focusNode,
    required this.onQuickPlay,
    required this.onSources,
    required this.onKeyEvent,
    this.showQuickPlay = true,
  });

  @override
  State<_CatalogItemCard> createState() => _CatalogItemCardState();
}

class _CatalogItemCardState extends State<_CatalogItemCard> {
  bool _isFocused = false;
  // For DPAD: track which button is focused (true = Quick Play, false = Browse)
  bool _isQuickPlayButtonFocused = false;

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    // Left/Right arrow navigation between buttons
    // Order: [Browse] [Quick Play]
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      if (_isQuickPlayButtonFocused) {
        setState(() => _isQuickPlayButtonFocused = false);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      if (!_isQuickPlayButtonFocused && widget.showQuickPlay) {
        setState(() => _isQuickPlayButtonFocused = true);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    // Select/Enter triggers the focused button
    if (event.logicalKey == LogicalKeyboardKey.select ||
        event.logicalKey == LogicalKeyboardKey.enter) {
      if (_isQuickPlayButtonFocused) {
        widget.onQuickPlay();
      } else {
        widget.onSources();
      }
      return KeyEventResult.handled;
    }

    // Pass other key events (up/down navigation) to parent
    return widget.onKeyEvent(event, isQuickPlayFocused: _isQuickPlayButtonFocused);
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
          if (focused || !widget.showQuickPlay) {
            _isQuickPlayButtonFocused = false;
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
      child: Material(
        color: Colors.transparent,
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Use vertical layout on narrow screens (< 500px)
            final useVerticalLayout = constraints.maxWidth < 500;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withOpacity(0.5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _isFocused
                      ? colorScheme.primary
                      : colorScheme.outline.withOpacity(0.2),
                  width: _isFocused ? 2 : 1,
                ),
              ),
              child: useVerticalLayout
                  ? _buildVerticalLayout(theme, colorScheme)
                  : _buildHorizontalLayout(theme, colorScheme),
            );
          },
        ),
      ),
    );
  }

  /// Horizontal layout for wide screens - thumbnail, details, and buttons in a row
  Widget _buildHorizontalLayout(ThemeData theme, ColorScheme colorScheme) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Thumbnail
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 80,
            height: 120,
            child: _buildPoster(colorScheme),
          ),
        ),
        const SizedBox(width: 14),
        // Details
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Title
              Text(
                widget.item.name,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              // Metadata row
              _buildMetadataRow(theme, colorScheme),
              // Genres
              if (widget.item.genres != null && widget.item.genres!.isNotEmpty) ...[
                const SizedBox(height: 6),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: widget.item.genres!.take(3).map((genre) {
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.12),
                        ),
                      ),
                      child: Text(
                        genre,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
              // Description
              if (widget.item.description != null && widget.item.description!.isNotEmpty &&
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
        // Action buttons
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildActionButton(
              icon: Icons.list_rounded,
              label: 'Browse',
              color: const Color(0xFF6366F1),
              isHighlighted: _isFocused && !_isQuickPlayButtonFocused,
              onTap: widget.onSources,
            ),
            const SizedBox(width: 6),
            if (widget.showQuickPlay)
              _buildActionButton(
                icon: Icons.play_arrow_rounded,
                label: 'Quick Play',
                color: const Color(0xFFB91C1C),
                isHighlighted: _isFocused && _isQuickPlayButtonFocused,
                onTap: widget.onQuickPlay,
              ),
          ],
        ),
      ],
    );
  }

  /// Vertical layout for narrow screens - content stacked with buttons below
  Widget _buildVerticalLayout(ThemeData theme, ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Top row: Thumbnail + Details
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Thumbnail
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 60,
                height: 85,
                child: _buildPoster(colorScheme),
              ),
            ),
            const SizedBox(width: 12),
            // Details - takes remaining space
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Title - full width available
                  Text(
                    widget.item.name,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  // Metadata row
                  _buildMetadataRow(theme, colorScheme),
                  // Genres
                  if (widget.item.genres != null && widget.item.genres!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      widget.item.genres!.join(', '),
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 11,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        // Bottom row: Action buttons
        Row(
          children: [
            Expanded(
              child: _buildActionButton(
                icon: Icons.list_rounded,
                label: 'Browse',
                color: const Color(0xFF6366F1),
                isHighlighted: _isFocused && !_isQuickPlayButtonFocused,
                onTap: widget.onSources,
              ),
            ),
            if (widget.showQuickPlay) ...[
              const SizedBox(width: 8),
              Expanded(
                child: _buildActionButton(
                  icon: Icons.play_arrow_rounded,
                  label: 'Quick Play',
                  color: const Color(0xFFB91C1C),
                  isHighlighted: _isFocused && _isQuickPlayButtonFocused,
                  onTap: widget.onQuickPlay,
                ),
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
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        if (widget.item.imdbRating != null) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.star, size: 12, color: Colors.amber),
                const SizedBox(width: 3),
                Text(
                  widget.item.imdbRating!.toStringAsFixed(1),
                  style: const TextStyle(
                    color: Colors.amber,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
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
    // Darker shade for gradient effect
    final darkColor = Color.lerp(color, Colors.black, 0.3)!;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          // Solid gradient background - always visible
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isHighlighted
                ? [color, darkColor]
                : [color.withValues(alpha: 0.85), darkColor.withValues(alpha: 0.85)],
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isHighlighted
                ? Colors.white.withValues(alpha: 0.4)
                : Colors.white.withValues(alpha: 0.15),
            width: isHighlighted ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: isHighlighted ? 0.6 : 0.3),
              blurRadius: isHighlighted ? 16 : 8,
              spreadRadius: isHighlighted ? 2 : 0,
              offset: const Offset(0, 4),
            ),
            if (isHighlighted)
              BoxShadow(
                color: color.withValues(alpha: 0.3),
                blurRadius: 24,
                spreadRadius: 4,
              ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: Colors.white,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPoster(ColorScheme colorScheme) {
    if (widget.item.poster != null && widget.item.poster!.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: widget.item.poster!,
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
          color: colorScheme.onSurfaceVariant.withOpacity(0.5),
        ),
      ),
    );
  }

  Widget _buildTypeBadge(String type) {
    Color color;
    String label;

    switch (type.toLowerCase()) {
      case 'movie':
        color = Colors.blue;
        label = 'Movie';
        break;
      case 'series':
        color = Colors.purple;
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
        color: color.withOpacity(0.15),
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

