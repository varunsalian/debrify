import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../models/stremio_addon.dart';
import '../models/advanced_search_selection.dart';
import '../services/stremio_service.dart';

/// Displays aggregated search results from all catalog sources
///
/// Features:
/// - First result: "Search [keyword]" action card
/// - Remaining results: Catalog search results as a grid
/// - TV D-pad navigation support
class AggregatedSearchResults extends StatefulWidget {
  /// The search query
  final String query;

  /// Callback when user clicks "Search [keyword]" action
  final VoidCallback onKeywordSearch;

  /// Callback when user selects a catalog item
  final void Function(AdvancedSearchSelection selection)? onItemSelected;

  /// Whether running on TV
  final bool isTelevision;

  const AggregatedSearchResults({
    super.key,
    required this.query,
    required this.onKeywordSearch,
    this.onItemSelected,
    this.isTelevision = false,
  });

  @override
  State<AggregatedSearchResults> createState() => _AggregatedSearchResultsState();
}

class _AggregatedSearchResultsState extends State<AggregatedSearchResults> {
  final StremioService _stremioService = StremioService.instance;
  final ScrollController _scrollController = ScrollController();

  List<StremioMeta> _results = [];
  bool _isLoading = false;
  String? _error;
  String _lastSearchedQuery = ''; // Track last searched query to avoid duplicate searches

  late FocusNode _keywordSearchFocusNode;
  late List<FocusNode> _resultFocusNodes;
  int _focusedIndex = -1; // -1 = keyword card focused, 0+ = result index

  @override
  void initState() {
    super.initState();
    _keywordSearchFocusNode = FocusNode(debugLabel: 'keyword_search_card');
    _resultFocusNodes = [];
    _performSearch();
  }

