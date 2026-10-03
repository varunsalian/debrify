import 'package:debrify/features/debrid_downloads/presentation/legacy_debrid/debrid_catalog_state.dart';
import 'package:debrify/features/debrid_downloads/presentation/legacy_debrid/debrid_download_state.dart';
import 'package:debrify/features/debrid_downloads/presentation/legacy_debrid/debrid_navigation_state.dart';
import 'package:debrify/features/debrid_downloads/presentation/legacy_debrid/debrid_view_state.dart';
import 'package:debrify/features/debrid_downloads/presentation/legacy_debrid/debrid_focus_state.dart';
import 'package:debrify/features/debrid_downloads/presentation/legacy_debrid/debrid_folder_search_state.dart';
import 'package:debrify/features/debrid_downloads/presentation/legacy_debrid/debrid_torrent_search_state.dart';
import 'package:debrify/features/debrid_downloads/presentation/legacy_debrid/debrid_selection_state.dart';
import 'package:debrify/features/debrid_downloads/presentation/legacy_debrid/debrid_add_input_state.dart';
import 'package:debrify/features/debrid_downloads/presentation/legacy_debrid/debrid_focus_actions.dart';
import 'package:debrify/features/debrid_downloads/presentation/legacy_debrid/debrid_back_navigation.dart';
import 'package:debrify/features/debrid_downloads/presentation/legacy_debrid/debrid_catalog_loading.dart';
import 'package:debrify/features/debrid_downloads/presentation/legacy_debrid/debrid_download_row_actions.dart';
import 'package:debrify/features/debrid_downloads/presentation/legacy_debrid/debrid_single_delete_actions.dart';
import 'package:debrify/features/debrid_downloads/presentation/legacy_debrid/debrid_delete_all_actions.dart';
import 'package:debrify/features/debrid_downloads/presentation/legacy_debrid/debrid_torrent_bulk_delete.dart';
import 'package:debrify/features/debrid_downloads/presentation/legacy_debrid/debrid_download_bulk_delete.dart';
import 'package:debrify/features/debrid_downloads/presentation/legacy_debrid/debrid_selection_actions.dart';
import 'package:debrify/features/debrid_downloads/presentation/legacy_debrid/debrid_selected_delete.dart';
import 'package:debrify/features/debrid_downloads/presentation/legacy_debrid/debrid_feedback.dart';
import 'package:debrify/features/debrid_downloads/presentation/legacy_debrid/debrid_sections.dart';
import 'package:debrify/features/debrid_downloads/models/debrid_downloads_view.dart';
import 'package:debrify/features/debrid_downloads/models/folder_view_mode.dart';
import 'package:debrify/features/debrid_downloads/models/rd_search_result.dart';
import 'package:debrify/features/debrid_downloads/application/debrid_folder_policy.dart';
import 'package:debrify/features/debrid_downloads/application/debrid_input_policy.dart';
import 'package:debrify/features/debrid_downloads/application/debrid_error_policy.dart';
import 'dart:convert';

import 'package:debrify/services/storage/playlist_storage.dart';
import 'package:debrify/services/storage/real_debrid_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/playlist_view_mode.dart';
import '../models/rd_torrent.dart';
import '../models/rd_file_node.dart';
import '../models/debrid_download.dart';
import '../services/analytics_service.dart';
import '../theme/app_theme_scope.dart';
import '../services/debrid_service.dart';
import '../services/series_source_service.dart';
import '../utils/formatters.dart';
import '../utils/file_utils.dart';
import '../utils/series_parser.dart';
import '../utils/rd_folder_tree_builder.dart';
import '../utils/platform_util.dart';
import 'video_player_screen.dart';
import '../services/video_player_launcher.dart';
import '../services/download_service.dart';
import '../services/main_page_bridge.dart';
import '../widgets/debrify_tv_channel_add_bridge.dart';
import '../widgets/cloud/cloud_file_row.dart';
import '../widgets/cloud/cloud_row_skeleton.dart';
import '../widgets/cloud/cloud_segmented_tabs.dart';
import '../widgets/cloud/cloud_theme.dart';
import '../widgets/file_selection_dialog.dart';
import '../widgets/tv_text_field.dart';
import '../utils/tv_keys.dart';

class DebridDownloadsScreen extends StatefulWidget {
  const DebridDownloadsScreen({
    super.key,
    this.initialTorrentForOptions,
    this.isPushedRoute = false,
    this.initialSearchQuery,
    this.selectSourceMode = false,
    this.onSourceSelected,
  });

  final RDTorrent? initialTorrentForOptions;

  /// When true, this screen was pushed as a route (not displayed in a tab).
  /// Back navigation will pop the route instead of switching tabs.
  final bool isPushedRoute;

  /// Pre-populate torrent search with this query on init.
  final String? initialSearchQuery;

  /// When true, torrent cards show "Select" instead of Open/Play/3-dot.
  final bool selectSourceMode;

  /// Called when user selects a torrent in select-source mode.
  final void Function(SeriesSource)? onSourceSelected;

  @override
  State<DebridDownloadsScreen> createState() => _DebridDownloadsScreenState();
}

class _DebridDownloadsScreenState extends State<DebridDownloadsScreen> {
  final _catalog = DebridCatalogState();
  final _downloadState = DebridDownloadState();
  final _nav = DebridNavigationState();
  final _view = DebridViewState();
  final _focus = DebridFocusState();
  final _folderSearch = DebridFolderSearchState();
  final _torrentSearch = DebridTorrentSearchState();
  final _selection = DebridSelectionState();
  final _addInput = DebridAddInputState();
  late final _sections = _createSections();

  DebridSections _createSections() {
    final sections = DebridSections();
    sections.focusActions = DebridFocusActions((
    focusState: _focus,
    mounted: () => mounted,
    navigationState: _nav,
    catalogState: _catalog,
    downloadState: _downloadState,
    ));
    sections.backNavigation = DebridBackNavigation((
    context: () => context,
    selectionState: _selection,
    exitSelectionMode: () => sections.selectionActions.exitSelectionMode(),
    folderSearchState: _folderSearch,
    toggleSearch: () => _toggleSearch(),
    navigationState: _nav,
    navigateUp: () => _navigateUp(),
    selectSourceMode: () => widget.selectSourceMode,
    isPushedRoute: () => widget.isPushedRoute,
    initialTorrentForOptions: () => widget.initialTorrentForOptions,
    ));
    sections.catalogLoading = DebridCatalogLoading((
    focusState: _focus,
    catalogState: _catalog,
    downloadState: _downloadState,
    mounted: () => mounted,
    setState: setState,
    submitTorrentSearch: () => _submitTorrentSearch(),
    initialSearchQuery: () => widget.initialSearchQuery,
    focusFirstItemOrFallback: () => sections.focusActions.focusFirstItemOrFallback(),
    ));
    sections.downloadRowActions = DebridDownloadRowActions((
    catalogState: _catalog,
    copyToClipboard: (String text) => sections.feedback.copyToClipboard(text),
    mounted: () => mounted,
    context: () => context,
    showError: (String message) => sections.feedback.showError(message),
    ));
    sections.singleDeleteActions = DebridSingleDeleteActions((
    catalogState: _catalog,
    context: () => context,
    mounted: () => mounted,
    setState: setState,
    showSuccess: (String message) => sections.feedback.showSuccess(message),
    showError: (String message) => sections.feedback.showError(message),
    downloadState: _downloadState,
    ));
    sections.deleteAllActions = DebridDeleteAllActions((
    catalogState: _catalog,
    context: () => context,
    mounted: () => mounted,
    showDeleteAllProgressDialog: () => sections.torrentBulkDelete.showDeleteAllProgressDialog(),
    downloadState: _downloadState,
    showDeleteAllDownloadsProgressDialog: () => sections.downloadBulkDelete.showDeleteAllDownloadsProgressDialog(),
    ));
    sections.torrentBulkDelete = DebridTorrentBulkDelete((
    context: () => context,
    catalogState: _catalog,
    mounted: () => mounted,
    fetchTorrents: (String apiKey, {bool reset = false}) => sections.catalogLoading.fetchTorrents(apiKey, reset: reset),
    setState: setState,
    showSuccess: (String message) => sections.feedback.showSuccess(message),
    showError: (String message) => sections.feedback.showError(message),
    ));
    sections.downloadBulkDelete = DebridDownloadBulkDelete((
    context: () => context,
    catalogState: _catalog,
    mounted: () => mounted,
    fetchDownloads: (String apiKey, {bool reset = false}) => sections.catalogLoading.fetchDownloads(apiKey, reset: reset),
    setState: setState,
    downloadState: _downloadState,
    showSuccess: (String message) => sections.feedback.showSuccess(message),
    showError: (String message) => sections.feedback.showError(message),
    ));
    sections.selectionActions = DebridSelectionActions((
    catalogState: _catalog,
    selectionState: _selection,
    downloadState: _downloadState,
    setState: setState,
    context: () => context,
    mounted: () => mounted,
    showDeleteSelectedProgressDialog: (Set<String> ids, bool isTorrents) => sections.selectedDelete.showDeleteSelectedProgressDialog(ids, isTorrents),
    ));
    sections.selectedDelete = DebridSelectedDelete((
    context: () => context,
    catalogState: _catalog,
    mounted: () => mounted,
    setState: setState,
    downloadState: _downloadState,
    selectionState: _selection,
    showSuccess: (String message) => sections.feedback.showSuccess(message),
    showError: (String message) => sections.feedback.showError(message),
    ));
    sections.feedback = DebridFeedback((
    context: () => context,
    ));
    return sections;
  }

  // TV content focus handler (stored for proper unregistration)

  // Torrent Downloads data

  // Downloads data

  // Folder navigation state

   // e.g., ["Season 1", "Episodes"]

   // Current folder contents

  // View mode state

  // Magnet input

  // Link input

  // Multi-select state

  // TV/DPAD navigation

  // Flag to focus first item after data loads (set by TV content focus handler)

  // Torrent list search state

  // Whether RD is hidden from bottom-nav. In selectSourceMode we use this to
  // decide whether to restrict searches to queries matching the show title.

  // Search state (for folder browsing mode)

