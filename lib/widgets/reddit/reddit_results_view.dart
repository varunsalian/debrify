import 'package:flutter/material.dart';
import '../../models/playlist_view_mode.dart';
import '../../services/reddit_service.dart';
import '../../services/reddit_embed_resolver_service.dart';
import '../../services/storage_service.dart';
import '../../services/video_player_launcher.dart';
import '../../screens/debrify_tv/widgets/tv_focus_scroll_wrapper.dart';
import 'reddit_filters.dart';
import 'reddit_video_card.dart';
import 'reddit_empty_state.dart';

/// Main view for Reddit video results, to be embedded in TorrentSearchScreen
class RedditResultsView extends StatefulWidget {
  final String searchQuery;
  final bool isTelevision;

  const RedditResultsView({
    super.key,
    required this.searchQuery,
    this.isTelevision = false,
  });

  @override
  State<RedditResultsView> createState() => RedditResultsViewState();
}

class RedditResultsViewState extends State<RedditResultsView> {
  final ScrollController _scrollController = ScrollController();
  final List<RedditVideoPost> _posts = [];

  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  String? _afterCursor;
  String? _errorMessage;

  // Filter state
  String? _selectedSubreddit;
  RedditSort _selectedSort = RedditSort.relevance;
  RedditTimeFilter _selectedTimeFilter = RedditTimeFilter.all;
  bool _allowNsfw = false;
  bool _settingsLoaded = false;

  // Focus nodes for DPAD
  final FocusNode _subredditFilterFocusNode = FocusNode(debugLabel: 'reddit-subreddit-filter');
  final FocusNode _sortFilterFocusNode = FocusNode(debugLabel: 'reddit-sort-filter');
  final FocusNode _timeFilterFocusNode = FocusNode(debugLabel: 'reddit-time-filter');
  final List<FocusNode> _cardFocusNodes = [];

  String _lastSearchQuery = '';

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final allowNsfw = await StorageService.getRedditAllowNsfw();
    final defaultSubreddit = await StorageService.getRedditDefaultSubreddit();

    if (!mounted) return;

    setState(() {
      _allowNsfw = allowNsfw;
      _settingsLoaded = true;
      if (defaultSubreddit != null && defaultSubreddit.isNotEmpty) {
        _selectedSubreddit = defaultSubreddit;
      }
    });