  @override
  void didUpdateWidget(AggregatedSearchResults oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only search if query actually changed AND we don't already have results for this query
    if (oldWidget.query != widget.query && widget.query != _lastSearchedQuery) {
      _performSearch();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _keywordSearchFocusNode.dispose();
    for (final node in _resultFocusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  Future<void> _performSearch() async {
    if (widget.query.trim().isEmpty) {
      setState(() {
        _results = [];
        _isLoading = false;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final searchQuery = widget.query; // Capture query at start of search
      final results = await _stremioService.searchCatalogs(searchQuery);

      if (mounted) {
        // Sort results by relevance (title match priority)
        final sortedResults = _sortByRelevance(results, searchQuery);

        // Update focus nodes for new results
        _updateFocusNodes(sortedResults.length);

        setState(() {
          _results = sortedResults;
          _isLoading = false;
          _lastSearchedQuery = searchQuery; // Remember what we searched for
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Search failed: $e';
          _isLoading = false;
        });
      }
    }
  }

  void _updateFocusNodes(int count) {
    // Dispose old nodes
    for (final node in _resultFocusNodes) {
      node.dispose();
    }
    // Create new nodes
    _resultFocusNodes = List.generate(
      count,
      (i) => FocusNode(debugLabel: 'search_result_$i'),
    );
  }

  /// Sort results by relevance to the search query
  /// Priority: exact match > starts with > contains > other
  List<StremioMeta> _sortByRelevance(List<StremioMeta> results, String query) {
    final queryLower = query.toLowerCase().trim();

    int relevanceScore(StremioMeta item) {
      final titleLower = item.name.toLowerCase();

      // Exact match (highest priority)
      if (titleLower == queryLower) return 100;

      // Title starts with query
      if (titleLower.startsWith(queryLower)) return 80;

      // Query is a complete word in title
      final words = titleLower.split(RegExp(r'\s+'));
      if (words.any((w) => w == queryLower)) return 70;

      // Title contains query as substring
      if (titleLower.contains(queryLower)) return 50;

      // Any word in title starts with query
      if (words.any((w) => w.startsWith(queryLower))) return 30;

      // No direct match (lowest priority)
      return 0;
    }

    // Sort by relevance score (descending), then by rating if available
    final sorted = List<StremioMeta>.from(results);
    sorted.sort((a, b) {
      final scoreA = relevanceScore(a);
      final scoreB = relevanceScore(b);

      if (scoreA != scoreB) return scoreB - scoreA;

      // Secondary sort by rating
      final ratingA = a.imdbRating ?? 0;
      final ratingB = b.imdbRating ?? 0;
      return ratingB.compareTo(ratingA);
    });

    return sorted;
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

  KeyEventResult _handleKeywordCardKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.select ||
        event.logicalKey == LogicalKeyboardKey.enter) {
      widget.onKeywordSearch();
      return KeyEventResult.handled;
    }

    // Down arrow: move to first result
    if (event.logicalKey == LogicalKeyboardKey.arrowDown && _results.isNotEmpty) {
      _resultFocusNodes[0].requestFocus();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  KeyEventResult _handleResultKeyEvent(FocusNode node, KeyEvent event, int index) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.select ||
        event.logicalKey == LogicalKeyboardKey.enter) {
      _onItemSelected(_results[index]);
      return KeyEventResult.handled;
    }

    final screenWidth = MediaQuery.sizeOf(context).width;
    final columns = _getColumnCount(screenWidth);

    // Arrow navigation in grid
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (index < columns) {
        // First row: go to keyword card
        _keywordSearchFocusNode.requestFocus();
      } else {
        // Move up one row
        _resultFocusNodes[index - columns].requestFocus();
      }
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      final nextIndex = index + columns;
      if (nextIndex < _results.length) {
        _resultFocusNodes[nextIndex].requestFocus();
        return KeyEventResult.handled;
      }
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowLeft && index > 0) {
      _resultFocusNodes[index - 1].requestFocus();
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowRight &&
        index < _results.length - 1) {
      _resultFocusNodes[index + 1].requestFocus();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  int _getColumnCount(double screenWidth) {
    if (screenWidth > 1200) return 6;
    if (screenWidth > 900) return 5;
    if (screenWidth > 600) return 4;
    if (screenWidth > 400) return 3;
    return 2;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screenWidth = MediaQuery.sizeOf(context).width;
    final columns = _getColumnCount(screenWidth);

    return CustomScrollView(
      controller: _scrollController,
      slivers: [
        // "Search [keyword]" action card - always first
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: _KeywordSearchCard(
              query: widget.query,
              focusNode: _keywordSearchFocusNode,
              isFocused: _focusedIndex == -1,
              onTap: widget.onKeywordSearch,
              onFocusChange: (focused) {
                setState(() {
                  _focusedIndex = focused ? -1 : _focusedIndex;
                });
              },
              onKeyEvent: _handleKeywordCardKeyEvent,
            ),
          ),
        ),

        // Results section header
        if (_results.isNotEmpty || _isLoading)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    Icons.movie_filter,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Catalog Results',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (!_isLoading) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${_results.length}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

        // Loading state
        if (_isLoading)
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverGrid(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.7,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) => _ShimmerCard(),
                childCount: 8,
              ),
            ),
          ),

        // Error state
        if (_error != null && !_isLoading)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 48,
                    color: theme.colorScheme.error,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),

        // Results grid
        if (!_isLoading && _error == null && _results.isNotEmpty)
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverGrid(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.65,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final item = _results[index];
                  return _CatalogResultCard(
                    item: item,
                    focusNode: _resultFocusNodes[index],
                    isFocused: _focusedIndex == index,
                    onTap: () => _onItemSelected(item),
                    onFocusChange: (focused) {
                      setState(() {
                        _focusedIndex = focused ? index : _focusedIndex;
                      });
                    },
                    onKeyEvent: (node, event) =>
                        _handleResultKeyEvent(node, event, index),
                  );
                },
                childCount: _results.length,
              ),
            ),
          ),

        // Empty state
        if (!_isLoading && _error == null && _results.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.search_off,
                    size: 64,
                    color: theme.colorScheme.onSurfaceVariant.withOpacity(0.5),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No catalog results found',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Try the keyword search above for torrent results',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant.withOpacity(0.7),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// "Search [keyword]" action card
class _KeywordSearchCard extends StatelessWidget {
  final String query;
  final FocusNode focusNode;
  final bool isFocused;
  final VoidCallback onTap;
  final ValueChanged<bool> onFocusChange;
  final KeyEventResult Function(FocusNode, KeyEvent) onKeyEvent;

  const _KeywordSearchCard({
    required this.query,
    required this.focusNode,
    required this.isFocused,
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
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                colorScheme.primary,
                colorScheme.primary.withOpacity(0.8),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            border: isFocused
                ? Border.all(color: Colors.white, width: 3)
                : null,
            boxShadow: [
              BoxShadow(
                color: colorScheme.primary.withOpacity(isFocused ? 0.5 : 0.3),
                blurRadius: isFocused ? 20 : 12,
                spreadRadius: isFocused ? 2 : 0,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.search,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Search Torrents',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Search for "$query" across torrent engines',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.white.withOpacity(0.9),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios,
                color: Colors.white.withOpacity(0.8),
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Individual catalog result card
class _CatalogResultCard extends StatelessWidget {
  final StremioMeta item;
  final FocusNode focusNode;
  final bool isFocused;
  final VoidCallback onTap;
  final ValueChanged<bool> onFocusChange;
  final KeyEventResult Function(FocusNode, KeyEvent) onKeyEvent;

  const _CatalogResultCard({
    required this.item,
    required this.focusNode,
    required this.isFocused,
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
          scale: isFocused ? 1.05 : 1.0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
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
                  // Poster
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
                    child: _buildTypeBadge(),
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
                            fontSize: 12,
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
          size: 40,
          color: colorScheme.onSurfaceVariant.withOpacity(0.5),
        ),
      ),
    );
  }

  Widget _buildTypeBadge() {
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
        fontSize: 10,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// Shimmer loading card
class _ShimmerCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
    );
  }
}
