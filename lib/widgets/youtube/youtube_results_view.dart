import 'package:flutter/material.dart';
import '../../models/playlist_view_mode.dart';
import '../../models/stremio_subtitle.dart';
import '../../models/torrent.dart';
import '../browse/browse_results_focus.dart';
import '../../services/youtube_service.dart';
import '../../services/storage_service.dart';
import '../../services/video_player_launcher.dart';
import '../../services/download_service.dart';
import '../../screens/debrify_tv/widgets/tv_focus_scroll_wrapper.dart';
import '../../theme/app_theme_scope.dart';
import 'youtube_filters.dart';
import 'youtube_video_card.dart';
import 'youtube_empty_state.dart';

/// Main view for YouTube video results, embedded in TorrentSearchScreen.
///
/// Search-only: YouTube has no public trending API available on-device, so the
/// view shows an empty prompt until the user searches.
class YoutubeResultsView extends StatefulWidget {
  final String searchQuery;
  final bool isTelevision;

  /// Bumped by the parent on every submit — including a re-submit of the same
  /// text — so a retry after a failed/empty search re-runs even though
  /// [searchQuery] is unchanged.
  final int searchToken;

  /// Called when the user presses DPAD-up from the filter row, to return focus
  /// to the search field (TV navigation).
  final VoidCallback? onUpArrowFromFilters;

  const YoutubeResultsView({
    super.key,
    required this.searchQuery,
    this.isTelevision = false,
    this.searchToken = 0,
    this.onUpArrowFromFilters,
  });

  @override
  State<YoutubeResultsView> createState() => YoutubeResultsViewState();
}

