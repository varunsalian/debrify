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
class CatalogBrowser extends StatefulWidget {
  /// Callback when user selects an item to search streams for
  final void Function(AdvancedSearchSelection selection)? onItemSelected;

  const CatalogBrowser({super.key, this.onItemSelected});

  @override
  State<CatalogBrowser> createState() => _CatalogBrowserState();
}

class _CatalogBrowserState extends State<CatalogBrowser> {
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

  // Scroll controller for pagination
  final ScrollController _scrollController = ScrollController();

  // Focus nodes for TV/DPAD navigation
  final FocusNode _providerDropdownFocusNode = FocusNode(debugLabel: 'provider_dropdown');
  final FocusNode _catalogDropdownFocusNode = FocusNode(debugLabel: 'catalog_dropdown');
  final FocusNode _genreDropdownFocusNode = FocusNode(debugLabel: 'genre_dropdown');
  List<FocusNode> _contentFocusNodes = [];

  @override
  void initState() {
    super.initState();
    _loadAddons();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _providerDropdownFocusNode.dispose();
    _catalogDropdownFocusNode.dispose();
    _genreDropdownFocusNode.dispose();
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
      final catalogAddons = await _stremioService.getCatalogAddons();
      if (mounted) {
        setState(() {
          _addons = catalogAddons;
          _isLoadingAddons = false;
          // Auto-select first addon if available
          if (_addons.isNotEmpty && _selectedAddon == null) {
            _selectedAddon = _addons.first;
            // Auto-select first catalog of first addon
            if (_selectedAddon!.catalogs.isNotEmpty) {
              _selectedCatalog = _selectedAddon!.catalogs.first;
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

  void _refreshContentFocusNodes() {
    // Only add new focus nodes for new items (don't dispose existing ones during pagination)
    final currentCount = _contentFocusNodes.length;
    final neededCount = _content.length;

    if (neededCount > currentCount) {
      // Add focus nodes for new items only
      for (int i = currentCount; i < neededCount; i++) {
        _contentFocusNodes.add(FocusNode(debugLabel: 'content_item_$i'));
      }
    } else if (neededCount < currentCount) {
      // Content was reset (new catalog/filter) - dispose extra nodes and trim list
      for (int i = neededCount; i < currentCount; i++) {
        _contentFocusNodes[i].dispose();
      }
      _contentFocusNodes = _contentFocusNodes.sublist(0, neededCount);
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
    );

    widget.onItemSelected!(selection);
  }

  // Current column count based on screen width (updated by LayoutBuilder)
  int _currentColumns = 3;

  KeyEventResult _handleContentItemKey(int index, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final columns = _currentColumns;

    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (index < columns) {
        // Move to genre dropdown or catalog dropdown
        if (_selectedCatalog?.supportsGenre ?? false) {
          FocusScope.of(context).requestFocus(_genreDropdownFocusNode);
        } else {
          FocusScope.of(context).requestFocus(_catalogDropdownFocusNode);
        }
        return KeyEventResult.handled;
      }
      final targetIndex = index - columns;
      if (targetIndex >= 0 && targetIndex < _contentFocusNodes.length) {
        FocusScope.of(context).requestFocus(_contentFocusNodes[targetIndex]);
        return KeyEventResult.handled;
      }
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      final targetIndex = index + columns;
      if (targetIndex < _contentFocusNodes.length) {
        FocusScope.of(context).requestFocus(_contentFocusNodes[targetIndex]);
        return KeyEventResult.handled;
      }
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      if (index % columns > 0) {
        FocusScope.of(context).requestFocus(_contentFocusNodes[index - 1]);
        return KeyEventResult.handled;
      }
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      if (index % columns < columns - 1 && index + 1 < _contentFocusNodes.length) {
        FocusScope.of(context).requestFocus(_contentFocusNodes[index + 1]);
        return KeyEventResult.handled;
      }
    }

    if (event.logicalKey == LogicalKeyboardKey.select ||
        event.logicalKey == LogicalKeyboardKey.enter) {
      _onItemTap(_content[index]);
      return KeyEventResult.handled;
    }

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
        // Content grid
        Expanded(
          child: _buildContentGrid(),
        ),
      ],
    );
  }

  Widget _buildFiltersRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
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
      ),
    );
  }

