import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../models/stremio_addon.dart';
import '../models/advanced_search_selection.dart';
import '../services/stremio_service.dart';

/// Netflix-style homepage grid with horizontal scrolling rows per catalog
///
/// Features:
/// - One row per catalog section
/// - Horizontal scrolling within rows
/// - TV D-pad navigation (up/down between rows, left/right within)
/// - Lazy loading support
class HomepageCatalogGrid extends StatefulWidget {
  /// Callback when user selects an item
  final void Function(AdvancedSearchSelection selection)? onItemSelected;

  /// Whether running on TV (affects layout and focus)
  final bool isTelevision;

  const HomepageCatalogGrid({
    super.key,
    this.onItemSelected,
    this.isTelevision = false,
  });

  @override
  State<HomepageCatalogGrid> createState() => _HomepageCatalogGridState();
}

class _HomepageCatalogGridState extends State<HomepageCatalogGrid> {
  final StremioService _stremioService = StremioService.instance;
  final ScrollController _scrollController = ScrollController();

  List<CatalogSection> _sections = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadContent();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadContent() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final sections = await _stremioService.fetchHomepageContent(
        itemsPerCatalog: 15,
        maxSections: 12,
      );

      if (mounted) {
        setState(() {
          _sections = sections;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load content: $e';
          _isLoading = false;
        });
      }
    }
  }

  void _onItemSelected(StremioMeta item) {
    final selection = AdvancedSearchSelection(
      imdbId: item.id,
      isSeries: item.type == 'series',
      title: item.name,
      year: item.year,
      contentType: item.type,
    );
    widget.onItemSelected?.call(selection);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return _buildLoadingState();
    }

    if (_error != null) {
      return _buildErrorState();
    }

    if (_sections.isEmpty) {
      return _buildEmptyState();
    }

    return RefreshIndicator(
      onRefresh: _loadContent,
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(vertical: 16),
        itemCount: _sections.length,
        itemBuilder: (context, index) {
          return _CatalogRow(
            section: _sections[index],
            isTelevision: widget.isTelevision,
            onItemSelected: _onItemSelected,
            rowIndex: index,
            totalRows: _sections.length,
          );
        },
      ),
    );
  }

  Widget _buildLoadingState() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 16),
      itemCount: 4,
      itemBuilder: (context, index) => _ShimmerRow(),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline,
            size: 48,
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(height: 16),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _loadContent,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.movie_filter_outlined,
            size: 64,
            color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.5),
          ),
          const SizedBox(height: 16),
          Text(
            'No catalog content available',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Add Stremio addons with catalog support in settings',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.7),
            ),
          ),
        ],
      ),
    );
  }
}

/// A single horizontal row for a catalog section
class _CatalogRow extends StatefulWidget {
  final CatalogSection section;
  final bool isTelevision;
  final void Function(StremioMeta item) onItemSelected;
  final int rowIndex;
  final int totalRows;

  const _CatalogRow({
    required this.section,
    required this.isTelevision,
    required this.onItemSelected,
    required this.rowIndex,
    required this.totalRows,
  });

  @override
  State<_CatalogRow> createState() => _CatalogRowState();
}

class _CatalogRowState extends State<_CatalogRow> {
  final ScrollController _scrollController = ScrollController();
  late List<FocusNode> _itemFocusNodes;
  int _focusedIndex = -1;

  @override
  void initState() {
    super.initState();
    _itemFocusNodes = List.generate(
      widget.section.items.length,
      (i) => FocusNode(debugLabel: 'catalog_item_${widget.rowIndex}_$i'),
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    for (final node in _itemFocusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  void _scrollToItem(int index) {
    if (!_scrollController.hasClients) return;

    const double cardWidth = 140;
    const double cardSpacing = 12;
    final targetOffset = index * (cardWidth + cardSpacing);

    _scrollController.animateTo(
      targetOffset.clamp(0, _scrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
    );
  }

  KeyEventResult _handleItemKeyEvent(FocusNode node, KeyEvent event, int index) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    // Select/Enter activates item
    if (event.logicalKey == LogicalKeyboardKey.select ||
        event.logicalKey == LogicalKeyboardKey.enter) {
      widget.onItemSelected(widget.section.items[index]);
      return KeyEventResult.handled;
    }

    // Left arrow: move to previous item
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft && index > 0) {
      _itemFocusNodes[index - 1].requestFocus();
      _scrollToItem(index - 1);
      return KeyEventResult.handled;
    }

    // Right arrow: move to next item
    if (event.logicalKey == LogicalKeyboardKey.arrowRight &&
        index < widget.section.items.length - 1) {
      _itemFocusNodes[index + 1].requestFocus();
      _scrollToItem(index + 1);
      return KeyEventResult.handled;
    }

    // Up/Down arrows are handled by parent for row navigation
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Section header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Icon(
                Icons.extension,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.section.title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${widget.section.items.length}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),

        // Horizontal item list
        SizedBox(
          height: 220, // Card height + padding for scale animation
          child: ListView.builder(
            controller: _scrollController,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            clipBehavior: Clip.none,
            cacheExtent: 400,
            itemCount: widget.section.items.length,
            itemBuilder: (context, index) {
              final item = widget.section.items[index];
              return Padding(
                padding: EdgeInsets.only(
                  right: index < widget.section.items.length - 1 ? 12 : 0,
                ),
                child: _CatalogItemCard(
                  item: item,
                  focusNode: _itemFocusNodes[index],
                  isFocused: _focusedIndex == index,
                  isTelevision: widget.isTelevision,
                  onTap: () => widget.onItemSelected(item),
                  onFocusChange: (focused) {
                    setState(() {
                      _focusedIndex = focused ? index : -1;
                    });
                    if (focused) {
                      _scrollToItem(index);
                    }
                  },
                  onKeyEvent: (node, event) => _handleItemKeyEvent(node, event, index),
                ),
              );
            },
          ),
        ),

        const SizedBox(height: 8),
      ],
    );
  }
}

