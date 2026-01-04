import 'dart:ui';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:android_intent_plus/android_intent.dart';
import '../../models/torbox_file.dart';
import '../../models/torbox_torrent.dart';
import '../../models/torbox_web_download.dart';
import '../../models/rd_file_node.dart';
import '../../services/torbox_service.dart';
import '../../services/video_player_launcher.dart';
import '../../services/torbox_torrent_control_service.dart';
import '../../services/storage_service.dart';
import '../../services/main_page_bridge.dart';
import '../../services/download_service.dart';
import '../../utils/formatters.dart';
import '../../utils/file_utils.dart';
import '../../utils/series_parser.dart';
import '../../utils/torbox_folder_tree_builder.dart';
import '../../widgets/stat_chip.dart';
import '../../widgets/file_selection_dialog.dart';
import '../video_player_screen.dart';
import '../debrify_tv/widgets/tv_focus_scroll_wrapper.dart';

class TorboxDownloadsScreen extends StatefulWidget {
  const TorboxDownloadsScreen({
    super.key,
    this.initialTorrentToOpen,
    this.isPushedRoute = false,
  });

  final TorboxTorrent? initialTorrentToOpen;

  /// When true, this screen was pushed as a route (not displayed in a tab).
  /// Back navigation will pop the route instead of switching tabs.
  final bool isPushedRoute;

  @override
  State<TorboxDownloadsScreen> createState() => _TorboxDownloadsScreenState();
}

enum _FolderViewMode { raw, sortedAZ, seriesArrange }

enum _TorboxDownloadsView { torrents, webDownloads }

class _TorboxDownloadsScreenState extends State<TorboxDownloadsScreen> {
  _TorboxDownloadsView _selectedView = _TorboxDownloadsView.torrents;

  final ScrollController _scrollController = ScrollController();
  final List<TorboxTorrent> _torrents = [];
  final TextEditingController _magnetController = TextEditingController();

  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  bool _initialLoad = true;
  int _offset = 0;
  String _errorMessage = '';
  String? _apiKey;
  TorboxTorrent? _pendingInitialTorrent;
  bool _initialActionHandled = false;

  // Web Downloads state
  final List<TorboxWebDownload> _webDownloads = [];
  final ScrollController _webDownloadScrollController = ScrollController();
  bool _isLoadingWebDownloads = false;
  bool _isLoadingMoreWebDownloads = false;
  bool _hasMoreWebDownloads = true;
  int _webDownloadOffset = 0;
  String _webDownloadErrorMessage = '';
  final TextEditingController _webLinkController = TextEditingController();
  final TextEditingController _webNameController = TextEditingController();
  final TextEditingController _webPasswordController = TextEditingController();

  // Folder navigation state
  TorboxTorrent? _currentTorrent; // null means we're at root (torrent list)
  TorboxWebDownload? _currentWebDownload; // null means we're not viewing a web download
  List<String> _currentPath = []; // Path within current torrent/web download's folder tree
  RDFileNode? _currentFolderNode; // Current folder node being viewed
  final List<({TorboxTorrent? torrent, TorboxWebDownload? webDownload, List<String> path, RDFileNode? node})> _navigationStack = [];

  // View mode state
  final Map<int, _FolderViewMode> _torrentViewModes = {};
  final Map<int, _FolderViewMode> _webDownloadViewModes = {};
  List<RDFileNode>? _currentViewNodes;

  // Focus nodes for TV/DPAD navigation
  final FocusNode _viewModeDropdownFocusNode = FocusNode(debugLabel: 'torbox-view-mode');

  // Search state (for folder browsing mode)
  bool _isSearchActive = false;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode(debugLabel: 'torbox-search');
  final FocusNode _searchButtonFocusNode = FocusNode(debugLabel: 'torbox-search-button');
  final FocusNode _searchClearFocusNode = FocusNode(debugLabel: 'torbox-search-clear');
  List<_TorboxSearchResult> _searchResults = [];

  static const int _limit = 50;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _webDownloadScrollController.addListener(_onWebDownloadScroll);
    _pendingInitialTorrent = widget.initialTorrentToOpen;
    _loadApiKeyAndTorrents();

