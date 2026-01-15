import 'dart:async';

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

  // Debounce timer for search
  Timer? _debounceTimer;
  // Longer debounce for TV (remote typing is slower)
  Duration get _debounceDuration => widget.isTelevision
      ? const Duration(milliseconds: 750)
      : const Duration(milliseconds: 400);

  late FocusNode _keywordSearchFocusNode;
  late List<FocusNode> _resultFocusNodes;
  int _focusedIndex = -1; // -1 = keyword card focused, 0+ = result index

  @override
  void initState() {
    super.initState();
    _keywordSearchFocusNode = FocusNode(debugLabel: 'keyword_search_card');
    _resultFocusNodes = [];
    // Initial search without debounce
    _performSearch();
  }

  @override
  void didUpdateWidget(AggregatedSearchResults oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only search if query actually changed AND we don't already have results for this query
    if (oldWidget.query != widget.query && widget.query != _lastSearchedQuery) {
      _debouncedSearch();
    }
  }

  void _debouncedSearch() {
    // Cancel any pending search
    _debounceTimer?.cancel();

    // If query is empty, clear results immediately
    if (widget.query.trim().isEmpty) {
      setState(() {
        _results = [];
        _isLoading = false;
      });
      return;
    }

    // Start debounce timer
    _debounceTimer = Timer(_debounceDuration, () {
      if (mounted) {
        _performSearch();
      }
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
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

    // Arrow navigation in list (up/down only)
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (index == 0) {
        // First item: go to keyword card
        _keywordSearchFocusNode.requestFocus();
      } else {
        // Move up one item
        _resultFocusNodes[index - 1].requestFocus();
      }
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (index < _results.length - 1) {
        _resultFocusNodes[index + 1].requestFocus();
        return KeyEventResult.handled;
      }
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _ShimmerCard(),
                ),
                childCount: 6,
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

        // Results list
        if (!_isLoading && _error == null && _results.isNotEmpty)
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final item = _results[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _CatalogResultCard(
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
                    ),
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

/// Compact "Search torrents" action chip
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
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(28),
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: colorScheme.primary,
              borderRadius: BorderRadius.circular(28),
              border: isFocused
                  ? Border.all(color: Colors.white, width: 2)
                  : null,
              boxShadow: [
                BoxShadow(
                  color: colorScheme.primary.withOpacity(0.4),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.search,
                  color: Colors.white,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        const TextSpan(
                          text: 'Tap to search ',
                          style: TextStyle(
                            color: Colors.white70,
                          ),
                        ),
                        TextSpan(
                          text: '"$query"',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    style: theme.textTheme.bodyMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(
                  Icons.arrow_forward,
                  color: Colors.white70,
                  size: 18,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Horizontal catalog result card with thumbnail on left
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
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withOpacity(0.5),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isFocused
                    ? colorScheme.primary
                    : colorScheme.outline.withOpacity(0.2),
                width: isFocused ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                // Thumbnail
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 56,
                    height: 80,
                    child: _buildPoster(colorScheme),
                  ),
                ),
                const SizedBox(width: 12),
                // Details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Title
                      Text(
                        item.name,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      // Metadata row
                      Row(
                        children: [
                          _buildTypeBadge(),
                          if (item.year != null) ...[
                            const SizedBox(width: 8),
                            Text(
                              item.year!,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                          if (item.imdbRating != null) ...[
                            const SizedBox(width: 8),
                            Icon(
                              Icons.star,
                              size: 14,
                              color: Colors.amber,
                            ),
                            const SizedBox(width: 2),
                            Text(
                              '${item.imdbRating}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                // Arrow
                Icon(
                  Icons.chevron_right,
                  color: colorScheme.onSurfaceVariant,
                ),
              ],
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
          item.type == 'movie' ? Icons.movie : Icons.tv,
          size: 24,
          color: colorScheme.onSurfaceVariant.withOpacity(0.5),
        ),
      ),
    );
  }

  Widget _buildTypeBadge() {
    final typeLabel = item.type == 'movie' ? 'Movie' : item.type == 'series' ? 'Series' : item.type;
    final color = item.type == 'movie'
        ? Colors.blue
        : item.type == 'series'
            ? Colors.purple
            : Colors.teal;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        typeLabel,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Horizontal shimmer loading card
class _ShimmerCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.outline.withOpacity(0.2),
        ),
      ),
      child: Row(
        children: [
          // Thumbnail placeholder
          Container(
            width: 56,
            height: 80,
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          const SizedBox(width: 12),
          // Text placeholders
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  height: 14,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  height: 14,
                  width: 120,
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  height: 12,
                  width: 80,
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
