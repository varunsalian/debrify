import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/rd_torrent.dart';
import '../models/debrid_download.dart';
import '../services/debrid_service.dart';
import '../services/storage_service.dart';
import '../utils/formatters.dart';
import '../utils/file_utils.dart';
import '../utils/series_parser.dart';
import '../widgets/stat_chip.dart';
import 'video_player_screen.dart';
import '../services/download_service.dart';
import 'dart:ui'; // Added for ImageFilter

class DebridDownloadsScreen extends StatefulWidget {
  const DebridDownloadsScreen({super.key});

  @override
  State<DebridDownloadsScreen> createState() => _DebridDownloadsScreenState();
}

class _DebridDownloadsScreenState extends State<DebridDownloadsScreen> with TickerProviderStateMixin {
  late TabController _tabController;
  int _selectedIndex = 0;
  
  // Torrent Downloads data
  final List<RDTorrent> _torrents = [];
  final ScrollController _torrentScrollController = ScrollController();
  bool _isLoadingTorrents = false;
  bool _isLoadingMoreTorrents = false;
  String _torrentErrorMessage = '';
  int _torrentPage = 1;
  bool _hasMoreTorrents = true;
  
  // Downloads data
  final List<DebridDownload> _downloads = [];
  final ScrollController _downloadScrollController = ScrollController();
  bool _isLoadingDownloads = false;
  bool _isLoadingMoreDownloads = false;
  String _downloadErrorMessage = '';
  int _downloadPage = 1;
  bool _hasMoreDownloads = true;
  
  String? _apiKey;
  static const int _limit = 50;
  
