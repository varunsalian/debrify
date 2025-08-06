import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/rd_torrent.dart';
import '../models/debrid_download.dart';
import '../services/debrid_service.dart';
import '../services/storage_service.dart';
import '../utils/formatters.dart';
import '../utils/file_utils.dart';
import '../widgets/stat_chip.dart';
import 'video_player_screen.dart';

class DebridDownloadsScreen extends StatefulWidget {
  const DebridDownloadsScreen({super.key});

  @override
  State<DebridDownloadsScreen> createState() => _DebridDownloadsScreenState();
}

class _DebridDownloadsScreenState extends State<DebridDownloadsScreen> with TickerProviderStateMixin {
  late TabController _tabController;
  
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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadApiKeyAndData();
    _torrentScrollController.addListener(_onTorrentScroll);
    _downloadScrollController.addListener(_onDownloadScroll);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _torrentScrollController.dispose();
    _downloadScrollController.dispose();
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
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return FutureBuilder<List<Map<String, dynamic>>>(
          future: DebridService.unrestrictLinks(_apiKey!, torrent.links),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return AlertDialog(
                title: const Text('Processing Files'),
                content: const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Unrestricting download links...'),
                  ],
                ),
              );
            }

            if (snapshot.hasError) {
              return AlertDialog(
                title: const Text('Error'),
                content: Text('Failed to unrestrict links: ${snapshot.error}'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('OK'),
                  ),
                ],
              );
            }

            final unrestrictedLinks = snapshot.data!;
            
                                     return Dialog(
               backgroundColor: const Color(0xFF1E293B),
               shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
               child: Container(
                 width: MediaQuery.of(context).size.width * 0.9,
                 constraints: BoxConstraints(
                   maxHeight: MediaQuery.of(context).size.height * 0.8,
                   maxWidth: MediaQuery.of(context).size.width * 0.9,
                 ),
                 padding: const EdgeInsets.all(20),
                 child: Column(
                   mainAxisSize: MainAxisSize.min,
                   crossAxisAlignment: CrossAxisAlignment.start,
                   children: [
                     // Header
                     Row(
                       children: [
                         Container(
                           padding: const EdgeInsets.all(8),
                           decoration: BoxDecoration(
                             color: const Color(0xFF6366F1).withValues(alpha: 0.2),
                             borderRadius: BorderRadius.circular(8),
                           ),
                           child: Icon(
                             showPlayButtons ? Icons.play_circle : Icons.download,
                             color: const Color(0xFF6366F1),
                             size: 20,
                           ),
                         ),
                         const SizedBox(width: 12),
                         Expanded(
                           child: Column(
                             crossAxisAlignment: CrossAxisAlignment.start,
                             children: [
                               Text(
                                 showPlayButtons ? 'File Options' : 'Download Files',
                                 style: TextStyle(
                                   fontSize: 18,
                                   fontWeight: FontWeight.bold,
                                   color: Colors.white,
                                 ),
                               ),
                               Text(
                                 torrent.filename,
                                 style: TextStyle(
                                   fontSize: 14,
                                   color: Colors.grey[400],
                                 ),
                                 maxLines: 1,
                                 overflow: TextOverflow.ellipsis,
                               ),
                             ],
                           ),
                         ),
                       ],
                     ),
                    
                    const SizedBox(height: 20),
                    
                    // File count and copy all button
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0xFF475569).withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                Icon(
                                  Icons.file_copy,
                                  size: 16,
                                  color: Colors.grey[400],
                                ),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    '${unrestrictedLinks.length} files available',
                                    style: TextStyle(
                                      color: Colors.grey[300],
                                      fontWeight: FontWeight.w500,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                                                     ElevatedButton.icon(
                             onPressed: () => _copyAllLinks(unrestrictedLinks),
                             icon: const Icon(Icons.copy_all, size: 16),
                             label: Text(showPlayButtons ? 'Copy All Links' : 'Copy All'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF6366F1),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    const SizedBox(height: 16),
                    
                    // Files list
                    Flexible(
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: const Color(0xFF475569).withValues(alpha: 0.3),
                          ),
                        ),
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: unrestrictedLinks.length,
                          separatorBuilder: (context, index) => Divider(
                            height: 1,
                            color: const Color(0xFF475569).withValues(alpha: 0.3),
                            indent: 16,
                            endIndent: 16,
                          ),
                          itemBuilder: (context, index) {
                            final link = unrestrictedLinks[index];
                            final fileName = link['filename'] ?? 'Unknown file';
                            final fileSize = link['filesize'] ?? 0;
                            final mimeType = link['mimeType']?.toString() ?? '';
                            final isVideo = FileUtils.isVideoMimeType(mimeType);
                            
                            return Container(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Top row: File icon, name, and size
                                  Row(
                                    children: [
                                      // File icon
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: isVideo 
                                            ? const Color(0xFFE50914).withValues(alpha: 0.2)
                                            : const Color(0xFFF59E0B).withValues(alpha: 0.2),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Icon(
                                          isVideo ? Icons.play_arrow : Icons.insert_drive_file,
                                          color: isVideo ? const Color(0xFFE50914) : const Color(0xFFF59E0B),
                                          size: 20,
                                        ),
                                      ),
                                      
                                      const SizedBox(width: 12),
                                      
                                      // File info
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              fileName,
                                              style: const TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w500,
                                                color: Colors.white,
                                              ),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              Formatters.formatFileSize(fileSize),
                                              style: TextStyle(
                                                color: Colors.grey[400],
                                                fontSize: 12,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  
                                  // Bottom row: Action buttons (show for all files when showPlayButtons is true)
                                  if (showPlayButtons) ...[
                                    const SizedBox(height: 12),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        // Play button
                                        Container(
                                          decoration: BoxDecoration(
                                            color: isVideo
                                              ? const Color(0xFFE50914).withValues(alpha: 0.2)
                                              : const Color(0xFF6366F1).withValues(alpha: 0.2),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: IconButton(
                                            icon: Icon(
                                              isVideo ? Icons.play_arrow : Icons.play_circle_outline,
                                              color: isVideo
                                                ? const Color(0xFFE50914)
                                                : const Color(0xFF6366F1),
                                              size: 20,
                                            ),
                                            onPressed: () {
                                              final downloadLink = link['download'];
                                              if (downloadLink != null) {
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
                                            },
                                            tooltip: FileUtils.isProblematicVideo(fileName)
                                              ? 'Play video (may not work well)'
                                              : 'Play video',
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        // Copy button
                                        Container(
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF10B981).withValues(alpha: 0.2),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: IconButton(
                                            icon: const Icon(
                                              Icons.copy,
                                              color: Color(0xFF10B981),
                                              size: 20,
                                            ),
                                            onPressed: () {
                                              final downloadLink = link['download'];
                                              if (downloadLink != null) {
                                                _copyToClipboard(downloadLink);
                                                Navigator.of(context).pop();
                                              }
                                            },
                                            tooltip: 'Copy download link',
                                          ),
                                        ),
                                      ],
                                    ),
                                  ] else if (!isVideo || !showPlayButtons) ...[
                                    // For non-video files or when not showing play buttons, show copy button inline
                                    const SizedBox(height: 12),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        Container(
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF10B981).withValues(alpha: 0.2),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: IconButton(
                                            icon: const Icon(
                                              Icons.copy,
                                              color: Color(0xFF10B981),
                                              size: 20,
                                            ),
                                            onPressed: () {
                                              final downloadLink = link['download'];
                                              if (downloadLink != null) {
                                                _copyToClipboard(downloadLink);
                                                Navigator.of(context).pop();
                                              }
                                            },
                                            tooltip: 'Copy download link',
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: 20),
                    
                    // Close button
                    SizedBox(
                      width: double.infinity,
                      child: TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.grey[400],
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text('Close'),
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
    
    if (errorString.contains('invalid api key') || errorString.contains('401')) {
      return 'Invalid API key. Please check your Real Debrid settings.';
    } else if (errorString.contains('network error') || errorString.contains('connection')) {
      return 'Network connection error. Please check your internet connection.';
    } else if (errorString.contains('timeout')) {
      return 'Request timed out. Please try again.';
    } else if (errorString.contains('long') || errorString.contains('int')) {
      return 'Data format error. Please refresh and try again.';
    } else if (errorString.contains('json')) {
      return 'Invalid response format. Please try again.';
    } else if (errorString.contains('failed to load torrents') || errorString.contains('failed to load downloads')) {
      return 'Unable to load downloads. Please check your connection and try again.';
    } else {
      return 'Something went wrong. Please try again.';
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
          // Header
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(16),
                bottomRight: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.download,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'RD Downloads',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Your downloads from Real Debrid',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onPrimaryContainer.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          // Tabs
          Container(
            color: Theme.of(context).colorScheme.primaryContainer,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TabBar(
              controller: _tabController,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.grey[400],
              indicatorColor: Colors.white,
              indicatorWeight: 3,
              labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.normal, fontSize: 14),
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
                     icon: const Icon(Icons.more_horiz, size: 18),
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
                 
                 // Play button (for all single files - MIME type checked after unrestricting)
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
} 