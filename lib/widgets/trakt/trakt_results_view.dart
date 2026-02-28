import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/stremio_addon.dart';
import '../../models/advanced_search_selection.dart';
import '../../services/trakt/trakt_service.dart';
import '../../services/trakt/trakt_item_transformer.dart';
import '../../screens/debrify_tv/widgets/tv_focus_scroll_wrapper.dart';

/// Trakt list type options
enum TraktListType {
  watchlist,
  collection,
  ratings,
  recommendations,
  customList,
}

extension TraktListTypeExtension on TraktListType {
  String get label {
    switch (this) {
      case TraktListType.watchlist:
        return 'Watchlist';
      case TraktListType.collection:
        return 'Collection';
      case TraktListType.ratings:
        return 'Ratings';
      case TraktListType.recommendations:
        return 'Recommendations';
      case TraktListType.customList:
        return 'Custom Lists';
    }
  }

  String get apiValue {
    switch (this) {
      case TraktListType.watchlist:
        return 'watchlist';
      case TraktListType.collection:
        return 'collection';
      case TraktListType.ratings:
        return 'ratings';
      case TraktListType.recommendations:
        return 'recommendations';
      case TraktListType.customList:
        return '';
    }
  }
}

/// Content type for Trakt lists
enum TraktContentType {
  movies,
  shows,
}

extension TraktContentTypeExtension on TraktContentType {
  String get label {
    switch (this) {
      case TraktContentType.movies:
        return 'Movies';
      case TraktContentType.shows:
        return 'Shows';
    }
  }

  String get apiValue {
    switch (this) {
      case TraktContentType.movies:
        return 'movies';
      case TraktContentType.shows:
        return 'shows';
    }
  }
}

/// Main view for Trakt list results, embedded in TorrentSearchScreen.
class TraktResultsView extends StatefulWidget {
  final String searchQuery;
  final bool isTelevision;
  final void Function(AdvancedSearchSelection) onItemSelected;
  final void Function(AdvancedSearchSelection)? onQuickPlay;
  final bool showQuickPlay;
  final VoidCallback? onUpArrowFromFilters;

  const TraktResultsView({
    super.key,
    required this.searchQuery,
    this.isTelevision = false,
    required this.onItemSelected,
    this.onQuickPlay,
    this.showQuickPlay = true,
    this.onUpArrowFromFilters,
  });

  @override
  State<TraktResultsView> createState() => TraktResultsViewState();
}

class TraktResultsViewState extends State<TraktResultsView> {
  final ScrollController _scrollController = ScrollController();
  final TraktService _traktService = TraktService.instance;

  // Filters
  TraktListType _selectedListType = TraktListType.watchlist;
  TraktContentType _selectedContentType = TraktContentType.movies;

  // Custom lists
  List<Map<String, dynamic>> _customLists = [];
  Map<String, dynamic>? _selectedCustomList;
  bool _customListsLoaded = false;

  // Items
  List<StremioMeta> _items = [];
  List<StremioMeta> _filteredItems = [];
  bool _isLoading = false;
  String? _errorMessage;
  bool _isAuthenticated = false;
  bool _authChecked = false;

  // Watch progress (movies only): imdbId → 0-100
  Map<String, double> _watchProgress = {};
  bool _progressLoaded = false;

  // Focus nodes for DPAD
  final FocusNode _listTypeFocusNode = FocusNode(debugLabel: 'trakt-list-type');
  final FocusNode _contentTypeFocusNode = FocusNode(debugLabel: 'trakt-content-type');
  final FocusNode _customListFocusNode = FocusNode(debugLabel: 'trakt-custom-list');
  final List<FocusNode> _cardFocusNodes = [];

  String _lastSearchQuery = '';

  @override
  void initState() {
    super.initState();
    _checkAuthAndLoad();
  }

  @override
  void didUpdateWidget(TraktResultsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.searchQuery != _lastSearchQuery) {
      _lastSearchQuery = widget.searchQuery;
      _applySearchFilter();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _listTypeFocusNode.dispose();
    _contentTypeFocusNode.dispose();
    _customListFocusNode.dispose();
    for (final node in _cardFocusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  Future<void> _checkAuthAndLoad() async {
    final authenticated = await _traktService.isAuthenticated();
    if (!mounted) return;
    setState(() {
      _isAuthenticated = authenticated;
      _authChecked = true;
    });
    if (authenticated) {
      _fetchItems();
    }
  }

  Future<void> _fetchItems() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _items = [];
      _filteredItems = [];
    });

