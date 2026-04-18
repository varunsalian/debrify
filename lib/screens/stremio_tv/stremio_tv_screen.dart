import 'dart:async';

import 'package:collection/collection.dart';
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
import '../../utils/formatters.dart';
import '../../services/torrent_service.dart';
import 'stremio_tv_service.dart';
import 'widgets/stremio_tv_channel_row.dart';
import 'widgets/stremio_tv_empty_state.dart';
import 'widgets/stremio_tv_channel_filter_sheet.dart';
import 'widgets/stremio_tv_guide_sheet.dart';
import 'widgets/psych_loading_overlay.dart';
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
  int _seriesRotationMinutes = 45;
  bool _randomEpisodes = false;
  bool _autoRefresh = true;
  String _preferredQuality = 'auto';
  String _debridProvider = 'auto';
  int _maxStartPercent = -1; // -1 = no limit (slot progress), 0 = beginning
  bool _hideNowPlaying = false;
  double? _currentSlotProgress;
  int _playGeneration = 0;
  int _dialogGeneration = -1;
  String? _currentPlayTitle; // Overrides item.name when playing series episodes

  /// Get the rotation duration for a channel based on its content type.
  int _rotationFor(StremioTvChannel channel) =>
      channel.type == 'series' ? _seriesRotationMinutes : _rotationMinutes;

  Timer? _refreshTimer;
  final List<FocusNode> _rowFocusNodes = [];
  int _focusedIndex = 0;

  // Mix salt (0-9, cycles on shuffle button)
  int _mixSalt = 0;

  // Header buttons
  final FocusNode _searchBtnFocusNode = FocusNode(debugLabel: 'searchBtn');
  final FocusNode _menuFocusNode = FocusNode(debugLabel: 'menuBtn');
  final FocusNode _submenuFocusNode = FocusNode(debugLabel: 'localCatalogs');
  final MenuController _menuController = MenuController();

  // Search
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _searchQuery = '';
  bool _showSearchField = false;

  // Lazy loading: track channels currently being fetched to avoid duplicates
  final Set<String> _loadingChannelIds = {};

  // Track mounted state for auto-play
  String? _pendingChannelId;
  bool _startupAutoPlayActive = false;

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
      _searchBtnFocusNode.requestFocus();
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
    _searchBtnFocusNode.dispose();
    _menuFocusNode.dispose();
    _submenuFocusNode.dispose();
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
      MainPageBridge.unregisterTvContentFocusHandler(
        9,
        _tvContentFocusHandler!,
      );
    }
    super.dispose();
  }

  Future<void> _loadSettings() async {
    _rotationMinutes = await StorageService.getStremioTvRotationMinutes();
    _seriesRotationMinutes =
        await StorageService.getStremioTvSeriesRotationMinutes();
    _randomEpisodes = await StorageService.getStremioTvRandomEpisodes();
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
      _startupAutoPlayActive = true;
      await _ensureChannelLoaded(id);
      if (mounted) _playChannelById(id);
    }
  }

  void _notifyStartupAutoLaunchFailed(String reason) {
    if (!_startupAutoPlayActive) return;
    _startupAutoPlayActive = false;
    MainPageBridge.notifyAutoLaunchFailed(reason);
  }

  void _notifyStartupPlayerLaunching() {
    if (!_startupAutoPlayActive) return;
    _startupAutoPlayActive = false;
    MainPageBridge.notifyPlayerLaunching();
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

  /// Wraps a MenuItemButton inside a submenu with DPAD navigation:
  /// - Left/Right arrow: close submenu, return to parent SubmenuButton
  /// - Escape/Back: close entire menu, return to 3-dot button
  Widget _submenuItem({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    bool autofocus = false,
  }) {
    return Focus(
      canRequestFocus: false,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.arrowRight ||
            event.logicalKey == LogicalKeyboardKey.arrowLeft) {
          // Close just the submenu — focus parent SubmenuButton
          _submenuFocusNode.requestFocus();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.escape ||
            event.logicalKey == LogicalKeyboardKey.goBack) {
          // Close entire menu
          _menuController.close();
          _menuFocusNode.requestFocus();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: MenuItemButton(
        autofocus: autofocus,
        leadingIcon: Icon(icon),
        onPressed: onPressed,
        child: Text(label),
      ),
    );
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

  Future<void> _importFromTrakt() async {
    final imported = await StremioTvLocalCatalogsDialog.importFromTrakt(
      context,
    );
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
  /// Returns false for non-2xx responses, missing content-length,
  /// or placeholder videos (< 50 MB).
  /// Follows up to 5 redirects to reach the final URL.
  Future<bool> _isValidStreamUrl(String url) async {
    try {
      final client = http.Client();
      try {
        var currentUrl = url;
        for (int i = 0; i < 5; i++) {
          final request = http.Request('HEAD', Uri.parse(currentUrl));
          request.followRedirects = false;
          final streamed = await client
              .send(request)
              .timeout(const Duration(seconds: 5));
          // Drain response stream to release resources
          await streamed.stream.drain();

          if (streamed.statusCode >= 300 && streamed.statusCode < 400) {
            final location = streamed.headers['location'];
            if (location == null || location.isEmpty) {
              debugPrint(
                'StremioTV: HEAD $currentUrl → ${streamed.statusCode} (redirect, no location)',
              );
              return false;
            }
            // Resolve relative redirects
            currentUrl = Uri.parse(currentUrl).resolve(location).toString();
            debugPrint(
              'StremioTV: HEAD → ${streamed.statusCode}, following redirect',
            );
            continue;
          }

          // Reject non-2xx responses
          if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
            debugPrint(
              'StremioTV: HEAD $currentUrl → ${streamed.statusCode}, rejecting non-2xx',
            );
            return false;
          }

          final contentLength = int.tryParse(
            streamed.headers['content-length'] ?? '',
          );
          if (contentLength == null) {
            debugPrint(
              'StremioTV: HEAD $currentUrl → ${streamed.statusCode}, no content-length',
            );
            return false;
          }
          final sizeMb = (contentLength / (1024 * 1024)).toStringAsFixed(1);
          debugPrint(
            'StremioTV: HEAD $currentUrl → ${streamed.statusCode}, size: ${sizeMb}MB',
          );
          return contentLength >= _minContentBytes;
        }
        // Too many redirects
        debugPrint('StremioTV: HEAD $url → too many redirects, rejecting');
        return false;
      } finally {
        client.close();
      }
    } catch (e) {
      debugPrint('StremioTV: HEAD check failed for $url: $e');
      return false;
    }
  }

  Future<void> _playChannel(StremioTvChannel channel) async {
    final myGeneration = ++_playGeneration;

    // Ensure items are loaded before trying to play
    if (!channel.hasItems) {
      await _ensureChannelItemsLoaded(channel);
      if (!mounted || _playGeneration != myGeneration) return;
    }

    final nowPlaying = _service.getNowPlaying(
      channel,
      rotationMinutes: _rotationFor(channel),
      salt: _mixSalt,
    );
    if (nowPlaying == null) {
      _notifyStartupAutoLaunchFailed('No items available for channel');
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
      _notifyStartupAutoLaunchFailed('Channel item has no valid ID');
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
      showPsychLoading(
        context,
        'Spinning the wheel of fate for ${item.name}...',
      );

      final episodeSeed = _randomEpisodes
          ? '${channel.id}:${DateTime.now().millisecondsSinceEpoch}'
          : '${channel.id}:${nowPlaying.slotStart.millisecondsSinceEpoch}';
      final resolved = await _service.resolveRandomEpisode(
        item: item,
        addon: channel.addon,
        seed: episodeSeed,
      );

      if (!mounted || _playGeneration != myGeneration) return;
      Navigator.of(context).pop(); // Dismiss episode resolution dialog

      if (resolved == null) {
        _notifyStartupAutoLaunchFailed('Could not resolve episode');
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

    // Show loading dialog with updatable message
    if (!mounted || _playGeneration != myGeneration) return;
    _dialogGeneration = myGeneration;
    final loadingStatus = showPsychLoadingUpdatable(
      context,
      season != null
          ? 'Summoning ${item.name} S${season}E$episode from the void...'
          : 'Warping into the ${item.name} dimension...',
      onCancel: () {
        _playGeneration++;
        _dialogGeneration = -1;
        _notifyStartupAutoLaunchFailed('Playback canceled');
        if (mounted) Navigator.of(context).pop();
      },
    );

    try {
      final isMovie = item.type.toLowerCase() == 'movie';
      var results = await TorrentService.searchByImdbWithStremio(
        item.effectiveImdbId ?? item.id,
        isMovie: isMovie,
        season: season,
        episode: episode,
        contentType: item.type,
        stremioTimeout: const Duration(seconds: 7),
        engineTimeout: const Duration(seconds: 10),
      );

      // For series, retry with episode 1 if the picked episode returns no streams
      if (!isMovie && episode != null && episode != 1) {
        final torrents = results['torrents'] as List<Torrent>? ?? [];
        if (torrents.isEmpty) {
          debugPrint(
            'StremioTV: No streams for S${season}E$episode, retrying with E1',
          );
          final retryResults = await TorrentService.searchByImdbWithStremio(
            item.effectiveImdbId ?? item.id,
            isMovie: false,
            season: season,
            episode: 1,
            contentType: item.type,
            stremioTimeout: const Duration(seconds: 7),
            engineTimeout: const Duration(seconds: 10),
          );
          final retryTorrents =
              retryResults['torrents'] as List<Torrent>? ?? [];
          if (retryTorrents.isNotEmpty) {
            results = retryResults;
            episode = 1;
            _currentPlayTitle = '${item.name} (S${season}E1)';
          }
        }
      }

      if (!mounted || _playGeneration != myGeneration) {
        if (_dialogGeneration == myGeneration && mounted) {
          _dialogGeneration = -1;
          Navigator.of(context).pop();
        }
        return;
      }

      final torrents = results['torrents'] as List<Torrent>? ?? [];
      final directCount = torrents.where((t) => t.isDirectStream).length;
      final torrentCount = torrents
          .where((t) => !t.isDirectStream && !t.isExternalStream)
          .length;
      loadingStatus.value =
          'Found $directCount direct + $torrentCount torrent streams, resolving...';

      if (torrents.isEmpty) {
        _notifyStartupAutoLaunchFailed('No streams found');
        if (mounted) {
          Navigator.of(context).pop();
          _dialogGeneration = -1;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('No streams found for ${item.name}')),
          );
        }
        return;
      }

      // Build playable sources list (exclude external URLs and tiny junk files)
      // Direct streams under 5MB are placeholder/tracking files (e.g. mytrakt sync)
      // Filter out 480p torrents — rarely cached on debrid services
      var playableSources = torrents
          .where((t) => !t.isExternalStream)
          .where((t) => !t.isDirectStream || t.sizeBytes >= 5 * 1024 * 1024)
          .where(
            (t) =>
                t.streamType != StreamType.torrent ||
                _extractQuality(t.name) != '480p',
          )
          .toList();

      // For TorBox, filter torrent sources to only cached ones
      if (_debridProvider == 'torbox') {
        final tbKey = await StorageService.getTorboxApiKey();
        if (tbKey != null && tbKey.isNotEmpty) {
          final torrentHashes = playableSources
              .where((t) => t.streamType == StreamType.torrent)
              .map((t) => t.infohash.trim().toLowerCase())
              .where((h) => h.isNotEmpty)
              .toList();
          if (torrentHashes.isNotEmpty) {
            if (!mounted) return;
            final cachedHashes = await TorboxService.checkCachedTorrents(
              apiKey: tbKey,
              infoHashes: torrentHashes,
            );
            final cachedSet = cachedHashes
                .map((h) => h.trim().toLowerCase())
                .toSet();
            debugPrint(
              'StremioTV: TorBox cache check: ${cachedSet.length} cached '
              'out of ${torrentHashes.length} torrents',
            );
            // Keep direct streams + only cached torrents
            playableSources = playableSources
                .where(
                  (t) =>
                      t.streamType != StreamType.torrent ||
                      cachedSet.contains(t.infohash.trim().toLowerCase()),
                )
                .toList();
          }
        }
      }

      if (playableSources.isEmpty) {
        _notifyStartupAutoLaunchFailed('No playable streams found');
        if (mounted) {
          Navigator.of(context).pop();
          _dialogGeneration = -1;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('No playable streams found for ${item.name}'),
            ),
          );
        }
        return;
      }

      // Try to find the best stream to auto-play
      // Priority: direct URL streams first (validated, sorted by quality), then torrents via debrid
      if (_preferredQuality != 'auto') {
        debugPrint('StremioTV: Preferred quality: $_preferredQuality');
      }

      String? firstPlayableUrl;
      int firstPlayableIndex = 0;

      final directStreams = _sortStreamsByQuality(
        playableSources.where((t) => t.isDirectStream).toList(),
      );
      final maxDirectAttempts = directStreams.length.clamp(0, 20);
      for (int d = 0; d < maxDirectAttempts; d++) {
        final stream = directStreams[d];
        if (stream.directUrl == null || stream.directUrl!.isEmpty) continue;
        if (!mounted || _playGeneration != myGeneration) return;
        final valid = await _isValidStreamUrl(stream.directUrl!);
        if (!mounted || _playGeneration != myGeneration) return;
        if (valid) {
          firstPlayableUrl = stream.directUrl!;
          firstPlayableIndex = playableSources.indexWhere(
            (t) => t.directUrl == stream.directUrl && t.name == stream.name,
          );
          if (firstPlayableIndex < 0) firstPlayableIndex = 0;
          break;
        }
        debugPrint(
          'StremioTV: Skipping invalid direct stream: ${stream.source}',
        );
      }

      // If no direct stream worked, try torrents via debrid
      if (firstPlayableUrl == null) {
        // TorBox torrents are already filtered to cached-only in playableSources
        final torrentStreams = _sortStreamsByQuality(
          playableSources
              .where((t) => t.streamType == StreamType.torrent)
              .toList(),
        );

        final maxTorrentAttempts = torrentStreams.length.clamp(0, 20);
        for (int i = 0; i < maxTorrentAttempts; i++) {
          if (!mounted || _playGeneration != myGeneration) return;
          final url = await _resolveTorrentUrl(
            torrentStreams[i],
            item,
            _debridProvider,
          );
          if (url != null && url.isNotEmpty) {
            firstPlayableUrl = url;
            firstPlayableIndex = playableSources.indexWhere(
              (t) =>
                  t.infohash == torrentStreams[i].infohash &&
                  t.name == torrentStreams[i].name,
            );
            if (firstPlayableIndex < 0) firstPlayableIndex = 0;
            break;
          }
          debugPrint(
            'StremioTV: Torrent ${i + 1}/$maxTorrentAttempts failed, '
            '${i + 1 < maxTorrentAttempts ? "trying next..." : "giving up."}',
          );
        }
      }

      if (firstPlayableUrl == null || firstPlayableUrl.isEmpty) {
        _notifyStartupAutoLaunchFailed('No auto-play stream resolved');
        if (mounted) {
          Navigator.of(context).pop();
          _dialogGeneration = -1;
          // Show source picker so user can manually select
          final result = await _showManualSourcePicker(playableSources, item);
          if (result != null && mounted) {
            _notifyStartupPlayerLaunching();
            await VideoPlayerLauncher.push(
              context,
              VideoPlayerLaunchArgs(
                videoUrl: result.$1,
                title: _currentPlayTitle ?? item.name,
                startAtPercent: _currentSlotProgress,
                contentImdbId: item.effectiveImdbId,
                contentTitle: item.name,
                contentType: item.type,
                stremioSources: playableSources,
                stremioCurrentSourceIndex: result.$2,
                resolveStremioSource: _createSourceResolver(item),
                stremioTvChannels: _buildGuideChannelMetadata(),
                stremioTvCurrentChannelId: channel.id,
                stremioTvRotationMinutes: _rotationMinutes,
                stremioTvSeriesRotationMinutes: _seriesRotationMinutes,
                stremioTvMixSalt: _mixSalt,
                stremioTvGuideDataProvider: _createGuideDataProvider(),
                stremioTvChannelSwitchProvider: _createChannelSwitchProvider(),
              ),
            );
          }
        }
        return;
      }

      if (!mounted) return;

      // Dismiss loading dialog right before player launch
      Navigator.of(context).pop();
      _dialogGeneration = -1;
      _notifyStartupPlayerLaunching();

      // Launch player with all sources for in-player switching
      await VideoPlayerLauncher.push(
        context,
        VideoPlayerLaunchArgs(
          videoUrl: firstPlayableUrl,
          title: _currentPlayTitle ?? item.name,
          startAtPercent: _currentSlotProgress,
          contentImdbId: item.effectiveImdbId,
          contentTitle: item.name,
          contentType: item.type,
          stremioSources: playableSources,
          stremioCurrentSourceIndex: firstPlayableIndex,
          resolveStremioSource: _createSourceResolver(item),
          stremioTvChannels: _buildGuideChannelMetadata(),
          stremioTvCurrentChannelId: channel.id,
          stremioTvRotationMinutes: _rotationMinutes,
          stremioTvSeriesRotationMinutes: _seriesRotationMinutes,
          stremioTvMixSalt: _mixSalt,
          stremioTvGuideDataProvider: _createGuideDataProvider(),
          stremioTvChannelSwitchProvider: _createChannelSwitchProvider(),
        ),
      );
    } catch (e) {
      _notifyStartupAutoLaunchFailed('Error searching streams: $e');
      if (!mounted) return;
      if (_dialogGeneration == myGeneration) {
        _dialogGeneration = -1;
        Navigator.of(context).pop();
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error searching streams: $e')));
    }
  }

  /// Resolves a channel to a playable URL without any UI interactions.
  /// Used by the in-player channel guide for background channel switching.
  Future<_ChannelPlaybackResult?> _resolveChannelPlayback(
    StremioTvChannel channel,
  ) async {
    // Ensure items are loaded
    if (!channel.hasItems) {
      await _ensureChannelItemsLoaded(channel);
    }

    final nowPlaying = _service.getNowPlaying(
      channel,
      rotationMinutes: _rotationFor(channel),
      salt: _mixSalt,
    );
    if (nowPlaying == null) return null;

    final item = nowPlaying.item;
    final slotProgress = _computeStartProgress(channel.id, nowPlaying.progress);

    if (!item.hasValidId) return null;

    // For series, resolve a random episode
    int? season;
    int? episode;
    if (item.type.toLowerCase() == 'series') {
      final episodeSeed = _randomEpisodes
          ? '${channel.id}:${DateTime.now().millisecondsSinceEpoch}'
          : '${channel.id}:${nowPlaying.slotStart.millisecondsSinceEpoch}';
      final resolved = await _service.resolveRandomEpisode(
        item: item,
        addon: channel.addon,
        seed: episodeSeed,
      );
      if (resolved == null) return null;
      season = resolved.season;
      episode = resolved.episode;
    }

    final playTitle = season != null
        ? '${item.name} (S${season}E$episode)'
        : item.name;

    // Search streams (torrent engines + Stremio addons)
    final isMovie = item.type.toLowerCase() == 'movie';
    var results = await TorrentService.searchByImdbWithStremio(
      item.effectiveImdbId ?? item.id,
      isMovie: isMovie,
      season: season,
      episode: episode,
      contentType: item.type,
      stremioTimeout: const Duration(seconds: 7),
    );

    // E1 fallback for series
    if (!isMovie && episode != null && episode != 1) {
      final torrents = results['torrents'] as List<Torrent>? ?? [];
      if (torrents.isEmpty) {
        debugPrint(
          'StremioTV guide: No streams for S${season}E$episode, retrying E1',
        );
        final retryResults = await TorrentService.searchByImdbWithStremio(
          item.effectiveImdbId ?? item.id,
          isMovie: false,
          season: season,
          episode: 1,
          contentType: item.type,
          stremioTimeout: const Duration(seconds: 7),
          engineTimeout: const Duration(seconds: 10),
        );
        if ((retryResults['torrents'] as List<Torrent>? ?? []).isNotEmpty) {
          results = retryResults;
          episode = 1;
        }
      }
    }

    final torrents = results['torrents'] as List<Torrent>? ?? [];
    if (torrents.isEmpty) return null;

    // Filter sources — exclude 480p torrents (rarely cached on debrid)
    var playableSources = torrents
        .where((t) => !t.isExternalStream)
        .where((t) => !t.isDirectStream || t.sizeBytes >= 5 * 1024 * 1024)
        .where(
          (t) =>
              t.streamType != StreamType.torrent ||
              _extractQuality(t.name) != '480p',
        )
        .toList();

    // TorBox cache filter
    if (_debridProvider == 'torbox') {
      final tbKey = await StorageService.getTorboxApiKey();
      if (tbKey != null && tbKey.isNotEmpty) {
        final torrentHashes = playableSources
            .where((t) => t.streamType == StreamType.torrent)
            .map((t) => t.infohash.trim().toLowerCase())
            .where((h) => h.isNotEmpty)
            .toList();
        if (torrentHashes.isNotEmpty) {
          final cachedHashes = await TorboxService.checkCachedTorrents(
            apiKey: tbKey,
            infoHashes: torrentHashes,
          );
          final cachedSet = cachedHashes
              .map((h) => h.trim().toLowerCase())
              .toSet();
          playableSources = playableSources
              .where(
                (t) =>
                    t.streamType != StreamType.torrent ||
                    cachedSet.contains(t.infohash.trim().toLowerCase()),
              )
              .toList();
        }
      }
    }

    if (playableSources.isEmpty) return null;

    // Auto-play best stream
    String? firstPlayableUrl;
    int firstPlayableIndex = 0;

    // Try direct streams
    final directStreams = _sortStreamsByQuality(
      playableSources.where((t) => t.isDirectStream).toList(),
    );
    for (int d = 0; d < directStreams.length.clamp(0, 20); d++) {
      final stream = directStreams[d];
      if (stream.directUrl == null || stream.directUrl!.isEmpty) continue;
      final valid = await _isValidStreamUrl(stream.directUrl!);
      if (valid) {
        firstPlayableUrl = stream.directUrl!;
        firstPlayableIndex = playableSources.indexWhere(
          (t) => t.directUrl == stream.directUrl && t.name == stream.name,
        );
        if (firstPlayableIndex < 0) firstPlayableIndex = 0;
        break;
      }
    }

    // Try torrents via debrid
    if (firstPlayableUrl == null) {
      final torrentStreams = _sortStreamsByQuality(
        playableSources
            .where((t) => t.streamType == StreamType.torrent)
            .toList(),
      );
      for (int i = 0; i < torrentStreams.length.clamp(0, 20); i++) {
        final url = await _resolveTorrentUrl(
          torrentStreams[i],
          item,
          _debridProvider,
        );
        if (url != null && url.isNotEmpty) {
          firstPlayableUrl = url;
          firstPlayableIndex = playableSources.indexWhere(
            (t) =>
                t.infohash == torrentStreams[i].infohash &&
                t.name == torrentStreams[i].name,
          );
          if (firstPlayableIndex < 0) firstPlayableIndex = 0;
          break;
        }
      }
    }

    if (firstPlayableUrl == null || firstPlayableUrl.isEmpty) return null;

    final title = season != null
        ? '${item.name} (S${season}E$episode)'
        : playTitle;

    return _ChannelPlaybackResult(
      url: firstPlayableUrl,
      title: title,
      contentType: item.type,
      contentImdbId: item.effectiveImdbId,
      startAtPercent: slotProgress,
      playableSources: playableSources,
      sourceIndex: firstPlayableIndex,
      sourceResolver: _createSourceResolver(item),
    );
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
        contentTitle: item.name,
        contentType: item.type,
      ),
    );
  }

  /// Returns true if playback was launched successfully, false on failure.
  Future<bool> _playTorrentViaDebrid(Torrent torrent, StremioMeta item) async {
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
      showPsychLoading(context, 'Hacking into the Real Debrid mainframe...');
      dialogShown = true;

      final magnet =
          'magnet:?xt=urn:btih:${torrent.infohash}&dn=${Uri.encodeComponent(torrent.name)}';

      // Use video file selection mode with fallback chain
      final result = await DebridService.addTorrentToDebridPreferVideos(
        apiKey,
        magnet,
      );

      final links = result['links'] as List<dynamic>? ?? [];
      final updatedInfo = result['updatedInfo'] as Map<String, dynamic>? ?? {};
      final files = updatedInfo['files'] as List<dynamic>? ?? [];

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
            contentTitle: item.name,
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

  Future<bool> _playViaTorbox(Torrent torrent, StremioMeta item) async {
    bool dialogShown = false;
    try {
      if (!mounted) return false;
      showPsychLoading(context, 'Opening a portal through Torbox...');
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
        torrentId: torrentId is int
            ? torrentId
            : int.parse(torrentId.toString()),
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
            contentTitle: item.name,
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

  Future<bool> _playViaPikPak(Torrent torrent, StremioMeta item) async {
    bool dialogShown = false;
    try {
      if (!mounted) return false;
      showPsychLoading(context, 'Beaming data through PikPak hyperspace...');
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
      final allVideoFiles = prepared['allVideoFiles'] as List<dynamic>?;
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
            contentTitle: item.name,
            contentType: item.type,
            playlist: [
              PlaylistEntry(url: streamUrl, title: title, provider: 'pikpak'),
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

  /// Show a bottom sheet with all available sources so the user can pick one manually.
  /// Returns (resolvedUrl, sourceIndex) or null if dismissed.
  Future<(String, int)?> _showManualSourcePicker(
    List<Torrent> sources,
    StremioMeta item,
  ) async {
    final resolver = _createSourceResolver(item);
    return showModalBottomSheet<(String, int)?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ManualSourcePickerSheet(
        sources: sources,
        resolver: resolver,
        validateDirectUrl: _isValidStreamUrl,
      ),
    );
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

  // ─── Source Resolution (no dialogs, returns URL) ────────────────────

  /// Creates a resolver closure that snapshots current state at creation time.
  Future<String?> Function(Torrent) _createSourceResolver(StremioMeta item) {
    final debridProvider = _debridProvider;
    return (Torrent torrent) async {
      if (torrent.isDirectStream) {
        return torrent.directUrl;
      }
      if (torrent.streamType == StreamType.torrent) {
        return _resolveTorrentUrl(torrent, item, debridProvider);
      }
      return null;
    };
  }

  // ─── Stremio TV In-Player Guide ─────────────────────────────────────

  /// Build channel metadata list for the in-player guide.
  /// Includes inline now/next data for channels that already have items loaded.
  List<Map<String, dynamic>> _buildGuideChannelMetadata() {
    return _channels.map((ch) {
      final data = <String, dynamic>{
        'id': ch.id,
        'name': ch.displayName,
        'number': ch.channelNumber,
        'type': ch.type,
        'isFavorite': ch.isFavorite,
      };
      if (ch.hasItems) {
        final rotation = _rotationFor(ch);
        final np = _service.getNowPlaying(
          ch,
          rotationMinutes: rotation,
          salt: _mixSalt,
        );
        final next = _service.getNextPlaying(
          ch,
          rotationMinutes: rotation,
          salt: _mixSalt,
        );
        if (np != null) {
          data['nowPlaying'] = {
            'title': np.item.name,
            'poster': np.item.poster,
            'year': np.item.year,
            'rating': np.item.imdbRating,
            'type': np.item.type,
            'slotEndMs': np.slotEnd.millisecondsSinceEpoch,
            'progress': np.progress,
          };
        }
        if (next != null) {
          data['nextUp'] = {
            'title': next.item.name,
            'poster': next.item.poster,
            'year': next.item.year,
            'rating': next.item.imdbRating,
            'type': next.item.type,
          };
        }
      }
      return data;
    }).toList();
  }

  /// Creates a guide data provider closure for lazy-loading channel data.
  Future<Map<String, dynamic>?> Function(List<String>)
  _createGuideDataProvider() {
    return (List<String> channelIds) async {
      final result = <String, dynamic>{};
      for (final id in channelIds) {
        final ch = _channels.firstWhereOrNull((c) => c.id == id);
        if (ch == null) continue;
        if (!ch.hasItems) await _service.loadChannelItems(ch);
        if (!ch.hasItems) continue;
        final rotation = _rotationFor(ch);
        final np = _service.getNowPlaying(
          ch,
          rotationMinutes: rotation,
          salt: _mixSalt,
        );
        final next = _service.getNextPlaying(
          ch,
          rotationMinutes: rotation,
          salt: _mixSalt,
        );
        result[id] = {
          if (np != null)
            'nowPlaying': {
              'title': np.item.name,
              'poster': np.item.poster,
              'year': np.item.year,
              'rating': np.item.imdbRating,
              'type': np.item.type,
              'slotEndMs': np.slotEnd.millisecondsSinceEpoch,
              'progress': np.progress,
            },
          if (next != null)
            'nextUp': {
              'title': next.item.name,
              'poster': next.item.poster,
              'year': next.item.year,
              'rating': next.item.imdbRating,
              'type': next.item.type,
            },
        };
      }
      return result;
    };
  }

  /// Creates a channel switch provider closure for the in-player guide.
  Future<Map<String, dynamic>?> Function(String)
  _createChannelSwitchProvider() {
    return (String channelId) async {
      final ch = _channels.firstWhereOrNull((c) => c.id == channelId);
      if (ch == null) return null;
      final result = await _resolveChannelPlayback(ch);
      if (result == null) return null;
      return {
        'url': result.url,
        'title': result.title,
        'contentType': result.contentType,
        'contentImdbId': result.contentImdbId,
        'startAtPercent': result.startAtPercent,
        'stremioSources': result.playableSources
            .map((t) => t.toJson())
            .toList(),
        'stremioCurrentSourceIndex': result.sourceIndex,
        'sourceResolver': result.sourceResolver,
      };
    };
  }

  /// Resolve a torrent to a playable URL via the given debrid provider.
  Future<String?> _resolveTorrentUrl(
    Torrent torrent,
    StremioMeta item,
    String debridProvider,
  ) async {
    // Try the selected provider first
    if (debridProvider == 'realdebrid') {
      final rdKey = await StorageService.getApiKey();
      if (rdKey != null && rdKey.isNotEmpty) {
        return _resolveViaRealDebrid(torrent, item, rdKey);
      }
    } else if (debridProvider == 'torbox') {
      final tbKey = await StorageService.getTorboxApiKey();
      if (tbKey != null && tbKey.isNotEmpty) {
        return _resolveViaTorbox(torrent, tbKey);
      }
    } else if (debridProvider == 'pikpak') {
      final pikpakEnabled = await StorageService.getPikPakEnabled();
      if (pikpakEnabled) {
        return _resolveViaPikPak(torrent, item);
      }
    }

    // Auto fallback
    final rdKey = await StorageService.getApiKey();
    if (rdKey != null && rdKey.isNotEmpty) {
      return _resolveViaRealDebrid(torrent, item, rdKey);
    }
    final tbKey = await StorageService.getTorboxApiKey();
    if (tbKey != null && tbKey.isNotEmpty) {
      return _resolveViaTorbox(torrent, tbKey);
    }
    final pikpakEnabled = await StorageService.getPikPakEnabled();
    if (pikpakEnabled) {
      return _resolveViaPikPak(torrent, item);
    }

    return null;
  }

  Future<String?> _resolveViaRealDebrid(
    Torrent torrent,
    StremioMeta item,
    String apiKey,
  ) async {
    try {
      final magnet =
          'magnet:?xt=urn:btih:${torrent.infohash}&dn=${Uri.encodeComponent(torrent.name)}';
      final result = await DebridService.addTorrentToDebridPreferVideos(
        apiKey,
        magnet,
      );

      final links = result['links'] as List<dynamic>? ?? [];
      final updatedInfo = result['updatedInfo'] as Map<String, dynamic>? ?? {};
      final files = updatedInfo['files'] as List<dynamic>? ?? [];

      if (links.isEmpty) return null;

      String linkToUnrestrict = links.first.toString();
      if (item.type.toLowerCase() == 'movie' && links.length > 1) {
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
      return unrestrictResult['download'] as String?;
    } catch (e) {
      debugPrint('StremioTV: RD resolve error: $e');
      return null;
    }
  }

  Future<String?> _resolveViaTorbox(Torrent torrent, String apiKey) async {
    try {
      final magnet =
          'magnet:?xt=urn:btih:${torrent.infohash}&dn=${Uri.encodeComponent(torrent.name)}';
      final result = await TorboxService.createTorrent(
        apiKey: apiKey,
        magnet: magnet,
      );
      final data = result['data'];
      final torrentId = data is Map
          ? (data['torrent_id'] ?? data['id'])
          : (result['torrent_id'] ?? result['id']);

      if (torrentId == null) return null;

      await Future.delayed(const Duration(seconds: 3));

      final torrentInfo = await TorboxService.getTorrentById(
        apiKey,
        torrentId is int ? torrentId : int.parse(torrentId.toString()),
      );

      if (torrentInfo == null) return null;

      final allFiles = torrentInfo.files;
      final videoFiles = allFiles
          .where((f) => FileUtils.isVideoFile(f.name))
          .toList();
      final files = videoFiles.isNotEmpty ? videoFiles : allFiles;
      if (files.isEmpty) return null;

      var targetFile = files.first;
      if (files.length > 1) {
        for (final f in files) {
          if (f.size > targetFile.size) {
            targetFile = f;
          }
        }
      }

      return await TorboxService.requestFileDownloadLink(
        apiKey: apiKey,
        torrentId: torrentId is int
            ? torrentId
            : int.parse(torrentId.toString()),
        fileId: targetFile.id,
      );
    } catch (e) {
      debugPrint('StremioTV: Torbox resolve error: $e');
      return null;
    }
  }

  Future<String?> _resolveViaPikPak(Torrent torrent, StremioMeta item) async {
    try {
      final prepared = await PikPakTvService.instance.prepareTorrent(
        infohash: torrent.infohash.trim().toLowerCase(),
        torrentName: torrent.name,
      );

      if (prepared == null) return null;

      String? streamUrl = prepared['url'] as String?;

      final allVideoFiles = prepared['allVideoFiles'] as List<dynamic>?;
      if (allVideoFiles != null &&
          allVideoFiles.isNotEmpty &&
          item.type.toLowerCase() == 'movie') {
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

      return streamUrl;
    } catch (e) {
      debugPrint('StremioTV: PikPak resolve error: $e');
      return null;
    }
  }

  void _playChannelById(String channelId) {
    if (_channels.isEmpty) {
      _notifyStartupAutoLaunchFailed('Channels not loaded');
      return;
    }
    if (_startupAutoPlayActive &&
        !_channels.any((channel) => channel.id == channelId)) {
      _notifyStartupAutoLaunchFailed('Startup channel not found');
      return;
    }
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
      rotationMinutes: _rotationFor(channel),
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
    final focusedChannelId = _currentFocusedChannelId();
    final newState = !channel.isFavorite;
    await StorageService.setStremioTvChannelFavorited(channel.id, newState);
    if (!mounted) return;
    final previousChannels = List<StremioTvChannel>.from(_channels);
    setState(() {
      channel.isFavorite = newState;
      _channels = _sortedChannels(_channels);
      _reorderRowFocusNodes(previousChannels, _channels);
    });
    if (focusedChannelId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final newIndex = _channels.indexWhere(
          (ch) => ch.id == focusedChannelId,
        );
        if (newIndex >= 0 && newIndex < _rowFocusNodes.length) {
          _rowFocusNodes[newIndex].requestFocus();
        }
      });
    }
  }

  Future<void> _copyLocalCatalogJson(StremioTvChannel channel) async {
    final payload = await LocalCatalogExporter.loadCatalog(
      catalogId: channel.catalog.id,
      catalogType: channel.type,
    );
    if (!mounted) return;
    if (payload == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Local catalog could not be found'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    await Clipboard.setData(ClipboardData(text: payload.json));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Copied "${payload.name}" JSON to clipboard'),
        behavior: SnackBarBehavior.floating,
      ),
    );
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

  String? _currentFocusedChannelId() {
    final focusedNodeIndex = _rowFocusNodes.indexWhere((node) => node.hasFocus);
    if (focusedNodeIndex >= 0 && focusedNodeIndex < _channels.length) {
      return _channels[focusedNodeIndex].id;
    }
    if (_focusedIndex >= 0 && _focusedIndex < _channels.length) {
      return _channels[_focusedIndex].id;
    }
    return null;
  }

  void _reorderRowFocusNodes(
    List<StremioTvChannel> previousChannels,
    List<StremioTvChannel> reorderedChannels,
  ) {
    final nodeByChannelId = <String, FocusNode>{};
    final previousLength = previousChannels.length < _rowFocusNodes.length
        ? previousChannels.length
        : _rowFocusNodes.length;
    for (int i = 0; i < previousLength; i++) {
      nodeByChannelId[previousChannels[i].id] = _rowFocusNodes[i];
    }

    final reorderedNodes = <FocusNode>[];
    for (int i = 0; i < reorderedChannels.length; i++) {
      reorderedNodes.add(
        nodeByChannelId.remove(reorderedChannels[i].id) ??
            FocusNode(debugLabel: 'stremioTvRow$i'),
      );
    }

    for (final leftover in nodeByChannelId.values) {
      leftover.dispose();
    }

    _rowFocusNodes
      ..clear()
      ..addAll(reorderedNodes);
  }

  KeyEventResult _handleSearchKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final text = _searchController.text;
    final selection = _searchController.selection;
    final isAtStart =
        !selection.isValid ||
        (selection.baseOffset == 0 && selection.extentOffset == 0);

    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      // Focus search/settings button row
      _searchBtnFocusNode.requestFocus();
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      // Search bar is at the top — nothing above it
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      if (text.isEmpty || isAtStart) {
        MainPageBridge.focusTvSidebar?.call();
      }
      // Always consume — either sidebar focus or cursor movement
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      // Always consume — let TextField handle cursor movement internally
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.escape ||
        event.logicalKey == LogicalKeyboardKey.goBack) {
      if (text.isNotEmpty) {
        _searchController.clear();
        return KeyEventResult.handled;
      }
      // Hide search field on back when empty
      if (_showSearchField) {
        setState(() => _showSearchField = false);
        _searchBtnFocusNode.requestFocus();
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
                // Controls row — search + settings centered
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Collapsible search field
                      AnimatedSize(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOut,
                        alignment: Alignment.topCenter,
                        child: _showSearchField
                            ? Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: TextField(
                                  controller: _searchController,
                                  focusNode: _searchFocusNode,
                                  style: const TextStyle(color: Colors.white),
                                  decoration: InputDecoration(
                                    hintText: 'Search channels...',
                                    hintStyle: TextStyle(
                                      color: Colors.white.withValues(
                                        alpha: 0.3,
                                      ),
                                    ),
                                    prefixIcon: Icon(
                                      Icons.search_rounded,
                                      color: Colors.white.withValues(
                                        alpha: 0.35,
                                      ),
                                    ),
                                    suffixIcon: _searchQuery.isNotEmpty
                                        ? IconButton(
                                            icon: Icon(
                                              Icons.close_rounded,
                                              color: Colors.white.withValues(
                                                alpha: 0.5,
                                              ),
                                            ),
                                            onPressed: () {
                                              _searchController.clear();
                                              setState(() {
                                                _showSearchField = false;
                                              });
                                            },
                                          )
                                        : null,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(14),
                                      borderSide: BorderSide.none,
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(14),
                                      borderSide: BorderSide.none,
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(14),
                                      borderSide: BorderSide(
                                        color: Colors.white.withValues(
                                          alpha: 0.15,
                                        ),
                                        width: 1,
                                      ),
                                    ),
                                    filled: true,
                                    fillColor: Colors.white.withValues(
                                      alpha: 0.07,
                                    ),
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 14,
                                    ),
                                  ),
                                  textInputAction: TextInputAction.search,
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),
                      // Centered search + settings buttons
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Search toggle button
                          Focus(
                            focusNode: _searchBtnFocusNode,
                            onKeyEvent: (node, event) {
                              if (event is! KeyDownEvent)
                                return KeyEventResult.ignored;
                              if (event.logicalKey ==
                                  LogicalKeyboardKey.arrowRight) {
                                _menuFocusNode.requestFocus();
                                return KeyEventResult.handled;
                              }
                              if (event.logicalKey ==
                                  LogicalKeyboardKey.arrowLeft) {
                                MainPageBridge.focusTvSidebar?.call();
                                return KeyEventResult.handled;
                              }
                              if (event.logicalKey ==
                                  LogicalKeyboardKey.arrowUp) {
                                if (_showSearchField) {
                                  _searchFocusNode.requestFocus();
                                }
                                return KeyEventResult.handled;
                              }
                              if (event.logicalKey ==
                                  LogicalKeyboardKey.arrowDown) {
                                final filtered = _filteredChannels;
                                if (filtered.isNotEmpty &&
                                    _rowFocusNodes.isNotEmpty) {
                                  final firstIdx = _channels.indexOf(
                                    filtered.first,
                                  );
                                  if (firstIdx >= 0 &&
                                      firstIdx < _rowFocusNodes.length) {
                                    _rowFocusNodes[firstIdx].requestFocus();
                                  }
                                }
                                return KeyEventResult.handled;
                              }
                              if (event.logicalKey ==
                                      LogicalKeyboardKey.select ||
                                  event.logicalKey ==
                                      LogicalKeyboardKey.enter) {
                                setState(() {
                                  _showSearchField = !_showSearchField;
                                });
                                if (_showSearchField) {
                                  WidgetsBinding.instance.addPostFrameCallback((
                                    _,
                                  ) {
                                    _searchFocusNode.requestFocus();
                                  });
                                }
                                return KeyEventResult.handled;
                              }
                              return KeyEventResult.ignored;
                            },
                            child: GestureDetector(
                              onTap: () {
                                setState(() {
                                  _showSearchField = !_showSearchField;
                                });
                                if (_showSearchField) {
                                  WidgetsBinding.instance.addPostFrameCallback((
                                    _,
                                  ) {
                                    _searchFocusNode.requestFocus();
                                  });
                                }
                              },
                              child: ListenableBuilder(
                                listenable: _searchBtnFocusNode,
                                builder: (context, _) => Container(
                                  height: 40,
                                  width: 40,
                                  decoration: BoxDecoration(
                                    color: _searchBtnFocusNode.hasFocus
                                        ? Colors.white.withValues(alpha: 0.15)
                                        : const Color(0xFF141414),
                                    borderRadius: BorderRadius.circular(20),
                                    border: _searchBtnFocusNode.hasFocus
                                        ? Border.all(
                                            color: Colors.white.withValues(
                                              alpha: 0.6,
                                            ),
                                            width: 2,
                                          )
                                        : null,
                                  ),
                                  child: Icon(
                                    Icons.search_rounded,
                                    size: 20,
                                    color:
                                        (_searchBtnFocusNode.hasFocus ||
                                            _showSearchField ||
                                            _searchQuery.isNotEmpty)
                                        ? Colors.white
                                        : Colors.white.withValues(alpha: 0.5),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          // Settings/options button
                          Focus(
                            focusNode: _menuFocusNode,
                            onKeyEvent: (node, event) {
                              if (event is! KeyDownEvent)
                                return KeyEventResult.ignored;
                              if (_menuController.isOpen) {
                                if (event.logicalKey ==
                                        LogicalKeyboardKey.escape ||
                                    event.logicalKey ==
                                        LogicalKeyboardKey.goBack) {
                                  _menuController.close();
                                  _menuFocusNode.requestFocus();
                                  return KeyEventResult.handled;
                                }
                                return KeyEventResult.ignored;
                              }
                              if (event.logicalKey ==
                                  LogicalKeyboardKey.arrowUp) {
                                if (_showSearchField) {
                                  _searchFocusNode.requestFocus();
                                }
                                return KeyEventResult.handled;
                              }
                              if (event.logicalKey ==
                                  LogicalKeyboardKey.arrowRight) {
                                return KeyEventResult.handled;
                              }
                              if (event.logicalKey ==
                                  LogicalKeyboardKey.arrowLeft) {
                                _searchBtnFocusNode.requestFocus();
                                return KeyEventResult.handled;
                              }
                              if (event.logicalKey ==
                                  LogicalKeyboardKey.arrowDown) {
                                final filtered = _filteredChannels;
                                if (filtered.isNotEmpty &&
                                    _rowFocusNodes.isNotEmpty) {
                                  final firstIdx = _channels.indexOf(
                                    filtered.first,
                                  );
                                  if (firstIdx >= 0 &&
                                      firstIdx < _rowFocusNodes.length) {
                                    _rowFocusNodes[firstIdx].requestFocus();
                                  }
                                }
                                return KeyEventResult.handled;
                              }
                              if (event.logicalKey ==
                                      LogicalKeyboardKey.select ||
                                  event.logicalKey ==
                                      LogicalKeyboardKey.enter) {
                                _menuController.open();
                                return KeyEventResult.handled;
                              }
                              return KeyEventResult.ignored;
                            },
                            child: ListenableBuilder(
                              listenable: _menuFocusNode,
                              builder: (context, child) => MenuAnchor(
                                controller: _menuController,
                                menuChildren: [
                                  MenuItemButton(
                                    autofocus: true,
                                    leadingIcon: const Icon(
                                      Icons.shuffle_rounded,
                                    ),
                                    onPressed: () {
                                      setState(
                                        () => _mixSalt = (_mixSalt + 1) % 10,
                                      );
                                    },
                                    child: Text(
                                      'Shuffle (Mix ${_mixSalt + 1})',
                                    ),
                                  ),
                                  MenuItemButton(
                                    leadingIcon: const Icon(
                                      Icons.refresh_rounded,
                                    ),
                                    onPressed: _refreshing
                                        ? null
                                        : () => _refresh(),
                                    child: const Text('Refresh'),
                                  ),
                                  MenuItemButton(
                                    leadingIcon: const Icon(Icons.tune_rounded),
                                    onPressed: () => _openChannelFilter(),
                                    child: const Text('Filter channels'),
                                  ),
                                  SubmenuButton(
                                    focusNode: _submenuFocusNode,
                                    leadingIcon: const Icon(
                                      Icons.playlist_add_rounded,
                                    ),
                                    menuChildren: [
                                      _submenuItem(
                                        autofocus: true,
                                        icon: Icons.list_rounded,
                                        label: 'Manage',
                                        onPressed: _openLocalCatalogs,
                                      ),
                                      _submenuItem(
                                        icon: Icons.file_upload_outlined,
                                        label: 'From File',
                                        onPressed: _importFromFile,
                                      ),
                                      _submenuItem(
                                        icon: Icons.link_rounded,
                                        label: 'From URL',
                                        onPressed: _importFromUrl,
                                      ),
                                      _submenuItem(
                                        icon: Icons.data_object_rounded,
                                        label: 'Paste JSON',
                                        onPressed: _importFromJson,
                                      ),
                                      _submenuItem(
                                        icon: Icons.source_rounded,
                                        label: 'From Repository',
                                        onPressed: _importFromRepo,
                                      ),
                                      _submenuItem(
                                        icon: Icons.movie_filter_rounded,
                                        label: 'From Trakt',
                                        onPressed: _importFromTrakt,
                                      ),
                                    ],
                                    child: const Text('Import'),
                                  ),
                                ],
                                builder: (context, controller, child) =>
                                    Container(
                                      height: 40,
                                      width: 40,
                                      decoration: BoxDecoration(
                                        color: _menuFocusNode.hasFocus
                                            ? Colors.white.withValues(
                                                alpha: 0.15,
                                              )
                                            : const Color(0xFF141414),
                                        borderRadius: BorderRadius.circular(20),
                                        border: _menuFocusNode.hasFocus
                                            ? Border.all(
                                                color: Colors.white.withValues(
                                                  alpha: 0.6,
                                                ),
                                                width: 2,
                                              )
                                            : null,
                                      ),
                                      child: IconButton(
                                        icon: const Icon(
                                          Icons.settings_rounded,
                                          size: 20,
                                        ),
                                        padding: EdgeInsets.zero,
                                        color: _menuFocusNode.hasFocus
                                            ? Colors.white
                                            : Colors.white.withValues(
                                                alpha: 0.5,
                                              ),
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
                    ],
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
                        padding: const EdgeInsets.only(top: 8, bottom: 16),
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final channel = filtered[index];
                          final realIndex = _channels.indexOf(channel);

                          // Trigger lazy load for visible channels
                          if (!channel.hasItems &&
                              !_loadingChannelIds.contains(channel.id)) {
                            _ensureChannelItemsLoaded(channel);
                          }

                          final nowPlaying = _service.getNowPlaying(
                            channel,
                            rotationMinutes: _rotationFor(channel),
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
                          final isLoading = _loadingChannelIds.contains(
                            channel.id,
                          );
                          final focusNode = realIndex < _rowFocusNodes.length
                              ? _rowFocusNodes[realIndex]
                              : FocusNode();

                          return ListenableBuilder(
                            listenable: focusNode,
                            builder: (context, _) {
                              if (focusNode.hasFocus &&
                                  _focusedIndex != realIndex) {
                                WidgetsBinding.instance.addPostFrameCallback((
                                  _,
                                ) {
                                  if (mounted) {
                                    setState(() => _focusedIndex = realIndex);
                                  }
                                });
                              }
                              return StremioTvChannelRow(
                                key: ValueKey(channel.id),
                                channel: channel,
                                nowPlaying: nowPlaying,
                                isLoading: isLoading,
                                isFocused: focusNode.hasFocus,
                                focusNode: focusNode,
                                hideNowPlaying: _hideNowPlaying,
                                onTap: () => _playChannel(channel),
                                onLongPress: () => _toggleFavorite(channel),
                                onFavoritePressed: () =>
                                    _toggleFavorite(channel),
                                onExportPressed: channel.isLocal
                                    ? () => _copyLocalCatalogJson(channel)
                                    : null,
                                onGuidePressed: _hideNowPlaying
                                    ? null
                                    : () => _showGuide(channel),
                                onLeftPress: MainPageBridge.focusTvSidebar,
                                onUpPress: index == 0
                                    ? () {
                                        _searchBtnFocusNode.requestFocus();
                                      }
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

// ─── Manual Source Picker (shown when auto-play fails) ────────────────────

class _ManualSourcePickerSheet extends StatefulWidget {
  final List<Torrent> sources;
  final Future<String?> Function(Torrent) resolver;
  final Future<bool> Function(String url) validateDirectUrl;

  const _ManualSourcePickerSheet({
    required this.sources,
    required this.resolver,
    required this.validateDirectUrl,
  });

  @override
  State<_ManualSourcePickerSheet> createState() =>
      _ManualSourcePickerSheetState();
}

class _ManualSourcePickerSheetState extends State<_ManualSourcePickerSheet> {
  int? _resolvingIndex; // index in widget.sources (original)
  int? _failedIndex; // index of last failed source
  final _firstItemFocusNode = FocusNode();
  final _firstTabFocusNode = FocusNode();
  int _activeTab = 0; // 0 = All, 1 = Direct, 2 = Torrent

  late List<Torrent> _directSources;
  late List<Torrent> _torrentSources;

  @override
  void initState() {
    super.initState();
    _directSources = widget.sources.where((t) => t.isDirectStream).toList();
    _torrentSources = widget.sources
        .where((t) => t.streamType == StreamType.torrent)
        .toList();
    // Auto-focus first item after build (for DPAD)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _firstItemFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _firstItemFocusNode.dispose();
    _firstTabFocusNode.dispose();
    super.dispose();
  }

  List<Torrent> get _filteredSources {
    switch (_activeTab) {
      case 1:
        return _directSources;
      case 2:
        return _torrentSources;
      default:
        return widget.sources;
    }
  }

  String _parseQuality(String name) {
    final lower = name.toLowerCase();
    if (lower.contains('2160p') ||
        lower.contains('4k') ||
        lower.contains('uhd'))
      return '4K';
    if (lower.contains('1080p') || lower.contains('1080i')) return '1080p';
    if (lower.contains('720p')) return '720p';
    if (lower.contains('480p') || lower.contains('sd')) return '480p';
    return 'HD';
  }

  Color _qualityColor(String quality) {
    switch (quality) {
      case '4K':
        return const Color(0xFFFFD600);
      case '1080p':
        return const Color(0xFF536DFE);
      case '720p':
        return const Color(0xFF00BFA5);
      case '480p':
        return const Color(0xFF78909C);
      default:
        return const Color(0xFF90A4AE);
    }
  }

  Future<void> _onSourceTap(Torrent source) async {
    if (_resolvingIndex != null) return;
    final originalIndex = widget.sources.indexOf(source);
    setState(() {
      _resolvingIndex = originalIndex;
      _failedIndex = null;
    });

    try {
      final url = await widget.resolver(source);
      if (!mounted) return;
      if (url != null && url.isNotEmpty) {
        // Validate direct URLs with HEAD check (size >= 50MB)
        if (source.isDirectStream) {
          final valid = await widget.validateDirectUrl(url);
          if (!mounted) return;
          if (!valid) {
            setState(() {
              _resolvingIndex = null;
              _failedIndex = originalIndex;
            });
            return;
          }
        }
        Navigator.of(context).pop((url, originalIndex));
      } else {
        setState(() {
          _resolvingIndex = null;
          _failedIndex = originalIndex;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _resolvingIndex = null;
        _failedIndex = originalIndex;
      });
    }
  }

  Widget _buildTab(
    String label,
    int count,
    int tabIndex, {
    FocusNode? focusNode,
  }) {
    final isActive = _activeTab == tabIndex;
    return _SourcePickerTab(
      focusNode: focusNode,
      label: '$label ($count)',
      isActive: isActive,
      onTap: () {
        setState(() => _activeTab = tabIndex);
        // Re-focus first item in the new tab's list
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _firstItemFocusNode.requestFocus();
        });
      },
      onDownPress: () => _firstItemFocusNode.requestFocus(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredSources;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.7,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF101016),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  color: Color(0xFFFFB74D),
                  size: 22,
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Auto-play failed — select a source',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Tabs
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
            child: Row(
              children: [
                _buildTab(
                  'All',
                  widget.sources.length,
                  0,
                  focusNode: _firstTabFocusNode,
                ),
                const SizedBox(width: 8),
                if (_directSources.isNotEmpty) ...[
                  _buildTab('Direct', _directSources.length, 1),
                  const SizedBox(width: 8),
                ],
                if (_torrentSources.isNotEmpty)
                  _buildTab('Torrent', _torrentSources.length, 2),
              ],
            ),
          ),
          const Divider(color: Colors.white12, height: 1),
          // Source list
          Flexible(
            child: filtered.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Text(
                        'No sources in this category',
                        style: TextStyle(color: Colors.white38, fontSize: 14),
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: filtered.length,
                    itemBuilder: (ctx, i) {
                      final source = filtered[i];
                      final quality = _parseQuality(source.displayTitle);
                      final qColor = _qualityColor(quality);
                      final originalIndex = widget.sources.indexOf(source);
                      final isResolving = _resolvingIndex == originalIndex;
                      final size = source.sizeBytes > 0
                          ? Formatters.formatFileSize(source.sizeBytes)
                          : null;
                      final isDirect = source.isDirectStream;

                      final isFailed = _failedIndex == originalIndex;

                      return _SourcePickerItem(
                        focusNode: i == 0 ? _firstItemFocusNode : null,
                        isFirst: i == 0,
                        onUpToTabs: () => _firstTabFocusNode.requestFocus(),
                        quality: quality,
                        qualityColor: qColor,
                        title: source.displayTitle,
                        meta: [
                          if (isDirect) 'Direct' else 'Torrent',
                          if (size != null) size,
                          if (!isDirect && source.seeders > 0)
                            '${source.seeders} seeders',
                          if (source.source.isNotEmpty) source.source,
                        ].join(' · '),
                        isResolving: isResolving,
                        isFailed: isFailed,
                        onTap: isResolving ? null : () => _onSourceTap(source),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// Tab button with DPAD focus support.
class _SourcePickerTab extends StatefulWidget {
  final FocusNode? focusNode;
  final String label;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback? onDownPress;

  const _SourcePickerTab({
    this.focusNode,
    required this.label,
    required this.isActive,
    required this.onTap,
    this.onDownPress,
  });

  @override
  State<_SourcePickerTab> createState() => _SourcePickerTabState();
}

class _SourcePickerTabState extends State<_SourcePickerTab> {
  bool _focused = false;

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.select ||
        event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.gameButtonA) {
      widget.onTap();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      widget.onDownPress?.call();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      return KeyEventResult.handled; // consume — nothing above tabs
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode,
      onFocusChange: (f) => setState(() => _focused = f),
      onKeyEvent: _handleKey,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: widget.isActive
                ? const Color(0xFF536DFE)
                : _focused
                ? const Color(0xFF536DFE).withValues(alpha: 0.15)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: _focused
                  ? const Color(0xFF536DFE).withValues(alpha: 0.7)
                  : widget.isActive
                  ? Colors.transparent
                  : Colors.white12,
              width: _focused ? 1.5 : 1,
            ),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              color: widget.isActive ? Colors.white : Colors.white54,
              fontSize: 13,
              fontWeight: widget.isActive ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }
}

/// Individual source item with DPAD focus support.
class _SourcePickerItem extends StatefulWidget {
  final FocusNode? focusNode;
  final String quality;
  final Color qualityColor;
  final String title;
  final String meta;
  final bool isResolving;
  final bool isFailed;
  final VoidCallback? onTap;
  final bool isFirst; // first item in list — up arrow goes to tabs
  final VoidCallback? onUpToTabs;

  const _SourcePickerItem({
    this.focusNode,
    required this.quality,
    required this.qualityColor,
    required this.title,
    required this.meta,
    required this.isResolving,
    this.isFailed = false,
    this.onTap,
    this.isFirst = false,
    this.onUpToTabs,
  });

  @override
  State<_SourcePickerItem> createState() => _SourcePickerItemState();
}

class _SourcePickerItemState extends State<_SourcePickerItem> {
  late final FocusNode _focusNode;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focusNode = widget.focusNode ?? FocusNode();
  }

  @override
  void dispose() {
    if (widget.focusNode == null) _focusNode.dispose();
    super.dispose();
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.select ||
        event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.gameButtonA) {
      widget.onTap?.call();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp && widget.isFirst) {
      widget.onUpToTabs?.call();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape ||
        event.logicalKey == LogicalKeyboardKey.goBack) {
      Navigator.of(context).pop();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final qColor = widget.qualityColor;
    return Focus(
      focusNode: _focusNode,
      onFocusChange: (f) => setState(() => _focused = f),
      onKeyEvent: _handleKey,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: _focused ? const Color(0xFF1A1A2E) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _focused
                  ? const Color(0xFF536DFE).withValues(alpha: 0.7)
                  : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              // Quality badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: qColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: qColor.withValues(alpha: 0.4)),
                ),
                child: Text(
                  widget.quality,
                  style: TextStyle(
                    color: qColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Title + meta
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _focused ? Colors.white : Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      widget.meta,
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              // Loading, failed, or play icon
              if (widget.isResolving)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFF536DFE),
                  ),
                )
              else if (widget.isFailed)
                const Icon(
                  Icons.error_outline,
                  color: Color(0xFFEF5350),
                  size: 22,
                )
              else
                Icon(
                  Icons.play_circle_outline,
                  color: _focused ? Colors.white54 : Colors.white24,
                  size: 22,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Result from resolving a channel to a playable stream (no UI).
class _ChannelPlaybackResult {
  final String url;
  final String title;
  final String contentType;
  final String? contentImdbId;
  final double? startAtPercent;
  final List<Torrent> playableSources;
  final int sourceIndex;
  final Future<String?> Function(Torrent) sourceResolver;

  const _ChannelPlaybackResult({
    required this.url,
    required this.title,
    required this.contentType,
    this.contentImdbId,
    this.startAtPercent,
    required this.playableSources,
    required this.sourceIndex,
    required this.sourceResolver,
  });
}