    // If we have a default subreddit set, load its content
    if (_selectedSubreddit != null) {
      _performSearch();
    }
  }

  @override
  void didUpdateWidget(RedditResultsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Search when query changes
    if (widget.searchQuery != _lastSearchQuery) {
      _lastSearchQuery = widget.searchQuery;
      _performSearch();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _subredditFilterFocusNode.dispose();
    _sortFilterFocusNode.dispose();
    _timeFilterFocusNode.dispose();
    for (final node in _cardFocusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 300) {
      _loadMore();
    }
  }

  bool get _isSearching => widget.searchQuery.isNotEmpty;

  bool get _canLoad => _isSearching || _selectedSubreddit != null;

  Future<void> _performSearch() async {
    debugPrint('RedditResultsView: _performSearch called, _canLoad=$_canLoad, _isSearching=$_isSearching, subreddit=$_selectedSubreddit');

    if (!_canLoad) {
      setState(() {
        _posts.clear();
        _errorMessage = null;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _posts.clear();
      _afterCursor = null;
      _hasMore = true;
    });

    // Dispose old focus nodes
    for (final node in _cardFocusNodes) {
      node.dispose();
    }
    _cardFocusNodes.clear();

    try {
      RedditListingResult result;

      if (_isSearching && _selectedSubreddit == null) {
        // Global search
        result = await RedditService.searchAllVideos(
          query: widget.searchQuery,
          sort: _selectedSort,
          timeFilter: _selectedTimeFilter,
          limit: 100,
          allowNsfw: _allowNsfw,
        );
      } else if (_isSearching && _selectedSubreddit != null) {
        // Search within subreddit
        result = await RedditService.searchSubredditVideos(
          subreddit: _selectedSubreddit!,
          query: widget.searchQuery,
          sort: _selectedSort,
          timeFilter: _selectedTimeFilter,
          limit: 100,
          allowNsfw: _allowNsfw,
        );
      } else {
        // Browse subreddit
        result = await RedditService.getSubredditVideos(
          subreddit: _selectedSubreddit!,
          sort: _selectedSort == RedditSort.relevance ? RedditSort.hot : _selectedSort,
          timeFilter: _selectedTimeFilter,
          limit: 100,
          allowNsfw: _allowNsfw,
        );
      }

      if (!mounted) return;

      debugPrint('RedditResultsView: Got ${result.posts.length} posts, hasMore=${result.hasMore}');

      // Create focus nodes for cards
      for (int i = 0; i < result.posts.length; i++) {
        _cardFocusNodes.add(FocusNode(debugLabel: 'reddit-card-$i'));
      }

      setState(() {
        _isLoading = false;
        _posts.addAll(result.posts);
        _afterCursor = result.after;
        _hasMore = result.hasMore;
      });
    } catch (e) {
      if (!mounted) return;
      debugPrint('RedditResultsView: Error - $e');
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore || !_canLoad) return;

    setState(() => _isLoadingMore = true);

    try {
      RedditListingResult result;

      if (_isSearching && _selectedSubreddit == null) {
        result = await RedditService.searchAllVideos(
          query: widget.searchQuery,
          sort: _selectedSort,
          timeFilter: _selectedTimeFilter,
          limit: 100,
          after: _afterCursor,
          allowNsfw: _allowNsfw,
        );
      } else if (_isSearching && _selectedSubreddit != null) {
        result = await RedditService.searchSubredditVideos(
          subreddit: _selectedSubreddit!,
          query: widget.searchQuery,
          sort: _selectedSort,
          timeFilter: _selectedTimeFilter,
          limit: 100,
          after: _afterCursor,
          allowNsfw: _allowNsfw,
        );
      } else {
        result = await RedditService.getSubredditVideos(
          subreddit: _selectedSubreddit!,
          sort: _selectedSort == RedditSort.relevance ? RedditSort.hot : _selectedSort,
          timeFilter: _selectedTimeFilter,
          limit: 100,
          after: _afterCursor,
          allowNsfw: _allowNsfw,
        );
      }

      if (!mounted) return;

      // Create focus nodes for new cards
      final startIndex = _cardFocusNodes.length;
      for (int i = 0; i < result.posts.length; i++) {
        _cardFocusNodes.add(FocusNode(debugLabel: 'reddit-card-${startIndex + i}'));
      }

      setState(() {
        _isLoadingMore = false;
        _posts.addAll(result.posts);
        _afterCursor = result.after;
        _hasMore = result.hasMore;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoadingMore = false);
    }
  }

  void _onSubredditChanged(String? subreddit) {
    setState(() {
      _selectedSubreddit = subreddit;
      // When browsing subreddit without search, default to Hot
      if (!_isSearching && subreddit != null && _selectedSort == RedditSort.relevance) {
        _selectedSort = RedditSort.hot;
      }
    });
    _performSearch();
  }

  void _onSortChanged(RedditSort sort) {
    setState(() => _selectedSort = sort);
    _performSearch();
  }

  void _onTimeFilterChanged(RedditTimeFilter filter) {
    setState(() => _selectedTimeFilter = filter);
    _performSearch();
  }

  Future<void> _playVideo(RedditVideoPost post) async {
    String? playUrl = post.playableUrl;

    // Handle Redgifs posts - fetch actual video URL
    if (playUrl == null && post.isRedgifs) {
      // Show loading indicator
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 12),
                Text('Loading video...'),
              ],
            ),
            duration: Duration(seconds: 2),
          ),
        );
      }

      playUrl = await RedditEmbedResolverService.resolveVideoUrl(post.redgifsUrl!);

      if (!mounted) return;

      // Hide the loading snackbar
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
    }

    if (playUrl == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No playable video found')),
        );
      }
      return;
    }

    await VideoPlayerLauncher.push(
      context,
      VideoPlayerLaunchArgs(
        videoUrl: playUrl,
        title: post.title,
        subtitle: 'r/${post.subreddit} • u/${post.author}',
        viewMode: PlaylistViewMode.sorted,
      ),
    );
  }

  /// Focus the first filter (for DPAD navigation from search input)
  void focusFirstFilter() {
    _subredditFilterFocusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Filters bar (always visible when Reddit is selected)
        RedditFiltersBar(
            selectedSubreddit: _selectedSubreddit,
            selectedSort: _selectedSort,
            selectedTimeFilter: _selectedTimeFilter,
            isSearching: _isSearching,
            resultCount: _posts.length,
            onSubredditChanged: _onSubredditChanged,
            onSortChanged: _onSortChanged,
            onTimeFilterChanged: _onTimeFilterChanged,
            subredditFocusNode: _subredditFilterFocusNode,
            sortFocusNode: _sortFilterFocusNode,
            timeFocusNode: _timeFilterFocusNode,
          ),

        // Content
        Expanded(
          child: _buildContent(),
        ),
      ],
    );
  }

  Widget _buildContent() {
    // Empty state when nothing to show
    if (!_canLoad && _posts.isEmpty && !_isLoading) {
      return const RedditEmptyState();
    }

    // Loading
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    // Error
    if (_errorMessage != null && _posts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              _errorMessage!,
              style: Theme.of(context).textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _performSearch,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    // No results
    if (_posts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.video_library_outlined,
              size: 64,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              'No videos found',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              _isSearching
                  ? 'Try a different search term'
                  : 'Try a different subreddit',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    // Results list
    return TvFocusScrollWrapper(
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.only(top: 8, bottom: 16),
        itemCount: _posts.length + (_hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= _posts.length) {
            return _buildLoadingIndicator();
          }

          return RedditVideoCard(
            post: _posts[index],
            onTap: () => _playVideo(_posts[index]),
            focusNode: index < _cardFocusNodes.length ? _cardFocusNodes[index] : null,
          );
        },
      ),
    );
  }

  Widget _buildLoadingIndicator() {
    return Container(
      padding: const EdgeInsets.all(16),
      alignment: Alignment.center,
      child: _isLoadingMore
          ? const CircularProgressIndicator()
          : const SizedBox.shrink(),
    );
  }
}
