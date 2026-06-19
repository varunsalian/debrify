import 'package:flutter/material.dart';
import '../../models/playlist_view_mode.dart';
import '../../services/lemmy_service.dart';
import '../../services/youtube_service.dart';
import '../../services/reddit_embed_resolver_service.dart';
import '../../services/storage_service.dart';
import '../../services/video_player_launcher.dart';
import '../../services/download_service.dart';
import '../../screens/debrify_tv/widgets/tv_focus_scroll_wrapper.dart';
import 'lemmy_filters.dart';
import 'lemmy_video_card.dart';
import 'lemmy_empty_state.dart';

/// Main view for Lemmy video results, to be embedded in TorrentSearchScreen
class LemmyResultsView extends StatefulWidget {
  final String searchQuery;
  final bool isTelevision;

  const LemmyResultsView({
    super.key,
    required this.searchQuery,
    this.isTelevision = false,
  });

  @override
  State<LemmyResultsView> createState() => LemmyResultsViewState();
}

class LemmyResultsViewState extends State<LemmyResultsView> {
  final ScrollController _scrollController = ScrollController();
  final List<LemmyVideoPost> _posts = [];

  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  String? _afterCursor;
  String? _errorMessage;

  // Filter state
  String? _selectedCommunity;
  LemmySort _selectedSort = LemmySort.active;
  LemmyTimeFilter _selectedTimeFilter = LemmyTimeFilter.all;
  bool _allowNsfw = false;

  bool _isRandomLoading = false;

  // Focus nodes for DPAD
  final FocusNode _communityFilterFocusNode = FocusNode(debugLabel: 'lemmy-community-filter');
  final FocusNode _sortFilterFocusNode = FocusNode(debugLabel: 'lemmy-sort-filter');
  final FocusNode _timeFilterFocusNode = FocusNode(debugLabel: 'lemmy-time-filter');
  final FocusNode _randomButtonFocusNode = FocusNode(debugLabel: 'lemmy-random-button');
  final List<FocusNode> _cardFocusNodes = [];

  String _lastSearchQuery = '';
  int _searchGeneration = 0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final allowNsfw = await StorageService.getLemmyAllowNsfw();
    final instance = await StorageService.getLemmyInstance();
    final defaultCommunity = await StorageService.getLemmyDefaultCommunity();

    LemmyService.instanceBaseUrl = instance;

    if (!mounted) return;

    setState(() {
      _allowNsfw = allowNsfw;
      if (defaultCommunity != null && defaultCommunity.isNotEmpty) {
        _selectedCommunity = defaultCommunity;
      }
    });

