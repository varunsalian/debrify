import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../screens/video_player_screen.dart'; // re-exports PlaylistEntry
import '../../services/alldebrid_service.dart';
import '../../services/storage_service.dart';
import '../../services/download_service.dart';
import '../../services/video_player_launcher.dart';
import '../../services/main_page_bridge.dart';
import '../../models/alldebrid_magnet.dart';
import '../../models/alldebrid_file.dart';
import '../../models/playlist_view_mode.dart';
import '../../utils/file_utils.dart';
import '../../utils/formatters.dart';
import '../../utils/series_parser.dart';
import '../../widgets/file_selection_dialog.dart';
import '../debrify_tv/widgets/tv_focus_scroll_wrapper.dart';

/// Cloud-library browser for AllDebrid. AllDebrid's cloud is a flat list of
/// magnets (each with files), so this is a two-level browser (magnet list →
/// the selected magnet's files), built to match the Torbox/Real-Debrid
/// downloads pages (same toolbar, cards and action buttons).
class AllDebridFilesScreen extends StatefulWidget {
  final bool isPushedRoute;

  const AllDebridFilesScreen({super.key, this.isPushedRoute = false});

  @override
  State<AllDebridFilesScreen> createState() => _AllDebridFilesScreenState();
}

class _AllDebridFilesScreenState extends State<AllDebridFilesScreen> {
  static const int _tabIndex = 12;

  String? _apiKey;
  bool _loading = true;
  String? _error;

  List<AllDebridMagnet> _magnets = [];

  // When non-null, we are viewing this magnet's files.
  AllDebridMagnet? _currentMagnet;
  List<AllDebridFile> _currentFiles = [];
  bool _loadingFiles = false;

  bool get _isAtRoot => _currentMagnet == null;

  // Root search.
  bool _searchActive = false;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final FocusNode _searchClearFocusNode = FocusNode();

  // In-folder (files) search.
  bool _fileSearchActive = false;
  String _fileSearchQuery = '';
  final TextEditingController _fileSearchController = TextEditingController();
  final FocusNode _fileSearchFocusNode = FocusNode();

  // Multi-select (magnet ids) for bulk delete.
  bool _selectionMode = false;
  final Set<String> _selectedIds = {};

  final ScrollController _scrollController = ScrollController();
  final FocusNode _backButtonFocusNode = FocusNode();
  final FocusNode _deleteButtonFocusNode = FocusNode();
  final FocusNode _toolbarSearchFocusNode = FocusNode();
  VoidCallback? _tvContentFocusHandler;

  // TV: focus the first magnet card when the user moves focus into content.
  bool _shouldFocusOnLoad = false;
  final FocusNode _firstItemFocusNode = FocusNode(debugLabel: 'ad-first-item');

  @override
  void initState() {
    super.initState();
    if (!widget.isPushedRoute) {
      MainPageBridge.registerTabBackHandler('alldebrid', _handleBackNavigation);
      _tvContentFocusHandler = () {
        _shouldFocusOnLoad = true;
        _focusFirstItem();
      };
      MainPageBridge.registerTvContentFocusHandler(
        _tabIndex,
        _tvContentFocusHandler!,
      );
    }
    _load();
  }

  @override
  void dispose() {
    if (!widget.isPushedRoute) {
      MainPageBridge.unregisterTabBackHandler('alldebrid');
      if (_tvContentFocusHandler != null) {
        MainPageBridge.unregisterTvContentFocusHandler(
          _tabIndex,
          _tvContentFocusHandler!,
        );
      }
    }
    _searchController.dispose();
    _searchFocusNode.dispose();
    _searchClearFocusNode.dispose();
    _fileSearchController.dispose();
    _fileSearchFocusNode.dispose();
    _scrollController.dispose();
    _backButtonFocusNode.dispose();
    _deleteButtonFocusNode.dispose();
    _toolbarSearchFocusNode.dispose();
    _firstItemFocusNode.dispose();
    super.dispose();
  }

