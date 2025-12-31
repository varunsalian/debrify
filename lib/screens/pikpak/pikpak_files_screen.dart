import 'package:flutter/material.dart';
import 'dart:convert';
import '../../screens/video_player_screen.dart';
import '../../services/pikpak_api_service.dart';
import '../../services/storage_service.dart';
import '../../services/download_service.dart';
import '../../services/video_player_launcher.dart';
import '../../utils/file_utils.dart';
import '../../utils/formatters.dart';
import '../../utils/series_parser.dart';
import '../../widgets/file_selection_dialog.dart';

class PikPakFilesScreen extends StatefulWidget {
  final String? initialFolderId;
  final String? initialFolderName;

  const PikPakFilesScreen({
    super.key,
    this.initialFolderId,
    this.initialFolderName,
  });

  @override
  State<PikPakFilesScreen> createState() => _PikPakFilesScreenState();
}

/// View modes for folder display
enum _FolderViewMode { raw, sortedAZ, seriesArrange }

class _PikPakFilesScreenState extends State<PikPakFilesScreen> {
  final ScrollController _scrollController = ScrollController();
  final List<Map<String, dynamic>> _files = [];

  bool _isLoading = false;
  bool _initialLoad = true;
  String _errorMessage = '';
  bool _pikpakEnabled = false;
  bool _showVideosOnly = true;
  bool _ignoreSmallVideos = true;
  String? _email;

  // Pagination state
  String? _nextPageToken;
  bool _hasMore = true;
  bool _isLoadingMore = false;

  // Folder navigation state
  String? _currentFolderId;
  String _currentFolderName = 'My Files';
  final List<({String? id, String name})> _navigationStack = [];
  String? _restrictedFolderId;
  String? _restrictedFolderName;
  bool _isAtRestrictedRoot = false;

  // View mode state (per-folder persistence during session)
  final Map<String, _FolderViewMode> _folderViewModes = {};

  // Virtual folder navigation for Series Arrange mode
  bool _isInVirtualFolder = false;
  String? _virtualFolderName; // e.g., "Season 1"
  List<Map<String, dynamic>> _virtualFolderFiles = []; // Files in virtual Season

  // Cache for recursive file listings (avoid repeated API calls)
  final Map<String, List<Map<String, dynamic>>> _recursiveFileCache = {};

