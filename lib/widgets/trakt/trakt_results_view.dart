import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../models/stremio_addon.dart';
import '../../models/advanced_search_selection.dart';
import '../../services/trakt/trakt_service.dart';
import '../../services/trakt/trakt_item_transformer.dart';
import '../../services/trakt/trakt_episode_model.dart';
import 'trakt_menu_helpers.dart';
import '../../services/tvmaze_service.dart';
import '../../services/series_source_service.dart';
import '../../services/storage_service.dart';
import '../../screens/debrid_downloads_screen.dart';
import '../../screens/torbox/torbox_downloads_screen.dart';
import '../../screens/debrify_tv/widgets/tv_focus_scroll_wrapper.dart';
import '../../screens/stremio_tv/widgets/stremio_tv_catalog_picker_dialog.dart';
import '../add_source_picker_dialog.dart';

// ─── Shared OTT Constants ────────────────────────────────────────────────────
const _traktRed = Color(0xFFED1C24);
const _surfaceDark = Color(0xFF06080F);

const _placeholderGradient = BoxDecoration(
  gradient: LinearGradient(colors: [Color(0xFF1A1A2E), _surfaceDark]),
);

/// Renders a CachedNetworkImage if URL is valid, otherwise a dark gradient placeholder.
Widget _buildOttBackdropImage(String? imageUrl) {
  if (imageUrl == null || imageUrl.isEmpty) {
    return Container(decoration: _placeholderGradient);
  }
  return CachedNetworkImage(
    imageUrl: imageUrl,
    memCacheWidth: 600,
    fit: BoxFit.cover,
    placeholder: (context, url) => Container(decoration: _placeholderGradient),
    errorWidget: (context, url, error) =>
        Container(decoration: _placeholderGradient),
  );
}

/// Trakt list type options
enum TraktListType {
  progress,
  watchlist,
  history,
  customList,
  likedLists,
  collection,
  ratings,
  trending,
  popular,
  anticipated,
  recommendations,
  search,
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
      case TraktListType.history:
        return 'History';
      case TraktListType.trending:
        return 'Trending';
      case TraktListType.popular:
        return 'Popular';
      case TraktListType.anticipated:
        return 'Anticipated';
      case TraktListType.recommendations:
        return 'Recommendations';
      case TraktListType.progress:
        return 'Continue Watching';
      case TraktListType.search:
        return 'Search Trakt';
      case TraktListType.customList:
        return 'Custom Lists';
      case TraktListType.likedLists:
        return 'Liked Lists';
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
      case TraktListType.history:
        return 'history';
      case TraktListType.trending:
        return 'trending';
      case TraktListType.popular:
        return 'popular';
      case TraktListType.anticipated:
        return 'anticipated';
      case TraktListType.recommendations:
        return 'recommendations';
      case TraktListType.progress:
        return 'playback';
      case TraktListType.search:
        return 'search';
      case TraktListType.customList:
        return '';
      case TraktListType.likedLists:
        return '';
    }
  }
}

/// Content type for Trakt lists
enum TraktContentType { movies, shows }

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

// TraktEpisodeMenuAction and TraktItemMenuAction enums are in trakt_menu_helpers.dart

/// Main view for Trakt list results, embedded in TorrentSearchScreen.
class TraktResultsView extends StatefulWidget {
  final String searchQuery;
  final bool isTelevision;
  final void Function(AdvancedSearchSelection) onItemSelected;
  final void Function(AdvancedSearchSelection)? onQuickPlay;
  final bool showQuickPlay;
  final VoidCallback? onUpArrowFromFilters;
  final VoidCallback? onEpisodeModeExited;

  /// Called when user wants to select a torrent source for a series.
  /// Parent should trigger series probing search in select-source mode.
  final void Function(StremioMeta show)? onSelectSource;

  /// Called when user selects "Search Season Packs" for a series.
  final void Function(StremioMeta show)? onSearchPacks;

  const TraktResultsView({
    super.key,
    required this.searchQuery,
    this.isTelevision = false,
    required this.onItemSelected,
    this.onQuickPlay,
    this.showQuickPlay = true,
    this.onUpArrowFromFilters,
    this.onEpisodeModeExited,
    this.onSelectSource,
    this.onSearchPacks,
  });

  @override
  State<TraktResultsView> createState() => TraktResultsViewState();
}

class TraktResultsViewState extends State<TraktResultsView> {
  final ScrollController _scrollController = ScrollController();
  final TraktService _traktService = TraktService.instance;
  bool _quickPlayInProgress = false;

  // Filters
  TraktListType _selectedListType = TraktListType.progress;
  TraktContentType _selectedContentType = TraktContentType.movies;

  // Custom lists
  List<Map<String, dynamic>> _customLists = [];
  Map<String, dynamic>? _selectedCustomList;
  bool _customListsLoaded = false;

  // Liked lists
  List<Map<String, dynamic>> _likedLists = [];
  Map<String, dynamic>? _selectedLikedList;
  bool _likedListsLoaded = false;

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

  // Playback entry IDs from /sync/playback, keyed by IMDB ID
  Map<String, List<int>> _playbackIds = {};

  // Bound series sources: imdbId → List<SeriesSource> (cached for menu display)
  Map<String, List<SeriesSource>> _boundSources = {};

  // Focus nodes for DPAD
  final FocusNode _listTypeFocusNode = FocusNode(debugLabel: 'trakt-list-type');
  final FocusNode _contentTypeFocusNode = FocusNode(
    debugLabel: 'trakt-content-type',
  );
  final FocusNode _customListFocusNode = FocusNode(
    debugLabel: 'trakt-custom-list',
  );
  final FocusNode _likedListFocusNode = FocusNode(
    debugLabel: 'trakt-liked-list',
  );
  final List<FocusNode> _cardFocusNodes = [];

  String _lastSearchQuery = '';
  Timer? _searchDebounce;

  // Episode drill-down state
  int _episodeModeGeneration = 0;
  StremioMeta? _selectedShow;
  List<TraktSeason> _seasons = [];
  int _selectedSeasonNumber = 1;
  bool _isLoadingEpisodes = false;
  String? _episodeErrorMessage;
  Map<String, double> _episodeWatchProgress = {};
  ({int season, int episode})? _nextEpisode;
  final ScrollController _episodeScrollController = ScrollController();
  final List<FocusNode> _episodeFocusNodes = [];
  final FocusNode _seasonDropdownFocusNode = FocusNode(
    debugLabel: 'trakt-season-dropdown',
  );
  final FocusNode _backButtonFocusNode = FocusNode(
    debugLabel: 'trakt-back-button',
  );

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
      if (_selectedListType == TraktListType.search) {
        // Debounce API search to avoid hammering Trakt on every keystroke
        _searchDebounce?.cancel();
        if (widget.searchQuery.isEmpty) {
          _fetchItems(); // Clear results immediately
        } else {
          _searchDebounce = Timer(const Duration(milliseconds: 500), () {
            if (mounted) _fetchItems();
          });
        }
      } else {
        _applySearchFilter();
      }
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _scrollController.dispose();
    _episodeScrollController.dispose();
    _listTypeFocusNode.dispose();
    _contentTypeFocusNode.dispose();
    _customListFocusNode.dispose();
    _likedListFocusNode.dispose();
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
    // Load saved Trakt defaults (list type + content type)
    final savedListType = await StorageService.getHomeDefaultTraktListType();
    final savedContentType =
        await StorageService.getHomeDefaultTraktContentType();
    if (!mounted) return;
    if (savedListType != null) {
      final listType = TraktListType.values
          .where((t) => t.apiValue == savedListType || t.name == savedListType)
          .firstOrNull;
      if (listType != null) _selectedListType = listType;
    }
    if (savedContentType != null) {
      final contentType = TraktContentType.values
          .where(
            (t) => t.apiValue == savedContentType || t.name == savedContentType,
          )
          .firstOrNull;
      if (contentType != null) _selectedContentType = contentType;
    }

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
    // Search type: don't auto-fetch, wait for query
    if (_selectedListType == TraktListType.search &&
        widget.searchQuery.isEmpty) {
      setState(() {
        _isLoading = false;
        _items = [];
        _filteredItems = [];
      });
      return;
    }

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

