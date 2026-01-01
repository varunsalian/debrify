import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:android_intent_plus/android_intent.dart';
import '../models/playlist_view_mode.dart';
import '../models/rd_torrent.dart';
import '../models/rd_file_node.dart';
import '../models/debrid_download.dart';
import '../services/debrid_service.dart';
import '../services/storage_service.dart';
import '../utils/formatters.dart';
import '../utils/file_utils.dart';
import '../utils/series_parser.dart';
import '../utils/rd_folder_tree_builder.dart';
import 'video_player_screen.dart';
import '../services/video_player_launcher.dart';
import '../services/download_service.dart';
import '../services/android_native_downloader.dart';
import '../services/main_page_bridge.dart';
import 'dart:ui'; // Added for ImageFilter
import '../widgets/file_selection_dialog.dart';

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

enum _FolderViewMode { raw, sortedAZ, seriesArrange }

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

  // Folder navigation state
  String? _currentTorrentId;
  RDTorrent? _currentTorrent;
  List<String> _folderPath = []; // e.g., ["Season 1", "Episodes"]
  RDFileNode? _currentFolderTree;
  List<RDFileNode>? _currentViewNodes; // Current folder contents
  bool _isLoadingFolder = false;

  // View mode state
  final Map<String, _FolderViewMode> _torrentViewModes = {};

  // Magnet input
  final TextEditingController _magnetController = TextEditingController();
  bool _isAddingMagnet = false;

  // Link input
  final TextEditingController _linkController = TextEditingController();
  bool _isAddingLink = false;

  // TV/DPAD navigation
  bool _isTelevision = false;
  final FocusNode _backButtonFocusNode = FocusNode(debugLabel: 'rd-back');
  final FocusNode _refreshButtonFocusNode = FocusNode(debugLabel: 'rd-refresh');
  final FocusNode _viewModeDropdownFocusNode = FocusNode(debugLabel: 'rd-view-mode');

  @override
  void initState() {
    super.initState();
    _checkIfTelevision();
    _loadApiKeyAndData();
    _torrentScrollController.addListener(_onTorrentScroll);
    _downloadScrollController.addListener(_onDownloadScroll);

    // Register back navigation handler for folder navigation (tab screen)
    MainPageBridge.registerTabBackHandler('realdebrid', _handleBackNavigation);

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
          // Navigate into the torrent folder instead of showing dialog
          await _navigateIntoTorrent(widget.initialTorrentForOptions!);
        }
      }
    });
  }

  Future<void> _checkIfTelevision() async {
    final isTv = await AndroidNativeDownloader.isTelevision();
    if (mounted) {
      setState(() {
        _isTelevision = isTv;
      });
    }
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
    // Unregister back navigation handler
    MainPageBridge.unregisterTabBackHandler('realdebrid');

    _torrentScrollController.dispose();
    _downloadScrollController.dispose();
    _magnetController.dispose();
    _linkController.dispose();

    // Dispose focus nodes
    _backButtonFocusNode.dispose();
    _refreshButtonFocusNode.dispose();
    _viewModeDropdownFocusNode.dispose();

    super.dispose();
  }

  /// Handle back navigation for folder browsing.
  /// Returns true if handled (navigated up), false if at root level.
  bool _handleBackNavigation() {
    // If came from torrent search "Open in RealDebrid" flow and at torrent root,
    // go back to torrent search instead of torrents list
    if (MainPageBridge.returnToTorrentSearchOnBack &&
        _folderPath.isEmpty &&
        _currentTorrentId != null) {
      MainPageBridge.returnToTorrentSearchOnBack = false;
      MainPageBridge.switchTab?.call(0); // Torrent search is index 0
      return true;
    }
    if (_currentTorrentId != null) {
      _navigateUp();
      return true; // We handled the back press
    }
    return false; // Not in folder mode, let app handle it
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
      // Multiple links - navigate into torrent folder view
      if (mounted) {
        await _navigateIntoTorrent(torrent);
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
            await VideoPlayerLauncher.push(
              context,
              VideoPlayerLaunchArgs(
                videoUrl: downloadLink,
                title: torrent.filename,
                subtitle: Formatters.formatFileSize(torrent.bytes),
                viewMode: PlaylistViewMode.sorted, // Single file - not series
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
      // Multiple files - navigate into torrent folder view
      if (mounted) {
        await _navigateIntoTorrent(torrent);
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
        await VideoPlayerLauncher.push(
          context,
          VideoPlayerLaunchArgs(
            videoUrl: download.download,
            title: download.filename,
            subtitle: Formatters.formatFileSize(download.filesize),
            viewMode: PlaylistViewMode.sorted, // Single file - not series
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Added to downloads')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to start download: $e')));
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

  // Removed deprecated _showMultipleLinksDialog method
  // The method has been replaced with _navigateIntoTorrent for multi-file torrents

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

  // ========== Folder Navigation Methods ==========

  /// Navigate into a torrent (shows root level folders/files)
  Future<void> _navigateIntoTorrent(RDTorrent torrent) async {
    if (_apiKey == null) return;

    setState(() {
      _isLoadingFolder = true;
    });

    try {
      // Get torrent info to check for RAR archives
      final torrentInfo = await DebridService.getTorrentInfo(_apiKey!, torrent.id);
      final files = (torrentInfo['files'] as List<dynamic>?)?.map((f) => f as Map<String, dynamic>).toList() ?? [];
      final links = (torrentInfo['links'] as List<dynamic>?) ?? [];

      // Check if this is a RAR archive
      final isRarArchive = RDFolderTreeBuilder.isRarArchive(files, links);

      if (isRarArchive) {
        // Show a message that this cannot be browsed
        setState(() {
          _isLoadingFolder = false;
        });

        // Show dialog explaining RAR archives and offering to download
        if (mounted) {
          await showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: const Color(0xFF1E293B),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF59E0B),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.archive, color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'RAR Archive Detected',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              content: Text(
                'This is a RAR archive that Real-Debrid has not extracted yet. '
                'The folder structure shown represents the archive contents, but only the RAR file itself can be downloaded.\n\n'
                'You can download the RAR archive to extract it locally.',
                style: const TextStyle(color: Colors.grey),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
                ),
                TextButton(
                  onPressed: () async {
                    Navigator.of(ctx).pop();
                    // Download the single RAR file
                    if (links.isNotEmpty) {
                      try {
                        final unrestrictResult = await DebridService.unrestrictLink(_apiKey!, links[0]);
                        final downloadUrl = unrestrictResult['download'] as String?;
                        if (downloadUrl != null) {
                          _copyToClipboard(downloadUrl);
                        }
                      } catch (e) {
                        _showError('Failed to get download link: ${e.toString()}');
                      }
                    }
                  },
                  style: TextButton.styleFrom(foregroundColor: const Color(0xFF60A5FA)),
                  child: const Text('Copy Download Link'),
                ),
              ],
            ),
          );
        }
        return;
      }

      // Not a RAR archive - proceed with normal folder navigation
      // Get the folder tree for this torrent
      final folderTree = await DebridService.getTorrentFolderTree(
        _apiKey!,
        torrent.id,
      );
      final rootNodes = RDFolderTreeBuilder.getRootLevelNodes(folderTree);

      // Initialize view mode for this torrent if not already set
      _torrentViewModes.putIfAbsent(torrent.id, () => _FolderViewMode.raw);

      // Apply view mode transformation to root nodes
      final mode = _torrentViewModes[torrent.id]!;
      List<RDFileNode> transformedNodes;
      switch (mode) {
        case _FolderViewMode.raw:
          transformedNodes = rootNodes;
          break;
        case _FolderViewMode.sortedAZ:
          transformedNodes = _applySortedView(rootNodes);
          break;
        case _FolderViewMode.seriesArrange:
          transformedNodes = _applySeriesArrangedView(rootNodes);
          break;
      }

      setState(() {
        _currentTorrentId = torrent.id;
        _currentTorrent = torrent;
        _currentFolderTree = folderTree;
        _currentViewNodes = transformedNodes;
        _folderPath = [];
        _isLoadingFolder = false;
      });

    } catch (e) {
      setState(() {
        _isLoadingFolder = false;
      });
      _showError('Failed to load torrent contents: ${e.toString()}');
    }
  }

  /// Navigate into a folder
  void _navigateIntoFolder(RDFileNode folder) {
    if (!folder.isFolder) return;

    // Apply view mode to folder children
    // NOTE: Series Arrange only makes sense at root level (it creates virtual Season folders)
    // When inside any folder, show files in sorted or raw view
    final mode = _getCurrentViewMode();
    List<RDFileNode> transformedChildren;

    if (mode == _FolderViewMode.seriesArrange) {
      // Inside a folder with Series Arrange mode: show files sorted by name
      transformedChildren = _applySortedView(folder.children);
    } else {
      switch (mode) {
        case _FolderViewMode.raw:
          transformedChildren = folder.children;
          break;
        case _FolderViewMode.sortedAZ:
          transformedChildren = _applySortedView(folder.children);
          break;
        case _FolderViewMode.seriesArrange:
          // Should never reach here
          transformedChildren = folder.children;
          break;
      }
    }

    setState(() {
      _folderPath.add(folder.name);
      _currentViewNodes = transformedChildren;
    });

  }

  /// Navigate up one level
  void _navigateUp() {
    if (_folderPath.isEmpty && _currentTorrentId != null) {
      // Go back to torrents list
      setState(() {
        _currentTorrentId = null;
        _currentTorrent = null;
        _currentFolderTree = null;
        _currentViewNodes = null;
        _folderPath = [];
      });

    } else if (_folderPath.isNotEmpty && _currentFolderTree != null) {
      // Go up one folder level
      _folderPath.removeLast();

      // Get raw nodes at the new path
      List<RDFileNode> rawNodes;
      if (_folderPath.isEmpty) {
        rawNodes = RDFolderTreeBuilder.getRootLevelNodes(_currentFolderTree!);
      } else {
        // Find the folder node at the current path
        RDFileNode currentNode = _currentFolderTree!;
        for (final folderName in _folderPath) {
          final childFolder = currentNode.children.cast<RDFileNode?>().firstWhere(
            (node) => node?.name == folderName && node?.isFolder == true,
            orElse: () => null,
          );
          if (childFolder != null) {
            currentNode = childFolder;
          } else {
            // Folder not found - reset to root
            _folderPath.clear();
            rawNodes = RDFolderTreeBuilder.getRootLevelNodes(_currentFolderTree!);
            // Apply view mode and set state
            final mode = _getCurrentViewMode();
            List<RDFileNode> transformedNodes;
            switch (mode) {
              case _FolderViewMode.raw:
                transformedNodes = rawNodes;
                break;
              case _FolderViewMode.sortedAZ:
                transformedNodes = _applySortedView(rawNodes);
                break;
              case _FolderViewMode.seriesArrange:
                transformedNodes = _applySeriesArrangedView(rawNodes);
                break;
            }
            setState(() {
              _currentViewNodes = transformedNodes;
            });
            return;
          }
        }
        rawNodes = currentNode.children;
      }

      // Apply view mode transformation
      // NOTE: Series Arrange only applies at root level
      final mode = _getCurrentViewMode();
      List<RDFileNode> transformedNodes;

      if (mode == _FolderViewMode.seriesArrange && _folderPath.isNotEmpty) {
        // Still inside a folder after going up - use sorted view
        transformedNodes = _applySortedView(rawNodes);
      } else {
        switch (mode) {
          case _FolderViewMode.raw:
            transformedNodes = rawNodes;
            break;
          case _FolderViewMode.sortedAZ:
            transformedNodes = _applySortedView(rawNodes);
            break;
          case _FolderViewMode.seriesArrange:
            transformedNodes = _applySeriesArrangedView(rawNodes);
            break;
        }
      }

      setState(() {
        _currentViewNodes = transformedNodes;
      });

    }
  }

  String _getCurrentFolderTitle() {
    if (_currentTorrentId == null) return '';
    if (_folderPath.isEmpty) {
      return _currentTorrent?.filename ?? 'Torrent Files';
    }
    return _folderPath.last;
  }

  /// Detect if current folder contains series episodes
  /// Checks recursively in subfolders as well
  bool _detectSeriesPattern(List<RDFileNode> nodes) {
    // Collect video files recursively from current level and subfolders
    final videoFiles = _collectVideoFilesRecursively(nodes);

    if (videoFiles.length < 3) return false;

    final filenames = videoFiles.map((n) => n.name).toList();
    final analysis = SeriesParser.analyzePlaylistConfidence(filenames);
    return analysis.classification == PlaylistClassification.SERIES;
  }

  /// Recursively collect all video files from nodes and their subfolders
  List<RDFileNode> _collectVideoFilesRecursively(List<RDFileNode> nodes) {
    final videoFiles = <RDFileNode>[];

    for (final node in nodes) {
      if (node.isFolder) {
        // Recursively collect from subfolder
        videoFiles.addAll(_collectVideoFilesRecursively(node.children));
      } else if (FileUtils.isVideoFile(node.name)) {
        // Add video file
        videoFiles.add(node);
      }
    }

    return videoFiles;
  }

  /// Apply sorted view (folders first A-Z, then files A-Z)
  /// Special handling for numbered folders and files to sort numerically
  List<RDFileNode> _applySortedView(List<RDFileNode> nodes) {
    final folders = nodes.where((n) => n.isFolder).toList();
    final files = nodes.where((n) => !n.isFolder).toList();

    // Sort folders with special handling for numbered folders
    folders.sort((a, b) {
      // Extract numbers if folders are named "Season X", "Chapter X", etc.
      final aNum = _extractSeasonNumber(a.name);
      final bNum = _extractSeasonNumber(b.name);

      // If both have numbers, sort numerically
      if (aNum != null && bNum != null) {
        return aNum.compareTo(bNum);
      }

      // If only one has a number, numbered folders come first
      if (aNum != null) return -1;
      if (bNum != null) return 1;

      // Otherwise sort alphabetically
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

    // Sort files with special handling for files starting with numbers
    files.sort((a, b) {
      // Extract leading numbers from filenames (e.g., "10. Video.mp4" -> 10)
      final aNum = _extractLeadingNumber(a.name);
      final bNum = _extractLeadingNumber(b.name);

      // If both start with numbers, sort numerically
      if (aNum != null && bNum != null) {
        return aNum.compareTo(bNum);
      }

      // If only one starts with a number, numbered files come first
      if (aNum != null) return -1;
      if (bNum != null) return 1;

      // Otherwise sort alphabetically
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

    return [...folders, ...files];
  }

  /// Extract number from folder name for numerical sorting
  /// Handles: "1. Introduction", "10. Chapter", "Season 10", "Chapter_12", "Episode 5", "Part 3", etc.
  /// Returns null if no number pattern found
  int? _extractSeasonNumber(String folderName) {
    // Try multiple patterns in order of specificity
    final patterns = [
      // Leading numbers: "1. ", "10-", "5_", etc.
      RegExp(r'^(\d+)[\s._-]'),
      // Season X, Season_X, Season-X
      RegExp(r'season[\s_-]*(\d+)', caseSensitive: false),
      // Chapter X, Chapter_X, Chapter-X
      RegExp(r'chapter[\s_-]*(\d+)', caseSensitive: false),
      // Episode X, Episode_X, Episode-X
      RegExp(r'episode[\s_-]*(\d+)', caseSensitive: false),
      // Part X, Part_X, Part-X
      RegExp(r'part[\s_-]*(\d+)', caseSensitive: false),
      // Any word followed by number at the start (e.g., "Lesson_5", "Module-3")
      RegExp(r'^[a-z]+[\s_-]*(\d+)', caseSensitive: false),
    ];

    final lowerName = folderName.toLowerCase();

    for (final pattern in patterns) {
      final match = pattern.firstMatch(lowerName);
      if (match != null && match.groupCount >= 1) {
        return int.tryParse(match.group(1)!);
      }
    }

    return null;
  }

  /// Extract leading number from filename for numerical sorting
  /// Handles: "10. Video.mp4", "9 - Title.mkv", "05_Episode.mp4", etc.
  /// Returns null if filename doesn't start with a number
  int? _extractLeadingNumber(String filename) {
    // Match numbers at the start of filename (before any separator like . - _ space)
    // Examples: "10.", "9 -", "05_", "123-"
    final pattern = RegExp(r'^(\d+)[\s._-]');
    final match = pattern.firstMatch(filename);

    if (match != null && match.groupCount >= 1) {
      return int.tryParse(match.group(1)!);
    }

    return null;
  }

  /// Apply series arranged view (create virtual Season folders)
  List<RDFileNode> _applySeriesArrangedView(List<RDFileNode> nodes) {
    final folders = nodes.where((n) => n.isFolder).toList();
    final files = nodes.where((n) => !n.isFolder).toList();

    // Parse files for series info
    final videoFiles = files.where((f) => FileUtils.isVideoFile(f.name)).toList();
    final nonVideoFiles = files.where((f) => !FileUtils.isVideoFile(f.name)).toList();

    if (videoFiles.isEmpty) return nodes;

    final filenames = videoFiles.map((f) => f.name).toList();

    try {
      final parsedInfos = SeriesParser.parsePlaylist(filenames);

      // Group by season
      final Map<int, List<RDFileNode>> seasonMap = {};
      for (int i = 0; i < videoFiles.length; i++) {
        final info = parsedInfos[i];
        if (info.isSeries && info.season != null) {
          seasonMap.putIfAbsent(info.season!, () => []);
          seasonMap[info.season!]!.add(videoFiles[i]);
        } else {
          // If not parsed as series, default to Season 1
          seasonMap.putIfAbsent(1, () => []);
          seasonMap[1]!.add(videoFiles[i]);
        }
      }

      // Create virtual season folders
      final seasonFolders = seasonMap.entries.map((entry) {
        final seasonNum = entry.key;
        final seasonFiles = entry.value;

        // Sort episodes within season by episode number
        seasonFiles.sort((a, b) {
          final aInfo = SeriesParser.parseFilename(a.name);
          final bInfo = SeriesParser.parseFilename(b.name);
          final aEp = aInfo.episode ?? 0;
          final bEp = bInfo.episode ?? 0;
          return aEp.compareTo(bEp);
        });

        return RDFileNode.folder(
          name: seasonNum == 0 ? 'Season 0 - Specials' : 'Season $seasonNum',
          children: seasonFiles,
        );
      }).toList();

      // Sort season folders by season number
      seasonFolders.sort((a, b) {
        final aNum = int.tryParse(a.name.replaceAll(RegExp(r'\D'), '')) ?? 0;
        final bNum = int.tryParse(b.name.replaceAll(RegExp(r'\D'), '')) ?? 0;
        return aNum.compareTo(bNum);
      });

      return [...folders, ...seasonFolders, ...nonVideoFiles];
    } catch (e) {
      debugPrint('Series arrangement failed: $e');
      return _applySortedView(nodes); // Fallback to sorted view
    }
  }

  /// Get current view mode for active torrent
  _FolderViewMode _getCurrentViewMode() {
    if (_currentTorrentId == null) return _FolderViewMode.raw;
    return _torrentViewModes[_currentTorrentId] ?? _FolderViewMode.raw;
  }

  /// Set view mode and refresh display
  void _setViewMode(_FolderViewMode mode) {
    if (_currentTorrentId == null || _currentViewNodes == null) return;

    // Get raw nodes based on current path
    List<RDFileNode> rawNodes;
    if (_folderPath.isEmpty && _currentFolderTree != null) {
      rawNodes = RDFolderTreeBuilder.getRootLevelNodes(_currentFolderTree!);
    } else if (_currentFolderTree != null) {
      // Navigate to current path to get raw nodes
      RDFileNode currentNode = _currentFolderTree!;
      for (final folderName in _folderPath) {
        final childFolder = currentNode.children.cast<RDFileNode?>().firstWhere(
          (node) => node?.name == folderName && node?.isFolder == true,
          orElse: () => null,
        );
        if (childFolder != null) {
          currentNode = childFolder;
        } else {
          setState(() {
            _currentViewNodes = [];
          });
          return;
        }
      }
      rawNodes = currentNode.children;
    } else {
      return;
    }

    // If user selected Series Arrange, detect if content is actually a series
    if (mode == _FolderViewMode.seriesArrange) {
      final isSeries = _detectSeriesPattern(rawNodes);

      if (!isSeries) {
        // Not a series - show snackbar and fallback to sorted view
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('No series detected in this folder. Switching to Sort (A-Z) view.'),
            duration: const Duration(seconds: 3),
            backgroundColor: const Color(0xFF1E293B),
            behavior: SnackBarBehavior.floating,
          ),
        );

        // Switch to sorted view instead
        setState(() {
          _torrentViewModes[_currentTorrentId!] = _FolderViewMode.sortedAZ;
          _currentViewNodes = _applySortedView(rawNodes);
        });
        return;
      }
    }

    // Apply transformation based on mode
    setState(() {
      _torrentViewModes[_currentTorrentId!] = mode;

      switch (mode) {
        case _FolderViewMode.raw:
          _currentViewNodes = rawNodes;
          break;
        case _FolderViewMode.sortedAZ:
          _currentViewNodes = _applySortedView(rawNodes);
          break;
        case _FolderViewMode.seriesArrange:
          _currentViewNodes = _applySeriesArrangedView(rawNodes);
          break;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // If in folder browsing mode, show folder view
    if (_currentTorrentId != null) {
      return _buildFolderBrowserScaffold();
    }

    final Widget content = _selectedView == _DebridDownloadsView.torrents
        ? _buildTorrentContent()
        : _buildDownloadContent();

    return Scaffold(
      body: FocusTraversalGroup(
        policy: OrderedTraversalPolicy(),
        child: Column(
          children: [
            const SizedBox(height: 8),
            Expanded(child: content),
          ],
        ),
      ),
    );
  }

  Widget _buildViewModeDropdown() {
    final theme = Theme.of(context);
    final mode = _getCurrentViewMode();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        border: Border(
          bottom: BorderSide(
            color: theme.dividerColor.withValues(alpha: 0.1),
            width: 1,
          ),
        ),
      ),
      child: DropdownButtonFormField<_FolderViewMode>(
        focusNode: _viewModeDropdownFocusNode,
        autofocus: true,
        isExpanded: true,
        value: mode,
        decoration: InputDecoration(
          labelText: 'View Mode',
          prefixIcon: Icon(
            mode == _FolderViewMode.raw
                ? Icons.view_list
                : mode == _FolderViewMode.sortedAZ
                    ? Icons.sort_by_alpha
                    : Icons.video_library,
            color: theme.colorScheme.primary,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          filled: true,
          fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        ),
        items: const [
          DropdownMenuItem(
            value: _FolderViewMode.raw,
            child: Text('Raw'),
          ),
          DropdownMenuItem(
            value: _FolderViewMode.sortedAZ,
            child: Text('Sort (A-Z)'),
          ),
          DropdownMenuItem(
            value: _FolderViewMode.seriesArrange,
            child: Text('Series Arrange'),
          ),
        ],
        onChanged: (value) {
          if (value != null) _setViewMode(value);
        },
      ),
    );
  }

  Widget _buildFolderBrowserScaffold() {
    // Back navigation is handled via MainPageBridge.handleBackNavigation
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          focusNode: _backButtonFocusNode,
          icon: const Icon(Icons.arrow_back),
          onPressed: () => _handleBackNavigation(),
        ),
        title: Text(_getCurrentFolderTitle()),
        actions: [
          IconButton(
            focusNode: _refreshButtonFocusNode,
            icon: const Icon(Icons.refresh),
            onPressed: _currentTorrent != null
                ? () => _navigateIntoTorrent(_currentTorrent!)
                : null,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildViewModeDropdown(),
          Expanded(
            child: FocusTraversalGroup(
              policy: OrderedTraversalPolicy(),
              child: _buildFolderContentsView(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFolderContentsView() {
    if (_isLoadingFolder) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_currentViewNodes == null || _currentViewNodes!.isEmpty) {
      return const Center(child: Text('Empty folder'));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _currentViewNodes!.length,
      cacheExtent: 200.0, // Pre-cache items for smoother scrolling
      addRepaintBoundaries: true, // Optimize repainting
      itemBuilder: (context, index) {
        final node = _currentViewNodes![index];
        return RepaintBoundary(
          child: _buildNodeCard(node, index),
        );
      },
    );
  }

  Widget _buildNodeCard(RDFileNode node, int index) {
    final isFolder = node.isFolder;
    final isVideo = !isFolder && FileUtils.isVideoFile(node.name);
    final borderColor = Colors.white.withValues(alpha: 0.08);
    final glowColor = const Color(0xFF6366F1).withValues(alpha: 0.08);

    final cardContent = Container(
      margin: const EdgeInsets.only(bottom: 12),
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
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: glowColor,
            blurRadius: 20,
            offset: const Offset(0, 4),
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
                  children: [
                    Icon(
                      isFolder
                          ? Icons.folder
                          : (isVideo
                                ? Icons.play_circle_outline
                                : Icons.insert_drive_file),
                      color: isFolder
                          ? Colors.amber
                          : (isVideo ? Colors.blue : Colors.grey),
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            node.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                              color: Colors.white,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            isFolder
                                ? '${RDFolderTreeBuilder.countFiles(node)} files • ${Formatters.formatFileSize(node.totalBytes)}'
                                : Formatters.formatFileSize(node.bytes ?? 0),
                            style: TextStyle(
                              color: Colors.grey[400],
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Action buttons (always show for all files)
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
              child: Row(
                children: [
                  if (isFolder) ...[
                    Expanded(
                      child: FilledButton.icon(
                        autofocus: index == 0,
                        onPressed: () => _navigateIntoFolder(node),
                        icon: const Icon(Icons.folder_open, size: 18),
                        label: const Text('Open'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => _playFolder(node),
                        icon: const Icon(Icons.play_arrow, size: 18),
                        label: const Text('Play'),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.green.shade700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ] else if (isVideo) ...[
                    Expanded(
                      child: FilledButton.icon(
                        autofocus: index == 0,
                        onPressed: () => _playFile(node),
                        icon: const Icon(Icons.play_arrow, size: 18),
                        label: const Text('Play'),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ] else ...[
                    // Non-video files get a Download button
                    Expanded(
                      child: FilledButton.icon(
                        autofocus: index == 0,
                        onPressed: () => _downloadFile(node),
                        icon: const Icon(Icons.download, size: 18),
                        label: const Text('Download'),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],

                  // Three-dot menu
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert),
                    tooltip: 'More options',
                    onSelected: (value) {
                      if (value == 'download') {
                        isFolder ? _downloadFolder(node) : _downloadFile(node);
                      } else if (value == 'add_to_playlist') {
                        isFolder
                            ? _addFolderToPlaylist(node)
                            : _addNodeFileToPlaylist(node);
                      } else if (value == 'copy_link') {
                        _copyNodeDownloadLink(node);
                      } else if (value == 'open_external') {
                        _openWithExternalPlayer(node);
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'download',
                        child: Row(
                          children: [
                            Icon(Icons.download, size: 18, color: Colors.green),
                            SizedBox(width: 12),
                            Text('Download'),
                          ],
                        ),
                      ),
                      // Only show "Add to Playlist" for video files or folders (not for subtitle/other files)
                      if (isFolder || isVideo)
                        const PopupMenuItem(
                          value: 'add_to_playlist',
                          child: Row(
                            children: [
                              Icon(
                                Icons.playlist_add,
                                size: 18,
                                color: Colors.blue,
                              ),
                              SizedBox(width: 12),
                              Text('Add to Playlist'),
                            ],
                          ),
                        ),
                      // Only show "Open with External Player" for video files, not folders
                      if (isVideo && !isFolder)
                        const PopupMenuItem(
                          value: 'open_external',
                          child: Row(
                            children: [
                              Icon(Icons.open_in_new, size: 18, color: Colors.orange),
                              SizedBox(width: 12),
                              Text('Open with External Player'),
                            ],
                          ),
                        ),
                      // Only show "Copy Download Link" for files, not folders
                      if (!isFolder)
                        const PopupMenuItem(
                          value: 'copy_link',
                          child: Row(
                            children: [
                              Icon(Icons.link, size: 18, color: Colors.grey),
                              SizedBox(width: 12),
                              Text('Copy Download Link'),
                            ],
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );

    return cardContent;
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
                autofocus: true,
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
          cacheExtent: 200.0, // Pre-cache items for smoother scrolling
          addRepaintBoundaries: true, // Optimize repainting
          itemBuilder: (context, index) {
            if (index == _torrents.length) {
              // Loading more indicator
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              );
            }

            final torrent = _torrents[index];
            return KeyedSubtree(
              key: ValueKey(torrent.id),
              child: _buildTorrentCard(torrent, index),
            );
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
                autofocus: true,
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
          cacheExtent: 200.0, // Pre-cache items for smoother scrolling
          addRepaintBoundaries: true, // Optimize repainting
          itemBuilder: (context, index) {
            if (index == _downloads.length) {
              // Loading more indicator
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              );
            }

            final download = _downloads[index];
            return KeyedSubtree(
              key: ValueKey(download.id),
              child: _buildDownloadCard(download),
            );
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

  Widget _buildTorrentCard(RDTorrent torrent, int index) {
    // Always treat torrents as folders - user needs to "Open" to see actual files
    // Never show Play button at root level
    final cardContent = Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top section: Icon + Name + Metadata
            Row(
              children: [
                Icon(
                  Icons.folder, // Always show folder icon
                  color: Colors.amber,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        torrent.filename,
                        style: const TextStyle(
                          fontWeight: FontWeight.w500,
                          fontSize: 16,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            Formatters.formatFileSize(torrent.bytes),
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '•',
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${torrent.links.length} ${torrent.links.length == 1 ? 'file' : 'files'}',
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '•',
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _formatDate(torrent.added),
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Bottom section: Action buttons
            Row(
              children: [
                // Always show Open and Play buttons for all torrents
                Expanded(
                  child: FilledButton.icon(
                    autofocus: index == 0,
                    onPressed: () => _navigateIntoTorrent(torrent),
                    icon: const Icon(Icons.folder_open, size: 18),
                    label: const Text('Open'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _handlePlayMultiFileTorrent(torrent),
                    icon: const Icon(Icons.play_arrow, size: 18),
                    label: const Text('Play'),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.green.shade700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // Three-dot menu
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert),
                  tooltip: 'More options',
                  onSelected: (value) {
                    if (value == 'download') {
                      _handleDownloadTorrent(torrent);
                    } else if (value == 'add_to_playlist') {
                      _handleAddTorrentToPlaylist(torrent);
                    } else if (value == 'delete') {
                      _handleDeleteTorrent(torrent);
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'download',
                      child: Row(
                        children: [
                          Icon(Icons.download, size: 18, color: Colors.green),
                          SizedBox(width: 12),
                          Text('Download'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'add_to_playlist',
                      child: Row(
                        children: [
                          Icon(
                            Icons.playlist_add,
                            size: 18,
                            color: Colors.blue,
                          ),
                          SizedBox(width: 12),
                          Text('Add to Playlist'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(
                            Icons.delete_outline,
                            size: 18,
                            color: Colors.red,
                          ),
                          SizedBox(width: 12),
                          Text('Delete'),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );

    return cardContent;
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

    try {
      // Show loading
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

      // Get torrent info to access files and links
      final torrentInfo = await DebridService.getTorrentInfo(_apiKey!, torrent.id);
      final allFiles = (torrentInfo['files'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      final links = (torrentInfo['links'] as List).cast<String>();

      // Filter to only selected files (files that were selected when adding to RD)
      // Only selected files have corresponding links and can be downloaded
      final files = allFiles.where((file) => file['selected'] == 1).toList();

      if (mounted) Navigator.of(context).pop();

      if (files.isEmpty || links.isEmpty) {
        _showError('No files available for download');
        return;
      }

      // Format files for FileSelectionDialog
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
            torrentName: torrent.filename,
            onDownload: (selectedFiles) {
              if (selectedFiles.isEmpty) return;
              _downloadSelectedRealDebridFiles(
                selectedFiles: selectedFiles,
                links: links,
                folderName: torrent.filename,
              );
            },
          );
        },
      );
    } catch (e) {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      _showError('Failed to load torrent: $e');
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
            'title': FileUtils.cleanPlaylistTitle(torrent.filename),
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
        'title': FileUtils.cleanPlaylistTitle(torrent.filename),
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
    showDialog(
      context: context,
      builder: (sheetContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: BackdropFilter(
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
                borderRadius: BorderRadius.circular(24),
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
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
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
    final canStream = download.streamable == 1;
    final isVideo = FileUtils.isVideoFile(download.filename);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  canStream || isVideo
                      ? Icons.play_circle_outline
                      : Icons.insert_drive_file,
                  color: canStream || isVideo ? Colors.blue : Colors.grey,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        download.filename,
                        style: const TextStyle(
                          fontWeight: FontWeight.w500,
                          fontSize: 16,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            Formatters.formatFileSize(download.filesize),
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text('•', style: TextStyle(color: Colors.grey.shade600)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              download.host,
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: 13,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                if (canStream) ...[
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => _handlePlayDownload(download),
                      icon: const Icon(Icons.play_arrow, size: 18),
                      label: const Text('Play'),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _handleQueueDownload(download),
                    icon: const Icon(Icons.download, size: 18),
                    label: const Text('Download'),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.green.shade700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // 3-dot menu
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert),
                  tooltip: 'More options',
                  onSelected: (value) {
                    if (value == 'copy_link') {
                      _handleDownloadAction(download);
                    } else if (value == 'delete') {
                      _handleDeleteDownload(download);
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'copy_link',
                      child: Row(
                        children: [
                          Icon(Icons.link, size: 18, color: Colors.orange),
                          SizedBox(width: 12),
                          Text('Copy Link'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete_outline, size: 18, color: Colors.red),
                          SizedBox(width: 12),
                          Text('Delete'),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
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

      // isSeries is already detected earlier in this function (line 3126)
      await VideoPlayerLauncher.push(
        context,
        VideoPlayerLaunchArgs(
          videoUrl: initialVideoUrl,
          title: torrent.filename,
          subtitle: '${entries.length} files',
          playlist: entries,
          startIndex: 0,
          viewMode: isSeries ? PlaylistViewMode.series : PlaylistViewMode.sorted,
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
            Focus(
              onKeyEvent: (node, event) {
                if (event is KeyDownEvent &&
                    event.logicalKey == LogicalKeyboardKey.arrowDown) {
                  node.nextFocus();
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: TextField(
                controller: _linkController,
                autofocus: true,
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
            await VideoPlayerLauncher.push(
              context,
              VideoPlayerLaunchArgs(
                videoUrl: downloadLink,
                title: torrent.filename,
                subtitle: 'File ${index + 1}',
                viewMode: PlaylistViewMode.sorted, // Single file - not series
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
          'title': FileUtils.cleanPlaylistTitle(torrent.filename),
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
    // Track current season for navigation
    int? _currentSeason;

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
          currentSeason: _currentSeason,
          onSeasonChanged: (season) {
            setBrowserState(() {
              _currentSeason = season;
            });
          },
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
    required int? currentSeason,
    required Function(int?) onSeasonChanged,
  }) {
    // Use the passed currentSeason instead of defining a local one
    final _currentSeason = currentSeason;
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
                      onSeasonChanged(null);
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
                  onSeasonChanged: onSeasonChanged,
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
    required Function(int?) onSeasonChanged,
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
          key: ValueKey('season-$seasonNumber'),
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
                onSeasonChanged(seasonNumber);
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
          key: ValueKey('file-$fileIndex'),
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

  // ========== File/Folder Action Methods ==========

  /// Play a single file from the folder browser
  Future<void> _playFile(RDFileNode file) async {
    if (_apiKey == null || _currentTorrentId == null) return;

    try {
      // Show loading dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );

      // Get download URL for the file
      final downloadUrl = await DebridService.getFileDownloadUrl(
        _apiKey!,
        _currentTorrentId!,
        file.linkIndex,
      );

      // Close loading dialog
      if (mounted) Navigator.of(context).pop();

      // Launch video player
      await VideoPlayerLauncher.push(
        context,
        VideoPlayerLaunchArgs(
          videoUrl: downloadUrl,
          title: file.name,
          subtitle: Formatters.formatFileSize(file.bytes ?? 0),
          viewMode: PlaylistViewMode.sorted, // Single file - not series
        ),
      );
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop();
        _showError('Failed to play file: ${e.toString()}');
      }
    }
  }

  /// Play all videos in a folder with a playlist
  Future<void> _playFolder(RDFileNode folder) async {
    if (_apiKey == null || _currentTorrentId == null || _currentTorrent == null) return;

    try {
      // Show loading dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );

      // Collect all video files in the folder
      final videoFiles = RDFolderTreeBuilder.collectVideoFiles(folder);
      if (videoFiles.isEmpty) {
        if (mounted) {
          Navigator.of(context).pop();
          _showError('No video files found in this folder');
        }
        return;
      }

      // Sort videos using series parser to handle episode ordering
      final fileNames = videoFiles.map((f) => f.name).toList();
      final parsedVideos = SeriesParser.parsePlaylist(fileNames);

      // Sort by season and episode if available, otherwise by name
      final sortedVideoFiles = List<RDFileNode>.from(videoFiles)
        ..sort((a, b) {
          final aIndex = fileNames.indexOf(a.name);
          final bIndex = fileNames.indexOf(b.name);

          if (aIndex >= 0 &&
              aIndex < parsedVideos.length &&
              bIndex >= 0 &&
              bIndex < parsedVideos.length) {
            final aInfo = parsedVideos[aIndex];
            final bInfo = parsedVideos[bIndex];

            // Compare seasons first
            final seasonCompare = (aInfo.season ?? 0).compareTo(
              bInfo.season ?? 0,
            );
            if (seasonCompare != 0) return seasonCompare;

            // Then compare episodes
            final episodeCompare = (aInfo.episode ?? 0).compareTo(
              bInfo.episode ?? 0,
            );
            if (episodeCompare != 0) return episodeCompare;
          }

          // Finally compare by filename
          return a.name.compareTo(b.name);
        });

      // Get the first video URL to start playing
      final firstVideoUrl = await DebridService.getFileDownloadUrl(
        _apiKey!,
        _currentTorrentId!,
        sortedVideoFiles[0].linkIndex,
      );

      // Close loading dialog
      if (mounted) Navigator.of(context).pop();

      // Create playlist entries using restrictedLink (like _handlePlayMultiFileTorrent)
      final playlist = sortedVideoFiles.map((file) {
        return PlaylistEntry(
          title: file.name,
          url: '', // Will be loaded on demand
          restrictedLink: _currentTorrent!.links[file.linkIndex],
          sizeBytes: file.bytes ?? 0,
        );
      }).toList();

      // Detect if it's a series collection
      final filenames = playlist.map((e) => e.title).toList();
      final isSeries = playlist.length > 1 && SeriesParser.isSeriesPlaylist(filenames);

      // Launch video player with playlist
      await VideoPlayerLauncher.push(
        context,
        VideoPlayerLaunchArgs(
          videoUrl: firstVideoUrl,
          title: folder.name,
          subtitle: '${videoFiles.length} videos',
          playlist: playlist,
          startIndex: 0,
          viewMode: isSeries ? PlaylistViewMode.series : PlaylistViewMode.sorted,
        ),
      );
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop();
        _showError('Failed to play folder: ${e.toString()}');
      }
    }
  }

  /// Download a single file
  Future<void> _downloadFile(RDFileNode file) async {
    if (_apiKey == null || _currentTorrentId == null) {
      _showError('No API key or torrent ID available');
      return;
    }

    try {
      // Show loading
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
                'Preparing download...',
                style: TextStyle(color: Colors.white),
              ),
            ],
          ),
        ),
      );

      // Get the torrent info to access the restricted link
      final torrentInfo = await DebridService.getTorrentInfo(
        _apiKey!,
        _currentTorrentId!,
      );
      final links = (torrentInfo['links'] as List).cast<String>();

      // Validate linkIndex
      if (file.linkIndex >= links.length) {
        if (mounted) Navigator.of(context).pop();
        _showError('Invalid file link index');
        return;
      }

      // Get restricted link (no unrestriction - download service will do it lazily)
      final restrictedLink = links[file.linkIndex];

      // Use file name from node (download service will get RD filename when unrestricting)
      final fileName = file.name;

      // Close loading dialog
      if (mounted) Navigator.of(context).pop();

      // Pass metadata for lazy unrestriction
      final meta = jsonEncode({
        'restrictedLink': restrictedLink,
        'apiKey': _apiKey,
        'torrentHash': _currentTorrent?.hash,
        'fileIndex': file.linkIndex,
      });

      // Pass restricted link as URL (download service will replace it)
      await DownloadService.instance.enqueueDownload(
        url: restrictedLink,
        fileName: fileName,
        meta: meta,
        torrentName: _currentTorrent?.filename,
        context: mounted ? context : null,
      );

      _showSuccess('Download queued: $fileName');
    } catch (e) {
      // Close loading dialog if still open
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      _showError('Failed to download: $e');
    }
  }

  /// Download files from a folder with file selection dialog
  Future<void> _downloadFolder(RDFileNode folder) async {
    if (_apiKey == null || _currentTorrentId == null) {
      _showError('No API key or torrent ID available');
      return;
    }

    try {
      // Show loading
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Scanning folder...', style: TextStyle(color: Colors.white)),
            ],
          ),
        ),
      );

      // Collect all files recursively
      final allFiles = RDFolderTreeBuilder.collectAllFiles(folder);

      // Get torrent info to access links
      final torrentInfo = await DebridService.getTorrentInfo(
        _apiKey!,
        _currentTorrentId!,
      );
      final links = (torrentInfo['links'] as List).cast<String>();

      if (mounted) Navigator.of(context).pop();

      if (allFiles.isEmpty) {
        _showError('No files found in folder');
        return;
      }

      // Format files for FileSelectionDialog
      final formattedFiles = <Map<String, dynamic>>[];
      for (final file in allFiles) {
        // Build relative path from folder name
        final fullPath = file.path ?? file.name;
        // Remove the parent folder name from the path if present
        final relativePath = fullPath.contains('/')
            ? fullPath.substring(fullPath.indexOf('/') + 1)
            : fullPath;

        formattedFiles.add({
          '_fullPath': relativePath,
          'name': file.name,
          'size': (file.bytes ?? 0).toString(),
          '_linkIndex': file.linkIndex,
          '_rdFileNode': file, // Store original node for download
        });
      }

      // Show file selection dialog
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (BuildContext context) {
          return FileSelectionDialog(
            files: formattedFiles,
            torrentName: folder.name,
            onDownload: (selectedFiles) {
              if (selectedFiles.isEmpty) return;
              _downloadSelectedRealDebridFiles(
                selectedFiles: selectedFiles,
                links: links,
                folderName: folder.name,
              );
            },
          );
        },
      );
    } catch (e) {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      _showError('Failed to load folder: $e');
    }
  }

  /// Download selected Real-Debrid files from file selection dialog
  Future<void> _downloadSelectedRealDebridFiles({
    required List<Map<String, dynamic>> selectedFiles,
    required List<String> links,
    required String folderName,
  }) async {
    if (!mounted) return;

    try {
      // Show progress
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                'Queuing ${selectedFiles.length} file${selectedFiles.length == 1 ? '' : 's'}...',
                style: const TextStyle(color: Colors.white),
              ),
            ],
          ),
        ),
      );

      // Queue downloads for each selected file
      int successCount = 0;
      int failCount = 0;

      for (final fileData in selectedFiles) {
        try {
          // Extract link index and file name
          final linkIndex = fileData['_linkIndex'] as int;
          final fileName = (fileData['_fullPath'] as String?) ?? (fileData['name'] as String? ?? 'download');

          // Validate linkIndex
          if (linkIndex >= links.length) {
            failCount++;
            continue;
          }

          // Get restricted link (no API call - instant!)
          final restrictedLink = links[linkIndex];

          // Pass metadata for lazy unrestriction
          final meta = jsonEncode({
            'restrictedLink': restrictedLink,
            'apiKey': _apiKey,
            'torrentHash': _currentTorrent?.hash,
            'fileIndex': linkIndex,
          });

          // Queue download instantly (download service will unrestrict when ready)
          await DownloadService.instance.enqueueDownload(
            url: restrictedLink, // Pass restricted link (will be replaced by download service)
            fileName: fileName,
            meta: meta,
            torrentName: _currentTorrent?.filename ?? folderName,
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
        _showSuccess(
          'Queued $successCount file${successCount == 1 ? '' : 's'} for download',
        );
      } else if (successCount > 0 && failCount > 0) {
        _showError(
          'Queued $successCount file${successCount == 1 ? '' : 's'}, $failCount failed',
        );
      } else {
        _showError('Failed to queue any files for download');
      }
    } catch (e) {
      // Close any open dialogs
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      _showError('Failed to queue downloads: $e');
    }
  }

  /// Add a single file to playlist
  Future<void> _addNodeFileToPlaylist(RDFileNode file) async {
    if (_currentTorrentId == null) return;

    try {
      final added = await StorageService.addPlaylistItemRaw({
        'provider': 'rd',
        'title': FileUtils.cleanPlaylistTitle(file.name),
        'kind': 'single',
        'rdTorrentId': _currentTorrentId,
        'rdLinkIndex': file.linkIndex,
        'sizeBytes': file.bytes,
      });

      if (mounted) {
        _showSuccess(added ? 'Added to playlist' : 'Already in playlist');
      }
    } catch (e) {
      if (mounted) {
        _showError('Failed to add to playlist: ${e.toString()}');
      }
    }
  }

  /// Add all videos in a folder to playlist
  Future<void> _addFolderToPlaylist(RDFileNode folder) async {
    if (_currentTorrentId == null) return;

    try {
      // Collect video files
      final videoFiles = RDFolderTreeBuilder.collectVideoFiles(folder);
      if (videoFiles.isEmpty) {
        _showError('No video files to add');
        return;
      }

      // Add as a collection to playlist
      final added = await StorageService.addPlaylistItemRaw({
        'provider': 'rd',
        'title': FileUtils.cleanPlaylistTitle(folder.name),
        'kind': 'collection',
        'rdTorrentId': _currentTorrentId,
        'rdFileNodes': videoFiles.map((f) => f.toJson()).toList(),
        'fileCount': videoFiles.length,
        'totalBytes': folder.totalBytes,
      });

      if (mounted) {
        _showSuccess(
          added
              ? 'Added ${videoFiles.length} videos to playlist'
              : 'Already in playlist',
        );
      }
    } catch (e) {
      if (mounted) {
        _showError('Failed to add to playlist: ${e.toString()}');
      }
    }
  }

  /// Format date to relative time or absolute date
  String _formatDate(String isoDate) {
    try {
      final date = DateTime.parse(isoDate);
      final now = DateTime.now();
      final difference = now.difference(date);

      if (difference.inDays == 0) {
        if (difference.inHours == 0) {
          return '${difference.inMinutes}m ago';
        }
        return '${difference.inHours}h ago';
      } else if (difference.inDays < 7) {
        return '${difference.inDays}d ago';
      } else {
        return '${date.month}/${date.day}/${date.year}';
      }
    } catch (e) {
      return '';
    }
  }

  /// Copy download link for torrent to clipboard
  Future<void> _copyDownloadLink(RDTorrent torrent) async {
    if (_apiKey == null) return;

    try {
      // Get torrent info
      final info = await DebridService.getTorrentInfo(_apiKey!, torrent.id);
      final links = (info['links'] as List).cast<String>();

      if (links.isEmpty) {
        _showError('No links available');
        return;
      }

      // Unrestrict the first link
      final unrestrictedData = await DebridService.unrestrictLink(
        _apiKey!,
        links[0],
      );
      final downloadUrl = unrestrictedData['download'] as String;

      // Copy to clipboard
      await Clipboard.setData(ClipboardData(text: downloadUrl));
      _showSuccess('Download link copied to clipboard');
    } catch (e) {
      _showError('Failed to get download link: $e');
    }
  }

  /// Copy download link for file node to clipboard
  Future<void> _copyNodeDownloadLink(RDFileNode node) async {
    if (_apiKey == null || _currentTorrentId == null) return;

    try {
      // Unrestrict the file's link
      final downloadUrl = await DebridService.getFileDownloadUrl(
        _apiKey!,
        _currentTorrentId!,
        node.linkIndex,
      );

      // Copy to clipboard
      await Clipboard.setData(ClipboardData(text: downloadUrl));
      _showSuccess('Download link copied to clipboard');
    } catch (e) {
      _showError('Failed to get download link: $e');
    }
  }

  /// Open video file with external player
  Future<void> _openWithExternalPlayer(RDFileNode node) async {
    if (_apiKey == null || _currentTorrentId == null) return;

    try {
      // Show loading indicator
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );

      // Unrestrict the file's link
      final downloadUrl = await DebridService.getFileDownloadUrl(
        _apiKey!,
        _currentTorrentId!,
        node.linkIndex,
      );

      // Close loading indicator
      if (mounted) {
        Navigator.of(context).pop();
      }

      // Launch with external player
      if (Platform.isAndroid) {
        // On Android, use intent with video MIME type to show video player chooser
        final intent = AndroidIntent(
          action: 'action_view',
          data: downloadUrl,
          type: 'video/*',
        );
        await intent.launch();
        _showSuccess('Opening with external player...');
      } else {
        // On other platforms, use url_launcher
        final Uri uri = Uri.parse(downloadUrl);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalNonBrowserApplication);
          _showSuccess('Opening with external player...');
        } else {
          _showError('Could not open external player');
        }
      }
    } catch (e) {
      // Close loading indicator if still open
      if (mounted) {
        Navigator.of(context).pop();
      }
      _showError('Failed to open with external player: $e');
    }
  }
}
