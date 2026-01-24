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
/// - Quick Play and Sources buttons for each catalog item
/// - TV D-pad navigation support
class AggregatedSearchResults extends StatefulWidget {
  /// The search query
  final String query;

  /// Callback when user clicks "Search [keyword]" action
  final VoidCallback onKeywordSearch;

  /// Callback when user selects a catalog item (Sources button)
  final void Function(AdvancedSearchSelection selection)? onItemSelected;

  /// Callback when user wants to quick play an item (Quick Play button)
  /// If null, Quick Play button will fallback to onItemSelected behavior
  final void Function(AdvancedSearchSelection selection)? onQuickPlay;

  /// Whether to show the Quick Play button (hide when PikPak is default provider)
  final bool showQuickPlay;

  /// Whether running on TV
  final bool isTelevision;

  /// Callback when keyword search focus node is ready (for external focus control)
  final void Function(FocusNode focusNode)? onKeywordFocusNodeReady;

  /// Callback when user presses Up arrow from keyword card (to return focus to search field)
  final VoidCallback? onRequestFocusAbove;

  const AggregatedSearchResults({
    super.key,
    required this.query,
    required this.onKeywordSearch,
    this.onItemSelected,
    this.onQuickPlay,
    this.showQuickPlay = true,
    this.isTelevision = false,
    this.onKeywordFocusNodeReady,
    this.onRequestFocusAbove,
  });

  @override
  State<AggregatedSearchResults> createState() => AggregatedSearchResultsState();
}

class AggregatedSearchResultsState extends State<AggregatedSearchResults> {
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
  late List<GlobalKey> _resultCardKeys; // Keys for scroll-into-view
  int _focusedIndex = -1; // -1 = keyword card focused, 0+ = result index

  @override
  void initState() {
    super.initState();
    _keywordSearchFocusNode = FocusNode(debugLabel: 'keyword_search_card');
    _resultFocusNodes = [];
    _resultCardKeys = [];
    // Notify parent of the focus node for external focus control
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onKeywordFocusNodeReady?.call(_keywordSearchFocusNode);
    });
    // Initial search without debounce
    _performSearch();
  }

  /// Request focus on the first result card (for DPAD navigation from Sources)
  /// Returns true if focus was set, false if no results to focus
  bool requestFocusOnFirstResult() {
    if (_resultFocusNodes.isNotEmpty) {
      _resultFocusNodes[0].requestFocus();
      return true;
    }
    return false;
  }

  /// Request focus on the keyword search card (for DPAD navigation from Sources)
  void requestFocusOnKeywordCard() {
    _keywordSearchFocusNode.requestFocus();
  }

  /// Check if there are results to navigate to
  bool get hasResults => _results.isNotEmpty;

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
    // Create new nodes and keys
    _resultFocusNodes = List.generate(
      count,
      (i) => FocusNode(debugLabel: 'search_result_$i'),
    );
    _resultCardKeys = List.generate(
      count,
      (i) => GlobalKey(debugLabel: 'search_result_key_$i'),
    );
  }

  /// Scroll a result card into view when focused
  void _scrollResultIntoView(int index) {
    if (index < 0 || index >= _resultCardKeys.length) return;
    final key = _resultCardKeys[index];
    final context = key.currentContext;
    if (context != null) {
      Scrollable.ensureVisible(
        context,
        alignment: 0.3, // Show focused item in upper-middle of viewport
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
      );
    }
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
      posterUrl: item.poster,
    );
    widget.onItemSelected?.call(selection);
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

  KeyEventResult _handleKeywordCardKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.select ||
        event.logicalKey == LogicalKeyboardKey.enter) {
      widget.onKeywordSearch();
      return KeyEventResult.handled;
    }

    // Up arrow: return focus to search field
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      widget.onRequestFocusAbove?.call();
      return KeyEventResult.handled;
    }

    // Down arrow: move to first result
    if (event.logicalKey == LogicalKeyboardKey.arrowDown && _results.isNotEmpty) {
      _resultFocusNodes[0].requestFocus();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  KeyEventResult _handleResultKeyEvent(FocusNode node, KeyEvent event, int index, {bool? isQuickPlayFocused}) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    // Select/Enter is now handled within the card widget for button selection

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
                    child: KeyedSubtree(
                      key: _resultCardKeys[index],
                      child: _CatalogResultCard(
                        item: item,
                        focusNode: _resultFocusNodes[index],
                        isFocused: _focusedIndex == index,
                        onQuickPlay: () => _onQuickPlay(item),
                        onSources: () => _onItemSelected(item),
                        onFocusChange: (focused) {
                          setState(() {
                            _focusedIndex = focused ? index : _focusedIndex;
                          });
                          // Scroll into view when focused
                          if (focused) {
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              _scrollResultIntoView(index);
                            });
                          }
                        },
                        onKeyEvent: (node, event, {bool? isQuickPlayFocused}) =>
                            _handleResultKeyEvent(node, event, index, isQuickPlayFocused: isQuickPlayFocused),
                        showQuickPlay: widget.showQuickPlay,
                      ),
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
/// Features Quick Play and Sources buttons with DPAD navigation support
class _CatalogResultCard extends StatefulWidget {
  final StremioMeta item;
  final FocusNode focusNode;
  final bool isFocused;
  final VoidCallback onQuickPlay;
  final VoidCallback onSources;
  final ValueChanged<bool> onFocusChange;
  final KeyEventResult Function(FocusNode, KeyEvent, {bool? isQuickPlayFocused}) onKeyEvent;
  final bool showQuickPlay;

