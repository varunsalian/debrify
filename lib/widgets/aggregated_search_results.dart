import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../models/stremio_addon.dart';
import '../models/advanced_search_selection.dart';
import '../services/stremio_service.dart';
import '../services/trakt/trakt_service.dart';
import '../services/series_source_service.dart';
import '../services/storage_service.dart';
import 'trakt/trakt_menu_helpers.dart';

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

  /// Callback when user selects "Select Source" for a series
  final void Function(StremioMeta)? onSelectSource;

  /// Callback when user wants to browse a series with episode drill-down
  /// Passes the show and its source addon so the parent can switch to that addon's CatalogBrowser
  final void Function(StremioMeta show, StremioAddon addon)? onBrowseSeriesEpisodes;

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
    this.onSelectSource,
    this.onBrowseSeriesEpisodes,
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

  // Race condition protection - ignore stale search responses
  int _activeSearchRequestId = 0;

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

  // Trakt integration
  bool _isTraktAuthenticated = false;

  // Bound sources for movies
  Map<String, List<SeriesSource>> _boundSources = {};

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
    TraktService.instance.isAuthenticated().then((auth) {
      if (mounted) setState(() => _isTraktAuthenticated = auth);
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

  /// Request focus on the last focused result card (for sidebar navigation)
  /// Returns true if focus was restored, false if no valid target
  bool requestFocusOnLastResult() {
    // If keyword card was last focused, focus it
    if (_focusedIndex == -1) {
      _keywordSearchFocusNode.requestFocus();
      return true;
    }
    // If a result was last focused, restore focus to it
    if (_focusedIndex >= 0 && _focusedIndex < _resultFocusNodes.length) {
      _resultFocusNodes[_focusedIndex].requestFocus();
      return true;
    }
    // Fallback to first result or keyword card
    if (_resultFocusNodes.isNotEmpty) {
      _resultFocusNodes[0].requestFocus();
      return true;
    }
    _keywordSearchFocusNode.requestFocus();
    return true;
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

    // Increment request ID to track this specific search request
    final int requestId = ++_activeSearchRequestId;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final searchQuery = widget.query; // Capture query at start of search
      final results = await _stremioService.searchCatalogs(searchQuery);

      // Race condition check: ignore stale responses from older requests
      if (!mounted || requestId != _activeSearchRequestId) {
        debugPrint('AggregatedSearchResults: Ignoring stale response for "$searchQuery" (request $requestId, current $_activeSearchRequestId)');
        return;
      }

      // Sort results by relevance (title match priority)
      final sortedResults = _sortByRelevance(results, searchQuery);

      // Update focus nodes for new results
      _updateFocusNodes(sortedResults.length);

      setState(() {
        _results = sortedResults;
        _isLoading = false;
        _lastSearchedQuery = searchQuery; // Remember what we searched for
      });
      _loadBoundSources();
    } catch (e) {
      // Race condition check for error case too
      if (!mounted || requestId != _activeSearchRequestId) {
        return;
      }
      setState(() {
        _error = 'Search failed: $e';
        _isLoading = false;
      });
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
    // For series, try episode drill-down if source addon supports meta
    if (item.type == 'series' &&
        item.sourceAddon != null &&
        item.sourceAddon!.supportsMeta &&
        widget.onBrowseSeriesEpisodes != null) {
      widget.onBrowseSeriesEpisodes!(item, item.sourceAddon!);
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
    widget.onItemSelected?.call(selection);
  }

  void _onQuickPlay(StremioMeta item) async {
    int? season;
    int? episode;

    // For series, look up last played episode to determine S/E
    if (item.type == 'series') {
      final imdbId = item.effectiveImdbId;
      if (imdbId != null) {
        final lastPlayed = await StorageService.getLastPlayedEpisodeByImdbId(imdbId);
        if (!mounted) return;
        if (lastPlayed != null) {
          season = lastPlayed['season'] as int?;
          episode = lastPlayed['episode'] as int?;
        }
      }
      // Fallback to title-based lookup
      if (season == null || episode == null) {
        final byTitle = await StorageService.getLastPlayedEpisode(seriesTitle: item.name);
        if (!mounted) return;
        if (byTitle != null) {
          season = byTitle['season'] as int?;
          episode = byTitle['episode'] as int?;
        }
      }
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

  /// Public: refresh bound sources cache (call after Select Source completes).
  void refreshBoundSources() => _loadBoundSources();

  /// Load bound sources for displayed movie and series items.
  Future<void> _loadBoundSources() async {
    final items = _results.where((i) => i.type == 'movie' || i.type == 'series');
    final sources = <String, List<SeriesSource>>{};
    for (final item in items) {
      final imdbId = item.effectiveImdbId ?? item.id;
      final list = await SeriesSourceService.getSources(imdbId);
      if (list.isNotEmpty) sources[imdbId] = list;
    }
    if (mounted) setState(() => _boundSources = sources);
  }

  /// Handle select source action — show edit dialog if source exists, otherwise enter select mode.
  void _handleSelectSourceAction(StremioMeta item) {
    final imdbId = item.effectiveImdbId ?? item.id;
    if (_boundSources.containsKey(imdbId)) {
      _showEditSourceDialog(item);
    } else {
      widget.onSelectSource?.call(item);
    }
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
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 450, maxHeight: 500),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.link_rounded, color: Color(0xFF60A5FA), size: 24),
                          const SizedBox(width: 8),
                          Text(
                            isMovie ? 'Movie Source' : 'Series Sources (${sources.length})',
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
                            style: TextStyle(color: Colors.white38, fontSize: 11),
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
                                    await SeriesSourceService.removeSourceByHash(imdbId, source.torrentHash);
                                    final updated = await SeriesSourceService.getSources(imdbId);
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
                                    if (updated.isEmpty && dialogContext.mounted) {
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
                                SeriesSourceService.setSources(imdbId, List.of(sources));
                                setState(() => _boundSources[imdbId] = List.of(sources));
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
                                    await SeriesSourceService.removeSourceByHash(imdbId, source.torrentHash);
                                    final updated = await SeriesSourceService.getSources(imdbId);
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
                                    if (updated.isEmpty && dialogContext.mounted) {
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
                              icon: Icon(isMovie ? Icons.swap_horiz_rounded : Icons.add_rounded, size: 18),
                              label: Text(isMovie ? 'Change Source' : 'Add Source'),
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF6366F1),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                          ),
                          if (!isMovie && sources.length > 1) ...[
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () async {
                                  await SeriesSourceService.removeAllSources(imdbId);
                                  if (mounted) {
                                    setState(() => _boundSources.remove(imdbId));
                                  }
                                  if (dialogContext.mounted) Navigator.of(dialogContext).pop();
                                },
                                icon: const Icon(Icons.delete_sweep_outlined, size: 18, color: Color(0xFFEF4444)),
                                label: const Text('Remove All', style: TextStyle(color: Color(0xFFEF4444))),
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(color: Color(0xFFEF4444), width: 1),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                              ),
                            ),
                          ],
                          if (isMovie) ...[
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () async {
                                  await SeriesSourceService.removeAllSources(imdbId);
                                  if (mounted) {
                                    setState(() => _boundSources.remove(imdbId));
                                  }
                                  if (dialogContext.mounted) Navigator.of(dialogContext).pop();
                                },
                                icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Color(0xFFEF4444)),
                                label: const Text('Remove', style: TextStyle(color: Color(0xFFEF4444))),
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(color: Color(0xFFEF4444), width: 1),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        child: const Text('Close', style: TextStyle(color: Colors.white54)),
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
                style: const TextStyle(color: Color(0xFF60A5FA), fontSize: 11, fontWeight: FontWeight.w700),
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
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: serviceColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    serviceLabel,
                    style: TextStyle(color: serviceColor, fontSize: 10, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 16, color: Color(0xFFEF4444)),
            onPressed: onDelete,
            tooltip: 'Remove source',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
          if (showDragHandle)
            const Icon(Icons.drag_handle_rounded, size: 18, color: Colors.white24),
        ],
      ),
    );
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
                        onTraktMenuAction: (item.hasValidImdbId || (item.hasValidId && (item.type == 'movie' || item.type == 'series')))
                            ? (action) => handleTraktMenuAction(context, item, action,
                                onSelectSource: widget.onSelectSource,
                                onEditSource: _handleSelectSourceAction)
                            : null,
                        hasBoundSource: _boundSources.containsKey(item.effectiveImdbId ?? item.id),
                        isTraktAuthenticated: _isTraktAuthenticated,
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
  final void Function(TraktItemMenuAction action)? onTraktMenuAction;
  final bool hasBoundSource;
  final bool isTraktAuthenticated;

  const _CatalogResultCard({
    required this.item,
    required this.focusNode,
    required this.isFocused,
    required this.onQuickPlay,
    required this.onSources,
    required this.onFocusChange,
    required this.onKeyEvent,
    this.showQuickPlay = true,
    this.onTraktMenuAction,
    this.hasBoundSource = false,
    this.isTraktAuthenticated = false,
  });

  @override
  State<_CatalogResultCard> createState() => _CatalogResultCardState();
}

