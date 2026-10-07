import 'package:debrify/features/premiumize_files/presentation/legacy_premiumize/premiumize_catalog_state.dart';
import 'package:debrify/features/premiumize_files/presentation/legacy_premiumize/premiumize_navigation_state.dart';
import 'package:debrify/features/premiumize_files/presentation/legacy_premiumize/premiumize_view_state.dart';
import 'package:debrify/features/premiumize_files/presentation/legacy_premiumize/premiumize_focus_state.dart';
import 'package:debrify/features/premiumize_files/presentation/legacy_premiumize/premiumize_selection_state.dart';
import 'package:debrify/features/premiumize_files/presentation/legacy_premiumize/premiumize_search_state.dart';
import 'package:debrify/features/premiumize_files/presentation/legacy_premiumize/premiumize_link_state.dart';
import 'package:debrify/features/premiumize_files/models/folder_view_mode.dart';
import 'package:debrify/features/premiumize_files/models/premiumize_view.dart';
import 'package:debrify/features/premiumize_files/application/premiumize_sort_policy.dart';
import 'package:debrify/features/premiumize_files/application/premiumize_playlist_titles.dart';
import 'dart:async';
import 'package:debrify/services/storage/playlist_storage.dart';
import 'package:debrify/services/storage/premiumize_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../screens/video_player_screen.dart'; // re-exports PlaylistEntry
import '../../services/analytics_service.dart';
import '../../services/premiumize_service.dart';
import '../../services/download_service.dart';
import '../../services/video_player_launcher.dart';
import '../../services/main_page_bridge.dart';
import '../../services/series_source_service.dart';
import '../../models/premiumize_folder_item.dart';
import '../../models/premiumize_transfer.dart';
import '../../utils/file_utils.dart';
import '../../utils/formatters.dart';
import '../../utils/series_parser.dart';
import '../../widgets/cloud/cloud_file_row.dart';
import '../../widgets/cloud/cloud_row_skeleton.dart';
import '../../widgets/cloud/cloud_segmented_tabs.dart';
import '../../widgets/cloud/cloud_theme.dart';
import '../../widgets/file_selection_dialog.dart';
import '../../widgets/tv_text_field.dart';
import '../debrify_tv/widgets/tv_focus_scroll_wrapper.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_theme_scope.dart';
import '../../utils/tv_keys.dart';

/// Cloud-library browser for Premiumize, mirroring the Torbox/PikPak navigation
/// pages. Premiumize's cloud is a real server-side folder hierarchy, so this
/// browses folders by id (like PikPak) and additionally exposes a Transfers
/// view (Premiumize's queued/running magnet transfers).
class PremiumizeFilesScreen extends StatefulWidget {
  final String? initialFolderId;
  final String? initialFolderName;
  final String? initialSearchQuery;
  final bool selectSourceMode;
  final Future<void> Function(SeriesSource)? onSourceSelected;

  /// When true, this screen was pushed as a route (not displayed in a tab).
  /// Back navigation pops the route instead of switching tabs.
  final bool isPushedRoute;

  const PremiumizeFilesScreen({
    super.key,
    this.initialFolderId,
    this.initialFolderName,
    this.initialSearchQuery,
    this.isPushedRoute = false,
    this.selectSourceMode = false,
    this.onSourceSelected,
  });

  @override
  State<PremiumizeFilesScreen> createState() => _PremiumizeFilesScreenState();
}

class _PremiumizeFilesScreenState extends State<PremiumizeFilesScreen> {
  final _catalog = PremiumizeCatalogState();
  final _nav = PremiumizeNavigationState();
  final _view = PremiumizeViewState();
  final _focus = PremiumizeFocusState();
  final _selection = PremiumizeSelectionState();
  final _search = PremiumizeSearchState();
  final _link = PremiumizeLinkState();

  // Premiumize tab index in main.dart's page list (for TV focus + back handler).
  static const int _tabIndex = 11;

  bool get _isAllSelected =>
      _selection.selectedIds.length == _catalog.items.length &&
      _catalog.items.isNotEmpty;

  bool get _isAtRoot => _nav.currentFolderId == null;

  @override
  void initState() {
    super.initState();
    AnalyticsService.screenView('premiumize_files');
    _loadSettings();

    if (widget.isPushedRoute) {
      MainPageBridge.pushRouteBackHandler(_handleBackNavigation);
    } else {
      MainPageBridge.registerTabBackHandler(
        'premiumize',
        _handleBackNavigation,
      );
      _focus.tvContentFocusHandler = () {
        _focus.shouldFocusOnLoad = true;
        _focusFirstItemOrFallback();
      };
      MainPageBridge.registerTvContentFocusHandler(
        _tabIndex,
        _focus.tvContentFocusHandler!,
      );
    }
  }

