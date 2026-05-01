import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/storage_service.dart';
import '../services/main_page_bridge.dart';
import '../services/playlist_player_service.dart';
import '../widgets/adaptive_playlist_section.dart';
import 'playlist_content_view_screen.dart';

class PlaylistScreen extends StatefulWidget {
  const PlaylistScreen({super.key});

  @override
  State<PlaylistScreen> createState() => _PlaylistScreenState();
}

class _PlaylistScreenState extends State<PlaylistScreen> {
  late Future<void> _initFuture;
  List<Map<String, dynamic>> _allItems = [];
  Map<String, Map<String, dynamic>> _progressMap = {};

  // TV content focus handler (stored for proper unregistration)
  VoidCallback? _tvContentFocusHandler;

  // Search state
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final FocusNode _searchBarFocusNode = FocusNode();
  final ValueNotifier<String> _searchQuery = ValueNotifier<String>('');
  Timer? _searchDebouncer;
  bool _showSearchField = false;

  // Favorites state
  Set<String> _favoriteKeys = {};

  // Track focus state for restoration after operations
  int? _targetFocusIndex;
  bool _shouldRestoreFocus = false;

  // Prevent concurrent deletion operations
  bool _isDeletionInProgress = false;

  // GlobalKeys for playlist sections (for TV focus management)
  final GlobalKey<AdaptivePlaylistSectionState> _favoritesSectionKey =
      GlobalKey();
  final GlobalKey<AdaptivePlaylistSectionState> _allItemsSectionKey =
      GlobalKey();

  @override
  void initState() {
    super.initState();
    _initFuture = _init();

    // Search controller listener with debounce
    _searchController.addListener(_onSearchChanged);

    // Search bar DPAD key handler
    _searchBarFocusNode.onKeyEvent = _handleSearchBarKeyEvent;

    // Register TV sidebar focus handler (tab index 1 = Playlist)
    _tvContentFocusHandler = () {
      // Priority: 1) First card in Favorites, 2) First card in All Items, 3) Search button
      // Try favorites section first
      if (_favoritesSectionKey.currentState != null &&
          _favoritesSectionKey.currentState!.hasItems) {
        if (_favoritesSectionKey.currentState!.requestFocusOnFirstItem()) {
          return;
        }
      }
      // Try all items section
      if (_allItemsSectionKey.currentState != null &&
          _allItemsSectionKey.currentState!.hasItems) {
        if (_allItemsSectionKey.currentState!.requestFocusOnFirstItem()) {
          return;
        }
      }
      // Fallback to search button
      _searchFocusNode.requestFocus();
    };
    MainPageBridge.registerTvContentFocusHandler(1, _tvContentFocusHandler!);
  }

  @override
  void dispose() {
    if (_tvContentFocusHandler != null) {
      MainPageBridge.unregisterTvContentFocusHandler(
        1,
        _tvContentFocusHandler!,
      );
    }
    // Remove listener before disposing controller
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _searchFocusNode.dispose();
    _searchBarFocusNode.dispose();
    _searchQuery.dispose();
    _searchDebouncer?.cancel();
    super.dispose();
  }

  void _onSearchChanged() {
    _searchDebouncer?.cancel();
    _searchDebouncer = Timer(const Duration(milliseconds: 100), () {
      _searchQuery.value = _searchController.text.toLowerCase().trim();
    });
  }

