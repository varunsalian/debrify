import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:developer' show Timeline, Flow;
import 'package:flutter/services.dart';
import '../models/playlist_view_mode.dart';
import '../models/torrent.dart';
import '../models/advanced_search_selection.dart';
import '../models/torrent_filter_state.dart';
import '../services/torrent_service.dart';
import '../services/debrid_service.dart';
import '../services/storage_service.dart';
import '../services/engine/settings_manager.dart';
import '../services/engine/dynamic_engine.dart';
import '../services/download_service.dart';
import '../services/pikpak_api_service.dart';
import '../services/video_player_launcher.dart';
import '../services/android_native_downloader.dart';
import '../utils/formatters.dart';
import '../utils/file_utils.dart';
import '../utils/series_parser.dart';
import '../utils/rd_folder_tree_builder.dart';
import '../widgets/stat_chip.dart';
import '../widgets/file_selection_dialog.dart';
import 'video_player_screen.dart';
import '../models/rd_torrent.dart';
import '../services/main_page_bridge.dart';
import '../services/torbox_service.dart';
import '../models/torbox_torrent.dart';
import '../models/torbox_file.dart';
import '../screens/torbox/torbox_downloads_screen.dart';
import '../widgets/shimmer.dart';
import '../widgets/channel_picker_dialog.dart';
import '../services/debrify_tv_repository.dart';
import '../services/debrify_tv_cache_service.dart';
import '../models/debrify_tv_cache.dart';
import '../widgets/advanced_search_sheet.dart';
import '../widgets/torrent_filters_sheet.dart';
import '../services/imdb_lookup_service.dart';
import 'dart:async';

// Search mode for torrent search
enum SearchMode { keyword, imdb }

class TorrentSearchScreen extends StatefulWidget {
  const TorrentSearchScreen({super.key});

  @override
  State<TorrentSearchScreen> createState() => _TorrentSearchScreenState();
}

/// Preserves search state when navigating away (e.g., to view torrent in debrid tab)
/// This allows seamless return to the search screen with results intact
class _TorrentSearchPreservedState {
  String? searchQuery;
  SearchMode? searchMode;
  ImdbTitleResult? selectedImdbTitle;
  bool? isSeries;
  List<Torrent>? allTorrents;
  List<Torrent>? torrents;
  bool? hasSearched;
  Map<String, bool>? engineStates;
  Map<String, int>? engineCounts;
  Map<String, String>? engineErrors;
  String? selectedEngineFilter;
  String? sortBy;
  bool? sortAscending;
  TorrentFilterState? filters;
  String? seasonText;
  String? episodeText;
  List<int>? availableSeasons;
  int? selectedSeason;
  bool? seriesControlsExpanded;
  bool? imdbControlsCollapsed;
  Map<String, bool>? torboxCacheStatus;
  Map<String, _TorrentMetadata>? torrentMetadata;
  bool? showingTorboxCachedOnly;
  double? scrollOffset;

  bool get hasState => hasSearched == true && (allTorrents?.isNotEmpty ?? false);

  void clear() {
    searchQuery = null;
    searchMode = null;
    selectedImdbTitle = null;
    isSeries = null;
    allTorrents = null;
    torrents = null;
    hasSearched = null;
    engineStates = null;
    engineCounts = null;
    engineErrors = null;
    selectedEngineFilter = null;
    sortBy = null;
    sortAscending = null;
    filters = null;
    seasonText = null;
    episodeText = null;
    availableSeasons = null;
    selectedSeason = null;
    seriesControlsExpanded = null;
    imdbControlsCollapsed = null;
    torboxCacheStatus = null;
    torrentMetadata = null;
    showingTorboxCachedOnly = null;
    scrollOffset = null;
  }
}

/// Static preserved state instance
final _preservedState = _TorrentSearchPreservedState();