      if (_selectedListType == TraktListType.search) {
        final searchType = _selectedContentType == TraktContentType.shows
            ? 'show'
            : 'movie';
        rawItems = await _traktService.searchItems(
          widget.searchQuery,
          searchType,
        );
      } else if (_selectedListType == TraktListType.customList) {
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

        final listSlug =
            _selectedCustomList!['ids']?['slug'] as String? ??
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
      } else if (_selectedListType == TraktListType.likedLists) {
        // Load liked lists if not loaded
        if (!_likedListsLoaded) {
          _likedLists = await _traktService.fetchLikedLists();
          if (!mounted) return;
          _likedListsLoaded = true;
          if (_likedLists.isNotEmpty && _selectedLikedList == null) {
            _selectedLikedList = _likedLists.first;
          }
        }

        if (_selectedLikedList == null) {
          if (!mounted) return;
          setState(() {
            _isLoading = false;
            _items = [];
            _filteredItems = [];
          });
          return;
        }

        final listSlug =
            _selectedLikedList!['ids']?['slug'] as String? ??
            _selectedLikedList!['ids']?['trakt']?.toString();
        final owner =
            (_selectedLikedList!['user'] as Map<String, dynamic>?)?['username']
                as String?;
        if (listSlug == null ||
            listSlug.isEmpty ||
            owner == null ||
            owner.isEmpty) {
          if (!mounted) return;
          setState(() {
            _isLoading = false;
            _errorMessage = 'Invalid liked list identifier';
          });
          return;
        }
        rawItems = await _traktService.fetchLikedListItems(
          owner,
          listSlug,
          _selectedContentType.apiValue,
        );
      } else if (_selectedListType == TraktListType.progress) {
        // Continue Watching — fetch from /sync/playback (partial progress items)
        // Trakt uses 'movies' and 'episodes' (not 'shows') for playback
        final playbackType = _selectedContentType == TraktContentType.shows
            ? 'episodes'
            : 'movies';
        rawItems = await _traktService.fetchPlaybackItems(playbackType);
        if (!mounted) return;

        // For shows: also find recently watched shows with a next episode available
        // (covers shows where last episode was fully watched but more episodes exist)
        if (_selectedContentType == TraktContentType.shows) {
          // Collect IMDB IDs already in playback to avoid duplicates
          final playbackImdbIds = <String>{};
          for (final raw in rawItems) {
            if (raw is! Map<String, dynamic>) continue;
            final show = raw['show'] as Map<String, dynamic>?;
            final ids = show?['ids'] as Map<String, dynamic>?;
            final imdbId = ids?['imdb'] as String?;
            if (imdbId != null) playbackImdbIds.add(imdbId);
          }

          final recentWithNext = await _traktService
              .fetchRecentShowsWithNextEpisode(excludeImdbIds: playbackImdbIds);
          if (!mounted) return;

          if (recentWithNext.isNotEmpty) {
            rawItems = List<dynamic>.from(rawItems)..addAll(recentWithNext);
          }
        }
      } else {
        rawItems = await _traktService.fetchList(
          _selectedListType.apiValue,
          _selectedContentType.apiValue,
        );
      }

      if (!mounted) return;

      // Capture playback IDs for Continue Watching items
      if (_selectedListType == TraktListType.progress) {
        final pbIds = <String, List<int>>{};
        for (final raw in rawItems) {
          if (raw is! Map<String, dynamic>) continue;
          final pbId = raw['id'] as int?;
          final contentKey = _selectedContentType == TraktContentType.shows
              ? 'show'
              : 'movie';
          final content = raw[contentKey] as Map<String, dynamic>?;
          final ids = content?['ids'] as Map<String, dynamic>?;
          final imdbId = ids?['imdb'] as String?;
          if (imdbId != null && pbId != null) {
            pbIds.putIfAbsent(imdbId, () => []).add(pbId);
          }
        }
        _playbackIds = pbIds;
      } else {
        _playbackIds = {};
      }

      // Transform raw items into StremioMeta objects
      final List<StremioMeta> metas;
      if ((_selectedListType == TraktListType.progress ||
              _selectedListType == TraktListType.history) &&
          _selectedContentType == TraktContentType.shows) {
        // Playback/history episodes → deduplicate into shows
        metas = TraktItemTransformer.transformPlaybackEpisodes(rawItems);
      } else {
        final inferredType = _selectedContentType == TraktContentType.shows
            ? 'show'
            : 'movie';
        metas = TraktItemTransformer.transformList(
          rawItems,
          inferredType: inferredType,
        );
      }

      setState(() {
        _isLoading = false;
        _items = metas;
      });
      _applySearchFilter(); // Also rebuilds _cardFocusNodes

      // Load bound sources for series and movie items (non-blocking)
      if (_selectedContentType == TraktContentType.shows ||
          _selectedContentType == TraktContentType.movies) {
        _loadBoundSources();
      }

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
      if (type == TraktListType.likedLists && !_likedListsLoaded) {
        _selectedLikedList = null;
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

  void _onLikedListChanged(Map<String, dynamic>? list) {
    if (list == null || list == _selectedLikedList) return;
    setState(() => _selectedLikedList = list);
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
      traktSource: true,
    );
    widget.onItemSelected(selection);
  }

  void _onQuickPlay(StremioMeta item) async {
    if (_quickPlayInProgress) return;
    _quickPlayInProgress = true;

    try {
      int? season;
      int? episode;

      double? traktProgress = _traktProgressForItem(item);

      if (item.type == 'series') {
        final showId = item.effectiveImdbId ?? item.id;
        final next = await _traktService.fetchNextEpisode(showId);
        if (!mounted) return;
        season = next?.season;
        episode = next?.episode;

        // Fetch episode-specific playback progress from Trakt
        if (season != null && episode != null) {
          final episodeProgress = await _traktService
              .fetchEpisodePlaybackProgress(showId);
          if (!mounted) return;
          final key = '$season-$episode';
          final p = episodeProgress[key];
          if (p != null && p > 0 && p < 100) {
            traktProgress = p;
          }
        }
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
        traktProgressPercent: traktProgress,
        traktSource: true,
      );
      if (widget.onQuickPlay != null) {
        widget.onQuickPlay!(selection);
      } else {
        widget.onItemSelected(selection);
      }
    } finally {
      _quickPlayInProgress = false;
    }
  }