    // Browse the federated feed (or default community) immediately so the
    // view isn't empty on first open, matching Reddit's behaviour.
    _performSearch();
  }

  @override
  void didUpdateWidget(LemmyResultsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.searchQuery != _lastSearchQuery) {
      _lastSearchQuery = widget.searchQuery;
      _performSearch();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _communityFilterFocusNode.dispose();
    _sortFilterFocusNode.dispose();
    _timeFilterFocusNode.dispose();
    _randomButtonFocusNode.dispose();
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

  Future<LemmyListingResult> _fetch({String? after}) {
    if (_isSearching) {
      return LemmyService.fetchSearchVideos(
        query: widget.searchQuery,
        community: _selectedCommunity,
        sort: _selectedSort,
        timeFilter: _selectedTimeFilter,
        after: after,
        allowNsfw: _allowNsfw,
      );
    }
    return LemmyService.fetchCommunityVideos(
      community: _selectedCommunity,
      sort: _selectedSort,
      timeFilter: _selectedTimeFilter,
      after: after,
      allowNsfw: _allowNsfw,
    );
  }

  Future<void> _performSearch() async {
    final generation = ++_searchGeneration;

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
      final result = await _fetch();

      if (!mounted || generation != _searchGeneration) return;

      debugPrint('LemmyResultsView: Got ${result.posts.length} posts, hasMore=${result.hasMore}');

      for (int i = 0; i < result.posts.length; i++) {
        _cardFocusNodes.add(FocusNode(debugLabel: 'lemmy-card-$i'));
      }

      setState(() {
        _isLoading = false;
        _posts.addAll(result.posts);
        _afterCursor = result.after;
        _hasMore = result.hasMore;
      });
    } catch (e) {
      if (!mounted || generation != _searchGeneration) return;
      debugPrint('LemmyResultsView: Error - $e');
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore) return;

    final generation = _searchGeneration;

    setState(() => _isLoadingMore = true);

    try {
      final result = await _fetch(after: _afterCursor);

      if (!mounted || generation != _searchGeneration) return;

      final startIndex = _cardFocusNodes.length;
      for (int i = 0; i < result.posts.length; i++) {
        _cardFocusNodes.add(FocusNode(debugLabel: 'lemmy-card-${startIndex + i}'));
      }

      setState(() {
        _isLoadingMore = false;
        _posts.addAll(result.posts);
        _afterCursor = result.after;
        _hasMore = result.hasMore;
      });
    } catch (e) {
      if (!mounted || generation != _searchGeneration) return;
      setState(() => _isLoadingMore = false);
    }
  }

  void _onCommunityChanged(String? community) {
    setState(() => _selectedCommunity = community);
    _performSearch();
  }

  void _onSortChanged(LemmySort sort) {
    setState(() => _selectedSort = sort);
    _performSearch();
  }

  void _onTimeFilterChanged(LemmyTimeFilter filter) {
    setState(() => _selectedTimeFilter = filter);
    _performSearch();
  }

  Future<void> _playRandomVideo() async {
    if (_isRandomLoading || _selectedCommunity == null) return;

    setState(() => _isRandomLoading = true);

    try {
      final post = await LemmyService.getRandomVideo(
        community: _selectedCommunity,
        allowNsfw: _allowNsfw,
      );

      if (!mounted) return;

      if (post == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No random video found — try again')),
        );
        return;
      }

      await _playVideo(post);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Random failed: ${e.toString().replaceAll('Exception: ', '')}')),
      );
    } finally {
      if (mounted) setState(() => _isRandomLoading = false);
    }
  }

  /// Resolve a YouTube post's streams on-device, showing a loading snackbar.
  Future<YoutubeResolvedStreams?> _resolveYouTube(LemmyVideoPost post) async {
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
          duration: Duration(seconds: 4),
        ),
      );
    }

    YoutubeResolvedStreams? streams;
    try {
      streams = await YoutubeService.resolveStreams(post.youtubeId!);
    } catch (_) {
      streams = null;
    }

    if (mounted) ScaffoldMessenger.of(context).hideCurrentSnackBar();
    return streams;
  }

  Future<void> _playVideo(LemmyVideoPost post) async {
    String? playUrl = post.playableUrl;

    // Handle Redgifs posts - fetch actual video URL
    if (playUrl == null && post.isRedgifs) {
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
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
    }

    // Handle YouTube posts - resolve a playable stream on-device
    String? audioUrl;
    String? fallbackUrl;
    if (playUrl == null && post.isYouTube) {
      final streams = await _resolveYouTube(post);
      playUrl = streams?.playUrl;
      audioUrl = streams?.audioUrl;
      fallbackUrl = streams?.downloadUrl;
      if (!mounted) return;
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
        audioUrl: audioUrl,
        fallbackUrl: fallbackUrl,
        title: post.title,
        subtitle: 'c/${post.community} • u/${post.author}',
        viewMode: PlaylistViewMode.sorted,
      ),
    );
  }

  Future<void> _downloadVideo(LemmyVideoPost post) async {
    String? downloadUrl = post.directVideoUrl;

    // Handle Redgifs posts - fetch actual video URL
    if (downloadUrl == null && post.isRedgifs) {
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
                Text('Fetching video URL...'),
              ],
            ),
            duration: Duration(seconds: 2),
          ),
        );
      }

      downloadUrl = await RedditEmbedResolverService.resolveVideoUrl(post.redgifsUrl!);

      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
    }

    // Handle YouTube posts - resolve a downloadable stream on-device
    if (downloadUrl == null && post.isYouTube) {
      downloadUrl = (await _resolveYouTube(post))?.downloadUrl;
      if (!mounted) return;
    }

    if (downloadUrl == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No downloadable video found')),
        );
      }
      return;
    }

    // Generate filename from post title
    final sanitizedTitle = post.title
        .replaceAll(RegExp(r'[^\w\s-]'), '')
        .replaceAll(RegExp(r'\s+'), '_')
        .trim();
    final communitySlug = post.community.split('@').first;
    final fileName = '${communitySlug}_$sanitizedTitle.mp4';

    try {
      await DownloadService.instance.enqueueDownload(
        url: downloadUrl,
        fileName: fileName,
        context: context,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Added to downloads')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Download failed: $e')),
      );
    }
  }

  /// Focus the first filter (for DPAD navigation from search input)
  void focusFirstFilter() {
    _communityFilterFocusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        LemmyFiltersBar(
          selectedCommunity: _selectedCommunity,
          selectedSort: _selectedSort,
          selectedTimeFilter: _selectedTimeFilter,
          isSearching: _isSearching,
          resultCount: _posts.length,
          onCommunityChanged: _onCommunityChanged,
          onSortChanged: _onSortChanged,
          onTimeFilterChanged: _onTimeFilterChanged,
          onRandomPressed: _playRandomVideo,
          isRandomLoading: _isRandomLoading,
          communityFocusNode: _communityFilterFocusNode,
          sortFocusNode: _sortFilterFocusNode,
          timeFocusNode: _timeFilterFocusNode,
          randomFocusNode: _randomButtonFocusNode,
        ),

        // Download hint
        if (_posts.isNotEmpty && !widget.isTelevision)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(
              'Long press to download',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),

        Expanded(child: _buildContent()),
      ],
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

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

    if (_posts.isEmpty) {
      // Show the branded empty state before the first load, a "no results"
      // message afterwards.
      if (!_isSearching && _selectedCommunity == null && _searchGeneration == 0) {
        return const LemmyEmptyState();
      }
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
                  : 'Try a different community',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return TvFocusScrollWrapper(
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.only(top: 8, bottom: 16),
        itemCount: _posts.length + (_hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= _posts.length) {
            return _buildLoadingIndicator();
          }

          return LemmyVideoCard(
            post: _posts[index],
            onTap: () => _playVideo(_posts[index]),
            onDownload: () => _downloadVideo(_posts[index]),
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