  Widget _buildProviderDropdown() {
    return Focus(
      focusNode: _providerDropdownFocusNode,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.1),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<StremioAddon>(
            value: _selectedAddon,
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
      ),
    );
  }

  Widget _buildCatalogDropdown() {
    final catalogs = _selectedAddon?.catalogs ?? [];

    return Focus(
      focusNode: _catalogDropdownFocusNode,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.1),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<StremioAddonCatalog>(
            value: _selectedCatalog,
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
                        catalog.name,
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
      ),
    );
  }

  Widget _buildGenreDropdown() {
    final genreOptions = _selectedCatalog?.genreOptions ?? [];
    if (genreOptions.isEmpty) return const SizedBox.shrink();

    return Focus(
      focusNode: _genreDropdownFocusNode,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.1),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String?>(
            value: _selectedGenre,
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
      ),
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

  Widget _buildContentGrid() {
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

    return LayoutBuilder(
      builder: (context, constraints) {
        // Responsive columns: more columns on wider screens
        final width = constraints.maxWidth;
        final crossAxisCount = width > 900 ? 6 : width > 600 ? 4 : 3;

        // Update column count for DPAD navigation
        _currentColumns = crossAxisCount;

        return GridView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.all(12),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            childAspectRatio: 0.7,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
          ),
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
        return _CatalogItemCard(
          item: item,
          focusNode: index < _contentFocusNodes.length
              ? _contentFocusNodes[index]
              : null,
          onTap: () => _onItemTap(item),
          onKeyEvent: (event) => _handleContentItemKey(index, event),
        );
      },
        );
      },
    );
  }
}

/// A card widget for displaying a catalog item (movie/series/channel)
class _CatalogItemCard extends StatefulWidget {
  final StremioMeta item;
  final FocusNode? focusNode;
  final VoidCallback onTap;
  final KeyEventResult Function(KeyEvent) onKeyEvent;

  const _CatalogItemCard({
    required this.item,
    this.focusNode,
    required this.onTap,
    required this.onKeyEvent,
  });

  @override
  State<_CatalogItemCard> createState() => _CatalogItemCardState();
}

class _CatalogItemCardState extends State<_CatalogItemCard> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode,
      onFocusChange: (focused) {
        setState(() => _isFocused = focused);
        if (focused) {
          Scrollable.ensureVisible(
            context,
            alignment: 0.5,
            duration: const Duration(milliseconds: 200),
          );
        }
      },
      onKeyEvent: (node, event) => widget.onKeyEvent(event),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _isFocused
                  ? Colors.white.withValues(alpha: 0.8)
                  : Colors.transparent,
              width: 2,
            ),
            boxShadow: _isFocused
                ? [
                    BoxShadow(
                      color: Colors.white.withValues(alpha: 0.2),
                      blurRadius: 12,
                      spreadRadius: 2,
                    ),
                  ]
                : null,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Poster image
                if (widget.item.poster != null)
                  CachedNetworkImage(
                    imageUrl: widget.item.poster!,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => Container(
                      color: Colors.white.withValues(alpha: 0.05),
                      child: const Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                    errorWidget: (context, url, error) => _buildPlaceholder(),
                  )
                else
                  _buildPlaceholder(),
                // Gradient overlay
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.8),
                        ],
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Type badge
                        _buildTypeBadge(widget.item.type),
                        const SizedBox(height: 4),
                        // Title
                        Text(
                          widget.item.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        // Year/rating
                        if (widget.item.year != null || widget.item.imdbRating != null)
                          Row(
                            children: [
                              if (widget.item.year != null)
                                Text(
                                  widget.item.year!,
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.7),
                                    fontSize: 11,
                                  ),
                                ),
                              if (widget.item.year != null &&
                                  widget.item.imdbRating != null)
                                Text(
                                  ' \u2022 ',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.5),
                                    fontSize: 11,
                                  ),
                                ),
                              if (widget.item.imdbRating != null)
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.star_rounded,
                                      size: 12,
                                      color: Color(0xFFFBBF24),
                                    ),
                                    const SizedBox(width: 2),
                                    Text(
                                      widget.item.imdbRating!.toStringAsFixed(1),
                                      style: TextStyle(
                                        color: Colors.white.withValues(alpha: 0.7),
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      color: Colors.white.withValues(alpha: 0.05),
      child: Center(
        child: Icon(
          _getTypeIcon(widget.item.type),
          size: 32,
          color: Colors.white.withValues(alpha: 0.3),
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
        color = const Color(0xFFF472B6);
        label = 'TV';
        break;
      case 'anime':
        color = const Color(0xFFA78BFA);
        label = 'Anime';
        break;
      default:
        color = const Color(0xFFFBBF24);
        label = type;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: color.withValues(alpha: 0.4),
          width: 1,
        ),
      ),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
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