class _TorrentSearchScreenState extends State<TorrentSearchScreen>
    with TickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _resultsScrollController = ScrollController();
  final FocusNode _searchFocusNode = FocusNode();
  final FocusNode _providerAccordionFocusNode = FocusNode();
  final FocusNode _advancedButtonFocusNode = FocusNode();
  final FocusNode _sortDropdownFocusNode = FocusNode();
  final FocusNode _sortDirectionFocusNode = FocusNode();
  final FocusNode _filterButtonFocusNode = FocusNode();
  final FocusNode _clearFiltersButtonFocusNode = FocusNode();

  // IMDB Smart Search Mode focus nodes
  final FocusNode _modeSelectorFocusNode = FocusNode();
  final FocusNode _selectionChipFocusNode = FocusNode();
  final FocusNode _expandControlsFocusNode = FocusNode();
  final FocusNode _seasonInputFocusNode = FocusNode();
  final FocusNode _episodeInputFocusNode = FocusNode();
  List<FocusNode> _autocompleteFocusNodes = [];

  // Focus states using ValueNotifier to avoid full screen rebuilds
  final ValueNotifier<bool> _searchFocused = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _providerAccordionFocused = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _advancedButtonFocused = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _sortDropdownFocused = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _sortDirectionFocused = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _filterButtonFocused = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _clearFiltersButtonFocused = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _modeSelectorFocused = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _selectionChipFocused = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _expandControlsFocused = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _seasonInputFocused = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _episodeInputFocused = ValueNotifier<bool>(false);

  List<Torrent> _torrents = [];
  List<Torrent> _allTorrents = [];
  Map<String, int> _engineCounts = {};
  Map<String, String> _engineErrors = {};
  Map<String, _TorrentMetadata> _torrentMetadata = {};
  String? _selectedEngineFilter; // null means show all
  bool _isLoading = false;
  String _errorMessage = '';
  bool _hasSearched = false;
  int _activeSearchRequestId = 0;
  String? _apiKey;
  String? _torboxApiKey;
  bool _torboxCacheCheckEnabled = false;
  Map<String, bool>? _torboxCacheStatus;
  bool _realDebridIntegrationEnabled = true;
  bool _torboxIntegrationEnabled = true;
  bool _pikpakEnabled = false;
  bool _showingTorboxCachedOnly = false;
  bool _isTelevision = false;
  bool _isBulkAdding = false;
  double? _pendingScrollOffset; // Scroll offset to restore after list is built
  double _lastKnownScrollOffset = 0.0; // Track scroll position continuously
  final List<FocusNode> _cardFocusNodes = [];
  int _focusedCardIndex = -1; // -1 means no card is focused

  // Search engine toggles - dynamic engine states
  Map<String, bool> _engineStates = {};
  List<DynamicEngine> _availableEngines = [];
  final SettingsManager _settingsManager = SettingsManager();
  // Dynamic focus nodes for engine toggles
  final Map<String, FocusNode> _engineTileFocusNodes = {};
  final Map<String, bool> _engineTileFocusStates = {}; // Track focus as simple bools
  bool _showProvidersPanel = false;
  AdvancedSearchSelection? _activeAdvancedSelection;

  // IMDB Smart Search Mode state
  SearchMode _searchMode = SearchMode.keyword;
  List<ImdbTitleResult> _imdbAutocompleteResults = [];
  bool _isImdbSearching = false;
  String? _imdbSearchError;
  ImdbTitleResult? _selectedImdbTitle;
  bool _isSeries = false;
  bool _imdbControlsCollapsed = false;
  bool _seriesControlsExpanded = false; // Whether to show Movie/Series chips and S/E inputs
  Timer? _imdbSearchDebouncer;
  int _imdbRequestId = 0; // Track request IDs to prevent race conditions
  final TextEditingController _seasonController = TextEditingController();
  final TextEditingController _episodeController = TextEditingController();

  // Season dropdown state (for simplified season selector)
  List<int>? _availableSeasons; // List of season numbers from IMDbbot API, null for movies
  int? _selectedSeason; // null means "All Seasons" selected

  // Sorting options
  String _sortBy = 'relevance'; // relevance, name, size, seeders, date
  bool _sortAscending = false;
  TorrentFilterState _filters = const TorrentFilterState.empty();
  bool get _hasActiveFilters => !_filters.isEmpty;

  // Torrent Search History
  List<Map<String, dynamic>> _searchHistory = [];
  bool _historyTrackingEnabled = true;
  final FocusNode _historyDisableSwitchFocusNode = FocusNode();
  final FocusNode _historyClearButtonFocusNode = FocusNode();
  final ValueNotifier<bool> _historyDisableSwitchFocused = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _historyClearButtonFocused = ValueNotifier<bool>(false);
  final List<FocusNode> _historyCardFocusNodes = [];

  late AnimationController _listAnimationController;
  late Animation<double> _listAnimation;

  static const Map<ShortcutActivator, Intent> _activateShortcuts =
      <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
      };

  @override
  void initState() {
    super.initState();

    // Expose post-torrent action handler via bridge for deep links
    MainPageBridge.handleRealDebridResult = (result, torrentName, apiKey) async {
      if (!mounted) return;
      await _handlePostTorrentAction(result, torrentName, apiKey, -1);
    };

    // Expose Torbox post-action handler via bridge for deep links
    MainPageBridge.handleTorboxResult = (torboxTorrent) async {
      if (!mounted) return;
      // For deep link calls, we need to find the original torrent by hash
      final torrent = _findTorrentByInfohash(torboxTorrent.hash, torboxTorrent.name);
      await _showTorboxPostAddOptions(torboxTorrent, torrent);
    };

    // Expose PikPak post-action handler via bridge for deep links
    MainPageBridge.handlePikPakResult = (fileId, fileName) async {
      if (!mounted) return;
      await _showPikPakPostAddOptionsFromExternal(fileId, fileName);
    };

    _listAnimationController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _listAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _listAnimationController,
        curve: Curves.easeInOut,
      ),
    );

    // Focus listeners removed - now using onFocusChange callbacks directly in widgets
    // Exception: DropdownButton doesn't have onFocusChange, so we use a listener
    _sortDropdownFocusNode.addListener(_onSortDropdownFocusChange);

    // Track scroll position continuously so we can preserve it on dispose
    _resultsScrollController.addListener(_onScrollChanged);

    _listAnimationController.forward();
    _loadDefaultSettings();
    _detectTelevision();
    MainPageBridge.addIntegrationListener(_handleIntegrationChanged);
    _loadApiKeys();
    _loadSearchHistory();
    StorageService.getTorboxCacheCheckEnabled().then((enabled) {
      if (!mounted) return;
      setState(() {
        _torboxCacheCheckEnabled = enabled;
      });
    });

    // Restore preserved state if available (returning from debrid folder view)
    _restorePreservedState();
  }

  /// Restores search state if navigating back from debrid folder view
  void _restorePreservedState() {
    if (!_preservedState.hasState) return;

    // Restore all preserved state
    _searchController.text = _preservedState.searchQuery ?? '';
    _searchMode = _preservedState.searchMode ?? SearchMode.keyword;
    _selectedImdbTitle = _preservedState.selectedImdbTitle;
    _isSeries = _preservedState.isSeries ?? false;
    _allTorrents = _preservedState.allTorrents ?? [];
    _torrents = _preservedState.torrents ?? [];
    _hasSearched = _preservedState.hasSearched ?? false;
    _engineStates = _preservedState.engineStates ?? {};
    _engineCounts = _preservedState.engineCounts ?? {};
    _engineErrors = _preservedState.engineErrors ?? {};
    _selectedEngineFilter = _preservedState.selectedEngineFilter;
    _sortBy = _preservedState.sortBy ?? 'relevance';
    _sortAscending = _preservedState.sortAscending ?? false;
    _filters = _preservedState.filters ?? const TorrentFilterState.empty();
    _seasonController.text = _preservedState.seasonText ?? '';
    _episodeController.text = _preservedState.episodeText ?? '';
    _availableSeasons = _preservedState.availableSeasons;
    _selectedSeason = _preservedState.selectedSeason;
    _seriesControlsExpanded = _preservedState.seriesControlsExpanded ?? false;
    _imdbControlsCollapsed = _preservedState.imdbControlsCollapsed ?? false;
    _torboxCacheStatus = _preservedState.torboxCacheStatus;
    _torrentMetadata = _preservedState.torrentMetadata ?? {};
    _showingTorboxCachedOnly = _preservedState.showingTorboxCachedOnly ?? false;

    // Ensure focus nodes are created for restored torrents
    _ensureFocusNodes();

    // Store scroll offset to restore after build completes
    _pendingScrollOffset = _preservedState.scrollOffset;

    // Clear preserved state after restoration (one-time use)
    _preservedState.clear();
  }

  Future<void> _detectTelevision() async {
    final isTv = await AndroidNativeDownloader.isTelevision();
    if (mounted) {
      setState(() {
        _isTelevision = isTv;
      });
    }
  }

  void _onSortDropdownFocusChange() {
    _sortDropdownFocused.value = _sortDropdownFocusNode.hasFocus;
    if (_sortDropdownFocusNode.hasFocus && _isTelevision) {
      _scrollToFocusNode(_sortDropdownFocusNode);
    }
  }

  void _onScrollChanged() {
    if (_resultsScrollController.hasClients) {
      _lastKnownScrollOffset = _resultsScrollController.offset;
    }
  }

  /// Scrolls to make the focused widget visible on TV
  void _scrollToFocusNode(FocusNode node) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final context = node.context;
      if (context != null) {
        Scrollable.ensureVisible(
          context,
          alignment: 0.3,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  void _ensureFocusNodes() {
    // Dispose old focus nodes if list shrunk
    while (_cardFocusNodes.length > _torrents.length) {
      _cardFocusNodes.removeLast().dispose();
    }

    // Add new focus nodes if list grew
    while (_cardFocusNodes.length < _torrents.length) {
      final index = _cardFocusNodes.length;
      final node = FocusNode(debugLabel: 'torrent-card-$index');
      _cardFocusNodes.add(node);
    }
  }

  void _ensureHistoryFocusNodes() {
    // Dispose old focus nodes if list shrunk
    while (_historyCardFocusNodes.length > _searchHistory.length) {
      _historyCardFocusNodes.removeLast().dispose();
    }

    // Add new focus nodes if list grew
    while (_historyCardFocusNodes.length < _searchHistory.length) {
      final index = _historyCardFocusNodes.length;
      final node = FocusNode(debugLabel: 'history-card-$index');
      _historyCardFocusNodes.add(node);
    }
  }

  bool get _bothServicesEnabled {
    return _realDebridIntegrationEnabled &&
        _torboxIntegrationEnabled &&
        _apiKey != null &&
        _apiKey!.isNotEmpty &&
        _torboxApiKey != null &&
        _torboxApiKey!.isNotEmpty;
  }

  int get _enabledServicesCount {
    int count = 0;
    if (_realDebridIntegrationEnabled && _apiKey != null && _apiKey!.isNotEmpty) {
      count++;
    }
    if (_torboxIntegrationEnabled && _torboxApiKey != null && _torboxApiKey!.isNotEmpty) {
      count++;
    }
    if (_pikpakEnabled) {
      count++;
    }
    return count;
  }

  bool get _multipleServicesEnabled {
    return _enabledServicesCount > 1;
  }

  void _handleTorrentCardActivated(Torrent torrent, int index) {
    if (_multipleServicesEnabled) {
      // Show dialog to choose service
      _showServiceSelectionDialog(torrent, index);
    } else if (_realDebridIntegrationEnabled && _apiKey != null && _apiKey!.isNotEmpty) {
      // Direct to Real-Debrid
      _addToRealDebrid(torrent.infohash, torrent.name, index);
    } else if (_torboxIntegrationEnabled && _torboxApiKey != null && _torboxApiKey!.isNotEmpty) {
      // Direct to Torbox
      _addToTorbox(torrent.infohash, torrent.name);
    } else if (_pikpakEnabled) {
      // Direct to PikPak
      _sendToPikPak(torrent.infohash, torrent.name);
    } else {
      // No service configured
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please configure Real-Debrid, Torbox, or PikPak in Settings'),
        ),
      );
    }
  }

  Future<void> _showServiceSelectionDialog(Torrent torrent, int index) async {
    final List<Widget> options = [];

    // Add Torbox option if enabled
    if (_torboxIntegrationEnabled && _torboxApiKey != null && _torboxApiKey!.isNotEmpty) {
      options.add(
        ListTile(
          leading: const Icon(Icons.flash_on_rounded, color: Color(0xFF7C3AED)),
          title: const Text('Torbox', style: TextStyle(color: Colors.white)),
          onTap: () => Navigator.of(context).pop('torbox'),
        ),
      );
    }

    // Add Real-Debrid option if enabled
    if (_realDebridIntegrationEnabled && _apiKey != null && _apiKey!.isNotEmpty) {
      options.add(
        ListTile(
          leading: const Icon(Icons.cloud_rounded, color: Color(0xFFE50914)),
          title: const Text('Real-Debrid', style: TextStyle(color: Colors.white)),
          onTap: () => Navigator.of(context).pop('debrid'),
        ),
      );
    }

    // Add PikPak option if enabled
    if (_pikpakEnabled) {
      options.add(
        ListTile(
          leading: const Icon(Icons.folder_rounded, color: Color(0xFF0088CC)),
          title: const Text('PikPak', style: TextStyle(color: Colors.white)),
          onTap: () => Navigator.of(context).pop('pikpak'),
        ),
      );
    }

    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF0F172A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
        title: const Text(
          'Add Torrent',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: options,
        ),
      ),
    );

    if (result == 'torbox') {
      _addToTorbox(torrent.infohash, torrent.name);
    } else if (result == 'debrid') {
      _addToRealDebrid(torrent.infohash, torrent.name, index);
    } else if (result == 'pikpak') {
      _sendToPikPak(torrent.infohash, torrent.name);
    }
  }

  Future<void> _loadDefaultSettings() async {
    // Load available engines based on current search mode
    List<DynamicEngine> engines;

    if (_searchMode == SearchMode.imdb) {
      // For IMDB mode, get engines that specifically support IMDB search
      engines = await TorrentService.getImdbSearchEngines();
      debugPrint('TorrentSearchScreen: Loading IMDB engines: ${engines.map((e) => e.name).toList()}');
    } else {
      // For keyword mode, get all keyword search capable engines
      engines = await TorrentService.getKeywordSearchEngines();
      debugPrint('TorrentSearchScreen: Loading keyword engines: ${engines.map((e) => e.name).toList()}');
    }

    // If no engines available for this mode, try to get any available engines as fallback
    if (engines.isEmpty) {
      debugPrint('TorrentSearchScreen: No engines available for $_searchMode mode');
      engines = await TorrentService.getAvailableEngines();

      // Filter based on mode even from all engines
      if (_searchMode == SearchMode.imdb) {
        engines = engines.where((e) => e.supportsImdbSearch).toList();
      } else {
        engines = engines.where((e) => e.supportsKeywordSearch).toList();
      }

      if (engines.isEmpty) {
        debugPrint('TorrentSearchScreen: Still no engines after fallback filter');
      }
    }

    final Map<String, bool> states = {};

    // Preserve previous enabled states where possible, but only for available engines
    final previousStates = Map<String, bool>.from(_engineStates);

    // Load enabled state for each engine from SettingsManager
    for (final engine in engines) {
      final engineId = engine.name;

      // If we had a previous state for this engine, preserve it
      // Otherwise, load from settings
      if (previousStates.containsKey(engineId)) {
        states[engineId] = previousStates[engineId]!;
      } else {
        final defaultEnabled = engine.settingsConfig.enabled?.defaultBool ?? true;
        final isEnabled = await _settingsManager.getEnabled(engineId, defaultEnabled);
        states[engineId] = isEnabled;
      }
    }

    // If no engines are enabled after switching mode, enable the first available engine
    if (states.isNotEmpty && !states.values.any((enabled) => enabled)) {
      final firstEngineId = engines.first.name;
      states[firstEngineId] = true;
    }

    if (!mounted) return;
    setState(() {
      _availableEngines = engines;
      _engineStates = states;
    });

    // Ensure focus nodes exist for all engines
    _ensureEngineFocusNodes();

    // Focus the search field after a short delay to ensure UI is ready
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) {
        _searchFocusNode.requestFocus();
      }
    });

    // Load default filters only if no preserved state (not returning from debrid folder)
    if (!_preservedState.hasState) {
      await _loadDefaultFilters();
    }
  }

  Future<void> _loadDefaultFilters() async {
    try {
      final qualities = await StorageService.getDefaultFilterQualities();
      final sources = await StorageService.getDefaultFilterRipSources();
      final languages = await StorageService.getDefaultFilterLanguages();

      if (!mounted) return;

      // Convert stored strings back to enums
      final qualitySet = <QualityTier>{};
      final sourceSet = <RipSourceCategory>{};
      final languageSet = <AudioLanguage>{};

      for (final q in qualities) {
        final tier = QualityTier.values.where((e) => e.name == q).firstOrNull;
        if (tier != null) qualitySet.add(tier);
      }
      for (final s in sources) {
        final source = RipSourceCategory.values.where((e) => e.name == s).firstOrNull;
        if (source != null) sourceSet.add(source);
      }
      for (final l in languages) {
        final lang = AudioLanguage.values.where((e) => e.name == l).firstOrNull;
        if (lang != null) languageSet.add(lang);
      }

      // Only set if any defaults are configured
      if (qualitySet.isNotEmpty || sourceSet.isNotEmpty || languageSet.isNotEmpty) {
        setState(() {
          _filters = TorrentFilterState(
            qualities: qualitySet,
            ripSources: sourceSet,
            languages: languageSet,
          );
        });
      }
    } catch (e) {
      debugPrint('TorrentSearchScreen: Failed to load default filters: $e');
    }
  }

  void _ensureEngineFocusNodes() {
    // Remove focus nodes for engines that no longer exist
    final engineIds = _availableEngines.map((e) => e.name).toSet();
    final keysToRemove = _engineTileFocusNodes.keys
        .where((key) => !engineIds.contains(key))
        .toList();
    for (final key in keysToRemove) {
      _engineTileFocusNodes[key]?.dispose();
      _engineTileFocusNodes.remove(key);
      _engineTileFocusStates.remove(key);
    }

    // Add focus nodes for new engines
    for (final engine in _availableEngines) {
      final engineId = engine.name;
      if (!_engineTileFocusNodes.containsKey(engineId)) {
        final node = FocusNode(debugLabel: 'engine-tile-$engineId');
        _engineTileFocusNodes[engineId] = node;
        _engineTileFocusStates[engineId] = false;
      }
    }
  }

  void _handleIntegrationChanged() {
    _loadApiKeys();
  }

  Future<void> _loadApiKeys() async {
    final rdKey = await StorageService.getApiKey();
    final torboxKey = await StorageService.getTorboxApiKey();
    final rdEnabled = await StorageService.getRealDebridIntegrationEnabled();
    final torboxEnabled = await StorageService.getTorboxIntegrationEnabled();
    final pikpakEnabled = await StorageService.getPikPakEnabled();
    if (!mounted) return;
    setState(() {
      _apiKey = rdKey;
      _torboxApiKey = torboxKey;
      _realDebridIntegrationEnabled = rdEnabled;
      _torboxIntegrationEnabled = torboxEnabled;
      _pikpakEnabled = pikpakEnabled;
    });
  }

  // ============================================================================
  // Torrent Search History Methods
  // ============================================================================

  Torrent _findTorrentByInfohash(String infohash, String fallbackName) {
    return _torrents.firstWhere(
      (t) => t.infohash.toLowerCase() == infohash.toLowerCase(),
      orElse: () => _allTorrents.firstWhere(
        (t) => t.infohash.toLowerCase() == infohash.toLowerCase(),
        orElse: () => Torrent(
          rowid: 0,
          infohash: infohash,
          name: fallbackName,
          sizeBytes: 0,
          createdUnix: 0,
          seeders: 0,
          leechers: 0,
          completed: 0,
          scrapedDate: 0,
          source: 'unknown',
        ),
      ),
    );
  }

  Future<void> _loadSearchHistory() async {
    final history = await StorageService.getTorrentSearchHistory();
    final enabled = await StorageService.getTorrentSearchHistoryEnabled();
    if (!mounted) return;
    setState(() {
      _searchHistory = history;
      _historyTrackingEnabled = enabled;
    });
    _ensureHistoryFocusNodes();
  }

  Future<void> _saveToHistory(Torrent torrent, String service) async {
    if (!_historyTrackingEnabled) return;
    await StorageService.addTorrentToHistory(torrent.toJson(), service);
    await _loadSearchHistory(); // Refresh
  }

  Future<void> _clearHistory() async {
    await StorageService.clearTorrentSearchHistory();
    await _loadSearchHistory();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Search history cleared'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _toggleHistoryTracking(bool enabled) async {
    setState(() {
      _historyTrackingEnabled = enabled;
    });
    await StorageService.setTorrentSearchHistoryEnabled(enabled);
  }

  String _getServiceLabel(String service) {
    switch (service.toLowerCase()) {
      case 'realdebrid':
        return 'Real-Debrid';
      case 'torbox':
        return 'Torbox';
      case 'pikpak':
        return 'PikPak';
      default:
        return service;
    }
  }

  @override
  void dispose() {
    // Preserve state before disposing (for seamless return after viewing debrid folder)
    _preservedState.searchQuery = _searchController.text;
    _preservedState.searchMode = _searchMode;
    _preservedState.selectedImdbTitle = _selectedImdbTitle;
    _preservedState.isSeries = _isSeries;
    _preservedState.allTorrents = List.from(_allTorrents);
    _preservedState.torrents = List.from(_torrents);
    _preservedState.hasSearched = _hasSearched;
    _preservedState.engineStates = Map.from(_engineStates);
    _preservedState.engineCounts = Map.from(_engineCounts);
    _preservedState.engineErrors = Map.from(_engineErrors);
    _preservedState.selectedEngineFilter = _selectedEngineFilter;
    _preservedState.sortBy = _sortBy;
    _preservedState.sortAscending = _sortAscending;
    _preservedState.filters = _filters;
    _preservedState.seasonText = _seasonController.text;
    _preservedState.episodeText = _episodeController.text;
    _preservedState.availableSeasons = _availableSeasons != null ? List.from(_availableSeasons!) : null;
    _preservedState.selectedSeason = _selectedSeason;
    _preservedState.seriesControlsExpanded = _seriesControlsExpanded;
    _preservedState.imdbControlsCollapsed = _imdbControlsCollapsed;
    _preservedState.torboxCacheStatus = _torboxCacheStatus != null ? Map.from(_torboxCacheStatus!) : null;
    _preservedState.torrentMetadata = Map.from(_torrentMetadata);
    _preservedState.showingTorboxCachedOnly = _showingTorboxCachedOnly;
    // Use last known offset since controller may not have clients during dispose
    _preservedState.scrollOffset = _lastKnownScrollOffset;

    _sortDropdownFocusNode.removeListener(_onSortDropdownFocusChange);
    _resultsScrollController.removeListener(_onScrollChanged);
    _searchController.dispose();
    _resultsScrollController.dispose();
    _searchFocusNode.dispose();
    _providerAccordionFocusNode.dispose();
    _advancedButtonFocusNode.dispose();
    _sortDropdownFocusNode.dispose();
    _sortDirectionFocusNode.dispose();
    _filterButtonFocusNode.dispose();
    _clearFiltersButtonFocusNode.dispose();

    // Dispose ValueNotifiers
    _searchFocused.dispose();
    _providerAccordionFocused.dispose();
    _advancedButtonFocused.dispose();
    _sortDropdownFocused.dispose();
    _sortDirectionFocused.dispose();
    _filterButtonFocused.dispose();
    _clearFiltersButtonFocused.dispose();
    _modeSelectorFocused.dispose();
    _selectionChipFocused.dispose();
    _expandControlsFocused.dispose();
    _seasonInputFocused.dispose();
    _episodeInputFocused.dispose();
    _historyDisableSwitchFocused.dispose();
    _historyClearButtonFocused.dispose();

    // Dispose IMDB Smart Search Mode resources
    _modeSelectorFocusNode.dispose();
    _selectionChipFocusNode.dispose();
    _expandControlsFocusNode.dispose();
    _seasonInputFocusNode.dispose();
    _episodeInputFocusNode.dispose();
    _seasonController.dispose();
    _episodeController.dispose();
    _imdbSearchDebouncer?.cancel();
    _imdbRequestId = 0; // Reset request ID
    for (final node in _autocompleteFocusNodes) {
      node.dispose();
    }
    _autocompleteFocusNodes.clear();

    for (final node in _cardFocusNodes) {
      node.dispose();
    }
    // Card focus states now use index tracking - no disposal needed

    // Dispose history focus nodes
    _historyDisableSwitchFocusNode.dispose();
    _historyClearButtonFocusNode.dispose();
    for (final node in _historyCardFocusNodes) {
      node.dispose();
    }

    // Dispose dynamic engine focus nodes
    for (final node in _engineTileFocusNodes.values) {
      node.dispose();
    }
    _engineTileFocusNodes.clear();
    _engineTileFocusStates.clear();
    MainPageBridge.removeIntegrationListener(_handleIntegrationChanged);
    MainPageBridge.handleRealDebridResult = null;
    MainPageBridge.handleTorboxResult = null;
    MainPageBridge.handlePikPakResult = null;
    _listAnimationController.dispose();
    super.dispose();
  }

  Future<void> _searchTorrents(String query) async {
    if (query.trim().isEmpty) return;

    final int requestId = ++_activeSearchRequestId;
    setState(() {
      _isLoading = true;
      _errorMessage = '';
      _hasSearched = true;
      _torboxCacheStatus = null;
      _showingTorboxCachedOnly = false;
      _selectedEngineFilter = null; // Reset engine filter on new search
    });

    // Hide keyboard
    _searchFocusNode.unfocus();

    final results = await Future.wait([
      StorageService.getTorboxCacheCheckEnabled(),
      StorageService.getTorboxApiKey(),
      StorageService.getRealDebridIntegrationEnabled(),
      StorageService.getTorboxIntegrationEnabled(),
      StorageService.getApiKey(),
      StorageService.getPikPakEnabled(),
    ]);
    final bool cacheCheckPreference = results[0] as bool;
    final String? torboxKey = results[1] as String?;
    final bool rdEnabled = results[2] as bool;
    final bool torboxEnabled = results[3] as bool;
    final String? rdKey = results[4] as String?;
    final bool pikpakEnabled = results[5] as bool;
    if (mounted) {
      setState(() {
        _torboxCacheCheckEnabled = cacheCheckPreference;
        _torboxApiKey = torboxKey;
        _realDebridIntegrationEnabled = rdEnabled;
        _torboxIntegrationEnabled = torboxEnabled;
        _apiKey = rdKey;
        _pikpakEnabled = pikpakEnabled;
      });
    }

    try {
      final Map<String, dynamic> result;
      final selection = _activeAdvancedSelection;

      // Use IMDB search when we have an advanced selection, otherwise keyword search
      if (selection != null && selection.imdbId.trim().isNotEmpty) {
        debugPrint('TorrentSearchScreen: Using IMDB search for ${selection.imdbId}, isMovie=${!selection.isSeries}, title=${selection.title}');
        result = await TorrentService.searchByImdb(
          selection.imdbId,
          engineStates: _engineStates,
          isMovie: !selection.isSeries,
          season: selection.season,
          episode: selection.episode,
        );
      } else {
        debugPrint('TorrentSearchScreen: Using KEYWORD search (no advanced selection) for query: $query');
        result = await TorrentService.searchAllEngines(
          query,
          engineStates: _engineStates,
        );
      }

      final combinedTorrents = (result['torrents'] as List<Torrent>).toList(
        growable: false,
      );
      final Map<String, String> engineErrors = {};
      final rawErrors = result['engineErrors'];
      if (rawErrors is Map) {
        rawErrors.forEach((key, value) {
          engineErrors[key.toString()] = value?.toString() ?? '';
        });
      }
      if (engineErrors.isNotEmpty) {
        debugPrint(
          'TorrentSearchScreen: Search engine failures: $engineErrors',
        );
      }
      String nextErrorMessage = '';
      if (engineErrors.isNotEmpty && combinedTorrents.isEmpty) {
        final failedEngines = engineErrors.keys
            .map(_friendlyEngineName)
            .join(', ');
        nextErrorMessage =
            'Failed to load results from $failedEngines. Please try again.';
      }
      Map<String, bool>? torboxCacheMap;

      final String? torboxKeyValue = torboxKey;
      if (cacheCheckPreference &&
          torboxEnabled &&
          torboxKeyValue != null &&
          torboxKeyValue.isNotEmpty &&
          combinedTorrents.isNotEmpty) {
        final uniqueHashes = combinedTorrents
            .map((torrent) => torrent.infohash.trim().toLowerCase())
            .where((hash) => hash.isNotEmpty)
            .toSet()
            .toList();

        if (uniqueHashes.isNotEmpty) {
          try {
            final cachedHashes = await TorboxService.checkCachedTorrents(
              apiKey: torboxKeyValue,
              infoHashes: uniqueHashes,
              listFiles: false,
            );
            torboxCacheMap = {
              for (final hash in uniqueHashes)
                hash: cachedHashes.contains(hash),
            };
          } catch (e) {
            debugPrint('TorrentSearchScreen: Torbox cache check failed: $e');
            torboxCacheMap = null;
          }
        }
      }

      final bool torboxActive =
          torboxEnabled && torboxKeyValue != null && torboxKeyValue.isNotEmpty;
      final bool realDebridActive =
          rdEnabled && rdKey != null && rdKey.isNotEmpty;
      bool showOnlyCached = false;
      List<Torrent> filteredTorrents = combinedTorrents;
      if (cacheCheckPreference &&
          torboxActive &&
          !realDebridActive &&
          torboxCacheMap != null) {
        filteredTorrents = combinedTorrents
            .where((torrent) {
              final hash = torrent.infohash.trim().toLowerCase();
              return torboxCacheMap![hash] ?? false;
            })
            .toList(growable: false);
        showOnlyCached = true;
      }

      // Filter by season when season is specified but episode is not
      // This ensures we only show torrents that include the requested season
      if (selection != null &&
          selection.isSeries &&
          selection.season != null &&
          selection.episode == null) {
        final beforeFilterCount = filteredTorrents.length;
        final requestedSeason = selection.season!;

        // Keep only torrents that include the requested season
        filteredTorrents = filteredTorrents
            .where((torrent) {
              switch (torrent.coverageType) {
                case 'completeSeries':
                  // Always include complete series (they include all seasons)
                  return true;

                case 'multiSeasonPack':
                  // Include if the requested season is within the range
                  if (torrent.startSeason != null && torrent.endSeason != null) {
                    return torrent.startSeason! <= requestedSeason &&
                           torrent.endSeason! >= requestedSeason;
                  }
                  // If season range data is missing, exclude to be safe
                  return false;

                case 'seasonPack':
                  // Include only if it matches the requested season exactly
                  return torrent.seasonNumber == requestedSeason;

                case 'singleEpisode':
                  // For single episodes, check if they belong to the requested season
                  // Parse the episode pattern from the name
                  final name = torrent.name.toUpperCase();

                  // Check various season formats: S04, Season 4, etc.
                  final seasonPadded = requestedSeason.toString().padLeft(2, '0');
                  final seasonPatterns = [
                    'S$seasonPadded',  // S04
                    'S$requestedSeason', // S4
                    'SEASON $requestedSeason', // Season 4
                    'SEASON$requestedSeason',  // Season4
                    '${requestedSeason}X', // 4x (for 4x01 format)
                  ];

                  // Check if any pattern matches
                  for (final pattern in seasonPatterns) {
                    if (name.contains(pattern)) {
                      return true;
                    }
                  }

                  // If we can't determine the season, exclude the single episode
                  return false;

                default:
                  // Unknown coverage type - keep it to avoid over-filtering
                  return true;
              }
            })
            .toList(growable: false);

        final afterFilterCount = filteredTorrents.length;
        debugPrint(
          'TorrentSearchScreen: Season filter applied for Season $requestedSeason - '
          'filtered from $beforeFilterCount to $afterFilterCount torrents '
          '(removed ${beforeFilterCount - afterFilterCount} torrents from other seasons)',
        );

        // Show helpful message if all results were filtered out
        if (filteredTorrents.isEmpty && beforeFilterCount > 0) {
          nextErrorMessage =
              'No torrents found for Season $requestedSeason. Found $beforeFilterCount torrents from other seasons that were filtered out.';
        }
      }

      // Filter out season packs when a specific episode is requested
      // Only apply this filter for TV series searches with episode specified
      if (selection != null &&
          selection.isSeries &&
          selection.episode != null) {
        final beforeFilterCount = filteredTorrents.length;

        // Build the expected episode pattern (e.g., "S05E01" or "5x1")
        final season = selection.season!;
        final episode = selection.episode!;
        final expectedS = 'S${season.toString().padLeft(2, '0')}E${episode.toString().padLeft(2, '0')}';
        final expectedSNoZero = 'S${season}E${episode}';
        final expectedX = '${season}x${episode.toString().padLeft(2, '0')}';
        final expectedXNoZero = '${season}x${episode}';

        // Keep only single episode torrents that match the requested episode
        filteredTorrents = filteredTorrents
            .where((torrent) {
              // Must be a single episode (not a pack)
              if (torrent.coverageType != 'singleEpisode') return false;

              // Check if torrent name contains the episode pattern
              final name = torrent.name.toUpperCase();

              // Check various episode formats: S05E01, S5E1, 5x01, 5x1
              if (name.contains(expectedS.toUpperCase()) ||
                  name.contains(expectedSNoZero.toUpperCase()) ||
                  name.contains(expectedX.toUpperCase()) ||
                  name.contains(expectedXNoZero.toUpperCase())) {
                return true;
              }

              return false;
            })
            .toList(growable: false);

        final afterFilterCount = filteredTorrents.length;
        debugPrint(
          'TorrentSearchScreen: Episode filter applied for S${selection.season?.toString().padLeft(2, '0')}E${selection.episode?.toString().padLeft(2, '0')} - '
          'filtered from $beforeFilterCount to $afterFilterCount torrents '
          '(removed ${beforeFilterCount - afterFilterCount} season/complete series packs)',
        );

        // Show helpful message if all results were filtered out
        if (filteredTorrents.isEmpty && beforeFilterCount > 0) {
          final episodeLabel = 'S${selection.season?.toString().padLeft(2, '0')}E${selection.episode?.toString().padLeft(2, '0')}';
          nextErrorMessage =
              'No single episode torrents found for $episodeLabel. Found $beforeFilterCount season/series packs that were filtered out.';
        }
      }

      if (!mounted || requestId != _activeSearchRequestId) {
        return;
      }

      final metadata = _buildTorrentMetadataMap(filteredTorrents);

      setState(() {
        _engineCounts = Map<String, int>.from(result['engineCounts'] as Map);
        _engineErrors = engineErrors;
        _torboxCacheStatus = torboxCacheMap;
        _isLoading = false;
        _showingTorboxCachedOnly = showOnlyCached;
        _errorMessage = nextErrorMessage;
      });

      // Apply sorting + filters to the new dataset
      _sortTorrents(nextBase: filteredTorrents, metadataOverride: metadata);
      _listAnimationController.forward();
    } catch (e) {
      if (!mounted || requestId != _activeSearchRequestId) {
        return;
      }
      setState(() {
        // Format the error for display
        String errorMsg = e.toString().replaceAll('Exception: ', '');
        if (errorMsg.contains('SocketException') || errorMsg.contains('Failed host lookup')) {
          errorMsg = 'Network error. Please check your connection.';
        } else if (errorMsg.contains('TimeoutException')) {
          errorMsg = 'Search timed out. Please try again.';
        } else if (errorMsg.length > 100) {
          errorMsg = 'Search failed. Please try again.';
        }
        _errorMessage = errorMsg;
        _isLoading = false;
      });
    }
  }

  String _friendlyEngineName(String name) {
    switch (name) {
      case 'torrents_csv':
        return 'Torrents CSV';
      case 'pirate_bay':
        return 'The Pirate Bay';
      case 'yts':
        return 'YTS';
      case 'solid_torrents':
        return 'SolidTorrents';
      case 'torrentio':
        return 'Torrentio';
      default:
        return name;
    }
  }

  String? _sourceTagLabel(String rawSource) {
    switch (rawSource.trim().toLowerCase()) {
      case 'yts':
        return 'YTS';
      case 'pirate_bay':
        return 'TPB';
      case 'torrents_csv':
        return 'TCSV';
      case 'solid_torrents':
        return 'ST';
      case 'torrentio':
        return 'TIO';
      case 'knaben':
        return 'KNB';
      default:
        return null;
    }
  }

  Widget? _buildSourceTag(String rawSource) {
    final label = _sourceTagLabel(rawSource);
    if (label == null) return null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFACC15), Color(0xFFF59E0B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFF59E0B).withValues(alpha: 0.35),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: const Color(0xFFFEF3C7).withValues(alpha: 0.7),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.star_rounded,
            size: 13,
            color: const Color(0xFF713F12).withValues(alpha: 0.85),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
              color: Color(0xFF713F12),
            ),
          ),
        ],
      ),
    );
  }

  // Build source chip for stats row - compact version matching StatChip style
  Widget _buildSourceStatChip(String rawSource) {
    final label = _sourceTagLabel(rawSource);
    if (label == null) {
      // Return a default source chip if no label
      return StatChip(
        icon: Icons.source_rounded,
        text: 'Unknown',
        color: const Color(0xFF6B7280), // Gray 500
      );
    }

    // Determine color based on source
    Color sourceColor;
    switch (rawSource.trim().toLowerCase()) {
      case 'yts':
        sourceColor = const Color(0xFF10B981); // Emerald 500
        break;
      case 'pirate_bay':
        sourceColor = const Color(0xFFF59E0B); // Amber 500 (keeping original yellow tone)
        break;
      case 'torrents_csv':
        sourceColor = const Color(0xFF3B82F6); // Blue 500
        break;
      case 'solid_torrents':
        sourceColor = const Color(0xFFEF4444); // Red 500
        break;
      case 'torrentio':
        sourceColor = const Color(0xFF8B5CF6); // Violet 500
        break;
      case 'knaben':
        sourceColor = const Color(0xFFEC4899); // Pink 500
        break;
      default:
        sourceColor = const Color(0xFF6B7280); // Gray 500
        break;
    }

    return StatChip(
      icon: Icons.source_rounded,
      text: label,
      color: sourceColor,
    );
  }

  void _setEngineEnabled(String engineId, bool value) {
    if (_engineStates[engineId] == value) return;
    setState(() {
      _engineStates[engineId] = value;
    });
    // Persist to SettingsManager
    _settingsManager.setEnabled(engineId, value);
    if (_hasSearched && _searchController.text.trim().isNotEmpty) {
      _searchTorrents(_searchController.text);
    }
  }

  void _handleSearchFieldChanged(String value) {
    // In IMDB mode, trigger autocomplete search
    if (_searchMode == SearchMode.imdb) {
      // On TV: Don't trigger autocomplete as user types (only on Enter/Submit)
      // On non-TV: Trigger autocomplete as they type (current behavior)
      if (!_isTelevision) {
        _onImdbSearchTextChanged(value);
      }
      // If user manually edits, clear the active selection
      final trimmed = value.trim();
      if (_activeAdvancedSelection != null &&
          trimmed != _activeAdvancedSelection!.displayQuery) {
        setState(() {
          _selectedImdbTitle = null;
          _activeAdvancedSelection = null;
        });
      }
      return;
    }

    // Keyword mode: clear advanced selection if user manually edits
    final trimmed = value.trim();
    if (_activeAdvancedSelection != null &&
        trimmed != _activeAdvancedSelection!.displayQuery) {
      setState(() {
        _activeAdvancedSelection = null;
      });
    }
  }

  Future<void> _openAdvancedSearchDialog() async {
    final selection = await showModalBottomSheet<AdvancedSearchSelection>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) =>
          AdvancedSearchSheet(initialSelection: _activeAdvancedSelection),
    );

    if (selection != null) {
      setState(() {
        _activeAdvancedSelection = selection;
        _searchController.text = selection.displayQuery;
      });
      await _searchTorrents(selection.displayQuery);
    }
  }

  Widget _buildAdvancedButton() {
    final selection = _activeAdvancedSelection;
    final label = selection == null ? 'Adv' : 'Adv*';
    return Focus(
      focusNode: _advancedButtonFocusNode,
      onFocusChange: (focused) {
        _advancedButtonFocused.value = focused; // No setState needed!
      },
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.select ||
                event.logicalKey == LogicalKeyboardKey.enter)) {
          _openAdvancedSearchDialog();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Tooltip(
        message: selection == null
            ? 'Search via IMDb + Torrentio'
            : 'Advanced Torrentio search active',
        child: ValueListenableBuilder<bool>(
          valueListenable: _advancedButtonFocused,
          builder: (context, isFocused, child) => Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: isFocused
                  ? Border.all(color: Colors.white, width: 2)
                  : null,
            ),
            child: child,
          ),
          child: TextButton.icon(
            onPressed: selection == null
                ? _openAdvancedSearchDialog
                : () async {
                    await _openAdvancedSearchDialog();
                  },
            style: TextButton.styleFrom(
              backgroundColor: selection == null
                  ? const Color(0xFF1E3A8A)
                  : const Color(0xFF7C3AED),
              foregroundColor: Colors.white,
              minimumSize: const Size(64, 36),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            icon: const Icon(Icons.auto_awesome_outlined, size: 16),
            label: Text(label, style: const TextStyle(fontSize: 12)),
          ),
        ),
      ),
    );
  }

  // Mode selector dropdown for Smart Search Mode
  Widget _buildModeSelector() {
    return Focus(
      focusNode: _modeSelectorFocusNode,
      onFocusChange: (focused) {
        _modeSelectorFocused.value = focused; // No setState needed!
      },
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.select ||
                event.logicalKey == LogicalKeyboardKey.enter)) {
          // Toggle between modes on select/enter
          _toggleSearchMode();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: ValueListenableBuilder<bool>(
        valueListenable: _modeSelectorFocused,
        builder: (context, isFocused, child) => Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: isFocused
                ? Border.all(color: Colors.white, width: 2)
                : null,
          ),
          child: child,
        ),
        child: PopupMenuButton<SearchMode>(
          onSelected: (mode) {
            setState(() {
              _searchMode = mode;
              // Clear autocomplete when switching modes
              _imdbAutocompleteResults.clear();
              _selectedImdbTitle = null;
              _imdbSearchError = null;
              _seriesControlsExpanded = false; // Reset expansion state
              if (mode == SearchMode.keyword) {
                // Clear IMDB-specific state when returning to keyword mode
                _activeAdvancedSelection = null;
                _isSeries = false;
                _seasonController.clear();
                _episodeController.clear();
              }
            });
            // Reload engines for the new search mode
            _loadDefaultSettings();
          },
          itemBuilder: (context) => [
            PopupMenuItem(
              value: SearchMode.keyword,
              child: Row(
                children: [
                  Icon(
                    Icons.search_rounded,
                    size: 18,
                    color: _searchMode == SearchMode.keyword
                        ? const Color(0xFF7C3AED)
                        : Colors.white70,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Keyword',
                    style: TextStyle(
                      color: _searchMode == SearchMode.keyword
                          ? const Color(0xFF7C3AED)
                          : Colors.white,
                      fontWeight: _searchMode == SearchMode.keyword
                          ? FontWeight.w600
                          : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
            PopupMenuItem(
              value: SearchMode.imdb,
              child: Row(
                children: [
                  Icon(
                    Icons.auto_awesome_outlined,
                    size: 18,
                    color: _searchMode == SearchMode.imdb
                        ? const Color(0xFF7C3AED)
                        : Colors.white70,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'IMDB',
                    style: TextStyle(
                      color: _searchMode == SearchMode.imdb
                          ? const Color(0xFF7C3AED)
                          : Colors.white,
                      fontWeight: _searchMode == SearchMode.imdb
                          ? FontWeight.w600
                          : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
          ],
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: _searchMode == SearchMode.imdb
                  ? const Color(0xFF7C3AED)
                  : const Color(0xFF1E3A8A),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _searchMode == SearchMode.imdb
                      ? Icons.auto_awesome_outlined
                      : Icons.search_rounded,
                  size: 16,
                  color: Colors.white,
                ),
                const SizedBox(width: 6),
                Text(
                  _searchMode == SearchMode.imdb ? 'IMDB' : 'Keyword',
                  style: const TextStyle(fontSize: 12, color: Colors.white),
                ),
                const SizedBox(width: 4),
                const Icon(
                  Icons.arrow_drop_down_rounded,
                  size: 18,
                  color: Colors.white,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _toggleSearchMode() {
    setState(() {
      _searchMode =
          _searchMode == SearchMode.keyword ? SearchMode.imdb : SearchMode.keyword;
      _imdbAutocompleteResults.clear();
      _selectedImdbTitle = null;
      _imdbSearchError = null;
      _seriesControlsExpanded = false; // Reset expansion state
      if (_searchMode == SearchMode.keyword) {
        _activeAdvancedSelection = null;
        _isSeries = false;
        _seasonController.clear();
        _episodeController.clear();
      }
    });
    // Reload engines for the new search mode
    _loadDefaultSettings();
  }

  // IMDB autocomplete search with debouncing
  void _onImdbSearchTextChanged(String query) {
    // Cancel previous timer
    _imdbSearchDebouncer?.cancel();

    // Increment request ID to track the latest request
    final requestId = ++_imdbRequestId;
    debugPrint('IMDB search triggered for: "$query" (requestId: $requestId)');

    if (query.trim().isEmpty) {
      setState(() {
        _imdbAutocompleteResults.clear();
        _imdbSearchError = null;
        _isImdbSearching = false;
      });
      return;
    }

    if (query.trim().length < 2) {
      setState(() {
        _imdbAutocompleteResults.clear();
        _imdbSearchError = 'Enter at least 2 characters';
        _isImdbSearching = false;
      });
      return;
    }

    // Don't show loading state immediately to prevent flicker
    // It will be shown after debounce if search actually happens
    setState(() {
      _imdbSearchError = null;
    });

    // Debounce: wait 500ms after user stops typing (increased from 300ms)
    _imdbSearchDebouncer = Timer(const Duration(milliseconds: 500), () {
      // Only show loading state when we're actually about to search
      if (mounted) {
        setState(() {
          _isImdbSearching = true;
        });
      }
      _performImdbAutocompleteSearch(query.trim(), requestId);
    });
  }

  Future<void> _performImdbAutocompleteSearch(String query, int requestId) async {
    try {
      debugPrint('IMDB search started for: "$query" (requestId: $requestId)');
      final results = await ImdbLookupService.searchTitles(query);

      // Check if this is still the latest request
      if (requestId != _imdbRequestId) {
        debugPrint('IMDB search discarded (stale): "$query" (requestId: $requestId, current: $_imdbRequestId)');
        return;
      }

      if (!mounted) return;

      debugPrint('IMDB search completed: "$query" (requestId: $requestId, results: ${results.length})');

      // Dispose old focus nodes and create new ones
      for (final node in _autocompleteFocusNodes) {
        node.dispose();
      }
      _autocompleteFocusNodes = List.generate(
        results.take(10).length,
        (index) => FocusNode(debugLabel: 'imdb_autocomplete_$index'),
      );

      setState(() {
        _imdbAutocompleteResults = results.take(10).toList();
        _isImdbSearching = false;
        _imdbSearchError = results.isEmpty ? 'No IMDb matches found' : null;
      });

      // On TV: Auto-focus first result after results appear
      if (_isTelevision && _autocompleteFocusNodes.isNotEmpty && results.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          Future.delayed(const Duration(milliseconds: 150), () {
            if (_autocompleteFocusNodes.isNotEmpty && mounted) {
              _autocompleteFocusNodes[0].requestFocus();
            }
          });
        });
      }
    } catch (e) {
      // Check if this is still the latest request before updating error state
      if (requestId != _imdbRequestId) {
        debugPrint('IMDB search error discarded (stale): "$query" (requestId: $requestId, current: $_imdbRequestId)');
        return;
      }

      debugPrint('IMDB autocomplete error for "$query" (requestId: $requestId): $e');
      if (!mounted) return;
      setState(() {
        _imdbAutocompleteResults.clear();
        _isImdbSearching = false;
        _imdbSearchError = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  // Handle IMDB result selection
  void _onImdbResultSelected(ImdbTitleResult result) async {

    // Clear autocomplete immediately
    setState(() {
      _selectedImdbTitle = result;
      _imdbAutocompleteResults.clear();
      _imdbSearchError = null;
      _isImdbSearching = true; // Show loading indicator while fetching details
      _imdbControlsCollapsed = false; // Expand controls for new selection
    });

    try {
      // Fetch title details to determine if it's a movie or series
      final details = await ImdbLookupService.getTitleDetails(result.imdbId);

      if (!mounted) return;

      // Parse the response to determine type
      bool isSeries = false;
      if (details['short'] != null && details['short'] is Map) {
        final shortData = details['short'] as Map<String, dynamic>;
        final type = shortData['@type']?.toString() ?? '';
        isSeries = type == 'TVSeries';
      } else {
        // Fallback if structure is different
        isSeries = false;
      }

      // Extract available seasons from IMDbbot API for series
      List<int>? availableSeasons;
      if (isSeries) {
        try {
          final main = details['main'];
          if (main != null && main is Map) {
            final episodes = main['episodes'];
            if (episodes != null && episodes is Map) {
              final seasons = episodes['seasons'];
              if (seasons != null && seasons is List) {
                availableSeasons = seasons
                    .map((s) => (s is Map) ? (s['number'] as int?) : null)
                    .where((n) => n != null)
                    .cast<int>()
                    .toList();
                debugPrint('TorrentSearchScreen: Extracted ${availableSeasons.length} seasons from IMDbbot API: $availableSeasons');
              }
            }
          }
        } catch (e) {
          debugPrint('TorrentSearchScreen: Error extracting seasons from API: $e');
          availableSeasons = null;
        }
      }

      setState(() {
        _isSeries = isSeries;
        _availableSeasons = availableSeasons;
        _selectedSeason = null; // Default to "All Seasons"
        _seasonController.clear();
        _episodeController.clear();
        _isImdbSearching = false;
        // For series, hide controls initially - user can expand to customize
        _seriesControlsExpanded = !isSeries; // Movies don't need controls, series start collapsed
      });

      debugPrint('TorrentSearchScreen: IMDB title detected - isSeries=$isSeries, title=${_selectedImdbTitle?.title}');

      // Search immediately for both movies and series
      // For series, this will search with default params (null season/episode means all episodes)
      // Users can refine the search later by expanding controls and setting season/episode
      _createAdvancedSelectionAndSearch();
    } catch (e) {
      debugPrint('IMDB Smart Search: Error fetching title details: $e');

      if (!mounted) return;

      // On error, show type selector so user can manually choose
      setState(() {
        _isImdbSearching = false;
        _imdbSearchError = 'Could not determine title type. Please select manually.';
        // Default to movie on error
        _isSeries = false;
        _seasonController.clear();
        _episodeController.clear();
        _seriesControlsExpanded = true; // Show controls on error so user can manually choose
      });

      // Still allow search for movies by default
      _createAdvancedSelectionAndSearch();
    }
  }

  void _createAdvancedSelectionAndSearch() {
    if (_selectedImdbTitle == null) return;

    int? season;
    int? episode;

    if (_isSeries) {
      final bool hasSeasonData = _availableSeasons != null && _availableSeasons!.isNotEmpty;

      // Use dropdown value if available, otherwise fall back to text input
      if (hasSeasonData) {
        // Dropdown mode: use _selectedSeason (null means "All Seasons")
        season = _selectedSeason;

        // Only parse episode if a specific season is selected
        if (season != null) {
          final episodeText = _episodeController.text.trim();
          if (episodeText.isNotEmpty) {
            episode = int.tryParse(episodeText);
          }
          // Note: Don't default to episode 1 if episode is empty
          // This allows searching entire season when episode is not specified
        }
        // If season is null (All Seasons), both season and episode remain null
        // This searches the entire series
      } else {
        // Text input mode (fallback when API didn't provide season data)
        final seasonText = _seasonController.text.trim();
        final episodeText = _episodeController.text.trim();

        if (seasonText.isNotEmpty) {
          season = int.tryParse(seasonText);
        }

        if (episodeText.isNotEmpty) {
          episode = int.tryParse(episodeText);
        } else if (season != null) {
          // Default to episode 1 if season is specified in text mode
          episode = 1;
        }
      }
    }

    final selection = AdvancedSearchSelection(
      imdbId: _selectedImdbTitle!.imdbId,
      isSeries: _isSeries,
      title: _selectedImdbTitle!.title,
      year: _selectedImdbTitle!.year,
      season: season,
      episode: episode,
    );

    debugPrint('TorrentSearchScreen: Creating AdvancedSearchSelection - isSeries=${selection.isSeries}, title=${selection.title}, imdbId=${selection.imdbId}, season=$season, episode=$episode');

    setState(() {
      _activeAdvancedSelection = selection;
      _searchController.text = selection.displayQuery;
      // Auto-collapse controls after search
      _imdbControlsCollapsed = true;
    });

    // Trigger torrent search
    _searchTorrents(selection.displayQuery);
  }

  // Clear IMDB selection
  void _clearImdbSelection() {
    setState(() {
      _selectedImdbTitle = null;
      _activeAdvancedSelection = null;
      _isSeries = false;
      _availableSeasons = null;
      _selectedSeason = null;
      _seasonController.clear();
      _episodeController.clear();
      _searchController.clear();
      _imdbSearchError = null; // Clear any errors when clearing selection
      _isImdbSearching = false; // Reset loading state
      _imdbControlsCollapsed = false; // Expand controls when clearing
      _seriesControlsExpanded = false; // Reset expansion state
    });
  }

  // Build IMDB autocomplete dropdown
  Widget _buildImdbAutocompleteDropdown() {
    if (_imdbAutocompleteResults.isEmpty && !_isImdbSearching && _imdbSearchError == null) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 8,
            spreadRadius: 2,
          ),
        ],
      ),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.5,
      ),
      child: _isImdbSearching
          ? const Padding(
              padding: EdgeInsets.all(32.0),
              child: Center(
                child: CircularProgressIndicator(),
              ),
            )
          : _imdbSearchError != null
              ? Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(
                    _imdbSearchError!,
                    style: const TextStyle(color: Color(0xFFF87171)),
                    textAlign: TextAlign.center,
                    softWrap: true,
                    overflow: TextOverflow.visible,
                  ),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: _imdbAutocompleteResults.length,
                  itemBuilder: (context, index) {
                    final result = _imdbAutocompleteResults[index];
                    final focusNode = _autocompleteFocusNodes[index];
                    return _ImdbAutocompleteItem(
                      result: result,
                      focusNode: focusNode,
                      onSelected: () => _onImdbResultSelected(result),
                      onKeyEvent: (event) => _handleAutocompleteKeyEvent(index, event),
                    );
                  },
                ),
    );
  }

  // Handle keyboard events for autocomplete items
  KeyEventResult _handleAutocompleteKeyEvent(int index, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (index > 0) {
        _autocompleteFocusNodes[index - 1].requestFocus();
      } else {
        _searchFocusNode.requestFocus();
      }
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (index < _autocompleteFocusNodes.length - 1) {
        _autocompleteFocusNodes[index + 1].requestFocus();
      } else {
        // Last autocomplete item - navigate to Season box if series is selected
        if (_isSeries && _selectedImdbTitle != null) {
          _seasonInputFocusNode.requestFocus();
        }
      }
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.select ||
        event.logicalKey == LogicalKeyboardKey.enter) {
      _onImdbResultSelected(_imdbAutocompleteResults[index]);
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.escape ||
        event.logicalKey == LogicalKeyboardKey.goBack) {
      setState(() {
        _imdbAutocompleteResults.clear();
      });
      _searchFocusNode.requestFocus();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  // Handle D-pad navigation for season dropdown
  KeyEventResult _handleSeasonDropdownKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final hasSeasonData = _availableSeasons != null && _availableSeasons!.isNotEmpty;

    // Open custom season picker dialog on Select/Enter/Space
    if (event.logicalKey == LogicalKeyboardKey.select ||
        event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.space) {
      debugPrint('Season dropdown: Opening custom picker dialog');
      _showSeasonPickerDialog();
      return KeyEventResult.handled;
    }

    // Arrow Down -> Episode field (if visible) or first result card
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      // If episode input is visible, navigate to it
      if (_selectedSeason != null && hasSeasonData) {
        _episodeInputFocusNode.requestFocus();
      } else if (_torrents.isNotEmpty && _cardFocusNodes.isNotEmpty) {
        // Navigate to first result card
        _cardFocusNodes[0].requestFocus();
        setState(() {
          _focusedCardIndex = 0;
        });
      }
      return KeyEventResult.handled;
    }

    // Arrow Up or Escape/Back -> Search field
    if (event.logicalKey == LogicalKeyboardKey.arrowUp ||
        event.logicalKey == LogicalKeyboardKey.escape ||
        event.logicalKey == LogicalKeyboardKey.goBack) {
      _searchFocusNode.requestFocus();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  // Show custom season picker dialog (TV-compatible)
  void _showSeasonPickerDialog() {
    if (_availableSeasons == null || _availableSeasons!.isEmpty) return;

    showDialog<int?>(
      context: context,
      builder: (BuildContext context) {
        return SimpleDialog(
          title: const Text('Select Season'),
          backgroundColor: const Color(0xFF1E293B),
          children: [
            // "All Seasons" option
            SimpleDialogOption(
              onPressed: () {
                Navigator.pop(context, null);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12.0),
                child: Text(
                  'All Seasons',
                  style: TextStyle(
                    fontSize: 14,
                    color: _selectedSeason == null
                        ? const Color(0xFF7C3AED)
                        : Colors.white,
                    fontWeight: _selectedSeason == null
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
              ),
            ),
            // Individual seasons
            ..._availableSeasons!.map((season) {
              return SimpleDialogOption(
                onPressed: () {
                  Navigator.pop(context, season);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12.0),
                  child: Text(
                    'Season $season',
                    style: TextStyle(
                      fontSize: 14,
                      color: _selectedSeason == season
                          ? const Color(0xFF7C3AED)
                          : Colors.white,
                      fontWeight: _selectedSeason == season
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                ),
              );
            }).toList(),
          ],
        );
      },
    ).then((selectedValue) {
      if (selectedValue != _selectedSeason) {
        setState(() {
          _selectedSeason = selectedValue;
          _episodeController.clear();
        });
        _createAdvancedSelectionAndSearch();
      }
    });
  }

  KeyEventResult _handleSeasonInputKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    // Arrow Right or Arrow Down -> Episode field
    if (event.logicalKey == LogicalKeyboardKey.arrowRight ||
        event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _episodeInputFocusNode.requestFocus();
      return KeyEventResult.handled;
    }

    // Arrow Up or Escape/Back -> Search field
    if (event.logicalKey == LogicalKeyboardKey.arrowUp ||
        event.logicalKey == LogicalKeyboardKey.escape ||
        event.logicalKey == LogicalKeyboardKey.goBack) {
      _searchFocusNode.requestFocus();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  KeyEventResult _handleEpisodeInputKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    // Arrow Left or Arrow Up -> Season field
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
        event.logicalKey == LogicalKeyboardKey.arrowUp) {
      _seasonInputFocusNode.requestFocus();
      return KeyEventResult.handled;
    }

    // Arrow Down -> Navigate to first torrent result if available
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (_cardFocusNodes.isNotEmpty) {
        _cardFocusNodes[0].requestFocus();
        return KeyEventResult.handled;
      }
    }

    // Escape/Back -> Search field
    if (event.logicalKey == LogicalKeyboardKey.escape ||
        event.logicalKey == LogicalKeyboardKey.goBack) {
      _searchFocusNode.requestFocus();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  // Build active IMDB selection chip
  Widget _buildImdbSelectionChip() {
    // Removed - chip takes up too much space
    return const SizedBox.shrink();
  }

  // Build movie/series type selector and S/E inputs
  Widget _buildImdbTypeAndEpisodeControls() {
    if (_selectedImdbTitle == null) {
      return const SizedBox.shrink();
    }

    // For movies: hide when collapsed
    // For series: never hide (we show either the expandable button or full controls)
    if (_imdbControlsCollapsed && !_isSeries) {
      return const SizedBox.shrink();
    }

    // Show loading indicator while fetching title details
    if (_isImdbSearching) {
      return Container(
        margin: const EdgeInsets.only(top: 8, bottom: 8),
        padding: const EdgeInsets.all(12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(
                  const Color(0xFF7C3AED),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'Detecting title type...',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    // Show error message if present
    if (_imdbSearchError != null) {
      return Container(
        margin: const EdgeInsets.only(top: 8, bottom: 8),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: Colors.red.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.error_outline,
              size: 16,
              color: Colors.red,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _imdbSearchError!,
                style: TextStyle(
                  color: Colors.red,
                  fontSize: 13,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 5,
              ),
            ),
          ],
        ),
      );
    }

    // For movies, don't show controls at all
    if (!_isSeries) {
      return const SizedBox.shrink();
    }

    // For series, show season dropdown and conditional episode input
    // If we don't have season data from API, fall back to text inputs
    final bool hasSeasonData = _availableSeasons != null && _availableSeasons!.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (hasSeasonData) ...[
                // Season dropdown (when API data is available)
                SizedBox(
                  width: 120, // Fixed width matching episode input
                  height: 44, // Fixed height for consistency
                  child: ValueListenableBuilder<bool>(
                    valueListenable: _seasonInputFocused,
                    builder: (context, isFocused, child) => Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF2D3B5F), // Distinct purple-blue background
                        border: Border.all(
                          color: isFocused
                              ? const Color(0xFF7C3AED)
                              : Colors.white.withValues(alpha: 0.3),
                          width: isFocused ? 2 : 1,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: child,
                    ),
                    child: Focus(
                      focusNode: _seasonInputFocusNode,
                      onFocusChange: (focused) {
                        _seasonInputFocused.value = focused; // No setState needed!
                      },
                      onKeyEvent: (node, event) => _handleSeasonDropdownKeyEvent(event),
                      child: InkWell(
                        onTap: _showSeasonPickerDialog,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  _selectedSeason == null
                                      ? 'All Seasons'
                                      : 'Season $_selectedSeason',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: _selectedSeason == null
                                        ? Colors.white.withValues(alpha: 0.7)
                                        : Colors.white,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Icon(
                                Icons.arrow_drop_down,
                                color: Colors.white.withValues(alpha: 0.7),
                                size: 18,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ] else ...[
                // Fallback: Season text input (when API data is not available)
                SizedBox(
                  width: 120, // Same width as dropdown version
                  height: 44, // Same height for consistency
                  child: Focus(
                    onKeyEvent: (node, event) => _handleSeasonInputKeyEvent(event),
                    child: TextField(
                      focusNode: _seasonInputFocusNode,
                      controller: _seasonController,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(fontSize: 12), // Match dropdown font size
                      decoration: InputDecoration(
                        labelText: 'Season',
                        labelStyle: const TextStyle(fontSize: 12),
                        isDense: true,
                        filled: true, // Add background color
                        fillColor: const Color(0xFF2D3B5F), // Same purple-blue as dropdown
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(
                            color: Colors.white.withValues(alpha: 0.3),
                            width: 1,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(
                            color: Color(0xFF7C3AED),
                            width: 2,
                          ),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10, // Match dropdown padding
                          vertical: 10, // Adjusted for same height
                        ),
                      ),
                      onChanged: (_) {
                        _createAdvancedSelectionAndSearch();
                      },
                    ),
                  ),
                ),
              ],
              const SizedBox(width: 8),
              // Episode input - only show when specific season is selected (not "All Seasons")
              if (!hasSeasonData || _selectedSeason != null)
                Container(
                  width: 120, // Same width as season dropdown
                  height: 44, // Same height for consistency
                  constraints: const BoxConstraints(
                    minWidth: 120,
                    maxWidth: 120,
                    minHeight: 44,
                    maxHeight: 44,
                  ),
                  child: Focus(
                    onKeyEvent: (node, event) => _handleEpisodeInputKeyEvent(event),
                    child: TextField(
                      focusNode: _episodeInputFocusNode,
                      controller: _episodeController,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(fontSize: 12), // Match dropdown font size
                      decoration: InputDecoration(
                        hintText: hasSeasonData ? 'Episode' : 'Episode',
                        hintStyle: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withValues(alpha: 0.6),
                        ),
                        isDense: true,
                        filled: true,
                        fillColor: const Color(0xFF1E293B),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(
                            color: Colors.white.withValues(alpha: 0.3),
                            width: 1,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(
                            color: Color(0xFF7C3AED),
                            width: 2,
                          ),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 12,
                        ),
                      ),
                      onChanged: (_) {
                        _createAdvancedSelectionAndSearch();
                      },
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProvidersAccordion(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: _providerAccordionFocused,
      builder: (context, isFocused, child) => Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B).withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isFocused
                ? const Color(0xFF3B82F6).withValues(alpha: 0.6)
                : const Color(0xFF3B82F6).withValues(alpha: 0.2),
            width: isFocused ? 2 : 1,
          ),
        ),
        child: child,
      ),
      child: Column(
        children: [
          FocusableActionDetector(
            focusNode: _providerAccordionFocusNode,
            onShowFocusHighlight: (focused) {
              _providerAccordionFocused.value = focused; // No setState needed!
            },
            shortcuts: _activateShortcuts,
            actions: <Type, Action<Intent>>{
              ActivateIntent: CallbackAction<ActivateIntent>(
                onInvoke: (intent) {
                  setState(() => _showProvidersPanel = !_showProvidersPanel);
                  return null;
                },
              ),
            },
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              canRequestFocus: false,
              onTap: () =>
                  setState(() => _showProvidersPanel = !_showProvidersPanel),
              child: ValueListenableBuilder<bool>(
                valueListenable: _providerAccordionFocused,
                builder: (context, isFocused, child) => Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: isFocused
                        ? const Color(0xFF3B82F6).withValues(alpha: 0.15)
                        : Colors.transparent,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: child,
                ),
                child: Row(
                  children: [
                    Icon(
                      _showProvidersPanel
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Search Providers (${_engineStates.values.where((enabled) => enabled).length})',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _availableEngines.map((engine) {
                      final engineId = engine.name;
                      final focusNode = _engineTileFocusNodes[engineId];
                      final isEnabled = _engineStates[engineId] ?? false;
                      final isFocused = _engineTileFocusStates[engineId] ?? false;

                      return _buildProviderSwitch(
                        context,
                        label: engine.displayName,
                        value: isEnabled,
                        onToggle: (value) => _setEngineEnabled(engineId, value),
                        tileFocusNode: focusNode ?? FocusNode(),
                        tileFocused: isFocused,
                        onFocusChange: (visible) {
                          if (_engineTileFocusStates[engineId] != visible) {
                            setState(() {
                              _engineTileFocusStates[engineId] = visible;
                            });
                          }
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),
                  _buildAdvancedProviderHint(context),
                ],
              ),
            ),
            crossFadeState: _showProvidersPanel
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 220),
          ),
        ],
      ),
    );
  }

  Widget _buildAdvancedProviderHint(BuildContext context) {
    // Show different hints based on search mode
    final String hintText;
    final IconData hintIcon;
    final Color hintColor;

    if (_searchMode == SearchMode.imdb) {
      hintText = 'IMDB mode shows only engines that support IMDB search (like Torrentio). Switch to Keyword mode to see all engines.';
      hintIcon = Icons.info_outline_rounded;
      hintColor = const Color(0xFF7C3AED);
    } else {
      hintText = 'Need IMDb-accurate results? Switch to IMDB mode to search with IMDB IDs, seasons, and episodes.';
      hintIcon = Icons.auto_awesome_rounded;
      hintColor = const Color(0xFFFACC15);
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1F2937),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: hintColor.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(
            hintIcon,
            color: hintColor,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              hintText,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.white.withValues(alpha: 0.8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProviderSwitch(
    BuildContext context, {
    required String label,
    required bool value,
    required ValueChanged<bool> onToggle,
    required FocusNode tileFocusNode,
    required bool tileFocused,
    required ValueChanged<bool> onFocusChange,
  }) {
    return FocusableActionDetector(
      focusNode: tileFocusNode,
      shortcuts: _activateShortcuts,
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (intent) {
            onToggle(!value);
            return null;
          },
        ),
      },
      onShowFocusHighlight: onFocusChange,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: value
              ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.6)
              : Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
          border: Border.all(
            color: tileFocused
                ? Theme.of(context).colorScheme.primary
                : value
                    ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.3)
                    : Colors.transparent,
            width: tileFocused ? 2 : 1,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          canRequestFocus: false,
          onTap: () => onToggle(!value),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  value ? Icons.check_circle : Icons.circle_outlined,
                  size: 18,
                  color: value
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    label,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: value
                          ? Theme.of(context).colorScheme.onPrimaryContainer
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                      fontWeight: value ? FontWeight.w600 : FontWeight.normal,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _copyMagnetLink(String infohash) {
    final magnetLink = 'magnet:?xt=urn:btih:$infohash';
    Clipboard.setData(ClipboardData(text: magnetLink));

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.tertiary,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.check,
                color: Theme.of(context).colorScheme.onTertiary,
                size: 16,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Magnet link copied to clipboard!',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
        backgroundColor: Theme.of(context).colorScheme.surface,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _sortTorrents({
    List<Torrent>? nextBase,
    Map<String, _TorrentMetadata>? metadataOverride,
    bool reuseMetadata = false, // Skip expensive metadata rebuilding when only sort changes
  }) {
    Timeline.startSync('TorrentSearchScreen.sortTorrents');
    final List<Torrent> baseList = nextBase ?? _allTorrents;
    final Map<String, _TorrentMetadata> metadata =
        metadataOverride ??
        (reuseMetadata
            ? _torrentMetadata // Reuse existing parsed metadata
            : (nextBase != null
                ? _buildTorrentMetadataMap(baseList)
                : _torrentMetadata));

    final List<Torrent> sortedTorrents = List<Torrent>.from(baseList);

    // Determine if we should apply season pack prioritization
    // Only apply for TV series searches when episode is NOT specified
    // When episode IS specified, we prioritize single episodes instead
    final bool isSeries = _activeAdvancedSelection?.isSeries ?? false;
    final bool hasEpisode = _activeAdvancedSelection?.episode != null;
    final bool shouldApplyCoveragePriority = isSeries && !hasEpisode;
    final bool shouldPrioritizeSingleEpisode = isSeries && hasEpisode;

    debugPrint('TorrentSearchScreen: Sorting torrents - isSeries=$isSeries, hasEpisode=$hasEpisode, '
        'shouldApplyCoveragePriority=$shouldApplyCoveragePriority, shouldPrioritizeSingleEpisode=$shouldPrioritizeSingleEpisode, '
        'season=${_activeAdvancedSelection?.season}, episode=${_activeAdvancedSelection?.episode}, title=${_activeAdvancedSelection?.title}');

    switch (_sortBy) {
      case 'name':
        sortedTorrents.sort((a, b) {
          // Primary: coverage type prioritization
          if (shouldApplyCoveragePriority) {
            // Prefer season packs (lower priority number = higher rank)
            final coverageComp = a.coveragePriority.compareTo(b.coveragePriority);
            if (coverageComp != 0) return coverageComp;
          } else if (shouldPrioritizeSingleEpisode) {
            // Prefer single episodes (higher priority number = higher rank)
            final coverageComp = b.coveragePriority.compareTo(a.coveragePriority);
            if (coverageComp != 0) return coverageComp;
          }

          // Secondary: name
          final comparison = a.displayTitle.toLowerCase().compareTo(
            b.displayTitle.toLowerCase(),
          );
          return _sortAscending ? comparison : -comparison;
        });
        break;
      case 'size':
        sortedTorrents.sort((a, b) {
          // Primary: coverage type prioritization
          if (shouldApplyCoveragePriority) {
            // Prefer season packs (lower priority number = higher rank)
            final coverageComp = a.coveragePriority.compareTo(b.coveragePriority);
            if (coverageComp != 0) return coverageComp;
          } else if (shouldPrioritizeSingleEpisode) {
            // Prefer single episodes (higher priority number = higher rank)
            final coverageComp = b.coveragePriority.compareTo(a.coveragePriority);
            if (coverageComp != 0) return coverageComp;
          }

          // Secondary: size
          final comparison = a.sizeBytes.compareTo(b.sizeBytes);
          return _sortAscending ? comparison : -comparison;
        });
        break;
      case 'seeders':
        sortedTorrents.sort((a, b) {
          // Primary: coverage type prioritization
          if (shouldApplyCoveragePriority) {
            // Prefer season packs (lower priority number = higher rank)
            final coverageComp = a.coveragePriority.compareTo(b.coveragePriority);
            if (coverageComp != 0) return coverageComp;
          } else if (shouldPrioritizeSingleEpisode) {
            // Prefer single episodes (higher priority number = higher rank)
            final coverageComp = b.coveragePriority.compareTo(a.coveragePriority);
            if (coverageComp != 0) return coverageComp;
          }

          // Secondary: seeders
          final comparison = a.seeders.compareTo(b.seeders);
          return _sortAscending ? comparison : -comparison;
        });
        break;
      case 'date':
        sortedTorrents.sort((a, b) {
          // Primary: coverage type prioritization
          if (shouldApplyCoveragePriority) {
            // Prefer season packs (lower priority number = higher rank)
            final coverageComp = a.coveragePriority.compareTo(b.coveragePriority);
            if (coverageComp != 0) return coverageComp;
          } else if (shouldPrioritizeSingleEpisode) {
            // Prefer single episodes (higher priority number = higher rank)
            final coverageComp = b.coveragePriority.compareTo(a.coveragePriority);
            if (coverageComp != 0) return coverageComp;
          }

          // Secondary: date
          final comparison = a.createdUnix.compareTo(b.createdUnix);
          return _sortAscending ? comparison : -comparison;
        });
        break;
      case 'relevance':
      default:
        // Sort by coverage type first, then maintain original order
        sortedTorrents.sort((a, b) {
          // Primary: coverage type prioritization
          if (shouldApplyCoveragePriority) {
            // Prefer season packs (lower priority number = higher rank)
            final coverageComp = a.coveragePriority.compareTo(b.coveragePriority);
            if (coverageComp != 0) return coverageComp;
          } else if (shouldPrioritizeSingleEpisode) {
            // Prefer single episodes (higher priority number = higher rank)
            final coverageComp = b.coveragePriority.compareTo(a.coveragePriority);
            if (coverageComp != 0) return coverageComp;
          }

          // Secondary: seeders (best quality indicator for relevance)
          return b.seeders.compareTo(a.seeders);
        });
        break;
    }

    final filtered = _applyFiltersToList(sortedTorrents, metadataMap: metadata);

    // Debug: Log top 3 results to understand sorting
    if (sortedTorrents.isNotEmpty) {
      debugPrint('TorrentSearchScreen: Top 3 results after sorting:');
      for (int i = 0; i < sortedTorrents.length && i < 3; i++) {
        final t = sortedTorrents[i];
        debugPrint('  $i: ${t.name} - coveragePriority=${t.coveragePriority}, coverageType=${t.coverageType}, seeders=${t.seeders}');
      }
    }

    setState(() {
      _allTorrents = sortedTorrents;
      _torrentMetadata = metadata;
      _torrents = filtered;
      _ensureFocusNodes();
    });

    // Auto-focus first result on TV after search
    if (_isTelevision && _cardFocusNodes.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _cardFocusNodes.isNotEmpty) {
          _cardFocusNodes[0].requestFocus();
        }
      });
    }
    Timeline.finishSync();
  }

  List<Torrent> _applyFiltersToList(
    List<Torrent> source, {
    TorrentFilterState? filtersOverride,
    Map<String, _TorrentMetadata>? metadataMap,
  }) {
    final TorrentFilterState activeFilters = filtersOverride ?? _filters;

    // First apply engine filter if active
    List<Torrent> engineFiltered = source;
    if (_selectedEngineFilter != null) {
      engineFiltered = source
          .where((torrent) => torrent.source == _selectedEngineFilter)
          .toList();
    }

    // Then apply other filters
    if (activeFilters.isEmpty) {
      return List<Torrent>.from(engineFiltered);
    }

    final meta = metadataMap ?? _torrentMetadata;
    return engineFiltered
        .where((torrent) {
          final info = meta[torrent.infohash];
          if (activeFilters.qualities.isNotEmpty) {
            final tier = info?.qualityTier;
            if (tier == null || !activeFilters.qualities.contains(tier)) {
              return false;
            }
          }
          if (activeFilters.ripSources.isNotEmpty) {
            final rip = info?.ripSource ?? RipSourceCategory.other;
            if (!activeFilters.ripSources.contains(rip)) {
              return false;
            }
          }
          if (activeFilters.languages.isNotEmpty) {
            final lang = info?.audioLanguage;
            if (lang == null || !activeFilters.languages.contains(lang)) {
              return false;
            }
          }
          return true;
        })
        .toList(growable: false);
  }

  void _applyEngineFilter() {
    // Re-apply filters and sorting with the new engine filter
    final filtered = _applyFiltersToList(_allTorrents, metadataMap: _torrentMetadata);
    setState(() {
      _torrents = filtered;
      _ensureFocusNodes();
    });
  }

  Map<String, _TorrentMetadata> _buildTorrentMetadataMap(
    List<Torrent> torrents,
  ) {
    final map = <String, _TorrentMetadata>{};
    for (final torrent in torrents) {
      final info = SeriesParser.parseFilename(torrent.name);
      map[torrent.infohash] = _TorrentMetadata(
        seriesInfo: info,
        qualityTier: _detectQualityTier(info.quality, torrent.name),
        ripSource: _detectRipSource(torrent.name),
        audioLanguage: _detectAudioLanguage(torrent.name),
      );
    }
    return map;
  }

  QualityTier? _detectQualityTier(String? parsedQuality, String rawName) {
    final normalized = '$rawName ${parsedQuality ?? ''}'.toLowerCase();
    if (normalized.contains('2160') ||
        normalized.contains('4k') ||
        normalized.contains('uhd')) {
      return QualityTier.ultraHd;
    }
    if (normalized.contains('1080')) {
      return QualityTier.fullHd;
    }
    if (normalized.contains('720')) {
      return QualityTier.hd;
    }
    if (normalized.contains('480') ||
        normalized.contains('360') ||
        normalized.contains('sd') ||
        normalized.contains('cam')) {
      return QualityTier.sd;
    }
    return null;
  }

  RipSourceCategory _detectRipSource(String rawName) {
    final lower = rawName.toLowerCase();
    if (_matchesAny(lower, ['bluray', 'blu-ray', 'bdrip', 'brrip', 'remux'])) {
      return RipSourceCategory.bluRay;
    }
    if (_matchesAny(lower, [
      'webrip',
      'web-dl',
      'webdl',
      'webhd',
      'webmux',
      'web ',
      'amzn',
      'nf.web',
    ])) {
      return RipSourceCategory.web;
    }
    if (_matchesAny(lower, ['hdrip', 'hdtv', 'ppv', 'dsr'])) {
      return RipSourceCategory.hdrip;
    }
    if (_matchesAny(lower, ['dvdrip', 'dvd-rip', 'dvdscr', 'dvd'])) {
      return RipSourceCategory.dvdrip;
    }
    final camRegex = RegExp(r'\b(cam|hdcam|camrip|telesync|ts|tc)\b');
    if (camRegex.hasMatch(lower)) {
      return RipSourceCategory.cam;
    }
    return RipSourceCategory.other;
  }

  AudioLanguage? _detectAudioLanguage(String rawName) {
    final lower = rawName.toLowerCase();
    // Multi-audio detection first (takes priority)
    if (_matchesAny(lower, [
      'multi-audio',
      'multi audio',
      'multiaudio',
      'dual-audio',
      'dual audio',
      'dualaudio',
      'multi-lang',
      'multilang',
    ])) {
      return AudioLanguage.multiAudio;
    }
    // Individual language detection
    if (RegExp(r'\b(hindi|hin)\b').hasMatch(lower)) {
      return AudioLanguage.hindi;
    }
    if (RegExp(r'\b(spanish|spa|esp|latino|castellano)\b').hasMatch(lower)) {
      return AudioLanguage.spanish;
    }
    if (RegExp(r'\b(french|fra|fre|vf|vff|vfq)\b').hasMatch(lower)) {
      return AudioLanguage.french;
    }
    if (RegExp(r'\b(german|ger|deu|german\.dts)\b').hasMatch(lower)) {
      return AudioLanguage.german;
    }
    if (RegExp(r'\b(russian|rus)\b').hasMatch(lower)) {
      return AudioLanguage.russian;
    }
    if (RegExp(r'\b(chinese|chi|chs|cht|mandarin|cantonese)\b').hasMatch(lower)) {
      return AudioLanguage.chinese;
    }
    if (RegExp(r'\b(japanese|jap|jpn)\b').hasMatch(lower)) {
      return AudioLanguage.japanese;
    }
    if (RegExp(r'\b(korean|kor)\b').hasMatch(lower)) {
      return AudioLanguage.korean;
    }
    if (RegExp(r'\b(italian|ita)\b').hasMatch(lower)) {
      return AudioLanguage.italian;
    }
    if (RegExp(r'\b(portuguese|por|pt-br)\b').hasMatch(lower)) {
      return AudioLanguage.portuguese;
    }
    if (RegExp(r'\b(arabic|ara)\b').hasMatch(lower)) {
      return AudioLanguage.arabic;
    }
    if (RegExp(r'\b(english|eng)\b').hasMatch(lower)) {
      return AudioLanguage.english;
    }
    return null; // Unknown/not specified
  }

  bool _matchesAny(String source, List<String> needles) {
    for (final needle in needles) {
      if (source.contains(needle)) {
        return true;
      }
    }
    return false;
  }

  Future<void> _openFiltersSheet() async {
    if (_allTorrents.isEmpty && !_hasActiveFilters) return;

    final result = await showDialog<TorrentFilterState>(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        child: TorrentFiltersSheet(initialState: _filters),
      ),
    );

    if (result == null || result == _filters) return;

    setState(() {
      _filters = result;
      _torrents = _applyFiltersToList(
        _allTorrents,
        filtersOverride: result,
        metadataMap: _torrentMetadata,
      );
      _ensureFocusNodes();
    });
  }

  void _clearAllFilters() {
    if (!_hasActiveFilters) return;
    setState(() {
      _filters = const TorrentFilterState.empty();
      _torrents = List<Torrent>.from(_allTorrents);
      _ensureFocusNodes();
    });
  }

  List<String> _buildActiveFilterBadges() {
    final badges = <String>[];
    for (final tier in _filters.qualities) {
      badges.add('Quality · ${_qualityLabel(tier)}');
    }
    for (final source in _filters.ripSources) {
      badges.add('Source · ${_ripLabel(source)}');
    }
    for (final lang in _filters.languages) {
      badges.add('Language · ${_languageLabel(lang)}');
    }
    return badges;
  }

  String _qualityLabel(QualityTier tier) {
    switch (tier) {
      case QualityTier.ultraHd:
        return '4K / UHD';
      case QualityTier.fullHd:
        return '1080p';
      case QualityTier.hd:
        return '720p';
      case QualityTier.sd:
        return '480p & below';
    }
  }

  String _ripLabel(RipSourceCategory category) {
    switch (category) {
      case RipSourceCategory.web:
        return 'WEB / WEB-DL';
      case RipSourceCategory.bluRay:
        return 'BluRay';
      case RipSourceCategory.hdrip:
        return 'HDRip / HDTV';
      case RipSourceCategory.dvdrip:
        return 'DVDRip';
      case RipSourceCategory.cam:
        return 'CAM / TS';
      case RipSourceCategory.other:
        return 'Other';
    }
  }

  String _languageLabel(AudioLanguage language) {
    switch (language) {
      case AudioLanguage.english:
        return 'English';
      case AudioLanguage.hindi:
        return 'Hindi';
      case AudioLanguage.spanish:
        return 'Spanish';
      case AudioLanguage.french:
        return 'French';
      case AudioLanguage.german:
        return 'German';
      case AudioLanguage.russian:
        return 'Russian';
      case AudioLanguage.chinese:
        return 'Chinese';
      case AudioLanguage.japanese:
        return 'Japanese';
      case AudioLanguage.korean:
        return 'Korean';
      case AudioLanguage.italian:
        return 'Italian';
      case AudioLanguage.portuguese:
        return 'Portuguese';
      case AudioLanguage.arabic:
        return 'Arabic';
      case AudioLanguage.multiAudio:
        return 'Multi-Audio';
    }
  }

  Future<void> _sendToPikPak(String infohash, String torrentName) async {
    try {
      final magnet = 'magnet:?xt=urn:btih:$infohash&dn=${Uri.encodeComponent(torrentName)}';

      final pikpak = PikPakApiService.instance;

      // Show loading dialog with progress
      String? fileId;
      String? taskId;
      int progress = 0;
      bool cancelled = false;
      bool showingTimeoutOptions = false;
      final startTime = DateTime.now();

      // Get parent folder ID (restricted folder or root)
      final parentFolderId = await StorageService.getPikPakRestrictedFolderId();

      // Find or create "debrify-torrents" subfolder
      String? subFolderId;
      try {
        subFolderId = await pikpak.findOrCreateSubfolder(
          folderName: 'debrify-torrents',
          parentFolderId: parentFolderId,
          getCachedId: StorageService.getPikPakTorrentsFolderId,
          setCachedId: StorageService.setPikPakTorrentsFolderId,
        );
        print('PikPak: Using subfolder ID: $subFolderId');
      } catch (e) {
        // Check if this is the restricted folder deleted error
        if (e.toString().contains('RESTRICTED_FOLDER_DELETED')) {
          print('PikPak: Detected restricted folder was deleted');
          await _handlePikPakRestrictedFolderDeleted();
          return;
        }
        print('PikPak: Failed to create subfolder, using parent folder: $e');
        subFolderId = parentFolderId;
      }

      // Add to PikPak first
      final addResult = await pikpak.addOfflineDownload(
        magnet,
        parentFolderId: subFolderId,
      );
      print('PikPak: addOfflineDownload response: $addResult');

      // Extract file ID and task ID
      if (addResult['file'] != null) {
        fileId = addResult['file']['id'];
      } else if (addResult['task'] != null) {
        fileId = addResult['task']['file_id'];
      } else if (addResult['id'] != null) {
        fileId = addResult['id'];
      }

      // Extract task ID for tracking download progress
      if (addResult['task'] != null) {
        taskId = addResult['task']['id'];
        print('PikPak: Extracted task_id: $taskId');
      }

      if (fileId == null) {
        throw Exception('Could not get file ID from PikPak');
      }

      print('PikPak: Extracted file_id: $fileId, task_id: $taskId');

      // Add to search history after successful addition to PikPak
      final torrent = _findTorrentByInfohash(infohash, torrentName);
      await _saveToHistory(torrent, 'pikpak');

      if (!mounted) return;

      // Show loading dialog and start polling
      bool pollingStarted = false;

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              // Start polling only once
              if (!pollingStarted && !cancelled) {
                pollingStarted = true;
                _pollPikPakStatus(
                  fileId!,
                  taskId,
                  torrentName,
                  torrent,
                  dialogContext,
                  setDialogState,
                  startTime,
                  (p) {
                    if (mounted) setDialogState(() => progress = p);
                  },
                  () => cancelled,
                  (show) {
                    if (mounted) setDialogState(() => showingTimeoutOptions = show);
                  },
                );
              }

              final elapsed = DateTime.now().difference(startTime);
              final showTakingLonger = elapsed.inSeconds > 30 && !showingTimeoutOptions;

              return AlertDialog(
                backgroundColor: const Color(0xFF0F172A),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                title: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFAA00).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.cloud_sync, color: Color(0xFFFFAA00), size: 20),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Processing on PikPak',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      torrentName,
                      maxLines: 5,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (!showingTimeoutOptions) ...[
                      LinearProgressIndicator(
                        value: progress > 0 ? progress / 100 : null,
                        backgroundColor: Colors.white.withValues(alpha: 0.1),
                        valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFFFAA00)),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        progress > 0 ? 'Downloading: $progress%' : 'Checking status...',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                          fontSize: 12,
                        ),
                      ),
                      if (showTakingLonger) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Taking longer than expected...',
                          style: TextStyle(
                            color: Colors.orange.withValues(alpha: 0.8),
                            fontSize: 12,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ] else ...[
                      const Text(
                        'This torrent is taking a while. What would you like to do?',
                        style: TextStyle(fontSize: 14),
                      ),
                    ],
                  ],
                ),
                actions: showingTimeoutOptions
                    ? [
                        TextButton(
                          autofocus: true,
                          onPressed: () {
                            setDialogState(() {
                              showingTimeoutOptions = false;
                            });
                          },
                          child: const Text('Keep Waiting'),
                        ),
                        TextButton(
                          onPressed: () {
                            cancelled = true;
                            Navigator.of(dialogContext).pop();
                            _showPikPakSnack('You can find it in PikPak Files later');
                          },
                          child: const Text('View Later'),
                        ),
                        TextButton(
                          onPressed: () {
                            cancelled = true;
                            Navigator.of(dialogContext).pop();
                          },
                          style: TextButton.styleFrom(foregroundColor: Colors.red.shade400),
                          child: const Text('Cancel'),
                        ),
                      ]
                    : [
                        TextButton(
                          autofocus: true,
                          onPressed: () {
                            cancelled = true;
                            Navigator.of(dialogContext).pop();
                            _showPikPakSnack('Added to PikPak. You can find it in PikPak Files.');
                          },
                          child: const Text('Run in Background'),
                        ),
                      ],
              );
            },
          );
        },
      );
    } catch (e) {
      print('Error sending to PikPak: $e');
      if (!mounted) return;

      // Check if the error is because the restricted folder was deleted
      final folderExists =
          await PikPakApiService.instance.verifyRestrictedFolderExists();
      if (!folderExists) {
        // Restricted folder was deleted - auto logout
        await _handlePikPakRestrictedFolderDeleted();
        return;
      }

      _showPikPakSnack('Failed: ${e.toString()}', isError: true);
    }
  }

  /// Handle the case when PikPak restricted folder has been deleted externally
  Future<void> _handlePikPakRestrictedFolderDeleted() async {
    print(
      'PikPak: Restricted folder was deleted externally, logging out user...',
    );

    // Logout from PikPak
    await PikPakApiService.instance.logout();

    if (!mounted) return;

    // Show error message
    _showPikPakSnack(
      'Restricted folder was deleted. You have been logged out.',
      isError: true,
    );
  }

  /// Show bulk add provider selection dialog
  Future<void> _showBulkAddDialog() async {
    final List<Widget> options = [];

    // Add Torbox option (greyed out/disabled)
    options.add(
      ListTile(
        leading: const Icon(Icons.flash_on_rounded, color: Color(0xFF7C3AED)),
        title: const Text('TorBox', style: TextStyle(color: Colors.white)),
        subtitle: const Text('Coming soon', style: TextStyle(color: Colors.white54, fontSize: 12)),
        enabled: false,
        onTap: null,
      ),
    );

    // Add Real-Debrid option (greyed out/disabled)
    options.add(
      ListTile(
        leading: const Icon(Icons.cloud_rounded, color: Color(0xFFE50914)),
        title: const Text('Real-Debrid', style: TextStyle(color: Colors.white)),
        subtitle: const Text('Coming soon', style: TextStyle(color: Colors.white54, fontSize: 12)),
        enabled: false,
        onTap: null,
      ),
    );

    // Add PikPak option (enabled if configured)
    if (_pikpakEnabled) {
      options.add(
        ListTile(
          leading: const Icon(Icons.folder_rounded, color: Color(0xFF0088CC)),
          title: const Text('PikPak', style: TextStyle(color: Colors.white)),
          onTap: () => Navigator.of(context).pop('pikpak'),
        ),
      );
    } else {
      options.add(
        ListTile(
          leading: const Icon(Icons.folder_rounded, color: Color(0xFF0088CC)),
          title: const Text('PikPak', style: TextStyle(color: Colors.white)),
          subtitle: const Text('Not configured', style: TextStyle(color: Colors.white54, fontSize: 12)),
          enabled: false,
          onTap: null,
        ),
      );
    }

    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF0F172A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF6366F1).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.playlist_add, color: Color(0xFF6366F1), size: 20),
            ),
            const SizedBox(width: 12),
            const Text(
              'Bulk Add Torrents',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 18),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Add all ${_torrents.length} torrents to:',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 16),
            ...options,
          ],
        ),
      ),
    );

    if (result == 'pikpak') {
      _bulkAddToPikPak();
    }
  }

  /// Bulk add all torrents to PikPak with batching and progress tracking
  Future<void> _bulkAddToPikPak() async {
    if (_torrents.isEmpty) return;

    setState(() {
      _isBulkAdding = true;
    });

    final pikpak = PikPakApiService.instance;
    final totalTorrents = _torrents.length;
    int successCount = 0;
    int failureCount = 0;
    int currentIndex = 0;
    bool cancelled = false;

    // Track status of each torrent
    final Map<String, String> torrentStatus = {};
    for (final torrent in _torrents) {
      torrentStatus[torrent.infohash] = 'pending';
    }

    try {
      // Get or create the debrify-torrents subfolder once
      final parentFolderId = await StorageService.getPikPakRestrictedFolderId();
      String? subFolderId;

      try {
        subFolderId = await pikpak.findOrCreateSubfolder(
          folderName: 'debrify-torrents',
          parentFolderId: parentFolderId,
          getCachedId: StorageService.getPikPakTorrentsFolderId,
          setCachedId: StorageService.setPikPakTorrentsFolderId,
        );
        print('PikPak Bulk: Using subfolder ID: $subFolderId');
      } catch (e) {
        if (e.toString().contains('RESTRICTED_FOLDER_DELETED')) {
          await _handlePikPakRestrictedFolderDeleted();
          setState(() {
            _isBulkAdding = false;
          });
          return;
        }
        print('PikPak Bulk: Failed to create subfolder, using parent folder: $e');
        subFolderId = parentFolderId;
      }

      if (!mounted) return;

      // Capture the dialog state setter for use in async operations
      StateSetter? dialogSetState;

      // Show progress dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              // Capture the setDialogState for async operations
              dialogSetState = setDialogState;

              return AlertDialog(
                backgroundColor: const Color(0xFF0F172A),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                ),
                title: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFAA00).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.cloud_upload, color: Color(0xFFFFAA00), size: 20),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Adding to PikPak',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                content: SizedBox(
                  width: double.maxFinite,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LinearProgressIndicator(
                        value: totalTorrents > 0 ? currentIndex / totalTorrents : 0,
                        backgroundColor: Colors.white.withValues(alpha: 0.1),
                        valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFFFAA00)),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Progress: $currentIndex of $totalTorrents',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981).withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.check_circle, color: Color(0xFF10B981), size: 14),
                                const SizedBox(width: 4),
                                Text(
                                  'Success: $successCount',
                                  style: const TextStyle(
                                    color: Color(0xFF10B981),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEF4444).withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.error, color: Color(0xFFEF4444), size: 14),
                                const SizedBox(width: 4),
                                Text(
                                  'Failed: $failureCount',
                                  style: const TextStyle(
                                    color: Color(0xFFEF4444),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Container(
                        constraints: const BoxConstraints(maxHeight: 200),
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: _torrents.length,
                          itemBuilder: (context, index) {
                            final torrent = _torrents[index];
                            final status = torrentStatus[torrent.infohash] ?? 'pending';

                            IconData icon;
                            Color iconColor;

                            if (status == 'success') {
                              icon = Icons.check_circle;
                              iconColor = const Color(0xFF10B981);
                            } else if (status == 'error') {
                              icon = Icons.error;
                              iconColor = const Color(0xFFEF4444);
                            } else if (status == 'processing') {
                              icon = Icons.hourglass_empty;
                              iconColor = const Color(0xFFFFAA00);
                            } else {
                              icon = Icons.circle_outlined;
                              iconColor = Colors.white54;
                            }

                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Row(
                                children: [
                                  Icon(icon, color: iconColor, size: 16),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      torrent.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: Colors.white.withValues(alpha: 0.7),
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      cancelled = true;
                      Navigator.of(dialogContext).pop();
                    },
                    child: const Text('Cancel'),
                  ),
                ],
              );
            },
          );
        },
      );

      // Process torrents in batches of 3 concurrent requests
      const batchSize = 3;

      for (int i = 0; i < _torrents.length && !cancelled; i += batchSize) {
        final batchEnd = (i + batchSize).clamp(0, _torrents.length);
        final batch = _torrents.sublist(i, batchEnd);

        // Process batch concurrently
        await Future.wait(
          batch.map((torrent) async {
            if (cancelled) return;

            try {
              // Update status to processing
              if (mounted) {
                dialogSetState?.call(() {
                  torrentStatus[torrent.infohash] = 'processing';
                  currentIndex++;
                });
              }

              final magnet = 'magnet:?xt=urn:btih:${torrent.infohash}&dn=${Uri.encodeComponent(torrent.name)}';

              await pikpak.addOfflineDownload(
                magnet,
                parentFolderId: subFolderId,
              );

              // Update status to success
              if (mounted) {
                dialogSetState?.call(() {
                  torrentStatus[torrent.infohash] = 'success';
                  successCount++;
                });
              }

              print('PikPak Bulk: Successfully added ${torrent.name}');
            } catch (e) {
              // Update status to error
              if (mounted) {
                dialogSetState?.call(() {
                  torrentStatus[torrent.infohash] = 'error';
                  failureCount++;
                });
              }

              print('PikPak Bulk: Failed to add ${torrent.name}: $e');
            }
          }),
        );

        // Small delay between batches to avoid overwhelming the API
        if (i + batchSize < _torrents.length && !cancelled) {
          await Future.delayed(const Duration(milliseconds: 500));
        }
      }

      // Close progress dialog
      if (mounted) {
        Navigator.of(context).pop();
      }

      // Show summary
      if (!cancelled && mounted) {
        if (successCount > 0 && failureCount == 0) {
          _showPikPakSnack('Successfully added $successCount/${totalTorrents} torrents to PikPak');
        } else if (successCount > 0 && failureCount > 0) {
          _showPikPakSnack(
            'Added $successCount/${totalTorrents} torrents. $failureCount failed.',
            isError: true,
          );
        } else {
          _showPikPakSnack('Failed to add torrents to PikPak', isError: true);
        }
      }
    } catch (e) {
      print('Error in bulk add to PikPak: $e');

      if (mounted) {
        Navigator.of(context).pop();

        // Check if the error is because the restricted folder was deleted
        final folderExists = await PikPakApiService.instance.verifyRestrictedFolderExists();
        if (!folderExists) {
          await _handlePikPakRestrictedFolderDeleted();
          return;
        }

        _showPikPakSnack('Bulk add failed: ${e.toString()}', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isBulkAdding = false;
        });
      }
    }
  }

  Future<void> _pollPikPakStatus(
    String fileId,
    String? taskId,
    String torrentName,
    Torrent torrent,
    BuildContext dialogContext,
    StateSetter setDialogState,
    DateTime startTime,
    Function(int) onProgress,
    bool Function() isCancelled,
    Function(bool) setShowTimeoutOptions,
  ) async {
    final pikpak = PikPakApiService.instance;
    const pollInterval = Duration(seconds: 2);
    const timeoutShowOptions = Duration(seconds: 60);
    const extraTimeFor100Percent = Duration(seconds: 10);

    // Phase 1: Poll TASK status until progress >= 90% (if taskId available)
    if (taskId != null) {
      print('PikPak: Starting task-based polling for taskId: $taskId');
      DateTime? reached90PercentTime;

      while (!isCancelled()) {
        await Future.delayed(pollInterval);
        if (isCancelled() || !mounted) return;

        // Check if we should show timeout options
        final elapsed = DateTime.now().difference(startTime);
        if (elapsed > timeoutShowOptions) {
          setShowTimeoutOptions(true);
          return;
        }

        try {
          final taskData = await pikpak.getTaskStatus(taskId);
          final taskPhase = taskData['phase'];
          final taskProgress = taskData['progress'];

          // Update progress from task
          if (taskProgress != null) {
            try {
              final p = taskProgress is int ? taskProgress : int.parse(taskProgress.toString());
              print('PikPak: Task progress: $p%, phase: $taskPhase');
              onProgress(p);

              // Check if task is complete
              if (taskPhase == 'PHASE_TYPE_COMPLETE') {
                print('PikPak: Task completed (100%), proceeding to file scanning');
                break;
              }

              // Check if task failed
              if (taskPhase == 'PHASE_TYPE_ERROR') {
                if (!mounted) return;
                Navigator.of(dialogContext).pop();
                _showPikPakSnack('Download failed on PikPak', isError: true);
                return;
              }

              // Track when we first reach 90%
              if (p >= 90 && reached90PercentTime == null) {
                print('PikPak: Reached 90%, giving ${extraTimeFor100Percent.inSeconds} extra seconds for completion');
                reached90PercentTime = DateTime.now();
              }

              // If at 90%+, check if extra time has elapsed
              if (reached90PercentTime != null) {
                final timeSince90 = DateTime.now().difference(reached90PercentTime);
                if (timeSince90 >= extraTimeFor100Percent) {
                  print('PikPak: Extra time for 100% elapsed ($p%), proceeding with file scanning anyway');
                  break;
                }
              }
            } catch (_) {
              print('PikPak: Could not parse task progress: $taskProgress');
            }
          }
        } catch (e) {
          print('PikPak: Task polling error: $e');
          // If task API fails, fall back to file-based polling
          print('PikPak: Falling back to file-based polling');
          break;
        }
      }

      if (isCancelled() || !mounted) return;
    } else {
      print('PikPak: No taskId available, using file-based polling');
    }

    // Phase 2: Now check file status and extract videos
    // (Either task reached 90%+ or we fell back to file-based polling)
    print('PikPak: Starting file status check for fileId: $fileId');

    while (!isCancelled()) {
      await Future.delayed(pollInterval);
      if (isCancelled() || !mounted) return;

      // Check if we should show timeout options
      final elapsed = DateTime.now().difference(startTime);
      if (elapsed > timeoutShowOptions) {
        setShowTimeoutOptions(true);
        return;
      }

      try {
        final fileData = await pikpak.getFileDetails(fileId);
        final phase = fileData['phase'];
        final kind = fileData['kind'];

        // Update progress from file (fallback if task polling didn't work)
        final progressValue = fileData['progress'];
        if (progressValue != null) {
          try {
            final p = progressValue is int ? progressValue : int.parse(progressValue.toString());
            onProgress(p);
          } catch (_) {}
        }

        // Check if complete
        if (phase == 'PHASE_TYPE_COMPLETE') {
          if (!mounted) return;
          Navigator.of(dialogContext).pop();

          // Get all video files (recursively from all folders)
          List<Map<String, dynamic>> videoFiles = [];

          print('PikPak: Download complete. kind=$kind, fileId=$fileId');

          if (kind == 'drive#folder') {
            // It's a folder (torrent pack), recursively extract all videos
            print('PikPak: It is a folder, starting recursive extraction...');
            videoFiles = await _extractAllPikPakVideos(pikpak, fileId);
            print('PikPak: Recursive extraction found ${videoFiles.length} videos');
          } else {
            // Single file
            final mimeType = fileData['mime_type'] ?? '';
            print('PikPak: It is a single file. mimeType=$mimeType');
            if (mimeType.startsWith('video/')) {
              videoFiles = [fileData];
            }
          }

          print('PikPak: Final video count: ${videoFiles.length}');
          if (!mounted) return;

          // If no videos found, PikPak might still be processing the torrent files
          if (videoFiles.isEmpty && kind == 'drive#folder') {
            _showPikPakSnack(
              'Files still processing on PikPak. Check PikPak Files later.',
            );
            return;
          }

          await _showPikPakPostAddOptions(torrentName, fileId, videoFiles, torrent);
          return;
        }

        // Check if failed
        if (phase == 'PHASE_TYPE_ERROR') {
          if (!mounted) return;
          Navigator.of(dialogContext).pop();
          _showPikPakSnack('Download failed on PikPak', isError: true);
          return;
        }
      } catch (e) {
        print('PikPak polling error: $e');
        // Continue polling on error
      }
    }
  }

  Future<void> _showPikPakPostAddOptions(
    String torrentName,
    String fileId,
    List<Map<String, dynamic>> videoFiles,
    Torrent torrent,
  ) async {
    if (!mounted) return;

    final hasVideo = videoFiles.isNotEmpty;
    final postAction = await StorageService.getPikPakPostTorrentAction();
    final pikpakHidden = await StorageService.getPikPakHiddenFromNav();

    // For PikPak, we only extract video files, so if we have videos, we can enable video-only actions
    // Note: PikPak filtering already ensures only video files are in videoFiles list
    final isVideoOnly = videoFiles.isNotEmpty;

    // Handle automatic actions based on preference
    switch (postAction) {
      case 'none':
        // Show confirmation that torrent was added
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.check, color: Colors.white, size: 16),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Torrent added to PikPak successfully',
                    style: TextStyle(fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF1E293B),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            margin: const EdgeInsets.all(16),
            duration: const Duration(seconds: 3),
          ),
        );
        return;
      case 'open':
        // Open in PikPak tab
        MainPageBridge.openPikPakFolder?.call(fileId, torrentName);
        return;
      case 'playlist':
        // Add to playlist
        if (hasVideo) {
          _addPikPakToPlaylist(videoFiles, torrentName, fileId);
        }
        return;
      case 'channel':
        // Add to channel
        final keyword = _searchController.text.trim();
        await _addTorrentToChannel(torrent, keyword);
        return;
      case 'play':
        if (hasVideo) {
          _playPikPakVideos(videoFiles, torrentName);
          return;
        }
        // Fall through to 'choose' if no video
        break;
      case 'download':
        if (isVideoOnly) {
          // Auto-download all videos without dialog
          _downloadPikPakFiles(fileId, torrentName);
          return;
        }
        // Fall through to 'choose' if not video-only
        break;
      case 'choose':
      default:
        // Show the dialog
        break;
    }

    await showDialog(
      context: context,
      builder: (ctx) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Container(
              color: const Color(0xFF0F172A),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 12),
                  Container(
                    width: 42,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFFFFAA00), Color(0xFFFF6600)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Icon(Icons.cloud_done_rounded, color: Colors.white),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                torrentName,
                                maxLines: 5,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                hasVideo
                                    ? 'Ready on PikPak. ${videoFiles.length} video${videoFiles.length > 1 ? 's' : ''} found.'
                                    : 'Ready on PikPak. No videos detected.',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.6),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(ctx).pop(),
                          icon: const Icon(Icons.close_rounded, color: Colors.white54),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1, color: Color(0xFF1E293B)),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _DebridActionTile(
                            icon: Icons.open_in_new,
                            color: const Color(0xFFF59E0B),
                            title: 'Open in PikPak',
                            subtitle: 'View folder in PikPak files tab',
                            enabled: true,
                            autofocus: true,
                            onTap: () {
                              Navigator.of(ctx).pop();
                              // Navigate to the specific PikPak folder
                              MainPageBridge.openPikPakFolder?.call(fileId, torrentName);
                            },
                          ),
                          _DebridActionTile(
                            icon: Icons.play_circle_fill_rounded,
                            color: const Color(0xFF60A5FA),
                            title: 'Play now',
                            subtitle: hasVideo
                                ? 'Stream instantly from PikPak.'
                                : 'No video files found.',
                            enabled: hasVideo,
                            autofocus: false,
                            onTap: () {
                              Navigator.of(ctx).pop();
                              _playPikPakVideos(videoFiles, torrentName);
                            },
                          ),
                          _DebridActionTile(
                            icon: Icons.download_rounded,
                            color: const Color(0xFF4ADE80),
                            title: 'Download to device',
                            subtitle: 'Grab files from PikPak instantly.',
                            enabled: true,
                            onTap: () {
                              Navigator.of(ctx).pop();
                              _downloadPikPakFiles(fileId, torrentName);
                            },
                          ),
                          _DebridActionTile(
                            icon: Icons.playlist_add_rounded,
                            color: const Color(0xFFA855F7),
                            title: 'Add to playlist',
                            subtitle: hasVideo
                                ? 'Save for later viewing.'
                                : 'Available for video files only.',
                            enabled: hasVideo,
                            onTap: () {
                              Navigator.of(ctx).pop();
                              _addPikPakToPlaylist(videoFiles, torrentName, fileId);
                            },
                          ),
                          _DebridActionTile(
                            icon: Icons.connected_tv,
                            color: const Color(0xFF10B981),
                            title: 'Add to channel',
                            subtitle: 'Cache this torrent in a Debrify TV channel.',
                            enabled: true,
                            onTap: () {
                              Navigator.of(ctx).pop();
                              final keyword = _searchController.text.trim();
                              _addTorrentToChannel(torrent, keyword);
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('Close', style: TextStyle(color: Colors.white54)),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// Handle PikPak post-action for external magnet links
  Future<void> _showPikPakPostAddOptionsFromExternal(
    String fileId,
    String fileName,
  ) async {
    if (!mounted) return;

    final postAction = await StorageService.getPikPakPostTorrentAction();
    final pikpakHidden = await StorageService.getPikPakHiddenFromNav();

    // For 'none' action, just show success
    if (postAction == 'none') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.check, color: Colors.white, size: 16),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Torrent added to PikPak successfully',
                  style: TextStyle(fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
          backgroundColor: const Color(0xFF1E293B),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          margin: const EdgeInsets.all(16),
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }

    // For 'open' action, open PikPak folder directly
    if (postAction == 'open') {
      MainPageBridge.openPikPakFolder?.call(fileId, fileName);
      return;
    }

    // For video-related actions (playlist, play, download, choose), fetch folder contents
    List<Map<String, dynamic>> videoFiles = [];
    try {
      final pikpak = PikPakApiService.instance;
      final allFiles = await pikpak.listFilesRecursive(folderId: fileId);
      videoFiles = allFiles.where((file) {
        final name = (file['name'] as String?) ?? '';
        final kind = (file['kind'] as String?) ?? '';
        return kind != 'drive#folder' && FileUtils.isVideoFile(name);
      }).toList();
    } catch (e) {
      debugPrint('PikPak: Failed to list files for post-action: $e');
    }

    final hasVideo = videoFiles.isNotEmpty;

    // Handle specific actions
    switch (postAction) {
      case 'playlist':
        if (hasVideo) {
          _addPikPakToPlaylist(videoFiles, fileName, fileId);
        } else {
          _showPikPakNoVideosSnack();
        }
        return;
      case 'play':
        if (hasVideo) {
          _playPikPakVideos(videoFiles, fileName);
        } else {
          _showPikPakNoVideosSnack();
        }
        return;
      case 'download':
        if (hasVideo) {
          _downloadPikPakFiles(fileId, fileName);
        } else {
          _showPikPakNoVideosSnack();
        }
        return;
      case 'choose':
      default:
        // Show dialog with options
        break;
    }

    // Show choose dialog
    await showDialog(
      context: context,
      builder: (ctx) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Container(
              color: const Color(0xFF0F172A),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 12),
                  Container(
                    width: 42,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFFFFAA00), Color(0xFFFF6600)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Icon(Icons.cloud_done_rounded, color: Colors.white),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                fileName,
                                maxLines: 5,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                hasVideo
                                    ? 'Ready on PikPak. ${videoFiles.length} video${videoFiles.length > 1 ? 's' : ''} found.'
                                    : 'Ready on PikPak. No videos detected.',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.6),
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1, color: Color(0xFF1E293B)),
                  // Action buttons
                  _DebridActionTile(
                    icon: Icons.open_in_new,
                    color: const Color(0xFFF59E0B),
                    title: 'Open in PikPak',
                    subtitle: 'View folder in PikPak files tab',
                    enabled: true,
                    autofocus: true,
                    onTap: () {
                      Navigator.of(ctx).pop();
                      MainPageBridge.openPikPakFolder?.call(fileId, fileName);
                    },
                  ),
                  _DebridActionTile(
                    icon: Icons.play_circle_fill_rounded,
                    color: const Color(0xFF60A5FA),
                    title: 'Play now',
                    subtitle: hasVideo
                        ? 'Stream instantly from PikPak.'
                        : 'No video files found.',
                    enabled: hasVideo,
                    autofocus: false,
                    onTap: () {
                      Navigator.of(ctx).pop();
                      _playPikPakVideos(videoFiles, fileName);
                    },
                  ),
                  _DebridActionTile(
                    icon: Icons.download_rounded,
                    color: const Color(0xFF4ADE80),
                    title: 'Download to device',
                    subtitle: 'Grab files from PikPak instantly.',
                    enabled: true,
                    onTap: () {
                      Navigator.of(ctx).pop();
                      _downloadPikPakFiles(fileId, fileName);
                    },
                  ),
                  _DebridActionTile(
                    icon: Icons.playlist_add_rounded,
                    color: const Color(0xFFA78BFA),
                    title: 'Add to Playlist',
                    subtitle: hasVideo
                        ? 'Save for later playback.'
                        : 'No video files to add.',
                    enabled: hasVideo,
                    onTap: () {
                      Navigator.of(ctx).pop();
                      _addPikPakToPlaylist(videoFiles, fileName, fileId);
                    },
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showPikPakNoVideosSnack() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('No video files found in this torrent'),
        backgroundColor: Colors.orange,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  Future<void> _playPikPakVideos(List<Map<String, dynamic>> videoFiles, String torrentName) async {
    if (videoFiles.isEmpty) return;

    final pikpak = PikPakApiService.instance;

    // Single video - play with playlist entry for consistent resume key
    if (videoFiles.length == 1) {
      final file = videoFiles.first;
      try {
        final fullData = await pikpak.getFileDetails(file['id']);
        final url = pikpak.getStreamingUrl(fullData);
        if (url != null && mounted) {
          // Launch player immediately - retry logic will handle cold storage
          final sizeBytes = int.tryParse(file['size']?.toString() ?? '0') ?? 0;
          final title = file['name'] ?? torrentName;
          await VideoPlayerLauncher.push(
            context,
            VideoPlayerLaunchArgs(
              videoUrl: url,
              title: title,
              subtitle: Formatters.formatFileSize(sizeBytes),
              playlist: [
                PlaylistEntry(
                  url: url,
                  title: title,
                  provider: 'pikpak',
                  pikpakFileId: file['id'],
                  sizeBytes: sizeBytes,
                ),
              ],
              startIndex: 0,
              viewMode: PlaylistViewMode.sorted, // Single file - not series
            ),
          );
        }
      } catch (e) {
        _showPikPakSnack('Failed to play: ${e.toString()}', isError: true);
      }
      return;
    }

    // Multiple videos - build playlist like Torbox
    final entries = <_PikPakPlaylistItem>[];
    for (int i = 0; i < videoFiles.length; i++) {
      final file = videoFiles[i];
      final displayName = _pikpakDisplayName(file);
      final info = SeriesParser.parseFilename(displayName);
      entries.add(_PikPakPlaylistItem(
        file: file,
        originalIndex: i,
        seriesInfo: info,
        displayName: displayName,
      ));
    }

    // Detect if it's a series collection
    final filenames = entries.map((e) => e.displayName).toList();
    final bool isSeriesCollection =
        entries.length > 1 && SeriesParser.isSeriesPlaylist(filenames);

    // Sort entries
    final sortedEntries = [...entries];
    if (isSeriesCollection) {
      sortedEntries.sort((a, b) {
        final aInfo = a.seriesInfo;
        final bInfo = b.seriesInfo;
        final seasonCompare = (aInfo.season ?? 0).compareTo(bInfo.season ?? 0);
        if (seasonCompare != 0) return seasonCompare;
        final episodeCompare = (aInfo.episode ?? 0).compareTo(bInfo.episode ?? 0);
        if (episodeCompare != 0) return episodeCompare;
        return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
      });
    } else {
      sortedEntries.sort(
        (a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
      );
    }

    // Find first episode to start from
    final seriesInfos = sortedEntries.map((e) => e.seriesInfo).toList();
    int startIndex = isSeriesCollection ? _findFirstEpisodeIndex(seriesInfos) : 0;
    if (startIndex < 0 || startIndex >= sortedEntries.length) {
      startIndex = 0;
    }

    // Resolve only the first video URL (lazy loading for rest)
    String initialUrl = '';
    try {
      final firstFile = sortedEntries[startIndex].file;
      final fullData = await pikpak.getFileDetails(firstFile['id']);
      initialUrl = pikpak.getStreamingUrl(fullData) ?? '';
    } catch (e) {
      _showPikPakSnack('Failed to prepare stream: ${e.toString()}', isError: true);
      return;
    }

    if (initialUrl.isEmpty) {
      _showPikPakSnack('Could not get streaming URL', isError: true);
      return;
    }

    // Launch player immediately - retry logic will handle cold storage for all videos
    // Build playlist entries
    final playlistEntries = <PlaylistEntry>[];
    for (int i = 0; i < sortedEntries.length; i++) {
      final entry = sortedEntries[i];
      final seriesInfo = entry.seriesInfo;
      final episodeLabel = _formatPikPakPlaylistTitle(
        info: seriesInfo,
        fallback: entry.displayName,
        isSeriesCollection: isSeriesCollection,
      );
      final combinedTitle = _combineSeriesAndEpisodeTitle(
        seriesTitle: seriesInfo.title,
        episodeLabel: episodeLabel,
        isSeriesCollection: isSeriesCollection,
        fallback: entry.displayName,
      );
      playlistEntries.add(PlaylistEntry(
        url: i == startIndex ? initialUrl : '',
        title: combinedTitle,
        provider: 'pikpak',
        pikpakFileId: entry.file['id'],
        sizeBytes: int.tryParse(entry.file['size']?.toString() ?? '0'),
      ));
    }

    // Calculate subtitle
    final totalBytes = sortedEntries.fold<int>(
      0,
      (sum, e) => sum + (int.tryParse(e.file['size']?.toString() ?? '0') ?? 0),
    );
    final subtitle =
        '${playlistEntries.length} ${isSeriesCollection ? 'episodes' : 'files'} • ${Formatters.formatFileSize(totalBytes)}';

    if (!mounted) return;
    await VideoPlayerLauncher.push(
      context,
      VideoPlayerLaunchArgs(
        videoUrl: initialUrl,
        title: torrentName,
        subtitle: subtitle,
        playlist: playlistEntries,
        startIndex: startIndex,
        viewMode: isSeriesCollection ? PlaylistViewMode.series : PlaylistViewMode.sorted,
      ),
    );
  }

  String _pikpakDisplayName(Map<String, dynamic> file) {
    final name = file['name']?.toString() ?? '';
    if (name.isNotEmpty) {
      return FileUtils.getFileName(name);
    }
    return 'File ${file['id']}';
  }

  String _formatPikPakPlaylistTitle({
    required SeriesInfo info,
    required String fallback,
    required bool isSeriesCollection,
  }) {
    if (!isSeriesCollection) {
      return fallback;
    }

    final season = info.season;
    final episode = info.episode;
    if (info.isSeries && season != null && episode != null) {
      final seasonLabel = season.toString().padLeft(2, '0');
      final episodeLabel = episode.toString().padLeft(2, '0');
      final description = info.episodeTitle?.trim().isNotEmpty == true
          ? info.episodeTitle!.trim()
          : info.title?.trim().isNotEmpty == true
          ? info.title!.trim()
          : fallback;
      return 'S${seasonLabel}E$episodeLabel · $description';
    }

    return fallback;
  }

  Future<void> _addPikPakToPlaylist(List<Map<String, dynamic>> videoFiles, String torrentName, String folderId) async {
    if (videoFiles.isEmpty) {
      _showPikPakSnack('No video files to add', isError: true);
      return;
    }

    if (videoFiles.length == 1) {
      final file = videoFiles.first;
      final added = await StorageService.addPlaylistItemRaw({
        'provider': 'pikpak',
        'title': FileUtils.cleanPlaylistTitle(file['name'] ?? torrentName),
        'kind': 'single',
        'pikpakFileId': file['id'],
        // Store full metadata for instant playback
        'pikpakFile': {
          'id': file['id'],
          'name': file['name'],
          'size': file['size'],
          'mime_type': file['mime_type'],
        },
        'sizeBytes': int.tryParse(file['size']?.toString() ?? '0'),
      });
      _showPikPakSnack(added ? 'Added to playlist' : 'Already in playlist', isError: !added);
    } else {
      // Save as collection with full metadata for instant playback
      final fileIds = videoFiles.map((f) => f['id'] as String).toList();
      final filesMetadata = videoFiles.map((f) => {
        'id': f['id'],
        'name': f['name'],
        'size': f['size'],
        'mime_type': f['mime_type'],
      }).toList();

      final added = await StorageService.addPlaylistItemRaw({
        'provider': 'pikpak',
        'title': FileUtils.cleanPlaylistTitle(torrentName),
        'kind': 'collection',
        'pikpakFileId': folderId,       // Store the folder ID for folder structure preservation
        'pikpakFiles': filesMetadata,  // NEW: Full metadata for instant playback
        'pikpakFileIds': fileIds,       // KEEP: For backward compatibility and deduplication
        'count': videoFiles.length,
      });
      _showPikPakSnack(
        added ? 'Added ${videoFiles.length} videos to playlist' : 'Already in playlist',
        isError: !added,
      );
    }
  }

  Future<void> _downloadPikPakFiles(String fileId, String torrentName) async {
    // Show selection dialog for downloading files
    if (!mounted) return;

    final pikpak = PikPakApiService.instance;

    // Show loading dialog while we fetch the file structure
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text(
              'Scanning files...',
              style: TextStyle(color: Colors.white),
            ),
          ],
        ),
      ),
    );

    try {
      // Get all files from the folder (recursively)
      final fileData = await pikpak.getFileDetails(fileId);
      final kind = fileData['kind'];
      List<Map<String, dynamic>> allFiles = [];

      if (kind == 'drive#folder') {
        // Extract all files recursively
        allFiles = await _extractAllPikPakFiles(pikpak, fileId);
      } else {
        // Single file
        allFiles = [fileData];
      }

      // Close loading dialog
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }

      if (allFiles.isEmpty) {
        _showPikPakSnack('No files found to download', isError: true);
        return;
      }

      // Show file selection dialog
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (BuildContext context) {
          return FileSelectionDialog(
            files: allFiles,
            torrentName: torrentName,
            onDownload: (selectedFiles) {
              if (selectedFiles.isEmpty) return;
              _downloadSelectedPikPakFiles(selectedFiles, torrentName);
            },
          );
        },
      );
    } catch (e) {
      // Close loading dialog if still open
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      _showPikPakSnack('Failed to fetch files: $e', isError: true);
    }
  }

  /// Downloads selected files from PikPak with folder grouping (similar to Real-Debrid)
  Future<void> _downloadSelectedPikPakFiles(List<Map<String, dynamic>> files, String torrentName) async {
    if (files.isEmpty) return;

    int successCount = 0;
    int failCount = 0;
    final pikpak = PikPakApiService.instance;

    // Show loading dialog
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              'Preparing ${files.length} file${files.length > 1 ? 's' : ''}...',
              style: const TextStyle(color: Colors.white),
            ),
          ],
        ),
      ),
    );

    for (final file in files) {
      try {
        final fileId = file['id'] as String?;
        if (fileId == null) continue;

        // Get fresh file details with download URL
        final freshFileData = await pikpak.getFileDetails(fileId);
        final downloadUrl = freshFileData['web_content_link'] as String?;

        if (downloadUrl == null || downloadUrl.isEmpty) {
          failCount++;
          continue;
        }

        // Extract file path and name - use the full path if available (from folder navigation)
        final fullPath = file['_fullPath'] as String? ?? file['name'] as String? ?? 'download';
        final displayName = file['_displayName'] as String? ?? file['name'] as String? ?? 'download';

        // Create metadata with folder structure info (similar to Real-Debrid pattern)
        final meta = jsonEncode({
          'pikpakDownload': true,
          'pikpakFileId': fileId,
          'pikpakFileName': fullPath,  // Store full path for folder structure
          'pikpakDisplayName': displayName,  // Display name for UI
        });

        // Enqueue download with torrentName for grouping (like Real-Debrid does)
        // This groups all files under the same torrent name in the downloads screen
        await DownloadService.instance.enqueueDownload(
          url: downloadUrl,
          fileName: displayName,  // Use display name (just the filename, not the full path)
          meta: meta,
          torrentName: torrentName,  // KEY: This groups downloads under the torrent folder
          context: mounted ? context : null,
        );
        successCount++;
      } catch (e) {
        print('Error queueing file for download: $e');
        failCount++;
      }
    }

    // Close loading dialog
    if (mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }

    if (successCount > 0) {
      _showPikPakSnack('Queued $successCount file${successCount > 1 ? 's' : ''} for download');
    }
    if (failCount > 0) {
      _showPikPakSnack('Failed to queue $failCount file${failCount > 1 ? 's' : ''}', isError: true);
    }
  }

  /// Recursively extract all files (not just videos) from a PikPak folder
  /// Preserves folder structure by prefixing file names with their relative path
  Future<List<Map<String, dynamic>>> _extractAllPikPakFiles(
    PikPakApiService pikpak,
    String folderId, {
    int maxDepth = 5,
    int currentDepth = 0,
    String currentPath = '',  // Track the current folder path
  }) async {
    if (currentDepth >= maxDepth) {
      return [];
    }

    final List<Map<String, dynamic>> files = [];

    try {
      final result = await pikpak.listFiles(parentId: folderId);
      final items = result.files;

      for (final item in items) {
        final kind = item['kind'] ?? '';
        final itemName = item['name'] ?? 'unknown';

        if (kind == 'drive#folder') {
          // Build the path for this subfolder
          final subPath = currentPath.isEmpty ? itemName : '$currentPath/$itemName';

          // Recursively scan subfolder with updated path
          final subFiles = await _extractAllPikPakFiles(
            pikpak,
            item['id'],
            maxDepth: maxDepth,
            currentDepth: currentDepth + 1,
            currentPath: subPath,
          );
          files.addAll(subFiles);
        } else {
          // It's a file - add folder path to the file name
          final fileWithPath = Map<String, dynamic>.from(item);
          if (currentPath.isNotEmpty) {
            // Prefix the file name with its folder path
            fileWithPath['name'] = '$currentPath/$itemName';
          }
          files.add(fileWithPath);
        }
      }
    } catch (e) {
      print('Error extracting PikPak files: $e');
    }

    return files;
  }

  void _showPikPakSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isError ? const Color(0xFFEF4444) : const Color(0xFF22C55E),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                isError ? Icons.error : Icons.check_circle,
                color: Colors.white,
                size: 16,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(message, style: const TextStyle(fontWeight: FontWeight.w500)),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF1E293B),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: Duration(seconds: isError ? 4 : 3),
      ),
    );
  }

  /// Add torrent to a Debrify TV channel
  Future<void> _addTorrentToChannel(Torrent torrent, String searchKeyword) async {
    if (!mounted) return;

    // Validate keyword is not empty
    final normalizedKeyword = searchKeyword.trim().toLowerCase();
    debugPrint('[AddToChannel] Original keyword: "$searchKeyword", Normalized: "$normalizedKeyword"');

    if (normalizedKeyword.isEmpty) {
      debugPrint('[AddToChannel] ERROR: Empty keyword, aborting');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot add torrent: search keyword is empty'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    try {
      // Show channel picker dialog
      final result = await showDialog<ChannelPickerResult>(
        context: context,
        builder: (ctx) => ChannelPickerDialog(
          searchKeyword: searchKeyword,
        ),
      );

      if (result == null || !mounted) return;

      debugPrint('[AddToChannel] Selected channel: ${result.channelName} (${result.channelId}), isNew: ${result.isNewChannel}');

      // Fetch channel once to avoid duplicate queries
      final channel = (await DebrifyTvRepository.instance.fetchAllChannels())
          .firstWhere(
            (ch) => ch.channelId == result.channelId,
            orElse: () => throw Exception('Channel no longer exists'),
          );

      debugPrint('[AddToChannel] Channel fetched. Current keywords: ${channel.keywords}');

      // Get current cache entry for this channel
      var cacheEntry = await DebrifyTvCacheService.getEntry(result.channelId);
      debugPrint('[AddToChannel] Cache entry exists: ${cacheEntry != null}, Torrent count: ${cacheEntry?.torrents.length ?? 0}');

      // If cache entry doesn't exist, create empty one
      if (cacheEntry == null) {
        debugPrint('[AddToChannel] Creating new cache entry with warming status');
        cacheEntry = DebrifyTvChannelCacheEntry.empty(
          channelId: result.channelId,
          normalizedKeywords: channel.keywords.map((k) => k.toLowerCase()).toList(),
          status: DebrifyTvCacheStatus.warming,
        );
      }

      // Convert Torrent to CachedTorrent with validated source
      final cachedTorrent = CachedTorrent.fromTorrent(
        torrent,
        keywords: [normalizedKeyword],
        sources: torrent.source.isNotEmpty ? [torrent.source] : [],
      );
      debugPrint('[AddToChannel] Created CachedTorrent: ${torrent.name} (${torrent.infohash}), source: "${torrent.source}"');

      // Check if torrent already exists in cache
      final existingIndex = cacheEntry.torrents.indexWhere(
        (t) => t.infohash == cachedTorrent.infohash,
      );
      debugPrint('[AddToChannel] Torrent exists in cache: ${existingIndex >= 0} (index: $existingIndex)');

      List<CachedTorrent> updatedTorrents;
      if (existingIndex >= 0) {
        // Merge with existing torrent (adds keyword if not present)
        debugPrint('[AddToChannel] Merging with existing torrent, adding keyword: "$normalizedKeyword"');
        final merged = cacheEntry.torrents[existingIndex].merge(
          keywords: [normalizedKeyword],
        );
        updatedTorrents = List.from(cacheEntry.torrents);
        updatedTorrents[existingIndex] = merged;
      } else {
        // Add new torrent to the beginning
        debugPrint('[AddToChannel] Adding new torrent to cache');
        updatedTorrents = [cachedTorrent, ...cacheEntry.torrents];
      }

      // Update channel keywords if search keyword is new
      final channelKeywords = List<String>.from(channel.keywords);
      debugPrint('[AddToChannel] Checking if keyword exists. Channel keywords: $channelKeywords');

      final keywordExists = channelKeywords.any(
        (kw) => kw.toLowerCase() == normalizedKeyword,
      );
      debugPrint('[AddToChannel] Keyword "$normalizedKeyword" exists: $keywordExists');

      if (!keywordExists) {
        debugPrint('[AddToChannel] Adding keyword "$searchKeyword" to channel keywords');
        channelKeywords.add(searchKeyword);

        // Update channel record with new keyword
        final updatedChannel = channel.copyWith(
          keywords: channelKeywords,
          updatedAt: DateTime.now(),
        );
        debugPrint('[AddToChannel] Updating channel with new keywords: $channelKeywords');
        await DebrifyTvRepository.instance.upsertChannel(updatedChannel);
        debugPrint('[AddToChannel] Channel updated successfully');
      } else {
        debugPrint('[AddToChannel] Keyword already exists, skipping channel update');
      }

      // Update cache entry with new torrents
      final normalizedChannelKeywords = channelKeywords.map((k) => k.toLowerCase()).toList();
      debugPrint('[AddToChannel] Preparing cache update. Normalized keywords: $normalizedChannelKeywords, Torrent count: ${updatedTorrents.length}');

      final updatedEntry = cacheEntry.copyWith(
        torrents: updatedTorrents,
        normalizedKeywords: normalizedChannelKeywords,
        status: DebrifyTvCacheStatus.ready,
      );

      // Save updated cache
      debugPrint('[AddToChannel] Saving cache entry...');
      await DebrifyTvCacheService.saveEntry(updatedEntry);
      debugPrint('[AddToChannel] Cache saved successfully');

      if (!mounted) return;

      final successMessage = existingIndex >= 0
          ? 'Torrent updated in "${result.channelName}"'
          : result.isNewChannel
              ? 'Channel "${result.channelName}" created with torrent!'
              : 'Torrent added to "${result.channelName}"';
      debugPrint('[AddToChannel] SUCCESS: $successMessage');

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(successMessage),
          backgroundColor: const Color(0xFF10B981),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      debugPrint('[AddToChannel] ERROR: $e');
      debugPrint('[AddToChannel] Stack trace: ${StackTrace.current}');

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to add torrent to channel: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  /// Recursively extract all video files from a PikPak folder and its subfolders
  /// Preserves folder structure by prefixing file names with their relative path
  Future<List<Map<String, dynamic>>> _extractAllPikPakVideos(
    PikPakApiService pikpak,
    String folderId, {
    int maxDepth = 5,
    int currentDepth = 0,
    String currentPath = '',  // Track the current folder path
  }) async {
    if (currentDepth >= maxDepth) {
      print('PikPak: Max depth reached at $currentDepth');
      return [];
    }

    final List<Map<String, dynamic>> videos = [];

    try {
      print('PikPak: Scanning folder $folderId (depth: $currentDepth)');
      final result = await pikpak.listFiles(parentId: folderId);
      final files = result.files;
      print('PikPak: Found ${files.length} items in folder');

      for (final file in files) {
        final kind = file['kind'] ?? '';
        final mimeType = file['mime_type'] ?? '';
        final itemName = file['name'] ?? 'unknown';

        print('PikPak: Item: $itemName, kind: $kind, mime: $mimeType');

        if (kind == 'drive#folder') {
          // Build the path for this subfolder
          final subPath = currentPath.isEmpty ? itemName : '$currentPath/$itemName';

          // Recursively scan subfolder with updated path
          print('PikPak: Entering subfolder: $itemName');
          final subVideos = await _extractAllPikPakVideos(
            pikpak,
            file['id'],
            maxDepth: maxDepth,
            currentDepth: currentDepth + 1,
            currentPath: subPath,
          );
          print('PikPak: Found ${subVideos.length} videos in subfolder: $itemName');
          videos.addAll(subVideos);
        } else if (mimeType.startsWith('video/')) {
          // It's a video file - add folder path to the file name
          print('PikPak: Found video: $itemName');
          final videoWithPath = Map<String, dynamic>.from(file);
          if (currentPath.isNotEmpty) {
            // Prefix the file name with its folder path
            videoWithPath['name'] = '$currentPath/$itemName';
          }
          videos.add(videoWithPath);
        }
      }
    } catch (e) {
      print('Error extracting PikPak videos from folder $folderId: $e');
    }

    // Sort videos by name for consistent ordering
    videos.sort((a, b) {
      final nameA = (a['name'] ?? '').toString().toLowerCase();
      final nameB = (b['name'] ?? '').toString().toLowerCase();
      return nameA.compareTo(nameB);
    });

    print('PikPak: Total videos found at depth $currentDepth: ${videos.length}');
    return videos;
  }

  Future<void> _addToRealDebrid(
    String infohash,
    String torrentName,
    int index,
  ) async {
    // Check if API key is available
    final apiKey = await StorageService.getApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.error, color: Colors.white, size: 16),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Please add your Real Debrid API key in Settings first!',
                  style: TextStyle(fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
          backgroundColor: const Color(0xFF1E293B),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          margin: const EdgeInsets.all(16),
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }

    // Show loading dialog
    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.4),
      pageBuilder: (_, __, ___) => const SizedBox.shrink(),
      transitionDuration: const Duration(milliseconds: 220),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween(begin: 0.95, end: 1.0).animate(curved),
            child: Dialog(
              backgroundColor: Theme.of(context).colorScheme.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.primary.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.download_rounded,
                        color: Theme.of(context).colorScheme.primary,
                        size: 32,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Adding to Real Debrid...',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      torrentName,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 5,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 20),
                    CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );

    try {
      final magnetLink = 'magnet:?xt=urn:btih:$infohash';
      final result = await DebridService.addTorrentToDebrid(apiKey, magnetLink);

      // Close loading dialog
      Navigator.of(context).pop();

      // Add to search history
      final torrent = _findTorrentByInfohash(infohash, torrentName);
      await _saveToHistory(torrent, 'realdebrid');

      // Handle post-torrent action
      await _handlePostTorrentAction(result, torrentName, apiKey, index);
    } catch (e) {
      // Close loading dialog
      Navigator.of(context).pop();

      // Show error message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.error, color: Colors.white, size: 16),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _formatRealDebridError(e),
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
          backgroundColor: const Color(0xFF1E293B),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          margin: const EdgeInsets.all(16),
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  Future<void> _showFileSelectionDialog(
    String infohash,
    String torrentName,
    int index,
  ) async {
    // Check if API key is available
    final apiKey = await StorageService.getApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.error, color: Colors.white, size: 16),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Please add your Real Debrid API key in Settings first!',
                  style: TextStyle(fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
          backgroundColor: const Color(0xFF1E293B),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          margin: const EdgeInsets.all(16),
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.85,
            ),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF1E293B), Color(0xFF334155)],
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: const Color(0xFF6366F1).withValues(alpha: 0.3),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.5),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header with gradient background
                Container(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                    ),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(20),
                      topRight: Radius.circular(20),
                    ),
                  ),
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.3),
                            width: 1,
                          ),
                        ),
                        child: const Icon(
                          Icons.folder_open_rounded,
                          color: Colors.white,
                          size: 32,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Select Files to Download',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          torrentName,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Colors.white,
                            fontWeight: FontWeight.w500,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 5,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),

                // Content (scrollable to avoid overflow)
                Flexible(
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        children: [
                          // File selection options with beautiful cards
                          _buildOptionCard(
                            context: context,
                            title: 'Smart (recommended)',
                            subtitle: 'Detect media vs non-media automatically',
                            icon: Icons.auto_awesome_rounded,
                            value: 'smart',
                            selectedOption: null,
                            onChanged: (value) {
                              Navigator.of(context).pop();
                              _addToRealDebridWithSelection(
                                infohash,
                                torrentName,
                                value!,
                                index,
                              );
                            },
                            gradient: const LinearGradient(
                              colors: [Color(0xFF22C55E), Color(0xFF16A34A)],
                            ),
                          ),
                          const SizedBox(height: 12),
                          _buildOptionCard(
                            context: context,
                            title: 'All video files',
                            subtitle: 'Ideal for web series and stuff',
                            icon: Icons.video_library_rounded,
                            value: 'video',
                            selectedOption: null,
                            onChanged: (value) {
                              Navigator.of(context).pop();
                              _addToRealDebridWithSelection(
                                infohash,
                                torrentName,
                                value!,
                                index,
                              );
                            },
                            gradient: const LinearGradient(
                              colors: [Color(0xFF10B981), Color(0xFF059669)],
                            ),
                          ),
                          const SizedBox(height: 12),
                          _buildOptionCard(
                            context: context,
                            title: 'File with highest size',
                            subtitle: 'Ideal for movies',
                            icon: Icons.movie_rounded,
                            value: 'largest',
                            selectedOption: null,
                            onChanged: (value) {
                              Navigator.of(context).pop();
                              _addToRealDebridWithSelection(
                                infohash,
                                torrentName,
                                value!,
                                index,
                              );
                            },
                            gradient: const LinearGradient(
                              colors: [Color(0xFFF59E0B), Color(0xFFD97706)],
                            ),
                          ),
                          const SizedBox(height: 12),
                          _buildOptionCard(
                            context: context,
                            title: 'All files',
                            subtitle: 'Ideal for apps, games, archives etc',
                            icon: Icons.folder_rounded,
                            value: 'all',
                            selectedOption: null,
                            onChanged: (value) {
                              Navigator.of(context).pop();
                              _addToRealDebridWithSelection(
                                infohash,
                                torrentName,
                                value!,
                                index,
                              );
                            },
                            gradient: const LinearGradient(
                              colors: [Color(0xFF8B5CF6), Color(0xFF7C3AED)],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _addToRealDebridWithSelection(
    String infohash,
    String torrentName,
    String fileSelection,
    int index,
  ) async {
    // Check if API key is available
    final apiKey = await StorageService.getApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.error, color: Colors.white, size: 16),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Please add your Real Debrid API key in Settings first!',
                  style: TextStyle(fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
          backgroundColor: const Color(0xFF1E293B),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          margin: const EdgeInsets.all(16),
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }

    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: const Color(0xFF1E293B),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6366F1).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.download_rounded,
                    color: Color(0xFF6366F1),
                    size: 32,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Adding to Real Debrid...',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  torrentName,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.7),
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 5,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 20),
                const CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF6366F1)),
                ),
              ],
            ),
          ),
        );
      },
    );

    try {
      final magnetLink = 'magnet:?xt=urn:btih:$infohash';
      final result = await DebridService.addTorrentToDebrid(
        apiKey,
        magnetLink,
        tempFileSelection: fileSelection,
      );

      // Close loading dialog
      Navigator.of(context).pop();

      // Handle post-torrent action
      await _handlePostTorrentAction(result, torrentName, apiKey, index);
    } catch (e) {
      // Close loading dialog
      Navigator.of(context).pop();

      // Show error message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.error, color: Colors.white, size: 16),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _formatRealDebridError(e),
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
          backgroundColor: const Color(0xFF1E293B),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          margin: const EdgeInsets.all(16),
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  Future<void> _addToTorbox(String infohash, String torrentName) async {
    final apiKey = await StorageService.getTorboxApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      _showTorboxApiKeyMissingMessage();
      return;
    }

    _showTorboxLoadingDialog(torrentName);

    try {
      final magnetLink = 'magnet:?xt=urn:btih:$infohash';
      final response = await TorboxService.createTorrent(
        apiKey: apiKey,
        magnet: magnetLink,
        seed: true,
        allowZip: true,
        addOnlyIfCached: true,
      );

      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }

      final success = response['success'] as bool? ?? false;
      if (!success) {
        final error = (response['error'] ?? '').toString();
        if (error == 'DOWNLOAD_NOT_CACHED') {
          _showTorboxSnack(
            'This torrent is not cached on Torbox. Please try a different torrent.',
            isError: true,
          );
        } else if (error.contains('INVALID_API_KEY') || error.contains('UNAUTHORIZED')) {
          _showTorboxSnack(
            'Invalid API key. Please check your Torbox settings.',
            isError: true,
          );
        } else if (error.contains('ALREADY_ADDED')) {
          _showTorboxSnack(
            'This torrent is already in your Torbox account.',
            isError: true,
          );
        } else if (error.contains('MAGNET_INVALID')) {
          _showTorboxSnack(
            'Invalid torrent. Please try a different one.',
            isError: true,
          );
        } else if (error.contains('QUOTA_EXCEEDED') || error.contains('LIMIT_REACHED')) {
          _showTorboxSnack(
            'Your Torbox account has reached its limit. Please upgrade or remove old torrents.',
            isError: true,
          );
        } else if (error.contains('SERVICE_UNAVAILABLE') || error.contains('MAINTENANCE')) {
          _showTorboxSnack(
            'Torbox service is temporarily unavailable. Please try again later.',
            isError: true,
          );
        } else {
          // For any other error, format it nicely
          final friendlyError = _formatTorboxError(error);
          _showTorboxSnack(
            friendlyError.isEmpty ? 'Failed to add torrent to Torbox.' : friendlyError,
            isError: true,
          );
        }
        return;
      }

      final data = response['data'];
      final torrentId = _asIntMapValue(data, 'torrent_id');
      if (torrentId == null) {
        _showTorboxSnack(
          'Torrent added but missing torrent id in response.',
          isError: true,
        );
        return;
      }

      final torboxTorrent = await _fetchTorboxTorrentById(apiKey, torrentId);
      if (torboxTorrent == null) {
        _showTorboxSnack(
          'Torbox cached the torrent but details are not ready yet. Check the Torbox tab shortly.',
        );
        return;
      }

      // Add to search history
      final torrent = _findTorrentByInfohash(infohash, torrentName);
      await _saveToHistory(torrent, 'torbox');

      if (!mounted) return;
      await _showTorboxPostAddOptions(torboxTorrent, torrent);
    } catch (e) {
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      _showTorboxSnack(
        'Failed to add torrent: ${_formatTorboxError(e)}',
        isError: true,
      );
    }
  }

  void _showTorboxApiKeyMissingMessage() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.error, color: Colors.white, size: 16),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Please add your Torbox API key in Settings first!',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF1E293B),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showTorboxLoadingDialog(String torrentName) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return Dialog(
          backgroundColor: const Color(0xFF1E293B),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF7C3AED).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.flash_on_rounded,
                    color: Color(0xFFDB2777),
                    size: 32,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Adding to Torbox...',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  torrentName,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.7),
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 5,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 20),
                const CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFDB2777)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<TorboxTorrent?> _fetchTorboxTorrentById(
    String apiKey,
    int torrentId,
  ) async {
    return TorboxService.getTorrentById(apiKey, torrentId, attempts: 5);
  }

  Future<void> _showTorboxPostAddOptions(TorboxTorrent torboxTorrent, Torrent torrent) async {
    if (!mounted) return;
    final videoFiles = torboxTorrent.files.where(_torboxFileLooksLikeVideo).toList();
    final hasVideo = videoFiles.isNotEmpty;

    // Get the post-torrent action preference
    final postAction = await StorageService.getTorboxPostTorrentAction();
    final torboxHidden = await StorageService.getTorboxHiddenFromNav();
    final apiKey = await StorageService.getTorboxApiKey();

    // Check if torrent is video-only for auto-download handling
    final isVideoOnly = torboxTorrent.files.isNotEmpty &&
        torboxTorrent.files.every((file) => _torboxFileLooksLikeVideo(file));

    // Handle automatic actions based on preference
    switch (postAction) {
      case 'none':
        // Show confirmation that torrent was added
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.check, color: Colors.white, size: 16),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Torrent added to Torbox successfully',
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF1E293B),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            margin: const EdgeInsets.all(16),
            duration: const Duration(seconds: 3),
          ),
        );
        return;
      case 'open':
        // Open in Torbox tab
        MainPageBridge.openTorboxFolder?.call(torboxTorrent);
        return;
      case 'playlist':
        // Add to playlist
        if (hasVideo) {
          _addTorboxTorrentToPlaylist(torboxTorrent);
        }
        return;
      case 'channel':
        // Add to channel
        final keyword = _searchController.text.trim();
        await _addTorrentToChannel(torrent, keyword);
        return;
      case 'play':
        if (hasVideo) {
          _playTorboxTorrent(torboxTorrent);
          return;
        }
        // Fall through to 'choose' if no video
        break;
      case 'download':
        if (isVideoOnly) {
          // Auto-download all videos without dialog
          _showTorboxDownloadOptions(torboxTorrent);
          return;
        }
        // Fall through to 'choose' if not video-only
        break;
      case 'choose':
      default:
        // Show the dialog
        break;
    }

    await showDialog(
      context: context,
      builder: (ctx) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 24,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Container(
              color: const Color(0xFF0F172A),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 12),
                  Container(
                    width: 42,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF7C3AED), Color(0xFFDB2777)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Icon(
                            Icons.flash_on_rounded,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                torboxTorrent.name,
                                maxLines: 5,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                hasVideo
                                    ? 'Cached on Torbox. Choose your next step.'
                                    : 'Available for download. No obvious videos detected.',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.6),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(ctx).pop(),
                          icon: const Icon(
                            Icons.close_rounded,
                            color: Colors.white54,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1, color: Color(0xFF1E293B)),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _DebridActionTile(
                            icon: Icons.open_in_new,
                            color: const Color(0xFFF59E0B),
                            title: 'Open in Torbox',
                            subtitle: 'View this torrent in Torbox tab',
                            enabled: true,
                            autofocus: true,
                            onTap: () {
                              Navigator.of(ctx).pop();
                              // Open the torrent in Torbox tab
                              MainPageBridge.openTorboxFolder?.call(torboxTorrent);
                            },
                          ),
                          _DebridActionTile(
                            icon: Icons.play_circle_fill_rounded,
                            color: const Color(0xFF60A5FA),
                            title: 'Play now',
                            subtitle: hasVideo
                                ? 'Open instantly in the Torbox player experience.'
                                : 'Available for torrents with video files.',
                            enabled: hasVideo,
                            autofocus: false,
                            onTap: () {
                              Navigator.of(ctx).pop();
                              _playTorboxTorrent(torboxTorrent);
                            },
                          ),
                          _DebridActionTile(
                            icon: Icons.download_rounded,
                            color: const Color(0xFF4ADE80),
                            title: 'Download to device',
                            subtitle: 'Grab files via Torbox instantly.',
                            enabled: true,
                            onTap: () {
                              Navigator.of(ctx).pop();
                              _showTorboxDownloadOptions(torboxTorrent);
                            },
                          ),
                          _DebridActionTile(
                            icon: Icons.link,
                            color: const Color(0xFFEC4899),
                            title: 'Copy Download Link (Zip)',
                            subtitle: 'Copy ZIP download link to clipboard',
                            enabled: apiKey != null && apiKey.isNotEmpty,
                            onTap: () {
                              Navigator.of(ctx).pop();
                              if (apiKey != null && apiKey.isNotEmpty) {
                                _copyTorboxZipLink(torboxTorrent, apiKey);
                              }
                            },
                          ),
                          _DebridActionTile(
                            icon: Icons.playlist_add_rounded,
                            color: const Color(0xFFA855F7),
                            title: 'Add to playlist',
                            subtitle: hasVideo
                                ? 'Keep this torrent handy in your Debrify playlist.'
                                : 'Available for video torrents only.',
                            enabled: hasVideo,
                            onTap: () {
                              Navigator.of(ctx).pop();
                              _addTorboxTorrentToPlaylist(torboxTorrent);
                            },
                          ),
                          _DebridActionTile(
                            icon: Icons.connected_tv,
                            color: const Color(0xFF10B981),
                            title: 'Add to channel',
                            subtitle: 'Cache this torrent in a Debrify TV channel.',
                            enabled: true,
                            onTap: () {
                              Navigator.of(ctx).pop();
                              final keyword = _searchController.text.trim();
                              // Use the torrent parameter directly since it's already the correct Torrent type
                              _addTorrentToChannel(torrent, keyword);
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
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
  }

  Future<void> _addTorboxTorrentToPlaylist(TorboxTorrent torrent) async {
    final videoFiles = torrent.files.where(_torboxFileLooksLikeVideo).toList();
    if (videoFiles.isEmpty) {
      _showTorboxSnack('No playable Torbox video files found.', isError: true);
      return;
    }

    if (videoFiles.length == 1) {
      final file = videoFiles.first;
      final displayName = _torboxDisplayName(file);
      final added = await StorageService.addPlaylistItemRaw({
        'provider': 'torbox',
        'title': FileUtils.cleanPlaylistTitle(displayName.isNotEmpty ? displayName : torrent.name),
        'kind': 'single',
        'torboxTorrentId': torrent.id,
        'torboxFileId': file.id,
        'torrent_hash': torrent.hash,
        'sizeBytes': file.size,
      });
      _showTorboxSnack(
        added ? 'Added to playlist' : 'Already in playlist',
        isError: !added,
      );
      return;
    }

    final fileIds = videoFiles.map((file) => file.id).toList();
    final added = await StorageService.addPlaylistItemRaw({
      'provider': 'torbox',
      'title': FileUtils.cleanPlaylistTitle(torrent.name),
      'kind': 'collection',
      'torboxTorrentId': torrent.id,
      'torboxFileIds': fileIds,
      'torrent_hash': torrent.hash,
      'count': videoFiles.length,
    });
    _showTorboxSnack(
      added ? 'Added collection to playlist' : 'Already in playlist',
      isError: !added,
    );
  }

  Future<void> _showTorboxDownloadOptions(TorboxTorrent torrent) async {
    final apiKey = await StorageService.getTorboxApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      _showTorboxApiKeyMissingMessage();
      return;
    }

    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        bool isLoadingZip = false;
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListTile(
                      leading: const Icon(Icons.checklist_outlined),
                      title: const Text('Select files to download'),
                      subtitle: const Text(
                        'Choose specific files from this torrent',
                      ),
                      onTap: () {
                        Navigator.of(sheetContext).pop();
                        _showTorboxFileSelection(
                          torrent: torrent,
                          apiKey: apiKey,
                        );
                      },
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.archive_outlined),
                      title: const Text('Download whole torrent as ZIP'),
                      subtitle: const Text(
                        'Create a single archive for offline use',
                      ),
                      trailing: isLoadingZip
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : null,
                      enabled: !isLoadingZip,
                      onTap: isLoadingZip
                          ? null
                          : () {
                              Navigator.of(sheetContext).pop();
                              _showTorboxSnack(
                                'Torbox ZIP downloads coming soon',
                              );
                            },
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// Show file selection dialog for Torbox torrents
  Future<void> _showTorboxFileSelection({
    required TorboxTorrent torrent,
    required String apiKey,
  }) async {
    if (torrent.files.isEmpty) {
      _showTorboxSnack('No files found in torrent', isError: true);
      return;
    }

    // Format files for FileSelectionDialog
    // Map Torbox file structure to the format expected by FileSelectionDialog
    final formattedFiles = <Map<String, dynamic>>[];
    for (final file in torrent.files) {
      // Use the file's name for _fullPath (which includes path separators)
      formattedFiles.add({
        '_fullPath': file.name,  // Use name field for full path
        'name': file.name,
        'size': file.size.toString(),
        '_torboxFileId': file.id,  // Store the file ID for later use
      });
    }

    // Show file selection dialog
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return FileSelectionDialog(
          files: formattedFiles,
          torrentName: torrent.name,
          onDownload: (selectedFiles) {
            if (selectedFiles.isEmpty) return;
            _downloadSelectedTorboxFiles(
              selectedFiles: selectedFiles,
              torrent: torrent,
              apiKey: apiKey,
            );
          },
        );
      },
    );
  }

  /// Download selected files from Torbox
  /// Follows the pattern from torbox_downloads_screen.dart _downloadMultipleFiles
  Future<void> _downloadSelectedTorboxFiles({
    required List<Map<String, dynamic>> selectedFiles,
    required TorboxTorrent torrent,
    required String apiKey,
  }) async {
    if (selectedFiles.isEmpty) return;

    // Show confirmation dialog
    final totalSize = selectedFiles.fold<int>(
      0,
      (sum, file) => sum + (int.tryParse(file['size']?.toString() ?? '0') ?? 0),
    );

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Download Files'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Download ${selectedFiles.length} file${selectedFiles.length == 1 ? '' : 's'}?'),
            const SizedBox(height: 16),
            Text(
              'Total size: ${Formatters.formatFileSize(totalSize)}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.download),
            label: const Text('Download'),
          ),
        ],
      ),
    ) ?? false;

    if (!confirmed || !mounted) return;

    // Show progress
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text(
              'Queueing downloads...',
              style: TextStyle(color: Colors.white),
            ),
          ],
        ),
      ),
    );

    // Queue downloads for each file
    // CRITICAL: Following the SAME pattern as Real-Debrid
    // We DON'T request download URLs upfront - we queue with metadata for lazy fetching
    // The DownloadService will request the URL when it's ready to download (lazy loading)
    int successCount = 0;
    int failCount = 0;

    for (final selectedFile in selectedFiles) {
      try {
        final fileId = selectedFile['_torboxFileId'] as int;
        final fileName = (selectedFile['_fullPath'] as String?) ?? 'Unknown';

        // Find the corresponding TorboxFile object
        final torboxFile = torrent.files.firstWhere(
          (f) => f.id == fileId,
          orElse: () => throw Exception('File not found in torrent'),
        );

        // Use shortName if available, otherwise extract from name
        final displayName = torboxFile.shortName.isNotEmpty
            ? torboxFile.shortName
            : FileUtils.getFileName(fileName);

        // Pass metadata for lazy URL fetching (no API call - instant!)
        // The download service will request the URL when ready
        final meta = jsonEncode({
          'torboxTorrentId': torrent.id,
          'torboxFileId': fileId,
          'apiKey': apiKey,
          'torboxDownload': true,
        });

        // Queue download instantly (download service will fetch URL when ready)
        await DownloadService.instance.enqueueDownload(
          url: '', // Empty URL - will be fetched by download service
          fileName: displayName,
          meta: meta,
          torrentName: torrent.name,
          context: mounted ? context : null,
        );

        successCount++;
      } catch (e) {
        failCount++;
      }
    }

    // Close progress dialog
    if (mounted) Navigator.of(context).pop();

    // Show result
    if (successCount > 0 && failCount == 0) {
      _showTorboxSnack(
        'Queued $successCount file${successCount == 1 ? '' : 's'} for download',
        isError: false,
      );
    } else if (successCount > 0 && failCount > 0) {
      _showTorboxSnack(
        'Queued $successCount file${successCount == 1 ? '' : 's'}, $failCount failed',
        isError: true,
      );
    } else {
      _showTorboxSnack(
        'Failed to queue any files for download',
        isError: true,
      );
    }
  }

  Future<String> _requestTorboxStreamUrl({
    required String apiKey,
    required TorboxTorrent torrent,
    required TorboxFile file,
  }) async {
    final url = await TorboxService.requestFileDownloadLink(
      apiKey: apiKey,
      torrentId: torrent.id,
      fileId: file.id,
    );
    if (url.isEmpty) {
      throw Exception('Torbox returned an empty stream URL');
    }
    return url;
  }

  int _findFirstEpisodeIndex(List<SeriesInfo> infos) {
    int startIndex = 0;
    int? bestSeason;
    int? bestEpisode;

    for (int i = 0; i < infos.length; i++) {
      final info = infos[i];
      final season = info.season;
      final episode = info.episode;
      if (!info.isSeries || season == null || episode == null) {
        continue;
      }

      final bool isBetterSeason = bestSeason == null || season < bestSeason;
      final bool isBetterEpisode =
          bestSeason != null &&
          season == bestSeason &&
          (bestEpisode == null || episode < bestEpisode);

      if (isBetterSeason || isBetterEpisode) {
        bestSeason = season;
        bestEpisode = episode;
        startIndex = i;
      }
    }

    return startIndex;
  }

  String _torboxDisplayName(TorboxFile file) {
    if (file.shortName.isNotEmpty) {
      return file.shortName;
    }
    if (file.name.isNotEmpty) {
      return FileUtils.getFileName(file.name);
    }
    return 'File ${file.id}';
  }

  String _formatTorboxPlaylistTitle({
    required SeriesInfo info,
    required String fallback,
    required bool isSeriesCollection,
  }) {
    if (!isSeriesCollection) {
      return fallback;
    }

    final season = info.season;
    final episode = info.episode;
    if (info.isSeries && season != null && episode != null) {
      final seasonLabel = season.toString().padLeft(2, '0');
      final episodeLabel = episode.toString().padLeft(2, '0');
      final description = info.episodeTitle?.trim().isNotEmpty == true
          ? info.episodeTitle!.trim()
          : info.title?.trim().isNotEmpty == true
          ? info.title!.trim()
          : fallback;
      return 'S${seasonLabel}E$episodeLabel · $description';
    }

    return fallback;
  }

  String _combineSeriesAndEpisodeTitle({
    required String? seriesTitle,
    required String episodeLabel,
    required bool isSeriesCollection,
    required String fallback,
  }) {
    if (!isSeriesCollection) {
      return fallback;
    }

    final cleanSeriesTitle = seriesTitle
        ?.replaceAll(RegExp(r'[._\-]+$'), '')
        .trim();
    if (cleanSeriesTitle != null && cleanSeriesTitle.isNotEmpty) {
      return '$cleanSeriesTitle $episodeLabel';
    }

    return fallback;
  }

  Future<void> _playTorboxTorrent(TorboxTorrent torrent) async {
    final apiKey = await StorageService.getTorboxApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      _showTorboxApiKeyMissingMessage();
      return;
    }

    final videoFiles = torrent.files.where((file) {
      if (file.zipped) return false;
      return _torboxFileLooksLikeVideo(file);
    }).toList();

    if (videoFiles.isEmpty) {
      _showTorboxSnack(
        'No playable video files found in this torrent.',
        isError: true,
      );
      return;
    }

    if (videoFiles.length == 1) {
      final file = videoFiles.first;
      try {
        final streamUrl = await _requestTorboxStreamUrl(
          apiKey: apiKey,
          torrent: torrent,
          file: file,
        );
        if (!mounted) return;
        await VideoPlayerLauncher.push(
          context,
          VideoPlayerLaunchArgs(
            videoUrl: streamUrl,
            title: torrent.name,
            subtitle: Formatters.formatFileSize(file.size),
            viewMode: PlaylistViewMode.sorted, // Single file - not series
          ),
        );
      } catch (e) {
        _showTorboxSnack(
          'Failed to play file: ${_formatTorboxError(e)}',
          isError: true,
        );
      }
      return;
    }

    final entries = List<_TorboxPlaylistItem>.generate(videoFiles.length, (
      index,
    ) {
      final displayName = _torboxDisplayName(videoFiles[index]);
      final info = SeriesParser.parseFilename(displayName);
      return _TorboxPlaylistItem(
        file: videoFiles[index],
        originalIndex: index,
        seriesInfo: info,
        displayName: displayName,
      );
    });

    final filenames = entries
        .map((entry) => _torboxDisplayName(entry.file))
        .toList();
    final bool isSeriesCollection =
        entries.length > 1 && SeriesParser.isSeriesPlaylist(filenames);

    final sortedEntries = [...entries];
    if (isSeriesCollection) {
      sortedEntries.sort((a, b) {
        final aInfo = a.seriesInfo;
        final bInfo = b.seriesInfo;
        final seasonCompare = (aInfo.season ?? 0).compareTo(bInfo.season ?? 0);
        if (seasonCompare != 0) return seasonCompare;
        final episodeCompare = (aInfo.episode ?? 0).compareTo(
          bInfo.episode ?? 0,
        );
        if (episodeCompare != 0) return episodeCompare;
        return a.displayName.toLowerCase().compareTo(
          b.displayName.toLowerCase(),
        );
      });
    } else {
      sortedEntries.sort(
        (a, b) =>
            a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
      );
    }

    final seriesInfos = sortedEntries.map((entry) => entry.seriesInfo).toList();
    int startIndex = isSeriesCollection
        ? _findFirstEpisodeIndex(seriesInfos)
        : 0;
    if (startIndex < 0 || startIndex >= sortedEntries.length) {
      startIndex = 0;
    }

    String initialUrl = '';
    try {
      initialUrl = await _requestTorboxStreamUrl(
        apiKey: apiKey,
        torrent: torrent,
        file: sortedEntries[startIndex].file,
      );
    } catch (e) {
      _showTorboxSnack(
        'Failed to prepare stream: ${_formatTorboxError(e)}',
        isError: true,
      );
      return;
    }

    final playlistEntries = <PlaylistEntry>[];
    for (int i = 0; i < sortedEntries.length; i++) {
      final entry = sortedEntries[i];
      final displayName = entry.displayName;
      final seriesInfo = entry.seriesInfo;
      final episodeLabel = _formatTorboxPlaylistTitle(
        info: seriesInfo,
        fallback: displayName,
        isSeriesCollection: isSeriesCollection,
      );
      final combinedTitle = _combineSeriesAndEpisodeTitle(
        seriesTitle: seriesInfo.title,
        episodeLabel: episodeLabel,
        isSeriesCollection: isSeriesCollection,
        fallback: displayName,
      );
      playlistEntries.add(
        PlaylistEntry(
          url: i == startIndex ? initialUrl : '',
          title: combinedTitle,
          provider: 'torbox',
          torboxTorrentId: torrent.id,
          torboxFileId: entry.file.id,
          sizeBytes: entry.file.size,
          torrentHash: torrent.hash.isNotEmpty ? torrent.hash : null,
        ),
      );
    }

    final totalBytes = sortedEntries.fold<int>(
      0,
      (sum, entry) => sum + entry.file.size,
    );
    final subtitle =
        '${playlistEntries.length} ${isSeriesCollection ? 'episodes' : 'files'} • ${Formatters.formatFileSize(totalBytes)}';

    if (!mounted) return;
    await VideoPlayerLauncher.push(
      context,
      VideoPlayerLaunchArgs(
        videoUrl: initialUrl,
        title: torrent.name,
        subtitle: subtitle,
        playlist: playlistEntries,
        startIndex: startIndex,
        viewMode: isSeriesCollection ? PlaylistViewMode.series : PlaylistViewMode.sorted,
      ),
    );
  }

  void _openTorboxFiles(TorboxTorrent torrent) {
    if (MainPageBridge.openTorboxFolder != null) {
      MainPageBridge.openTorboxFolder!(torrent);
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => TorboxDownloadsScreen(
            initialTorrentToOpen: torrent,
          ),
        ),
      );
    }
  }

  void _showTorboxSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError
            ? const Color(0xFFEF4444)
            : const Color(0xFF1E293B),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _copyTorboxZipLink(TorboxTorrent torrent, String apiKey) {
    final zipLink = TorboxService.createZipPermalink(apiKey, torrent.id);
    Clipboard.setData(ClipboardData(text: zipLink));

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF7C3AED),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.check,
                color: Colors.white,
                size: 16,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'ZIP download link copied to clipboard!',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF1E293B),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  bool _torboxFileLooksLikeVideo(TorboxFile file) {
    final name = file.shortName.isNotEmpty
        ? file.shortName
        : FileUtils.getFileName(file.name);
    return FileUtils.isVideoFile(name) ||
        (file.mimetype?.toLowerCase().startsWith('video/') ?? false);
  }

  bool _torboxResultIsCached(String infohash) {
    if (!_torboxCacheCheckEnabled) return true;
    final status = _torboxCacheStatus;
    if (status == null) return true;
    final sanitized = infohash.trim().toLowerCase();
    if (sanitized.isEmpty) return true;
    return status[sanitized] ?? false;
  }

  String _formatTorboxError(Object error) {
    final raw = error.toString();

    // Strip common prefixes
    String cleaned = raw
        .replaceFirst('Exception: ', '')
        .replaceFirst('Error: ', '')
        .trim();

    // Handle common API error patterns
    if (cleaned.contains('SocketException') || cleaned.contains('Failed host lookup')) {
      return 'Network error. Please check your connection.';
    }
    if (cleaned.contains('TimeoutException') || cleaned.contains('timed out')) {
      return 'Request timed out. Please try again.';
    }
    if (cleaned.contains('401') || cleaned.contains('Unauthorized')) {
      return 'Invalid API key. Please check your Torbox settings.';
    }
    if (cleaned.contains('403') || cleaned.contains('Forbidden')) {
      return 'Access denied. Your Torbox account may not have permission.';
    }
    if (cleaned.contains('404') || cleaned.contains('Not found')) {
      return 'Torrent not found on Torbox.';
    }
    if (cleaned.contains('429') || cleaned.contains('Too many requests')) {
      return 'Too many requests. Please wait a moment and try again.';
    }
    if (cleaned.contains('500') || cleaned.contains('502') || cleaned.contains('503')) {
      return 'Torbox service is temporarily unavailable. Please try again later.';
    }

    // If it's too technical or long, provide a generic message
    if (cleaned.length > 100 || cleaned.contains('dart:') || cleaned.contains('at Object')) {
      return 'An unexpected error occurred. Please try again.';
    }

    return cleaned.isEmpty ? 'An error occurred' : cleaned;
  }

  String _formatRealDebridError(Object error) {
    final raw = error.toString();

    // Strip common prefixes
    String cleaned = raw
        .replaceFirst('Exception: ', '')
        .replaceFirst('Error: ', '')
        .replaceFirst('Failed to add torrent to Real Debrid: ', '')
        .trim();

    // Handle common network errors
    if (cleaned.contains('SocketException') || cleaned.contains('Failed host lookup')) {
      return 'Network error. Please check your connection.';
    }
    if (cleaned.contains('TimeoutException') || cleaned.contains('timed out')) {
      return 'Request timed out. Please try again.';
    }

    // Handle Real-Debrid specific errors
    if (cleaned.contains('Invalid API key') || cleaned.contains('401') || cleaned.contains('Unauthorized')) {
      return 'Invalid API key. Please check your Real-Debrid settings.';
    }
    if (cleaned.contains('Account locked') || cleaned.contains('403') || cleaned.contains('Forbidden')) {
      return 'Account locked or access denied. Please check your Real-Debrid account.';
    }
    if (cleaned.contains('not readily available') || cleaned.contains('File is not available')) {
      return 'This file is not cached on Real-Debrid. Please try a different torrent.';
    }
    if (cleaned.contains('No files found') || cleaned.contains('files_are_mandatory')) {
      return 'No valid files found in this torrent.';
    }
    if (cleaned.contains('magnet_error') || cleaned.contains('Invalid magnet')) {
      return 'Invalid torrent magnet link. Please try a different torrent.';
    }
    if (cleaned.contains('torrent_too_big') || cleaned.contains('too big')) {
      return 'Torrent is too large. Please try a smaller torrent.';
    }
    if (cleaned.contains('permission_denied') || cleaned.contains('need_premium')) {
      return 'Premium account required. Please upgrade your Real-Debrid account.';
    }
    if (cleaned.contains('404') || cleaned.contains('Not found')) {
      return 'Torrent not found on Real-Debrid.';
    }
    if (cleaned.contains('429') || cleaned.contains('Too many')) {
      return 'Too many requests. Please wait a moment and try again.';
    }
    if (cleaned.contains('500') || cleaned.contains('502') || cleaned.contains('503') || cleaned.contains('service_unavailable')) {
      return 'Real-Debrid service is temporarily unavailable. Please try again later.';
    }

    // If it's too technical or long, provide a generic message
    if (cleaned.length > 100 || cleaned.contains('dart:') || cleaned.contains('at Object')) {
      return 'An unexpected error occurred. Please try again.';
    }

    return cleaned.isEmpty ? 'Failed to add torrent to Real-Debrid' : cleaned;
  }

  int? _asIntMapValue(dynamic data, String key) {
    if (data is Map<String, dynamic>) {
      final value = data[key];
      if (value is int) return value;
      if (value is String) return int.tryParse(value);
      if (value is num) return value.toInt();
    }
    return null;
  }

  Widget _buildOptionCard({
    required BuildContext context,
    required String title,
    required String subtitle,
    required IconData icon,
    required String value,
    required String? selectedOption,
    required Function(String?) onChanged,
    required LinearGradient gradient,
  }) {
    final isSelected = selectedOption == value;

    return Container(
      decoration: BoxDecoration(
        gradient: isSelected
            ? gradient
            : LinearGradient(
                colors: [
                  Colors.grey.withValues(alpha: 0.1),
                  Colors.grey.withValues(alpha: 0.05),
                ],
              ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSelected
              ? Colors.white.withValues(alpha: 0.3)
              : Colors.grey.withValues(alpha: 0.2),
          width: isSelected ? 2 : 1,
        ),
        boxShadow: isSelected
            ? [
                BoxShadow(
                  color: gradient.colors.first.withValues(alpha: 0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => onChanged(value),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Icon container
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? Colors.white.withValues(alpha: 0.2)
                        : Colors.grey.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected
                          ? Colors.white.withValues(alpha: 0.3)
                          : Colors.grey.withValues(alpha: 0.2),
                      width: 1,
                    ),
                  ),
                  child: Icon(
                    icon,
                    color: isSelected ? Colors.white : Colors.grey[400],
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),

                // Text content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: isSelected ? Colors.white : Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: isSelected
                              ? Colors.white.withValues(alpha: 0.8)
                              : Colors.grey[400],
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),

                // Selection indicator
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected
                          ? Colors.white
                          : Colors.grey.withValues(alpha: 0.4),
                      width: 2,
                    ),
                    color: isSelected ? Colors.white : Colors.transparent,
                  ),
                  child: isSelected
                      ? Icon(
                          Icons.check,
                          color: gradient.colors.first,
                          size: 16,
                        )
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _handlePostTorrentAction(
    Map<String, dynamic> result,
    String torrentName,
    String apiKey,
    int index,
  ) async {
    final postAction = await StorageService.getPostTorrentAction();
    final rdHidden = await StorageService.getRealDebridHiddenFromNav();
    final downloadLink = result['downloadLink'] as String;
    final fileSelection = result['fileSelection'] as String;
    final links = result['links'] as List<dynamic>;
    final files = result['files'] as List<dynamic>?;
    final updatedInfo = result['updatedInfo'] as Map<String, dynamic>?;

    // Check if this is a RAR archive (multiple files but only 1 link)
    final isRarArchive = (files != null && files.isNotEmpty)
        ? RDFolderTreeBuilder.isRarArchive(
            files.map((f) => f as Map<String, dynamic>).toList(),
            links,
          )
        : false;

    // Special case: if user prefers auto-download and torrent is media-only, download all immediately
    final hasAnyVideo = (files ?? []).any((f) {
      final name =
          (f['name'] as String?) ??
          (f['filename'] as String?) ??
          (f['path'] as String?) ??
          '';
      final base = name.startsWith('/') ? name.split('/').last : name;
      return base.isNotEmpty && FileUtils.isVideoFile(base);
    });
    final isMediaOnly =
        (files != null && files.isNotEmpty) &&
        files.every((f) {
          final name =
              (f['name'] as String?) ??
              (f['filename'] as String?) ??
              (f['path'] as String?) ??
              '';
          final base = name.startsWith('/') ? name.split('/').last : name;
          return base.isNotEmpty && FileUtils.isVideoFile(base);
        });

    if (postAction == 'download' && isMediaOnly) {
      // Auto-download all videos without dialog
      _showDownloadSelectionDialog(links, torrentName);
      return;
    }

    switch (postAction) {
      case 'none':
        // Show confirmation that torrent was added
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.check, color: Colors.white, size: 16),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Torrent added to Real Debrid successfully',
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF1E293B),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            margin: const EdgeInsets.all(16),
            duration: const Duration(seconds: 3),
          ),
        );
        break;
      case 'open':
        // Open in Real-Debrid tab
        if (!isRarArchive) {
          final rdTorrent = RDTorrent(
            id: result['torrentId'].toString(),
            filename: torrentName,
            hash: '',
            bytes: 0,
            host: '',
            split: 0,
            progress: 0,
            status: '',
            added: DateTime.now().toIso8601String(),
            links: links.map((e) => e.toString()).toList(),
          );
          MainPageBridge.openDebridOptions?.call(rdTorrent);
        }
        break;
      case 'playlist':
        // Add to playlist
        if (hasAnyVideo) {
          if (links.length == 1) {
            String finalTitle = torrentName;
            try {
              final torrentId = result['torrentId']?.toString();
              if (torrentId != null && torrentId.isNotEmpty) {
                final torrentInfo =
                    await DebridService.getTorrentInfo(
                      await StorageService.getApiKey() ?? '',
                      torrentId,
                    );
                final filename = torrentInfo['filename']?.toString();
                if (filename != null && filename.isNotEmpty) {
                  finalTitle = filename;
                }
              }
            } catch (_) {}

            final added =
                await StorageService.addPlaylistItemRaw({
                  'title': FileUtils.cleanPlaylistTitle(finalTitle),
                  'url': '',
                  'restrictedLink': links[0],
                  'rdTorrentId': result['torrentId']?.toString(),
                  'kind': 'single',
                });
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  added
                      ? 'Added to playlist'
                      : 'Already in playlist',
                ),
              ),
            );
          } else {
            final torrentId =
                result['torrentId']?.toString() ?? '';
            if (torrentId.isEmpty) return;
            final added =
                await StorageService.addPlaylistItemRaw({
                  'title': FileUtils.cleanPlaylistTitle(torrentName),
                  'kind': 'collection',
                  'rdTorrentId': torrentId,
                  'count': links.length,
                });
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  added
                      ? 'Added collection to playlist'
                      : 'Already in playlist',
                ),
              ),
            );
          }
        }
        break;
      case 'channel':
        // Add to channel
        final keyword = _searchController.text.trim();
        if (index >= 0 && index < _torrents.length) {
          await _addTorrentToChannel(_torrents[index], keyword);
        }
        break;
      case 'choose':
        await showDialog(
          context: context,
          builder: (ctx) {
            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 24,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Container(
                  color: const Color(0xFF0F172A),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 12),
                      Container(
                        width: 42,
                        height: 5,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFF6366F1),
                                    Color(0xFF8B5CF6),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: const Icon(
                                Icons.cloud_download_rounded,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    torrentName,
                                    maxLines: 5,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    links.length == 1
                                        ? 'Ready to unrestrict and stream/download.'
                                        : '${links.length} files available in this torrent.',
                                    style: TextStyle(
                                      color: Colors.white.withValues(
                                        alpha: 0.6,
                                      ),
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: () => Navigator.of(ctx).pop(),
                              icon: const Icon(
                                Icons.close_rounded,
                                color: Colors.white54,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1, color: Color(0xFF1E293B)),
                      Flexible(
                        child: SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _DebridActionTile(
                                icon: Icons.open_in_new,
                                color: const Color(0xFFF59E0B),
                                title: 'Open in Real-Debrid',
                                subtitle: isRarArchive
                                    ? 'Not available for RAR archives (not extracted by Real-Debrid)'
                                    : 'View this torrent in Real-Debrid tab',
                                enabled: !isRarArchive,
                                autofocus: !isRarArchive,
                                onTap: () {
                                  Navigator.of(ctx).pop();
                                  // Create RDTorrent object and open it in Real-Debrid tab
                                  final rdTorrent = RDTorrent(
                                    id: result['torrentId'].toString(),
                                    filename: torrentName,
                                    hash: '',
                                    bytes: 0,
                                    host: '',
                                    split: 0,
                                    progress: 0,
                                    status: '',
                                    added: DateTime.now().toIso8601String(),
                                    links: links.map((e) => e.toString()).toList(),
                                  );
                                  MainPageBridge.openDebridOptions?.call(rdTorrent);
                                },
                              ),
                              _DebridActionTile(
                                icon: Icons.play_circle_rounded,
                                color: const Color(0xFF60A5FA),
                                title: 'Play now',
                                subtitle: hasAnyVideo
                                    ? 'Unrestrict and open instantly in the built-in player.'
                                    : 'Available for video torrents only.',
                                enabled: hasAnyVideo,
                                autofocus: isRarArchive && hasAnyVideo,
                                onTap: () async {
                                  Navigator.of(ctx).pop();
                                  await _playFromResult(
                                    links: links,
                                    files: files,
                                    updatedInfo: updatedInfo,
                                    torrentName: torrentName,
                                    fileSelection: fileSelection,
                                    torrentId: result['torrentId']?.toString(),
                                  );
                                },
                              ),
                              _DebridActionTile(
                                icon: Icons.download_rounded,
                                color: const Color(0xFF4ADE80),
                                title: 'Download to device',
                                subtitle: isRarArchive
                                    ? 'Downloads the RAR archive to your device'
                                    : 'Downloads the files to your device',
                                enabled: true,
                                onTap: () async {
                                  Navigator.of(ctx).pop();
                                  // RAR archives: always download the single link directly
                                  if (isRarArchive) {
                                    _downloadFile(downloadLink, torrentName);
                                  } else if (hasAnyVideo) {
                                    if (links.length == 1) {
                                      _downloadFile(downloadLink, torrentName);
                                    } else {
                                      // Show file selection dialog for multiple video files
                                      await _showRealDebridFileSelection(
                                        result: result,
                                        torrentName: torrentName,
                                        apiKey: apiKey,
                                      );
                                    }
                                  } else {
                                    if (links.length > 1) {
                                      _showDownloadSelectionDialog(links, torrentName);
                                    } else {
                                      _downloadFile(downloadLink, torrentName);
                                    }
                                  }
                                },
                              ),
                              _DebridActionTile(
                                icon: Icons.playlist_add_rounded,
                                color: const Color(0xFFA855F7),
                                title: 'Add to playlist',
                                subtitle: hasAnyVideo
                                    ? 'Keep this torrent handy in your Debrify playlist.'
                                    : 'Available for video torrents only.',
                                enabled: hasAnyVideo,
                                onTap: () async {
                                  Navigator.of(ctx).pop();
                                  if (!hasAnyVideo) return;
                                  if (links.length == 1) {
                                    String finalTitle = torrentName;
                                    try {
                                      final torrentId = result['torrentId']?.toString();
                                      if (torrentId != null && torrentId.isNotEmpty) {
                                        final torrentInfo =
                                            await DebridService.getTorrentInfo(
                                              apiKey,
                                              torrentId,
                                            );
                                        final filename = torrentInfo['filename']
                                            ?.toString();
                                        if (filename != null && filename.isNotEmpty) {
                                          finalTitle = filename;
                                        }
                                      }
                                    } catch (_) {}

                                    final added =
                                        await StorageService.addPlaylistItemRaw({
                                          'title': FileUtils.cleanPlaylistTitle(finalTitle),
                                          'url': '',
                                          'restrictedLink': links[0],
                                          'rdTorrentId': result['torrentId']
                                              ?.toString(),
                                          'kind': 'single',
                                        });
                                    if (!mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          added
                                              ? 'Added to playlist'
                                              : 'Already in playlist',
                                        ),
                                      ),
                                    );
                                  } else {
                                    final torrentId =
                                        result['torrentId']?.toString() ?? '';
                                    if (torrentId.isEmpty) return;
                                    final added =
                                        await StorageService.addPlaylistItemRaw({
                                          'title': FileUtils.cleanPlaylistTitle(torrentName),
                                          'kind': 'collection',
                                          'rdTorrentId': torrentId,
                                          'count': links.length,
                                        });
                                    if (!mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          added
                                              ? 'Added collection to playlist'
                                              : 'Already in playlist',
                                        ),
                                      ),
                                    );
                                  }
                                },
                              ),
                              _DebridActionTile(
                                icon: Icons.connected_tv,
                                color: const Color(0xFF10B981),
                                title: 'Add to channel',
                                subtitle: 'Cache this torrent in a Debrify TV channel.',
                                enabled: true,
                                onTap: () {
                                  Navigator.of(ctx).pop();
                                  final keyword = _searchController.text.trim();
                                  if (index >= 0 && index < _torrents.length) {
                                    _addTorrentToChannel(_torrents[index], keyword);
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        child: const Text(
                          'Cancel',
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
        break;
      case 'play':
        await _playFromResult(
          links: links,
          files: files,
          updatedInfo: updatedInfo,
          torrentName: torrentName,
          fileSelection: fileSelection,
          torrentId: result['torrentId']?.toString(),
        );
        break;
      case 'copy':
        // Copy to clipboard
        Clipboard.setData(ClipboardData(text: downloadLink));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.check, color: Colors.white, size: 16),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Torrent added to Real Debrid! Download link copied to clipboard.',
                    style: TextStyle(fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF1E293B),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            margin: const EdgeInsets.all(16),
            duration: const Duration(seconds: 4),
          ),
        );
        break;
      case 'download':
        // Download file(s) - use same logic as "choose" case
        if (hasAnyVideo) {
          // Check if single video file - download directly
          if (links.length == 1) {
            await _downloadFile(downloadLink, torrentName);
          } else {
            // Show file selection dialog for multiple video files
            await _showRealDebridFileSelection(
              result: result,
              torrentName: torrentName,
              apiKey: apiKey,
            );
          }
        } else {
          if (links.length > 1) {
            _showDownloadSelectionDialog(links, torrentName);
          } else {
            await _downloadFile(downloadLink, torrentName);
          }
        }
        break;
    }
  }

  // Compact action button widget for the chooser dialog
  Future<void> _playFromResult({
    required List<dynamic> links,
    required List<dynamic>? files,
    required Map<String, dynamic>? updatedInfo,
    required String torrentName,
    required String fileSelection,
    String? torrentId,
  }) async {
    final String? apiKey = await StorageService.getApiKey();
    if (apiKey == null || apiKey.isEmpty) return;
    // If multiple RD links exist, treat as multi-file playlist (series pack, multi-episode, etc.)
    if (links.length > 1) {
      await _handlePlayMultiFileTorrentWithInfo(
        links,
        files,
        updatedInfo,
        torrentName,
        apiKey,
        0,
        torrentId,
      );
      return;
    }
    try {
      final unrestrictResult = await DebridService.unrestrictLink(
        apiKey,
        links[0],
      );
      final videoUrl = unrestrictResult['download'];
      final mimeType = unrestrictResult['mimeType']?.toString() ?? '';
      if (FileUtils.isVideoMimeType(mimeType)) {
        if (!mounted) return;

        // Fetch actual torrent filename for resume key parity with Debrid screen
        String finalTitle = torrentName;
        try {
          if (torrentId != null && torrentId.isNotEmpty) {
            final torrentInfo = await DebridService.getTorrentInfo(
              apiKey,
              torrentId,
            );
            final filename = torrentInfo['filename']?.toString();
            if (filename != null && filename.isNotEmpty) {
              finalTitle = filename;
            }
          }
        } catch (_) {
          // Fallback to torrentName if fetch fails
        }

        await VideoPlayerLauncher.push(
          context,
          VideoPlayerLaunchArgs(
            videoUrl: videoUrl,
            title: finalTitle,
            viewMode: PlaylistViewMode.sorted, // Single file - not series
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.check, color: Colors.white, size: 16),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Added to torrent but the file is not a video file',
                    style: TextStyle(fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF1E293B),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            margin: const EdgeInsets.all(16),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.error, color: Colors.white, size: 16),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Failed to load video: ${e.toString()}',
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
          backgroundColor: const Color(0xFF1E293B),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          margin: const EdgeInsets.all(16),
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  Future<void> _handlePlayMultiFileTorrentWithInfo(
    List<dynamic> links,
    List<dynamic>? files,
    Map<String, dynamic>? updatedInfo,
    String torrentName,
    String apiKey,
    int index,
    String? torrentId,
  ) async {
    try {
      // Show loading dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          backgroundColor: Color(0xFF1E293B),
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Text(
                'Preparing playlist…',
                style: TextStyle(color: Colors.white),
              ),
            ],
          ),
        ),
      );

      // Use file information from torrent info for true lazy loading
      if (files == null || updatedInfo == null) {
        if (mounted) Navigator.of(context).pop(); // close loading
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.error,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Failed to get file information from torrent.',
                      style: TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
              backgroundColor: const Color(0xFF1E293B),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              margin: const EdgeInsets.all(16),
              duration: const Duration(seconds: 4),
            ),
          );
        }
        return;
      }

      // Get selected files from the torrent info
      final selectedFiles = files
          .where((file) => file['selected'] == 1)
          .toList();

      // If no selected files, use all files (they might all be selected by default)
      final allFilesToUse = selectedFiles.isNotEmpty ? selectedFiles : files;

      // Filter to only video files
      final filesToUse = allFilesToUse.where((file) {
        String? filename =
            file['name']?.toString() ??
            file['filename']?.toString() ??
            file['path']?.toString();

        // If we got a path, extract just the filename
        if (filename != null && filename.startsWith('/')) {
          filename = filename.split('/').last;
        }

        return filename != null && FileUtils.isVideoFile(filename);
      }).toList();

      // Check if this is an archive (multiple files, single link)
      bool isArchive = false;
      if (filesToUse.length > 1 && links.length == 1) {
        isArchive = true;
      }

      if (isArchive) {
        if (mounted) Navigator.of(context).pop(); // close loading
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.error,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'This is an archived torrent. Please extract it first.',
                      style: TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
              backgroundColor: const Color(0xFF1E293B),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              margin: const EdgeInsets.all(16),
              duration: const Duration(seconds: 4),
            ),
          );
        }
        return;
      }

      // Multiple individual files - create playlist with true lazy loading
      final List<PlaylistEntry> entries = [];

      // Get filenames from files with null safety
      final filenames = filesToUse.map((file) {
        String? name =
            file['name']?.toString() ??
            file['filename']?.toString() ??
            file['path']?.toString();

        // If we got a path, extract just the filename
        if (name != null && name.startsWith('/')) {
          name = name.split('/').last;
        }

        return name ?? 'Unknown File';
      }).toList();

      // Check if this is a series
      final isSeries = SeriesParser.isSeriesPlaylist(filenames);

      if (isSeries) {
        // For series: find the first episode and unrestrict only that one
        final seriesInfos = SeriesParser.parsePlaylist(filenames);

        // Find the first episode (lowest season, lowest episode)
        int firstEpisodeIndex = 0;
        int lowestSeason = 999;
        int lowestEpisode = 999;

        for (int i = 0; i < seriesInfos.length; i++) {
          final info = seriesInfos[i];
          if (info.isSeries && info.season != null && info.episode != null) {
            if (info.season! < lowestSeason ||
                (info.season! == lowestSeason &&
                    info.episode! < lowestEpisode)) {
              lowestSeason = info.season!;
              lowestEpisode = info.episode!;
              firstEpisodeIndex = i;
            }
          }
        }

        // Create playlist entries with true lazy loading
        for (int i = 0; i < filesToUse.length; i++) {
          final file = filesToUse[i];
          String? filename =
              file['name']?.toString() ??
              file['filename']?.toString() ??
              file['path']?.toString();

          // If we got a path, extract just the filename
          if (filename != null && filename.startsWith('/')) {
            filename = filename.split('/').last;
          }

          final finalFilename = filename ?? 'Unknown File';
          final int? sizeBytes = (file is Map) ? (file['bytes'] as int?) : null;

          // Check if we have a corresponding link
          if (i >= links.length) {
            // Skip if no corresponding link
            continue;
          }

          if (i == firstEpisodeIndex) {
            // First episode: try to unrestrict for immediate playback
            try {
              final unrestrictResult = await DebridService.unrestrictLink(
                apiKey,
                links[i],
              );
              final url = unrestrictResult['download']?.toString() ?? '';
              if (url.isNotEmpty) {
                entries.add(
                  PlaylistEntry(
                    url: url,
                    title: finalFilename,
                    sizeBytes: sizeBytes,
                  ),
                );
              } else {
                // If unrestriction failed or returned empty URL, add as restricted link
                entries.add(
                  PlaylistEntry(
                    url: '', // Empty URL - will be filled when unrestricted
                    title: finalFilename,
                    restrictedLink: links[i],
                    sizeBytes: sizeBytes,
                  ),
                );
              }
            } catch (e) {
              // If unrestriction fails, add as restricted link for lazy loading
              entries.add(
                PlaylistEntry(
                  url: '', // Empty URL - will be filled when unrestricted
                  title: finalFilename,
                  restrictedLink: links[i],
                  sizeBytes: sizeBytes,
                ),
              );
            }
          } else {
            // Other episodes: keep restricted links for lazy loading
            entries.add(
              PlaylistEntry(
                url: '', // Empty URL - will be filled when unrestricted
                title: finalFilename,
                restrictedLink: links[i],
                sizeBytes: sizeBytes,
              ),
            );
          }
        }
      } else {
        // For movies: unrestrict only the first video
        for (int i = 0; i < filesToUse.length; i++) {
          final file = filesToUse[i];
          String? filename =
              file['name']?.toString() ??
              file['filename']?.toString() ??
              file['path']?.toString();

          // If we got a path, extract just the filename
          if (filename != null && filename.startsWith('/')) {
            filename = filename.split('/').last;
          }

          final finalFilename = filename ?? 'Unknown File';
          final int? sizeBytes = (file is Map) ? (file['bytes'] as int?) : null;

          // Check if we have a corresponding link
          if (i >= links.length) {
            // Skip if no corresponding link
            continue;
          }

          if (i == 0) {
            // First video: try to unrestrict for immediate playback
            try {
              final unrestrictResult = await DebridService.unrestrictLink(
                apiKey,
                links[i],
              );
              final url = unrestrictResult['download']?.toString() ?? '';
              if (url.isNotEmpty) {
                entries.add(
                  PlaylistEntry(
                    url: url,
                    title: finalFilename,
                    sizeBytes: sizeBytes,
                  ),
                );
              } else {
                // If unrestriction failed or returned empty URL, add as restricted link
                entries.add(
                  PlaylistEntry(
                    url: '', // Empty URL - will be filled when unrestricted
                    title: finalFilename,
                    restrictedLink: links[i],
                    sizeBytes: sizeBytes,
                  ),
                );
              }
            } catch (e) {
              // If unrestriction fails, add as restricted link for lazy loading
              entries.add(
                PlaylistEntry(
                  url: '', // Empty URL - will be filled when unrestricted
                  title: finalFilename,
                  restrictedLink: links[i],
                  sizeBytes: sizeBytes,
                ),
              );
            }
          } else {
            // Other videos: keep restricted links for lazy loading
            entries.add(
              PlaylistEntry(
                url: '', // Empty URL - will be filled when unrestricted
                title: finalFilename,
                restrictedLink: links[i],
                sizeBytes: sizeBytes,
              ),
            );
          }
        }
      }

      if (mounted) Navigator.of(context).pop(); // close loading

      if (entries.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.error,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'No playable video files found in this torrent.',
                      style: TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
              backgroundColor: const Color(0xFF1E293B),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              margin: const EdgeInsets.all(16),
              duration: const Duration(seconds: 4),
            ),
          );
        }
        return;
      }

      if (!mounted) return;

      // Determine the initial video URL - use the first unrestricted URL or empty string
      String initialVideoUrl = '';
      if (entries.isNotEmpty && entries.first.url.isNotEmpty) {
        initialVideoUrl = entries.first.url;
      }

      // Fetch actual torrent filename for resume key parity with Debrid screen
      String finalTitle = torrentName;
      try {
        if (torrentId != null && torrentId.isNotEmpty) {
          final torrentInfo = await DebridService.getTorrentInfo(
            apiKey,
            torrentId,
          );
          final filename = torrentInfo['filename']?.toString();
          if (filename != null && filename.isNotEmpty) {
            finalTitle = filename;
          }
        }
      } catch (_) {
        // Fallback to torrentName if fetch fails
      }

      await VideoPlayerLauncher.push(
        context,
        VideoPlayerLaunchArgs(
          videoUrl: initialVideoUrl,
          title: finalTitle,
          subtitle: '${entries.length} files',
          playlist: entries.isNotEmpty ? entries : null,
          startIndex: 0,
          viewMode: isSeries ? PlaylistViewMode.series : PlaylistViewMode.sorted,
        ),
      );
    } catch (e) {
      if (mounted) {
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.error, color: Colors.white, size: 16),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Failed to prepare playlist: ${e.toString()}',
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF1E293B),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            margin: const EdgeInsets.all(16),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  Future<void> _showDownloadSelectionDialog(
    List<dynamic> links,
    String torrentName,
  ) async {
    // Show file selection dialog immediately (no upfront unrestriction)
    final apiKey = await StorageService.getApiKey();
    if (apiKey == null) return;

    // Create file list with restricted links (unrestriction happens on-demand)
    final List<Map<String, dynamic>> fileList = [];
    for (int i = 0; i < links.length; i++) {
      final link = links[i];
      // Extract filename from link if possible, otherwise use generic name
      String fileName = 'File ${i + 1}';
      try {
        final uri = Uri.parse(link);
        if (uri.pathSegments.isNotEmpty) {
          fileName = uri.pathSegments.last;
        }
      } catch (_) {
        // Use default filename
      }

      fileList.add({
        'restrictedLink': link,
        'filename': fileName,
        'fileIndex': i,
      });
    }

    if (fileList.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.error, color: Colors.white, size: 16),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'No downloadable video files found in this torrent.',
                    style: TextStyle(fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF1E293B),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            margin: const EdgeInsets.all(16),
            duration: const Duration(seconds: 4),
          ),
        );
      }
      return;
    }

    // Show the download selection dialog with unrestricted links
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: const Color(0xFF1E293B),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.8,
            ),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Select Video to Download',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Download All option
                  ListTile(
                    leading: const Icon(
                      Icons.download_for_offline,
                      color: Color(0xFF10B981),
                    ),
                    title: const Text(
                      'Download All',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      'Download all ${fileList.length} files',
                      style: TextStyle(color: Colors.grey[400]),
                    ),
                    onTap: () async {
                      Navigator.of(context).pop();
                      await _downloadAllFiles(fileList, torrentName);
                    },
                  ),
                  const Divider(color: Colors.grey),
                  // Individual video options - scrollable
                  Expanded(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: fileList.length,
                      itemBuilder: (context, index) {
                        final file = fileList[index];
                        final fileName = file['filename'] as String;
                        return ListTile(
                          key: ValueKey('${file['id'] ?? index}'),
                          leading: const Icon(
                            Icons.video_file,
                            color: Colors.grey,
                          ),
                          title: Text(
                            fileName,
                            style: const TextStyle(color: Colors.white),
                            maxLines: 5,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            'Tap to download',
                            style: TextStyle(color: Colors.grey[400]),
                          ),
                          onTap: () async {
                            Navigator.of(context).pop();
                            await _downloadFile(
                              file['restrictedLink'],
                              fileName,
                              torrentName: torrentName,
                            );
                          },
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _downloadAllFiles(
    List<Map<String, dynamic>> files,
    String torrentName,
  ) async {
    try {
      // Start downloads for all files
      for (final file in files) {
        final restrictedLink = (file['restrictedLink'] ?? '').toString();
        final fileName = (file['filename'] ?? 'file').toString();
        if (restrictedLink.isEmpty) continue;
        final meta = jsonEncode({
          'restrictedLink': restrictedLink,
          'apiKey': _apiKey ?? '',
          'torrentHash': (file['torrentHash'] ?? '').toString(),
          'fileIndex': file['fileIndex'] ?? '',
        });
        await DownloadService.instance.enqueueDownload(
          url: restrictedLink, // Use restricted link directly
          fileName: fileName,
          context: context,
          torrentName: torrentName,
          meta: meta,
        );
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.download,
                  color: Colors.white,
                  size: 16,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Started downloading ${files.length} files! Check Downloads tab for progress.',
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
          backgroundColor: const Color(0xFF1E293B),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          margin: const EdgeInsets.all(16),
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.error, color: Colors.white, size: 16),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Failed to start downloads: ${e.toString()}',
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
          backgroundColor: const Color(0xFF1E293B),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          margin: const EdgeInsets.all(16),
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  /// Show file selection dialog for Real-Debrid torrents
  Future<void> _showRealDebridFileSelection({
    required Map<String, dynamic> result,
    required String torrentName,
    required String apiKey,
  }) async {
    final torrentId = result['torrentId']?.toString();
    if (torrentId == null || torrentId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Torrent ID not available'),
          backgroundColor: Color(0xFFEF4444),
        ),
      );
      return;
    }

    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text(
              'Loading torrent files...',
              style: TextStyle(color: Colors.white),
            ),
          ],
        ),
      ),
    );

    try {
      // Get torrent info to get file list
      final torrentInfo = await DebridService.getTorrentInfo(apiKey, torrentId);
      final allFiles = (torrentInfo['files'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      final links = (torrentInfo['links'] as List?)?.cast<String>() ?? [];

      // Filter to only selected files (files that were selected when adding to RD)
      // Only selected files have corresponding links and can be downloaded
      final files = allFiles.where((file) => file['selected'] == 1).toList();

      if (mounted) Navigator.of(context).pop();

      if (files.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No files found in torrent'),
            backgroundColor: Color(0xFFEF4444),
          ),
        );
        return;
      }

      // Format files for FileSelectionDialog
      // Map RD file structure to the format expected by FileSelectionDialog
      final formattedFiles = <Map<String, dynamic>>[];
      for (int i = 0; i < files.length; i++) {
        final file = files[i];
        final path = (file['path'] as String?) ?? '';
        final bytes = file['bytes'] as int? ?? 0;

        formattedFiles.add({
          '_fullPath': path,  // Use path field for full path
          'name': path,
          'size': bytes.toString(),
          '_linkIndex': i,  // Store the link index for later use
        });
      }

      // Show file selection dialog
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (BuildContext context) {
          return FileSelectionDialog(
            files: formattedFiles,
            torrentName: torrentName,
            onDownload: (selectedFiles) {
              if (selectedFiles.isEmpty) return;
              _downloadSelectedRealDebridFiles(
                selectedFiles: selectedFiles,
                torrentId: torrentId,
                torrentName: torrentName,
                apiKey: apiKey,
                links: links,
                torrentHash: torrentInfo['hash']?.toString() ?? '',
              );
            },
          );
        },
      );
    } catch (e) {
      if (mounted) Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load torrent files: ${e.toString()}'),
          backgroundColor: const Color(0xFFEF4444),
        ),
      );
    }
  }

  /// Download selected files from Real-Debrid
  /// Follows the SAME pattern as folder downloads in debrid_downloads_screen.dart
  Future<void> _downloadSelectedRealDebridFiles({
    required List<Map<String, dynamic>> selectedFiles,
    required String torrentId,
    required String torrentName,
    required String apiKey,
    required List<String> links,
    required String torrentHash,
  }) async {
    if (selectedFiles.isEmpty) return;

    // Show confirmation dialog
    final totalSize = selectedFiles.fold<int>(
      0,
      (sum, file) => sum + (int.tryParse(file['size']?.toString() ?? '0') ?? 0),
    );

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Download Files'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Download ${selectedFiles.length} file${selectedFiles.length == 1 ? '' : 's'}?'),
            const SizedBox(height: 16),
            Text(
              'Total size: ${Formatters.formatFileSize(totalSize)}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.download),
            label: const Text('Download'),
          ),
        ],
      ),
    ) ?? false;

    if (!confirmed || !mounted) return;

    // Show progress
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text(
              'Queueing downloads...',
              style: TextStyle(color: Colors.white),
            ),
          ],
        ),
      ),
    );

    // Queue downloads for each file
    // CRITICAL: Following the SAME pattern as debrid_downloads_screen.dart
    // We DON'T unrestrict everything upfront - we queue with metadata for lazy unrestriction
    int successCount = 0;
    int failCount = 0;

    for (final file in selectedFiles) {
      try {
        final linkIndex = file['_linkIndex'] as int? ?? -1;

        // Validate linkIndex
        if (linkIndex < 0 || linkIndex >= links.length) {
          failCount++;
          continue;
        }

        // Get restricted link (no API call - instant!)
        final restrictedLink = links[linkIndex];
        final fileName = (file['_fullPath'] as String?) ?? 'Unknown';

        // Pass metadata for lazy unrestriction
        // The download service will unrestrict when ready
        final meta = jsonEncode({
          'restrictedLink': restrictedLink,
          'apiKey': apiKey,
          'torrentHash': torrentHash,
          'fileIndex': linkIndex,
        });

        // Queue download instantly (download service will unrestrict when ready)
        await DownloadService.instance.enqueueDownload(
          url: restrictedLink, // Pass restricted link (will be replaced by download service)
          fileName: fileName.split('/').last,
          meta: meta,
          torrentName: torrentName,
          context: mounted ? context : null,
        );

        successCount++;
      } catch (e) {
        // Silently handle individual file failures during batch operations
        failCount++;
      }
    }

    // Close progress dialog
    if (mounted) Navigator.of(context).pop();

    // Show result
    if (successCount > 0 && failCount == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Queued $successCount file${successCount == 1 ? '' : 's'} for download',
          ),
          backgroundColor: const Color(0xFF10B981),
        ),
      );
    } else if (successCount > 0 && failCount > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Queued $successCount file${successCount == 1 ? '' : 's'}, $failCount failed',
          ),
          backgroundColor: const Color(0xFFEF4444),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to queue any files for download'),
          backgroundColor: Color(0xFFEF4444),
        ),
      );
    }
  }

  Future<void> _downloadFile(
    String downloadLink,
    String fileName, {
    String? torrentName,
  }) async {
    try {
      final meta = jsonEncode({
        'restrictedLink': downloadLink,
        'apiKey': _apiKey ?? '',
        'torrentHash': '',
        'fileIndex': '',
      });
      await DownloadService.instance.enqueueDownload(
        url: downloadLink, // Use restricted link directly
        fileName: fileName,
        context: context,
        torrentName:
            torrentName ??
            fileName, // Use provided torrent name or fileName as fallback
        meta: meta,
      );

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.download,
                  color: Colors.white,
                  size: 16,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Download started! Check Downloads tab for progress.',
                  style: TextStyle(fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
          backgroundColor: const Color(0xFF1E293B),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          margin: const EdgeInsets.all(16),
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.error, color: Colors.white, size: 16),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Failed to start download: ${e.toString()}',
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
          backgroundColor: const Color(0xFF1E293B),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          margin: const EdgeInsets.all(16),
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  Widget _buildEngineStatusChips(BuildContext context) {
    final List<Widget> chips = [];

    final engines = [
      {'key': 'torrents_csv', 'short': 'TCSV', 'name': 'Torrents CSV'},
      {'key': 'pirate_bay', 'short': 'TPB', 'name': 'Pirate Bay'},
      {'key': 'yts', 'short': 'YTS', 'name': 'YTS'},
      {'key': 'solid_torrents', 'short': 'ST', 'name': 'SolidTorrents'},
      {'key': 'torrentio', 'short': 'TIO', 'name': 'Torrentio'},
      {'key': 'knaben', 'short': 'KNB', 'name': 'Knaben'},
    ];

    for (final engine in engines) {
      final key = engine['key'] as String;
      final short = engine['short'] as String;
      final count = _engineCounts[key] ?? 0;
      final hasError = _engineErrors.containsKey(key);

      if (count > 0 || hasError) {
        final isSelected = _selectedEngineFilter == key;
        chips.add(
          GestureDetector(
            onTap: hasError ? null : () {
              setState(() {
                // Toggle filter: if already selected, deselect (show all)
                _selectedEngineFilter = isSelected ? null : key;
                // Apply filter to current torrents
                _applyEngineFilter();
              });
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: hasError
                    ? Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.3)
                    : isSelected
                        ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.8)
                        : Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: hasError
                      ? Theme.of(context).colorScheme.error.withValues(alpha: 0.5)
                      : isSelected
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
                  width: isSelected ? 2 : 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    hasError ? Icons.error_outline : isSelected ? Icons.filter_alt : Icons.check_circle,
                    size: 14,
                    color: hasError
                        ? Theme.of(context).colorScheme.error
                        : isSelected
                            ? Theme.of(context).colorScheme.onPrimary
                            : Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    short,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: hasError
                          ? Theme.of(context).colorScheme.onErrorContainer
                          : isSelected
                              ? Theme.of(context).colorScheme.onPrimary
                              : Theme.of(context).colorScheme.onPrimaryContainer,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                      fontSize: 11,
                    ),
                  ),
                  if (!hasError && count > 0) ...[
                    const SizedBox(width: 4),
                    Text(
                      '$count',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: isSelected
                            ? Theme.of(context).colorScheme.onPrimary.withValues(alpha: 0.9)
                            : Theme.of(context).colorScheme.onPrimaryContainer.withValues(alpha: 0.8),
                        fontSize: 10,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      }
    }

    if (chips.isEmpty) {
      return Text(
        'No results',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
        ),
      );
    }

    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: chips,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFF0F172A), // Slate 900 - Deep blue-black
                const Color(0xFF1E293B), // Slate 800 - Rich blue-grey
                const Color(0xFF1E3A8A), // Blue 900 - Deep premium blue
              ],
            ),
          ),
          child: SafeArea(
            child: FocusTraversalGroup(
              policy: OrderedTraversalPolicy(),
              child: Column(
                children: [
                  // Search Box
              Container(
                margin: const EdgeInsets.all(8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      const Color(
                        0xFF1E40AF,
                      ).withValues(alpha: 0.9), // Blue 800
                      const Color(
                        0xFF1E3A8A,
                      ).withValues(alpha: 0.8), // Blue 900
                    ],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF1E40AF).withValues(alpha: 0.4),
                      blurRadius: 25,
                      offset: const Offset(0, 15),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Search Input + Advanced action
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _SearchTextField(
                            controller: _searchController,
                            focusNode: _searchFocusNode,
                            searchMode: _searchMode,
                            isTelevision: _isTelevision,
                            selectedImdbTitle: _selectedImdbTitle,
                            hasAutocompleteResults: _imdbAutocompleteResults.isNotEmpty,
                            hasAutocompleteFocusNodes: _autocompleteFocusNodes.isNotEmpty,
                            isSeries: _isSeries,
                            autocompleteFocusNodes: _autocompleteFocusNodes,
                            seasonInputFocusNode: _seasonInputFocusNode,
                            onClearPressed: () {
                              _searchController.clear();
                              _handleSearchFieldChanged('');
                              _searchFocusNode.requestFocus();
                            },
                            onChanged: _handleSearchFieldChanged,
                            onSubmitted: (query) {
                              // In IMDB mode, don't trigger search on submit unless a selection has been made
                              if (_searchMode == SearchMode.keyword) {
                                _searchTorrents(query);
                              } else if (_searchMode == SearchMode.imdb) {
                                // On TV: Trigger autocomplete when Enter is pressed
                                if (_isTelevision && _selectedImdbTitle == null) {
                                  _onImdbSearchTextChanged(query);
                                } else if (_selectedImdbTitle != null) {
                                  // Already has selection, can re-search
                                  _createAdvancedSelectionAndSearch();
                                }
                              }
                            },
                            onFocusChange: (focused) {
                              _searchFocused.value = focused; // No setState needed!
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        _buildModeSelector(),
                      ],
                    ),

                    // Helper text for IMDB mode on TV
                    if (_searchMode == SearchMode.imdb && _isTelevision && _selectedImdbTitle == null) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF7C3AED).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: const Color(0xFF7C3AED).withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.info_outline,
                              color: Color(0xFF7C3AED),
                              size: 16,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Type a title and press Enter to search IMDB',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.9),
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    // IMDB Smart Search Mode UI components
                    if (_searchMode == SearchMode.imdb) ...[
                      // Autocomplete dropdown
                      _buildImdbAutocompleteDropdown(),
                      // Active selection chip
                      _buildImdbSelectionChip(),
                      // Type selector and S/E inputs
                      _buildImdbTypeAndEpisodeControls(),
                    ],

                    // Search Engine Toggles
                    const SizedBox(height: 16),
                    _buildProvidersAccordion(context),
                  ],
                ),
              ),

              // Content Section
              Expanded(
                child: Builder(
                  builder: (context) {
                    if (_isLoading) {
                      return ListView.builder(
                        padding: const EdgeInsets.only(
                          bottom: 16,
                          left: 12,
                          right: 12,
                          top: 12,
                        ),
                        itemCount: 6,
                        itemBuilder: (context, i) {
                          return Container(
                            key: ValueKey('shimmer-$i'),
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(
                                0xFF1E293B,
                              ).withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: const [
                                Shimmer(width: double.infinity, height: 18),
                                SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(child: Shimmer(height: 22)),
                                    SizedBox(width: 8),
                                    Shimmer(width: 70, height: 22),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      );
                    }

                    if (_errorMessage.isNotEmpty) {
                      return ListView(
                        padding: const EdgeInsets.only(bottom: 16),
                        children: [
                          Container(
                            margin: const EdgeInsets.all(12),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [Color(0xFF7F1D1D), Color(0xFF991B1B)],
                              ),
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(
                                    0xFFEF4444,
                                  ).withValues(alpha: 0.3),
                                  blurRadius: 20,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(
                                    Icons.error_outline_rounded,
                                    color: Colors.white,
                                    size: 36,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                const Text(
                                  'Oops! Something went wrong',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  _errorMessage,
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.9),
                                    fontSize: 12,
                                  ),
                                  textAlign: TextAlign.center,
                                  softWrap: true,
                                  overflow: TextOverflow.visible,
                                ),
                                const SizedBox(height: 12),
                                ElevatedButton.icon(
                                  onPressed: () =>
                                      _searchTorrents(_searchController.text),
                                  icon: const Icon(Icons.refresh_rounded),
                                  label: const Text('Try Again'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.white,
                                    foregroundColor: const Color(0xFF7F1D1D),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    }

                    if (!_hasSearched) {
                      return _buildHistorySection();
                    }

                    if (_torrents.isEmpty) {
                      final bool hasRawResults = _allTorrents.isNotEmpty;
                      final bool noMatchesBecauseOfFilters =
                          hasRawResults && _hasActiveFilters;
                      return ListView(
                        padding: const EdgeInsets.only(bottom: 16),
                        children: [
                          if (_showingTorboxCachedOnly)
                            _buildTorboxCachedOnlyNotice(),
                          Container(
                            margin: const EdgeInsets.all(12),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [Color(0xFF1E293B), Color(0xFF334155)],
                              ),
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.3),
                                  blurRadius: 20,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const SizedBox(height: 16),
                                Text(
                                  noMatchesBecauseOfFilters
                                      ? 'No Filters Matched'
                                      : 'No Results Found',
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  noMatchesBecauseOfFilters
                                      ? 'Current filters hide every match. Try adjusting them.'
                                      : 'Try different keywords or check your spelling',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: Colors.white70,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                if (noMatchesBecauseOfFilters)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 16),
                                    child: ElevatedButton.icon(
                                      onPressed: _clearAllFilters,
                                      icon: const Icon(
                                        Icons.filter_alt_off_rounded,
                                      ),
                                      label: const Text('Clear Filters'),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      );
                    }
                    final bool showCachedOnlyBanner = _showingTorboxCachedOnly;
                    final int metadataRows = showCachedOnlyBanner ? 3 : 2;

                    // Restore scroll position if pending
                    if (_pendingScrollOffset != null) {
                      final offset = _pendingScrollOffset!;
                      _pendingScrollOffset = null;
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted && _resultsScrollController.hasClients) {
                          final maxScroll = _resultsScrollController.position.maxScrollExtent;
                          final targetOffset = offset > maxScroll ? maxScroll : offset;
                          if (targetOffset > 0) {
                            _resultsScrollController.jumpTo(targetOffset);
                          }
                        }
                      });
                    }

                    return ListView.builder(
                      controller: _resultsScrollController,
                      padding: const EdgeInsets.only(bottom: 16),
                      itemCount: _torrents.length + metadataRows,
                      itemBuilder: (context, index) {
                        if (index == 0) {
                          return FadeTransition(
                            opacity: _listAnimation,
                            child: Container(
                              margin: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    Color(0xFF1E40AF),
                                    Color(0xFF1E3A8A),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(8),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(
                                      0xFF1E40AF,
                                    ).withValues(alpha: 0.4),
                                    blurRadius: 8,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(4),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withValues(
                                            alpha: 0.2,
                                          ),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: const Icon(
                                          Icons.search_rounded,
                                          color: Colors.white,
                                          size: 14,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          '${_torrents.length} Result${_torrents.length == 1 ? '' : 's'}${_showingTorboxCachedOnly ? ' (Torbox cached)' : ''}',
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  _buildEngineStatusChips(context),
                                ],
                              ),
                            ),
                          );
                        }
                        if (index == 1) {
                          return Container(
                            margin: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(
                                0xFF1E293B,
                              ).withValues(alpha: 0.8),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: const Color(
                                  0xFF3B82F6,
                                ).withValues(alpha: 0.2),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(
                                    0xFF1E40AF,
                                  ).withValues(alpha: 0.1),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      Icons.sort_rounded,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                      size: 16,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Sort by:',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: ValueListenableBuilder<bool>(
                                        valueListenable: _sortDropdownFocused,
                                        builder: (context, isFocused, child) => Container(
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(4),
                                            border: isFocused
                                                ? Border.all(color: const Color(0xFF3B82F6), width: 2)
                                                : null,
                                          ),
                                          child: child,
                                        ),
                                        child: DropdownButton<String>(
                                          value: _sortBy,
                                          focusNode: _sortDropdownFocusNode,
                                          onChanged: (String? newValue) {
                                            if (newValue != null) {
                                              setState(() {
                                                _sortBy = newValue;
                                              });
                                              _sortTorrents(reuseMetadata: true); // Reuse parsed metadata
                                            }
                                          },
                                          items: const [
                                            DropdownMenuItem(
                                              value: 'relevance',
                                              child: Text(
                                                'Relevance',
                                                style: TextStyle(fontSize: 12),
                                              ),
                                            ),
                                            DropdownMenuItem(
                                              value: 'name',
                                              child: Text(
                                                'Name',
                                                style: TextStyle(fontSize: 12),
                                              ),
                                            ),
                                            DropdownMenuItem(
                                              value: 'size',
                                              child: Text(
                                                'Size',
                                                style: TextStyle(fontSize: 12),
                                              ),
                                            ),
                                            DropdownMenuItem(
                                              value: 'seeders',
                                              child: Text(
                                                'Seeders',
                                                style: TextStyle(fontSize: 12),
                                              ),
                                            ),
                                            DropdownMenuItem(
                                              value: 'date',
                                              child: Text(
                                                'Date',
                                                style: TextStyle(fontSize: 12),
                                              ),
                                            ),
                                          ],
                                          style: TextStyle(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onSurface,
                                            fontSize: 12,
                                          ),
                                          underline: Container(),
                                          icon: Icon(
                                            Icons.arrow_drop_down,
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant,
                                            size: 16,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Focus(
                                      focusNode: _sortDirectionFocusNode,
                                      onFocusChange: (focused) {
                                        _sortDirectionFocused.value = focused;
                                        if (focused && _isTelevision) {
                                          _scrollToFocusNode(_sortDirectionFocusNode);
                                        }
                                      },
                                      onKeyEvent: (node, event) {
                                        if (event is KeyDownEvent &&
                                            (event.logicalKey == LogicalKeyboardKey.select ||
                                                event.logicalKey == LogicalKeyboardKey.enter)) {
                                          setState(() {
                                            _sortAscending = !_sortAscending;
                                          });
                                          _sortTorrents(reuseMetadata: true); // Reuse parsed metadata
                                          return KeyEventResult.handled;
                                        }
                                        return KeyEventResult.ignored;
                                      },
                                      child: ValueListenableBuilder<bool>(
                                        valueListenable: _sortDirectionFocused,
                                        builder: (context, isFocused, child) => Container(
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(4),
                                            border: isFocused
                                                ? Border.all(color: const Color(0xFF3B82F6), width: 2)
                                                : null,
                                          ),
                                          child: child,
                                        ),
                                        child: IconButton(
                                          onPressed: () {
                                            setState(() {
                                              _sortAscending = !_sortAscending;
                                            });
                                            _sortTorrents(reuseMetadata: true); // Reuse parsed metadata
                                          },
                                          icon: Icon(
                                            _sortAscending
                                                ? Icons.arrow_upward
                                                : Icons.arrow_downward,
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant,
                                            size: 16,
                                          ),
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(
                                            minWidth: 24,
                                            minHeight: 24,
                                          ),
                                        ),
                                      ),
                                    ),
                                    Focus(
                                      focusNode: _filterButtonFocusNode,
                                      onFocusChange: (focused) {
                                        _filterButtonFocused.value = focused;
                                        if (focused && _isTelevision) {
                                          _scrollToFocusNode(_filterButtonFocusNode);
                                        }
                                      },
                                      onKeyEvent: (node, event) {
                                        if (event is KeyDownEvent &&
                                            (event.logicalKey == LogicalKeyboardKey.select ||
                                                event.logicalKey == LogicalKeyboardKey.enter)) {
                                          if (!(_allTorrents.isEmpty && !_hasActiveFilters)) {
                                            _openFiltersSheet();
                                          }
                                          return KeyEventResult.handled;
                                        }
                                        return KeyEventResult.ignored;
                                      },
                                      child: ValueListenableBuilder<bool>(
                                        valueListenable: _filterButtonFocused,
                                        builder: (context, isFocused, child) => Container(
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(4),
                                            border: isFocused
                                                ? Border.all(color: const Color(0xFF3B82F6), width: 2)
                                                : null,
                                          ),
                                          child: child,
                                        ),
                                        child: IconButton(
                                          onPressed:
                                              (_allTorrents.isEmpty &&
                                                  !_hasActiveFilters)
                                              ? null
                                              : _openFiltersSheet,
                                          icon: Stack(
                                            clipBehavior: Clip.none,
                                            children: [
                                              Icon(
                                                Icons.filter_list_rounded,
                                                color:
                                                    (_allTorrents.isEmpty &&
                                                        !_hasActiveFilters)
                                                    ? Theme.of(
                                                        context,
                                                      ).disabledColor
                                                    : Theme.of(context)
                                                          .colorScheme
                                                          .onSurfaceVariant,
                                                size: 18,
                                              ),
                                              if (_hasActiveFilters)
                                                Positioned(
                                                  right: -2,
                                                  top: -2,
                                                  child: Container(
                                                    width: 8,
                                                    height: 8,
                                                    decoration: const BoxDecoration(
                                                      color: Color(0xFF38BDF8),
                                                      shape: BoxShape.circle,
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                          tooltip: 'Filter results',
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                if (_hasActiveFilters)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 8.0),
                                    child: Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [
                                        ..._buildActiveFilterBadges()
                                            .map(
                                              (badge) => Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 4,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: Colors.white
                                                      .withValues(alpha: 0.08),
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                        999,
                                                      ),
                                                ),
                                                child: Text(
                                                  badge,
                                                  style: const TextStyle(
                                                    fontSize: 11,
                                                    color: Colors.white70,
                                                  ),
                                                ),
                                              ),
                                            )
                                            .toList(),
                                        Focus(
                                          focusNode: _clearFiltersButtonFocusNode,
                                          onFocusChange: (focused) {
                                            _clearFiltersButtonFocused.value = focused; // No setState needed!
                                          },
                                          onKeyEvent: (node, event) {
                                            if (event is KeyDownEvent &&
                                                (event.logicalKey == LogicalKeyboardKey.select ||
                                                    event.logicalKey == LogicalKeyboardKey.enter)) {
                                              _clearAllFilters();
                                              return KeyEventResult.handled;
                                            }
                                            return KeyEventResult.ignored;
                                          },
                                          child: ValueListenableBuilder<bool>(
                                            valueListenable: _clearFiltersButtonFocused,
                                            builder: (context, isFocused, child) => Container(
                                              decoration: BoxDecoration(
                                                borderRadius: BorderRadius.circular(4),
                                                border: isFocused
                                                    ? Border.all(color: const Color(0xFF3B82F6), width: 2)
                                                    : null,
                                              ),
                                              child: child,
                                            ),
                                            child: TextButton(
                                              onPressed: _clearAllFilters,
                                              child: const Text(
                                                'Clear filters',
                                                style: TextStyle(fontSize: 11),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          );
                        }

                        if (showCachedOnlyBanner && index == 2) {
                          return _buildTorboxCachedOnlyNotice();
                        }

                        final torrent = _torrents[index - metadataRows];
                        return RepaintBoundary(
                          child: Padding(
                            key: ValueKey(torrent.infohash),
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: _buildTorrentCard(
                              torrent,
                              index - metadataRows,
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
        ),
        // Bulk Add Floating Action Button
        if (_torrents.isNotEmpty && !_isBulkAdding && !_isTelevision)
          Positioned(
            right: 16,
            bottom: 16,
            child: FloatingActionButton.extended(
              onPressed: _showBulkAddDialog,
              backgroundColor: const Color(0xFF6366F1),
              elevation: 8,
              icon: const Icon(Icons.playlist_add, color: Colors.white),
              label: const Text(
                'Bulk Add',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildTorboxCachedOnlyNotice() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E3A8A).withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: const Color(0xFF38BDF8).withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline_rounded,
            color: Color(0xFF38BDF8),
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Showing Torbox cached results only. Disable "Check Torbox cache during searches" in Torbox settings to see every result.',
              style: TextStyle(
                fontSize: 12,
                color: Colors.white.withValues(alpha: 0.85),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Build size chip or pack type chip based on coverage type
  Widget _buildSizeOrPackChip(Torrent torrent) {
    // For single episodes or unknown coverage: show actual size
    if (torrent.coverageType == null ||
        torrent.coverageType == 'singleEpisode') {
      return StatChip(
        icon: Icons.storage_rounded,
        text: Formatters.formatFileSize(torrent.sizeBytes),
        color: const Color(0xFF0EA5E9), // Sky 500 - Premium blue
      );
    }

    // For packs: show pack type label instead of misleading individual file size
    switch (torrent.coverageType) {
      case 'completeSeries':
        return StatChip(
          icon: Icons.video_library_rounded,
          text: 'Complete Series',
          color: const Color(0xFF8B5CF6), // Violet 500 - Rich purple
        );

      case 'multiSeasonPack':
        return StatChip(
          icon: Icons.video_collection_rounded,
          text: 'Multi-Season',
          color: const Color(0xFFF59E0B), // Amber 500 - Warm amber
        );

      case 'seasonPack':
        return StatChip(
          icon: Icons.folder_rounded,
          text: 'Season Pack',
          color: const Color(0xFF22C55E), // Green 500 - Fresh green
        );

      default:
        // Fallback for unknown pack types
        return StatChip(
          icon: Icons.folder_rounded,
          text: 'Multi-file',
          color: const Color(0xFF6B7280), // Gray 500
        );
    }
  }

  // ============================================================================
  // Torrent Search History UI
  // ============================================================================

  Widget _buildHistorySection() {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _buildHistoryHeaderRow(),
        const SizedBox(height: 12),
        if (_searchHistory.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF1E293B), Color(0xFF334155)],
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.search_rounded,
                  size: 48,
                  color: Colors.white.withValues(alpha: 0.3),
                ),
                const SizedBox(height: 16),
                Text(
                  'No search history yet',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Your recent torrents will appear here',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.white.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ),
        if (_searchHistory.isNotEmpty)
        ..._searchHistory.asMap().entries.map((entry) {
          final index = entry.key;
          final historyItem = entry.value;
          final torrentJson = historyItem['torrent'] as Map<String, dynamic>;
          final torrent = Torrent.fromJson(torrentJson);
          final service = historyItem['service'] as String;

          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              border: Border.all(
                color: const Color(0xFFFBBF24).withValues(alpha: 0.3),
                width: 1.5,
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFBBF24).withValues(alpha: 0.1),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                if (index == 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFBBF24).withValues(alpha: 0.15),
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(14),
                        topRight: Radius.circular(14),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.history_rounded, size: 14, color: Color(0xFFFBBF24)),
                        const SizedBox(width: 6),
                        Text(
                          'Last clicked • ${_getServiceLabel(service)}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFFFBBF24),
                          ),
                        ),
                      ],
                    ),
                  ),
                _buildHistoryTorrentCard(torrent, index),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildHistoryTorrentCard(Torrent torrent, int index) {
    // For TV mode, use dedicated history focus nodes
    if (_isTelevision && index < _historyCardFocusNodes.length) {
      return _TorrentCard(
        torrent: torrent,
        index: index,
        focusNode: _historyCardFocusNodes[index],
        isTelevision: _isTelevision,
        apiKey: _apiKey,
        torboxApiKey: _torboxApiKey,
        torboxCacheStatus: _torboxCacheStatus,
        realDebridIntegrationEnabled: _realDebridIntegrationEnabled,
        torboxIntegrationEnabled: _torboxIntegrationEnabled,
        pikpakEnabled: _pikpakEnabled,
        torboxCacheCheckEnabled: _torboxCacheCheckEnabled,
        isSeries: _isSeries,
        selectedImdbTitle: _selectedImdbTitle,
        hasSeasonData: _availableSeasons != null && _availableSeasons!.isNotEmpty,
        selectedSeason: _selectedSeason,
        seasonInputFocusNode: _seasonInputFocusNode,
        onCardActivated: () => _handleTorrentCardActivated(torrent, index),
        onCopyMagnet: () => _copyMagnetLink(torrent.infohash),
        onAddToDebrid: _addToRealDebrid,
        onAddToTorbox: _addToTorbox,
        onAddToPikPak: _sendToPikPak,
        onShowFileSelection: _showFileSelectionDialog,
        buildSizeOrPackChip: _buildSizeOrPackChip,
        buildSourceStatChip: _buildSourceStatChip,
        torboxResultIsCached: _torboxResultIsCached,
        searchFocusNode: _searchFocusNode,
        episodeInputFocusNode: _episodeInputFocusNode,
        filterButtonFocusNode: _filterButtonFocusNode,
      );
    }

    // For non-TV, use regular non-TV card content
    return _buildNonTVCardContent(torrent);
  }

  Widget _buildHistoryHeaderRow() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1E293B), Color(0xFF334155)],
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.history_rounded, color: Color(0xFFFBBF24), size: 20),
          const SizedBox(width: 8),
          const Text(
            'Recent Searches',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          const Spacer(),
          // History enabled label
          Text(
            _historyTrackingEnabled ? 'History' : 'Disabled',
            style: TextStyle(
              fontSize: 11,
              color: _historyTrackingEnabled
                  ? const Color(0xFF22C55E)
                  : Colors.white.withValues(alpha: 0.5),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 8),
          // Disable Switch
          Focus(
            focusNode: _historyDisableSwitchFocusNode,
            onFocusChange: (focused) {
              _historyDisableSwitchFocused.value = focused; // No setState needed!
            },
            onKeyEvent: (node, event) {
              if (event is KeyDownEvent &&
                  (event.logicalKey == LogicalKeyboardKey.select ||
                      event.logicalKey == LogicalKeyboardKey.enter ||
                      event.logicalKey == LogicalKeyboardKey.space)) {
                _toggleHistoryTracking(!_historyTrackingEnabled);
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: ValueListenableBuilder<bool>(
              valueListenable: _historyDisableSwitchFocused,
              builder: (context, isFocused, child) => Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: isFocused
                      ? Border.all(color: Colors.white, width: 2)
                      : null,
                ),
                child: child,
              ),
              child: Transform.scale(
                scale: 0.75,
                child: Switch(
                  value: _historyTrackingEnabled,
                  onChanged: _toggleHistoryTracking,
                  activeColor: const Color(0xFF22C55E),
                  inactiveThumbColor: Colors.white.withValues(alpha: 0.7),
                  inactiveTrackColor: Colors.white.withValues(alpha: 0.2),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Clear Button
          Focus(
            focusNode: _historyClearButtonFocusNode,
            onFocusChange: (focused) {
              _historyClearButtonFocused.value = focused; // No setState needed!
            },
            onKeyEvent: (node, event) {
              if (event is KeyDownEvent &&
                  (event.logicalKey == LogicalKeyboardKey.select ||
                      event.logicalKey == LogicalKeyboardKey.enter)) {
                _clearHistory();
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: InkWell(
              onTap: _clearHistory,
              borderRadius: BorderRadius.circular(8),
              child: ValueListenableBuilder<bool>(
                valueListenable: _historyClearButtonFocused,
                builder: (context, isFocused, child) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: isFocused
                        ? const Color(0xFFEF4444).withValues(alpha: 0.2)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isFocused
                          ? const Color(0xFFEF4444)
                          : const Color(0xFFEF4444).withValues(alpha: 0.3),
                      width: isFocused ? 2 : 1,
                    ),
                  ),
                  child: child,
                ),
                child: Row(
                  children: [
                    const Icon(Icons.clear_all_rounded, size: 16, color: Color(0xFFEF4444)),
                    const SizedBox(width: 4),
                    const Text(
                      'Clear',
                      style: TextStyle(fontSize: 11, color: Color(0xFFEF4444), fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTorrentCard(Torrent torrent, int index) {
    // For TV mode, use the new isolated _TorrentCard widget
    if (_isTelevision && index < _cardFocusNodes.length) {
      return _TorrentCard(
        torrent: torrent,
        index: index,
        focusNode: _cardFocusNodes[index],
        isTelevision: _isTelevision,
        apiKey: _apiKey,
        torboxApiKey: _torboxApiKey,
        torboxCacheStatus: _torboxCacheStatus,
        realDebridIntegrationEnabled: _realDebridIntegrationEnabled,
        torboxIntegrationEnabled: _torboxIntegrationEnabled,
        pikpakEnabled: _pikpakEnabled,
        torboxCacheCheckEnabled: _torboxCacheCheckEnabled,
        isSeries: _isSeries,
        selectedImdbTitle: _selectedImdbTitle,
        hasSeasonData: _availableSeasons != null && _availableSeasons!.isNotEmpty,
        selectedSeason: _selectedSeason,
        seasonInputFocusNode: _seasonInputFocusNode,
        onCardActivated: () => _handleTorrentCardActivated(torrent, index),
        onCopyMagnet: () => _copyMagnetLink(torrent.infohash),
        onAddToDebrid: _addToRealDebrid,
        onAddToTorbox: _addToTorbox,
        onAddToPikPak: _sendToPikPak,
        onShowFileSelection: _showFileSelectionDialog,
        buildSizeOrPackChip: _buildSizeOrPackChip,
        buildSourceStatChip: _buildSourceStatChip,
        torboxResultIsCached: _torboxResultIsCached,
        searchFocusNode: _searchFocusNode,
        episodeInputFocusNode: _episodeInputFocusNode,
        filterButtonFocusNode: _filterButtonFocusNode,
      );
    }

    // For non-TV mode, use GestureDetector with inline card content
    return GestureDetector(
      onTap: () {
        // Navigate to torrent details or perform default action
        // For now, just log or do nothing since TV has the smart action
      },
      child: _buildNonTVCardContent(torrent),
    );
  }

  Widget _buildNonTVCardContent(Torrent torrent) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF1E293B), // Slate 800
            Color(0xFF334155), // Slate 700
          ],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title Row
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    torrent.displayTitle,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                    maxLines: 5,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () => _copyMagnetLink(torrent.infohash),
                  tooltip: 'Copy magnet link',
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  style: IconButton.styleFrom(
                    backgroundColor: const Color(0xFF1D2A3F),
                    foregroundColor: const Color(0xFF60A5FA),
                    padding: const EdgeInsets.all(10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: const Color(0xFF3B82F6).withValues(alpha: 0.35),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Stats Grid
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _buildSizeOrPackChip(torrent),
                StatChip(
                  icon: Icons.upload_rounded,
                  text: '${torrent.seeders}',
                  color: const Color(0xFF22C55E),
                ),
                StatChip(
                  icon: Icons.download_rounded,
                  text: '${torrent.leechers}',
                  color: const Color(0xFFF59E0B),
                ),
                _buildSourceStatChip(torrent.source),
              ],
            ),
            const SizedBox(height: 10),

            // Date
            Row(
              children: [
                Icon(
                  Icons.schedule_rounded,
                  color: Colors.white.withValues(alpha: 0.6),
                  size: 14,
                ),
                const SizedBox(width: 4),
                Text(
                  Formatters.formatDate(torrent.createdUnix),
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.white.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Action Buttons - Get the index for this torrent
            _buildNonTVActionButtons(torrent, _torrents.indexOf(torrent)),
          ],
        ),
      ),
    );
  }

  Widget _buildNonTVActionButtons(Torrent torrent, int index) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompactLayout = constraints.maxWidth < 360;

        Widget buildTorboxButton() {
          final bool isCached = _torboxResultIsCached(torrent.infohash);
          final gradientColors = isCached
              ? const [Color(0xFF7C3AED), Color(0xFFDB2777)]
              : const [Color(0xFF475569), Color(0xFF1F2937)];
          final shadowColor = isCached
              ? const Color(0xFF7C3AED).withValues(alpha: 0.35)
              : const Color(0xFF1F2937).withValues(alpha: 0.25);
          final textColor = isCached ? Colors.white : Colors.white70;

          return Opacity(
            opacity: isCached ? 1.0 : 0.55,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                focusColor: const Color(0xFF7C3AED).withValues(alpha: 0.25),
                onTap: isCached ? () => _addToTorbox(torrent.infohash, torrent.name) : null,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: LinearGradient(
                      colors: gradientColors,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: shadowColor,
                        spreadRadius: 0,
                        blurRadius: 12,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.flash_on_rounded, color: textColor, size: 16),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          'Torbox',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.2,
                            color: textColor,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.expand_more_rounded, color: textColor.withValues(alpha: 0.7), size: 18),
                    ],
                  ),
                ),
              ),
            ),
          );
        }

        Widget buildRealDebridButton() {
          return Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              focusColor: const Color(0xFF6366F1).withValues(alpha: 0.25),
              onTap: () => _addToRealDebrid(torrent.infohash, torrent.name, index),
              onLongPress: () => _showFileSelectionDialog(torrent.infohash, torrent.name, index),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: const LinearGradient(
                    colors: [Color(0xFF1E40AF), Color(0xFF6366F1)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF1E40AF).withValues(alpha: 0.4),
                      spreadRadius: 0,
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.cloud_download_rounded, color: Colors.white, size: 16),
                    SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'Real-Debrid',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.2,
                          color: Colors.white,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                    SizedBox(width: 4),
                    Icon(Icons.expand_more_rounded, color: Colors.white70, size: 18),
                  ],
                ),
              ),
            ),
          );
        }

        Widget buildPikPakButton() {
          return Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              focusColor: const Color(0xFF0088CC).withValues(alpha: 0.25),
              onTap: () => _sendToPikPak(torrent.infohash, torrent.name),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0088CC), Color(0xFF229ED9)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF0088CC).withValues(alpha: 0.4),
                      spreadRadius: 0,
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.telegram, color: Colors.white, size: 16),
                    SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'PikPak',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.2,
                          color: Colors.white,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                    SizedBox(width: 4),
                    Icon(Icons.expand_more_rounded, color: Colors.white70, size: 18),
                  ],
                ),
              ),
            ),
          );
        }

        final Widget? torboxButton = (_torboxIntegrationEnabled && _torboxApiKey != null && _torboxApiKey!.isNotEmpty)
            ? buildTorboxButton()
            : null;
        final Widget? realDebridButton = (_realDebridIntegrationEnabled && _apiKey != null && _apiKey!.isNotEmpty)
            ? buildRealDebridButton()
            : null;
        final Widget? pikpakButton = _pikpakEnabled ? buildPikPakButton() : null;

        if (torboxButton == null && realDebridButton == null && pikpakButton == null) {
          return const SizedBox.shrink();
        }

        final int buttonCount = [torboxButton, realDebridButton, pikpakButton].where((b) => b != null).length;

        if (isCompactLayout) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (torboxButton != null) torboxButton,
              if (torboxButton != null && (realDebridButton != null || pikpakButton != null)) const SizedBox(height: 8),
              if (realDebridButton != null) realDebridButton,
              if (realDebridButton != null && pikpakButton != null) const SizedBox(height: 8),
              if (pikpakButton != null) pikpakButton,
            ],
          );
        }

        if (buttonCount == 3) {
          return Row(
            children: [
              Expanded(child: torboxButton!),
              const SizedBox(width: 8),
              Expanded(child: realDebridButton!),
              const SizedBox(width: 8),
              Expanded(child: pikpakButton!),
            ],
          );
        } else if (buttonCount == 2) {
          return Row(
            children: [
              if (torboxButton != null) Expanded(child: torboxButton),
              if (torboxButton != null && (realDebridButton != null || pikpakButton != null)) const SizedBox(width: 8),
              if (realDebridButton != null) Expanded(child: realDebridButton),
              if (realDebridButton != null && pikpakButton != null) const SizedBox(width: 8),
              if (pikpakButton != null) Expanded(child: pikpakButton),
            ],
          );
        } else {
          final Widget singleButton = torboxButton ?? realDebridButton ?? pikpakButton!;
          return SizedBox(width: double.infinity, child: singleButton);
        }
      },
    );
  }
}