  Future<void> _onMenuAction(
    StremioMeta item,
    TraktItemMenuAction action,
  ) async {
    final imdbId = item.effectiveImdbId ?? item.id;
    final type = item.type;
    bool success = false;
    String actionLabel = '';

    switch (action) {
      case TraktItemMenuAction.addToWatchlist:
        actionLabel = 'Added to Watchlist';
        success = await _traktService.addToWatchlist(imdbId, type);
      case TraktItemMenuAction.removeFromWatchlist:
        actionLabel = 'Removed from Watchlist';
        success = await _traktService.removeFromWatchlist(imdbId, type);
        if (success && mounted) _fetchItems();
      case TraktItemMenuAction.addToCollection:
        actionLabel = 'Added to Collection';
        success = await _traktService.addToCollection(imdbId, type);
      case TraktItemMenuAction.removeFromCollection:
        actionLabel = 'Removed from Collection';
        success = await _traktService.removeFromCollection(imdbId, type);
        if (success && mounted) _fetchItems();
      case TraktItemMenuAction.markWatched:
        actionLabel = 'Marked as Watched';
        success = await _traktService.addToHistory(imdbId, type);
        if (success && mounted) {
          setState(() => _watchProgress[imdbId] = 100.0);
        }
      case TraktItemMenuAction.markUnwatched:
        actionLabel = 'Marked as Unwatched';
        success = await _traktService.removeFromHistory(imdbId, type);
        if (success && mounted) {
          setState(() => _watchProgress.remove(imdbId));
        }
      case TraktItemMenuAction.rate:
        final rating = await _showRatingDialog();
        if (rating == null) return;
        actionLabel = 'Rated $rating/10';
        success = await _traktService.rateItem(imdbId, type, rating);
      case TraktItemMenuAction.removeRating:
        actionLabel = 'Rating Removed';
        success = await _traktService.removeRating(imdbId, type);
        if (success && mounted) _fetchItems();
      case TraktItemMenuAction.addToList:
        final list = await _showCustomListPickerDialog();
        if (list == null) return;
        final listSlug =
            list['ids']?['slug'] as String? ??
            list['ids']?['trakt']?.toString();
        if (listSlug == null || listSlug.isEmpty) return;
        actionLabel = 'Added to "${list['name']}"';
        success = await _traktService.addToCustomList(listSlug, imdbId, type);
      case TraktItemMenuAction.removeFromList:
        if (_selectedCustomList == null) return;
        final listSlug =
            _selectedCustomList!['ids']?['slug'] as String? ??
            _selectedCustomList!['ids']?['trakt']?.toString();
        if (listSlug == null || listSlug.isEmpty) return;
        actionLabel = 'Removed from List';
        success = await _traktService.removeFromCustomList(
          listSlug,
          imdbId,
          type,
        );
        if (success && mounted) _fetchItems();
      case TraktItemMenuAction.removeFromPlayback:
        final pbIds = _playbackIds[imdbId];
        if (pbIds == null || pbIds.isEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'No in-progress playback to remove — try marking the next episode as watched instead',
                ),
                duration: Duration(seconds: 3),
              ),
            );
          }
          return;
        }
        actionLabel = 'Removed from Continue Watching';
        for (final pbId in pbIds) {
          final ok = await _traktService.removePlaybackItem(pbId);
          if (ok) success = true;
        }
        if (success && mounted) _fetchItems();
      case TraktItemMenuAction.addToStremioTv:
        await _handleAddToStremioTv(item);
        return;
      case TraktItemMenuAction.selectSource:
        _handleSelectSourceAction(item);
        return; // Handled via dialog, no snackbar needed
      case TraktItemMenuAction.playRandomEpisode:
        return; // Not exposed in Trakt results menus
      case TraktItemMenuAction.searchPacks:
        widget.onSearchPacks?.call(item);
        return;
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(success ? actionLabel : 'Failed: $actionLabel'),
        backgroundColor: success
            ? const Color(0xFF34D399)
            : const Color(0xFFEF4444),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<int?> _showRatingDialog() => showTraktRatingDialog(context);

  Future<Map<String, dynamic>?> _showCustomListPickerDialog() =>
      showTraktCustomListPickerDialog(context);

  Future<void> _handleAddToStremioTv(StremioMeta item) async {
    final result = await StremioTvCatalogPickerDialog.show(context, item: item);
    if (!mounted || result == null) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.message),
        backgroundColor: result.duplicate
            ? Colors.orange.shade700
            : const Color(0xFF34D399),
      ),
    );
  }

  /// Public: refresh bound sources cache (call after Select Source completes).
  void refreshBoundSources() {
    _loadBoundSources();
    _loadBoundSourceForShow();
  }

  /// Load bound sources for all currently displayed series and movie items.
  Future<void> _loadBoundSources() async {
    final seriesItems = _filteredItems.where(
      (i) => i.type == 'series' || i.type == 'movie',
    );
    final sources = <String, List<SeriesSource>>{};
    for (final item in seriesItems) {
      final imdbId = item.effectiveImdbId ?? item.id;
      final list = await SeriesSourceService.getSources(imdbId);
      if (list.isNotEmpty) sources[imdbId] = list;
    }
    if (mounted) setState(() => _boundSources = sources);
  }

  /// Load bound source for the currently selected show (episode mode).
  Future<void> _loadBoundSourceForShow() async {
    if (_selectedShow == null) return;
    final imdbId = _selectedShow!.effectiveImdbId ?? _selectedShow!.id;
    final list = await SeriesSourceService.getSources(imdbId);
    if (mounted) {
      setState(() {
        if (list.isNotEmpty) {
          _boundSources[imdbId] = list;
        } else {
          _boundSources.remove(imdbId);
        }
      });
    }
  }

  /// Show "Edit Sources" dialog with list of bound sources and management options.
  Future<void> _showEditSourceDialog(StremioMeta show) async {
    final imdbId = show.effectiveImdbId ?? show.id;
    final isMovie = show.type == 'movie';
    var sources =
        _boundSources[imdbId] ?? await SeriesSourceService.getSources(imdbId);
    if (sources.isEmpty || !mounted) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return Dialog(
              backgroundColor: const Color(0xFF1E293B),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 450,
                  maxHeight: 500,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.link_rounded,
                            color: Color(0xFF60A5FA),
                            size: 24,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            isMovie
                                ? 'Movie Source'
                                : 'Series Sources (${sources.length})',
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
                            style: TextStyle(
                              color: Colors.white38,
                              fontSize: 11,
                            ),
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
                                      await SeriesSourceService.removeSourceByHash(
                                        imdbId,
                                        source.torrentHash,
                                      );
                                      final updated =
                                          await SeriesSourceService.getSources(
                                            imdbId,
                                          );
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
                                      if (updated.isEmpty &&
                                          dialogContext.mounted) {
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
                                  // Persist reorder (defensive copy)
                                  SeriesSourceService.setSources(
                                    imdbId,
                                    List.of(sources),
                                  );
                                  setState(
                                    () => _boundSources[imdbId] = List.of(
                                      sources,
                                    ),
                                  );
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
                                      await SeriesSourceService.removeSourceByHash(
                                        imdbId,
                                        source.torrentHash,
                                      );
                                      final updated =
                                          await SeriesSourceService.getSources(
                                            imdbId,
                                          );
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
                                      if (updated.isEmpty &&
                                          dialogContext.mounted) {
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
                              icon: Icon(
                                isMovie
                                    ? Icons.swap_horiz_rounded
                                    : Icons.add_rounded,
                                size: 18,
                              ),
                              label: Text(
                                isMovie ? 'Change Source' : 'Add Source',
                              ),
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF6366F1),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                          ),
                          if (!isMovie && sources.length > 1) ...[
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () async {
                                  await SeriesSourceService.removeAllSources(
                                    imdbId,
                                  );
                                  if (mounted) {
                                    setState(
                                      () => _boundSources.remove(imdbId),
                                    );
                                  }
                                  if (dialogContext.mounted)
                                    Navigator.of(dialogContext).pop();
                                },
                                icon: const Icon(
                                  Icons.delete_sweep_outlined,
                                  size: 18,
                                  color: Color(0xFFEF4444),
                                ),
                                label: const Text(
                                  'Remove All',
                                  style: TextStyle(color: Color(0xFFEF4444)),
                                ),
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(
                                    color: Color(0xFFEF4444),
                                    width: 1,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      // Add from Debrid button
                      FutureBuilder<List<bool>>(
                        future: Future.wait([
                          StorageService.getApiKey().then(
                            (k) => k != null && k.isNotEmpty,
                          ),
                          StorageService.getTorboxApiKey().then(
                            (k) => k != null && k.isNotEmpty,
                          ),
                        ]),
                        builder: (context, snapshot) {
                          final rdEnabled = snapshot.data?[0] ?? false;
                          final torboxEnabled = snapshot.data?[1] ?? false;
                          if (!rdEnabled && !torboxEnabled)
                            return const SizedBox.shrink();

                          return Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: () {
                                  Navigator.of(dialogContext).pop();
                                  _pushDebridSelectSource(
                                    show: show,
                                    imdbId: imdbId,
                                    rdEnabled: rdEnabled,
                                    torboxEnabled: torboxEnabled,
                                  );
                                },
                                icon: const Icon(
                                  Icons.cloud_download_outlined,
                                  size: 18,
                                  color: Color(0xFF60A5FA),
                                ),
                                label: const Text(
                                  'Add from Debrid',
                                  style: TextStyle(color: Color(0xFF60A5FA)),
                                ),
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(
                                    color: Color(0xFF60A5FA),
                                    width: 1,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        child: const Text(
                          'Close',
                          style: TextStyle(color: Colors.white54),
                        ),
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

  /// Push debrid downloads screen in select-source mode.
  /// If both providers enabled, shows a picker first.
  void _pushDebridSelectSource({
    required StremioMeta show,
    required String imdbId,
    required bool rdEnabled,
    required bool torboxEnabled,
  }) {
    final isMovie = show.type == 'movie';

    Future<void> saveSource(SeriesSource source) async {
      if (isMovie) {
        await SeriesSourceService.setSources(imdbId, [source]);
      } else {
        await SeriesSourceService.addSource(imdbId, source);
      }
      final updated = await SeriesSourceService.getSources(imdbId);
      if (mounted) {
        setState(() => _boundSources[imdbId] = updated);
      }
    }

    void pushRd() {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => DebridDownloadsScreen(
            isPushedRoute: true,
            initialSearchQuery: show.name,
            selectSourceMode: true,
            onSourceSelected: saveSource,
          ),
        ),
      );
    }

    void pushTorbox() {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => TorboxDownloadsScreen(
            isPushedRoute: true,
            initialSearchQuery: show.name,
            selectSourceMode: true,
            onSourceSelected: saveSource,
          ),
        ),
      );
    }

    if (rdEnabled && !torboxEnabled) {
      pushRd();
      return;
    }
    if (torboxEnabled && !rdEnabled) {
      pushTorbox();
      return;
    }

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Select Provider',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.cloud, color: Color(0xFF22C55E)),
              title: const Text(
                'Real-Debrid',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () {
                Navigator.of(sheetContext).pop();
                pushRd();
              },
            ),
            ListTile(
              leading: const Icon(Icons.cloud, color: Color(0xFF7C3AED)),
              title: const Text(
                'TorBox',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () {
                Navigator.of(sheetContext).pop();
                pushTorbox();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
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
          // Priority number (hidden for single-source items like movies)
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
                style: const TextStyle(
                  color: Color(0xFF60A5FA),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          // Source info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  source.torrentName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: serviceColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    serviceLabel,
                    style: TextStyle(
                      color: serviceColor,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Delete button
          IconButton(
            icon: const Icon(
              Icons.close_rounded,
              size: 16,
              color: Color(0xFFEF4444),
            ),
            onPressed: onDelete,
            tooltip: 'Remove source',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
          // Drag handle
          if (showDragHandle)
            const Icon(
              Icons.drag_handle_rounded,
              size: 18,
              color: Colors.white24,
            ),
        ],
      ),
    );
  }

  /// Handle menu action for select/edit source. Shows edit dialog if a source exists, otherwise the picker.
  void _handleSelectSourceAction(StremioMeta item) {
    final imdbId = item.effectiveImdbId ?? item.id;
    if (_boundSources.containsKey(imdbId)) {
      _showEditSourceDialog(item);
    } else {
      _showAddSourcePicker(item, imdbId);
    }
  }

  /// Show the add-source picker (Torrent Search / Real-Debrid / TorBox).
  /// Skips the picker if no cloud providers are enabled.
  Future<void> _showAddSourcePicker(StremioMeta item, String imdbId) async {
    final rdKey = await StorageService.getApiKey();
    final torboxKey = await StorageService.getTorboxApiKey();
    final rdEnabled = rdKey != null && rdKey.isNotEmpty;
    final torboxEnabled = torboxKey != null && torboxKey.isNotEmpty;

    if (!mounted) return;

    if (!rdEnabled && !torboxEnabled) {
      widget.onSelectSource?.call(item);
      return;
    }

    await showAddSourcePickerDialog(
      context,
      onTorrentSearch: () => widget.onSelectSource?.call(item),
      onRealDebrid: rdEnabled
          ? () => _pushDebridSelectSource(
              show: item,
              imdbId: imdbId,
              rdEnabled: true,
              torboxEnabled: false,
            )
          : null,
      onTorbox: torboxEnabled
          ? () => _pushDebridSelectSource(
              show: item,
              imdbId: imdbId,
              rdEnabled: false,
              torboxEnabled: true,
            )
          : null,
    );
  }

  /// Focus the first filter (for DPAD navigation from search input)
  void focusFirstFilter() {
    // In episode mode, focus the episode filter bar instead of the main filters
    if (_selectedShow != null) {
      _backButtonFocusNode.requestFocus();
      return;
    }
    _listTypeFocusNode.requestFocus();
  }

  void _focusFirstCard() {
    if (_filteredItems.isNotEmpty && _cardFocusNodes.isNotEmpty) {
      _cardFocusNodes[0].requestFocus();
    }
  }

  /// Public entry point to open episode browser for a show.
  /// Used by home sections to navigate here.
  void enterEpisodeMode(StremioMeta show, {int? season, int? episode}) =>
      _enterEpisodeMode(show, initialSeason: season, initialEpisode: episode);

  // ── Episode drill-down ──────────────────────────────────────────────────────

  Future<void> _enterEpisodeMode(
    StremioMeta show, {
    int? initialSeason,
    int? initialEpisode,
  }) async {
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

      // Enrich episodes with TVMaze thumbnails + fetch watch progress + next episode in parallel
      final nextEpisodeFuture = _traktService.fetchNextEpisode(showId);
      await Future.wait([
        _enrichEpisodeThumbnails(showId, seasons, generation),
        _fetchEpisodeWatchProgress(showId, generation),
      ]);
      final nextEpisode = await nextEpisodeFuture;
      if (!mounted || generation != _episodeModeGeneration) return;

      // Store next episode for UI highlighting
      _nextEpisode = nextEpisode;

      // Prefer an explicit target episode when supplied (calendar/deep-link
      // flows), otherwise fall back to Trakt's next-episode context.
      var targetSeason = defaultSeason.number;
      int? targetEpisodeNumber;
      if (initialSeason != null &&
          initialEpisode != null &&
          seasons.any((s) => s.number == initialSeason) &&
          seasons
              .firstWhere((s) => s.number == initialSeason)
              .episodes
              .any((e) => e.number == initialEpisode)) {
        targetSeason = initialSeason;
        targetEpisodeNumber = initialEpisode;
      } else if (nextEpisode != null) {
        final hasSeason = seasons.any((s) => s.number == nextEpisode.season);
        if (hasSeason) {
          targetSeason = nextEpisode.season;
          targetEpisodeNumber = nextEpisode.episode;
        }
      }

      // Rebuild focus nodes for the target season
      if (targetSeason != defaultSeason.number) {
        for (final node in _episodeFocusNodes) {
          node.dispose();
        }
        _episodeFocusNodes.clear();
        final targetSeasonObj = seasons.firstWhere(
          (s) => s.number == targetSeason,
        );
        for (int i = 0; i < targetSeasonObj.episodes.length; i++) {
          _episodeFocusNodes.add(FocusNode(debugLabel: 'trakt-ep-$i'));
        }
      }

      setState(() {
        _seasons = seasons;
        _selectedSeasonNumber = targetSeason;
        _isLoadingEpisodes = false;
      });

      // Load bound source for this show (non-blocking)
      _loadBoundSourceForShow();

      // Scroll to the requested episode after the frame renders.
      if (targetEpisodeNumber != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || generation != _episodeModeGeneration) return;
          final season = _seasons.firstWhere(
            (s) => s.number == targetSeason,
            orElse: () => _seasons.first,
          );
          final epIndex = season.episodes.indexWhere(
            (e) => e.number == targetEpisodeNumber,
          );
          if (epIndex >= 0) {
            // Scroll to the episode if it's not at the top
            if (epIndex > 0 && _episodeScrollController.hasClients) {
              final maxExtent =
                  _episodeScrollController.position.maxScrollExtent;
              final ratio = epIndex / season.episodes.length;
              _episodeScrollController.jumpTo(
                (maxExtent * ratio).clamp(0.0, maxExtent),
              );
            }
            // After the item is built, focus it and ensure visible
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted || generation != _episodeModeGeneration) return;
              if (epIndex < _episodeFocusNodes.length) {
                _episodeFocusNodes[epIndex].requestFocus();
                final ctx = _episodeFocusNodes[epIndex].context;
                if (ctx != null) {
                  Scrollable.ensureVisible(
                    ctx,
                    alignment: 0.3,
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOut,
                  );
                }
              }
            });
          }
        });
      } else {
        // No next episode — focus the first episode card
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || generation != _episodeModeGeneration) return;
          if (_episodeFocusNodes.isNotEmpty) {
            _episodeFocusNodes[0].requestFocus();
          }
        });
      }
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
        final url =
            image?['medium'] as String? ?? image?['original'] as String?;
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
        if (merged[entry.key] == 100.0)
          continue; // Don't downgrade fully watched
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
      _nextEpisode = null;
    });
    widget.onEpisodeModeExited?.call();
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
      traktProgressPercent:
          _episodeWatchProgress['${episode.season}-${episode.number}'],
      traktSource: true,
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
      traktProgressPercent:
          _episodeWatchProgress['${episode.season}-${episode.number}'],
      traktSource: true,
    );
    if (widget.onQuickPlay != null) {
      widget.onQuickPlay!(selection);
    } else {
      widget.onItemSelected(selection);
    }
  }

  Future<void> _onEpisodeMenuAction(
    TraktEpisode episode,
    TraktEpisodeMenuAction action,
  ) async {
    final show = _selectedShow;
    if (show == null) return;
    final showImdbId = show.effectiveImdbId ?? show.id;
    final key = '${episode.season}-${episode.number}';
    bool success = false;
    String actionLabel = '';

    switch (action) {
      case TraktEpisodeMenuAction.markWatched:
        actionLabel = 'Marked as Watched';
        success = await _traktService.markEpisodeWatched(
          showImdbId,
          episode.season,
          episode.number,
        );
        if (success && mounted) {
          setState(() => _episodeWatchProgress[key] = 100.0);
        }
      case TraktEpisodeMenuAction.markUnwatched:
        actionLabel = 'Marked as Unwatched';
        success = await _traktService.markEpisodeUnwatched(
          showImdbId,
          episode.season,
          episode.number,
        );
        if (success && mounted) {
          setState(() => _episodeWatchProgress.remove(key));
        }
      case TraktEpisodeMenuAction.rate:
        final rating = await _showRatingDialog();
        if (rating == null) return;
        actionLabel = 'Rated $rating/10';
        success = await _traktService.rateEpisode(
          showImdbId,
          episode.season,
          episode.number,
          rating,
        );
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(success ? actionLabel : 'Failed: $actionLabel'),
        backgroundColor: success
            ? const Color(0xFF34D399)
            : const Color(0xFFEF4444),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _focusFirstEpisodeCard() {
    if (_episodeFocusNodes.isNotEmpty) {
      _episodeFocusNodes[0].requestFocus();
    }
  }

  KeyEventResult _handleEpisodeCardKey(
    int index,
    KeyEvent event, {
    bool? isQuickPlayFocused,
  }) {
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
      if (index < currentSeason.episodes.length - 1 &&
          index < _episodeFocusNodes.length - 1) {
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
    final hasCustomList = _selectedListType == TraktListType.customList;
    final hasLikedList = _selectedListType == TraktListType.likedLists;
    final hasSubList = hasCustomList || hasLikedList;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: Row(
          children: [
            // List type dropdown
            Flexible(
              flex: hasSubList ? 3 : 4,
              child: _buildDropdown<TraktListType>(
                focusNode: _listTypeFocusNode,
                value: _selectedListType,
                items: TraktListType.values
                    .map(
                      (t) => DropdownMenuItem(
                        value: t,
                        child: Text(
                          t.label,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    )
                    .toList(),
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
              flex: 2,
              child: _buildDropdown<TraktContentType>(
                focusNode: _contentTypeFocusNode,
                value: _selectedContentType,
                items: TraktContentType.values
                    .map(
                      (t) => DropdownMenuItem(
                        value: t,
                        child: Text(
                          t.label,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: _onContentTypeChanged,
                hint: 'Type',
                onUpArrow: widget.onUpArrowFromFilters,
                onDownArrow: _focusFirstCard,
                onLeftFocus: _listTypeFocusNode,
                onRightFocus: hasCustomList
                    ? _customListFocusNode
                    : hasLikedList
                    ? _likedListFocusNode
                    : null,
              ),
            ),
            // Custom list dropdown (only when Custom Lists is selected)
            if (hasCustomList) ...[
              const SizedBox(width: 8),
              Flexible(
                flex: 3,
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
                      child: Text(
                        name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                        ),
                      ),
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
                  onRightFocus: null,
                ),
              ),
            ],
            // Liked list dropdown (only when Liked Lists is selected)
            if (hasLikedList) ...[
              const SizedBox(width: 8),
              Flexible(
                flex: 3,
                child: _buildDropdown<String>(
                  focusNode: _likedListFocusNode,
                  value: _selectedLikedList != null
                      ? '${(_selectedLikedList!['user'] as Map<String, dynamic>?)?['username'] ?? ''}/${_selectedLikedList!['ids']?['slug'] ?? ''}'
                      : null,
                  items: _likedLists.map((list) {
                    final slug = list['ids']?['slug'] as String? ?? '';
                    final name = list['name'] as String? ?? 'Unknown';
                    final owner =
                        (list['user'] as Map<String, dynamic>?)?['username']
                            as String? ??
                        '';
                    final key = '$owner/$slug';
                    return DropdownMenuItem(
                      value: key,
                      child: Text(
                        owner.isNotEmpty ? '$name ($owner)' : name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }).toList(),
                  onChanged: (key) {
                    if (key == null) return;
                    final list = _likedLists.firstWhere((l) {
                      final s = l['ids']?['slug'] as String? ?? '';
                      final o =
                          (l['user'] as Map<String, dynamic>?)?['username']
                              as String? ??
                          '';
                      return '$o/$s' == key;
                    }, orElse: () => _likedLists.first);
                    _onLikedListChanged(list);
                  },
                  hint: 'Select List',
                  onUpArrow: widget.onUpArrowFromFilters,
                  onDownArrow: _focusFirstCard,
                  onLeftFocus: _contentTypeFocusNode,
                  onRightFocus: null,
                ),
              ),
            ],
            // Item count / loading indicator
            const SizedBox(width: 8),
            if (_isLoading)
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else if (_filteredItems.isNotEmpty)
              Text(
                '${_filteredItems.length}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
    );
  }

  bool get hasCustomListActive => _selectedListType == TraktListType.customList;
  bool get hasLikedListActive => _selectedListType == TraktListType.likedLists;

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
    // Attach key handler directly to the dropdown's focus node
    focusNode.onKeyEvent = (node, event) {
      if (event is! KeyDownEvent) return KeyEventResult.ignored;
      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        onUpArrow?.call();
        return onUpArrow != null
            ? KeyEventResult.handled
            : KeyEventResult.ignored;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        onDownArrow?.call();
        return onDownArrow != null
            ? KeyEventResult.handled
            : KeyEventResult.ignored;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowLeft &&
          onLeftFocus != null) {
        onLeftFocus.requestFocus();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowRight &&
          onRightFocus != null) {
        onRightFocus.requestFocus();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    };
    return ListenableBuilder(
      listenable: focusNode,
      builder: (context, _) {
        final hasFocus = focusNode.hasFocus;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: hasFocus
                ? Theme.of(context).colorScheme.surfaceContainerHighest
                : Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: hasFocus
                  ? const Color(0xFF60A5FA)
                  : Theme.of(
                      context,
                    ).colorScheme.outline.withValues(alpha: 0.3),
              width: hasFocus ? 2.0 : 1.0,
            ),
            boxShadow: hasFocus
                ? [
                    BoxShadow(
                      color: const Color(0xFF60A5FA).withValues(alpha: 0.3),
                      blurRadius: 12,
                      spreadRadius: 0,
                    ),
                  ]
                : null,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              focusNode: focusNode,
              focusColor: Colors.transparent,
              value: value,
              isExpanded: true,
              isDense: true,
              dropdownColor: const Color(0xFF1E293B),
              icon: Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 20,
                color: hasFocus
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.7),
              ),
              hint: Text(
                hint,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 13,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              items: items,
              onChanged: onChanged,
            ),
          ),
        );
      },
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
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Try a different search term',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 13,
              ),
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
              progress:
                  _selectedContentType == TraktContentType.movies &&
                      _progressLoaded
                  ? _watchProgress[item.effectiveImdbId ?? item.id]
                  : null,
              focusNode: index < _cardFocusNodes.length
                  ? _cardFocusNodes[index]
                  : null,
              onSources: () => _onItemTap(item),
              onQuickPlay: () => _onQuickPlay(item),
              showQuickPlay: widget.showQuickPlay,
              onKeyEvent: (event, {bool? isQuickPlayFocused}) => _handleCardKey(
                index,
                event,
                isQuickPlayFocused: isQuickPlayFocused,
              ),
              listType: _selectedListType,
              onMenuAction: (action) => _onMenuAction(item, action),
              hasBoundSource: _boundSources.containsKey(
                item.effectiveImdbId ?? item.id,
              ),
            ),
          );
        },
      ),
    );
  }

  KeyEventResult _handleCardKey(
    int index,
    KeyEvent event, {
    bool? isQuickPlayFocused,
  }) {
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
      if (index < _filteredItems.length - 1 &&
          index < _cardFocusNodes.length - 1) {
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
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF1A1A2E), _surfaceDark],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            // Back button
            Focus(
              focusNode: _backButtonFocusNode,
              onFocusChange: (focused) => setState(() {}),
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
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: _backButtonFocusNode.hasFocus
                      ? Colors.white.withValues(alpha: 0.1)
                      : Colors.transparent,
                  border: _backButtonFocusNode.hasFocus
                      ? Border.all(color: const Color(0xFF60A5FA), width: 2)
                      : null,
                ),
                child: IconButton(
                  icon: const Icon(Icons.arrow_back_rounded),
                  onPressed: _exitEpisodeMode,
                  tooltip: 'Back to shows',
                ),
              ),
            ),
            const SizedBox(width: 8),

            // Season dropdown
            if (_seasons.isNotEmpty)
              Flexible(
                flex: 1,
                child: _buildDropdown<int>(
                  focusNode: _seasonDropdownFocusNode,
                  value: _selectedSeasonNumber,
                  items: _seasons
                      .map(
                        (s) => DropdownMenuItem(
                          value: s.number,
                          child: Text(
                            s.displayLabel,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: _onSeasonChanged,
                  hint: 'Season',
                  onUpArrow: widget.onUpArrowFromFilters,
                  onDownArrow: _focusFirstEpisodeCard,
                  onLeftFocus: _backButtonFocusNode,
                ),
              ),

            // Select Source / Edit Source button
            if (_selectedShow != null && widget.onSelectSource != null) ...[
              const SizedBox(width: 8),
              Builder(
                builder: (context) {
                  final imdbId =
                      _selectedShow!.effectiveImdbId ?? _selectedShow!.id;
                  final sourceCount = _boundSources[imdbId]?.length ?? 0;
                  return _SelectSourceButton(
                    hasBoundSource: sourceCount > 0,
                    sourceCount: sourceCount,
                    onTap: () => _handleSelectSourceAction(_selectedShow!),
                    onLeftFocus: _seasons.isNotEmpty
                        ? _seasonDropdownFocusNode
                        : _backButtonFocusNode,
                    onUpArrow: widget.onUpArrowFromFilters,
                    onDownArrow: _focusFirstEpisodeCard,
                  );
                },
              ),
            ],
          ],
        ),
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
              Icon(
                Icons.error_outline,
                size: 48,
                color: Theme.of(context).colorScheme.error,
              ),
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
            Icon(
              Icons.tv_off_rounded,
              size: 48,
              color: Colors.white.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 12),
            Text(
              'No seasons found',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 16,
              ),
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
              focusNode: index < _episodeFocusNodes.length
                  ? _episodeFocusNodes[index]
                  : null,
              onBrowse: () => _onEpisodeTap(episode),
              onQuickPlay: () => _onEpisodeQuickPlay(episode),
              showQuickPlay: widget.showQuickPlay,
              watchProgress:
                  _episodeWatchProgress['${episode.season}-${episode.number}'],
              isNextEpisode:
                  _nextEpisode != null &&
                  _nextEpisode!.season == episode.season &&
                  _nextEpisode!.episode == episode.number,
              onKeyEvent: (event, {bool? isQuickPlayFocused}) =>
                  _handleEpisodeCardKey(
                    index,
                    event,
                    isQuickPlayFocused: isQuickPlayFocused,
                  ),
              onMenuAction: (action) => _onEpisodeMenuAction(episode, action),
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
            Icon(Icons.error_outline, size: 64, color: colorScheme.error),
            const SizedBox(height: 16),
            Text('Failed to load list', style: theme.textTheme.titleMedium),
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
            _selectedListType == TraktListType.search
                ? Icons.search
                : Icons.movie_filter_outlined,
            size: 64,
            color: colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 16),
          Text('No items found', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            _selectedListType == TraktListType.search
                ? (widget.searchQuery.isEmpty
                      ? 'Type in the search bar above to search Trakt.'
                      : 'No ${_selectedContentType.label.toLowerCase()} found for "${widget.searchQuery}".')
                : _selectedListType == TraktListType.progress
                ? 'You haven\'t watched any ${_selectedContentType.label.toLowerCase()} yet.'
                : 'Your ${_selectedListType.label.toLowerCase()} is empty for ${_selectedContentType.label.toLowerCase()}.',
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
  final KeyEventResult Function(KeyEvent, {bool? isQuickPlayFocused})
  onKeyEvent;
  final TraktListType? listType;
  final void Function(TraktItemMenuAction action)? onMenuAction;
  final bool hasBoundSource;

  const _TraktItemCard({
    required this.item,
    this.progress,
    this.focusNode,
    required this.onSources,
    required this.onQuickPlay,
    this.showQuickPlay = true,
    required this.onKeyEvent,
    this.listType,
    this.onMenuAction,
    this.hasBoundSource = false,
  });

  @override
  State<_TraktItemCard> createState() => _TraktItemCardState();
}

