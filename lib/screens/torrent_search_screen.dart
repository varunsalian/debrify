import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/torrent.dart';
import '../services/torrent_service.dart';
import '../services/debrid_service.dart';
import '../services/storage_service.dart';
import '../services/download_service.dart';
import '../utils/formatters.dart';
import '../utils/file_utils.dart';
import '../widgets/stat_chip.dart';
import 'video_player_screen.dart';

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
  bool _isLoading = false;
  String _errorMessage = '';
  bool _hasSearched = false;
  bool _isSearchExpanded = false; // New state for search box expansion
  String _selectedSearchEngine = 'torrents_csv'; // Default search engine
  
  late AnimationController _searchAnimationController;
  late AnimationController _listAnimationController;
  late AnimationController _searchBoxAnimationController; // New animation controller
  late Animation<double> _searchAnimation;
  late Animation<double> _listAnimation;
  late Animation<double> _searchBoxAnimation; // New animation for search box

  @override
  void initState() {
    super.initState();
    _searchAnimationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _listAnimationController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _searchBoxAnimationController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    
    _searchAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _searchAnimationController,
      curve: Curves.elasticOut,
    ));
    
    _listAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _listAnimationController,
      curve: Curves.easeInOut,
    ));

    _searchBoxAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _searchBoxAnimationController,
      curve: Curves.easeInOut,
    ));
    
    _searchAnimationController.forward();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _searchAnimationController.dispose();
    _listAnimationController.dispose();
    _searchBoxAnimationController.dispose();
    super.dispose();
  }

  Future<void> _searchTorrents(String query) async {
    if (query.trim().isEmpty) return;

    setState(() {
      _isLoading = true;
      _errorMessage = '';
      _hasSearched = true;
      _isSearchExpanded = true;
    });

    // Hide keyboard and animate search box
    _searchFocusNode.unfocus();
    _searchBoxAnimationController.forward();

    try {
      final torrents = await TorrentService.searchTorrents(query, engineName: _selectedSearchEngine);
      setState(() {
        _torrents = torrents;
        _isLoading = false;
      });
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
                'Magnet link copied to clipboard!',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF1E293B),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _toggleSearchBox() {
    if (_isSearchExpanded) {
      setState(() {
        _isSearchExpanded = false;
      });
      _searchBoxAnimationController.reverse();
    } else {
      setState(() {
        _isSearchExpanded = true;
      });
      _searchBoxAnimationController.forward();
      _searchFocusNode.requestFocus();
    }
  }

  Future<void> _addToRealDebrid(String infohash, String torrentName) async {
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
                const SizedBox(height: 16),
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
      final result = await DebridService.addTorrentToDebrid(apiKey, magnetLink);
      
      // Close loading dialog
      Navigator.of(context).pop();
      
      // Handle post-torrent action
      await _handlePostTorrentAction(result, torrentName, apiKey);
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

  Future<void> _showFileSelectionDialog(String infohash, String torrentName) async {
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

    String? selectedOption;

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return Dialog(
              backgroundColor: Colors.transparent,
              child: Container(
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
                    
                    // Content
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        children: [
                          // File selection options with beautiful cards
                          _buildOptionCard(
                            context: context,
                            title: 'All video files',
                            subtitle: 'Ideal for web series and stuff',
                            icon: Icons.video_library_rounded,
                            value: 'video',
                            selectedOption: selectedOption,
                            onChanged: (value) {
                              setState(() {
                                selectedOption = value;
                              });
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
                            selectedOption: selectedOption,
                            onChanged: (value) {
                              setState(() {
                                selectedOption = value;
                              });
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
                            selectedOption: selectedOption,
                            onChanged: (value) {
                              setState(() {
                                selectedOption = value;
                              });
                            },
                            gradient: const LinearGradient(
                              colors: [Color(0xFF8B5CF6), Color(0xFF7C3AED)],
                            ),
                          ),
                          
                          const SizedBox(height: 24),
                          
                          // Action buttons
                          Row(
                            children: [
                              Expanded(
                                child: Container(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        Colors.grey.withValues(alpha: 0.2),
                                        Colors.grey.withValues(alpha: 0.1),
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: Colors.grey.withValues(alpha: 0.3),
                                      width: 1,
                                    ),
                                  ),
                                  child: Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      onTap: () => Navigator.of(context).pop(),
                                      borderRadius: BorderRadius.circular(12),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(vertical: 16),
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Icon(
                                              Icons.close_rounded,
                                              color: Colors.grey[400],
                                              size: 18,
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              'Cancel',
                                              style: TextStyle(
                                                color: Colors.grey[400],
                                                fontWeight: FontWeight.w600,
                                                fontSize: 14,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Container(
                                  decoration: BoxDecoration(
                                    gradient: selectedOption == null
                                        ? LinearGradient(
                                            colors: [
                                              Colors.grey.withValues(alpha: 0.3),
                                              Colors.grey.withValues(alpha: 0.2),
                                            ],
                                          )
                                        : const LinearGradient(
                                            colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                                          ),
                                    borderRadius: BorderRadius.circular(12),
                                    boxShadow: selectedOption == null
                                        ? null
                                        : [
                                            BoxShadow(
                                              color: const Color(0xFF6366F1).withValues(alpha: 0.4),
                                              blurRadius: 8,
                                              offset: const Offset(0, 4),
                                            ),
                                          ],
                                  ),
                                  child: Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      onTap: selectedOption == null
                                          ? null
                                          : () {
                                              Navigator.of(context).pop();
                                              _addToRealDebridWithSelection(infohash, torrentName, selectedOption!);
                                            },
                                      borderRadius: BorderRadius.circular(12),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(vertical: 16),
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Icon(
                                              Icons.download_rounded,
                                              color: selectedOption == null ? Colors.grey[600] : Colors.white,
                                              size: 18,
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              'Add to Debrid',
                                              style: TextStyle(
                                                color: selectedOption == null ? Colors.grey[600] : Colors.white,
                                                fontWeight: FontWeight.w600,
                                                fontSize: 14,
                                              ),
                                            ),
                                          ],
                                        ),
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
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _addToRealDebridWithSelection(String infohash, String torrentName, String fileSelection) async {
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
      await _handlePostTorrentAction(result, torrentName, apiKey);
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

  Future<void> _handlePostTorrentAction(Map<String, dynamic> result, String torrentName, String apiKey) async {
    final postAction = await StorageService.getPostTorrentAction();
    final downloadLink = result['downloadLink'] as String;
    final fileSelection = result['fileSelection'] as String;
    final links = result['links'] as List<dynamic>;

    switch (postAction) {
      case 'copy':
        // Copy to clipboard (default behavior)
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
        // Play video - handle multiple files with playlist
        if (fileSelection == 'video' && links.length > 1) {
          // Multiple video files - create playlist
          await _handlePlayMultiFileTorrent(links, torrentName, apiKey);
        } else {
          // Single file or all files - play directly
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => VideoPlayerScreen(
                videoUrl: downloadLink,
                title: torrentName,
              ),
            ),
          );
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

  Future<void> _handlePlayMultiFileTorrent(List<dynamic> links, String torrentName, String apiKey) async {
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

      final List<PlaylistEntry> entries = [];
      for (final link in links) {
        try {
          final res = await DebridService.unrestrictLink(apiKey, link);
          final url = (res['download'] ?? '').toString();
          final fname = (res['filename'] ?? '').toString();
          final mime = (res['mimeType'] ?? '').toString();
          if (url.isEmpty) continue;
          // Filter to videos only
          if (FileUtils.isVideoMimeType(mime) || FileUtils.isVideoFile(fname)) {
            entries.add(PlaylistEntry(url: url, title: fname.isNotEmpty ? fname : torrentName));
          }
        } catch (_) {
          // Skip problematic item
          continue;
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
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => VideoPlayerScreen(
            videoUrl: entries.first.url,
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
                              await _downloadFile(link['download'], fileName);
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

  Future<void> _downloadFile(String downloadLink, String fileName) async {
    try {
      await DownloadService.instance.enqueueDownload(
        url: downloadLink,
        fileName: fileName,
        context: context,
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

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF020617), // Slate 950
            Color(0xFF0F172A), // Slate 900
          ],
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            // Animated Search Box
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              margin: EdgeInsets.all(_isSearchExpanded ? 4 : 8),
              padding: EdgeInsets.all(_isSearchExpanded ? 8 : 12),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF1E293B), // Slate 800
                    Color(0xFF334155), // Slate 700
                  ],
                ),
                borderRadius: BorderRadius.circular(_isSearchExpanded ? 12 : 16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: _isSearchExpanded ? 10 : 20,
                    offset: Offset(0, _isSearchExpanded ? 5 : 10),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Search Icon and Title (only show when not expanded)
                  if (!_isSearchExpanded) ...[
                    ScaleTransition(
                      scale: _searchAnimation,
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF6366F1).withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.search_rounded,
                              color: Color(0xFF6366F1),
                              size: 24,
                            ),
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'Search Torrents',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Find and download your favorite content',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.white.withValues(alpha: 0.7),
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                        ],
                      ),
                    ),
                  ],
                  
                  // Search Input
                  Focus(
                    onKey: (node, event) {
                      if (event is! RawKeyDownEvent) return KeyEventResult.ignored;
                      if (!_isSearchExpanded && (event.logicalKey == LogicalKeyboardKey.select || event.logicalKey == LogicalKeyboardKey.enter)) {
                        _toggleSearchBox();
                        _searchFocusNode.requestFocus();
                        return KeyEventResult.handled;
                      }
                      return KeyEventResult.ignored;
                    },
                    child: GestureDetector(
                      onTap: _isSearchExpanded ? null : _toggleSearchBox,
                      child: Container(
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
                            hintText: _isSearchExpanded ? 'Search torrents...' : 'Enter torrent name...',
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
                            fillColor: const Color(0xFF334155),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                          ),
                          onChanged: (value) => setState(() {}),
                        ),
                      ),
                    ),
                  ),
                  
                  // Search Engine Dropdown
                  const SizedBox(height: 24),
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: const Color(0xFF334155),
                    ),
                    child: DropdownButtonFormField<String>(
                      value: _selectedSearchEngine,
                      onChanged: (String? newValue) {
                        if (newValue != null) {
                          setState(() {
                            _selectedSearchEngine = newValue;
                          });
                        }
                      },
                      style: const TextStyle(color: Colors.white),
                      dropdownColor: const Color(0xFF1E293B),
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(12)),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: Color(0xFF334155),
                        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                        isDense: false,
                      ),
                      items: [
                        DropdownMenuItem(
                          value: 'torrents_csv',
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF6366F1).withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Icon(
                                  Icons.search_rounded,
                                  color: Color(0xFF6366F1),
                                  size: 16,
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Text('Torrents CSV'),
                            ],
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'pirate_bay',
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF59E0B).withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Icon(
                                  Icons.sailing_rounded,
                                  color: Color(0xFFF59E0B),
                                  size: 16,
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Text('The Pirate Bay'),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  // Search Button (only show when not expanded)
                  if (!_isSearchExpanded) ...[
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () => _searchTorrents(_searchController.text),
                        icon: const Icon(Icons.search_rounded),
                        label: const Text(
                          'Search',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF6366F1),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 8,
                          shadowColor: const Color(0xFF6366F1).withValues(alpha: 0.4),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            
            // Content Section
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: 16),
                child: _buildContent(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B).withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const CircularProgressIndicator(
              color: Color(0xFF6366F1),
              strokeWidth: 3,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Searching for torrents...',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Please wait while we find the best results',
            style: TextStyle(
              fontSize: 12,
              color: Colors.white.withValues(alpha: 0.7),
            ),
          ),
        ],
      );
    }

    if (_errorMessage.isNotEmpty) {
      return Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF7F1D1D), // Red 900
              Color(0xFF991B1B), // Red 800
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
      );
    }

    if (!_hasSearched) {
      return Container(
        margin: const EdgeInsets.all(8),
        padding: const EdgeInsets.all(12),
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
      );
    }

    if (_torrents.isEmpty) {
      return Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.all(16),
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
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF59E0B).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                Icons.search_off_rounded,
                color: Color(0xFFF59E0B),
                size: 36,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'No Results Found',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Try different keywords or check your spelling',
              style: TextStyle(
                fontSize: 14,
                color: Colors.white.withValues(alpha: 0.7),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return FadeTransition(
      opacity: _listAnimation,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _torrents.length,
        itemBuilder: (context, index) {
          final torrent = _torrents[index];
          return _buildTorrentCard(torrent, index);
        },
      ),
    );
  }

  Widget _buildTorrentCard(Torrent torrent, int index) {
    return TweenAnimationBuilder<double>(
      duration: Duration(milliseconds: 300 + (index * 100)),
      tween: Tween(begin: 0.0, end: 1.0),
      builder: (context, value, child) {
        return Transform.translate(
          offset: Offset(0, 50 * (1 - value)),
          child: Opacity(
            opacity: value,
            child: Container(
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
                          color: const Color(0xFF3B82F6), // Blue
                        ),
                        StatChip(
                          icon: Icons.upload_rounded,
                          text: '${torrent.seeders}',
                          color: const Color(0xFF10B981), // Emerald
                        ),
                        StatChip(
                          icon: Icons.download_rounded,
                          text: '${torrent.leechers}',
                          color: const Color(0xFFF59E0B), // Amber
                        ),
                        StatChip(
                          icon: Icons.check_circle_rounded,
                          text: '${torrent.completed}',
                          color: const Color(0xFF8B5CF6), // Violet
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
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: () => _copyMagnetLink(torrent.infohash),
                              onFocusChange: (_) {},
                              focusColor: const Color(0x336366F1),
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF6366F1).withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: const Color(0xFF6366F1).withValues(alpha: 0.3),
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.copy_rounded,
                                      color: const Color(0xFF6366F1),
                                      size: 14,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Copy Magnet',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w500,
                                        color: const Color(0xFF6366F1),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: () => _addToRealDebrid(torrent.infohash, torrent.name),
                              onLongPress: () => _showFileSelectionDialog(torrent.infohash, torrent.name),
                              onFocusChange: (_) {},
                              focusColor: const Color(0x3310B981),
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF10B981).withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: const Color(0xFF10B981).withValues(alpha: 0.3),
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.download_rounded,
                                      color: const Color(0xFF10B981),
                                      size: 14,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Add to Debrid',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w500,
                                        color: const Color(0xFF10B981),
                                      ),
                                    ),
                                    const SizedBox(width: 2),
                                    Icon(
                                      Icons.more_horiz,
                                      color: const Color(0xFF10B981),
                                      size: 10,
                                    ),
                                  ],
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
            ),
          ),
        );
      },
    );
  }
} 