/// Individual torrent card widget with isolated focus state
class _TorrentCard extends StatefulWidget {
  const _TorrentCard({
    required this.torrent,
    required this.index,
    required this.focusNode,
    required this.isTelevision,
    required this.apiKey,
    required this.torboxApiKey,
    required this.torboxCacheStatus,
    required this.realDebridIntegrationEnabled,
    required this.torboxIntegrationEnabled,
    required this.pikpakEnabled,
    required this.torboxCacheCheckEnabled,
    required this.isSeries,
    required this.selectedImdbTitle,
    required this.hasSeasonData,
    required this.selectedSeason,
    required this.seasonInputFocusNode,
    required this.onCardActivated,
    required this.onCopyMagnet,
    required this.onAddToDebrid,
    required this.onAddToTorbox,
    required this.onAddToPikPak,
    required this.onShowFileSelection,
    required this.buildSizeOrPackChip,
    required this.buildSourceStatChip,
    required this.torboxResultIsCached,
    required this.searchFocusNode,
    required this.episodeInputFocusNode,
    required this.filterButtonFocusNode,
  });

  final Torrent torrent;
  final int index;
  final FocusNode focusNode;
  final bool isTelevision;
  final String? apiKey;
  final String? torboxApiKey;
  final Map<String, bool>? torboxCacheStatus;
  final bool realDebridIntegrationEnabled;
  final bool torboxIntegrationEnabled;
  final bool pikpakEnabled;
  final bool torboxCacheCheckEnabled;
  final bool isSeries;
  final ImdbTitleResult? selectedImdbTitle;
  final bool hasSeasonData;
  final int? selectedSeason;
  final FocusNode seasonInputFocusNode;
  final VoidCallback onCardActivated;
  final VoidCallback onCopyMagnet;
  final void Function(String infohash, String name, int index) onAddToDebrid;
  final void Function(String infohash, String name) onAddToTorbox;
  final void Function(String infohash, String name) onAddToPikPak;
  final void Function(String infohash, String name, int index) onShowFileSelection;
  final Widget Function(Torrent) buildSizeOrPackChip;
  final Widget Function(String) buildSourceStatChip;
  final bool Function(String) torboxResultIsCached;
  final FocusNode searchFocusNode;
  final FocusNode episodeInputFocusNode;
  final FocusNode filterButtonFocusNode;