class _TraktItemCardState extends State<_TraktItemCard> {
  bool _isFocused = false;
  // For DPAD: track which button is focused by index
  // Order: [Browse=0] [Quick Play=1?] [More=last?]
  int _focusedButtonIndex = 0;
  final GlobalKey<PopupMenuButtonState<TraktItemMenuAction>> _menuKey =
      GlobalKey();

  int get _buttonCount {
    int count = 1; // Browse always exists
    if (widget.showQuickPlay) count++;
    if (widget.onMenuAction != null) count++;
    return count;
  }

  int? get _quickPlayIndex => widget.showQuickPlay ? 1 : null;
  int? get _moreIndex => widget.onMenuAction != null ? _buttonCount - 1 : null;

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    // Left/Right arrow navigation between buttons
    // Order: [Browse] [Quick Play?] [More?]
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

    // Select/Enter triggers the focused button
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

    return widget.onKeyEvent(
      event,
      isQuickPlayFocused: _focusedButtonIndex == _quickPlayIndex,
    );
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
          _focusedButtonIndex = 0;
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
        child: AnimatedScale(
          scale: _isFocused ? 1.02 : 1.0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _isFocused
                    ? Colors.white.withValues(alpha: 0.35)
                    : Colors.white.withValues(alpha: 0.06),
                width: _isFocused ? 1.5 : 1,
              ),
              boxShadow: _isFocused
                  ? [
                      BoxShadow(
                        color: Colors.white.withValues(alpha: 0.1),
                        blurRadius: 16,
                        spreadRadius: 0,
                      ),
                    ]
                  : null,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Stack(
                children: [
                  // Layer 1: Backdrop image
                  Positioned.fill(
                    child: _buildOttBackdropImage(
                      widget.item.background ?? widget.item.poster,
                    ),
                  ),
                  // Layer 2: Dark gradient scrim
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: [
                            Colors.black.withValues(alpha: 0.95),
                            Colors.black.withValues(alpha: 0.8),
                            Colors.black.withValues(alpha: 0.5),
                          ],
                          stops: const [0.0, 0.5, 1.0],
                        ),
                      ),
                    ),
                  ),
                  // Layer 3: Content
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final useVerticalLayout = constraints.maxWidth < 500;
                        return useVerticalLayout
                            ? _buildVerticalLayout(theme, colorScheme)
                            : _buildHorizontalLayout(theme, colorScheme);
                      },
                    ),
                  ),
                  // Layer 4: Progress bar
                  if (widget.progress != null && widget.progress! > 0)
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: FractionallySizedBox(
                          widthFactor: (widget.progress! / 100).clamp(0.0, 1.0),
                          child: Container(
                            height: 3,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  _traktRed,
                                  _traktRed.withValues(alpha: 0.7),
                                ],
                              ),
                            ),
                          ),
                        ),
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

  Widget _buildOverflowMenu() {
    final listType = widget.listType;
    final isWatched =
        (widget.progress ?? 0) >= 100 ||
        (widget.progress == null &&
            (listType == TraktListType.progress ||
                listType == TraktListType.history));
    final isHighlighted = _isFocused && _focusedButtonIndex == _moreIndex;

    return Container(
      decoration: isHighlighted
          ? BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.4),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.white.withValues(alpha: 0.15),
                  blurRadius: 12,
                  spreadRadius: 1,
                ),
              ],
            )
          : null,
      child: PopupMenuButton<TraktItemMenuAction>(
        key: _menuKey,
        icon: Icon(
          Icons.more_vert,
          size: 20,
          color: isHighlighted
              ? Colors.white
              : Colors.white.withValues(alpha: 0.7),
        ),
        tooltip: 'More options',
        color: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        onSelected: (action) => widget.onMenuAction?.call(action),
        itemBuilder: (context) => [
          PopupMenuItem(
            value: listType == TraktListType.watchlist
                ? TraktItemMenuAction.removeFromWatchlist
                : TraktItemMenuAction.addToWatchlist,
            child: Row(
              children: [
                Icon(
                  listType == TraktListType.watchlist
                      ? Icons.bookmark_remove
                      : Icons.bookmark_add_outlined,
                  size: 18,
                  color: const Color(0xFFFBBF24),
                ),
                const SizedBox(width: 12),
                Text(
                  listType == TraktListType.watchlist
                      ? 'Remove from Watchlist'
                      : 'Add to Watchlist',
                ),
              ],
            ),
          ),
          PopupMenuItem(
            value: listType == TraktListType.collection
                ? TraktItemMenuAction.removeFromCollection
                : TraktItemMenuAction.addToCollection,
            child: Row(
              children: [
                Icon(
                  listType == TraktListType.collection
                      ? Icons.library_add_check
                      : Icons.library_add_outlined,
                  size: 18,
                  color: const Color(0xFF60A5FA),
                ),
                const SizedBox(width: 12),
                Text(
                  listType == TraktListType.collection
                      ? 'Remove from Collection'
                      : 'Add to Collection',
                ),
              ],
            ),
          ),
          PopupMenuItem(
            value: isWatched
                ? TraktItemMenuAction.markUnwatched
                : TraktItemMenuAction.markWatched,
            child: Row(
              children: [
                Icon(
                  isWatched ? Icons.visibility_off : Icons.visibility,
                  size: 18,
                  color: const Color(0xFF34D399),
                ),
                const SizedBox(width: 12),
                Text(isWatched ? 'Mark as Unwatched' : 'Mark as Watched'),
              ],
            ),
          ),
          PopupMenuItem(
            value: listType == TraktListType.ratings
                ? TraktItemMenuAction.removeRating
                : TraktItemMenuAction.rate,
            child: Row(
              children: [
                Icon(
                  listType == TraktListType.ratings
                      ? Icons.star_border
                      : Icons.star_rate_rounded,
                  size: 18,
                  color: const Color(0xFFFBBF24),
                ),
                const SizedBox(width: 12),
                Text(
                  listType == TraktListType.ratings ? 'Remove Rating' : 'Rate',
                ),
              ],
            ),
          ),
          PopupMenuItem(
            value: listType == TraktListType.customList
                ? TraktItemMenuAction.removeFromList
                : TraktItemMenuAction.addToList,
            child: Row(
              children: [
                Icon(
                  listType == TraktListType.customList
                      ? Icons.playlist_remove
                      : Icons.playlist_add,
                  size: 18,
                  color: const Color(0xFFEC4899),
                ),
                const SizedBox(width: 12),
                Text(
                  listType == TraktListType.customList
                      ? 'Remove from List'
                      : 'Add to List...',
                ),
              ],
            ),
          ),
          if (listType == TraktListType.progress)
            const PopupMenuItem(
              value: TraktItemMenuAction.removeFromPlayback,
              child: Row(
                children: [
                  Icon(
                    Icons.delete_outline_rounded,
                    size: 18,
                    color: Color(0xFFEF4444),
                  ),
                  SizedBox(width: 12),
                  Text('Remove from Continue Watching'),
                ],
              ),
            ),
          PopupMenuItem(
            value: TraktItemMenuAction.selectSource,
            child: Row(
              children: [
                Icon(
                  widget.hasBoundSource
                      ? Icons.edit_rounded
                      : Icons.link_rounded,
                  size: 18,
                  color: const Color(0xFF60A5FA),
                ),
                const SizedBox(width: 12),
                Text(
                  widget.hasBoundSource
                      ? (widget.item.type == 'movie'
                            ? 'Edit Source'
                            : 'Edit Sources')
                      : 'Select Source',
                ),
              ],
            ),
          ),
          if (widget.item.type == 'series')
            const PopupMenuItem(
              value: TraktItemMenuAction.searchPacks,
              child: Row(
                children: [
                  Icon(
                    Icons.inventory_2_outlined,
                    size: 18,
                    color: Color(0xFFFBBF24),
                  ),
                  SizedBox(width: 12),
                  Text('Search Season Packs'),
                ],
              ),
            ),
          const PopupMenuItem(
            value: TraktItemMenuAction.addToStremioTv,
            child: Row(
              children: [
                Icon(Icons.live_tv_rounded, size: 18, color: Color(0xFF22C55E)),
                SizedBox(width: 12),
                Text('Add to Stremio TV'),
              ],
            ),
          ),
        ],
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
                  shadows: [const Shadow(blurRadius: 8, color: Colors.black)],
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              _buildMetadataRow(theme, colorScheme),
              if (widget.item.genres != null &&
                  widget.item.genres!.isNotEmpty) ...[
                const SizedBox(height: 6),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: widget.item.genres!.take(3).map((genre) {
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.15),
                        ),
                      ),
                      child: Text(
                        genre,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.8),
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
          label: widget.item.type == 'series' ? 'Episodes' : 'Sources',
          color: const Color(0xFF8B5CF6),
          isHighlighted: _isFocused && _focusedButtonIndex == 0,
          onTap: widget.onSources,
        ),
        if (widget.showQuickPlay) ...[
          const SizedBox(width: 6),
          _buildActionButton(
            icon: Icons.play_arrow_rounded,
            label: 'Play',
            color: _traktRed,
            isHighlighted: _isFocused && _focusedButtonIndex == _quickPlayIndex,
            onTap: widget.onQuickPlay,
          ),
        ],
        if (widget.onMenuAction != null) ...[
          const SizedBox(width: 4),
          _buildOverflowMenu(),
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
                      shadows: [
                        const Shadow(blurRadius: 8, color: Colors.black),
                      ],
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  _buildMetadataRow(theme, colorScheme),
                  if (widget.item.genres != null &&
                      widget.item.genres!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: widget.item.genres!.take(3).map((genre) {
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.15),
                            ),
                          ),
                          child: Text(
                            genre,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.8),
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        );
                      }).toList(),
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
                label: widget.item.type == 'series' ? 'Episodes' : 'Sources',
                color: const Color(0xFF8B5CF6),
                isHighlighted: _isFocused && _focusedButtonIndex == 0,
                onTap: widget.onSources,
              ),
            ),
            if (widget.showQuickPlay) ...[
              const SizedBox(width: 8),
              Expanded(
                child: _buildActionButton(
                  icon: Icons.play_arrow_rounded,
                  label: 'Play',
                  color: _traktRed,
                  isHighlighted:
                      _isFocused && _focusedButtonIndex == _quickPlayIndex,
                  onTap: widget.onQuickPlay,
                ),
              ),
            ],
            if (widget.onMenuAction != null) ...[
              const SizedBox(width: 4),
              _buildOverflowMenu(),
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
        color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
        size: 32,
      ),
    );
  }

  Widget _buildPosterWithProgress(
    ColorScheme colorScheme, {
    required double width,
    required double height,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: width,
        height: height,
        child: _buildPoster(colorScheme),
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
          Icon(Icons.star_rounded, size: 14, color: const Color(0xFFFBBF24)),
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
        if (widget.progress != null && widget.progress! > 0) ...[
          const SizedBox(width: 8),
          Text(
            widget.progress! >= 100.0
                ? 'Watched'
                : '${widget.progress!.round()}%',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
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
    return GestureDetector(
      onTap: onTap,
      child: AnimatedScale(
        scale: isHighlighted ? 1.08 : 1.0,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isHighlighted ? color : Colors.black.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isHighlighted ? color : color.withValues(alpha: 0.6),
              width: 1,
            ),
            boxShadow: isHighlighted
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.4),
                      blurRadius: 12,
                      spreadRadius: 0,
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 15,
                color: isHighlighted
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.9),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    color: isHighlighted
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.9),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
            ],
          ),
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
  final bool isNextEpisode;
  final KeyEventResult Function(KeyEvent, {bool? isQuickPlayFocused})
  onKeyEvent;
  final void Function(TraktEpisodeMenuAction action)? onMenuAction;

  const _TraktEpisodeCard({
    required this.episode,
    this.showPosterUrl,
    this.focusNode,
    required this.onBrowse,
    required this.onQuickPlay,
    this.showQuickPlay = true,
    this.watchProgress,
    this.isNextEpisode = false,
    required this.onKeyEvent,
    this.onMenuAction,
  });

  @override
  State<_TraktEpisodeCard> createState() => _TraktEpisodeCardState();
}