  @override
  void dispose() {
    if (widget.isPushedRoute) {
      MainPageBridge.popRouteBackHandler(_handleBackNavigation);
    } else {
      MainPageBridge.unregisterTabBackHandler('premiumize');
      if (_focus.tvContentFocusHandler != null) {
        MainPageBridge.unregisterTvContentFocusHandler(
          _tabIndex,
          _focus.tvContentFocusHandler!,
        );
      }
    }
    _search.searchDebounce?.cancel();
    _focus.scrollController.dispose();
    _link.linkController.dispose();
    _search.searchController.dispose();
    _focus.refreshButtonFocusNode.dispose();
    _focus.backButtonFocusNode.dispose();
    _focus.retryButtonFocusNode.dispose();
    _focus.settingsButtonFocusNode.dispose();
    _focus.viewModeDropdownFocusNode.dispose();
    _focus.addLinkButtonFocusNode.dispose();
    _focus.firstItemFocusNode.dispose();
    _focus.deleteButtonFocusNode.dispose();
    _focus.searchFocusNode.dispose();
    _focus.searchButtonFocusNode.dispose();
    _focus.searchClearFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final enabled = await PremiumizeStorage.getPremiumizeIntegrationEnabled();
    final apiKey = await PremiumizeStorage.getPremiumizeApiKey();

    if (!mounted) return;
    setState(() {
      _catalog.premiumizeEnabled =
          enabled && apiKey != null && apiKey.isNotEmpty;
      _catalog.apiKey = apiKey;
      if (widget.initialFolderId != null && widget.initialFolderName != null) {
        _nav.currentFolderId = widget.initialFolderId;
        _nav.currentFolderName = widget.initialFolderName!;
      }
      final initialQuery = widget.initialSearchQuery?.trim() ?? '';
      if (initialQuery.isNotEmpty) {
        _search.isSearchActive = true;
        _search.searchController.text = initialQuery;
      }
    });

    if (_catalog.premiumizeEnabled) {
      _loadFolder();
      final initialQuery = widget.initialSearchQuery?.trim() ?? '';
      if (initialQuery.isNotEmpty) _performSearch(initialQuery);
    } else {
      setState(() => _catalog.initialLoad = false);
    }
  }

  // ── Loading ──────────────────────────────────────────────────────────────