  void _focusFirstItem() {
    if (!_shouldFocusOnLoad) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_shouldFocusOnLoad) return;
      if (_isAtRoot && _visibleMagnets.isNotEmpty) {
        _shouldFocusOnLoad = false;
        _firstItemFocusNode.requestFocus();
      }
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final apiKey = await StorageService.getAllDebridApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Add your AllDebrid API key in Settings first.';
      });
      return;
    }
    _apiKey = apiKey;
    try {
      final magnets = await AllDebridService.listMagnets(apiKey);
      if (!mounted) return;
      setState(() {
        _magnets = magnets;
        _loading = false;
        _selectedIds.removeWhere((id) => !magnets.any((m) => m.id == id));
      });
      _focusFirstItem();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Failed to load your AllDebrid library: $e';
      });
    }
  }

  Future<void> _refresh() async {
    if (_currentMagnet != null) {
      await _openMagnet(_currentMagnet!, force: true);
    } else {
      await _load();
    }
  }

  // ── Navigation ─────────────────────────────────────────────────────────────

  Future<void> _openMagnet(AllDebridMagnet magnet, {bool force = false}) async {
    final apiKey = _apiKey;
    if (apiKey == null || apiKey.isEmpty) return;
    if (!magnet.isReady) {
      _snack(
        magnet.isError
            ? 'This magnet failed on AllDebrid.'
            : 'This magnet is still downloading on AllDebrid.',
        isError: true,
      );
      return;
    }
    setState(() {
      _currentMagnet = magnet;
      _loadingFiles = true;
      _fileSearchActive = false;
      _fileSearchQuery = '';
      _fileSearchController.clear();
      if (!force) _currentFiles = [];
    });
    try {
      final files = await AllDebridService.getMagnetFiles(apiKey, magnet.id);
      if (!mounted) return;
      setState(() {
        _currentFiles = files;
        _loadingFiles = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingFiles = false);
      _snack('Failed to load files: $e', isError: true);
    }
  }

  void _navigateUp() {
    setState(() {
      _currentMagnet = null;
      _currentFiles = [];
      _loadingFiles = false;
      _fileSearchActive = false;
      _fileSearchQuery = '';
      _fileSearchController.clear();
    });
  }

  bool _handleBackNavigation() {
    if (_selectionMode) {
      _exitSelectionMode();
      return true;
    }
    if (_fileSearchActive) {
      setState(() {
        _fileSearchActive = false;
        _fileSearchQuery = '';
        _fileSearchController.clear();
      });
      return true;
    }
    if (_searchActive) {
      _toggleSearch();
      return true;
    }
    if (_currentMagnet != null) {
      _navigateUp();
      return true;
    }
    return false;
  }

  // ── Playback ─────────────────────────────────────────────────────────────

  bool _looksLikeVideo(AllDebridFile f) => FileUtils.isVideoFile(f.fileName);

  Future<String> _unlockStart(String apiKey, String lockedLink) async {
    try {
      return await AllDebridService.unlockLink(apiKey, lockedLink);
    } catch (e) {
      debugPrint('AllDebridFiles: unlock failed: $e');
      return '';
    }
  }

  Future<void> _playFile(AllDebridFile file) async {
    final apiKey = _apiKey;
    if (apiKey == null || apiKey.isEmpty) return;
    _showLoading('Unlocking…');
    final url = await _unlockStart(apiKey, file.link);
    _dismissLoading();
    if (!mounted) return;
    if (url.isEmpty) {
      _snack('Failed to unlock this file.', isError: true);
      return;
    }
    MainPageBridge.notifyPlayerLaunching();
    await VideoPlayerLauncher.push(
      context,
      VideoPlayerLaunchArgs(
        videoUrl: url,
        title: file.fileName,
        subtitle: file.size > 0 ? Formatters.formatFileSize(file.size) : null,
        playlist: [
          PlaylistEntry(
            url: url,
            title: file.fileName,
            relativePath: file.fileName,
            provider: 'alldebrid',
            allDebridLink: file.link,
            sizeBytes: file.size > 0 ? file.size : null,
          ),
        ],
        startIndex: 0,
        viewMode: PlaylistViewMode.sorted,
      ),
    );
  }

  Future<void> _playMagnet(AllDebridMagnet magnet) async {
    final apiKey = _apiKey;
    if (apiKey == null || apiKey.isEmpty) return;
    if (!magnet.isReady) {
      _snack('This magnet is not ready yet.', isError: true);
      return;
    }
    List<AllDebridFile> files = _currentFiles;
    if (_currentMagnet?.id != magnet.id || files.isEmpty) {
      _showLoading('Scanning magnet…');
      try {
        files = await AllDebridService.getMagnetFiles(apiKey, magnet.id);
      } catch (e) {
        _dismissLoading();
        _snack('Failed to scan magnet: $e', isError: true);
        return;
      }
      _dismissLoading();
    }
    await _playVideos(files, magnet.name);
  }

  Future<void> _playVideos(
    List<AllDebridFile> files,
    String collectionName,
  ) async {
    final apiKey = _apiKey;
    if (apiKey == null || apiKey.isEmpty) return;
    final videos = files.where(_looksLikeVideo).toList();
    if (videos.isEmpty) {
      _snack('No playable video files found.', isError: true);
      return;
    }

    if (videos.length == 1) {
      await _playFile(videos.first);
      return;
    }

    // Multi-file: build a series-aware playlist, unlocking only the start file
    // up front. The rest carry their stable locked link and are unlocked on
    // demand by the player's lazy AllDebrid resolver.
    final infos =
        videos.map((v) => SeriesParser.parseFilename(v.fileName)).toList();
    final filenames = videos.map((v) => v.fileName).toList();
    final bool isSeries =
        videos.length > 1 && SeriesParser.isSeriesPlaylist(filenames);

    final order = List<int>.generate(videos.length, (i) => i);
    if (isSeries) {
      order.sort((a, b) {
        final sa = infos[a].season ?? 0, sb = infos[b].season ?? 0;
        if (sa != sb) return sa.compareTo(sb);
        final ea = infos[a].episode ?? 0, eb = infos[b].episode ?? 0;
        if (ea != eb) return ea.compareTo(eb);
        return videos[a].fileName.toLowerCase().compareTo(
              videos[b].fileName.toLowerCase(),
            );
      });
    } else {
      order.sort(
        (a, b) => videos[a].fileName.toLowerCase().compareTo(
              videos[b].fileName.toLowerCase(),
            ),
      );
    }

    final sortedVideos = [for (final i in order) videos[i]];
    final sortedInfos = [for (final i in order) infos[i]];
    int startIndex = isSeries ? _findFirstEpisodeIndex(sortedInfos) : 0;
    if (startIndex < 0 || startIndex >= sortedVideos.length) startIndex = 0;

    _showLoading('Unlocking…');
    String startUrl = await _unlockStart(apiKey, sortedVideos[startIndex].link);
    if (startUrl.isEmpty) {
      for (int i = 0; i < sortedVideos.length; i++) {
        if (i == startIndex) continue;
        final u = await _unlockStart(apiKey, sortedVideos[i].link);
        if (u.isNotEmpty) {
          startUrl = u;
          startIndex = i;
          break;
        }
      }
    }
    _dismissLoading();
    if (!mounted) return;
    if (startUrl.isEmpty) {
      _snack('Failed to resolve playable links from AllDebrid.', isError: true);
      return;
    }

    final entries = <PlaylistEntry>[];
    for (int i = 0; i < sortedVideos.length; i++) {
      final v = sortedVideos[i];
      String relativePath = v.path;
      final firstSlash = relativePath.indexOf('/');
      if (firstSlash > 0) {
        relativePath = relativePath.substring(firstSlash + 1);
      }
      entries.add(
        PlaylistEntry(
          url: i == startIndex ? startUrl : '',
          title: v.fileName,
          relativePath: relativePath,
          provider: 'alldebrid',
          allDebridLink: v.link,
          sizeBytes: v.size > 0 ? v.size : null,
        ),
      );
    }

    final totalBytes = sortedVideos.fold<int>(0, (s, v) => s + v.size);
    final subtitle =
        '${entries.length} ${isSeries ? 'episodes' : 'files'} • ${Formatters.formatFileSize(totalBytes)}';

    if (!mounted) return;
    MainPageBridge.notifyPlayerLaunching();
    await VideoPlayerLauncher.push(
      context,
      VideoPlayerLaunchArgs(
        videoUrl: startUrl,
        title: collectionName,
        subtitle: subtitle,
        playlist: entries,
        startIndex: startIndex,
        viewMode: isSeries ? PlaylistViewMode.series : PlaylistViewMode.sorted,
      ),
    );
  }

  int _findFirstEpisodeIndex(List<SeriesInfo> infos) {
    int startIndex = 0;
    int? bestSeason;
    int? bestEpisode;
    for (int i = 0; i < infos.length; i++) {
      final info = infos[i];
      final season = info.season;
      final episode = info.episode;
      if (!info.isSeries || season == null || episode == null) continue;
      final betterSeason = bestSeason == null || season < bestSeason;
      final betterEpisode = bestSeason != null &&
          season == bestSeason &&
          (bestEpisode == null || episode < bestEpisode);
      if (betterSeason || betterEpisode) {
        bestSeason = season;
        bestEpisode = episode;
        startIndex = i;
      }
    }
    return startIndex;
  }

  // ── Download ─────────────────────────────────────────────────────────────

  Future<void> _downloadFile(AllDebridFile file) async {
    final apiKey = _apiKey;
    if (apiKey == null || apiKey.isEmpty) return;
    _showLoading('Preparing download…');
    final url = await _unlockStart(apiKey, file.link);
    _dismissLoading();
    if (!mounted) return;
    if (url.isEmpty) {
      _snack('Failed to unlock this file.', isError: true);
      return;
    }
    try {
      await DownloadService.instance.enqueueDownload(
        url: url,
        fileName: file.fileName,
        context: mounted ? context : null,
      );
      _snack('Download queued: ${file.fileName}', isError: false);
    } catch (e) {
      _snack('Failed to download: $e', isError: true);
    }
  }

  Future<void> _downloadMagnet(AllDebridMagnet magnet) async {
    final apiKey = _apiKey;
    if (apiKey == null || apiKey.isEmpty) return;
    List<AllDebridFile> files = _currentFiles;
    if (_currentMagnet?.id != magnet.id || files.isEmpty) {
      _showLoading('Scanning magnet…');
      try {
        files = await AllDebridService.getMagnetFiles(apiKey, magnet.id);
      } catch (e) {
        _dismissLoading();
        _snack('Failed to scan magnet: $e', isError: true);
        return;
      }
      _dismissLoading();
    }
    if (!mounted) return;
    if (files.isEmpty) {
      _snack('This magnet has no files.', isError: true);
      return;
    }
    final dialogFiles = <Map<String, dynamic>>[];
    for (int i = 0; i < files.length; i++) {
      dialogFiles.add({
        'name': files[i].path,
        '_fullPath': files[i].path,
        'size': files[i].size.toString(),
        '_adIndex': i,
      });
    }
    await showDialog(
      context: context,
      builder: (ctx) => FileSelectionDialog(
        files: dialogFiles,
        torrentName: magnet.name,
        onDownload: (selected) =>
            _downloadSelectedFiles(selected, files, magnet.name),
      ),
    );
  }

  Future<void> _downloadSelectedFiles(
    List<Map<String, dynamic>> selected,
    List<AllDebridFile> allFiles,
    String magnetName,
  ) async {
    final apiKey = _apiKey;
    if (apiKey == null || apiKey.isEmpty) return;
    if (selected.isEmpty) return;
    int success = 0, fail = 0;
    for (final f in selected) {
      final idx = f['_adIndex'] as int? ?? -1;
      if (idx < 0 || idx >= allFiles.length) {
        fail++;
        continue;
      }
      final target = allFiles[idx];
      final url = await _unlockStart(apiKey, target.link);
      if (url.isEmpty) {
        fail++;
        continue;
      }
      try {
        await DownloadService.instance.enqueueDownload(
          url: url,
          fileName: target.fileName,
          torrentName: magnetName,
          context: mounted ? context : null,
        );
        success++;
      } catch (_) {
        fail++;
      }
    }
    if (!mounted) return;
    if (success > 0 && fail == 0) {
      _snack('Queued $success file${success == 1 ? '' : 's'}', isError: false);
    } else if (success > 0) {
      _snack('Queued $success, $fail failed', isError: true);
    } else {
      _snack('Failed to queue any files', isError: true);
    }
  }

  // ── Add magnet ─────────────────────────────────────────────────────────────

  Future<void> _showAddMagnetDialog() async {
    final apiKey = _apiKey;
    if (apiKey == null || apiKey.isEmpty) return;
    final controller = TextEditingController();
    final magnet = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add magnet'),
        content: Focus(
          // D-pad: let arrow-down leave the field for the Cancel/Add buttons.
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent &&
                event.logicalKey == LogicalKeyboardKey.arrowDown) {
              node.nextFocus();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: TextField(
            controller: controller,
            autofocus: true,
            maxLines: 3,
            minLines: 1,
            decoration: const InputDecoration(
              hintText: 'Paste a magnet link or infohash',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (magnet == null || magnet.isEmpty) return;
    _showLoading('Adding…');
    try {
      await AllDebridService.uploadMagnet(apiKey, magnet);
      _dismissLoading();
      _snack('Magnet added', isError: false);
      await _load();
    } catch (e) {
      _dismissLoading();
      _snack('Failed to add magnet: $e', isError: true);
    }
  }

  // ── Delete ─────────────────────────────────────────────────────────────

  Future<void> _deleteMagnets(List<AllDebridMagnet> magnets,
      {String? title}) async {
    final apiKey = _apiKey;
    if (apiKey == null || apiKey.isEmpty || magnets.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title ??
            (magnets.length == 1
                ? 'Delete magnet?'
                : 'Delete ${magnets.length} magnets?')),
        content: Text(
          magnets.length == 1
              ? 'Remove "${magnets.first.name}" from your AllDebrid account?'
              : 'Remove these ${magnets.length} magnets from your AllDebrid account?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    _showLoading('Deleting…');
    for (final m in magnets) {
      await AllDebridService.deleteMagnet(apiKey, m.id);
    }
    _dismissLoading();
    _exitSelectionMode();
    await _load();
    if (mounted) {
      _snack(
        magnets.length == 1
            ? 'Magnet deleted'
            : '${magnets.length} magnets deleted',
        isError: false,
      );
    }
  }

  void _confirmDeleteAll() {
    if (_magnets.isEmpty) return;
    _deleteMagnets(List.of(_magnets), title: 'Delete all magnets?');
  }

  // ── Selection ─────────────────────────────────────────────────────────────

  void _toggleSelectionMode() {
    setState(() {
      _selectionMode = !_selectionMode;
      if (!_selectionMode) _selectedIds.clear();
    });
  }

  void _exitSelectionMode() {
    if (!_selectionMode && _selectedIds.isEmpty) return;
    setState(() {
      _selectionMode = false;
      _selectedIds.clear();
    });
  }

  void _toggleSelection(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  bool get _isAllSelected =>
      _visibleMagnets.isNotEmpty &&
      _visibleMagnets.every((m) => _selectedIds.contains(m.id));

  void _toggleSelectAll() {
    setState(() {
      if (_isAllSelected) {
        for (final m in _visibleMagnets) {
          _selectedIds.remove(m.id);
        }
      } else {
        for (final m in _visibleMagnets) {
          _selectedIds.add(m.id);
        }
      }
    });
  }

  Future<void> _handleDeleteSelected() async {
    final targets = _magnets.where((m) => _selectedIds.contains(m.id)).toList();
    if (targets.isEmpty) return;
    await _deleteMagnets(targets);
  }

  // ── Search ─────────────────────────────────────────────────────────────

  void _toggleSearch() {
    setState(() {
      _searchActive = !_searchActive;
      if (!_searchActive) {
        _searchQuery = '';
        _searchController.clear();
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _searchFocusNode.requestFocus();
        });
      }
    });
  }

  List<AllDebridMagnet> get _visibleMagnets {
    if (_searchQuery.trim().isEmpty) return _magnets;
    final q = _searchQuery.trim().toLowerCase();
    return _magnets.where((m) => m.name.toLowerCase().contains(q)).toList();
  }

  List<AllDebridFile> get _visibleFiles {
    if (_fileSearchQuery.trim().isEmpty) return _currentFiles;
    final q = _fileSearchQuery.trim().toLowerCase();
    return _currentFiles
        .where((f) => f.fileName.toLowerCase().contains(q))
        .toList();
  }

  // ── Dialog / snack helpers ───────────────────────────────────────────────

  bool _loadingDialogOpen = false;

  void _showLoading(String message) {
    if (_loadingDialogOpen || !mounted) return;
    _loadingDialogOpen = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Center(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
                const SizedBox(width: 16),
                Text(message),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _dismissLoading() {
    if (!_loadingDialogOpen) return;
    _loadingDialogOpen = false;
    if (mounted) Navigator.of(context, rootNavigator: true).pop();
  }

  void _snack(String message, {bool isError = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade700 : null,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _isAtRoot
          ? null
          : AppBar(
              leading: IconButton(
                focusNode: _backButtonFocusNode,
                icon: const Icon(Icons.arrow_back),
                onPressed: _navigateUp,
                tooltip: 'Back',
              ),
              title: Text(_currentMagnet!.name),
              actions: [
                if (_currentFiles.isNotEmpty)
                  IconButton(
                    icon: Icon(_fileSearchActive ? Icons.close : Icons.search),
                    onPressed: () {
                      setState(() {
                        _fileSearchActive = !_fileSearchActive;
                        if (!_fileSearchActive) {
                          _fileSearchQuery = '';
                          _fileSearchController.clear();
                        } else {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted) _fileSearchFocusNode.requestFocus();
                          });
                        }
                      });
                    },
                    tooltip: 'Search files',
                  ),
              ],
            ),
      body: Column(
        children: [
          const SizedBox(height: 8),
          if (_isAtRoot) _buildToolbar(),
          if (_isAtRoot && _searchActive) _buildSearchBar(),
          if (_isAtRoot && _selectionMode) _buildSelectionBar(),
          if (!_isAtRoot && _fileSearchActive) _buildFileSearchBar(),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildToolbar() {
    final theme = Theme.of(context);
    final hasItems = _magnets.isNotEmpty;
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 480;
        final double iconSize = isCompact ? 20 : 24;
        final iconPadding =
            isCompact ? const EdgeInsets.all(6) : const EdgeInsets.all(8);
        final iconConstraints = isCompact
            ? const BoxConstraints(minWidth: 36, minHeight: 36)
            : const BoxConstraints(minWidth: 44, minHeight: 44);
        return Container(
          margin: EdgeInsets.symmetric(
              horizontal: isCompact ? 8 : 16, vertical: 8),
          padding: EdgeInsets.symmetric(
              horizontal: isCompact ? 8 : 16, vertical: 8),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF1F2937)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  hasItems
                      ? '${_magnets.length} magnet${_magnets.length == 1 ? '' : 's'}'
                      : 'AllDebrid',
                  style: TextStyle(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              SizedBox(width: isCompact ? 6 : 12),
              if (hasItems) ...[
                Tooltip(
                  message: _selectionMode ? 'Exit selection' : 'Select items',
                  child: IconButton(
                    onPressed: _toggleSelectionMode,
                    iconSize: iconSize,
                    padding: iconPadding,
                    constraints: iconConstraints,
                    icon: Icon(
                        _selectionMode ? Icons.close : Icons.checklist_outlined),
                    color: _selectionMode
                        ? theme.colorScheme.error
                        : theme.colorScheme.onSurface,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                Tooltip(
                  message: 'Delete all magnets',
                  child: IconButton(
                    onPressed: _confirmDeleteAll,
                    iconSize: iconSize,
                    padding: iconPadding,
                    constraints: iconConstraints,
                    icon: const Icon(Icons.delete_sweep_outlined),
                    color: theme.colorScheme.error,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                Tooltip(
                  message: _searchActive ? 'Close search' : 'Search magnets',
                  child: IconButton(
                    focusNode: _toolbarSearchFocusNode,
                    onPressed: _toggleSearch,
                    iconSize: iconSize,
                    padding: iconPadding,
                    constraints: iconConstraints,
                    icon: Icon(_searchActive
                        ? Icons.search_off_rounded
                        : Icons.search_rounded),
                    color: _searchActive
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurface,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
              Tooltip(
                message: 'Add magnet link',
                child: IconButton(
                  onPressed: _showAddMagnetDialog,
                  iconSize: iconSize,
                  padding: iconPadding,
                  constraints: iconConstraints,
                  icon: const Icon(Icons.add_circle_outline),
                  color: theme.colorScheme.primary,
                  visualDensity: VisualDensity.compact,
                ),
              ),
              Tooltip(
                message: 'Refresh',
                child: IconButton(
                  onPressed: _refresh,
                  iconSize: iconSize,
                  padding: iconPadding,
                  constraints: iconConstraints,
                  icon: const Icon(Icons.refresh),
                  color: theme.colorScheme.onSurface,
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSelectionBar() {
    final theme = Theme.of(context);
    final count = _selectedIds.length;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Text(
            '$count selected',
            style: TextStyle(
              color: theme.colorScheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          TextButton(
            onPressed: _toggleSelectAll,
            child: Text(_isAllSelected ? 'Deselect All' : 'Select All'),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            focusNode: _deleteButtonFocusNode,
            onPressed: count > 0 ? _handleDeleteSelected : null,
            icon: const Icon(Icons.delete_outline, size: 18),
            label: const Text('Delete'),
            style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.error,
              disabledBackgroundColor:
                  theme.colorScheme.error.withValues(alpha: 0.3),
            ),
          ),
        ],
      ),
    );
  }

  /// Shared search-field decoration matching the Torbox/RD pages.
  InputDecoration _searchDecoration(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
        prefixIcon: Icon(Icons.search_rounded,
            color: Colors.white.withValues(alpha: 0.4), size: 20),
        filled: true,
        fillColor: const Color(0xFF1E293B),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF26A69A)),
        ),
      );

  /// D-pad escape handler for a search field: arrow-up at start or arrow-down
  /// at end (or when empty) unfocuses the field so the remote can move on;
  /// arrow-right jumps to the clear button when present. Mirrors the RD/Torbox
  /// downloads pages so the field isn't a D-pad trap.
  void _moveFocusTo(FocusNode? target, FocusNode field) {
    // Move focus to [target] if it's mounted; otherwise just release the field
    // so the remote can traverse onward.
    if (target != null && target.context != null) {
      target.requestFocus();
    } else {
      field.unfocus();
    }
  }

  KeyEventResult _searchFieldKey(
    KeyEvent event,
    TextEditingController controller,
    FocusNode fieldFocusNode, {
    FocusNode? clearFocusNode,
    FocusNode? upTarget,
    FocusNode? downTarget,
  }) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final textLength = controller.text.length;
    final selection = controller.selection;
    final isTextEmpty = textLength == 0;
    final isSelectionValid = selection.isValid && selection.baseOffset >= 0;
    final isAtStart = !isSelectionValid ||
        (selection.baseOffset == 0 && selection.extentOffset == 0);
    final isAtEnd = !isSelectionValid ||
        (selection.baseOffset == textLength &&
            selection.extentOffset == textLength);

    // Up at start (or empty) → toolbar; Down at end (or empty) → results.
    if (key == LogicalKeyboardKey.arrowUp && (isTextEmpty || isAtStart)) {
      _moveFocusTo(upTarget, fieldFocusNode);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown && (isTextEmpty || isAtEnd)) {
      _moveFocusTo(downTarget, fieldFocusNode);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight &&
        clearFocusNode != null &&
        !isTextEmpty &&
        isAtEnd) {
      clearFocusNode.requestFocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget _buildSearchBar() {
    final hasText = _searchController.text.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        children: [
          Expanded(
            child: Focus(
              onKeyEvent: (node, event) => _searchFieldKey(
                event,
                _searchController,
                _searchFocusNode,
                clearFocusNode: hasText ? _searchClearFocusNode : null,
                upTarget: _toolbarSearchFocusNode,
                downTarget: _firstItemFocusNode,
              ),
              child: TextField(
                controller: _searchController,
                focusNode: _searchFocusNode,
                textInputAction: TextInputAction.search,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                onChanged: (v) => setState(() => _searchQuery = v),
                onSubmitted: (_) => _searchFocusNode.unfocus(),
                decoration: _searchDecoration('Search your magnets...'),
              ),
            ),
          ),
          if (hasText)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Focus(
                focusNode: _searchClearFocusNode,
                onKeyEvent: (node, event) {
                  if (event is! KeyDownEvent) return KeyEventResult.ignored;
                  final key = event.logicalKey;
                  if (key == LogicalKeyboardKey.select ||
                      key == LogicalKeyboardKey.enter) {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                    _searchFocusNode.requestFocus();
                    return KeyEventResult.handled;
                  }
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
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                          _searchFocusNode.requestFocus();
                        },
                        icon: Icon(Icons.clear_rounded,
                            color: Colors.white.withValues(alpha: 0.4),
                            size: 18),
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

  Widget _buildFileSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Focus(
        onKeyEvent: (node, event) =>
            _searchFieldKey(
          event,
          _fileSearchController,
          _fileSearchFocusNode,
          upTarget: _backButtonFocusNode,
          downTarget: _firstItemFocusNode,
        ),
        child: TextField(
          controller: _fileSearchController,
          focusNode: _fileSearchFocusNode,
          textInputAction: TextInputAction.search,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          onChanged: (v) => setState(() => _fileSearchQuery = v),
          onSubmitted: (_) => _fileSearchFocusNode.unfocus(),
          decoration: _searchDecoration('Search files...'),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, size: 48, color: Colors.white38),
              const SizedBox(height: 16),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }
    if (!_isAtRoot) {
      return _buildFilesView();
    }
    return _buildMagnetsView();
  }

  Widget _buildMagnetsView() {
    final magnets = _visibleMagnets;
    if (magnets.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          children: [
            const SizedBox(height: 120),
            Center(
              child: Text(
                _searchQuery.isNotEmpty
                    ? 'No magnets match your search.'
                    : 'Your AllDebrid library is empty.',
                style: const TextStyle(color: Colors.white54),
              ),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.all(16),
        itemCount: magnets.length,
        itemBuilder: (context, index) {
          return KeyedSubtree(
            key: ValueKey(magnets[index].id),
            child: _buildMagnetCard(magnets[index], index),
          );
        },
      ),
    );
  }

  Widget _buildMagnetCard(AllDebridMagnet m, int index) {
    final theme = Theme.of(context);
    final isSelected = _selectedIds.contains(m.id);
    final statusLine = m.isReady
        ? Formatters.formatFileSize(m.size)
        : m.isError
            ? 'Failed'
            : 'Downloading ${m.progressPercent}%';

    return TvFocusScrollWrapper(
      child: GestureDetector(
        onTap: _selectionMode ? () => _toggleSelection(m.id) : null,
        child: Card(
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: _selectionMode && isSelected
                ? BorderSide(color: theme.colorScheme.primary, width: 2)
                : BorderSide.none,
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (_selectionMode) ...[
                      Checkbox(
                        value: isSelected,
                        onChanged: (_) => _toggleSelection(m.id),
                      ),
                      const SizedBox(width: 4),
                    ],
                    Icon(
                      m.isError ? Icons.error_outline : Icons.folder,
                      color: m.isError ? Colors.red : Colors.amber,
                      size: 32,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            m.name.isEmpty ? '(unnamed)' : m.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.w500,
                              fontSize: 16,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            statusLine,
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
                if (!_selectionMode) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      if (m.isReady) ...[
                        Expanded(
                          child: _buildActionButton(
                            focusNode: index == 0 ? _firstItemFocusNode : null,
                            icon: Icons.folder_open,
                            label: 'Open',
                            color: const Color(0xFF8B5CF6),
                            onTap: () => _openMagnet(m),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildActionButton(
                            icon: Icons.play_arrow_rounded,
                            label: 'Play',
                            color: const Color(0xFF22C55E),
                            onTap: () => _playMagnet(m),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ] else
                        const Spacer(),
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert),
                        tooltip: 'More options',
                        onSelected: (value) {
                          switch (value) {
                            case 'open':
                              _openMagnet(m);
                              break;
                            case 'play':
                              _playMagnet(m);
                              break;
                            case 'download':
                              _downloadMagnet(m);
                              break;
                            case 'delete':
                              _deleteMagnets([m]);
                              break;
                          }
                        },
                        itemBuilder: (ctx) => [
                          if (m.isReady)
                            const PopupMenuItem(
                              value: 'open',
                              child: Row(children: [
                                Icon(Icons.folder_open,
                                    size: 18, color: Colors.blue),
                                SizedBox(width: 12),
                                Text('Open'),
                              ]),
                            ),
                          if (m.isReady)
                            const PopupMenuItem(
                              value: 'download',
                              child: Row(children: [
                                Icon(Icons.download,
                                    size: 18, color: Colors.green),
                                SizedBox(width: 12),
                                Text('Download to device'),
                              ]),
                            ),
                          const PopupMenuItem(
                            value: 'delete',
                            child: Row(children: [
                              Icon(Icons.delete_outline,
                                  size: 18, color: Colors.red),
                              SizedBox(width: 12),
                              Text('Delete'),
                            ]),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFilesView() {
    if (_loadingFiles) {
      return const Center(child: CircularProgressIndicator());
    }
    final files = _visibleFiles;
    if (files.isEmpty) {
      return Center(
        child: Text(
          _fileSearchQuery.isNotEmpty
              ? 'No files match your search.'
              : 'No files in this magnet.',
          style: const TextStyle(color: Colors.white54),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: files.length,
      itemBuilder: (context, index) {
        return KeyedSubtree(
          key: ValueKey('${_currentMagnet!.id}:${files[index].path}:$index'),
          child: _buildFileCard(files[index], index),
        );
      },
    );
  }

  Widget _buildFileCard(AllDebridFile f, int index) {
    final isVideo = _looksLikeVideo(f);
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
                    isVideo
                        ? Icons.play_circle_outline
                        : Icons.insert_drive_file,
                    color: isVideo ? Colors.blue : Colors.grey,
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          f.fileName,
                          style: const TextStyle(
                            fontWeight: FontWeight.w500,
                            fontSize: 16,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          Formatters.formatFileSize(f.size),
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
                  if (isVideo)
                    Expanded(
                      child: _buildActionButton(
                        focusNode: index == 0 ? _firstItemFocusNode : null,
                        icon: Icons.play_arrow_rounded,
                        label: 'Play',
                        color: const Color(0xFF22C55E),
                        onTap: () => _playFile(f),
                      ),
                    )
                  else
                    Expanded(
                      child: _buildActionButton(
                        focusNode: index == 0 ? _firstItemFocusNode : null,
                        icon: Icons.download_rounded,
                        label: 'Download',
                        color: const Color(0xFF3B82F6),
                        onTap: () => _downloadFile(f),
                      ),
                    ),
                  const SizedBox(width: 8),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert),
                    tooltip: 'More options',
                    onSelected: (value) {
                      if (value == 'download') _downloadFile(f);
                    },
                    itemBuilder: (ctx) => [
                      const PopupMenuItem(
                        value: 'download',
                        child: Row(children: [
                          Icon(Icons.download, size: 18, color: Colors.green),
                          SizedBox(width: 12),
                          Text('Download'),
                        ]),
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

  /// Pill action button matching the Torbox/RD downloads pages: a focusable
  /// container that fills with [color] and glows when focused (TV/D-pad).
  Widget _buildActionButton({
    FocusNode? focusNode,
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Focus(
      focusNode: focusNode,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.select ||
                event.logicalKey == LogicalKeyboardKey.enter)) {
          onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (context) {
          final isFocused = Focus.of(context).hasFocus;
          return GestureDetector(
            onTap: onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: isFocused ? color : Colors.black.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isFocused ? color : color.withValues(alpha: 0.6),
                  width: isFocused ? 1.5 : 1,
                ),
                boxShadow: isFocused
                    ? [
                        BoxShadow(
                          color: color.withValues(alpha: 0.4),
                          blurRadius: 12,
                        ),
                      ]
                    : null,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    icon,
                    size: 16,
                    color: isFocused
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.9),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: TextStyle(
                      color: isFocused
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.9),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
