import 'package:flutter/material.dart';
import '../../models/iptv_playlist.dart';
import '../../models/playlist_view_mode.dart';
import '../../services/iptv_service.dart';
import '../../services/xtream_codes_service.dart';
import '../../services/storage_service.dart';
import '../../services/video_player_launcher.dart';
import '../../screens/debrify_tv/widgets/tv_focus_scroll_wrapper.dart';
import '../../screens/settings/iptv_settings_page.dart';
import 'iptv_filters.dart';
import 'iptv_channel_card.dart';
import 'iptv_empty_state.dart';

/// Main view for IPTV M3U results, to be embedded in TorrentSearchScreen
class IptvResultsView extends StatefulWidget {
  final String searchQuery;
  final bool isTelevision;
  /// Callback when up arrow is pressed from filters (to go back to source dropdown)
  final VoidCallback? onUpArrowFromFilters;

  const IptvResultsView({
    super.key,
    required this.searchQuery,
    this.isTelevision = false,
    this.onUpArrowFromFilters,
  });

  @override
  State<IptvResultsView> createState() => IptvResultsViewState();
}

class IptvResultsViewState extends State<IptvResultsView> {
  final ScrollController _scrollController = ScrollController();
  final IptvService _iptvService = IptvService.instance;

  // Playlists and settings
  List<IptvPlaylist> _playlists = [];
  IptvPlaylist? _selectedPlaylist;
  bool _settingsLoaded = false;

  // Current playlist data
  List<IptvChannel> _allChannels = [];
  List<IptvChannel> _filteredChannels = [];
  List<String> _categories = [];
  String? _selectedCategory;

  // Content type for Xtream Codes playlists
  String _selectedContentType = 'live';

  // Loading state
  bool _isLoading = false;
  String? _errorMessage;

  // Favorites
  Set<String> _favoriteUrls = {};

  // Focus nodes for DPAD
  final FocusNode _playlistFilterFocusNode = FocusNode(debugLabel: 'iptv-playlist-filter');
  final FocusNode _categoryFilterFocusNode = FocusNode(debugLabel: 'iptv-category-filter');
  final FocusNode _contentTypeFocusNode = FocusNode(debugLabel: 'iptv-content-type-filter');
  final List<FocusNode> _cardFocusNodes = [];

