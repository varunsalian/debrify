import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/stremio_addon.dart';
import '../../models/advanced_search_selection.dart';
import '../../services/trakt/trakt_service.dart';
import '../../services/trakt/trakt_item_transformer.dart';
import '../../services/trakt/trakt_episode_model.dart';
import 'trakt_menu_helpers.dart';
import '../catalog_item_tile.dart';
import '../home/home_theme.dart';
import '../episode_tile.dart';
import '../../services/tvmaze_service.dart';
import '../../services/local_bound_source_service.dart';
import '../../services/series_source_service.dart';
import '../../services/storage_service.dart';
import '../../screens/catalog_item_detail_screen.dart';
import '../../screens/debrid_downloads_screen.dart';
import '../../screens/torbox/torbox_downloads_screen.dart';
import '../../screens/debrify_tv/widgets/tv_focus_scroll_wrapper.dart';
import '../../screens/stremio_tv/widgets/stremio_tv_catalog_picker_dialog.dart';
import '../add_source_picker_dialog.dart';

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

  /// Called when user enters episode drill-down (opens a series).
  final VoidCallback? onEpisodeModeEntered;

  /// Called when user wants to select a torrent source for a series.
  /// Parent should trigger series probing search in select-source mode.
  final void Function(StremioMeta show)? onSelectSource;

  /// Called when user picks "Keyword Search" from the add-source picker.
  final void Function(StremioMeta show)? onKeywordSelectSource;

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
    this.onEpisodeModeEntered,
    this.onSelectSource,
    this.onKeywordSelectSource,
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

        final listId = _selectedLikedList!['ids']?['trakt']?.toString();
        final listSlug = _selectedLikedList!['ids']?['slug'] as String?;
        final ownerSlug =
            (_selectedLikedList!['user']
                    as Map<String, dynamic>?)?['ids']?['slug']
                as String?;
        final owner =
            (_selectedLikedList!['user'] as Map<String, dynamic>?)?['username']
                as String?;
        final hasListId = listId != null && listId.isNotEmpty;
        final hasOwnerPath =
            listSlug != null &&
            listSlug.isNotEmpty &&
            ((ownerSlug != null && ownerSlug.isNotEmpty) ||
                (owner != null && owner.isNotEmpty));
        if (!hasListId && !hasOwnerPath) {
          if (!mounted) return;
          setState(() {
            _isLoading = false;
            _errorMessage = 'Invalid liked list identifier';
          });
          return;
        }
        rawItems = await _traktService.fetchLikedListItemsFromList(
          _selectedLikedList!,
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

  /// Opens the cinematic detail screen (Play / Sources / quick actions),
  /// matching the catalog grid. Sources/Episodes and Play defer to the
  /// existing Trakt handlers via the detail screen's buttons.
  Future<void> _openItemDetail(StremioMeta item) async {
    final hasBoundSource =
        _boundSources.containsKey(item.effectiveImdbId ?? item.id);

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CatalogItemDetailScreen(
          item: item,
          isTelevision: widget.isTelevision,
          showQuickPlay: widget.showQuickPlay,
          hasBoundSource: hasBoundSource,
          traktMenuOptions: _buildTraktQuickActions(item, hasBoundSource),
          onTraktAction: (action) {
            // These actions take the user away from / replace the host
            // screen (pack search, source picker, Stremio TV, random
            // episode). The detail screen is pushed on top, so close it
            // first or the result happens invisibly behind it.
            const leaves = {
              TraktItemMenuAction.searchPacks,
              TraktItemMenuAction.selectSource,
              TraktItemMenuAction.addToStremioTv,
              TraktItemMenuAction.playRandomEpisode,
            };
            if (leaves.contains(action) && Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            }
            _onMenuAction(item, action);
          },
          onPlay: () => _onQuickPlay(item),
          // The shared detail screen no longer self-pops on Browse; preserve
          // the prior pop-then-callback behaviour here (Trakt episode mode is
          // still inline — migrated in a later slice).
          onBrowse: () {
            Navigator.of(context).pop();
            _onItemTap(item);
          },
        ),
      ),
    );
  }

  /// Context-aware quick actions for the detail screen: shows Remove-from-X
  /// when viewing that Trakt list (watchlist/collection/ratings/custom list/
  /// continue-watching), Add-to-X otherwise. App/Stremio actions come first,
  /// then the Trakt-syncing ones (badged TRAKT in the UI).
  List<TraktMenuOption> _buildTraktQuickActions(
    StremioMeta item,
    bool hasBoundSource,
  ) {
    final lt = _selectedListType;
    final id = item.effectiveImdbId ?? item.id;
    final isSeries = item.type == 'series';
    final isMovie = item.type == 'movie';
    final pct = (_selectedContentType == TraktContentType.movies &&
            _progressLoaded)
        ? _watchProgress[id]
        : null;
    final isWatched = (pct ?? 0) >= 100 ||
        (pct == null &&
            (lt == TraktListType.progress || lt == TraktListType.history));

    return [
      // ── App / Stremio (no TRAKT badge) ──
      if (isSeries || isMovie)
        TraktMenuOption(
          action: TraktItemMenuAction.selectSource,
          icon: hasBoundSource ? Icons.edit_rounded : Icons.link_rounded,
          color: const Color(0xFF60A5FA),
          label: hasBoundSource
              ? (isMovie ? 'Edit Source' : 'Edit Sources')
              : 'Select Source',
          caption: hasBoundSource ? 'Edit Source' : 'Select Source',
        ),
      const TraktMenuOption(
        action: TraktItemMenuAction.addToStremioTv,
        icon: Icons.live_tv_rounded,
        color: Color(0xFF22C55E),
        label: 'Add to Stremio TV',
        caption: 'Stremio TV',
      ),
      if (isSeries)
        const TraktMenuOption(
          action: TraktItemMenuAction.searchPacks,
          icon: Icons.inventory_2_rounded,
          color: Color(0xFFFBBF24),
          label: 'Search Season Packs',
          caption: 'Packs',
        ),

      // ── Trakt-syncing (badged TRAKT) ──
      if (_isAuthenticated) ...[
        if (lt == TraktListType.watchlist)
          const TraktMenuOption(
            action: TraktItemMenuAction.removeFromWatchlist,
            icon: Icons.bookmark_remove_rounded,
            color: Color(0xFFFBBF24),
            label: 'Remove from Trakt Watchlist',
            caption: 'Watchlist',
            isTrakt: true,
          )
        else
          const TraktMenuOption(
            action: TraktItemMenuAction.addToWatchlist,
            icon: Icons.bookmark_add_rounded,
            color: Color(0xFFFBBF24),
            label: 'Add to Trakt Watchlist',
            caption: 'Watchlist',
            isTrakt: true,
          ),
        if (lt == TraktListType.collection)
          const TraktMenuOption(
            action: TraktItemMenuAction.removeFromCollection,
            icon: Icons.library_add_check_rounded,
            color: Color(0xFF60A5FA),
            label: 'Remove from Trakt Collection',
            caption: 'Collection',
            isTrakt: true,
          )
        else
          const TraktMenuOption(
            action: TraktItemMenuAction.addToCollection,
            icon: Icons.video_library_rounded,
            color: Color(0xFF60A5FA),
            label: 'Add to Trakt Collection',
            caption: 'Collection',
            isTrakt: true,
          ),
        if (isWatched)
          const TraktMenuOption(
            action: TraktItemMenuAction.markUnwatched,
            icon: Icons.visibility_off_rounded,
            color: Color(0xFF34D399),
            label: 'Mark as Unwatched on Trakt',
            caption: 'Unwatch',
            isTrakt: true,
          )
        else
          const TraktMenuOption(
            action: TraktItemMenuAction.markWatched,
            icon: Icons.check_circle_rounded,
            color: Color(0xFF34D399),
            label: 'Mark as Watched on Trakt',
            caption: 'Watched',
            isTrakt: true,
          ),
        if (lt == TraktListType.ratings)
          const TraktMenuOption(
            action: TraktItemMenuAction.removeRating,
            icon: Icons.star_border_rounded,
            color: Color(0xFFFBBF24),
            label: 'Remove Trakt Rating',
            caption: 'Rating',
            isTrakt: true,
          )
        else
          const TraktMenuOption(
            action: TraktItemMenuAction.rate,
            icon: Icons.star_rounded,
            color: Color(0xFFFBBF24),
            label: 'Rate on Trakt',
            caption: 'Rate',
            isTrakt: true,
          ),
        if (lt == TraktListType.customList)
          const TraktMenuOption(
            action: TraktItemMenuAction.removeFromList,
            icon: Icons.playlist_remove_rounded,
            color: Color(0xFFEC4899),
            label: 'Remove from Trakt List',
            caption: 'List',
            isTrakt: true,
          )
        else
          const TraktMenuOption(
            action: TraktItemMenuAction.addToList,
            icon: Icons.playlist_add_rounded,
            color: Color(0xFFEC4899),
            label: 'Add to Trakt List…',
            caption: 'Add to List',
            isTrakt: true,
          ),
        if (lt == TraktListType.progress)
          const TraktMenuOption(
            action: TraktItemMenuAction.removeFromPlayback,
            icon: Icons.delete_outline_rounded,
            color: Color(0xFFEF4444),
            label: 'Remove from Continue Watching',
            caption: 'Remove',
            isTrakt: true,
          ),
      ],
    ];
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
                                _showAddSourcePicker(show, imdbId);
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
                                  if (dialogContext.mounted) {
                                    Navigator.of(dialogContext).pop();
                                  }
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
      case SeriesSource.localService:
        serviceColor = const Color(0xFF60A5FA);
        serviceLabel = 'Local';
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

    final isMovie = item.type == 'movie';
    final supportsLocal = isMovie || item.type == 'series';
    if (!rdEnabled && !torboxEnabled && !supportsLocal) {
      widget.onSelectSource?.call(item);
      return;
    }

    await showAddSourcePickerDialog(
      context,
      onTorrentSearch: () => widget.onSelectSource?.call(item),
      onKeywordSearch: widget.onKeywordSelectSource != null
          ? () => widget.onKeywordSelectSource!.call(item)
          : null,
      onLocal: supportsLocal && !LocalBoundSourceService.isLocalBindingDisabled
          ? () => _pickAndSaveLocalSource(item, imdbId)
          : null,
      localDisabledReason: supportsLocal
          ? LocalBoundSourceService.localDisabledReason
          : null,
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

  Future<void> _pickAndSaveLocalSource(StremioMeta item, String imdbId) async {
    final SeriesSource? source;
    if (item.type == 'series') {
      source = await LocalBoundSourceService.pickSeriesSource(
        context,
        title: item.name,
      );
    } else {
      source = await LocalBoundSourceService.pickMovieSource(
        context,
        title: item.name,
        year: item.year,
      );
    }
    if (source == null) return;

    if (item.type == 'series') {
      await SeriesSourceService.addSource(imdbId, source);
    } else {
      await SeriesSourceService.setSources(imdbId, [source]);
    }
    final updated = await SeriesSourceService.getSources(imdbId);
    if (!mounted) return;
    setState(() => _boundSources[imdbId] = updated);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Local source set: ${source.torrentName}'),
        backgroundColor: const Color(0xFF10B981),
      ),
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
    // Hide the host bar as soon as the loading state is shown. Every
    // terminal failure path below restores it via onEpisodeModeExited so
    // a failed/empty entry can never leave the bar permanently hidden.
    widget.onEpisodeModeEntered?.call();

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
        widget.onEpisodeModeExited?.call();
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

      // Scroll to (and focus) the requested episode once its tile is
      // actually built. Robust against variable EpisodeTile height, lazy
      // ListView building, and the host bar-hide relayout.
      final scrollSeason = _seasons.firstWhere(
        (s) => s.number == targetSeason,
        orElse: () => _seasons.first,
      );
      final scrollEpIndex = targetEpisodeNumber != null
          ? scrollSeason.episodes.indexWhere(
              (e) => e.number == targetEpisodeNumber,
            )
          : -1;
      _scrollFocusEpisode(
        scrollEpIndex < 0 ? 0 : scrollEpIndex,
        scrollSeason.episodes.length,
        generation,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingEpisodes = false;
        _episodeErrorMessage = 'Failed to load seasons: $e';
      });
      widget.onEpisodeModeExited?.call();
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
        if (merged[entry.key] == 100.0) {
          continue; // Don't downgrade fully watched
        }
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

  /// Robustly brings episode [epIndex] into view.
  ///
  /// The episode list is a lazy ListView with variable-height tiles, so a
  /// single proportional jump is unreliable — an off-screen target tile
  /// isn't built, leaving its FocusNode contextless and the jump estimate
  /// wrong. This re-reads scroll metrics each frame and converges (the
  /// builder's maxScrollExtent grows as more rows lay out). Once the tile
  /// exists: on TV focus it (the tile self-centers via
  /// EpisodeTile.onFocusChange and shows the focus border for the remote);
  /// on mobile/desktop just scroll it into view without focusing — an
  /// auto-applied golden focus border there looks out of place. Bounded so
  /// it can never spin.
  void _scrollFocusEpisode(int epIndex, int episodeCount, int generation) {
    const int maxAttempts = 16;
    void attempt(int n) {
      if (!mounted || generation != _episodeModeGeneration) return;
      if (epIndex < 0 || epIndex >= _episodeFocusNodes.length) return;
      final node = _episodeFocusNodes[epIndex];
      if (node.context != null) {
        if (widget.isTelevision) {
          // Tile self-scrolls into view via EpisodeTile.onFocusChange.
          node.requestFocus();
        } else {
          Scrollable.ensureVisible(
            node.context!,
            alignment: 0.5,
            alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
          );
        }
        return;
      }
      if (n >= maxAttempts || !_episodeScrollController.hasClients) {
        if (widget.isTelevision) node.requestFocus(); // best effort, then stop
        return;
      }
      final pos = _episodeScrollController.position;
      final ratio = episodeCount > 1 ? epIndex / (episodeCount - 1) : 0.0;
      final target = (pos.maxScrollExtent * ratio).clamp(
        0.0,
        pos.maxScrollExtent,
      );
      if ((target - pos.pixels).abs() > 1.0) {
        _episodeScrollController.jumpTo(target);
      }
      WidgetsBinding.instance.addPostFrameCallback((_) => attempt(n + 1));
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => attempt(0));
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
            color: Colors.white.withValues(alpha: hasFocus ? 0.12 : 0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: hasFocus
                  ? HomeTheme.focusGold
                  : Colors.white.withValues(alpha: 0.10),
              width: hasFocus ? 2.0 : 1.0,
            ),
            boxShadow: hasFocus
                ? [
                    BoxShadow(
                      color: HomeTheme.focusGold.withValues(alpha: 0.32),
                      blurRadius: 14,
                      spreadRadius: 0,
                    ),
                  ]
                : null,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              focusNode: focusNode,
              focusColor: Colors.transparent,
              value: value,
              isExpanded: true,
              isDense: true,
              borderRadius: BorderRadius.circular(12),
              dropdownColor: const Color(0xFF14141C),
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

    final w = MediaQuery.of(context).size.width;
    final crossAxisCount =
        catalogGridColumnsFor(w, isTelevision: widget.isTelevision);
    final hPadding = w >= 900 ? 40.0 : 20.0;
    final showProgress =
        _selectedContentType == TraktContentType.movies && _progressLoaded;

    return TvFocusScrollWrapper(
      child: GridView.builder(
        controller: _scrollController,
        padding: EdgeInsets.fromLTRB(hPadding, 12, hPadding, 24),
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          // Pure poster aspect (2:3) — title appears inside on focus.
          childAspectRatio: 0.667,
          mainAxisSpacing: 24,
          crossAxisSpacing: 18,
        ),
        itemCount: _filteredItems.length,
        itemBuilder: (context, index) {
          final item = _filteredItems[index];
          final pct =
              showProgress ? _watchProgress[item.effectiveImdbId ?? item.id] : null;
          return CatalogItemTile(
            item: item,
            isTelevision: widget.isTelevision,
            focusNode: index < _cardFocusNodes.length
                ? _cardFocusNodes[index]
                : null,
            hasBoundSource: _boundSources.containsKey(
              item.effectiveImdbId ?? item.id,
            ),
            progress: (pct != null && pct > 0) ? pct / 100.0 : null,
            onOpen: () => _openItemDetail(item),
            onLongPress: widget.showQuickPlay
                ? () => _onQuickPlay(item)
                : null,
          );
        },
      ),
    );
  }

  Widget _buildEpisodeFiltersBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.08),
            width: 0.5,
          ),
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
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _backButtonFocusNode.hasFocus
                      ? Colors.white.withValues(alpha: 0.16)
                      : Colors.white.withValues(alpha: 0.06),
                  border: Border.all(
                    color: _backButtonFocusNode.hasFocus
                        ? HomeTheme.focusGold
                        : Colors.white.withValues(alpha: 0.14),
                    width: _backButtonFocusNode.hasFocus ? 2 : 1,
                  ),
                ),
                child: IconButton(
                  padding: EdgeInsets.zero,
                  iconSize: 20,
                  color: Colors.white,
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

    final w = MediaQuery.of(context).size.width;
    final hPad = w >= 900 ? 40.0 : 16.0;

    return TvFocusScrollWrapper(
      child: ListView.builder(
        controller: _episodeScrollController,
        padding: EdgeInsets.fromLTRB(hPad, 10, hPad, 28),
        itemCount: currentSeason.episodes.length,
        itemBuilder: (context, index) {
          final episode = currentSeason.episodes[index];
          return Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: EpisodeTile(
              episode: episode,
              showImageUrl: _selectedShow!.poster,
              isTelevision: widget.isTelevision,
              showQuickPlay: widget.showQuickPlay,
              focusNode: index < _episodeFocusNodes.length
                  ? _episodeFocusNodes[index]
                  : null,
              watchProgress: _episodeWatchProgress[
                  '${episode.season}-${episode.number}'],
              isNext: _nextEpisode != null &&
                  _nextEpisode!.season == episode.season &&
                  _nextEpisode!.episode == episode.number,
              onPlay: () => _onEpisodeQuickPlay(episode),
              onSources: () => _onEpisodeTap(episode),
              onMenuAction: (action) =>
                  _onEpisodeMenuAction(episode, action),
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
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: widget.hasBoundSource
                ? HomeTheme.focusGold.withValues(alpha: 0.14)
                : Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _isFocused
                  ? HomeTheme.focusGold
                  : widget.hasBoundSource
                  ? HomeTheme.focusGold.withValues(alpha: 0.45)
                  : Colors.white.withValues(alpha: 0.14),
              width: _isFocused ? 2 : 1,
            ),
            boxShadow: _isFocused
                ? [
                    BoxShadow(
                      color: HomeTheme.focusGold.withValues(alpha: 0.32),
                      blurRadius: 12,
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
                    ? HomeTheme.focusGold
                    : Colors.white.withValues(alpha: 0.85),
              ),
              const SizedBox(width: 6),
              Text(
                widget.hasBoundSource
                    ? (widget.sourceCount > 1
                          ? 'Sources (${widget.sourceCount})'
                          : 'Source')
                    : 'Select Source',
                style: TextStyle(
                  color: widget.hasBoundSource
                      ? HomeTheme.focusGold
                      : Colors.white.withValues(alpha: 0.85),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