  KeyEventResult _handleSearchBarKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final text = _searchController.text;
    final selection = _searchController.selection;
    final isAtStart =
        !selection.isValid ||
        (selection.baseOffset == 0 && selection.extentOffset == 0);

    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _searchFocusNode.requestFocus();
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      if (text.isEmpty || isAtStart) {
        MainPageBridge.focusTvSidebar?.call();
      }
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.escape ||
        event.logicalKey == LogicalKeyboardKey.goBack) {
      if (text.isNotEmpty) {
        _searchController.clear();
        return KeyEventResult.handled;
      }
      if (_showSearchField) {
        setState(() => _showSearchField = false);
        _searchFocusNode.requestFocus();
        return KeyEventResult.handled;
      }
    }

    return KeyEventResult.ignored;
  }

  Future<void> _init() async {
    await _loadData();
  }

  Future<void> _loadData() async {
    final items = await StorageService.getPlaylistItemsRaw();

    // Apply poster overrides for items that have saved custom posters
    for (var item in items) {
      final posterOverride = await StorageService.getPlaylistPosterOverride(
        item,
      );
      if (posterOverride != null && posterOverride.isNotEmpty) {
        item['posterUrl'] = posterOverride;
      }
    }

    // Load progress data from playback state
    final progressMap = await StorageService.buildPlaylistProgressMap(items);

    // Load favorites
    final favoriteKeys = await StorageService.getPlaylistFavoriteKeys();

    if (!mounted) return;
    setState(() {
      _allItems = items;
      _progressMap = progressMap;
      _favoriteKeys = favoriteKeys;
    });
  }

  Future<void> _refresh() async {
    await _loadData();
  }

  // Section getter: All items sorted by addedAt (most recent first)
  List<Map<String, dynamic>> get _allItemsSorted {
    return _allItems.toList()..sort((a, b) {
      final aAdded = a['addedAt'] as int? ?? 0;
      final bAdded = b['addedAt'] as int? ?? 0;
      return bAdded.compareTo(aAdded); // Descending (most recent first)
    });
  }

  // Search-filtered items
  List<Map<String, dynamic>> _getFilteredItems(String query) {
    if (query.isEmpty) return _allItemsSorted;
    return _allItemsSorted.where((item) {
      final title = ((item['title'] as String?) ?? '').toLowerCase();
      return title.contains(query);
    }).toList();
  }

  // Favorites section items (filtered by search)
  List<Map<String, dynamic>> _getFavoriteItems(String query) {
    return _getFilteredItems(query).where((item) {
      final dedupeKey = StorageService.computePlaylistDedupeKey(item);
      return _favoriteKeys.contains(dedupeKey);
    }).toList();
  }

  // All items section (filtered by search)
  List<Map<String, dynamic>> _getAllItemsSection(String query) {
    return _getFilteredItems(query);
  }

  // Toggle favorite status for an item
  Future<void> _toggleFavorite(Map<String, dynamic> item) async {
    final dedupeKey = StorageService.computePlaylistDedupeKey(item);
    final isCurrentlyFavorited = _favoriteKeys.contains(dedupeKey);

    await StorageService.setPlaylistItemFavorited(item, !isCurrentlyFavorited);

    if (!mounted) return;
    setState(() {
      if (isCurrentlyFavorited) {
        _favoriteKeys.remove(dedupeKey);
      } else {
        _favoriteKeys.add(dedupeKey);
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          isCurrentlyFavorited
              ? 'Removed from favorites'
              : 'Added to favorites',
        ),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  Future<void> _viewItem(Map<String, dynamic> item) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => PlaylistContentViewScreen(
          playlistItem: item,
          onPlaybackStarted: () => Navigator.of(context).pop(),
        ),
      ),
    );

    // Refresh data when returning from view screen
    // This ensures poster updates are reflected immediately
    await _refresh();
  }

  Future<void> _playItem(Map<String, dynamic> item) async {
    await PlaylistPlayerService.play(context, item);
    if (!mounted) return;
    await _refresh();
  }

  Future<void> _removeItem(Map<String, dynamic> item) async {
    // Prevent concurrent deletions
    if (_isDeletionInProgress) return;

    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF0F172A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: Colors.white.withOpacity(0.08)),
        ),
        title: const Text(
          'Remove from playlist?',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        content: Text(
          '"${item['title'] ?? 'This item'}" will be removed from your playlist. You can always add it again later.',
          style: const TextStyle(color: Colors.white70, fontSize: 15),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            style: TextButton.styleFrom(
              foregroundColor: Colors.white70,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            ),
            child: const Text('Keep'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFE50914),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      // Set deletion lock
      setState(() {
        _isDeletionInProgress = true;
      });

      try {
        // Find the index of the item being deleted for focus restoration
        final currentIndex = _allItems.indexWhere(
          (playlistItem) =>
              StorageService.computePlaylistDedupeKey(playlistItem) ==
              StorageService.computePlaylistDedupeKey(item),
        );

        final dedupeKey = StorageService.computePlaylistDedupeKey(item);
        await StorageService.removePlaylistItemByKey(dedupeKey);
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Removed from playlist')));

        // Set focus restoration flags BEFORE refresh
        // Only restore focus if there will be items remaining after deletion
        if (_allItems.length > 1 && currentIndex >= 0) {
          setState(() {
            // Calculate target index based on position of deleted item
            // If deleting last item, focus on new last item (length - 2)
            // Otherwise, focus stays at same index (which now contains next item)
            if (currentIndex >= _allItems.length - 1) {
              // Deleting the last item - focus previous item
              _targetFocusIndex = _allItems.length - 2;
            } else {
              // Deleting item in middle or start - focus stays at same index
              _targetFocusIndex = currentIndex;
            }
            _shouldRestoreFocus = true;
          });
        } else {
          // If this is the last item, don't try to restore focus
          setState(() {
            _shouldRestoreFocus = false;
            _targetFocusIndex = null;
          });
        }

        await _refresh();
      } finally {
        // Always release deletion lock
        if (mounted) {
          setState(() {
            _isDeletionInProgress = false;
          });
        }
      }
    }
  }

  Future<void> _clearPlaylistProgress(Map<String, dynamic> item) async {
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF0F172A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: Colors.white.withOpacity(0.08)),
        ),
        title: const Text(
          'Clear watch progress?',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        content: Text(
          'All watch progress for "${item['title'] ?? 'this playlist'}" will be cleared. This cannot be undone.',
          style: const TextStyle(color: Colors.white70, fontSize: 15),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            style: TextButton.styleFrom(
              foregroundColor: Colors.white70,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            ),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFFF9800),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            ),
            child: const Text('Clear Progress'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final title = item['title'] as String? ?? '';
      await StorageService.clearPlaylistProgress(title: title);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Watch progress cleared')));
      await _refresh();
    }
  }

  // Show search dialog
  void _toggleSearchField() {
    setState(() {
      _showSearchField = !_showSearchField;
    });
    if (_showSearchField) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _searchBarFocusNode.requestFocus();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: FutureBuilder<void>(
        future: _initFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                valueColor: AlwaysStoppedAnimation(Color(0xFF6366F1)),
              ),
            );
          }

          if (_allItems.isEmpty) {
            return Column(
              children: [
                _buildSearchArea(''),
                Expanded(child: _buildEmptyState()),
              ],
            );
          }

          return ValueListenableBuilder<String>(
            valueListenable: _searchQuery,
            builder: (context, query, child) {
              final favoriteItems = _getFavoriteItems(query);
              final allItems = _getAllItemsSection(query);

              if (allItems.isEmpty && favoriteItems.isEmpty) {
                return Column(
                  children: [
                    _buildSearchArea(query),
                    Expanded(child: _buildNoResultsState(query)),
                  ],
                );
              }

              return FocusTraversalGroup(
                policy: _PlaylistFocusTraversalPolicy(),
                child: RefreshIndicator(
                  onRefresh: _refresh,
                  backgroundColor: const Color(0xFF1E293B),
                  color: const Color(0xFF6366F1),
                  child: CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(
                      parent: BouncingScrollPhysics(),
                    ),
                    cacheExtent: 500.0,
                    slivers: [
                      // Search area - inline bar + toggle button
                      SliverToBoxAdapter(child: _buildSearchArea(query)),

                      // Favorites Section
                      if (favoriteItems.isNotEmpty) ...[
                        SliverToBoxAdapter(
                          child: RepaintBoundary(
                            child: AdaptivePlaylistSection(
                              key: _favoritesSectionKey,
                              sectionTitle: 'Favorites',
                              sectionIcon: Icons.star_rounded,
                              sectionIconColor: const Color(0xFFFFD700),
                              items: favoriteItems,
                              progressMap: _progressMap,
                              favoriteKeys: _favoriteKeys,
                              onItemPlay: _playItem,
                              onItemView: _viewItem,
                              onItemDelete: _removeItem,
                              onItemClearProgress: _clearPlaylistProgress,
                              onItemToggleFavorite: _toggleFavorite,
                              shouldAutofocusFirst: false,
                              targetFocusIndex: _shouldRestoreFocus
                                  ? _targetFocusIndex
                                  : null,
                              shouldRestoreFocus: _shouldRestoreFocus,
                              onFocusRestored: () {
                                setState(() {
                                  _shouldRestoreFocus = false;
                                  _targetFocusIndex = null;
                                });
                              },
                              // UP from Favorites -> Search button
                              onUpArrowPressed: () =>
                                  _searchFocusNode.requestFocus(),
                              // DOWN from Favorites -> First item in All Items
                              onDownArrowPressed: () {
                                _allItemsSectionKey.currentState
                                    ?.requestFocusOnFirstItem();
                              },
                            ),
                          ),
                        ),
                        const SliverToBoxAdapter(child: SizedBox(height: 28)),
                      ],

                      // All Items Section
                      SliverToBoxAdapter(
                        child: RepaintBoundary(
                          child: AdaptivePlaylistSection(
                            key: _allItemsSectionKey,
                            sectionTitle: favoriteItems.isNotEmpty
                                ? 'All Items'
                                : '',
                            sectionIcon: favoriteItems.isNotEmpty
                                ? Icons.grid_view_rounded
                                : null,
                            sectionIconColor: const Color(0xFF6366F1),
                            items: allItems,
                            progressMap: _progressMap,
                            favoriteKeys: _favoriteKeys,
                            onItemPlay: _playItem,
                            onItemView: _viewItem,
                            onItemDelete: _removeItem,
                            onItemClearProgress: _clearPlaylistProgress,
                            onItemToggleFavorite: _toggleFavorite,
                            shouldAutofocusFirst: false,
                            targetFocusIndex:
                                _shouldRestoreFocus && favoriteItems.isEmpty
                                ? _targetFocusIndex
                                : null,
                            shouldRestoreFocus:
                                _shouldRestoreFocus && favoriteItems.isEmpty,
                            onFocusRestored: () {
                              setState(() {
                                _shouldRestoreFocus = false;
                                _targetFocusIndex = null;
                              });
                            },
                            // UP from All Items -> First item in Favorites (if exists), else Search
                            onUpArrowPressed: () {
                              if (_favoritesSectionKey.currentState != null &&
                                  _favoritesSectionKey.currentState!.hasItems) {
                                _favoritesSectionKey.currentState!
                                    .requestFocusOnFirstItem();
                              } else {
                                _searchFocusNode.requestFocus();
                              }
                            },
                          ),
                        ),
                      ),

                      const SliverToBoxAdapter(child: SizedBox(height: 40)),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildSearchArea(String currentQuery) {
    final hasActiveSearch = currentQuery.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Column(
        children: [
          // Inline search bar (toggled)
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            child: _showSearchField
                ? Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: TextField(
                      controller: _searchController,
                      focusNode: _searchBarFocusNode,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Search...',
                        hintStyle: TextStyle(
                          color: Colors.white.withValues(alpha: 0.3),
                        ),
                        prefixIcon: Icon(
                          Icons.search_rounded,
                          color: Colors.white.withValues(alpha: 0.35),
                        ),
                        suffixIcon: ValueListenableBuilder<TextEditingValue>(
                          valueListenable: _searchController,
                          builder: (context, value, _) {
                            if (value.text.isEmpty)
                              return const SizedBox.shrink();
                            return IconButton(
                              icon: Icon(
                                Icons.close_rounded,
                                color: Colors.white.withValues(alpha: 0.5),
                              ),
                              onPressed: () {
                                _searchController.clear();
                              },
                            );
                          },
                        ),
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.07),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(
                            color: Colors.white.withValues(alpha: 0.15),
                            width: 1,
                          ),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          // Search toggle button (centered)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [_buildSearchButton(hasActiveSearch)],
          ),
        ],
      ),
    );
  }

  Widget _buildSearchButton(bool hasActiveSearch) {
    return Focus(
      focusNode: _searchFocusNode,
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            MainPageBridge.focusTvSidebar?.call();
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
            if (_showSearchField) {
              _searchBarFocusNode.requestFocus();
            }
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
            if (_favoritesSectionKey.currentState != null &&
                _favoritesSectionKey.currentState!.hasItems) {
              if (_favoritesSectionKey.currentState!
                  .requestFocusOnFirstItem()) {
                return KeyEventResult.handled;
              }
            }
            if (_allItemsSectionKey.currentState != null &&
                _allItemsSectionKey.currentState!.hasItems) {
              if (_allItemsSectionKey.currentState!.requestFocusOnFirstItem()) {
                return KeyEventResult.handled;
              }
            }
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.select ||
              event.logicalKey == LogicalKeyboardKey.enter) {
            _toggleSearchField();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (context) {
          final isFocused = Focus.of(context).hasFocus;
          return GestureDetector(
            onTap: _toggleSearchField,
            child: Container(
              height: 40,
              width: 40,
              decoration: BoxDecoration(
                color: isFocused
                    ? Colors.white.withValues(alpha: 0.15)
                    : const Color(0xFF141414),
                borderRadius: BorderRadius.circular(20),
                border: isFocused
                    ? Border.all(
                        color: Colors.white.withValues(alpha: 0.6),
                        width: 2,
                      )
                    : null,
              ),
              child: Icon(
                Icons.search_rounded,
                size: 20,
                color: (isFocused || hasActiveSearch || _showSearchField)
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.5),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B).withValues(alpha: 0.5),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.video_library_outlined,
              size: 56,
              color: Colors.white.withValues(alpha: 0.3),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'No items in playlist',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 17,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Add items from your debrid downloads',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.35),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoResultsState(String query) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B).withValues(alpha: 0.5),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.search_off_rounded,
              size: 56,
              color: Colors.white.withValues(alpha: 0.3),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'No results found',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 17,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Try searching for "$query" differently',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.35),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

/// Search dialog for playlist search - TV optimized
/// Custom focus traversal policy that prevents focus from escaping upward to navbar
class _PlaylistFocusTraversalPolicy extends FocusTraversalPolicy
    with DirectionalFocusTraversalPolicyMixin {
  @override
  bool inDirection(FocusNode currentNode, TraversalDirection direction) {
    // Let the default behavior handle most directions
    final result = super.inDirection(currentNode, direction);

    // If trying to go up and no node was found (would escape to navbar),
    // prevent the focus change by returning true (handled) without moving focus
    if (direction == TraversalDirection.up && !result) {
      return true; // Claim we handled it, but don't actually move focus
    }

    return result;
  }

  @override
  Iterable<FocusNode> sortDescendants(
    Iterable<FocusNode> descendants,
    FocusNode currentNode,
  ) {
    // Use reading order (left-to-right, top-to-bottom)
    return descendants.toList()..sort((a, b) {
      final aRect = a.rect;
      final bRect = b.rect;

      // Sort by Y first (top to bottom), then by X (left to right)
      final yDiff = aRect.top.compareTo(bRect.top);
      if (yDiff != 0) return yDiff;
      return aRect.left.compareTo(bRect.left);
    });
  }
}
