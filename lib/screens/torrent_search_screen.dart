import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:flutter/services.dart';
import '../models/torrent.dart';
import '../services/torrent_service.dart';
import '../services/debrid_service.dart';
import '../services/storage_service.dart';
import '../services/download_service.dart';
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

class TorrentSearchScreen extends StatefulWidget {
  const TorrentSearchScreen({super.key});

  @override
  State<TorrentSearchScreen> createState() => _TorrentSearchScreenState();
}

class _TorrentSearchScreenState extends State<TorrentSearchScreen>
    with TickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  List<Torrent> _torrents = [];
  Map<String, int> _engineCounts = {};
  bool _isLoading = false;
  String _errorMessage = '';
  bool _hasSearched = false;
  String? _apiKey;
  String? _torboxApiKey;
  bool _torboxCacheCheckEnabled = false;
  Map<String, bool>? _torboxCacheStatus;
  bool _realDebridIntegrationEnabled = true;
  bool _torboxIntegrationEnabled = true;
  bool _showingTorboxCachedOnly = false;

  // Search engine toggles
  bool _useTorrentsCsv = true;
  bool _usePirateBay = true;

  // Sorting options
  String _sortBy = 'relevance'; // relevance, name, size, seeders, date
  bool _sortAscending = false;

  late AnimationController _listAnimationController;
  late Animation<double> _listAnimation;

  @override
  void initState() {
    super.initState();
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

    _listAnimationController.forward();
    _loadDefaultSettings();
    MainPageBridge.addIntegrationListener(_handleIntegrationChanged);
    _loadApiKeys();
    StorageService.getTorboxCacheCheckEnabled().then((enabled) {
      if (!mounted) return;
      setState(() {
        _torboxCacheCheckEnabled = enabled;
      });
    });
  }

  Future<void> _loadDefaultSettings() async {
    final defaultTorrentsCsv =
        await StorageService.getDefaultTorrentsCsvEnabled();
    final defaultPirateBay = await StorageService.getDefaultPirateBayEnabled();

    setState(() {
      _useTorrentsCsv = defaultTorrentsCsv;
      _usePirateBay = defaultPirateBay;
    });

    // Focus the search field after a short delay to ensure UI is ready
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) {
        _searchFocusNode.requestFocus();
      }
    });
  }

  void _handleIntegrationChanged() {
    _loadApiKeys();
  }

  Future<void> _loadApiKeys() async {
    final rdKey = await StorageService.getApiKey();
    final torboxKey = await StorageService.getTorboxApiKey();
    final rdEnabled = await StorageService.getRealDebridIntegrationEnabled();
    final torboxEnabled = await StorageService.getTorboxIntegrationEnabled();
    if (!mounted) return;
    setState(() {
      _apiKey = rdKey;
      _torboxApiKey = torboxKey;
      _realDebridIntegrationEnabled = rdEnabled;
      _torboxIntegrationEnabled = torboxEnabled;
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    MainPageBridge.removeIntegrationListener(_handleIntegrationChanged);
    _listAnimationController.dispose();
    super.dispose();
  }

  Future<void> _searchTorrents(String query) async {
    if (query.trim().isEmpty) return;

    setState(() {
      _isLoading = true;
      _errorMessage = '';
      _hasSearched = true;
      _torboxCacheStatus = null;
      _showingTorboxCachedOnly = false;
    });

    // Hide keyboard
    _searchFocusNode.unfocus();

    final results = await Future.wait([
      StorageService.getTorboxCacheCheckEnabled(),
      StorageService.getTorboxApiKey(),
      StorageService.getRealDebridIntegrationEnabled(),
      StorageService.getTorboxIntegrationEnabled(),
      StorageService.getApiKey(),
    ]);
    final bool cacheCheckPreference = results[0] as bool;
    final String? torboxKey = results[1] as String?;
    final bool rdEnabled = results[2] as bool;
    final bool torboxEnabled = results[3] as bool;
    final String? rdKey = results[4] as String?;
    if (mounted) {
      setState(() {
        _torboxCacheCheckEnabled = cacheCheckPreference;
        _torboxApiKey = torboxKey;
        _realDebridIntegrationEnabled = rdEnabled;
        _torboxIntegrationEnabled = torboxEnabled;
        _apiKey = rdKey;
      });
    }

    try {
      final result = await TorrentService.searchAllEngines(
        query,
        useTorrentsCsv: _useTorrentsCsv,
        usePirateBay: _usePirateBay,
      );
      final fetchedTorrents = (result['torrents'] as List<Torrent>).toList(
        growable: false,
      );
      Map<String, bool>? torboxCacheMap;

      final String? torboxKeyValue = torboxKey;
      if (cacheCheckPreference &&
          torboxEnabled &&
          torboxKeyValue != null &&
          torboxKeyValue.isNotEmpty &&
          fetchedTorrents.isNotEmpty) {
        final uniqueHashes = fetchedTorrents
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

      final bool torboxActive = torboxEnabled &&
          torboxKeyValue != null &&
          torboxKeyValue.isNotEmpty;
      final bool realDebridActive =
          rdEnabled && rdKey != null && rdKey.isNotEmpty;
      bool showOnlyCached = false;
      List<Torrent> filteredTorrents = fetchedTorrents;
      if (cacheCheckPreference &&
          torboxActive &&
          !realDebridActive &&
          torboxCacheMap != null) {
        filteredTorrents = fetchedTorrents.where((torrent) {
          final hash = torrent.infohash.trim().toLowerCase();
          return torboxCacheMap![hash] ?? false;
        }).toList(growable: false);
        showOnlyCached = true;
      }

      setState(() {
        _torrents = filteredTorrents;
        _engineCounts = Map<String, int>.from(result['engineCounts'] as Map);
        _torboxCacheStatus = torboxCacheMap;
        _isLoading = false;
        _showingTorboxCachedOnly = showOnlyCached;
      });

      // Apply sorting to the results
      _sortTorrents();
      _listAnimationController.forward();
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceAll('Exception: ', '');
        _isLoading = false;
      });
    }
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

  void _sortTorrents() {
    if (_torrents.isEmpty) return;

    List<Torrent> sortedTorrents = List.from(_torrents);

    switch (_sortBy) {
      case 'name':
        sortedTorrents.sort((a, b) {
          int comparison = a.name.toLowerCase().compareTo(b.name.toLowerCase());
          return _sortAscending ? comparison : -comparison;
        });
        break;
      case 'size':
        sortedTorrents.sort((a, b) {
          int comparison = a.sizeBytes.compareTo(b.sizeBytes);
          return _sortAscending ? comparison : -comparison;
        });
        break;
      case 'seeders':
        sortedTorrents.sort((a, b) {
          int comparison = a.seeders.compareTo(b.seeders);
          return _sortAscending ? comparison : -comparison;
        });
        break;
      case 'date':
        sortedTorrents.sort((a, b) {
          int comparison = a.createdUnix.compareTo(b.createdUnix);
          return _sortAscending ? comparison : -comparison;
        });
        break;
      case 'relevance':
      default:
        // Keep original order (relevance is maintained by search engines)
        break;
    }

    setState(() {
      _torrents = sortedTorrents;
    });
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
                  e.toString().replaceAll('Exception: ', ''),
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
                  e.toString().replaceAll('Exception: ', ''),
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
            'Torrent is not cached on Torbox yet. Disable "add only if cached" in future to force add.',
            isError: true,
          );
        } else {
          _showTorboxSnack(
            error.isEmpty ? 'Failed to cache torrent on Torbox.' : error,
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
    const limit = 50;
    int attempt = 0;
    while (attempt < 5) {
      int offset = 0;
      bool hasMore = true;
      while (hasMore) {
        final result = await TorboxService.getTorrents(
          apiKey,
          offset: offset,
          limit: limit,
        );
        final torrents = (result['torrents'] as List).cast<TorboxTorrent>();
        for (final torrent in torrents) {
          if (torrent.id == torrentId) {
            return torrent;
          }
        }
        hasMore = result['hasMore'] as bool? ?? false;
        if (!hasMore) break;
        offset += limit;
      }
      await Future.delayed(const Duration(milliseconds: 300));
      attempt += 1;
    }
    return null;
  }

  Future<void> _showTorboxPostAddOptions(TorboxTorrent torrent) async {
    if (!mounted) return;
    final videoFiles = torrent.files.where(_torboxFileLooksLikeVideo).toList();
    final hasVideo = videoFiles.isNotEmpty;

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
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => VideoPlayerScreen(
              videoUrl: streamUrl,
              title: torrent.name,
              subtitle: Formatters.formatFileSize(file.size),
            ),
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
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VideoPlayerScreen(
          videoUrl: initialUrl,
          title: torrent.name,
          subtitle: subtitle,
          playlist: playlistEntries,
          startIndex: startIndex,
        ),
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
    return raw.replaceFirst('Exception: ', '').trim();
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
                                  'apiKey': apiKey,
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
                                  'apiKey': apiKey,
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

        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) =>
                VideoPlayerScreen(videoUrl: videoUrl, title: finalTitle),
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

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => VideoPlayerScreen(
            videoUrl: initialVideoUrl,
            title: finalTitle,
            subtitle: '${entries.length} files',
            playlist: entries.isNotEmpty ? entries : null,
            startIndex: 0,
          ),
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

  String _buildEngineBreakdownText() {
    if (_engineCounts.isEmpty) {
      // Show which engines are selected
      final List<String> selectedEngines = [];
      if (_useTorrentsCsv) selectedEngines.add('Torrents CSV');
      if (_usePirateBay) selectedEngines.add('The Pirate Bay');

      if (selectedEngines.isEmpty) {
        return 'No search engines selected';
      }

      return 'From ${selectedEngines.join(' and ')}';
    }

    final List<String> breakdowns = [];

    // Add Torrents CSV count
    final csvCount = _engineCounts['torrents_csv'] ?? 0;
    if (csvCount > 0) {
      breakdowns.add('Torrents CSV: $csvCount');
    }

    // Add Pirate Bay count
    final pbCount = _engineCounts['pirate_bay'] ?? 0;
    if (pbCount > 0) {
      breakdowns.add('The Pirate Bay: $pbCount');
    }

    if (breakdowns.isEmpty) {
      return 'No results found';
    }

    return breakdowns.join(' • ');
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
                    const Color(0xFF1E40AF).withValues(alpha: 0.9), // Blue 800
                    const Color(0xFF1E3A8A).withValues(alpha: 0.8), // Blue 900
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
                  // Search Input
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF6366F1).withValues(alpha: 0.3),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: TextField(
                      controller: _searchController,
                      focusNode: _searchFocusNode,
                      onSubmitted: (query) => _searchTorrents(query),
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Search all engines...',
                        hintStyle: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                        ),
                        prefixIcon: const Icon(
                          Icons.search_rounded,
                          color: Color(0xFF6366F1),
                        ),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(
                                  Icons.clear_rounded,
                                  color: Color(0xFFEF4444),
                                ),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() {});
                                },
                              )
                            : null,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: Theme.of(context).colorScheme.surfaceVariant,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                      ),
                      onChanged: (value) => setState(() {}),
                    ),
                  ),

                  // Search Engine Toggles
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B).withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: const Color(0xFF3B82F6).withValues(alpha: 0.2),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF1E40AF).withValues(alpha: 0.1),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              Switch(
                                value: _useTorrentsCsv,
                                onChanged: (value) {
                                  setState(() {
                                    _useTorrentsCsv = value;
                                  });
                                  // Auto-refresh if we have results
                                  if (_hasSearched &&
                                      _searchController.text
                                          .trim()
                                          .isNotEmpty) {
                                    _searchTorrents(_searchController.text);
                                  }
                                },
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Torrents CSV',
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                      ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          width: 1,
                          height: 24,
                          color: Theme.of(
                            context,
                          ).colorScheme.outline.withValues(alpha: 0.3),
                        ),
                        Expanded(
                          child: Row(
                            children: [
                              Switch(
                                value: _usePirateBay,
                                onChanged: (value) {
                                  setState(() {
                                    _usePirateBay = value;
                                  });
                                  // Auto-refresh if we have results
                                  if (_hasSearched &&
                                      _searchController.text
                                          .trim()
                                          .isNotEmpty) {
                                    _searchTorrents(_searchController.text);
                                  }
                                },
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Pirate Bay',
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
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
                                    color: Colors.white.withValues(alpha: 0.2),
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
                            children: const [
                              SizedBox(height: 16),
                              Text(
                                'No Results Found',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              SizedBox(height: 8),
                              Text(
                                'Try different keywords or check your spelling',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.white70,
                                ),
                                textAlign: TextAlign.center,
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
                                colors: [Color(0xFF1E40AF), Color(0xFF1E3A8A)],
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
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.2),
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
                                    () {
                                      final baseText =
                                          '${_torrents.length} Result${_torrents.length == 1 ? '' : 's'} Found • ${_buildEngineBreakdownText()}';
                                      if (_showingTorboxCachedOnly) {
                                        return '$baseText • Torbox cached only';
                                      }
                                      if (_torboxCacheStatus != null &&
                                          _torboxCacheCheckEnabled) {
                                        return '$baseText • Torbox cache check';
                                      }
                                      return baseText;
                                    }(),
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
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
                          child: Row(
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
                              IconButton(
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
                        child:
                            _buildTorrentCard(torrent, index - metadataRows),
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
        boxShadow: [
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
                    maxLines: 2,
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

            // Action Buttons
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

                  final button = Container(
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
                  );

                  return IgnorePointer(
                    ignoring: !isCached,
                    child: Opacity(
                      opacity: isCached ? 1.0 : 0.55,
                      child: GestureDetector(
                        onTap: isCached
                            ? () => _addToTorbox(torrent.infohash, torrent.name)
                            : null,
                        child: button,
                      ),
                    ),
                  );
                }

                Widget buildRealDebridButton() {
                  return GestureDetector(
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

                if (torboxButton == null && realDebridButton == null) {
                  return const SizedBox.shrink();
                }

                if (isCompactLayout) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (torboxButton != null) torboxButton,
                      if (torboxButton != null && realDebridButton != null)
                        const SizedBox(height: 8),
                      if (realDebridButton != null) realDebridButton,
                    ],
                  );
                }

                if (torboxButton != null && realDebridButton != null) {
                  return Row(
                    children: [
                      Expanded(child: torboxButton),
                      const SizedBox(width: 8),
                      Expanded(child: realDebridButton),
                    ],
                  );
                }

                final Widget singleButton = torboxButton ?? realDebridButton!;
                return SizedBox(width: double.infinity, child: singleButton);
              },
            ),
          ],
        ),
      ),
    );
  }
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

class _DebridActionTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool enabled;

  const _DebridActionTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: enabled ? onTap : null,
      child: Opacity(
        opacity: enabled ? 1.0 : 0.45,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: const Color(0xFF111827),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF1F2937)),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.14),
                blurRadius: 16,
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
                    colors: [color, color.withValues(alpha: 0.6)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
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
    );
  }
}
