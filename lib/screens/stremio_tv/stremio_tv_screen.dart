import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_theme_scope.dart';
import '../../widgets/pipeline_loading_overlay.dart';
import '../../models/play_loader_art.dart';
import '../../models/stremio_addon.dart';
import '../../models/stremio_tv/stremio_tv_channel.dart';
import '../../models/stremio_tv/stremio_tv_now_playing.dart';
import '../../models/torrent.dart';
import '../../services/play_loader_style.dart';
import '../../services/analytics_service.dart';
import '../../services/mdblist/mdblist_service.dart';
import '../../services/debrid_service.dart';
import '../../services/stream_url_validator.dart';
import '../../services/main_page_bridge.dart';
import '../../services/storage_service.dart';
import '../../services/video_player_launcher.dart';
import '../../services/torbox_service.dart';
import '../../services/torbox_torrent_control_service.dart';
import '../../services/pikpak_api_service.dart';
import '../../services/pikpak_tv_service.dart';
import '../../services/premiumize_service.dart';
import '../../models/premiumize_file.dart';
import '../../services/alldebrid_service.dart';
import '../../utils/file_utils.dart';
import '../../utils/rd_blocked_filter.dart';
import '../../utils/formatters.dart';
import '../../utils/stremio_episode_selector.dart';
import '../../utils/stremio_tv_debrid_fallback.dart';
import '../../utils/series_parser.dart';
import '../../utils/source_quality.dart';
import '../../utils/torrent_coverage_detector.dart';
import '../../services/torrent_service.dart';
import '../catalog_item_detail_screen.dart';
import '../settings/stremio_tv_settings_page.dart';
import 'stremio_tv_filter_page.dart';
import 'stremio_tv_service.dart';
import 'widgets/stremio_tv_tuner.dart';
import 'widgets/stremio_tv_empty_state.dart';
import 'widgets/stremio_tv_guide_sheet.dart';
import 'widgets/stremio_tv_local_catalogs_dialog.dart';
import '../../utils/tv_keys.dart';
import '../../widgets/tv_text_field.dart';

/// Main Stremio TV screen — a TV guide powered by Stremio addon catalogs.
///
/// Each addon catalog becomes a "channel" with a deterministic "now playing"
/// item that rotates on a configurable schedule.
class StremioTvScreen extends StatefulWidget {
  /// The resolved native Android-TV flag, threaded down from the app shell
  /// (see main.dart `_buildPage`). Prefer this over a width heuristic: on a TV
  /// the logical canvas sits right at the old `width >= 900` threshold, so
  /// screens that guessed from width flipped to the non-navigable phone layout.
  final bool isTelevision;

  const StremioTvScreen({super.key, this.isTelevision = false});

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
  bool _rdSkipBlockedTorrents = false;
  bool _torrentsFirst = true;
  List<MapEntry<String, String>> _availableProviders = [];
  int _maxStartPercent = -1; // -1 = no limit (slot progress), 0 = beginning
  bool _hideNowPlaying = false;
  double? _currentSlotProgress;
  int _playGeneration = 0;
  String? _currentPlayTitle; // Overrides item.name when playing series episodes
  final Map<String, _StremioTvPlaybackCursor> _playbackCursors = {};

  /// Get the rotation duration for a channel based on its content type.
  int _rotationFor(StremioTvChannel channel) =>
      channel.type == 'series' ? _seriesRotationMinutes : _rotationMinutes;

  final List<FocusNode> _rowFocusNodes = [];
  int _focusedIndex = 0;

  /// Imperative handle to the tuner so header→dial focus jumps scroll the
  /// target card into view before focusing it — a recycled off-screen card
  /// can't otherwise receive focus (silent no-op), which stranded focus on the
  /// header search box after a long channel hold.
  final StremioTvTunerController _tunerController = StremioTvTunerController();

  /// Bumped whenever a channel's items finish lazy-loading. The tuner is
  /// wrapped in a ValueListenableBuilder on this, so a load completing
  /// mid-surf rebuilds only the tuner subtree — not the whole screen with its
  /// header — which is what made DPAD navigation stutter while channels were
  /// still tuning in.
  final ValueNotifier<int> _contentRevision = ValueNotifier<int>(0);

  // Mix salt (0-9, cycles on shuffle button)
  int _mixSalt = 0;

  // Header buttons
  final FocusNode _searchBtnFocusNode = FocusNode(debugLabel: 'searchBtn');
  final FocusNode _providerFocusNode = FocusNode(debugLabel: 'providerBtn');
  final FocusNode _menuFocusNode = FocusNode(debugLabel: 'menuBtn');
  final FocusNode _submenuFocusNode = FocusNode(debugLabel: 'localCatalogs');
  final MenuController _providerMenuController = MenuController();
  final MenuController _menuController = MenuController();

  // Search
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _searchQuery = '';
  bool _showSearchField = false;
  // Whether MDBList is connected — gates the "Import → From MDBList" entry so
  // an unauthed user isn't offered a dead import (MDBList is also hidden from
  // Settings for the alpha).
  bool _mdblistConnected = false;

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
    AnalyticsService.screenView('stremio_tv');
    _loadSettings().then((_) => _discoverAndLoad());
    MdblistService.instance.isAuthenticated().then((v) {
      if (mounted && v != _mdblistConnected) {
        setState(() => _mdblistConnected = v);
      }
    });

    // Search DPAD exits live on the TvTextField (onUp/Down/Left/RightArrow).
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

