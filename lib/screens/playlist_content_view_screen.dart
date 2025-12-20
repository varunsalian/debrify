import 'package:flutter/material.dart';

import '../models/rd_file_node.dart';
import '../models/series_playlist.dart';
import '../services/storage_service.dart';
import '../services/debrid_service.dart';
import '../services/torbox_service.dart';
import '../services/pikpak_api_service.dart';
import '../services/video_player_launcher.dart';
import '../services/main_page_bridge.dart';
import '../services/episode_info_service.dart';
import '../services/tvmaze_service.dart';
import '../utils/series_parser.dart';
import '../utils/file_utils.dart';
import '../utils/formatters.dart';
import '../utils/rd_folder_tree_builder.dart';
import '../utils/torbox_folder_tree_builder.dart';
import '../widgets/view_mode_dropdown.dart';
import '../widgets/tvmaze_search_dialog.dart';
import 'video_player_screen.dart';

/// Screen for viewing contents of a playlist item
/// Supports Raw, Sort, and Series Arrange view modes
/// Handles folder navigation and progress tracking
class PlaylistContentViewScreen extends StatefulWidget {
  final Map<String, dynamic> playlistItem;
  final VoidCallback? onPlaybackStarted;

  const PlaylistContentViewScreen({
    super.key,
    required this.playlistItem,
    this.onPlaybackStarted,
  });

  @override
  State<PlaylistContentViewScreen> createState() => _PlaylistContentViewScreenState();
}

class _PlaylistContentViewScreenState extends State<PlaylistContentViewScreen> {
  bool _isLoading = true;
  String? _errorMessage;

  // Current navigation state
  List<String> _folderPath = []; // Path segments for breadcrumbs
  RDFileNode? _rootContent; // Root content tree
  List<RDFileNode>? _currentViewNodes; // Current folder's visible nodes (after view mode transformation)

  // View mode state
  FolderViewMode _currentViewMode = FolderViewMode.raw;

  // Focus management for TV navigation
  final FocusNode _viewModeDropdownFocusNode = FocusNode(debugLabel: 'playlist-view-mode-dropdown');
  final FocusNode _backButtonFocusNode = FocusNode(debugLabel: 'playlist-back-button');

  // Progress tracking cache
  Map<String, Map<String, dynamic>> _fileProgressCache = {};

  // OTT View state
  SeriesPlaylist? _seriesPlaylist;
  int _selectedSeasonNumber = 1;
  bool _isLoadingSeriesMetadata = false;

  @override
  void initState() {
    super.initState();
    _initializeScreen();
  }

  /// Initialize screen by loading saved mode first, then content
  Future<void> _initializeScreen() async {
    // Load saved view mode first
    await _loadSavedViewMode();

    // Then load content
    await _loadContent();

    // Parse series playlist BEFORE applying view mode
    // This ensures _seriesPlaylist is available when _applyViewMode() checks it
    if (_rootContent != null) {
      await _parseSeriesPlaylist();

      // Auto-set Series View for detected series (only if no saved preference exists)
      final savedViewMode = await StorageService.getPlaylistItemViewMode(widget.playlistItem);
      if (_seriesPlaylist?.isSeries == true && savedViewMode == null) {
        setState(() {
          _currentViewMode = FolderViewMode.seriesArrange;
        });
      }

      // THEN apply view mode (can now use _seriesPlaylist.isSeries)
      _applyViewMode(_currentViewMode);
    }

    // Note: Progress is now loaded within _parseSeriesPlaylist()
    // so we don't need to call _loadProgressData() here anymore
  }

  @override
  void dispose() {
    _viewModeDropdownFocusNode.dispose();
    _backButtonFocusNode.dispose();
    super.dispose();
  }

  /// Load saved view mode for this playlist item
  Future<void> _loadSavedViewMode() async {
    final savedModeString = await StorageService.getPlaylistItemViewMode(widget.playlistItem);
    if (savedModeString != null && mounted) {
      setState(() {
        _currentViewMode = _viewModeFromString(savedModeString);
      });
    }
  }

  /// Convert string to FolderViewMode
  FolderViewMode _viewModeFromString(String mode) {
    switch (mode) {
      case 'raw':
        return FolderViewMode.raw;
      case 'sortedAZ':
        return FolderViewMode.sortedAZ;
      case 'seriesArrange':
        return FolderViewMode.seriesArrange;
      default:
        return FolderViewMode.raw;
    }
  }

  /// Convert FolderViewMode to string
  String _viewModeToString(FolderViewMode mode) {
    switch (mode) {
      case FolderViewMode.raw:
        return 'raw';
      case FolderViewMode.sortedAZ:
        return 'sortedAZ';
      case FolderViewMode.seriesArrange:
        return 'seriesArrange';
    }
  }

  /// Load progress data for all files
  Future<void> _loadProgressData() async {
    try {
      // Get the series/collection title from the playlist item
      final String? seriesTitle = widget.playlistItem['seriesTitle'] as String?;
      print('🎬 Loading progress for series: $seriesTitle');
      print('📦 Playlist item keys: ${widget.playlistItem.keys.toList()}');

      // If it's a series, load all episode progress
      if (seriesTitle != null && seriesTitle.isNotEmpty) {
        final episodeProgress = await StorageService.getEpisodeProgress(
          seriesTitle: seriesTitle,
        );
        print('📊 Loaded ${episodeProgress.length} episodes with progress');
        print('🔑 Progress keys: ${episodeProgress.keys.toList()}');
        setState(() {
          _fileProgressCache = episodeProgress;
        });
      } else {
        print('⚠️ No series title found, trying fallback methods');
        // Fallback: try to get title from other fields
        final title = widget.playlistItem['title'] as String?;
        if (title != null) {
          print('🔄 Trying with title: $title');
          final episodeProgress = await StorageService.getEpisodeProgress(
            seriesTitle: title,
          );
          print('📊 Loaded ${episodeProgress.length} episodes with progress');
          print('🔑 Progress keys: ${episodeProgress.keys.toList()}');
          setState(() {
            _fileProgressCache = episodeProgress;
          });
        } else {
          _fileProgressCache = {};
        }
      }
    } catch (e) {
      print('❌ Error loading progress data: $e');
      _fileProgressCache = {};
    }
  }

  /// Load content from provider
  Future<void> _loadContent() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final provider = (widget.playlistItem['provider'] as String?) ?? 'realdebrid';

      if (provider == 'torbox') {
        await _loadTorboxContent();
      } else if (provider == 'pikpak') {
        await _loadPikPakContent();
      } else {
        await _loadRealDebridContent();
      }

