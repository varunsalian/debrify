import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../screens/video_player_screen.dart'; // re-exports PlaylistEntry
import '../../services/premiumize_service.dart';
import '../../services/storage_service.dart';
import '../../services/download_service.dart';
import '../../services/video_player_launcher.dart';
import '../../services/main_page_bridge.dart';
import '../../models/premiumize_folder_item.dart';
import '../../models/premiumize_transfer.dart';
import '../../utils/file_utils.dart';
import '../../utils/formatters.dart';
import '../../utils/series_parser.dart';
import '../../widgets/file_selection_dialog.dart';
import '../debrify_tv/widgets/tv_focus_scroll_wrapper.dart';
import '../../utils/tv_keys.dart';

/// Cloud-library browser for Premiumize, mirroring the Torbox/PikPak navigation
/// pages. Premiumize's cloud is a real server-side folder hierarchy, so this
/// browses folders by id (like PikPak) and additionally exposes a Transfers
/// view (Premiumize's queued/running magnet transfers).
class PremiumizeFilesScreen extends StatefulWidget {
  final String? initialFolderId;
  final String? initialFolderName;

  /// When true, this screen was pushed as a route (not displayed in a tab).
  /// Back navigation pops the route instead of switching tabs.
  final bool isPushedRoute;

  const PremiumizeFilesScreen({
    super.key,
    this.initialFolderId,
    this.initialFolderName,
    this.isPushedRoute = false,
  });

  @override
  State<PremiumizeFilesScreen> createState() => _PremiumizeFilesScreenState();
}

enum _FolderViewMode { raw, sortedAZ }

enum _PremiumizeView { files, transfers }

class _PremiumizeFilesScreenState extends State<PremiumizeFilesScreen> {
  final ScrollController _scrollController = ScrollController();

  // Premiumize tab index in main.dart's page list (for TV focus + back handler).
  static const int _tabIndex = 11;

  String? _apiKey;
  bool _premiumizeEnabled = false;

  bool _isLoading = false;
  bool _initialLoad = true;
  String _errorMessage = '';

  // Active view (cloud files vs transfers).
  _PremiumizeView _selectedView = _PremiumizeView.files;

  // Cloud files state.
  final List<PremiumizeFolderItem> _items = [];

  // Transfers state.
  final List<PremiumizeTransfer> _transfers = [];
  bool _isLoadingTransfers = false;

  // Folder navigation state (server-side, by id).
  String? _currentFolderId; // null = root
  String _currentFolderName = 'My Files';
  final List<({String? id, String name})> _navigationStack = [];

  // Per-folder view-mode persistence during this session.
  final Map<String, _FolderViewMode> _folderViewModes = {};

  // TV content focus handler (stored for proper unregistration).
  VoidCallback? _tvContentFocusHandler;
  bool _shouldFocusOnLoad = false;

  // Add-link state.
  final TextEditingController _linkController = TextEditingController();
  bool _isAddingLink = false;

  // Multi-select state.
  bool _isSelectionMode = false;
  final Set<String> _selectedIds = {};
  bool get _isAllSelected =>
      _selectedIds.length == _items.length && _items.isNotEmpty;

  // Search state. At root this runs a server-side cloud search (debounced);
  // inside a folder it filters the currently-loaded items locally.
  bool _isSearchActive = false;
  bool _isSearching = false; // a cloud search request is in flight
  Timer? _searchDebounce;
  final TextEditingController _searchController = TextEditingController();
  List<PremiumizeFolderItem> _searchResults = [];

  // Focus nodes for TV/D-pad navigation.
  final FocusNode _refreshButtonFocusNode =
      FocusNode(debugLabel: 'pm-refresh');
  final FocusNode _backButtonFocusNode = FocusNode(debugLabel: 'pm-back');
  final FocusNode _retryButtonFocusNode = FocusNode(debugLabel: 'pm-retry');
  final FocusNode _settingsButtonFocusNode = FocusNode(debugLabel: 'pm-settings');
  final FocusNode _viewModeDropdownFocusNode =
      FocusNode(debugLabel: 'pm-view-mode');
  final FocusNode _addLinkButtonFocusNode = FocusNode(debugLabel: 'pm-add-link');
  final FocusNode _firstItemFocusNode = FocusNode(debugLabel: 'pm-first-item');
  final FocusNode _deleteButtonFocusNode = FocusNode(debugLabel: 'pm-delete-btn');
  final FocusNode _searchFocusNode = FocusNode(debugLabel: 'pm-search');
  final FocusNode _searchButtonFocusNode =
      FocusNode(debugLabel: 'pm-search-button');
  final FocusNode _searchClearFocusNode =
      FocusNode(debugLabel: 'pm-search-clear');

  bool get _isAtRoot => _currentFolderId == null;

  @override
  void initState() {
    super.initState();
    _loadSettings();

    if (widget.isPushedRoute) {
      MainPageBridge.pushRouteBackHandler(_handleBackNavigation);
    } else {
      MainPageBridge.registerTabBackHandler('premiumize', _handleBackNavigation);
      _tvContentFocusHandler = () {
        _shouldFocusOnLoad = true;
        _focusFirstItemOrFallback();
      };
      MainPageBridge.registerTvContentFocusHandler(
        _tabIndex,
        _tvContentFocusHandler!,
      );
    }
  }

  @override
  void dispose() {
    if (widget.isPushedRoute) {
      MainPageBridge.popRouteBackHandler(_handleBackNavigation);
    } else {
      MainPageBridge.unregisterTabBackHandler('premiumize');
      if (_tvContentFocusHandler != null) {
        MainPageBridge.unregisterTvContentFocusHandler(
          _tabIndex,
          _tvContentFocusHandler!,
        );
      }
    }
    _searchDebounce?.cancel();
    _scrollController.dispose();
    _linkController.dispose();
    _searchController.dispose();
    _refreshButtonFocusNode.dispose();
    _backButtonFocusNode.dispose();
    _retryButtonFocusNode.dispose();
    _settingsButtonFocusNode.dispose();
    _viewModeDropdownFocusNode.dispose();
    _addLinkButtonFocusNode.dispose();
    _firstItemFocusNode.dispose();
    _deleteButtonFocusNode.dispose();
    _searchFocusNode.dispose();
    _searchButtonFocusNode.dispose();
    _searchClearFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final enabled = await StorageService.getPremiumizeIntegrationEnabled();
    final apiKey = await StorageService.getPremiumizeApiKey();

    if (!mounted) return;
    setState(() {
      _premiumizeEnabled = enabled && apiKey != null && apiKey.isNotEmpty;
      _apiKey = apiKey;
      if (widget.initialFolderId != null && widget.initialFolderName != null) {
        _currentFolderId = widget.initialFolderId;
        _currentFolderName = widget.initialFolderName!;
      }
    });

    if (_premiumizeEnabled) {
      _loadFolder();
    } else {
      setState(() => _initialLoad = false);
    }
  }