    // No periodic screen-level refresh: the tuner runs its own 15s tick
    // (gated on the Auto-refresh setting, passed below) for progress bars
    // and slot rollovers, so a 30s whole-screen setState here was pure
    // rebuild churn on top of it.
  }

  @override
  void dispose() {
    _contentRevision.dispose();
    _searchBtnFocusNode.dispose();
    _providerFocusNode.dispose();
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
    final debridProvider = await StorageService.getStremioTvDebridProvider();
    _availableProviders = await _loadAvailableProviders();
    if (debridProvider != 'auto' &&
        !_availableProviders.any(
          (provider) => provider.key == debridProvider,
        )) {
      _debridProvider = 'auto';
      await StorageService.setStremioTvDebridProvider('auto');
    } else {
      _debridProvider = debridProvider;
    }
    _rdSkipBlockedTorrents = await StorageService.getRdSkipBlockedTorrents();
    _torrentsFirst = await StorageService.getStremioTvTorrentsFirst();
    _maxStartPercent = await StorageService.getStremioTvMaxStartPercent();
    _hideNowPlaying = await StorageService.getStremioTvHideNowPlaying();
  }

  Future<List<MapEntry<String, String>>> _loadAvailableProviders() async {
    final providers = <MapEntry<String, String>>[];
    final rdKey = await StorageService.getApiKey();
    if (rdKey != null && rdKey.isNotEmpty) {
      providers.add(const MapEntry('realdebrid', 'Real-Debrid'));
    }
    final tbKey = await StorageService.getTorboxApiKey();
    if (tbKey != null && tbKey.isNotEmpty) {
      providers.add(const MapEntry('torbox', 'TorBox'));
    }
    final pikpakEnabled = await StorageService.getPikPakEnabled();
    if (pikpakEnabled) {
      providers.add(const MapEntry('pikpak', 'PikPak'));
    }
    final pmEnabled = await StorageService.getPremiumizeIntegrationEnabled();
    final pmKey = await StorageService.getPremiumizeApiKey();
    if (pmEnabled && pmKey != null && pmKey.isNotEmpty) {
      providers.add(const MapEntry('premiumize', 'Premiumize'));
    }
    final adEnabled = await StorageService.getAllDebridIntegrationEnabled();
    final adKey = await StorageService.getAllDebridApiKey();
    if (adEnabled && adKey != null && adKey.isNotEmpty) {
      providers.add(const MapEntry('alldebrid', 'AllDebrid'));
    }
    return providers;
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

  Widget _topMenuItem({
    required Widget leadingIcon,
    required String label,
    required VoidCallback onPressed,
    required MenuController controller,
    required FocusNode anchorFocusNode,
    bool autofocus = false,
    bool closeOnArrowUp = false,
  }) {
    return Focus(
      canRequestFocus: false,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if ((closeOnArrowUp &&
                event.logicalKey == LogicalKeyboardKey.arrowUp) ||
            event.logicalKey == LogicalKeyboardKey.escape ||
            event.logicalKey == LogicalKeyboardKey.goBack) {
          controller.close();
          anchorFocusNode.requestFocus();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: MenuItemButton(
        autofocus: autofocus,
        leadingIcon: leadingIcon,
        onPressed: onPressed,
        child: Text(label),
      ),
    );
  }

  Future<void> _openChannelFilter() async {
    final filterTree = await _service.getFilterTree();
    final disabledBefore = await StorageService.getStremioTvDisabledFilters();
    if (!mounted) return;

    // Full-screen DPAD-first filter page (instant push, matching the
    // channel-detail transition). The page persists before popping and
    // reports whether anything changed.
    final changed = await Navigator.of(context).push<bool>(
      PageRouteBuilder(
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (_, __, ___) => StremioTvFilterPage(
          filterTree: filterTree,
          disabledFilters: Set.of(disabledBefore),
          isTelevision: widget.isTelevision,
        ),
      ),
    );

    if (changed == true && mounted) {
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

  Future<void> _importFromMdblist() async {
    final imported = await StremioTvLocalCatalogsDialog.importFromMdblist(
      context,
    );
    if (imported && mounted) _refresh();
  }

  Future<void> _openStremioTvSettings() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const StremioTvSettingsPage()));
    if (!mounted) return;
    await _loadSettings();
    if (mounted) setState(() {});
  }

  Future<void> _setDebridProvider(String value) async {
    await StorageService.setStremioTvDebridProvider(value);
    if (!mounted) return;
    setState(() => _debridProvider = value);
  }

  String _providerShortLabel(String provider) {
    switch (provider) {
      case 'realdebrid':
        return 'RD';
      case 'torbox':
        return 'TB';
      case 'pikpak':
        return 'PP';
      case 'premiumize':
        return 'PM';
      case 'alldebrid':
        return 'AD';
      default:
        return 'AUTO';
    }
  }

  String _providerFullLabel(String provider) {
    switch (provider) {
      case 'realdebrid':
        return 'Real-Debrid';
      case 'torbox':
        return 'TorBox';
      case 'pikpak':
        return 'PikPak';
      case 'premiumize':
        return 'Premiumize';
      case 'alldebrid':
        return 'AllDebrid';
      default:
        if (_availableProviders.isEmpty) return 'Auto';
        return 'Auto (${_availableProviders.first.value})';
    }
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
      // Items landed for an existing channel: rebuild just the tuner (via its
      // ValueListenableBuilder), not the whole screen — a full setState here
      // fired once per completing fetch and stuttered mid-surf navigation.
      _contentRevision.value++;
    }
  }

  // ============================================================================
  // Playback
  // ============================================================================

  /// Extract normalized quality from a stream/torrent name.
  /// Returns '2160p', '1080p', '720p', '480p', or null.
  static String? _extractQuality(String name) {
    switch (sourceQualityForName(name)) {
      case SourceQuality.ultraHd:
        return '2160p';
      case SourceQuality.fullHd:
        return '1080p';
      case SourceQuality.hd:
        return '720p';
      case SourceQuality.sd:
        return '480p';
      case null:
        return null;
    }
  }

  /// Sort streams so those matching [_preferredQuality] come first.
  /// Within same-quality group, preserves original order.
  Future<({String url, int index})?> _tryDirectStreams(
    List<Torrent> playableSources,
    int myGeneration,
  ) async {
    final directStreams = _sortStreamsByQuality(
      playableSources.where((t) => t.isDirectStream).toList(),
    );
    final maxDirectAttempts = directStreams.length.clamp(0, 20);
    for (int d = 0; d < maxDirectAttempts; d++) {
      final stream = directStreams[d];
      if (stream.directUrl == null || stream.directUrl!.isEmpty) continue;
      if (!mounted || _playGeneration != myGeneration) return null;
      final valid = await _isValidStreamUrl(stream.directUrl!);
      if (!mounted || _playGeneration != myGeneration) return null;
      if (valid) {
        final index = playableSources.indexWhere(
          (t) => t.directUrl == stream.directUrl && t.name == stream.name,
        );
        return (url: stream.directUrl!, index: index < 0 ? 0 : index);
      }
      debugPrint(
        'StremioTV: Skipping invalid direct stream: ${stream.source}',
      );
    }
    return null;
  }

  Future<({String url, int index})?> _tryTorrentsViaDebrid(
    List<Torrent> playableSources,
    StremioMeta item,
    int myGeneration, {
    int? season,
    int? episode,
  }) async {
    final torrentStreams = _sortStreamsByQuality(
      playableSources
          .where((t) => t.streamType == StreamType.torrent)
          .toList(),
    );
    final maxTorrentAttempts = torrentStreams.length.clamp(0, 20);
    final attemptedTorrents = torrentStreams
        .take(maxTorrentAttempts)
        .toList();
    final loadAutoTorboxCachedHashes =
        StremioTvDebridFallback.memoizeAsync<Set<String>>(
      () => _loadTorboxCachedHashes(
        attemptedTorrents,
        isCancelled: () =>
            !mounted || _playGeneration != myGeneration,
      ),
    );

    for (int i = 0; i < maxTorrentAttempts; i++) {
      if (!mounted || _playGeneration != myGeneration) return null;
      final url = await _resolveTorrentUrl(
        torrentStreams[i],
        item,
        _debridProvider,
        season: season,
        episode: episode,
        isCancelled: () =>
            !mounted || _playGeneration != myGeneration,
        loadAutoTorboxCachedHashes: _debridProvider == 'auto'
            ? loadAutoTorboxCachedHashes
            : null,
      );
      if (url != null && url.isNotEmpty) {
        final index = playableSources.indexWhere(
          (t) =>
              t.infohash == torrentStreams[i].infohash &&
              t.name == torrentStreams[i].name,
        );
        return (url: url, index: index < 0 ? 0 : index);
      }
      debugPrint(
        'StremioTV: Torrent ${i + 1}/$maxTorrentAttempts failed, '
        '${i + 1 < maxTorrentAttempts ? "trying next..." : "giving up."}',
      );
    }
    return null;
  }

  /// Filters torrent candidates down to those that can actually provide the
  /// requested [season]/[episode]:
  ///  - non-torrent streams (direct/addon) pass through — they were queried
  ///    per-episode already;
  ///  - season/multi-season/complete packs are kept when they cover the target
  ///    season (or their range is unknown, in which case in-pack file
  ///    selection picks the episode);
  ///  - single-episode torrents are dropped only when we CONFIDENTLY parse a
  ///    different S/E from the name; ambiguous/unparseable names are kept.
  ///
  /// If every candidate is confidently a different episode this can return no
  /// torrents — that is intentional (see note at the return).
  List<Torrent> _filterTorrentsForEpisode(
    List<Torrent> sources, {
    required int season,
    required int episode,
  }) {
    final kept = <Torrent>[];
    for (final t in sources) {
      if (t.streamType != StreamType.torrent) {
        kept.add(t);
        continue;
      }
      final coverage = TorrentCoverageDetector.detectCoverage(
        title: t.name,
        infohash: t.infohash,
      );
      switch (coverage.coverageType) {
        case CoverageType.completeSeries:
          kept.add(t);
          break;
        case CoverageType.multiSeasonPack:
          if (coverage.startSeason == null ||
              coverage.endSeason == null ||
              (season >= coverage.startSeason! &&
                  season <= coverage.endSeason!)) {
            kept.add(t);
          }
          break;
        case CoverageType.seasonPack:
          if (coverage.seasonNumber == null ||
              coverage.seasonNumber == season) {
            kept.add(t);
          }
          break;
        case CoverageType.singleEpisode:
          final info = SeriesParser.parseFilename(t.name);
          // Only drop when we're CONFIDENT it's a different episode — i.e. both
          // season and episode parsed and at least one differs. Ambiguous /
          // unparseable names are kept (could be the right episode with odd
          // naming, or a pack we failed to classify).
          final confidentMismatch = info.season != null &&
              info.episode != null &&
              (info.season != season || info.episode != episode);
          if (!confidentMismatch) {
            kept.add(t);
          }
          break;
      }
    }

    // NOTE: we intentionally do NOT fall back to the unfiltered set when this
    // leaves zero torrents. Zero here means every candidate confidently parsed
    // to a *different* episode, so falling back would replay the exact bug this
    // filter exists to fix. Returning the filtered set lets resolution use any
    // per-episode direct streams, or fail so the next-provider advances to a
    // slot/episode we can actually play correctly.
    return kept;
  }

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

  /// Direct-stream validity: delegated to the shared [StreamUrlValidator]
  /// (extracted from this screen so quick-play uses the identical check).
  Future<bool> _isValidStreamUrl(String url) =>
      StreamUrlValidator.isPlayableVideoUrl(url);

  /// Maps the active debrid provider to the Pipeline loader's chip label,
  /// two-letter code, accent colour, and whether it runs a cache-check stage.
  /// Colours mirror the Home/Search play loader (torrent_playback_service).
  ({String label, String code, Color color, bool cacheCheck}) _tvProviderInfo() {
    switch (_debridProvider) {
      case 'realdebrid':
        return (
          label: 'Real-Debrid',
          code: 'RD',
          color: const Color(0xFF10B981),
          cacheCheck: false,
        );
      case 'torbox':
        return (
          label: 'TorBox',
          code: 'TB',
          color: const Color(0xFF8B5CF6),
          cacheCheck: true,
        );
      case 'premiumize':
        return (
          label: 'Premiumize',
          code: 'PM',
          color: const Color(0xFFF59E0B),
          cacheCheck: true,
        );
      case 'alldebrid':
        return (
          label: 'AllDebrid',
          code: 'AD',
          color: const Color(0xFF26A69A),
          cacheCheck: false,
        );
      case 'pikpak':
        return (
          label: 'PikPak',
          code: 'PP',
          color: const Color(0xFF6366F1),
          cacheCheck: false,
        );
      default:
        return (
          label: 'Debrid',
          code: 'DB',
          color: PipelineLoadingOverlay.accent,
          cacheCheck: false,
        );
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

    // Cinematic staged loader (matches Home → detail → Play). Shown up front so
    // it also covers the random-episode resolve; the subtitle is omitted since
    // the episode isn't known yet for series.
    if (!mounted) return;
    final app = AppThemeScope.of(context);
    final pInfo = _tvProviderInfo();
    final overlay = PipelineLoadingOverlay.show(
      context,
      posterUrl: item.poster ?? item.background,
      title: item.name,
      providerLabel: pInfo.label,
      providerCode: pInfo.code,
      providerColor: pInfo.color,
      hasCacheCheck: pInfo.cacheCheck,
      // The loader is a dark cinematic plate on every theme (black Material,
      // black-at-alpha scrims), so its ink is `onGlass`, never page ink.
      // `inkOnFill` is already contrast-scored against the accent it sits on.
      loaderGround: app.stremioTv.loaderGround,
      loaderAccent: app.stremioTv.loaderAccent,
      loaderAccent2: app.stremioTv.loaderAccent2,
      railFar: app.stremioTv.loaderRailFar,
      // Settings → Appearance → Play Loader: the same look the Home/detail
      // play path uses, so a Debrify TV launch doesn't contradict the choice.
      style: PlayLoaderStyleController.cached ==
              PlayLoaderStyleController.classic
          ? PlayLoaderStyle.classic
          : PlayLoaderStyle.marquee,
      art: PlayLoaderArt.fromMeta(item),
      ink: app.onGlass,
      inkOnFill: app.stremioTv.inkOnFill,
      onCancel: () {
        // The overlay dismisses itself; just abort the in-flight play. Every
        // await below bails on the _playGeneration mismatch.
        _playGeneration++;
        _notifyStartupAutoLaunchFailed('Playback canceled');
      },
    );

    // For series, resolve a random episode first
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

      if (!mounted || _playGeneration != myGeneration) {
        overlay.dismiss();
        return;
      }

      if (resolved == null) {
        overlay.dismiss();
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

    try {
      final isMovie = item.type.toLowerCase() == 'movie';
      final results = await TorrentService.searchByImdbWithStremio(
        item.effectiveImdbId ?? item.id,
        isMovie: isMovie,
        season: season,
        episode: episode,
        contentType: item.type,
        stremioTimeout: const Duration(seconds: 7),
        engineTimeout: const Duration(seconds: 10),
      );

      if (!mounted || _playGeneration != myGeneration) {
        overlay.dismiss();
        return;
      }

      final torrents = results['torrents'] as List<Torrent>? ?? [];
      final directCount = torrents.where((t) => t.isDirectStream).length;
      final torrentCount = torrents
          .where((t) => !t.isDirectStream && !t.isExternalStream)
          .length;
      overlay.setStage(
        PlayLoadStage.searching,
        sourceCount: directCount + torrentCount,
      );

      if (torrents.isEmpty) {
        overlay.dismiss();
        _notifyStartupAutoLaunchFailed('No streams found');
        if (mounted) {
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

      // Drop torrents that belong to a different episode (see
      // _filterTorrentsForEpisode) — keyword engines return the whole series,
      // and the top-seeded wrong episode would otherwise win auto-play.
      if (!isMovie && season != null && episode != null) {
        playableSources = _filterTorrentsForEpisode(
          playableSources,
          season: season,
          episode: episode,
        );
      }

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
            if (!mounted) {
              overlay.dismiss();
              return;
            }
            overlay.setStage(PlayLoadStage.cacheCheck);
            final cachedHashes = await TorboxService.checkCachedTorrents(
              apiKey: tbKey,
              infoHashes: torrentHashes,
            );
            final cachedSet = cachedHashes
                .map((h) => h.trim().toLowerCase())
                .toSet();
            overlay.setStage(
              PlayLoadStage.cacheCheck,
              cachedCount: cachedSet.length,
            );
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

      // For Premiumize, filter torrent sources to only cached ones
      if (_debridProvider == 'premiumize') {
        final pmKey = await StorageService.getPremiumizeApiKey();
        if (pmKey != null && pmKey.isNotEmpty) {
          final torrentSources = playableSources
              .where((t) => t.streamType == StreamType.torrent)
              .toList();
          final torrentHashes = torrentSources
              .map((t) => t.infohash.trim().toLowerCase())
              .where((h) => h.isNotEmpty)
              .toList();
          if (torrentHashes.isNotEmpty) {
            if (!mounted) {
              overlay.dismiss();
              return;
            }
            overlay.setStage(PlayLoadStage.cacheCheck);
            final cachedResults = await PremiumizeService.checkCache(
              pmKey,
              torrentHashes,
            );
            final cachedSet = <String>{};
            for (int i = 0; i < torrentHashes.length; i++) {
              if (i < cachedResults.length && cachedResults[i]) {
                cachedSet.add(torrentHashes[i]);
              }
            }
            overlay.setStage(
              PlayLoadStage.cacheCheck,
              cachedCount: cachedSet.length,
            );
            debugPrint(
              'StremioTV: Premiumize cache check: ${cachedSet.length} cached '
              'out of ${torrentHashes.length} torrents',
            );
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
        overlay.dismiss();
        _notifyStartupAutoLaunchFailed('No playable streams found');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('No playable streams found for ${item.name}'),
            ),
          );
        }
        return;
      }

      // Try to find the best stream to auto-play
      if (_preferredQuality != 'auto') {
        debugPrint('StremioTV: Preferred quality: $_preferredQuality');
      }

      String? firstPlayableUrl;
      int firstPlayableIndex = 0;

      // Resolving the actual stream URL via the debrid provider.
      overlay.setStage(PlayLoadStage.preparing);

      // Try torrents or direct streams based on setting, fall back to the other
      ({String url, int index})? resolved;
      if (_torrentsFirst) {
        resolved = await _tryTorrentsViaDebrid(
          playableSources, item, myGeneration, season: season, episode: episode,
        );
        resolved ??= await _tryDirectStreams(playableSources, myGeneration);
      } else {
        resolved = await _tryDirectStreams(playableSources, myGeneration);
        resolved ??= await _tryTorrentsViaDebrid(
          playableSources, item, myGeneration, season: season, episode: episode,
        );
      }
      if (resolved != null) {
        firstPlayableUrl = resolved.url;
        firstPlayableIndex = resolved.index;
      }

      if (firstPlayableUrl == null || firstPlayableUrl.isEmpty) {
        overlay.dismiss();
        _notifyStartupAutoLaunchFailed('No auto-play stream resolved');
        // Skip the manual picker if the play was cancelled mid-resolve.
        if (mounted && _playGeneration == myGeneration) {
          // Show source picker so user can manually select
          final result = await _showManualSourcePicker(
            playableSources,
            item,
            season: season,
            episode: episode,
          );
          if (result != null && mounted) {
            _notifyStartupPlayerLaunching();
            _rememberPlaybackCursor(
              channel.id,
              baseSlotStartMs: nowPlaying.slotStart.millisecondsSinceEpoch,
              slotOffset: 0,
            );
            await VideoPlayerLauncher.push(
              context,
              VideoPlayerLaunchArgs(
                videoUrl: result.url,
                title: _currentPlayTitle ?? item.name,
                startAtPercent: _currentSlotProgress,
                contentImdbId: item.effectiveImdbId,
                contentTitle: item.name,
                contentType: item.type,
                contentSeason: season,
                contentEpisode: episode,
                stremioSources: playableSources,
                stremioCurrentSourceIndex: result.sourceIndex,
                resolveStremioSource: _createSourceResolver(
                  item,
                  season: season,
                  episode: episode,
                ),
                stremioTvChannels: _buildGuideChannelMetadata(),
                stremioTvCurrentChannelId: channel.id,
                stremioTvRotationMinutes: _rotationMinutes,
                stremioTvSeriesRotationMinutes: _seriesRotationMinutes,
                stremioTvMixSalt: _mixSalt,
                stremioTvGuideDataProvider: _createGuideDataProvider(),
                stremioTvChannelSwitchProvider: _createChannelSwitchProvider(),
                stremioTvNextProvider: _createNextProvider(),
              ),
            );
          }
        }
        return;
      }

      // Also honour a Cancel that landed while the stream was resolving — the
      // resolve helpers can return a valid URL after onCancel bumped the
      // generation, and this is the last gate before launch.
      if (!mounted || _playGeneration != myGeneration) {
        overlay.dismiss();
        return;
      }

      // Tick the final stage, then dismiss right before the player launches.
      overlay.setStage(PlayLoadStage.starting);
      overlay.dismiss();
      _notifyStartupPlayerLaunching();
      _rememberPlaybackCursor(
        channel.id,
        baseSlotStartMs: nowPlaying.slotStart.millisecondsSinceEpoch,
        slotOffset: 0,
      );

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
          contentSeason: season,
          contentEpisode: episode,
          stremioSources: playableSources,
          stremioCurrentSourceIndex: firstPlayableIndex,
          resolveStremioSource: _createSourceResolver(
            item,
            season: season,
            episode: episode,
          ),
          stremioTvChannels: _buildGuideChannelMetadata(),
          stremioTvCurrentChannelId: channel.id,
          stremioTvRotationMinutes: _rotationMinutes,
          stremioTvSeriesRotationMinutes: _seriesRotationMinutes,
          stremioTvMixSalt: _mixSalt,
          stremioTvGuideDataProvider: _createGuideDataProvider(),
          stremioTvChannelSwitchProvider: _createChannelSwitchProvider(),
          stremioTvNextProvider: _createNextProvider(),
        ),
      );
    } catch (e) {
      overlay.dismiss();
      _notifyStartupAutoLaunchFailed('Error searching streams: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error searching streams: $e')));
    }
  }

  /// Resolves a channel to a playable URL without any UI interactions.
  /// Used by the in-player channel guide for background channel switching.
  Future<_ChannelPlaybackResult?> _resolveChannelPlayback(
    StremioTvChannel channel, {
    int slotOffset = 0,
  }) async {
    // Ensure items are loaded
    if (!channel.hasItems) {
      await _ensureChannelItemsLoaded(channel);
    }

    final schedule = _service.getSchedule(
      channel,
      count: slotOffset + 2,
      rotationMinutes: _rotationFor(channel),
      salt: _mixSalt,
    );
    if (schedule.length <= slotOffset) return null;

    final basePlaying = schedule.first;
    final nowPlaying = schedule[slotOffset];
    final nextPlaying = schedule.length > slotOffset + 1
        ? schedule[slotOffset + 1]
        : null;

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
    final results = await TorrentService.searchByImdbWithStremio(
      item.effectiveImdbId ?? item.id,
      isMovie: isMovie,
      season: season,
      episode: episode,
      contentType: item.type,
      stremioTimeout: const Duration(seconds: 7),
    );

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

    // Episode-match filter — many engines (e.g. apibay keyword search) return
    // single-episode torrents for the WRONG episode of the same series. Without
    // this, the highest-seeded unrelated episode wins auto-play and every slot
    // plays the same file. Keep exact-episode matches + season-covering packs,
    // drop single-episode torrents that belong to a different episode.
    if (!isMovie && season != null && episode != null) {
      playableSources = _filterTorrentsForEpisode(
        playableSources,
        season: season,
        episode: episode,
      );
    }

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

    // Premiumize cache filter
    if (_debridProvider == 'premiumize') {
      final pmKey = await StorageService.getPremiumizeApiKey();
      if (pmKey != null && pmKey.isNotEmpty) {
        final torrentSources = playableSources
            .where((t) => t.streamType == StreamType.torrent)
            .toList();
        final torrentHashes = torrentSources
            .map((t) => t.infohash.trim().toLowerCase())
            .where((h) => h.isNotEmpty)
            .toList();
        if (torrentHashes.isNotEmpty) {
          final cachedResults = await PremiumizeService.checkCache(
            pmKey,
            torrentHashes,
          );
          final cachedSet = <String>{};
          for (int i = 0; i < torrentHashes.length; i++) {
            if (i < cachedResults.length && cachedResults[i]) {
              cachedSet.add(torrentHashes[i]);
            }
          }
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

    // Auto-play best stream (respects torrents-first setting)
    final gen = _playGeneration;
    ({String url, int index})? resolved;
    if (_torrentsFirst) {
      resolved = await _tryTorrentsViaDebrid(
        playableSources, item, gen, season: season, episode: episode,
      );
      resolved ??= await _tryDirectStreams(playableSources, gen);
    } else {
      resolved = await _tryDirectStreams(playableSources, gen);
      resolved ??= await _tryTorrentsViaDebrid(
        playableSources, item, gen, season: season, episode: episode,
      );
    }

    if (resolved == null) return null;

    final firstPlayableUrl = resolved.url;
    final firstPlayableIndex = resolved.index;

    final title = season != null
        ? '${item.name} (S${season}E$episode)'
        : playTitle;

    return _ChannelPlaybackResult(
      url: firstPlayableUrl,
      title: title,
      contentType: item.type,
      contentImdbId: item.effectiveImdbId,
      contentSeason: season,
      contentEpisode: episode,
      startAtPercent: slotProgress,
      playableSources: playableSources,
      sourceIndex: firstPlayableIndex,
      sourceResolver: _createSourceResolver(
        item,
        season: season,
        episode: episode,
      ),
      nowPlayingGuideData: _guideDataFor(nowPlaying),
      nextUpGuideData: nextPlaying != null ? _guideDataFor(nextPlaying) : null,
      baseSlotStartMs: basePlaying.slotStart.millisecondsSinceEpoch,
      slotOffset: slotOffset,
    );
  }

  /// Show a bottom sheet with all available sources so the user can pick one manually.
  /// Returns (resolvedUrl, sourceIndex) or null if dismissed.
  Future<_ResolvedSourceChoice?> _showManualSourcePicker(
    List<Torrent> sources,
    StremioMeta item, {
    int? season,
    int? episode,
  }) async {
    final resolver = _createSourceResolver(
      item,
      season: season,
      episode: episode,
    );
    return showModalBottomSheet<_ResolvedSourceChoice?>(
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

  void _rememberPlaybackCursor(
    String channelId, {
    required int baseSlotStartMs,
    required int slotOffset,
  }) {
    _playbackCursors[channelId] = _StremioTvPlaybackCursor(
      baseSlotStartMs: baseSlotStartMs,
      slotOffset: slotOffset,
    );
  }

  int _nextSlotOffsetFor(StremioTvChannel channel) {
    final current = _service.getNowPlaying(
      channel,
      rotationMinutes: _rotationFor(channel),
      salt: _mixSalt,
    );
    if (current == null) return 1;

    final currentBaseMs = current.slotStart.millisecondsSinceEpoch;
    final cursor = _playbackCursors[channel.id];
    if (cursor == null || cursor.baseSlotStartMs != currentBaseMs) {
      return 1;
    }
    return cursor.slotOffset + 1;
  }

  Map<String, dynamic> _guideDataFor(StremioTvNowPlaying playing) {
    return {
      'title': playing.item.name,
      'poster': playing.item.poster,
      'year': playing.item.year,
      'rating': playing.item.imdbRating,
      'type': playing.item.type,
      'slotEndMs': playing.slotEnd.millisecondsSinceEpoch,
      'progress': playing.progress,
    };
  }

  Map<String, dynamic> _playbackResultToMap(
    String channelId,
    _ChannelPlaybackResult result,
  ) {
    return {
      'channelId': channelId,
      'url': result.url,
      'title': result.title,
      'contentType': result.contentType,
      'contentImdbId': result.contentImdbId,
      if (result.contentSeason != null) 'contentSeason': result.contentSeason,
      if (result.contentEpisode != null)
        'contentEpisode': result.contentEpisode,
      'startAtPercent': result.startAtPercent,
      'stremioSources': result.playableSources.map((t) => t.toJson()).toList(),
      'stremioCurrentSourceIndex': result.sourceIndex,
      'sourceResolver': result.sourceResolver,
      'nowPlaying': result.nowPlayingGuideData,
      if (result.nextUpGuideData != null) 'nextUp': result.nextUpGuideData,
    };
  }

  // ─── Source Resolution (no dialogs, returns URL) ────────────────────

  /// Creates a resolver closure that snapshots current state at creation time.
  Future<String?> Function(Torrent) _createSourceResolver(
    StremioMeta item, {
    int? season,
    int? episode,
  }) {
    final debridProvider = _debridProvider;
    return (Torrent torrent) async {
      if (torrent.isDirectStream) {
        return torrent.directUrl;
      }
      if (torrent.streamType == StreamType.torrent) {
        return _resolveTorrentUrl(
          torrent,
          item,
          debridProvider,
          season: season,
          episode: episode,
        );
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
      _rememberPlaybackCursor(
        channelId,
        baseSlotStartMs: result.baseSlotStartMs,
        slotOffset: result.slotOffset,
      );
      return _playbackResultToMap(channelId, result);
    };
  }

  /// Creates a provider for the player Next button in Stremio TV mode.
  ///
  /// It advances one guide slot at a time and keeps a small per-channel cursor.
  /// An unavailable slot is reported to the player instead of silently skipping
  /// over another series and making the channel appear to contain one title.
  /// The failed slot is still remembered, so another explicit Next press moves
  /// on rather than retrying it forever.
  Future<Map<String, dynamic>?> Function(String) _createNextProvider() {
    return (String channelId) async {
      final ch = _channels.firstWhereOrNull((c) => c.id == channelId);
      if (ch == null) return null;

      final slotOffset = _nextSlotOffsetFor(ch);
      final result = await _resolveChannelPlayback(
        ch,
        slotOffset: slotOffset,
      );
      if (result != null) {
        _rememberPlaybackCursor(
          channelId,
          baseSlotStartMs: result.baseSlotStartMs,
          slotOffset: result.slotOffset,
        );
        return _playbackResultToMap(channelId, result);
      }

      debugPrint(
        'StremioTV next: slot offset $slotOffset unavailable; '
        'not skipping it silently.',
      );
      final current = _service.getNowPlaying(
        ch,
        rotationMinutes: _rotationFor(ch),
        salt: _mixSalt,
      );
      if (current != null) {
        _rememberPlaybackCursor(
          channelId,
          baseSlotStartMs: current.slotStart.millisecondsSinceEpoch,
          slotOffset: slotOffset,
        );
      }
      return null;
    };
  }

  /// Resolve a torrent to a playable URL via the given debrid provider.
  Future<String?> _resolveTorrentUrl(
    Torrent torrent,
    StremioMeta item,
    String debridProvider, {
    int? season,
    int? episode,
    bool Function()? isCancelled,
    Future<Set<String>> Function()? loadAutoTorboxCachedHashes,
  }) => StremioTvDebridFallback.resolve<String>(
    selected: debridProvider,
    isCancelled: isCancelled,
    canAttempt: (provider) async {
      switch (provider) {
        case 'realdebrid':
          return !_rdSkipBlockedTorrents ||
              !isRdBlockedTorrent(torrent.name);
        case 'torbox':
          if (debridProvider != 'auto') return true;
          final cachedHashes = loadAutoTorboxCachedHashes != null
              ? await loadAutoTorboxCachedHashes()
              : await _loadTorboxCachedHashes(
                  <Torrent>[torrent],
                  isCancelled: isCancelled,
                );
          return cachedHashes.contains(
            torrent.infohash.trim().toLowerCase(),
          );
        case 'premiumize':
          return StorageService.getPremiumizeIntegrationEnabled();
        case 'alldebrid':
          return StorageService.getAllDebridIntegrationEnabled();
        default:
          return true;
      }
    },
    attempt: (provider) async {
      switch (provider) {
        case 'realdebrid':
          final apiKey = await StorageService.getApiKey();
          if (apiKey == null || apiKey.isEmpty) return null;
          return _resolveViaRealDebrid(
            torrent,
            item,
            apiKey,
            season: season,
            episode: episode,
          );
        case 'torbox':
          final apiKey = await StorageService.getTorboxApiKey();
          if (apiKey == null || apiKey.isEmpty) return null;
          return _resolveViaTorbox(
            torrent,
            item,
            apiKey,
            season: season,
            episode: episode,
            isCancelled: isCancelled,
          );
        case 'pikpak':
          if (!await StorageService.getPikPakEnabled()) return null;
          return _resolveViaPikPak(
            torrent,
            item,
            season: season,
            episode: episode,
            isCancelled: isCancelled,
          );
        case 'premiumize':
          final apiKey = await StorageService.getPremiumizeApiKey();
          if (apiKey == null || apiKey.isEmpty) return null;
          return _resolveViaPremiumize(
            torrent,
            item,
            apiKey,
            season: season,
            episode: episode,
          );
        case 'alldebrid':
          final apiKey = await StorageService.getAllDebridApiKey();
          if (apiKey == null || apiKey.isEmpty) return null;
          return _resolveViaAllDebrid(
            torrent,
            item,
            apiKey,
            season: season,
            episode: episode,
          );
      }
      return null;
    },
  );

  Future<Set<String>> _loadTorboxCachedHashes(
    Iterable<Torrent> torrents, {
    bool Function()? isCancelled,
  }) async {
    if (isCancelled?.call() ?? false) return const <String>{};

    final apiKey = await StorageService.getTorboxApiKey();
    if (apiKey == null ||
        apiKey.isEmpty ||
        (isCancelled?.call() ?? false)) {
      return const <String>{};
    }

    final infoHashes = torrents
        .map((torrent) => torrent.infohash.trim().toLowerCase())
        .where((hash) => hash.isNotEmpty)
        .toSet()
        .toList();
    if (infoHashes.isEmpty) return const <String>{};

    try {
      final cachedHashes = await TorboxService.checkCachedTorrents(
        apiKey: apiKey,
        infoHashes: infoHashes,
      );
      if (isCancelled?.call() ?? false) return const <String>{};

      final normalized = cachedHashes
          .map((hash) => hash.trim().toLowerCase())
          .where((hash) => hash.isNotEmpty)
          .toSet();
      debugPrint(
        'StremioTV: Auto TorBox cache check found ${normalized.length} '
        'of ${infoHashes.length} candidate(s)',
      );
      return normalized;
    } catch (e) {
      debugPrint('StremioTV: TorBox cache check failed: $e');
      return const <String>{};
    }
  }

  Future<String?> _resolveViaRealDebrid(
    Torrent torrent,
    StremioMeta item,
    String apiKey, {
    int? season,
    int? episode,
  }) async {
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
      final selectedVideoFiles = <Map<String, dynamic>>[];
      final selectedVideoLinks = <String>[];
      int linkIndex = 0;
      for (final file in files) {
        if (file is! Map<String, dynamic>) continue;
        final selected = file['selected'] == 1 || file['selected'] == true;
        if (!selected) continue;
        final rawName =
            (file['path'] as String?) ?? (file['name'] as String?) ?? '';
        if (FileUtils.isVideoFile(FileUtils.getFileName(rawName)) &&
            linkIndex < links.length) {
          selectedVideoFiles.add(file);
          selectedVideoLinks.add(links[linkIndex].toString());
        }
        linkIndex++;
      }

      final isSeries = item.type.toLowerCase() == 'series';
      if (isSeries && season != null && episode != null) {
        final candidateNames = selectedVideoFiles.map((file) {
          return (file['path'] as String?) ?? (file['name'] as String?) ?? '';
        }).toList();
        final targetIndex = StremioEpisodeSelector
            .findEpisodeFileIndexWithSingleFileFallback(
          candidateNames,
          sourceName: torrent.name,
          season: season,
          episode: episode,
        );
        if (targetIndex == null || targetIndex >= selectedVideoLinks.length) {
          debugPrint(
            'StremioTV: RD could not match S${season}E$episode in ${torrent.name}, '
            'rejecting source',
          );
          final torrentId = result['torrentId']?.toString();
          if (torrentId != null && torrentId.isNotEmpty) {
            try {
              await DebridService.deleteTorrent(apiKey, torrentId);
            } catch (_) {}
          }
          return null;
        } else {
          linkToUnrestrict = selectedVideoLinks[targetIndex];
        }
      } else if (item.type.toLowerCase() == 'movie' &&
          selectedVideoLinks.length > 1) {
        final targetIndex = StremioEpisodeSelector.findLargestFileIndex(
          selectedVideoFiles.map((file) => file['bytes'] as int?).toList(),
        );
        if (targetIndex < selectedVideoLinks.length) {
          linkToUnrestrict = selectedVideoLinks[targetIndex];
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

  /// Resolves a torrent to a playable URL via AllDebrid. Follows the
  /// Real-Debrid model (no cache-check API): adds the magnet trusting the
  /// `ready` flag (no polling), and on not-ready deletes the magnet and
  /// returns null so the caller probes the next source. Picks the episode
  /// (series) or largest file (movie), then unlocks that locked link.
  Future<String?> _resolveViaAllDebrid(
    Torrent torrent,
    StremioMeta item,
    String apiKey, {
    int? season,
    int? episode,
  }) async {
    try {
      final magnet =
          'magnet:?xt=urn:btih:${torrent.infohash}&dn=${Uri.encodeComponent(torrent.name)}';
      AllDebridAddResult result;
      try {
        result = await AllDebridService.addMagnetAndResolveFiles(apiKey, magnet);
      } on AllDebridTorrentNotReadyException catch (e) {
        // Not cached/ready — don't leave it downloading on the account.
        await AllDebridService.deleteMagnet(e.apiKey, e.magnetId);
        return null;
      }

      final videoFiles = result.files
          .where((f) => FileUtils.isVideoFile(f.fileName))
          .toList();
      if (videoFiles.isEmpty) return null;

      String targetLink = videoFiles.first.link;

      final isSeries = item.type.toLowerCase() == 'series';
      if (isSeries && season != null && episode != null) {
        final candidateNames = videoFiles.map((f) => f.path).toList();
        final targetIndex = StremioEpisodeSelector
            .findEpisodeFileIndexWithSingleFileFallback(
          candidateNames,
          sourceName: torrent.name,
          season: season,
          episode: episode,
        );
        if (targetIndex == null || targetIndex >= videoFiles.length) {
          debugPrint(
            'StremioTV: AllDebrid could not match S${season}E$episode in '
            '${torrent.name}, rejecting source',
          );
          try {
            await AllDebridService.deleteMagnet(apiKey, result.magnetId);
          } catch (_) {}
          return null;
        } else {
          targetLink = videoFiles[targetIndex].link;
        }
      } else if (item.type.toLowerCase() == 'movie' && videoFiles.length > 1) {
        final targetIndex = StremioEpisodeSelector.findLargestFileIndex(
          videoFiles.map<int?>((f) => f.size).toList(),
        );
        if (targetIndex < videoFiles.length) {
          targetLink = videoFiles[targetIndex].link;
        }
      }

      if (targetLink.isEmpty) return null;
      final url = await AllDebridService.unlockLink(apiKey, targetLink);
      return url.isEmpty ? null : url;
    } catch (e) {
      debugPrint('StremioTV: AllDebrid resolve error: $e');
      return null;
    }
  }

  Future<String?> _resolveViaTorbox(
    Torrent torrent,
    StremioMeta item,
    String apiKey, {
    int? season,
    int? episode,
    bool Function()? isCancelled,
  }) async {
    int? createdTorrentId;
    var keepTorrent = false;
    try {
      final magnet =
          'magnet:?xt=urn:btih:${torrent.infohash}&dn=${Uri.encodeComponent(torrent.name)}';
      final result = await TorboxService.createTorrent(
        apiKey: apiKey,
        magnet: magnet,
      );
      final data = result['data'];
      final rawTorrentId = data is Map
          ? (data['torrent_id'] ?? data['id'])
          : (result['torrent_id'] ?? result['id']);

      createdTorrentId = rawTorrentId is int
          ? rawTorrentId
          : int.tryParse(rawTorrentId?.toString() ?? '');
      if (createdTorrentId == null) return null;

      await Future.delayed(const Duration(seconds: 3));
      if (isCancelled?.call() ?? false) return null;

      final torrentInfo = await TorboxService.getTorrentById(
        apiKey,
        createdTorrentId,
      );

      if (torrentInfo == null || (isCancelled?.call() ?? false)) return null;

      final allFiles = torrentInfo.files;
      final videoFiles = allFiles
          .where((f) => FileUtils.isVideoFile(f.name))
          .toList();
      final files = videoFiles.isNotEmpty ? videoFiles : allFiles;
      if (files.isEmpty) return null;

      var targetFile = files.first;
      if (item.type.toLowerCase() == 'series' &&
          season != null &&
          episode != null) {
        if (files.length > 1) {
          final fallbackIndex = StremioEpisodeSelector.findLargestFileIndex(
            files.map((f) => f.size).toList(),
          );
          targetFile = files[fallbackIndex];
        }
        final candidateNames = files
            .map((f) => f.absolutePath ?? f.name)
            .toList();
        final targetIndex = StremioEpisodeSelector
            .findEpisodeFileIndexWithSingleFileFallback(
          candidateNames,
          sourceName: torrent.name,
          season: season,
          episode: episode,
        );
        if (targetIndex == null || targetIndex >= files.length) {
          debugPrint(
            'StremioTV: Torbox could not match S${season}E$episode in ${torrent.name}, '
            'rejecting source',
          );
          return null;
        } else {
          targetFile = files[targetIndex];
        }
      } else if (item.type.toLowerCase() == 'movie' && files.length > 1) {
        final targetIndex = StremioEpisodeSelector.findLargestFileIndex(
          files.map((f) => f.size).toList(),
        );
        targetFile = files[targetIndex];
      } else if (files.length > 1) {
        for (final f in files) {
          if (f.size > targetFile.size) {
            targetFile = f;
          }
        }
      }

      final streamUrl = await TorboxService.requestFileDownloadLink(
        apiKey: apiKey,
        torrentId: createdTorrentId,
        fileId: targetFile.id,
      );
      if (streamUrl.isEmpty || (isCancelled?.call() ?? false)) return null;

      keepTorrent = true;
      return streamUrl;
    } catch (e) {
      debugPrint('StremioTV: Torbox resolve error: $e');
      return null;
    } finally {
      if (createdTorrentId != null && !keepTorrent) {
        try {
          await TorboxTorrentControlService.deleteTorrent(
            apiKey: apiKey,
            torrentId: createdTorrentId,
          ).timeout(const Duration(seconds: 10));
        } catch (e) {
          debugPrint(
            'StremioTV: Failed to delete rejected TorBox torrent '
            '$createdTorrentId: $e',
          );
        }
      }
    }
  }

  Future<String?> _resolveViaPikPak(
    Torrent torrent,
    StremioMeta item, {
    int? season,
    int? episode,
    bool Function()? isCancelled,
  }) async {
    Map<String, dynamic>? preparedForCleanup;
    var keepPreparedItem = false;
    try {
      final prepared = await PikPakTvService.instance.prepareTorrent(
        infohash: torrent.infohash.trim().toLowerCase(),
        torrentName: torrent.name,
      );

      if (prepared == null) return null;
      preparedForCleanup = prepared;
      if (isCancelled?.call() ?? false) return null;

      String? streamUrl = prepared['url'] as String?;

      final allVideoFiles = prepared['allVideoFiles'] as List<dynamic>?;
      final isSeries = item.type.toLowerCase() == 'series';
      if (isSeries &&
          season != null &&
          episode != null &&
          (allVideoFiles == null || allVideoFiles.isEmpty)) {
        final directNames = <String>[
          if ((prepared['title'] as String?)?.trim().isNotEmpty == true)
            (prepared['title'] as String).trim(),
          torrent.name,
        ];
        final directMatch = StremioEpisodeSelector.namesContainEpisode(
          directNames,
          season: season,
          episode: episode,
        );
        if (!directMatch) {
          debugPrint(
            'StremioTV: PikPak single file could not verify '
            'S${season}E$episode in ${torrent.name}, rejecting source',
          );
          return null;
        }
      }
      if (allVideoFiles != null && allVideoFiles.isNotEmpty) {
        Map<String, dynamic>? targetFile;
        if (isSeries && season != null && episode != null) {
          final candidateNames = allVideoFiles.map((file) {
            if (file is! Map<String, dynamic>) return '';
            return (file['_fullPath'] as String?) ??
                (file['name'] as String?) ??
                '';
          }).toList();
          final targetIndex = StremioEpisodeSelector
              .findEpisodeFileIndexWithSingleFileFallback(
            candidateNames,
            sourceName: torrent.name,
            season: season,
            episode: episode,
          );
          if (targetIndex == null || targetIndex >= allVideoFiles.length) {
            debugPrint(
              'StremioTV: PikPak could not match S${season}E$episode in ${torrent.name}, '
              'rejecting source',
            );
            return null;
          } else {
            final file = allVideoFiles[targetIndex];
            if (file is Map<String, dynamic>) {
              targetFile = file;
            }
          }
        } else if (item.type.toLowerCase() == 'movie') {
          final targetIndex = StremioEpisodeSelector.findLargestFileIndex(
            allVideoFiles.map((file) {
              if (file is! Map<String, dynamic>) return null;
              return file['size'] as int?;
            }).toList(),
          );
          final file = allVideoFiles[targetIndex];
          if (file is Map<String, dynamic>) {
            targetFile = file;
          }
        }

        if (targetFile != null) {
          final targetFileId = targetFile['id'] as String?;
          if (targetFileId == null || targetFileId.isEmpty) return null;

          final api = PikPakApiService.instance;
          final fileData = await api.getFileDetails(targetFileId);
          final url = api.getStreamingUrl(fileData);
          if (url == null || url.isEmpty) return null;
          streamUrl = url;
        } else if (isSeries && season != null && episode != null) {
          return null;
        }
      }

      if (streamUrl == null ||
          streamUrl.isEmpty ||
          (isCancelled?.call() ?? false)) {
        return null;
      }

      keepPreparedItem = true;
      return streamUrl;
    } catch (e) {
      debugPrint('StremioTV: PikPak resolve error: $e');
      return null;
    } finally {
      if (preparedForCleanup != null && !keepPreparedItem) {
        await _trashRejectedPikPakItem(preparedForCleanup);
      }
    }
  }

  Future<void> _trashRejectedPikPakItem(
    Map<String, dynamic> prepared,
  ) async {
    final rootId = StremioTvDebridFallback.pikPakCleanupRootId(prepared);
    if (rootId == null) return;

    try {
      await PikPakApiService.instance
          .batchTrashFiles(<String>[rootId])
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      debugPrint(
        'StremioTV: Failed to trash rejected PikPak item $rootId: $e',
      );
    }
  }

  Future<String?> _resolveViaPremiumize(
    Torrent torrent,
    StremioMeta item,
    String apiKey, {
    int? season,
    int? episode,
  }) async {
    try {
      final magnet =
          'magnet:?xt=urn:btih:${torrent.infohash}&dn=${Uri.encodeComponent(torrent.name)}';
      final files = await PremiumizeService.directDownload(apiKey, magnet);

      if (files.isEmpty) return null;

      final videoFiles = files
          .where((f) => FileUtils.isVideoFile(f.fileName))
          .toList();
      final candidates = videoFiles.isNotEmpty ? videoFiles : files;

      PremiumizeFile? targetFile;
      final isSeries = item.type.toLowerCase() == 'series';
      if (isSeries && season != null && episode != null) {
        final candidateNames = candidates.map((f) => f.path).toList();
        final targetIndex = StremioEpisodeSelector
            .findEpisodeFileIndexWithSingleFileFallback(
          candidateNames,
          sourceName: torrent.name,
          season: season,
          episode: episode,
        );
        if (targetIndex != null && targetIndex < candidates.length) {
          targetFile = candidates[targetIndex];
        } else {
          debugPrint(
            'StremioTV: Premiumize could not match S${season}E$episode in '
            '${torrent.name}, rejecting source',
          );
          return null;
        }
      }
      targetFile ??= candidates.length > 1
          ? candidates.reduce((a, b) => a.size >= b.size ? a : b)
          : candidates.first;

      return targetFile.streamLink ?? targetFile.link;
    } catch (e) {
      debugPrint('StremioTV: Premiumize resolve error: $e');
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
  // Channel Detail (cinematic "tune-in")
  // ============================================================================

  bool _pushingChannelDetail = false;

  /// Tune in: opens the reused [CatalogItemDetailScreen] for the channel's
  /// now-playing item with a fast zoom/fade so selecting a channel feels
  /// like committing to it rather than a stock page push.
  Future<void> _openChannelDetail(StremioTvChannel channel) async {
    if (_pushingChannelDetail) return;
    _pushingChannelDetail = true;
    try {
      await _pushChannelDetail(channel);
    } finally {
      _pushingChannelDetail = false;
    }
  }

  Future<void> _pushChannelDetail(StremioTvChannel channel) async {
    if (!channel.hasItems) {
      await _ensureChannelItemsLoaded(channel);
      // _ensureChannelItemsLoaded early-returns when a load is already in
      // flight (the Tuner kicks one off on focus), so the await above may
      // not have actually waited. Poll the in-flight load to settle before
      // deciding there's nothing to show — otherwise "View details" on a
      // still-tuning channel wrongly reports "No items available".
      var waitedMs = 0;
      while (mounted &&
          !channel.hasItems &&
          _loadingChannelIds.contains(channel.id) &&
          waitedMs < 8000) {
        await Future.delayed(const Duration(milliseconds: 120));
        waitedMs += 120;
      }
      if (!mounted) return;
    }
    final nowPlaying = _service.getNowPlaying(
      channel,
      rotationMinutes: _rotationFor(channel),
      salt: _mixSalt,
    );
    if (nowPlaying == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No items available for this channel'),
          ),
        );
      }
      return;
    }
    final screen = CatalogItemDetailScreen(
      item: nowPlaying.item,
      isTelevision: widget.isTelevision,
      onPlay: () => _playChannel(channel),
      onBrowse: () => _playChannel(channel),
      enablePrimarySourcesHold: false,
    );
    await Navigator.of(context).push(
      PageRouteBuilder(
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (_, __, ___) => screen,
      ),
    );
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

  Future<void> _editLocalCatalog(StremioTvChannel channel) async {
    final previousFocusedIndex = _focusedIndex;
    final previousFocusedChannelId = _currentFocusedChannelId();
    final previousFilteredIndex = previousFocusedChannelId == null
        ? -1
        : _filteredChannels.indexWhere(
            (ch) => ch.id == previousFocusedChannelId,
          );
    final changed = await StremioTvLocalCatalogEditorDialog.show(
      context,
      catalogId: channel.catalog.id,
      catalogType: channel.type,
    );
    if (changed != true || !mounted) return;

    await _refresh();
    if (!mounted) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      void focusChannelById(String channelId) {
        final channelIndex = _channels.indexWhere((ch) => ch.id == channelId);
        if (channelIndex >= 0 && channelIndex < _rowFocusNodes.length) {
          _rowFocusNodes[channelIndex].requestFocus();
          setState(() => _focusedIndex = channelIndex);
        }
      }

      final visibleChannels = _filteredChannels;
      final visibleEditedChannel = visibleChannels.firstWhereOrNull(
        (ch) => ch.id == channel.id,
      );
      if (visibleEditedChannel != null) {
        focusChannelById(visibleEditedChannel.id);
        return;
      }

      final visiblePreviousChannel = previousFocusedChannelId == null
          ? null
          : visibleChannels.firstWhereOrNull(
              (ch) => ch.id == previousFocusedChannelId,
            );
      if (visiblePreviousChannel != null) {
        focusChannelById(visiblePreviousChannel.id);
        return;
      }

      if (visibleChannels.isNotEmpty) {
        final fallbackVisibleIndex = previousFilteredIndex >= 0
            ? previousFilteredIndex.clamp(0, visibleChannels.length - 1)
            : previousFocusedIndex.clamp(0, visibleChannels.length - 1);
        focusChannelById(visibleChannels[fallbackVisibleIndex].id);
        return;
      }

      _searchBtnFocusNode.requestFocus();
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

  /// Returns focus from the header back into the Dial. Targets the card the
  /// user last had focused (so it works after surfing right) rather than
  /// always the first channel — whose card is scrolled off-screen and
  /// focus-detached, which is why down-arrow silently did nothing.
  void _focusDialFromHeader() {
    if (_rowFocusNodes.isEmpty) return;
    final filtered = _filteredChannels;
    if (filtered.isEmpty) return;
    // Preferred target: the last-focused channel if it's still displayed;
    // otherwise the first visible channel.
    int targetIdx = -1;
    if (_focusedIndex >= 0 &&
        _focusedIndex < _rowFocusNodes.length &&
        _focusedIndex < _channels.length &&
        filtered.contains(_channels[_focusedIndex])) {
      targetIdx = _focusedIndex;
    } else {
      targetIdx = _channels.indexOf(filtered.first);
    }
    if (targetIdx < 0 || targetIdx >= _rowFocusNodes.length) return;
    // Route through the tuner so an off-screen (recycled) dial card is scrolled
    // into view *before* focusing — a bare requestFocus on an unmounted
    // ListView child silently no-ops, which is why down-arrow from the header
    // could fail to return focus to the channels after a long surf.
    if (_tunerController.focusRealIndex(targetIdx)) return;
    // Fallback (narrow layout / tuner not mounted): best-effort direct focus.
    _rowFocusNodes[targetIdx].requestFocus();
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

  /// Back/Escape ladder for the search bar: clear text first, then hide the
  /// field. Sits on an ancestor Focus of the search field so it runs when the
  /// TvTextField shell lets the key bubble.
  KeyEventResult _handleSearchBarBack(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.escape ||
        event.logicalKey == LogicalKeyboardKey.goBack) {
      if (_searchController.text.isNotEmpty) {
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
    final app = AppThemeScope.of(context);

    return Scaffold(
      // Match the Home board: sit the whole screen on the same cinematic
      // indigo→near-black wash instead of a flat black, so the tuner reads as
      // part of the same app rather than a separate dark surface.
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: BoxDecoration(gradient: app.home.wash),
        child: _loading
          ? _buildLoadingSkeleton()
          : Column(
              children: [
                // Premium header bar
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        app.home.bg,
                        app.home.bg.withValues(alpha: 0.0),
                      ],
                    ),
                  ),
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
                                child: Focus(
                                  canRequestFocus: false,
                                  skipTraversal: true,
                                  onKeyEvent: _handleSearchBarBack,
                                  child: TvTextField(
                                  controller: _searchController,
                                  focusNode: _searchFocusNode,
                                  style: TextStyle(color: app.core.tx),
                                  accent: app.youtube.focus,
                                  keyboardGround: app.youtube.keyboardPanel,
                                  keyboardInk: app.core.tx,
                                  keyboardInkOnAccent:
                                      app.inkOn(app.youtube.focus),
                                  onSubmitted: (_) =>
                                      _searchBtnFocusNode.requestFocus(),
                                  onDownArrow: () =>
                                      _searchBtnFocusNode.requestFocus(),
                                  onUpArrow: () {
                                    // Search bar is at the top — nothing above
                                  },
                                  onLeftArrow: () =>
                                      MainPageBridge.focusTvSidebar?.call(),
                                  onRightArrow: () {
                                    // Nothing to the right — consume
                                  },
                                  decoration: InputDecoration(
                                    hintText: 'Search channels...',
                                    hintStyle: TextStyle(
                                      color: app.core.tx.withValues(
                                        alpha: 0.3,
                                      ),
                                    ),
                                    prefixIcon: Icon(
                                      Icons.search_rounded,
                                      color: app.core.tx.withValues(
                                        alpha: 0.35,
                                      ),
                                    ),
                                    suffixIcon: _searchQuery.isNotEmpty
                                        ? IconButton(
                                            icon: Icon(
                                              Icons.close_rounded,
                                              color: app.core.tx.withValues(
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
                                      borderRadius: app.shape.br(14),
                                      borderSide: BorderSide.none,
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: app.shape.br(14),
                                      borderSide: BorderSide.none,
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: app.shape.br(14),
                                      borderSide: BorderSide(
                                        color: app.core.tx.withValues(
                                          alpha: 0.15,
                                        ),
                                        width: 1,
                                      ),
                                    ),
                                    filled: true,
                                    fillColor: app.core.tx.withValues(
                                      alpha: 0.07,
                                    ),
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 14,
                                    ),
                                  ),
                                  textInputAction: TextInputAction.search,
                                  ),
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Search toggle button
                          Focus(
                            focusNode: _searchBtnFocusNode,
                            onKeyEvent: (node, event) {
                              if (event is! KeyDownEvent) {
                                return KeyEventResult.ignored;
                              }
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
                                _focusDialFromHeader();
                                return KeyEventResult.handled;
                              }
                              if (isActivateKey(event.logicalKey)) {
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
                                builder: (context, _) => _headerButton(
                                  focused: _searchBtnFocusNode.hasFocus,
                                  active: _showSearchField || _searchQuery.isNotEmpty,
                                  child: Icon(
                                    Icons.search_rounded,
                                    size: 20,
                                    color: (_searchBtnFocusNode.hasFocus ||
                                            _showSearchField ||
                                            _searchQuery.isNotEmpty)
                                        ? app.core.tx
                                        : app.core.tx.withValues(alpha: 0.5),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          // Options button
                          Focus(
                            focusNode: _menuFocusNode,
                            onKeyEvent: (node, event) {
                              if (event is! KeyDownEvent) {
                                return KeyEventResult.ignored;
                              }
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
                                if (_availableProviders.isNotEmpty) {
                                  _providerFocusNode.requestFocus();
                                }
                                return KeyEventResult.handled;
                              }
                              if (event.logicalKey ==
                                  LogicalKeyboardKey.arrowLeft) {
                                _searchBtnFocusNode.requestFocus();
                                return KeyEventResult.handled;
                              }
                              if (event.logicalKey ==
                                  LogicalKeyboardKey.arrowDown) {
                                _focusDialFromHeader();
                                return KeyEventResult.handled;
                              }
                              if (isActivateKey(event.logicalKey)) {
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
                                  _topMenuItem(
                                    autofocus: true,
                                    leadingIcon: const Icon(
                                      Icons.shuffle_rounded,
                                    ),
                                    controller: _menuController,
                                    anchorFocusNode: _menuFocusNode,
                                    closeOnArrowUp: true,
                                    onPressed: () {
                                      setState(
                                        () => _mixSalt = (_mixSalt + 1) % 10,
                                      );
                                    },
                                    label: 'Shuffle (Mix ${_mixSalt + 1})',
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
                                  MenuItemButton(
                                    leadingIcon: const Icon(
                                      Icons.settings_rounded,
                                    ),
                                    onPressed: _openStremioTvSettings,
                                    child: const Text('Stremio TV Settings'),
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
                                      // Hidden for the alpha (kMdblistEnabled)
                                      // and only when connected — no dead import.
                                      if (kMdblistEnabled && _mdblistConnected)
                                        _submenuItem(
                                          icon: Icons
                                              .playlist_add_check_circle_outlined,
                                          label: 'From MDBList',
                                          onPressed: _importFromMdblist,
                                        ),
                                    ],
                                    child: const Text('Import'),
                                  ),
                                ],
                                builder: (context, controller, child) =>
                                    _headerButton(
                                      focused: _menuFocusNode.hasFocus,
                                      child: Icon(
                                        Icons.more_vert_rounded,
                                        size: 20,
                                        color: _menuFocusNode.hasFocus
                                            ? app.core.tx
                                            : app.core.tx.withValues(
                                                alpha: 0.5,
                                              ),
                                      ),
                                      onTap: () {
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
                          if (_availableProviders.isNotEmpty) ...[
                            const SizedBox(width: 10),
                            // Provider selector
                            Focus(
                              focusNode: _providerFocusNode,
                              onKeyEvent: (node, event) {
                                if (event is! KeyDownEvent) {
                                  return KeyEventResult.ignored;
                                }
                                if (_providerMenuController.isOpen) {
                                  if (event.logicalKey ==
                                          LogicalKeyboardKey.escape ||
                                      event.logicalKey ==
                                          LogicalKeyboardKey.goBack) {
                                    _providerMenuController.close();
                                    _providerFocusNode.requestFocus();
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
                                    LogicalKeyboardKey.arrowLeft) {
                                  _menuFocusNode.requestFocus();
                                  return KeyEventResult.handled;
                                }
                                if (event.logicalKey ==
                                    LogicalKeyboardKey.arrowRight) {
                                  return KeyEventResult.handled;
                                }
                                if (event.logicalKey ==
                                    LogicalKeyboardKey.arrowDown) {
                                  _focusDialFromHeader();
                                  return KeyEventResult.handled;
                                }
                                if (isActivateKey(event.logicalKey)) {
                                  _providerMenuController.open();
                                  return KeyEventResult.handled;
                                }
                                return KeyEventResult.ignored;
                              },
                              child: ListenableBuilder(
                                listenable: _providerFocusNode,
                                builder: (context, child) => MenuAnchor(
                                  controller: _providerMenuController,
                                  menuChildren: [
                                    _topMenuItem(
                                      autofocus: true,
                                      leadingIcon: Icon(
                                        _debridProvider == 'auto'
                                            ? Icons.check_rounded
                                            : Icons.circle_outlined,
                                      ),
                                      label: _providerFullLabel('auto'),
                                      onPressed: () =>
                                          _setDebridProvider('auto'),
                                      controller: _providerMenuController,
                                      anchorFocusNode: _providerFocusNode,
                                      closeOnArrowUp: true,
                                    ),
                                    ..._availableProviders.map(
                                      (provider) => MenuItemButton(
                                        leadingIcon: Icon(
                                          _debridProvider == provider.key
                                              ? Icons.check_rounded
                                              : Icons.circle_outlined,
                                        ),
                                        onPressed: () =>
                                            _setDebridProvider(provider.key),
                                        child: Text(provider.value),
                                      ),
                                    ),
                                  ],
                                  builder: (context, controller, child) =>
                                      GestureDetector(
                                        onTap: () {
                                          if (controller.isOpen) {
                                            controller.close();
                                          } else {
                                            controller.open();
                                          }
                                        },
                                        child: _headerButton(
                                          focused: _providerFocusNode.hasFocus,
                                          wide: true,
                                          child: Text(
                                            _providerShortLabel(
                                              _debridProvider,
                                            ),
                                            style: TextStyle(
                                              color: _providerFocusNode.hasFocus
                                                  ? app.core.tx
                                                  : app.core.tx.withValues(
                                                      alpha: 0.68,
                                                    ),
                                              fontSize: 13,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        ),
                                      ),
                                ),
                              ),
                            ),
                          ],
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
                      return ValueListenableBuilder<int>(
                        valueListenable: _contentRevision,
                        builder: (context, _, __) {
                          // Computed inside the builder so a revision bump
                          // hands the tuner a fresh snapshot consistent with
                          // the live _channels/_rowFocusNodes it also gets.
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
                          return StremioTvTuner(
                            controller: _tunerController,
                            channels: filtered,
                            allChannels: _channels,
                            rowFocusNodes: _rowFocusNodes,
                            service: _service,
                            rotationFor: _rotationFor,
                            mixSalt: _mixSalt,
                            hideNowPlaying: _hideNowPlaying,
                            autoRefresh: _autoRefresh,
                            isTelevision: widget.isTelevision,
                            loadingChannelIds: _loadingChannelIds,
                            ensureLoaded: (channel) {
                              if (!channel.hasItems &&
                                  !_loadingChannelIds.contains(channel.id)) {
                                _ensureChannelItemsLoaded(channel);
                              }
                            },
                            onOpenDetail: _openChannelDetail,
                            onPlay: _playChannel,
                            // Restore the "max start %" cap on the *displayed*
                            // progress so the bar matches where playback will
                            // actually join (matches the old row's
                            // displayProgress semantics exactly).
                            displayProgress: (channel, rawProgress) {
                              if (_maxStartPercent == 0) return 0.0;
                              return _computeStartProgress(
                                    channel.id,
                                    rawProgress,
                                  ) ??
                                  rawProgress;
                            },
                            onToggleFavorite: _toggleFavorite,
                            onShowGuide: _showGuide,
                            onEditLocal: _editLocalCatalog,
                            onExportLocal: _copyLocalCatalogJson,
                            onFocusSidebar: () =>
                                MainPageBridge.focusTvSidebar?.call(),
                            onFocusHeader: () =>
                                _searchBtnFocusNode.requestFocus(),
                            onFocusedIndexChanged: (realIndex) {
                              // Bookkeeping only — never read in build(), so
                              // no setState (keeps surfing lag-free) and it
                              // stays current for header↕ navigation even
                              // mid-surf.
                              _focusedIndex = realIndex;
                            },
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
      ),
    );
  }

  Widget _headerButton({
    required bool focused,
    required Widget child,
    bool active = false,
    bool wide = false,
    VoidCallback? onTap,
  }) {
    final app = AppThemeScope.of(context);
    final btn = Container(
      height: 40,
      constraints: wide ? const BoxConstraints(minWidth: 48) : null,
      width: wide ? null : 40,
      padding: wide ? const EdgeInsets.symmetric(horizontal: 12) : null,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        // Home chrome language (matches the Catalog/Keyword mode toggle): an
        // active control fills with the purple accent; focus is a white ring
        // that shows even on the active one, since DPAD focus lands there first
        // and the fill alone wouldn't signal the remote moved.
        color: active
            ? app.home.chromeAccent
            : app.stremioTv.surfaceFill,
        borderRadius: app.shape.br(12),
        border: Border.all(
          color: focused
              ? app.stremioTv.focusRing
              : app.stremioTv.hairline,
          width: focused ? 2 : 0.5,
        ),
      ),
      child: child,
    );
    if (onTap != null) return GestureDetector(onTap: onTap, child: btn);
    return btn;
  }

  Widget _buildLoadingSkeleton() {
    final app = AppThemeScope.of(context);
    return Column(
      children: [
        const SizedBox(height: 52),
        // Skeleton stage area
        Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 32),
            decoration: BoxDecoration(
              color: app.core.tx.withValues(alpha: 0.03),
              borderRadius: app.shape.br(20),
            ),
            child: Stack(
              children: [
                Positioned(
                  left: 48,
                  bottom: 60,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 80,
                        height: 28,
                        decoration: BoxDecoration(
                          color: app.core.tx.withValues(alpha: 0.06),
                          borderRadius: app.shape.br(10),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        width: 320,
                        height: 36,
                        decoration: BoxDecoration(
                          color: app.stremioTv.surfaceFill,
                          borderRadius: app.shape.br(8),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        width: 200,
                        height: 16,
                        decoration: BoxDecoration(
                          color: app.core.tx.withValues(alpha: 0.03),
                          borderRadius: app.shape.br(6),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        // Skeleton dial cards
        SizedBox(
          height: 220,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 32),
            itemCount: 6,
            itemBuilder: (context, i) {
              return Container(
                width: 138,
                margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                decoration: BoxDecoration(
                  color: app.stremioTv.surfaceFill,
                  borderRadius: app.shape.br(16),
                  border: Border.all(
                    color: app.core.tx.withValues(alpha: 0.04),
                    width: 0.5,
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 14),
      ],
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
    return sourceQualityBadgeForName(name) ?? 'HD';
  }

  Color _qualityColor(String quality) {
    // Ordered most-capable-first, indexed by tier — the list's ORDER is the
    // contract, so this switch maps position, not hue.
    final tiers = AppThemeScope.of(context).stremioTv.qualityTier;
    switch (quality) {
      case '4K':
        return tiers[0];
      case '1080p':
        return tiers[1];
      case '720p':
        return tiers[2];
      case '480p':
        return tiers[3];
      default:
        return tiers[4];
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
        Navigator.of(
          context,
        ).pop(_ResolvedSourceChoice(url: url, sourceIndex: originalIndex));
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
    final app = AppThemeScope.of(context);
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
              color: app.core.tx.withAlpha(0x3D),
              borderRadius: app.shape.br(2),
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
                Expanded(
                  child: Text(
                    'Auto-play failed — select a source',
                    style: TextStyle(
                      color: app.core.tx,
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
          Divider(color: app.core.tx.withAlpha(0x1F), height: 1),
          // Source list
          Flexible(
            child: filtered.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        'No sources in this category',
                        style: TextStyle(
                            color: app.core.tx.withAlpha(0x62), fontSize: 14),
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
    if (isActivateKey(event.logicalKey)) {
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
    final app = AppThemeScope.of(context);
    return Focus(
      focusNode: widget.focusNode,
      onFocusChange: (f) => setState(() => _focused = f),
      onKeyEvent: _handleKey,
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            // Active = purple fill, focus = white ring (Home mode-toggle
            // pattern); the ring shows even on the active pill.
            color: widget.isActive
                ? app.home.chromeAccent
                : Colors.transparent,
            borderRadius: app.shape.br(20),
            border: Border.all(
              color: _focused
                  ? app.stremioTv.focusRing
                  : widget.isActive
                      ? Colors.transparent
                      : app.core.tx.withAlpha(0x1F),
              width: _focused ? 2 : 1,
            ),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              color: widget.isActive
                  ? app.inkOn(app.home.chromeAccent)
                  : app.core.tx.withAlpha(0x8A),
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
    if (isActivateKey(event.logicalKey)) {
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
    final app = AppThemeScope.of(context);
    final qColor = widget.qualityColor;
    return Focus(
      focusNode: _focusNode,
      onFocusChange: (f) => setState(() => _focused = f),
      onKeyEvent: _handleKey,
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: _focused
                ? app.home.chromeAccent.withValues(alpha: 0.15)
                : Colors.transparent,
            borderRadius: app.shape.br(10),
            border: Border.all(
              // Chrome focus ring (width 2), matching the reskinned toggles /
              // header buttons so every DPAD-focusable control reads the same.
              color: _focused ? app.stremioTv.focusRing : Colors.transparent,
              width: 2,
            ),
          ),
          child: Row(
            children: [
              // Quality badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: qColor.withValues(alpha: 0.15),
                  borderRadius: app.shape.br(6),
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
                        color: _focused
                            ? app.core.tx
                            : app.core.tx.withAlpha(0xB3),
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      widget.meta,
                      style: TextStyle(
                        color: app.core.tx.withAlpha(0x62),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              // Loading, failed, or play icon
              if (widget.isResolving)
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: app.home.chromeAccent,
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
                  color: _focused
                      ? app.core.tx.withAlpha(0x8A)
                      : app.core.tx.withAlpha(0x3D),
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
  final int? contentSeason;
  final int? contentEpisode;
  final double? startAtPercent;
  final List<Torrent> playableSources;
  final int sourceIndex;
  final Future<String?> Function(Torrent) sourceResolver;
  final Map<String, dynamic> nowPlayingGuideData;
  final Map<String, dynamic>? nextUpGuideData;
  final int baseSlotStartMs;
  final int slotOffset;

  const _ChannelPlaybackResult({
    required this.url,
    required this.title,
    required this.contentType,
    this.contentImdbId,
    this.contentSeason,
    this.contentEpisode,
    this.startAtPercent,
    required this.playableSources,
    required this.sourceIndex,
    required this.sourceResolver,
    required this.nowPlayingGuideData,
    this.nextUpGuideData,
    required this.baseSlotStartMs,
    required this.slotOffset,
  });
}

class _ResolvedSourceChoice {
  final String url;
  final int sourceIndex;

  const _ResolvedSourceChoice({required this.url, required this.sourceIndex});
}

class _StremioTvPlaybackCursor {
  final int baseSlotStartMs;
  final int slotOffset;

  const _StremioTvPlaybackCursor({
    required this.baseSlotStartMs,
    required this.slotOffset,
  });
}
