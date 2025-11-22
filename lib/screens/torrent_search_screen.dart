import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:flutter/services.dart';
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
import '../widgets/stat_chip.dart';
import 'video_player_screen.dart';
import '../models/rd_torrent.dart';
import '../services/main_page_bridge.dart';
import '../services/torbox_service.dart';
import '../models/torbox_torrent.dart';
import '../models/torbox_file.dart';
import '../screens/torbox/torbox_downloads_screen.dart';
import '../widgets/shimmer.dart';
import '../widgets/advanced_search_sheet.dart';
import '../widgets/torrent_filters_sheet.dart';

class TorrentSearchScreen extends StatefulWidget {
  const TorrentSearchScreen({super.key});

  @override
  State<TorrentSearchScreen> createState() => _TorrentSearchScreenState();
}

class _TorrentSearchScreenState extends State<TorrentSearchScreen>
    with TickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final FocusNode _providerAccordionFocusNode = FocusNode();
  final FocusNode _advancedButtonFocusNode = FocusNode();
  final FocusNode _sortDirectionFocusNode = FocusNode();
  final FocusNode _filterButtonFocusNode = FocusNode();
  final FocusNode _clearFiltersButtonFocusNode = FocusNode();
  bool _searchFocused = false;
  bool _providerAccordionFocused = false;
  bool _advancedButtonFocused = false;
  bool _sortDirectionFocused = false;
  bool _filterButtonFocused = false;
  bool _clearFiltersButtonFocused = false;
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
  final List<FocusNode> _cardFocusNodes = [];
  final List<bool> _cardFocusStates = [];

  // Search engine toggles - dynamic engine states
  Map<String, bool> _engineStates = {};
  List<DynamicEngine> _availableEngines = [];
  final SettingsManager _settingsManager = SettingsManager();
  // Dynamic focus nodes for engine toggles
  final Map<String, FocusNode> _engineTileFocusNodes = {};
  final Map<String, bool> _engineTileFocusStates = {};
  bool _showProvidersPanel = false;
  AdvancedSearchSelection? _activeAdvancedSelection;

  // Sorting options
  String _sortBy = 'relevance'; // relevance, name, size, seeders, date
  bool _sortAscending = false;
  TorrentFilterState _filters = const TorrentFilterState.empty();
  bool get _hasActiveFilters => !_filters.isEmpty;

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
    MainPageBridge.handleTorboxResult = (torrent) async {
      if (!mounted) return;
      await _showTorboxPostAddOptions(torrent);
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

    _searchFocusNode.addListener(() {
      if (!mounted) return;
      setState(() {
        _searchFocused = _searchFocusNode.hasFocus;
      });
    });

    _providerAccordionFocusNode.addListener(() {
      if (!mounted) return;
      setState(() {
        _providerAccordionFocused = _providerAccordionFocusNode.hasFocus;
      });
    });

    _advancedButtonFocusNode.addListener(() {
      if (!mounted) return;
      setState(() {
        _advancedButtonFocused = _advancedButtonFocusNode.hasFocus;
      });
    });

    _sortDirectionFocusNode.addListener(() {
      if (!mounted) return;
      setState(() {
        _sortDirectionFocused = _sortDirectionFocusNode.hasFocus;
      });
    });

    _filterButtonFocusNode.addListener(() {
      if (!mounted) return;
      setState(() {
        _filterButtonFocused = _filterButtonFocusNode.hasFocus;
      });
    });

    _clearFiltersButtonFocusNode.addListener(() {
      if (!mounted) return;
      setState(() {
        _clearFiltersButtonFocused = _clearFiltersButtonFocusNode.hasFocus;
      });
    });

    _listAnimationController.forward();
    _loadDefaultSettings();
    _detectTelevision();
    MainPageBridge.addIntegrationListener(_handleIntegrationChanged);
    _loadApiKeys();
    StorageService.getTorboxCacheCheckEnabled().then((enabled) {
      if (!mounted) return;
      setState(() {
        _torboxCacheCheckEnabled = enabled;
      });
    });
  }

  Future<void> _detectTelevision() async {
    final isTv = await AndroidNativeDownloader.isTelevision();
    if (mounted) {
      setState(() {
        _isTelevision = isTv;
      });
    }
  }

  void _ensureFocusNodes() {
    // Dispose old focus nodes if list shrunk
    while (_cardFocusNodes.length > _torrents.length) {
      _cardFocusNodes.removeLast().dispose();
      _cardFocusStates.removeLast();
    }

    // Add new focus nodes if list grew
    while (_cardFocusNodes.length < _torrents.length) {
      final index = _cardFocusNodes.length;
      final node = FocusNode(debugLabel: 'torrent-card-$index');
      node.addListener(() {
        if (!mounted) return;
        setState(() {
          _cardFocusStates[index] = node.hasFocus;
        });
        if (node.hasFocus) {
          // Auto-scroll to focused card
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            // Will be handled by Scrollable.ensureVisible in the widget
          });
        }
      });
      _cardFocusNodes.add(node);
      _cardFocusStates.add(false);
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

  void _handleTorrentCardActivated(Torrent torrent, int index) {
    if (_bothServicesEnabled) {
      // Show dialog to choose service
      _showServiceSelectionDialog(torrent, index);
    } else if (_realDebridIntegrationEnabled && _apiKey != null && _apiKey!.isNotEmpty) {
      // Direct to Real-Debrid
      _addToRealDebrid(torrent.infohash, torrent.name, index);
    } else if (_torboxIntegrationEnabled && _torboxApiKey != null && _torboxApiKey!.isNotEmpty) {
      // Direct to Torbox
      _addToTorbox(torrent.infohash, torrent.name);
    } else {
      // No service configured
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please configure Real-Debrid or Torbox in Settings'),
        ),
      );
    }
  }

  Future<void> _showServiceSelectionDialog(Torrent torrent, int index) async {
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
          children: [
            ListTile(
              leading: const Icon(Icons.flash_on_rounded, color: Color(0xFF7C3AED)),
              title: const Text('Torbox', style: TextStyle(color: Colors.white)),
              onTap: () => Navigator.of(context).pop('torbox'),
            ),
            ListTile(
              leading: const Icon(Icons.cloud_rounded, color: Color(0xFFE50914)),
              title: const Text('Real-Debrid', style: TextStyle(color: Colors.white)),
              onTap: () => Navigator.of(context).pop('debrid'),
            ),
          ],
        ),
      ),
    );

    if (result == 'torbox') {
      _addToTorbox(torrent.infohash, torrent.name);
    } else if (result == 'debrid') {
      _addToRealDebrid(torrent.infohash, torrent.name, index);
    }
  }

  Future<void> _loadDefaultSettings() async {
    // Load available engines dynamically from TorrentService
    final engines = await TorrentService.getKeywordSearchEngines();
    final Map<String, bool> states = {};

    // Load enabled state for each engine from SettingsManager
    for (final engine in engines) {
      final engineId = engine.name;
      final defaultEnabled = engine.settingsConfig.enabled?.defaultBool ?? true;
      final isEnabled = await _settingsManager.getEnabled(engineId, defaultEnabled);
      states[engineId] = isEnabled;
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
        node.addListener(() {
          if (!mounted) return;
          setState(() {
            _engineTileFocusStates[engineId] = node.hasFocus;
          });
        });
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

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _providerAccordionFocusNode.dispose();
    _advancedButtonFocusNode.dispose();
    _sortDirectionFocusNode.dispose();
    _filterButtonFocusNode.dispose();
    _clearFiltersButtonFocusNode.dispose();
    for (final node in _cardFocusNodes) {
      node.dispose();
    }
    // Dispose dynamic engine focus nodes
    for (final node in _engineTileFocusNodes.values) {
      node.dispose();
    }
    _engineTileFocusNodes.clear();
    MainPageBridge.removeIntegrationListener(_handleIntegrationChanged);
    MainPageBridge.handleRealDebridResult = null;
    MainPageBridge.handleTorboxResult = null;
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
        debugPrint('TorrentSearchScreen: Using IMDB search for ${selection.imdbId}');
        result = await TorrentService.searchByImdb(
          selection.imdbId,
          engineStates: _engineStates,
          isMovie: !selection.isSeries,
          season: selection.season,
          episode: selection.episode,
        );
      } else {
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
    final trimmed = value.trim();
    if (_activeAdvancedSelection != null &&
        trimmed != _activeAdvancedSelection!.displayQuery) {
      setState(() {
        _activeAdvancedSelection = null;
      });
    } else {
      setState(() {});
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
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: _advancedButtonFocused
                ? Border.all(color: Colors.white, width: 2)
                : null,
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


  Widget _buildProviderSummaryText(BuildContext context) {
    final enabledCount = _engineStates.values.where((enabled) => enabled).length;
    if (enabledCount == 0) {
      return Text(
        'No providers selected',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.error,
        ),
      );
    }
    return Text(
      '$enabledCount enabled',
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }

  Widget _buildProvidersAccordion(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B).withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _providerAccordionFocused
              ? const Color(0xFF3B82F6).withValues(alpha: 0.6)
              : const Color(0xFF3B82F6).withValues(alpha: 0.2),
          width: _providerAccordionFocused ? 2 : 1,
        ),
      ),
      child: Column(
        children: [
          FocusableActionDetector(
            focusNode: _providerAccordionFocusNode,
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
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: _providerAccordionFocused
                      ? const Color(0xFF3B82F6).withValues(alpha: 0.15)
                      : Colors.transparent,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Icon(
                      _showProvidersPanel
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Search Providers',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    _buildProviderSummaryText(context),
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
                      final isFocused = _engineTileFocusStates[engineId] ?? false;
                      final isEnabled = _engineStates[engineId] ?? false;
                      return _buildProviderSwitch(
                        context,
                        label: engine.displayName,
                        value: isEnabled,
                        onToggle: (value) => _setEngineEnabled(engineId, value),
                        tileFocusNode: focusNode ?? FocusNode(),
                        tileFocused: isFocused,
                        onFocusChange: (visible) {
                          if (_engineTileFocusStates[engineId] != visible) {
                            setState(() => _engineTileFocusStates[engineId] = visible);
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1F2937),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFFACC15).withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.auto_awesome_rounded,
            color: Color(0xFFFACC15),
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Need IMDb-accurate results? Use Advanced search to pull Torrentio streams via IMDb ID, seasons, and episodes.',
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
                Text(
                  label,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: value
                        ? Theme.of(context).colorScheme.onPrimaryContainer
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: value ? FontWeight.w600 : FontWeight.normal,
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
  }) {
    final List<Torrent> baseList = nextBase ?? _allTorrents;
    final Map<String, _TorrentMetadata> metadata =
        metadataOverride ??
        (nextBase != null
            ? _buildTorrentMetadataMap(baseList)
            : _torrentMetadata);

    final List<Torrent> sortedTorrents = List<Torrent>.from(baseList);

    switch (_sortBy) {
      case 'name':
        sortedTorrents.sort((a, b) {
          final comparison = a.name.toLowerCase().compareTo(
            b.name.toLowerCase(),
          );
          return _sortAscending ? comparison : -comparison;
        });
        break;
      case 'size':
        sortedTorrents.sort((a, b) {
          final comparison = a.sizeBytes.compareTo(b.sizeBytes);
          return _sortAscending ? comparison : -comparison;
        });
        break;
      case 'seeders':
        sortedTorrents.sort((a, b) {
          final comparison = a.seeders.compareTo(b.seeders);
          return _sortAscending ? comparison : -comparison;
        });
        break;
      case 'date':
        sortedTorrents.sort((a, b) {
          final comparison = a.createdUnix.compareTo(b.createdUnix);
          return _sortAscending ? comparison : -comparison;
        });
        break;
      case 'relevance':
      default:
        // Keep original order (relevance maintained by search engines)
        break;
    }

    final filtered = _applyFiltersToList(sortedTorrents, metadataMap: metadata);

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

    final result = await showModalBottomSheet<TorrentFilterState>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => TorrentFiltersSheet(initialState: _filters),
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

      // Add to PikPak first
      final addResult = await pikpak.addOfflineDownload(magnet);
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
                      maxLines: 2,
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
      _showPikPakSnack('Failed: ${e.toString()}', isError: true);
    }
  }

  Future<void> _pollPikPakStatus(
    String fileId,
    String? taskId,
    String torrentName,
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

          await _showPikPakPostAddOptions(torrentName, fileId, videoFiles);
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
  ) async {
    if (!mounted) return;

    final hasVideo = videoFiles.isNotEmpty;
    final postAction = await StorageService.getPikPakPostTorrentAction();

    // Handle automatic actions
    switch (postAction) {
      case 'play':
        if (hasVideo) {
          _playPikPakVideos(videoFiles, torrentName);
          return;
        }
        break;
      case 'choose':
      default:
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
                                maxLines: 2,
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
                  _DebridActionTile(
                    icon: Icons.play_circle_fill_rounded,
                    color: const Color(0xFF60A5FA),
                    title: 'Play now',
                    subtitle: hasVideo
                        ? 'Stream instantly from PikPak.'
                        : 'No video files found.',
                    enabled: hasVideo,
                    autofocus: true,
                    onTap: () {
                      Navigator.of(ctx).pop();
                      _playPikPakVideos(videoFiles, torrentName);
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
                      _addPikPakToPlaylist(videoFiles, torrentName);
                    },
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

  Future<void> _addPikPakToPlaylist(List<Map<String, dynamic>> videoFiles, String torrentName) async {
    if (videoFiles.isEmpty) {
      _showPikPakSnack('No video files to add', isError: true);
      return;
    }

    if (videoFiles.length == 1) {
      final file = videoFiles.first;
      final added = await StorageService.addPlaylistItemRaw({
        'provider': 'pikpak',
        'title': file['name'] ?? torrentName,
        'kind': 'single',
        'pikpakFileId': file['id'],
        'sizeBytes': int.tryParse(file['size']?.toString() ?? '0'),
      });
      _showPikPakSnack(added ? 'Added to playlist' : 'Already in playlist', isError: !added);
    } else {
      // Save as collection (like Torbox)
      final fileIds = videoFiles.map((f) => f['id'] as String).toList();
      final added = await StorageService.addPlaylistItemRaw({
        'provider': 'pikpak',
        'title': torrentName,
        'kind': 'collection',
        'pikpakFileIds': fileIds,
        'count': videoFiles.length,
      });
      _showPikPakSnack(
        added ? 'Added ${videoFiles.length} videos to playlist' : 'Already in playlist',
        isError: !added,
      );
    }
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

  /// Recursively extract all video files from a PikPak folder and its subfolders
  Future<List<Map<String, dynamic>>> _extractAllPikPakVideos(
    PikPakApiService pikpak,
    String folderId, {
    int maxDepth = 5,
    int currentDepth = 0,
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
        final name = file['name'] ?? 'unknown';

        print('PikPak: Item: $name, kind: $kind, mime: $mimeType');

        if (kind == 'drive#folder') {
          // Recursively scan subfolder
          print('PikPak: Entering subfolder: $name');
          final subVideos = await _extractAllPikPakVideos(
            pikpak,
            file['id'],
            maxDepth: maxDepth,
            currentDepth: currentDepth + 1,
          );
          print('PikPak: Found ${subVideos.length} videos in subfolder: $name');
          videos.addAll(subVideos);
        } else if (mimeType.startsWith('video/')) {
          // It's a video file
          print('PikPak: Found video: $name');
          videos.add(file);
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
                      maxLines: 2,
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
                          maxLines: 2,
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
                  maxLines: 2,
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

      if (!mounted) return;
      await _showTorboxPostAddOptions(torboxTorrent);
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
                  maxLines: 2,
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

  Future<void> _showTorboxPostAddOptions(TorboxTorrent torrent) async {
    if (!mounted) return;
    final videoFiles = torrent.files.where(_torboxFileLooksLikeVideo).toList();
    final hasVideo = videoFiles.isNotEmpty;

    // Get the post-torrent action preference
    final postAction = await StorageService.getTorboxPostTorrentAction();

    // Check if torrent is video-only for auto-download handling
    final isVideoOnly = torrent.files.isNotEmpty &&
        torrent.files.every((file) => _torboxFileLooksLikeVideo(file));

    // Handle automatic actions based on preference
    switch (postAction) {
      case 'play':
        if (hasVideo) {
          _playTorboxTorrent(torrent);
          return;
        }
        // Fall through to 'choose' if no video
        break;
      case 'download':
        if (isVideoOnly) {
          // Auto-download all videos without dialog
          _showTorboxDownloadOptions(torrent);
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
                                torrent.name,
                                maxLines: 2,
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
                  _DebridActionTile(
                    icon: Icons.play_circle_fill_rounded,
                    color: const Color(0xFF60A5FA),
                    title: 'Play now',
                    subtitle: hasVideo
                        ? 'Open instantly in the Torbox player experience.'
                        : 'Available for torrents with video files.',
                    enabled: hasVideo,
                    autofocus: true,
                    onTap: () {
                      Navigator.of(ctx).pop();
                      _playTorboxTorrent(torrent);
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
                      _showTorboxDownloadOptions(torrent);
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
                      _addTorboxTorrentToPlaylist(torrent);
                    },
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
        'title': displayName.isNotEmpty ? displayName : torrent.name,
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
      'title': torrent.name,
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
                    ListTile(
                      leading: const Icon(Icons.list_alt),
                      title: const Text('Select files to download'),
                      subtitle: const Text('Open Torbox file browser'),
                      onTap: () {
                        Navigator.of(sheetContext).pop();
                        _openTorboxFiles(torrent);
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
      ),
    );
  }

  void _openTorboxFiles(TorboxTorrent torrent) {
    if (MainPageBridge.openTorboxAction != null) {
      MainPageBridge.openTorboxAction!(torrent, TorboxQuickAction.files);
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => TorboxDownloadsScreen(
            initialTorrentForAction: torrent,
            initialAction: TorboxQuickAction.files,
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
    final downloadLink = result['downloadLink'] as String;
    final fileSelection = result['fileSelection'] as String;
    final links = result['links'] as List<dynamic>;
    final files = result['files'] as List<dynamic>?;
    final updatedInfo = result['updatedInfo'] as Map<String, dynamic>?;

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
                                    maxLines: 2,
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
                      _DebridActionTile(
                        icon: Icons.play_circle_rounded,
                        color: const Color(0xFF60A5FA),
                        title: 'Play now',
                        subtitle: hasAnyVideo
                            ? 'Unrestrict and open instantly in the built-in player.'
                            : 'Available for video torrents only.',
                        enabled: hasAnyVideo,
                        autofocus: true,
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
                        subtitle: 'Downloads the files to your device',
                        enabled: true,
                        onTap: () {
                          Navigator.of(ctx).pop();
                          if (hasAnyVideo) {
                            if (links.length == 1) {
                              _downloadFile(downloadLink, torrentName);
                            } else {
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
                                  'title': finalTitle,
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
                                  'title': torrentName,
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
            // Multiple video files - show file selection
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
                          leading: const Icon(
                            Icons.video_file,
                            color: Colors.grey,
                          ),
                          title: Text(
                            fileName,
                            style: const TextStyle(color: Colors.white),
                            maxLines: 2,
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
    return Container(
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
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 160),
                            curve: Curves.easeOutCubic,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: _searchFocused
                                  ? Border.all(
                                      color: const Color(0xFF6366F1),
                                      width: 1.6,
                                    )
                                  : null,
                              boxShadow: [
                                BoxShadow(
                                  color:
                                      (_searchFocused
                                              ? const Color(0xFF6366F1)
                                              : const Color(0xFF6366F1))
                                          .withValues(
                                            alpha: _searchFocused ? 0.45 : 0.3,
                                          ),
                                  blurRadius: _searchFocused ? 16 : 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Shortcuts(
                              shortcuts: const <ShortcutActivator, Intent>{
                                SingleActivator(LogicalKeyboardKey.arrowDown):
                                    NextFocusIntent(),
                                SingleActivator(LogicalKeyboardKey.arrowUp):
                                    PreviousFocusIntent(),
                              },
                              child: Actions(
                                actions: <Type, Action<Intent>>{
                                  NextFocusIntent:
                                      CallbackAction<NextFocusIntent>(
                                        onInvoke: (intent) {
                                          FocusScope.of(context).nextFocus();
                                          return null;
                                        },
                                      ),
                                  PreviousFocusIntent:
                                      CallbackAction<PreviousFocusIntent>(
                                        onInvoke: (intent) {
                                          FocusScope.of(
                                            context,
                                          ).previousFocus();
                                          return null;
                                        },
                                      ),
                                },
                                child: TextField(
                                  controller: _searchController,
                                  focusNode: _searchFocusNode,
                                  onSubmitted: (query) =>
                                      _searchTorrents(query),
                                  style: const TextStyle(color: Colors.white),
                                  decoration: InputDecoration(
                                    hintText: 'Search all engines...',
                                    hintStyle: TextStyle(
                                      color: Colors.white.withValues(
                                        alpha: 0.5,
                                      ),
                                    ),
                                    prefixIcon: const Icon(
                                      Icons.search_rounded,
                                      color: Color(0xFF6366F1),
                                    ),
                                    suffixIcon:
                                        _searchController.text.isNotEmpty
                                        ? IconButton(
                                            icon: const Icon(
                                              Icons.clear_rounded,
                                              color: Color(0xFFEF4444),
                                            ),
                                            onPressed: () {
                                              _searchController.clear();
                                              _handleSearchFieldChanged('');
                                              _searchFocusNode.requestFocus();
                                            },
                                          )
                                        : null,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide.none,
                                    ),
                                    filled: true,
                                    fillColor: Theme.of(
                                      context,
                                    ).colorScheme.surfaceContainerHigh,
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 10,
                                    ),
                                  ),
                                  onChanged: _handleSearchFieldChanged,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        _buildAdvancedButton(),
                      ],
                    ),
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
                      return ListView(
                        padding: const EdgeInsets.only(bottom: 16),
                        children: [
                          Container(
                            margin: const EdgeInsets.all(8),
                            padding: const EdgeInsets.all(12),
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
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: const Color(
                                      0xFF6366F1,
                                    ).withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(
                                    Icons.search_rounded,
                                    color: Color(0xFF6366F1),
                                    size: 32,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                const Text(
                                  'Ready to Search?',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Enter a torrent name above to get started',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.white.withValues(alpha: 0.7),
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 12),
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: Colors.white.withValues(
                                        alpha: 0.2,
                                      ),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.tips_and_updates_rounded,
                                        color: const Color(0xFFF59E0B),
                                        size: 16,
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          'Try: movies, games, software',
                                          style: TextStyle(
                                            color: Colors.white.withValues(
                                              alpha: 0.8,
                                            ),
                                            fontSize: 10,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
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

                    return ListView.builder(
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
                                      child: DropdownButton<String>(
                                        value: _sortBy,
                                        onChanged: (String? newValue) {
                                          if (newValue != null) {
                                            setState(() {
                                              _sortBy = newValue;
                                            });
                                            _sortTorrents();
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
                                    const SizedBox(width: 8),
                                    Focus(
                                      focusNode: _sortDirectionFocusNode,
                                      onKeyEvent: (node, event) {
                                        if (event is KeyDownEvent &&
                                            (event.logicalKey == LogicalKeyboardKey.select ||
                                                event.logicalKey == LogicalKeyboardKey.enter)) {
                                          setState(() {
                                            _sortAscending = !_sortAscending;
                                          });
                                          _sortTorrents();
                                          return KeyEventResult.handled;
                                        }
                                        return KeyEventResult.ignored;
                                      },
                                      child: Container(
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(4),
                                          border: _sortDirectionFocused
                                              ? Border.all(color: const Color(0xFF3B82F6), width: 2)
                                              : null,
                                        ),
                                        child: IconButton(
                                          onPressed: () {
                                            setState(() {
                                              _sortAscending = !_sortAscending;
                                            });
                                            _sortTorrents();
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
                                      child: Container(
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(4),
                                          border: _filterButtonFocused
                                              ? Border.all(color: const Color(0xFF3B82F6), width: 2)
                                              : null,
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
                                          onKeyEvent: (node, event) {
                                            if (event is KeyDownEvent &&
                                                (event.logicalKey == LogicalKeyboardKey.select ||
                                                    event.logicalKey == LogicalKeyboardKey.enter)) {
                                              _clearAllFilters();
                                              return KeyEventResult.handled;
                                            }
                                            return KeyEventResult.ignored;
                                          },
                                          child: Container(
                                            decoration: BoxDecoration(
                                              borderRadius: BorderRadius.circular(4),
                                              border: _clearFiltersButtonFocused
                                                  ? Border.all(color: const Color(0xFF3B82F6), width: 2)
                                                  : null,
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
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: _buildTorrentCard(
                            torrent,
                            index - metadataRows,
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

  Widget _buildTorrentCard(Torrent torrent, int index) {
    final sourceTag = _buildSourceTag(torrent.source);
    final isFocused = index < _cardFocusStates.length && _cardFocusStates[index];

    Widget cardContent = Container(
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
        border: _isTelevision && isFocused
            ? Border.all(color: const Color(0xFFE50914), width: 3)
            : null,
        boxShadow: _isTelevision && isFocused
            ? [
                BoxShadow(
                  color: const Color(0xFFE50914).withValues(alpha: 0.4),
                  blurRadius: 24,
                  spreadRadius: 2,
                  offset: const Offset(0, 8),
                ),
              ]
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 15,
                  offset: const Offset(0, 8),
                ),
              ],
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
                    torrent.name,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                    maxLines: _isTelevision && isFocused ? null : 2,
                    overflow: _isTelevision && isFocused ? null : TextOverflow.ellipsis,
                  ),
                ),
                if (sourceTag != null) ...[const SizedBox(width: 8), sourceTag],
                if (!_isTelevision) ...[
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
              ],
            ),
            const SizedBox(height: 12),

            // Stats Grid
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                StatChip(
                  icon: Icons.storage_rounded,
                  text: Formatters.formatFileSize(torrent.sizeBytes),
                  color: const Color(0xFF0EA5E9), // Sky 500 - Premium blue
                ),
                StatChip(
                  icon: Icons.upload_rounded,
                  text: '${torrent.seeders}',
                  color: const Color(0xFF22C55E), // Green 500 - Fresh green
                ),
                StatChip(
                  icon: Icons.download_rounded,
                  text: '${torrent.leechers}',
                  color: const Color(0xFFF59E0B), // Amber 500 - Warm amber
                ),
                StatChip(
                  icon: Icons.check_circle_rounded,
                  text: '${torrent.completed}',
                  color: const Color(0xFF8B5CF6), // Violet 500 - Rich purple
                ),
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

            // Action Buttons (Hidden on TV since we use smart action on card click)
            if (!_isTelevision)
              LayoutBuilder(
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
                        focusColor:
                            const Color(0xFF7C3AED).withValues(alpha: 0.25),
                        onTap: isCached
                            ? () => _addToTorbox(torrent.infohash, torrent.name)
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
                          _addToRealDebrid(torrent.infohash, torrent.name, index),
                      onLongPress: () {
                        _showFileSelectionDialog(
                          torrent.infohash,
                          torrent.name,
                          index,
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
                          _sendToPikPak(torrent.infohash, torrent.name),
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
                    (_torboxIntegrationEnabled &&
                        _torboxApiKey != null &&
                        _torboxApiKey!.isNotEmpty)
                    ? buildTorboxButton()
                    : null;
                final Widget? realDebridButton =
                    (_realDebridIntegrationEnabled &&
                        _apiKey != null &&
                        _apiKey!.isNotEmpty)
                    ? buildRealDebridButton()
                    : null;
                final Widget? pikpakButton = _pikpakEnabled
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
            if (_isTelevision && isFocused) ...[
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

    // Wrap with Focus widget for TV navigation
    if (_isTelevision && index < _cardFocusNodes.length) {
      return Focus(
        focusNode: _cardFocusNodes[index],
        onKeyEvent: (node, event) {
          // Handle OK/Select/Enter press
          if (event is KeyDownEvent &&
              (event.logicalKey == LogicalKeyboardKey.select ||
                  event.logicalKey == LogicalKeyboardKey.enter ||
                  event.logicalKey == LogicalKeyboardKey.space)) {
            _handleTorrentCardActivated(torrent, index);
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Builder(
          builder: (context) {
            if (isFocused) {
              // Auto-scroll when focused
              WidgetsBinding.instance.addPostFrameCallback((_) {
                Scrollable.ensureVisible(
                  context,
                  alignment: 0.2,
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOutCubic,
                );
              });
            }
            return cardContent;
          },
        ),
      );
    }

    return cardContent;
  }
}

class _TorrentMetadata {
  final SeriesInfo seriesInfo;
  final QualityTier? qualityTier;
  final RipSourceCategory ripSource;

  const _TorrentMetadata({
    required this.seriesInfo,
    this.qualityTier,
    RipSourceCategory? ripSource,
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