  @override
  void initState() {
    super.initState();
    AnalyticsService.screenView('debrid_downloads');

    // Row 0 binds this node; CloudFileRow supplies the key handling (its
    // upFocusNode routes ↑ to the torrent search field when active).
    _focus.firstItemFocusNode = FocusNode(debugLabel: 'rd-first-item');

    // Initialize torrent search focus node with DPAD key handler
    _focus.torrentSearchFocusNode = FocusNode(
      debugLabel: 'rd-torrent-search',
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;
        if (key == LogicalKeyboardKey.arrowUp) {
          // Up escapes the field toward the view-selector tabs above it.
          node.focusInDirection(TraversalDirection.up);
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowDown) {
          _focus.firstItemFocusNode.requestFocus();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
    );

    if (widget.selectSourceMode &&
        widget.initialSearchQuery != null &&
        widget.initialSearchQuery!.isNotEmpty) {
      _torrentSearch.isTorrentSearchActive = true;
      _torrentSearch.torrentSearchController.text = widget.initialSearchQuery!;
      RealDebridStorage.getRealDebridHiddenFromNav().then((v) {
        if (mounted) setState(() => _torrentSearch.hiddenFromNav = v);
      });
    }

    _sections.catalogLoading.loadApiKeyAndData();
    _focus.torrentScrollController.addListener(_sections.catalogLoading.onTorrentScroll);
    _focus.downloadScrollController.addListener(_sections.catalogLoading.onDownloadScroll);

    // Register back navigation handler for folder navigation
    if (widget.isPushedRoute) {
      // Pushed as a route - use pushed route handler
      MainPageBridge.pushRouteBackHandler(_sections.backNavigation.handleBackNavigation);
      // Set up timeout - if a DEEP LINK into a specific torrent hasn't resolved
      // after 10s, pop and show an error. Only when we were actually deep-linked
      // (initialTorrentForOptions); when browsing from the Cloud hub there's no
      // target, so the torrents-list root is the resting state — no timeout.
      Future.delayed(const Duration(seconds: 10), () {
        if (mounted &&
            widget.isPushedRoute &&
            !widget.selectSourceMode &&
            widget.initialTorrentForOptions != null &&
            _nav.currentTorrentId == null) {
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
      // Displayed in a tab
      MainPageBridge.registerTabBackHandler(
        'realdebrid',
        _sections.backNavigation.handleBackNavigation,
      );
      // Register TV sidebar focus handler (tab index 4 = Real Debrid)
      _focus.tvContentFocusHandler = () {
        // Set flag to focus after data loads
        _focus.shouldFocusOnLoad = true;
        // Try to focus now in case data is already loaded
        _sections.focusActions.focusFirstItemOrFallback();
      };
      MainPageBridge.registerTvContentFocusHandler(4, _focus.tvContentFocusHandler!);
    }

    // If asked to show options for a specific torrent, open after init
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (widget.initialTorrentForOptions != null) {
        // Wait until API key is loaded
        int attempts = 0;
        while (_catalog.apiKey == null && attempts < 20) {
          await Future.delayed(const Duration(milliseconds: 150));
          attempts++;
        }

        if (mounted && _catalog.apiKey != null) {
          // Navigate into the torrent folder instead of showing dialog
          await _navigateIntoTorrent(widget.initialTorrentForOptions!);
        }
      }
    });
  }

  @override
  void dispose() {
    // Unregister back navigation handler
    if (widget.isPushedRoute) {
      MainPageBridge.popRouteBackHandler(_sections.backNavigation.handleBackNavigation);
    } else {
      MainPageBridge.unregisterTabBackHandler('realdebrid');
      if (_focus.tvContentFocusHandler != null) {
        MainPageBridge.unregisterTvContentFocusHandler(
          4,
          _focus.tvContentFocusHandler!,
        );
      }
    }

    _focus.torrentScrollController.dispose();
    _focus.downloadScrollController.dispose();
    _addInput.magnetController.dispose();
    _addInput.linkController.dispose();

    // Dispose focus nodes
    _focus.backButtonFocusNode.dispose();
    _focus.refreshButtonFocusNode.dispose();
    _focus.viewModeDropdownFocusNode.dispose();
    _focus.firstItemFocusNode.dispose();
    _focus.deleteButtonFocusNode.dispose();
    _folderSearch.searchController.dispose();
    _focus.searchFocusNode.dispose();
    _focus.searchButtonFocusNode.dispose();
    _focus.searchClearFocusNode.dispose();
    _torrentSearch.torrentSearchController.dispose();
    _focus.torrentSearchFocusNode.dispose();
    _focus.torrentSearchClearFocusNode.dispose();

    super.dispose();
  }

  // Torrent list search methods

  void _toggleTorrentSearch() {
    if (widget.selectSourceMode) return;
    setState(() {
      _torrentSearch.isTorrentSearchActive = !_torrentSearch.isTorrentSearchActive;
      if (!_torrentSearch.isTorrentSearchActive) {
        _torrentSearch.torrentSearchController.clear();
        _torrentSearch.torrentSearchQuery = '';
        _torrentSearch.allTorrentsForSearch.clear();
      }
    });
  }

  bool _queryMatchesInitialTitle(String query) {
    final title = widget.initialSearchQuery;
    if (title == null || title.isEmpty) return true;
    const stopwords = {'the', 'a', 'an'};
    final rawTokens = title
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9]+'))
        .where((t) => t.isNotEmpty)
        .toList();
    final filtered = rawTokens
        .where((t) => !stopwords.contains(t) && t.length >= 2)
        .toList();
    final effectiveTokens = filtered.isEmpty ? rawTokens : filtered;
    if (effectiveTokens.isEmpty) return true;
    final normalizedQuery = query.toLowerCase();
    return effectiveTokens.any((t) => normalizedQuery.contains(t));
  }

  void _submitTorrentSearch() {
    final query = _torrentSearch.torrentSearchController.text.trim();
    if (query.isEmpty) {
      _focus.torrentSearchSubmitFocus.cancel();
      return;
    }
    if (widget.selectSourceMode &&
        _torrentSearch.hiddenFromNav &&
        !_queryMatchesInitialTitle(query)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Search must include part of "${widget.initialSearchQuery}"',
          ),
          backgroundColor: const Color(0xFFF59E0B),
          duration: const Duration(seconds: 3),
        ),
      );
      _focus.torrentSearchSubmitFocus.cancel();
      return;
    }
    _focus.torrentSearchSubmitFocus.arm(enabled: PlatformUtil.isTelevision);
    setState(() => _torrentSearch.torrentSearchQuery = query);
    if (_torrentSearch.allTorrentsForSearch.isEmpty) {
      if (!_torrentSearch.isLoadingSearch) _fetchAllTorrentsForSearch();
    } else {
      setState(() {}); // Trigger rebuild with new query
      _completeTorrentSearchSubmitFocus();
    }
  }

  void _completeTorrentSearchSubmitFocus() {
    if (_filteredSearchTorrents.isEmpty) {
      _focus.torrentSearchSubmitFocus.cancel();
      return;
    }
    _focus.torrentSearchSubmitFocus.complete(
      field: _focus.torrentSearchFocusNode,
      isMounted: () => mounted,
      requestFocus: _focus.firstItemFocusNode.requestFocus,
      targetHasFocus: () => _focus.firstItemFocusNode.hasFocus,
    );
  }

  Future<void> _fetchAllTorrentsForSearch() async {
    if (_catalog.apiKey == null) {
      _focus.torrentSearchSubmitFocus.cancel();
      return;
    }
    setState(() => _torrentSearch.isLoadingSearch = true);

    try {
      final List<RDTorrent> allTorrents = [];
      int page = 1;
      bool hasMore = true;

      while (hasMore) {
        final result = await DebridService.getTorrents(
          _catalog.apiKey!,
          page: page,
          limit: 2000,
        );
        final List<RDTorrent> batch = result['torrents'];
        allTorrents.addAll(batch);
        hasMore = result['hasMore'] && batch.isNotEmpty;
        page++;
        // Safety cap at 3 pages (6000 torrents max)
        if (page > 3) break;
      }

      if (mounted) {
        setState(() {
          _torrentSearch.allTorrentsForSearch = allTorrents;
          _torrentSearch.isLoadingSearch = false;
        });
        _completeTorrentSearchSubmitFocus();
      }
    } catch (e) {
      if (mounted) {
        _focus.torrentSearchSubmitFocus.cancel();
        setState(() => _torrentSearch.isLoadingSearch = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to load torrents for search: ${e.toString()}',
            ),
          ),
        );
      }
    }
  }

  List<RDTorrent> get _filteredSearchTorrents {
    if (widget.selectSourceMode && _torrentSearch.torrentSearchQuery.isEmpty) return [];
    final downloaded = _torrentSearch.allTorrentsForSearch.where((t) => t.isDownloaded);
    if (_torrentSearch.torrentSearchQuery.isEmpty) return downloaded.toList();
    final query = _torrentSearch.torrentSearchQuery.toLowerCase();
    return downloaded
        .where((t) => t.filename.toLowerCase().contains(query))
        .toList();
  }

  // Downloads methods

  Future<void> _handlePlayVideo(RDTorrent torrent) async {
    if (_catalog.apiKey == null) return;

    if (torrent.links.length == 1) {
      // Single file - check MIME type after unrestricting
      try {
        final unrestrictResult = await DebridService.unrestrictLink(
          _catalog.apiKey!,
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
            _sections.feedback.showError('This file is not a video (MIME type: $mimeType)');
          }
        }
      } catch (e) {
        if (mounted) {
          _sections.feedback.showError('Failed to load video: ${e.toString()}');
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

  // --- Multi-select helpers ---

  // ========== Folder Navigation Methods ==========

  Future<void> _navigateIntoTorrent(RDTorrent torrent) async {
    if (_catalog.apiKey == null) return;

    _sections.selectionActions.exitSelectionMode();

    // Focus first item after folder contents load
    _focus.shouldFocusOnLoad = true;
    _sections.catalogLoading.resetListScroll();

    setState(() {
      _nav.isLoadingFolder = true;
    });

    try {
      // Get torrent info to check for RAR archives
      final torrentInfo = await DebridService.getTorrentInfo(
        _catalog.apiKey!,
        torrent.id,
      );
      final files =
          (torrentInfo['files'] as List<dynamic>?)
              ?.map((f) => f as Map<String, dynamic>)
              .toList() ??
          [];
      final links = (torrentInfo['links'] as List<dynamic>?) ?? [];

      // Check if this is a RAR archive
      final isRarArchive = RDFolderTreeBuilder.isRarArchive(files, links);

      if (isRarArchive) {
        // Show a message that this cannot be browsed
        setState(() {
          _nav.isLoadingFolder = false;
        });

        // Show dialog explaining RAR archives and offering to download
        if (mounted) {
          await showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: AppThemeScope.of(ctx).cloud.dialogSurface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF59E0B),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.archive,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'RAR Archive Detected',
                      style: TextStyle(fontWeight: FontWeight.bold),
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
                  child: const Text(
                    'Cancel',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
                TextButton(
                  onPressed: () async {
                    Navigator.of(ctx).pop();
                    // Download the single RAR file
                    if (links.isNotEmpty) {
                      try {
                        final unrestrictResult =
                            await DebridService.unrestrictLink(
                              _catalog.apiKey!,
                              links[0],
                            );
                        final downloadUrl =
                            unrestrictResult['download'] as String?;
                        if (downloadUrl != null) {
                          _sections.feedback.copyToClipboard(downloadUrl);
                        }
                      } catch (e) {
                        _sections.feedback.showError(
                          'Failed to get download link: ${e.toString()}',
                        );
                      }
                    }
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF60A5FA),
                  ),
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
        _catalog.apiKey!,
        torrent.id,
      );
      final rootNodes = RDFolderTreeBuilder.getRootLevelNodes(folderTree);

      // Initialize view mode for this torrent if not already set
      _view.torrentViewModes.putIfAbsent(torrent.id, () => FolderViewMode.raw);

      // Apply view mode transformation to root nodes
      final mode = _view.torrentViewModes[torrent.id]!;
      List<RDFileNode> transformedNodes;
      switch (mode) {
        case FolderViewMode.raw:
          transformedNodes = rootNodes;
          break;
        case FolderViewMode.sortedAZ:
          transformedNodes = applySortedView(rootNodes);
          break;
        case FolderViewMode.seriesArrange:
          transformedNodes = applySeriesArrangedView(rootNodes);
          break;
      }

      if (!mounted) return;
      setState(() {
        _nav.currentTorrentId = torrent.id;
        _nav.currentTorrent = torrent;
        _nav.currentFolderTree = folderTree;
        _nav.currentViewNodes = transformedNodes;
        _nav.folderPath = [];
        _nav.isLoadingFolder = false;
      });

      // Focus first item after folder contents load
      _sections.focusActions.focusFirstItemOrFallback();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _nav.isLoadingFolder = false;
      });
      _sections.feedback.showError('Failed to load torrent contents: ${e.toString()}');
    }
  }

  /// Navigate into a folder
  void _navigateIntoFolder(RDFileNode folder) {
    if (!folder.isFolder) return;

    // Focus first item after navigation
    _focus.shouldFocusOnLoad = true;

    // Apply view mode to folder children
    // NOTE: Series Arrange only makes sense at root level (it creates virtual Season folders)
    // When inside any folder, show files in sorted or raw view
    final mode = _getCurrentViewMode();
    List<RDFileNode> transformedChildren;

    if (mode == FolderViewMode.seriesArrange) {
      // Inside a folder with Series Arrange mode: show files sorted by name
      transformedChildren = applySortedView(folder.children);
    } else {
      switch (mode) {
        case FolderViewMode.raw:
          transformedChildren = folder.children;
          break;
        case FolderViewMode.sortedAZ:
          transformedChildren = applySortedView(folder.children);
          break;
        case FolderViewMode.seriesArrange:
          // Should never reach here
          transformedChildren = folder.children;
          break;
      }
    }

    setState(() {
      _nav.folderPath.add(folder.name);
      _nav.currentViewNodes = transformedChildren;
    });

    // Focus first item after navigation
    _sections.focusActions.focusFirstItemOrFallback();
  }

  /// Navigate up one level
  void _navigateUp() {
    // Refocus the first row once the previous listing shows — the focused
    // row is disposed by the swap and nothing else reclaims DPAD focus.
    _focus.shouldFocusOnLoad = true;
    _sections.catalogLoading.resetListScroll();
    if (_nav.folderPath.isEmpty && _nav.currentTorrentId != null) {
      // Go back to torrents list
      setState(() {
        _nav.currentTorrentId = null;
        _nav.currentTorrent = null;
        _nav.currentFolderTree = null;
        _nav.currentViewNodes = null;
        _nav.folderPath = [];
      });
      _sections.focusActions.focusFirstItemOrFallback();
    } else if (_nav.folderPath.isNotEmpty && _nav.currentFolderTree != null) {
      // Go up one folder level
      _nav.folderPath.removeLast();

      // Get raw nodes at the new path
      List<RDFileNode> rawNodes;
      if (_nav.folderPath.isEmpty) {
        rawNodes = RDFolderTreeBuilder.getRootLevelNodes(_nav.currentFolderTree!);
      } else {
        // Find the folder node at the current path
        RDFileNode currentNode = _nav.currentFolderTree!;
        for (final folderName in _nav.folderPath) {
          final childFolder = currentNode.children
              .cast<RDFileNode?>()
              .firstWhere(
                (node) => node?.name == folderName && node?.isFolder == true,
                orElse: () => null,
              );
          if (childFolder != null) {
            currentNode = childFolder;
          } else {
            // Folder not found - reset to root
            _nav.folderPath.clear();
            rawNodes = RDFolderTreeBuilder.getRootLevelNodes(
              _nav.currentFolderTree!,
            );
            // Apply view mode and set state
            final mode = _getCurrentViewMode();
            List<RDFileNode> transformedNodes;
            switch (mode) {
              case FolderViewMode.raw:
                transformedNodes = rawNodes;
                break;
              case FolderViewMode.sortedAZ:
                transformedNodes = applySortedView(rawNodes);
                break;
              case FolderViewMode.seriesArrange:
                transformedNodes = applySeriesArrangedView(rawNodes);
                break;
            }
            setState(() {
              _nav.currentViewNodes = transformedNodes;
            });
            _sections.focusActions.focusFirstItemOrFallback();
            return;
          }
        }
        rawNodes = currentNode.children;
      }

      // Apply view mode transformation
      // NOTE: Series Arrange only applies at root level
      final mode = _getCurrentViewMode();
      List<RDFileNode> transformedNodes;

      if (mode == FolderViewMode.seriesArrange && _nav.folderPath.isNotEmpty) {
        // Still inside a folder after going up - use sorted view
        transformedNodes = applySortedView(rawNodes);
      } else {
        switch (mode) {
          case FolderViewMode.raw:
            transformedNodes = rawNodes;
            break;
          case FolderViewMode.sortedAZ:
            transformedNodes = applySortedView(rawNodes);
            break;
          case FolderViewMode.seriesArrange:
            transformedNodes = applySeriesArrangedView(rawNodes);
            break;
        }
      }

      setState(() {
        _nav.currentViewNodes = transformedNodes;
      });
      _sections.focusActions.focusFirstItemOrFallback();
    }
  }

  String _getCurrentFolderTitle() {
    if (_nav.currentTorrentId == null) return '';
    if (_nav.folderPath.isEmpty) {
      return _nav.currentTorrent?.filename ?? 'Torrent Files';
    }
    return _nav.folderPath.last;
  }

  /// Get current view mode for active torrent
  FolderViewMode _getCurrentViewMode() {
    if (_nav.currentTorrentId == null) return FolderViewMode.raw;
    return _view.torrentViewModes[_nav.currentTorrentId] ?? FolderViewMode.raw;
  }

  /// Set view mode and refresh display
  void _setViewMode(FolderViewMode mode) {
    if (_nav.currentTorrentId == null || _nav.currentViewNodes == null) return;

    // Get raw nodes based on current path
    List<RDFileNode> rawNodes;
    if (_nav.folderPath.isEmpty && _nav.currentFolderTree != null) {
      rawNodes = RDFolderTreeBuilder.getRootLevelNodes(_nav.currentFolderTree!);
    } else if (_nav.currentFolderTree != null) {
      // Navigate to current path to get raw nodes
      RDFileNode currentNode = _nav.currentFolderTree!;
      for (final folderName in _nav.folderPath) {
        final childFolder = currentNode.children.cast<RDFileNode?>().firstWhere(
          (node) => node?.name == folderName && node?.isFolder == true,
          orElse: () => null,
        );
        if (childFolder != null) {
          currentNode = childFolder;
        } else {
          setState(() {
            _nav.currentViewNodes = [];
          });
          return;
        }
      }
      rawNodes = currentNode.children;
    } else {
      return;
    }

    // If user selected Series Arrange, detect if content is actually a series
    if (mode == FolderViewMode.seriesArrange) {
      final isSeries = detectSeriesPattern(rawNodes);

      if (!isSeries) {
        // Not a series - show snackbar and fallback to sorted view
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'No series detected in this folder. Switching to Sort (A-Z) view.',
            ),
            duration: const Duration(seconds: 3),
            backgroundColor: AppThemeScope.of(context).cloud.dialogSurface,
            behavior: SnackBarBehavior.floating,
          ),
        );

        // Switch to sorted view instead
        setState(() {
          _view.torrentViewModes[_nav.currentTorrentId!] = FolderViewMode.sortedAZ;
          _nav.currentViewNodes = applySortedView(rawNodes);
        });
        return;
      }
    }

    // Apply transformation based on mode
    setState(() {
      _view.torrentViewModes[_nav.currentTorrentId!] = mode;

      switch (mode) {
        case FolderViewMode.raw:
          _nav.currentViewNodes = rawNodes;
          break;
        case FolderViewMode.sortedAZ:
          _nav.currentViewNodes = applySortedView(rawNodes);
          break;
        case FolderViewMode.seriesArrange:
          _nav.currentViewNodes = applySeriesArrangedView(rawNodes);
          break;
      }
    });
  }

  // ============ Search Methods ============

  /// Toggle search mode on/off
  void _toggleSearch() {
    setState(() {
      _folderSearch.isSearchActive = !_folderSearch.isSearchActive;
      if (!_folderSearch.isSearchActive) {
        _folderSearch.searchController.clear();
        _folderSearch.searchResults.clear();
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _focus.searchFocusNode.requestFocus();
        });
      }
    });
  }

  /// Perform deep search across all files in current torrent
  void _performSearch(String query) {
    if (_nav.currentFolderTree == null || query.isEmpty) {
      setState(() => _folderSearch.searchResults = []);
      return;
    }

    final lowerQuery = query.toLowerCase();
    final results = <RDSearchResult>[];

    void searchNode(RDFileNode node, List<String> path) {
      if (!node.isFolder) {
        if (FileUtils.isVideoFile(node.name) &&
            node.name.toLowerCase().contains(lowerQuery)) {
          results.add(RDSearchResult(node: node, path: path.join(' / ')));
        }
      } else {
        for (final child in node.children) {
          searchNode(child, [...path, node.name]);
        }
      }
    }

    for (final child in _nav.currentFolderTree!.children) {
      searchNode(child, []);
    }

    setState(() => _folderSearch.searchResults = results);
  }

  /// Build the search bar widget
  Widget _buildSearchBar() {
    final app = AppThemeScope.of(context);
    final hasText = _folderSearch.searchController.text.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: TvTextField(
              controller: _folderSearch.searchController,
              focusNode: _focus.searchFocusNode,
              textInputAction: TextInputAction.search,
              // D-pad exits for Android TV (formerly a Focus/onKeyEvent wrapper)
              onUpArrow: () => _focus.searchFocusNode.unfocus(),
              onDownArrow: () => _focus.searchFocusNode.unfocus(),
              onRightArrow: hasText
                  ? () => _focus.searchClearFocusNode.requestFocus()
                  : null,
              decoration: InputDecoration(
                hintText: 'Search all files...',
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
          // Clear button - separate focusable widget for D-pad navigation
          if (hasText)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Focus(
                focusNode: _focus.searchClearFocusNode,
                onKeyEvent: (node, event) {
                  if (event is! KeyDownEvent) return KeyEventResult.ignored;
                  final key = event.logicalKey;

                  // Select/Enter: clear search
                  if (isActivateKey(key)) {
                    setState(() {
                      _folderSearch.searchController.clear();
                      _folderSearch.searchResults.clear();
                    });
                    _focus.searchFocusNode.requestFocus();
                    return KeyEventResult.handled;
                  }

                  // Arrow Left: go back to TextField
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
                        color: const Color(0xFF1E293B),
                        borderRadius: app.shape.br(8),
                        border: isFocused
                            // Pinned with the slate fill above, which does
                            // not follow the palette: a paper theme's
                            // near-black ring on dark slate is a ring you
                            // cannot see.
                            ? Border.all(color: Colors.white, width: 2)
                            : null,
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.clear, color: Colors.grey),
                        onPressed: () {
                          setState(() {
                            _folderSearch.searchController.clear();
                            _folderSearch.searchResults.clear();
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

  /// Build search results list
  Widget _buildSearchResults() {
    if (_folderSearch.searchController.text.isEmpty) {
      return const Center(
        child: Text(
          'Type to search all files',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    if (_folderSearch.searchResults.isEmpty) {
      return const Center(
        child: Text('No files found', style: TextStyle(color: Colors.grey)),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _folderSearch.searchResults.length,
      itemBuilder: (context, index) {
        final result = _folderSearch.searchResults[index];
        return _buildSearchResultCard(result, index);
      },
    );
  }

  /// Build a card for a search result
  Widget _buildSearchResultCard(RDSearchResult result, int index) {
    final node = result.node;
    final borderColor = Colors.white.withValues(alpha: 0.08);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1F2A44), Color(0xFF111C32)],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor, width: 1.2),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => _playFile(node),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(
                  Icons.play_circle_outline,
                  color: Colors.blue,
                  size: 32,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        node.name,
                        style: const TextStyle(fontWeight: FontWeight.w500),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (result.path.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          result.path,
                          style: TextStyle(
                            color: Colors.grey[500],
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      if (node.bytes != null)
                        Text(
                          Formatters.formatFileSize(node.bytes!),
                          style: TextStyle(
                            color: Colors.grey[400],
                            fontSize: 12,
                          ),
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

  @override
  Widget build(BuildContext context) {
    // When DEEP-LINKED into a specific torrent (pushed WITH a target) and still
    // at root, show the loading state while we navigate into it. When browsing
    // from the Cloud hub there's no target, so the torrents-list root is the
    // real content — don't gate it behind a spinner.
    if (widget.isPushedRoute &&
        !widget.selectSourceMode &&
        widget.initialTorrentForOptions != null &&
        _nav.currentTorrentId == null) {
      return CloudScaffold(
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

    // If in folder browsing mode, show folder view
    if (_nav.currentTorrentId != null) {
      return _buildFolderBrowserScaffold();
    }

    final Widget content = _catalog.selectedView == DebridDownloadsView.torrents
        ? _buildTorrentContent()
        : _buildDownloadContent();

    return CloudScaffold(
      appBar: widget.selectSourceMode
          ? AppBar(
              leading: IconButton(
                focusNode: _focus.backButtonFocusNode,
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.of(context).pop(),
                tooltip: 'Back',
              ),
              title: const Text('Select Source from Real-Debrid'),
            )
          : null,
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
      child: Focus(
        skipTraversal: true,
        onKeyEvent: (node, event) {
          // Navigate to back button on up arrow
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.arrowUp) {
            _focus.backButtonFocusNode.requestFocus();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: DropdownButtonFormField<FolderViewMode>(
          focusNode: _focus.viewModeDropdownFocusNode,
          autofocus: true,
          isExpanded: true,
          value: mode,
          decoration: InputDecoration(
            labelText: 'View Mode',
            prefixIcon: Icon(
              mode == FolderViewMode.raw
                  ? Icons.view_list
                  : mode == FolderViewMode.sortedAZ
                  ? Icons.sort_by_alpha
                  : Icons.video_library,
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
            DropdownMenuItem(value: FolderViewMode.raw, child: Text('Raw')),
            DropdownMenuItem(
              value: FolderViewMode.sortedAZ,
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

  Widget _buildFolderBrowserScaffold() {
    // Back navigation is handled via MainPageBridge.handleBackNavigation
    final currentMode = _getCurrentViewMode();
    final showSearch = currentMode != FolderViewMode.seriesArrange;

    return CloudScaffold(
      appBar: AppBar(
        leading: Focus(
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
            onPressed: () => _sections.backNavigation.handleBackNavigation(),
          ),
        ),
        title: Text(_getCurrentFolderTitle()),
        actions: [
          if (showSearch)
            IconButton(
              focusNode: _focus.searchButtonFocusNode,
              icon: Icon(_folderSearch.isSearchActive ? Icons.close : Icons.search),
              onPressed: _toggleSearch,
              tooltip: _folderSearch.isSearchActive ? 'Close search' : 'Search files',
            ),
          IconButton(
            focusNode: _focus.refreshButtonFocusNode,
            icon: const Icon(Icons.refresh),
            onPressed: _nav.currentTorrent != null
                ? () => _navigateIntoTorrent(_nav.currentTorrent!)
                : null,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildViewModeDropdown(),
          if (_folderSearch.isSearchActive && showSearch) _buildSearchBar(),
          Expanded(
            child: FocusTraversalGroup(
              policy: OrderedTraversalPolicy(),
              child: _folderSearch.isSearchActive
                  ? _buildSearchResults()
                  : _buildFolderContentsView(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFolderLoadingView() {
    return const CloudRowSkeletonList();
  }

  Widget _buildFolderContentsView() {
    if (_nav.isLoadingFolder) {
      return _buildFolderLoadingView();
    }

    if (_nav.currentViewNodes == null || _nav.currentViewNodes!.isEmpty) {
      return const Center(child: Text('Empty folder'));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _nav.currentViewNodes!.length,
      cacheExtent: 200.0, // Pre-cache items for smoother scrolling
      addRepaintBoundaries: true, // Optimize repainting
      itemBuilder: (context, index) {
        final node = _nav.currentViewNodes![index];
        return RepaintBoundary(child: _buildNodeCard(node, index));
      },
    );
  }

  Widget _buildNodeCard(RDFileNode node, int index) {
    final isFolder = node.isFolder;
    final isVideo = !isFolder && FileUtils.isVideoFile(node.name);

    // Same action set (labels, conditions) the old pills + ⋮ menu offered —
    // no delete at node granularity, exactly as before.
    final actions = <CloudRowAction>[
      if (isFolder || isVideo)
        CloudRowAction(
          icon: Icons.play_arrow_rounded,
          label: 'Play',
          showInStrip: true,
          onSelected: () {
            if (isFolder) {
              _playFolder(node);
            } else {
              _playFile(node);
            }
          },
        ),
      CloudRowAction(
        icon: Icons.download_rounded,
        label: 'Download',
        showInStrip: true,
        onSelected: () {
          if (isFolder) {
            _downloadFolder(node);
          } else {
            _downloadFile(node);
          }
        },
      ),
      if (isFolder || isVideo)
        CloudRowAction(
          icon: Icons.playlist_add,
          label: 'Add to Playlist',
          onSelected: () {
            if (isFolder) {
              _addFolderToPlaylist(node);
            } else {
              _addNodeFileToPlaylist(node);
            }
          },
        ),
      if (!isFolder)
        CloudRowAction(
          icon: Icons.link,
          label: 'Copy Download Link',
          onSelected: () => _copyNodeDownloadLink(node),
        ),
    ];

    return CloudFileRow(
      kind: isFolder
          ? CloudRowKind.folder
          : isVideo
          ? CloudRowKind.video
          : CloudRowKind.file,
      title: node.name,
      meta: isFolder
          ? '${RDFolderTreeBuilder.countFiles(node)} files · ${Formatters.formatFileSize(node.totalBytes)}'
          : Formatters.formatFileSize(node.bytes ?? 0),
      onTap: isFolder
          ? () => _navigateIntoFolder(node)
          : isVideo
          ? () => _playFile(node)
          : null,
      actions: actions,
      focusNode: index == 0 ? _focus.firstItemFocusNode : null,
    );
  }

  /// Full-width view switcher on its own line under the toolbar (two labels
  /// don't fit the toolbar slot the old single-label dropdown used).
  Widget _buildViewSelectorBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: CloudSegmentedTabs<DebridDownloadsView>(
        segments: const [
          CloudSegment(
            DebridDownloadsView.torrents,
            'Torrent Downloads',
            Icons.folder_rounded,
          ),
          CloudSegment(
            DebridDownloadsView.ddl,
            'DDL Downloads',
            Icons.download_rounded,
          ),
        ],
        selected: _catalog.selectedView,
        onSelected: (value) {
          if (value == _catalog.selectedView) return;
          _sections.selectionActions.exitSelectionMode();
          // The two root lists swap in the same element slot, so the incoming
          // one would inherit the outgoing list's scroll offset.
          _sections.catalogLoading.resetListScroll();
          setState(() => _catalog.selectedView = value);
        },
      ),
    );
  }

  Widget _buildSelectionBar() {
    final app = AppThemeScope.of(context);
    final theme = Theme.of(context);
    final count = _sections.selectionActions.activeSelectedIds.length;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.1),
        borderRadius: app.shape.br(12),
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
            onPressed: _sections.selectionActions.toggleSelectAll,
            child: Text(_sections.selectionActions.isAllSelected ? 'Deselect All' : 'Select All'),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            focusNode: _focus.deleteButtonFocusNode,
            onPressed: count > 0 ? _sections.selectionActions.handleDeleteSelected : null,
            icon: const Icon(Icons.delete_outline, size: 18),
            label: const Text('Delete'),
            style:
                FilledButton.styleFrom(
                  backgroundColor: theme.colorScheme.error,
                  disabledBackgroundColor: theme.colorScheme.error.withValues(
                    alpha: 0.3,
                  ),
                ).copyWith(
                  side: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.focused)) {
                      return BorderSide(color: app.core.tx, width: 3);
                    }
                    return null;
                  }),
                ),
          ),
        ],
      ),
    );
  }

  /// Opened from the Cloud hub to browse (pushed, no deep-link target, not
  /// select-source) — the list root has no other Back affordance, so show one.
  bool get _isBrowsePush =>
      widget.isPushedRoute &&
      !widget.selectSourceMode &&
      widget.initialTorrentForOptions == null;

  Widget _buildTorrentToolbar() {
    final theme = Theme.of(context);
    final app = AppThemeScope.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 480;
        final double iconSize = isCompact ? 20 : 24;
        final EdgeInsets iconPadding = isCompact
            ? const EdgeInsets.all(6)
            : const EdgeInsets.all(8);
        final BoxConstraints iconConstraints = isCompact
            ? const BoxConstraints(minWidth: 36, minHeight: 36)
            : const BoxConstraints(minWidth: 44, minHeight: 44);
        return Container(
          margin: EdgeInsets.symmetric(
            horizontal: isCompact ? 8 : 16,
            vertical: 8,
          ),
          padding: EdgeInsets.symmetric(
            horizontal: isCompact ? 8 : 16,
            vertical: 8,
          ),
          decoration: BoxDecoration(
            color: app.fade(app.core.tx, 0.05),
            borderRadius: app.shape.br(12),
            border: Border.all(color: app.fade(app.core.tx, 0.08)),
          ),
          child: Row(
            children: [
              if (_isBrowsePush) ...[
                Tooltip(
                  message: 'Back',
                  child: IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    iconSize: iconSize,
                    padding: iconPadding,
                    constraints: iconConstraints,
                    icon: const Icon(Icons.arrow_back),
                    color: theme.colorScheme.onSurface,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                SizedBox(width: isCompact ? 4 : 8),
              ],
              const Spacer(),
              Tooltip(
                message: _torrentSearch.isTorrentSearchActive
                    ? 'Close search'
                    : 'Search torrents',
                child: IconButton(
                  onPressed: _toggleTorrentSearch,
                  iconSize: iconSize,
                  padding: iconPadding,
                  constraints: iconConstraints,
                  icon: Icon(
                    _torrentSearch.isTorrentSearchActive
                        ? Icons.search_off_rounded
                        : Icons.search_rounded,
                  ),
                  color: _torrentSearch.isTorrentSearchActive
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurface,
                  visualDensity: VisualDensity.compact,
                ),
              ),
              if (_catalog.torrents.isNotEmpty) ...[
                Tooltip(
                  message: _selection.isSelectionMode ? 'Exit selection' : 'Select items',
                  child: IconButton(
                    onPressed: _sections.selectionActions.toggleSelectionMode,
                    iconSize: iconSize,
                    padding: iconPadding,
                    constraints: iconConstraints,
                    icon: Icon(
                      _selection.isSelectionMode ? Icons.close : Icons.checklist_outlined,
                    ),
                    color: _selection.isSelectionMode
                        ? theme.colorScheme.error
                        : theme.colorScheme.onSurface,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                Tooltip(
                  message: 'Delete all torrents',
                  child: IconButton(
                    onPressed: _sections.deleteAllActions.handleDeleteAllTorrents,
                    iconSize: iconSize,
                    padding: iconPadding,
                    constraints: iconConstraints,
                    icon: const Icon(Icons.delete_sweep_outlined),
                    color: theme.colorScheme.error,
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
            ],
          ),
        );
      },
    );
  }

  Widget _buildDownloadToolbar() {
    final theme = Theme.of(context);
    final app = AppThemeScope.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 480;
        final double iconSize = isCompact ? 20 : 24;
        final EdgeInsets iconPadding = isCompact
            ? const EdgeInsets.all(6)
            : const EdgeInsets.all(8);
        final BoxConstraints iconConstraints = isCompact
            ? const BoxConstraints(minWidth: 36, minHeight: 36)
            : const BoxConstraints(minWidth: 44, minHeight: 44);
        return Container(
          margin: EdgeInsets.symmetric(
            horizontal: isCompact ? 8 : 16,
            vertical: 8,
          ),
          padding: EdgeInsets.symmetric(
            horizontal: isCompact ? 8 : 16,
            vertical: 8,
          ),
          decoration: BoxDecoration(
            color: app.fade(app.core.tx, 0.05),
            borderRadius: app.shape.br(12),
            border: Border.all(color: app.fade(app.core.tx, 0.08)),
          ),
          child: Row(
            children: [
              if (_isBrowsePush) ...[
                Tooltip(
                  message: 'Back',
                  child: IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    iconSize: iconSize,
                    padding: iconPadding,
                    constraints: iconConstraints,
                    icon: const Icon(Icons.arrow_back),
                    color: theme.colorScheme.onSurface,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                SizedBox(width: isCompact ? 4 : 8),
              ],
              const Spacer(),
              if (_downloadState.downloads.isNotEmpty) ...[
                Tooltip(
                  message: _selection.isSelectionMode ? 'Exit selection' : 'Select items',
                  child: IconButton(
                    onPressed: _sections.selectionActions.toggleSelectionMode,
                    iconSize: iconSize,
                    padding: iconPadding,
                    constraints: iconConstraints,
                    icon: Icon(
                      _selection.isSelectionMode ? Icons.close : Icons.checklist_outlined,
                    ),
                    color: _selection.isSelectionMode
                        ? theme.colorScheme.error
                        : theme.colorScheme.onSurface,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                Tooltip(
                  message: 'Delete all downloads',
                  child: IconButton(
                    onPressed: _sections.deleteAllActions.handleDeleteAllDownloads,
                    iconSize: iconSize,
                    padding: iconPadding,
                    constraints: iconConstraints,
                    icon: const Icon(Icons.delete_sweep_outlined),
                    color: theme.colorScheme.error,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
              Tooltip(
                message: 'Add file link',
                child: IconButton(
                  onPressed: _showAddLinkDialog,
                  iconSize: iconSize,
                  padding: iconPadding,
                  constraints: iconConstraints,
                  icon: const Icon(Icons.note_add_outlined),
                  color: theme.colorScheme.primary,
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTorrentContent() {
    Widget body;

    if (_catalog.isLoadingTorrents && _catalog.torrents.isEmpty) {
      body = const CloudRowSkeletonList();
    } else if (_catalog.torrentErrorMessage.isNotEmpty && _catalog.torrents.isEmpty) {
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
                      _catalog.torrentErrorMessage,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.red[600], fontSize: 14),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                autofocus: true,
                onPressed: () => _sections.catalogLoading.fetchTorrents(_catalog.apiKey!, reset: true),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    } else if (_catalog.torrents.isEmpty) {
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
          if (_catalog.apiKey != null) {
            await _sections.catalogLoading.fetchTorrents(_catalog.apiKey!, reset: true);
          }
        },
        color: Colors.white,
        backgroundColor: const Color(0xFF1E293B),
        strokeWidth: 3,
        child: ListView.builder(
          controller: _focus.torrentScrollController,
          padding: const EdgeInsets.all(16),
          itemCount: _catalog.torrents.length + (_catalog.hasMoreTorrents ? 1 : 0),
          cacheExtent: 200.0, // Pre-cache items for smoother scrolling
          addRepaintBoundaries: true, // Optimize repainting
          itemBuilder: (context, index) {
            if (index == _catalog.torrents.length) {
              // Loading more indicator
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              );
            }

            final torrent = _catalog.torrents[index];
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
        if (!widget.selectSourceMode) _buildTorrentToolbar(),
        _buildViewSelectorBar(),
        if (_torrentSearch.isTorrentSearchActive) _buildTorrentSearchBar(),
        if (_selection.isSelectionMode) _buildSelectionBar(),
        Expanded(
          child: _nav.isLoadingFolder
              ? _buildFolderLoadingView()
              : _torrentSearch.isTorrentSearchActive
              ? _buildTorrentSearchResults()
              : body,
        ),
      ],
    );
  }

  // Focus nodes for torrent search DPAD navigation

  Widget _buildTorrentSearchBar() {
    final app = AppThemeScope.of(context);
    final hasText = _torrentSearch.torrentSearchController.text.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        children: [
          Expanded(
            child: TvTextField(
              controller: _torrentSearch.torrentSearchController,
              focusNode: _focus.torrentSearchFocusNode,
              autofocus: true,
              onChanged: (_) => _focus.torrentSearchSubmitFocus.cancel(),
              onSubmitted: (_) => _submitTorrentSearch(),
              textInputAction: TextInputAction.search,
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Search your torrents...',
                hintStyle: TextStyle(color: app.fade(app.core.tx, 0.3)),
                prefixIcon: Icon(
                  Icons.search_rounded,
                  color: app.fade(app.core.tx, 0.4),
                  size: 20,
                ),
                filled: true,
                fillColor: app.fade(app.core.tx, 0.06),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: app.shape.br(12),
                  borderSide: BorderSide(color: app.fade(app.core.tx, 0.08)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: app.shape.br(12),
                  borderSide: BorderSide(color: app.fade(app.core.tx, 0.08)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: app.shape.br(12),
                  borderSide: BorderSide(color: app.cloud.accent),
                ),
              ),
            ),
          ),
          if (hasText)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Focus(
                focusNode: _focus.torrentSearchClearFocusNode,
                onKeyEvent: (node, event) {
                  if (event is! KeyDownEvent) return KeyEventResult.ignored;
                  final key = event.logicalKey;
                  if (isActivateKey(key) || key == LogicalKeyboardKey.space) {
                    _focus.torrentSearchSubmitFocus.cancel();
                    _torrentSearch.torrentSearchController.clear();
                    setState(() => _torrentSearch.torrentSearchQuery = '');
                    _focus.torrentSearchFocusNode.requestFocus();
                    return KeyEventResult.handled;
                  }
                  if (key == LogicalKeyboardKey.arrowLeft) {
                    _focus.torrentSearchFocusNode.requestFocus();
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: Builder(
                  builder: (context) {
                    final isFocused = Focus.of(context).hasFocus;
                    return IconButton(
                      onPressed: () {
                        _focus.torrentSearchSubmitFocus.cancel();
                        _torrentSearch.torrentSearchController.clear();
                        setState(() => _torrentSearch.torrentSearchQuery = '');
                        _focus.torrentSearchFocusNode.requestFocus();
                      },
                      icon: Icon(
                        Icons.clear_rounded,
                        color: isFocused
                            ? app.core.tx
                            : app.fade(app.core.tx, 0.4),
                        size: 18,
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

  Widget _buildTorrentSearchResults() {
    final app = AppThemeScope.of(context);
    if (_torrentSearch.isLoadingSearch) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text(
              'Loading all torrents...',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    final results = _filteredSearchTorrents;

    if (_torrentSearch.torrentSearchQuery.isEmpty) {
      return Center(
        child: Text(
          'Type a keyword and press search',
          style: TextStyle(color: app.fade(app.core.tx, 0.4)),
        ),
      );
    }

    if (results.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off_rounded,
              size: 48,
              color: app.fade(app.core.tx, 0.2),
            ),
            const SizedBox(height: 12),
            Text(
              'No results',
              style: TextStyle(color: app.fade(app.core.tx, 0.5)),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: results.length,
      itemBuilder: (context, index) {
        final torrent = results[index];
        return KeyedSubtree(
          key: ValueKey('search_${torrent.id}'),
          child: _buildTorrentCard(torrent, index),
        );
      },
    );
  }

  Widget _buildDownloadContent() {
    Widget body;

    if (_downloadState.isLoadingDownloads && _downloadState.downloads.isEmpty) {
      body = const CloudRowSkeletonList();
    } else if (_downloadState.downloadErrorMessage.isNotEmpty && _downloadState.downloads.isEmpty) {
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
                      _downloadState.downloadErrorMessage,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.red[600], fontSize: 14),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                autofocus: true,
                onPressed: () => _sections.catalogLoading.fetchDownloads(_catalog.apiKey!, reset: true),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    } else if (_downloadState.downloads.isEmpty) {
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
          if (_catalog.apiKey != null) {
            await _sections.catalogLoading.fetchDownloads(_catalog.apiKey!, reset: true);
          }
        },
        color: Colors.white,
        backgroundColor: const Color(0xFF1E293B),
        strokeWidth: 3,
        child: ListView.builder(
          controller: _focus.downloadScrollController,
          padding: const EdgeInsets.all(16),
          itemCount: _downloadState.downloads.length + (_downloadState.hasMoreDownloads ? 1 : 0),
          cacheExtent: 200.0, // Pre-cache items for smoother scrolling
          addRepaintBoundaries: true, // Optimize repainting
          itemBuilder: (context, index) {
            if (index == _downloadState.downloads.length) {
              // Loading more indicator
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              );
            }

            final download = _downloadState.downloads[index];
            return KeyedSubtree(
              key: ValueKey(download.id),
              child: _buildDownloadCard(download, index),
            );
          },
        ),
      );
    }

    return Column(
      children: [
        if (!widget.selectSourceMode) _buildDownloadToolbar(),
        _buildViewSelectorBar(),
        if (_selection.isSelectionMode) _buildSelectionBar(),
        Expanded(child: body),
      ],
    );
  }

  Widget _buildTorrentCard(RDTorrent torrent, int index) {
    final meta =
        '${Formatters.formatFileSize(torrent.bytes)} · ${torrent.links.length} ${torrent.links.length == 1 ? 'file' : 'files'} · ${_formatDate(torrent.added)}';
    final upNode = (index == 0)
        ? (_selection.isSelectionMode
              ? _focus.deleteButtonFocusNode
              : (_torrentSearch.isTorrentSearchActive ? _focus.torrentSearchFocusNode : null))
        : null;

    if (widget.selectSourceMode) {
      // Select-source flow: the row IS the Select action — no strip, no menu.
      return CloudFileRow(
        kind: CloudRowKind.folder,
        title: torrent.filename,
        meta: meta,
        onTap: () {
          final source = SeriesSource(
            torrentHash: torrent.hash,
            torrentName: torrent.filename,
            debridService: 'rd',
            debridTorrentId: torrent.id,
            boundAt: DateTime.now().millisecondsSinceEpoch,
          );
          widget.onSourceSelected?.call(source);
          Navigator.of(context).pop();
        },
        focusNode: index == 0 ? _focus.firstItemFocusNode : null,
        upFocusNode: upNode,
      );
    }

    // Same action set (labels, conditions) the old Open/Play pills + ⋮ menu
    // offered; the row's tap now carries Open.
    final actions = <CloudRowAction>[
      CloudRowAction(
        icon: Icons.play_arrow_rounded,
        label: 'Play',
        showInStrip: true,
        onSelected: () => _handlePlayMultiFileTorrent(torrent),
      ),
      CloudRowAction(
        icon: Icons.download,
        label: 'Download',
        showInStrip: true,
        onSelected: () => _handleDownloadTorrent(torrent),
      ),
      CloudRowAction(
        icon: Icons.playlist_add,
        label: 'Add to Playlist',
        onSelected: () => _handleAddTorrentToPlaylist(torrent),
      ),
      CloudRowAction(
        icon: Icons.live_tv_rounded,
        label: 'Add to Debrify TV',
        onSelected: () => _handleAddTorrentToDebrifyTv(torrent),
      ),
      CloudRowAction(
        icon: Icons.delete_outline,
        label: 'Delete',
        destructive: true,
        onSelected: () => _sections.singleDeleteActions.handleDeleteTorrent(torrent),
      ),
    ];

    return CloudFileRow(
      kind: CloudRowKind.folder,
      title: torrent.filename,
      meta: meta,
      onTap: () => _navigateIntoTorrent(torrent),
      actions: actions,
      selectionMode: _selection.isSelectionMode,
      selected: _selection.selectedTorrentIds.contains(torrent.id),
      onToggleSelected: () => _sections.selectionActions.toggleTorrentSelection(torrent.id),
      focusNode: index == 0 ? _focus.firstItemFocusNode : null,
      upFocusNode: upNode,
    );
  }

  Future<void> _handleDownloadTorrent(RDTorrent torrent) async {
    if (_catalog.apiKey == null) return;

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
      final torrentInfo = await DebridService.getTorrentInfo(
        _catalog.apiKey!,
        torrent.id,
      );
      final allFiles =
          (torrentInfo['files'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      final links = (torrentInfo['links'] as List).cast<String>();

      // Filter to only selected files (files that were selected when adding to RD)
      // Only selected files have corresponding links and can be downloaded
      final files = allFiles.where((file) => file['selected'] == 1).toList();

      if (mounted) Navigator.of(context).pop();

      if (files.isEmpty || links.isEmpty) {
        _sections.feedback.showError('No files available for download');
        return;
      }

      // Format files for FileSelectionDialog
      final formattedFiles = <Map<String, dynamic>>[];
      for (int i = 0; i < files.length; i++) {
        final file = files[i];
        final path = (file['path'] as String?) ?? '';
        final bytes = file['bytes'] as int? ?? 0;

        formattedFiles.add({
          '_fullPath': path, // Use path field for full path
          'name': path,
          'size': bytes.toString(),
          '_linkIndex': i, // Store the link index for later use
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
      _sections.feedback.showError('Failed to load torrent: $e');
    }
  }

  Future<void> _handleAddTorrentToPlaylist(RDTorrent torrent) async {
    if (_catalog.apiKey == null) return;

    if (torrent.links.length == 1) {
      try {
        final unrestrictResult = await DebridService.unrestrictLink(
          _catalog.apiKey!,
          torrent.links[0],
        );
        final mimeType = unrestrictResult['mimeType']?.toString() ?? '';

        if (FileUtils.isVideoMimeType(mimeType)) {
          final ok = await PlaylistStorage.addPlaylistItemRaw({
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
            _sections.feedback.showError('This file is not a video (MIME type: $mimeType)');
          }
        }
      } catch (e) {
        if (mounted) {
          _sections.feedback.showError('Failed to validate file: ${e.toString()}');
        }
      }
    } else {
      final ok = await PlaylistStorage.addPlaylistItemRaw({
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

  Future<void> _handleAddTorrentToDebrifyTv(RDTorrent torrent) async {
    try {
      final result = await DebrifyTvChannelAddBridge.addTorrentsToChannel(
        context,
        torrents: [DebrifyTvChannelAddBridge.fromRealDebridTorrent(torrent)],
        searchKeyword: _torrentSearch.torrentSearchQuery,
      );

      if (result == null || !mounted) return;
      _sections.feedback.showSuccess(result.successMessage);
    } on DebrifyTvChannelAddException catch (e) {
      if (!mounted) return;
      _sections.feedback.showError(e.message);
    } catch (e) {
      if (!mounted) return;
      _sections.feedback.showError('Failed to add torrent to Debrify TV: $e');
    }
  }

  Widget _buildDownloadCard(DebridDownload download, int index) {
    final canStream = download.streamable == 1;
    final isVideo = FileUtils.isVideoFile(download.filename);

    if (widget.selectSourceMode) {
      final selectable = canStream || isVideo;
      return CloudFileRow(
        kind: selectable ? CloudRowKind.video : CloudRowKind.file,
        title: download.filename,
        meta:
            '${Formatters.formatFileSize(download.filesize)} · ${download.host}',
        onTap: selectable
            ? () {
                widget.onSourceSelected?.call(
                  SeriesSource(
                    torrentHash: '',
                    torrentName: download.filename,
                    debridService: 'rd',
                    debridTorrentId: download.id,
                    cloudSourceKind: SeriesSource.cloudKindWebDownload,
                    boundAt: DateTime.now().millisecondsSinceEpoch,
                  ),
                );
                Navigator.of(context).pop();
              }
            : null,
        focusNode: index == 0 ? _focus.firstItemFocusNode : null,
      );
    }

    // Same action set the old Play/Download buttons + ⋮ menu offered; the
    // row's tap now carries Play for streamable downloads.
    // Play is offered for anything WE can stream, not only what the provider
    // flags. `streamable` describes the provider's own transcoding service;
    // we hand the direct link to our player instead, which reads plenty the
    // provider won't transcode (MPEG program streams, for one). Non-video
    // files are unaffected — they still offer download only.
    final actions = <CloudRowAction>[
      if (canStream || isVideo)
        CloudRowAction(
          icon: Icons.play_arrow_rounded,
          label: 'Play',
          showInStrip: true,
          onSelected: () => _sections.downloadRowActions.handlePlayDownload(download),
        ),
      CloudRowAction(
        icon: Icons.download,
        label: 'Download',
        showInStrip: true,
        onSelected: () => _sections.downloadRowActions.handleQueueDownload(download),
      ),
      CloudRowAction(
        icon: Icons.link,
        label: 'Copy Link',
        onSelected: () => _sections.downloadRowActions.handleDownloadAction(download),
      ),
      CloudRowAction(
        icon: Icons.delete_outline,
        label: 'Delete',
        destructive: true,
        onSelected: () => _sections.singleDeleteActions.handleDeleteDownload(download),
      ),
    ];

    return CloudFileRow(
      kind: (canStream || isVideo) ? CloudRowKind.video : CloudRowKind.file,
      title: download.filename,
      meta:
          '${Formatters.formatFileSize(download.filesize)} · ${download.host}',
      onTap: (canStream || isVideo)
          ? () => _sections.downloadRowActions.handlePlayDownload(download)
          : null,
      actions: actions,
      selectionMode: _selection.isSelectionMode,
      selected: _selection.selectedDownloadIds.contains(download.id),
      onToggleSelected: () => _sections.selectionActions.toggleDownloadSelection(download.id),
      focusNode: index == 0 ? _focus.firstItemFocusNode : null,
      upFocusNode: (_selection.isSelectionMode && index == 0)
          ? _focus.deleteButtonFocusNode
          : null,
    );
  }

  Future<void> _handlePlayMultiFileTorrent(RDTorrent torrent) async {
    if (_catalog.apiKey == null) return;
    try {
      // Show loading dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          backgroundColor: AppThemeScope.of(context).cloud.dialogSurface,
          content: const Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Text('Preparing playlist…'),
            ],
          ),
        ),
      );

      // Get torrent info to access file names and links
      final torrentInfo = await DebridService.getTorrentInfo(
        _catalog.apiKey!,
        torrent.id,
      );
      final files = torrentInfo['files'] as List<dynamic>?;
      final infoLinks = (torrentInfo['links'] as List<dynamic>? ?? [])
          .map((l) => l?.toString() ?? '')
          .toList();

      if (files == null || files.isEmpty) {
        if (mounted) Navigator.of(context).pop(); // close loading
        if (mounted) {
          _sections.feedback.showError('Failed to get file information from torrent.');
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
      if (filesToUse.length > 1 && infoLinks.length == 1) {
        isArchive = true;
      }

      if (isArchive) {
        if (mounted) Navigator.of(context).pop(); // close loading
        if (mounted) {
          _sections.feedback.showError('This is an archived torrent. Please extract it first.');
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

          // Save full path for relativePath before stripping to filename
          String? relativePath = filename;
          if (relativePath != null && relativePath.startsWith('/')) {
            relativePath = relativePath.substring(1); // Remove leading slash
          }

          // If we got a path, extract just the filename
          if (filename != null && filename.startsWith('/')) {
            filename = filename.split('/').last;
          }

          final finalFilename = filename ?? 'Unknown File';
          final int? sizeBytes = (file is Map) ? (file['bytes'] as int?) : null;

          // Check if we have a corresponding link
          if (i >= infoLinks.length) {
            continue;
          }

          if (i == firstEpisodeIndex) {
            try {
              final unrestrictResult = await DebridService.unrestrictLink(
                _catalog.apiKey!,
                infoLinks[i],
              );
              final url = unrestrictResult['download']?.toString() ?? '';
              if (url.isNotEmpty) {
                entries.add(
                  PlaylistEntry(
                    url: url,
                    title: finalFilename,
                    relativePath: relativePath,
                    sizeBytes: sizeBytes,
                  ),
                );
              } else {
                entries.add(
                  PlaylistEntry(
                    url: '',
                    title: finalFilename,
                    relativePath: relativePath,
                    restrictedLink: infoLinks[i],
                    sizeBytes: sizeBytes,
                  ),
                );
              }
            } catch (e) {
              entries.add(
                PlaylistEntry(
                  url: '',
                  title: finalFilename,
                  relativePath: relativePath,
                  restrictedLink: infoLinks[i],
                  sizeBytes: sizeBytes,
                ),
              );
            }
          } else {
            entries.add(
              PlaylistEntry(
                url: '',
                title: finalFilename,
                relativePath: relativePath,
                restrictedLink: infoLinks[i],
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

          String? relativePath = filename;
          if (relativePath != null && relativePath.startsWith('/')) {
            relativePath = relativePath.substring(1);
          }

          if (filename != null && filename.startsWith('/')) {
            filename = filename.split('/').last;
          }

          final finalFilename = filename ?? 'Unknown File';
          final int? sizeBytes = (file is Map) ? (file['bytes'] as int?) : null;

          if (i >= infoLinks.length) {
            continue;
          }

          if (i == 0) {
            try {
              final unrestrictResult = await DebridService.unrestrictLink(
                _catalog.apiKey!,
                infoLinks[i],
              );
              final url = unrestrictResult['download']?.toString() ?? '';
              if (url.isNotEmpty) {
                entries.add(
                  PlaylistEntry(
                    url: url,
                    title: finalFilename,
                    relativePath: relativePath,
                    sizeBytes: sizeBytes,
                  ),
                );
              } else {
                entries.add(
                  PlaylistEntry(
                    url: '',
                    title: finalFilename,
                    relativePath: relativePath,
                    restrictedLink: infoLinks[i],
                    sizeBytes: sizeBytes,
                  ),
                );
              }
            } catch (e) {
              entries.add(
                PlaylistEntry(
                  url: '',
                  title: finalFilename,
                  relativePath: relativePath,
                  restrictedLink: infoLinks[i],
                  sizeBytes: sizeBytes,
                ),
              );
            }
          } else {
            entries.add(
              PlaylistEntry(
                url: '',
                title: finalFilename,
                relativePath: relativePath,
                restrictedLink: infoLinks[i],
                sizeBytes: sizeBytes,
              ),
            );
          }
        }
      }

      if (mounted) Navigator.of(context).pop(); // close loading

      if (entries.isEmpty) {
        if (mounted) {
          _sections.feedback.showError('No playable video files found in this torrent.');
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
          viewMode: isSeries
              ? PlaylistViewMode.series
              : PlaylistViewMode.sorted,
        ),
      );
    } catch (e) {
      if (mounted) {
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
        _sections.feedback.showError('Failed to prepare playlist: $e');
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
                controller: _addInput.magnetController,
                decoration: const InputDecoration(
                  hintText: 'Paste magnet link here...',
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.all(16),
                ),
                maxLines: 3,
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
                    onPressed: _addInput.isAddingMagnet
                        ? null
                        : _addMagnetWithDefaultSelection,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      backgroundColor: const Color(0xFF6366F1),
                    ),
                    child: _addInput.isAddingMagnet
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
        _addInput.magnetController.text = text;
      }
    }
  }

  Future<void> _addMagnetWithDefaultSelection() async {
    final magnetLink = _addInput.magnetController.text.trim();
    if (magnetLink.isEmpty) {
      _sections.feedback.showError('Please enter a magnet link');
      return;
    }

    if (!isValidMagnetLink(magnetLink)) {
      _sections.feedback.showError('Please enter a valid magnet link');
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
        _addInput.isAddingMagnet = true;
      });
    }

    try {
      // Get the default file selection preference
      final fileSelection = await RealDebridStorage.getFileSelection();

      // Add the magnet using the same logic as the torrent search screen
      await DebridService.addTorrentToDebrid(
        _catalog.apiKey!,
        magnetLink,
        tempFileSelection: fileSelection,
      );

      // Close loading dialog
      if (mounted) {
        Navigator.of(context).pop();
      }

      // Clear the input
      _addInput.magnetController.clear();

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
      await _sections.catalogLoading.fetchTorrents(_catalog.apiKey!, reset: true);
    } on TorrentNotCachedException catch (e) {
      await DebridService.deleteTorrent(e.apiKey, e.torrentId);
      if (mounted) Navigator.of(context).pop();
      if (mounted) _sections.feedback.showError('File is not readily available in Real Debrid');
    } catch (e) {
      // Close loading dialog
      if (mounted) {
        Navigator.of(context).pop();
      }

      if (mounted) {
        _sections.feedback.showError(getUserFriendlyErrorMessage(e.toString()));
      }
    } finally {
      if (mounted) {
        setState(() {
          _addInput.isAddingMagnet = false;
        });
      }
    }
  }

  Future<void> _showAdvancedMagnetDialog() async {
    final magnetLink = _addInput.magnetController.text.trim();
    if (magnetLink.isEmpty) {
      _sections.feedback.showError('Please enter a magnet link first');
      return;
    }

    if (!isValidMagnetLink(magnetLink)) {
      _sections.feedback.showError('Please enter a valid magnet link');
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
            onPressed: _addInput.isAddingMagnet
                ? null
                : () => _addMagnetWithSelection(magnetLink, 'smart'),
            child: _addInput.isAddingMagnet
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Smart (recommended)'),
          ),
          TextButton(
            onPressed: _addInput.isAddingMagnet
                ? null
                : () => _addMagnetWithSelection(magnetLink, 'largest'),
            child: _addInput.isAddingMagnet
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Largest File'),
          ),
          TextButton(
            onPressed: _addInput.isAddingMagnet
                ? null
                : () => _addMagnetWithSelection(magnetLink, 'video'),
            child: _addInput.isAddingMagnet
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Video Files'),
          ),
          TextButton(
            onPressed: _addInput.isAddingMagnet
                ? null
                : () => _addMagnetWithSelection(magnetLink, 'all'),
            child: _addInput.isAddingMagnet
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
      _addInput.isAddingMagnet = true;
    });

    try {
      // Add the magnet with the selected file preference
      await DebridService.addTorrentToDebrid(
        _catalog.apiKey!,
        magnetLink,
        tempFileSelection: fileSelection,
      );

      // Close loading dialog
      if (mounted) {
        Navigator.of(context).pop();
      }

      // Clear the input
      _addInput.magnetController.clear();

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
      await _sections.catalogLoading.fetchTorrents(_catalog.apiKey!, reset: true);
    } on TorrentNotCachedException catch (e) {
      await DebridService.deleteTorrent(e.apiKey, e.torrentId);
      if (mounted) Navigator.of(context).pop();
      if (mounted) _sections.feedback.showError('File is not readily available in Real Debrid');
    } catch (e) {
      // Close loading dialog
      if (mounted) {
        Navigator.of(context).pop();
      }

      if (mounted) {
        _sections.feedback.showError(getUserFriendlyErrorMessage(e.toString()));
      }
    } finally {
      if (mounted) {
        setState(() {
          _addInput.isAddingMagnet = false;
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
      builder: (context) {
        final app = AppThemeScope.of(context);
        return AlertDialog(
          backgroundColor: app.cloud.dialogSurface,
          shape: RoundedRectangleBorder(borderRadius: app.shape.br(16)),
          title: const Text(
            'Add Link',
            style: TextStyle(fontWeight: FontWeight.bold),
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
                  controller: _addInput.linkController,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: 'https://example.com/file.zip',
                    hintStyle: TextStyle(color: Colors.grey[600]),
                    border: OutlineInputBorder(
                      borderRadius: app.shape.br(8),
                      borderSide: const BorderSide(color: Color(0xFF475569)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: app.shape.br(8),
                      borderSide: const BorderSide(color: Color(0xFF475569)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: app.shape.br(8),
                      borderSide: BorderSide(color: app.cloud.accent),
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
                    onPressed: _addInput.isAddingLink ? null : _addLink,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      backgroundColor: const Color(0xFF6366F1),
                    ),
                    child: _addInput.isAddingLink
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
        );
      },
    );
  }

  Future<void> _autoPasteLink() async {
    final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
    if (clipboardData?.text != null) {
      final text = clipboardData!.text!.trim();
      // Check if it looks like a URL
      if (text.startsWith('http://') || text.startsWith('https://')) {
        _addInput.linkController.text = text;
      }
    }
  }

  Future<void> _addLink() async {
    final link = _addInput.linkController.text.trim();
    if (link.isEmpty) {
      _sections.feedback.showError('Please enter a link');
      return;
    }

    if (!isValidLink(link)) {
      _sections.feedback.showError(
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
        backgroundColor: AppThemeScope.of(context).cloud.dialogSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Unrestricting Link',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            const Text('Processing link...'),
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
        _addInput.isAddingLink = true;
      });
    }

    try {
      // Unrestrict the link
      await DebridService.unrestrictLink(_catalog.apiKey!, link);

      // Close loading dialog
      if (mounted) {
        Navigator.of(context).pop();
      }

      // Clear the input
      _addInput.linkController.clear();

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
      await _sections.catalogLoading.fetchDownloads(_catalog.apiKey!, reset: true);
    } catch (e) {
      // Close loading dialog
      if (mounted) {
        Navigator.of(context).pop();
      }

      if (mounted) {
        // Show the actual Real Debrid error message with user-friendly formatting
        final errorMessage = e.toString().replaceFirst('Exception: ', '');
        final friendlyMessage = getLinkUnrestrictErrorMessage(errorMessage);
        _sections.feedback.showError(friendlyMessage);
      }
    } finally {
      if (mounted) {
        setState(() {
          _addInput.isAddingLink = false;
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
    if (_catalog.apiKey == null) return;

    try {
      setLocal(() {
        unrestrictingFiles[index] = true;
      });

      final unrestrictResult = await DebridService.unrestrictLink(
        _catalog.apiKey!,
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
            _sections.feedback.showError('This file is not a video (MIME type: $mimeType)');
          }
        }
      } else {
        if (mounted) {
          _sections.feedback.showError('Failed to get download link');
        }
      }
    } catch (e) {
      if (mounted) {
        _sections.feedback.showError('Failed to load video: ${e.toString()}');
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
    if (_catalog.apiKey == null) return;

    try {
      // Check if it's a video file before adding to playlist
      final unrestrictResult = await DebridService.unrestrictLink(
        _catalog.apiKey!,
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
        final ok = await PlaylistStorage.addPlaylistItemRaw(item);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ok ? 'Added to playlist' : 'Already in playlist'),
          ),
        );
      } else {
        if (mounted) {
          _sections.feedback.showError('This file is not a video (MIME type: $mimeType)');
        }
      }
    } catch (e) {
      if (mounted) {
        _sections.feedback.showError('Failed to validate file: ${e.toString()}');
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
    if (_catalog.apiKey == null) return;

    try {
      setLocal(() {
        unrestrictingFiles[index] = true;
      });

      final unrestrictResult = await DebridService.unrestrictLink(
        _catalog.apiKey!,
        torrent.links[index],
      );
      final downloadLink = unrestrictResult['download']?.toString() ?? '';

      if (downloadLink.isNotEmpty) {
        await DownloadService.instance.enqueueDownload(
          credentialKey: 'real_debrid_api_key',
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
          _sections.feedback.showError('Failed to get download link');
        }
      }
    } catch (e) {
      if (mounted) {
        _sections.feedback.showError('Failed to get download link: ${e.toString()}');
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
    if (_catalog.apiKey == null) return;

    try {
      setLocal(() {
        unrestrictingFiles[index] = true;
      });

      final unrestrictResult = await DebridService.unrestrictLink(
        _catalog.apiKey!,
        torrent.links[index],
      );
      final downloadLink = unrestrictResult['download']?.toString() ?? '';

      if (downloadLink.isNotEmpty) {
        if (mounted) {
          _sections.feedback.copyToClipboard(downloadLink);
        }
      } else {
        if (mounted) {
          _sections.feedback.showError('Failed to get download link');
        }
      }
    } catch (e) {
      if (mounted) {
        _sections.feedback.showError('Failed to get download link: ${e.toString()}');
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
    // Hoisted by the caller: this builds once per list item and again on every
    // animation tick, so the theme lookup must not happen in here.
    required Color surface,
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
                    surface.withValues(alpha: 0.8),
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
                                  ? Icon(
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
                                      : Icon(
                                          Icons.play_arrow_rounded,
                                          color: Colors.white,
                                          size: 18,
                                        ),
                                  label: Text(
                                    isUnrestricting ? 'Loading...' : 'Play',
                                    style: TextStyle(
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
                                  : Icon(
                                      Icons.copy_rounded,
                                      size: 16,
                                      color: Colors.white,
                                    ),
                              label: Text(
                                isUnrestricting ? 'Working…' : 'Copy',
                                style: TextStyle(
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
    final app = AppThemeScope.of(context);
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
              color: app.cloud.dialogSurface.withValues(alpha: 0.5),
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
                      borderRadius: app.shape.br(8),
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
                      borderRadius: app.shape.br(12),
                    ),
                    child: Text(
                      // Ink pinned with the green fill above: the surface does
                      // not follow the palette, so its ink must not either.
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
    // Hoisted out of the itemBuilders below: one theme lookup per list build.
    final app = AppThemeScope.of(context);
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
            color: app.cloud.dialogSurface.withValues(alpha: 0.3),
            borderRadius: app.shape.br(12),
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
                        borderRadius: app.shape.br(6),
                      ),
                      // Both glyphs pinned with the green fill/border above.
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
    // Hoisted out of itemBuilder: one theme lookup per list build, not per row.
    final app = AppThemeScope.of(context);
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
            surface: app.cloud.dialogSurface,
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
    if (_catalog.apiKey == null || _nav.currentTorrentId == null) return;

    try {
      // Show loading dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );

      // Get download URL for the file
      final downloadUrl = await DebridService.getFileDownloadUrl(
        _catalog.apiKey!,
        _nav.currentTorrentId!,
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
        _sections.feedback.showError('Failed to play file: ${e.toString()}');
      }
    }
  }

  /// Play all videos in a folder with a playlist
  Future<void> _playFolder(RDFileNode folder) async {
    if (_catalog.apiKey == null ||
        _nav.currentTorrentId == null ||
        _nav.currentTorrent == null) {
      return;
    }

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
          _sections.feedback.showError('No video files found in this folder');
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
        _catalog.apiKey!,
        _nav.currentTorrentId!,
        sortedVideoFiles[0].linkIndex,
      );

      // Close loading dialog
      if (mounted) Navigator.of(context).pop();

      // Create playlist entries using restrictedLink (like _handlePlayMultiFileTorrent)
      final playlist = sortedVideoFiles.map((file) {
        return PlaylistEntry(
          title: file.name,
          url: '', // Will be loaded on demand
          restrictedLink: _nav.currentTorrent!.links[file.linkIndex],
          sizeBytes: file.bytes ?? 0,
        );
      }).toList();

      // Detect if it's a series collection
      final filenames = playlist.map((e) => e.title).toList();
      final isSeries =
          playlist.length > 1 && SeriesParser.isSeriesPlaylist(filenames);

      // Launch video player with playlist
      await VideoPlayerLauncher.push(
        context,
        VideoPlayerLaunchArgs(
          videoUrl: firstVideoUrl,
          title: folder.name,
          subtitle: '${videoFiles.length} videos',
          playlist: playlist,
          startIndex: 0,
          viewMode: isSeries
              ? PlaylistViewMode.series
              : PlaylistViewMode.sorted,
        ),
      );
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop();
        _sections.feedback.showError('Failed to play folder: ${e.toString()}');
      }
    }
  }

  /// Download a single file
  Future<void> _downloadFile(RDFileNode file) async {
    if (_catalog.apiKey == null || _nav.currentTorrentId == null) {
      _sections.feedback.showError('No API key or torrent ID available');
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
        _catalog.apiKey!,
        _nav.currentTorrentId!,
      );
      final links = (torrentInfo['links'] as List).cast<String>();

      // Validate linkIndex
      if (file.linkIndex >= links.length) {
        if (mounted) Navigator.of(context).pop();
        _sections.feedback.showError('Invalid file link index');
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
        'torrentHash': _nav.currentTorrent?.hash,
        'fileIndex': file.linkIndex,
      });

      // Pass restricted link as URL (download service will replace it)
      await DownloadService.instance.enqueueDownload(
        credentialKey: 'real_debrid_api_key',
        url: restrictedLink,
        fileName: fileName,
        meta: meta,
        torrentName: _nav.currentTorrent?.filename,
        context: mounted ? context : null,
      );

      _sections.feedback.showSuccess('Download queued: $fileName');
    } catch (e) {
      // Close loading dialog if still open
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      _sections.feedback.showError('Failed to download: $e');
    }
  }

  /// Download files from a folder with file selection dialog
  Future<void> _downloadFolder(RDFileNode folder) async {
    if (_catalog.apiKey == null || _nav.currentTorrentId == null) {
      _sections.feedback.showError('No API key or torrent ID available');
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
        _catalog.apiKey!,
        _nav.currentTorrentId!,
      );
      final links = (torrentInfo['links'] as List).cast<String>();

      if (mounted) Navigator.of(context).pop();

      if (allFiles.isEmpty) {
        _sections.feedback.showError('No files found in folder');
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
      _sections.feedback.showError('Failed to load folder: $e');
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
          final fileName =
              (fileData['_fullPath'] as String?) ??
              (fileData['name'] as String? ?? 'download');

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
            'torrentHash': _nav.currentTorrent?.hash,
            'fileIndex': linkIndex,
          });

          // Queue download instantly (download service will unrestrict when ready)
          await DownloadService.instance.enqueueDownload(
            credentialKey: 'real_debrid_api_key',
            url:
                restrictedLink, // Pass restricted link (will be replaced by download service)
            fileName: fileName,
            meta: meta,
            torrentName: _nav.currentTorrent?.filename ?? folderName,
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
        _sections.feedback.showSuccess(
          'Queued $successCount file${successCount == 1 ? '' : 's'} for download',
        );
      } else if (successCount > 0 && failCount > 0) {
        _sections.feedback.showError(
          'Queued $successCount file${successCount == 1 ? '' : 's'}, $failCount failed',
        );
      } else {
        _sections.feedback.showError('Failed to queue any files for download');
      }
    } catch (e) {
      // Close any open dialogs
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      _sections.feedback.showError('Failed to queue downloads: $e');
    }
  }

  /// Add a single file to playlist
  Future<void> _addNodeFileToPlaylist(RDFileNode file) async {
    if (_nav.currentTorrentId == null) return;

    try {
      final added = await PlaylistStorage.addPlaylistItemRaw({
        'provider': 'rd',
        'title': FileUtils.cleanPlaylistTitle(file.name),
        'kind': 'single',
        'rdTorrentId': _nav.currentTorrentId,
        'rdLinkIndex': file.linkIndex,
        'sizeBytes': file.bytes,
      });

      if (mounted) {
        _sections.feedback.showSuccess(added ? 'Added to playlist' : 'Already in playlist');
      }
    } catch (e) {
      if (mounted) {
        _sections.feedback.showError('Failed to add to playlist: ${e.toString()}');
      }
    }
  }

  /// Add all videos in a folder to playlist
  Future<void> _addFolderToPlaylist(RDFileNode folder) async {
    if (_nav.currentTorrentId == null) return;

    try {
      // Collect video files
      final videoFiles = RDFolderTreeBuilder.collectVideoFiles(folder);
      if (videoFiles.isEmpty) {
        _sections.feedback.showError('No video files to add');
        return;
      }

      // Add as a collection to playlist
      final added = await PlaylistStorage.addPlaylistItemRaw({
        'provider': 'rd',
        'title': FileUtils.cleanPlaylistTitle(folder.name),
        'kind': 'collection',
        'rdTorrentId': _nav.currentTorrentId,
        'rdFileNodes': videoFiles.map((f) => f.toJson()).toList(),
        'fileCount': videoFiles.length,
        'totalBytes': folder.totalBytes,
      });

      if (mounted) {
        _sections.feedback.showSuccess(
          added
              ? 'Added ${videoFiles.length} videos to playlist'
              : 'Already in playlist',
        );
      }
    } catch (e) {
      if (mounted) {
        _sections.feedback.showError('Failed to add to playlist: ${e.toString()}');
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
    if (_catalog.apiKey == null) return;

    try {
      // Get torrent info
      final info = await DebridService.getTorrentInfo(_catalog.apiKey!, torrent.id);
      final links = (info['links'] as List).cast<String>();

      if (links.isEmpty) {
        _sections.feedback.showError('No links available');
        return;
      }

      // Unrestrict the first link
      final unrestrictedData = await DebridService.unrestrictLink(
        _catalog.apiKey!,
        links[0],
      );
      final downloadUrl = unrestrictedData['download'] as String;

      // Copy to clipboard
      await Clipboard.setData(ClipboardData(text: downloadUrl));
      _sections.feedback.showSuccess('Download link copied to clipboard');
    } catch (e) {
      _sections.feedback.showError('Failed to get download link: $e');
    }
  }

  /// Copy download link for file node to clipboard
  Future<void> _copyNodeDownloadLink(RDFileNode node) async {
    if (_catalog.apiKey == null || _nav.currentTorrentId == null) return;

    try {
      // Unrestrict the file's link
      final downloadUrl = await DebridService.getFileDownloadUrl(
        _catalog.apiKey!,
        _nav.currentTorrentId!,
        node.linkIndex,
      );

      // Copy to clipboard
      await Clipboard.setData(ClipboardData(text: downloadUrl));
      _sections.feedback.showSuccess('Download link copied to clipboard');
    } catch (e) {
      _sections.feedback.showError('Failed to get download link: $e');
    }
  }
}

/// Frozen original-code characterization accessor; production does not call it.
@visibleForTesting
Map<String, Object?> debridDownloadsTestAccess(State<DebridDownloadsScreen> state) {
  final s = state as _DebridDownloadsScreenState;
  return {
    'selectedView': s._catalog.selectedView,
    'tvContentFocusHandler': s._focus.tvContentFocusHandler,
    'torrents': s._catalog.torrents,
    'torrentScrollController': s._focus.torrentScrollController,
    'isLoadingTorrents': s._catalog.isLoadingTorrents,
    'isLoadingMoreTorrents': s._catalog.isLoadingMoreTorrents,
    'torrentErrorMessage': s._catalog.torrentErrorMessage,
    'torrentPage': s._catalog.torrentPage,
    'hasMoreTorrents': s._catalog.hasMoreTorrents,
    'downloads': s._downloadState.downloads,
    'downloadScrollController': s._focus.downloadScrollController,
    'isLoadingDownloads': s._downloadState.isLoadingDownloads,
    'isLoadingMoreDownloads': s._downloadState.isLoadingMoreDownloads,
    'downloadErrorMessage': s._downloadState.downloadErrorMessage,
    'downloadPage': s._downloadState.downloadPage,
    'hasMoreDownloads': s._downloadState.hasMoreDownloads,
    'apiKey': s._catalog.apiKey,
    'currentTorrentId': s._nav.currentTorrentId,
    'currentTorrent': s._nav.currentTorrent,
    'folderPath': s._nav.folderPath,
    'currentFolderTree': s._nav.currentFolderTree,
    'currentViewNodes': s._nav.currentViewNodes,
    'isLoadingFolder': s._nav.isLoadingFolder,
    'torrentViewModes': s._view.torrentViewModes,
    'magnetController': s._addInput.magnetController,
    'isAddingMagnet': s._addInput.isAddingMagnet,
    'linkController': s._addInput.linkController,
    'isAddingLink': s._addInput.isAddingLink,
    'isSelectionMode': s._selection.isSelectionMode,
    'selectedTorrentIds': s._selection.selectedTorrentIds,
    'selectedDownloadIds': s._selection.selectedDownloadIds,
    'backButtonFocusNode': s._focus.backButtonFocusNode,
    'refreshButtonFocusNode': s._focus.refreshButtonFocusNode,
    'viewModeDropdownFocusNode': s._focus.viewModeDropdownFocusNode,
    'firstItemFocusNode': s._focus.firstItemFocusNode,
    'deleteButtonFocusNode': s._focus.deleteButtonFocusNode,
    'torrentSearchSubmitFocus': s._focus.torrentSearchSubmitFocus,
    'shouldFocusOnLoad': s._focus.shouldFocusOnLoad,
    'isTorrentSearchActive': s._torrentSearch.isTorrentSearchActive,
    'torrentSearchController': s._torrentSearch.torrentSearchController,
    'allTorrentsForSearch': s._torrentSearch.allTorrentsForSearch,
    'isLoadingSearch': s._torrentSearch.isLoadingSearch,
    'torrentSearchQuery': s._torrentSearch.torrentSearchQuery,
    'hiddenFromNav': s._torrentSearch.hiddenFromNav,
    'isSearchActive': s._folderSearch.isSearchActive,
    'searchController': s._folderSearch.searchController,
    'searchFocusNode': s._focus.searchFocusNode,
    'searchButtonFocusNode': s._focus.searchButtonFocusNode,
    'searchClearFocusNode': s._focus.searchClearFocusNode,
    'searchResults': s._folderSearch.searchResults,
    'torrentSearchFocusNode': s._focus.torrentSearchFocusNode,
    'torrentSearchClearFocusNode': s._focus.torrentSearchClearFocusNode,
    'activeSelectedIds': s._sections.selectionActions.activeSelectedIds,
    'activeItemCount': s._sections.selectionActions.activeItemCount,
    'isAllSelected': s._sections.selectionActions.isAllSelected,
    'focusFirstItemOrFallback': s._sections.focusActions.focusFirstItemOrFallback,
    'handleBackNavigation': s._sections.backNavigation.handleBackNavigation,
    'onTorrentScroll': s._sections.catalogLoading.onTorrentScroll,
    'onDownloadScroll': s._sections.catalogLoading.onDownloadScroll,
    'loadApiKeyAndData': s._sections.catalogLoading.loadApiKeyAndData,
    'fetchTorrents': s._sections.catalogLoading.fetchTorrents,
    'loadMoreTorrents': s._sections.catalogLoading.loadMoreTorrents,
    'toggleTorrentSearch': s._toggleTorrentSearch,
    'queryMatchesInitialTitle': s._queryMatchesInitialTitle,
    'submitTorrentSearch': s._submitTorrentSearch,
    'completeTorrentSearchSubmitFocus': s._completeTorrentSearchSubmitFocus,
    'fetchAllTorrentsForSearch': s._fetchAllTorrentsForSearch,
    'filteredSearchTorrents': s._filteredSearchTorrents,
    'fetchDownloads': s._sections.catalogLoading.fetchDownloads,
    'loadMoreDownloads': s._sections.catalogLoading.loadMoreDownloads,
    'handleDownloadAction': s._sections.downloadRowActions.handleDownloadAction,
    'handlePlayDownload': s._sections.downloadRowActions.handlePlayDownload,
    'handleQueueDownload': s._sections.downloadRowActions.handleQueueDownload,
    'handleDeleteTorrent': s._sections.singleDeleteActions.handleDeleteTorrent,
    'handleDeleteAllTorrents': s._sections.deleteAllActions.handleDeleteAllTorrents,
    'showDeleteAllProgressDialog': s._sections.torrentBulkDelete.showDeleteAllProgressDialog,
    'handleDeleteAllDownloads': s._sections.deleteAllActions.handleDeleteAllDownloads,
    'showDeleteAllDownloadsProgressDialog': s._sections.downloadBulkDelete.showDeleteAllDownloadsProgressDialog,
    'handleDeleteDownload': s._sections.singleDeleteActions.handleDeleteDownload,
    'toggleSelectionMode': s._sections.selectionActions.toggleSelectionMode,
    'exitSelectionMode': s._sections.selectionActions.exitSelectionMode,
    'toggleTorrentSelection': s._sections.selectionActions.toggleTorrentSelection,
    'toggleDownloadSelection': s._sections.selectionActions.toggleDownloadSelection,
    'toggleSelectAll': s._sections.selectionActions.toggleSelectAll,
    'handleDeleteSelected': s._sections.selectionActions.handleDeleteSelected,
    'showDeleteSelectedProgressDialog': s._sections.selectedDelete.showDeleteSelectedProgressDialog,
    'copyToClipboard': s._sections.feedback.copyToClipboard,
    'showSuccess': s._sections.feedback.showSuccess,
    'getUserFriendlyErrorMessage': getUserFriendlyErrorMessage,
    'getLinkUnrestrictErrorMessage': getLinkUnrestrictErrorMessage,
    'showError': s._sections.feedback.showError,
    'resetListScroll': s._sections.catalogLoading.resetListScroll,
    'navigateIntoTorrent': s._navigateIntoTorrent,
    'navigateIntoFolder': s._navigateIntoFolder,
    'navigateUp': s._navigateUp,
    'getCurrentFolderTitle': s._getCurrentFolderTitle,
    'detectSeriesPattern': detectSeriesPattern,
    'collectVideoFilesRecursively': collectVideoFilesRecursively,
    'applySortedView': applySortedView,
    'extractSeasonNumber': extractSeasonNumber,
    'extractLeadingNumber': extractLeadingNumber,
    'applySeriesArrangedView': applySeriesArrangedView,
    'getCurrentViewMode': s._getCurrentViewMode,
    'setViewMode': s._setViewMode,
    'toggleSearch': s._toggleSearch,
    'performSearch': s._performSearch,
    'isBrowsePush': s._isBrowsePush,
    'handleDownloadTorrent': s._handleDownloadTorrent,
    'handleAddTorrentToPlaylist': s._handleAddTorrentToPlaylist,
    'handleAddTorrentToDebrifyTv': s._handleAddTorrentToDebrifyTv,
    'handlePlayMultiFileTorrent': s._handlePlayMultiFileTorrent,
    'showAddMagnetDialog': s._showAddMagnetDialog,
    'autoPasteMagnetLink': s._autoPasteMagnetLink,
    'isValidMagnetLink': isValidMagnetLink,
    'addMagnetWithDefaultSelection': s._addMagnetWithDefaultSelection,
    'showAdvancedMagnetDialog': s._showAdvancedMagnetDialog,
    'addMagnetWithSelection': s._addMagnetWithSelection,
    'showAddLinkDialog': s._showAddLinkDialog,
    'autoPasteLink': s._autoPasteLink,
    'isValidLink': isValidLink,
    'addLink': s._addLink,
    'playFileOnDemand': s._playFileOnDemand,
    'addFileToPlaylist': s._addFileToPlaylist,
    'downloadFileOnDemand': s._downloadFileOnDemand,
    'copyFileLinkOnDemand': s._copyFileLinkOnDemand,
    'playFile': s._playFile,
    'playFolder': s._playFolder,
    'downloadFile': s._downloadFile,
    'downloadFolder': s._downloadFolder,
    'downloadSelectedRealDebridFiles': s._downloadSelectedRealDebridFiles,
    'addNodeFileToPlaylist': s._addNodeFileToPlaylist,
    'addFolderToPlaylist': s._addFolderToPlaylist,
    'formatDate': s._formatDate,
    'copyNodeDownloadLink': s._copyNodeDownloadLink,
    'rawMode': FolderViewMode.raw,
    'sortedMode': FolderViewMode.sortedAZ,
    'seriesMode': FolderViewMode.seriesArrange,
  };
}
