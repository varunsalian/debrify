import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../models/stremio_addon.dart';
import '../../models/stremio_tv/stremio_tv_channel.dart';
import '../../models/torrent.dart';
import '../../services/debrid_service.dart';
import '../../services/main_page_bridge.dart';
import '../../services/storage_service.dart';
import '../../services/video_player_launcher.dart';
import '../../services/torbox_service.dart';
import '../../services/pikpak_api_service.dart';
import 'stremio_tv_service.dart';
import 'widgets/stremio_tv_channel_row.dart';
import 'widgets/stremio_tv_empty_state.dart';

/// Main Stremio TV screen — a TV guide powered by Stremio addon catalogs.
///
/// Each addon catalog becomes a "channel" with a deterministic "now playing"
/// item that rotates on a configurable schedule.
class StremioTvScreen extends StatefulWidget {
  const StremioTvScreen({super.key});

  @override
  State<StremioTvScreen> createState() => _StremioTvScreenState();
}

class _StremioTvScreenState extends State<StremioTvScreen> {
  final StremioTvService _service = StremioTvService.instance;

  List<StremioTvChannel> _channels = [];
  bool _loading = true;
  bool _refreshing = false;
  int _rotationMinutes = 60;
  bool _autoRefresh = true;
  double? _currentSlotProgress;

  Timer? _refreshTimer;
  final List<FocusNode> _rowFocusNodes = [];
  int _focusedIndex = 0;

  // Lazy loading: track channels currently being fetched to avoid duplicates
  final Set<String> _loadingChannelIds = {};

  // Track mounted state for auto-play
  String? _pendingChannelId;

  @override
  void initState() {
    super.initState();
    _loadSettings().then((_) => _discoverAndLoad());

    // Register the auto-play bridge
    MainPageBridge.watchStremioTvChannel = (channelId) async {
      if (mounted) {
        _playChannelById(channelId);
      }
    };

    // Check for pending auto-play
    final pending = MainPageBridge.getAndClearStremioTvChannelToAutoPlay();
    if (pending != null) {
      _pendingChannelId = pending;
    }

    // Start periodic refresh for progress bars
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted && _autoRefresh) {
        setState(() {}); // Refresh progress bars
        // Check if any slot boundaries have been crossed
        _checkRotationBoundaries();
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    for (final node in _rowFocusNodes) {
      node.dispose();
    }
    // Only clear if we're the active handler
    if (MainPageBridge.watchStremioTvChannel != null) {
      MainPageBridge.watchStremioTvChannel = null;
    }
    super.dispose();
  }

  Future<void> _loadSettings() async {
    _rotationMinutes = await StorageService.getStremioTvRotationMinutes();
    _autoRefresh = await StorageService.getStremioTvAutoRefresh();
  }

  Future<void> _discoverAndLoad() async {
    setState(() => _loading = true);

    final channels = await _service.discoverChannels();

    // Set up focus nodes
    for (final node in _rowFocusNodes) {
      node.dispose();
    }
    _rowFocusNodes.clear();
    for (int i = 0; i < channels.length; i++) {
      _rowFocusNodes.add(FocusNode(debugLabel: 'stremioTvRow$i'));
    }

    if (mounted) {
      setState(() {
        _channels = _sortedChannels(channels);
        _loading = false;
      });
    }

    // Handle pending auto-play (eagerly load the target channel first)
    if (_pendingChannelId != null && mounted) {
      final id = _pendingChannelId!;
      _pendingChannelId = null;
      await _ensureChannelLoaded(id);
      if (mounted) _playChannelById(id);
    }
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);

    await _loadSettings();
    final channels = await _service.discoverChannels();

    // Clear loading tracker and invalidate cache so channels refetch
    _loadingChannelIds.clear();
    for (final ch in channels) {
      ch.lastFetched = null;
    }

    // Reset focus nodes
    for (final node in _rowFocusNodes) {
      node.dispose();
    }
    _rowFocusNodes.clear();
    for (int i = 0; i < channels.length; i++) {
      _rowFocusNodes.add(FocusNode(debugLabel: 'stremioTvRow$i'));
    }