  Future<void> _loadFolder() async {
    final apiKey = _catalog.apiKey;
    if (apiKey == null || apiKey.isEmpty || _catalog.isLoading) return;

    setState(() {
      _catalog.isLoading = true;
      _catalog.errorMessage = '';
    });

    try {
      final listing = await PremiumizeService.listFolder(
        apiKey,
        folderId: _nav.currentFolderId,
      );
      if (!mounted) return;

      final mode = _getCurrentViewMode();
      final ordered = _applyViewMode(mode, listing.items);

      setState(() {
        _catalog.items
          ..clear()
          ..addAll(ordered);
        _catalog.isLoading = false;
        _catalog.initialLoad = false;
      });
      _focusFirstItemOrFallback();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _catalog.errorMessage = e.toString();
        _catalog.isLoading = false;
        _catalog.initialLoad = false;
      });
    }
  }

  Future<void> _loadTransfers() async {
    final apiKey = _catalog.apiKey;
    if (apiKey == null || apiKey.isEmpty || _catalog.isLoadingTransfers) return;

    setState(() {
      _catalog.isLoadingTransfers = true;
      _catalog.errorMessage = '';
    });

    try {
      final transfers = await PremiumizeService.listTransfers(apiKey);
      if (!mounted) return;
      setState(() {
        _catalog.transfers
          ..clear()
          ..addAll(transfers);
        _catalog.isLoadingTransfers = false;
        _catalog.initialLoad = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _catalog.errorMessage = e.toString();
        _catalog.isLoadingTransfers = false;
        _catalog.initialLoad = false;
      });
    }
  }

  Future<void> _refresh() async {
    _exitSelectionMode();
    if (_view.selectedView == PremiumizeView.transfers) {
      await _loadTransfers();
    } else {
      await _loadFolder();
    }
  }

  void _switchView(PremiumizeView view) {
    if (_view.selectedView == view) return;
    _exitSelectionMode();
    // Reset the Files list offset so a Files→Transfers→Files round-trip
    // doesn't land back on a stale scroll position.
    if (_focus.scrollController.hasClients) _focus.scrollController.jumpTo(0);
    setState(() {
      _view.selectedView = view;
      _catalog.errorMessage = '';
    });
    if (view == PremiumizeView.transfers) {
      _loadTransfers();
    } else {
      _loadFolder();
    }
  }

  // ── Folder navigation ──────────────────────────────────────────────────────

  void _navigateIntoFolder(PremiumizeFolderItem folder) {
    _exitSelectionMode();
    _focus.shouldFocusOnLoad = true;
    // Reset scroll while the outgoing list is still attached, so the new
    // folder never inherits the old offset.
    if (_focus.scrollController.hasClients) _focus.scrollController.jumpTo(0);
    setState(() {
      _nav.navigationStack.add((
        id: _nav.currentFolderId,
        name: _nav.currentFolderName,
      ));
      _nav.currentFolderId = folder.id;
      _nav.currentFolderName = folder.name;
      // Clear stale rows so the loading skeleton shows instead of the
      // outgoing folder's contents sitting frozen while the fetch runs.
      _catalog.items.clear();
      _search.isSearchActive = false;
      _search.searchController.clear();
      _search.searchResults = [];
    });
    _loadFolder();
  }

  void _navigateUp() {
    _exitSelectionMode();
    if (_nav.navigationStack.isEmpty) return;
    // Refocus the first row once the parent listing loads — clearing _items
    // disposes the focused row and nothing else reclaims DPAD focus.
    _focus.shouldFocusOnLoad = true;
    if (_focus.scrollController.hasClients) _focus.scrollController.jumpTo(0);
    setState(() {
      final previous = _nav.navigationStack.removeLast();
      _nav.currentFolderId = previous.id;
      _nav.currentFolderName = previous.name;
      _catalog.items.clear();
    });
    _loadFolder();
  }

  bool _handleBackNavigation() {
    if (_selection.isSelectionMode) {
      _exitSelectionMode();
      return true;
    }
    if (_search.isSearchActive) {
      _toggleSearch();
      return true;
    }
    if (_nav.navigationStack.isNotEmpty) {
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
      MainPageBridge.switchTab?.call(MainTab.legacyTorrentSearch);
      return true;
    }
    return false;
  }

  // ── View modes ─────────────────────────────────────────────────────────────

  PremiumizeFolderViewMode _getCurrentViewMode() {
    if (_isAtRoot) return PremiumizeFolderViewMode.raw;
    return _view.folderViewModes[_nav.currentFolderId!] ??
        PremiumizeFolderViewMode.raw;
  }

  void _setViewMode(PremiumizeFolderViewMode mode) {
    if (_isAtRoot) return;
    setState(() {
      _view.folderViewModes[_nav.currentFolderId!] = mode;
      final reordered = _applyViewMode(mode, _catalog.items);
      _catalog.items
        ..clear()
        ..addAll(reordered);
    });
  }

  List<PremiumizeFolderItem> _applyViewMode(
    PremiumizeFolderViewMode mode,
    List<PremiumizeFolderItem> items,
  ) {
    if (mode == PremiumizeFolderViewMode.raw) return List.of(items);
    return applySortedView(items);
  }

  // ── Search ─────────────────────────────────────────────────────────────────

  void _toggleSearch() {
    setState(() {
      _search.isSearchActive = !_search.isSearchActive;
      if (!_search.isSearchActive) {
        _search.searchDebounce?.cancel();
        _search.searchController.clear();
        _search.searchResults = [];
        _search.isSearching = false;
      } else {
        // Search and multi-select are mutually exclusive: selection bar actions
        // operate on _items, not search results.
        _selection.isSelectionMode = false;
        _selection.selectedIds.clear();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _focus.searchFocusNode.requestFocus();
        });
      }
    });
  }

  void _performSearch(String query) {
    final q = query.trim();
    if (q.isEmpty) {
      _search.searchDebounce?.cancel();
      setState(() {
        _search.searchResults = [];
        _search.isSearching = false;
      });
      return;
    }

    // Root: server-side cloud search (recursive), debounced to limit calls.
    if (_isAtRoot) {
      _search.searchDebounce?.cancel();
      setState(() => _search.isSearching = true);
      _search.searchDebounce = Timer(
        const Duration(milliseconds: 350),
        () => _runCloudSearch(q),
      );
      return;
    }

    // Inside a folder: filter the currently-loaded items locally.
    final lower = q.toLowerCase();
    setState(() {
      _search.isSearching = false;
      _search.searchResults = _catalog.items
          .where((i) => !i.isFolder && i.name.toLowerCase().contains(lower))
          .toList();
    });
  }

  Future<void> _runCloudSearch(String query) async {
    final apiKey = _catalog.apiKey;
    if (apiKey == null || apiKey.isEmpty) return;
    try {
      final results = await PremiumizeService.searchCloud(apiKey, query);
      if (!mounted) return;
      // Drop stale results if the query changed while the request was in flight.
      if (_search.searchController.text.trim() != query) return;
      setState(() {
        _search.searchResults = results;
        _search.isSearching = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _search.isSearching = false);
      _showSnackBar('Search failed: $e', isError: true);
    }
  }

  // ── Playback ───────────────────────────────────────────────────────────────

  Future<void> _selectBoundSource(PremiumizeFolderItem item) async {
    final apiKey = _catalog.apiKey;
    if (apiKey == null || apiKey.isEmpty) return;

    _showLoadingDialog(
      item.isFolder ? 'Checking folder for videos...' : 'Checking file...',
    );
    var checkingDialogOpen = true;
    void closeCheckingDialog() {
      if (!checkingDialogOpen) return;
      checkingDialogOpen = false;
      _dismissDialog();
    }

    try {
      if (item.isFolder) {
        final files = await PremiumizeService.listFolderRecursive(
          apiKey,
          item.id,
        );
        if (!mounted) return;
        final videos = files.where((f) => f.isVideo).toList();
        if (videos.isEmpty) {
          closeCheckingDialog();
          _showSnackBar('This folder has no playable videos', isError: true);
          return;
        }
        final first = videos.first;
        final firstReady =
            first.playableUrl?.isNotEmpty == true ||
            await PremiumizeService.resolveItemById(apiKey, first.id) != null;
        if (!mounted) return;
        if (!firstReady) {
          closeCheckingDialog();
          _showSnackBar(
            'This folder has no ready video streams',
            isError: true,
          );
          return;
        }
      } else {
        if (!item.isVideo) {
          closeCheckingDialog();
          _showSnackBar('Only video files can be bound', isError: true);
          return;
        }
        final resolved = await PremiumizeService.resolveItemById(
          apiKey,
          item.id,
        );
        if (resolved == null || resolved.link.isEmpty) {
          closeCheckingDialog();
          _showSnackBar('This file is not ready to stream', isError: true);
          return;
        }
      }

      closeCheckingDialog();
      await widget.onSourceSelected?.call(
        SeriesSource(
          torrentHash: '',
          torrentName: item.name,
          debridService: 'premiumize',
          debridTorrentId: item.id,
          cloudSourceKind: item.isFolder
              ? SeriesSource.cloudKindFolder
              : SeriesSource.cloudKindFile,
          boundAt: DateTime.now().millisecondsSinceEpoch,
        ),
      );
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      closeCheckingDialog();
      if (mounted) {
        _showSnackBar(
          'Could not bind this Premiumize source: $e',
          isError: true,
        );
      }
    }
  }

  Future<void> _playFile(PremiumizeFolderItem file) async {
    String? url = file.playableUrl;
    // Search hits (folder/search) may omit the direct link — resolve by id.
    if ((url == null || url.isEmpty) &&
        _catalog.apiKey != null &&
        _catalog.apiKey!.isNotEmpty) {
      final resolved = await PremiumizeService.resolveItemById(
        _catalog.apiKey!,
        file.id,
      );
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
        subtitle: sizeBytes != null
            ? Formatters.formatFileSize(sizeBytes)
            : null,
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
    final apiKey = _catalog.apiKey;
    if (apiKey == null || apiKey.isEmpty) return;

    _showLoadingDialog('Scanning folder for videos...');
    try {
      final all = await PremiumizeService.listFolderRecursive(
        apiKey,
        folder.id,
      );
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
          subtitle: sizeBytes != null
              ? Formatters.formatFileSize(sizeBytes)
              : null,
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
    final infos = videos
        .map((v) => SeriesParser.parseFilename(v.name))
        .toList();
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
        return videos[a].name.toLowerCase().compareTo(
          videos[b].name.toLowerCase(),
        );
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

    int startIndex = isSeries ? findFirstEpisodeIndex(sortedInfos) : 0;
    if (startIndex < 0 || startIndex >= sortedVideos.length) startIndex = 0;

    final entries = <PlaylistEntry>[];
    for (int i = 0; i < sortedVideos.length; i++) {
      final v = sortedVideos[i];
      final info = sortedInfos[i];
      final episodeLabel = formatPlaylistTitle(
        info: info,
        fallback: v.name,
        isSeriesCollection: isSeries,
      );
      final title = composeEntryTitle(
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
        credentialKey: 'premiumize_api_key',
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
    final apiKey = _catalog.apiKey;
    if (apiKey == null || apiKey.isEmpty) return;

    _showLoadingDialog('Scanning folder for files...');
    try {
      final all = await PremiumizeService.listFolderRecursive(
        apiKey,
        folder.id,
      );
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
          credentialKey: 'premiumize_api_key',
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
      _showSnackBar(
        'Queued $success file${success == 1 ? '' : 's'}',
        isError: false,
      );
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
    final added = await PlaylistStorage.addPlaylistItemRaw({
      'provider': 'premiumize',
      'title': FileUtils.cleanPlaylistTitle(file.name),
      'kind': 'single',
      'premiumizeItemId': file.id,
      'premiumizeFile': {'id': file.id, 'name': file.name, 'size': file.size},
      'sizeBytes': file.size > 0 ? file.size : null,
    });
    _showSnackBar(
      added ? 'Added to playlist' : 'Already in playlist',
      isError: !added,
    );
  }

  Future<void> _addFolderToPlaylist(PremiumizeFolderItem folder) async {
    final apiKey = _catalog.apiKey;
    if (apiKey == null || apiKey.isEmpty) return;

    _showLoadingDialog('Scanning folder for videos...');
    try {
      final all = await PremiumizeService.listFolderRecursive(
        apiKey,
        folder.id,
      );
      _dismissDialog();
      if (!mounted) return;

      final videos = all.where((f) => f.isVideo).toList();
      if (videos.isEmpty) {
        _showSnackBar('This folder doesn\'t contain any videos', isError: true);
        return;
      }

      if (videos.length == 1) {
        final v = videos.first;
        final added = await PlaylistStorage.addPlaylistItemRaw({
          'provider': 'premiumize',
          'title': FileUtils.cleanPlaylistTitle(v.name),
          'kind': 'single',
          'premiumizeItemId': v.id,
          'premiumizeFile': {'id': v.id, 'name': v.name, 'size': v.size},
          'sizeBytes': v.size > 0 ? v.size : null,
        });
        _showSnackBar(
          added ? 'Added to playlist' : 'Already in playlist',
          isError: !added,
        );
        return;
      }

      final fileIds = videos.map((v) => v.id).toList();
      final filesMeta = videos
          .map((v) => {'id': v.id, 'name': v.name, 'size': v.size})
          .toList();
      final added = await PlaylistStorage.addPlaylistItemRaw({
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
    if (_selection.selectedIds.isEmpty) return;
    final selected = _catalog.items
        .where((i) => _selection.selectedIds.contains(i.id))
        .toList();
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
    final apiKey = _catalog.apiKey;
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
      _catalog.items.removeWhere((i) => deletedIds.contains(i.id));
      _search.searchResults.removeWhere((i) => deletedIds.contains(i.id));
      _selection.selectedIds.clear();
      _selection.isSelectionMode = false;
    });
    if (fail == 0) {
      _showSnackBar(
        'Deleted ${deletedIds.length} item${deletedIds.length == 1 ? '' : 's'}',
        isError: false,
      );
    } else {
      _showSnackBar(
        'Deleted ${deletedIds.length}, $fail failed',
        isError: true,
      );
    }
  }

  // ── Transfers ────────────────────────────────────────────────────────────────

  Future<void> _deleteTransfer(PremiumizeTransfer transfer) async {
    final apiKey = _catalog.apiKey;
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
      setState(
        () => _catalog.transfers.removeWhere((t) => t.id == transfer.id),
      );
      _showSnackBar('Transfer removed', isError: false);
    } catch (e) {
      _showSnackBar('Failed to remove transfer: $e', isError: true);
    }
  }

  Future<void> _clearFinishedTransfers() async {
    final apiKey = _catalog.apiKey;
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
        backgroundColor: AppThemeScope.of(context).cloud.dialogSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Add to Premiumize',
          style: TextStyle(fontWeight: FontWeight.bold),
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
                controller: _link.linkController,
                autofocus: true,
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
              'Adding to cloud spends fair-use points (~1pt/GB).',
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              _link.linkController.clear();
              Navigator.of(context).pop();
            },
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFFB923C),
            ),
            onPressed: _link.isAddingLink ? null : _addLink,
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
        _link.linkController.text = text;
      }
    } catch (_) {}
  }

  Future<void> _addLink() async {
    final link = _link.linkController.text.trim();
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
    final apiKey = _catalog.apiKey;
    if (apiKey == null || apiKey.isEmpty) return;

    Navigator.of(context).pop();
    setState(() => _link.isAddingLink = true);
    _showLoadingDialog('Adding to Premiumize...');

    try {
      await PremiumizeService.createTransfer(
        apiKey,
        link,
        folderId: _nav.currentFolderId,
      );
      _dismissDialog();
      if (!mounted) return;
      _link.linkController.clear();
      _showSnackBar('Added to Premiumize', isError: false);
      await _refresh();
    } catch (e) {
      _dismissDialog();
      _showSnackBar('Failed to add: $e', isError: true);
    } finally {
      if (mounted) setState(() => _link.isAddingLink = false);
    }
  }

  // ── Multi-select helpers ─────────────────────────────────────────────────────

  void _toggleSelectionMode() {
    setState(() {
      if (_selection.isSelectionMode) _selection.selectedIds.clear();
      _selection.isSelectionMode = !_selection.isSelectionMode;
    });
  }

  void _exitSelectionMode() {
    if (!_selection.isSelectionMode) return;
    setState(() {
      _selection.isSelectionMode = false;
      _selection.selectedIds.clear();
    });
  }

  void _toggleSelection(String id) {
    setState(() {
      if (_selection.selectedIds.contains(id)) {
        _selection.selectedIds.remove(id);
      } else {
        _selection.selectedIds.add(id);
      }
    });
  }

  void _toggleSelectAll() {
    setState(() {
      if (_isAllSelected) {
        _selection.selectedIds.clear();
      } else {
        _selection.selectedIds
          ..clear()
          ..addAll(_catalog.items.map((i) => i.id));
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
    if (!_focus.shouldFocusOnLoad) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_focus.shouldFocusOnLoad) return;
      if (_catalog.items.isNotEmpty) {
        _focus.shouldFocusOnLoad = false;
        _focus.firstItemFocusNode.requestFocus();
      } else if (!_catalog.isLoading) {
        _focus.shouldFocusOnLoad = false;
        _focus.addLinkButtonFocusNode.requestFocus();
      }
    });
  }

  void _showSnackBar(
    String message, {
    bool isError = true,
    Duration? duration,
  }) {
    if (!mounted) return;
    final app = AppThemeScope.of(context);
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
                borderRadius: app.shape.br(8),
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
        backgroundColor: app.cloud.dialogSurface,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: app.shape.br(12)),
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

  // ── Build ──────────────────────────────────────────────────────────────────

  /// Pushed from the Cloud hub to browse (no folder target) — the root has no
  /// folder-up Back, so the AppBar offers a Back-to-hub instead.
  bool get _isBrowsePush =>
      widget.isPushedRoute && widget.initialFolderId == null;

  @override
  Widget build(BuildContext context) {
    if (widget.isPushedRoute && _isAtRoot && _catalog.initialLoad) {
      return CloudScaffold(
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

    if (!_catalog.premiumizeEnabled) return _buildNotEnabled();
    if (_catalog.initialLoad &&
        (_catalog.isLoading || _catalog.isLoadingTransfers)) {
      return const CloudScaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_catalog.errorMessage.isNotEmpty &&
        _catalog.items.isEmpty &&
        _catalog.transfers.isEmpty) {
      return _buildError();
    }

    final showViewModeDropdown =
        _view.selectedView == PremiumizeView.files &&
        _nav.navigationStack.isNotEmpty;
    // Search is available in the files view everywhere: at root it runs a
    // server-side cloud search; inside a folder it filters locally.
    final showSearch = _view.selectedView == PremiumizeView.files;

    final bool isCompact = MediaQuery.sizeOf(context).width < 500;
    final double iconSize = isCompact ? 20 : 24;
    final EdgeInsets iconPadding = isCompact
        ? const EdgeInsets.all(6)
        : const EdgeInsets.all(8);
    final BoxConstraints iconConstraints = isCompact
        ? const BoxConstraints(minWidth: 36, minHeight: 36)
        : const BoxConstraints(minWidth: 48, minHeight: 48);

    return CloudScaffold(
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
                  focusNode: _focus.backButtonFocusNode,
                  icon: const Icon(Icons.arrow_back),
                  onPressed: _handleBackNavigation,
                  tooltip: 'Back',
                ),
              )
            // At the browse root (pushed from the Cloud hub with no folder
            // target) there's no folder-up back — offer a Back-to-hub instead.
            : (_isBrowsePush
                  ? IconButton(
                      icon: const Icon(Icons.arrow_back),
                      tooltip: 'Back',
                      onPressed: () => Navigator.of(context).maybePop(),
                    )
                  : null),
        title: Text(
          widget.selectSourceMode
              ? 'Select Premiumize Source'
              : (_isAtRoot ? 'Premiumize' : _nav.currentFolderName),
        ),
        actions: [
          // Keep the button mounted while a navigation fetch runs (_items is
          // cleared then) so the AppBar doesn't flicker and TV focus parked
          // on it isn't dropped.
          if (_view.selectedView == PremiumizeView.files &&
              (_catalog.items.isNotEmpty || _catalog.isLoading) &&
              !_search.isSearchActive &&
              !widget.selectSourceMode)
            IconButton(
              icon: Icon(
                _selection.isSelectionMode
                    ? Icons.close
                    : Icons.checklist_outlined,
              ),
              onPressed: _toggleSelectionMode,
              tooltip: _selection.isSelectionMode
                  ? 'Exit selection'
                  : 'Select items',
              color: _selection.isSelectionMode
                  ? Theme.of(context).colorScheme.error
                  : null,
              iconSize: iconSize,
              padding: iconPadding,
              constraints: iconConstraints,
              visualDensity: VisualDensity.compact,
            ),
          if (showSearch)
            IconButton(
              focusNode: _focus.searchButtonFocusNode,
              icon: Icon(_search.isSearchActive ? Icons.close : Icons.search),
              onPressed: _toggleSearch,
              tooltip: _search.isSearchActive ? 'Close search' : 'Search files',
              iconSize: iconSize,
              padding: iconPadding,
              constraints: iconConstraints,
              visualDensity: VisualDensity.compact,
            ),
          if (!widget.selectSourceMode)
            IconButton(
              focusNode: _focus.addLinkButtonFocusNode,
              icon: const Icon(Icons.add_link),
              onPressed: _catalog.isLoading ? null : _showAddLinkDialog,
              tooltip: 'Add to Premiumize',
              iconSize: iconSize,
              padding: iconPadding,
              constraints: iconConstraints,
              visualDensity: VisualDensity.compact,
            ),
          IconButton(
            focusNode: _focus.refreshButtonFocusNode,
            icon: const Icon(Icons.refresh),
            onPressed: (_catalog.isLoading || _catalog.isLoadingTransfers)
                ? null
                : _refresh,
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
          if (_isAtRoot && !_search.isSearchActive && !widget.selectSourceMode)
            _buildViewSelector(),
          if (_selection.isSelectionMode) _buildSelectionBar(),
          if (showViewModeDropdown) _buildViewModeDropdown(),
          if (_search.isSearchActive && showSearch) _buildSearchBar(),
          Expanded(
            child: FocusTraversalGroup(
              policy: OrderedTraversalPolicy(),
              child: RefreshIndicator(onRefresh: _refresh, child: _buildBody()),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_search.isSearchActive) return _buildSearchResults();
    if (_view.selectedView == PremiumizeView.transfers) {
      return _buildTransfersList();
    }
    // Folder navigation clears _items, so a fetch with nothing to show gets
    // the shimmer skeleton. Pull-to-refresh keeps its items and never hits
    // this branch — the RefreshIndicator spinner covers it.
    if (_catalog.isLoading && _catalog.items.isEmpty) {
      return const CloudRowSkeletonList();
    }
    if (_catalog.items.isEmpty) return _buildEmpty();
    return _buildFileList();
  }

  Widget _buildViewSelector() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: CloudSegmentedTabs<PremiumizeView>(
        segments: const [
          CloudSegment(PremiumizeView.files, 'My Files', Icons.folder_rounded),
          CloudSegment(
            PremiumizeView.transfers,
            'Transfers',
            Icons.swap_vert_rounded,
          ),
        ],
        selected: _view.selectedView,
        onSelected: _switchView,
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
          bottom: BorderSide(color: theme.dividerColor.withValues(alpha: 0.1)),
        ),
      ),
      child: Focus(
        skipTraversal: true,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.arrowUp) {
            _focus.backButtonFocusNode.requestFocus();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: DropdownButtonFormField<PremiumizeFolderViewMode>(
          focusNode: _focus.viewModeDropdownFocusNode,
          isExpanded: true,
          value: mode,
          decoration: InputDecoration(
            labelText: 'View Mode',
            prefixIcon: Icon(
              mode == PremiumizeFolderViewMode.raw
                  ? Icons.view_list
                  : Icons.sort_by_alpha,
              color: theme.colorScheme.primary,
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            filled: true,
            fillColor: theme.colorScheme.surfaceContainerHighest.withValues(
              alpha: 0.3,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
            ),
          ),
          items: const [
            DropdownMenuItem(
              value: PremiumizeFolderViewMode.raw,
              child: Text('Raw'),
            ),
            DropdownMenuItem(
              value: PremiumizeFolderViewMode.sortedAZ,
              child: Text('Sort (A-Z)'),
            ),
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
    final count = _selection.selectedIds.length;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.3),
        ),
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
            focusNode: _focus.deleteButtonFocusNode,
            onPressed: count > 0 ? _handleDeleteSelected : null,
            icon: const Icon(Icons.delete_outline, size: 18),
            label: const Text('Delete'),
            style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.error,
              disabledBackgroundColor: theme.colorScheme.error.withValues(
                alpha: 0.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    final app = AppThemeScope.of(context);
    final hasText = _search.searchController.text.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: TvTextField(
              controller: _search.searchController,
              focusNode: _focus.searchFocusNode,
              textInputAction: TextInputAction.search,
              // D-pad exits for Android TV (formerly a Focus/onKeyEvent
              // wrapper): up to the app-bar actions, down into the results,
              // right to the clear button when visible.
              onUpArrow: () => _focus.searchFocusNode.focusInDirection(
                TraversalDirection.up,
              ),
              onDownArrow: () => _focus.searchFocusNode.focusInDirection(
                TraversalDirection.down,
              ),
              onRightArrow: hasText
                  ? () => _focus.searchClearFocusNode.requestFocus()
                  : null,
              decoration: InputDecoration(
                hintText: _isAtRoot
                    ? 'Search your Premiumize cloud...'
                    : 'Search files...',
                prefixIcon: const Icon(Icons.search, color: Colors.grey),
                filled: true,
                fillColor: app.fade(app.core.tx, 0.06),
                border: OutlineInputBorder(
                  borderRadius: app.shape.br(8),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
              onChanged: _performSearch,
              onSubmitted: (_) => _focus.searchFocusNode.unfocus(),
            ),
          ),
          if (hasText)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Focus(
                focusNode: _focus.searchClearFocusNode,
                onKeyEvent: (node, event) {
                  if (event is! KeyDownEvent) return KeyEventResult.ignored;
                  final key = event.logicalKey;
                  if (isActivateKey(key)) {
                    setState(() {
                      _search.searchController.clear();
                      _search.searchResults = [];
                    });
                    _focus.searchFocusNode.requestFocus();
                    return KeyEventResult.handled;
                  }
                  if (key == LogicalKeyboardKey.arrowLeft) {
                    _focus.searchFocusNode.requestFocus();
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: Builder(
                  builder: (context) {
                    final isFocused = Focus.of(context).hasFocus;
                    return Container(
                      decoration: BoxDecoration(
                        color: app.fade(app.core.tx, 0.06),
                        borderRadius: app.shape.br(8),
                        border: isFocused
                            ? Border.all(color: app.core.tx, width: 2)
                            : null,
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.clear, color: Colors.grey),
                        onPressed: () {
                          setState(() {
                            _search.searchController.clear();
                            _search.searchResults = [];
                          });
                          _focus.searchFocusNode.requestFocus();
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
    if (_search.searchController.text.trim().isEmpty) {
      return Center(
        child: Text(
          _isAtRoot ? 'Type to search your cloud' : 'Type to search files',
          style: const TextStyle(color: Colors.grey),
        ),
      );
    }
    if (_search.isSearching && _search.searchResults.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_search.searchResults.isEmpty) {
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
      itemCount: _search.searchResults.length,
      itemBuilder: (context, index) {
        final item = _search.searchResults[index];
        return KeyedSubtree(
          key: ValueKey('search-${item.id}'),
          child: _buildFileCard(item, index, autofocusFirst: false),
        );
      },
    );
  }

  Widget _buildFileList() {
    return ListView.builder(
      controller: _focus.scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: _catalog.items.length,
      itemBuilder: (context, index) {
        final item = _catalog.items[index];
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
    final isVideo = item.isVideo;
    final date = _formatUnixDate(item.createdAt);
    final metaParts = <String>[
      if (!item.isFolder && item.size > 0) Formatters.formatFileSize(item.size),
      if (date.isNotEmpty) date,
    ];

    if (widget.selectSourceMode) {
      return CloudFileRow(
        kind: item.isFolder
            ? CloudRowKind.folder
            : isVideo
            ? CloudRowKind.video
            : CloudRowKind.file,
        title: item.name,
        meta: metaParts.isEmpty ? null : metaParts.join(' · '),
        onTap: (item.isFolder || isVideo)
            ? () => _selectBoundSource(item)
            : null,
        actions: item.isFolder
            ? [
                CloudRowAction(
                  icon: Icons.folder_open_rounded,
                  label: 'Browse folder',
                  onSelected: () => _navigateIntoFolder(item),
                ),
              ]
            : const [],
        focusNode: (autofocusFirst && index == 0)
            ? _focus.firstItemFocusNode
            : null,
      );
    }

    // Same action set (labels, icons, conditions) the old Open/Play pills +
    // ⋮ menu offered; the row's tap now carries Open (folders) and Play
    // (videos).
    final actions = <CloudRowAction>[
      // Videos get a ▶ too, even though tapping the row already plays them —
      // folder rows have one, and a video row without it reads as unplayable.
      if (item.isFolder || isVideo)
        CloudRowAction(
          icon: Icons.play_arrow_rounded,
          label: 'Play',
          showInStrip: true,
          onSelected: () {
            if (item.isFolder) {
              _playFolder(item);
            } else {
              _playFile(item);
            }
          },
        ),
      CloudRowAction(
        icon: Icons.download,
        label: 'Download',
        showInStrip: true,
        onSelected: () {
          if (item.isFolder) {
            _downloadFolder(item);
          } else {
            _downloadFile(item);
          }
        },
      ),
      if (item.isFolder || isVideo)
        CloudRowAction(
          icon: Icons.playlist_add,
          label: 'Add to Playlist',
          onSelected: () => _addToPlaylist(item),
        ),
      CloudRowAction(
        icon: Icons.delete_outline,
        label: 'Delete',
        destructive: true,
        onSelected: () => _showDeleteDialog(item),
      ),
    ];

    return CloudFileRow(
      kind: item.isFolder
          ? CloudRowKind.folder
          : isVideo
          ? CloudRowKind.video
          : CloudRowKind.file,
      title: item.name,
      meta: metaParts.isEmpty ? null : metaParts.join(' · '),
      onTap: item.isFolder
          ? () => _navigateIntoFolder(item)
          : isVideo
          ? () => _playFile(item)
          : null,
      actions: actions,
      selectionMode: _selection.isSelectionMode,
      selected: _selection.selectedIds.contains(item.id),
      onToggleSelected: () => _toggleSelection(item.id),
      focusNode: (autofocusFirst && index == 0)
          ? _focus.firstItemFocusNode
          : null,
    );
  }

  Widget _buildTransfersList() {
    if (_catalog.isLoadingTransfers && _catalog.transfers.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_catalog.transfers.isEmpty) {
      return ListView(
        children: [
          const SizedBox(height: 120),
          Center(
            child: Column(
              children: [
                Icon(
                  Icons.swap_vert_rounded,
                  size: 64,
                  color: Colors.grey.shade400,
                ),
                const SizedBox(height: 16),
                Text(
                  'No Transfers',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
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

    final app = AppThemeScope.of(context);
    final hasFinished = _catalog.transfers.any((t) => t.isFinished);
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
            itemCount: _catalog.transfers.length,
            itemBuilder: (context, index) =>
                _buildTransferCard(_catalog.transfers[index], app),
          ),
        ),
      ],
    );
  }

  Widget _buildTransferCard(PremiumizeTransfer transfer, AppTheme app) {
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
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
        decoration: BoxDecoration(
          color: app.fade(app.core.tx, 0.05),
          borderRadius: app.shape.br(12),
          border: Border.all(color: app.fade(app.core.tx, 0.07)),
        ),
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
                      fontWeight: FontWeight.w500,
                      fontSize: 14,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.delete_outline,
                    size: 20,
                    color: Colors.red,
                  ),
                  tooltip: 'Delete transfer',
                  onPressed: () => _deleteTransfer(transfer),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (transfer.isRunning) ...[
              ClipRRect(
                borderRadius: app.shape.br(4),
                child: LinearProgressIndicator(
                  value: transfer.progress > 0 ? transfer.progress : null,
                  minHeight: 5,
                  backgroundColor: app.fade(app.core.tx, 0.08),
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
    return CloudScaffold(
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
                Text(
                  'Premiumize Not Configured',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 16),
                Text(
                  'Add your Premiumize API key in Settings to view and manage your cloud.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade600),
                ),
                const SizedBox(height: 32),
                FilledButton.icon(
                  focusNode: _focus.settingsButtonFocusNode,
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
    return CloudScaffold(
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
                Text(
                  'Failed to Load',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 16),
                Text(
                  _catalog.errorMessage,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade600),
                ),
                const SizedBox(height: 32),
                FilledButton.icon(
                  focusNode: _focus.retryButtonFocusNode,
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

/// Original-code characterization seam: fresh state and real action tear-offs.
@visibleForTesting
Map<String, Object?> premiumizeFilesTestAccess(
  State<PremiumizeFilesScreen> state,
) {
  final s = state as _PremiumizeFilesScreenState;
  return {
    'scrollController': s._focus.scrollController,
    'apiKey': s._catalog.apiKey,
    'premiumizeEnabled': s._catalog.premiumizeEnabled,
    'isLoading': s._catalog.isLoading,
    'initialLoad': s._catalog.initialLoad,
    'errorMessage': s._catalog.errorMessage,
    'selectedView': s._view.selectedView,
    'items': s._catalog.items,
    'transfers': s._catalog.transfers,
    'isLoadingTransfers': s._catalog.isLoadingTransfers,
    'currentFolderId': s._nav.currentFolderId,
    'currentFolderName': s._nav.currentFolderName,
    'navigationStack': s._nav.navigationStack,
    'folderViewModes': s._view.folderViewModes,
    'tvContentFocusHandler': s._focus.tvContentFocusHandler,
    'shouldFocusOnLoad': s._focus.shouldFocusOnLoad,
    'linkController': s._link.linkController,
    'isAddingLink': s._link.isAddingLink,
    'isSelectionMode': s._selection.isSelectionMode,
    'selectedIds': s._selection.selectedIds,
    'isAllSelected': s._isAllSelected,
    'isSearchActive': s._search.isSearchActive,
    'isSearching': s._search.isSearching,
    'searchDebounce': s._search.searchDebounce,
    'searchController': s._search.searchController,
    'searchResults': s._search.searchResults,
    'refreshButtonFocusNode': s._focus.refreshButtonFocusNode,
    'backButtonFocusNode': s._focus.backButtonFocusNode,
    'retryButtonFocusNode': s._focus.retryButtonFocusNode,
    'settingsButtonFocusNode': s._focus.settingsButtonFocusNode,
    'viewModeDropdownFocusNode': s._focus.viewModeDropdownFocusNode,
    'addLinkButtonFocusNode': s._focus.addLinkButtonFocusNode,
    'firstItemFocusNode': s._focus.firstItemFocusNode,
    'deleteButtonFocusNode': s._focus.deleteButtonFocusNode,
    'searchFocusNode': s._focus.searchFocusNode,
    'searchButtonFocusNode': s._focus.searchButtonFocusNode,
    'searchClearFocusNode': s._focus.searchClearFocusNode,
    'isAtRoot': s._isAtRoot,
    'loadSettings': s._loadSettings,
    'loadFolder': s._loadFolder,
    'loadTransfers': s._loadTransfers,
    'refresh': s._refresh,
    'switchView': s._switchView,
    'navigateIntoFolder': s._navigateIntoFolder,
    'navigateUp': s._navigateUp,
    'handleBackNavigation': s._handleBackNavigation,
    'getCurrentViewMode': s._getCurrentViewMode,
    'setViewMode': s._setViewMode,
    'applyViewMode': s._applyViewMode,
    'applySortedView': applySortedView,
    'extractSeasonNumber': extractSeasonNumber,
    'extractLeadingNumber': extractLeadingNumber,
    'toggleSearch': s._toggleSearch,
    'performSearch': s._performSearch,
    'runCloudSearch': s._runCloudSearch,
    'selectBoundSource': s._selectBoundSource,
    'playFile': s._playFile,
    'playFolder': s._playFolder,
    'playPremiumizeVideos': s._playPremiumizeVideos,
    'downloadFile': s._downloadFile,
    'downloadFolder': s._downloadFolder,
    'downloadSelectedFiles': s._downloadSelectedFiles,
    'addToPlaylist': s._addToPlaylist,
    'addFileToPlaylist': s._addFileToPlaylist,
    'addFolderToPlaylist': s._addFolderToPlaylist,
    'showDeleteDialog': s._showDeleteDialog,
    'handleDeleteSelected': s._handleDeleteSelected,
    'executeDelete': s._executeDelete,
    'deleteTransfer': s._deleteTransfer,
    'clearFinishedTransfers': s._clearFinishedTransfers,
    'showAddLinkDialog': s._showAddLinkDialog,
    'autoPasteLink': s._autoPasteLink,
    'addLink': s._addLink,
    'toggleSelectionMode': s._toggleSelectionMode,
    'exitSelectionMode': s._exitSelectionMode,
    'toggleSelection': s._toggleSelection,
    'toggleSelectAll': s._toggleSelectAll,
    'showLoadingDialog': s._showLoadingDialog,
    'dismissDialog': s._dismissDialog,
    'focusFirstItemOrFallback': s._focusFirstItemOrFallback,
    'showSnackBar': s._showSnackBar,
    'formatUnixDate': s._formatUnixDate,
    'formatPlaylistTitle': formatPlaylistTitle,
    'composeEntryTitle': composeEntryTitle,
    'findFirstEpisodeIndex': findFirstEpisodeIndex,
    'isBrowsePush': s._isBrowsePush,
    'rawMode': PremiumizeFolderViewMode.raw,
    'sortedMode': PremiumizeFolderViewMode.sortedAZ,
    'filesView': PremiumizeView.files,
    'transfersView': PremiumizeView.transfers,
  };
}