    // Dispose old focus nodes
    for (final node in _cardFocusNodes) {
      node.dispose();
    }
    _cardFocusNodes.clear();

    try {
      List<dynamic> rawItems;

      if (_selectedListType == TraktListType.customList) {
        // Load custom lists if not loaded
        if (!_customListsLoaded) {
          _customLists = await _traktService.fetchCustomLists();
          if (!mounted) return;
          _customListsLoaded = true;
          if (_customLists.isNotEmpty && _selectedCustomList == null) {
            _selectedCustomList = _customLists.first;
          }
        }

        if (_selectedCustomList == null) {
          if (!mounted) return;
          setState(() {
            _isLoading = false;
            _items = [];
            _filteredItems = [];
          });
          return;
        }

        final listSlug = _selectedCustomList!['ids']?['slug'] as String? ??
            _selectedCustomList!['ids']?['trakt']?.toString();
        if (listSlug == null || listSlug.isEmpty) {
          if (!mounted) return;
          setState(() {
            _isLoading = false;
            _errorMessage = 'Invalid list identifier';
          });
          return;
        }
        rawItems = await _traktService.fetchCustomListItems(
          listSlug,
          _selectedContentType.apiValue,
        );
      } else {
        rawItems = await _traktService.fetchList(
          _selectedListType.apiValue,
          _selectedContentType.apiValue,
        );
      }

      if (!mounted) return;

      // Infer type for flat-format endpoints (recommendations)
      final inferredType = _selectedContentType == TraktContentType.shows ? 'show' : 'movie';
      final metas = TraktItemTransformer.transformList(rawItems, inferredType: inferredType);

      setState(() {
        _isLoading = false;
        _items = metas;
      });
      _applySearchFilter(); // Also rebuilds _cardFocusNodes

      // Fetch watch progress for movies (non-blocking)
      if (_selectedContentType == TraktContentType.movies) {
        _fetchMovieProgress();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to load Trakt list: $e';
      });
    }
  }

  void _applySearchFilter() {
    for (final node in _cardFocusNodes) {
      node.dispose();
    }
    _cardFocusNodes.clear();

    List<StremioMeta> filtered;
    if (widget.searchQuery.isEmpty) {
      filtered = _items;
    } else {
      final query = widget.searchQuery.toLowerCase();
      filtered = _items.where((item) {
        return item.name.toLowerCase().contains(query) ||
            (item.description?.toLowerCase().contains(query) ?? false);
      }).toList();
    }

    for (int i = 0; i < filtered.length; i++) {
      _cardFocusNodes.add(FocusNode(debugLabel: 'trakt-card-$i'));
    }
    setState(() => _filteredItems = filtered);
  }

  Future<void> _fetchMovieProgress() async {
    try {
      // Start with watched movies (all 100%)
      final watched = await _traktService.fetchWatchedMovies();
      if (!mounted) return;

      // Overlay playback progress (partial overrides completed — user may be rewatching)
      final playback = await _traktService.fetchPlaybackProgress();
      if (!mounted) return;

      final merged = <String, double>{...watched};
      for (final entry in playback.entries) {
        if (entry.value > 5.0) {
          // Meaningful rewatch progress — override "Watched"
          merged[entry.key] = entry.value;
        } else if (!merged.containsKey(entry.key)) {
          // Not previously watched — show actual progress
          merged[entry.key] = entry.value;
        }
      }
      setState(() {
        _watchProgress = merged;
        _progressLoaded = true;
      });
    } catch (e) {
      if (!mounted) return;
      // Non-critical — items still display without progress
      debugPrint('Trakt: Failed to fetch watch progress: $e');
    }
  }

  void _onListTypeChanged(TraktListType? type) {
    if (type == null || type == _selectedListType) return;
    setState(() {
      _selectedListType = type;
      _watchProgress = {};
      _progressLoaded = false;
      if (type == TraktListType.customList && !_customListsLoaded) {
        _selectedCustomList = null;
      }
    });
    _fetchItems();
  }

  void _onContentTypeChanged(TraktContentType? type) {
    if (type == null || type == _selectedContentType) return;
    setState(() {
      _selectedContentType = type;
      _watchProgress = {};
      _progressLoaded = false;
    });
    _fetchItems();
  }

  void _onCustomListChanged(Map<String, dynamic>? list) {
    if (list == null || list == _selectedCustomList) return;
    setState(() => _selectedCustomList = list);
    _fetchItems();
  }

  double? _traktProgressForItem(StremioMeta item) {
    if (!_progressLoaded || item.type != 'movie') return null;
    final imdbId = item.effectiveImdbId ?? item.id;
    final p = _watchProgress[imdbId];
    // Only useful for partial progress (not fully watched or unstarted)
    if (p == null || p <= 0 || p >= 100) return null;
    return p;
  }

  void _onItemTap(StremioMeta item) {
    final selection = AdvancedSearchSelection(
      imdbId: item.effectiveImdbId ?? item.id,
      isSeries: item.type == 'series',
      title: item.name,
      year: item.year,
      contentType: item.type,
      posterUrl: item.poster,
      traktProgressPercent: _traktProgressForItem(item),
    );
    widget.onItemSelected(selection);
  }

  void _onQuickPlay(StremioMeta item) {
    final selection = AdvancedSearchSelection(
      imdbId: item.effectiveImdbId ?? item.id,
      isSeries: item.type == 'series',
      title: item.name,
      year: item.year,
      contentType: item.type,
      posterUrl: item.poster,
      traktProgressPercent: _traktProgressForItem(item),
    );
    if (widget.onQuickPlay != null) {
      widget.onQuickPlay!(selection);
    } else {
      widget.onItemSelected(selection);
    }
  }

  /// Focus the first filter (for DPAD navigation from search input)
  void focusFirstFilter() {
    _listTypeFocusNode.requestFocus();
  }

  void _focusFirstCard() {
    if (_filteredItems.isNotEmpty && _cardFocusNodes.isNotEmpty) {
      _cardFocusNodes[0].requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_authChecked) {
      return const Center(child: CircularProgressIndicator());
    }

    if (!_isAuthenticated) {
      return _buildNotAuthenticatedState(context);
    }

    return Column(
      children: [
        _buildFiltersBar(context),
        Expanded(child: _buildContent(context)),
      ],
    );
  }

  Widget _buildFiltersBar(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          // List type dropdown
          Flexible(
            child: _buildDropdown<TraktListType>(
              focusNode: _listTypeFocusNode,
              value: _selectedListType,
              items: TraktListType.values.map((t) => DropdownMenuItem(
                value: t,
                child: Text(t.label, style: const TextStyle(color: Colors.white, fontSize: 14)),
              )).toList(),
              onChanged: _onListTypeChanged,
              hint: 'List Type',
              onUpArrow: widget.onUpArrowFromFilters,
              onDownArrow: _focusFirstCard,
              onRightFocus: _contentTypeFocusNode,
            ),
          ),
          const SizedBox(width: 8),
          // Content type dropdown
          Flexible(
            child: _buildDropdown<TraktContentType>(
              focusNode: _contentTypeFocusNode,
              value: _selectedContentType,
              items: TraktContentType.values.map((t) => DropdownMenuItem(
                value: t,
                child: Text(t.label, style: const TextStyle(color: Colors.white, fontSize: 14)),
              )).toList(),
              onChanged: _onContentTypeChanged,
              hint: 'Content Type',
              onUpArrow: widget.onUpArrowFromFilters,
              onDownArrow: _focusFirstCard,
              onLeftFocus: _listTypeFocusNode,
              onRightFocus: _selectedListType == TraktListType.customList ? _customListFocusNode : null,
            ),
          ),
          // Custom list dropdown (only when Custom Lists is selected)
          if (_selectedListType == TraktListType.customList) ...[
            const SizedBox(width: 8),
            Flexible(
              child: _buildDropdown<String>(
                focusNode: _customListFocusNode,
                value: _selectedCustomList != null
                    ? (_selectedCustomList!['ids']?['slug'] as String? ?? '')
                    : null,
                items: _customLists.map((list) {
                  final slug = list['ids']?['slug'] as String? ?? '';
                  final name = list['name'] as String? ?? 'Unknown';
                  return DropdownMenuItem(
                    value: slug,
                    child: Text(name, style: const TextStyle(color: Colors.white, fontSize: 14)),
                  );
                }).toList(),
                onChanged: (slug) {
                  if (slug == null) return;
                  final list = _customLists.firstWhere(
                    (l) => (l['ids']?['slug'] as String? ?? '') == slug,
                    orElse: () => _customLists.first,
                  );
                  _onCustomListChanged(list);
                },
                hint: 'Select List',
                onUpArrow: widget.onUpArrowFromFilters,
                onDownArrow: _focusFirstCard,
                onLeftFocus: _contentTypeFocusNode,
              ),
            ),
          ],
          // Item count pushed to right
          const Spacer(),
          if (_isLoading)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else if (_filteredItems.isNotEmpty)
            Text(
              '${_filteredItems.length} item${_filteredItems.length != 1 ? 's' : ''}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDropdown<T>({
    required FocusNode focusNode,
    required T? value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
    required String hint,
    VoidCallback? onUpArrow,
    VoidCallback? onDownArrow,
    FocusNode? onLeftFocus,
    FocusNode? onRightFocus,
  }) {
    return Focus(
      focusNode: focusNode,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
          onUpArrow?.call();
          return onUpArrow != null ? KeyEventResult.handled : KeyEventResult.ignored;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
          onDownArrow?.call();
          return onDownArrow != null ? KeyEventResult.handled : KeyEventResult.ignored;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowLeft && onLeftFocus != null) {
          onLeftFocus.requestFocus();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowRight && onRightFocus != null) {
          onRightFocus.requestFocus();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: Theme.of(context).colorScheme.outline.withOpacity(0.3),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<T>(
            value: value,
            isExpanded: true,
            dropdownColor: const Color(0xFF1E293B),
            icon: Icon(
              Icons.keyboard_arrow_down_rounded,
              color: Colors.white.withValues(alpha: 0.7),
            ),
            hint: Text(
              hint,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
            ),
            items: items,
            onChanged: onChanged,
          ),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return _buildErrorState(context);
    }

    if (_items.isEmpty) {
      return _buildEmptyListState(context);
    }

    if (_filteredItems.isEmpty) {
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
              'No matching items',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 16),
            ),
            const SizedBox(height: 4),
            Text(
              'Try a different search term',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 13),
            ),
          ],
        ),
      );
    }

    return TvFocusScrollWrapper(
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.only(top: 8, bottom: 16, left: 16, right: 16),
        itemCount: _filteredItems.length,
        itemBuilder: (context, index) {
          final item = _filteredItems[index];
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _TraktItemCard(
              item: item,
              progress: _selectedContentType == TraktContentType.movies && _progressLoaded
                  ? _watchProgress[item.effectiveImdbId ?? item.id]
                  : null,
              focusNode: index < _cardFocusNodes.length ? _cardFocusNodes[index] : null,
              onSources: () => _onItemTap(item),
              onQuickPlay: () => _onQuickPlay(item),
              showQuickPlay: widget.showQuickPlay,
              onKeyEvent: (event, {bool? isQuickPlayFocused}) => _handleCardKey(index, event, isQuickPlayFocused: isQuickPlayFocused),
            ),
          );
        },
      ),
    );
  }

  KeyEventResult _handleCardKey(int index, KeyEvent event, {bool? isQuickPlayFocused}) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (index > 0) {
        _cardFocusNodes[index - 1].requestFocus();
      } else {
        _listTypeFocusNode.requestFocus();
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (index < _filteredItems.length - 1 && index < _cardFocusNodes.length - 1) {
        _cardFocusNodes[index + 1].requestFocus();
      }
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  Widget _buildNotAuthenticatedState(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.movie_filter_rounded,
              size: 64,
              color: colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              'Connect your Trakt account',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Log in to Trakt to browse your watchlist, collection, and more.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () {
                Navigator.of(context).pushNamed('/settings/trakt').then((_) {
                  _checkAuthAndLoad();
                });
              },
              icon: const Icon(Icons.settings),
              label: const Text('Go to Settings'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              'Failed to load list',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _fetchItems,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyListState(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.movie_filter_outlined,
            size: 64,
            color: colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 16),
          Text(
            'No items found',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Your ${_selectedListType.label.toLowerCase()} is empty for ${_selectedContentType.label.toLowerCase()}.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Item Card ─────────────────────────────────────────────────────────────────

/// Card widget for a single Trakt media item.
/// Features Browse and Quick Play buttons with DPAD navigation support.
class _TraktItemCard extends StatefulWidget {
  final StremioMeta item;
  final double? progress; // null = don't show, 0-100 = percentage
  final FocusNode? focusNode;
  final VoidCallback onSources;
  final VoidCallback onQuickPlay;
  final bool showQuickPlay;
  final KeyEventResult Function(KeyEvent, {bool? isQuickPlayFocused}) onKeyEvent;

  const _TraktItemCard({
    required this.item,
    this.progress,
    this.focusNode,
    required this.onSources,
    required this.onQuickPlay,
    this.showQuickPlay = true,
    required this.onKeyEvent,
  });

  @override
  State<_TraktItemCard> createState() => _TraktItemCardState();
}

class _TraktItemCardState extends State<_TraktItemCard> {
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

    return widget.onKeyEvent(event, isQuickPlayFocused: _isQuickPlayButtonFocused);
  }

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
          _isQuickPlayButtonFocused = false;
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
        child: AnimatedContainer(
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
          child: LayoutBuilder(
            builder: (context, constraints) {
              final useVerticalLayout = constraints.maxWidth < 500;
              return useVerticalLayout
                  ? _buildVerticalLayout(theme, colorScheme)
                  : _buildHorizontalLayout(theme, colorScheme);
            },
          ),
        ),
      ),
    );
  }

  Widget _buildHorizontalLayout(ThemeData theme, ColorScheme colorScheme) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Poster with progress bar overlay
        _buildPosterWithProgress(colorScheme, width: 80, height: 120),
        const SizedBox(width: 14),
        // Details
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.item.name,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              _buildMetadataRow(theme, colorScheme),
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
                        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
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
        // Action buttons (side-by-side)
        _buildActionButton(
          icon: Icons.list_rounded,
          label: 'Browse',
          color: const Color(0xFF6366F1),
          isHighlighted: _isFocused && !_isQuickPlayButtonFocused,
          onTap: widget.onSources,
        ),
        if (widget.showQuickPlay) ...[
          const SizedBox(width: 6),
          _buildActionButton(
            icon: Icons.play_arrow_rounded,
            label: 'Quick Play',
            color: const Color(0xFFB91C1C),
            isHighlighted: _isFocused && _isQuickPlayButtonFocused,
            onTap: widget.onQuickPlay,
          ),
        ],
      ],
    );
  }

  Widget _buildVerticalLayout(ThemeData theme, ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildPosterWithProgress(colorScheme, width: 60, height: 85),
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
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  _buildMetadataRow(theme, colorScheme),
                  if (widget.item.genres != null && widget.item.genres!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      widget.item.genres!.join(', '),
                      style: const TextStyle(color: Colors.white54, fontSize: 11),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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

  Widget _buildPoster(ColorScheme colorScheme) {
    if (widget.item.poster != null) {
      return Image.network(
        widget.item.poster!,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _buildPosterPlaceholder(colorScheme),
      );
    }
    return _buildPosterPlaceholder(colorScheme);
  }

  Widget _buildPosterPlaceholder(ColorScheme colorScheme) {
    return Container(
      color: colorScheme.surfaceContainerHighest,
      child: Icon(
        widget.item.type == 'series' ? Icons.tv_rounded : Icons.movie_rounded,
        color: colorScheme.onSurfaceVariant.withOpacity(0.5),
        size: 32,
      ),
    );
  }

  Widget _buildPosterWithProgress(ColorScheme colorScheme, {required double width, required double height}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: width,
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _buildPoster(colorScheme),
            if (widget.progress != null && widget.progress! > 0 && widget.progress! < 100)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  height: 3,
                  color: Colors.black.withValues(alpha: 0.5),
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: (widget.progress! / 100).clamp(0.0, 1.0),
                    child: Container(
                      height: 3,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFBBF24),
                        borderRadius: BorderRadius.circular(1.5),
                      ),
                    ),
                  ),
                ),
              ),
            if (widget.progress != null && widget.progress! >= 100)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  height: 3,
                  decoration: BoxDecoration(
                    color: const Color(0xFF34D399),
                    borderRadius: BorderRadius.circular(1.5),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetadataRow(ThemeData theme, ColorScheme colorScheme) {
    return Row(
      children: [
        // Type badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: widget.item.type == 'series'
                ? const Color(0xFF34D399).withValues(alpha: 0.15)
                : const Color(0xFF60A5FA).withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            widget.item.type == 'series' ? 'Series' : 'Movie',
            style: TextStyle(
              color: widget.item.type == 'series'
                  ? const Color(0xFF34D399)
                  : const Color(0xFF60A5FA),
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
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
          Icon(
            Icons.star_rounded,
            size: 14,
            color: const Color(0xFFFBBF24),
          ),
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
        if (widget.progress != null) ...[
          const SizedBox(width: 8),
          if (widget.progress! >= 100.0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF34D399).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'Watched',
                style: TextStyle(
                  color: Color(0xFF34D399),
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            )
          else
            Text(
              '${widget.progress!.round()}%',
              style: TextStyle(
                color: widget.progress! > 0
                    ? const Color(0xFFFBBF24)
                    : Colors.white.withValues(alpha: 0.3),
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
    final darkColor = Color.lerp(color, Colors.black, 0.3)!;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
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
}