    if (mounted) {
      setState(() {
        _channels = _sortedChannels(channels);
        _refreshing = false;
      });
    } else {
      _refreshing = false;
    }
  }

  List<StremioTvChannel> _sortedChannels(List<StremioTvChannel> channels) {
    final favorites = channels.where((ch) => ch.isFavorite).toList();
    final rest = channels.where((ch) => !ch.isFavorite).toList();
    favorites.sort((a, b) => a.channelNumber.compareTo(b.channelNumber));
    rest.sort((a, b) => a.channelNumber.compareTo(b.channelNumber));
    return [...favorites, ...rest];
  }

  void _checkRotationBoundaries() {
    // If items need to rotate, reload channels where the slot changed
    // This is lightweight — just recalculates getNowPlaying()
    setState(() {}); // The getNowPlaying call in build() handles this
  }

  // ============================================================================
  // Lazy Loading
  // ============================================================================

  /// Lazy-load items for a single channel by ID.
  Future<void> _ensureChannelLoaded(String channelId) async {
    final idx = _channels.indexWhere((ch) => ch.id == channelId);
    if (idx == -1) return;
    await _ensureChannelItemsLoaded(_channels[idx]);
  }

  /// Lazy-load items for a single channel.
  /// Prevents duplicate concurrent fetches via [_loadingChannelIds].
  /// Removes the channel from the list if it loads with zero items.
  Future<void> _ensureChannelItemsLoaded(StremioTvChannel channel) async {
    if (channel.hasItems && !channel.isCacheStale) return;
    if (_loadingChannelIds.contains(channel.id)) return;

    _loadingChannelIds.add(channel.id);

    try {
      await _service.loadChannelItems(channel);
    } catch (_) {
      // Mark as fetched so we don't retry every frame
      channel.lastFetched = DateTime.now();
    } finally {
      _loadingChannelIds.remove(channel.id);
    }

    if (!mounted) return;

    // Remove channels that loaded with no usable items
    if (channel.items.isEmpty && channel.lastFetched != null) {
      setState(() {
        final idx = _channels.indexWhere((ch) => ch.id == channel.id);
        if (idx != -1) {
          _channels.removeAt(idx);
          if (idx < _rowFocusNodes.length) {
            _rowFocusNodes[idx].dispose();
            _rowFocusNodes.removeAt(idx);
          }
        }
      });
    } else {
      setState(() {});
    }
  }

  // ============================================================================
  // Playback
  // ============================================================================

  /// Minimum content size (200 MB) to consider a direct stream valid.
  /// Anything smaller is likely a placeholder/error video.
  static const int _minContentBytes = 200 * 1024 * 1024;

  /// Check if a direct stream URL has sufficient content size.
  /// Returns false for placeholder videos (< 200 MB).
  /// Follows up to 5 redirects to reach the final URL.
  Future<bool> _isValidStreamUrl(String url) async {
    try {
      final client = http.Client();
      try {
        var currentUrl = url;
        for (int i = 0; i < 5; i++) {
          final request = http.Request('HEAD', Uri.parse(currentUrl));
          request.followRedirects = false;
          final streamed = await client.send(request).timeout(
                const Duration(seconds: 5),
              );
          // Drain response stream to release resources
          await streamed.stream.drain();

          if (streamed.statusCode >= 300 && streamed.statusCode < 400) {
            final location = streamed.headers['location'];
            if (location == null || location.isEmpty) {
              debugPrint('StremioTV: HEAD $currentUrl → ${streamed.statusCode} (redirect, no location)');
              return true;
            }
            // Resolve relative redirects
            currentUrl = Uri.parse(currentUrl).resolve(location).toString();
            debugPrint('StremioTV: HEAD → ${streamed.statusCode}, following redirect');
            continue;
          }

          final contentLength =
              int.tryParse(streamed.headers['content-length'] ?? '') ?? 0;
          final sizeMb = (contentLength / (1024 * 1024)).toStringAsFixed(1);
          debugPrint('StremioTV: HEAD $currentUrl → ${streamed.statusCode}, size: ${sizeMb}MB');
          if (contentLength == 0) return true;
          return contentLength >= _minContentBytes;
        }
        // Too many redirects — allow through
        debugPrint('StremioTV: HEAD $url → too many redirects, allowing');
        return true;
      } finally {
        client.close();
      }
    } catch (e) {
      debugPrint('StremioTV: HEAD check failed for $url: $e');
      return true;
    }
  }

  Future<void> _playChannel(StremioTvChannel channel) async {
    // Ensure items are loaded before trying to play
    if (!channel.hasItems) {
      await _ensureChannelItemsLoaded(channel);
      if (!mounted) return;
    }

    final nowPlaying = _service.getNowPlaying(
      channel,
      rotationMinutes: _rotationMinutes,
    );
    if (nowPlaying == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No items available for this channel')),
        );
      }
      return;
    }

    final item = nowPlaying.item;
    _currentSlotProgress = nowPlaying.progress;

    if (!item.hasValidImdbId) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${item.name} does not have a valid IMDB ID for stream search',
            ),
          ),
        );
      }
      return;
    }

    // Show loading dialog
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        content: Row(
          children: [
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                'Searching streams for ${item.name}...',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );

    try {
      final results = await _service.searchStreams(
        type: item.type,
        imdbId: item.id,
      );

      if (!mounted) return;
      Navigator.of(context).pop(); // Dismiss loading dialog

      final torrents = results['torrents'] as List<Torrent>? ?? [];

      if (torrents.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('No streams found for ${item.name}'),
            ),
          );
        }
        return;
      }

      // Try to find the best stream to play
      // Priority: direct URL streams first (validated), then torrents via debrid
      final directStreams =
          torrents.where((t) => t.isDirectStream).toList();
      for (final stream in directStreams) {
        if (stream.directUrl == null || stream.directUrl!.isEmpty) continue;
        if (!mounted) return;
        final valid = await _isValidStreamUrl(stream.directUrl!);
        if (!mounted) return;
        if (valid) {
          await _playDirectStream(stream, item);
          return;
        }
        debugPrint(
          'StremioTV: Skipping small stream (< 200MB): ${stream.source}',
        );
      }

      // For torrent streams, try to resolve via debrid
      final torrentStreams =
          torrents.where((t) => t.streamType == StreamType.torrent).toList();
      if (torrentStreams.isNotEmpty) {
        await _playTorrentViaDebrid(torrentStreams.first, item);
        return;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No playable streams found for ${item.name}')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop(); // Dismiss loading dialog
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error searching streams: $e')),
      );
    }
  }

  Future<void> _playDirectStream(Torrent torrent, StremioMeta item) async {
    if (torrent.directUrl == null || torrent.directUrl!.isEmpty) return;

    await VideoPlayerLauncher.push(
      context,
      VideoPlayerLaunchArgs(
        videoUrl: torrent.directUrl!,
        title: item.name,
        subtitle: torrent.source,
        startAtPercent: _currentSlotProgress,
        contentImdbId: item.hasValidImdbId ? item.id : null,
        contentType: item.type,
      ),
    );
  }

  Future<void> _playTorrentViaDebrid(
    Torrent torrent,
    StremioMeta item,
  ) async {
    // Try Real Debrid first, then Torbox, then PikPak
    final rdKey = await StorageService.getApiKey();
    if (rdKey != null && rdKey.isNotEmpty) {
      await _playViaRealDebrid(torrent, item, rdKey);
      return;
    }

    final tbKey = await StorageService.getTorboxApiKey();
    if (tbKey != null && tbKey.isNotEmpty) {
      await _playViaTorbox(torrent, item);
      return;
    }

    final pikpakEnabled = await StorageService.getPikPakEnabled();
    if (pikpakEnabled) {
      await _playViaPikPak(torrent, item);
      return;
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No debrid provider configured. Connect Real Debrid, Torbox, or PikPak in Settings.',
          ),
        ),
      );
    }
  }

  Future<void> _playViaRealDebrid(
    Torrent torrent,
    StremioMeta item,
    String apiKey,
  ) async {
    try {
      // Show progress
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          content: Row(
            children: [
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 16),
              const Expanded(child: Text('Resolving via Real Debrid...')),
            ],
          ),
        ),
      );

      final magnet =
          'magnet:?xt=urn:btih:${torrent.infohash}&dn=${Uri.encodeComponent(torrent.name)}';
      final addResult = await DebridService.addMagnet(apiKey, magnet);
      final torrentId = addResult['id'];

      // Select all files (empty list = 'all')
      await DebridService.selectFiles(apiKey, torrentId, []);

      // Wait briefly for processing
      await Future.delayed(const Duration(seconds: 2));

      final info = await DebridService.getTorrentInfo(apiKey, torrentId);
      final links = info['links'] as List<dynamic>? ?? [];

      if (!mounted) return;
      Navigator.of(context).pop(); // Dismiss progress

      if (links.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No links available from Real Debrid')),
          );
        }
        return;
      }

      // Unrestrict the first link
      final unrestrictResult = await DebridService.unrestrictLink(
        apiKey,
        links.first.toString(),
      );
      final videoUrl = unrestrictResult['download'] as String?;

      if (videoUrl != null && videoUrl.isNotEmpty && mounted) {
        await VideoPlayerLauncher.push(
          context,
          VideoPlayerLaunchArgs(
            videoUrl: videoUrl,
            title: item.name,
            startAtPercent: _currentSlotProgress,
            contentImdbId: item.hasValidImdbId ? item.id : null,
            contentType: item.type,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      // Dismiss dialog if still showing
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Real Debrid error: $e')),
      );
    }
  }

  Future<void> _playViaTorbox(
    Torrent torrent,
    StremioMeta item,
  ) async {
    try {
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          content: Row(
            children: [
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 16),
              const Expanded(child: Text('Resolving via Torbox...')),
            ],
          ),
        ),
      );

      final tbKey = await StorageService.getTorboxApiKey();
      if (tbKey == null || tbKey.isEmpty) {
        if (!mounted) return;
        Navigator.of(context).pop();
        return;
      }

      final magnet =
          'magnet:?xt=urn:btih:${torrent.infohash}&dn=${Uri.encodeComponent(torrent.name)}';
      final result = await TorboxService.createTorrent(
        apiKey: tbKey,
        magnet: magnet,
      );
      final torrentId = result['torrent_id'] ?? result['id'];

      if (torrentId == null) {
        if (!mounted) return;
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to add torrent to Torbox')),
        );
        return;
      }

      // Wait for processing
      await Future.delayed(const Duration(seconds: 3));

      // Get torrent info to find a file to download
      final torrentInfo = await TorboxService.getTorrentById(
        tbKey,
        torrentId is int ? torrentId : int.parse(torrentId.toString()),
      );

      if (!mounted) return;
      Navigator.of(context).pop();

      if (torrentInfo == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not get torrent info from Torbox'),
            ),
          );
        }
        return;
      }

      // Request download link for the first file
      final files = torrentInfo.files;
      if (files.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No files found in Torbox torrent')),
          );
        }
        return;
      }

      final downloadLink = await TorboxService.requestFileDownloadLink(
        apiKey: tbKey,
        torrentId: torrentId is int ? torrentId : int.parse(torrentId.toString()),
        fileId: files.first.id,
      );

      if (downloadLink.isNotEmpty && mounted) {
        await VideoPlayerLauncher.push(
          context,
          VideoPlayerLaunchArgs(
            videoUrl: downloadLink,
            title: item.name,
            startAtPercent: _currentSlotProgress,
            contentImdbId: item.hasValidImdbId ? item.id : null,
            contentType: item.type,
          ),
        );
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No download link available from Torbox'),
            ),
          );
        }
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Torbox error: $e')),
      );
    }
  }

  Future<void> _playViaPikPak(
    Torrent torrent,
    StremioMeta item,
  ) async {
    try {
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          content: Row(
            children: [
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 16),
              const Expanded(child: Text('Resolving via PikPak...')),
            ],
          ),
        ),
      );

      final pikpak = PikPakApiService.instance;
      final magnet =
          'magnet:?xt=urn:btih:${torrent.infohash}&dn=${Uri.encodeComponent(torrent.name)}';
      final result = await pikpak.addOfflineDownload(magnet);
      final fileId = result['task']?['file_id'] as String?;

      if (fileId == null || fileId.isEmpty) {
        if (!mounted) return;
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to add torrent to PikPak')),
        );
        return;
      }

      // Wait for processing
      await Future.delayed(const Duration(seconds: 3));

      final fileData = await pikpak.getFileDetails(fileId);
      final url = pikpak.getStreamingUrl(fileData);

      if (!mounted) return;
      Navigator.of(context).pop();

      if (url != null && url.isNotEmpty) {
        await VideoPlayerLauncher.push(
          context,
          VideoPlayerLaunchArgs(
            videoUrl: url,
            title: item.name,
            startAtPercent: _currentSlotProgress,
            contentImdbId: item.hasValidImdbId ? item.id : null,
            contentType: item.type,
          ),
        );
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No streaming URL available from PikPak'),
            ),
          );
        }
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('PikPak error: $e')),
      );
    }
  }

  void _playChannelById(String channelId) {
    if (_channels.isEmpty) return;
    final channel = _channels.firstWhere(
      (ch) => ch.id == channelId,
      orElse: () => _channels.first,
    );
    _playChannel(channel);
  }

  // ============================================================================
  // Favorites
  // ============================================================================

  Future<void> _toggleFavorite(StremioTvChannel channel) async {
    final newState = !channel.isFavorite;
    await StorageService.setStremioTvChannelFavorited(channel.id, newState);
    if (!mounted) return;
    setState(() {
      channel.isFavorite = newState;
      _channels = _sortedChannels(_channels);
    });
  }

  // ============================================================================
  // Build
  // ============================================================================

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _channels.isEmpty
              ? const StremioTvEmptyState()
              : Column(
                  children: [
                    // Header
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
                      child: Row(
                        children: [
                          Icon(
                            Icons.smart_display_rounded,
                            color: theme.colorScheme.primary,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Stremio TV',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              color: theme.colorScheme.primaryContainer,
                            ),
                            child: Text(
                              '${_channels.length} channels',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onPrimaryContainer,
                              ),
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            onPressed: _refreshing ? null : _refresh,
                            icon: _refreshing
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.refresh_rounded),
                            tooltip: 'Refresh channels',
                          ),
                        ],
                      ),
                    ),
                    // Channel list
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.only(top: 8, bottom: 16),
                        itemCount: _channels.length,
                        itemBuilder: (context, index) {
                          final channel = _channels[index];

                          // Trigger lazy load for visible channels
                          if (!channel.hasItems &&
                              !_loadingChannelIds.contains(channel.id)) {
                            _ensureChannelItemsLoaded(channel);
                          }

                          final nowPlaying = _service.getNowPlaying(
                            channel,
                            rotationMinutes: _rotationMinutes,
                          );
                          final isLoading =
                              _loadingChannelIds.contains(channel.id);
                          final focusNode = index < _rowFocusNodes.length
                              ? _rowFocusNodes[index]
                              : FocusNode();

                          return ListenableBuilder(
                            listenable: focusNode,
                            builder: (context, _) {
                              if (focusNode.hasFocus &&
                                  _focusedIndex != index) {
                                WidgetsBinding.instance
                                    .addPostFrameCallback((_) {
                                  if (mounted) {
                                    setState(
                                        () => _focusedIndex = index);
                                  }
                                });
                              }
                              return StremioTvChannelRow(
                                channel: channel,
                                nowPlaying: nowPlaying,
                                isLoading: isLoading,
                                isFocused: focusNode.hasFocus,
                                focusNode: focusNode,
                                onTap: () => _playChannel(channel),
                                onLongPress: () =>
                                    _toggleFavorite(channel),
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
    );
  }
}
