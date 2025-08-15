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
import '../services/download_service.dart';

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
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0B1220),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return FutureBuilder<List<Map<String, dynamic>>>(
          future: DebridService.unrestrictLinks(_apiKey!, torrent.links),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    SizedBox(height: 8),
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Unrestricting download links...'),
                    SizedBox(height: 8),
                  ],
                ),
              );
            }
            if (snapshot.hasError) {
              return Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Failed to unrestrict links'),
                    const SizedBox(height: 12),
                    Text(snapshot.error.toString(),
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.7))),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Close'),
                    ),
                  ],
                ),
              );
            }

            final unrestrictedLinks = snapshot.data!;
            bool downloadingAll = false;
            int addCount = 0;
            final Set<int> added = {};
            return StatefulBuilder(
              builder: (context, setLocal) {
                final kb = MediaQuery.of(context).viewInsets.bottom;
                return Padding(
                  padding: EdgeInsets.only(bottom: kb),
                  child: SafeArea(
                    top: false,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Header
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  showPlayButtons ? Icons.play_circle_fill : Icons.file_download,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'File Options',
                                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${torrent.filename} • ${unrestrictedLinks.length} files',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              FilledButton.icon(
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
                                            SnackBar(content: Text('Added ${unrestrictedLinks.length} downloads')),
                                          );
                                        }
                                      },
                                icon: downloadingAll
                                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                    : const Icon(Icons.download_rounded),
                                label: Text(downloadingAll ? 'Adding $addCount/${unrestrictedLinks.length}…' : 'Download All'),
                              ),
                            ],
                          ),
                        ),

                        if (downloadingAll) ...[
                          const SizedBox(height: 8),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: LinearProgressIndicator(
                                minHeight: 6,
                                value: unrestrictedLinks.isEmpty ? null : (addCount / unrestrictedLinks.length).clamp(0.0, 1.0),
                              ),
                            ),
                          ),
                        ],

                        const SizedBox(height: 12),

                        // File list
                        Flexible(
                          child: ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                            shrinkWrap: true,
                            itemCount: unrestrictedLinks.length,
                            separatorBuilder: (_, __) => Divider(
                              height: 1,
                              color: const Color(0xFF223047),
                            ),
                            itemBuilder: (context, index) {
                              final link = unrestrictedLinks[index];
                              final fileName = (link['filename'] ?? 'Unknown file').toString();
                              final fileSize = (link['filesize'] ?? 0) as int;
                              final mimeType = (link['mimeType'] ?? '').toString();
                              final isVideo = FileUtils.isVideoMimeType(mimeType);
                              final isAdded = added.contains(index);

                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: (isVideo ? const Color(0xFFE50914) : const Color(0xFFF59E0B)).withValues(alpha: 0.18),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Icon(isVideo ? Icons.play_arrow : Icons.insert_drive_file,
                                          color: isVideo ? const Color(0xFFE50914) : const Color(0xFFF59E0B)),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            fileName,
                                            maxLines: 3,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            Formatters.formatFileSize(fileSize),
                                            style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.7)),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    if (showPlayButtons && isVideo) ...[
                                      OutlinedButton.icon(
                                        onPressed: () => _playUnrestricted(link),
                                        icon: const Icon(Icons.play_arrow),
                                        label: const Text('Play'),
                                      ),
                                      const SizedBox(width: 8),
                                    ],
                                    FilledButton.tonalIcon(
                                      onPressed: isAdded
                                          ? null
                                          : () async {
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
                                      icon: Icon(isAdded ? Icons.check_circle : Icons.download_rounded),
                                      label: Text(isAdded ? 'Added' : 'Download'),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),

                        // Footer
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                          child: SizedBox(
                            width: double.infinity,
                            child: TextButton(
                              onPressed: () => Navigator.of(context).pop(),
                              child: const Text('Close'),
                            ),
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

      final List<PlaylistEntry> entries = [];
      for (final l in torrent.links) {
        try {
          final res = await DebridService.unrestrictLink(_apiKey!, l);
          final url = (res['download'] ?? '').toString();
          final fname = (res['filename'] ?? '').toString();
          final mime = (res['mimeType'] ?? '').toString();
          if (url.isEmpty) continue;
          // Filter to videos only
          if (FileUtils.isVideoMimeType(mime) || FileUtils.isVideoFile(fname)) {
            entries.add(PlaylistEntry(url: url, title: fname.isNotEmpty ? fname : torrent.filename));
          }
        } catch (_) {
          // Skip problematic item
          continue;
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
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => VideoPlayerScreen(
            videoUrl: entries.first.url,
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
} 