  // ── Loading ──────────────────────────────────────────────────────────────

  Future<void> _loadFolder() async {
    final apiKey = _apiKey;
    if (apiKey == null || apiKey.isEmpty || _isLoading) return;

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final listing =
          await PremiumizeService.listFolder(apiKey, folderId: _currentFolderId);
      if (!mounted) return;

      final mode = _getCurrentViewMode();
      final ordered = _applyViewMode(mode, listing.items);

      setState(() {
        _items
          ..clear()
          ..addAll(ordered);
        _isLoading = false;
        _initialLoad = false;
      });
      _focusFirstItemOrFallback();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
        _initialLoad = false;
      });
    }
  }

  Future<void> _loadTransfers() async {
    final apiKey = _apiKey;
    if (apiKey == null || apiKey.isEmpty || _isLoadingTransfers) return;

    setState(() {
      _isLoadingTransfers = true;
      _errorMessage = '';
    });

    try {
      final transfers = await PremiumizeService.listTransfers(apiKey);
      if (!mounted) return;
      setState(() {
        _transfers
          ..clear()
          ..addAll(transfers);
        _isLoadingTransfers = false;
        _initialLoad = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString();
        _isLoadingTransfers = false;
        _initialLoad = false;
      });
    }
  }

  Future<void> _refresh() async {
    _exitSelectionMode();
    if (_selectedView == _PremiumizeView.transfers) {
      await _loadTransfers();
    } else {
      await _loadFolder();
    }
  }

  void _switchView(_PremiumizeView view) {
    if (_selectedView == view) return;
    _exitSelectionMode();
    setState(() {
      _selectedView = view;
      _errorMessage = '';
    });
    if (view == _PremiumizeView.transfers) {
      _loadTransfers();
    } else {
      _loadFolder();
    }
  }

  // ── Folder navigation ──────────────────────────────────────────────────────

  void _navigateIntoFolder(PremiumizeFolderItem folder) {
    _exitSelectionMode();
    _shouldFocusOnLoad = true;
    setState(() {
      _navigationStack
          .add((id: _currentFolderId, name: _currentFolderName));
      _currentFolderId = folder.id;
      _currentFolderName = folder.name;
      _isSearchActive = false;
      _searchController.clear();
      _searchResults = [];
    });
    _loadFolder();
  }

  void _navigateUp() {
    _exitSelectionMode();
    if (_navigationStack.isEmpty) return;
    setState(() {
      final previous = _navigationStack.removeLast();
      _currentFolderId = previous.id;
      _currentFolderName = previous.name;
    });
    _loadFolder();
  }

  bool _handleBackNavigation() {
    if (_isSelectionMode) {
      _exitSelectionMode();
      return true;
    }
    if (_isSearchActive) {
      _toggleSearch();
      return true;
    }
    if (_navigationStack.isNotEmpty) {
      _navigateUp();
      return true;
    }
    // At this folder's root (no deeper stack). If opened as a pushed route
    // (e.g. deep-linked into a specific folder), pop back to the caller.
    if (widget.isPushedRoute) {
      Navigator.of(context).pop();
      return true;
    }
    if (MainPageBridge.returnToTorrentSearchOnBack) {
      MainPageBridge.returnToTorrentSearchOnBack = false;
      MainPageBridge.switchTab?.call(0);
      return true;
    }
    return false;
  }

  // ── View modes ─────────────────────────────────────────────────────────────

  _FolderViewMode _getCurrentViewMode() {
    if (_isAtRoot) return _FolderViewMode.raw;
    return _folderViewModes[_currentFolderId!] ?? _FolderViewMode.raw;
  }

  void _setViewMode(_FolderViewMode mode) {
    if (_isAtRoot) return;
    setState(() {
      _folderViewModes[_currentFolderId!] = mode;
      final reordered = _applyViewMode(mode, _items);
      _items
        ..clear()
        ..addAll(reordered);
    });
  }

  List<PremiumizeFolderItem> _applyViewMode(
    _FolderViewMode mode,
    List<PremiumizeFolderItem> items,
  ) {
    if (mode == _FolderViewMode.raw) return List.of(items);
    return _applySortedView(items);
  }

  List<PremiumizeFolderItem> _applySortedView(
    List<PremiumizeFolderItem> items,
  ) {
    final folders = items.where((i) => i.isFolder).toList();
    final files = items.where((i) => !i.isFolder).toList();

    int cmp(String a, String b, {bool seasonAware = false}) {
      final aNum = seasonAware ? _extractSeasonNumber(a) : _extractLeadingNumber(a);
      final bNum = seasonAware ? _extractSeasonNumber(b) : _extractLeadingNumber(b);
      if (aNum != null && bNum != null) return aNum.compareTo(bNum);
      if (aNum != null) return -1;
      if (bNum != null) return 1;
      return a.toLowerCase().compareTo(b.toLowerCase());
    }

    folders.sort((a, b) => cmp(a.name, b.name, seasonAware: true));
    files.sort((a, b) => cmp(a.name, b.name));
    return [...folders, ...files];
  }

  int? _extractSeasonNumber(String name) {
    final patterns = [
      RegExp(r'^(\d+)[\s._-]'),
      RegExp(r'season[\s_-]*(\d+)', caseSensitive: false),
      RegExp(r'chapter[\s_-]*(\d+)', caseSensitive: false),
      RegExp(r'episode[\s_-]*(\d+)', caseSensitive: false),
      RegExp(r'part[\s_-]*(\d+)', caseSensitive: false),
      RegExp(r'^[a-z]+[\s_-]*(\d+)', caseSensitive: false),
    ];
    final lower = name.toLowerCase();
    for (final p in patterns) {
      final m = p.firstMatch(lower);
      if (m != null && m.groupCount >= 1) return int.tryParse(m.group(1)!);
    }
    return null;
  }

  int? _extractLeadingNumber(String name) {
    final m = RegExp(r'^(\d+)[\s._-]').firstMatch(name);
    if (m != null && m.groupCount >= 1) return int.tryParse(m.group(1)!);
    return null;
  }

  // ── Search ─────────────────────────────────────────────────────────────────

  void _toggleSearch() {
    setState(() {
      _isSearchActive = !_isSearchActive;
      if (!_isSearchActive) {
        _searchDebounce?.cancel();
        _searchController.clear();
        _searchResults = [];
        _isSearching = false;
      } else {
        // Search and multi-select are mutually exclusive: selection bar actions
        // operate on _items, not search results.
        _isSelectionMode = false;
        _selectedIds.clear();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _searchFocusNode.requestFocus();
        });
      }
    });
  }

  void _performSearch(String query) {
    final q = query.trim();
    if (q.isEmpty) {
      _searchDebounce?.cancel();
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
      return;
    }

    // Root: server-side cloud search (recursive), debounced to limit calls.
    if (_isAtRoot) {
      _searchDebounce?.cancel();
      setState(() => _isSearching = true);
      _searchDebounce =
          Timer(const Duration(milliseconds: 350), () => _runCloudSearch(q));
      return;
    }

    // Inside a folder: filter the currently-loaded items locally.
    final lower = q.toLowerCase();
    setState(() {
      _isSearching = false;
      _searchResults = _items
          .where((i) => !i.isFolder && i.name.toLowerCase().contains(lower))
          .toList();
    });
  }

  Future<void> _runCloudSearch(String query) async {
    final apiKey = _apiKey;
    if (apiKey == null || apiKey.isEmpty) return;
    try {
      final results = await PremiumizeService.searchCloud(apiKey, query);
      if (!mounted) return;
      // Drop stale results if the query changed while the request was in flight.
      if (_searchController.text.trim() != query) return;
      setState(() {
        _searchResults = results;
        _isSearching = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSearching = false);
      _showSnackBar('Search failed: $e', isError: true);
    }
  }

  // ── Playback ───────────────────────────────────────────────────────────────

  Future<void> _playFile(PremiumizeFolderItem file) async {
    String? url = file.playableUrl;
    // Search hits (folder/search) may omit the direct link — resolve by id.
    if ((url == null || url.isEmpty) &&
        _apiKey != null &&
        _apiKey!.isNotEmpty) {
      final resolved = await PremiumizeService.resolveItemById(_apiKey!, file.id);
      url = resolved?.link;
    }
    if (url == null || url.isEmpty) {
      _showSnackBar('No playable URL for this file', isError: true);
      return;
    }
    final sizeBytes = file.size > 0 ? file.size : null;
    if (!mounted) return;
    MainPageBridge.notifyPlayerLaunching();
    await VideoPlayerLauncher.push(
      context,
      VideoPlayerLaunchArgs(
        videoUrl: url,
        title: file.name,
        subtitle: sizeBytes != null ? Formatters.formatFileSize(sizeBytes) : null,
        playlist: [
          PlaylistEntry(
            url: url,
            title: file.name,
            relativePath: file.relativePath ?? file.name,
            provider: 'premiumize',
            premiumizeItemId: file.id,
            sizeBytes: sizeBytes,
          ),
        ],
        startIndex: 0,
      ),
    );
  }

  Future<void> _playFolder(PremiumizeFolderItem folder) async {
    final apiKey = _apiKey;
    if (apiKey == null || apiKey.isEmpty) return;

    _showLoadingDialog('Scanning folder for videos...');
    try {
      final all =
          await PremiumizeService.listFolderRecursive(apiKey, folder.id);
      _dismissDialog();
      if (!mounted) return;

      final videos = all.where((f) => f.isVideo).toList();
      if (videos.isEmpty) {
        _showSnackBar('This folder doesn\'t contain any videos', isError: true);
        return;
      }
      await _playPremiumizeVideos(videos, folder.name);
    } catch (e) {
      _dismissDialog();
      _showSnackBar('Failed to scan folder: $e', isError: true);
    }
  }

  Future<void> _playPremiumizeVideos(
    List<PremiumizeFolderItem> videos,
    String collectionName,
  ) async {
    if (videos.isEmpty) return;

    // Single video.
    if (videos.length == 1) {
      final v = videos.first;
      final url = v.playableUrl;
      if (url == null || url.isEmpty) {
        _showSnackBar('No playable URL for this file', isError: true);
        return;
      }
      final sizeBytes = v.size > 0 ? v.size : null;
      if (!mounted) return;
      MainPageBridge.notifyPlayerLaunching();
      await VideoPlayerLauncher.push(
        context,
        VideoPlayerLaunchArgs(
          videoUrl: url,
          title: v.name,
          subtitle:
              sizeBytes != null ? Formatters.formatFileSize(sizeBytes) : null,
          playlist: [
            PlaylistEntry(
              url: url,
              title: v.name,
              relativePath: v.relativePath ?? v.name,
              provider: 'premiumize',
              premiumizeItemId: v.id,
              sizeBytes: sizeBytes,
            ),
          ],
          startIndex: 0,
        ),
      );
      return;
    }

    // Collection.
    final infos =
        videos.map((v) => SeriesParser.parseFilename(v.name)).toList();
    final filenames = videos.map((v) => v.name).toList();
    final bool isSeries =
        videos.length > 1 && SeriesParser.isSeriesPlaylist(filenames);

    final indexed = List.generate(videos.length, (i) => i);
    if (isSeries) {
      indexed.sort((a, b) {
        final sa = infos[a].season ?? 0, sb = infos[b].season ?? 0;
        if (sa != sb) return sa.compareTo(sb);
        final ea = infos[a].episode ?? 0, eb = infos[b].episode ?? 0;
        if (ea != eb) return ea.compareTo(eb);
        return videos[a].name.toLowerCase().compareTo(videos[b].name.toLowerCase());
      });
    } else {
      indexed.sort(
        (a, b) => videos[a].name.toLowerCase().compareTo(
              videos[b].name.toLowerCase(),
            ),
      );
    }

    final sortedVideos = [for (final i in indexed) videos[i]];
    final sortedInfos = [for (final i in indexed) infos[i]];

    int startIndex = isSeries ? _findFirstEpisodeIndex(sortedInfos) : 0;
    if (startIndex < 0 || startIndex >= sortedVideos.length) startIndex = 0;

    final entries = <PlaylistEntry>[];
    for (int i = 0; i < sortedVideos.length; i++) {
      final v = sortedVideos[i];
      final info = sortedInfos[i];
      final episodeLabel = _formatPlaylistTitle(
        info: info,
        fallback: v.name,
        isSeriesCollection: isSeries,
      );
      final title = _composeEntryTitle(
        seriesTitle: info.title,
        episodeLabel: episodeLabel,
        isSeriesCollection: isSeries,
        fallback: v.name,
      );
      entries.add(
        PlaylistEntry(
          // folder/list already returns direct links, so fill all up front.
          url: v.playableUrl ?? '',
          title: title,
          relativePath: v.relativePath ?? v.name,
          provider: 'premiumize',
          premiumizeItemId: v.id,
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
        videoUrl: entries[startIndex].url,
        title: collectionName,
        subtitle: subtitle,
        playlist: entries,
        startIndex: startIndex,
      ),
    );
  }

  // ── Download ───────────────────────────────────────────────────────────────

  Future<void> _downloadFile(PremiumizeFolderItem file) async {
    final url = file.link;
    if (url == null || url.isEmpty) {
      _showSnackBar('No download URL for this file', isError: true);
      return;
    }
    try {
      await DownloadService.instance.enqueueDownload(
        url: url,
        fileName: file.name,
        context: mounted ? context : null,
      );
      _showSnackBar('Download queued: ${file.name}', isError: false);
    } catch (e) {
      _showSnackBar('Failed to download: $e', isError: true);
    }
  }

  Future<void> _downloadFolder(PremiumizeFolderItem folder) async {
    final apiKey = _apiKey;
    if (apiKey == null || apiKey.isEmpty) return;

    _showLoadingDialog('Scanning folder for files...');
    try {
      final all =
          await PremiumizeService.listFolderRecursive(apiKey, folder.id);
      _dismissDialog();
      if (!mounted) return;

      final files = all.where((f) => !f.isFolder).toList();
      if (files.isEmpty) {
        _showSnackBar('This folder doesn\'t contain any files', isError: true);
        return;
      }

      final dialogFiles = <Map<String, dynamic>>[];
      for (int i = 0; i < files.length; i++) {
        dialogFiles.add({
          'name': files[i].relativePath ?? files[i].name,
          '_fullPath': files[i].relativePath ?? files[i].name,
          'size': files[i].size.toString(),
          '_premiumizeIndex': i,
        });
      }

      await showDialog(
        context: context,
        builder: (context) => FileSelectionDialog(
          files: dialogFiles,
          torrentName: folder.name,
          onDownload: (selected) =>
              _downloadSelectedFiles(selected, files, folder.name),
        ),
      );
    } catch (e) {
      _dismissDialog();
      _showSnackBar('Failed to scan folder: $e', isError: true);
    }
  }

  Future<void> _downloadSelectedFiles(
    List<Map<String, dynamic>> selected,
    List<PremiumizeFolderItem> allFiles,
    String folderName,
  ) async {
    if (selected.isEmpty) return;
    int success = 0, fail = 0;
    for (final f in selected) {
      try {
        final idx = f['_premiumizeIndex'] as int? ?? -1;
        if (idx < 0 || idx >= allFiles.length) {
          fail++;
          continue;
        }
        final target = allFiles[idx];
        final url = target.link;
        if (url == null || url.isEmpty) {
          fail++;
          continue;
        }
        await DownloadService.instance.enqueueDownload(
          url: url,
          fileName: target.name,
          torrentName: folderName,
          context: mounted ? context : null,
        );
        success++;
      } catch (_) {
        fail++;
      }
    }
    if (!mounted) return;
    if (success > 0 && fail == 0) {
      _showSnackBar('Queued $success file${success == 1 ? '' : 's'}',
          isError: false);
    } else if (success > 0) {
      _showSnackBar('Queued $success, $fail failed', isError: true);
    } else {
      _showSnackBar('Failed to queue any files', isError: true);
    }
  }

  // ── Add to playlist ──────────────────────────────────────────────────────────

  Future<void> _addToPlaylist(PremiumizeFolderItem item) async {
    if (item.isFolder) {
      await _addFolderToPlaylist(item);
    } else {
      await _addFileToPlaylist(item);
    }
  }

  Future<void> _addFileToPlaylist(PremiumizeFolderItem file) async {
    if (!file.isVideo) {
      _showSnackBar('Only video files can be added to playlist', isError: true);
      return;
    }
    final added = await StorageService.addPlaylistItemRaw({
      'provider': 'premiumize',
      'title': FileUtils.cleanPlaylistTitle(file.name),
      'kind': 'single',
      'premiumizeItemId': file.id,
      'premiumizeFile': {
        'id': file.id,
        'name': file.name,
        'size': file.size,
      },
      'sizeBytes': file.size > 0 ? file.size : null,
    });
    _showSnackBar(added ? 'Added to playlist' : 'Already in playlist',
        isError: !added);
  }

  Future<void> _addFolderToPlaylist(PremiumizeFolderItem folder) async {
    final apiKey = _apiKey;
    if (apiKey == null || apiKey.isEmpty) return;

    _showLoadingDialog('Scanning folder for videos...');
    try {
      final all =
          await PremiumizeService.listFolderRecursive(apiKey, folder.id);
      _dismissDialog();
      if (!mounted) return;

      final videos = all.where((f) => f.isVideo).toList();
      if (videos.isEmpty) {
        _showSnackBar('This folder doesn\'t contain any videos', isError: true);
        return;
      }

      if (videos.length == 1) {
        final v = videos.first;
        final added = await StorageService.addPlaylistItemRaw({
          'provider': 'premiumize',
          'title': FileUtils.cleanPlaylistTitle(v.name),
          'kind': 'single',
          'premiumizeItemId': v.id,
          'premiumizeFile': {'id': v.id, 'name': v.name, 'size': v.size},
          'sizeBytes': v.size > 0 ? v.size : null,
        });
        _showSnackBar(added ? 'Added to playlist' : 'Already in playlist',
            isError: !added);
        return;
      }

      final fileIds = videos.map((v) => v.id).toList();
      final filesMeta = videos
          .map((v) => {'id': v.id, 'name': v.name, 'size': v.size})
          .toList();
      final added = await StorageService.addPlaylistItemRaw({
        'provider': 'premiumize',
        'title': FileUtils.cleanPlaylistTitle(folder.name),
        'kind': 'collection',
        'premiumizeItemId': folder.id,
        'premiumizeFiles': filesMeta,
        'premiumizeItemIds': fileIds,
        'count': videos.length,
      });
      _showSnackBar(
        added
            ? 'Added ${videos.length} videos to playlist'
            : 'Already in playlist',
        isError: !added,
      );
    } catch (e) {
      _dismissDialog();
      _showSnackBar('Failed to scan folder: $e', isError: true);
    }
  }

  // ── Delete ─────────────────────────────────────────────────────────────────

  void _showDeleteDialog(PremiumizeFolderItem item) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${item.isFolder ? 'Folder' : 'File'}'),
        content: Text(
          'Permanently delete "${item.name}"? This cannot be undone.',
        ),
        actions: [
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () {
              Navigator.of(context).pop();
              _executeDelete([item]);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Future<void> _handleDeleteSelected() async {
    if (_selectedIds.isEmpty) return;
    final selected =
        _items.where((i) => _selectedIds.contains(i.id)).toList();
    final count = selected.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete $count item${count == 1 ? '' : 's'}'),
        content: Text(
          'Permanently delete $count selected item${count == 1 ? '' : 's'}? '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _executeDelete(selected);
    }
  }

  Future<void> _executeDelete(List<PremiumizeFolderItem> items) async {
    final apiKey = _apiKey;
    if (apiKey == null || apiKey.isEmpty) return;

    _showSnackBar(
      'Deleting ${items.length} item${items.length == 1 ? '' : 's'}...',
      isError: false,
    );
    final deletedIds = <String>{};
    int fail = 0;
    for (final item in items) {
      try {
        if (item.isFolder) {
          await PremiumizeService.deleteFolder(apiKey, item.id);
        } else {
          await PremiumizeService.deleteItem(apiKey, item.id);
        }
        deletedIds.add(item.id);
      } catch (_) {
        fail++;
      }
    }
    if (!mounted) return;
    setState(() {
      _items.removeWhere((i) => deletedIds.contains(i.id));
      _searchResults.removeWhere((i) => deletedIds.contains(i.id));
      _selectedIds.clear();
      _isSelectionMode = false;
    });
    if (fail == 0) {
      _showSnackBar(
        'Deleted ${deletedIds.length} item${deletedIds.length == 1 ? '' : 's'}',
        isError: false,
      );
    } else {
      _showSnackBar('Deleted ${deletedIds.length}, $fail failed',
          isError: true);
    }
  }

  // ── Transfers ────────────────────────────────────────────────────────────────

  Future<void> _deleteTransfer(PremiumizeTransfer transfer) async {
    final apiKey = _apiKey;
    if (apiKey == null || apiKey.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Transfer'),
        content: Text('Remove "${transfer.name}" from your transfers?'),
        actions: [
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await PremiumizeService.deleteTransfer(apiKey, transfer.id);
      if (!mounted) return;
      setState(() => _transfers.removeWhere((t) => t.id == transfer.id));
      _showSnackBar('Transfer removed', isError: false);
    } catch (e) {
      _showSnackBar('Failed to remove transfer: $e', isError: true);
    }
  }

  Future<void> _clearFinishedTransfers() async {
    final apiKey = _apiKey;
    if (apiKey == null || apiKey.isEmpty) return;
    try {
      await PremiumizeService.clearFinishedTransfers(apiKey);
      _showSnackBar('Cleared finished transfers', isError: false);
      await _loadTransfers();
    } catch (e) {
      _showSnackBar('Failed to clear: $e', isError: true);
    }
  }

  // ── Add link ───────────────────────────────────────────────────────────────

  Future<void> _showAddLinkDialog() async {
    await _autoPasteLink();
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Add to Premiumize',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter a magnet or link to add to your cloud:',
              style: TextStyle(color: Colors.grey, fontSize: 14),
            ),
            const SizedBox(height: 12),
            Focus(
              // D-pad: let arrow-down move focus out of the field to the buttons.
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
                  hintText: 'magnet:?xt=... or https://...',
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
                    borderSide: const BorderSide(color: Color(0xFFFB923C)),
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
                maxLines: 3,
                minLines: 1,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Adding to cloud spends fair-use points (~1pt/GB).',
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              _linkController.clear();
              Navigator.of(context).pop();
            },
            child: const Text('Cancel'),
          ),
          FilledButton(
            style:
                FilledButton.styleFrom(backgroundColor: const Color(0xFFFB923C)),
            onPressed: _isAddingLink ? null : _addLink,
            child: const Text('Add', style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );
  }

  Future<void> _autoPasteLink() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text?.trim();
      if (text != null &&
          (text.startsWith('http://') ||
              text.startsWith('https://') ||
              text.startsWith('magnet:'))) {
        _linkController.text = text;
      }
    } catch (_) {}
  }

  Future<void> _addLink() async {
    final link = _linkController.text.trim();
    if (link.isEmpty) {
      _showSnackBar('Please enter a link', isError: true);
      return;
    }
    if (!(link.startsWith('http://') ||
        link.startsWith('https://') ||
        link.startsWith('magnet:'))) {
      _showSnackBar('Please enter a valid URL or magnet link', isError: true);
      return;
    }
    final apiKey = _apiKey;
    if (apiKey == null || apiKey.isEmpty) return;

    Navigator.of(context).pop();
    setState(() => _isAddingLink = true);
    _showLoadingDialog('Adding to Premiumize...');

    try {
      await PremiumizeService.createTransfer(
        apiKey,
        link,
        folderId: _currentFolderId,
      );
      _dismissDialog();
      if (!mounted) return;
      _linkController.clear();
      _showSnackBar('Added to Premiumize', isError: false);
      await _refresh();
    } catch (e) {
      _dismissDialog();
      _showSnackBar('Failed to add: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isAddingLink = false);
    }
  }

  // ── Multi-select helpers ─────────────────────────────────────────────────────

  void _toggleSelectionMode() {
    setState(() {
      if (_isSelectionMode) _selectedIds.clear();
      _isSelectionMode = !_isSelectionMode;
    });
  }

  void _exitSelectionMode() {
    if (!_isSelectionMode) return;
    setState(() {
      _isSelectionMode = false;
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

  void _toggleSelectAll() {
    setState(() {
      if (_isAllSelected) {
        _selectedIds.clear();
      } else {
        _selectedIds
          ..clear()
          ..addAll(_items.map((i) => i.id));
      }
    });
  }

  // ── Misc helpers ─────────────────────────────────────────────────────────────

  void _showLoadingDialog(String message) {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(message, style: const TextStyle(color: Colors.white)),
          ],
        ),
      ),
    );
  }

  void _dismissDialog() {
    if (mounted && Navigator.of(context, rootNavigator: true).canPop()) {
      Navigator.of(context, rootNavigator: true).pop();
    }
  }

  void _focusFirstItemOrFallback() {
    if (!_shouldFocusOnLoad) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_shouldFocusOnLoad) return;
      if (_items.isNotEmpty) {
        _shouldFocusOnLoad = false;
        _firstItemFocusNode.requestFocus();
      } else if (!_isLoading) {
        _shouldFocusOnLoad = false;
        _addLinkButtonFocusNode.requestFocus();
      }
    });
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

  String _formatUnixDate(int seconds) {
    if (seconds <= 0) return '';
    try {
      final date = DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
      final diff = DateTime.now().difference(date);
      if (diff.inDays == 0) {
        if (diff.inHours == 0) return '${diff.inMinutes}m ago';
        return '${diff.inHours}h ago';
      } else if (diff.inDays < 7) {
        return '${diff.inDays}d ago';
      }
      return '${date.month}/${date.day}/${date.year}';
    } catch (_) {
      return '';
    }
  }

  // ── Series helpers (shared shape with PikPak/playlist player) ────────────────

  String _formatPlaylistTitle({
    required SeriesInfo info,
    required String fallback,
    required bool isSeriesCollection,
  }) {
    if (!isSeriesCollection) return fallback;
    final season = info.season;
    final episode = info.episode;
    if (info.isSeries && season != null && episode != null) {
      final s = season.toString().padLeft(2, '0');
      final e = episode.toString().padLeft(2, '0');
      final desc = info.episodeTitle?.trim().isNotEmpty == true
          ? info.episodeTitle!.trim()
          : info.title?.trim().isNotEmpty == true
              ? info.title!.trim()
              : fallback;
      return 'S${s}E$e · $desc';
    }
    return fallback;
  }

  String _composeEntryTitle({
    required String? seriesTitle,
    required String episodeLabel,
    required bool isSeriesCollection,
    required String fallback,
  }) {
    if (!isSeriesCollection) return fallback;
    final clean = seriesTitle?.replaceAll(RegExp(r'[._\-]+$'), '').trim();
    if (clean != null && clean.isNotEmpty) return '$clean $episodeLabel';
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

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (widget.isPushedRoute && _isAtRoot && _initialLoad) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: const Text('Opening folder...'),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (!_premiumizeEnabled) return _buildNotEnabled();
    if (_initialLoad && (_isLoading || _isLoadingTransfers)) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_errorMessage.isNotEmpty &&
        _items.isEmpty &&
        _transfers.isEmpty) {
      return _buildError();
    }

    final showViewModeDropdown =
        _selectedView == _PremiumizeView.files && _navigationStack.isNotEmpty;
    // Search is available in the files view everywhere: at root it runs a
    // server-side cloud search; inside a folder it filters locally.
    final showSearch = _selectedView == _PremiumizeView.files;

    final bool isCompact = MediaQuery.sizeOf(context).width < 500;
    final double iconSize = isCompact ? 20 : 24;
    final EdgeInsets iconPadding =
        isCompact ? const EdgeInsets.all(6) : const EdgeInsets.all(8);
    final BoxConstraints iconConstraints = isCompact
        ? const BoxConstraints(minWidth: 36, minHeight: 36)
        : const BoxConstraints(minWidth: 48, minHeight: 48);

    return Scaffold(
      appBar: AppBar(
        leading: (!_isAtRoot)
            ? Focus(
                onKeyEvent: (node, event) {
                  if (event is KeyDownEvent &&
                      event.logicalKey == LogicalKeyboardKey.arrowLeft &&
                      MainPageBridge.focusTvSidebar != null) {
                    MainPageBridge.focusTvSidebar!();
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: IconButton(
                  focusNode: _backButtonFocusNode,
                  icon: const Icon(Icons.arrow_back),
                  onPressed: _handleBackNavigation,
                  tooltip: 'Back',
                ),
              )
            : null,
        title: Text(_isAtRoot ? 'Premiumize' : _currentFolderName),
        actions: [
          if (_selectedView == _PremiumizeView.files &&
              _items.isNotEmpty &&
              !_isSearchActive)
            IconButton(
              icon: Icon(
                  _isSelectionMode ? Icons.close : Icons.checklist_outlined),
              onPressed: _toggleSelectionMode,
              tooltip: _isSelectionMode ? 'Exit selection' : 'Select items',
              color: _isSelectionMode
                  ? Theme.of(context).colorScheme.error
                  : null,
              iconSize: iconSize,
              padding: iconPadding,
              constraints: iconConstraints,
              visualDensity: VisualDensity.compact,
            ),
          if (showSearch)
            IconButton(
              focusNode: _searchButtonFocusNode,
              icon: Icon(_isSearchActive ? Icons.close : Icons.search),
              onPressed: _toggleSearch,
              tooltip: _isSearchActive ? 'Close search' : 'Search files',
              iconSize: iconSize,
              padding: iconPadding,
              constraints: iconConstraints,
              visualDensity: VisualDensity.compact,
            ),
          IconButton(
            focusNode: _addLinkButtonFocusNode,
            icon: const Icon(Icons.add_link),
            onPressed: _isLoading ? null : _showAddLinkDialog,
            tooltip: 'Add to Premiumize',
            iconSize: iconSize,
            padding: iconPadding,
            constraints: iconConstraints,
            visualDensity: VisualDensity.compact,
          ),
          IconButton(
            focusNode: _refreshButtonFocusNode,
            icon: const Icon(Icons.refresh),
            onPressed: (_isLoading || _isLoadingTransfers) ? null : _refresh,
            tooltip: 'Refresh',
            iconSize: iconSize,
            padding: iconPadding,
            constraints: iconConstraints,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
      body: Column(
        children: [
          if (_isAtRoot && !_isSearchActive) _buildViewSelector(),
          if (_isSelectionMode) _buildSelectionBar(),
          if (showViewModeDropdown) _buildViewModeDropdown(),
          if (_isSearchActive && showSearch) _buildSearchBar(),
          Expanded(
            child: FocusTraversalGroup(
              policy: OrderedTraversalPolicy(),
              child: RefreshIndicator(
                onRefresh: _refresh,
                child: _buildBody(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isSearchActive) return _buildSearchResults();
    if (_selectedView == _PremiumizeView.transfers) return _buildTransfersList();
    if (_items.isEmpty) return _buildEmpty();
    return _buildFileList();
  }

  Widget _buildViewSelector() {
    final theme = Theme.of(context);
    Widget chip(String label, IconData icon, _PremiumizeView view) {
      final selected = _selectedView == view;
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Material(
            color: selected
                ? theme.colorScheme.primary.withValues(alpha: 0.15)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => _switchView(view),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: selected
                        ? theme.colorScheme.primary.withValues(alpha: 0.5)
                        : theme.dividerColor.withValues(alpha: 0.2),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon,
                        size: 18,
                        color: selected ? theme.colorScheme.primary : null),
                    const SizedBox(width: 8),
                    Text(
                      label,
                      style: TextStyle(
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w500,
                        color: selected ? theme.colorScheme.primary : null,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Row(
        children: [
          chip('My Files', Icons.folder_rounded, _PremiumizeView.files),
          chip('Transfers', Icons.swap_vert_rounded, _PremiumizeView.transfers),
        ],
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
          ),
        ),
      ),
      child: Focus(
        skipTraversal: true,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.arrowUp) {
            _backButtonFocusNode.requestFocus();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: DropdownButtonFormField<_FolderViewMode>(
          focusNode: _viewModeDropdownFocusNode,
          isExpanded: true,
          value: mode,
          decoration: InputDecoration(
            labelText: 'View Mode',
            prefixIcon: Icon(
              mode == _FolderViewMode.raw
                  ? Icons.view_list
                  : Icons.sort_by_alpha,
              color: theme.colorScheme.primary,
            ),
            border:
                OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            filled: true,
            fillColor:
                theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          ),
          items: const [
            DropdownMenuItem(value: _FolderViewMode.raw, child: Text('Raw')),
            DropdownMenuItem(
                value: _FolderViewMode.sortedAZ, child: Text('Sort (A-Z)')),
          ],
          onChanged: (value) {
            if (value != null) _setViewMode(value);
          },
        ),
      ),
    );
  }

  Widget _buildSelectionBar() {
    final theme = Theme.of(context);
    final count = _selectedIds.length;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.3)),
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

  Widget _buildSearchBar() {
    final hasText = _searchController.text.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: Focus(
              // D-pad navigation handler for Android TV.
              onKeyEvent: (node, event) {
                if (event is! KeyDownEvent) return KeyEventResult.ignored;
                final key = event.logicalKey;
                final textLength = _searchController.text.length;
                final selection = _searchController.selection;
                final isSelectionValid =
                    selection.isValid && selection.baseOffset >= 0;
                final isAtStart = !isSelectionValid ||
                    (selection.baseOffset == 0 && selection.extentOffset == 0);
                final isAtEnd = !isSelectionValid ||
                    (selection.baseOffset == textLength &&
                        selection.extentOffset == textLength);
                final isEmpty = textLength == 0;

                // Up at start/empty: move focus up (to the app-bar actions),
                // not unfocus — unfocus would make the highlight vanish.
                if (key == LogicalKeyboardKey.arrowUp && (isEmpty || isAtStart)) {
                  _searchFocusNode.focusInDirection(TraversalDirection.up);
                  return KeyEventResult.handled;
                }
                // Down at end/empty: move focus down into the results list.
                if (key == LogicalKeyboardKey.arrowDown && (isEmpty || isAtEnd)) {
                  _searchFocusNode.focusInDirection(TraversalDirection.down);
                  return KeyEventResult.handled;
                }
                // Right at end: move to the clear button when visible.
                if (key == LogicalKeyboardKey.arrowRight &&
                    hasText &&
                    (isEmpty || isAtEnd)) {
                  _searchClearFocusNode.requestFocus();
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: TextField(
                controller: _searchController,
                focusNode: _searchFocusNode,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: _isAtRoot
                      ? 'Search your Premiumize cloud...'
                      : 'Search files...',
                  prefixIcon: const Icon(Icons.search, color: Colors.grey),
                  filled: true,
                  fillColor: const Color(0xFF1E293B),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                style: const TextStyle(color: Colors.white),
                onChanged: _performSearch,
                onSubmitted: (_) => _searchFocusNode.unfocus(),
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
                  if (isActivateKey(key)) {
                    setState(() {
                      _searchController.clear();
                      _searchResults = [];
                    });
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
                        icon: const Icon(Icons.clear, color: Colors.grey),
                        onPressed: () {
                          setState(() {
                            _searchController.clear();
                            _searchResults = [];
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

  Widget _buildSearchResults() {
    if (_searchController.text.trim().isEmpty) {
      return Center(
        child: Text(
          _isAtRoot ? 'Type to search your cloud' : 'Type to search files',
          style: const TextStyle(color: Colors.grey),
        ),
      );
    }
    if (_isSearching && _searchResults.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_searchResults.isEmpty) {
      return const Center(
        child: Text('No results found', style: TextStyle(color: Colors.grey)),
      );
    }
    // Reuse the full file card so search results get the same Open / Play /
    // ⋮ (Download · Add to Playlist · Delete) actions as the main list.
    // autofocusFirst is disabled so results don't steal focus from the search
    // box while the user is typing.
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        final item = _searchResults[index];
        return KeyedSubtree(
          key: ValueKey('search-${item.id}'),
          child: _buildFileCard(item, index, autofocusFirst: false),
        );
      },
    );
  }

  Widget _buildFileList() {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: _items.length,
      itemBuilder: (context, index) {
        final item = _items[index];
        return KeyedSubtree(
          key: ValueKey(item.id),
          child: _buildFileCard(item, index),
        );
      },
    );
  }

  Widget _buildFileCard(
    PremiumizeFolderItem item,
    int index, {
    bool autofocusFirst = true,
  }) {
    final theme = Theme.of(context);
    final isSelected = _selectedIds.contains(item.id);
    final isVideo = item.isVideo;

    return TvFocusScrollWrapper(
      child: GestureDetector(
        onTap: _isSelectionMode ? () => _toggleSelection(item.id) : null,
        child: Card(
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: _isSelectionMode && isSelected
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
                    if (_isSelectionMode) ...[
                      Checkbox(
                        value: isSelected,
                        onChanged: (_) => _toggleSelection(item.id),
                      ),
                      const SizedBox(width: 4),
                    ],
                    Icon(
                      item.isFolder
                          ? Icons.folder
                          : isVideo
                              ? Icons.play_circle_outline
                              : Icons.insert_drive_file,
                      color: item.isFolder
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
                            item.name,
                            style: const TextStyle(
                                fontWeight: FontWeight.w500, fontSize: 16),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              if (!item.isFolder && item.size > 0) ...[
                                Text(
                                  Formatters.formatFileSize(item.size),
                                  style: TextStyle(
                                      color: Colors.grey.shade600,
                                      fontSize: 13),
                                ),
                                if (_formatUnixDate(item.createdAt)
                                    .isNotEmpty) ...[
                                  const SizedBox(width: 8),
                                  Text('•',
                                      style: TextStyle(
                                          color: Colors.grey.shade600)),
                                  const SizedBox(width: 8),
                                ],
                              ],
                              if (_formatUnixDate(item.createdAt).isNotEmpty)
                                Text(
                                  _formatUnixDate(item.createdAt),
                                  style: TextStyle(
                                      color: Colors.grey.shade600,
                                      fontSize: 13),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (!_isSelectionMode) ...[
                  const SizedBox(height: 12),
                  FocusTraversalGroup(
                    policy: OrderedTraversalPolicy(),
                    child: Row(
                      children: [
                        if (item.isFolder) ...[
                          Expanded(
                            child: _buildActionButton(
                              focusNode: (autofocusFirst && index == 0)
                                  ? _firstItemFocusNode
                                  : null,
                              autofocus: autofocusFirst && index == 0,
                              icon: Icons.folder_open,
                              label: 'Open',
                              color: const Color(0xFF8B5CF6),
                              onTap: () => _navigateIntoFolder(item),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildActionButton(
                              icon: Icons.play_arrow_rounded,
                              label: 'Play',
                              color: const Color(0xFF22C55E),
                              onTap: () => _playFolder(item),
                            ),
                          ),
                          const SizedBox(width: 8),
                        ] else if (isVideo) ...[
                          Expanded(
                            child: _buildActionButton(
                              focusNode: (autofocusFirst && index == 0)
                                  ? _firstItemFocusNode
                                  : null,
                              autofocus: autofocusFirst && index == 0,
                              icon: Icons.play_arrow_rounded,
                              label: 'Play',
                              color: const Color(0xFF22C55E),
                              onTap: () => _playFile(item),
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        PopupMenuButton<String>(
                          icon: const Icon(Icons.more_vert),
                          tooltip: 'More options',
                          onSelected: (value) {
                            switch (value) {
                              case 'download':
                                if (item.isFolder) {
                                  _downloadFolder(item);
                                } else {
                                  _downloadFile(item);
                                }
                                break;
                              case 'add_to_playlist':
                                _addToPlaylist(item);
                                break;
                              case 'delete':
                                _showDeleteDialog(item);
                                break;
                            }
                          },
                          itemBuilder: (context) => [
                            const PopupMenuItem(
                              value: 'download',
                              child: Row(
                                children: [
                                  Icon(Icons.download,
                                      size: 18, color: Colors.green),
                                  SizedBox(width: 12),
                                  Text('Download'),
                                ],
                              ),
                            ),
                            if (item.isFolder || isVideo)
                              const PopupMenuItem(
                                value: 'add_to_playlist',
                                child: Row(
                                  children: [
                                    Icon(Icons.playlist_add,
                                        size: 18, color: Colors.blue),
                                    SizedBox(width: 12),
                                    Text('Add to Playlist'),
                                  ],
                                ),
                              ),
                            const PopupMenuItem(
                              value: 'delete',
                              child: Row(
                                children: [
                                  Icon(Icons.delete_outline,
                                      size: 18, color: Colors.red),
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
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTransfersList() {
    if (_isLoadingTransfers && _transfers.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_transfers.isEmpty) {
      return ListView(
        children: [
          const SizedBox(height: 120),
          Center(
            child: Column(
              children: [
                Icon(Icons.swap_vert_rounded,
                    size: 64, color: Colors.grey.shade400),
                const SizedBox(height: 16),
                Text('No Transfers',
                    style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 8),
                Text(
                  'Magnets you add appear here while they download.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
        ],
      );
    }

    final hasFinished = _transfers.any((t) => t.isFinished);
    return Column(
      children: [
        if (hasFinished)
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: TextButton.icon(
                onPressed: _clearFinishedTransfers,
                icon: const Icon(Icons.cleaning_services_outlined, size: 18),
                label: const Text('Clear finished'),
              ),
            ),
          ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _transfers.length,
            itemBuilder: (context, index) =>
                _buildTransferCard(_transfers[index]),
          ),
        ),
      ],
    );
  }

  Widget _buildTransferCard(PremiumizeTransfer transfer) {
    final theme = Theme.of(context);
    Color statusColor;
    IconData statusIcon;
    if (transfer.isFinished) {
      statusColor = const Color(0xFF22C55E);
      statusIcon = Icons.check_circle_outline;
    } else if (transfer.isError) {
      statusColor = const Color(0xFFEF4444);
      statusIcon = Icons.error_outline;
    } else {
      statusColor = const Color(0xFFFB923C);
      statusIcon = Icons.downloading_rounded;
    }

    return TvFocusScrollWrapper(
      child: Card(
        margin: const EdgeInsets.only(bottom: 12),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(statusIcon, color: statusColor),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      transfer.name,
                      style: const TextStyle(
                          fontWeight: FontWeight.w500, fontSize: 15),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline,
                        size: 20, color: Colors.red),
                    tooltip: 'Delete transfer',
                    onPressed: () => _deleteTransfer(transfer),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (transfer.isRunning) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: transfer.progress > 0 ? transfer.progress : null,
                    minHeight: 6,
                    backgroundColor:
                        theme.colorScheme.surfaceContainerHighest,
                    valueColor: AlwaysStoppedAnimation(statusColor),
                  ),
                ),
                const SizedBox(height: 6),
              ],
              Text(
                transfer.message ??
                    (transfer.isFinished
                        ? 'Finished'
                        : transfer.isError
                            ? 'Error'
                            : '${transfer.progressPercent}%'),
                style: TextStyle(color: statusColor, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton({
    FocusNode? focusNode,
    bool autofocus = false,
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Focus(
      focusNode: focusNode,
      autofocus: autofocus,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent && isActivateKey(event.logicalKey)) {
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
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                  Icon(icon,
                      size: 16,
                      color: isFocused
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.9)),
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

  Widget _buildEmpty() {
    final isInFolder = !_isAtRoot;
    return ListView(
      children: [
        const SizedBox(height: 120),
        Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              children: [
                Icon(Icons.folder_open,
                    size: 64, color: Colors.grey.shade400),
                const SizedBox(height: 24),
                Text(
                  isInFolder ? 'Folder is Empty' : 'No Files Yet',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 16),
                Text(
                  isInFolder
                      ? 'This folder doesn\'t contain any files or subfolders.'
                      : 'Add torrents from search or with the + button to see them here.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNotEnabled() {
    return Scaffold(
      appBar: AppBar(title: const Text('Premiumize')),
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
                Text('Premiumize Not Configured',
                    style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 16),
                Text(
                  'Add your Premiumize API key in Settings to view and manage your cloud.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade600),
                ),
                const SizedBox(height: 32),
                FilledButton.icon(
                  focusNode: _settingsButtonFocusNode,
                  autofocus: true,
                  onPressed: () => _showSnackBar(
                    'Open Settings > Premiumize to configure',
                    isError: false,
                  ),
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
      appBar: AppBar(title: const Text('Premiumize')),
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
                Text('Failed to Load',
                    style: Theme.of(context).textTheme.headlineSmall),
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
                  onPressed: _refresh,
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
}
