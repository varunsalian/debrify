import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/pikpak_api_service.dart';
import '../../services/storage_service.dart';
import '../../services/video_player_launcher.dart';
import '../../utils/formatters.dart';

class PikPakFilesScreen extends StatefulWidget {
  const PikPakFilesScreen({super.key});

  @override
  State<PikPakFilesScreen> createState() => _PikPakFilesScreenState();
}

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

  // Folder navigation state
  String? _currentFolderId;
  String _currentFolderName = 'My Files';
  final List<({String? id, String name})> _navigationStack = [];

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final enabled = await StorageService.getPikPakEnabled();
    final showVideosOnly = await StorageService.getPikPakShowVideosOnly();
    final ignoreSmallVideos = await StorageService.getPikPakIgnoreSmallVideos();
    final email = await PikPakApiService.instance.getEmail();

    if (!mounted) return;

    setState(() {
      _pikpakEnabled = enabled;
      _showVideosOnly = showVideosOnly;
      _ignoreSmallVideos = ignoreSmallVideos;
      _email = email;
    });

    if (enabled) {
      _loadFiles();
    }
  }

  Future<void> _loadFiles() async {
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final files = await PikPakApiService.instance.listFiles(parentId: _currentFolderId);

      if (!mounted) return;

      // Filter files based on settings
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

      setState(() {
        _files.clear();
        _files.addAll(filteredFiles);
        _isLoading = false;
        _initialLoad = false;
      });
    } catch (e) {
      print('Error loading PikPak files: $e');
      if (!mounted) return;

      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
        _initialLoad = false;
      });
    }
  }

  void _navigateIntoFolder(String folderId, String folderName) {
    setState(() {
      // Push current folder to stack before navigating
      _navigationStack.add((id: _currentFolderId, name: _currentFolderName));
      _currentFolderId = folderId;
      _currentFolderName = folderName;
    });
    _loadFiles();
  }

  void _navigateUp() {
    setState(() {
      // Pop from stack to go back one level
      if (_navigationStack.isNotEmpty) {
        final previous = _navigationStack.removeLast();
        _currentFolderId = previous.id;
        _currentFolderName = previous.name;
      } else {
        // Already at root
        _currentFolderId = null;
        _currentFolderName = 'My Files';
      }
    });
    _loadFiles();
  }

  Future<void> _playFile(Map<String, dynamic> fileData) async {
    try {
      // Check if it's a folder
      final kind = fileData['kind'];
      if (kind == 'drive#folder') {
        _showSnackBar('Cannot play folders. Please select a video file.', isError: true);
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
        builder: (dialogContext) => const Center(
          child: CircularProgressIndicator(),
        ),
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
      final streamingUrl = PikPakApiService.instance.getStreamingUrl(freshFileData);

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

  Future<void> _deleteFile(Map<String, dynamic> fileData) async {
    final fileName = fileData['name'] ?? 'this file';

    // Confirm deletion
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete File'),
        content: Text('Are you sure you want to delete "$fileName"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    _showSnackBar('Delete functionality coming soon...', isError: false);
    // TODO: Implement delete via PikPak API
  }

  Future<void> _refreshFiles() async {
    await _loadFiles();
    _showSnackBar('Files refreshed', isError: false);
  }

  void _showSnackBar(String message, {bool isError = true, Duration? duration}) {
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

  @override
  Widget build(BuildContext context) {
    if (!_pikpakEnabled) {
      return _buildNotEnabled();
    }

    if (_initialLoad && _isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_errorMessage.isNotEmpty) {
      return _buildError();
    }

    return Scaffold(
      appBar: AppBar(
        leading: _currentFolderId != null
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: _navigateUp,
                tooltip: 'Back',
              )
            : null,
        title: Text(_currentFolderName),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _refreshFiles,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshFiles,
        child: _files.isEmpty ? _buildEmpty() : _buildFileList(),
      ),
    );
  }

  Widget _buildNotEnabled() {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PikPak Files'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.cloud_off,
                size: 64,
                color: Colors.grey.shade400,
              ),
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
                onPressed: () {
                  // TODO: Navigate to settings
                  _showSnackBar('Open Settings > PikPak to configure', isError: false);
                },
                icon: const Icon(Icons.settings),
                label: const Text('Go to Settings'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildError() {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PikPak Files'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 64,
                color: Colors.red.shade400,
              ),
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
                onPressed: _refreshFiles,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
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
            Icon(
              Icons.folder_open,
              size: 64,
              color: Colors.grey.shade400,
            ),
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
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: _files.length,
      itemBuilder: (context, index) {
        final file = _files[index];
        return _buildFileCard(file);
      },
    );
  }

  Widget _buildFileCard(Map<String, dynamic> file) {
    final name = file['name'] ?? 'Unknown';
    final size = file['size'];
    final mimeType = file['mime_type'] ?? '';
    final kind = file['kind'] ?? '';
    final phase = file['phase'] ?? '';
    final createdTime = file['created_time'] ?? '';

    final isFolder = kind == 'drive#folder';
    final isVideo = mimeType.startsWith('video/');
    final isComplete = phase == 'PHASE_TYPE_COMPLETE';

    // Videos are ready to play if they're complete
    // We'll check for actual streaming links when playing
    final hasStreamingLink = isVideo && isComplete;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: isFolder
            ? () => _navigateIntoFolder(file['id'], name)
            : isVideo
                ? () => _playFile(file)
                : null,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    isFolder
                        ? Icons.folder
                        : isVideo
                            ? Icons.play_circle_outline
                            : Icons.insert_drive_file,
                    color: isFolder
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
                                Formatters.formatFileSize(int.tryParse(size.toString()) ?? 0),
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
              Row(
                children: [
                  if (isFolder) ...[
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => _navigateIntoFolder(file['id'], name),
                        icon: const Icon(Icons.folder_open, size: 18),
                        label: const Text('Open'),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ] else if (isVideo && isComplete) ...[
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => _playFile(file),
                        icon: const Icon(Icons.play_arrow, size: 18),
                        label: const Text('Play'),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _deleteFile(file),
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: const Text('Delete'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
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
}
