import 'package:flutter/material.dart';
import 'dart:convert';
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
  const DebridDownloadsScreen({super.key, this.initialTorrentForOptions});

  final RDTorrent? initialTorrentForOptions;

  @override
  State<DebridDownloadsScreen> createState() => _DebridDownloadsScreenState();
}

class _ActionSheetOption {
  const _ActionSheetOption({
    required this.icon,
    required this.label,
    this.onTap,
    this.destructive = false,
    this.enabled = true,
  });

  final IconData icon;
  final String label;
  final Future<void> Function()? onTap;
  final bool destructive;
  final bool enabled;
}

enum _DebridDownloadsView { torrents, ddl }

class _DebridDownloadsScreenState extends State<DebridDownloadsScreen> {
  _DebridDownloadsView _selectedView = _DebridDownloadsView.torrents;

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

  // File browser navigation state
  int? _currentSeason;

  // Magnet input
  final TextEditingController _magnetController = TextEditingController();
  bool _isAddingMagnet = false;

  // Link input
  final TextEditingController _linkController = TextEditingController();
  bool _isAddingLink = false;

  @override
  void initState() {
    super.initState();
    _loadApiKeyAndData();
    _torrentScrollController.addListener(_onTorrentScroll);
    _downloadScrollController.addListener(_onDownloadScroll);

    // If asked to show options for a specific torrent, open after init
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (widget.initialTorrentForOptions != null) {
        // Wait until API key is loaded
        int attempts = 0;
        while (_apiKey == null && attempts < 20) {
          await Future.delayed(const Duration(milliseconds: 150));
          attempts++;
        }
        if (mounted && _apiKey != null) {
          _showMultipleLinksDialog(
            widget.initialTorrentForOptions!,
            showPlayButtons: false,
          );
        }
      }
    });
  }

  void _showDownloadMoreOptions(DebridDownload download) {
    final canStream = download.streamable == 1;
    final options = <_ActionSheetOption>[
      if (canStream)
        _ActionSheetOption(
          icon: Icons.play_arrow,
          label: 'Play',
          onTap: () => _handlePlayDownload(download),
        ),
      _ActionSheetOption(
        icon: Icons.copy,
        label: 'Copy Link',
        onTap: () async {
          await _handleDownloadAction(download);
        },
      ),
      _ActionSheetOption(
        icon: Icons.delete_outline,
        label: 'Delete Download',
        destructive: true,
        onTap: () => _handleDeleteDownload(download),
      ),
    ];

    _showOptionsSheet(options);
  }

  @override
  void dispose() {
    _torrentScrollController.dispose();
    _downloadScrollController.dispose();
    _magnetController.dispose();
    _linkController.dispose();
    super.dispose();
  }

  void _onTorrentScroll() {
    if (_torrentScrollController.position.pixels >=
        _torrentScrollController.position.maxScrollExtent - 200) {
      if (!_isLoadingMoreTorrents && _hasMoreTorrents) {
        _loadMoreTorrents();
      }
    }
  }

  void _onDownloadScroll() {
    if (_downloadScrollController.position.pixels >=
        _downloadScrollController.position.maxScrollExtent - 200) {
      if (!_isLoadingMoreDownloads && _hasMoreDownloads) {
        _loadMoreDownloads();
      }
    }
  }

  Future<void> _loadApiKeyAndData() async {
    final apiKey = await StorageService.getApiKey();

    if (mounted) {
      setState(() {
        _apiKey = apiKey;
      });
    }

    if (apiKey != null) {
      await _fetchTorrents(apiKey, reset: true);
      await _fetchDownloads(apiKey, reset: true);
    } else {
      if (mounted) {
        setState(() {
          _torrentErrorMessage =
              'No API key configured. Please add your Real Debrid API key in Settings.';
          _downloadErrorMessage =
              'No API key configured. Please add your Real Debrid API key in Settings.';
        });
      }
    }
  }

  Future<void> _fetchTorrents(String apiKey, {bool reset = false}) async {
    if (reset) {
      if (mounted) {
        setState(() {
          _torrentPage = 1;
          _hasMoreTorrents = true;
          _torrents.clear();
        });
      }
    }

    if (mounted) {
      setState(() {
        _isLoadingTorrents = true;
        _torrentErrorMessage = '';
      });
    }

    try {
      final result = await DebridService.getTorrents(
        apiKey,
        page: _torrentPage,
        limit: _limit,
        // filter: 'downloaded', // Temporarily removed to test
      );

      final List<RDTorrent> newTorrents = result['torrents'];
      final bool hasMore = result['hasMore'];

      if (mounted) {
        setState(() {
          if (reset) {
            _torrents.clear();
          }
          // Filter to show only downloaded torrents
          final downloadedTorrents = newTorrents
              .where((torrent) => torrent.isDownloaded)
              .toList();
          _torrents.addAll(downloadedTorrents);
          _hasMoreTorrents = hasMore;
          _torrentPage++;
          _isLoadingTorrents = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _torrentErrorMessage = _getUserFriendlyErrorMessage(e);
          _isLoadingTorrents = false;
        });
      }
    }
  }

  Future<void> _loadMoreTorrents() async {
    if (_apiKey == null || _isLoadingMoreTorrents || !_hasMoreTorrents) return;

    if (mounted) {
      setState(() {
        _isLoadingMoreTorrents = true;
      });
    }

    try {
      final result = await DebridService.getTorrents(
        _apiKey!,
        page: _torrentPage,
        limit: _limit,
        // filter: 'downloaded', // Temporarily removed to test
      );

      final List<RDTorrent> newTorrents = result['torrents'];
      final bool hasMore = result['hasMore'];

      if (mounted) {
        setState(() {
          // Filter to show only downloaded torrents
          final downloadedTorrents = newTorrents
              .where((torrent) => torrent.isDownloaded)
              .toList();
          _torrents.addAll(downloadedTorrents);
          _hasMoreTorrents = hasMore;
          _torrentPage++;
          _isLoadingMoreTorrents = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _torrentErrorMessage = _getUserFriendlyErrorMessage(e);
          _isLoadingMoreTorrents = false;
        });
      }
    }
  }

  // Downloads methods
  Future<void> _fetchDownloads(String apiKey, {bool reset = false}) async {
    if (reset) {
      if (mounted) {
        setState(() {
          _downloadPage = 1;
          _hasMoreDownloads = true;
          _downloads.clear();
        });
      }
    }

    if (mounted) {
      setState(() {
        _isLoadingDownloads = true;
        _downloadErrorMessage = '';
      });
    }

    try {
      final result = await DebridService.getDownloads(
        apiKey,
        page: _downloadPage,
        limit: _limit,
      );

      final List<DebridDownload> newDownloads = result['downloads'];
      final bool hasMore = result['hasMore'];

      if (mounted) {
        setState(() {
          if (reset) {
            _downloads.clear();
          }
          _downloads.addAll(newDownloads);
          _hasMoreDownloads = hasMore;
          _downloadPage++;
          _isLoadingDownloads = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _downloadErrorMessage = _getUserFriendlyErrorMessage(e);
          _isLoadingDownloads = false;
        });
      }
    }
  }

  Future<void> _loadMoreDownloads() async {
    if (_apiKey == null || _isLoadingMoreDownloads || !_hasMoreDownloads)
      return;

    if (mounted) {
      setState(() {
        _isLoadingMoreDownloads = true;
      });
    }

    try {
      final result = await DebridService.getDownloads(
        _apiKey!,
        page: _downloadPage,
        limit: _limit,
      );

      final List<DebridDownload> newDownloads = result['downloads'];
      final bool hasMore = result['hasMore'];

      if (mounted) {
        setState(() {
          _downloads.addAll(newDownloads);
          _hasMoreDownloads = hasMore;
          _downloadPage++;
          _isLoadingMoreDownloads = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _downloadErrorMessage = _getUserFriendlyErrorMessage(e);
          _isLoadingMoreDownloads = false;
        });
      }
    }
  }

  Future<void> _handleFileOptions(RDTorrent torrent) async {
    if (_apiKey == null) return;

    if (torrent.links.length == 1) {
      // Single link - unrestrict and copy directly
      try {
        final unrestrictResult = await DebridService.unrestrictLink(
          _apiKey!,
          torrent.links[0],
        );
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
        _showMultipleLinksDialog(torrent, showPlayButtons: false);
      }
    }
  }

  Future<void> _handlePlayVideo(RDTorrent torrent) async {
    if (_apiKey == null) return;

    if (torrent.links.length == 1) {
      // Single file - check MIME type after unrestricting
      try {
        final unrestrictResult = await DebridService.unrestrictLink(
          _apiKey!,
          torrent.links[0],
        );
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
        _showMultipleLinksDialog(torrent, showPlayButtons: false);
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
        _showError(
          'This file is not a video (MIME type: ${download.mimeType})',
        );
      }
    }
  }

  Future<void> _handleQueueDownload(DebridDownload download) async {
    if (_apiKey == null) return;

    try {
      final meta = jsonEncode({
        'restrictedLink': download.link,
        'apiKey': _apiKey ?? '',
        'torrentHash': '',
        'fileIndex': '',
      });
      await DownloadService.instance.enqueueDownload(
        url: download.link,
        fileName: download.filename,
        context: context,
        torrentName: download.filename,
        meta: meta,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Added to downloads')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to start download: $e'),
        ),
      );
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
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
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

  Future<void> _handleDeleteAllTorrents() async {
    if (_apiKey == null || _torrents.isEmpty) return;

    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Delete All Torrents',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Are you sure you want to delete all ${_torrents.length} torrents from Real Debrid? This action cannot be undone.',
          style: const TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete All'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await _showDeleteAllProgressDialog();
    }
  }

  Future<void> _showDeleteAllProgressDialog() async {
    bool isCancelled = false;
    int completed = 0;
    int total = _torrents.length;
    List<String> failedDeletes = [];
    StateSetter? setDialogState;

    // Show progress dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, dialogStateSetter) {
          setDialogState = dialogStateSetter;
          return AlertDialog(
            backgroundColor: const Color(0xFF1E293B),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Text(
              'Deleting All Torrents',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Deleting torrents... ($completed/$total)',
                  style: const TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 16),
                LinearProgressIndicator(
                  value: total > 0 ? completed / total : 0,
                  backgroundColor: Colors.grey.withValues(alpha: 0.3),
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    Color(0xFFEF4444),
                  ),
                ),
                const SizedBox(height: 16),
                if (failedDeletes.isNotEmpty)
                  Text(
                    'Failed: ${failedDeletes.length}',
                    style: const TextStyle(color: Colors.red, fontSize: 12),
                  ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  isCancelled = true;
                  Navigator.of(context).pop();
                },
                child: const Text(
                  'Cancel',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            ],
          );
        },
      ),
    );

    // Perform batch delete
    try {
      for (int i = 0; i < _torrents.length && !isCancelled; i++) {
        final torrent = _torrents[i];

        try {
          await DebridService.deleteTorrent(_apiKey!, torrent.id);
          completed++;

          // Update dialog state only if not cancelled
          if (!isCancelled && setDialogState != null) {
            setDialogState!(() {});
          }

          // Small delay to prevent overwhelming the API
          await Future.delayed(const Duration(milliseconds: 200));
        } catch (e) {
          failedDeletes.add(torrent.filename);
          completed++;

          // Update dialog state only if not cancelled
          if (!isCancelled && setDialogState != null) {
            setDialogState!(() {});
          }
        }
      }

      // Close progress dialog only if not already cancelled
      if (mounted && !isCancelled) {
        Navigator.of(context).pop();
      }

      if (!isCancelled) {
        // Update the torrents list
        if (mounted) {
          setState(() {
            _torrents.clear();
          });
        }

        // Refresh the list to load more items from next pages
        if (mounted) {
          await _fetchTorrents(_apiKey!, reset: true);
        }

        // Show result message
        if (failedDeletes.isEmpty) {
          _showSuccess('All torrents deleted successfully!');
        } else {
          _showError(
            'Deleted ${completed - failedDeletes.length} torrents. ${failedDeletes.length} failed to delete.',
          );
        }
      } else {
        // Operation was cancelled, refresh the list to show current state
        if (mounted) {
          await _fetchTorrents(_apiKey!, reset: true);
        }
      }
    } catch (e) {
      // Close progress dialog
      if (mounted) {
        Navigator.of(context).pop();
        _showError('Failed to delete torrents: ${e.toString()}');
      }
    }
  }

  Future<void> _handleDeleteAllDownloads() async {
    if (_apiKey == null || _downloads.isEmpty) return;

    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Delete All Downloads',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Are you sure you want to delete all ${_downloads.length} downloads from Real Debrid? This action cannot be undone.',
          style: const TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete All'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await _showDeleteAllDownloadsProgressDialog();
    }
  }

  Future<void> _showDeleteAllDownloadsProgressDialog() async {
    bool isCancelled = false;
    int completed = 0;
    int total = _downloads.length;
    List<String> failedDeletes = [];
    StateSetter? setDialogState;

    // Show progress dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, dialogStateSetter) {
          setDialogState = dialogStateSetter;
          return AlertDialog(
            backgroundColor: const Color(0xFF1E293B),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Text(
              'Deleting All Downloads',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Deleting downloads... ($completed/$total)',
                  style: const TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 16),
                LinearProgressIndicator(
                  value: total > 0 ? completed / total : 0,
                  backgroundColor: Colors.grey.withValues(alpha: 0.3),
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    Color(0xFFEF4444),
                  ),
                ),
                const SizedBox(height: 16),
                if (failedDeletes.isNotEmpty)
                  Text(
                    'Failed: ${failedDeletes.length}',
                    style: const TextStyle(color: Colors.red, fontSize: 12),
                  ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  isCancelled = true;
                  Navigator.of(context).pop();
                },
                child: const Text(
                  'Cancel',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            ],
          );
        },
      ),
    );

    // Perform batch delete
    try {
      for (int i = 0; i < _downloads.length && !isCancelled; i++) {
        final download = _downloads[i];

        try {
          await DebridService.deleteDownload(_apiKey!, download.id);
          completed++;

          // Update dialog state only if not cancelled
          if (!isCancelled && setDialogState != null) {
            setDialogState!(() {});
          }

          // Small delay to prevent overwhelming the API
          await Future.delayed(const Duration(milliseconds: 200));
        } catch (e) {
          failedDeletes.add(download.filename);
          completed++;

          // Update dialog state only if not cancelled
          if (!isCancelled && setDialogState != null) {
            setDialogState!(() {});
          }
        }
      }

      // Close progress dialog only if not already cancelled
      if (mounted && !isCancelled) {
        Navigator.of(context).pop();
      }

      if (!isCancelled) {
        // Update the downloads list
        if (mounted) {
          setState(() {
            _downloads.clear();
          });
        }

        // Refresh the list to load more items from next pages
        if (mounted) {
          await _fetchDownloads(_apiKey!, reset: true);
        }

        // Show result message
        if (failedDeletes.isEmpty) {
          _showSuccess('All downloads deleted successfully!');
        } else {
          _showError(
            'Deleted ${completed - failedDeletes.length} downloads. ${failedDeletes.length} failed to delete.',
          );
        }
      } else {
        // Operation was cancelled, refresh the list to show current state
        if (mounted) {
          await _fetchDownloads(_apiKey!, reset: true);
        }
      }
    } catch (e) {
      // Close progress dialog
      if (mounted) {
        Navigator.of(context).pop();
        _showError('Failed to delete downloads: ${e.toString()}');
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
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
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

  Future<void> _showMultipleLinksDialog(
    RDTorrent torrent, {
    bool showPlayButtons = false,
  }) async {
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
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(28),
              ),
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
            child: FutureBuilder<Map<String, dynamic>>(
              future: DebridService.getTorrentInfo(_apiKey!, torrent.id),
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
                                color: const Color(
                                  0xFF6366F1,
                                ).withValues(alpha: 0.3),
                                blurRadius: 15,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: const CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                            strokeWidth: 3,
                          ),
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          'Loading Files',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Getting file information...',
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
                                color: const Color(
                                  0xFFEF4444,
                                ).withValues(alpha: 0.3),
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
                          'Failed to Load File Info',
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

                final torrentInfo = snapshot.data!;
                final allFiles = torrentInfo['files'] as List<dynamic>? ?? [];

                // Get selected files from the torrent info
                final selectedFilesFromTorrent = allFiles
                    .where((file) => file['selected'] == 1)
                    .toList();

                // Only show files that are selected (selected: 1)
                final files = selectedFilesFromTorrent;

                // Detect if this is a series and group files by season
                final filenames = files.map((file) {
                  String fileName = file['path']?.toString() ?? 'Unknown file';
                  if (fileName.startsWith('/')) {
                    fileName = fileName.split('/').last;
                  }
                  return fileName;
                }).toList();

                final isSeries = SeriesParser.isSeriesPlaylist(filenames);
                final seriesInfos = SeriesParser.parsePlaylist(filenames);

                // If no files are selected, show empty state
                if (files.isEmpty) {
                  return Container(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(context).size.height * 0.9,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Header
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
                              // Title
                              Text(
                                '${torrent.filename} (0 files)',
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

                        // Empty state message
                        Expanded(
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(20),
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [
                                        Color(0xFFF59E0B),
                                        Color(0xFFD97706),
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(20),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(
                                          0xFFF59E0B,
                                        ).withValues(alpha: 0.3),
                                        blurRadius: 15,
                                        offset: const Offset(0, 8),
                                      ),
                                    ],
                                  ),
                                  child: const Icon(
                                    Icons.folder_off_rounded,
                                    color: Colors.white,
                                    size: 32,
                                  ),
                                ),
                                const SizedBox(height: 20),
                                const Text(
                                  'No Files Available',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'No files are currently selected for download.\nPlease select files in Real Debrid first.',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey[400],
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        ),

                        // Close button
                        Container(
                          padding: const EdgeInsets.all(20),
                          child: SizedBox(
                            width: double.infinity,
                            child: TextButton(
                              onPressed: () => Navigator.of(context).pop(),
                              style: TextButton.styleFrom(
                                backgroundColor: const Color(0xFF475569),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              child: const Text(
                                'Close',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }

                // NOTE: Real-Debrid returns links[] in the same order as the selected files list
                // We therefore use the index within the filtered `files` list directly to index links[]

                bool downloadingAll = false;
                int addCount = 0;
                final Set<int> added = {};
                final Set<int> selectedFiles = {}; // Track selected files
                final Map<int, bool> unrestrictingFiles =
                    {}; // Track which files are being unrestricted
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
                                  '${torrent.filename} (${files.length} files)',
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
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 12,
                              ),
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
                                        '$addCount/${files.length}',
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
                                      value: files.isEmpty
                                          ? null
                                          : (addCount / files.length).clamp(
                                              0.0,
                                              1.0,
                                            ),
                                      backgroundColor: Colors.grey[800],
                                      valueColor:
                                          const AlwaysStoppedAnimation<Color>(
                                            Color(0xFF10B981),
                                          ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],

                          // File List - conditional rendering for series vs regular files
                          Flexible(
                            child: isSeries
                                ? _buildSeriesFileBrowser(
                                    files: files,
                                    seriesInfos: seriesInfos,
                                    selectedFiles: selectedFiles,
                                    added: added,
                                    unrestrictingFiles: unrestrictingFiles,
                                    showPlayButtons: showPlayButtons,
                                    torrent: torrent,
                                    setLocal: setLocal,
                                  )
                                : ListView.separated(
                                    padding: const EdgeInsets.fromLTRB(
                                      24,
                                      8,
                                      24,
                                      16,
                                    ),
                                    shrinkWrap: true,
                                    itemCount: files.length,
                                    separatorBuilder: (_, __) =>
                                        const SizedBox(height: 12),
                                    itemBuilder: (context, index) {
                                      final file = files[index];
                                      String fileName =
                                          file['path']?.toString() ??
                                          'Unknown file';
                                      if (fileName.startsWith('/')) {
                                        fileName = fileName.split('/').last;
                                      }
                                      final fileSize =
                                          (file['bytes'] ?? 0) as int;
                                      final isVideo = FileUtils.isVideoFile(
                                        fileName,
                                      );
                                      final isAdded = added.contains(index);
                                      final isSelected = selectedFiles.contains(
                                        index,
                                      );
                                      final isUnrestricting =
                                          unrestrictingFiles[index] ?? false;

                                      return _buildModernFileCard(
                                        fileName: fileName,
                                        fileSize: fileSize,
                                        isVideo: isVideo,
                                        isAdded: isAdded,
                                        isSelected: isSelected,
                                        isUnrestricting: isUnrestricting,
                                        showPlayButtons: showPlayButtons,
                                        onPlay: () => _playFileOnDemand(
                                          torrent,
                                          index,
                                          setLocal,
                                          unrestrictingFiles,
                                        ),
                                        onAddToPlaylist: () =>
                                            _addFileToPlaylist(
                                              torrent,
                                              index,
                                              setLocal,
                                            ),
                                        onDownload: () => _downloadFileOnDemand(
                                          torrent,
                                          index,
                                          fileName,
                                          setLocal,
                                          added,
                                          unrestrictingFiles,
                                        ),
                                        onCopy: () => _copyFileLinkOnDemand(
                                          torrent,
                                          index,
                                          setLocal,
                                          unrestrictingFiles,
                                        ),
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
                              color: const Color(
                                0xFF0F172A,
                              ).withValues(alpha: 0.5),
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
                                        colors: [
                                          Color(0xFF8B5CF6),
                                          Color(0xFF7C3AED),
                                        ],
                                      ),
                                      borderRadius: BorderRadius.circular(16),
                                      boxShadow: [
                                        BoxShadow(
                                          color: const Color(
                                            0xFF8B5CF6,
                                          ).withValues(alpha: 0.3),
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
                                              final selectedIndices =
                                                  selectedFiles.toList();
                                              for (
                                                var i = 0;
                                                i < selectedIndices.length;
                                                i++
                                              ) {
                                                final index =
                                                    selectedIndices[i];
                                                final file = files[index];
                                                String fileName =
                                                    file['path']?.toString() ??
                                                    'file';
                                                if (fileName.startsWith('/')) {
                                                  fileName = fileName
                                                      .split('/')
                                                      .last;
                                                }

                                                // Queue download with restricted link (unrestriction happens on-demand)
                                                try {
                                                  final meta = jsonEncode({
                                                    'restrictedLink':
                                                        torrent.links[index],
                                                    'apiKey': _apiKey ?? '',
                                                    'torrentHash':
                                                        (torrent.id ?? '')
                                                            .toString(),
                                                    'fileIndex': index,
                                                  });
                                                  await DownloadService.instance
                                                      .enqueueDownload(
                                                        url: torrent
                                                            .links[index], // Use restricted link directly
                                                        fileName: fileName,
                                                        context: context,
                                                        torrentName:
                                                            torrent.filename,
                                                        meta: meta,
                                                      );
                                                  setLocal(() {
                                                    added.add(index);
                                                    addCount = i + 1;
                                                  });
                                                } catch (e) {
                                                  // Handle error silently for batch operations
                                                }
                                              }
                                              setLocal(() {
                                                downloadingAll = false;
                                                selectedFiles
                                                    .clear(); // Clear selection after download
                                              });
                                              if (mounted) {
                                                ScaffoldMessenger.of(
                                                  context,
                                                ).showSnackBar(
                                                  SnackBar(
                                                    content: Row(
                                                      children: [
                                                        Container(
                                                          padding:
                                                              const EdgeInsets.all(
                                                                8,
                                                              ),
                                                          decoration: BoxDecoration(
                                                            color: const Color(
                                                              0xFF8B5CF6,
                                                            ),
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  8,
                                                                ),
                                                          ),
                                                          child: const Icon(
                                                            Icons.check,
                                                            color: Colors.white,
                                                            size: 16,
                                                          ),
                                                        ),
                                                        const SizedBox(
                                                          width: 12,
                                                        ),
                                                        Expanded(
                                                          child: Text(
                                                            'Added ${selectedIndices.length} selected downloads',
                                                            style:
                                                                const TextStyle(
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w500,
                                                                ),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                    backgroundColor:
                                                        const Color(0xFF1E293B),
                                                    behavior: SnackBarBehavior
                                                        .floating,
                                                    shape: RoundedRectangleBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            12,
                                                          ),
                                                    ),
                                                    margin:
                                                        const EdgeInsets.all(
                                                          16,
                                                        ),
                                                  ),
                                                );
                                              }
                                            },
                                      icon: downloadingAll
                                          ? const SizedBox(
                                              width: 16,
                                              height: 16,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Colors.white,
                                              ),
                                            )
                                          : const Icon(
                                              Icons.download_rounded,
                                              color: Colors.white,
                                            ),
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
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 20,
                                          vertical: 12,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
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
                                            colors: [
                                              Color(0xFF10B981),
                                              Color(0xFF059669),
                                            ],
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: const Color(
                                                0xFF10B981,
                                              ).withValues(alpha: 0.3),
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
                                                  for (
                                                    var i = 0;
                                                    i < files.length;
                                                    i++
                                                  ) {
                                                    final file = files[i];
                                                    String fileName =
                                                        file['path']
                                                            ?.toString() ??
                                                        'file';
                                                    if (fileName.startsWith(
                                                      '/',
                                                    )) {
                                                      fileName = fileName
                                                          .split('/')
                                                          .last;
                                                    }

                                                    // Queue download with restricted link (unrestriction happens on-demand)
                                                    try {
                                                      final meta = jsonEncode({
                                                        'restrictedLink':
                                                            torrent.links[i],
                                                        'apiKey': _apiKey ?? '',
                                                        'torrentHash':
                                                            (torrent.id ?? '')
                                                                .toString(),
                                                        'fileIndex': i,
                                                      });
                                                      await DownloadService
                                                          .instance
                                                          .enqueueDownload(
                                                            url: torrent
                                                                .links[i], // Use restricted link directly
                                                            fileName: fileName,
                                                            context: context,
                                                            torrentName: torrent
                                                                .filename,
                                                            meta: meta,
                                                          );
                                                      setLocal(() {
                                                        added.add(i);
                                                        addCount = i + 1;
                                                      });
                                                    } catch (e) {
                                                      // Handle error silently for batch operations
                                                    }
                                                  }
                                                  setLocal(
                                                    () =>
                                                        downloadingAll = false,
                                                  );
                                                  if (mounted) {
                                                    ScaffoldMessenger.of(
                                                      context,
                                                    ).showSnackBar(
                                                      SnackBar(
                                                        content: Row(
                                                          children: [
                                                            Container(
                                                              padding:
                                                                  const EdgeInsets.all(
                                                                    8,
                                                                  ),
                                                              decoration: BoxDecoration(
                                                                color:
                                                                    const Color(
                                                                      0xFF10B981,
                                                                    ),
                                                                borderRadius:
                                                                    BorderRadius.circular(
                                                                      8,
                                                                    ),
                                                              ),
                                                              child: const Icon(
                                                                Icons.check,
                                                                color: Colors
                                                                    .white,
                                                                size: 16,
                                                              ),
                                                            ),
                                                            const SizedBox(
                                                              width: 12,
                                                            ),
                                                            Expanded(
                                                              child: Text(
                                                                'Added ${files.length} downloads',
                                                                style: const TextStyle(
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w500,
                                                                ),
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                        backgroundColor:
                                                            const Color(
                                                              0xFF1E293B,
                                                            ),
                                                        behavior:
                                                            SnackBarBehavior
                                                                .floating,
                                                        shape: RoundedRectangleBorder(
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                12,
                                                              ),
                                                        ),
                                                        margin:
                                                            const EdgeInsets.all(
                                                              16,
                                                            ),
                                                      ),
                                                    );
                                                  }
                                                },
                                          icon: downloadingAll
                                              ? const SizedBox(
                                                  width: 16,
                                                  height: 16,
                                                  child:
                                                      CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                        color: Colors.white,
                                                      ),
                                                )
                                              : const Icon(
                                                  Icons.download_rounded,
                                                  color: Colors.white,
                                                ),
                                          label: Text(
                                            downloadingAll
                                                ? 'Adding $addCount/${files.length}…'
                                                : 'Download All',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          style: FilledButton.styleFrom(
                                            backgroundColor: Colors.transparent,
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 20,
                                              vertical: 12,
                                            ),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(16),
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
                                        onPressed: () =>
                                            Navigator.of(context).pop(),
                                        style: TextButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 12,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              16,
                                            ),
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
              child: const Icon(Icons.check, color: Colors.white, size: 16),
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
    } else if (errorString.contains('invalid api key') ||
        errorString.contains('401')) {
      return 'Invalid API key. Please check your Real Debrid settings.';
    } else if (errorString.contains('account locked') ||
        errorString.contains('403')) {
      return 'Your Real Debrid account is locked. Please check your account status.';
    } else if (errorString.contains('network error') ||
        errorString.contains('connection')) {
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
    } else if (errorString.contains('failed to load torrents') ||
        errorString.contains('failed to load downloads')) {
      return 'Unable to load downloads. Please check your connection and try again.';
    } else {
      return 'Failed to add torrent. Please try again.';
    }
  }

  String _getLinkUnrestrictErrorMessage(String errorMessage) {
    final errorString = errorMessage.toLowerCase();

    // Handle specific Real Debrid error codes and messages
    if (errorString.contains('infringing_file')) {
      return 'This file contains copyrighted content and cannot be unrestricted.';
    } else if (errorString.contains('invalid_link')) {
      return 'Invalid or unsupported link format.';
    } else if (errorString.contains('file_not_found')) {
      return 'File not found or no longer available.';
    } else if (errorString.contains('host_not_supported')) {
      return 'This file hosting service is not supported by Real Debrid.';
    } else if (errorString.contains('file_too_large')) {
      return 'File size exceeds Real Debrid limits.';
    } else if (errorString.contains('quota_exceeded')) {
      return 'Real Debrid quota exceeded. Please try again later.';
    } else if (errorString.contains('invalid api key') ||
        errorString.contains('401')) {
      return 'Invalid API key. Please check your Real Debrid settings.';
    } else if (errorString.contains('account_locked') ||
        errorString.contains('403')) {
      return 'Your Real Debrid account is locked. Please check your account status.';
    } else if (errorString.contains('network error') ||
        errorString.contains('connection')) {
      return 'Network connection error. Please check your internet connection.';
    } else if (errorString.contains('timeout')) {
      return 'Request timed out. Please try again.';
    } else {
      // For other errors, try to extract a clean message
      if (errorString.contains('failed to unrestrict link:')) {
        // Extract the status code and clean up the message
        final parts = errorMessage.split(' - ');
        if (parts.length > 1) {
          return 'Failed to unrestrict link (${parts[0].split(': ').last}). Please try a different link.';
        }
      }
      return 'Failed to unrestrict link. Please try a different link.';
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
              child: const Icon(Icons.error, color: Colors.white, size: 16),
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
    final Widget content = _selectedView == _DebridDownloadsView.torrents
        ? _buildTorrentContent()
        : _buildDownloadContent();

    return Scaffold(
      body: Column(
        children: [
          const SizedBox(height: 8),
          Expanded(child: content),
        ],
      ),
    );
  }

  Widget _buildViewSelector() {
    final theme = Theme.of(context);
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: theme.colorScheme.onPrimaryContainer.withValues(alpha: 0.1),
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<_DebridDownloadsView>(
          value: _selectedView,
          dropdownColor: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          iconEnabledColor: theme.colorScheme.onPrimaryContainer,
          style: TextStyle(
            color: theme.colorScheme.onPrimaryContainer,
            fontWeight: FontWeight.w600,
          ),
          items: const [
            DropdownMenuItem(
              value: _DebridDownloadsView.torrents,
              child: Text('Torrent Downloads'),
            ),
            DropdownMenuItem(
              value: _DebridDownloadsView.ddl,
              child: Text('DDL Downloads'),
            ),
          ],
          onChanged: (value) {
            if (value != null && value != _selectedView) {
              setState(() => _selectedView = value);
            }
          },
        ),
      ),
    );
  }

  Widget _buildTorrentToolbar() {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF1F2937)),
      ),
      child: Row(
        children: [
          _buildViewSelector(),
          const Spacer(),
          Tooltip(
            message: 'Add magnet link',
            child: IconButton(
              onPressed: _showAddMagnetDialog,
              icon: const Icon(Icons.add_circle_outline),
              color: theme.colorScheme.primary,
              visualDensity: VisualDensity.compact,
            ),
          ),
          const SizedBox(width: 8),
          Tooltip(
            message: 'Delete all torrents',
            child: IconButton(
              onPressed: _torrents.isEmpty ? null : _handleDeleteAllTorrents,
              icon: const Icon(Icons.delete_sweep),
              color: const Color(0xFFEF4444),
              visualDensity: VisualDensity.compact,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDownloadToolbar() {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF1F2937)),
      ),
      child: Row(
        children: [
          _buildViewSelector(),
          const Spacer(),
          Tooltip(
            message: 'Add file link',
            child: IconButton(
              onPressed: _showAddLinkDialog,
              icon: const Icon(Icons.note_add_outlined),
              color: theme.colorScheme.primary,
              visualDensity: VisualDensity.compact,
            ),
          ),
          const SizedBox(width: 8),
          Tooltip(
            message: 'Delete all DDL downloads',
            child: IconButton(
              onPressed: _downloads.isEmpty ? null : _handleDeleteAllDownloads,
              icon: const Icon(Icons.delete_sweep),
              color: const Color(0xFFEF4444),
              visualDensity: VisualDensity.compact,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTorrentContent() {
    Widget body;

    if (_isLoadingTorrents && _torrents.isEmpty) {
      body = const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading your torrent downloads...'),
          ],
        ),
      );
    } else if (_torrentErrorMessage.isNotEmpty && _torrents.isEmpty) {
      body = Center(
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
                    Icon(Icons.error_outline, color: Colors.red, size: 48),
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
                      style: TextStyle(color: Colors.red[600], fontSize: 14),
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
    } else if (_torrents.isEmpty) {
      body = const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.download_done, size: 64, color: Colors.grey),
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
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    } else {
      body = RefreshIndicator(
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
                child: Center(child: CircularProgressIndicator()),
              );
            }

            final torrent = _torrents[index];
            return _buildTorrentCard(torrent);
          },
        ),
      );
    }

    return Column(
      children: [
        _buildTorrentToolbar(),
        Expanded(child: body),
      ],
    );
  }

  Widget _buildDownloadContent() {
    Widget body;

    if (_isLoadingDownloads && _downloads.isEmpty) {
      body = const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading your DDL downloads...'),
          ],
        ),
      );
    } else if (_downloadErrorMessage.isNotEmpty && _downloads.isEmpty) {
      body = Center(
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
                    Icon(Icons.error_outline, color: Colors.red, size: 48),
                    const SizedBox(height: 12),
                    Text(
                      'Error Loading DDL Downloads',
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
                      style: TextStyle(color: Colors.red[600], fontSize: 14),
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
    } else if (_downloads.isEmpty) {
      body = const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.download_done, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'No DDL downloads yet',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.grey,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Your DDL downloads will appear here',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    } else {
      body = RefreshIndicator(
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
                child: Center(child: CircularProgressIndicator()),
              );
            }

            final download = _downloads[index];
            return _buildDownloadCard(download);
          },
        ),
      );
    }

    return Column(
      children: [
        _buildDownloadToolbar(),
        Expanded(child: body),
      ],
    );
  }

  Widget _buildTorrentCard(RDTorrent torrent) {
    final bool showProblematicVideo =
        torrent.links.length == 1 &&
        FileUtils.isProblematicVideo(torrent.filename);
    const playColor = Color(0xFF7F1D1D); // softened red
    const downloadColor = Color(0xFF065F46); // softened green
    const problematicColor = Color(0xFFD97706);
    final borderColor = Colors.white.withValues(alpha: 0.08);
    final glowColor = const Color(0xFF6366F1).withValues(alpha: 0.08);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1F2A44), Color(0xFF111C32)],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 20,
            offset: const Offset(0, 12),
          ),
          BoxShadow(
            color: glowColor,
            blurRadius: 26,
            offset: const Offset(0, 6),
          ),
        ],
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
                  crossAxisAlignment: CrossAxisAlignment.start,
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
                    const SizedBox(width: 8),
                    _buildMoreOptionsButton(torrent),
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
                      text:
                          '${torrent.links.length} file${torrent.links.length > 1 ? 's' : ''}',
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
                    Icon(Icons.computer, size: 16, color: Colors.grey[400]),
                    const SizedBox(width: 4),
                    Text(
                      torrent.host,
                      style: TextStyle(color: Colors.grey[400], fontSize: 12),
                    ),
                    const Spacer(),
                    Text(
                      'Added ${Formatters.formatDateString(torrent.added)}',
                      style: TextStyle(color: Colors.grey[400], fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Action buttons
          Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF131E33), Color(0xFF0B1224)],
              ),
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(18),
                bottomRight: Radius.circular(18),
              ),
              border: Border(
                top: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isCompact = constraints.maxWidth < 380;
                  final playButton = _buildPrimaryActionButton(
                    icon: showProblematicVideo
                        ? Icons.warning
                        : Icons.play_arrow,
                    label: 'Play',
                    backgroundColor: showProblematicVideo
                        ? problematicColor
                        : playColor,
                    onPressed: () {
                      if (torrent.links.length == 1) {
                        _handlePlayVideo(torrent);
                      } else {
                        _handlePlayMultiFileTorrent(torrent);
                      }
                    },
                  );
                  final downloadButton = _buildPrimaryActionButton(
                    icon: Icons.download_rounded,
                    label: 'Download',
                    backgroundColor: downloadColor,
                    onPressed: () => _handleDownloadTorrent(torrent),
                  );

                  if (isCompact) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(width: double.infinity, child: playButton),
                        const SizedBox(height: 8),
                        SizedBox(width: double.infinity, child: downloadButton),
                      ],
                    );
                  }

                  return Row(
                    children: [
                      Expanded(child: playButton),
                      const SizedBox(width: 12),
                      Expanded(child: downloadButton),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrimaryActionButton({
    required IconData icon,
    required String label,
    required Color backgroundColor,
    required VoidCallback onPressed,
  }) {
    return FilledButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 20),
      label: Text(label),
      style: FilledButton.styleFrom(
        backgroundColor: backgroundColor,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _buildMoreOptionsButton(RDTorrent torrent) {
    return IconButton(
      onPressed: () => _showTorrentMoreOptions(torrent),
      icon: const Icon(Icons.more_vert, size: 20),
      tooltip: 'More options',
      style: IconButton.styleFrom(
        backgroundColor: const Color(0xFF111C32),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.all(12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: const Color(0xFF475569).withValues(alpha: 0.3),
          ),
        ),
      ),
    );
  }

  Widget _buildDownloadMoreOptionsButton(DebridDownload download) {
    return IconButton(
      onPressed: () => _showDownloadMoreOptions(download),
      icon: const Icon(Icons.more_vert, size: 20),
      tooltip: 'More options',
      style: IconButton.styleFrom(
        backgroundColor: const Color(0xFF111C32),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.all(12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: const Color(0xFF475569).withValues(alpha: 0.3),
          ),
        ),
      ),
    );
  }

  Future<void> _handleDownloadTorrent(RDTorrent torrent) async {
    if (_apiKey == null) return;

    if (torrent.links.length == 1) {
      try {
        final meta = jsonEncode({
          'restrictedLink': torrent.links.first,
          'apiKey': _apiKey ?? '',
          'torrentHash': (torrent.id ?? '').toString(),
          'fileIndex': 0,
        });
        await DownloadService.instance.enqueueDownload(
          url: torrent.links.first,
          fileName: torrent.filename,
          context: context,
          torrentName: torrent.filename,
          meta: meta,
        );
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Added to downloads')));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to start download: $e')),
          );
        }
      }
    } else {
      if (mounted) {
        _showMultipleLinksDialog(torrent, showPlayButtons: false);
      }
    }
  }

  Future<void> _handleAddTorrentToPlaylist(RDTorrent torrent) async {
    if (_apiKey == null) return;

    if (torrent.links.length == 1) {
      try {
        final unrestrictResult = await DebridService.unrestrictLink(
          _apiKey!,
          torrent.links[0],
        );
        final mimeType = unrestrictResult['mimeType']?.toString() ?? '';

        if (FileUtils.isVideoMimeType(mimeType)) {
          final ok = await StorageService.addPlaylistItemRaw({
            'title': torrent.filename,
            'url': '',
            'restrictedLink': torrent.links[0],
            'rdTorrentId': torrent.id,
            'kind': 'single',
          });
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(ok ? 'Added to playlist' : 'Already in playlist'),
            ),
          );
        } else {
          if (mounted) {
            _showError('This file is not a video (MIME type: $mimeType)');
          }
        }
      } catch (e) {
        if (mounted) {
          _showError('Failed to validate file: ${e.toString()}');
        }
      }
    } else {
      final ok = await StorageService.addPlaylistItemRaw({
        'title': torrent.filename,
        'kind': 'collection',
        'rdTorrentId': torrent.id,
        'count': torrent.links.length,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok ? 'Added to playlist' : 'Already in playlist'),
        ),
      );
    }
  }

  void _showTorrentMoreOptions(RDTorrent torrent) {
    final isMultiFile = torrent.links.length > 1;
    final options = <_ActionSheetOption>[
      _ActionSheetOption(
        icon: Icons.playlist_add,
        label: 'Add to Playlist',
        onTap: () => _handleAddTorrentToPlaylist(torrent),
      ),
      _ActionSheetOption(
        icon: Icons.copy,
        label: 'Copy Link',
        onTap: isMultiFile ? null : () => _handleFileOptions(torrent),
        enabled: !isMultiFile,
      ),
      _ActionSheetOption(
        icon: Icons.delete_outline,
        label: 'Delete Torrent',
        onTap: () => _handleDeleteTorrent(torrent),
        destructive: true,
      ),
    ];

    _showOptionsSheet(options);
  }

  void _showOptionsSheet(List<_ActionSheetOption> options) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  const Color(0xFF0F172A).withValues(alpha: 0.98),
                  const Color(0xFF1E293B).withValues(alpha: 0.98),
                ],
              ),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
              border: Border.all(
                color: const Color(0xFF6366F1).withValues(alpha: 0.2),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.45),
                  blurRadius: 28,
                  offset: const Offset(0, 16),
                ),
              ],
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    const SizedBox(height: 14),
                    for (final option in options) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: InkWell(
                          onTap: option.enabled
                              ? () async {
                                  Navigator.of(sheetContext).pop();
                                  await option.onTap?.call();
                                }
                              : null,
                          borderRadius: BorderRadius.circular(16),
                          splashColor: option.enabled
                              ? const Color(0xFF6366F1).withValues(alpha: 0.2)
                              : Colors.transparent,
                          highlightColor: option.enabled
                              ? Colors.white.withValues(alpha: 0.06)
                              : Colors.transparent,
                          child: Opacity(
                            opacity: option.enabled ? 1.0 : 0.45,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 14,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF111C32),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: const Color(
                                    0xFF475569,
                                  ).withValues(alpha: 0.35),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    option.icon,
                                    size: 20,
                                    color: option.destructive
                                        ? const Color(0xFFEF4444)
                                        : Colors.white,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      option.label,
                                      style: TextStyle(
                                        color: option.destructive
                                            ? const Color(0xFFEF4444)
                                            : Colors.white,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  Icon(
                                    Icons.chevron_right,
                                    size: 20,
                                    color: Colors.white.withValues(alpha: 0.25),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDownloadCard(DebridDownload download) {
    final borderColor = Colors.white.withValues(alpha: 0.08);
    final glowColor = const Color(0xFF6366F1).withValues(alpha: 0.08);
    final canStream = download.streamable == 1;
    final showProblematicVideo =
        canStream && FileUtils.isProblematicVideo(download.filename);
    const playColor = Color(0xFF7F1D1D);
    const downloadColor = Color(0xFF065F46);
    const problematicColor = Color(0xFFD97706);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1F2A44), Color(0xFF111C32)],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 20,
            offset: const Offset(0, 12),
          ),
          BoxShadow(
            color: glowColor,
            blurRadius: 26,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
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
                    const SizedBox(width: 8),
                    _buildDownloadMoreOptionsButton(download),
                  ],
                ),
                const SizedBox(height: 12),
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
                      text:
                          '${download.chunks} chunk${download.chunks == 1 ? '' : 's'}',
                      color: const Color(0xFFF59E0B),
                    ),
                    const SizedBox(width: 8),
                    StatChip(
                      icon: canStream ? Icons.play_arrow : Icons.download,
                      text: canStream ? 'Streamable' : 'Download only',
                      color: canStream
                          ? const Color(0xFFE50914)
                          : const Color(0xFF10B981),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(Icons.computer, size: 16, color: Colors.grey[400]),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        download.host,
                        style:
                            TextStyle(color: Colors.grey[400], fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Generated ${Formatters.formatDateString(download.generated)}',
                      style: TextStyle(color: Colors.grey[400], fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF131E33), Color(0xFF0B1224)],
              ),
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(18),
                bottomRight: Radius.circular(18),
              ),
              border: Border(
                top: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isCompact = constraints.maxWidth < 380;
                  final Widget downloadButton = _buildPrimaryActionButton(
                    icon: Icons.download_rounded,
                    label: 'Download',
                    backgroundColor: downloadColor,
                    onPressed: () => _handleQueueDownload(download),
                  );

                  if (!canStream) {
                    return SizedBox(
                      width: double.infinity,
                      child: downloadButton,
                    );
                  }

                  final Widget playButton = _buildPrimaryActionButton(
                    icon:
                        showProblematicVideo ? Icons.warning : Icons.play_arrow,
                    label: 'Play',
                    backgroundColor:
                        showProblematicVideo ? problematicColor : playColor,
                    onPressed: () => _handlePlayDownload(download),
                  );

                  if (isCompact) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        playButton,
                        const SizedBox(height: 8),
                        downloadButton,
                      ],
                    );
                  }

                  return Row(
                    children: [
                      Expanded(child: playButton),
                      const SizedBox(width: 12),
                      Expanded(child: downloadButton),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
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
      final torrentInfo = await DebridService.getTorrentInfo(
        _apiKey!,
        torrent.id,
      );
      final files = torrentInfo['files'] as List<dynamic>?;

      if (files == null || files.isEmpty) {
        if (mounted) Navigator.of(context).pop(); // close loading
        if (mounted) {
          _showError('Failed to get file information from torrent.');
        }
        return;
      }

      // Get selected files from the torrent info
      final selectedFiles = files
          .where((file) => file['selected'] == 1)
          .toList();

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
          if (i >= torrent.links.length) {
            // Skip if no corresponding link
            continue;
          }

          if (i == firstEpisodeIndex) {
            // First episode: try to unrestrict for immediate playback
            try {
              final unrestrictResult = await DebridService.unrestrictLink(
                _apiKey!,
                torrent.links[i],
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
                    restrictedLink: torrent.links[i],
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
                  restrictedLink: torrent.links[i],
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
                restrictedLink: torrent.links[i],
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
          if (i >= torrent.links.length) {
            // Skip if no corresponding link
            continue;
          }

          if (i == 0) {
            // First video: try to unrestrict for immediate playback
            try {
              final unrestrictResult = await DebridService.unrestrictLink(
                _apiKey!,
                torrent.links[i],
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
                    restrictedLink: torrent.links[i],
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
                  restrictedLink: torrent.links[i],
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
                restrictedLink: torrent.links[i],
                sizeBytes: sizeBytes,
              ),
            );
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
                    onPressed: _isAddingMagnet
                        ? null
                        : _addMagnetWithDefaultSelection,
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
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
            ),
          ],
        ),
      ),
    );

    if (mounted) {
      setState(() {
        _isAddingMagnet = true;
      });
    }

    try {
      // Get the default file selection preference
      final fileSelection = await StorageService.getFileSelection();

      // Add the magnet using the same logic as the torrent search screen
      await DebridService.addTorrentToDebrid(
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
            onPressed: _isAddingMagnet
                ? null
                : () => _addMagnetWithSelection(magnetLink, 'smart'),
            child: _isAddingMagnet
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Smart (recommended)'),
          ),
          TextButton(
            onPressed: _isAddingMagnet
                ? null
                : () => _addMagnetWithSelection(magnetLink, 'largest'),
            child: _isAddingMagnet
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Largest File'),
          ),
          TextButton(
            onPressed: _isAddingMagnet
                ? null
                : () => _addMagnetWithSelection(magnetLink, 'video'),
            child: _isAddingMagnet
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Video Files'),
          ),
          TextButton(
            onPressed: _isAddingMagnet
                ? null
                : () => _addMagnetWithSelection(magnetLink, 'all'),
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

  Future<void> _addMagnetWithSelection(
    String magnetLink,
    String fileSelection,
  ) async {
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
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
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
      await DebridService.addTorrentToDebrid(
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

  // Link input methods
  Future<void> _showAddLinkDialog() async {
    // Auto-paste link from clipboard if available
    await _autoPasteLink();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Add Link',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter a link to unrestrict:',
              style: TextStyle(color: Colors.grey, fontSize: 14),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _linkController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'https://example.com/file.zip',
                hintStyle: TextStyle(color: Colors.grey[600]),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFF475569)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFF475569)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFF6366F1)),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
              ),
              maxLines: 3,
              minLines: 1,
            ),
            const SizedBox(height: 8),
            Text(
              'Supported: Direct download links, file hosting services, etc.',
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
            ),
          ],
        ),
        actions: [
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
                child: FilledButton(
                  onPressed: _isAddingLink ? null : _addLink,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    backgroundColor: const Color(0xFF6366F1),
                  ),
                  child: _isAddingLink
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
    );
  }

  Future<void> _autoPasteLink() async {
    final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
    if (clipboardData?.text != null) {
      final text = clipboardData!.text!.trim();
      // Check if it looks like a URL
      if (text.startsWith('http://') || text.startsWith('https://')) {
        _linkController.text = text;
      }
    }
  }

  bool _isValidLink(String link) {
    final trimmedLink = link.trim();
    return trimmedLink.startsWith('http://') ||
        trimmedLink.startsWith('https://');
  }

  Future<void> _addLink() async {
    final link = _linkController.text.trim();
    if (link.isEmpty) {
      _showError('Please enter a link');
      return;
    }

    if (!_isValidLink(link)) {
      _showError(
        'Please enter a valid URL (must start with http:// or https://)',
      );
      return;
    }

    Navigator.of(context).pop(); // Close the dialog

    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Unrestricting Link',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            const Text(
              'Processing link...',
              style: TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 8),
            Text(
              'This may take a few moments',
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
            ),
          ],
        ),
      ),
    );

    if (mounted) {
      setState(() {
        _isAddingLink = true;
      });
    }

    try {
      // Unrestrict the link
      await DebridService.unrestrictLink(_apiKey!, link);

      // Close loading dialog
      if (mounted) {
        Navigator.of(context).pop();
      }

      // Clear the input
      _linkController.clear();

      // Show success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Link unrestricted successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }

      // Refresh the downloads list
      await _fetchDownloads(_apiKey!, reset: true);
    } catch (e) {
      // Close loading dialog
      if (mounted) {
        Navigator.of(context).pop();
      }

      if (mounted) {
        // Show the actual Real Debrid error message with user-friendly formatting
        final errorMessage = e.toString().replaceFirst('Exception: ', '');
        final friendlyMessage = _getLinkUnrestrictErrorMessage(errorMessage);
        _showError(friendlyMessage);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isAddingLink = false;
        });
      }
    }
  }

  // New on-demand action handlers
  Future<void> _playFileOnDemand(
    RDTorrent torrent,
    int index,
    StateSetter setLocal,
    Map<int, bool> unrestrictingFiles,
  ) async {
    if (_apiKey == null) return;

    try {
      setLocal(() {
        unrestrictingFiles[index] = true;
      });

      final unrestrictResult = await DebridService.unrestrictLink(
        _apiKey!,
        torrent.links[index],
      );
      final downloadLink = unrestrictResult['download']?.toString() ?? '';
      final mimeType = unrestrictResult['mimeType']?.toString() ?? '';

      if (downloadLink.isNotEmpty) {
        // Check if it's actually a video using MIME type
        if (FileUtils.isVideoMimeType(mimeType)) {
          if (mounted) {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => VideoPlayerScreen(
                  videoUrl: downloadLink,
                  title: torrent.filename,
                  subtitle: 'File ${index + 1}',
                ),
              ),
            );
          }
        } else {
          if (mounted) {
            _showError('This file is not a video (MIME type: $mimeType)');
          }
        }
      } else {
        if (mounted) {
          _showError('Failed to get download link');
        }
      }
    } catch (e) {
      if (mounted) {
        _showError('Failed to load video: ${e.toString()}');
      }
    } finally {
      setLocal(() {
        unrestrictingFiles[index] = false;
      });
    }
  }

  Future<void> _addFileToPlaylist(
    RDTorrent torrent,
    int index,
    StateSetter setLocal,
  ) async {
    if (_apiKey == null) return;

    try {
      // Check if it's a video file before adding to playlist
      final unrestrictResult = await DebridService.unrestrictLink(
        _apiKey!,
        torrent.links[index],
      );
      final mimeType = unrestrictResult['mimeType']?.toString() ?? '';

      // Check if it's actually a video using MIME type
      if (FileUtils.isVideoMimeType(mimeType)) {
        final item = {
          'title': torrent.filename,
          'url': '',
          'restrictedLink': torrent.links[index],
          'rdTorrentId': torrent.id,
          'kind': 'single',
        };
        final ok = await StorageService.addPlaylistItemRaw(item);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ok ? 'Added to playlist' : 'Already in playlist'),
          ),
        );
      } else {
        if (mounted) {
          _showError('This file is not a video (MIME type: $mimeType)');
        }
      }
    } catch (e) {
      if (mounted) {
        _showError('Failed to validate file: ${e.toString()}');
      }
    }
  }

  Future<void> _downloadFileOnDemand(
    RDTorrent torrent,
    int index,
    String fileName,
    StateSetter setLocal,
    Set<int> added,
    Map<int, bool> unrestrictingFiles,
  ) async {
    if (_apiKey == null) return;

    try {
      setLocal(() {
        unrestrictingFiles[index] = true;
      });

      final unrestrictResult = await DebridService.unrestrictLink(
        _apiKey!,
        torrent.links[index],
      );
      final downloadLink = unrestrictResult['download']?.toString() ?? '';

      if (downloadLink.isNotEmpty) {
        await DownloadService.instance.enqueueDownload(
          url: downloadLink,
          // Use RD-provided filename if available to avoid mismatches
          fileName: (unrestrictResult['filename']?.toString() ?? fileName),
          context: context,
          torrentName: torrent.filename,
        );
        setLocal(() {
          added.add(index);
        });
      } else {
        if (mounted) {
          _showError('Failed to get download link');
        }
      }
    } catch (e) {
      if (mounted) {
        _showError('Failed to get download link: ${e.toString()}');
      }
    } finally {
      setLocal(() {
        unrestrictingFiles[index] = false;
      });
    }
  }

  Future<void> _copyFileLinkOnDemand(
    RDTorrent torrent,
    int index,
    StateSetter setLocal,
    Map<int, bool> unrestrictingFiles,
  ) async {
    if (_apiKey == null) return;

    try {
      setLocal(() {
        unrestrictingFiles[index] = true;
      });

      final unrestrictResult = await DebridService.unrestrictLink(
        _apiKey!,
        torrent.links[index],
      );
      final downloadLink = unrestrictResult['download']?.toString() ?? '';

      if (downloadLink.isNotEmpty) {
        if (mounted) {
          _copyToClipboard(downloadLink);
        }
      } else {
        if (mounted) {
          _showError('Failed to get download link');
        }
      }
    } catch (e) {
      if (mounted) {
        _showError('Failed to get download link: ${e.toString()}');
      }
    } finally {
      setLocal(() {
        unrestrictingFiles[index] = false;
      });
    }
  }

  Widget _buildModernFileCard({
    required String fileName,
    required int fileSize,
    required bool isVideo,
    required bool isAdded,
    required bool isSelected,
    required bool isUnrestricting,
    required bool showPlayButtons,
    required VoidCallback onPlay,
    required VoidCallback onAddToPlaylist,
    required VoidCallback onDownload,
    required VoidCallback onCopy,
    required VoidCallback onSelect,
    required int index,
    String? episodeInfo,
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
                                      ? [
                                          const Color(0xFFE50914),
                                          const Color(0xFFDC2626),
                                        ]
                                      : [
                                          const Color(0xFFF59E0B),
                                          const Color(0xFFD97706),
                                        ],
                                ),
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color:
                                        (isVideo
                                                ? const Color(0xFFE50914)
                                                : const Color(0xFFF59E0B))
                                            .withValues(alpha: 0.3),
                                    blurRadius: 12,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                              ),
                              child: Icon(
                                isVideo
                                    ? Icons.play_arrow_rounded
                                    : Icons.insert_drive_file_rounded,
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
                                  Row(
                                    children: [
                                      if (episodeInfo != null) ...[
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: const Color(
                                              0xFF6366F1,
                                            ).withValues(alpha: 0.2),
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                            border: Border.all(
                                              color: const Color(
                                                0xFF6366F1,
                                              ).withValues(alpha: 0.3),
                                              width: 1,
                                            ),
                                          ),
                                          child: Text(
                                            episodeInfo,
                                            style: const TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: Color(0xFF6366F1),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                      ],
                                      Expanded(
                                        child: Text(
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
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(
                                        0xFF475569,
                                      ).withValues(alpha: 0.3),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: const Color(
                                          0xFF64748B,
                                        ).withValues(alpha: 0.3),
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
                                boxShadow: isSelected
                                    ? [
                                        BoxShadow(
                                          color: const Color(
                                            0xFF8B5CF6,
                                          ).withValues(alpha: 0.3),
                                          blurRadius: 8,
                                          offset: const Offset(0, 2),
                                        ),
                                      ]
                                    : null,
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
                                    colors: [
                                      Color(0xFF6366F1),
                                      Color(0xFF8B5CF6),
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(
                                        0xFF6366F1,
                                      ).withValues(alpha: 0.3),
                                      blurRadius: 8,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: FilledButton.icon(
                                  onPressed: isUnrestricting ? null : onPlay,
                                  icon: isUnrestricting
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            valueColor:
                                                AlwaysStoppedAnimation<Color>(
                                                  Colors.white,
                                                ),
                                          ),
                                        )
                                      : const Icon(
                                          Icons.play_arrow_rounded,
                                          color: Colors.white,
                                          size: 18,
                                        ),
                                  label: Text(
                                    isUnrestricting ? 'Loading...' : 'Play',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                    ),
                                  ),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: Colors.transparent,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 10,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                            ],
                            OutlinedButton.icon(
                              onPressed: isUnrestricting ? null : onCopy,
                              icon: isUnrestricting
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                              Colors.white,
                                            ),
                                      ),
                                    )
                                  : const Icon(
                                      Icons.copy_rounded,
                                      size: 16,
                                      color: Colors.white,
                                    ),
                              label: Text(
                                isUnrestricting ? 'Working…' : 'Copy',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(
                                  color: Colors.white.withValues(alpha: 0.2),
                                ),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 10,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: isAdded
                                      ? [
                                          const Color(0xFF10B981),
                                          const Color(0xFF059669),
                                        ]
                                      : [
                                          const Color(0xFF1E293B),
                                          const Color(0xFF334155),
                                        ],
                                ),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isAdded
                                      ? const Color(
                                          0xFF10B981,
                                        ).withValues(alpha: 0.5)
                                      : const Color(
                                          0xFF475569,
                                        ).withValues(alpha: 0.5),
                                  width: 1,
                                ),
                                boxShadow: isAdded
                                    ? [
                                        BoxShadow(
                                          color: const Color(
                                            0xFF10B981,
                                          ).withValues(alpha: 0.3),
                                          blurRadius: 8,
                                          offset: const Offset(0, 4),
                                        ),
                                      ]
                                    : null,
                              ),
                              child: FilledButton.icon(
                                onPressed: (isAdded || isUnrestricting)
                                    ? null
                                    : onDownload,
                                icon: isUnrestricting
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(
                                                Colors.grey,
                                              ),
                                        ),
                                      )
                                    : Icon(
                                        isAdded
                                            ? Icons.check_circle_rounded
                                            : Icons.download_rounded,
                                        color: isAdded
                                            ? Colors.white
                                            : Colors.grey[300],
                                        size: 18,
                                      ),
                                label: Text(
                                  isUnrestricting
                                      ? 'Getting Link...'
                                      : (isAdded ? 'Added' : 'Download'),
                                  style: TextStyle(
                                    color: isAdded
                                        ? Colors.white
                                        : Colors.grey[300],
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                                style: FilledButton.styleFrom(
                                  backgroundColor: Colors.transparent,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 10,
                                  ),
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

  Widget _buildSeriesFileBrowser({
    required List<dynamic> files,
    required List<SeriesInfo> seriesInfos,
    required Set<int> selectedFiles,
    required Set<int> added,
    required Map<int, bool> unrestrictingFiles,
    required bool showPlayButtons,
    required RDTorrent torrent,
    required StateSetter setLocal,
  }) {
    return StatefulBuilder(
      builder: (context, setBrowserState) {
        return _buildFileBrowserContent(
          files: files,
          seriesInfos: seriesInfos,
          selectedFiles: selectedFiles,
          added: added,
          unrestrictingFiles: unrestrictingFiles,
          showPlayButtons: showPlayButtons,
          torrent: torrent,
          setLocal: setLocal,
          setBrowserState: setBrowserState,
        );
      },
    );
  }

  Widget _buildFileBrowserContent({
    required List<dynamic> files,
    required List<SeriesInfo> seriesInfos,
    required Set<int> selectedFiles,
    required Set<int> added,
    required Map<int, bool> unrestrictingFiles,
    required bool showPlayButtons,
    required RDTorrent torrent,
    required StateSetter setLocal,
    required StateSetter setBrowserState,
  }) {
    // Group files by season
    final seasonMap = <int, List<Map<String, dynamic>>>{};
    String? seriesTitle;

    for (int i = 0; i < files.length; i++) {
      final file = files[i];
      final seriesInfo = seriesInfos[i];

      if (seriesInfo.isSeries && seriesInfo.season != null) {
        final seasonNumber = seriesInfo.season!;
        seriesTitle ??= seriesInfo.title;

        seasonMap.putIfAbsent(seasonNumber, () => []);
        seasonMap[seasonNumber]!.add({
          'file': file,
          'seriesInfo': seriesInfo,
          'index': i,
        });
      }
    }

    // Sort seasons
    final sortedSeasons = seasonMap.keys.toList()..sort();

    return Column(
      children: [
        // Breadcrumb navigation
        if (_currentSeason != null) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B).withValues(alpha: 0.5),
              border: Border(
                bottom: BorderSide(
                  color: const Color(0xFF475569).withValues(alpha: 0.3),
                  width: 1,
                ),
              ),
            ),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () {
                    setBrowserState(() {
                      _currentSeason = null;
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6366F1).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: const Color(0xFF6366F1).withValues(alpha: 0.3),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.arrow_back_rounded,
                          color: Color(0xFF6366F1),
                          size: 16,
                        ),
                        const SizedBox(width: 4),
                        const Text(
                          'Back to Seasons',
                          style: TextStyle(
                            color: Color(0xFF6366F1),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Season $_currentSeason',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                // Selection counter
                if (selectedFiles.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${selectedFiles.length} selected',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],

        // Content area
        Expanded(
          child: _currentSeason == null
              ? _buildSeasonsList(
                  seasonMap: seasonMap,
                  sortedSeasons: sortedSeasons,
                  selectedFiles: selectedFiles,
                  added: added,
                  unrestrictingFiles: unrestrictingFiles,
                  showPlayButtons: showPlayButtons,
                  torrent: torrent,
                  setLocal: setLocal,
                  setBrowserState: setBrowserState,
                )
              : _buildEpisodesList(
                  seasonFiles: seasonMap[_currentSeason]!,
                  selectedFiles: selectedFiles,
                  added: added,
                  unrestrictingFiles: unrestrictingFiles,
                  showPlayButtons: showPlayButtons,
                  torrent: torrent,
                  setLocal: setLocal,
                ),
        ),
      ],
    );
  }

  Widget _buildSeasonsList({
    required Map<int, List<Map<String, dynamic>>> seasonMap,
    required List<int> sortedSeasons,
    required Set<int> selectedFiles,
    required Set<int> added,
    required Map<int, bool> unrestrictingFiles,
    required bool showPlayButtons,
    required RDTorrent torrent,
    required StateSetter setLocal,
    required StateSetter setBrowserState,
  }) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
      shrinkWrap: true,
      itemCount: sortedSeasons.length,
      itemBuilder: (context, seasonIndex) {
        final seasonNumber = sortedSeasons[seasonIndex];
        final seasonFiles = seasonMap[seasonNumber]!;

        // Sort episodes within season
        seasonFiles.sort((a, b) {
          final aEpisode = a['seriesInfo'].episode ?? 0;
          final bEpisode = b['seriesInfo'].episode ?? 0;
          return aEpisode.compareTo(bEpisode);
        });

        // Check if all episodes in this season are selected
        final seasonFileIndices = seasonFiles
            .map((f) => f['index'] as int)
            .toList();
        final allSelected = seasonFileIndices.every(
          (index) => selectedFiles.contains(index),
        );
        final someSelected = seasonFileIndices.any(
          (index) => selectedFiles.contains(index),
        );

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B).withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: const Color(0xFF475569).withValues(alpha: 0.3),
              width: 1,
            ),
          ),
          child: GestureDetector(
            onTap: () {
              setBrowserState(() {
                _currentSeason = seasonNumber;
              });
            },
            child: Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  // Season checkbox
                  GestureDetector(
                    onTap: () {
                      setLocal(() {
                        final seasonFileIndices = seasonFiles
                            .map((f) => f['index'] as int)
                            .toList();
                        if (allSelected) {
                          // Deselect all episodes in this season
                          selectedFiles.removeAll(seasonFileIndices);
                        } else {
                          // Select all episodes in this season
                          selectedFiles.addAll(seasonFileIndices);
                        }
                      });
                    },
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: allSelected
                            ? const Color(0xFF10B981)
                            : someSelected
                            ? const Color(0xFF10B981).withValues(alpha: 0.3)
                            : Colors.transparent,
                        border: Border.all(
                          color: allSelected || someSelected
                              ? const Color(0xFF10B981)
                              : Colors.grey[600]!,
                          width: 2,
                        ),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: allSelected
                          ? const Icon(
                              Icons.check,
                              color: Colors.white,
                              size: 16,
                            )
                          : someSelected
                          ? const Icon(
                              Icons.remove,
                              color: Colors.white,
                              size: 16,
                            )
                          : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Folder icon
                  Icon(
                    Icons.folder_rounded,
                    color: const Color(0xFF6366F1),
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  // Season title
                  Expanded(
                    child: Text(
                      'Season $seasonNumber',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  // Episode count
                  Text(
                    '${seasonFiles.length} episodes',
                    style: TextStyle(color: Colors.grey[400], fontSize: 14),
                  ),
                  const SizedBox(width: 8),
                  // Navigation arrow
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    color: Colors.grey[400],
                    size: 16,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildEpisodesList({
    required List<Map<String, dynamic>> seasonFiles,
    required Set<int> selectedFiles,
    required Set<int> added,
    required Map<int, bool> unrestrictingFiles,
    required bool showPlayButtons,
    required RDTorrent torrent,
    required StateSetter setLocal,
  }) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
      shrinkWrap: true,
      itemCount: seasonFiles.length,
      itemBuilder: (context, index) {
        final seasonFile = seasonFiles[index];
        final file = seasonFile['file'] as Map<String, dynamic>;
        final seriesInfo = seasonFile['seriesInfo'] as SeriesInfo;
        final fileIndex = seasonFile['index'] as int;

        String fileName = file['path']?.toString() ?? 'Unknown file';
        if (fileName.startsWith('/')) {
          fileName = fileName.split('/').last;
        }
        final fileSize = (file['bytes'] ?? 0) as int;
        final isVideo = FileUtils.isVideoFile(fileName);
        final isAdded = added.contains(fileIndex);
        final isSelected = selectedFiles.contains(fileIndex);
        final isUnrestricting = unrestrictingFiles[fileIndex] ?? false;

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          child: _buildModernFileCard(
            fileName: fileName,
            fileSize: fileSize,
            isVideo: isVideo,
            isAdded: isAdded,
            isSelected: isSelected,
            isUnrestricting: isUnrestricting,
            showPlayButtons: showPlayButtons,
            onPlay: () => _playFileOnDemand(
              torrent,
              fileIndex,
              setLocal,
              unrestrictingFiles,
            ),
            onAddToPlaylist: () =>
                _addFileToPlaylist(torrent, fileIndex, setLocal),
            onDownload: () => _downloadFileOnDemand(
              torrent,
              fileIndex,
              fileName,
              setLocal,
              added,
              unrestrictingFiles,
            ),
            onCopy: () => _copyFileLinkOnDemand(
              torrent,
              fileIndex,
              setLocal,
              unrestrictingFiles,
            ),
            onSelect: () {
              setLocal(() {
                if (isSelected) {
                  selectedFiles.remove(fileIndex);
                } else {
                  selectedFiles.add(fileIndex);
                }
              });
            },
            index: index,
            episodeInfo: seriesInfo.episode != null
                ? 'E${seriesInfo.episode.toString().padLeft(2, '0')}'
                : null,
          ),
        );
      },
    );
  }
}