class YoutubeResultsViewState extends State<YoutubeResultsView>
    implements BrowseResultsFocusController {
  final ScrollController _scrollController = ScrollController();
  final List<YoutubeVideo> _videos = [];

  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _hasMore = false;
  String? _errorMessage;

  final List<FocusNode> _cardFocusNodes = [];
  final FocusNode _qualityFocusNode = FocusNode(debugLabel: 'youtube-quality-filter');

  int _maxHeight = 1080;

  String _lastSearchQuery = '';
  int _searchGeneration = 0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _lastSearchQuery = widget.searchQuery;
    _loadQuality();
    if (widget.searchQuery.isNotEmpty) _performSearch();
  }

  Future<void> _loadQuality() async {
    final h = await StorageService.getYoutubeMaxHeight();
    if (mounted) setState(() => _maxHeight = h);
  }

  void _onQualityChanged(int height) {
    setState(() => _maxHeight = height);
    StorageService.setYoutubeMaxHeight(height);
    // Applies to the next video resolved; current playback is unaffected.
  }

  @override
  void didUpdateWidget(YoutubeResultsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Re-search when the query changes, or when the token advances (a re-submit
    // of the same text — e.g. a retry after a transient failure).
    if (widget.searchQuery != _lastSearchQuery ||
        widget.searchToken != oldWidget.searchToken) {
      _lastSearchQuery = widget.searchQuery;
      _performSearch();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _qualityFocusNode.dispose();
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
      streams = await YoutubeService.resolveStreams(
        video.id,
        withCaptions: true,
      );
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

    // Offer every available resolution as an in-player switchable "source".
    // Only in the separate-audio path: each source is a video-only track that
    // shares streams.audioUrl, which the player re-muxes on switch (so audio is
    // preserved across a quality change on both media_kit and Android TV).
    List<Torrent>? sources;
    int? currentSourceIndex;
    Future<String?> Function(Torrent)? resolveSource;
    final qualities = streams?.qualities ?? const <YoutubeQuality>[];
    final hasAudio = streams?.audioUrl?.isNotEmpty ?? false;
    if (hasAudio && qualities.length > 1) {
      sources = [
        for (final q in qualities)
          Torrent(
            rowid: 0,
            infohash: '',
            name: q.label,
            sizeBytes: 0,
            createdUnix: 0,
            seeders: 0,
            leechers: 0,
            completed: 0,
            scrapedDate: 0,
            source: 'youtube',
            streamType: StreamType.directUrl,
            directUrl: q.videoUrl,
            hasRealInfoHash: false,
          ),
      ];
      // Default-select the quality we're actually launching (the capped pick).
      final def = qualities.indexWhere((q) => q.videoUrl == playUrl);
      currentSourceIndex = def >= 0 ? def : 0;
      resolveSource = (t) async => t.directUrl;
    }

    // YouTube closed captions → the player's launch-time subtitle group. Each
    // language becomes a selectable track; auto-generated tracks are labelled.
    final captions = streams?.captions ?? const <YoutubeCaptionTrack>[];
    final initialSubtitles = <StremioSubtitle>[
      for (final c in captions)
        StremioSubtitle(
          // Include the video id so the id is unique per video: the player
          // names its subtitle temp file from the id and reuses an existing
          // file, so a non-unique id would serve one video's captions on
          // another.
          id: 'yt:${video.id}:${c.langCode}${c.isAutoGenerated ? ':auto' : ''}',
          url: c.url,
          lang: c.langCode,
          label: c.isAutoGenerated ? '${c.langName} (auto)' : c.langName,
          source: 'YouTube',
        ),
    ];

    await VideoPlayerLauncher.push(
      context,
      VideoPlayerLaunchArgs(
        videoUrl: playUrl,
        audioUrl: streams?.audioUrl,
        fallbackUrl: streams?.downloadUrl,
        title: streams?.title ?? video.title,
        subtitle: video.author,
        viewMode: PlaylistViewMode.sorted,
        stremioSources: sources,
        stremioCurrentSourceIndex: currentSourceIndex,
        resolveStremioSource: resolveSource,
        initialSubtitles: initialSubtitles.isEmpty ? null : initialSubtitles,
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
        SnackBar(
          content: Text(_downloadQualityMessage(streams)),
          duration: const Duration(seconds: 7),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Download failed: $e')),
      );
    }
  }

  /// Snackbar text explaining the chosen download quality and why it isn't
  /// selectable. YouTube only serves a single audio+video file at low
  /// resolutions (≤720p); 1080p and up come as separate video/audio tracks that
  /// must be merged (muxed) — which we don't do on download — so we grab the
  /// best combined stream automatically.
  String _downloadQualityMessage(YoutubeResolvedStreams? streams) {
    final h = streams?.downloadHeight;
    final quality = h != null ? '${h}p' : 'best available';
    if (streams?.downloadHasAudio == false) {
      return 'Added to downloads at $quality (no audio — YouTube offered no '
          'combined video+audio file for this one).';
    }
    return 'Added to downloads at $quality — the best quality YouTube serves '
        'as a single file with audio. Higher resolutions come as separate '
        'video/audio that must be merged, so quality can’t be picked here.';
  }

  /// DPAD entry point from the search input: focus the quality selector.
  @override
  void focusFirstFilter() {
    _qualityFocusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        YoutubeFiltersBar(
          selectedHeight: _maxHeight,
          resultCount: _videos.length,
          isTelevision: widget.isTelevision,
          onQualityChanged: _onQualityChanged,
          qualityFocusNode: _qualityFocusNode,
          onUpArrowPressed: widget.onUpArrowFromFilters,
        ),
        Expanded(child: _buildContent()),
      ],
    );
  }

  Widget _buildContent() {
    final app = AppThemeScope.of(context);
    if (_isLoading) {
      return Center(
        child: CircularProgressIndicator(color: app.seeAll.accent),
      );
    }

    if (_errorMessage != null && _videos.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              // Off-rung: the dim rung struck up to its shipped 0.55.
              color: app.fade(app.youtube.textDim, 1.1),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                _errorMessage!,
                style: TextStyle(
                  color: app.youtube.textBody,
                  fontSize: 16,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _performSearch,
              style: FilledButton.styleFrom(
                backgroundColor: app.seeAll.accent,
              ),
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
              color: app.youtube.textFaint,
            ),
            const SizedBox(height: 16),
            const Text(
              'No videos found',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Try a different search term',
              style: TextStyle(
                color: app.youtube.textDim,
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    return TvFocusScrollWrapper(
      child: LayoutBuilder(
        builder: (context, constraints) {
          const hPad = 16.0;
          const spacing = 16.0;
          final columns = youtubeGridColumnsFor(
            constraints.maxWidth,
            isTelevision: widget.isTelevision,
          );
          // Derive the card aspect ratio from the actual column width so the
          // 16:9 thumbnail plus a fixed meta block fits exactly at any size —
          // no overflow, no clipped titles, whatever the device.
          final colWidth =
              (constraints.maxWidth - hPad * 2 - spacing * (columns - 1)) /
                  columns;
          const metaHeight = 96.0;
          final cardHeight = colWidth * 9 / 16 + metaHeight;
          final aspectRatio = colWidth / cardHeight;

          return CustomScrollView(
            controller: _scrollController,
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(hPad, 12, hPad, 8),
                sliver: SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    childAspectRatio: aspectRatio,
                    mainAxisSpacing: 22,
                    crossAxisSpacing: spacing,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => YoutubeVideoCard(
                      video: _videos[index],
                      isTelevision: widget.isTelevision,
                      onTap: () => _playVideo(_videos[index]),
                      onDownload: () => _downloadVideo(_videos[index]),
                      focusNode: index < _cardFocusNodes.length
                          ? _cardFocusNodes[index]
                          : null,
                    ),
                    childCount: _videos.length,
                  ),
                ),
              ),
              if (_hasMore)
                SliverToBoxAdapter(child: _buildLoadingIndicator()),
            ],
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
          ? CircularProgressIndicator(
              color: AppThemeScope.of(context).seeAll.accent,
            )
          : const SizedBox.shrink(),
    );
  }
}