class _CatalogResultCardState extends State<_CatalogResultCard> {
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

    return widget.onKeyEvent(node, event,
        isQuickPlayFocused: _focusedButtonIndex == _quickPlayIndex);
  }

  void _handleFocusChange(bool focused) {
    if (focused) {
      setState(() => _focusedButtonIndex = 0);
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
              isHighlighted: widget.isFocused && _focusedButtonIndex == 0,
              onTap: widget.onSources,
            ),
            if (widget.showQuickPlay) ...[
              const SizedBox(width: 6),
              _buildActionButton(
                icon: Icons.play_arrow_rounded,
                label: 'Quick Play',
                color: const Color(0xFF10B981),
                isHighlighted: widget.isFocused && _focusedButtonIndex == _quickPlayIndex,
                onTap: widget.onQuickPlay,
              ),
            ],
            if (widget.onTraktMenuAction != null) ...[
              const SizedBox(width: 4),
              buildTraktAddOnlyOverflowMenu(
                isHighlighted: widget.isFocused && _focusedButtonIndex == _moreIndex,
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
            Flexible(
              child: _buildActionButton(
                icon: Icons.list_rounded,
                label: 'Browse',
                color: const Color(0xFF6366F1),
                isHighlighted: widget.isFocused && _focusedButtonIndex == 0,
                onTap: widget.onSources,
              ),
            ),
            if (widget.showQuickPlay) ...[
              const SizedBox(width: 8),
              Flexible(
                child: _buildActionButton(
                  icon: Icons.play_arrow_rounded,
                  label: 'Quick Play',
                  color: const Color(0xFF10B981),
                  isHighlighted: widget.isFocused && _focusedButtonIndex == _quickPlayIndex,
                  onTap: widget.onQuickPlay,
                ),
              ),
            ],
            if (widget.onTraktMenuAction != null) ...[
              const SizedBox(width: 4),
              buildTraktAddOnlyOverflowMenu(
                isHighlighted: widget.isFocused && _focusedButtonIndex == _moreIndex,
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
            Flexible(
              child: Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
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