class _TraktEpisodeCardState extends State<_TraktEpisodeCard> {
  bool _isFocused = false;
  int _focusedButtonIndex = 0;
  final GlobalKey<PopupMenuButtonState<TraktEpisodeMenuAction>> _menuKey =
      GlobalKey();

  int get _buttonCount {
    int count = 1; // Browse
    if (widget.showQuickPlay) count++;
    if (widget.onMenuAction != null) count++;
    return count;
  }

  int? get _quickPlayIndex => widget.showQuickPlay ? 1 : null;
  int? get _moreIndex => widget.onMenuAction != null ? _buttonCount - 1 : null;

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
        widget.onBrowse();
      } else if (_focusedButtonIndex == _quickPlayIndex) {
        widget.onQuickPlay();
      } else if (_focusedButtonIndex == _moreIndex) {
        _menuKey.currentState?.showButtonMenu();
      }
      return KeyEventResult.handled;
    }

    return widget.onKeyEvent(
      event,
      isQuickPlayFocused: _focusedButtonIndex == _quickPlayIndex,
    );
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
          _focusedButtonIndex = 0;
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
            color: _isFocused
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.white.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(12),
            border: widget.isNextEpisode && !_isFocused
                ? Border(
                    left: const BorderSide(color: _traktRed, width: 3),
                    top: BorderSide(
                      color: Colors.white.withValues(alpha: 0.06),
                    ),
                    right: BorderSide(
                      color: Colors.white.withValues(alpha: 0.06),
                    ),
                    bottom: BorderSide(
                      color: Colors.white.withValues(alpha: 0.06),
                    ),
                  )
                : Border.all(
                    color: _isFocused
                        ? Colors.white.withValues(alpha: 0.3)
                        : Colors.white.withValues(alpha: 0.06),
                    width: _isFocused ? 1.5 : 1,
                  ),
            boxShadow: _isFocused
                ? [
                    BoxShadow(
                      color: Colors.white.withValues(alpha: 0.08),
                      blurRadius: 16,
                      spreadRadius: 0,
                    ),
                  ]
                : null,
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

  Widget _buildEpisodeOverflowMenu() {
    final isWatched = (widget.watchProgress ?? 0) >= 100;
    final isHighlighted = _isFocused && _focusedButtonIndex == _moreIndex;

    return Container(
      decoration: isHighlighted
          ? BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.4),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.white.withValues(alpha: 0.15),
                  blurRadius: 12,
                  spreadRadius: 1,
                ),
              ],
            )
          : null,
      child: PopupMenuButton<TraktEpisodeMenuAction>(
        key: _menuKey,
        icon: Icon(
          Icons.more_vert,
          size: 20,
          color: isHighlighted
              ? Colors.white
              : Colors.white.withValues(alpha: 0.7),
        ),
        tooltip: 'More options',
        color: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        onSelected: (action) => widget.onMenuAction?.call(action),
        itemBuilder: (context) => [
          PopupMenuItem(
            value: isWatched
                ? TraktEpisodeMenuAction.markUnwatched
                : TraktEpisodeMenuAction.markWatched,
            child: Row(
              children: [
                Icon(
                  isWatched ? Icons.visibility_off : Icons.visibility,
                  size: 18,
                  color: const Color(0xFF34D399),
                ),
                const SizedBox(width: 12),
                Text(isWatched ? 'Mark as Unwatched' : 'Mark as Watched'),
              ],
            ),
          ),
          PopupMenuItem(
            value: TraktEpisodeMenuAction.rate,
            child: Row(
              children: [
                Icon(
                  Icons.star_rate_rounded,
                  size: 18,
                  color: const Color(0xFFFBBF24),
                ),
                const SizedBox(width: 12),
                const Text('Rate Episode'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHorizontalLayout(ThemeData theme, ColorScheme colorScheme) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Episode thumbnail with overlays
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 155,
            height: 88,
            child: Stack(
              fit: StackFit.expand,
              children: [
                _buildOttBackdropImage(
                  widget.episode.thumbnailUrl ?? widget.showPosterUrl,
                ),
                // "UP NEXT" badge top-left
                if (widget.isNextEpisode)
                  Positioned(
                    top: 4,
                    left: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: _traktRed.withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'UP NEXT',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                  ),
                // Progress bar bottom
                if (widget.watchProgress != null && widget.watchProgress! > 0)
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: (widget.watchProgress! / 100).clamp(
                          0.0,
                          1.0,
                        ),
                        child: Container(
                          height: 3,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                _traktRed,
                                _traktRed.withValues(alpha: 0.7),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
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
              if (widget.episode.overview != null &&
                  widget.episode.overview!.isNotEmpty) ...[
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
          label: 'Sources',
          color: const Color(0xFF8B5CF6),
          isHighlighted: _isFocused && _focusedButtonIndex == 0,
          onTap: widget.onBrowse,
        ),
        if (widget.showQuickPlay) ...[
          const SizedBox(width: 6),
          _buildActionButton(
            icon: Icons.play_arrow_rounded,
            label: 'Play',
            color: _traktRed,
            isHighlighted: _isFocused && _focusedButtonIndex == _quickPlayIndex,
            onTap: widget.onQuickPlay,
          ),
        ],
        if (widget.onMenuAction != null) ...[
          const SizedBox(width: 4),
          _buildEpisodeOverflowMenu(),
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
            // Thumbnail with overlays
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 120,
                height: 68,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _buildOttBackdropImage(
                      widget.episode.thumbnailUrl ?? widget.showPosterUrl,
                    ),
                    if (widget.isNextEpisode)
                      Positioned(
                        top: 4,
                        left: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: _traktRed.withValues(alpha: 0.85),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'UP NEXT',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ),
                      ),
                    if (widget.watchProgress != null &&
                        widget.watchProgress! > 0)
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: FractionallySizedBox(
                            widthFactor: (widget.watchProgress! / 100).clamp(
                              0.0,
                              1.0,
                            ),
                            child: Container(
                              height: 3,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    _traktRed,
                                    _traktRed.withValues(alpha: 0.7),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
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
        if (widget.episode.overview != null &&
            widget.episode.overview!.isNotEmpty) ...[
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
                label: 'Sources',
                color: const Color(0xFF8B5CF6),
                isHighlighted: _isFocused && _focusedButtonIndex == 0,
                onTap: widget.onBrowse,
              ),
            ),
            if (widget.showQuickPlay) ...[
              const SizedBox(width: 8),
              Expanded(
                child: _buildActionButton(
                  icon: Icons.play_arrow_rounded,
                  label: 'Play',
                  color: _traktRed,
                  isHighlighted:
                      _isFocused && _focusedButtonIndex == _quickPlayIndex,
                  onTap: widget.onQuickPlay,
                ),
              ),
            ],
            if (widget.onMenuAction != null) ...[
              const SizedBox(width: 4),
              _buildEpisodeOverflowMenu(),
            ],
          ],
        ),
      ],
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
        // Episode metadata — uses Wrap to handle small screens
        Wrap(
          spacing: 6,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
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
            if (widget.isNextEpisode)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF6366F1).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'Up Next',
                  style: TextStyle(
                    color: Color(0xFF818CF8),
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            if (ep.formattedAirDate != null)
              Text(
                ep.formattedAirDate!,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 11,
                ),
              ),
            if (ep.runtime != null)
              Text(
                '${ep.runtime} min',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 11,
                ),
              ),
            if (ep.rating != null)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.star_rounded,
                    size: 13,
                    color: Color(0xFFFBBF24),
                  ),
                  const SizedBox(width: 2),
                  Text(
                    ep.rating!.toStringAsFixed(1),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            if (progress != null && progress > 0)
              Text(
                progress >= 100.0 ? 'Watched' : '${progress.round()}%',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.45),
                  fontSize: 11,
                ),
              ),
          ],
        ),
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
    return GestureDetector(
      onTap: onTap,
      child: AnimatedScale(
        scale: isHighlighted ? 1.08 : 1.0,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isHighlighted ? color : Colors.black.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isHighlighted ? color : color.withValues(alpha: 0.6),
              width: 1,
            ),
            boxShadow: isHighlighted
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.4),
                      blurRadius: 12,
                      spreadRadius: 0,
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 15,
                color: isHighlighted
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.9),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    color: isHighlighted
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.9),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Select Source Button ─────────────────────────────────────────────────────