      // Note: View mode is now applied in _initializeScreen() after _parseSeriesPlaylist()
      // This ensures _seriesPlaylist is available for series detection
    } catch (e) {
      print('Error loading content: $e');
      setState(() {
        _errorMessage = 'Failed to load content: ${e.toString()}';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /// Load Real-Debrid content
  Future<void> _loadRealDebridContent() async {
    final rdTorrentId = widget.playlistItem['rdTorrentId'] as String?;
    if (rdTorrentId == null) {
      throw Exception('No Real-Debrid torrent ID found');
    }

    final apiKey = await StorageService.getApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      throw Exception('No API key configured');
    }

    final info = await DebridService.getTorrentInfo(apiKey, rdTorrentId);
    final allFiles = (info['files'] as List<dynamic>? ?? const []);

    if (allFiles.isEmpty) {
      throw Exception('No files found in torrent');
    }

    // Use existing RDFolderTreeBuilder utility
    _rootContent = RDFolderTreeBuilder.buildTree(allFiles.cast<Map<String, dynamic>>());
  }

  /// Load Torbox content
  Future<void> _loadTorboxContent() async {
    final torboxTorrentId = widget.playlistItem['torboxTorrentId'] as int?;
    if (torboxTorrentId == null) {
      throw Exception('No Torbox torrent ID found');
    }

    final String? apiKey = await StorageService.getTorboxApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      throw Exception('Please set your Torbox API key in Settings');
    }

    final cachedTorrent = await TorboxService.getTorrentById(apiKey, torboxTorrentId);
    if (cachedTorrent == null) {
      throw Exception('Torrent not found');
    }

    final allFiles = cachedTorrent.files ?? [];
    if (allFiles.isEmpty) {
      throw Exception('No files found in torrent');
    }

    // Use existing TorboxFolderTreeBuilder utility which accepts TorboxFile objects
    _rootContent = TorboxFolderTreeBuilder.buildTree(allFiles);
  }

  /// Load PikPak content
  Future<void> _loadPikPakContent() async {
    // Get the folder/file ID
    final pikpakFileId = widget.playlistItem['pikpakFileId'] as String?;

    if (pikpakFileId != null) {
      // Preferred: Fetch fresh folder structure from PikPak
      _rootContent = await _buildPikPakFolderTree(pikpakFileId);
    } else {
      // Fallback: Use cached files (for old playlist items without pikpakFileId)
      final cachedFiles = widget.playlistItem['pikpakFiles'] as List?;
      if (cachedFiles != null && cachedFiles.isNotEmpty) {
        final files = cachedFiles.cast<Map<String, dynamic>>();
        _rootContent = _buildPikPakFileTree(files);
      } else {
        throw Exception('No PikPak file data found. Please remove and re-add this item to playlist.');
      }
    }
  }

  /// Build folder tree from PikPak by fetching folder structure
  /// This properly preserves the folder hierarchy
  Future<RDFileNode> _buildPikPakFolderTree(String folderId, {int depth = 0, String currentPath = ''}) async {
    final pikpak = PikPakApiService.instance;

    // Prevent infinite recursion or excessively deep folder structures
    const int maxDepth = 4;
    if (depth > maxDepth) {
      throw Exception('Folder hierarchy too deep (max $maxDepth levels). Please reorganize your folders.');
    }

    // Fetch files in this folder (non-recursive)
    final result = await pikpak.listFiles(parentId: folderId, limit: 100);
    final files = result.files;

    final List<RDFileNode> children = [];
    int fileIndex = 0;

    for (final file in files) {
      final kind = file['kind'] ?? '';
      final name = (file['name'] as String?) ?? 'Unknown';
      final fileId = file['id'] as String?;

      if (kind == 'drive#folder') {
        // Recursively build subfolder
        if (fileId != null) {
          // Build path for subfolder
          final subPath = currentPath.isEmpty ? name : '$currentPath/$name';
          final subTree = await _buildPikPakFolderTree(fileId, depth: depth + 1, currentPath: subPath);
          children.add(RDFileNode.folder(
            name: name,
            children: subTree.children,
          ));
        }
      } else {
        // Add file node
        final sizeRaw = file['size'];
        final size = sizeRaw is int ? sizeRaw : (sizeRaw is String ? int.tryParse(sizeRaw) ?? 0 : 0);

        // Store the PikPak file metadata in the node's path field (we'll parse it later)
        // Format: "pikpak://fileId|fileName"
        final pikpakUrl = 'pikpak://$fileId|$name';

        // Build relative path for series parsing
        final relPath = currentPath.isEmpty ? name : '$currentPath/$name';

        children.add(RDFileNode.file(
          name: name,
          fileId: fileIndex,
          path: pikpakUrl, // Store PikPak file ID and name here
          relativePath: relPath, // Store clean path for series parsing
          bytes: size,
          linkIndex: fileIndex,
        ));
        fileIndex++;
      }
    }

    return RDFileNode.folder(name: 'Root', children: children);
  }

  /// Build file tree from PikPak files (from recursive list)
  /// Used as fallback for old playlist items without pikpakFileId
  /// Displays as a flat list since we don't have folder structure info
  RDFileNode _buildPikPakFileTree(List<Map<String, dynamic>> files) {
    final List<RDFileNode> nodes = [];

    for (int i = 0; i < files.length; i++) {
      final file = files[i];
      final kind = file['kind'] ?? '';
      final name = (file['name'] as String?) ?? 'Unknown';
      final fileId = file['id'] as String?;

      // PikPak returns size as String, need to parse it
      final sizeRaw = file['size'];
      final size = sizeRaw is int ? sizeRaw : (sizeRaw is String ? int.tryParse(sizeRaw) ?? 0 : 0);

      if (kind == 'drive#folder') {
        // Skip folders in flat view since we don't have hierarchy
        continue;
      } else if (fileId != null) {
        // Add file node with pikpak:// URL for playback
        final pikpakUrl = 'pikpak://$fileId|$name';

        nodes.add(RDFileNode.file(
          name: name,
          fileId: i,
          path: pikpakUrl, // Store PikPak file ID for playback
          bytes: size,
          linkIndex: i,
        ));
      }
    }

    return RDFileNode.folder(name: 'Root', children: nodes);
  }

  /// Apply view mode transformation
  void _applyViewMode(FolderViewMode mode) {
    if (_rootContent == null) return;

    setState(() {
      _currentViewMode = mode;

      // Get current folder's nodes
      RDFileNode currentFolder = _rootContent!;
      for (final segment in _folderPath) {
        // Find child folder by name
        RDFileNode? child;
        try {
          child = currentFolder.children.firstWhere(
            (c) => c.name == segment && c.isFolder,
          );
        } catch (e) {
          // Folder not found - reset to root
          print('Warning: Folder "$segment" not found in current view, resetting to root');
          _folderPath.clear();
          currentFolder = _rootContent!;
          break;
        }

        if (child != null) {
          currentFolder = child;
        }
      }

      // Apply transformation based on mode
      switch (mode) {
        case FolderViewMode.raw:
          _currentViewNodes = currentFolder.children;
          break;
        case FolderViewMode.sortedAZ:
          _currentViewNodes = _applySortedView(currentFolder.children);
          break;
        case FolderViewMode.seriesArrange:
          _currentViewNodes = _applySeriesArrangeView(currentFolder.children);
          break;
      }
    });

    // Save view mode preference
    StorageService.savePlaylistItemViewMode(widget.playlistItem, _viewModeToString(mode));
  }

  /// Apply sorted A-Z view
  List<RDFileNode> _applySortedView(List<RDFileNode> nodes) {
    final folders = nodes.where((n) => n.isFolder).toList();
    final files = nodes.where((n) => !n.isFolder).toList();

    // Sort folders with numerical handling (same logic as PikPak/RD/Torbox)
    folders.sort((a, b) {
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

    // Sort files with numerical handling (same logic as PikPak/RD/Torbox)
    files.sort((a, b) {
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

  /// Apply series arrange view (creates virtual season folders)
  List<RDFileNode> _applySeriesArrangeView(List<RDFileNode> nodes) {
    final videoFiles = nodes.where((n) => !n.isFolder && FileUtils.isVideoFile(n.name)).toList();
    final otherNodes = nodes.where((n) => n.isFolder || !FileUtils.isVideoFile(n.name)).toList();

    if (videoFiles.length < 3) {
      // Not enough files for series detection, fallback to sorted
      return _applySortedView(nodes);
    }

    // Use the already-parsed _seriesPlaylist instead of re-parsing filenames
    // This is more accurate (considers TVMaze mappings) and faster
    if (_seriesPlaylist == null || !_seriesPlaylist!.isSeries) {
      return _applySortedView(nodes);
    }

    // Parse filenames for season/episode extraction
    final filenames = videoFiles.map((f) => f.name).toList();
    final parsed = SeriesParser.parsePlaylist(filenames);

    // Group by season
    final Map<int, List<RDFileNode>> seasonMap = {};
    for (int i = 0; i < videoFiles.length; i++) {
      final info = parsed[i];
      if (info.isSeries && info.season != null) {
        seasonMap.putIfAbsent(info.season!, () => []);
        seasonMap[info.season!]!.add(videoFiles[i]);
      }
    }

    // Create virtual season folders
    final List<RDFileNode> seasonFolders = [];
    for (final seasonNum in seasonMap.keys.toList()..sort()) {
      final seasonFiles = seasonMap[seasonNum]!;
      seasonFolders.add(RDFileNode.folder(
        name: seasonNum == 0 ? 'Season 0 - Specials' : 'Season $seasonNum',
        children: seasonFiles,
      ));
    }

    return [...otherNodes, ...seasonFolders];
  }


  /// Navigate into a folder
  void _navigateIntoFolder(RDFileNode folder) {
    if (!folder.isFolder) return;

    setState(() {
      _folderPath.add(folder.name);
    });

    _applyViewMode(_currentViewMode);
  }

  /// Navigate up one level
  void _navigateUp() {
    if (_folderPath.isEmpty) {
      Navigator.of(context).pop();
      return;
    }

    setState(() {
      _folderPath.removeLast();
    });

    _applyViewMode(_currentViewMode);
  }

  /// Play a file with full playlist support
  Future<void> _playFile(RDFileNode file) async {
    if (file.isFolder || _rootContent == null) return;

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
              Text('Preparing playlist…', style: TextStyle(color: Colors.white)),
            ],
          ),
        ),
      );

      // Get all video files from the entire tree
      final allFiles = _rootContent!.getAllFiles();
      final videoFiles = allFiles
          .where((node) => FileUtils.isVideoFile(node.name))
          .toList();

      if (videoFiles.isEmpty) {
        if (Navigator.of(context).canPop()) Navigator.of(context).pop();
        return;
      }

      // Find the selected file index
      int startIndex = 0;
      for (int i = 0; i < videoFiles.length; i++) {
        if (videoFiles[i].name == file.name && videoFiles[i].path == file.path) {
          startIndex = i;
          break;
        }
      }

      final provider = ((widget.playlistItem['provider'] as String?) ?? 'realdebrid').toLowerCase();

      if (provider == 'realdebrid') {
        await _playRealDebridPlaylist(videoFiles, startIndex);
      } else if (provider == 'torbox') {
        await _playTorboxPlaylist(videoFiles, startIndex);
      } else if (provider == 'pikpak') {
        await _playPikPakPlaylist(videoFiles, startIndex);
      }

      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      print('❌ Error playing file: $e');
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to play file: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = (widget.playlistItem['title'] as String?) ?? 'Playlist Item';

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          focusNode: _backButtonFocusNode,
          icon: const Icon(Icons.arrow_back),
          onPressed: _navigateUp,
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 16)),
            if (_folderPath.isNotEmpty)
              Text(
                _folderPath.join(' > '),
                style: const TextStyle(fontSize: 12, color: Colors.white70),
              ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadContent,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Column(
        children: [
          // View mode dropdown
          if (!_isLoading && _errorMessage == null)
            ViewModeDropdown(
              currentMode: _currentViewMode,
              onModeChanged: _applyViewMode,
              focusNode: _viewModeDropdownFocusNode,
            ),

          // Content area
          Expanded(
            child: _buildContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.red),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _loadContent,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_currentViewNodes == null || _currentViewNodes!.isEmpty) {
      return const Center(child: Text('No files found'));
    }

    // For Series Arrange mode, show OTT-style view
    if (_currentViewMode == FolderViewMode.seriesArrange) {
      return _buildOTTView();
    }

    // For Raw and Sort modes, show file browser
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _currentViewNodes!.length,
      itemBuilder: (context, index) {
        final node = _currentViewNodes![index];
        return _buildFileCard(node);
      },
    );
  }

  Widget _buildFileCard(RDFileNode node) {
    final isFolder = node.isFolder;
    final isVideo = !isFolder && FileUtils.isVideoFile(node.name);

    // Get progress for this file (if it's a video)
    double progress = 0.0;
    bool isFinished = false;
    if (isVideo) {
      // Try to get progress from cache
      // For series, use season/episode key; for others use filename
      final progressData = _getProgressForFile(node);
      if (progressData != null) {
        final positionMs = progressData['positionMs'] as int? ?? 0;
        final durationMs = progressData['durationMs'] as int? ?? 0;
        if (durationMs > 0) {
          progress = positionMs / durationMs;
          // Consider finished if 90%+ watched or less than 2 minutes remaining
          isFinished = progress >= 0.9 || (durationMs - positionMs) < 120000;
        }
      }
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: const Color(0xFF1E293B),
      child: InkWell(
        onTap: () {
          if (isFolder) {
            _navigateIntoFolder(node);
          } else if (isVideo) {
            _playFile(node);
          }
        },
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  // Icon
                  Icon(
                    isFolder
                        ? Icons.folder
                        : isVideo
                            ? Icons.play_circle_outline
                            : Icons.insert_drive_file,
                    color: isFolder ? Colors.amber : Colors.blue,
                    size: 32,
                  ),
                  const SizedBox(width: 12),

                  // File info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          node.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          isFolder
                              ? '${node.fileCount} files • ${Formatters.formatFileSize(node.totalBytes)}'
                              : Formatters.formatFileSize(node.bytes ?? 0),
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Arrow for folders or progress indicator for videos
                  if (isFolder)
                    const Icon(Icons.chevron_right, color: Colors.white54)
                  else if (isVideo && progress > 0.0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isFinished ? const Color(0xFF059669) : Colors.blue,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        isFinished ? 'DONE' : '${(progress * 100).round()}%',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // Progress bar overlay for videos
            if (isVideo && progress > 0.0)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  height: 3,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.3),
                  ),
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: progress,
                    child: Container(
                      decoration: BoxDecoration(
                        color: isFinished ? const Color(0xFF059669) : Colors.blue,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Get progress data for a specific file
  Map<String, dynamic>? _getProgressForFile(RDFileNode file) {
    // Try to parse season/episode from filename for series
    final seriesInfo = SeriesParser.parseFilename(file.name);
    if (seriesInfo.isSeries && seriesInfo.season != null && seriesInfo.episode != null) {
      final key = '${seriesInfo.season}_${seriesInfo.episode}';
      return _fileProgressCache[key];
    }

    // For non-series collections, try using season 0 with index
    // Find the file index in all video files
    if (_rootContent != null && _seriesPlaylist != null && !_seriesPlaylist!.isSeries) {
      final allFiles = _rootContent!.getAllFiles();
      final videoFiles = allFiles
          .where((node) => FileUtils.isVideoFile(node.name))
          .toList();

      final fileIndex = videoFiles.indexWhere((node) =>
        node.name == file.name && node.path == file.path);

      if (fileIndex >= 0) {
        final key = '0_${fileIndex + 1}'; // season 0, 1-based episode index
        final progress = _fileProgressCache[key];
        if (progress != null) {
          return progress;
        }
      }
    }

    // Fallback: try using filename as key
    return _fileProgressCache[file.name];
  }

  /// Build OTT-style view for Series Arrange mode
  Widget _buildOTTView() {
    // Parse series playlist if not already done
    if (_seriesPlaylist == null && _rootContent != null) {
      _parseSeriesPlaylist();
    }

    if (_seriesPlaylist == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (!_seriesPlaylist!.isSeries) {
      // Auto-switch to Sort (A-Z) view after a brief delay
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted && _currentViewMode == FolderViewMode.seriesArrange) {
          setState(() {
            _currentViewMode = FolderViewMode.sortedAZ;
            _applyViewMode(FolderViewMode.sortedAZ);
          });
        }
      });

      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.info_outline, size: 48, color: Colors.white70),
              const SizedBox(height: 16),
              const Text(
                'No series detected in this content',
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 8),
              const Text(
                'Switching to Sort (A-Z) view...',
                style: TextStyle(color: Colors.white60, fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }

    final season = _seriesPlaylist!.getSeason(_selectedSeasonNumber);
    if (season == null) {
      // Default to first available season
      if (_seriesPlaylist!.seasons.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          setState(() {
            _selectedSeasonNumber = _seriesPlaylist!.seasons.first.seasonNumber;
          });
        });
      }
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        // Season selector
        _buildSeasonSelector(),

        // Loading indicator for metadata
        if (_isLoadingSeriesMetadata)
          const LinearProgressIndicator(),

        // Episode list
        Expanded(
          child: _buildEpisodeList(season),
        ),
      ],
    );
  }

  /// Parse series playlist from current view nodes
  Future<void> _parseSeriesPlaylist() async {
    if (_rootContent == null) return;

    try {
      // Get ALL video files recursively from the entire content tree
      final allFiles = _rootContent!.getAllFiles();
      final videoFiles = allFiles
          .where((node) => FileUtils.isVideoFile(node.name))
          .toList();

      if (videoFiles.isEmpty) {
        return;
      }

      // Create PlaylistEntry objects from video files
      final entries = videoFiles.map((f) => PlaylistEntry(
        url: '',  // Not needed for parsing
        title: f.name,
        relativePath: f.relativePath ?? f.path, // Use relativePath if available, fallback to path
      )).toList();

      // Get series/collection title from playlist item
      // Try 'seriesTitle' first (if previously extracted), fallback to 'title' (raw torrent name)
      final String? collectionTitle = widget.playlistItem['seriesTitle'] as String? ??
                                       widget.playlistItem['title'] as String?;

      _seriesPlaylist = SeriesPlaylist.fromPlaylistEntries(
        entries,
        collectionTitle: collectionTitle,
      );

      // Reload progress with the clean extracted series/collection title!
      // This works for both series and movie collections
      final String? titleForProgress = _seriesPlaylist!.seriesTitle ??
                                        widget.playlistItem['title'] as String?;

      if (titleForProgress != null && titleForProgress.isNotEmpty) {
        print('🔄 Reloading progress with clean title: $titleForProgress');
        print('📌 isSeries: ${_seriesPlaylist!.isSeries}');
        final episodeProgress = await StorageService.getEpisodeProgress(
          seriesTitle: titleForProgress,
        );
        print('📊 Loaded ${episodeProgress.length} episodes with progress');
        print('🔑 Progress keys: ${episodeProgress.keys.toList()}');
        _fileProgressCache = episodeProgress;
      }

      // Check if we have a saved TVMaze mapping (indicates cached data)
      // Only show loading indicator if data needs to be fetched
      bool showLoading = true;
      if (widget.playlistItem != null) {
        final mapping = await StorageService.getTVMazeSeriesMapping(widget.playlistItem!);
        if (mapping != null) {
          showLoading = false;  // Data should be cached, skip loading indicator
        }
      }

      if (showLoading) {
        setState(() {
          _isLoadingSeriesMetadata = true;
        });
      }

      // Fetch TVMaze metadata asynchronously
      if (_seriesPlaylist!.isSeries) {
        _seriesPlaylist!.fetchEpisodeInfo(playlistItem: widget.playlistItem).then((_) {
          if (mounted) {
            setState(() {
              _isLoadingSeriesMetadata = false;
            });
          }
        }).catchError((e) {
          print('Failed to fetch episode metadata: $e');
          if (mounted) {
            setState(() {
              _isLoadingSeriesMetadata = false;
            });
          }
        });
      }
    } catch (e) {
      print('Failed to parse series playlist: $e');
      setState(() {
        _isLoadingSeriesMetadata = false;
      });
    }
  }

  /// Show the Fix Metadata dialog to manually select a TV show
  Future<void> _showFixMetadataDialog() async {
    // Show the search dialog
    final selectedShow = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (context) => TVMazeSearchDialog(
        initialQuery: _seriesPlaylist?.seriesTitle ?? '',
      ),
    );

    if (selectedShow != null && mounted) {
      // 1. Get OLD mapping (before it's overwritten)
      final oldMapping = await StorageService.getTVMazeSeriesMapping(widget.playlistItem);
      final oldShowId = oldMapping?['tvmazeShowId'] as int?;

      // 2. Clear old show ID cache if it exists
      if (oldShowId != null && oldShowId != selectedShow['id']) {
        debugPrint('🧹 Clearing old show ID cache: $oldShowId');
        await TVMazeService.clearShowCache(oldShowId);
        await EpisodeInfoService.clearShowCache(oldShowId);
      }

      // 3. Clear series name cache (existing logic)
      await EpisodeInfoService.clearSeriesCache(_seriesPlaylist?.seriesTitle ?? '');
      await TVMazeService.clearSeriesCache(_seriesPlaylist?.seriesTitle ?? '');

      // 4. Save new mapping
      await StorageService.saveTVMazeSeriesMapping(
        playlistItem: widget.playlistItem,
        tvmazeShowId: selectedShow['id'] as int,
        showName: selectedShow['name'] as String,
      );

      // Update playlist item poster/cover image
      await _updatePlaylistPoster(selectedShow);

      // Show success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Metadata fixed! Using "${selectedShow['name']}" from TVMaze'),
            backgroundColor: Colors.green,
          ),
        );
      }

      // Reload episode info with the new show ID
      if (_seriesPlaylist != null && _seriesPlaylist!.isSeries && mounted) {
        setState(() {
          _isLoadingSeriesMetadata = true;
        });

        _seriesPlaylist!.fetchEpisodeInfo(playlistItem: widget.playlistItem).then((_) {
          if (mounted) {
            setState(() {
              _isLoadingSeriesMetadata = false;
            });
          }
        }).catchError((e) {
          print('Failed to refresh episode metadata: $e');
          if (mounted) {
            setState(() {
              _isLoadingSeriesMetadata = false;
            });
          }
        });
      }
    }
  }

  /// Update the playlist item's poster/cover image with the TVMaze show poster
  Future<void> _updatePlaylistPoster(Map<String, dynamic> showInfo) async {
    try {
      // Extract poster URL from TVMaze show data
      // TVMaze provides 'image' with 'medium' and 'original' URLs
      final image = showInfo['image'];
      String? posterUrl;

      if (image != null && image is Map<String, dynamic>) {
        // Prefer original over medium for better quality
        posterUrl = image['original'] as String? ?? image['medium'] as String?;
      }

      if (posterUrl == null || posterUrl.isEmpty) {
        print('No poster URL found in TVMaze show data');
        return;
      }

      print('🎬 Updating playlist poster with: $posterUrl');

      // CRITICAL: Save poster override to persistent storage
      // This ensures the poster persists across app restarts
      await StorageService.savePlaylistPosterOverride(
        playlistItem: widget.playlistItem,
        posterUrl: posterUrl,
      );

      // Also update the in-memory playlist item for immediate UI update
      final provider = (widget.playlistItem['provider'] as String?) ?? 'realdebrid';
      bool updated = false;

      if (provider.toLowerCase() == 'realdebrid') {
        final rdTorrentId = widget.playlistItem['rdTorrentId'] as String?;
        if (rdTorrentId != null) {
          updated = await StorageService.updatePlaylistItemPoster(
            posterUrl,
            rdTorrentId: rdTorrentId,
          );
        }
      } else if (provider.toLowerCase() == 'torbox') {
        final torboxTorrentId = widget.playlistItem['torboxTorrentId'];
        if (torboxTorrentId != null) {
          // Torbox uses integer IDs, but updatePlaylistItemPoster expects String
          // We need to update the playlist manually
          final items = await StorageService.getPlaylistItemsRaw();
          final itemIndex = items.indexWhere(
            (item) => item['torboxTorrentId'] == torboxTorrentId,
          );

          if (itemIndex >= 0) {
            items[itemIndex]['posterUrl'] = posterUrl;
            await StorageService.savePlaylistItemsRaw(items);
            updated = true;
          }
        }
      } else if (provider.toLowerCase() == 'pikpak') {
        final pikpakCollectionId = widget.playlistItem['pikpakCollectionId'] as String?;
        if (pikpakCollectionId != null) {
          updated = await StorageService.updatePlaylistItemPoster(
            posterUrl,
            pikpakCollectionId: pikpakCollectionId,
          );
        }
      }

      if (updated) {
        print('✅ Successfully updated playlist poster in memory and persistent storage');
      } else {
        print('⚠️ Updated persistent storage but in-memory update failed - poster will still persist on restart');
      }
    } catch (e) {
      print('❌ Error updating playlist poster: $e');
    }
  }

  /// Build season selector dropdown
  Widget _buildSeasonSelector() {
    if (_seriesPlaylist == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.1),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.video_library, size: 20, color: Colors.white70),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _seriesPlaylist!.seriesTitle ?? 'Series',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 12),
          // Fix Metadata button
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _showFixMetadataDialog,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.orange.withValues(alpha: 0.5),
                    width: 1,
                  ),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.build,
                      color: Colors.orange,
                      size: 14,
                    ),
                    SizedBox(width: 4),
                    Text(
                      'Fix Metadata',
                      style: TextStyle(
                        color: Colors.orange,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          DropdownButton<int>(
            value: _selectedSeasonNumber,
            dropdownColor: const Color(0xFF1E293B),
            underline: const SizedBox.shrink(),
            items: _seriesPlaylist!.seasons.map((season) {
              return DropdownMenuItem(
                value: season.seasonNumber,
                child: Text(
                  season.seasonNumber == 0
                      ? 'Specials'
                      : 'Season ${season.seasonNumber}',
                  style: const TextStyle(fontSize: 14),
                ),
              );
            }).toList(),
            onChanged: (value) {
              if (value != null) {
                setState(() {
                  _selectedSeasonNumber = value;
                });
              }
            },
          ),
        ],
      ),
    );
  }

  /// Build episode list
  Widget _buildEpisodeList(SeriesSeason season) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: season.episodes.length,
      itemBuilder: (context, index) {
        final episode = season.episodes[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: _buildEpisodeCard(episode),
        );
      },
    );
  }

  /// Build episode card with responsive layout (vertical on mobile, horizontal on desktop)
  Widget _buildEpisodeCard(SeriesEpisode episode) {
    // Get progress for this episode
    double progress = 0.0;
    bool isFinished = false;
    if (episode.seriesInfo.season != null && episode.seriesInfo.episode != null) {
      final key = '${episode.seriesInfo.season}_${episode.seriesInfo.episode}';
      print('🔍 Looking for progress with key: $key for ${episode.displayTitle}');
      print('💾 Available keys in cache: ${_fileProgressCache.keys.toList()}');
      final progressData = _fileProgressCache[key];
      if (progressData != null) {
        print('✅ Found progress data: $progressData');
        final positionMs = progressData['positionMs'] as int? ?? 0;
        final durationMs = progressData['durationMs'] as int? ?? 0;
        if (durationMs > 0) {
          progress = positionMs / durationMs;
          isFinished = progress >= 0.9 || (durationMs - positionMs) < 120000;
          print('📈 Progress: ${(progress * 100).round()}%, Finished: $isFinished');
        }
      } else {
        print('❌ No progress data found for key: $key');
      }
    }

    final episodeInfo = episode.episodeInfo;
    final hasMetadata = episodeInfo != null;

    // Detect screen width for responsive layout
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;

    return Card(
      color: const Color(0xFF1E293B),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _playEpisode(episode),
        child: isMobile
            ? _buildMobileEpisodeCard(episode, progress, isFinished, hasMetadata, episodeInfo)
            : _buildDesktopEpisodeCard(episode, progress, isFinished, hasMetadata, episodeInfo),
      ),
    );
  }

  /// Build mobile vertical layout (thumbnail top, info bottom)
  Widget _buildMobileEpisodeCard(
    SeriesEpisode episode,
    double progress,
    bool isFinished,
    bool hasMetadata,
    EpisodeInfo? episodeInfo,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Thumbnail section with 16:9 aspect ratio
        AspectRatio(
          aspectRatio: 16 / 9,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Episode thumbnail or placeholder
              if (hasMetadata && episodeInfo!.poster != null)
                Image.network(
                  episodeInfo.poster!,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return _buildThumbnailPlaceholder(episode);
                  },
                )
              else
                _buildThumbnailPlaceholder(episode),

              // Play button overlay
              Center(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.7),
                    shape: BoxShape.circle,
                  ),
                  padding: const EdgeInsets.all(16),
                  child: const Icon(
                    Icons.play_arrow,
                    color: Colors.white,
                    size: 40,
                  ),
                ),
              ),

              // Top left: Episode number badge
              Positioned(
                top: 8,
                left: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: const Color(0xFF6366F1),
                      width: 1.5,
                    ),
                  ),
                  child: Text(
                    episode.seasonEpisodeString,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),

              // Top right: IMDB rating badge
              if (hasMetadata && episodeInfo!.rating != null)
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5C518),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.star, color: Colors.black, size: 14),
                        const SizedBox(width: 4),
                        Text(
                          episodeInfo.rating!.toStringAsFixed(1),
                          style: const TextStyle(
                            color: Colors.black,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // Watch status badge (bottom left corner)
              if (progress > 0.0)
                Positioned(
                  bottom: 8,
                  left: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: isFinished
                          ? const Color(0xFF059669)
                          : const Color(0xFF6366F1),
                      borderRadius: BorderRadius.circular(6),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.4),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isFinished ? Icons.check_circle : Icons.play_circle_filled,
                          color: Colors.white,
                          size: 14,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          isFinished
                              ? 'WATCHED'
                              : '${(progress * 100).round()}%',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),

        // Info section below thumbnail
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Episode title with status chip
              Row(
                children: [
                  Expanded(
                    child: Text(
                      episode.displayTitle,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (progress > 0.0) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: isFinished
                            ? const Color(0xFF059669).withValues(alpha: 0.2)
                            : const Color(0xFF6366F1).withValues(alpha: 0.2),
                        border: Border.all(
                          color: isFinished
                              ? const Color(0xFF059669)
                              : const Color(0xFF6366F1),
                          width: 1,
                        ),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        isFinished ? 'WATCHED' : 'WATCHING',
                        style: TextStyle(
                          color: isFinished
                              ? const Color(0xFF059669)
                              : const Color(0xFF6366F1),
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),

              // Watch progress info
              if (progress > 0.0 && !isFinished)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Icon(
                        Icons.history,
                        size: 14,
                        color: const Color(0xFF6366F1),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${(progress * 100).round()}% watched',
                        style: const TextStyle(
                          color: Color(0xFF6366F1),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),

              // Runtime and Air date
              if (hasMetadata)
                Row(
                  children: [
                    if (episodeInfo!.runtime != null) ...[
                      const Icon(Icons.schedule, size: 14, color: Colors.white60),
                      const SizedBox(width: 4),
                      Text(
                        '${episodeInfo.runtime} min',
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 12,
                        ),
                      ),
                    ],
                    if (episodeInfo.runtime != null && episodeInfo.airDate != null)
                      const Text('  •  ', style: TextStyle(color: Colors.white60, fontSize: 12)),
                    if (episodeInfo.airDate != null) ...[
                      const Icon(Icons.calendar_today, size: 14, color: Colors.white60),
                      const SizedBox(width: 4),
                      Text(
                        episodeInfo.airDate!,
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              const SizedBox(height: 8),

              // Description
              if (hasMetadata && episodeInfo!.plot != null)
                Text(
                  episodeInfo.plot!,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    height: 1.4,
                  ),
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),

        // Progress bar at the bottom
        if (progress > 0.0)
          SizedBox(
            height: 6,
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: Colors.black.withValues(alpha: 0.3),
              valueColor: AlwaysStoppedAnimation<Color>(
                isFinished ? const Color(0xFF059669) : const Color(0xFF6366F1),
              ),
              minHeight: 6,
            ),
          ),
      ],
    );
  }

  /// Build desktop horizontal layout (thumbnail left, info right)
  Widget _buildDesktopEpisodeCard(
    SeriesEpisode episode,
    double progress,
    bool isFinished,
    bool hasMetadata,
    EpisodeInfo? episodeInfo,
  ) {
    return Column(
      children: [
        // Main content - horizontal layout
        SizedBox(
          height: 180,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left: Thumbnail with overlays
              SizedBox(
                width: 240,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Episode thumbnail or placeholder
                    if (hasMetadata && episodeInfo!.poster != null)
                      Image.network(
                        episodeInfo.poster!,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return _buildThumbnailPlaceholder(episode);
                        },
                      )
                    else
                      _buildThumbnailPlaceholder(episode),

                    // Play button overlay
                    Center(
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.7),
                          shape: BoxShape.circle,
                        ),
                        padding: const EdgeInsets.all(16),
                        child: const Icon(
                          Icons.play_arrow,
                          color: Colors.white,
                          size: 40,
                        ),
                      ),
                    ),

                    // Top left: Episode number badge
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.8),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: const Color(0xFF6366F1),
                            width: 1.5,
                          ),
                        ),
                        child: Text(
                          episode.seasonEpisodeString,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),

                    // Top right: IMDB rating badge
                    if (hasMetadata && episodeInfo?.rating != null)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF5C518),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.star, color: Colors.black, size: 14),
                              const SizedBox(width: 4),
                              Text(
                                episodeInfo!.rating!.toStringAsFixed(1),
                                style: const TextStyle(
                                  color: Colors.black,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                    // Watch status badge (bottom left corner)
                    if (progress > 0.0)
                      Positioned(
                        bottom: 8,
                        left: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: isFinished
                                ? const Color(0xFF059669)
                                : const Color(0xFF6366F1),
                            borderRadius: BorderRadius.circular(6),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.4),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isFinished ? Icons.check_circle : Icons.play_circle_filled,
                                color: Colors.white,
                                size: 14,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                isFinished
                                    ? 'WATCHED'
                                    : '${(progress * 100).round()}%',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              // Right: Episode info
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Episode title with status chip
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              episode.displayTitle,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (progress > 0.0) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: isFinished
                                    ? const Color(0xFF059669).withValues(alpha: 0.2)
                                    : const Color(0xFF6366F1).withValues(alpha: 0.2),
                                border: Border.all(
                                  color: isFinished
                                      ? const Color(0xFF059669)
                                      : const Color(0xFF6366F1),
                                  width: 1,
                                ),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                isFinished ? 'WATCHED' : 'WATCHING',
                                style: TextStyle(
                                  color: isFinished
                                      ? const Color(0xFF059669)
                                      : const Color(0xFF6366F1),
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 8),

                      // Watch progress info
                      if (progress > 0.0 && !isFinished)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              Icon(
                                Icons.history,
                                size: 14,
                                color: const Color(0xFF6366F1),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${(progress * 100).round()}% watched',
                                style: const TextStyle(
                                  color: Color(0xFF6366F1),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),

                      // Runtime and Air date
                      if (hasMetadata)
                        Row(
                          children: [
                            if (episodeInfo!.runtime != null) ...[
                              const Icon(Icons.schedule, size: 14, color: Colors.white60),
                              const SizedBox(width: 4),
                              Text(
                                '${episodeInfo!.runtime} min',
                                style: const TextStyle(
                                  color: Colors.white60,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                            if (episodeInfo!.runtime != null && episodeInfo!.airDate != null)
                              const Text('  •  ', style: TextStyle(color: Colors.white60)),
                            if (episodeInfo!.airDate != null) ...[
                              const Icon(Icons.calendar_today, size: 14, color: Colors.white60),
                              const SizedBox(width: 4),
                              Text(
                                episodeInfo!.airDate!,
                                style: const TextStyle(
                                  color: Colors.white60,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ],
                        ),
                      const SizedBox(height: 8),

                      // Description
                      if (hasMetadata && episodeInfo!.plot != null)
                        Expanded(
                          child: Text(
                            episodeInfo.plot!,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                              height: 1.4,
                            ),
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                          ),
                        )
                      else
                        const Spacer(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        // Progress bar at the bottom
        if (progress > 0.0)
          SizedBox(
            height: 6,
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: Colors.black.withValues(alpha: 0.3),
              valueColor: AlwaysStoppedAnimation<Color>(
                isFinished ? const Color(0xFF059669) : const Color(0xFF6366F1),
              ),
              minHeight: 6,
            ),
          ),
      ],
    );
  }

  /// Build thumbnail placeholder
  Widget _buildThumbnailPlaceholder(SeriesEpisode episode) {
    return Container(
      color: Colors.grey.shade900,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.video_library,
              color: Colors.white38,
              size: 48,
            ),
            const SizedBox(height: 8),
            Text(
              episode.seasonEpisodeString,
              style: const TextStyle(
                color: Colors.white38,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Play episode from OTT view with full playlist support
  Future<void> _playEpisode(SeriesEpisode episode) async {
    if (_rootContent == null || !mounted) return;

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
              Text('Preparing playlist…', style: TextStyle(color: Colors.white)),
            ],
          ),
        ),
      );

      // Get all video files from the entire tree
      final allFiles = _rootContent!.getAllFiles();
      final videoFiles = allFiles
          .where((node) => FileUtils.isVideoFile(node.name))
          .toList();

      if (videoFiles.isEmpty) {
        if (Navigator.of(context).canPop()) Navigator.of(context).pop();
        return;
      }

      // Find the selected episode index
      int startIndex = 0;
      if (episode.originalIndex >= 0 && episode.originalIndex < videoFiles.length) {
        startIndex = episode.originalIndex;
      } else {
        // Fallback: try to match by filename
        for (int i = 0; i < videoFiles.length; i++) {
          if (videoFiles[i].name == episode.filename) {
            startIndex = i;
            break;
          }
        }
      }

      final provider = ((widget.playlistItem['provider'] as String?) ?? 'realdebrid').toLowerCase();

      if (provider == 'realdebrid') {
        await _playRealDebridPlaylist(videoFiles, startIndex);
      } else if (provider == 'torbox') {
        await _playTorboxPlaylist(videoFiles, startIndex);
      } else if (provider == 'pikpak') {
        await _playPikPakPlaylist(videoFiles, startIndex);
      }

      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      print('❌ Error playing episode: $e');
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}')),
        );
      }
    }
  }

  /// Play Real-Debrid playlist
  Future<void> _playRealDebridPlaylist(List<RDFileNode> videoFiles, int startIndex) async {
    final String? apiKey = await StorageService.getApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      throw Exception('Please set your Real-Debrid API key in Settings');
    }

    final rdTorrentId = widget.playlistItem['rdTorrentId'] as String?;
    if (rdTorrentId == null) {
      throw Exception('No Real-Debrid torrent ID found');
    }

    final info = await DebridService.getTorrentInfo(apiKey, rdTorrentId);
    final links = (info['links'] as List<dynamic>?) ?? [];

    // Build playlist entries
    final List<PlaylistEntry> entries = [];
    for (int i = 0; i < videoFiles.length; i++) {
      final file = videoFiles[i];
      final linkIndex = file.linkIndex ?? i;

      if (linkIndex >= links.length) continue;

      if (i == startIndex) {
        // Unrestrict the first file
        try {
          final unrestrictResult = await DebridService.unrestrictLink(apiKey, links[linkIndex]);
          final url = unrestrictResult['download']?.toString() ?? '';
          entries.add(PlaylistEntry(
            url: url,
            title: file.name,
            relativePath: file.path,
            rdTorrentId: rdTorrentId,
            rdLinkIndex: linkIndex,
            sizeBytes: file.bytes,
          ));
        } catch (_) {
          entries.add(PlaylistEntry(
            url: '',
            title: file.name,
            relativePath: file.path,
            restrictedLink: links[linkIndex],
            rdTorrentId: rdTorrentId,
            rdLinkIndex: linkIndex,
            sizeBytes: file.bytes,
          ));
        }
      } else {
        entries.add(PlaylistEntry(
          url: '',
          title: file.name,
          relativePath: file.path,
          restrictedLink: links[linkIndex],
          rdTorrentId: rdTorrentId,
          rdLinkIndex: linkIndex,
          sizeBytes: file.bytes,
        ));
      }
    }

    if (entries.isEmpty) {
      throw Exception('No playable files found');
    }

    final String initialVideoUrl = entries[startIndex].url;
    final String seriesTitle = _seriesPlaylist?.seriesTitle ?? widget.playlistItem['title'] as String? ?? 'Series';

    if (!mounted) return;

    // Hide auto-launch overlay before launching player
    widget.onPlaybackStarted?.call();
    MainPageBridge.notifyPlayerLaunching();

    await VideoPlayerLauncher.push(
      context,
      VideoPlayerLaunchArgs(
        videoUrl: initialVideoUrl,
        title: seriesTitle,
        subtitle: '${entries.length} episodes',
        playlist: entries,
        startIndex: startIndex,
        rdTorrentId: rdTorrentId,
        disableAutoResume: true,
        isSeries: _seriesPlaylist?.isSeries, // Pass detected series flag
      ),
    );
  }

  /// Play Torbox playlist
  Future<void> _playTorboxPlaylist(List<RDFileNode> videoFiles, int startIndex) async {
    final String? apiKey = await StorageService.getTorboxApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      throw Exception('Please set your Torbox API key in Settings');
    }

    final torboxTorrentId = widget.playlistItem['torboxTorrentId'] as int?;
    if (torboxTorrentId == null) {
      throw Exception('No Torbox torrent ID found');
    }

    // Build playlist entries
    final List<PlaylistEntry> entries = [];
    for (int i = 0; i < videoFiles.length; i++) {
      final file = videoFiles[i];

      if (i == startIndex) {
        // Get streaming URL for first file
        try {
          if (file.fileId != null) {
            final url = await TorboxService.requestFileDownloadLink(
              apiKey: apiKey,
              torrentId: torboxTorrentId,
              fileId: file.fileId!,
            );
            entries.add(PlaylistEntry(
              url: url,
              title: file.name,
              relativePath: _cleanTorboxPath(file.path),
              torboxTorrentId: torboxTorrentId,
              torboxFileId: file.fileId,
              sizeBytes: file.bytes,
            ));
          }
        } catch (_) {
          entries.add(PlaylistEntry(
            url: '',
            title: file.name,
            relativePath: _cleanTorboxPath(file.path),
            torboxTorrentId: torboxTorrentId,
            torboxFileId: file.fileId,
            sizeBytes: file.bytes,
          ));
        }
      } else {
        entries.add(PlaylistEntry(
          url: '',
          title: file.name,
          relativePath: _cleanTorboxPath(file.path),
          torboxTorrentId: torboxTorrentId,
          torboxFileId: file.fileId,
          sizeBytes: file.bytes,
        ));
      }
    }

    if (entries.isEmpty) {
      throw Exception('No playable files found');
    }

    final String initialVideoUrl = entries[startIndex].url;
    final String seriesTitle = _seriesPlaylist?.seriesTitle ?? widget.playlistItem['title'] as String? ?? 'Series';

    if (!mounted) return;

    // Hide auto-launch overlay before launching player
    widget.onPlaybackStarted?.call();
    MainPageBridge.notifyPlayerLaunching();

    await VideoPlayerLauncher.push(
      context,
      VideoPlayerLaunchArgs(
        videoUrl: initialVideoUrl,
        title: seriesTitle,
        subtitle: '${entries.length} episodes',
        playlist: entries,
        startIndex: startIndex,
        disableAutoResume: true,
        isSeries: _seriesPlaylist?.isSeries, // Pass detected series flag
      ),
    );
  }

  /// Play PikPak playlist
  Future<void> _playPikPakPlaylist(List<RDFileNode> videoFiles, int startIndex) async {
    final pikpak = PikPakApiService.instance;

    if (!await pikpak.isAuthenticated()) {
      throw Exception('Please login to PikPak in Settings');
    }

    // Build playlist entries
    final List<PlaylistEntry> entries = [];
    for (int i = 0; i < videoFiles.length; i++) {
      final file = videoFiles[i];

      // Extract PikPak file ID from the path field
      // Format: "pikpak://fileId|fileName"
      String? fileId;
      final path = file.path;
      if (path != null && path.startsWith('pikpak://')) {
        final parts = path.substring(9).split('|');
        if (parts.isNotEmpty) {
          fileId = parts[0];
        }
      }

      if (fileId == null) continue;

      if (i == startIndex) {
        // Get streaming URL for first file
        try {
          final fileData = await pikpak.getFileDetails(fileId);
          final streamingUrl = pikpak.getStreamingUrl(fileData);
          entries.add(PlaylistEntry(
            url: streamingUrl ?? '',
            title: file.name,
            relativePath: file.relativePath,
            pikpakFileId: fileId,
            sizeBytes: file.bytes,
          ));
        } catch (_) {
          entries.add(PlaylistEntry(
            url: '',
            title: file.name,
            relativePath: file.relativePath,
            pikpakFileId: fileId,
            sizeBytes: file.bytes,
          ));
        }
      } else {
        entries.add(PlaylistEntry(
          url: '',
          title: file.name,
          relativePath: file.relativePath,
          pikpakFileId: fileId,
          sizeBytes: file.bytes,
        ));
      }
    }

    if (entries.isEmpty) {
      throw Exception('No playable files found');
    }

    final String initialVideoUrl = entries[startIndex].url;
    final String seriesTitle = _seriesPlaylist?.seriesTitle ?? widget.playlistItem['title'] as String? ?? 'Series';

    if (!mounted) return;

    // Hide auto-launch overlay before launching player
    widget.onPlaybackStarted?.call();
    MainPageBridge.notifyPlayerLaunching();

    await VideoPlayerLauncher.push(
      context,
      VideoPlayerLaunchArgs(
        videoUrl: initialVideoUrl,
        title: seriesTitle,
        subtitle: '${entries.length} episodes',
        playlist: entries,
        startIndex: startIndex,
        disableAutoResume: true,
        isSeries: _seriesPlaylist?.isSeries, // Pass detected series flag
      ),
    );
  }

  /// Clean Torbox path by removing "TorrentName..." prefix
  /// Example: "TorrentName.../Season 1/Episode 1.mkv" -> "Season 1/Episode 1.mkv"
  String? _cleanTorboxPath(String? path) {
    if (path == null) return null;

    // Check if there's a "..." separator (torrent name prefix)
    if (path.contains('.../')) {
      final parts = path.split('.../');
      if (parts.length > 1) {
        // Return everything after the first "..."
        return parts.skip(1).join('.../');
      }
    }

    // If no "..." separator, return as-is
    return path;
  }
}