  @override
  State<_TorrentCard> createState() => _TorrentCardState();
}

class _TorrentCardState extends State<_TorrentCard> {
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocusChange);
    super.dispose();
  }

  void _onFocusChange() {
    if (!mounted) return;
    final focused = widget.focusNode.hasFocus;
    if (_isFocused != focused) {
      setState(() {
        _isFocused = focused;
      });

      // Auto-scroll on focus
      if (focused && widget.isTelevision) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final context = widget.focusNode.context;
          if (context != null) {
            Scrollable.ensureVisible(
              context,
              alignment: 0.2,
              duration: const Duration(milliseconds: 100),
              curve: Curves.easeOutCubic,
            );
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode,
      onKeyEvent: (node, event) {
        // Handle OK/Select/Enter press
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.select ||
                event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.space)) {
          widget.onCardActivated();
          return KeyEventResult.handled;
        }
        // Handle Arrow Up from first card - navigate to filter button in sort/filter row
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.arrowUp &&
            widget.index == 0) {
          // Navigate to the filter button in the sort/filter row
          widget.filterButtonFocusNode.requestFocus();
          return KeyEventResult.handled;
        }
        // Handle Back/Escape to return to search field (TV shortcut)
        if (widget.isTelevision && event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.escape ||
                event.logicalKey == LogicalKeyboardKey.backspace)) {
          // Only handle if this is the first card (avoid capturing all back presses)
          if (widget.index == 0) {
            widget.searchFocusNode.requestFocus();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: _buildCardContent(),
    );
  }

  Widget _buildCardContent() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF1E293B), // Slate 800
            Color(0xFF334155), // Slate 700
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: widget.isTelevision && _isFocused
            ? Border.all(color: const Color(0xFFE50914), width: 3)
            : null,
        boxShadow: widget.isTelevision && _isFocused
            ? [
                BoxShadow(
                  color: const Color(0xFFE50914).withValues(alpha: 0.4),
                  blurRadius: 8,
                  spreadRadius: 2,
                  offset: const Offset(0, 8),
                ),
              ]
            : null,
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title Row - Now with more space for title!
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    widget.torrent.displayTitle,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                    maxLines: 5,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (!widget.isTelevision) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: widget.onCopyMagnet,
                    tooltip: 'Copy magnet link',
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFF1D2A3F),
                      foregroundColor: const Color(0xFF60A5FA),
                      padding: const EdgeInsets.all(10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color: const Color(0xFF3B82F6).withValues(alpha: 0.35),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),

            // Stats Grid - Now includes source instead of completed
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                widget.buildSizeOrPackChip(widget.torrent),
                StatChip(
                  icon: Icons.upload_rounded,
                  text: '${widget.torrent.seeders}',
                  color: const Color(0xFF22C55E), // Green 500 - Fresh green
                ),
                StatChip(
                  icon: Icons.download_rounded,
                  text: '${widget.torrent.leechers}',
                  color: const Color(0xFFF59E0B), // Amber 500 - Warm amber
                ),
                widget.buildSourceStatChip(widget.torrent.source),
              ],
            ),
            const SizedBox(height: 10),

            // Date
            Row(
              children: [
                Icon(
                  Icons.schedule_rounded,
                  color: Colors.white.withValues(alpha: 0.6),
                  size: 14,
                ),
                const SizedBox(width: 4),
                Text(
                  Formatters.formatDate(widget.torrent.createdUnix),
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.white.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Action Buttons (Hidden on TV since we use smart action on card click)
            if (!widget.isTelevision)
            LayoutBuilder(
              builder: (context, constraints) {
              final isCompactLayout = constraints.maxWidth < 360;

              Widget buildTorboxButton() {
                final bool isCached = widget.torboxResultIsCached(widget.torrent.infohash);
                final gradientColors = isCached
                    ? const [Color(0xFF7C3AED), Color(0xFFDB2777)]
                    : const [Color(0xFF475569), Color(0xFF1F2937)];
                final shadowColor = isCached
                    ? const Color(0xFF7C3AED).withValues(alpha: 0.35)
                    : const Color(0xFF1F2937).withValues(alpha: 0.25);
                final textColor = isCached ? Colors.white : Colors.white70;

                return Opacity(
                  opacity: isCached ? 1.0 : 0.55,
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      focusColor:
                          const Color(0xFF7C3AED).withValues(alpha: 0.25),
                      onTap: isCached
                          ? () => widget.onAddToTorbox(widget.torrent.infohash, widget.torrent.name)
                          : null,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          gradient: LinearGradient(
                            colors: gradientColors,
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: shadowColor,
                              spreadRadius: 0,
                              blurRadius: 12,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.flash_on_rounded,
                              color: textColor,
                              size: 16,
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                'Torbox',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.2,
                                  color: textColor,
                                ),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              Icons.expand_more_rounded,
                              color: textColor.withValues(alpha: 0.7),
                              size: 18,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }

              Widget buildRealDebridButton() {
                return Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    focusColor:
                        const Color(0xFF6366F1).withValues(alpha: 0.25),
                    onTap: () =>
                        widget.onAddToDebrid(widget.torrent.infohash, widget.torrent.name, widget.index),
                    onLongPress: () {
                      widget.onShowFileSelection(
                        widget.torrent.infohash,
                        widget.torrent.name,
                        widget.index,
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        gradient: const LinearGradient(
                          colors: [Color(0xFF1E40AF), Color(0xFF6366F1)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(
                              0xFF1E40AF,
                            ).withValues(alpha: 0.4),
                            spreadRadius: 0,
                            blurRadius: 12,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(
                            Icons.cloud_download_rounded,
                            color: Colors.white,
                            size: 16,
                          ),
                          SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              'Real-Debrid',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.2,
                                color: Colors.white,
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ),
                          SizedBox(width: 4),
                          Icon(
                            Icons.expand_more_rounded,
                            color: Colors.white70,
                            size: 18,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }

              Widget buildPikPakButton() {
                return Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    focusColor:
                        const Color(0xFF0088CC).withValues(alpha: 0.25),
                    onTap: () =>
                        widget.onAddToPikPak(widget.torrent.infohash, widget.torrent.name),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        gradient: const LinearGradient(
                          colors: [Color(0xFF0088CC), Color(0xFF229ED9)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(
                              0xFF0088CC,
                            ).withValues(alpha: 0.4),
                            spreadRadius: 0,
                            blurRadius: 12,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(
                            Icons.telegram,
                            color: Colors.white,
                            size: 16,
                          ),
                          SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              'PikPak',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.2,
                                color: Colors.white,
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ),
                          SizedBox(width: 4),
                          Icon(
                            Icons.expand_more_rounded,
                            color: Colors.white70,
                            size: 18,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }

              final Widget? torboxButton =
                  (widget.torboxIntegrationEnabled &&
                      widget.torboxApiKey != null &&
                      widget.torboxApiKey!.isNotEmpty)
                  ? buildTorboxButton()
                  : null;
              final Widget? realDebridButton =
                  (widget.realDebridIntegrationEnabled &&
                      widget.apiKey != null &&
                      widget.apiKey!.isNotEmpty)
                  ? buildRealDebridButton()
                  : null;
              final Widget? pikpakButton = widget.pikpakEnabled
                  ? buildPikPakButton()
                  : null;

              if (torboxButton == null && realDebridButton == null && pikpakButton == null) {
                return const SizedBox.shrink();
              }

              // Count active buttons
              final int buttonCount = [torboxButton, realDebridButton, pikpakButton]
                  .where((button) => button != null)
                  .length;

              if (isCompactLayout) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (torboxButton != null) torboxButton,
                    if (torboxButton != null && (realDebridButton != null || pikpakButton != null))
                      const SizedBox(height: 8),
                    if (realDebridButton != null) realDebridButton,
                    if (realDebridButton != null && pikpakButton != null)
                      const SizedBox(height: 8),
                    if (pikpakButton != null) pikpakButton,
                  ],
                );
              }

              // For non-compact layouts, show buttons in a row
              if (buttonCount == 3) {
                return Row(
                  children: [
                    Expanded(child: torboxButton!),
                    const SizedBox(width: 8),
                    Expanded(child: realDebridButton!),
                    const SizedBox(width: 8),
                    Expanded(child: pikpakButton!),
                  ],
                );
              } else if (buttonCount == 2) {
                return Row(
                  children: [
                    if (torboxButton != null) Expanded(child: torboxButton),
                    if (torboxButton != null && (realDebridButton != null || pikpakButton != null))
                      const SizedBox(width: 8),
                    if (realDebridButton != null) Expanded(child: realDebridButton),
                    if (realDebridButton != null && pikpakButton != null)
                      const SizedBox(width: 8),
                    if (pikpakButton != null) Expanded(child: pikpakButton),
                  ],
                );
              } else {
                final Widget singleButton = torboxButton ?? realDebridButton ?? pikpakButton!;
                return SizedBox(width: double.infinity, child: singleButton);
              }
            },
          ),
          // TV hint
          if (widget.isTelevision && _isFocused) ...[
            const SizedBox(height: 12),
            Text(
              'Press OK to add torrent',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 11,
                fontStyle: FontStyle.italic,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    ),
  );
  }
}

class _TorrentMetadata {
  final SeriesInfo seriesInfo;
  final QualityTier? qualityTier;
  final RipSourceCategory ripSource;
  final AudioLanguage? audioLanguage;

  const _TorrentMetadata({
    required this.seriesInfo,
    this.qualityTier,
    RipSourceCategory? ripSource,
    this.audioLanguage,
  }) : ripSource = ripSource ?? RipSourceCategory.other;
}

class _TorboxPlaylistItem {
  final TorboxFile file;
  final int originalIndex;
  final SeriesInfo seriesInfo;
  final String displayName;

  const _TorboxPlaylistItem({
    required this.file,
    required this.originalIndex,
    required this.seriesInfo,
    required this.displayName,
  });
}

class _PikPakPlaylistItem {
  final Map<String, dynamic> file;
  final int originalIndex;
  final SeriesInfo seriesInfo;
  final String displayName;

  const _PikPakPlaylistItem({
    required this.file,
    required this.originalIndex,
    required this.seriesInfo,
    required this.displayName,
  });
}

class _DebridActionTile extends StatefulWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool enabled;
  final bool autofocus;

  const _DebridActionTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
    required this.enabled,
    this.autofocus = false,
  });

  @override
  State<_DebridActionTile> createState() => _DebridActionTileState();
}

class _DebridActionTileState extends State<_DebridActionTile> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Focus(
      autofocus: widget.autofocus,
      onFocusChange: (focused) {
        if (mounted) {
          setState(() {
            _focused = focused;
          });
        }
      },
      onKeyEvent: (node, event) {
        if (widget.enabled &&
            event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.select ||
                event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.space)) {
          widget.onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: InkWell(
        onTap: widget.enabled ? widget.onTap : null,
        borderRadius: BorderRadius.circular(16),
        child: Opacity(
          opacity: widget.enabled ? 1.0 : 0.45,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFF111827),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _focused
                    ? widget.color
                    : const Color(0xFF1F2937),
                width: _focused ? 2 : 1,
              ),
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: _focused ? 0.3 : 0.14),
                blurRadius: _focused ? 20 : 16,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [widget.color, widget.color.withValues(alpha: 0.6)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(widget.icon, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.7),
                        height: 1.22,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Colors.white54),
            ],
          ),
        ),
      ),
      ),
    );
  }
}