/// Compact button for the episode browser header to select/edit a series source.
class _SelectSourceButton extends StatefulWidget {
  final bool hasBoundSource;
  final int sourceCount;
  final VoidCallback onTap;
  final FocusNode? onLeftFocus;
  final VoidCallback? onUpArrow;
  final VoidCallback? onDownArrow;

  const _SelectSourceButton({
    required this.hasBoundSource,
    this.sourceCount = 0,
    required this.onTap,
    this.onLeftFocus,
    this.onUpArrow,
    this.onDownArrow,
  });

  @override
  State<_SelectSourceButton> createState() => _SelectSourceButtonState();
}

class _SelectSourceButtonState extends State<_SelectSourceButton> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'select-source-btn');
  bool _isFocused = false;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      onFocusChange: (focused) => setState(() => _isFocused = focused),
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.select ||
            event.logicalKey == LogicalKeyboardKey.enter) {
          widget.onTap();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowLeft &&
            widget.onLeftFocus != null) {
          widget.onLeftFocus!.requestFocus();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
          return KeyEventResult.handled; // rightmost button, block traversal
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
          widget.onUpArrow?.call();
          return widget.onUpArrow != null
              ? KeyEventResult.handled
              : KeyEventResult.ignored;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
          widget.onDownArrow?.call();
          return widget.onDownArrow != null
              ? KeyEventResult.handled
              : KeyEventResult.ignored;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: widget.hasBoundSource
                ? const Color(0xFF60A5FA).withValues(alpha: 0.15)
                : Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _isFocused
                  ? const Color(0xFF60A5FA)
                  : widget.hasBoundSource
                  ? const Color(0xFF60A5FA).withValues(alpha: 0.4)
                  : Colors.white.withValues(alpha: 0.15),
              width: _isFocused ? 2 : 1,
            ),
            boxShadow: _isFocused
                ? [
                    BoxShadow(
                      color: const Color(0xFF60A5FA).withValues(alpha: 0.3),
                      blurRadius: 8,
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.hasBoundSource
                    ? Icons.link_rounded
                    : Icons.link_off_rounded,
                size: 16,
                color: widget.hasBoundSource
                    ? const Color(0xFF60A5FA)
                    : Colors.white.withValues(alpha: 0.6),
              ),
              const SizedBox(width: 4),
              Text(
                widget.hasBoundSource
                    ? (widget.sourceCount > 1
                          ? 'Sources (${widget.sourceCount})'
                          : 'Source')
                    : 'Select Source',
                style: TextStyle(
                  color: widget.hasBoundSource
                      ? const Color(0xFF60A5FA)
                      : Colors.white.withValues(alpha: 0.6),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
