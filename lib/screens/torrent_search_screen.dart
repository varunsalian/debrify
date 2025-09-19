import 'package:flutter/material.dart';
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
    
    _listAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _listAnimationController,
      curve: Curves.easeInOut,
    ));
    
    _listAnimationController.forward();
    _loadDefaultSettings();
  }

  Future<void> _loadDefaultSettings() async {
    final defaultTorrentsCsv = await StorageService.getDefaultTorrentsCsvEnabled();
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

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _listAnimationController.dispose();
    super.dispose();
  }

  Future<void> _searchTorrents(String query) async {
    if (query.trim().isEmpty) return;

    setState(() {
      _isLoading = true;
      _errorMessage = '';
      _hasSearched = true;
    });

    // Hide keyboard
    _searchFocusNode.unfocus();

    try {
      final result = await TorrentService.searchAllEngines(
        query,
        useTorrentsCsv: _useTorrentsCsv,
        usePirateBay: _usePirateBay,
      );
      setState(() {
        _torrents = result['torrents'] as List<Torrent>;
        _engineCounts = Map<String, int>.from(result['engineCounts'] as Map);
        _isLoading = false;
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



  Future<void> _addToRealDebrid(String infohash, String torrentName, int index) async {
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
                child: const Icon(
                  Icons.error,
                  color: Colors.white,
                  size: 16,
                ),
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
        final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween(begin: 0.95, end: 1.0).animate(curved),
            child: Dialog(
              backgroundColor: Theme.of(context).colorScheme.surface,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
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
                      valueColor: AlwaysStoppedAnimation<Color>(Theme.of(context).colorScheme.primary),
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
                child: const Icon(
                  Icons.error,
                  color: Colors.white,
                  size: 16,
                ),
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  Future<void> _showFileSelectionDialog(String infohash, String torrentName, int index) async {
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
                child: const Icon(
                  Icons.error,
                  color: Colors.white,
                  size: 16,
                ),
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                colors: [
                  Color(0xFF1E293B),
                  Color(0xFF334155),
                ],
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
                      colors: [
                        Color(0xFF6366F1),
                        Color(0xFF8B5CF6),
                      ],
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
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
                          _addToRealDebridWithSelection(infohash, torrentName, value!, index);
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
                          _addToRealDebridWithSelection(infohash, torrentName, value!, index);
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
                          _addToRealDebridWithSelection(infohash, torrentName, value!, index);
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
                          _addToRealDebridWithSelection(infohash, torrentName, value!, index);
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

  Future<void> _addToRealDebridWithSelection(String infohash, String torrentName, String fileSelection, int index) async {
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
                child: const Icon(
                  Icons.error,
                  color: Colors.white,
                  size: 16,
                ),
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
      final result = await DebridService.addTorrentToDebrid(apiKey, magnetLink, tempFileSelection: fileSelection);
      
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
                child: const Icon(
                  Icons.error,
                  color: Colors.white,
                  size: 16,
                ),
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
          duration: const Duration(seconds: 4),
        ),
      );
    }
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
        gradient: isSelected ? gradient : LinearGradient(
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
        boxShadow: isSelected ? [
          BoxShadow(
            color: gradient.colors.first.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ] : null,
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
                    color: isSelected 
                        ? Colors.white
                        : Colors.transparent,
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

  Future<void> _handlePostTorrentAction(Map<String, dynamic> result, String torrentName, String apiKey, int index) async {
    final postAction = await StorageService.getPostTorrentAction();
    final downloadLink = result['downloadLink'] as String;
    final fileSelection = result['fileSelection'] as String;
    final links = result['links'] as List<dynamic>;
    final files = result['files'] as List<dynamic>?;
    final updatedInfo = result['updatedInfo'] as Map<String, dynamic>?;

    switch (postAction) {
      case 'none':
        // Do nothing - just show success message
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
                    Icons.check,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Torrent added to Real Debrid successfully!',
                    style: TextStyle(fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF1E293B),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
            duration: const Duration(seconds: 4),
          ),
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
                  child: const Icon(
                    Icons.check,
                    color: Colors.white,
                    size: 16,
                  ),
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
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
            duration: const Duration(seconds: 4),
          ),
        );
        break;
      case 'play':
        // Play video - check if it's actually a video file first
        if (fileSelection == 'video' && links.length > 1) {
          // Multiple video files - create playlist with true lazy loading
          await _handlePlayMultiFileTorrentWithInfo(links, files, updatedInfo, torrentName, apiKey, index);
        } else {
          // Single file - check MIME type after unrestricting
          try {
            final unrestrictResult = await DebridService.unrestrictLink(apiKey, links[0]);
            final videoUrl = unrestrictResult['download'];
            final mimeType = unrestrictResult['mimeType']?.toString() ?? '';
            
            // Check if it's actually a video using MIME type
            if (FileUtils.isVideoMimeType(mimeType)) {
              							Navigator.of(context).push(
								MaterialPageRoute(
									builder: (context) => VideoPlayerScreen(
										videoUrl: videoUrl,
										title: torrentName,
									),
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
                        child: const Icon(
                          Icons.check,
                          color: Colors.white,
                          size: 16,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Added to torrent but the file is not a video file',
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                  backgroundColor: const Color(0xFF1E293B),
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                      child: const Icon(
                        Icons.error,
                        color: Colors.white,
                        size: 16,
                      ),
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
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                margin: const EdgeInsets.all(16),
                duration: const Duration(seconds: 4),
              ),
            );
          }
        }
        break;
      case 'download':
        // Download file(s)
        if (fileSelection == 'video' && links.length > 1) {
          // Multiple video files - show selection dialog for download
          _showDownloadSelectionDialog(links, torrentName);
        } else {
          // Single file - download directly
          await _downloadFile(downloadLink, torrentName);
        }
        break;
    }
  }

  Future<void> _handlePlayMultiFileTorrentWithInfo(List<dynamic> links, List<dynamic>? files, Map<String, dynamic>? updatedInfo, String torrentName, String apiKey, int index) async {
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
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              margin: const EdgeInsets.all(16),
              duration: const Duration(seconds: 4),
            ),
          );
        }
        return;
      }

      // Get selected files from the torrent info
      final selectedFiles = files.where((file) => file['selected'] == 1).toList();
      
      // If no selected files, use all files (they might all be selected by default)
      final allFilesToUse = selectedFiles.isNotEmpty ? selectedFiles : files;
      
      // Filter to only video files
      final filesToUse = allFilesToUse.where((file) {
        String? filename = file['name']?.toString() ?? 
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
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
        String? name = file['name']?.toString() ?? 
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
                (info.season! == lowestSeason && info.episode! < lowestEpisode)) {
              lowestSeason = info.season!;
              lowestEpisode = info.episode!;
              firstEpisodeIndex = i;
            }
          }
        }
        
        // Create playlist entries with true lazy loading
        for (int i = 0; i < filesToUse.length; i++) {
          final file = filesToUse[i];
          String? filename = file['name']?.toString() ?? 
                            file['filename']?.toString() ?? 
                            file['path']?.toString();
          
          // If we got a path, extract just the filename
          if (filename != null && filename.startsWith('/')) {
            filename = filename.split('/').last;
          }
          
          final finalFilename = filename ?? 'Unknown File';
          
          // Check if we have a corresponding link
          if (i >= links.length) {
            // Skip if no corresponding link
            continue;
          }
          
          if (i == firstEpisodeIndex) {
            // First episode: try to unrestrict for immediate playback
            try {
              final unrestrictResult = await DebridService.unrestrictLink(apiKey, links[i]);
              final url = unrestrictResult['download']?.toString() ?? '';
              if (url.isNotEmpty) {
                entries.add(PlaylistEntry(
                  url: url,
                  title: finalFilename,
                ));
              } else {
                // If unrestriction failed or returned empty URL, add as restricted link
                entries.add(PlaylistEntry(
                  url: '', // Empty URL - will be filled when unrestricted
                  title: finalFilename,
                  restrictedLink: links[i],
                  apiKey: apiKey,
                ));
              }
            } catch (e) {
              // If unrestriction fails, add as restricted link for lazy loading
              entries.add(PlaylistEntry(
                url: '', // Empty URL - will be filled when unrestricted
                title: finalFilename,
                restrictedLink: links[i],
                apiKey: apiKey,
              ));
            }
          } else {
            // Other episodes: keep restricted links for lazy loading
            entries.add(PlaylistEntry(
              url: '', // Empty URL - will be filled when unrestricted
              title: finalFilename,
              restrictedLink: links[i],
              apiKey: apiKey,
            ));
          }
        }
      } else {
        // For movies: unrestrict only the first video
        for (int i = 0; i < filesToUse.length; i++) {
          final file = filesToUse[i];
          String? filename = file['name']?.toString() ?? 
                            file['filename']?.toString() ?? 
                            file['path']?.toString();
          
          // If we got a path, extract just the filename
          if (filename != null && filename.startsWith('/')) {
            filename = filename.split('/').last;
          }
          
          final finalFilename = filename ?? 'Unknown File';
          
          // Check if we have a corresponding link
          if (i >= links.length) {
            // Skip if no corresponding link
            continue;
          }
          
          if (i == 0) {
            // First video: try to unrestrict for immediate playback
            try {
              final unrestrictResult = await DebridService.unrestrictLink(apiKey, links[i]);
              final url = unrestrictResult['download']?.toString() ?? '';
              if (url.isNotEmpty) {
                entries.add(PlaylistEntry(
                  url: url,
                  title: finalFilename,
                ));
              } else {
                // If unrestriction failed or returned empty URL, add as restricted link
                entries.add(PlaylistEntry(
                  url: '', // Empty URL - will be filled when unrestricted
                  title: finalFilename,
                  restrictedLink: links[i],
                  apiKey: apiKey,
                ));
              }
            } catch (e) {
              // If unrestriction fails, add as restricted link for lazy loading
              entries.add(PlaylistEntry(
                url: '', // Empty URL - will be filled when unrestricted
                title: finalFilename,
                restrictedLink: links[i],
                apiKey: apiKey,
              ));
            }
          } else {
            // Other videos: keep restricted links for lazy loading
            entries.add(PlaylistEntry(
              url: '', // Empty URL - will be filled when unrestricted
              title: finalFilename,
              restrictedLink: links[i],
              apiKey: apiKey,
            ));
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
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
      
      			Navigator.of(context).push(
				MaterialPageRoute(
					builder: (context) => VideoPlayerScreen(
						videoUrl: initialVideoUrl,
						title: torrentName,
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
                  child: const Icon(
                    Icons.error,
                    color: Colors.white,
                    size: 16,
                  ),
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
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  Future<void> _showDownloadSelectionDialog(List<dynamic> links, String torrentName) async {
    // First, unrestrict all links to get proper download URLs and filenames
    final apiKey = await StorageService.getApiKey();
    if (apiKey == null) return;

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
              'Preparing download links…',
              style: TextStyle(color: Colors.white),
            ),
          ],
        ),
      ),
    );

    try {
      final List<Map<String, dynamic>> unrestrictedLinks = [];
      for (final link in links) {
        try {
          final res = await DebridService.unrestrictLink(apiKey, link);
          final url = (res['download'] ?? '').toString();
          final fname = (res['filename'] ?? '').toString();
          final mime = (res['mimeType'] ?? '').toString();
          if (url.isEmpty) continue;
          // Filter to videos only
          if (FileUtils.isVideoMimeType(mime) || FileUtils.isVideoFile(fname)) {
            unrestrictedLinks.add({
              'download': url,
              'filename': fname.isNotEmpty ? fname : 'Video File',
            });
          }
        } catch (_) {
          // Skip problematic item
          continue;
        }
      }

      if (mounted) Navigator.of(context).pop(); // close loading

      if (unrestrictedLinks.isEmpty) {
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
                      'No downloadable video files found in this torrent.',
                      style: TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
              backgroundColor: const Color(0xFF1E293B),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
                        'Download all ${unrestrictedLinks.length} videos',
                        style: TextStyle(color: Colors.grey[400]),
                      ),
                      onTap: () async {
                        Navigator.of(context).pop();
                        await _downloadAllFiles(unrestrictedLinks, torrentName);
                      },
                    ),
                    const Divider(color: Colors.grey),
                    // Individual video options - scrollable
                    Expanded(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: unrestrictedLinks.length,
                        itemBuilder: (context, index) {
                          final link = unrestrictedLinks[index];
                          final fileName = link['filename'] as String;
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
                              await _downloadFile(link['download'], fileName, torrentName: torrentName);
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
                  child: const Icon(
                    Icons.error,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Failed to prepare download links: ${e.toString()}',
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF1E293B),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }



  Future<void> _downloadAllFiles(List<Map<String, dynamic>> links, String torrentName) async {
    try {
      // Start downloads for all files
      for (final link in links) {
        final url = (link['download'] ?? '').toString();
        final fileName = (link['filename'] ?? 'file').toString();
        if (url.isEmpty) continue;
        await DownloadService.instance.enqueueDownload(
          url: url,
          fileName: fileName,
          context: context,
          torrentName: torrentName,
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
                  'Started downloading ${links.length} videos! Check Downloads tab for progress.',
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
          backgroundColor: const Color(0xFF1E293B),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                child: const Icon(
                  Icons.error,
                  color: Colors.white,
                  size: 16,
                ),
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  Future<void> _downloadFile(String downloadLink, String fileName, {String? torrentName}) async {
    try {
      await DownloadService.instance.enqueueDownload(
        url: downloadLink,
        fileName: fileName,
        context: context,
        torrentName: torrentName ?? fileName, // Use provided torrent name or fileName as fallback
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                child: const Icon(
                  Icons.error,
                  color: Colors.white,
                  size: 16,
                ),
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                                  if (_hasSearched && _searchController.text.trim().isNotEmpty) {
                                    _searchTorrents(_searchController.text);
                                  }
                                },
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Torrents CSV',
                                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
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
                                  if (_hasSearched && _searchController.text.trim().isNotEmpty) {
                                    _searchTorrents(_searchController.text);
                                  }
                                },
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Pirate Bay',
                                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                      padding: const EdgeInsets.only(bottom: 16, left: 12, right: 12, top: 12),
                      itemCount: 6,
                      itemBuilder: (context, i) {
                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E293B).withValues(alpha: 0.5),
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
                              colors: [
                                Color(0xFF7F1D1D),
                                Color(0xFF991B1B),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFEF4444).withValues(alpha: 0.3),
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
                                onPressed: () => _searchTorrents(_searchController.text),
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
                              colors: [
                                Color(0xFF1E293B),
                                Color(0xFF334155),
                              ],
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
                                  color: const Color(0xFF6366F1).withValues(alpha: 0.2),
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
                                          color: Colors.white.withValues(alpha: 0.8),
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
                        Container(
                          margin: const EdgeInsets.all(12),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                Color(0xFF1E293B),
                                Color(0xFF334155),
                              ],
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

                  return ListView.builder(
                    padding: const EdgeInsets.only(bottom: 16),
                    itemCount: _torrents.length + 2,
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return FadeTransition(
                          opacity: _listAnimation,
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                                  color: const Color(0xFF1E40AF).withValues(alpha: 0.4),
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
                                    '${_torrents.length} Result${_torrents.length == 1 ? '' : 's'} Found • ${_buildEngineBreakdownText()}',
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
                          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                              Icon(
                                Icons.sort_rounded,
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                                size: 16,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Sort by:',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                                    DropdownMenuItem(value: 'relevance', child: Text('Relevance', style: TextStyle(fontSize: 12))),
                                    DropdownMenuItem(value: 'name', child: Text('Name', style: TextStyle(fontSize: 12))),
                                    DropdownMenuItem(value: 'size', child: Text('Size', style: TextStyle(fontSize: 12))),
                                    DropdownMenuItem(value: 'seeders', child: Text('Seeders', style: TextStyle(fontSize: 12))),
                                    DropdownMenuItem(value: 'date', child: Text('Date', style: TextStyle(fontSize: 12))),
                                  ],
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.onSurface,
                                    fontSize: 12,
                                  ),
                                  underline: Container(),
                                  icon: Icon(
                                    Icons.arrow_drop_down,
                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                                  _sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  size: 16,
                                ),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                              ),
                            ],
                          ),
                        );
                      }

                      final torrent = _torrents[index - 2];
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: _buildTorrentCard(torrent, index - 2),
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
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => _copyMagnetLink(torrent.infohash),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF3B82F6).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: const Color(0xFF3B82F6).withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.copy_rounded,
                            color: const Color(0xFF60A5FA),
                            size: 14,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Copy Magnet',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: const Color(0xFF60A5FA),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: GestureDetector(
                    onTap: () => _addToRealDebrid(torrent.infohash, torrent.name, index),
                    onLongPress: () {
                      _showFileSelectionDialog(torrent.infohash, torrent.name, index);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF3B82F6).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: const Color(0xFF3B82F6).withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.download_rounded,
                            color: const Color(0xFF60A5FA),
                            size: 14,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Add to Debrid',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: const Color(0xFF60A5FA),
                            ),
                          ),
                          const SizedBox(width: 2),
                          Icon(
                            Icons.more_horiz,
                            color: const Color(0xFF60A5FA),
                            size: 10,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
} 