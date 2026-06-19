import 'package:flutter/material.dart';
import '../../models/playlist_view_mode.dart';
import '../../services/youtube_service.dart';
import '../../services/video_player_launcher.dart';
import '../../services/download_service.dart';
import '../../screens/debrify_tv/widgets/tv_focus_scroll_wrapper.dart';
import 'youtube_video_card.dart';
import 'youtube_empty_state.dart';

/// Main view for YouTube video results, embedded in TorrentSearchScreen.
///
/// Search-only: YouTube has no public trending API available on-device, so the
/// view shows an empty prompt until the user searches.
class YoutubeResultsView extends StatefulWidget {
  final String searchQuery;
  final bool isTelevision;

  const YoutubeResultsView({
    super.key,
    required this.searchQuery,
    this.isTelevision = false,
  });

  @override
  State<YoutubeResultsView> createState() => YoutubeResultsViewState();
}

class YoutubeResultsViewState extends State<YoutubeResultsView> {
  final ScrollController _scrollController = ScrollController();
  final List<YoutubeVideo> _videos = [];

  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _hasMore = false;
  String? _errorMessage;

  final List<FocusNode> _cardFocusNodes = [];

  String _lastSearchQuery = '';
  int _searchGeneration = 0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _lastSearchQuery = widget.searchQuery;
    if (widget.searchQuery.isNotEmpty) _performSearch();
  }

  @override
  void didUpdateWidget(YoutubeResultsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.searchQuery != _lastSearchQuery) {
      _lastSearchQuery = widget.searchQuery;
      _performSearch();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
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

  Future<void> _performSearch() async {
    final generation = ++_searchGeneration;

    for (final node in _cardFocusNodes) {
      node.dispose();
    }
    _cardFocusNodes.clear();

    if (!_isSearching) {
      setState(() {
        _videos.clear();
        _isLoading = false;
        _errorMessage = null;
        _hasMore = false;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _videos.clear();
      _hasMore = true;
    });

    try {
      final result = await YoutubeService.search(widget.searchQuery);

      if (!mounted || generation != _searchGeneration) return;

      for (int i = 0; i < result.videos.length; i++) {
        _cardFocusNodes.add(FocusNode(debugLabel: 'youtube-card-$i'));
      }

      setState(() {
        _isLoading = false;
        _videos.addAll(result.videos);
        _hasMore = result.hasMore;
      });
    } catch (e) {
      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore || !_isSearching) return;

    final generation = _searchGeneration;
    setState(() => _isLoadingMore = true);

    try {
      final result = await YoutubeService.searchMore();

      if (!mounted || generation != _searchGeneration) return;

      final startIndex = _cardFocusNodes.length;
      for (int i = 0; i < result.videos.length; i++) {
        _cardFocusNodes.add(FocusNode(debugLabel: 'youtube-card-${startIndex + i}'));
      }

      setState(() {
        _isLoadingMore = false;
        _videos.addAll(result.videos);
        _hasMore = result.hasMore;
      });
    } catch (e) {
      if (!mounted || generation != _searchGeneration) return;
      setState(() => _isLoadingMore = false);
    }
  }

  /// Resolve streams for a video, showing a loading snackbar while it works.
  Future<YoutubeResolvedStreams?> _resolve(YoutubeVideo video) async {
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
      streams = await YoutubeService.resolveStreams(video.id);
    } catch (_) {
      streams = null;
    }

    if (mounted) ScaffoldMessenger.of(context).hideCurrentSnackBar();
    return streams;
  }

  Future<void> _playVideo(YoutubeVideo video) async {
    final streams = await _resolve(video);
    if (!mounted) return;

    final playUrl = streams?.playUrl;
    if (playUrl == null || playUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not load this video')),
      );
      return;
    }

    await VideoPlayerLauncher.push(
      context,
      VideoPlayerLaunchArgs(
        videoUrl: playUrl,
        audioUrl: streams?.audioUrl,
        fallbackUrl: streams?.downloadUrl,
        title: streams?.title ?? video.title,
        subtitle: video.author,
        viewMode: PlaylistViewMode.sorted,
      ),
    );
  }

  Future<void> _downloadVideo(YoutubeVideo video) async {
    final streams = await _resolve(video);
    if (!mounted) return;

    final downloadUrl = streams?.downloadUrl;
    if (downloadUrl == null || downloadUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No downloadable stream found')),
      );
      return;
    }

    final sanitizedTitle = video.title
        .replaceAll(RegExp(r'[^\w\s-]'), '')
        .replaceAll(RegExp(r'\s+'), '_')
        .trim();
    final fileName = 'youtube_$sanitizedTitle.mp4';

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

  /// DPAD entry point from the search input: focus the first result card.
  void focusFirstFilter() {
    if (_cardFocusNodes.isNotEmpty) _cardFocusNodes.first.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (_videos.isNotEmpty && !widget.isTelevision)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${_videos.length} video${_videos.length != 1 ? 's' : ''} • long press to download',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
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

    if (_errorMessage != null && _videos.isEmpty) {
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
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                _errorMessage!,
                style: Theme.of(context).textTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
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

    if (_videos.isEmpty) {
      if (!_isSearching) {
        return const YoutubeEmptyState();
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
              'Try a different search term',
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
        itemCount: _videos.length + (_hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= _videos.length) {
            return _buildLoadingIndicator();
          }

          return YoutubeVideoCard(
            video: _videos[index],
            onTap: () => _playVideo(_videos[index]),
            onDownload: () => _downloadVideo(_videos[index]),
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