// Optimized search TextField widget - extracted to prevent unnecessary parent rebuilds
class _SearchTextField extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final SearchMode searchMode;
  final bool isTelevision;
  final ImdbTitleResult? selectedImdbTitle;
  final bool hasAutocompleteResults;
  final bool hasAutocompleteFocusNodes;
  final bool isSeries;
  final List<FocusNode> autocompleteFocusNodes;
  final FocusNode seasonInputFocusNode;
  final VoidCallback onClearPressed;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final ValueChanged<bool> onFocusChange;

  const _SearchTextField({
    required this.controller,
    required this.focusNode,
    required this.searchMode,
    required this.isTelevision,
    required this.selectedImdbTitle,
    required this.hasAutocompleteResults,
    required this.hasAutocompleteFocusNodes,
    required this.isSeries,
    required this.autocompleteFocusNodes,
    required this.seasonInputFocusNode,
    required this.onClearPressed,
    required this.onChanged,
    required this.onSubmitted,
    required this.onFocusChange,
  });

  @override
  State<_SearchTextField> createState() => _SearchTextFieldState();
}

class _SearchTextFieldState extends State<_SearchTextField> {
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocusChanged);
    // Removed controller listener - not needed, clear button uses ValueListenableBuilder
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocusChanged);
    // Removed controller listener cleanup
    super.dispose();
  }

  void _onFocusChanged() {
    final focused = widget.focusNode.hasFocus;
    if (_isFocused != focused) {
      setState(() {
        _isFocused = focused;
      });
      widget.onFocusChange(focused);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Use regular Container instead of AnimatedContainer to avoid animation overhead on every rebuild
    // Focus animation is handled by the border property changing
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: _isFocused
            ? Border.all(
                color: const Color(0xFF6366F1),
                width: 1.6,
              )
            : null,
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6366F1).withValues(
              alpha: _isFocused ? 0.45 : 0.3,
            ),
            blurRadius: _isFocused ? 16 : 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Shortcuts(
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.arrowDown): NextFocusIntent(),
          SingleActivator(LogicalKeyboardKey.arrowUp): PreviousFocusIntent(),
        },
        child: Actions(
          actions: <Type, Action<Intent>>{
            NextFocusIntent: CallbackAction<NextFocusIntent>(
              onInvoke: (intent) {
                if (widget.hasAutocompleteResults && widget.hasAutocompleteFocusNodes) {
                  widget.autocompleteFocusNodes[0].requestFocus();
                  return null;
                }
                if (widget.isSeries && widget.selectedImdbTitle != null) {
                  widget.seasonInputFocusNode.requestFocus();
                  return null;
                }
                FocusScope.of(context).nextFocus();
                return null;
              },
            ),
            PreviousFocusIntent: CallbackAction<PreviousFocusIntent>(
              onInvoke: (intent) {
                FocusScope.of(context).previousFocus();
                return null;
              },
            ),
          },
          child: Focus(
            focusNode: widget.focusNode,
            onFocusChange: (_) {}, // Handled by listener
            child: TextField(
              controller: widget.controller,
              onSubmitted: widget.onSubmitted,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: widget.searchMode == SearchMode.imdb
                    ? 'Search IMDB titles...'
                    : 'Search all engines...',
                hintStyle: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                ),
                prefixIcon: Icon(
                  widget.searchMode == SearchMode.imdb
                      ? Icons.auto_awesome_outlined
                      : Icons.search_rounded,
                  color: widget.searchMode == SearchMode.imdb
                      ? const Color(0xFF7C3AED)
                      : const Color(0xFF6366F1),
                ),
                // Use ValueListenableBuilder to rebuild only the clear button, not entire TextField
                suffixIcon: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: widget.controller,
                  builder: (context, value, child) {
                    return value.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(
                              Icons.clear_rounded,
                              color: Color(0xFFEF4444),
                            ),
                            onPressed: widget.onClearPressed,
                          )
                        : const SizedBox.shrink();
                  },
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Theme.of(context).colorScheme.surfaceContainerHigh,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),
              onChanged: widget.onChanged,
            ),
          ),
        ),
      ),
    );
  }
}