/// Individual catalog item card
class _CatalogItemCard extends StatelessWidget {
  final StremioMeta item;
  final FocusNode focusNode;
  final bool isFocused;
  final bool isTelevision;
  final VoidCallback onTap;
  final ValueChanged<bool> onFocusChange;
  final KeyEventResult Function(FocusNode, KeyEvent) onKeyEvent;

  const _CatalogItemCard({
    required this.item,
    required this.focusNode,
    required this.isFocused,
    required this.isTelevision,
    required this.onTap,
    required this.onFocusChange,
    required this.onKeyEvent,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Focus(
      focusNode: focusNode,
      onFocusChange: onFocusChange,
      onKeyEvent: onKeyEvent,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedScale(
          scale: isFocused ? 1.08 : 1.0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 140,
            height: 200,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: isFocused
                  ? Border.all(color: colorScheme.primary, width: 3)
                  : null,
              boxShadow: isFocused
                  ? [
                      BoxShadow(
                        color: colorScheme.primary.withOpacity(0.4),
                        blurRadius: 16,
                        spreadRadius: 2,
                      ),
                    ]
                  : [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(isFocused ? 9 : 12),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Poster image
                  _buildPoster(colorScheme),

                  // Gradient overlay
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.transparent,
                            Colors.black.withOpacity(0.7),
                            Colors.black.withOpacity(0.95),
                          ],
                          stops: const [0, 0.4, 0.75, 1],
                        ),
                      ),
                    ),
                  ),

                  // Type badge
                  Positioned(
                    top: 8,
                    left: 8,
                    child: _buildTypeBadge(colorScheme),
                  ),

                  // Title and metadata
                  Positioned(
                    left: 8,
                    right: 8,
                    bottom: 8,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          item.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            height: 1.2,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        _buildMetadata(),
                      ],
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

  Widget _buildPoster(ColorScheme colorScheme) {
    if (item.poster != null && item.poster!.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: item.poster!,
        fit: BoxFit.cover,
        placeholder: (context, url) => Container(
          color: colorScheme.surfaceContainerHighest,
          child: Center(
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: colorScheme.primary,
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
          item.type == 'movie' ? Icons.movie : Icons.tv,
          size: 48,
          color: colorScheme.onSurfaceVariant.withOpacity(0.5),
        ),
      ),
    );
  }

  Widget _buildTypeBadge(ColorScheme colorScheme) {
    final typeLabel = item.type.toUpperCase();
    final color = item.type == 'movie'
        ? Colors.blue
        : item.type == 'series'
            ? Colors.purple
            : Colors.teal;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.9),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        typeLabel,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildMetadata() {
    final parts = <String>[];
    if (item.year != null) parts.add(item.year!);
    if (item.imdbRating != null) parts.add('★ ${item.imdbRating}');

    if (parts.isEmpty) return const SizedBox.shrink();

    return Text(
      parts.join(' • '),
      style: TextStyle(
        color: Colors.white.withOpacity(0.7),
        fontSize: 11,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// Shimmer loading row
class _ShimmerRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shimmerColor = theme.colorScheme.surfaceContainerHighest;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header shimmer
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Container(
            width: 200,
            height: 20,
            decoration: BoxDecoration(
              color: shimmerColor,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),

        // Items shimmer
        SizedBox(
          height: 220,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            itemCount: 6,
            itemBuilder: (context, index) {
              return Padding(
                padding: EdgeInsets.only(right: index < 5 ? 12 : 0),
                child: Container(
                  width: 140,
                  height: 200,
                  decoration: BoxDecoration(
                    color: shimmerColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              );
            },
          ),
        ),

        const SizedBox(height: 8),
      ],
    );
  }
}