  const _CatalogResultCard({
    required this.item,
    required this.focusNode,
    required this.isFocused,
    required this.onQuickPlay,
    required this.onSources,
    required this.onFocusChange,
    required this.onKeyEvent,
    this.showQuickPlay = true,
  });

  @override
  State<_CatalogResultCard> createState() => _CatalogResultCardState();
}

class _CatalogResultCardState extends State<_CatalogResultCard> {
  // For DPAD: track which button is focused (true = Quick Play, false = Torrents)
  // Default to Torrents (first button)
  bool _isQuickPlayButtonFocused = false;

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    // Left/Right arrow navigation between buttons
    // Order: [Torrents] [Quick Play]
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      if (_isQuickPlayButtonFocused) {
        setState(() => _isQuickPlayButtonFocused = false); // Move to Torrents
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      if (!_isQuickPlayButtonFocused) {
        setState(() => _isQuickPlayButtonFocused = true); // Move to Quick Play
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
    return widget.onKeyEvent(node, event, isQuickPlayFocused: _isQuickPlayButtonFocused);
  }

  void _handleFocusChange(bool focused) {
    // Reset to Torrents button (first) when card gains focus
    if (focused) {
      setState(() => _isQuickPlayButtonFocused = false);
    }
    widget.onFocusChange(focused);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Focus(
      focusNode: widget.focusNode,
      onFocusChange: _handleFocusChange,
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
                  color: widget.isFocused
                      ? colorScheme.primary
                      : colorScheme.outline.withOpacity(0.2),
                  width: widget.isFocused ? 2 : 1,
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
      children: [
        // Thumbnail
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 70,
            height: 100,
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
              isHighlighted: widget.isFocused && !_isQuickPlayButtonFocused,
              onTap: widget.onSources,
            ),
            if (widget.showQuickPlay) ...[
              const SizedBox(width: 6),
              _buildActionButton(
                icon: Icons.play_arrow_rounded,
                label: 'Quick Play',
                color: const Color(0xFF10B981),
                isHighlighted: widget.isFocused && _isQuickPlayButtonFocused,
                onTap: widget.onQuickPlay,
              ),
            ],
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
                isHighlighted: widget.isFocused && !_isQuickPlayButtonFocused,
                onTap: widget.onSources,
              ),
            ),
            if (widget.showQuickPlay) ...[
              const SizedBox(width: 8),
              Expanded(
                child: _buildActionButton(
                  icon: Icons.play_arrow_rounded,
                  label: 'Quick Play',
                  color: const Color(0xFF10B981),
                  isHighlighted: widget.isFocused && _isQuickPlayButtonFocused,
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
        _buildTypeBadge(),
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
          const Icon(
            Icons.star,
            size: 14,
            color: Colors.amber,
          ),
          const SizedBox(width: 2),
          Text(
            '${widget.item.imdbRating}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
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
          widget.item.type == 'movie' ? Icons.movie : Icons.tv,
          size: 24,
          color: colorScheme.onSurfaceVariant.withOpacity(0.5),
        ),
      ),
    );
  }

  Widget _buildTypeBadge() {
    final typeLabel = widget.item.type == 'movie' ? 'Movie' : widget.item.type == 'series' ? 'Series' : widget.item.type;
    final color = widget.item.type == 'movie'
        ? Colors.blue
        : widget.item.type == 'series'
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
