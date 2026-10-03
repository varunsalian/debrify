import 'package:debrify/features/debrid_downloads/presentation/legacy_debrid/debrid_composition.dart';
import 'package:debrify/features/debrid_downloads/models/folder_view_mode.dart';
import 'package:debrify/features/debrid_downloads/application/debrid_folder_policy.dart';
import 'package:debrify/features/debrid_downloads/application/debrid_input_policy.dart';
import 'package:debrify/features/debrid_downloads/application/debrid_error_policy.dart';

import 'package:debrify/services/storage/real_debrid_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/rd_torrent.dart';
import '../services/analytics_service.dart';
import '../services/series_source_service.dart';
import '../services/main_page_bridge.dart';

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
  late final _sections = createDebridSections(
    (
      setState: setState,
      mounted: () => mounted,
      context: () => context,
      initialTorrentForOptions: () => widget.initialTorrentForOptions,
      isPushedRoute: () => widget.isPushedRoute,
      initialSearchQuery: () => widget.initialSearchQuery,
      selectSourceMode: () => widget.selectSourceMode,
      onSourceSelected: () => widget.onSourceSelected,
    ),
    (
      catalogState: _catalog,
      downloadState: _downloadState,
      navigationState: _nav,
      viewState: _view,
      focusState: _focus,
      folderSearchState: _folderSearch,
      torrentSearchState: _torrentSearch,
      selectionState: _selection,
      addInputState: _addInput,
    ),
  );

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
    _focus.torrentScrollController.addListener(
      _sections.catalogLoading.onTorrentScroll,
    );
    _focus.downloadScrollController.addListener(
      _sections.catalogLoading.onDownloadScroll,
    );

    // Register back navigation handler for folder navigation
    if (widget.isPushedRoute) {
      // Pushed as a route - use pushed route handler
      MainPageBridge.pushRouteBackHandler(
        _sections.backNavigation.handleBackNavigation,
      );
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
      MainPageBridge.registerTvContentFocusHandler(
        4,
        _focus.tvContentFocusHandler!,
      );
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
          await _sections.folderNavigation.navigateIntoTorrent(
            widget.initialTorrentForOptions!,
          );
        }
      }
    });
  }

  @override
  void dispose() {
    // Unregister back navigation handler
    if (widget.isPushedRoute) {
      MainPageBridge.popRouteBackHandler(
        _sections.backNavigation.handleBackNavigation,
      );
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

  @override
  Widget build(BuildContext context) => _sections.rootLayout.build(context);
}

/// Frozen original-code characterization accessor; production does not call it.
@visibleForTesting
Map<String, Object?> debridDownloadsTestAccess(
  State<DebridDownloadsScreen> state,
) {
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
    'focusFirstItemOrFallback':
        s._sections.focusActions.focusFirstItemOrFallback,
    'handleBackNavigation': s._sections.backNavigation.handleBackNavigation,
    'onTorrentScroll': s._sections.catalogLoading.onTorrentScroll,
    'onDownloadScroll': s._sections.catalogLoading.onDownloadScroll,
    'loadApiKeyAndData': s._sections.catalogLoading.loadApiKeyAndData,
    'fetchTorrents': s._sections.catalogLoading.fetchTorrents,
    'loadMoreTorrents': s._sections.catalogLoading.loadMoreTorrents,
    'toggleTorrentSearch': s._sections.torrentSearch.toggleTorrentSearch,
    'queryMatchesInitialTitle':
        s._sections.torrentSearch.queryMatchesInitialTitle,
    'submitTorrentSearch': s._sections.torrentSearch.submitTorrentSearch,
    'completeTorrentSearchSubmitFocus':
        s._sections.torrentSearch.completeTorrentSearchSubmitFocus,
    'fetchAllTorrentsForSearch':
        s._sections.torrentSearch.fetchAllTorrentsForSearch,
    'filteredSearchTorrents': s._sections.torrentSearch.filteredSearchTorrents,
    'fetchDownloads': s._sections.catalogLoading.fetchDownloads,
    'loadMoreDownloads': s._sections.catalogLoading.loadMoreDownloads,
    'handleDownloadAction': s._sections.downloadRowActions.handleDownloadAction,
    'handlePlayDownload': s._sections.downloadRowActions.handlePlayDownload,
    'handleQueueDownload': s._sections.downloadRowActions.handleQueueDownload,
    'handleDeleteTorrent': s._sections.singleDeleteActions.handleDeleteTorrent,
    'handleDeleteAllTorrents':
        s._sections.deleteAllActions.handleDeleteAllTorrents,
    'showDeleteAllProgressDialog':
        s._sections.torrentBulkDelete.showDeleteAllProgressDialog,
    'handleDeleteAllDownloads':
        s._sections.deleteAllActions.handleDeleteAllDownloads,
    'showDeleteAllDownloadsProgressDialog':
        s._sections.downloadBulkDelete.showDeleteAllDownloadsProgressDialog,
    'handleDeleteDownload':
        s._sections.singleDeleteActions.handleDeleteDownload,
    'toggleSelectionMode': s._sections.selectionActions.toggleSelectionMode,
    'exitSelectionMode': s._sections.selectionActions.exitSelectionMode,
    'toggleTorrentSelection':
        s._sections.selectionActions.toggleTorrentSelection,
    'toggleDownloadSelection':
        s._sections.selectionActions.toggleDownloadSelection,
    'toggleSelectAll': s._sections.selectionActions.toggleSelectAll,
    'handleDeleteSelected': s._sections.selectionActions.handleDeleteSelected,
    'showDeleteSelectedProgressDialog':
        s._sections.selectedDelete.showDeleteSelectedProgressDialog,
    'copyToClipboard': s._sections.feedback.copyToClipboard,
    'showSuccess': s._sections.feedback.showSuccess,
    'getUserFriendlyErrorMessage': getUserFriendlyErrorMessage,
    'getLinkUnrestrictErrorMessage': getLinkUnrestrictErrorMessage,
    'showError': s._sections.feedback.showError,
    'resetListScroll': s._sections.catalogLoading.resetListScroll,
    'navigateIntoTorrent': s._sections.folderNavigation.navigateIntoTorrent,
    'navigateIntoFolder': s._sections.folderNavigation.navigateIntoFolder,
    'navigateUp': s._sections.folderNavigation.navigateUp,
    'getCurrentFolderTitle': s._sections.folderNavigation.getCurrentFolderTitle,
    'detectSeriesPattern': detectSeriesPattern,
    'collectVideoFilesRecursively': collectVideoFilesRecursively,
    'applySortedView': applySortedView,
    'extractSeasonNumber': extractSeasonNumber,
    'extractLeadingNumber': extractLeadingNumber,
    'applySeriesArrangedView': applySeriesArrangedView,
    'getCurrentViewMode': s._sections.viewModes.getCurrentViewMode,
    'setViewMode': s._sections.viewModes.setViewMode,
    'toggleSearch': s._sections.folderSearch.toggleSearch,
    'performSearch': s._sections.folderSearch.performSearch,
    'isBrowsePush': s._sections.torrentToolbar.isBrowsePush,
    'handleDownloadTorrent':
        s._sections.torrentDownloadAction.handleDownloadTorrent,
    'handleAddTorrentToPlaylist':
        s._sections.torrentPlaylistActions.handleAddTorrentToPlaylist,
    'handleAddTorrentToDebrifyTv':
        s._sections.torrentPlaylistActions.handleAddTorrentToDebrifyTv,
    'handlePlayMultiFileTorrent':
        s._sections.multifilePlayback.handlePlayMultiFileTorrent,
    'showAddMagnetDialog': s._sections.magnetActions.showAddMagnetDialog,
    'autoPasteMagnetLink': s._sections.magnetActions.autoPasteMagnetLink,
    'isValidMagnetLink': isValidMagnetLink,
    'addMagnetWithDefaultSelection':
        s._sections.magnetActions.addMagnetWithDefaultSelection,
    'showAdvancedMagnetDialog':
        s._sections.magnetActions.showAdvancedMagnetDialog,
    'addMagnetWithSelection': s._sections.magnetActions.addMagnetWithSelection,
    'showAddLinkDialog': s._sections.linkActions.showAddLinkDialog,
    'autoPasteLink': s._sections.linkActions.autoPasteLink,
    'isValidLink': isValidLink,
    'addLink': s._sections.linkActions.addLink,
    'playFileOnDemand': s._sections.dormantFileActions.playFileOnDemand,
    'addFileToPlaylist': s._sections.dormantFileActions.addFileToPlaylist,
    'downloadFileOnDemand': s._sections.dormantFileActions.downloadFileOnDemand,
    'copyFileLinkOnDemand': s._sections.dormantFileActions.copyFileLinkOnDemand,
    'playFile': s._sections.filePlayback.playFile,
    'playFolder': s._sections.filePlayback.playFolder,
    'downloadFile': s._sections.fileDownloads.downloadFile,
    'downloadFolder': s._sections.fileDownloads.downloadFolder,
    'downloadSelectedRealDebridFiles':
        s._sections.fileDownloads.downloadSelectedRealDebridFiles,
    'addNodeFileToPlaylist':
        s._sections.nodePlaylistLinks.addNodeFileToPlaylist,
    'addFolderToPlaylist': s._sections.nodePlaylistLinks.addFolderToPlaylist,
    'formatDate': s._sections.torrentRow.formatDate,
    'copyNodeDownloadLink': s._sections.nodePlaylistLinks.copyNodeDownloadLink,
    'rawMode': FolderViewMode.raw,
    'sortedMode': FolderViewMode.sortedAZ,
    'seriesMode': FolderViewMode.seriesArrange,
  };
}
