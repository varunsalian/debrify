import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../../models/stremio_addon.dart';
import '../../models/stremio_tv/stremio_tv_channel.dart';
import '../../models/torrent.dart';
import '../../services/debrid_service.dart';
import '../../services/main_page_bridge.dart';
import '../../services/storage_service.dart';
import '../../services/video_player_launcher.dart';
import '../video_player/models/playlist_entry.dart';
import '../../services/torbox_service.dart';
import '../../services/pikpak_api_service.dart';
import '../../services/pikpak_tv_service.dart';
import '../../utils/file_utils.dart';
import 'stremio_tv_service.dart';
import 'widgets/stremio_tv_channel_row.dart';
import 'widgets/stremio_tv_empty_state.dart';
import 'widgets/stremio_tv_channel_filter_sheet.dart';
import 'widgets/stremio_tv_guide_sheet.dart';
import 'widgets/stremio_tv_local_catalogs_dialog.dart';

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
  int _rotationMinutes = 90;
  bool _autoRefresh = true;
  String _preferredQuality = 'auto';
  String _debridProvider = 'auto';
  int _maxStartPercent = -1; // -1 = no limit (slot progress), 0 = beginning
  bool _hideNowPlaying = false;
  double? _currentSlotProgress;
  String? _currentPlayTitle; // Overrides item.name when playing series episodes

  Timer? _refreshTimer;
  final List<FocusNode> _rowFocusNodes = [];
  int _focusedIndex = 0;

  // Mix salt (0-9, cycles on shuffle button)
  int _mixSalt = 0;

  // Header menu button
  final FocusNode _menuFocusNode = FocusNode(debugLabel: 'menuBtn');
  final MenuController _menuController = MenuController();

  // Search
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _searchQuery = '';

  // Lazy loading: track channels currently being fetched to avoid duplicates
  final Set<String> _loadingChannelIds = {};

  // Track mounted state for auto-play
  String? _pendingChannelId;

  // TV content focus handler (stored for proper unregistration)
  VoidCallback? _tvContentFocusHandler;

  @override
  void initState() {
    super.initState();
    _loadSettings().then((_) => _discoverAndLoad());

    // Search DPAD key handler
    _searchFocusNode.onKeyEvent = _handleSearchKeyEvent;
    _searchController.addListener(() {
      final q = _searchController.text.toLowerCase().trim();
      if (q != _searchQuery) {
        setState(() => _searchQuery = q);
      }
    });

    // Register TV sidebar focus handler (tab index 9 = Stremio TV)
    _tvContentFocusHandler = () {
      _searchFocusNode.requestFocus();
    };
    MainPageBridge.registerTvContentFocusHandler(9, _tvContentFocusHandler!);

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
    _menuFocusNode.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    for (final node in _rowFocusNodes) {
      node.dispose();
    }
    // Only clear if we're the active handler
    if (MainPageBridge.watchStremioTvChannel != null) {
      MainPageBridge.watchStremioTvChannel = null;
    }
    if (_tvContentFocusHandler != null) {
      MainPageBridge.unregisterTvContentFocusHandler(9, _tvContentFocusHandler!);
    }
    super.dispose();
  }

  Future<void> _loadSettings() async {
    _rotationMinutes = await StorageService.getStremioTvRotationMinutes();
    _autoRefresh = await StorageService.getStremioTvAutoRefresh();
    _preferredQuality = await StorageService.getStremioTvPreferredQuality();
    _debridProvider = await StorageService.getStremioTvDebridProvider();
    _maxStartPercent = await StorageService.getStremioTvMaxStartPercent();
    _hideNowPlaying = await StorageService.getStremioTvHideNowPlaying();
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

  Future<void> _openChannelFilter() async {
    final filterTree = await _service.getFilterTree();
    final disabledBefore = await StorageService.getStremioTvDisabledFilters();
    if (!mounted) return;

    await StremioTvChannelFilterSheet.show(
      context,
      filterTree: filterTree,
      disabledFilters: disabledBefore,
    );

    if (!mounted) return;
    // Re-read from storage to detect changes (covers both close button and swipe-dismiss)
    final disabledAfter = await StorageService.getStremioTvDisabledFilters();
    if (!mounted) return;

    if (disabledBefore.length != disabledAfter.length ||
        !disabledBefore.containsAll(disabledAfter)) {
      _refresh();
    }
  }

  Future<void> _openLocalCatalogs() async {
    final changed = await StremioTvLocalCatalogsDialog.show(context);
    if (changed == true && mounted) {
      _refresh();
    }
  }

  Future<void> _importFromFile() async {
    final imported = await StremioTvLocalCatalogsDialog.importFromFile(context);
    if (imported && mounted) _refresh();
  }

  Future<void> _importFromUrl() async {
    final imported = await StremioTvLocalCatalogsDialog.importFromUrl(context);
    if (imported && mounted) _refresh();
  }

  Future<void> _importFromJson() async {
    final imported = await StremioTvLocalCatalogsDialog.importFromJson(context);
    if (imported && mounted) _refresh();
  }

  Future<void> _importFromRepo() async {
    final imported = await StremioTvLocalCatalogsDialog.importFromRepo(context);
    if (imported && mounted) _refresh();
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
    if (channel.isLocal) return;
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
        if (idx == -1) return;

        // Rescue focus before disposing the node
        final removingFocused =
            idx < _rowFocusNodes.length && _rowFocusNodes[idx].hasFocus;
        if (removingFocused) {
          if (idx > 0 && idx - 1 < _rowFocusNodes.length) {
            _rowFocusNodes[idx - 1].requestFocus();
          } else if (idx + 1 < _rowFocusNodes.length) {
            _rowFocusNodes[idx + 1].requestFocus();
          } else {
            _searchFocusNode.requestFocus();
          }
        }

        _channels.removeAt(idx);
        if (idx < _rowFocusNodes.length) {
          _rowFocusNodes[idx].dispose();
          _rowFocusNodes.removeAt(idx);
        }

        // Keep _focusedIndex in sync
        if (removingFocused) {
          _focusedIndex = idx > 0 ? idx - 1 : 0;
        } else if (_focusedIndex > idx) {
          _focusedIndex--;
        }
      });
    } else {
      setState(() {});
    }
  }

  // ============================================================================
  // Playback
  // ============================================================================


  /// Extract normalized quality from a stream/torrent name.
  /// Returns '2160p', '1080p', '720p', '480p', or null.
  static final RegExp _qualityPattern = RegExp(
    r'\b(2160p|1080p|720p|480p|4K|UHD|FHD)\b',
    caseSensitive: false,
  );

  static String? _extractQuality(String name) {
    final match = _qualityPattern.firstMatch(name);
    if (match == null) return null;
    final q = match.group(1)!.toLowerCase();
    if (q == '4k' || q == 'uhd') return '2160p';
    if (q == 'fhd') return '1080p';
    return q;
  }

  /// Sort streams so those matching [_preferredQuality] come first.
  /// Within same-quality group, preserves original order.
  List<Torrent> _sortStreamsByQuality(List<Torrent> streams) {
    if (_preferredQuality == 'auto') return streams;
    final sorted = List<Torrent>.from(streams);
    sorted.sort((a, b) {
      final qa = _extractQuality(a.name);
      final qb = _extractQuality(b.name);
      final aMatch = qa == _preferredQuality ? 0 : 1;
      final bMatch = qb == _preferredQuality ? 0 : 1;
      return aMatch.compareTo(bMatch);
    });
    return sorted;
  }

  /// Minimum content size (50 MB) to consider a direct stream valid.
  /// Anything smaller is likely a placeholder/error video.
  static const int _minContentBytes = 50 * 1024 * 1024;

  /// Check if a direct stream URL has sufficient content size.
  /// Returns false for placeholder videos (< 200 MB).
  /// Follows up to 5 redirects to reach the final URL.
  Future<bool> _isValidStreamUrl(String url, {bool checkSize = true}) async {
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
          if (contentLength == 0 || !checkSize) return true;
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
      salt: _mixSalt,
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
    _currentSlotProgress = _computeStartProgress(
      channel.id,
      nowPlaying.progress,
    );

    if (!item.hasValidId) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${item.name} does not have a valid ID for stream search',
            ),
          ),
        );
      }
      return;
    }

    // For series, resolve a random episode first
    int? season;
    int? episode;
    if (item.type.toLowerCase() == 'series') {
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
                  'Picking a random episode of ${item.name}...',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      );

      final episodeSeed =
          '${channel.id}:${nowPlaying.slotStart.millisecondsSinceEpoch}';
      final resolved = await _service.resolveRandomEpisode(
        item: item,
        addon: channel.addon,
        seed: episodeSeed,
      );

      if (!mounted) return;
      Navigator.of(context).pop(); // Dismiss episode resolution dialog

      if (resolved == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Could not resolve episode for ${item.name}'),
            ),
          );
        }
        return;
      }

      season = resolved.season;
      episode = resolved.episode;
      _currentPlayTitle = '${item.name} (S${season}E$episode)';
      debugPrint('StremioTV: Playing ${item.name} S${season}E$episode');
    } else {
      _currentPlayTitle = null;
    }

    // Show loading dialog
    if (!mounted) return;
    bool streamDialogShown = false;
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
                season != null
                    ? 'Searching streams for ${item.name} S${season}E$episode...'
                    : 'Searching streams for ${item.name}...',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
    streamDialogShown = true;

    try {
      var results = await _service.searchStreams(
        type: item.type,
        imdbId: item.effectiveImdbId ?? item.id,
        season: season,
        episode: episode,
      );

      // For series, retry with episode 1 if the picked episode returns no streams
      if (item.type.toLowerCase() == 'series' &&
          episode != null &&
          episode != 1) {
        final torrents = results['torrents'] as List<Torrent>? ?? [];
        if (torrents.isEmpty) {
          debugPrint('StremioTV: No streams for S${season}E$episode, retrying with E1');
          final retryResults = await _service.searchStreams(
            type: item.type,
            imdbId: item.effectiveImdbId ?? item.id,
            season: season,
            episode: 1,
          );
          final retryTorrents = retryResults['torrents'] as List<Torrent>? ?? [];
          if (retryTorrents.isNotEmpty) {
            results = retryResults;
            episode = 1;
            _currentPlayTitle = '${item.name} (S${season}E1)';
          }
        }
      }

      if (!mounted) return;
      Navigator.of(context).pop(); // Dismiss loading dialog
      streamDialogShown = false;

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
      // Priority: direct URL streams first (validated, sorted by quality), then torrents via debrid
      if (_preferredQuality != 'auto') {
        debugPrint('StremioTV: Preferred quality: $_preferredQuality');
      }
      final directStreams = _sortStreamsByQuality(
        torrents.where((t) => t.isDirectStream).toList(),
      );
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

      // For torrent streams, try to resolve via debrid (up to 5 attempts)
      var torrentStreams = _sortStreamsByQuality(
        torrents.where((t) => t.streamType == StreamType.torrent).toList(),
      );

      // For TorBox (explicitly selected), batch-check cache and only attempt cached torrents
      if (torrentStreams.isNotEmpty && _debridProvider == 'torbox') {
        final tbKey = await StorageService.getTorboxApiKey();
        if (tbKey != null && tbKey.isNotEmpty) {
          final hashes = torrentStreams
              .map((t) => t.infohash.trim().toLowerCase())
              .where((h) => h.isNotEmpty)
              .toList();
          if (hashes.isNotEmpty) {
            final cachedHashes = await TorboxService.checkCachedTorrents(
              apiKey: tbKey,
              infoHashes: hashes,
            );
            if (cachedHashes.isNotEmpty) {
              final cachedNormalized = cachedHashes
                  .map((h) => h.trim().toLowerCase())
                  .toSet();
              torrentStreams = torrentStreams
                  .where((t) => cachedNormalized
                      .contains(t.infohash.trim().toLowerCase()))
                  .toList();
              debugPrint(
                'StremioTV: TorBox cache check: ${cachedHashes.length} cached '
                'out of ${hashes.length} torrents',
              );
            } else {
              debugPrint('StremioTV: TorBox cache check: none cached');
              torrentStreams = [];
            }
          }
        }
      }

      final maxTorrentAttempts = torrentStreams.length.clamp(0, 15);
      for (int i = 0; i < maxTorrentAttempts; i++) {
        if (!mounted) return;
        final success =
            await _playTorrentViaDebrid(torrentStreams[i], item);
        if (success) return;
        debugPrint(
          'StremioTV: Torrent ${i + 1}/$maxTorrentAttempts failed, '
          '${i + 1 < maxTorrentAttempts ? "trying next..." : "giving up."}',
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No playable streams found for ${item.name}')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      if (streamDialogShown) Navigator.of(context).pop();
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
        title: _currentPlayTitle ?? item.name,
        subtitle: torrent.source,
        startAtPercent: _currentSlotProgress,
        contentImdbId: item.effectiveImdbId,
        contentType: item.type,
      ),
    );
  }

  /// Returns true if playback was launched successfully, false on failure.
  Future<bool> _playTorrentViaDebrid(
    Torrent torrent,
    StremioMeta item,
  ) async {
    // Try the selected provider first
    if (_debridProvider == 'realdebrid') {
      final rdKey = await StorageService.getApiKey();
      if (rdKey != null && rdKey.isNotEmpty) {
        return _playViaRealDebrid(torrent, item, rdKey);
      }
    } else if (_debridProvider == 'torbox') {
      final tbKey = await StorageService.getTorboxApiKey();
      if (tbKey != null && tbKey.isNotEmpty) {
        return _playViaTorbox(torrent, item);
      }
    } else if (_debridProvider == 'pikpak') {
      final pikpakEnabled = await StorageService.getPikPakEnabled();
      if (pikpakEnabled) {
        return _playViaPikPak(torrent, item);
      }
    }

    // Auto or fallback if selected provider is unavailable
    final rdKey = await StorageService.getApiKey();
    if (rdKey != null && rdKey.isNotEmpty) {
      return _playViaRealDebrid(torrent, item, rdKey);
    }

    final tbKey = await StorageService.getTorboxApiKey();
    if (tbKey != null && tbKey.isNotEmpty) {
      return _playViaTorbox(torrent, item);
    }

    final pikpakEnabled = await StorageService.getPikPakEnabled();
    if (pikpakEnabled) {
      return _playViaPikPak(torrent, item);
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
    return false;
  }

  Future<bool> _playViaRealDebrid(
    Torrent torrent,
    StremioMeta item,
    String apiKey,
  ) async {
    bool dialogShown = false;
    try {
      // Show progress
      if (!mounted) return false;
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
      dialogShown = true;

      final magnet =
          'magnet:?xt=urn:btih:${torrent.infohash}&dn=${Uri.encodeComponent(torrent.name)}';

      // Use video file selection mode with fallback chain
      final result = await DebridService.addTorrentToDebridPreferVideos(
        apiKey,
        magnet,
      );

      final links = result['links'] as List<dynamic>? ?? [];
      final updatedInfo =
          result['updatedInfo'] as Map<String, dynamic>? ?? {};
      final files =
          updatedInfo['files'] as List<dynamic>? ?? [];

      if (!mounted) return false;
      Navigator.of(context).pop();
      dialogShown = false;

      if (links.isEmpty) {
        return false;
      }

      // For movies, pick the largest file; otherwise use the first link
      String linkToUnrestrict = links.first.toString();

      if (item.type.toLowerCase() == 'movie' && links.length > 1) {
        // Selected files map to links in order — find index of the largest
        final selectedFiles = files
            .where((f) => f is Map && f['selected'] == 1)
            .toList();

        if (selectedFiles.length == links.length) {
          int largestIndex = 0;
          int largestSize = 0;
          for (int i = 0; i < selectedFiles.length; i++) {
            final size = (selectedFiles[i]['bytes'] as int?) ?? 0;
            if (size > largestSize) {
              largestSize = size;
              largestIndex = i;
            }
          }
          linkToUnrestrict = links[largestIndex].toString();
        }
      }

      final unrestrictResult = await DebridService.unrestrictLink(
        apiKey,
        linkToUnrestrict,
      );
      final videoUrl = unrestrictResult['download'] as String?;

      if (videoUrl != null && videoUrl.isNotEmpty && mounted) {
        await VideoPlayerLauncher.push(
          context,
          VideoPlayerLaunchArgs(
            videoUrl: videoUrl,
            title: _currentPlayTitle ?? item.name,
            startAtPercent: _currentSlotProgress,
            contentImdbId: item.effectiveImdbId,
            contentType: item.type,
          ),
        );
        return true;
      }
      return false;
    } catch (e) {
      if (!mounted) return false;
      if (dialogShown) Navigator.of(context).pop();
      debugPrint('StremioTV: Real Debrid error: $e');
      return false;
    }
  }

  Future<bool> _playViaTorbox(
    Torrent torrent,
    StremioMeta item,
  ) async {
    bool dialogShown = false;
    try {
      if (!mounted) return false;
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
      dialogShown = true;

      final tbKey = await StorageService.getTorboxApiKey();
      if (tbKey == null || tbKey.isEmpty) {
        if (!mounted) return false;
        Navigator.of(context).pop();
        dialogShown = false;
        return false;
      }

      final magnet =
          'magnet:?xt=urn:btih:${torrent.infohash}&dn=${Uri.encodeComponent(torrent.name)}';
      final result = await TorboxService.createTorrent(
        apiKey: tbKey,
        magnet: magnet,
      );
      final data = result['data'];
      final torrentId = data is Map
          ? (data['torrent_id'] ?? data['id'])
          : (result['torrent_id'] ?? result['id']);

      if (torrentId == null) {
        if (!mounted) return false;
        Navigator.of(context).pop();
        dialogShown = false;
        return false;
      }

      // Wait for processing
      await Future.delayed(const Duration(seconds: 3));

      // Get torrent info to find a file to download
      final torrentInfo = await TorboxService.getTorrentById(
        tbKey,
        torrentId is int ? torrentId : int.parse(torrentId.toString()),
      );

      if (!mounted) return false;
      Navigator.of(context).pop();
      dialogShown = false;

      if (torrentInfo == null) {
        return false;
      }

      // Filter to video files only
      final allFiles = torrentInfo.files;
      final videoFiles = allFiles
          .where((f) => FileUtils.isVideoFile(f.name))
          .toList();
      final files = videoFiles.isNotEmpty ? videoFiles : allFiles;
      if (files.isEmpty) {
        return false;
      }

      // For movies, pick the largest video file
      var targetFile = files.first;
      if (item.type.toLowerCase() == 'movie' && files.length > 1) {
        for (final f in files) {
          if (f.size > targetFile.size) {
            targetFile = f;
          }
        }
      }

      final downloadLink = await TorboxService.requestFileDownloadLink(
        apiKey: tbKey,
        torrentId: torrentId is int ? torrentId : int.parse(torrentId.toString()),
        fileId: targetFile.id,
      );

      if (downloadLink.isNotEmpty && mounted) {
        await VideoPlayerLauncher.push(
          context,
          VideoPlayerLaunchArgs(
            videoUrl: downloadLink,
            title: _currentPlayTitle ?? item.name,
            startAtPercent: _currentSlotProgress,
            contentImdbId: item.effectiveImdbId,
            contentType: item.type,
          ),
        );
        return true;
      }
      return false;
    } catch (e) {
      if (!mounted) return false;
      if (dialogShown) Navigator.of(context).pop();
      debugPrint('StremioTV: Torbox error: $e');
      return false;
    }
  }

  Future<bool> _playViaPikPak(
    Torrent torrent,
    StremioMeta item,
  ) async {
    bool dialogShown = false;
    try {
      if (!mounted) return false;
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
      dialogShown = true;

      // Use PikPakTvService for caching detection, progress polling, folder handling
      final prepared = await PikPakTvService.instance.prepareTorrent(
        infohash: torrent.infohash.trim().toLowerCase(),
        torrentName: torrent.name,
      );

      if (prepared == null) {
        // Not cached or not ready — let retry loop try next torrent
        if (!mounted) return false;
        Navigator.of(context).pop();
        dialogShown = false;
        return false;
      }

      // Determine the streaming URL
      String? streamUrl = prepared['url'] as String?;

      // For multi-file torrents (folders), pick the largest video file for movies
      final allVideoFiles =
          prepared['allVideoFiles'] as List<dynamic>?;
      if (allVideoFiles != null &&
          allVideoFiles.isNotEmpty &&
          item.type.toLowerCase() == 'movie') {
        // Find largest video file by size
        Map<String, dynamic>? largestFile;
        int largestSize = 0;
        for (final file in allVideoFiles) {
          if (file is Map<String, dynamic>) {
            final size = (file['size'] as int?) ?? 0;
            if (size > largestSize) {
              largestSize = size;
              largestFile = file;
            }
          }
        }

        if (largestFile != null) {
          final largestFileId = largestFile['id'] as String?;
          if (largestFileId != null && largestFileId.isNotEmpty) {
            final api = PikPakApiService.instance;
            final fileData = await api.getFileDetails(largestFileId);
            final url = api.getStreamingUrl(fileData);
            if (url != null && url.isNotEmpty) {
              streamUrl = url;
            }
          }
        }
      }

      if (!mounted) return false;
      Navigator.of(context).pop();
      dialogShown = false;

      if (streamUrl != null && streamUrl.isNotEmpty) {
        final title = _currentPlayTitle ?? item.name;
        await VideoPlayerLauncher.push(
          context,
          VideoPlayerLaunchArgs(
            videoUrl: streamUrl,
            title: title,
            startAtPercent: _currentSlotProgress,
            contentImdbId: item.effectiveImdbId,
            contentType: item.type,
            playlist: [
              PlaylistEntry(
                url: streamUrl,
                title: title,
                provider: 'pikpak',
              ),
            ],
            startIndex: 0,
          ),
        );
        return true;
      }
      return false;
    } catch (e) {
      if (!mounted) return false;
      if (dialogShown) Navigator.of(context).pop();
      debugPrint('StremioTV: PikPak error: $e');
      return false;
    }
  }

  /// Compute the start progress for a channel based on the max start percent setting.
  /// Returns null (beginning), the raw slot progress, or a deterministic random
  /// value within [0, maxStartPercent] per channel.
  double? _computeStartProgress(String channelId, double rawProgress) {
    if (_maxStartPercent == 0) return null; // always from beginning
    if (_maxStartPercent < 0) return rawProgress; // no limit
    final cap = _maxStartPercent / 100.0;
    if (rawProgress <= cap) return rawProgress; // slot hasn't reached cap yet
    // Deterministic random within [0, cap] based on channel ID
    final hash = channelId.hashCode.abs();
    return (hash % 1000) / 1000.0 * cap;
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
  // Channel Guide
  // ============================================================================

  Future<void> _showGuide(StremioTvChannel channel) async {
    if (!channel.hasItems) {
      await _ensureChannelItemsLoaded(channel);
      if (!mounted) return;
    }
    if (channel.items.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No items available for this channel')),
        );
      }
      return;
    }

    final schedule = _service.getSchedule(
      channel,
      count: 5,
      rotationMinutes: _rotationMinutes,
      salt: _mixSalt,
    );
    if (schedule.isEmpty || !mounted) return;

    final tappedIndex = await StremioTvGuideSheet.show(
      context,
      channel: channel,
      schedule: schedule,
    );

    if (tappedIndex != null && mounted) {
      _playChannel(channel);
    }
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
  // Search
  // ============================================================================

  List<StremioTvChannel> get _filteredChannels {
    if (_searchQuery.isEmpty) return _channels;
    return _channels.where((ch) {
      final q = _searchQuery;
      return ch.displayName.toLowerCase().contains(q) ||
          ch.addon.name.toLowerCase().contains(q) ||
          ch.catalog.name.toLowerCase().contains(q) ||
          (ch.genre?.toLowerCase().contains(q) ?? false) ||
          ch.type.toLowerCase().contains(q);
    }).toList();
  }

  KeyEventResult _handleSearchKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final text = _searchController.text;
    final selection = _searchController.selection;
    final isAtEnd = !selection.isValid ||
        (selection.baseOffset == text.length &&
            selection.extentOffset == text.length);
    final isAtStart = !selection.isValid ||
        (selection.baseOffset == 0 && selection.extentOffset == 0);

    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (text.isEmpty || isAtEnd) {
        // Focus first channel row
        final filtered = _filteredChannels;
        if (filtered.isNotEmpty && _rowFocusNodes.isNotEmpty) {
          final firstIdx = _channels.indexOf(filtered.first);
          if (firstIdx >= 0 && firstIdx < _rowFocusNodes.length) {
            _rowFocusNodes[firstIdx].requestFocus();
          }
        }
        return KeyEventResult.handled;
      }
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (text.isEmpty || isAtStart) {
        _menuFocusNode.requestFocus();
        return KeyEventResult.handled;
      }
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      if (text.isEmpty || isAtStart) {
        MainPageBridge.focusTvSidebar?.call();
        return KeyEventResult.handled;
      }
    }

    if (event.logicalKey == LogicalKeyboardKey.escape ||
        event.logicalKey == LogicalKeyboardKey.goBack) {
      if (text.isNotEmpty) {
        _searchController.clear();
        return KeyEventResult.handled;
      }
    }

    return KeyEventResult.ignored;
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
                              _searchQuery.isNotEmpty
                                  ? '${_filteredChannels.length}/${_channels.length} channels'
                                  : '${_channels.length} channels',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onPrimaryContainer,
                              ),
                            ),
                          ),
                          const Spacer(),
                          Focus(
                            focusNode: _menuFocusNode,
                            onKeyEvent: (node, event) {
                              if (event is! KeyDownEvent) return KeyEventResult.ignored;
                              // When menu is open, let menu handle its own key events
                              if (_menuController.isOpen) return KeyEventResult.ignored;
                              if (event.logicalKey == LogicalKeyboardKey.arrowUp ||
                                  event.logicalKey == LogicalKeyboardKey.arrowRight) {
                                return KeyEventResult.handled;
                              }
                              if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                                MainPageBridge.focusTvSidebar?.call();
                                return KeyEventResult.handled;
                              }
                              if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                                _searchFocusNode.requestFocus();
                                return KeyEventResult.handled;
                              }
                              if (event.logicalKey == LogicalKeyboardKey.select ||
                                  event.logicalKey == LogicalKeyboardKey.enter) {
                                _menuController.open();
                                return KeyEventResult.handled;
                              }
                              return KeyEventResult.ignored;
                            },
                            child: ListenableBuilder(
                              listenable: _menuFocusNode,
                              builder: (context, child) => Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(8),
                                  color: _menuFocusNode.hasFocus
                                      ? theme.colorScheme.primaryContainer
                                      : null,
                                  border: _menuFocusNode.hasFocus
                                      ? Border.all(
                                          color: theme.colorScheme.primary,
                                          width: 2,
                                        )
                                      : null,
                                ),
                                child: MenuAnchor(
                                  controller: _menuController,
                                  menuChildren: [
                                    MenuItemButton(
                                      leadingIcon: const Icon(Icons.shuffle_rounded),
                                      onPressed: () {
                                        setState(() => _mixSalt = (_mixSalt + 1) % 10);
                                      },
                                      child: Text('Shuffle (Mix ${_mixSalt + 1})'),
                                    ),
                                    MenuItemButton(
                                      leadingIcon: const Icon(Icons.refresh_rounded),
                                      onPressed: _refreshing ? null : () => _refresh(),
                                      child: const Text('Refresh'),
                                    ),
                                    MenuItemButton(
                                      leadingIcon: const Icon(Icons.tune_rounded),
                                      onPressed: () => _openChannelFilter(),
                                      child: const Text('Filter channels'),
                                    ),
                                    SubmenuButton(
                                      leadingIcon: const Icon(Icons.playlist_add_rounded),
                                      menuChildren: [
                                        MenuItemButton(
                                          leadingIcon: const Icon(Icons.list_rounded),
                                          onPressed: _openLocalCatalogs,
                                          child: const Text('Manage'),
                                        ),
                                        MenuItemButton(
                                          leadingIcon: const Icon(Icons.file_upload_outlined),
                                          onPressed: _importFromFile,
                                          child: const Text('From File'),
                                        ),
                                        MenuItemButton(
                                          leadingIcon: const Icon(Icons.link_rounded),
                                          onPressed: _importFromUrl,
                                          child: const Text('From URL'),
                                        ),
                                        MenuItemButton(
                                          leadingIcon: const Icon(Icons.data_object_rounded),
                                          onPressed: _importFromJson,
                                          child: const Text('Paste JSON'),
                                        ),
                                        MenuItemButton(
                                          leadingIcon: const Icon(Icons.source_rounded),
                                          onPressed: _importFromRepo,
                                          child: const Text('From Repository'),
                                        ),
                                      ],
                                      child: const Text('Local Catalogs'),
                                    ),
                                  ],
                                  builder: (context, controller, child) =>
                                      IconButton(
                                    icon: const Icon(Icons.more_vert_rounded),
                                    tooltip: 'Options',
                                    onPressed: () {
                                      if (controller.isOpen) {
                                        controller.close();
                                      } else {
                                        controller.open();
                                      }
                                    },
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Search box
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                      child: TextField(
                        controller: _searchController,
                        focusNode: _searchFocusNode,
                        decoration: InputDecoration(
                          hintText: 'Search channels...',
                          prefixIcon: const Icon(Icons.search, size: 20),
                          suffixIcon: _searchQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear, size: 20),
                                  onPressed: _searchController.clear,
                                )
                              : null,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        textInputAction: TextInputAction.search,
                      ),
                    ),
                    // Channel list
                    Expanded(
                      child: Builder(
                        builder: (context) {
                          if (_channels.isEmpty) {
                            return const StremioTvEmptyState();
                          }
                          final filtered = _filteredChannels;
                          if (filtered.isEmpty && _searchQuery.isNotEmpty) {
                            return Center(
                              child: Text(
                                'No channels match "$_searchQuery"',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            );
                          }
                          return ListView.builder(
                            padding:
                                const EdgeInsets.only(top: 8, bottom: 16),
                            itemCount: filtered.length,
                            itemBuilder: (context, index) {
                              final channel = filtered[index];
                              final realIndex = _channels.indexOf(channel);

                              // Trigger lazy load for visible channels
                              if (!channel.hasItems &&
                                  !_loadingChannelIds
                                      .contains(channel.id)) {
                                _ensureChannelItemsLoaded(channel);
                              }

                              final nowPlaying = _service.getNowPlaying(
                                channel,
                                rotationMinutes: _rotationMinutes,
                                salt: _mixSalt,
                              );
                              // Compute display progress (capped/randomized per settings)
                              double? cappedProgress;
                              if (nowPlaying != null) {
                                if (_maxStartPercent == 0) {
                                  cappedProgress = 0.0;
                                } else {
                                  cappedProgress = _computeStartProgress(
                                    channel.id,
                                    nowPlaying.progress,
                                  );
                                }
                              }
                              final isLoading =
                                  _loadingChannelIds.contains(channel.id);
                              final focusNode =
                                  realIndex < _rowFocusNodes.length
                                      ? _rowFocusNodes[realIndex]
                                      : FocusNode();

                              return ListenableBuilder(
                                listenable: focusNode,
                                builder: (context, _) {
                                  if (focusNode.hasFocus &&
                                      _focusedIndex != realIndex) {
                                    WidgetsBinding.instance
                                        .addPostFrameCallback((_) {
                                      if (mounted) {
                                        setState(() =>
                                            _focusedIndex = realIndex);
                                      }
                                    });
                                  }
                                  return StremioTvChannelRow(
                                    channel: channel,
                                    nowPlaying: nowPlaying,
                                    isLoading: isLoading,
                                    isFocused: focusNode.hasFocus,
                                    focusNode: focusNode,
                                    hideNowPlaying: _hideNowPlaying,
                                    onTap: () => _playChannel(channel),
                                    onLongPress: () =>
                                        _toggleFavorite(channel),
                                    onGuidePressed: _hideNowPlaying
                                        ? null
                                        : () => _showGuide(channel),
                                    onLeftPress:
                                        MainPageBridge.focusTvSidebar,
                                    onUpPress: index == 0
                                        ? () => _searchFocusNode
                                            .requestFocus()
                                        : null,
                                    displayProgress: cappedProgress,
                                  );
                                },
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
