import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/playlist_view_mode.dart';
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
  State<PlaylistContentViewScreen> createState() =>
      _PlaylistContentViewScreenState();
}

class _PlaylistContentViewScreenState extends State<PlaylistContentViewScreen> {
  bool _isLoading = true;
  String? _errorMessage;

  // Current navigation state
  List<String> _folderPath = []; // Path segments for breadcrumbs
  RDFileNode? _rootContent; // Root content tree
  List<RDFileNode>?
  _currentViewNodes; // Current folder's visible nodes (after view mode transformation)

  // View mode state
  FolderViewMode _currentViewMode = FolderViewMode.raw;

  // Focus management for TV navigation
  final FocusNode _viewModeDropdownFocusNode = FocusNode(
    debugLabel: 'playlist-view-mode-dropdown',
  );
  final FocusNode _backButtonFocusNode = FocusNode(
    debugLabel: 'playlist-back-button',
  );

  // Progress tracking cache
  Map<String, Map<String, dynamic>> _fileProgressCache = {};

  // OTT View state
  SeriesPlaylist? _seriesPlaylist;
  int _selectedSeasonNumber = 1;
  bool _isLoadingSeriesMetadata = false;

  // Auto-scroll state
  final ScrollController _episodeListScrollController = ScrollController();
  int? _targetEpisodeIndex; // Episode to scroll to after list is built
  Timer? _scrollRetryTimer; // Timer for scroll retry to prevent memory leaks
  bool _isScrollScheduled =
      false; // Flag to prevent duplicate scroll scheduling

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
      final savedViewMode = await StorageService.getPlaylistItemViewMode(
        widget.playlistItem,
      );
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
    _scrollRetryTimer
        ?.cancel(); // Cancel any pending scroll retry to prevent memory leaks
    _viewModeDropdownFocusNode.dispose();
    _backButtonFocusNode.dispose();
    _episodeListScrollController.dispose();
    super.dispose();
  }

  /// Load saved view mode for this playlist item
  Future<void> _loadSavedViewMode() async {
    final savedModeString = await StorageService.getPlaylistItemViewMode(
      widget.playlistItem,
    );
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

  /// Convert FolderViewMode to PlaylistViewMode for video player
  PlaylistViewMode _convertToPlaylistViewMode(FolderViewMode mode) {
    switch (mode) {
      case FolderViewMode.raw:
        return PlaylistViewMode.raw;
      case FolderViewMode.sortedAZ:
        return PlaylistViewMode.sorted;
      case FolderViewMode.seriesArrange:
        return PlaylistViewMode.series;
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
      final provider =
          (widget.playlistItem['provider'] as String?) ?? 'realdebrid';

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
    _rootContent = RDFolderTreeBuilder.buildTree(
      allFiles.cast<Map<String, dynamic>>(),
    );
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

    final cachedTorrent = await TorboxService.getTorrentById(
      apiKey,
      torboxTorrentId,
    );
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
        throw Exception(
          'No PikPak file data found. Please remove and re-add this item to playlist.',
        );
      }
    }
  }

  /// Build folder tree from PikPak by fetching folder structure
  /// This properly preserves the folder hierarchy
  Future<RDFileNode> _buildPikPakFolderTree(
    String folderId, {
    int depth = 0,
    String currentPath = '',
  }) async {
    final pikpak = PikPakApiService.instance;

    // Prevent infinite recursion or excessively deep folder structures
    const int maxDepth = 4;
    if (depth > maxDepth) {
      throw Exception(
        'Folder hierarchy too deep (max $maxDepth levels). Please reorganize your folders.',
      );
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
          final subTree = await _buildPikPakFolderTree(
            fileId,
            depth: depth + 1,
            currentPath: subPath,
          );
          children.add(
            RDFileNode.folder(name: name, children: subTree.children),
          );
        }
      } else {
        // Add file node
        final sizeRaw = file['size'];
        final size = sizeRaw is int
            ? sizeRaw
            : (sizeRaw is String ? int.tryParse(sizeRaw) ?? 0 : 0);

        // Store the PikPak file metadata in the node's path field (we'll parse it later)
        // Format: "pikpak://fileId|fileName"
        final pikpakUrl = 'pikpak://$fileId|$name';

        // Build relative path for series parsing
        final relPath = currentPath.isEmpty ? name : '$currentPath/$name';

        children.add(
          RDFileNode.file(
            name: name,
            fileId: fileIndex,
            path: pikpakUrl, // Store PikPak file ID and name here
            relativePath: relPath, // Store clean path for series parsing
            bytes: size,
            linkIndex: fileIndex,
          ),
        );
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
      final size = sizeRaw is int
          ? sizeRaw
          : (sizeRaw is String ? int.tryParse(sizeRaw) ?? 0 : 0);

      if (kind == 'drive#folder') {
        // Skip folders in flat view since we don't have hierarchy
        continue;
      } else if (fileId != null) {
        // Add file node with pikpak:// URL for playback
        final pikpakUrl = 'pikpak://$fileId|$name';

        nodes.add(
          RDFileNode.file(
            name: name,
            fileId: i,
            path: pikpakUrl, // Store PikPak file ID for playback
            bytes: size,
            linkIndex: i,
          ),
        );
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
          print(
            'Warning: Folder "$segment" not found in current view, resetting to root',
          );
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
    StorageService.savePlaylistItemViewMode(
      widget.playlistItem,
      _viewModeToString(mode),
    );
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

  /// Apply Sort A-Z ordering to a list of video files for playback
  /// This ensures the playlist plays files in the same order as displayed in the UI
  /// Only applies sorting if _currentViewMode == FolderViewMode.sortedAZ
  ///
  /// The sorting logic MUST match _applySortedView to maintain UI/playback consistency:
  /// 1. Groups files by their folder path
  /// 2. Sorts files within each folder (numerically aware, then alphabetically)
  /// 3. Sorts folders by their top-level folder name (numerically aware, then alphabetically)
  /// 4. Rebuilds the list with sorted folders containing sorted files
  void _applySortedPlaylistOrder(List<RDFileNode> videoFiles) {
    if (_currentViewMode != FolderViewMode.sortedAZ) {
      return; // Only apply sorting in sortedAZ mode
    }

    // Group files by their folder path (everything before the filename)
    final folderGroups = <String, List<RDFileNode>>{};
    for (final node in videoFiles) {
      // Extract folder path from relativePath (or use path as fallback)
      final fullPath = (node.relativePath ?? node.path) ?? '';
      final lastSlashIndex = fullPath.lastIndexOf('/');
      final folderPath = lastSlashIndex >= 0
          ? fullPath.substring(0, lastSlashIndex)
          : '';

      folderGroups.putIfAbsent(folderPath, () => []);
      folderGroups[folderPath]!.add(node);
    }

    // Sort files within each folder group (SAME LOGIC AS UI)
    for (final group in folderGroups.values) {
      group.sort((a, b) {
        final aNum = _extractLeadingNumber(a.name);
        final bNum = _extractLeadingNumber(b.name);

        // If both start with numbers, sort numerically
        if (aNum != null && bNum != null) {
          return aNum.compareTo(bNum);
        }

        // If only one starts with a number, numbered files come first
        if (aNum != null) return -1;
        if (bNum != null) return 1;

        // Otherwise sort alphabetically (case-insensitive)
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    }

    // Sort folder paths using SAME LOGIC AS UI (_applySortedView sorts folders)
    // Extract the top-level folder name from each path for sorting
    final provider =
        ((widget.playlistItem['provider'] as String?) ?? 'realdebrid')
            .toLowerCase();
    final folderPathsList = folderGroups.keys.toList();
    folderPathsList.sort((a, b) {
      // Extract the top-level folder name from the path
      // Handle empty paths (root directory) and nested paths correctly
      String aFolderName;
      String bFolderName;

      if (a.isEmpty) {
        aFolderName = 'Root';
      } else {
        final aParts = a.split('/');
        // For Torbox: skip first folder level (torrent name), use second level
        // For others: use first folder level
        if (provider == 'torbox' && aParts.length > 1) {
          aFolderName = aParts[1]; // Second folder (skip torrent name)
        } else {
          aFolderName = aParts[0]; // First folder (top-level)
        }
      }

      if (b.isEmpty) {
        bFolderName = 'Root';
      } else {
        final bParts = b.split('/');
        // For Torbox: skip first folder level (torrent name), use second level
        // For others: use first folder level
        if (provider == 'torbox' && bParts.length > 1) {
          bFolderName = bParts[1]; // Second folder (skip torrent name)
        } else {
          bFolderName = bParts[0]; // First folder (top-level)
        }
      }

      // Use _extractSeasonNumber for numerical awareness (SAME AS UI)
      final aNum = _extractSeasonNumber(aFolderName);
      final bNum = _extractSeasonNumber(bFolderName);

      // If both have numbers, sort numerically
      if (aNum != null && bNum != null) {
        return aNum.compareTo(bNum);
      }

      // If only one has a number, numbered folders come first
      if (aNum != null) return -1;
      if (bNum != null) return 1;

      // Otherwise sort alphabetically (case-insensitive)
      return aFolderName.toLowerCase().compareTo(bFolderName.toLowerCase());
    });

    // Rebuild videoFiles list with sorted folders and sorted files within
    videoFiles.clear();
    for (final folderPath in folderPathsList) {
      videoFiles.addAll(folderGroups[folderPath]!);
    }
  }

  /// Apply series arrange view (creates virtual season folders)
  List<RDFileNode> _applySeriesArrangeView(List<RDFileNode> nodes) {
    final videoFiles = nodes
        .where((n) => !n.isFolder && FileUtils.isVideoFile(n.name))
        .toList();
    final otherNodes = nodes
        .where((n) => n.isFolder || !FileUtils.isVideoFile(n.name))
        .toList();

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
      seasonFolders.add(
        RDFileNode.folder(
          name: seasonNum == 0 ? 'Season 0 - Specials' : 'Season $seasonNum',
          children: seasonFiles,
        ),
      );
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
              Text(
                'Preparing playlist…',
                style: TextStyle(color: Colors.white),
              ),
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

      // Apply Sort A-Z sorting if in sortedAZ mode
      // Use EXACT same sorting logic as UI view mode (_applySortedView)
      _applySortedPlaylistOrder(videoFiles);

      // Find the selected file index
      int startIndex = 0;
      for (int i = 0; i < videoFiles.length; i++) {
        if (videoFiles[i].name == file.name &&
            videoFiles[i].path == file.path) {
          startIndex = i;
          break;
        }
      }

      final provider =
          ((widget.playlistItem['provider'] as String?) ?? 'realdebrid')
              .toLowerCase();

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

      // Reload progress after returning from video player
      if (mounted) {
        await _reloadProgress();
      }
    } catch (e) {
      print('❌ Error playing file: $e');
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }

      // Reload progress even if an error occurred
      // (user might have watched part of video before error)
      if (mounted) {
        await _reloadProgress();
      }

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to play file: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = (widget.playlistItem['title'] as String?) ?? 'Playlist Item';

    // At root when folder path is empty - allow normal pop to exit screen
    final isAtRoot = _folderPath.isEmpty;

    return PopScope(
      canPop: isAtRoot,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          // User pressed back while in a subfolder - navigate up
          _navigateUp();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            focusNode: _backButtonFocusNode,
            icon: const Icon(Icons.arrow_back),
            onPressed: _navigateUp,
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
            Expanded(child: _buildContent()),
          ],
        ),
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

    return FocusableActionDetector(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
      },
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (intent) {
            if (isFolder) {
              _navigateIntoFolder(node);
            } else if (isVideo) {
              _playFile(node);
            }
            return null;
          },
        ),
      },
      child: Card(
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
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: isFinished
                              ? const Color(0xFF059669)
                              : Colors.blue,
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
                          color: isFinished
                              ? const Color(0xFF059669)
                              : Colors.blue,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Get progress data for a specific file
  Map<String, dynamic>? _getProgressForFile(RDFileNode file) {
    // ALWAYS try to parse season/episode from filename first (regardless of view mode)
    // This ensures progress is consistent across Raw and Series Arrange modes
    final seriesInfo = SeriesParser.parseFilename(file.name);
    if (seriesInfo.season != null && seriesInfo.episode != null) {
      final key = '${seriesInfo.season}_${seriesInfo.episode}';
      final progressData = _fileProgressCache[key];
      if (progressData != null) {
        return progressData;
      }
    }

    // Fallback: For files without parseable season/episode, use sequential indexing
    // This is for non-series content like movies or special features
    if (_rootContent != null) {
      final allFiles = _rootContent!.getAllFiles();
      final videoFiles = allFiles
          .where((node) => FileUtils.isVideoFile(node.name))
          .toList();

      // IMPORTANT: Apply sorting if in sortedAZ mode to match the index used when saving progress
      // When playing in Sort A-Z mode, progress is saved using indices from the sorted list,
      // so we must apply the same sorting here to look up the correct progress key
      _applySortedPlaylistOrder(videoFiles);

      final fileIndex = videoFiles.indexWhere(
        (node) => node.name == file.name && node.path == file.path,
      );

      if (fileIndex >= 0) {
        final key = '0_${fileIndex + 1}'; // season 0, 1-based episode index
        return _fileProgressCache[key];
      }
    }

    // Final fallback: try using filename as key
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
        if (_isLoadingSeriesMetadata) const LinearProgressIndicator(),

        // Episode list
        Expanded(child: _buildEpisodeList(season)),
      ],
    );
  }

  /// Determine initial season based on most recently watched episode
  /// Returns the season number to start with (defaults to 1 if no progress)
  int _determineInitialSeason() {
    if (_fileProgressCache.isEmpty) return 1;

    // Find most recently watched episode
    String? mostRecentKey;
    int? mostRecentTimestamp;

    for (var entry in _fileProgressCache.entries) {
      final updatedAt = entry.value['updatedAt'];
      if (updatedAt != null) {
        try {
          // Handle both int (milliseconds) and String formats
          int timestamp;
          if (updatedAt is int) {
            // Assume it's already in milliseconds (most common format)
            timestamp = updatedAt;
          } else if (updatedAt is String) {
            // Try parsing as numeric timestamp first, then as ISO date string
            final parsed = int.tryParse(updatedAt);
            if (parsed != null) {
              // Detect if it's likely seconds (10 digits) vs milliseconds (13 digits)
              // Unix timestamp in seconds: ~10 digits (e.g., 1735134769)
              // Unix timestamp in milliseconds: ~13 digits (e.g., 1735134769000)
              if (parsed < 10000000000) {
                // Likely seconds, convert to milliseconds
                timestamp = parsed * 1000;
              } else {
                // Already milliseconds
                timestamp = parsed;
              }
            } else {
              // Parse as ISO date string
              timestamp = DateTime.parse(updatedAt).millisecondsSinceEpoch;
            }
          } else {
            continue;
          }

          if (mostRecentTimestamp == null || timestamp > mostRecentTimestamp) {
            mostRecentTimestamp = timestamp;
            mostRecentKey = entry.key;
          }
        } catch (e) {
          print(
            '⚠️ Failed to parse updatedAt timestamp: $updatedAt (${e.toString()})',
          );
        }
      }
    }

    if (mostRecentKey != null) {
      // Extract season from key format "{season}_{episode}"
      final parts = mostRecentKey.split('_');
      if (parts.length >= 2) {
        final seasonNum = int.tryParse(parts[0]);
        if (seasonNum != null) {
          print(
            '🎯 Found most recent season: $seasonNum from key: $mostRecentKey',
          );
          return seasonNum;
        }
      }
    }

    print('📺 No recent progress found, defaulting to Season 1');
    return 1; // Default to season 1
  }

  /// Determine initial episode index to scroll to within the selected season
  /// Returns the episode index (0-based) or null if no specific episode to scroll to
  int? _determineInitialEpisodeIndex(SeriesSeason season) {
    if (_fileProgressCache.isEmpty) return null;

    // Find most recently watched episode in this season
    int? mostRecentTimestamp;
    int? mostRecentEpisodeNum;

    for (var entry in _fileProgressCache.entries) {
      final key = entry.key;
      final parts = key.split('_');

      if (parts.length >= 2) {
        final seasonNum = int.tryParse(parts[0]);
        final episodeNum = int.tryParse(parts[1]);

        // Only consider episodes from the current season
        if (seasonNum == season.seasonNumber && episodeNum != null) {
          final updatedAt = entry.value['updatedAt'];
          if (updatedAt != null) {
            try {
              // Handle both int (milliseconds) and String formats
              int timestamp;
              if (updatedAt is int) {
                // Assume it's already in milliseconds (most common format)
                timestamp = updatedAt;
              } else if (updatedAt is String) {
                // Try parsing as numeric timestamp first, then as ISO date string
                final parsed = int.tryParse(updatedAt);
                if (parsed != null) {
                  // Detect if it's likely seconds (10 digits) vs milliseconds (13 digits)
                  // Unix timestamp in seconds: ~10 digits (e.g., 1735134769)
                  // Unix timestamp in milliseconds: ~13 digits (e.g., 1735134769000)
                  if (parsed < 10000000000) {
                    // Likely seconds, convert to milliseconds
                    timestamp = parsed * 1000;
                  } else {
                    // Already milliseconds
                    timestamp = parsed;
                  }
                } else {
                  // Parse as ISO date string
                  timestamp = DateTime.parse(updatedAt).millisecondsSinceEpoch;
                }
              } else {
                continue;
              }

              if (mostRecentTimestamp == null ||
                  timestamp > mostRecentTimestamp) {
                mostRecentTimestamp = timestamp;
                mostRecentEpisodeNum = episodeNum;
              }
            } catch (e) {
              print(
                '⚠️ Failed to parse updatedAt timestamp: $updatedAt (${e.toString()})',
              );
            }
          }
        }
      }
    }

    if (mostRecentEpisodeNum != null) {
      // Find the episode index in the season's episode list
      for (int i = 0; i < season.episodes.length; i++) {
        final episode = season.episodes[i];
        if (episode.seriesInfo.episode == mostRecentEpisodeNum) {
          print(
            '🎯 Found most recent episode in season: Episode $mostRecentEpisodeNum at index $i',
          );
          return i;
        }
      }
    }

    return null; // No specific episode to scroll to
  }

  /// Reload progress data from storage
  /// Called when returning from video player to refresh progress indicators
  Future<void> _reloadProgress() async {
    if (!mounted) return;

    try {
      // Get the series/collection title from the playlist item
      // IMPORTANT: Use same logic as _parseSeriesPlaylist() for consistency
      final String? seriesTitle =
          _seriesPlaylist?.seriesTitle ??
          widget.playlistItem['title'] as String?;

      if (seriesTitle != null && seriesTitle.isNotEmpty) {
        print('🔄 Reloading progress after video playback for: $seriesTitle');
        final episodeProgress = await StorageService.getEpisodeProgress(
          seriesTitle: seriesTitle,
        );

        if (!mounted) return; // Check again after async operation

        print(
          '📊 Reloaded ${episodeProgress.length} episodes with updated progress',
        );
        print('🔑 Progress keys: ${episodeProgress.keys.toList()}');

        setState(() {
          _fileProgressCache = episodeProgress;
        });
      }
    } catch (e) {
      print('❌ Error reloading progress data: $e');
      // Don't rethrow - this is a non-critical background operation
    }
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
      final entries = videoFiles
          .map(
            (f) => PlaylistEntry(
              url: '', // Not needed for parsing
              title: f.name,
              relativePath:
                  f.relativePath ??
                  f.path, // Use relativePath if available, fallback to path
            ),
          )
          .toList();

      // Get series/collection title from playlist item
      // Try 'seriesTitle' first (if previously extracted), fallback to 'title' (raw torrent name)
      final String? collectionTitle =
          widget.playlistItem['seriesTitle'] as String? ??
          widget.playlistItem['title'] as String?;

      _seriesPlaylist = SeriesPlaylist.fromPlaylistEntries(
        entries,
        collectionTitle: collectionTitle,
      );

      // Reload progress with the clean extracted series/collection title!
      // This works for both series and movie collections
      final String? titleForProgress =
          _seriesPlaylist!.seriesTitle ??
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

        // Determine initial season based on most recent viewing history
        if (_seriesPlaylist!.isSeries && _fileProgressCache.isNotEmpty) {
          final initialSeason = _determineInitialSeason();
          print('🎬 Setting initial season to: $initialSeason');
          _selectedSeasonNumber = initialSeason;
        }
      }

      // Check if we have a saved TVMaze mapping (indicates cached data)
      // Only show loading indicator if data needs to be fetched
      bool showLoading = true;
      if (widget.playlistItem != null) {
        final mapping = await StorageService.getTVMazeSeriesMapping(
          widget.playlistItem!,
        );
        if (mapping != null) {
          showLoading = false; // Data should be cached, skip loading indicator
        }
      }

      if (showLoading) {
        setState(() {
          _isLoadingSeriesMetadata = true;
        });
      }

      // Fetch TVMaze metadata asynchronously
      if (_seriesPlaylist!.isSeries) {
        _seriesPlaylist!
            .fetchEpisodeInfo(playlistItem: widget.playlistItem)
            .then((_) {
              if (mounted) {
                setState(() {
                  _isLoadingSeriesMetadata = false;
                });
              }
            })
            .catchError((e) {
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
      builder: (context) =>
          TVMazeSearchDialog(initialQuery: _seriesPlaylist?.seriesTitle ?? ''),
    );

    if (selectedShow != null && mounted) {
      // 1. Get OLD mapping (before it's overwritten)
      final oldMapping = await StorageService.getTVMazeSeriesMapping(
        widget.playlistItem,
      );
      final oldShowId = oldMapping?['tvmazeShowId'] as int?;

      // 2. Clear old show ID cache if it exists
      if (oldShowId != null && oldShowId != selectedShow['id']) {
        debugPrint('🧹 Clearing old show ID cache: $oldShowId');
        await TVMazeService.clearShowCache(oldShowId);
        await EpisodeInfoService.clearShowCache(oldShowId);
      }

      // 3. Clear series name cache (existing logic)
      await EpisodeInfoService.clearSeriesCache(
        _seriesPlaylist?.seriesTitle ?? '',
      );
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
            content: Text(
              'Metadata fixed! Using "${selectedShow['name']}" from TVMaze',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }

      // Reload episode info with the new show ID
      if (_seriesPlaylist != null && _seriesPlaylist!.isSeries && mounted) {
        setState(() {
          _isLoadingSeriesMetadata = true;
        });

        _seriesPlaylist!
            .fetchEpisodeInfo(playlistItem: widget.playlistItem)
            .then((_) {
              if (mounted) {
                setState(() {
                  _isLoadingSeriesMetadata = false;
                });
              }
            })
            .catchError((e) {
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
      final provider =
          (widget.playlistItem['provider'] as String?) ?? 'realdebrid';
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
        final pikpakCollectionId =
            widget.playlistItem['pikpakCollectionId'] as String?;
        if (pikpakCollectionId != null) {
          updated = await StorageService.updatePlaylistItemPoster(
            posterUrl,
            pikpakCollectionId: pikpakCollectionId,
          );
        }
      }

      if (updated) {
        print(
          '✅ Successfully updated playlist poster in memory and persistent storage',
        );
      } else {
        print(
          '⚠️ Updated persistent storage but in-memory update failed - poster will still persist on restart',
        );
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
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.1),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
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
                // Cancel any pending scroll retry timer before season change
                _scrollRetryTimer?.cancel();

                setState(() {
                  _selectedSeasonNumber = value;
                  // Reset target episode index when season changes manually
                  // so it recalculates for the new season
                  _targetEpisodeIndex = null;
                  // Reset scroll scheduled flag to allow auto-scroll in new season
                  _isScrollScheduled = false;
                });
              }
            },
          ),
          const Spacer(),
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
                    Icon(Icons.build, color: Colors.orange, size: 14),
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
        ],
      ),
    );
  }

  /// Build episode list
  Widget _buildEpisodeList(SeriesSeason season) {
    // Determine which episode to scroll to (if any)
    // Use _isScrollScheduled flag to prevent duplicate scroll scheduling during rebuilds
    if (_targetEpisodeIndex == null && !_isScrollScheduled) {
      _targetEpisodeIndex = _determineInitialEpisodeIndex(season);

      // Schedule auto-scroll after the list is built
      // IMPORTANT: Always schedule the callback - hasClients will be checked inside
      if (_targetEpisodeIndex != null) {
        _isScrollScheduled = true; // Mark as scheduled to prevent duplicates
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _scrollToEpisode(_targetEpisodeIndex!);
          }
          _isScrollScheduled = false; // Reset after scroll attempt
        });
      }
    }

    return ListView.builder(
      controller: _episodeListScrollController,
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

  /// Scroll to a specific episode index with animation
  void _scrollToEpisode(int episodeIndex, {int retryCount = 0}) {
    // Cancel any existing retry timer to prevent memory leaks
    _scrollRetryTimer?.cancel();

    if (!_episodeListScrollController.hasClients) {
      // Retry up to 3 times with increasing delay
      if (retryCount < 3) {
        print(
          '⏳ ScrollController not ready yet, scheduling retry ${retryCount + 1}/3',
        );
        _scrollRetryTimer = Timer(
          Duration(milliseconds: 100 * (retryCount + 1)),
          () {
            if (mounted) {
              _scrollToEpisode(episodeIndex, retryCount: retryCount + 1);
            }
          },
        );
      } else {
        print(
          '❌ Failed to scroll after 3 retries - ScrollController never attached',
        );
      }
      return;
    }

    // Calculate approximate position
    // Each episode card is roughly 180px (desktop) or 300px (mobile) + 16px padding
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;
    final estimatedItemHeight = isMobile
        ? 316.0
        : 196.0; // card height + padding
    final targetOffset = episodeIndex * estimatedItemHeight;

    // Ensure we don't scroll beyond the max extent
    final maxScrollExtent =
        _episodeListScrollController.position.maxScrollExtent;
    final finalOffset = targetOffset > maxScrollExtent
        ? maxScrollExtent
        : targetOffset;

    print(
      '📜 Auto-scrolling to episode index: $episodeIndex (offset: $finalOffset, max: $maxScrollExtent)',
    );

    // Scroll to the target episode with animation
    _episodeListScrollController.animateTo(
      finalOffset,
      duration: const Duration(milliseconds: 800),
      curve: Curves.easeInOut,
    );
  }

  /// Build episode card with responsive layout (vertical on mobile, horizontal on desktop)
  Widget _buildEpisodeCard(SeriesEpisode episode) {
    // Get progress for this episode
    double progress = 0.0;
    bool isFinished = false;
    if (episode.seriesInfo.season != null &&
        episode.seriesInfo.episode != null) {
      final key = '${episode.seriesInfo.season}_${episode.seriesInfo.episode}';
      print(
        '🔍 Looking for progress with key: $key for ${episode.displayTitle}',
      );
      print('💾 Available keys in cache: ${_fileProgressCache.keys.toList()}');
      final progressData = _fileProgressCache[key];
      if (progressData != null) {
        print('✅ Found progress data: $progressData');
        final positionMs = progressData['positionMs'] as int? ?? 0;
        final durationMs = progressData['durationMs'] as int? ?? 0;
        if (durationMs > 0) {
          progress = positionMs / durationMs;
          // Check if finished based on progress OR if it's marked as finished explicitly
          // Dummy data has durationMs = 1 to indicate manually marked as watched
          isFinished = progress >= 0.9 ||
                       (durationMs - positionMs) < 120000 ||
                       (positionMs == 0 && durationMs == 1);
          print(
            '📈 Progress: ${(progress * 100).round()}%, Finished: $isFinished',
          );
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

    return FocusableActionDetector(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
      },
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (intent) {
            _playEpisode(episode);
            return null;
          },
        ),
      },
      child: Card(
        color: const Color(0xFF1E293B),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _playEpisode(episode),
          child: isMobile
              ? _buildMobileEpisodeCard(
                  episode,
                  progress,
                  isFinished,
                  hasMetadata,
                  episodeInfo,
                )
              : _buildDesktopEpisodeCard(
                  episode,
                  progress,
                  isFinished,
                  hasMetadata,
                  episodeInfo,
                ),
        ),
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

              // Apply semi-transparent overlay for watched episodes
              if (isFinished)
                Container(
                  color: Colors.black.withValues(alpha: 0.6),
                ),

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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
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

              // Top right: Mark as watched button
              Positioned(
                top: 8,
                right: 8,
                child: GestureDetector(
                  onTap: () => _toggleWatchedState(episode),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isFinished
                        ? const Color(0xFF4CAF50)
                        : Colors.white.withValues(alpha: 0.3),
                      border: Border.all(
                        color: isFinished
                          ? const Color(0xFF4CAF50)
                          : Colors.white.withValues(alpha: 0.8),
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.4),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Icon(
                      isFinished ? Icons.check : Icons.circle_outlined,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
              ),

              // IMDB rating badge (moved to accommodate watched button)
              if (hasMetadata && episodeInfo!.rating != null)
                Positioned(
                  top: 8,
                  right: 52, // Positioned to the left of the watched button
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
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
                          isFinished
                              ? Icons.check_circle
                              : Icons.play_circle_filled,
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
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
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
                      const Icon(
                        Icons.schedule,
                        size: 14,
                        color: Colors.white60,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${episodeInfo.runtime} min',
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 12,
                        ),
                      ),
                    ],
                    if (episodeInfo.runtime != null &&
                        episodeInfo.airDate != null)
                      const Text(
                        '  •  ',
                        style: TextStyle(color: Colors.white60, fontSize: 12),
                      ),
                    if (episodeInfo.airDate != null) ...[
                      const Icon(
                        Icons.calendar_today,
                        size: 14,
                        color: Colors.white60,
                      ),
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

                    // Apply semi-transparent overlay for watched episodes
                    if (isFinished)
                      Container(
                        color: Colors.black.withValues(alpha: 0.6),
                      ),

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
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
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

                    // Top right: Mark as watched button
                    Positioned(
                      top: 8,
                      right: 8,
                      child: GestureDetector(
                        onTap: () => _toggleWatchedState(episode),
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isFinished
                              ? const Color(0xFF4CAF50)
                              : Colors.white.withValues(alpha: 0.3),
                            border: Border.all(
                              color: isFinished
                                ? const Color(0xFF4CAF50)
                                : Colors.white.withValues(alpha: 0.8),
                              width: 2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.4),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Icon(
                            isFinished ? Icons.check : Icons.circle_outlined,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                      ),
                    ),

                    // IMDB rating badge (moved to accommodate watched button)
                    if (hasMetadata && episodeInfo?.rating != null)
                      Positioned(
                        top: 8,
                        right: 60, // Positioned to the left of the watched button
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF5C518),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.star,
                                color: Colors.black,
                                size: 14,
                              ),
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
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
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
                                isFinished
                                    ? Icons.check_circle
                                    : Icons.play_circle_filled,
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
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: isFinished
                                    ? const Color(
                                        0xFF059669,
                                      ).withValues(alpha: 0.2)
                                    : const Color(
                                        0xFF6366F1,
                                      ).withValues(alpha: 0.2),
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
                              const Icon(
                                Icons.schedule,
                                size: 14,
                                color: Colors.white60,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${episodeInfo!.runtime} min',
                                style: const TextStyle(
                                  color: Colors.white60,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                            if (episodeInfo!.runtime != null &&
                                episodeInfo!.airDate != null)
                              const Text(
                                '  •  ',
                                style: TextStyle(color: Colors.white60),
                              ),
                            if (episodeInfo!.airDate != null) ...[
                              const Icon(
                                Icons.calendar_today,
                                size: 14,
                                color: Colors.white60,
                              ),
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
            const Icon(Icons.video_library, color: Colors.white38, size: 48),
            const SizedBox(height: 8),
            Text(
              episode.seasonEpisodeString,
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  /// Toggle the watched state of an episode
  Future<void> _toggleWatchedState(SeriesEpisode episode) async {
    if (_seriesPlaylist == null) return;

    // Get the series title for storage
    final String? seriesTitle = _seriesPlaylist!.seriesTitle ??
                                widget.playlistItem['title'] as String?;

    if (seriesTitle == null || seriesTitle.isEmpty) {
      print('❌ Cannot toggle watched state: No series title available');
      return;
    }

    // Get episode details
    final season = episode.seriesInfo.season ?? 1;
    final episodeNum = episode.seriesInfo.episode ?? 1;

    try {
      // Check current watched state
      final isCurrentlyFinished = await StorageService.isEpisodeFinished(
        seriesTitle: seriesTitle,
        season: season,
        episode: episodeNum,
      );

      if (isCurrentlyFinished) {
        // Episode is marked as watched, unmark it
        print('🔄 Unmarking as watched: $seriesTitle S${season}E$episodeNum');
        await StorageService.unmarkEpisodeAsFinished(
          seriesTitle: seriesTitle,
          season: season,
          episode: episodeNum,
        );
      } else {
        // Episode is not watched, mark it as finished
        print('✅ Marking as watched: $seriesTitle S${season}E$episodeNum');
        await StorageService.markEpisodeAsFinished(
          seriesTitle: seriesTitle,
          season: season,
          episode: episodeNum,
        );
      }

      // Reload the progress to update the UI
      await _reloadProgress();

      // Show a snackbar to confirm the action
      // Note: isCurrentlyFinished is the OLD state before toggle, so we invert the message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isCurrentlyFinished
                ? 'Episode marked as unwatched'
                : 'Episode marked as watched',
            ),
            duration: const Duration(seconds: 2),
            backgroundColor: isCurrentlyFinished
              ? const Color(0xFF6366F1)
              : const Color(0xFF4CAF50),
          ),
        );
      }
    } catch (e) {
      print('❌ Error toggling watched state: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating watched state: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
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
              Text(
                'Preparing playlist…',
                style: TextStyle(color: Colors.white),
              ),
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

      // Apply Sort A-Z sorting if in sortedAZ mode
      // Use EXACT same sorting logic as UI view mode (_applySortedView)
      _applySortedPlaylistOrder(videoFiles);

      // Find the selected episode index
      // The approach differs based on view mode:
      // - sortedAZ: Sorting changes indices, so we MUST find by filename
      // - raw/series/collection: originalIndex is still accurate (faster and more reliable)
      int startIndex = 0;
      if (_currentViewMode == FolderViewMode.sortedAZ) {
        // After sorting, indices change - must find by filename
        for (int i = 0; i < videoFiles.length; i++) {
          if (videoFiles[i].name == episode.filename) {
            startIndex = i;
            break;
          }
        }
      } else {
        // Raw/Series/Collection modes: originalIndex is still correct
        if (episode.originalIndex >= 0 &&
            episode.originalIndex < videoFiles.length) {
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
      }

      final provider =
          ((widget.playlistItem['provider'] as String?) ?? 'realdebrid')
              .toLowerCase();

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

      // Reload progress after returning from video player
      if (mounted) {
        await _reloadProgress();
      }
    } catch (e) {
      print('❌ Error playing episode: $e');
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }

      // Reload progress even if an error occurred
      // (user might have watched part of video before error)
      if (mounted) {
        await _reloadProgress();
      }

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: ${e.toString()}')));
      }
    }
  }

  /// Play Real-Debrid playlist
  Future<void> _playRealDebridPlaylist(
    List<RDFileNode> videoFiles,
    int startIndex,
  ) async {
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
          final unrestrictResult = await DebridService.unrestrictLink(
            apiKey,
            links[linkIndex],
          );
          final url = unrestrictResult['download']?.toString() ?? '';
          entries.add(
            PlaylistEntry(
              url: url,
              title: file.name,
              relativePath: file.relativePath ?? file.path,
              rdTorrentId: rdTorrentId,
              rdLinkIndex: linkIndex,
              sizeBytes: file.bytes,
              provider: 'realdebrid',
            ),
          );
        } catch (_) {
          entries.add(
            PlaylistEntry(
              url: '',
              title: file.name,
              relativePath: file.relativePath ?? file.path,
              restrictedLink: links[linkIndex],
              rdTorrentId: rdTorrentId,
              rdLinkIndex: linkIndex,
              sizeBytes: file.bytes,
              provider: 'realdebrid',
            ),
          );
        }
      } else {
        entries.add(
          PlaylistEntry(
            url: '',
            title: file.name,
            relativePath: file.relativePath ?? file.path,
            restrictedLink: links[linkIndex],
            rdTorrentId: rdTorrentId,
            rdLinkIndex: linkIndex,
            sizeBytes: file.bytes,
            provider: 'realdebrid',
          ),
        );
      }
    }

    if (entries.isEmpty) {
      throw Exception('No playable files found');
    }

    final String initialVideoUrl = entries[startIndex].url;
    final String seriesTitle =
        _seriesPlaylist?.seriesTitle ??
        widget.playlistItem['title'] as String? ??
        'Series';

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
        viewMode: _convertToPlaylistViewMode(_currentViewMode),
      ),
    );
  }

  /// Play Torbox playlist
  Future<void> _playTorboxPlaylist(
    List<RDFileNode> videoFiles,
    int startIndex,
  ) async {
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
            entries.add(
              PlaylistEntry(
                url: url,
                title: file.name,
                relativePath: _cleanTorboxPath(file.path),
                torboxTorrentId: torboxTorrentId,
                torboxFileId: file.fileId,
                sizeBytes: file.bytes,
                provider: 'torbox',
              ),
            );
          }
        } catch (_) {
          entries.add(
            PlaylistEntry(
              url: '',
              title: file.name,
              relativePath: _cleanTorboxPath(file.path),
              torboxTorrentId: torboxTorrentId,
              torboxFileId: file.fileId,
              sizeBytes: file.bytes,
              provider: 'torbox',
            ),
          );
        }
      } else {
        entries.add(
          PlaylistEntry(
            url: '',
            title: file.name,
            relativePath: _cleanTorboxPath(file.path),
            torboxTorrentId: torboxTorrentId,
            torboxFileId: file.fileId,
            sizeBytes: file.bytes,
            provider: 'torbox',
          ),
        );
      }
    }

    if (entries.isEmpty) {
      throw Exception('No playable files found');
    }

    final String initialVideoUrl = entries[startIndex].url;
    final String seriesTitle =
        _seriesPlaylist?.seriesTitle ??
        widget.playlistItem['title'] as String? ??
        'Series';

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
        viewMode: _convertToPlaylistViewMode(_currentViewMode),
      ),
    );
  }

  /// Play PikPak playlist
  Future<void> _playPikPakPlaylist(
    List<RDFileNode> videoFiles,
    int startIndex,
  ) async {
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
          entries.add(
            PlaylistEntry(
              url: streamingUrl ?? '',
              title: file.name,
              relativePath: file.relativePath,
              pikpakFileId: fileId,
              sizeBytes: file.bytes,
              provider: 'pikpak',
            ),
          );
        } catch (_) {
          entries.add(
            PlaylistEntry(
              url: '',
              title: file.name,
              relativePath: file.relativePath,
              pikpakFileId: fileId,
              sizeBytes: file.bytes,
              provider: 'pikpak',
            ),
          );
        }
      } else {
        entries.add(
          PlaylistEntry(
            url: '',
            title: file.name,
            relativePath: file.relativePath,
            pikpakFileId: fileId,
            sizeBytes: file.bytes,
            provider: 'pikpak',
          ),
        );
      }
    }

    if (entries.isEmpty) {
      throw Exception('No playable files found');
    }

    final String initialVideoUrl = entries[startIndex].url;
    final String seriesTitle =
        _seriesPlaylist?.seriesTitle ??
        widget.playlistItem['title'] as String? ??
        'Series';

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
        viewMode: _convertToPlaylistViewMode(_currentViewMode),
      ),
    );
  }

  /// Clean Torbox path by removing "TorrentName..." prefix
  /// Example: "TorrentName.../Season 1/Episode 1.mkv" -> "Season 1/Episode 1.mkv"
  String? _cleanTorboxPath(String? path) {
    if (path == null) return null;

    // Step 1: Remove "TorrentName..." prefix
    String cleanedPath = path;
    if (path.contains('.../')) {
      final parts = path.split('.../');
      if (parts.length > 1) {
        cleanedPath = parts.skip(1).join('.../');
      }
    }

    // Step 2: Strip first-level folder for Torbox files
    // Example: "Chapter_1-Introduction/1. Introduction.mp4" -> "1. Introduction.mp4"
    final firstSlash = cleanedPath.indexOf('/');
    if (firstSlash > 0) {
      cleanedPath = cleanedPath.substring(firstSlash + 1);
    }

    return cleanedPath;
  }
}