    // Register back navigation handler for folder navigation
    if (widget.isPushedRoute) {
      MainPageBridge.pushRouteBackHandler(_handleBackNavigation);
      // Set up timeout - if we're still at root after 10 seconds, pop and show error
      Future.delayed(const Duration(seconds: 10), () {
        if (mounted && widget.isPushedRoute && _isAtRoot) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to open torrent. Please try again.'),
              backgroundColor: Color(0xFFEF4444),
            ),
          );
        }
      });
    } else {
      MainPageBridge.registerTabBackHandler('torbox', _handleBackNavigation);
    }
  }

  @override
  void didUpdateWidget(TorboxDownloadsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialTorrentToOpen != null) {
      _pendingInitialTorrent = widget.initialTorrentToOpen;
      _initialActionHandled = false;
      _maybeTriggerInitialAction();
    }
  }

  /// Download files from a torrent with file selection dialog
  Future<void> _downloadAllTorrentFiles(TorboxTorrent torrent) async {
    final key = _apiKey;
    if (key == null || key.isEmpty) {
      _showSnackBar('Torbox API key not configured');
      return;
    }

    print('📦 Showing file selection for torrent: ${torrent.name}');
    print('   File count: ${torrent.files.length}');

    if (torrent.files.isEmpty) {
      _showSnackBar('No files found in torrent');
      return;
    }

    // Temporarily set _currentTorrent for the download process
    final previousTorrent = _currentTorrent;
    _currentTorrent = torrent;

    // Format files for FileSelectionDialog
    final formattedFiles = <Map<String, dynamic>>[];
    for (final file in torrent.files) {
      // Use shortName for file name, fullName for path structure
      final fullPath = file.name; // Full path with folders
      final relativePath = fullPath.contains('/')
          ? fullPath.substring(fullPath.indexOf('/') + 1)
          : fullPath;

      formattedFiles.add({
        '_fullPath': relativePath,
        'name': file.shortName.isNotEmpty ? file.shortName : FileUtils.getFileName(file.name),
        'size': file.size.toString(),
        '_torboxFile': file, // Store original TorboxFile for download
      });
    }

    // Show file selection dialog
    if (!mounted) {
      _currentTorrent = previousTorrent;
      return;
    }

    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return FileSelectionDialog(
          files: formattedFiles,
          torrentName: torrent.name,
          onDownload: (selectedFiles) {
            if (selectedFiles.isEmpty) return;
            _downloadSelectedTorboxFiles(selectedFiles, torrent.name);
          },
        );
      },
    );

    // Restore previous torrent
    _currentTorrent = previousTorrent;
  }

  Future<void> _handleAddToPlaylist(TorboxTorrent torrent) async {
    final videoFiles = torrent.files.where(_torboxFileLooksLikeVideo).toList();
    if (videoFiles.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No playable Torbox video files found.')),
      );
      return;
    }

    if (videoFiles.length == 1) {
      final file = videoFiles.first;
      final displayName = file.shortName.isNotEmpty
          ? file.shortName
          : FileUtils.getFileName(file.name);
      final added = await StorageService.addPlaylistItemRaw({
        'provider': 'torbox',
        'title': FileUtils.cleanPlaylistTitle(displayName.isNotEmpty ? displayName : torrent.name),
        'kind': 'single',
        'torboxTorrentId': torrent.id,
        'torboxFileId': file.id,
        'torrent_hash': torrent.hash,
        'sizeBytes': file.size,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(added ? 'Added to playlist' : 'Already in playlist'),
          backgroundColor: added ? null : const Color(0xFFEF4444),
        ),
      );
      return;
    }

    final ids = videoFiles.map((file) => file.id).toList();
    final added = await StorageService.addPlaylistItemRaw({
      'provider': 'torbox',
      'title': FileUtils.cleanPlaylistTitle(torrent.name),
      'kind': 'collection',
      'torboxTorrentId': torrent.id,
      'torboxFileIds': ids,
      'torrent_hash': torrent.hash,
      'count': videoFiles.length,
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          added ? 'Added collection to playlist' : 'Already in playlist',
        ),
        backgroundColor: added ? null : const Color(0xFFEF4444),
      ),
    );
  }

  Future<void> _copyTorrentLink(TorboxTorrent torrent) async {
    if (torrent.files.isEmpty) {
      _showComingSoon('No files available');
      return;
    }

    final file = torrent.files.firstWhere(
      (file) => !file.zipped,
      orElse: () => torrent.files.first,
    );

    await _copyTorboxFileLink(torrent, file);
  }

  Future<void> _copyTorboxFileLink(
    TorboxTorrent torrent,
    TorboxFile file,
  ) async {
    final key = _apiKey;
    if (key == null || key.isEmpty) {
      _showComingSoon('Add Torbox API key');
      return;
    }

    try {
      final link = await TorboxService.requestFileDownloadLink(
        apiKey: key,
        torrentId: torrent.id,
        fileId: file.id,
      );
      if (!mounted) return;
      await Clipboard.setData(ClipboardData(text: link));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Download link copied to clipboard.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to copy link: ${_formatTorboxError(e)}'),
          backgroundColor: const Color(0xFFEF4444),
        ),
      );
    }
  }

  Future<void> _copyTorrentZipLink(TorboxTorrent torrent) async {
    final key = _apiKey;
    if (key == null || key.isEmpty) {
      _showComingSoon('Add Torbox API key');
      return;
    }

    try {
      final zipUrl = TorboxService.createZipPermalink(key, torrent.id);
      await Clipboard.setData(ClipboardData(text: zipUrl));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ZIP download link copied to clipboard.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to copy ZIP link: ${_formatTorboxError(e)}'),
          backgroundColor: const Color(0xFFEF4444),
        ),
      );
    }
  }

  void _showTorboxTorrentMoreOptions(TorboxTorrent torrent) {
    final isMultiFile = torrent.files.length > 1;
    final options = <_TorboxMoreOption>[
      _TorboxMoreOption(
        icon: Icons.playlist_add,
        label: 'Add to Playlist',
        onTap: () => _handleAddToPlaylist(torrent),
      ),
      _TorboxMoreOption(
        icon: Icons.copy,
        label: 'Copy Link',
        onTap: isMultiFile
            ? () => _copyTorrentZipLink(torrent)
            : () => _copyTorrentLink(torrent),
      ),
      _TorboxMoreOption(
        icon: Icons.delete_outline,
        label: 'Delete Torrent',
        onTap: () => _confirmDeleteTorrent(torrent),
        destructive: true,
      ),
    ];

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
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
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
                                  await option.onTap();
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

  Future<void> _handlePlayTorrent(TorboxTorrent torrent) async {
    final key = _apiKey;
    if (key == null || key.isEmpty) {
      _showComingSoon('Add Torbox API key');
      return;
    }

    final videoFiles = torrent.files.where((file) {
      if (file.zipped) return false;
      return _torboxFileLooksLikeVideo(file);
    }).toList();

    debugPrint(
      'TorboxPlay: torrentId=${torrent.id} files=${videoFiles.length} name="${torrent.name}"',
    );

    if (videoFiles.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No playable video files found in this torrent.'),
          backgroundColor: Color(0xFFEF4444),
        ),
      );
      return;
    }

    if (videoFiles.length == 1) {
      final file = videoFiles.first;
      try {
        final streamUrl = await _requestTorboxStreamUrl(
          apiKey: key,
          torrent: torrent,
          file: file,
        );
        if (!mounted) return;
        await VideoPlayerLauncher.push(
          context,
          VideoPlayerLaunchArgs(
            videoUrl: streamUrl,
            title: torrent.name,
            subtitle: Formatters.formatFileSize(file.size),
          ),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to play file: ${_formatTorboxError(e)}'),
            backgroundColor: const Color(0xFFEF4444),
          ),
        );
      }
      return;
    }

    final candidates = videoFiles.map((file) {
      final displayName = _torboxDisplayName(file);
      final info = SeriesParser.parseFilename(displayName);
      return _TorboxEpisodeCandidate(
        file: file,
        displayName: displayName,
        info: info,
      );
    }).toList();

    final filenames = candidates.map((entry) => entry.displayName).toList();
    final bool isSeriesCollection =
        candidates.length > 1 && SeriesParser.isSeriesPlaylist(filenames);

    final sortedCandidates = [...candidates];
    sortedCandidates.sort((a, b) {
      final aInfo = a.info;
      final bInfo = b.info;

      final aIsSeries =
          aInfo.isSeries && aInfo.season != null && aInfo.episode != null;
      final bIsSeries =
          bInfo.isSeries && bInfo.season != null && bInfo.episode != null;

      if (aIsSeries && bIsSeries) {
        final seasonCompare = (aInfo.season ?? 0).compareTo(bInfo.season ?? 0);
        if (seasonCompare != 0) return seasonCompare;

        final episodeCompare = (aInfo.episode ?? 0).compareTo(
          bInfo.episode ?? 0,
        );
        if (episodeCompare != 0) return episodeCompare;
      } else if (aIsSeries != bIsSeries) {
        return aIsSeries ? -1 : 1;
      }

      final aName = a.displayName.toLowerCase();
      final bName = b.displayName.toLowerCase();
      return aName.compareTo(bName);
    });

    int startIndex = 0;
    if (isSeriesCollection) {
      startIndex = sortedCandidates.indexWhere(
        (candidate) =>
            candidate.info.isSeries &&
            candidate.info.season != null &&
            candidate.info.episode != null,
      );
      if (startIndex == -1) {
        startIndex = 0;
      }
    }

    final seriesInfos = sortedCandidates
        .map((candidate) => candidate.info)
        .toList();

    debugPrint(
      'TorboxPlay: isSeries=$isSeriesCollection startIndex=$startIndex (season=${startIndex < seriesInfos.length ? seriesInfos[startIndex].season : 'n/a'} episode=${startIndex < seriesInfos.length ? seriesInfos[startIndex].episode : 'n/a'})',
    );

    String initialUrl = '';
    try {
      initialUrl = await _requestTorboxStreamUrl(
        apiKey: key,
        torrent: torrent,
        file: sortedCandidates[startIndex].file,
      );
    } catch (e) {
      debugPrint(
        'TorboxDownloadsScreen: failed to prefetch initial stream for torrent=${torrent.id} fileIndex=$startIndex error=$e',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to prepare stream: ${_formatTorboxError(e)}'),
          backgroundColor: const Color(0xFFEF4444),
        ),
      );
      return;
    }

    final playlistEntries = <PlaylistEntry>[];
    for (int i = 0; i < sortedCandidates.length; i++) {
      final candidate = sortedCandidates[i];
      final info = candidate.info;
      final displayName = candidate.displayName;
      final episodeLabel = _formatTorboxPlaylistTitle(
        info: info,
        fallback: displayName,
        isSeriesCollection: isSeriesCollection,
      );
      final combinedTitle = _composeTorboxEntryTitle(
        seriesTitle: info.title,
        episodeLabel: episodeLabel,
        isSeriesCollection: isSeriesCollection,
        fallback: displayName,
      );

      // Strip first folder level (torrent name) from path
      String relativePath = candidate.file.name;
      final firstSlash = relativePath.indexOf('/');
      if (firstSlash > 0) {
        relativePath = relativePath.substring(firstSlash + 1);
      }

      playlistEntries.add(
        PlaylistEntry(
          url: i == startIndex ? initialUrl : '',
          title: combinedTitle,
          relativePath: relativePath, // Now excludes torrent name folder
          provider: 'torbox',
          torboxTorrentId: torrent.id,
          torboxFileId: candidate.file.id,
          sizeBytes: candidate.file.size,
          torrentHash: torrent.hash.isNotEmpty ? torrent.hash : null,
        ),
      );

      debugPrint(
        'TorboxPlay: entry[$i] title="$combinedTitle" season=${info.season} episode=${info.episode}',
      );
    }

    final totalBytes = sortedCandidates.fold<int>(
      0,
      (sum, entry) => sum + entry.file.size,
    );
    final subtitle =
        '${playlistEntries.length} ${isSeriesCollection ? 'episodes' : 'files'} • ${Formatters.formatFileSize(totalBytes)}';

    debugPrint(
      'TorboxDownloadsScreen: Play torrent ${torrent.id} (${playlistEntries.length} entries, startIndex=$startIndex, isSeries=$isSeriesCollection)',
    );

    if (!mounted) return;
    await VideoPlayerLauncher.push(
      context,
      VideoPlayerLaunchArgs(
        videoUrl: initialUrl,
        title: torrent.name,
        subtitle: subtitle,
        playlist: playlistEntries,
        startIndex: startIndex,
      ),
    );
  }

  Future<void> _confirmDeleteAll() async {
    final key = _apiKey;
    if (key == null || key.isEmpty) {
      _showComingSoon('Add Torbox API key');
      return;
    }

    if (_torrents.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete all torrents?'),
        content: Text(
          'Are you sure you want to delete all ${_torrents.length} cached torrents from Torbox? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
            ),
            child: const Text('Delete All'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await TorboxTorrentControlService.deleteTorrent(
        apiKey: key,
        deleteAll: true,
      );

      if (!mounted) return;

      setState(() {
        _torrents.clear();
        _hasMore = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('All Torbox torrents deleted.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to delete torrents: $e')));
    }
  }

  void _copyTorboxZipLink(TorboxTorrent torrent) {
    final key = _apiKey;
    if (key == null || key.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('API key not available'),
          backgroundColor: Color(0xFFEF4444),
        ),
      );
      return;
    }

    final zipLink = TorboxService.createZipPermalink(key, torrent.id);
    Clipboard.setData(ClipboardData(text: zipLink));

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF7C3AED),
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
                'ZIP download link copied to clipboard!',
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
  }

  Future<void> _confirmDeleteTorrent(TorboxTorrent torrent) async {
    final key = _apiKey;
    if (key == null || key.isEmpty) {
      _showComingSoon('Add Torbox API key');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete torrent?'),
        content: Text(
          'Are you sure you want to delete "${torrent.name}" from Torbox? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await TorboxTorrentControlService.deleteTorrent(
        apiKey: key,
        torrentId: torrent.id,
      );

      if (!mounted) return;

      setState(() {
        _torrents.removeWhere((item) => item.id == torrent.id);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Torrent deleted from Torbox.')),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to delete torrent: $e')));
    }
  }

  @override
  void dispose() {
    // Unregister back navigation handler
    if (widget.isPushedRoute) {
      MainPageBridge.popRouteBackHandler(_handleBackNavigation);
    } else {
      MainPageBridge.unregisterTabBackHandler('torbox');
    }

    _scrollController.dispose();
    _webDownloadScrollController.dispose();
    _magnetController.dispose();
    _webLinkController.dispose();
    _webNameController.dispose();
    _webPasswordController.dispose();
    _viewModeDropdownFocusNode.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _searchButtonFocusNode.dispose();
    _searchClearFocusNode.dispose();
    super.dispose();
  }

  /// Handle back navigation for folder browsing.
  /// Returns true if handled (navigated up), false if at root level.
  bool _handleBackNavigation() {
    // Close search first if active
    if (_isSearchActive) {
      _toggleSearch();
      return true;
    }

    // If inside a subfolder within a torrent, navigate up
    if (!_isAtRoot && _navigationStack.length > 1) {
      _navigateUp();
      return true;
    }

    // At torrent root level (viewing torrent files, not inside a subfolder)
    if (!_isAtRoot && _navigationStack.length == 1) {
      // If pushed as a route, pop to go back
      if (widget.isPushedRoute) {
        Navigator.of(context).pop();
        return true;
      }
      // If came from torrent search flow, switch back to torrent search tab
      if (MainPageBridge.returnToTorrentSearchOnBack) {
        MainPageBridge.returnToTorrentSearchOnBack = false;
        MainPageBridge.switchTab?.call(0);
        return true;
      }
      // Normal case: go back to torrents list
      _navigateUp();
      return true;
    }

    return false; // At root, let app handle it
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        !_isLoadingMore &&
        _hasMore &&
        !_isLoading) {
      _loadMore();
    }
  }

  void _onWebDownloadScroll() {
    if (_webDownloadScrollController.position.pixels >=
            _webDownloadScrollController.position.maxScrollExtent - 200 &&
        !_isLoadingMoreWebDownloads &&
        _hasMoreWebDownloads &&
        !_isLoadingWebDownloads) {
      _loadMoreWebDownloads();
    }
  }

  Future<void> _loadApiKeyAndTorrents() async {
    final key = await StorageService.getTorboxApiKey();
    if (!mounted) return;

    setState(() {
      _apiKey = key;
    });

    if (key == null || key.isEmpty) {
      setState(() {
        _initialLoad = false;
        _errorMessage =
            'Add your Torbox API key in Settings to view cached torrents.';
        _webDownloadErrorMessage =
            'Add your Torbox API key in Settings to view web downloads.';
      });
      return;
    }

    await Future.wait([
      _fetchTorrents(reset: true),
      _fetchWebDownloads(reset: true),
    ]);
  }

  Future<void> _fetchTorrents({bool reset = false}) async {
    final key = _apiKey;
    if (key == null || key.isEmpty) return;

    if (reset) {
      setState(() {
        _isLoading = true;
        _initialLoad = true;
        _errorMessage = '';
        _offset = 0;
        _hasMore = true;
        _torrents.clear();
      });
    } else {
      setState(() {
        _isLoadingMore = true;
      });
    }

    try {
      final result = await TorboxService.getTorrents(
        key,
        offset: _offset,
        limit: _limit,
      );
      final List<TorboxTorrent> fetched = (result['torrents'] as List)
          .cast<TorboxTorrent>();
      final bool hasMore = result['hasMore'] as bool? ?? false;
      final bool shouldFetchMore = fetched.isEmpty && hasMore;

      if (!mounted) return;

      setState(() {
        _torrents.addAll(fetched);
        _hasMore = hasMore;
        _offset += _limit;
        _isLoading = false;
        _isLoadingMore = false;
        _initialLoad = false;
        if (_torrents.isNotEmpty) {
          _errorMessage = '';
        } else if (!hasMore) {
          _errorMessage =
              'No cached torrents found yet. Add torrents via Torbox to see them here.';
        }
      });

      _maybeTriggerInitialAction();

      if (shouldFetchMore) {
        await _fetchTorrents();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
        _isLoading = false;
        _isLoadingMore = false;
        _initialLoad = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore) return;
    await _fetchTorrents();
  }

  Future<void> _refresh() async {
    if (_selectedView == _TorboxDownloadsView.torrents) {
      await _fetchTorrents(reset: true);
    } else {
      await _fetchWebDownloads(reset: true);
    }
  }

  // ==================== WEB DOWNLOADS METHODS ====================

  Future<void> _fetchWebDownloads({bool reset = false}) async {
    final key = _apiKey;
    if (key == null || key.isEmpty) return;

    if (reset) {
      setState(() {
        _isLoadingWebDownloads = true;
        _webDownloadErrorMessage = '';
        _webDownloadOffset = 0;
        _hasMoreWebDownloads = true;
        _webDownloads.clear();
      });
    } else {
      setState(() {
        _isLoadingMoreWebDownloads = true;
      });
    }

    try {
      final result = await TorboxService.getWebDownloads(
        key,
        offset: _webDownloadOffset,
        limit: _limit,
      );

      if (!mounted) return;

      final webDownloads = result['webDownloads'] as List<TorboxWebDownload>;
      final hasMore = result['hasMore'] as bool;

      setState(() {
        _webDownloads.addAll(webDownloads);
        _webDownloadOffset += webDownloads.length;
        _hasMoreWebDownloads = hasMore;
        _isLoadingWebDownloads = false;
        _isLoadingMoreWebDownloads = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _webDownloadErrorMessage = e.toString().replaceFirst('Exception: ', '');
        _isLoadingWebDownloads = false;
        _isLoadingMoreWebDownloads = false;
      });
    }
  }

  Future<void> _loadMoreWebDownloads() async {
    if (_isLoadingMoreWebDownloads || !_hasMoreWebDownloads) return;
    await _fetchWebDownloads();
  }

  Future<void> _handlePlayWebDownload(TorboxWebDownload webDownload) async {
    final key = _apiKey;
    if (key == null || key.isEmpty) {
      _showSnackBar('Torbox API key not configured');
      return;
    }

    final videoFiles = webDownload.files.where((file) {
      if (file.zipped) return false;
      return _torboxFileLooksLikeVideo(file);
    }).toList();

    if (videoFiles.isEmpty) {
      _showSnackBar('No playable video files found in this download.');
      return;
    }

    if (videoFiles.length == 1) {
      final file = videoFiles.first;
      try {
        final streamUrl = await TorboxService.requestWebDownloadFileLink(
          apiKey: key,
          webId: webDownload.id,
          fileId: file.id,
        );
        if (!mounted) return;
        await VideoPlayerLauncher.push(
          context,
          VideoPlayerLaunchArgs(
            videoUrl: streamUrl,
            title: webDownload.name,
            subtitle: Formatters.formatFileSize(file.size),
          ),
        );
      } catch (e) {
        if (!mounted) return;
        _showSnackBar('Failed to play file: ${_formatTorboxError(e)}');
      }
      return;
    }

    // Multiple video files - show selection dialog
    await showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Select a file to play'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: videoFiles.length,
              itemBuilder: (context, index) {
                final file = videoFiles[index];
                final fileName = file.shortName.isNotEmpty
                    ? file.shortName
                    : FileUtils.getFileName(file.name);
                return ListTile(
                  leading: const Icon(Icons.play_circle_outline),
                  title: Text(fileName, maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: Text(Formatters.formatFileSize(file.size)),
                  onTap: () async {
                    Navigator.of(dialogContext).pop();
                    try {
                      final streamUrl = await TorboxService.requestWebDownloadFileLink(
                        apiKey: key,
                        webId: webDownload.id,
                        fileId: file.id,
                      );
                      if (!mounted) return;
                      await VideoPlayerLauncher.push(
                        context,
                        VideoPlayerLaunchArgs(
                          videoUrl: streamUrl,
                          title: fileName,
                          subtitle: Formatters.formatFileSize(file.size),
                        ),
                      );
                    } catch (e) {
                      if (!mounted) return;
                      _showSnackBar('Failed to play file: ${_formatTorboxError(e)}');
                    }
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
  }

  /// Show dialog with download options for web downloads: select files or download as ZIP
  void _showWebDownloadOptionsDialog(TorboxWebDownload webDownload) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
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
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: Colors.white.withValues(alpha: 0.1),
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.download_rounded,
                          color: Color(0xFF10B981),
                          size: 24,
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'Download Options',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(dialogContext).pop(),
                          icon: const Icon(Icons.close),
                          color: Colors.grey.shade400,
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                  ),
                  // Options
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        // Option 1: Select files to download
                        _buildDownloadOptionCard(
                          icon: Icons.checklist_rounded,
                          title: 'Select files to download',
                          description: 'Choose specific files from this download',
                          color: const Color(0xFF6366F1),
                          onTap: () {
                            Navigator.of(dialogContext).pop();
                            _downloadWebDownloadFiles(webDownload);
                          },
                        ),
                        const SizedBox(height: 12),
                        // Option 2: Download as ZIP
                        _buildDownloadOptionCard(
                          icon: Icons.folder_zip_rounded,
                          title: 'Download as ZIP',
                          description: 'Download all files in a single ZIP archive',
                          color: const Color(0xFF10B981),
                          onTap: () {
                            _enqueueWebDownloadZipDownload(
                              webDownload: webDownload,
                              sheetContext: dialogContext,
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// Enqueue a ZIP download for a web download
  Future<void> _enqueueWebDownloadZipDownload({
    required TorboxWebDownload webDownload,
    required BuildContext sheetContext,
  }) async {
    final key = _apiKey;
    if (key == null || key.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Torbox API key is required. Please add it in Settings.'),
            backgroundColor: Color(0xFFEF4444),
          ),
        );
      }
      return;
    }

    Navigator.of(sheetContext).pop();

    if (!mounted) {
      return;
    }

    debugPrint(
      'TorboxDownloadsScreen: Starting ZIP download for web download ${webDownload.id}',
    );

    // Show loading indicator
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Preparing ZIP download...'),
        duration: Duration(seconds: 2),
      ),
    );

    try {
      // Generate ZIP permalink
      final zipUrl = TorboxService.createWebDownloadZipPermalink(key, webDownload.id);

      if (zipUrl.isEmpty) {
        debugPrint('TorboxDownloadsScreen: Failed to generate ZIP permalink');
        if (mounted) {
          messenger.showSnackBar(
            const SnackBar(
              content: Text('Failed to generate ZIP download link'),
              backgroundColor: Color(0xFFEF4444),
            ),
          );
        }
        return;
      }

      debugPrint('TorboxDownloadsScreen: Generated ZIP permalink: $zipUrl');

      // Create meta JSON with Torbox-specific fields for ZIP
      final meta = jsonEncode({
        'torboxWebDownloadId': webDownload.id,
        'apiKey': key,
        'torboxWebDownload': true,
        'torboxZip': true,
      });

      // Enqueue ZIP download
      final zipFileName = '${webDownload.name}.zip';
      await DownloadService.instance.enqueueDownload(
        url: zipUrl,
        fileName: zipFileName,
        meta: meta,
        torrentName: webDownload.name,
      );

      debugPrint('TorboxDownloadsScreen: Successfully enqueued ZIP download');

      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('ZIP download queued successfully'),
            backgroundColor: Color(0xFF10B981),
          ),
        );
      }
    } catch (e, stackTrace) {
      debugPrint('TorboxDownloadsScreen: Error during ZIP download: $e');
      debugPrint('Stack trace: $stackTrace');
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString().replaceFirst('Exception: ', '')}'),
            backgroundColor: const Color(0xFFEF4444),
          ),
        );
      }
    }
  }

  Future<void> _downloadWebDownloadFiles(TorboxWebDownload webDownload) async {
    final key = _apiKey;
    if (key == null || key.isEmpty) {
      _showSnackBar('Torbox API key not configured');
      return;
    }

    if (webDownload.files.isEmpty) {
      _showSnackBar('No files found in this download');
      return;
    }

    // Format files for FileSelectionDialog
    final formattedFiles = <Map<String, dynamic>>[];
    for (final file in webDownload.files) {
      formattedFiles.add({
        '_fullPath': file.name,
        'name': file.shortName.isNotEmpty ? file.shortName : FileUtils.getFileName(file.name),
        'size': file.size.toString(),
        '_torboxFile': file,
        '_webDownloadId': webDownload.id,
      });
    }

    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return FileSelectionDialog(
          files: formattedFiles,
          torrentName: webDownload.name,
          onDownload: (selectedFiles) {
            if (selectedFiles.isEmpty) return;
            _downloadSelectedWebDownloadFiles(selectedFiles, webDownload);
          },
        );
      },
    );
  }

  Future<void> _downloadSelectedWebDownloadFiles(
    List<Map<String, dynamic>> selectedFiles,
    TorboxWebDownload webDownload,
  ) async {
    final key = _apiKey;
    if (key == null || key.isEmpty) return;

    if (!mounted) return;

    try {
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

      int successCount = 0;
      int failCount = 0;

      for (final fileData in selectedFiles) {
        try {
          final file = fileData['_torboxFile'] as TorboxFile;
          final fileName = (fileData['_fullPath'] as String?) ?? (fileData['name'] as String? ?? file.shortName);

          final meta = jsonEncode({
            'torboxWebDownloadId': webDownload.id,
            'torboxFileId': file.id,
            'apiKey': key,
            'torboxWebDownload': true,
          });

          await DownloadService.instance.enqueueDownload(
            url: '',
            fileName: fileName,
            meta: meta,
            torrentName: webDownload.name,
            context: mounted ? context : null,
          );

          successCount++;
        } catch (e) {
          failCount++;
        }
      }

      if (mounted) Navigator.of(context).pop();

      if (successCount > 0 && failCount == 0) {
        _showSnackBar(
          'Queued $successCount file${successCount == 1 ? '' : 's'} for download',
          isError: false,
        );
      } else if (successCount > 0 && failCount > 0) {
        _showSnackBar(
          'Queued $successCount file${successCount == 1 ? '' : 's'}, $failCount failed',
        );
      } else {
        _showSnackBar('Failed to queue any files for download');
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      _showSnackBar('Failed to queue downloads: $e');
    }
  }

  Future<void> _copyWebDownloadLink(TorboxWebDownload webDownload) async {
    final key = _apiKey;
    if (key == null || key.isEmpty) {
      _showSnackBar('Torbox API key not configured');
      return;
    }

    if (webDownload.files.isEmpty) {
      _showSnackBar('No files available');
      return;
    }

    if (webDownload.files.length == 1) {
      // Single file - get direct link
      try {
        final link = await TorboxService.requestWebDownloadFileLink(
          apiKey: key,
          webId: webDownload.id,
          fileId: webDownload.files.first.id,
        );
        if (!mounted) return;
        await Clipboard.setData(ClipboardData(text: link));
        _showSnackBar('Download link copied to clipboard.', isError: false);
      } catch (e) {
        if (!mounted) return;
        _showSnackBar('Failed to copy link: ${_formatTorboxError(e)}');
      }
    } else {
      // Multiple files - get ZIP link
      final zipLink = TorboxService.createWebDownloadZipPermalink(key, webDownload.id);
      await Clipboard.setData(ClipboardData(text: zipLink));
      if (!mounted) return;
      _showSnackBar('ZIP download link copied to clipboard.', isError: false);
    }
  }

  Future<void> _handleAddWebDownloadToPlaylist(TorboxWebDownload webDownload) async {
    final videoFiles = webDownload.files.where((file) {
      if (file.zipped) return false;
      return _torboxFileLooksLikeVideo(file);
    }).toList();

    if (videoFiles.isEmpty) {
      _showSnackBar('No video files found in this download.');
      return;
    }

    if (videoFiles.length == 1) {
      // Single video - add as single item
      final file = videoFiles.first;
      final added = await StorageService.addPlaylistItemRaw({
        'provider': 'torbox_webdl',
        'title': FileUtils.cleanPlaylistTitle(webDownload.name),
        'kind': 'single',
        'torboxWebDownloadId': webDownload.id,
        'torboxFileId': file.id,
        'webdl_hash': webDownload.hash,
        'sizeBytes': file.size,
      });

      _showSnackBar(
        added ? 'Added to playlist' : 'Already in playlist',
        isError: !added,
      );
    } else {
      // Multiple videos - add as collection
      final ids = videoFiles.map((f) => f.id).toList();
      final added = await StorageService.addPlaylistItemRaw({
        'provider': 'torbox_webdl',
        'title': FileUtils.cleanPlaylistTitle(webDownload.name),
        'kind': 'collection',
        'torboxWebDownloadId': webDownload.id,
        'torboxFileIds': ids,
        'webdl_hash': webDownload.hash,
        'count': videoFiles.length,
      });

      _showSnackBar(
        added ? 'Added ${videoFiles.length} videos to playlist' : 'Already in playlist',
        isError: !added,
      );
    }
  }

  Future<void> _confirmDeleteWebDownload(TorboxWebDownload webDownload) async {
    final key = _apiKey;
    if (key == null || key.isEmpty) {
      _showSnackBar('Torbox API key not configured');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete web download?'),
        content: Text(
          'Are you sure you want to delete "${webDownload.name}" from Torbox? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await TorboxService.deleteWebDownload(
        apiKey: key,
        webId: webDownload.id,
      );

      if (!mounted) return;

      setState(() {
        _webDownloads.removeWhere((item) => item.id == webDownload.id);
      });

      _showSnackBar('Web download deleted from Torbox.', isError: false);
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('Failed to delete web download: ${_formatTorboxError(e)}');
    }
  }

  Future<void> _showAddWebDownloadDialog() async {
    if (_apiKey == null || _apiKey!.isEmpty) {
      _showSnackBar('Add Torbox API key first');
      return;
    }

    _webLinkController.clear();
    _webNameController.clear();
    _webPasswordController.clear();

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Add Web Download'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Focus(
                  onKeyEvent: (node, event) {
                    if (event is KeyDownEvent) {
                      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                        node.nextFocus();
                        return KeyEventResult.handled;
                      }
                    }
                    return KeyEventResult.ignored;
                  },
                  child: TextField(
                    controller: _webLinkController,
                    maxLines: 2,
                    autofocus: true,
                    decoration: const InputDecoration(
                      hintText: 'Paste URL here (YouTube, file hosts, etc.)',
                      labelText: 'URL *',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Focus(
                  onKeyEvent: (node, event) {
                    if (event is KeyDownEvent) {
                      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                        node.nextFocus();
                        return KeyEventResult.handled;
                      } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                        node.previousFocus();
                        return KeyEventResult.handled;
                      }
                    }
                    return KeyEventResult.ignored;
                  },
                  child: TextField(
                    controller: _webNameController,
                    decoration: const InputDecoration(
                      hintText: 'Custom name for the download',
                      labelText: 'Name (optional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Focus(
                  onKeyEvent: (node, event) {
                    if (event is KeyDownEvent) {
                      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                        node.nextFocus();
                        return KeyEventResult.handled;
                      } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                        node.previousFocus();
                        return KeyEventResult.handled;
                      }
                    }
                    return KeyEventResult.ignored;
                  },
                  child: TextField(
                    controller: _webPasswordController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      hintText: 'Password if required',
                      labelText: 'Password (optional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Supports YouTube, file hosts, and direct links.',
                  style: TextStyle(
                    color: Colors.grey[400],
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => _handleAddWebDownload(dialogContext),
              child: const Text('Add'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _handleAddWebDownload(BuildContext dialogContext) async {
    final link = _webLinkController.text.trim();
    if (link.isEmpty) {
      _showSnackBar('Please enter a URL.');
      return;
    }

    // Basic URL validation
    if (!link.startsWith('http://') && !link.startsWith('https://')) {
      _showSnackBar('Please enter a valid URL starting with http:// or https://');
      return;
    }

    Navigator.of(dialogContext).pop();

    final apiKey = _apiKey;
    if (apiKey == null || apiKey.isEmpty) return;

    final navigator = Navigator.of(context, rootNavigator: true);
    var dialogClosed = false;

    void closeDialogIfOpen() {
      if (!dialogClosed && navigator.canPop()) {
        navigator.pop();
        dialogClosed = true;
      }
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        return const AlertDialog(
          title: Text('Adding web download'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('This may take up to a minute...'),
            ],
          ),
        );
      },
    );

    try {
      final response = await TorboxService.createWebDownload(
        apiKey: apiKey,
        link: link,
        name: _webNameController.text.trim().isNotEmpty ? _webNameController.text.trim() : null,
        password: _webPasswordController.text.trim().isNotEmpty ? _webPasswordController.text.trim() : null,
      );

      if (!mounted) return;

      closeDialogIfOpen();

      final success = response['success'] as bool? ?? false;
      if (!success) {
        final errorMessage = (response['error'] ?? 'Failed to add web download').toString();
        _showSnackBar(errorMessage);
        return;
      }

      _webLinkController.clear();
      _webNameController.clear();
      _webPasswordController.clear();

      final detail = response['detail'] as String? ?? 'Web download added.';
      _showSnackBar(detail, isError: false);

      // Refresh the web downloads list
      await _fetchWebDownloads(reset: true);
    } catch (e) {
      if (!mounted) return;
      closeDialogIfOpen();
      _showSnackBar('Failed to add web download: ${e.toString().replaceFirst('Exception: ', '')}');
    }
  }

  bool _torboxFileLooksLikeVideo(TorboxFile file) {
    final name = file.shortName.isNotEmpty
        ? file.shortName
        : FileUtils.getFileName(file.name);
    return FileUtils.isVideoFile(name) ||
        (file.mimetype?.toLowerCase().startsWith('video/') ?? false);
  }

  String _torboxDisplayName(TorboxFile file) {
    if (file.shortName.isNotEmpty) {
      return file.shortName;
    }
    if (file.name.isNotEmpty) {
      return FileUtils.getFileName(file.name);
    }
    return 'File ${file.id}';
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

  void _maybeTriggerInitialAction() {
    if (_initialActionHandled) {
      return;
    }
    final pendingTorrent = _pendingInitialTorrent;
    if (pendingTorrent == null) {
      return;
    }

    // Try to find the torrent in the loaded list first
    TorboxTorrent? target;
    for (final torrent in _torrents) {
      if (torrent.id == pendingTorrent.id) {
        target = torrent;
        break;
      }
    }

    // If not found in list, use the pending torrent directly
    // (it already has all the data from the API response)
    target ??= pendingTorrent;

    _initialActionHandled = true;
    _pendingInitialTorrent = null;

    final selected = target;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Navigate directly into the torrent folder instead of showing popups
      // This matches the Real-Debrid behavior
      _navigateIntoTorrent(selected);
    });
  }

  Future<String> _requestTorboxStreamUrl({
    required String apiKey,
    required TorboxTorrent torrent,
    required TorboxFile file,
  }) async {
    final url = await TorboxService.requestFileDownloadLink(
      apiKey: apiKey,
      torrentId: torrent.id,
      fileId: file.id,
    );
    if (url.isEmpty) {
      throw Exception('Torbox returned an empty stream URL');
    }
    return url;
  }

  String _formatTorboxPlaylistTitle({
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

  String _composeTorboxEntryTitle({
    required String? seriesTitle,
    required String episodeLabel,
    required bool isSeriesCollection,
    required String fallback,
  }) {
    if (!isSeriesCollection) {
      return fallback;
    }

    final cleanSeries = seriesTitle?.replaceAll(RegExp(r'[._\-]+$'), '').trim();
    if (cleanSeries != null && cleanSeries.isNotEmpty) {
      return '$cleanSeries $episodeLabel';
    }

    return fallback;
  }

  String _formatTorboxError(Object error) {
    final raw = error.toString();
    return raw.replaceFirst('Exception: ', '').trim();
  }

  bool _isLikelySeries(List<_TorboxFileEntry> entries) {
    if (entries.length < 2) return false;

    final episodeEntries = entries.where((entry) {
      final info = entry.seriesInfo;
      final season = info.season;
      final episode = info.episode;
      if (!info.isSeries) return false;
      if (season == null || season <= 0) return false;
      if (episode == null || episode <= 0) return false;
      return true;
    }).toList();

    if (episodeEntries.length < 2) return false;

    final uniqueEpisodeKeys = episodeEntries
        .map(
          (entry) => '${entry.seriesInfo.season}:${entry.seriesInfo.episode}',
        )
        .toSet();
    if (uniqueEpisodeKeys.length < 2) return false;

    final ratio = episodeEntries.length / entries.length;
    if (ratio < 0.6) return false;

    return true;
  }

  Future<void> _showTorboxFileSelectionSheet(TorboxTorrent torrent) async {
    if (torrent.files.isEmpty) {
      _showComingSoon('No files available');
      return;
    }

    final files = torrent.files;
    final filenames = files
        .map(
          (file) => file.shortName.isNotEmpty
              ? file.shortName
              : FileUtils.getFileName(file.name),
        )
        .toList();
    final seriesInfos = SeriesParser.parsePlaylist(filenames);

    final entries = List<_TorboxFileEntry>.generate(
      files.length,
      (index) => _TorboxFileEntry(
        file: files[index],
        index: index,
        seriesInfo: index < seriesInfos.length
            ? seriesInfos[index]
            : SeriesParser.parseFilename(files[index].shortName),
      ),
    );

    final Set<int> selectedIndices = <int>{};

    bool showRaw = false;
    int? currentSeason;
    bool isProcessing = false;
    final bool isSeries = _isLikelySeries(entries);
    final bool hasVideo = entries.any(
      (entry) => _torboxFileLooksLikeVideo(entry.file),
    );
    final bool isMovieCollection = !isSeries && hasVideo;

    await showDialog<void>(
      context: context,
      builder: (sheetContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: StatefulBuilder(
              builder: (context, setSheetState) {
              final selectedEntries =
                  entries
                      .where((entry) => selectedIndices.contains(entry.index))
                      .toList()
                    ..sort((a, b) => a.index.compareTo(b.index));
              final selectedBytes = selectedEntries.fold<int>(
                0,
                (previousValue, entry) => previousValue + entry.file.size,
              );

              Widget content;
              if (showRaw) {
                content = _buildTorboxRawList(
                  entries: entries,
                  selectedIndices: selectedIndices,
                  onToggle: (index) {
                    setSheetState(() {
                      if (selectedIndices.contains(index)) {
                        selectedIndices.remove(index);
                      } else {
                        selectedIndices.add(index);
                      }
                    });
                  },
                  onCopy: (entry) => _copyTorboxFileLink(torrent, entry.file),
                );
              } else if (isSeries) {
                content = _buildTorboxSeriesView(
                  entries: entries,
                  selectedIndices: selectedIndices,
                  currentSeason: currentSeason,
                  onSeasonChange: (season) {
                    setSheetState(() {
                      currentSeason = season;
                    });
                  },
                  onToggleFile: (index) {
                    setSheetState(() {
                      if (selectedIndices.contains(index)) {
                        selectedIndices.remove(index);
                      } else {
                        selectedIndices.add(index);
                      }
                    });
                  },
                  onToggleSeason: (season, seasonIndices) {
                    setSheetState(() {
                      final hasAll = seasonIndices.every(
                        (index) => selectedIndices.contains(index),
                      );
                      if (hasAll) {
                        for (final idx in seasonIndices) {
                          selectedIndices.remove(idx);
                        }
                      } else {
                        selectedIndices.addAll(seasonIndices);
                      }
                    });
                  },
                  onCopy: (entry) => _copyTorboxFileLink(torrent, entry.file),
                );
              } else if (isMovieCollection) {
                content = _buildTorboxMovieView(
                  entries: entries,
                  selectedIndices: selectedIndices,
                  onToggle: (index) {
                    setSheetState(() {
                      if (selectedIndices.contains(index)) {
                        selectedIndices.remove(index);
                      } else {
                        selectedIndices.add(index);
                      }
                    });
                  },
                  onCopy: (entry) => _copyTorboxFileLink(torrent, entry.file),
                );
              } else {
                content = _buildTorboxGenericList(
                  entries: entries,
                  selectedIndices: selectedIndices,
                  onToggle: (index) {
                    setSheetState(() {
                      if (selectedIndices.contains(index)) {
                        selectedIndices.remove(index);
                      } else {
                        selectedIndices.add(index);
                      }
                    });
                  },
                  onCopy: (entry) => _copyTorboxFileLink(torrent, entry.file),
                );
              }

              final selectedCount = selectedEntries.length;
              final totalCount = entries.length;
              final selectionSummary = totalCount == 0
                  ? 'No files available'
                  : selectedCount == totalCount
                  ? 'All $totalCount files selected'
                  : '$selectedCount of $totalCount files selected';
              final selectedSizeText = selectedCount == 0
                  ? '0 B'
                  : Formatters.formatFileSize(selectedBytes);

              return Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.9,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      const Color(0xFF0F172A).withValues(alpha: 0.98),
                      const Color(0xFF1E293B).withValues(alpha: 0.98),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: const Color(0xFF6366F1).withValues(alpha: 0.2),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.4),
                      blurRadius: 30,
                      offset: const Offset(0, 10),
                    ),
                    BoxShadow(
                      color: const Color(0xFF6366F1).withValues(alpha: 0.1),
                      blurRadius: 20,
                      offset: const Offset(0, 0),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 24),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E293B).withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: const Color(
                              0xFF475569,
                            ).withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    selectionSummary,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Selected size: $selectedSizeText',
                                    style: TextStyle(
                                      color: Colors.grey[400],
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Row(
                              children: [
                                Text(
                                  'Raw',
                                  style: TextStyle(
                                    color: Colors.grey[300],
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Switch.adaptive(
                                  value: showRaw,
                                  activeColor: const Color(0xFF6366F1),
                                  onChanged: (value) {
                                    setSheetState(() {
                                      showRaw = value;
                                      currentSeason = null;
                                    });
                                  },
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Expanded(child: content),
                      Container(
                        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A).withValues(alpha: 0.9),
                          borderRadius: const BorderRadius.vertical(
                            bottom: Radius.circular(28),
                          ),
                          border: Border(
                            top: BorderSide(
                              color: const Color(
                                0xFF1F2937,
                              ).withValues(alpha: 0.6),
                              width: 1,
                            ),
                          ),
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: FilledButton.icon(
                                    onPressed: isProcessing
                                        ? null
                                        : () async {
                                            setSheetState(
                                              () => isProcessing = true,
                                            );
                                            final closed =
                                                await _enqueueTorboxDownloads(
                                                  torrent: torrent,
                                                  entriesToDownload: entries,
                                                  sheetContext: sheetContext,
                                                );
                                            if (!closed) {
                                              setSheetState(
                                                () => isProcessing = false,
                                              );
                                            }
                                          },
                                    icon: const Icon(Icons.download_rounded),
                                    label: Text(
                                      isProcessing
                                          ? 'Preparing…'
                                          : 'Download All',
                                    ),
                                    style: FilledButton.styleFrom(
                                      backgroundColor: const Color(
                                        0xFF10B981,
                                      ).withValues(alpha: 0.2),
                                      foregroundColor: const Color(0xFF10B981),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 20,
                                        vertical: 14,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                    ),
                                  ),
                                ),
                                if (selectedEntries.isNotEmpty) ...[
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: FilledButton.icon(
                                      onPressed: isProcessing
                                          ? null
                                          : () async {
                                              setSheetState(
                                                () => isProcessing = true,
                                              );
                                              final closed =
                                                  await _enqueueTorboxDownloads(
                                                    torrent: torrent,
                                                    entriesToDownload:
                                                        selectedEntries,
                                                    sheetContext: sheetContext,
                                                  );
                                              if (!closed) {
                                                setSheetState(
                                                  () => isProcessing = false,
                                                );
                                              }
                                            },
                                      icon: const Icon(Icons.checklist_rounded),
                                      label: Text(
                                        isProcessing
                                            ? 'Preparing…'
                                            : 'Download Selected',
                                      ),
                                      style: FilledButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 20,
                                          vertical: 14,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: TextButton(
                                onPressed: () =>
                                    Navigator.of(sheetContext).pop(),
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                                child: const Text(
                                  'Close',
                                  style: TextStyle(
                                    color: Color(0xFF6366F1),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Future<bool> _enqueueTorboxDownloads({
    required TorboxTorrent torrent,
    required List<_TorboxFileEntry> entriesToDownload,
    required BuildContext sheetContext,
  }) async {
    final key = _apiKey;
    if (key == null || key.isEmpty) {
      Navigator.of(sheetContext).pop();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Torbox API key is required. Please add it in Settings.'),
            backgroundColor: Color(0xFFEF4444),
          ),
        );
      }
      return true;
    }

    if (entriesToDownload.isEmpty) {
      Navigator.of(sheetContext).pop();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No files selected for download.'),
            backgroundColor: Color(0xFFEF4444),
          ),
        );
      }
      return true;
    }

    Navigator.of(sheetContext).pop();

    if (!mounted) {
      return true;
    }

    final count = entriesToDownload.length;
    debugPrint(
      'TorboxDownloadsScreen: Starting download for torrent ${torrent.id} ($count file(s)).',
    );

    // Show loading indicator
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(
        content: Text('Preparing $count file${count == 1 ? '' : 's'} for download...'),
        duration: const Duration(seconds: 2),
      ),
    );

    int successCount = 0;
    int failureCount = 0;
    String? lastError;

    try {
      for (final entry in entriesToDownload) {
        try {
          final file = entry.file;
          final fileName = file.shortName.isNotEmpty
              ? file.shortName
              : FileUtils.getFileName(file.name);

          debugPrint(
            'TorboxDownloadsScreen: Requesting download link for file ${file.id} in torrent ${torrent.id}',
          );

          // Request download link
          final downloadUrl = await TorboxService.requestFileDownloadLink(
            apiKey: key,
            torrentId: torrent.id,
            fileId: file.id,
          );

          if (downloadUrl.isEmpty) {
            debugPrint(
              'TorboxDownloadsScreen: Got empty download URL for file ${file.id}',
            );
            failureCount++;
            lastError = 'Empty download URL returned';
            continue;
          }

          debugPrint(
            'TorboxDownloadsScreen: Got download URL for file ${file.id}, enqueueing...',
          );

          // Create meta JSON with Torbox-specific fields
          final meta = jsonEncode({
            'torboxTorrentId': torrent.id,
            'torboxFileId': file.id,
            'apiKey': key,
            'torboxDownload': true,
          });

          // Enqueue download
          await DownloadService.instance.enqueueDownload(
            url: downloadUrl,
            fileName: fileName,
            meta: meta,
            torrentName: torrent.name,
          );

          successCount++;
          debugPrint(
            'TorboxDownloadsScreen: Successfully enqueued file ${file.id} ($fileName)',
          );
        } catch (e, stackTrace) {
          debugPrint('TorboxDownloadsScreen: Failed to enqueue file ${entry.file.id}: $e');
          debugPrint('Stack trace: $stackTrace');
          failureCount++;
          lastError = e.toString();
        }
      }

      if (!mounted) return true;

      // Show result feedback
      if (successCount > 0 && failureCount == 0) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              '$successCount file${successCount == 1 ? '' : 's'} queued for download',
            ),
            backgroundColor: const Color(0xFF10B981),
          ),
        );
      } else if (successCount > 0 && failureCount > 0) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              '$successCount file${successCount == 1 ? '' : 's'} queued, $failureCount failed',
            ),
            backgroundColor: const Color(0xFFF59E0B),
          ),
        );
      } else {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'Failed to queue downloads${lastError != null ? ': ${lastError.replaceFirst('Exception: ', '')}' : ''}',
            ),
            backgroundColor: const Color(0xFFEF4444),
          ),
        );
      }
    } catch (e, stackTrace) {
      debugPrint('TorboxDownloadsScreen: Error during batch download: $e');
      debugPrint('Stack trace: $stackTrace');
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString().replaceFirst('Exception: ', '')}'),
            backgroundColor: const Color(0xFFEF4444),
          ),
        );
      }
    }

    return true;
  }

  Future<void> _enqueueTorboxZipDownload({
    required TorboxTorrent torrent,
    required BuildContext sheetContext,
  }) async {
    final key = _apiKey;
    if (key == null || key.isEmpty) {
      Navigator.of(sheetContext).pop();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Torbox API key is required. Please add it in Settings.'),
            backgroundColor: Color(0xFFEF4444),
          ),
        );
      }
      return;
    }

    Navigator.of(sheetContext).pop();

    if (!mounted) {
      return;
    }

    debugPrint(
      'TorboxDownloadsScreen: Starting ZIP download for torrent ${torrent.id}',
    );

    // Show loading indicator
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Preparing ZIP download...'),
        duration: Duration(seconds: 2),
      ),
    );

    try {
      // Generate ZIP permalink
      final zipUrl = TorboxService.createZipPermalink(key, torrent.id);

      if (zipUrl.isEmpty) {
        debugPrint('TorboxDownloadsScreen: Failed to generate ZIP permalink');
        if (mounted) {
          messenger.showSnackBar(
            const SnackBar(
              content: Text('Failed to generate ZIP download link'),
              backgroundColor: Color(0xFFEF4444),
            ),
          );
        }
        return;
      }

      debugPrint('TorboxDownloadsScreen: Generated ZIP permalink: $zipUrl');

      // Create meta JSON with Torbox-specific fields for ZIP
      final meta = jsonEncode({
        'torboxTorrentId': torrent.id,
        'apiKey': key,
        'torboxDownload': true,
        'torboxZip': true,
      });

      // Enqueue ZIP download
      final zipFileName = '${torrent.name}.zip';
      await DownloadService.instance.enqueueDownload(
        url: zipUrl,
        fileName: zipFileName,
        meta: meta,
        torrentName: torrent.name,
      );

      debugPrint('TorboxDownloadsScreen: Successfully enqueued ZIP download');

      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('ZIP download queued successfully'),
            backgroundColor: Color(0xFF10B981),
          ),
        );
      }
    } catch (e, stackTrace) {
      debugPrint('TorboxDownloadsScreen: Error during ZIP download: $e');
      debugPrint('Stack trace: $stackTrace');
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString().replaceFirst('Exception: ', '')}'),
            backgroundColor: const Color(0xFFEF4444),
          ),
        );
      }
    }
  }

  /// Show dialog with download options: select files or download as ZIP
  void _showDownloadOptionsDialog(TorboxTorrent torrent) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
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
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: Colors.white.withValues(alpha: 0.1),
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.download_rounded,
                          color: Color(0xFF10B981),
                          size: 24,
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'Download Options',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(dialogContext).pop(),
                          icon: const Icon(Icons.close),
                          color: Colors.grey.shade400,
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                  ),
                  // Options
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        // Option 1: Select files to download
                        _buildDownloadOptionCard(
                          icon: Icons.checklist_rounded,
                          title: 'Select files to download',
                          description: 'Choose specific files from this torrent',
                          color: const Color(0xFF6366F1),
                          onTap: () {
                            Navigator.of(dialogContext).pop();
                            _downloadAllTorrentFiles(torrent);
                          },
                        ),
                        const SizedBox(height: 12),
                        // Option 2: Download whole torrent as ZIP
                        _buildDownloadOptionCard(
                          icon: Icons.folder_zip_rounded,
                          title: 'Download whole torrent as ZIP',
                          description: 'Download all files in a single ZIP archive',
                          color: const Color(0xFF10B981),
                          onTap: () {
                            _enqueueTorboxZipDownload(
                              torrent: torrent,
                              sheetContext: dialogContext,
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// Build a download option card for the dialog
  Widget _buildDownloadOptionCard({
    required IconData icon,
    required String title,
    required String description,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                color.withValues(alpha: 0.15),
                color.withValues(alpha: 0.05),
              ],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: color.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  color: color,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade400,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios_rounded,
                color: color.withValues(alpha: 0.5),
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTorboxRawList({
    required List<_TorboxFileEntry> entries,
    required Set<int> selectedIndices,
    required ValueChanged<int> onToggle,
    Future<void> Function(_TorboxFileEntry entry)? onCopy,
  }) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
      itemCount: entries.length,
      itemBuilder: (context, listIndex) {
        final entry = entries[listIndex];
        final isSelected = selectedIndices.contains(entry.index);
        final subtitle = entry.file.name != entry.file.shortName
            ? entry.file.name
            : entry.file.absolutePath;
        return Container(
          key: ValueKey('torbox-file-${entry.index}'),
          margin: const EdgeInsets.only(bottom: 12),
          child: _buildTorboxFileCard(
            entry: entry,
            isSelected: isSelected,
            onToggle: () => onToggle(entry.index),
            animationIndex: listIndex,
            subtitle: subtitle,
            onCopy: onCopy == null ? null : () => onCopy(entry),
          ),
        );
      },
    );
  }

  Widget _buildTorboxGenericList({
    required List<_TorboxFileEntry> entries,
    required Set<int> selectedIndices,
    required ValueChanged<int> onToggle,
    Future<void> Function(_TorboxFileEntry entry)? onCopy,
  }) {
    if (entries.isEmpty) {
      return _buildEmptyFilesState();
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
      children: [
        _buildSectionHeader('All Files'),
        const SizedBox(height: 12),
        for (int i = 0; i < entries.length; i++)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            child: _buildTorboxFileCard(
              entry: entries[i],
              isSelected: selectedIndices.contains(entries[i].index),
              onToggle: () => onToggle(entries[i].index),
              animationIndex: i,
              subtitle: entries[i].file.name != entries[i].file.shortName
                  ? entries[i].file.name
                  : entries[i].file.absolutePath,
              onCopy: onCopy == null ? null : () => onCopy(entries[i]),
            ),
          ),
      ],
    );
  }

  Widget _buildTorboxMovieView({
    required List<_TorboxFileEntry> entries,
    required Set<int> selectedIndices,
    required ValueChanged<int> onToggle,
    Future<void> Function(_TorboxFileEntry entry)? onCopy,
  }) {
    final mainEntries = <_TorboxFileEntry>[];
    final sampleEntries = <_TorboxFileEntry>[];
    final extraEntries = <_TorboxFileEntry>[];

    for (final entry in entries) {
      final fileNameLower = entry.file.shortName.toLowerCase();
      if (_torboxFileLooksLikeVideo(entry.file)) {
        if (fileNameLower.contains('sample')) {
          sampleEntries.add(entry);
        } else {
          mainEntries.add(entry);
        }
      } else {
        extraEntries.add(entry);
      }
    }

    if (mainEntries.isEmpty && sampleEntries.isEmpty && extraEntries.isEmpty) {
      return _buildEmptyFilesState();
    }

    Widget buildSection(
      String title,
      List<_TorboxFileEntry> sectionEntries, {
      String? badge,
    }) {
      if (sectionEntries.isEmpty) return const SizedBox.shrink();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(title),
          const SizedBox(height: 12),
          for (int i = 0; i < sectionEntries.length; i++)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              child: _buildTorboxFileCard(
                entry: sectionEntries[i],
                isSelected: selectedIndices.contains(sectionEntries[i].index),
                onToggle: () => onToggle(sectionEntries[i].index),
                animationIndex: i,
                badge: badge,
                subtitle:
                    sectionEntries[i].file.name !=
                        sectionEntries[i].file.shortName
                    ? sectionEntries[i].file.name
                    : null,
                onCopy: onCopy == null ? null : () => onCopy(sectionEntries[i]),
              ),
            ),
          const SizedBox(height: 16),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
      children: [
        buildSection('Main', mainEntries, badge: 'Main'),
        buildSection('Sample', sampleEntries, badge: 'Sample'),
        buildSection('Extras', extraEntries, badge: 'Extra'),
      ],
    );
  }

  Widget _buildTorboxSeriesView({
    required List<_TorboxFileEntry> entries,
    required Set<int> selectedIndices,
    required int? currentSeason,
    required ValueChanged<int?> onSeasonChange,
    required ValueChanged<int> onToggleFile,
    required void Function(int season, List<int> indices) onToggleSeason,
    Future<void> Function(_TorboxFileEntry entry)? onCopy,
  }) {
    final seasonMap = <int, List<_TorboxFileEntry>>{};
    final otherEntries = <_TorboxFileEntry>[];

    for (final entry in entries) {
      final info = entry.seriesInfo;
      if (info.isSeries && info.season != null && info.episode != null) {
        seasonMap.putIfAbsent(info.season!, () => []).add(entry);
      } else {
        otherEntries.add(entry);
      }
    }

    for (final seasonEntries in seasonMap.values) {
      seasonEntries.sort((a, b) {
        final epA = a.seriesInfo.episode ?? 0;
        final epB = b.seriesInfo.episode ?? 0;
        return epA.compareTo(epB);
      });
    }

    final sortedSeasons = seasonMap.keys.toList()..sort();

    if (currentSeason != null && !seasonMap.containsKey(currentSeason)) {
      onSeasonChange(null);
    }

    if (currentSeason == null) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
        children: [
          _buildSectionHeader('Seasons'),
          const SizedBox(height: 12),
          for (final seasonNumber in sortedSeasons)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF1E293B).withValues(alpha: 0.8),
                    const Color(0xFF111827).withValues(alpha: 0.6),
                  ],
                ),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: const Color(0xFF475569).withValues(alpha: 0.3),
                ),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () => onSeasonChange(seasonNumber),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 16,
                    ),
                    child: Row(
                      children: [
                        GestureDetector(
                          onTap: () {
                            onToggleSeason(
                              seasonNumber,
                              seasonMap[seasonNumber]!
                                  .map((entry) => entry.index)
                                  .toList(),
                            );
                          },
                          child: Container(
                            width: 26,
                            height: 26,
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981).withValues(
                                alpha:
                                    seasonMap[seasonNumber]!.every(
                                      (entry) =>
                                          selectedIndices.contains(entry.index),
                                    )
                                    ? 0.9
                                    : seasonMap[seasonNumber]!.any(
                                        (entry) => selectedIndices.contains(
                                          entry.index,
                                        ),
                                      )
                                    ? 0.4
                                    : 0,
                              ),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: const Color(0xFF10B981),
                                width: 2,
                              ),
                            ),
                            child:
                                seasonMap[seasonNumber]!.every(
                                  (entry) =>
                                      selectedIndices.contains(entry.index),
                                )
                                ? const Icon(
                                    Icons.check,
                                    color: Colors.white,
                                    size: 16,
                                  )
                                : seasonMap[seasonNumber]!.any(
                                    (entry) =>
                                        selectedIndices.contains(entry.index),
                                  )
                                ? const Icon(
                                    Icons.remove,
                                    color: Colors.white,
                                    size: 16,
                                  )
                                : null,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                            ),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Icon(
                            Icons.folder_rounded,
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Season $seasonNumber',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${seasonMap[seasonNumber]!.length} episodes',
                                style: TextStyle(
                                  color: Colors.grey[400],
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.arrow_forward_ios_rounded,
                          color: Colors.grey[500],
                          size: 16,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          if (otherEntries.isNotEmpty) ...[
            const SizedBox(height: 12),
            _buildSectionHeader('Extras'),
            const SizedBox(height: 12),
            for (int i = 0; i < otherEntries.length; i++)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                child: _buildTorboxFileCard(
                  entry: otherEntries[i],
                  isSelected: selectedIndices.contains(otherEntries[i].index),
                  onToggle: () => onToggleFile(otherEntries[i].index),
                  animationIndex: i,
                  subtitle: otherEntries[i].file.name,
                  badge: 'Extra',
                  onCopy: onCopy == null ? null : () => onCopy(otherEntries[i]),
                ),
              ),
          ],
        ],
      );
    }

    final chosenSeasonEntries = seasonMap[currentSeason] ?? [];

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
          child: Row(
            children: [
              TextButton.icon(
                onPressed: () => onSeasonChange(null),
                icon: const Icon(
                  Icons.arrow_back_rounded,
                  color: Color(0xFF6366F1),
                ),
                label: const Text(
                  'Back to seasons',
                  style: TextStyle(
                    color: Color(0xFF6366F1),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                'Season $currentSeason',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
            itemCount: chosenSeasonEntries.length,
            itemBuilder: (context, index) {
              final entry = chosenSeasonEntries[index];
              final info = entry.seriesInfo;
              final badge = info.episode != null
                  ? 'E${info.episode.toString().padLeft(2, '0')}'
                  : null;
              return Container(
                key: ValueKey('torbox-episode-${entry.index}'),
                margin: const EdgeInsets.only(bottom: 12),
                child: _buildTorboxFileCard(
                  entry: entry,
                  isSelected: selectedIndices.contains(entry.index),
                  onToggle: () => onToggleFile(entry.index),
                  animationIndex: index,
                  badge: badge,
                  onCopy: onCopy == null ? null : () => onCopy(entry),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildTorboxFileCard({
    required _TorboxFileEntry entry,
    required bool isSelected,
    required VoidCallback onToggle,
    required int animationIndex,
    String? badge,
    String? subtitle,
    Future<void> Function()? onCopy,
  }) {
    final file = entry.file;
    final fileName = file.shortName.isNotEmpty
        ? file.shortName
        : FileUtils.getFileName(file.name);
    final isVideo = _torboxFileLooksLikeVideo(file);
    final sizeText = Formatters.formatFileSize(file.size);

    final selectionColor = isSelected
        ? const Color(0xFF8B5CF6).withValues(alpha: 0.5)
        : const Color(0xFF475569).withValues(alpha: 0.3);

    return TweenAnimationBuilder<double>(
      duration: Duration(milliseconds: 250 + (animationIndex * 40)),
      tween: Tween(begin: 0.0, end: 1.0),
      builder: (context, value, child) {
        return Transform.translate(
          offset: Offset(0, 18 * (1 - value)),
          child: Opacity(opacity: value, child: child),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFF1E293B).withValues(alpha: 0.85),
              const Color(0xFF111827).withValues(alpha: 0.7),
            ],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selectionColor, width: isSelected ? 2 : 1),
          boxShadow: [
            BoxShadow(
              color: isSelected
                  ? const Color(0xFF8B5CF6).withValues(alpha: 0.2)
                  : Colors.black.withValues(alpha: 0.15),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
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
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    fileName,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  width: 24,
                                  height: 24,
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? const Color(
                                            0xFF8B5CF6,
                                          ).withValues(alpha: 0.9)
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: isSelected
                                          ? const Color(0xFF8B5CF6)
                                          : Colors.grey[600]!,
                                      width: 2,
                                    ),
                                  ),
                                  child: isSelected
                                      ? const Icon(
                                          Icons.check,
                                          size: 16,
                                          color: Colors.white,
                                        )
                                      : null,
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Text(
                                  sizeText,
                                  style: TextStyle(
                                    color: Colors.grey[300],
                                    fontSize: 12,
                                  ),
                                ),
                                if (badge != null) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(
                                        0xFF6366F1,
                                      ).withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: const Color(
                                          0xFF6366F1,
                                        ).withValues(alpha: 0.3),
                                      ),
                                    ),
                                    child: Text(
                                      badge,
                                      style: const TextStyle(
                                        color: Color(0xFF6366F1),
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            if (subtitle != null) ...[
                              const SizedBox(height: 8),
                              Text(
                                subtitle,
                                style: TextStyle(
                                  color: Colors.grey[400],
                                  fontSize: 12,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (onCopy != null) ...[
                    const SizedBox(height: 16),
                    Align(
                      alignment: Alignment.centerRight,
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          if (onCopy != null) {
                            await onCopy();
                          }
                        },
                        icon: const Icon(Icons.copy_rounded, size: 16),
                        label: const Text(
                          'Copy',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: BorderSide(
                            color: Colors.white.withValues(alpha: 0.25),
                          ),
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
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 14,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.2,
      ),
    );
  }

  Widget _buildEmptyFilesState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(
              Icons.folder_off_rounded,
              color: Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'No files available yet',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            'We could not find any files for this torrent.',
            style: TextStyle(color: Colors.grey[400], fontSize: 13),
          ),
        ],
      ),
    );
  }

  void _showComingSoon(String action) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$action support coming soon'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _showAddMagnetDialog() async {
    if (_apiKey == null || _apiKey!.isEmpty) {
      _showComingSoon('Add Torbox API key');
      return;
    }

    await _autoPasteMagnetLink();
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Add Magnet Link'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
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
                  controller: _magnetController,
                  maxLines: 3,
                  autofocus: true,
                  decoration: const InputDecoration(
                    hintText: 'Paste magnet link here…',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => _handleAddMagnet(dialogContext),
              child: const Text('Add'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _autoPasteMagnetLink() async {
    if (_magnetController.text.trim().isNotEmpty) return;
    final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
    final text = clipboardData?.text?.trim();
    if (text != null && text.startsWith('magnet:?')) {
      _magnetController.text = text;
    }
  }

  void _handleAddMagnet(BuildContext dialogContext) {
    final magnetLink = _magnetController.text.trim();
    if (magnetLink.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a magnet link.')),
      );
      return;
    }

    if (!_isValidMagnetLink(magnetLink)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid magnet link.')),
      );
      return;
    }

    Navigator.of(dialogContext).pop();
    _addMagnetToTorbox(magnetLink);
  }

  bool _isValidMagnetLink(String link) {
    final trimmed = link.trim();
    if (!trimmed.startsWith('magnet:?')) return false;
    if (!trimmed.toLowerCase().contains('xt=urn:btih:')) return false;
    return trimmed.length >= 50;
  }

  Future<void> _addMagnetToTorbox(String magnetLink) async {
    final apiKey = _apiKey;
    if (apiKey == null || apiKey.isEmpty) {
      _showComingSoon('Add Torbox API key');
      return;
    }

    final navigator = Navigator.of(context, rootNavigator: true);
    var dialogClosed = false;

    void closeDialogIfOpen() {
      if (!dialogClosed && navigator.canPop()) {
        navigator.pop();
        dialogClosed = true;
      }
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        return const AlertDialog(
          title: Text('Adding torrent'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Submitting magnet to Torbox…'),
            ],
          ),
        );
      },
    );

    try {
      final response = await TorboxService.createTorrent(
        apiKey: apiKey,
        magnet: magnetLink,
        seed: true,
        allowZip: true,
        addOnlyIfCached: true,
      );

      if (!mounted) return;

      closeDialogIfOpen();

      final success = response['success'] as bool? ?? false;
      if (!success) {
        final errorMessage = (response['error'] ?? 'Failed to add magnet')
            .toString();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: const Color(0xFFB91C1C),
          ),
        );
        return;
      }

      _magnetController.clear();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Magnet added to Torbox.')));

      await _refresh();
    } catch (e) {
      if (!mounted) return;
      closeDialogIfOpen();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Failed to add magnet: ${e.toString().replaceFirst('Exception: ', '')}',
          ),
          backgroundColor: const Color(0xFFB91C1C),
        ),
      );
    }
  }

  void _openSettings() {
    MainPageBridge.switchTab?.call(6);
  }

  // ==================== FILE/FOLDER ACTION METHODS ====================

  /// Get files list from current torrent or web download
  List<TorboxFile> get _currentFiles {
    return _currentTorrent?.files ?? _currentWebDownload?.files ?? [];
  }

  /// Play all videos in a folder
  Future<void> _playFolderVideos(RDFileNode folderNode) async {
    if (_currentTorrent == null && _currentWebDownload == null) return;

    final files = _currentFiles;
    final videoFiles = TorboxFolderTreeBuilder.collectVideoFiles(folderNode);
    if (videoFiles.isEmpty) {
      _showSnackBar('No video files found in this folder');
      return;
    }

    // Convert RDFileNodes to TorboxFiles for playback
    final torboxFiles = videoFiles
        .map((node) {
          // Find corresponding TorboxFile by linkIndex
          if (node.linkIndex >= 0 && node.linkIndex < files.length) {
            return files[node.linkIndex];
          }
          return null;
        })
        .where((f) => f != null)
        .cast<TorboxFile>()
        .toList();

    if (torboxFiles.isEmpty) {
      _showSnackBar('Could not load video files');
      return;
    }

    // Use existing play logic
    await _playTorboxFiles(torboxFiles, folderNode.name);
  }

  /// Play a single video file
  Future<void> _playVideoFile(RDFileNode fileNode) async {
    if ((_currentTorrent == null && _currentWebDownload == null) || fileNode.isFolder) return;

    final files = _currentFiles;
    // Find corresponding TorboxFile
    if (fileNode.linkIndex < 0 || fileNode.linkIndex >= files.length) {
      _showSnackBar('File not found');
      return;
    }

    final torboxFile = files[fileNode.linkIndex];

    try {
      final key = _apiKey;
      if (key == null || key.isEmpty) {
        _showSnackBar('Torbox API key not configured');
        return;
      }

      String streamUrl;
      if (_currentTorrent != null) {
        streamUrl = await _requestTorboxStreamUrl(
          apiKey: key,
          torrent: _currentTorrent!,
          file: torboxFile,
        );
      } else {
        streamUrl = await TorboxService.requestWebDownloadFileLink(
          apiKey: key,
          webId: _currentWebDownload!.id,
          fileId: torboxFile.id,
        );
      }

      if (!mounted) return;

      await VideoPlayerLauncher.push(
        context,
        VideoPlayerLaunchArgs(
          videoUrl: streamUrl,
          title: fileNode.name,
          subtitle: Formatters.formatFileSize(fileNode.bytes ?? 0),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('Failed to play file: ${_formatTorboxError(e)}');
    }
  }

  /// Download a file or folder
  Future<void> _downloadFileOrFolder(RDFileNode node) async {
    if (_currentTorrent == null && _currentWebDownload == null) {
      print('❌ Download: No current torrent or web download');
      return;
    }

    final files = _currentFiles;
    print('📥 Download requested: isFolder=${node.isFolder}, name=${node.name}');
    print('   Node details: fileId=${node.fileId}, linkIndex=${node.linkIndex}, bytes=${node.bytes}');
    print('   Current files count: ${files.length}');

    if (node.isFolder) {
      // Show file selection dialog for folder
      final allFiles = TorboxFolderTreeBuilder.collectAllFiles(node);
      print('   Collected ${allFiles.length} files from folder');

      final torboxFiles = allFiles
          .map((n) {
            print('   Mapping file: name=${n.name}, linkIndex=${n.linkIndex}, fileId=${n.fileId}');
            if (n.linkIndex >= 0 && n.linkIndex < files.length) {
              final torboxFile = files[n.linkIndex];
              print('   ✅ Mapped to TorboxFile: id=${torboxFile.id}, name=${torboxFile.name}');
              return torboxFile;
            }
            print('   ❌ linkIndex out of bounds: ${n.linkIndex} >= ${files.length}');
            return null;
          })
          .where((f) => f != null)
          .cast<TorboxFile>()
          .toList();

      print('   Mapped to ${torboxFiles.length} TorboxFiles');

      if (torboxFiles.isEmpty) {
        _showSnackBar('No files found in folder');
        return;
      }

      // Format files for FileSelectionDialog
      final formattedFiles = <Map<String, dynamic>>[];
      for (final file in torboxFiles) {
        // Use shortName for file name, fullName for path structure
        final fullPath = file.name; // Full path with folders
        final relativePath = fullPath.contains('/')
            ? fullPath.substring(fullPath.indexOf('/') + 1)
            : fullPath;

        formattedFiles.add({
          '_fullPath': relativePath,
          'name': file.shortName.isNotEmpty ? file.shortName : FileUtils.getFileName(file.name),
          'size': file.size.toString(),
          '_torboxFile': file, // Store original TorboxFile for download
        });
      }

      // Show file selection dialog
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (BuildContext context) {
          return FileSelectionDialog(
            files: formattedFiles,
            torrentName: node.name,
            onDownload: (selectedFiles) {
              if (selectedFiles.isEmpty) return;
              _downloadSelectedTorboxFiles(selectedFiles, node.name);
            },
          );
        },
      );
    } else {
      // Download single file
      print('   Attempting single file download');
      print('   Bounds check: ${node.linkIndex} >= 0 && ${node.linkIndex} < ${files.length}');

      if (node.linkIndex >= 0 && node.linkIndex < files.length) {
        final torboxFile = files[node.linkIndex];
        print('   ✅ Found TorboxFile at index ${node.linkIndex}:');
        print('      TorboxFile.id=${torboxFile.id}, name=${torboxFile.name}');
        print('      Node.fileId=${node.fileId}');
        print('      IDs match: ${torboxFile.id == node.fileId}');
        await _downloadSingleFile(torboxFile);
      } else {
        print('   ❌ linkIndex out of bounds! linkIndex=${node.linkIndex}, filesLength=${files.length}');
        _showSnackBar('Download failed: File index out of bounds');
      }
    }
  }

  /// Download selected Torbox files from file selection dialog
  Future<void> _downloadSelectedTorboxFiles(
    List<Map<String, dynamic>> selectedFiles,
    String folderName,
  ) async {
    final key = _apiKey;
    if (key == null || key.isEmpty || (_currentTorrent == null && _currentWebDownload == null)) {
      print('❌ _downloadSelectedTorboxFiles: Missing requirements');
      return;
    }

    // CRITICAL: Capture reference before async operations
    final torrent = _currentTorrent;
    final webDownload = _currentWebDownload;
    final isWebDownload = webDownload != null;

    if (!mounted) return;

    print('📦 _downloadSelectedTorboxFiles called: folderName=$folderName, selectedCount=${selectedFiles.length}');

    try {
      // Show progress dialog
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

      int successCount = 0;
      int failCount = 0;

      // CRITICAL: Following the SAME pattern as Real-Debrid
      // We DON'T request download URLs upfront - we queue with metadata for lazy fetching
      // The DownloadService will request the URL when it's ready to download (lazy loading)
      for (final fileData in selectedFiles) {
        try {
          // Extract TorboxFile from the formatted data
          final file = fileData['_torboxFile'] as TorboxFile;
          final fileName = (fileData['_fullPath'] as String?) ?? (fileData['name'] as String? ?? file.shortName);

          print('   Processing file: ${file.name}');

          // Pass metadata for lazy URL fetching (no API call - instant!)
          // The download service will request the URL when ready
          final Map<String, dynamic> metaMap;
          if (isWebDownload) {
            metaMap = {
              'torboxWebDownloadId': webDownload.id,
              'torboxFileId': file.id,
              'apiKey': key,
              'torboxWebDownload': true,
            };
          } else {
            metaMap = {
              'torboxTorrentId': torrent!.id,
              'torboxFileId': file.id,
              'apiKey': key,
              'torboxDownload': true,
            };
          }
          final meta = jsonEncode(metaMap);

          // Queue download instantly (download service will fetch URL when ready)
          await DownloadService.instance.enqueueDownload(
            url: '', // Empty URL - will be fetched by download service
            fileName: fileName,
            meta: meta,
            torrentName: folderName,
            context: mounted ? context : null,
          );

          print('     ✅ Enqueued successfully');
          successCount++;
        } catch (e) {
          print('     ❌ Error: $e');
          failCount++;
        }
      }

      // Close progress dialog
      if (mounted) Navigator.of(context).pop();

      // Show result
      if (successCount > 0 && failCount == 0) {
        _showSnackBar(
          'Queued $successCount file${successCount == 1 ? '' : 's'} for download',
          isError: false,
        );
      } else if (successCount > 0 && failCount > 0) {
        _showSnackBar(
          'Queued $successCount file${successCount == 1 ? '' : 's'}, $failCount failed',
        );
      } else {
        _showSnackBar('Failed to queue any files for download');
      }
    } catch (e) {
      // Close any open dialogs
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      _showSnackBar('Failed to queue downloads: $e');
    }
  }

  /// Add file or folder to playlist
  Future<void> _addFileOrFolderToPlaylist(RDFileNode node) async {
    if (_currentTorrent == null && _currentWebDownload == null) return;

    final files = _currentFiles;
    final isWebDownload = _currentWebDownload != null;

    if (node.isFolder) {
      // Add all video files in folder
      final videoFiles = TorboxFolderTreeBuilder.collectVideoFiles(node);
      final torboxFiles = videoFiles
          .map((n) {
            if (n.linkIndex >= 0 && n.linkIndex < files.length) {
              return files[n.linkIndex];
            }
            return null;
          })
          .where((f) => f != null)
          .cast<TorboxFile>()
          .toList();

      if (torboxFiles.isEmpty) {
        _showSnackBar('No video files found in folder');
        return;
      }

      // Add as collection
      final ids = torboxFiles.map((f) => f.id).toList();
      final Map<String, dynamic> playlistData;
      if (isWebDownload) {
        playlistData = {
          'provider': 'torbox_webdl',
          'title': FileUtils.cleanPlaylistTitle(node.name),
          'kind': 'collection',
          'torboxWebDownloadId': _currentWebDownload!.id,
          'torboxFileIds': ids,
          'webdl_hash': _currentWebDownload!.hash,
          'count': torboxFiles.length,
        };
      } else {
        playlistData = {
          'provider': 'torbox',
          'title': FileUtils.cleanPlaylistTitle(node.name),
          'kind': 'collection',
          'torboxTorrentId': _currentTorrent!.id,
          'torboxFileIds': ids,
          'torrent_hash': _currentTorrent!.hash,
          'count': torboxFiles.length,
        };
      }
      final added = await StorageService.addPlaylistItemRaw(playlistData);

      _showSnackBar(
        added ? 'Added ${torboxFiles.length} videos to playlist' : 'Already in playlist',
        isError: !added,
      );
    } else {
      // Add single file
      if (node.linkIndex >= 0 && node.linkIndex < files.length) {
        final torboxFile = files[node.linkIndex];
        final Map<String, dynamic> playlistData;
        if (isWebDownload) {
          playlistData = {
            'provider': 'torbox_webdl',
            'title': FileUtils.cleanPlaylistTitle(node.name),
            'kind': 'single',
            'torboxWebDownloadId': _currentWebDownload!.id,
            'torboxFileId': torboxFile.id,
            'webdl_hash': _currentWebDownload!.hash,
            'sizeBytes': torboxFile.size,
          };
        } else {
          playlistData = {
            'provider': 'torbox',
            'title': FileUtils.cleanPlaylistTitle(node.name),
            'kind': 'single',
            'torboxTorrentId': _currentTorrent!.id,
            'torboxFileId': torboxFile.id,
            'torrent_hash': _currentTorrent!.hash,
            'sizeBytes': torboxFile.size,
          };
        }
        final added = await StorageService.addPlaylistItemRaw(playlistData);

        _showSnackBar(
          added ? 'Added to playlist' : 'Already in playlist',
          isError: !added,
        );
      }
    }
  }

  /// Copy file download link
  Future<void> _copyFileLink(RDFileNode node) async {
    if ((_currentTorrent == null && _currentWebDownload == null) || node.isFolder) return;

    final files = _currentFiles;
    if (node.linkIndex >= 0 && node.linkIndex < files.length) {
      final torboxFile = files[node.linkIndex];
      if (_currentTorrent != null) {
        await _copyTorboxFileLink(_currentTorrent!, torboxFile);
      } else if (_currentWebDownload != null) {
        await _copyWebDownloadFileLink(_currentWebDownload!, torboxFile);
      }
    }
  }

  /// Copy web download file link
  Future<void> _copyWebDownloadFileLink(TorboxWebDownload webDownload, TorboxFile file) async {
    final key = _apiKey;
    if (key == null || key.isEmpty) {
      _showSnackBar('Torbox API key not configured');
      return;
    }

    try {
      final link = await TorboxService.requestWebDownloadFileLink(
        apiKey: key,
        webId: webDownload.id,
        fileId: file.id,
      );
      await Clipboard.setData(ClipboardData(text: link));
      if (!mounted) return;
      _showSnackBar('Download link copied to clipboard.', isError: false);
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('Failed to copy link: ${_formatTorboxError(e)}');
    }
  }

  /// Open file with external player
  Future<void> _openWithExternalPlayer(RDFileNode node) async {
    if ((_currentTorrent == null && _currentWebDownload == null) || node.isFolder) return;

    final key = _apiKey;
    if (key == null || key.isEmpty) {
      _showSnackBar('Torbox API key not configured');
      return;
    }

    final files = _currentFiles;
    if (node.linkIndex >= 0 && node.linkIndex < files.length) {
      final torboxFile = files[node.linkIndex];

      try {
        // Show loading
        if (!mounted) return;
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const Center(child: CircularProgressIndicator()),
        );

        String downloadUrl;
        if (_currentTorrent != null) {
          downloadUrl = await TorboxService.requestFileDownloadLink(
            apiKey: key,
            torrentId: _currentTorrent!.id,
            fileId: torboxFile.id,
          );
        } else {
          downloadUrl = await TorboxService.requestWebDownloadFileLink(
            apiKey: key,
            webId: _currentWebDownload!.id,
            fileId: torboxFile.id,
          );
        }

        if (!mounted) return;
        Navigator.of(context).pop(); // Close loading

        // Launch with external player
        if (Platform.isAndroid) {
          // On Android, use intent with video MIME type to show video player chooser
          final intent = AndroidIntent(
            action: 'action_view',
            data: downloadUrl,
            type: 'video/*',
          );
          await intent.launch();
          _showSnackBar('Opening with external player...', isError: false);
        } else {
          // On other platforms, use url_launcher
          final Uri uri = Uri.parse(downloadUrl);
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalNonBrowserApplication);
            _showSnackBar('Opening with external player...', isError: false);
          } else {
            _showSnackBar('Could not open external player');
          }
        }
      } catch (e) {
        if (!mounted) return;
        Navigator.of(context).pop(); // Close loading if still open
        _showSnackBar('Failed to open: ${_formatTorboxError(e)}');
      }
    }
  }

  /// Helper: Download a single file
  Future<void> _downloadSingleFile(TorboxFile file) async {
    final key = _apiKey;
    if (key == null || key.isEmpty || (_currentTorrent == null && _currentWebDownload == null)) {
      print('❌ _downloadSingleFile: Missing requirements');
      return;
    }

    final isWebDownload = _currentWebDownload != null;
    print('🔽 _downloadSingleFile called:');
    print('   File: id=${file.id}, name=${file.name}, shortName=${file.shortName}');
    print('   isWebDownload: $isWebDownload');
    print('   API Key: ${key.substring(0, 8)}...');

    try {
      final fileName = file.shortName.isNotEmpty
          ? file.shortName
          : FileUtils.getFileName(file.name);

      print('   Using fileName: $fileName');

      // Pass metadata for lazy URL fetching (download service will fetch URL when ready)
      final Map<String, dynamic> metaMap;
      if (isWebDownload) {
        metaMap = {
          'torboxWebDownloadId': _currentWebDownload!.id,
          'torboxFileId': file.id,
          'apiKey': key,
          'torboxWebDownload': true,
        };
      } else {
        metaMap = {
          'torboxTorrentId': _currentTorrent!.id,
          'torboxFileId': file.id,
          'apiKey': key,
          'torboxDownload': true,
        };
      }
      final meta = jsonEncode(metaMap);

      print('   📥 Enqueueing download with DownloadService (lazy URL fetching)...');
      await DownloadService.instance.enqueueDownload(
        url: '', // Empty URL - will be fetched by download service
        fileName: fileName,
        meta: meta,
        context: mounted ? context : null,
      );

      print('   ✅ Download queued successfully!');
      _showSnackBar('Download queued: $fileName', isError: false);
    } catch (e, stackTrace) {
      print('   ❌ Error in _downloadSingleFile:');
      print('   Error: $e');
      print('   StackTrace: $stackTrace');
      _showSnackBar('Failed to queue download: ${_formatTorboxError(e)}');
    }
  }

  /// Helper: Download multiple files
  Future<void> _downloadMultipleFiles(List<TorboxFile> files, String folderName) async {
    final key = _apiKey;
    if (key == null || key.isEmpty || (_currentTorrent == null && _currentWebDownload == null)) {
      print('❌ _downloadMultipleFiles: Missing requirements');
      return;
    }

    print('📦 _downloadMultipleFiles called: folderName=$folderName, fileCount=${files.length}');

    if (files.isEmpty) {
      print('   ❌ No files to download (empty list)');
      _showSnackBar('No files to download');
      return;
    }

    // Show confirmation
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Download Files'),
        content: Text('Download ${files.length} file${files.length == 1 ? '' : 's'} from "$folderName"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Download'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) {
      print('   User cancelled or context not mounted');
      return;
    }

    print('   User confirmed download, processing ${files.length} files...');

    final isWebDownload = _currentWebDownload != null;
    int successCount = 0;
    int failCount = 0;

    // CRITICAL: Following the SAME pattern as Real-Debrid
    // We DON'T request download URLs upfront - we queue with metadata for lazy fetching
    // The DownloadService will request the URL when it's ready to download (lazy loading)
    for (final file in files) {
      print('   Processing file ${successCount + failCount + 1}/${files.length}: ${file.name}');
      try {
        final fileName = file.shortName.isNotEmpty
            ? file.shortName
            : FileUtils.getFileName(file.name);

        // Pass metadata for lazy URL fetching (no API call - instant!)
        // The download service will request the URL when ready
        final Map<String, dynamic> metaMap;
        if (isWebDownload) {
          metaMap = {
            'torboxWebDownloadId': _currentWebDownload!.id,
            'torboxFileId': file.id,
            'apiKey': key,
            'torboxWebDownload': true,
          };
        } else {
          metaMap = {
            'torboxTorrentId': _currentTorrent!.id,
            'torboxFileId': file.id,
            'apiKey': key,
            'torboxDownload': true,
          };
        }
        final meta = jsonEncode(metaMap);

        // Queue download instantly (download service will fetch URL when ready)
        await DownloadService.instance.enqueueDownload(
          url: '', // Empty URL - will be fetched by download service
          fileName: fileName,
          meta: meta,
          torrentName: folderName,
          context: mounted ? context : null,
        );

        print('     ✅ Enqueued successfully');
        successCount++;
      } catch (e) {
        print('     ❌ Error: $e');
        failCount++;
      }
    }

    // Show result
    if (successCount > 0 && failCount == 0) {
      _showSnackBar(
        'Queued $successCount file${successCount == 1 ? '' : 's'} for download',
        isError: false,
      );
    } else if (successCount > 0 && failCount > 0) {
      _showSnackBar(
        'Queued $successCount file${successCount == 1 ? '' : 's'}, $failCount failed',
      );
    } else {
      _showSnackBar('Failed to queue any files for download');
    }
  }

  /// Helper: Play torbox files (reuse existing logic)
  Future<void> _playTorboxFiles(List<TorboxFile> files, String collectionName) async {
    // This will reuse the existing _handlePlayTorrent logic
    // but with just the files subset
    final key = _apiKey;
    if (key == null || key.isEmpty || (_currentTorrent == null && _currentWebDownload == null)) return;

    final videoFiles = files.where((file) {
      if (file.zipped) return false;
      return _torboxFileLooksLikeVideo(file);
    }).toList();

    if (videoFiles.isEmpty) {
      _showSnackBar('No playable video files found');
      return;
    }

    if (videoFiles.length == 1) {
      final file = videoFiles.first;
      try {
        String streamUrl;
        if (_currentWebDownload != null) {
          streamUrl = await TorboxService.requestWebDownloadFileLink(
            apiKey: key,
            webId: _currentWebDownload!.id,
            fileId: file.id,
          );
        } else {
          streamUrl = await _requestTorboxStreamUrl(
            apiKey: key,
            torrent: _currentTorrent!,
            file: file,
          );
        }
        if (!mounted) return;
        await VideoPlayerLauncher.push(
          context,
          VideoPlayerLaunchArgs(
            videoUrl: streamUrl,
            title: collectionName,
            subtitle: Formatters.formatFileSize(file.size),
          ),
        );
      } catch (e) {
        if (!mounted) return;
        _showSnackBar('Failed to play file: ${_formatTorboxError(e)}');
      }
      return;
    }

    // Multiple videos - build playlist (reuse existing logic from _handlePlayTorrent)
    final candidates = videoFiles.map((file) {
      final displayName = _torboxDisplayName(file);
      final info = SeriesParser.parseFilename(displayName);
      return _TorboxEpisodeCandidate(
        file: file,
        displayName: displayName,
        info: info,
      );
    }).toList();

    final filenames = candidates.map((entry) => entry.displayName).toList();
    final bool isSeriesCollection =
        candidates.length > 1 && SeriesParser.isSeriesPlaylist(filenames);

    final sortedCandidates = [...candidates];
    sortedCandidates.sort((a, b) {
      final aInfo = a.info;
      final bInfo = b.info;

      final aIsSeries =
          aInfo.isSeries && aInfo.season != null && aInfo.episode != null;
      final bIsSeries =
          bInfo.isSeries && bInfo.season != null && bInfo.episode != null;

      if (aIsSeries && bIsSeries) {
        final seasonCompare = (aInfo.season ?? 0).compareTo(bInfo.season ?? 0);
        if (seasonCompare != 0) return seasonCompare;

        final episodeCompare = (aInfo.episode ?? 0).compareTo(bInfo.episode ?? 0);
        if (episodeCompare != 0) return episodeCompare;
      } else if (aIsSeries != bIsSeries) {
        return aIsSeries ? -1 : 1;
      }

      final aName = a.displayName.toLowerCase();
      final bName = b.displayName.toLowerCase();
      return aName.compareTo(bName);
    });

    int startIndex = 0;
    if (isSeriesCollection) {
      startIndex = sortedCandidates.indexWhere(
        (candidate) =>
            candidate.info.isSeries &&
            candidate.info.season != null &&
            candidate.info.episode != null,
      );
      if (startIndex == -1) {
        startIndex = 0;
      }
    }

    String initialUrl = '';
    try {
      if (_currentWebDownload != null) {
        initialUrl = await TorboxService.requestWebDownloadFileLink(
          apiKey: key,
          webId: _currentWebDownload!.id,
          fileId: sortedCandidates[startIndex].file.id,
        );
      } else {
        initialUrl = await _requestTorboxStreamUrl(
          apiKey: key,
          torrent: _currentTorrent!,
          file: sortedCandidates[startIndex].file,
        );
      }
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('Failed to prepare stream: ${_formatTorboxError(e)}');
      return;
    }

    final playlistEntries = <PlaylistEntry>[];
    for (int i = 0; i < sortedCandidates.length; i++) {
      final candidate = sortedCandidates[i];
      final info = candidate.info;
      final displayName = candidate.displayName;
      final episodeLabel = _formatTorboxPlaylistTitle(
        info: info,
        fallback: displayName,
        isSeriesCollection: isSeriesCollection,
      );
      final combinedTitle = _composeTorboxEntryTitle(
        seriesTitle: info.title,
        episodeLabel: episodeLabel,
        isSeriesCollection: isSeriesCollection,
        fallback: displayName,
      );

      // Strip first folder level (torrent name) from path
      String relativePath = candidate.file.name;
      final firstSlash = relativePath.indexOf('/');
      if (firstSlash > 0) {
        relativePath = relativePath.substring(firstSlash + 1);
      }

      playlistEntries.add(
        PlaylistEntry(
          url: i == startIndex ? initialUrl : '',
          title: combinedTitle,
          relativePath: relativePath, // Now excludes torrent/web download name folder
          provider: 'torbox',
          torboxTorrentId: _currentTorrent?.id,
          torboxWebDownloadId: _currentWebDownload?.id,
          torboxFileId: candidate.file.id,
          sizeBytes: candidate.file.size,
          torrentHash: _currentTorrent?.hash.isNotEmpty == true ? _currentTorrent!.hash : null,
        ),
      );
    }

    final totalBytes = sortedCandidates.fold<int>(
      0,
      (sum, entry) => sum + entry.file.size,
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

  /// Helper: Show snackbar
  void _showSnackBar(String message, {bool isError = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? const Color(0xFFEF4444) : null,
      ),
    );
  }

  // ==================== FOLDER NAVIGATION METHODS ====================

  /// Navigate into a torrent (show its folder structure)
  void _navigateIntoTorrent(TorboxTorrent torrent) {
    print('🔍 Navigating into torrent: id=${torrent.id}, name=${torrent.name}');
    print('   Files count: ${torrent.files.length}');
    print('   Sample files:');
    for (int i = 0; i < (torrent.files.length < 5 ? torrent.files.length : 5); i++) {
      print('     [$i] id=${torrent.files[i].id}, name=${torrent.files[i].name}');
    }

    // Build folder tree for this torrent
    print('   Building folder tree...');
    final tree = TorboxFolderTreeBuilder.buildTree(torrent.files);
    print('   Tree built: root has ${tree.children.length} children');

    // Initialize view mode for this torrent if not already set
    _torrentViewModes.putIfAbsent(torrent.id, () => _FolderViewMode.raw);

    // Apply view mode transformation to root nodes
    final mode = _torrentViewModes[torrent.id]!;
    List<RDFileNode> transformedNodes;
    switch (mode) {
      case _FolderViewMode.raw:
        transformedNodes = tree.children;
        break;
      case _FolderViewMode.sortedAZ:
        transformedNodes = _applySortedView(tree.children);
        break;
      case _FolderViewMode.seriesArrange:
        transformedNodes = _applySeriesArrangedView(tree.children);
        break;
    }

    setState(() {
      // Push current state to navigation stack
      _navigationStack.add((
        torrent: _currentTorrent,
        webDownload: _currentWebDownload,
        path: List.from(_currentPath),
        node: _currentFolderNode,
      ));

      // Navigate to torrent root
      _currentTorrent = torrent;
      _currentWebDownload = null;
      _currentPath = [];
      _currentFolderNode = tree;
      _currentViewNodes = transformedNodes;
    });
  }

  /// Navigate into a web download (show its folder structure)
  void _navigateIntoWebDownload(TorboxWebDownload webDownload) {
    // Build folder tree for this web download
    final tree = TorboxFolderTreeBuilder.buildTree(webDownload.files);

    // Initialize view mode for this web download if not already set
    _webDownloadViewModes.putIfAbsent(webDownload.id, () => _FolderViewMode.raw);

    // Apply view mode transformation to root nodes
    final mode = _webDownloadViewModes[webDownload.id]!;
    List<RDFileNode> transformedNodes;
    switch (mode) {
      case _FolderViewMode.raw:
        transformedNodes = tree.children;
        break;
      case _FolderViewMode.sortedAZ:
        transformedNodes = _applySortedView(tree.children);
        break;
      case _FolderViewMode.seriesArrange:
        transformedNodes = _applySeriesArrangedView(tree.children);
        break;
    }

    setState(() {
      // Push current state to navigation stack
      _navigationStack.add((
        torrent: _currentTorrent,
        webDownload: _currentWebDownload,
        path: List.from(_currentPath),
        node: _currentFolderNode,
      ));

      // Navigate to web download root
      _currentTorrent = null;
      _currentWebDownload = webDownload;
      _currentPath = [];
      _currentFolderNode = tree;
      _currentViewNodes = transformedNodes;
    });
  }

  /// Navigate into a subfolder within current torrent/web download
  void _navigateIntoFolder(RDFileNode folderNode) {
    if (!folderNode.isFolder) return;

    // Apply view mode to folder children
    // NOTE: Series Arrange only makes sense at root level (it creates virtual Season folders)
    // When inside any folder, show files in sorted or raw view
    final mode = _getCurrentViewMode();
    List<RDFileNode> transformedChildren;

    switch (mode) {
      case _FolderViewMode.raw:
        transformedChildren = folderNode.children;
        break;
      case _FolderViewMode.sortedAZ:
        transformedChildren = _applySortedView(folderNode.children);
        break;
      case _FolderViewMode.seriesArrange:
        // Inside a folder with Series Arrange mode: show files sorted by name
        transformedChildren = _applySortedView(folderNode.children);
        break;
    }

    setState(() {
      // Push current state to navigation stack
      _navigationStack.add((
        torrent: _currentTorrent,
        webDownload: _currentWebDownload,
        path: List.from(_currentPath),
        node: _currentFolderNode,
      ));

      // Navigate into folder
      _currentPath.add(folderNode.name);
      _currentFolderNode = folderNode;
      _currentViewNodes = transformedChildren;
    });
  }

  /// Navigate up one level (back button)
  void _navigateUp() {
    if (_navigationStack.isEmpty) return;

    final previous = _navigationStack.removeLast();

    // Reapply view mode transformation after navigation
    List<RDFileNode>? transformedNodes;
    if (previous.node != null && (previous.torrent != null || previous.webDownload != null)) {
      _FolderViewMode mode;
      if (previous.torrent != null) {
        mode = _torrentViewModes[previous.torrent!.id] ?? _FolderViewMode.raw;
      } else {
        mode = _webDownloadViewModes[previous.webDownload!.id] ?? _FolderViewMode.raw;
      }
      final rawNodes = previous.node!.children;

      // Apply view mode transformation
      // NOTE: Series Arrange only applies at root level
      if (mode == _FolderViewMode.seriesArrange && previous.path.isNotEmpty) {
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
    }

    setState(() {
      _currentTorrent = previous.torrent;
      _currentWebDownload = previous.webDownload;
      _currentPath = previous.path;
      _currentFolderNode = previous.node;
      _currentViewNodes = transformedNodes;
    });
  }

  /// Check if we're at root level (torrent/web download list)
  bool get _isAtRoot => _currentTorrent == null && _currentWebDownload == null;

  /// Get current folder/torrent/web download name for display
  String get _currentFolderName {
    if (_isAtRoot) return 'Torbox Files';
    if (_currentPath.isEmpty) {
      return _currentTorrent?.name ?? _currentWebDownload?.name ?? 'Download';
    }
    return _currentPath.last;
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

  /// Get current view mode for active torrent/web download
  _FolderViewMode _getCurrentViewMode() {
    if (_currentTorrent != null) {
      return _torrentViewModes[_currentTorrent!.id] ?? _FolderViewMode.raw;
    }
    if (_currentWebDownload != null) {
      return _webDownloadViewModes[_currentWebDownload!.id] ?? _FolderViewMode.raw;
    }
    return _FolderViewMode.raw;
  }

  /// Set view mode and refresh display
  void _setViewMode(_FolderViewMode mode) {
    if ((_currentTorrent == null && _currentWebDownload == null) || _currentFolderNode == null) return;

    // Get raw nodes based on current path
    // Always rebuild tree from scratch to handle virtual folders
    final files = _currentTorrent?.files ?? _currentWebDownload?.files ?? [];
    final tree = TorboxFolderTreeBuilder.buildTree(files);
    List<RDFileNode> rawNodes;

    if (_currentPath.isEmpty) {
      // At torrent/web download root
      rawNodes = tree.children;
    } else {
      // Navigate to current path to get raw nodes
      RDFileNode currentNode = tree;
      bool pathValid = true;

      for (final folderName in _currentPath) {
        final childFolder = currentNode.children.cast<RDFileNode?>().firstWhere(
          (node) => node?.name == folderName && node?.isFolder == true,
          orElse: () => null,
        );
        if (childFolder != null) {
          currentNode = childFolder;
        } else {
          // Path not found in raw tree (likely inside virtual folder)
          // Fall back to root level
          pathValid = false;
          break;
        }
      }

      if (pathValid) {
        // Successfully navigated to the path
        rawNodes = currentNode.children;
      } else {
        // Path invalid (e.g., inside virtual Season folder) - reset to root
        rawNodes = tree.children;
        _currentPath.clear();
        _currentFolderNode = tree;
      }
    }

    // If user selected Series Arrange, detect if content is actually a series
    if (mode == _FolderViewMode.seriesArrange) {
      final isSeries = _detectSeriesPattern(rawNodes);

      if (!isSeries) {
        // Not a series - show snackbar and fallback to sorted view
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No series detected in this folder. Switching to Sort (A-Z) view.'),
            duration: Duration(seconds: 3),
            backgroundColor: Color(0xFF1E293B),
            behavior: SnackBarBehavior.floating,
          ),
        );

        // Switch to sorted view instead
        setState(() {
          if (_currentTorrent != null) {
            _torrentViewModes[_currentTorrent!.id] = _FolderViewMode.sortedAZ;
          } else if (_currentWebDownload != null) {
            _webDownloadViewModes[_currentWebDownload!.id] = _FolderViewMode.sortedAZ;
          }
          _currentViewNodes = _applySortedView(rawNodes);
        });
        return;
      }
    }

    // Apply transformation based on mode
    setState(() {
      if (_currentTorrent != null) {
        _torrentViewModes[_currentTorrent!.id] = mode;
      } else if (_currentWebDownload != null) {
        _webDownloadViewModes[_currentWebDownload!.id] = mode;
      }

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
        ],
        onChanged: (value) {
          if (value != null) _setViewMode(value);
        },
      ),
    );
  }

  // ============ Search Methods ============

  /// Toggle search mode on/off
  void _toggleSearch() {
    setState(() {
      _isSearchActive = !_isSearchActive;
      if (!_isSearchActive) {
        _searchController.clear();
        _searchResults.clear();
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _searchFocusNode.requestFocus();
        });
      }
    });
  }

  /// Perform deep search across all files in current torrent
  void _performSearch(String query) {
    // Get root folder node from navigation stack
    if (_navigationStack.isEmpty || query.isEmpty) {
      setState(() => _searchResults = []);
      return;
    }

    final rootEntry = _navigationStack.first;
    final rootNode = rootEntry.node;
    if (rootNode == null) {
      setState(() => _searchResults = []);
      return;
    }

    final lowerQuery = query.toLowerCase();
    final results = <_TorboxSearchResult>[];

    void searchNode(RDFileNode node, List<String> path) {
      if (!node.isFolder) {
        if (FileUtils.isVideoFile(node.name) &&
            node.name.toLowerCase().contains(lowerQuery)) {
          results.add(_TorboxSearchResult(node: node, path: path.join(' / ')));
        }
      } else {
        for (final child in node.children) {
          searchNode(child, [...path, node.name]);
        }
      }
    }

    for (final child in rootNode.children) {
      searchNode(child, []);
    }

    setState(() => _searchResults = results);
  }

  /// Build the search bar widget
  Widget _buildSearchBar() {
    final hasText = _searchController.text.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: Focus(
              // D-pad navigation handler for Android TV
              onKeyEvent: (node, event) {
                if (event is! KeyDownEvent) return KeyEventResult.ignored;
                final key = event.logicalKey;
                final textLength = _searchController.text.length;
                final selection = _searchController.selection;
                final isTextEmpty = textLength == 0;
                final isSelectionValid = selection.isValid && selection.baseOffset >= 0;
                final isAtStart = !isSelectionValid ||
                    (selection.baseOffset == 0 && selection.extentOffset == 0);
                final isAtEnd = !isSelectionValid ||
                    (selection.baseOffset == textLength && selection.extentOffset == textLength);

                // Arrow Up at start/empty: exit TextField
                if (key == LogicalKeyboardKey.arrowUp) {
                  if (isTextEmpty || isAtStart) {
                    _searchFocusNode.unfocus();
                    return KeyEventResult.handled;
                  }
                }

                // Arrow Down at end/empty: exit TextField to results
                if (key == LogicalKeyboardKey.arrowDown) {
                  if (isTextEmpty || isAtEnd) {
                    _searchFocusNode.unfocus();
                    return KeyEventResult.handled;
                  }
                }

                // Arrow Right at end: move to clear button if visible
                if (key == LogicalKeyboardKey.arrowRight) {
                  if (hasText && (isTextEmpty || isAtEnd)) {
                    _searchClearFocusNode.requestFocus();
                    return KeyEventResult.handled;
                  }
                }

                return KeyEventResult.ignored;
              },
              child: TextField(
                controller: _searchController,
                focusNode: _searchFocusNode,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Search all files...',
                  prefixIcon: const Icon(Icons.search, color: Colors.grey),
                  filled: true,
                  fillColor: const Color(0xFF1E293B),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                style: const TextStyle(color: Colors.white),
                onChanged: _performSearch,
                onSubmitted: (_) => _searchFocusNode.unfocus(),
              ),
            ),
          ),
          // Clear button - separate focusable widget for D-pad navigation
          if (hasText)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Focus(
                focusNode: _searchClearFocusNode,
                onKeyEvent: (node, event) {
                  if (event is! KeyDownEvent) return KeyEventResult.ignored;
                  final key = event.logicalKey;

                  // Select/Enter: clear search
                  if (key == LogicalKeyboardKey.select ||
                      key == LogicalKeyboardKey.enter) {
                    setState(() {
                      _searchController.clear();
                      _searchResults.clear();
                    });
                    _searchFocusNode.requestFocus();
                    return KeyEventResult.handled;
                  }

                  // Arrow Left: go back to TextField
                  if (key == LogicalKeyboardKey.arrowLeft) {
                    _searchFocusNode.requestFocus();
                    return KeyEventResult.handled;
                  }

                  return KeyEventResult.ignored;
                },
                child: Builder(
                  builder: (context) {
                    final isFocused = Focus.of(context).hasFocus;
                    return Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(8),
                        border: isFocused
                            ? Border.all(color: Colors.white, width: 2)
                            : null,
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.clear, color: Colors.grey),
                        onPressed: () {
                          setState(() {
                            _searchController.clear();
                            _searchResults.clear();
                          });
                          _searchFocusNode.requestFocus();
                        },
                      ),
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Build search results list
  Widget _buildSearchResults() {
    if (_searchController.text.isEmpty) {
      return const Center(
        child: Text('Type to search all files', style: TextStyle(color: Colors.grey)),
      );
    }

    if (_searchResults.isEmpty) {
      return const Center(
        child: Text('No files found', style: TextStyle(color: Colors.grey)),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        final result = _searchResults[index];
        return _buildSearchResultCard(result);
      },
    );
  }

  /// Build a card for a search result
  Widget _buildSearchResultCard(_TorboxSearchResult result) {
    final node = result.node;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1F2A44), Color(0xFF111C32)],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08), width: 1.2),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => _playVideoFile(node),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.play_circle_outline, color: Colors.blue, size: 32),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        node.name,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (result.path.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          result.path,
                          style: TextStyle(color: Colors.grey[500], fontSize: 12),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      if (node.bytes != null)
                        Text(
                          Formatters.formatFileSize(node.bytes!),
                          style: TextStyle(color: Colors.grey[400], fontSize: 12),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Get items to display (torrents/web downloads or files/folders)
  List<dynamic> get _currentItems {
    if (_isAtRoot) {
      // At root: show torrents or web downloads based on selected view
      if (_selectedView == _TorboxDownloadsView.webDownloads) {
        return _webDownloads;
      }
      return _torrents;
    } else {
      // Inside torrent/web download: show current folder's children (transformed by view mode)
      return _currentViewNodes ?? _currentFolderNode?.children ?? [];
    }
  }

  @override
  Widget build(BuildContext context) {
    // Back navigation is handled via MainPageBridge.handleBackNavigation

    // When pushed as a route and still at root, show loading state
    // (we're waiting for navigation into the specific torrent)
    if (widget.isPushedRoute && _isAtRoot) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop(),
            tooltip: 'Back',
          ),
          title: const Text('Opening torrent...'),
        ),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Loading torrent files...'),
            ],
          ),
        ),
      );
    }

    final currentMode = _getCurrentViewMode();
    final showSearch = !_isAtRoot && currentMode != _FolderViewMode.seriesArrange;

    return Scaffold(
      appBar: _isAtRoot ? null : AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => _handleBackNavigation(),
          tooltip: 'Back',
        ),
        title: Text(_currentFolderName),
        actions: [
          if (showSearch)
            IconButton(
              focusNode: _searchButtonFocusNode,
              icon: Icon(_isSearchActive ? Icons.close : Icons.search),
              onPressed: _toggleSearch,
              tooltip: _isSearchActive ? 'Close search' : 'Search files',
            ),
        ],
      ),
      body: Column(
        children: [
          const SizedBox(height: 8),
          if (_isAtRoot) _buildToolbar(),
          if (!_isAtRoot) _buildViewModeDropdown(),
          if (_isSearchActive && showSearch) _buildSearchBar(),
          Expanded(
            child: _isSearchActive
                ? _buildSearchResults()
                : RefreshIndicator(
                    onRefresh: _refresh,
                    child: _buildFilesFoldersList(),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilesFoldersList() {
    // Check if we're showing web downloads view at root level
    final isWebDownloadsView = _isAtRoot && _selectedView == _TorboxDownloadsView.webDownloads;

    if (isWebDownloadsView) {
      return _buildWebDownloadsList();
    }

    // Loading state
    if (_isLoading && _currentItems.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading your Torbox torrents...'),
          ],
        ),
      );
    }

    // Error state
    if (_errorMessage.isNotEmpty && _currentItems.isEmpty && !_initialLoad) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          Icon(
            Icons.flash_on_rounded,
            size: 48,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text(_errorMessage, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          if (_apiKey == null || _apiKey!.isEmpty)
            FilledButton(
              onPressed: _openSettings,
              child: const Text('Open Torbox Settings'),
            ),
        ],
      );
    }

    // Empty state
    if (_currentItems.isEmpty && !_isLoading) {
      final isRoot = _isAtRoot;
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isRoot ? Icons.inbox_outlined : Icons.folder_open,
                size: 64,
                color: Colors.grey.shade400,
              ),
              const SizedBox(height: 24),
              Text(
                isRoot ? 'No Torrents Yet' : 'Folder is Empty',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 16),
              Text(
                isRoot
                    ? 'Add torrents via Torbox to see them here.'
                    : 'This folder doesn\'t contain any files or subfolders.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
      );
    }

    // List of items (torrents or files/folders)
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: _currentItems.length + (_isLoadingMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= _currentItems.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final item = _currentItems[index];

        if (_isAtRoot) {
          // Show torrent as a folder
          return _buildTorrentFolderCard(item as TorboxTorrent, index);
        } else {
          // Show file or folder node
          return _buildFileOrFolderCard(item as RDFileNode, index);
        }
      },
    );
  }

  Widget _buildWebDownloadsList() {
    // Loading state
    if (_isLoadingWebDownloads && _webDownloads.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading your Torbox web downloads...'),
          ],
        ),
      );
    }

    // Error state
    if (_webDownloadErrorMessage.isNotEmpty && _webDownloads.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          Icon(
            Icons.link_rounded,
            size: 48,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text(_webDownloadErrorMessage, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          if (_apiKey == null || _apiKey!.isEmpty)
            FilledButton(
              onPressed: _openSettings,
              child: const Text('Open Torbox Settings'),
            ),
        ],
      );
    }

    // Empty state
    if (_webDownloads.isEmpty && !_isLoadingWebDownloads) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.link_off,
                size: 64,
                color: Colors.grey.shade400,
              ),
              const SizedBox(height: 24),
              Text(
                'No Web Downloads Yet',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 16),
              Text(
                'Add web downloads from YouTube, file hosts, and more.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
      );
    }

    // List of web downloads
    return ListView.builder(
      controller: _webDownloadScrollController,
      padding: const EdgeInsets.all(16),
      itemCount: _webDownloads.length + (_isLoadingMoreWebDownloads ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= _webDownloads.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        return _buildWebDownloadCard(_webDownloads[index], index);
      },
    );
  }

  Widget _buildWebDownloadCard(TorboxWebDownload webDownload, int index) {
    final videoCount = webDownload.files.where(_torboxFileLooksLikeVideo).length;

    return TvFocusScrollWrapper(
      child: Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.folder, color: Colors.blue, size: 32),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        webDownload.name,
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
                            Formatters.formatFileSize(webDownload.size),
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text('•', style: TextStyle(color: Colors.grey.shade600)),
                          const SizedBox(width: 8),
                          Text(
                            '${webDownload.files.length} file${webDownload.files.length == 1 ? '' : 's'}',
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
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _navigateIntoWebDownload(webDownload),
                    icon: const Icon(Icons.folder_open, size: 18),
                    label: const Text('Open'),
                  ),
                ),
                if (videoCount > 0) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => _handlePlayWebDownload(webDownload),
                      icon: const Icon(Icons.play_arrow, size: 18),
                      label: const Text('Play'),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.green.shade700,
                      ),
                    ),
                  ),
                ],
                const SizedBox(width: 8),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert),
                  tooltip: 'More options',
                  onSelected: (value) {
                    if (value == 'open') {
                      _navigateIntoWebDownload(webDownload);
                    } else if (value == 'download') {
                      _showWebDownloadOptionsDialog(webDownload);
                    } else if (value == 'copy_link') {
                      _copyWebDownloadLink(webDownload);
                    } else if (value == 'delete') {
                      _confirmDeleteWebDownload(webDownload);
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'open',
                      child: Row(
                        children: [
                          Icon(Icons.folder_open, size: 18, color: Colors.blue),
                          SizedBox(width: 12),
                          Text('Open'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'download',
                      child: Row(
                        children: [
                          Icon(Icons.download, size: 18, color: Colors.green),
                          SizedBox(width: 12),
                          Text('Download to device'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'copy_link',
                      child: Row(
                        children: [
                          Icon(Icons.link, size: 18, color: Color(0xFFEC4899)),
                          SizedBox(width: 12),
                          Text('Copy Download Link'),
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
      ),
    );
  }

  /// Build a card for a torrent (displayed as a folder at root level)
  Widget _buildTorrentFolderCard(TorboxTorrent torrent, int index) {
    final videoCount = torrent.files.where(_torboxFileLooksLikeVideo).length;

    return TvFocusScrollWrapper(
      child: Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.folder, color: Colors.amber, size: 32),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        torrent.name,
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
                            Formatters.formatFileSize(torrent.size),
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text('•', style: TextStyle(color: Colors.grey.shade600)),
                          const SizedBox(width: 8),
                          Text(
                            '${torrent.files.length} files',
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
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _navigateIntoTorrent(torrent),
                    icon: const Icon(Icons.folder_open, size: 18),
                    label: const Text('Open'),
                  ),
                ),
                if (videoCount > 0) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => _handlePlayTorrent(torrent),
                      icon: const Icon(Icons.play_arrow, size: 18),
                      label: const Text('Play'),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.green.shade700,
                      ),
                    ),
                  ),
                ],
                const SizedBox(width: 8),
                // 3-dot menu
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert),
                  tooltip: 'More options',
                  onSelected: (value) {
                    if (value == 'open') {
                      _navigateIntoTorrent(torrent);
                    } else if (value == 'download') {
                      _showDownloadOptionsDialog(torrent);
                    } else if (value == 'copy_zip_link') {
                      _copyTorboxZipLink(torrent);
                    } else if (value == 'add_to_playlist') {
                      _handleAddToPlaylist(torrent);
                    } else if (value == 'delete') {
                      _confirmDeleteTorrent(torrent);
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'open',
                      child: Row(
                        children: [
                          Icon(Icons.folder_open, size: 18, color: Colors.blue),
                          SizedBox(width: 12),
                          Text('Open'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'download',
                      child: Row(
                        children: [
                          Icon(Icons.download, size: 18, color: Colors.green),
                          SizedBox(width: 12),
                          Text('Download to device'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'copy_zip_link',
                      child: Row(
                        children: [
                          Icon(Icons.link, size: 18, color: Color(0xFFEC4899)),
                          SizedBox(width: 12),
                          Text('Copy Download Link (Zip)'),
                        ],
                      ),
                    ),
                    if (videoCount > 0)
                      const PopupMenuItem(
                        value: 'add_to_playlist',
                        child: Row(
                          children: [
                            Icon(Icons.playlist_add, size: 18, color: Colors.blue),
                            SizedBox(width: 12),
                            Text('Add to Playlist'),
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
      ),
    );
  }

  /// Build a card for a file or folder node (inside a torrent)
  Widget _buildFileOrFolderCard(RDFileNode node, int index) {
    final isFolder = node.isFolder;
    final isVideo = !isFolder && FileUtils.isVideoFile(node.name);

    return TvFocusScrollWrapper(
      child: Card(
      margin: const EdgeInsets.only(bottom: 12),
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
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        node.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w500,
                          fontSize: 16,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        isFolder
                            ? '${node.fileCount} items • ${Formatters.formatFileSize(node.totalBytes)}'
                            : Formatters.formatFileSize(node.bytes ?? 0),
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                if (isFolder) ...[
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => _navigateIntoFolder(node),
                      icon: const Icon(Icons.folder_open, size: 18),
                      label: const Text('Open'),
                    ),
                  ),
                  if (TorboxFolderTreeBuilder.hasVideoFiles(node)) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => _playFolderVideos(node),
                        icon: const Icon(Icons.play_arrow, size: 18),
                        label: const Text('Play'),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.green.shade700,
                        ),
                      ),
                    ),
                  ],
                ] else if (isVideo) ...[
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => _playVideoFile(node),
                      icon: const Icon(Icons.play_arrow, size: 18),
                      label: const Text('Play'),
                    ),
                  ),
                ],
                const SizedBox(width: 8),
                // 3-dot menu
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert),
                  tooltip: 'More options',
                  onSelected: (value) {
                    if (value == 'download') {
                      _downloadFileOrFolder(node);
                    } else if (value == 'add_to_playlist') {
                      _addFileOrFolderToPlaylist(node);
                    } else if (value == 'copy_link') {
                      _copyFileLink(node);
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
                    // Only show Add to Playlist for torrents, not web downloads
                    if (_currentWebDownload == null && (isVideo || (isFolder && TorboxFolderTreeBuilder.hasVideoFiles(node))))
                      const PopupMenuItem(
                        value: 'add_to_playlist',
                        child: Row(
                          children: [
                            Icon(Icons.playlist_add, size: 18, color: Colors.blue),
                            SizedBox(width: 12),
                            Text('Add to Playlist'),
                          ],
                        ),
                      ),
                    if (!isFolder)
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
                    if (isVideo)
                      const PopupMenuItem(
                        value: 'open_external',
                        child: Row(
                          children: [
                            Icon(Icons.open_in_new, size: 18, color: Colors.purple),
                            SizedBox(width: 12),
                            Text('Open with External Player'),
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
        child: DropdownButton<_TorboxDownloadsView>(
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
              value: _TorboxDownloadsView.torrents,
              child: Text('Torrents'),
            ),
            DropdownMenuItem(
              value: _TorboxDownloadsView.webDownloads,
              child: Text('Web Downloads'),
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

  Widget _buildToolbar() {
    final theme = Theme.of(context);
    final isTorrentsView = _selectedView == _TorboxDownloadsView.torrents;

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
          if (isTorrentsView) ...[
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
                onPressed: _torrents.isEmpty ? null : _confirmDeleteAll,
                icon: const Icon(Icons.delete_sweep),
                color: const Color(0xFFEF4444),
                visualDensity: VisualDensity.compact,
              ),
            ),
          ] else ...[
            Tooltip(
              message: 'Add web download',
              child: IconButton(
                onPressed: _showAddWebDownloadDialog,
                icon: const Icon(Icons.link),
                color: theme.colorScheme.primary,
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TorboxTorrentCard extends StatelessWidget {
  const _TorboxTorrentCard({
    super.key,
    required this.torrent,
    required this.onPlay,
    required this.onDownload,
    required this.onMoreOptions,
  });

  final TorboxTorrent torrent;
  final VoidCallback onPlay;
  final VoidCallback onDownload;
  final VoidCallback onMoreOptions;

  @override
  Widget build(BuildContext context) {
    final cachedAt = torrent.cachedAt ?? torrent.createdAt;
    final safeProgress = torrent.progress.clamp(0, 1);
    final progressPercent = (safeProgress * 100).round();
    final borderColor = Colors.white.withValues(alpha: 0.08);
    final glowColor = const Color(0xFF6366F1).withValues(alpha: 0.08);

    const playColor = Color(0xFF7F1D1D);
    const downloadColor = Color(0xFF065F46);

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
                        torrent.name,
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
                    _buildMoreOptionsButton(onMoreOptions),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    StatChip(
                      icon: Icons.storage,
                      text: Formatters.formatFileSize(torrent.size),
                      color: const Color(0xFF6366F1),
                    ),
                    const SizedBox(width: 8),
                    StatChip(
                      icon: Icons.link,
                      text:
                          '${torrent.files.length} file${torrent.files.length == 1 ? '' : 's'}',
                      color: const Color(0xFFF59E0B),
                    ),
                    const SizedBox(width: 8),
                    StatChip(
                      icon: Icons.download_done,
                      text: '$progressPercent%',
                      color: const Color(0xFF10B981),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(
                      Icons.flash_on_rounded,
                      size: 16,
                      color: Colors.grey[400],
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        'Server ${torrent.server} • ${torrent.owner.isEmpty ? 'Torbox' : torrent.owner}',
                        style: TextStyle(color: Colors.grey[400], fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Cached ${Formatters.formatDateTime(cachedAt.toIso8601String())}',
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
                  final playButton = _buildPrimaryButton(
                    icon: Icons.play_arrow,
                    label: 'Play',
                    backgroundColor: playColor,
                    onPressed: onPlay,
                  );
                  final downloadButton = _buildPrimaryButton(
                    icon: Icons.download_rounded,
                    label: 'Download',
                    backgroundColor: downloadColor,
                    onPressed: onDownload,
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

  Widget _buildPrimaryButton({
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

  Widget _buildMoreOptionsButton(VoidCallback onPressed) {
    return IconButton(
      onPressed: onPressed,
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
}

class _TorboxFileEntry {
  final TorboxFile file;
  final int index;
  final SeriesInfo seriesInfo;

  _TorboxFileEntry({
    required this.file,
    required this.index,
    required this.seriesInfo,
  });
}

class _TorboxEpisodeCandidate {
  final TorboxFile file;
  final SeriesInfo info;
  final String displayName;

  _TorboxEpisodeCandidate({
    required this.file,
    required this.info,
    required this.displayName,
  });

  int get size => file.size;
}

class _TorboxMoreOption {
  const _TorboxMoreOption({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
    this.enabled = true,
  });

  final IconData icon;
  final String label;
  final Future<void> Function() onTap;
  final bool destructive;
  final bool enabled;
}

/// Helper class to hold search result with its folder path
class _TorboxSearchResult {
  final RDFileNode node;
  final String path;

  const _TorboxSearchResult({required this.node, required this.path});
}