  // Magnet input
  final TextEditingController _magnetController = TextEditingController();
  bool _isAddingMagnet = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      setState(() {
        _selectedIndex = _tabController.index;
      });
    });
    _loadApiKeyAndData();
    _torrentScrollController.addListener(_onTorrentScroll);
    _downloadScrollController.addListener(_onDownloadScroll);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _torrentScrollController.dispose();
    _downloadScrollController.dispose();
    _magnetController.dispose();
    super.dispose();
  }

  void _onTorrentScroll() {
    if (_torrentScrollController.position.pixels >= _torrentScrollController.position.maxScrollExtent - 200) {
      if (!_isLoadingMoreTorrents && _hasMoreTorrents) {
        _loadMoreTorrents();
      }
    }
  }

  void _onDownloadScroll() {
    if (_downloadScrollController.position.pixels >= _downloadScrollController.position.maxScrollExtent - 200) {
      if (!_isLoadingMoreDownloads && _hasMoreDownloads) {
        _loadMoreDownloads();
      }
    }
  }

  Future<void> _loadApiKeyAndData() async {
    final apiKey = await StorageService.getApiKey();
    
    setState(() {
      _apiKey = apiKey;
    });

    if (apiKey != null) {
      await _fetchTorrents(apiKey, reset: true);
      await _fetchDownloads(apiKey, reset: true);
    } else {
      setState(() {
        _torrentErrorMessage = 'No API key configured. Please add your Real Debrid API key in Settings.';
        _downloadErrorMessage = 'No API key configured. Please add your Real Debrid API key in Settings.';
      });
    }
  }

  Future<void> _fetchTorrents(String apiKey, {bool reset = false}) async {
    if (reset) {
      setState(() {
        _torrentPage = 1;
        _hasMoreTorrents = true;
        _torrents.clear();
      });
    }

    setState(() {
      _isLoadingTorrents = true;
      _torrentErrorMessage = '';
    });

    try {
      final result = await DebridService.getTorrents(
        apiKey,
        page: _torrentPage,
        limit: _limit,
        // filter: 'downloaded', // Temporarily removed to test
      );

      final List<RDTorrent> newTorrents = result['torrents'];
      final bool hasMore = result['hasMore'];

      setState(() {
        if (reset) {
          _torrents.clear();
        }
        // Filter to show only downloaded torrents
        final downloadedTorrents = newTorrents.where((torrent) => torrent.isDownloaded).toList();
        _torrents.addAll(downloadedTorrents);
        _hasMoreTorrents = hasMore;
        _torrentPage++;
        _isLoadingTorrents = false;
      });
    } catch (e) {
      setState(() {
        _torrentErrorMessage = _getUserFriendlyErrorMessage(e);
        _isLoadingTorrents = false;
      });
    }
  }

  Future<void> _loadMoreTorrents() async {
    if (_apiKey == null || _isLoadingMoreTorrents || !_hasMoreTorrents) return;

    setState(() {
      _isLoadingMoreTorrents = true;
    });

    try {
      final result = await DebridService.getTorrents(
        _apiKey!,
        page: _torrentPage,
        limit: _limit,
        // filter: 'downloaded', // Temporarily removed to test
      );

      final List<RDTorrent> newTorrents = result['torrents'];
      final bool hasMore = result['hasMore'];

      setState(() {
        // Filter to show only downloaded torrents
        final downloadedTorrents = newTorrents.where((torrent) => torrent.isDownloaded).toList();
        _torrents.addAll(downloadedTorrents);
        _hasMoreTorrents = hasMore;
        _torrentPage++;
        _isLoadingMoreTorrents = false;
      });
    } catch (e) {
      setState(() {
        _torrentErrorMessage = _getUserFriendlyErrorMessage(e);
        _isLoadingMoreTorrents = false;
      });
    }
  }

  // Downloads methods
  Future<void> _fetchDownloads(String apiKey, {bool reset = false}) async {
    if (reset) {
      setState(() {
        _downloadPage = 1;
        _hasMoreDownloads = true;
        _downloads.clear();
      });
    }

    setState(() {
      _isLoadingDownloads = true;
      _downloadErrorMessage = '';
    });

    try {
      final result = await DebridService.getDownloads(
        apiKey,
        page: _downloadPage,
        limit: _limit,
      );

      final List<DebridDownload> newDownloads = result['downloads'];
      final bool hasMore = result['hasMore'];

      setState(() {
        if (reset) {
          _downloads.clear();
        }
        _downloads.addAll(newDownloads);
        _hasMoreDownloads = hasMore;
        _downloadPage++;
        _isLoadingDownloads = false;
      });
    } catch (e) {
      setState(() {
        _downloadErrorMessage = _getUserFriendlyErrorMessage(e);
        _isLoadingDownloads = false;
      });
    }
  }

  Future<void> _loadMoreDownloads() async {
    if (_apiKey == null || _isLoadingMoreDownloads || !_hasMoreDownloads) return;

    setState(() {
      _isLoadingMoreDownloads = true;
    });

    try {
      final result = await DebridService.getDownloads(
        _apiKey!,
        page: _downloadPage,
        limit: _limit,
      );

      final List<DebridDownload> newDownloads = result['downloads'];
      final bool hasMore = result['hasMore'];

      setState(() {
        _downloads.addAll(newDownloads);
        _hasMoreDownloads = hasMore;
        _downloadPage++;
        _isLoadingMoreDownloads = false;
      });
    } catch (e) {
      setState(() {
        _downloadErrorMessage = _getUserFriendlyErrorMessage(e);
        _isLoadingMoreDownloads = false;
      });
    }
  }

  Future<void> _handleFileOptions(RDTorrent torrent) async {
    if (_apiKey == null) return;

    if (torrent.links.length == 1) {
      // Single link - unrestrict and copy directly
      try {
        final unrestrictResult = await DebridService.unrestrictLink(_apiKey!, torrent.links[0]);
        final downloadLink = unrestrictResult['download'];
        if (mounted) {
          _copyToClipboard(downloadLink);
        }
      } catch (e) {
        if (mounted) {
          _showError('Failed to unrestrict link: ${e.toString()}');
        }
      }
    } else {
      // Multiple links - show popup with all files
      if (mounted) {
        _showMultipleLinksDialog(torrent, showPlayButtons: true);
      }
    }
  }

  Future<void> _handlePlayVideo(RDTorrent torrent) async {
    if (_apiKey == null) return;

    if (torrent.links.length == 1) {
      // Single file - check MIME type after unrestricting
      try {
        final unrestrictResult = await DebridService.unrestrictLink(_apiKey!, torrent.links[0]);
        final downloadLink = unrestrictResult['download'];
        final mimeType = unrestrictResult['mimeType']?.toString() ?? '';
        
        // Check if it's actually a video using MIME type
        if (FileUtils.isVideoMimeType(mimeType)) {
          if (mounted) {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => VideoPlayerScreen(
                  videoUrl: downloadLink,
                  title: torrent.filename,
                  subtitle: Formatters.formatFileSize(torrent.bytes),
                ),
              ),
            );
          }
        } else {
          if (mounted) {
            _showError('This file is not a video (MIME type: $mimeType)');
          }
        }
      } catch (e) {
        if (mounted) {
          _showError('Failed to load video: ${e.toString()}');
        }
      }
    } else {
      // Multiple files - show popup with play options
      if (mounted) {
        _showMultipleLinksDialog(torrent, showPlayButtons: true);
      }
    }
  }

  // Download action methods
  Future<void> _handleDownloadAction(DebridDownload download) async {
    if (_apiKey == null) return;

    // Copy download link to clipboard
    _copyToClipboard(download.download);
  }

  Future<void> _handlePlayDownload(DebridDownload download) async {
    if (_apiKey == null) return;

    // Check if it's a video file
    if (FileUtils.isVideoMimeType(download.mimeType)) {
      if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => VideoPlayerScreen(
              videoUrl: download.download,
              title: download.filename,
              subtitle: Formatters.formatFileSize(download.filesize),
            ),
          ),
        );
      }
    } else {
      if (mounted) {
        _showError('This file is not a video (MIME type: ${download.mimeType})');
      }
    }
  }

  Future<void> _handleDeleteTorrent(RDTorrent torrent) async {
    if (_apiKey == null) return;

    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Delete Torrent',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Are you sure you want to delete "${torrent.filename}" from Real Debrid? This action cannot be undone.',
          style: const TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.grey),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Colors.red,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        // Show loading indicator
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
                  'Deleting torrent...',
                  style: TextStyle(color: Colors.white),
                ),
              ],
            ),
          ),
        );

        // Delete the torrent
        await DebridService.deleteTorrent(_apiKey!, torrent.id);
        
        // Check if widget is still mounted before updating UI
        if (mounted) {
          // Close loading dialog
          Navigator.of(context).pop();
          
          // Remove the torrent from the local list
          setState(() {
            _torrents.removeWhere((t) => t.id == torrent.id);
          });
          
          // Show success message
          _showSuccess('Torrent deleted successfully!');
        }
      } catch (e) {
        // Check if widget is still mounted before updating UI
        if (mounted) {
          // Close loading dialog
          Navigator.of(context).pop();
          
          // Show error message
          _showError('Failed to delete torrent: ${e.toString()}');
        }
      }
    }
  }

  Future<void> _handleDeleteDownload(DebridDownload download) async {
    if (_apiKey == null) return;

    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Delete Download',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Are you sure you want to delete "${download.filename}" from Real Debrid? This action cannot be undone.',
          style: const TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.grey),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Colors.red,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        // Show loading indicator
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
                  'Deleting download...',
                  style: TextStyle(color: Colors.white),
                ),
              ],
            ),
          ),
        );

        // Delete the download
        await DebridService.deleteDownload(_apiKey!, download.id);
        
        // Check if widget is still mounted before updating UI
        if (mounted) {
          // Close loading dialog
          Navigator.of(context).pop();
          
          // Remove the download from the local list
          setState(() {
            _downloads.removeWhere((d) => d.id == download.id);
          });
          
          // Show success message
          _showSuccess('Download deleted successfully!');
        }
      } catch (e) {
        // Check if widget is still mounted before updating UI
        if (mounted) {
          // Close loading dialog
          Navigator.of(context).pop();
          
          // Show error message
          _showError('Failed to delete download: ${e.toString()}');
        }
      }
    }
  }

  Future<void> _showMultipleLinksDialog(RDTorrent torrent, {bool showPlayButtons = false}) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  const Color(0xFF0F172A).withValues(alpha: 0.98),
                  const Color(0xFF1E293B).withValues(alpha: 0.98),
                ],
              ),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              border: Border.all(
                color: const Color(0xFF6366F1).withValues(alpha: 0.2),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  blurRadius: 30,
                  offset: const Offset(0, -10),
                ),
                BoxShadow(
                  color: const Color(0xFF6366F1).withValues(alpha: 0.1),
                  blurRadius: 20,
                  offset: const Offset(0, 0),
                ),
              ],
            ),
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: DebridService.unrestrictLinks(_apiKey!, torrent.links),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Container(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Drag handle
                        Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey[600],
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(height: 24),
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                            ),
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF6366F1).withValues(alpha: 0.3),
                                blurRadius: 15,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: const CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            strokeWidth: 3,
                          ),
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          'Preparing Files',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Unrestricting download links...',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[400],
                          ),
                        ),
                      ],
                    ),
                  );
                }
                if (snapshot.hasError) {
                  return Container(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Drag handle
                        Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey[600],
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(height: 24),
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFFEF4444), Color(0xFFDC2626)],
                            ),
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFEF4444).withValues(alpha: 0.3),
                                blurRadius: 15,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.error_outline_rounded,
                            color: Colors.white,
                            size: 32,
                          ),
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          'Failed to Load Files',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          snapshot.error.toString(),
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[400],
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: () => Navigator.of(context).pop(),
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF6366F1),
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            child: const Text(
                              'Close',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }

                final unrestrictedLinks = snapshot.data!;
                bool downloadingAll = false;
                int addCount = 0;
                final Set<int> added = {};
                final Set<int> selectedFiles = {}; // Track selected files
                return StatefulBuilder(
                  builder: (context, setLocal) {
                    return Container(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.of(context).size.height * 0.9,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Minimal header with just drag handle and title
                          Container(
                            padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
                            child: Column(
                              children: [
                                // Drag handle
                                Container(
                                  width: 40,
                                  height: 4,
                                  decoration: BoxDecoration(
                                    color: Colors.grey[600],
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                // Simple title
                                Text(
                                  '${torrent.filename} (${unrestrictedLinks.length} files)',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),

                          if (downloadingAll) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                              child: Column(
                                children: [
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.download_rounded,
                                        color: Color(0xFF10B981),
                                        size: 20,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Downloading files...',
                                        style: TextStyle(
                                          color: Colors.grey[300],
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const Spacer(),
                                      Text(
                                        '$addCount/${unrestrictedLinks.length}',
                                        style: TextStyle(
                                          color: Colors.grey[400],
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: LinearProgressIndicator(
                                      minHeight: 8,
                                      value: unrestrictedLinks.isEmpty ? null : (addCount / unrestrictedLinks.length).clamp(0.0, 1.0),
                                      backgroundColor: Colors.grey[800],
                                      valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF10B981)),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],

                          // File List - now with more space
                          Flexible(
                            child: ListView.separated(
                              padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                              shrinkWrap: true,
                              itemCount: unrestrictedLinks.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 12),
                              itemBuilder: (context, index) {
                                final link = unrestrictedLinks[index];
                                final fileName = (link['filename'] ?? 'Unknown file').toString();
                                final fileSize = (link['filesize'] ?? 0) as int;
                                final mimeType = (link['mimeType'] ?? '').toString();
                                final isVideo = FileUtils.isVideoMimeType(mimeType);
                                final isAdded = added.contains(index);
                                final isSelected = selectedFiles.contains(index);

                                return _buildModernFileCard(
                                  fileName: fileName,
                                  fileSize: fileSize,
                                  isVideo: isVideo,
                                  isAdded: isAdded,
                                  isSelected: isSelected,
                                  showPlayButtons: showPlayButtons,
                                  onPlay: () => _playUnrestricted(link),
                                  onDownload: () async {
                                    final url = (link['download'] ?? '').toString();
                                    if (url.isEmpty) return;
                                    setLocal(() => added.add(index));
                                    await DownloadService.instance.enqueueDownload(
                                      url: url,
                                      fileName: fileName,
                                      context: context,
                                      torrentName: torrent.filename,
                                    );
                                  },
                                  onSelect: () {
                                    setLocal(() {
                                      if (isSelected) {
                                        selectedFiles.remove(index);
                                      } else {
                                        selectedFiles.add(index);
                                      }
                                    });
                                  },
                                  index: index,
                                );
                              },
                            ),
                          ),

                          // Compact footer with Download All, Download Selected, and Close buttons
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0F172A).withValues(alpha: 0.5),
                              borderRadius: const BorderRadius.only(
                                bottomLeft: Radius.circular(28),
                                bottomRight: Radius.circular(28),
                              ),
                            ),
                            child: Column(
                              children: [
                                // Download Selected button (only show when files are selected)
                                if (selectedFiles.isNotEmpty) ...[
                                  Container(
                                    width: double.infinity,
                                    decoration: BoxDecoration(
                                      gradient: const LinearGradient(
                                        colors: [Color(0xFF8B5CF6), Color(0xFF7C3AED)],
                                      ),
                                      borderRadius: BorderRadius.circular(16),
                                      boxShadow: [
                                        BoxShadow(
                                          color: const Color(0xFF8B5CF6).withValues(alpha: 0.3),
                                          blurRadius: 12,
                                          offset: const Offset(0, 6),
                                        ),
                                      ],
                                    ),
                                    child: FilledButton.icon(
                                      onPressed: downloadingAll
                                          ? null
                                          : () async {
                                              setLocal(() {
                                                downloadingAll = true;
                                                addCount = 0;
                                              });
                                              final selectedIndices = selectedFiles.toList();
                                              for (var i = 0; i < selectedIndices.length; i++) {
                                                final index = selectedIndices[i];
                                                final link = unrestrictedLinks[index];
                                                final url = (link['download'] ?? '').toString();
                                                final fileName = (link['filename'] ?? 'file').toString();
                                                if (url.isEmpty) continue;
                                                await DownloadService.instance.enqueueDownload(
                                                  url: url,
                                                  fileName: fileName,
                                                  context: context,
                                                  torrentName: torrent.filename,
                                                );
                                                setLocal(() {
                                                  added.add(index);
                                                  addCount = i + 1;
                                                });
                                              }
                                              setLocal(() {
                                                downloadingAll = false;
                                                selectedFiles.clear(); // Clear selection after download
                                              });
                                              if (mounted) {
                                                ScaffoldMessenger.of(context).showSnackBar(
                                                  SnackBar(
                                                    content: Row(
                                                      children: [
                                                        Container(
                                                          padding: const EdgeInsets.all(8),
                                                          decoration: BoxDecoration(
                                                            color: const Color(0xFF8B5CF6),
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
                                                            'Added ${selectedIndices.length} selected downloads',
                                                            style: const TextStyle(fontWeight: FontWeight.w500),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                    backgroundColor: const Color(0xFF1E293B),
                                                    behavior: SnackBarBehavior.floating,
                                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                                    margin: const EdgeInsets.all(16),
                                                  ),
                                                );
                                              }
                                            },
                                      icon: downloadingAll
                                          ? const SizedBox(
                                              width: 16,
                                              height: 16,
                                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                            )
                                          : const Icon(Icons.download_rounded, color: Colors.white),
                                      label: Text(
                                        downloadingAll 
                                            ? 'Adding $addCount/${selectedFiles.length}…' 
                                            : 'Download Selected (${selectedFiles.length})',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      style: FilledButton.styleFrom(
                                        backgroundColor: Colors.transparent,
                                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(16),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                ],
                                // Bottom row with Download All and Close buttons
                                Row(
                                  children: [
                                    // Download All button
                                    Expanded(
                                      child: Container(
                                        decoration: BoxDecoration(
                                          gradient: const LinearGradient(
                                            colors: [Color(0xFF10B981), Color(0xFF059669)],
                                          ),
                                          borderRadius: BorderRadius.circular(16),
                                          boxShadow: [
                                            BoxShadow(
                                              color: const Color(0xFF10B981).withValues(alpha: 0.3),
                                              blurRadius: 12,
                                              offset: const Offset(0, 6),
                                            ),
                                          ],
                                        ),
                                        child: FilledButton.icon(
                                          onPressed: downloadingAll
                                              ? null
                                              : () async {
                                                  setLocal(() {
                                                    downloadingAll = true;
                                                    addCount = 0;
                                                  });
                                                  for (var i = 0; i < unrestrictedLinks.length; i++) {
                                                    final link = unrestrictedLinks[i];
                                                    final url = (link['download'] ?? '').toString();
                                                    final fileName = (link['filename'] ?? 'file').toString();
                                                    if (url.isEmpty) continue;
                                                    await DownloadService.instance.enqueueDownload(
                                                      url: url,
                                                      fileName: fileName,
                                                      context: context,
                                                      torrentName: torrent.filename,
                                                    );
                                                    setLocal(() {
                                                      added.add(i);
                                                      addCount = i + 1;
                                                    });
                                                  }
                                                  setLocal(() => downloadingAll = false);
                                                  if (mounted) {
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
                                                                'Added ${unrestrictedLinks.length} downloads',
                                                                style: const TextStyle(fontWeight: FontWeight.w500),
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                        backgroundColor: const Color(0xFF1E293B),
                                                        behavior: SnackBarBehavior.floating,
                                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                                        margin: const EdgeInsets.all(16),
                                                      ),
                                                    );
                                                  }
                                                },
                                          icon: downloadingAll
                                              ? const SizedBox(
                                                  width: 16,
                                                  height: 16,
                                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                                )
                                              : const Icon(Icons.download_rounded, color: Colors.white),
                                          label: Text(
                                            downloadingAll ? 'Adding $addCount/${unrestrictedLinks.length}…' : 'Download All',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          style: FilledButton.styleFrom(
                                            backgroundColor: Colors.transparent,
                                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(16),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    // Close button
                                    SizedBox(
                                      width: 100,
                                      child: TextButton(
                                        onPressed: () => Navigator.of(context).pop(),
                                        style: TextButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(vertical: 12),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(16),
                                          ),
                                        ),
                                        child: const Text(
                                          'Close',
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                            color: Color(0xFF6366F1),
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
                    );
                  },
                );
              },
            ),
          ),
        );
      },
    );
  }

  void _copyAllLinks(List<Map<String, dynamic>> links) {
    final downloadLinks = links
        .map((link) => link['download'])
        .where((link) => link != null)
        .join('\n');
    
    _copyToClipboard(downloadLinks);
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    _showSuccess('Download link(s) copied to clipboard!');
  }

  void _showSuccess(String message) {
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
                message,
                style: const TextStyle(fontWeight: FontWeight.w500),
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



  String _getUserFriendlyErrorMessage(dynamic error) {
    final errorString = error.toString().toLowerCase();
    
    if (errorString.contains('file is not readily available in real debrid')) {
      return 'This torrent is not available on Real Debrid servers. Try a different torrent.';
    } else if (errorString.contains('invalid api key') || errorString.contains('401')) {
      return 'Invalid API key. Please check your Real Debrid settings.';
    } else if (errorString.contains('account locked') || errorString.contains('403')) {
      return 'Your Real Debrid account is locked. Please check your account status.';
    } else if (errorString.contains('network error') || errorString.contains('connection')) {
      return 'Network connection error. Please check your internet connection.';
    } else if (errorString.contains('timeout')) {
      return 'Request timed out. Please try again.';
    } else if (errorString.contains('no files found in torrent')) {
      return 'No files found in this torrent.';
    } else if (errorString.contains('failed to get download link')) {
      return 'Unable to get download link. The torrent may not be available.';
    } else if (errorString.contains('long') || errorString.contains('int')) {
      return 'Data format error. Please refresh and try again.';
    } else if (errorString.contains('json')) {
      return 'Invalid response format. Please try again.';
    } else if (errorString.contains('failed to load torrents') || errorString.contains('failed to load downloads')) {
      return 'Unable to load downloads. Please check your connection and try again.';
    } else {
      return 'Failed to add torrent. Please try again.';
    }
  }

  void _showError(String message) {
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
                message,
                style: const TextStyle(fontWeight: FontWeight.w500),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // Tabs
          Container(
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(12),
            ),
            child: TabBar(
              controller: _tabController,
              isScrollable: false,
              dividerColor: Colors.transparent,
              indicatorSize: TabBarIndicatorSize.tab,
              indicatorPadding: const EdgeInsets.all(6),
              labelPadding: const EdgeInsets.symmetric(vertical: 10),
              overlayColor: MaterialStateProperty.all(Colors.transparent),
              indicator: BoxDecoration(
                color: const Color(0xFF6366F1),
                borderRadius: BorderRadius.circular(10),
              ),
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white70,
              tabs: const [
                Tab(text: 'Torrent Downloads'),
                Tab(text: 'Downloads'),
              ],
            ),
          ),
          
          // Content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildTorrentContent(),
                _buildDownloadContent(),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: _selectedIndex == 0 ? FloatingActionButton(
        onPressed: _showAddMagnetDialog,
        backgroundColor: const Color(0xFF6366F1),
        child: const Icon(Icons.add, color: Colors.white),
      ) : null,
    );
  }

  Widget _buildTorrentContent() {
    if (_isLoadingTorrents && _torrents.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading your torrent downloads...'),
          ],
        ),
      );
    }

    if (_torrentErrorMessage.isNotEmpty && _torrents.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                ),
                child: Column(
                  children: [
                    Icon(
                      Icons.error_outline,
                      color: Colors.red,
                      size: 48,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Error Loading Torrent Downloads',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Colors.red[700],
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _torrentErrorMessage,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.red[600],
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => _fetchTorrents(_apiKey!, reset: true),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_torrents.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.download_done,
              size: 64,
              color: Colors.grey,
            ),
            SizedBox(height: 16),
            Text(
              'No torrent downloads yet',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.grey,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Your downloaded torrents will appear here',
              style: TextStyle(
                color: Colors.grey,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        if (_apiKey != null) {
          await _fetchTorrents(_apiKey!, reset: true);
        }
      },
      color: Colors.white,
      backgroundColor: const Color(0xFF1E293B),
      strokeWidth: 3,
      child: ListView.builder(
        controller: _torrentScrollController,
        padding: const EdgeInsets.all(16),
        itemCount: _torrents.length + (_hasMoreTorrents ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == _torrents.length) {
            // Loading more indicator
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                child: CircularProgressIndicator(),
              ),
            );
          }

          final torrent = _torrents[index];
          return _buildTorrentCard(torrent);
        },
      ),
    );
  }

  Widget _buildDownloadContent() {
    if (_isLoadingDownloads && _downloads.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading your downloads...'),
          ],
        ),
      );
    }

    if (_downloadErrorMessage.isNotEmpty && _downloads.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                ),
                child: Column(
                  children: [
                    Icon(
                      Icons.error_outline,
                      color: Colors.red,
                      size: 48,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Error Loading Downloads',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Colors.red[700],
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _downloadErrorMessage,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.red[600],
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => _fetchDownloads(_apiKey!, reset: true),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_downloads.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.download_done,
              size: 64,
              color: Colors.grey,
            ),
            SizedBox(height: 16),
            Text(
              'No downloads yet',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.grey,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Your downloads will appear here',
              style: TextStyle(
                color: Colors.grey,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        if (_apiKey != null) {
          await _fetchDownloads(_apiKey!, reset: true);
        }
      },
      color: Colors.white,
      backgroundColor: const Color(0xFF1E293B),
      strokeWidth: 3,
      child: ListView.builder(
        controller: _downloadScrollController,
        padding: const EdgeInsets.all(16),
        itemCount: _downloads.length + (_hasMoreDownloads ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == _downloads.length) {
            // Loading more indicator
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                child: CircularProgressIndicator(),
              ),
            );
          }

          final download = _downloads[index];
          return _buildDownloadCard(download);
        },
      ),
    );
  }

  Widget _buildTorrentCard(RDTorrent torrent) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF475569).withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title and status
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        torrent.filename,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                          color: Colors.white,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    // Small download button (only for single-file torrents)
                    if (torrent.links.length == 1)
                      IconButton(
                        tooltip: 'Download',
                        onPressed: () async {
                          if (_apiKey == null) return;
                          try {
                            final unrestrict = await DebridService.unrestrictLink(_apiKey!, torrent.links.first);
                            final link = unrestrict['download'] as String;
                            await DownloadService.instance.enqueueDownload(
                              url: link,
                              fileName: torrent.filename,
                              context: context,
                              torrentName: torrent.filename,
                            );
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Added to downloads')),
                              );
                            }
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Failed to start download: $e')),
                              );
                            }
                          }
                        },
                        icon: const Icon(Icons.download_rounded, color: Color(0xFF10B981)),
                      ),
                  ],
                ),
                
                const SizedBox(height: 12),
                
                // Stats row
                Row(
                  children: [
                                                              StatChip(
                       icon: Icons.storage,
                       text: Formatters.formatFileSize(torrent.bytes),
                       color: const Color(0xFF6366F1),
                     ),
                     const SizedBox(width: 8),
                     StatChip(
                       icon: Icons.link,
                       text: '${torrent.links.length} file${torrent.links.length > 1 ? 's' : ''}',
                       color: const Color(0xFFF59E0B),
                     ),
                     const SizedBox(width: 8),
                     StatChip(
                       icon: Icons.download_done,
                       text: '100%',
                       color: const Color(0xFF10B981),
                     ),
                  ],
                ),
                
                const SizedBox(height: 12),
                
                // Host info
                Row(
                  children: [
                    Icon(
                      Icons.computer,
                      size: 16,
                      color: Colors.grey[400],
                    ),
                    const SizedBox(width: 4),
                    Text(
                      torrent.host,
                      style: TextStyle(
                        color: Colors.grey[400],
                        fontSize: 12,
                      ),
                    ),
                    const Spacer(),
                                         Text(
                       'Added ${Formatters.formatDateString(torrent.added)}',
                       style: TextStyle(
                         color: Colors.grey[400],
                         fontSize: 12,
                       ),
                     ),
                  ],
                ),
              ],
            ),
          ),
          
                     // Action buttons
           Container(
             decoration: BoxDecoration(
               color: const Color(0xFF0F172A),
               borderRadius: const BorderRadius.only(
                 bottomLeft: Radius.circular(12),
                 bottomRight: Radius.circular(12),
               ),
             ),
             child: Row(
               children: [
                 // File options button
                                   Expanded(
                    child: TextButton.icon(
                      onPressed: () => _handleFileOptions(torrent),
                      icon: torrent.links.length > 1
                          ? const Icon(Icons.more_horiz, size: 18)
                          : const Icon(Icons.copy, size: 18),
                      label: Text(
                        torrent.links.length > 1 
                          ? 'File Options (${torrent.links.length})'
                          : 'Copy Download Link',
                      ),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF6366F1),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                 ),
                 
                // Play button
                if (torrent.links.length == 1) ...[
                  Container(
                    decoration: BoxDecoration(
                      border: Border(
                        left: BorderSide(
                          color: const Color(0xFF475569).withValues(alpha: 0.3),
                        ),
                      ),
                    ),
                    child: TextButton.icon(
                      onPressed: () => _handlePlayVideo(torrent),
                      icon: Icon(
                        FileUtils.isProblematicVideo(torrent.filename)
                          ? Icons.warning
                          : Icons.play_arrow,
                        size: 18,
                      ),
                      label: Text(
                        FileUtils.isProblematicVideo(torrent.filename) ? 'Play*' : 'Play',
                      ),
                      style: TextButton.styleFrom(
                        foregroundColor: FileUtils.isProblematicVideo(torrent.filename)
                          ? const Color(0xFFF59E0B)
                          : const Color(0xFFE50914),
                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                      ),
                    ),
                  ),
                ] else ...[
                  Container(
                    decoration: BoxDecoration(
                      border: Border(
                        left: BorderSide(
                          color: const Color(0xFF475569).withValues(alpha: 0.3),
                        ),
                      ),
                    ),
                    child: TextButton.icon(
                      onPressed: () => _handlePlayMultiFileTorrent(torrent),
                      icon: const Icon(Icons.play_arrow, size: 18),
                      label: const Text('Play'),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFFE50914),
                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                      ),
                    ),
                  ),
                ],
                 
                 // Delete button
                 Container(
                   decoration: BoxDecoration(
                     border: Border(
                       left: BorderSide(
                         color: const Color(0xFF475569).withValues(alpha: 0.3),
                       ),
                     ),
                   ),
                   child: TextButton.icon(
                     onPressed: () => _handleDeleteTorrent(torrent),
                     icon: const Icon(Icons.delete_outline, size: 18),
                     label: const Text('Delete'),
                     style: TextButton.styleFrom(
                       foregroundColor: const Color(0xFFEF4444),
                       padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
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

  Future<void> _handleDownloadActionForTorrent(RDTorrent torrent) async {
    if (_apiKey == null) return;
    try {
      final unrestrict = await DebridService.unrestrictLink(_apiKey!, torrent.links.first);
      final link = unrestrict['download'] as String;
      await Clipboard.setData(ClipboardData(text: link));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Link copied to clipboard')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to copy: $e')),
        );
      }
    }
  }

  Widget _buildDownloadCard(DebridDownload download) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF475569).withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title and status
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        download.filename,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                          color: Colors.white,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Download',
                      onPressed: () async {
                        if (_apiKey == null) return;
                        try {
                          final unrestrict = await DebridService.unrestrictLink(_apiKey!, download.link);
                          final link = unrestrict['download'] as String;
                          await DownloadService.instance.enqueueDownload(
                            url: link,
                            fileName: download.filename,
                            context: context,
                            torrentName: download.filename,
                          );
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Added to downloads')),
                            );
                          }
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Failed to start download: $e')),
                            );
                          }
                        }
                      },
                      icon: const Icon(Icons.download_rounded, color: Color(0xFF10B981)),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: const Color(0xFF10B981).withValues(alpha: 0.5),
                        ),
                      ),
                      child: const Text(
                        'Downloaded',
                        style: TextStyle(
                          color: Color(0xFF10B981),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 12),
                
                // Stats row
                Row(
                  children: [
                    StatChip(
                      icon: Icons.storage,
                      text: Formatters.formatFileSize(download.filesize),
                      color: const Color(0xFF6366F1),
                    ),
                    const SizedBox(width: 8),
                    StatChip(
                      icon: Icons.link,
                      text: '${download.chunks} chunks',
                      color: const Color(0xFFF59E0B),
                    ),
                    const SizedBox(width: 8),
                    StatChip(
                      icon: download.streamable == 1 ? Icons.play_arrow : Icons.download,
                      text: download.streamable == 1 ? 'Streamable' : 'Download',
                      color: download.streamable == 1 ? const Color(0xFFE50914) : const Color(0xFF10B981),
                    ),
                  ],
                ),
                
                const SizedBox(height: 12),
                
                // Host info
                Row(
                  children: [
                    Icon(
                      Icons.computer,
                      size: 16,
                      color: Colors.grey[400],
                    ),
                    const SizedBox(width: 4),
                    Text(
                      download.host,
                      style: TextStyle(
                        color: Colors.grey[400],
                        fontSize: 12,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      'Generated ${Formatters.formatDateString(download.generated)}',
                      style: TextStyle(
                        color: Colors.grey[400],
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          // Action buttons
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(12),
                bottomRight: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                // Copy link button
                Expanded(
                  child: TextButton.icon(
                    onPressed: () => _handleDownloadAction(download),
                    icon: const Icon(Icons.copy, size: 18),
                    label: const Text('Copy Download Link'),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF6366F1),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                
                // Play button (if streamable)
                if (download.streamable == 1) ...[
                  Container(
                    decoration: BoxDecoration(
                      border: Border(
                        left: BorderSide(
                          color: const Color(0xFF475569).withValues(alpha: 0.3),
                        ),
                      ),
                    ),
                    child: TextButton.icon(
                      onPressed: () => _handlePlayDownload(download),
                      icon: Icon(
                        FileUtils.isProblematicVideo(download.filename)
                          ? Icons.warning
                          : Icons.play_arrow,
                        size: 18,
                      ),
                      label: Text(
                        FileUtils.isProblematicVideo(download.filename) ? 'Play*' : 'Play',
                      ),
                      style: TextButton.styleFrom(
                        foregroundColor: FileUtils.isProblematicVideo(download.filename)
                          ? const Color(0xFFF59E0B)
                          : const Color(0xFFE50914),
                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                      ),
                    ),
                  ),
                ],
                
                // Delete button
                Container(
                  decoration: BoxDecoration(
                    border: Border(
                      left: BorderSide(
                        color: const Color(0xFF475569).withValues(alpha: 0.3),
                      ),
                    ),
                  ),
                  child: TextButton.icon(
                    onPressed: () => _handleDeleteDownload(download),
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('Delete'),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFFEF4444),
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
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



  void _playUnrestricted(Map<String, dynamic> link) {
    final downloadLink = (link['download'] ?? '').toString();
    final fileName = (link['filename'] ?? 'Video').toString();
    final fileSize = (link['filesize'] ?? 0) as int;
    if (downloadLink.isEmpty) return;
    Navigator.of(context).pop();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => VideoPlayerScreen(
          videoUrl: downloadLink,
          title: fileName,
          subtitle: Formatters.formatFileSize(fileSize),
        ),
      ),
    );
  }

  Future<void> _handlePlayMultiFileTorrent(RDTorrent torrent) async {
    if (_apiKey == null) return;
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

      // Get torrent info to access file names
      final torrentInfo = await DebridService.getTorrentInfo(_apiKey!, torrent.id);
      final files = torrentInfo['files'] as List<dynamic>?;
      
      if (files == null || files.isEmpty) {
        if (mounted) Navigator.of(context).pop(); // close loading
        if (mounted) {
          _showError('Failed to get file information from torrent.');
        }
        return;
      }

      // Get selected files from the torrent info
      final selectedFiles = files.where((file) => file['selected'] == 1).toList();
      
      // If no selected files, use all files (they might all be selected by default)
      final filesToUse = selectedFiles.isNotEmpty ? selectedFiles : files;
      
      // Check if this is an archive (multiple files, single link)
      bool isArchive = false;
      if (filesToUse.length > 1 && torrent.links.length == 1) {
        isArchive = true;
      }

      if (isArchive) {
        if (mounted) Navigator.of(context).pop(); // close loading
        if (mounted) {
          _showError('This is an archived torrent. Please extract it first.');
        }
        return;
      }

      // Multiple individual files - create playlist with true lazy loading
      final List<PlaylistEntry> entries = [];
      
      // Get filenames from files with null safety - try different possible field names
      final filenames = filesToUse.map((file) {
        // Try different possible field names for filename
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
          if (i >= torrent.links.length) {
            // Skip if no corresponding link
            continue;
          }
          
          if (i == firstEpisodeIndex) {
            // First episode: try to unrestrict for immediate playback
            try {
              final unrestrictResult = await DebridService.unrestrictLink(_apiKey!, torrent.links[i]);
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
                  restrictedLink: torrent.links[i],
                  apiKey: _apiKey,
                ));
              }
            } catch (e) {
              // If unrestriction fails, add as restricted link for lazy loading
              print('Failed to unrestrict first episode: $e');
              entries.add(PlaylistEntry(
                url: '', // Empty URL - will be filled when unrestricted
                title: finalFilename,
                restrictedLink: torrent.links[i],
                apiKey: _apiKey,
              ));
            }
          } else {
            // Other episodes: keep restricted links for lazy loading
            entries.add(PlaylistEntry(
              url: '', // Empty URL - will be filled when unrestricted
              title: finalFilename,
              restrictedLink: torrent.links[i],
              apiKey: _apiKey,
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
          if (i >= torrent.links.length) {
            // Skip if no corresponding link
            continue;
          }
          
          if (i == 0) {
            // First video: try to unrestrict for immediate playback
            try {
              final unrestrictResult = await DebridService.unrestrictLink(_apiKey!, torrent.links[i]);
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
                  restrictedLink: torrent.links[i],
                  apiKey: _apiKey,
                ));
              }
            } catch (e) {
              // If unrestriction fails, add as restricted link for lazy loading
              print('Failed to unrestrict first video: $e');
              entries.add(PlaylistEntry(
                url: '', // Empty URL - will be filled when unrestricted
                title: finalFilename,
                restrictedLink: torrent.links[i],
                apiKey: _apiKey,
              ));
            }
          } else {
            // Other videos: keep restricted links for lazy loading
            entries.add(PlaylistEntry(
              url: '', // Empty URL - will be filled when unrestricted
              title: finalFilename,
              restrictedLink: torrent.links[i],
              apiKey: _apiKey,
            ));
          }
        }
      }

      if (mounted) Navigator.of(context).pop(); // close loading

      if (entries.isEmpty) {
        if (mounted) {
          _showError('No playable video files found in this torrent.');
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
            title: torrent.filename,
            subtitle: '${entries.length} files',
            playlist: entries,
            startIndex: 0,
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
        _showError('Failed to prepare playlist: $e');
      }
    }
  }

  void _showAddMagnetDialog() {
    // Auto-paste if clipboard has magnet link
    _autoPasteMagnetLink();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Magnet Link'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF334155),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFF475569).withValues(alpha: 0.3),
                ),
              ),
              child: TextField(
                controller: _magnetController,
                decoration: const InputDecoration(
                  hintText: 'Paste magnet link here...',
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.all(16),
                ),
                maxLines: 3,
                style: const TextStyle(color: Colors.white),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      side: const BorderSide(color: Color(0xFF475569)),
                    ),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _showAdvancedMagnetDialog,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      side: const BorderSide(color: Color(0xFF475569)),
                    ),
                    child: const Text('Advanced'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _isAddingMagnet ? null : _addMagnetWithDefaultSelection,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      backgroundColor: const Color(0xFF6366F1),
                    ),
                    child: _isAddingMagnet
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Add'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _autoPasteMagnetLink() async {
    final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
    if (clipboardData?.text != null) {
      final text = clipboardData!.text!.trim();
      if (text.startsWith('magnet:?')) {
        _magnetController.text = text;
      }
    }
  }

  bool _isValidMagnetLink(String link) {
    final trimmedLink = link.trim();
    if (!trimmedLink.startsWith('magnet:?')) {
      return false;
    }
    
    // Check for required magnet link components
    if (!trimmedLink.contains('xt=urn:btih:')) {
      return false;
    }
    
    // Basic length check (magnet links are typically longer than 50 characters)
    if (trimmedLink.length < 50) {
      return false;
    }
    
    return true;
  }



  Future<void> _pasteMagnetLink() async {
    final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
    if (clipboardData?.text != null) {
      final text = clipboardData!.text!.trim();
      if (_isValidMagnetLink(text)) {
        _magnetController.text = text;
      } else {
        _showError('Clipboard does not contain a valid magnet link');
      }
    } else {
      _showError('No text found in clipboard');
    }
  }

  Future<void> _addMagnetWithDefaultSelection() async {
    final magnetLink = _magnetController.text.trim();
    if (magnetLink.isEmpty) {
      _showError('Please enter a magnet link');
      return;
    }

    if (!_isValidMagnetLink(magnetLink)) {
      _showError('Please enter a valid magnet link');
      return;
    }

    Navigator.of(context).pop(); // Close the dialog

    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Adding Torrent'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            const Text('Processing magnet link...'),
            const SizedBox(height: 8),
            Text(
              'This may take a few moments',
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );

    setState(() {
      _isAddingMagnet = true;
    });

    try {
      // Get the default file selection preference
      final fileSelection = await StorageService.getFileSelection();
      
      // Add the magnet using the same logic as the torrent search screen
      final result = await DebridService.addTorrentToDebrid(
        _apiKey!,
        magnetLink,
        tempFileSelection: fileSelection,
      );

      // Close loading dialog
      if (mounted) {
        Navigator.of(context).pop();
      }

      // Clear the input
      _magnetController.clear();

      // Show success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Magnet added successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }

      // Refresh the torrent list
      await _fetchTorrents(_apiKey!, reset: true);

    } catch (e) {
      // Close loading dialog
      if (mounted) {
        Navigator.of(context).pop();
      }
      
      if (mounted) {
        _showError(_getUserFriendlyErrorMessage(e.toString()));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isAddingMagnet = false;
        });
      }
    }
  }

  Future<void> _showAdvancedMagnetDialog() async {
    final magnetLink = _magnetController.text.trim();
    if (magnetLink.isEmpty) {
      _showError('Please enter a magnet link first');
      return;
    }

    if (!_isValidMagnetLink(magnetLink)) {
      _showError('Please enter a valid magnet link');
      return;
    }

    Navigator.of(context).pop(); // Close the first dialog

    // Show file selection dialog similar to torrent search screen
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select File Type'),
        content: const Text('Choose how to handle files in this torrent:'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: _isAddingMagnet ? null : () => _addMagnetWithSelection(magnetLink, 'largest'),
            child: _isAddingMagnet
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Largest File'),
          ),
          TextButton(
            onPressed: _isAddingMagnet ? null : () => _addMagnetWithSelection(magnetLink, 'video'),
            child: _isAddingMagnet
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Video Files'),
          ),
          TextButton(
            onPressed: _isAddingMagnet ? null : () => _addMagnetWithSelection(magnetLink, 'all'),
            child: _isAddingMagnet
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('All Files'),
          ),
        ],
      ),
    );
  }

  Future<void> _addMagnetWithSelection(String magnetLink, String fileSelection) async {
    Navigator.of(context).pop(); // Close the dialog

    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Adding Torrent'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            const Text('Processing magnet link...'),
            const SizedBox(height: 8),
            Text(
              'This may take a few moments',
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );

    setState(() {
      _isAddingMagnet = true;
    });

    try {
      // Add the magnet with the selected file preference
      final result = await DebridService.addTorrentToDebrid(
        _apiKey!,
        magnetLink,
        tempFileSelection: fileSelection,
      );

      // Close loading dialog
      if (mounted) {
        Navigator.of(context).pop();
      }

      // Clear the input
      _magnetController.clear();

      // Show success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Magnet added successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }

      // Refresh the torrent list
      await _fetchTorrents(_apiKey!, reset: true);

    } catch (e) {
      // Close loading dialog
      if (mounted) {
        Navigator.of(context).pop();
      }
      
      if (mounted) {
        _showError(_getUserFriendlyErrorMessage(e.toString()));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isAddingMagnet = false;
        });
      }
    }
  }

  Widget _buildModernFileCard({
    required String fileName,
    required int fileSize,
    required bool isVideo,
    required bool isAdded,
    required bool isSelected,
    required bool showPlayButtons,
    required VoidCallback onPlay,
    required VoidCallback onDownload,
    required VoidCallback onSelect,
    required int index,
  }) {
    return TweenAnimationBuilder<double>(
      duration: Duration(milliseconds: 300 + (index * 50)),
      tween: Tween(begin: 0.0, end: 1.0),
      builder: (context, value, child) {
        return Transform.translate(
          offset: Offset(0, 20 * (1 - value)),
          child: Opacity(
            opacity: value,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    const Color(0xFF1E293B).withValues(alpha: 0.8),
                    const Color(0xFF334155).withValues(alpha: 0.4),
                  ],
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isSelected 
                      ? const Color(0xFF8B5CF6).withValues(alpha: 0.5)
                      : const Color(0xFF475569).withValues(alpha: 0.3),
                  width: isSelected ? 2 : 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: isSelected 
                        ? const Color(0xFF8B5CF6).withValues(alpha: 0.2)
                        : Colors.black.withValues(alpha: 0.2),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onSelect, // Make entire card selectable
                  borderRadius: BorderRadius.circular(20),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Top section with icon, file info, and selection checkbox
                        Row(
                          children: [
                            // Enhanced file icon
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: isVideo 
                                      ? [const Color(0xFFE50914), const Color(0xFFDC2626)]
                                      : [const Color(0xFFF59E0B), const Color(0xFFD97706)],
                                ),
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: (isVideo ? const Color(0xFFE50914) : const Color(0xFFF59E0B)).withValues(alpha: 0.3),
                                    blurRadius: 12,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                              ),
                              child: Icon(
                                isVideo ? Icons.play_arrow_rounded : Icons.insert_drive_file_rounded,
                                color: Colors.white,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 16),
                            
                            // File details
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    fileName,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
                                      height: 1.3,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF475569).withValues(alpha: 0.3),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: const Color(0xFF64748B).withValues(alpha: 0.3),
                                        width: 1,
                                      ),
                                    ),
                                    child: Text(
                                      Formatters.formatFileSize(fileSize),
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                        color: Colors.grey[300],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            
                            // Selection checkbox
                            Container(
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isSelected 
                                    ? const Color(0xFF8B5CF6)
                                    : Colors.transparent,
                                border: Border.all(
                                  color: isSelected 
                                      ? const Color(0xFF8B5CF6)
                                      : Colors.grey[600]!,
                                  width: 2,
                                ),
                                boxShadow: isSelected ? [
                                  BoxShadow(
                                    color: const Color(0xFF8B5CF6).withValues(alpha: 0.3),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ] : null,
                              ),
                              child: isSelected
                                  ? const Icon(
                                      Icons.check,
                                      color: Colors.white,
                                      size: 16,
                                    )
                                  : null,
                            ),
                          ],
                        ),
                        
                        const SizedBox(height: 16),
                        
                        // Bottom section with action buttons
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            if (showPlayButtons && isVideo) ...[
                              Container(
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFF6366F1).withValues(alpha: 0.3),
                                      blurRadius: 8,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: FilledButton.icon(
                                  onPressed: onPlay,
                                  icon: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 18),
                                  label: const Text(
                                    'Play',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                    ),
                                  ),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: Colors.transparent,
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                            ],
                            Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: isAdded 
                                      ? [const Color(0xFF10B981), const Color(0xFF059669)]
                                      : [const Color(0xFF1E293B), const Color(0xFF334155)],
                                ),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isAdded 
                                      ? const Color(0xFF10B981).withValues(alpha: 0.5)
                                      : const Color(0xFF475569).withValues(alpha: 0.5),
                                  width: 1,
                                ),
                                boxShadow: isAdded ? [
                                  BoxShadow(
                                    color: const Color(0xFF10B981).withValues(alpha: 0.3),
                                    blurRadius: 8,
                                    offset: const Offset(0, 4),
                                  ),
                                ] : null,
                              ),
                              child: FilledButton.icon(
                                onPressed: isAdded ? null : onDownload,
                                icon: Icon(
                                  isAdded ? Icons.check_circle_rounded : Icons.download_rounded,
                                  color: isAdded ? Colors.white : Colors.grey[300],
                                  size: 18,
                                ),
                                label: Text(
                                  isAdded ? 'Added' : 'Download',
                                  style: TextStyle(
                                    color: isAdded ? Colors.white : Colors.grey[300],
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                                style: FilledButton.styleFrom(
                                  backgroundColor: Colors.transparent,
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
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
            ),
          ),
        );
      },
    );
  }

} 