  String _lastSearchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadFavorites();
  }

  Future<void> _loadFavorites() async {
    final urls = await StorageService.getIptvFavoriteChannelUrls();
    if (mounted) {
      setState(() => _favoriteUrls = urls);
    }
  }

  Future<void> _toggleFavorite(IptvChannel channel, bool isFavorited) async {
    await StorageService.setIptvChannelFavorited(
      channel.url,
      isFavorited,
      channelName: channel.name,
      logoUrl: channel.logoUrl,
      group: channel.group,
      playlistId: _selectedPlaylist?.id,
    );
    if (mounted) {
      setState(() {
        if (isFavorited) {
          _favoriteUrls.add(channel.url);
        } else {
          _favoriteUrls.remove(channel.url);
        }
      });
    }
  }

  Future<void> _loadSettings({bool forceReload = false}) async {
    var playlists = await StorageService.getIptvPlaylists();
    var defaultPlaylistId = await StorageService.getIptvDefaultPlaylist();

    // Add default playlist on first run (if not already initialized)
    final defaultsInitialized = await StorageService.getIptvDefaultsInitialized();
    if (!defaultsInitialized) {
      // Add the default iptv-org playlist
      final defaultPlaylist = IptvPlaylist(
        id: 'iptv-org-default',
        name: 'iptv-org',
        url: 'https://iptv-org.github.io/iptv/index.m3u',
        addedAt: DateTime.now(),
      );
      playlists = [defaultPlaylist, ...playlists];
      defaultPlaylistId = defaultPlaylist.id;

      // Save the default playlist and mark as initialized
      await StorageService.setIptvPlaylists(playlists);
      await StorageService.setIptvDefaultPlaylist(defaultPlaylistId);
      await StorageService.setIptvDefaultsInitialized(true);
    }

    if (!mounted) return;

    // Determine the new selected playlist
    IptvPlaylist? newSelectedPlaylist;
    if (defaultPlaylistId != null && playlists.isNotEmpty) {
      newSelectedPlaylist = playlists.firstWhere(
        (p) => p.id == defaultPlaylistId,
        orElse: () => playlists.first,
      );
    } else if (playlists.isNotEmpty) {
      newSelectedPlaylist = playlists.first;
    }

    // Check if playlist changed
    final playlistChanged = _selectedPlaylist?.id != newSelectedPlaylist?.id;

    setState(() {
      _playlists = playlists;
      _settingsLoaded = true;
      _selectedPlaylist = newSelectedPlaylist;
    });

    // Only reload playlist if it changed or forced, or if we have no channels loaded
    if (_selectedPlaylist != null && (forceReload || playlistChanged || _allChannels.isEmpty)) {
      _loadPlaylist(_selectedPlaylist!);
    }
  }

  @override
  void didUpdateWidget(IptvResultsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Search filter when query changes
    if (widget.searchQuery != _lastSearchQuery) {
      _lastSearchQuery = widget.searchQuery;
      _applyFilters();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _playlistFilterFocusNode.dispose();
    _categoryFilterFocusNode.dispose();
    _contentTypeFocusNode.dispose();
    for (final node in _cardFocusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  Future<void> _loadPlaylist(IptvPlaylist playlist) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _allChannels = [];
      _filteredChannels = [];
      _categories = [];
      _selectedCategory = null;
    });

    // Dispose old focus nodes
    for (final node in _cardFocusNodes) {
      node.dispose();
    }
    _cardFocusNodes.clear();

    // Determine source: XC API, local file, or URL
    final IptvParseResult result;
    if (playlist.isXtreamCodes) {
      final xcService = XtreamCodesService.instance;
      if (_selectedContentType == 'vod') {
        result = await xcService.fetchVodStreams(playlist.serverUrl!, playlist.username!, playlist.password!);
      } else {
        result = await xcService.fetchLiveStreams(playlist.serverUrl!, playlist.username!, playlist.password!);
      }
    } else if (playlist.isLocalFile) {
      result = _iptvService.parseContent(playlist.content!);
    } else {
      result = await _iptvService.fetchPlaylist(playlist.url);
    }

    if (!mounted) return;

    if (result.hasError) {
      setState(() {
        _isLoading = false;
        _errorMessage = result.error;
      });
      return;
    }

    // Create focus nodes for cards
    for (int i = 0; i < result.channels.length; i++) {
      _cardFocusNodes.add(FocusNode(debugLabel: 'iptv-card-$i'));
    }

    setState(() {
      _isLoading = false;
      _allChannels = result.channels;
      _categories = result.categories;
    });

    _applyFilters();
  }

  void _applyFilters() {
    var channels = _allChannels;

    // Filter by category
    if (_selectedCategory != null) {
      channels = _iptvService.filterByCategory(channels, _selectedCategory);
    }

    // Filter by search query
    if (widget.searchQuery.isNotEmpty) {
      channels = _iptvService.searchChannels(channels, widget.searchQuery);
    }

    setState(() {
      _filteredChannels = channels;
    });
  }

  void _onPlaylistChanged(IptvPlaylist? playlist) {
    if (playlist == null || playlist == _selectedPlaylist) return;

    setState(() {
      _selectedPlaylist = playlist;
      _selectedCategory = null;
      if (playlist.isXtreamCodes) {
        _selectedContentType = 'live';
      }
    });

    _loadPlaylist(playlist);
  }

  void _onContentTypeChanged(String contentType) {
    if (contentType == _selectedContentType) return;

    setState(() {
      _selectedContentType = contentType;
      _selectedCategory = null;
    });

    if (_selectedPlaylist != null) {
      _loadPlaylist(_selectedPlaylist!);
    }
  }

  void _onCategoryChanged(String? category) {
    setState(() => _selectedCategory = category);
    _applyFilters();
  }

  Future<void> _playChannel(IptvChannel channel) async {
    await VideoPlayerLauncher.push(
      context,
      VideoPlayerLaunchArgs(
        videoUrl: channel.url,
        title: channel.name,
        subtitle: channel.group ?? 'IPTV',
        viewMode: PlaylistViewMode.sorted,
      ),
    );
  }

  void _navigateToSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const IptvSettingsPage()),
    ).then((_) {
      // Reload settings when returning
      _loadSettings();
    });
  }

  /// Focus the first filter (for DPAD navigation from search input)
  void focusFirstFilter() {
    _playlistFilterFocusNode.requestFocus();
  }

  /// Focus the first channel card (for DPAD navigation from filters)
  void _focusFirstChannel() {
    // Only focus if we have filtered channels and focus nodes
    if (_filteredChannels.isNotEmpty && _cardFocusNodes.isNotEmpty) {
      _cardFocusNodes[0].requestFocus();
    }
  }

  /// Refresh playlists from storage (call after settings change)
  Future<void> refreshPlaylists() async {
    await _loadSettings();
  }

  @override
  Widget build(BuildContext context) {
    if (!_settingsLoaded) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        // Filters bar
        IptvFiltersBar(
          playlists: _playlists,
          selectedPlaylist: _selectedPlaylist,
          categories: _categories,
          selectedCategory: _selectedCategory,
          channelCount: _filteredChannels.length,
          isLoading: _isLoading,
          onPlaylistChanged: _onPlaylistChanged,
          onCategoryChanged: _onCategoryChanged,
          onAddPlaylist: _navigateToSettings,
          playlistFocusNode: _playlistFilterFocusNode,
          categoryFocusNode: _categoryFilterFocusNode,
          showContentTypeFilter: _selectedPlaylist?.isXtreamCodes ?? false,
          selectedContentType: _selectedContentType,
          onContentTypeChanged: _onContentTypeChanged,
          contentTypeFocusNode: _contentTypeFocusNode,
          onUpArrowPressed: widget.onUpArrowFromFilters,
          onDownArrowPressed: _focusFirstChannel,
        ),

        // Content
        Expanded(
          child: _buildContent(),
        ),
      ],
    );
  }

  Widget _buildContent() {
    // Empty state when no playlists
    if (_playlists.isEmpty) {
      return IptvEmptyState(
        hasPlaylists: false,
        onAddPlaylist: _navigateToSettings,
      );
    }

    // Empty state when no playlist selected
    if (_selectedPlaylist == null) {
      return const IptvEmptyState(hasPlaylists: true);
    }

    // Loading
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    // Error
    if (_errorMessage != null && _allChannels.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
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
                'Failed to load playlist',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                _errorMessage!,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => _loadPlaylist(_selectedPlaylist!),
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    // No channels found
    if (_filteredChannels.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.live_tv_outlined,
              size: 64,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              'No channels found',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              widget.searchQuery.isNotEmpty
                  ? 'Try a different search term'
                  : _selectedCategory != null
                      ? 'Try a different category'
                      : 'This playlist appears to be empty',
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
        itemCount: _filteredChannels.length,
        itemBuilder: (context, index) {
          final channel = _filteredChannels[index];
          return IptvChannelCard(
            channel: channel,
            onTap: () => _playChannel(channel),
            focusNode: index < _cardFocusNodes.length ? _cardFocusNodes[index] : null,
            isFavorited: _favoriteUrls.contains(channel.url),
            onFavoriteToggle: (isFavorited) => _toggleFavorite(channel, isFavorited),
          );
        },
      ),
    );
  }
}