  // Focus nodes for TV/DPAD navigation
  final FocusNode _refreshButtonFocusNode = FocusNode(
    debugLabel: 'pikpak-refresh',
  );
  final FocusNode _backButtonFocusNode = FocusNode(debugLabel: 'pikpak-back');
  final FocusNode _retryButtonFocusNode = FocusNode(debugLabel: 'pikpak-retry');
  final FocusNode _settingsButtonFocusNode = FocusNode(
    debugLabel: 'pikpak-settings',
  );
  final FocusNode _viewModeDropdownFocusNode = FocusNode(
    debugLabel: 'pikpak-view-mode',
  );

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadSettings();
  }

  void _onScroll() {
    // Load more when user scrolls near the bottom (200px threshold)
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMoreFiles();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _refreshButtonFocusNode.dispose();
    _backButtonFocusNode.dispose();
    _retryButtonFocusNode.dispose();
    _settingsButtonFocusNode.dispose();
    _viewModeDropdownFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final enabled = await StorageService.getPikPakEnabled();
    final showVideosOnly = await StorageService.getPikPakShowVideosOnly();
    final ignoreSmallVideos = await StorageService.getPikPakIgnoreSmallVideos();
    final email = await PikPakApiService.instance.getEmail();
    final restrictedId = await StorageService.getPikPakRestrictedFolderId();
    final restrictedName = await StorageService.getPikPakRestrictedFolderName();

    if (!mounted) return;

    // If enabled and has a restricted folder, verify it still exists
    if (enabled && restrictedId != null && restrictedId.isNotEmpty) {
      final folderExists =
          await PikPakApiService.instance.verifyRestrictedFolderExists();
      if (!folderExists) {
        // Restricted folder was deleted externally
        await _handleRestrictedFolderDeleted();
        return;
      }
    }

    setState(() {
      _pikpakEnabled = enabled;
      _showVideosOnly = showVideosOnly;
      _ignoreSmallVideos = ignoreSmallVideos;
      _email = email;
      _restrictedFolderId = restrictedId;
      _restrictedFolderName = restrictedName;

      // If initial folder is provided, navigate to it
      if (widget.initialFolderId != null && widget.initialFolderName != null) {
        _currentFolderId = widget.initialFolderId;
        _currentFolderName = widget.initialFolderName!;
        _isAtRestrictedRoot = false;
      }
      // Otherwise, initialize at restricted folder instead of root
      else if (restrictedId != null) {
        _currentFolderId = restrictedId;
        _currentFolderName = restrictedName ?? 'Restricted Folder';
        _isAtRestrictedRoot = true;
      }
    });

    if (enabled) {
      _loadFiles();
    }
  }

  /// Handle the case when the restricted folder has been deleted externally
  Future<void> _handleRestrictedFolderDeleted() async {
    print(
      'PikPak: Restricted folder was deleted externally, logging out user...',
    );

    // Logout from PikPak
    await PikPakApiService.instance.logout();

    if (!mounted) return;

    // Update state
    setState(() {
      _pikpakEnabled = false;
      _restrictedFolderId = null;
      _restrictedFolderName = null;
      _isLoading = false;
      _initialLoad = false;
      _errorMessage = '';
    });

    // Show snackbar
    _showSnackBar(
      'Restricted folder was deleted. You have been logged out.',
      isError: true,
      duration: const Duration(seconds: 5),
    );
  }

  Future<void> _loadFiles() async {
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
      _errorMessage = '';
      // Reset pagination state for fresh load
      _nextPageToken = null;
      _hasMore = true;
    });

    try {
      final result = await PikPakApiService.instance.listFiles(
        parentId: _currentFolderId,
      );

      if (!mounted) return;

      // Filter files based on settings
      final filteredFiles = _filterFiles(result.files);

      // Apply current view mode transformation
      final mode = _getCurrentViewMode();
      final transformedFiles = mode == _FolderViewMode.seriesArrange
          ? filteredFiles // Series Arrange is handled separately in _setViewMode
          : _applyViewMode(mode, filteredFiles);

      setState(() {
        _files.clear();
        _files.addAll(transformedFiles);
        _nextPageToken = result.nextPageToken;
        _hasMore =
            result.nextPageToken != null && result.nextPageToken!.isNotEmpty;
        _isLoading = false;
        _initialLoad = false;
      });
    } catch (e) {
      print('Error loading PikPak files: $e');
      if (!mounted) return;

      // Check if the restricted folder has been deleted externally
      if (_restrictedFolderId != null &&
          _currentFolderId == _restrictedFolderId) {
        // The error is likely because the restricted folder was deleted
        // Auto-logout the user
        await _handleRestrictedFolderDeleted();
        return;
      }

      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
        _initialLoad = false;
      });
    }
  }

  Future<void> _loadMoreFiles() async {
    // Don't load more if already loading, no more pages, or no page token
    if (_isLoadingMore || !_hasMore || _nextPageToken == null) return;

    setState(() {
      _isLoadingMore = true;
    });

    try {
      final result = await PikPakApiService.instance.listFiles(
        parentId: _currentFolderId,
        pageToken: _nextPageToken,
      );

      if (!mounted) return;

      // Filter files based on settings
      final filteredFiles = _filterFiles(result.files);

      setState(() {
        _files.addAll(filteredFiles);
        _nextPageToken = result.nextPageToken;
        _hasMore =
            result.nextPageToken != null && result.nextPageToken!.isNotEmpty;

        // Re-apply current view mode to maintain consistency
        final mode = _getCurrentViewMode();
        if (mode != _FolderViewMode.raw && mode != _FolderViewMode.seriesArrange) {
          final transformed = _applyViewMode(mode, _files);
          _files.clear();
          _files.addAll(transformed);
        }

        _isLoadingMore = false;
      });
    } catch (e) {
      print('Error loading more PikPak files: $e');
      if (!mounted) return;

      setState(() {
        _isLoadingMore = false;
      });

      _showSnackBar('Failed to load more files: $e');
    }
  }

  /// Filter files based on user settings (videos only, ignore small videos)
  List<Map<String, dynamic>> _filterFiles(List<Map<String, dynamic>> files) {
    List<Map<String, dynamic>> filteredFiles = files;

    // Filter by file type (videos only)
    if (_showVideosOnly) {
      filteredFiles = filteredFiles.where((file) {
        final kind = file['kind'] ?? '';
        final mimeType = file['mime_type'] ?? '';
        // Always show folders, only filter non-folder items
        return kind == 'drive#folder' || mimeType.startsWith('video/');
      }).toList();
    }

    // Filter by size (ignore videos under 100MB)
    if (_ignoreSmallVideos) {
      filteredFiles = filteredFiles.where((file) {
        final kind = file['kind'] ?? '';
        final mimeType = file['mime_type'] ?? '';
        final size = file['size'];

        // Always show folders
        if (kind == 'drive#folder') return true;

        // For videos, check size
        if (mimeType.startsWith('video/')) {
          if (size == null) return true; // Show if size is unknown
          final sizeBytes = int.tryParse(size.toString()) ?? 0;
          final sizeMB = sizeBytes / (1024 * 1024);
          return sizeMB >= 100; // Only show videos 100MB or larger
        }

        // Show non-video files if videos-only filter is off
        return true;
      }).toList();
    }

    return filteredFiles;
  }

  void _navigateIntoFolder(String folderId, String folderName) {
    setState(() {
      // Push current folder to stack before navigating
      _navigationStack.add((id: _currentFolderId, name: _currentFolderName));
      _currentFolderId = folderId;
      _currentFolderName = folderName;
      // We're navigating into a subfolder, so we're no longer at restricted root
      _isAtRestrictedRoot = false;
    });
    _loadFiles();
  }

  void _navigateUp() {
    // Don't navigate above restricted folder
    if (_restrictedFolderId != null &&
        _currentFolderId == _restrictedFolderId) {
      _showSnackBar('Already at restricted folder root', isError: false);
      return;
    }

    setState(() {
      // Pop from stack to go back one level
      if (_navigationStack.isNotEmpty) {
        final previous = _navigationStack.removeLast();
        _currentFolderId = previous.id;
        _currentFolderName = previous.name;

        // Check if we're back at the restricted root
        _isAtRestrictedRoot =
            (_restrictedFolderId != null &&
            _currentFolderId == _restrictedFolderId);
      } else {
        // Already at root (or restricted root)
        if (_restrictedFolderId != null) {
          _currentFolderId = _restrictedFolderId;
          _currentFolderName = _restrictedFolderName ?? 'Restricted Folder';
          _isAtRestrictedRoot = true;
        } else {
          _currentFolderId = null;
          _currentFolderName = 'My Files';
        }
      }
    });
    _loadFiles();
  }

  /// Navigate up with virtual folder support
  /// If in virtual folder, exit virtual folder first before navigating real folders
  void _navigateUpWithVirtual() {
    if (_isInVirtualFolder) {
      // Exit virtual folder, go back to transformed view
      setState(() {
        _isInVirtualFolder = false;
        _virtualFolderName = null;
        _virtualFolderFiles.clear();
      });

      // Re-apply current view mode to show the season folders again
      final mode = _getCurrentViewMode();
      _setViewMode(mode);
    } else {
      // Normal navigation up real folders
      _navigateUp();
    }
  }

  /// Navigate into a virtual Season folder
  void _navigateIntoVirtualFolder(Map<String, dynamic> virtualFolder) {
    final seasonName = virtualFolder['name'] as String? ?? 'Virtual Folder';
    final virtualFiles = virtualFolder['virtual_files'] as List<dynamic>? ?? [];

    // Validate virtual files exist
    if (virtualFiles.isEmpty) {
      _showSnackBar('Virtual folder is empty', isError: true);
      return;
    }

    try {
      final typedFiles = virtualFiles.cast<Map<String, dynamic>>();
      setState(() {
        _isInVirtualFolder = true;
        _virtualFolderName = seasonName;
        _virtualFolderFiles = typedFiles;
        _files.clear();
        _files.addAll(_virtualFolderFiles);
      });
    } catch (e) {
      print('Error navigating into virtual folder: $e');
      _showSnackBar('Failed to open virtual folder: $e', isError: true);
    }
  }

  Future<void> _playFile(Map<String, dynamic> fileData) async {
    try {
      // Check if it's a folder
      final kind = fileData['kind'];
      if (kind == 'drive#folder') {
        _showSnackBar(
          'Cannot play folders. Please select a video file.',
          isError: true,
        );
        return;
      }

      // Check if it's a video
      final mimeType = fileData['mime_type'] ?? '';
      if (!mimeType.startsWith('video/')) {
        _showSnackBar('Only video files can be played', isError: true);
        return;
      }

      // CRITICAL FIX: Fetch fresh file details with download URLs
      // listFiles() returns empty web_content_link/medias, so we need to call
      // getFileDetails() with usage=FETCH to get populated download URLs
      final fileId = fileData['id'];

      // Show loading indicator
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) =>
            const Center(child: CircularProgressIndicator()),
      );

      Map<String, dynamic> freshFileData;
      try {
        freshFileData = await PikPakApiService.instance.getFileDetails(fileId);
      } finally {
        // Close loading indicator
        if (mounted) {
          Navigator.of(context, rootNavigator: true).pop();
        }
      }

      // Extract streaming URL from fresh data
      final streamingUrl = PikPakApiService.instance.getStreamingUrl(
        freshFileData,
      );

      if (streamingUrl == null || streamingUrl.isEmpty) {
        _showSnackBar(
          'No streaming URL available for this file',
          isError: true,
        );
        return;
      }

      // Links ready - play the video
      if (!mounted) return;

      await VideoPlayerLauncher.push(
        context,
        VideoPlayerLaunchArgs(
          videoUrl: streamingUrl,
          title: freshFileData['name'] ?? 'Video',
        ),
      );
    } catch (e) {
      print('Error playing file: $e');
      _showSnackBar('Failed to play video: $e', isError: true);
    }
  }

  /// Download a single file
  Future<void> _downloadFile(Map<String, dynamic> file) async {
    final fileId = file['id'] as String?;
    final fileName = file['name'] ?? 'download';

    if (fileId == null) {
      _showSnackBar('Invalid file ID', isError: true);
      return;
    }

    // Check if it's a folder
    final kind = file['kind'];
    if (kind == 'drive#folder') {
      _showSnackBar(
        'Cannot download folders directly. Use Download button on folder.',
        isError: true,
      );
      return;
    }

    try {
      // Show loading indicator
      if (!mounted) return;
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
                'Preparing download...',
                style: TextStyle(color: Colors.white),
              ),
            ],
          ),
        ),
      );

      // Get fresh file details with download URLs
      Map<String, dynamic> freshFileData;
      try {
        freshFileData = await PikPakApiService.instance.getFileDetails(fileId);
      } catch (e) {
        // Close loading indicator
        if (mounted) {
          Navigator.of(context, rootNavigator: true).pop();
        }
        _showSnackBar('Failed to get download URL: $e', isError: true);
        return;
      }

      // Extract download URL (use web_content_link for all files)
      final downloadUrl = freshFileData['web_content_link'] as String?;

      // Close loading indicator
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }

      if (downloadUrl == null || downloadUrl.isEmpty) {
        _showSnackBar('No download URL available for this file', isError: true);
        return;
      }

      // Prepare metadata for download service
      final meta = jsonEncode({
        'pikpakDownload': true,
        'pikpakFileId': fileId,
        'pikpakFileName': fileName,
      });

      // Enqueue download
      await DownloadService.instance.enqueueDownload(
        url: downloadUrl,
        fileName: fileName,
        meta: meta,
        context: mounted ? context : null,
      );

      _showSnackBar('Download queued: $fileName', isError: false);
    } catch (e) {
      print('Error downloading file: $e');
      // Close loading indicator if still open
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      _showSnackBar('Failed to download: $e', isError: true);
    }
  }

  /// Download all files in a folder with file selection dialog
  /// Works for both root folders and subfolders
  /// When downloading a subfolder, only shows that subfolder's contents (not parent structure)
  Future<void> _downloadFolder(Map<String, dynamic> folder) async {
    final folderId = folder['id'] as String?;
    final folderName = folder['name'] ?? 'Folder';

    if (folderId == null) {
      _showSnackBar('Invalid folder ID', isError: true);
      return;
    }

    // Show loading dialog
    if (!mounted) return;
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
              'Scanning folder for files...',
              style: TextStyle(color: Colors.white),
            ),
          ],
        ),
      ),
    );

    try {
      // Recursively scan folder for all files WITH path tracking
      // This ensures the dialog shows folder structure starting from this folder
      final allFiles = await PikPakApiService.instance.listFilesRecursive(
        folderId: folderId,
        includePaths: true, // Enable path tracking for folder structure
      );

      // Close loading dialog
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }

      if (!mounted) return;

      // Filter out folders, keep only files
      final filesOnly = allFiles.where((file) {
        final kind = file['kind'] ?? '';
        return kind != 'drive#folder';
      }).toList();

      if (filesOnly.isEmpty) {
        _showSnackBar('This folder doesn\'t contain any files', isError: true);
        return;
      }

      // Show file selection dialog
      await showDialog(
        context: context,
        builder: (context) => FileSelectionDialog(
          files: filesOnly,
          torrentName: folderName,
          onDownload: (selectedFiles) {
            _downloadSelectedPikPakFiles(selectedFiles, folderName);
          },
        ),
      );
    } catch (e) {
      print('Error downloading folder: $e');
      if (mounted) {
        // Close loading dialog if still open
        Navigator.of(context, rootNavigator: true).pop();
      }
      _showSnackBar('Failed to scan folder: $e', isError: true);
    }
  }

  /// Download selected PikPak files from the file selection dialog
  /// Handles error reporting and uses folder name for download organization
  Future<void> _downloadSelectedPikPakFiles(
    List<Map<String, dynamic>> selectedFiles,
    String folderName,
  ) async {
    if (selectedFiles.isEmpty) {
      _showSnackBar('No files selected', isError: true);
      return;
    }

    int successCount = 0;
    int failCount = 0;

    // Show progress indicator
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
              'Queuing ${selectedFiles.length} file${selectedFiles.length == 1 ? '' : 's'}...',
              style: const TextStyle(color: Colors.white),
            ),
          ],
        ),
      ),
    );

    try {
      for (final file in selectedFiles) {
        try {
          final fileId = file['id'] as String?;
          // Use _fullPath if available (from path tracking), otherwise use original name
          final fileName = (file['_fullPath'] as String?) ?? file['name'] ?? 'download';

          if (fileId == null) {
            failCount++;
            continue;
          }

          // Get fresh file details with download URLs
          final freshFileData = await PikPakApiService.instance.getFileDetails(
            fileId,
          );
          final downloadUrl = freshFileData['web_content_link'] as String?;

          if (downloadUrl == null || downloadUrl.isEmpty) {
            failCount++;
            continue;
          }

          // Prepare metadata for download service
          final meta = jsonEncode({
            'pikpakDownload': true,
            'pikpakFileId': fileId,
            'pikpakFileName': fileName,
          });

          // Enqueue download with folder name for organization
          await DownloadService.instance.enqueueDownload(
            url: downloadUrl,
            fileName: fileName,
            meta: meta,
            torrentName: folderName, // Use folder name for organization
            context: mounted ? context : null,
          );

          successCount++;
        } catch (e) {
          print('Error queuing file for download: $e');
          failCount++;
        }
      }
    } finally {
      // Close progress dialog
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    }

    if (!mounted) return;

    // Show result
    if (successCount > 0 && failCount == 0) {
      _showSnackBar(
        'Queued $successCount file${successCount == 1 ? '' : 's'} for download',
        isError: false,
      );
    } else if (successCount > 0 && failCount > 0) {
      _showSnackBar(
        'Queued $successCount file${successCount == 1 ? '' : 's'}, $failCount failed',
        isError: true,
      );
    } else {
      _showSnackBar('Failed to queue any files for download', isError: true);
    }
  }

  Future<void> _refreshFiles() async {
    // Clear cache for current folder when refreshing
    if (_currentFolderId != null) {
      _recursiveFileCache.remove(_currentFolderId!);
    }

    // Exit virtual folder if in one
    if (_isInVirtualFolder) {
      setState(() {
        _isInVirtualFolder = false;
        _virtualFolderName = null;
        _virtualFolderFiles.clear();
      });
    }

    await _loadFiles();
    _showSnackBar('Files refreshed', isError: false);
  }

  void _showDeleteDialog(Map<String, dynamic> file) {
    final fileName = file['name'] ?? 'this item';
    final fileId = file['id'] as String?;

    if (fileId == null) {
      _showSnackBar('Cannot delete: Invalid file ID');
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete File'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('What would you like to do with "$fileName"?'),
            const SizedBox(height: 16),
            const Text(
              'Move to Trash: File can be recovered later\nDelete Permanently: Cannot be undone',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            autofocus: true, // Safe default for TV/DPAD
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _deleteFile(fileId, fileName, permanent: false);
            },
            child: const Text('Move to Trash'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _deleteFile(fileId, fileName, permanent: true);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete Permanently'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteFile(
    String fileId,
    String fileName, {
    required bool permanent,
  }) async {
    try {
      _showSnackBar(
        permanent ? 'Deleting permanently...' : 'Moving to trash...',
        isError: false,
      );

      if (permanent) {
        await PikPakApiService.instance.batchDeleteFiles([fileId]);
      } else {
        await PikPakApiService.instance.batchTrashFiles([fileId]);
      }

      if (!mounted) return;

      // Remove the file from the local list
      setState(() {
        _files.removeWhere((f) => f['id'] == fileId);
      });

      _showSnackBar(
        permanent
            ? '"$fileName" deleted permanently'
            : '"$fileName" moved to trash',
        isError: false,
      );
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('Failed to delete: $e');
    }
  }

  void _showSnackBar(
    String message, {
    bool isError = true,
    Duration? duration,
  }) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isError
                    ? const Color(0xFFEF4444)
                    : const Color(0xFF22C55E),
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
        duration: duration ?? const Duration(seconds: 3),
      ),
    );
  }

  // ========== VIEW MODE TRANSFORMATION METHODS ==========

  /// Get current view mode for the active folder
  _FolderViewMode _getCurrentViewMode() {
    // Virtual folders don't have their own view modes
    if (_isInVirtualFolder) return _FolderViewMode.seriesArrange;

    // Root level (no folder selected) defaults to Raw
    if (_currentFolderId == null) return _FolderViewMode.raw;

    return _folderViewModes[_currentFolderId!] ?? _FolderViewMode.raw;
  }

  /// Set view mode and refresh display
  Future<void> _setViewMode(_FolderViewMode mode) async {
    if (_currentFolderId == null) return;

    // If user selected Series Arrange, we need to fetch all files recursively
    if (mode == _FolderViewMode.seriesArrange) {
      // Show loading indicator
      setState(() {
        _isLoading = true;
      });

      try {
        // Fetch all files recursively from this folder
        List<Map<String, dynamic>> allFiles;
        if (_recursiveFileCache.containsKey(_currentFolderId!)) {
          allFiles = _recursiveFileCache[_currentFolderId!]!;
        } else {
          allFiles = await PikPakApiService.instance.listFilesRecursive(
            folderId: _currentFolderId!,
          );
          _recursiveFileCache[_currentFolderId!] = allFiles;
        }

        // Filter for video files only
        final videoFiles = allFiles.where((file) {
          final kind = file['kind'] ?? '';
          final mimeType = file['mime_type'] ?? '';
          return kind != 'drive#folder' && mimeType.startsWith('video/');
        }).toList();

        // Detect if it's actually a series
        if (videoFiles.length < 3) {
          _showFallbackToSorted('Not enough video files for series detection', allFiles);
          return;
        }

        final filenames = videoFiles.map((f) => f['name'] as String? ?? '').toList();
        final isSeries = SeriesParser.isSeriesPlaylist(filenames);

        if (!isSeries) {
          _showFallbackToSorted('No series detected in this folder', allFiles);
          return;
        }

        // It's a series! Apply Series Arrange view
        setState(() {
          _folderViewModes[_currentFolderId!] = mode;
          final transformed = _applySeriesArrangeView(allFiles);
          _files.clear();
          _files.addAll(transformed);
          _isLoading = false;
        });
      } catch (e) {
        print('Error applying Series Arrange view: $e');
        _showFallbackToSorted('Failed to load series view', null);
      }
    } else {
      // For Raw and Sort modes, work with current page files
      setState(() {
        _folderViewModes[_currentFolderId!] = mode;
        final transformed = _applyViewMode(mode, _files);
        _files.clear();
        _files.addAll(transformed);
        // Reset pagination when transforming (can't mix transformed/raw data)
        _nextPageToken = null;
        _hasMore = false;
      });
    }
  }

  /// Show snackbar and fallback to sorted view
  /// If allFiles is provided (from recursive fetch), use those instead of _files
  void _showFallbackToSorted(String reason, List<Map<String, dynamic>>? allFiles) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('No series detected in this folder. Switching to Sort (A-Z) view.'),
        duration: Duration(seconds: 3),
        backgroundColor: Color(0xFF1E293B),
        behavior: SnackBarBehavior.floating,
      ),
    );

    setState(() {
      _folderViewModes[_currentFolderId!] = _FolderViewMode.sortedAZ;
      // Use allFiles if provided (preserves full recursive fetch), otherwise use _files
      final filesToTransform = allFiles ?? _files;
      final transformed = _applySortedView(filesToTransform);
      _files.clear();
      _files.addAll(transformed);
      _isLoading = false;
    });
  }

  /// Apply view mode transformation to a list of files
  List<Map<String, dynamic>> _applyViewMode(
    _FolderViewMode mode,
    List<Map<String, dynamic>> items,
  ) {
    switch (mode) {
      case _FolderViewMode.raw:
        return items;
      case _FolderViewMode.sortedAZ:
        return _applySortedView(items);
      case _FolderViewMode.seriesArrange:
        return _applySeriesArrangeView(items);
    }
  }

  /// Apply sorted view (folders first A-Z, then files A-Z) with numerical sorting
  List<Map<String, dynamic>> _applySortedView(List<Map<String, dynamic>> items) {
    final folders = items.where((item) {
      final kind = item['kind'] ?? '';
      return kind == 'drive#folder';
    }).toList();

    final files = items.where((item) {
      final kind = item['kind'] ?? '';
      return kind != 'drive#folder';
    }).toList();

    // Sort folders with numerical handling
    folders.sort((a, b) {
      final aName = a['name'] as String? ?? '';
      final bName = b['name'] as String? ?? '';

      final aNum = _extractSeasonNumber(aName);
      final bNum = _extractSeasonNumber(bName);

      // If both have numbers, sort numerically
      if (aNum != null && bNum != null) {
        return aNum.compareTo(bNum);
      }

      // If only one has a number, numbered folders come first
      if (aNum != null) return -1;
      if (bNum != null) return 1;

      // Otherwise sort alphabetically
      return aName.toLowerCase().compareTo(bName.toLowerCase());
    });

    // Sort files with numerical handling
    files.sort((a, b) {
      final aName = a['name'] as String? ?? '';
      final bName = b['name'] as String? ?? '';

      final aNum = _extractLeadingNumber(aName);
      final bNum = _extractLeadingNumber(bName);

      // If both start with numbers, sort numerically
      if (aNum != null && bNum != null) {
        return aNum.compareTo(bNum);
      }

      // If only one starts with a number, numbered files come first
      if (aNum != null) return -1;
      if (bNum != null) return 1;

      // Otherwise sort alphabetically
      return aName.toLowerCase().compareTo(bName.toLowerCase());
    });

    return [...folders, ...files];
  }

  /// Extract number from folder name for numerical sorting
  /// Handles: "1. Introduction", "10. Chapter", "Season 10", "Chapter_12", "Episode 5", "Part 3", etc.
  int? _extractSeasonNumber(String folderName) {
    final patterns = [
      // Leading numbers: "1. ", "10-", "5_", etc.
      RegExp(r'^(\d+)[\s._-]'),
      // Season/Chapter/Episode/Part keywords: "Season 10", "Chapter_12", etc.
      RegExp(r'season[\s_-]*(\d+)', caseSensitive: false),
      RegExp(r'chapter[\s_-]*(\d+)', caseSensitive: false),
      RegExp(r'episode[\s_-]*(\d+)', caseSensitive: false),
      RegExp(r'part[\s_-]*(\d+)', caseSensitive: false),
      // Generic word followed by number: "Lesson_5", "Module-3"
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
  int? _extractLeadingNumber(String filename) {
    final pattern = RegExp(r'^(\d+)[\s._-]');
    final match = pattern.firstMatch(filename);

    if (match != null && match.groupCount >= 1) {
      return int.tryParse(match.group(1)!);
    }

    return null;
  }

  /// Apply series arranged view (create virtual Season folders)
  List<Map<String, dynamic>> _applySeriesArrangeView(
    List<Map<String, dynamic>> items,
  ) {
    // Separate folders and files
    final folders = items.where((item) {
      final kind = item['kind'] ?? '';
      return kind == 'drive#folder';
    }).toList();

    final files = items.where((item) {
      final kind = item['kind'] ?? '';
      return kind != 'drive#folder';
    }).toList();

    // Filter for video files only
    final videoFiles = files.where((file) {
      final mimeType = file['mime_type'] ?? '';
      return mimeType.startsWith('video/');
    }).toList();

    final nonVideoFiles = files.where((file) {
      final mimeType = file['mime_type'] ?? '';
      return !mimeType.startsWith('video/');
    }).toList();

    if (videoFiles.isEmpty) return items;

    final filenames = videoFiles.map((f) => f['name'] as String? ?? '').toList();

    try {
      final parsedInfos = SeriesParser.parsePlaylist(filenames);

      // Group by season
      final Map<int, List<Map<String, dynamic>>> seasonMap = {};
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
          final aInfo = SeriesParser.parseFilename(a['name'] as String? ?? '');
          final bInfo = SeriesParser.parseFilename(b['name'] as String? ?? '');
          final aEp = aInfo.episode ?? 0;
          final bEp = bInfo.episode ?? 0;
          return aEp.compareTo(bEp);
        });

        // Create virtual folder (marked with special kind)
        return {
          'id': 'virtual_season_$seasonNum',
          'kind': 'virtual#season',
          'name': seasonNum == 0 ? 'Season 0 - Specials' : 'Season $seasonNum',
          'season_number': seasonNum,
          'virtual_files': seasonFiles, // Store the files inside
          'size': seasonFiles.fold<int>(
            0,
            (sum, f) => sum + (int.tryParse(f['size']?.toString() ?? '0') ?? 0),
          ),
          'created_time': DateTime.now().toIso8601String(),
        };
      }).toList();

      // Sort season folders by season number
      seasonFolders.sort((a, b) {
        final aNum = a['season_number'] as int? ?? 0;
        final bNum = b['season_number'] as int? ?? 0;
        return aNum.compareTo(bNum);
      });

      return [...folders, ...seasonFolders, ...nonVideoFiles];
    } catch (e) {
      print('Series arrangement failed: $e');
      return _applySortedView(items); // Fallback to sorted view
    }
  }

  /// Build the view mode dropdown (shown below AppBar when inside folders)
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

  @override
  Widget build(BuildContext context) {
    if (!_pikpakEnabled) {
      return _buildNotEnabled();
    }

    if (_initialLoad && _isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_errorMessage.isNotEmpty) {
      return _buildError();
    }

    // Check if we should show the view mode dropdown
    // Only show when navigated at least one level deep (inside a folder)
    final showViewModeDropdown = _navigationStack.isNotEmpty || _isInVirtualFolder;

    // Check if we're at root (allow system back) or in subfolder (intercept back)
    final isAtRoot = _navigationStack.isEmpty &&
                     !_isInVirtualFolder &&
                     (_currentFolderId == null || _isAtRestrictedRoot);

    return PopScope(
      canPop: isAtRoot,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          // User pressed back while in a subfolder - navigate up
          _navigateUpWithVirtual();
        }
      },
      child: Scaffold(
      appBar: AppBar(
        leading: (_currentFolderId != null && !_isAtRestrictedRoot) || _isInVirtualFolder
            ? IconButton(
                focusNode: _backButtonFocusNode,
                icon: const Icon(Icons.arrow_back),
                onPressed: _navigateUpWithVirtual,
                tooltip: 'Back',
              )
            : null,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_isInVirtualFolder
                ? _virtualFolderName ?? 'Virtual Folder'
                : _currentFolderName),
            if (_restrictedFolderId != null && !_isInVirtualFolder)
              const Text(
                'Restricted Access',
                style: TextStyle(fontSize: 12, color: Colors.amber),
              ),
          ],
        ),
        actions: [
          IconButton(
            focusNode: _refreshButtonFocusNode,
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _refreshFiles,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Column(
        children: [
          // View mode dropdown (only shown when inside folders)
          if (showViewModeDropdown && !_isInVirtualFolder) _buildViewModeDropdown(),
          Expanded(
            child: FocusTraversalGroup(
              policy: OrderedTraversalPolicy(),
              child: RefreshIndicator(
                onRefresh: _refreshFiles,
                child: _files.isEmpty ? _buildEmpty() : _buildFileList(),
              ),
            ),
          ),
        ],
      ),
      ),
    );
  }

  Widget _buildNotEnabled() {
    return Scaffold(
      appBar: AppBar(title: const Text('PikPak Files')),
      body: FocusTraversalGroup(
        policy: OrderedTraversalPolicy(),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.cloud_off, size: 64, color: Colors.grey.shade400),
                const SizedBox(height: 24),
                Text(
                  'PikPak Not Configured',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 16),
                Text(
                  'Configure your PikPak account in Settings to view and manage files.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade600),
                ),
                const SizedBox(height: 32),
                FilledButton.icon(
                  focusNode: _settingsButtonFocusNode,
                  autofocus: true,
                  onPressed: () {
                    // TODO: Navigate to settings
                    _showSnackBar(
                      'Open Settings > PikPak to configure',
                      isError: false,
                    );
                  },
                  icon: const Icon(Icons.settings),
                  label: const Text('Go to Settings'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildError() {
    return Scaffold(
      appBar: AppBar(title: const Text('PikPak Files')),
      body: FocusTraversalGroup(
        policy: OrderedTraversalPolicy(),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 64, color: Colors.red.shade400),
                const SizedBox(height: 24),
                Text(
                  'Failed to Load Files',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 16),
                Text(
                  _errorMessage,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade600),
                ),
                const SizedBox(height: 32),
                FilledButton.icon(
                  focusNode: _retryButtonFocusNode,
                  autofocus: true,
                  onPressed: _refreshFiles,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    final isInFolder = _currentFolderId != null;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.folder_open, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 24),
            Text(
              isInFolder ? 'Folder is Empty' : 'No Files Yet',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            Text(
              isInFolder
                  ? 'This folder doesn\'t contain any files or subfolders.'
                  : 'Add torrents from the search screen to see them here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFileList() {
    // Add 1 to item count for loading indicator when loading more
    final itemCount = _files.length + (_isLoadingMore || _hasMore ? 1 : 0);

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        // Show loading indicator at the end
        if (index >= _files.length) {
          return _buildLoadingIndicator();
        }
        final file = _files[index];
        return KeyedSubtree(
          key: ValueKey(file['id'] ?? index),
          child: _buildFileCard(file, index),
        );
      },
    );
  }

  Widget _buildLoadingIndicator() {
    if (_isLoadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    // Show a subtle hint that more can be loaded
    if (_hasMore) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: Text(
            'Scroll for more',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildFileCard(Map<String, dynamic> file, int index) {
    final name = file['name'] ?? 'Unknown';
    final size = file['size'];
    final mimeType = file['mime_type'] ?? '';
    final kind = file['kind'] ?? '';
    final phase = file['phase'] ?? '';
    final createdTime = file['created_time'] ?? '';

    final isFolder = kind == 'drive#folder';
    final isVirtualFolder = kind == 'virtual#season'; // Virtual Season folder
    final isVideo = mimeType.startsWith('video/');
    final isComplete = phase == 'PHASE_TYPE_COMPLETE';

    // Videos are ready to play if they're complete
    // We'll check for actual streaming links when playing
    final hasStreamingLink = isVideo && isComplete;

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
                  isVirtualFolder
                      ? Icons.video_library
                      : isFolder
                      ? Icons.folder
                      : isVideo
                      ? Icons.play_circle_outline
                      : Icons.insert_drive_file,
                  color: isVirtualFolder
                      ? Colors.purple
                      : isFolder
                      ? Colors.amber
                      : isVideo
                      ? Colors.blue
                      : Colors.grey,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
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
                          if (size != null) ...[
                            Text(
                              Formatters.formatFileSize(
                                int.tryParse(size.toString()) ?? 0,
                              ),
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
                          ],
                          Text(
                            _formatDate(createdTime),
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
            if (!isComplete) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  const SizedBox(width: 12),
                  const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Downloading...',
                    style: TextStyle(
                      color: Colors.orange.shade700,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            // Wrap buttons in FocusTraversalGroup for horizontal navigation
            FocusTraversalGroup(
              policy: OrderedTraversalPolicy(),
              child: Row(
                children: [
                  if (isVirtualFolder) ...[
                    // Virtual Season folder - just open it
                    Expanded(
                      child: FilledButton.icon(
                        autofocus: index == 0,
                        onPressed: () => _navigateIntoVirtualFolder(file),
                        icon: const Icon(Icons.folder_open, size: 18),
                        label: const Text('Open'),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.purple.shade700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ] else if (isFolder) ...[
                    Expanded(
                      child: FilledButton.icon(
                        autofocus: index == 0, // Auto-focus first item's button
                        onPressed: () => _navigateIntoFolder(file['id'], name),
                        icon: const Icon(Icons.folder_open, size: 18),
                        label: const Text('Open'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => _playFolder(file),
                        icon: const Icon(Icons.play_arrow, size: 18),
                        label: const Text('Play'),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.green.shade700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ] else if (isVideo && isComplete) ...[
                    Expanded(
                      child: FilledButton.icon(
                        autofocus: index == 0, // Auto-focus first item's button
                        onPressed: () => _playFile(file),
                        icon: const Icon(Icons.play_arrow, size: 18),
                        label: const Text('Play'),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  // 3-dot menu for actions (hidden for virtual folders)
                  if (!isVirtualFolder)
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert),
                      tooltip: 'More options',
                      onSelected: (value) {
                        if (value == 'delete') {
                          _showDeleteDialog(file);
                        } else if (value == 'add_to_playlist') {
                          _handleAddToPlaylist(file);
                        } else if (value == 'download') {
                          if (isFolder) {
                            _downloadFolder(file);
                          } else {
                            _downloadFile(file);
                          }
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
            ),
          ],
        ),
      ),
    );
  }

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

  /// Play all videos in a folder (recursively scans subfolders)
  Future<void> _playFolder(Map<String, dynamic> folder) async {
    final folderId = folder['id'] as String?;
    final folderName = folder['name'] ?? 'Folder';

    if (folderId == null) {
      _showSnackBar('Invalid folder ID', isError: true);
      return;
    }

    // Show loading dialog
    if (!mounted) return;
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
              'Scanning folder for videos...',
              style: TextStyle(color: Colors.white),
            ),
          ],
        ),
      ),
    );

    try {
      // Recursively scan folder for all files
      final allFiles = await PikPakApiService.instance.listFilesRecursive(
        folderId: folderId,
      );

      // Close loading dialog
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }

      if (!mounted) return;

      // Filter for videos only
      List<Map<String, dynamic>> videoFiles = allFiles.where((file) {
        final mimeType = file['mime_type'] ?? '';
        final phase = file['phase'] ?? '';
        final isVideo = mimeType.startsWith('video/');
        final isComplete = phase == 'PHASE_TYPE_COMPLETE';
        return isVideo && isComplete;
      }).toList();

      // Apply user settings filters
      if (_showVideosOnly) {
        // Already filtered for videos above
      }

      if (_ignoreSmallVideos) {
        videoFiles = videoFiles.where((file) {
          final size = file['size'];
          if (size == null) return true;
          final sizeBytes = int.tryParse(size.toString()) ?? 0;
          final sizeMB = sizeBytes / (1024 * 1024);
          return sizeMB >= 100;
        }).toList();
      }

      if (videoFiles.isEmpty) {
        _showSnackBar('This folder doesn\'t contain any videos', isError: true);
        return;
      }

      // Use the same logic as torrent_search_screen.dart
      await _playPikPakVideos(videoFiles, folderName);
    } catch (e) {
      print('Error playing folder: $e');
      if (mounted) {
        // Close loading dialog if still open
        Navigator.of(context, rootNavigator: true).pop();
      }
      _showSnackBar('Failed to scan folder: $e', isError: true);
    }
  }

  /// Play PikPak videos (single or playlist) - mirrors torrent_search_screen.dart logic
  Future<void> _playPikPakVideos(
    List<Map<String, dynamic>> videoFiles,
    String collectionName,
  ) async {
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
          final title = file['name'] ?? collectionName;
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
        _showSnackBar('Failed to play: ${e.toString()}', isError: true);
      }
      return;
    }

    // Multiple videos - build playlist
    final entries = <_PikPakPlaylistItem>[];
    for (int i = 0; i < videoFiles.length; i++) {
      final file = videoFiles[i];
      final displayName = _pikpakDisplayName(file);
      final info = SeriesParser.parseFilename(displayName);
      entries.add(
        _PikPakPlaylistItem(
          file: file,
          originalIndex: i,
          seriesInfo: info,
          displayName: displayName,
        ),
      );
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

    // Find first episode to start from
    final seriesInfos = sortedEntries.map((e) => e.seriesInfo).toList();
    int startIndex = isSeriesCollection
        ? _findFirstEpisodeIndex(seriesInfos)
        : 0;
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
      _showSnackBar('Failed to prepare stream: ${e.toString()}', isError: true);
      return;
    }

    if (initialUrl.isEmpty) {
      _showSnackBar('Could not get streaming URL', isError: true);
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
      playlistEntries.add(
        PlaylistEntry(
          url: i == startIndex ? initialUrl : '',
          title: combinedTitle,
          provider: 'pikpak',
          pikpakFileId: entry.file['id'],
          sizeBytes: int.tryParse(entry.file['size']?.toString() ?? '0'),
        ),
      );
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
        title: collectionName,
        subtitle: subtitle,
        playlist: playlistEntries,
        startIndex: startIndex,
      ),
    );
  }

  /// Handle adding a file or folder to playlist
  Future<void> _handleAddToPlaylist(Map<String, dynamic> file) async {
    final kind = file['kind'] ?? '';
    final isFolder = kind == 'drive#folder';

    if (isFolder) {
      await _addFolderToPlaylist(file);
    } else {
      await _addSingleFileToPlaylist(file);
    }
  }

  /// Add a single video file to playlist
  Future<void> _addSingleFileToPlaylist(Map<String, dynamic> file) async {
    final mimeType = file['mime_type'] ?? '';
    final isVideo = mimeType.startsWith('video/');

    if (!isVideo) {
      _showSnackBar('Only video files can be added to playlist', isError: true);
      return;
    }

    final added = await StorageService.addPlaylistItemRaw({
      'provider': 'pikpak',
      'title': FileUtils.cleanPlaylistTitle(file['name'] ?? 'Video'),
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

    _showSnackBar(
      added ? 'Added to playlist' : 'Already in playlist',
      isError: !added,
    );
  }

  /// Add all videos in a folder to playlist (recursively scans subfolders)
  Future<void> _addFolderToPlaylist(Map<String, dynamic> folder) async {
    final folderId = folder['id'] as String?;
    final folderName = folder['name'] ?? 'Folder';

    if (folderId == null) {
      _showSnackBar('Invalid folder ID', isError: true);
      return;
    }

    // Show loading dialog
    if (!mounted) return;
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
              'Scanning folder for videos...',
              style: TextStyle(color: Colors.white),
            ),
          ],
        ),
      ),
    );

    try {
      // Recursively scan folder for all files
      final allFiles = await PikPakApiService.instance.listFilesRecursive(
        folderId: folderId,
      );

      // Close loading dialog
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }

      if (!mounted) return;

      // Filter for videos only
      List<Map<String, dynamic>> videoFiles = allFiles.where((file) {
        final mimeType = file['mime_type'] ?? '';
        final phase = file['phase'] ?? '';
        final isVideo = mimeType.startsWith('video/');
        final isComplete = phase == 'PHASE_TYPE_COMPLETE';
        return isVideo && isComplete;
      }).toList();

      // Apply user settings filters
      if (_ignoreSmallVideos) {
        videoFiles = videoFiles.where((file) {
          final size = file['size'];
          if (size == null) return true;
          final sizeBytes = int.tryParse(size.toString()) ?? 0;
          final sizeMB = sizeBytes / (1024 * 1024);
          return sizeMB >= 100;
        }).toList();
      }

      if (videoFiles.isEmpty) {
        _showSnackBar('This folder doesn\'t contain any videos', isError: true);
        return;
      }

      // Add to playlist
      if (videoFiles.length == 1) {
        // Single video file - store full metadata for instant playback
        final file = videoFiles.first;
        final added = await StorageService.addPlaylistItemRaw({
          'provider': 'pikpak',
          'title': FileUtils.cleanPlaylistTitle(file['name'] ?? folderName),
          'kind': 'single',
          'pikpakFileId': file['id'],
          'pikpakFile': {
            'id': file['id'],
            'name': file['name'],
            'size': file['size'],
            'mime_type': file['mime_type'],
          },
          'sizeBytes': int.tryParse(file['size']?.toString() ?? '0'),
        });
        _showSnackBar(
          added ? 'Added to playlist' : 'Already in playlist',
          isError: !added,
        );
      } else {
        // Multiple videos - save as collection with full metadata for instant playback
        // Store both pikpakFiles (new format) and pikpakFileIds (for dedupe compatibility)
        final fileIds = videoFiles.map((f) => f['id'] as String).toList();
        final filesMetadata = videoFiles
            .map(
              (f) => {
                'id': f['id'],
                'name': f['name'],
                'size': f['size'],
                'mime_type': f['mime_type'],
              },
            )
            .toList();

        final added = await StorageService.addPlaylistItemRaw({
          'provider': 'pikpak',
          'title': FileUtils.cleanPlaylistTitle(folderName),
          'kind': 'collection',
          'pikpakFileId': folderId, // Store the folder ID for folder structure
          'pikpakFiles':
              filesMetadata, // NEW: Full metadata for instant playback
          'pikpakFileIds':
              fileIds, // KEEP: For backward compatibility and deduplication
          'count': videoFiles.length,
        });
        _showSnackBar(
          added
              ? 'Added ${videoFiles.length} videos to playlist'
              : 'Already in playlist',
          isError: !added,
        );
      }
    } catch (e) {
      print('Error adding folder to playlist: $e');
      if (mounted) {
        // Close loading dialog if still open
        Navigator.of(context, rootNavigator: true).pop();
      }
      _showSnackBar('Failed to scan folder: $e', isError: true);
    }
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
}

/// Helper class for building PikPak playlists
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
