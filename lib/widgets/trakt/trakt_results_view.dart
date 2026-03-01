import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/stremio_addon.dart';
import '../../models/advanced_search_selection.dart';
import '../../services/trakt/trakt_service.dart';
import '../../services/trakt/trakt_item_transformer.dart';
import '../../services/trakt/trakt_episode_model.dart';
import '../../services/tvmaze_service.dart';
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

  // Episode drill-down state
  int _episodeModeGeneration = 0;
  StremioMeta? _selectedShow;
  List<TraktSeason> _seasons = [];
  int _selectedSeasonNumber = 1;
  bool _isLoadingEpisodes = false;
  String? _episodeErrorMessage;
  Map<String, double> _episodeWatchProgress = {};
  final ScrollController _episodeScrollController = ScrollController();
  final List<FocusNode> _episodeFocusNodes = [];
  final FocusNode _seasonDropdownFocusNode = FocusNode(debugLabel: 'trakt-season-dropdown');
  final FocusNode _backButtonFocusNode = FocusNode(debugLabel: 'trakt-back-button');

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
    _episodeScrollController.dispose();
    _listTypeFocusNode.dispose();
    _contentTypeFocusNode.dispose();
    _customListFocusNode.dispose();
    _seasonDropdownFocusNode.dispose();
    _backButtonFocusNode.dispose();
    for (final node in _cardFocusNodes) {
      node.dispose();
    }
    for (final node in _episodeFocusNodes) {
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
    final capturedContentType = _selectedContentType;
    try {
      // Start with watched movies (all 100%)
      final watched = await _traktService.fetchWatchedMovies();
      if (!mounted || _selectedContentType != capturedContentType) return;

      // Overlay playback progress (partial overrides completed — user may be rewatching)
      final playback = await _traktService.fetchPlaybackProgress();
      if (!mounted || _selectedContentType != capturedContentType) return;

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
    if (item.type == 'series') {
      _enterEpisodeMode(item);
      return;
    }
    final selection = AdvancedSearchSelection(
      imdbId: item.effectiveImdbId ?? item.id,
      isSeries: false,
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

  // ── Episode drill-down ──────────────────────────────────────────────────────

  Future<void> _enterEpisodeMode(StremioMeta show) async {
    final generation = ++_episodeModeGeneration;

    setState(() {
      _selectedShow = show;
      _isLoadingEpisodes = true;
      _episodeErrorMessage = null;
      _seasons = [];
      _selectedSeasonNumber = 1;
      _episodeWatchProgress = {};
    });

    for (final node in _episodeFocusNodes) {
      node.dispose();
    }
    _episodeFocusNodes.clear();

    try {
      final showId = show.effectiveImdbId ?? show.id;
      final rawSeasons = await _traktService.fetchShowSeasons(showId);
      if (!mounted || generation != _episodeModeGeneration) return;

      final seasons = rawSeasons
          .map((s) => TraktSeason.fromJson(s))
          .where((s) => s.episodes.isNotEmpty)
          .toList();

      // Sort: regular seasons first (1, 2, 3...), specials (0) at the end
      seasons.sort((a, b) {
        if (a.number == 0 && b.number != 0) return 1;
        if (a.number != 0 && b.number == 0) return -1;
        return a.number.compareTo(b.number);
      });

      if (seasons.isEmpty) {
        setState(() {
          _seasons = [];
          _isLoadingEpisodes = false;
        });
        return;
      }

      final defaultSeason = seasons.firstWhere(
        (s) => s.number > 0,
        orElse: () => seasons.first,
      );

      for (int i = 0; i < defaultSeason.episodes.length; i++) {
        _episodeFocusNodes.add(FocusNode(debugLabel: 'trakt-ep-$i'));
      }

      // Enrich episodes with TVMaze thumbnails + fetch watch progress in parallel
      await Future.wait([
        _enrichEpisodeThumbnails(showId, seasons, generation),
        _fetchEpisodeWatchProgress(showId, generation),
      ]);
      if (!mounted || generation != _episodeModeGeneration) return;

      setState(() {
        _seasons = seasons;
        _selectedSeasonNumber = defaultSeason.number;
        _isLoadingEpisodes = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingEpisodes = false;
        _episodeErrorMessage = 'Failed to load seasons: $e';
      });
    }
  }

  /// Fetch episode thumbnails from TVMaze and update cards.
  Future<void> _enrichEpisodeThumbnails(
    String imdbId,
    List<TraktSeason> seasons,
    int generation,
  ) async {
    try {
      final showData = await TVMazeService.lookupByImdbId(imdbId);
      if (!mounted || generation != _episodeModeGeneration) return;
      if (showData == null) return;

      final tvmazeId = showData['id'] as int?;
      if (tvmazeId == null) return;

      final tvmazeEpisodes = await TVMazeService.getEpisodes(tvmazeId);
      if (!mounted || generation != _episodeModeGeneration) return;
      if (tvmazeEpisodes.isEmpty) return;

      // Build lookup: "S-E" → image URL
      final imageMap = <String, String>{};
      for (final ep in tvmazeEpisodes) {
        final s = ep['season'] as int?;
        final e = ep['number'] as int?;
        final image = ep['image'] as Map<String, dynamic>?;
        final url = image?['medium'] as String? ?? image?['original'] as String?;
        if (s != null && e != null && url != null) {
          imageMap['$s-$e'] = url;
        }
      }

      // Apply to TraktEpisode objects
      for (final season in seasons) {
        for (final episode in season.episodes) {
          final url = imageMap['${episode.season}-${episode.number}'];
          if (url != null) {
            episode.thumbnailUrl = url;
          }
        }
      }
    } catch (e) {
      // Non-critical — episodes still display with show poster fallback
      debugPrint('Trakt: TVMaze thumbnail enrichment failed: $e');
    }
  }

  /// Fetch watch progress for episodes of this show from Trakt.
  /// [showId] can be IMDB ID or Trakt slug (used for /shows/{id}/progress/watched).
  Future<void> _fetchEpisodeWatchProgress(String showId, int generation) async {
    try {
      final watched = await _traktService.fetchWatchedShowEpisodes(showId);
      if (!mounted || generation != _episodeModeGeneration) return;

      // Playback endpoint requires filtering by IMDB ID — skip if we only have a slug
      final imdbId = _selectedShow?.effectiveImdbId;
      Map<String, double> playback = {};
      if (imdbId != null) {
        playback = await _traktService.fetchEpisodePlaybackProgress(imdbId);
        if (!mounted || generation != _episodeModeGeneration) return;
      }

      final merged = <String, double>{};
      // Mark fully watched episodes
      for (final key in watched) {
        merged[key] = 100.0;
      }
      // Overlay playback progress (only for episodes not already fully watched)
      for (final entry in playback.entries) {
        if (merged[entry.key] == 100.0) continue; // Don't downgrade fully watched
        if (entry.value > 5.0) {
          merged[entry.key] = entry.value;
        }
      }
      if (!mounted || generation != _episodeModeGeneration) return;
      setState(() {
        _episodeWatchProgress = merged;
      });
    } catch (e) {
      debugPrint('Trakt: Episode watch progress fetch failed: $e');
    }
  }

  void _exitEpisodeMode() {
    for (final node in _episodeFocusNodes) {
      node.dispose();
    }
    _episodeFocusNodes.clear();
    setState(() {
      _selectedShow = null;
      _seasons = [];
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

    final season = _seasons.firstWhere(
      (s) => s.number == seasonNumber,
      orElse: () => _seasons.first,
    );
    for (int i = 0; i < season.episodes.length; i++) {
      _episodeFocusNodes.add(FocusNode(debugLabel: 'trakt-ep-$i'));
    }

    setState(() => _selectedSeasonNumber = seasonNumber);
    if (_episodeScrollController.hasClients) {
      _episodeScrollController.jumpTo(0);
    }
  }

  void _onEpisodeTap(TraktEpisode episode) {
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
      traktProgressPercent: _episodeWatchProgress['${episode.season}-${episode.number}'],
    );
    widget.onItemSelected(selection);
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
      traktProgressPercent: _episodeWatchProgress['${episode.season}-${episode.number}'],
    );
    if (widget.onQuickPlay != null) {
      widget.onQuickPlay!(selection);
    } else {
      widget.onItemSelected(selection);
    }
  }

  void _focusFirstEpisodeCard() {
    if (_episodeFocusNodes.isNotEmpty) {
      _episodeFocusNodes[0].requestFocus();
    }
  }

  KeyEventResult _handleEpisodeCardKey(int index, KeyEvent event, {bool? isQuickPlayFocused}) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (index > 0) {
        _episodeFocusNodes[index - 1].requestFocus();
      } else {
        _backButtonFocusNode.requestFocus();
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      final currentSeason = _seasons.firstWhere(
        (s) => s.number == _selectedSeasonNumber,
        orElse: () => _seasons.first,
      );
      if (index < currentSeason.episodes.length - 1 && index < _episodeFocusNodes.length - 1) {
        _episodeFocusNodes[index + 1].requestFocus();
      }
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.escape ||
        event.logicalKey == LogicalKeyboardKey.goBack) {
      _exitEpisodeMode();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    if (!_authChecked) {
      return const Center(child: CircularProgressIndicator());
    }

    if (!_isAuthenticated) {
      return _buildNotAuthenticatedState(context);
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
            _buildEpisodeFiltersBar(context),
            Expanded(child: _buildEpisodeContent(context)),
          ],
        ),
      );
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
          _buildDropdown<TraktListType>(
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
          const SizedBox(width: 8),
          // Content type dropdown
          _buildDropdown<TraktContentType>(
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
          // Item count
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

  Widget _buildEpisodeFiltersBar(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          // Back button
          Focus(
            focusNode: _backButtonFocusNode,
            onKeyEvent: (node, event) {
              if (event is! KeyDownEvent) return KeyEventResult.ignored;
              if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
                _seasonDropdownFocusNode.requestFocus();
                return KeyEventResult.handled;
              }
              if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                _focusFirstEpisodeCard();
                return KeyEventResult.handled;
              }
              if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                widget.onUpArrowFromFilters?.call();
                return widget.onUpArrowFromFilters != null
                    ? KeyEventResult.handled
                    : KeyEventResult.ignored;
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
            child: IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: _exitEpisodeMode,
              tooltip: 'Back to shows',
            ),
          ),
          const SizedBox(width: 8),

          // Show title
          Flexible(
            child: Text(
              _selectedShow!.name,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),

          // Season dropdown
          if (_seasons.isNotEmpty)
            _buildDropdown<int>(
              focusNode: _seasonDropdownFocusNode,
              value: _selectedSeasonNumber,
              items: _seasons.map((s) => DropdownMenuItem(
                value: s.number,
                child: Text(
                  s.displayLabel,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
              )).toList(),
              onChanged: _onSeasonChanged,
              hint: 'Season',
              onUpArrow: widget.onUpArrowFromFilters,
              onDownArrow: _focusFirstEpisodeCard,
              onLeftFocus: _backButtonFocusNode,
            ),

          if (!_isLoadingEpisodes && _seasons.isNotEmpty) ...[
            const SizedBox(width: 8),
            Builder(builder: (context) {
              final season = _seasons.firstWhere(
                (s) => s.number == _selectedSeasonNumber,
                orElse: () => _seasons.first,
              );
              return Text(
                '${season.episodes.length} ep',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _buildEpisodeContent(BuildContext context) {
    if (_isLoadingEpisodes) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_episodeErrorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 48, color: Theme.of(context).colorScheme.error),
              const SizedBox(height: 12),
              Text(_episodeErrorMessage!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () => _enterEpisodeMode(_selectedShow!),
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_seasons.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.tv_off_rounded, size: 48, color: Colors.white.withValues(alpha: 0.5)),
            const SizedBox(height: 12),
            Text(
              'No seasons found',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 16),
            ),
          ],
        ),
      );
    }

    final currentSeason = _seasons.firstWhere(
      (s) => s.number == _selectedSeasonNumber,
      orElse: () => _seasons.first,
    );

    return TvFocusScrollWrapper(
      child: ListView.builder(
        controller: _episodeScrollController,
        padding: const EdgeInsets.only(top: 8, bottom: 16, left: 16, right: 16),
        itemCount: currentSeason.episodes.length,
        itemBuilder: (context, index) {
          final episode = currentSeason.episodes[index];
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _TraktEpisodeCard(
              episode: episode,
              showPosterUrl: _selectedShow!.poster,
              focusNode: index < _episodeFocusNodes.length ? _episodeFocusNodes[index] : null,
              onBrowse: () => _onEpisodeTap(episode),
              onQuickPlay: () => _onEpisodeQuickPlay(episode),
              showQuickPlay: widget.showQuickPlay,
              watchProgress: _episodeWatchProgress['${episode.season}-${episode.number}'],
              onKeyEvent: (event, {bool? isQuickPlayFocused}) =>
                  _handleEpisodeCardKey(index, event, isQuickPlayFocused: isQuickPlayFocused),
            ),
          );
        },
      ),
    );
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

// ─── Episode Card ───────────────────────────────────────────────────────────────

/// Card widget for a single Trakt episode.
/// Follows the same pattern as [_TraktItemCard] with DPAD navigation support.
class _TraktEpisodeCard extends StatefulWidget {
  final TraktEpisode episode;
  final String? showPosterUrl;
  final FocusNode? focusNode;
  final VoidCallback onBrowse;
  final VoidCallback onQuickPlay;
  final bool showQuickPlay;
  final double? watchProgress;
  final KeyEventResult Function(KeyEvent, {bool? isQuickPlayFocused}) onKeyEvent;

  const _TraktEpisodeCard({
    required this.episode,
    this.showPosterUrl,
    this.focusNode,
    required this.onBrowse,
    required this.onQuickPlay,
    this.showQuickPlay = true,
    this.watchProgress,
    required this.onKeyEvent,
  });

  @override
  State<_TraktEpisodeCard> createState() => _TraktEpisodeCardState();
}

class _TraktEpisodeCardState extends State<_TraktEpisodeCard> {
  bool _isFocused = false;
  bool _isQuickPlayButtonFocused = false;

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

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

    if (event.logicalKey == LogicalKeyboardKey.select ||
        event.logicalKey == LogicalKeyboardKey.enter) {
      if (_isQuickPlayButtonFocused) {
        widget.onQuickPlay();
      } else {
        widget.onBrowse();
      }
      return KeyEventResult.handled;
    }

    return widget.onKeyEvent(event, isQuickPlayFocused: _isQuickPlayButtonFocused);
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
        onTap: widget.onBrowse,
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
        // Show poster as thumbnail
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 60,
            height: 90,
            child: _buildPoster(colorScheme),
          ),
        ),
        const SizedBox(width: 14),
        // Episode details
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.episode.displayTitle,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              _buildMetadataRow(colorScheme),
              if (widget.episode.overview != null && widget.episode.overview!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  widget.episode.overview!,
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
        _buildActionButton(
          icon: Icons.list_rounded,
          label: 'Browse',
          color: const Color(0xFF6366F1),
          isHighlighted: _isFocused && !_isQuickPlayButtonFocused,
          onTap: widget.onBrowse,
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
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 50,
                height: 75,
                child: _buildPoster(colorScheme),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.episode.displayTitle,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  _buildMetadataRow(colorScheme),
                ],
              ),
            ),
          ],
        ),
        if (widget.episode.overview != null && widget.episode.overview!.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            widget.episode.overview!,
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
                onTap: widget.onBrowse,
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
    // Prefer episode thumbnail, fall back to show poster
    final url = widget.episode.thumbnailUrl ?? widget.showPosterUrl;
    if (url != null) {
      return Image.network(
        url,
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
        Icons.tv_rounded,
        color: colorScheme.onSurfaceVariant.withOpacity(0.5),
        size: 24,
      ),
    );
  }

  Widget _buildMetadataRow(ColorScheme colorScheme) {
    final ep = widget.episode;
    final progress = widget.watchProgress;
    final seasonLabel = ep.season.toString().padLeft(2, '0');
    final epLabel = ep.number.toString().padLeft(2, '0');
    final hasSecondRow = ep.runtime != null || ep.rating != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Row 1: S##E## badge + air date
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF34D399).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'S${seasonLabel}E$epLabel',
                style: const TextStyle(
                  color: Color(0xFF34D399),
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (ep.formattedAirDate != null) ...[
              const SizedBox(width: 8),
              Text(
                ep.formattedAirDate!,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ),
        // Row 2: runtime + rating
        if (hasSecondRow) ...[
          const SizedBox(height: 4),
          Row(
            children: [
              if (ep.runtime != null)
                Text(
                  '${ep.runtime} min',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 12,
                  ),
                ),
              if (ep.rating != null) ...[
                if (ep.runtime != null) const SizedBox(width: 8),
                const Icon(
                  Icons.star_rounded,
                  size: 14,
                  color: Color(0xFFFBBF24),
                ),
                const SizedBox(width: 2),
                Text(
                  ep.rating!.toStringAsFixed(1),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),
        ],
        // Row 3: watch progress indicator
        if (progress != null && progress > 0) ...[
          const SizedBox(height: 4),
          if (progress >= 100.0)
            const Row(
              children: [
                Icon(Icons.check_circle, size: 14, color: Color(0xFF34D399)),
                SizedBox(width: 4),
                Text(
                  'Watched',
                  style: TextStyle(
                    color: Color(0xFF34D399),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            )
          else
            Row(
              children: [
                SizedBox(
                  width: 60,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: progress / 100.0,
                      minHeight: 3,
                      backgroundColor: Colors.white.withValues(alpha: 0.1),
                      valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF34D399)),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '${progress.round()}%',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 11,
                  ),
                ),
              ],
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