// IMDB autocomplete item widget with DPAD support
class _ImdbAutocompleteItem extends StatefulWidget {
  final ImdbTitleResult result;
  final FocusNode focusNode;
  final VoidCallback onSelected;
  final KeyEventResult Function(KeyEvent) onKeyEvent;

  const _ImdbAutocompleteItem({
    required this.result,
    required this.focusNode,
    required this.onSelected,
    required this.onKeyEvent,
  });

  @override
  State<_ImdbAutocompleteItem> createState() => _ImdbAutocompleteItemState();
}

class _ImdbAutocompleteItemState extends State<_ImdbAutocompleteItem> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode,
      onFocusChange: (focused) {
        setState(() {
          _isFocused = focused;
        });
        if (focused) {
          // Ensure focused item is visible
          Scrollable.ensureVisible(
            context,
            alignment: 0.5,
            duration: const Duration(milliseconds: 200),
          );
        }
      },
      onKeyEvent: (node, event) => widget.onKeyEvent(event),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(
          color: _isFocused
              ? Colors.white.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: _isFocused
                ? Colors.white.withValues(alpha: 0.8)
                : Colors.transparent,
            width: 2,
          ),
        ),
        child: ListTile(
          onTap: widget.onSelected,
          leading: widget.result.posterUrl != null
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Image.network(
                    widget.result.posterUrl!,
                    width: 40,
                    height: 60,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        width: 40,
                        height: 60,
                        color: Colors.white.withValues(alpha: 0.1),
                        child: const Icon(
                          Icons.movie_outlined,
                          color: Colors.white54,
                        ),
                      );
                    },
                  ),
                )
              : Container(
                  width: 40,
                  height: 60,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Icon(
                    Icons.movie_outlined,
                    color: Colors.white54,
                  ),
                ),
          title: Text(
            widget.result.title,
            style: TextStyle(
              color: Colors.white,
              fontWeight: _isFocused ? FontWeight.w600 : FontWeight.normal,
              fontSize: 14,
            ),
          ),
          subtitle: widget.result.year != null
              ? Text(
                  widget.result.year!,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 12,
                  ),
                )
              : null,
          trailing: _isFocused
              ? Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 16,
                  color: Colors.white.withValues(alpha: 0.6),
                )
              : null,
        ),
      ),
    );
  }
}