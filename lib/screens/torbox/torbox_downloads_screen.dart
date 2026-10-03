import 'package:debrify/features/torbox_downloads/presentation/legacy_torbox/torbox_composition.dart';
import 'package:debrify/features/torbox_downloads/presentation/legacy_torbox/torbox_catalog_state.dart';
import 'package:debrify/features/torbox_downloads/presentation/legacy_torbox/torbox_web_state.dart';
import 'package:debrify/features/torbox_downloads/presentation/legacy_torbox/torbox_navigation_state.dart';
import 'package:debrify/features/torbox_downloads/presentation/legacy_torbox/torbox_view_state.dart';
import 'package:debrify/features/torbox_downloads/presentation/legacy_torbox/torbox_focus_state.dart';
import 'package:debrify/features/torbox_downloads/presentation/legacy_torbox/torbox_folder_search_state.dart';
import 'package:debrify/features/torbox_downloads/presentation/legacy_torbox/torbox_torrent_search_state.dart';
import 'package:debrify/features/torbox_downloads/presentation/legacy_torbox/torbox_selection_state.dart';
import 'package:debrify/features/torbox_downloads/presentation/legacy_torbox/torbox_add_input_state.dart';
import 'package:debrify/features/torbox_downloads/application/torbox_file_policy.dart';
import 'package:debrify/features/torbox_downloads/application/torbox_magnet_policy.dart';
import 'package:debrify/features/torbox_downloads/application/torbox_folder_policy.dart';

import 'package:debrify/services/storage/torbox_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/torbox_torrent.dart';
import '../../services/analytics_service.dart';
import '../../services/series_source_service.dart';
import '../../services/main_page_bridge.dart';

class TorboxDownloadsScreen extends StatefulWidget {
  const TorboxDownloadsScreen({
    super.key,
    this.initialTorrentToOpen,
    this.isPushedRoute = false,
    this.initialSearchQuery,
    this.selectSourceMode = false,
    this.onSourceSelected,
  });

  final TorboxTorrent? initialTorrentToOpen;

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
  State<TorboxDownloadsScreen> createState() => _TorboxDownloadsScreenState();
}

class _TorboxDownloadsScreenState extends State<TorboxDownloadsScreen> {
  final _catalog = TorboxCatalogState();
  final _web = TorboxWebState();
  final _nav = TorboxNavigationState();
  final _view = TorboxViewState();
  final _focus = TorboxFocusState();
  final _folderSearch = TorboxFolderSearchState();
  final _torrentSearch = TorboxTorrentSearchState();
  final _selection = TorboxSelectionState();
  final _addInput = TorboxAddInputState();
  late final _sections = createTorboxSections(
    (
      setState: setState,
      mounted: () => mounted,
      context: () => context,
      initialTorrentToOpen: () => widget.initialTorrentToOpen,
      isPushedRoute: () => widget.isPushedRoute,
      initialSearchQuery: () => widget.initialSearchQuery,
      selectSourceMode: () => widget.selectSourceMode,
      onSourceSelected: () => widget.onSourceSelected,
    ),
    (
      catalogState: _catalog,
      webState: _web,
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
    AnalyticsService.screenView('torbox_downloads');

    // Initialize first item focus node with DPAD up handler
    _focus.firstItemFocusNode = FocusNode(
      debugLabel: 'torbox-first-item',
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
          if (_torrentSearch.isTorrentSearchActive) {
            _focus.torrentSearchFocusNode.requestFocus();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
    );

    // Initialize torrent search focus node with DPAD navigation
    _focus.torrentSearchFocusNode = FocusNode(
      debugLabel: 'torbox-torrent-search',
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;
        if (key == LogicalKeyboardKey.arrowUp) {
          _focus.torrentSearchToggleFocusNode.requestFocus();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowDown) {
          _focus.firstItemFocusNode.requestFocus();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
    );

    _focus.scrollController.addListener(_sections.catalogLoading.onScroll);
    _focus.webDownloadScrollController.addListener(
      _sections.catalogLoading.onWebDownloadScroll,
    );
    _catalog.pendingInitialTorrent = widget.initialTorrentToOpen;

    if (widget.selectSourceMode &&
        widget.initialSearchQuery != null &&
        widget.initialSearchQuery!.isNotEmpty) {
      _torrentSearch.isTorrentSearchActive = true;
      _torrentSearch.torrentSearchController.text = widget.initialSearchQuery!;
      TorboxStorage.getTorboxHiddenFromNav().then((v) {
        if (mounted) setState(() => _torrentSearch.hiddenFromNav = v);
      });
    }

    _sections.catalogLoading.loadApiKeyAndTorrents();

    // Register back navigation handler for folder navigation
    if (widget.isPushedRoute) {
      MainPageBridge.pushRouteBackHandler(
        _sections.backNavigation.handleBackNavigation,
      );
      // Set up timeout - only when DEEP-LINKED into a specific torrent
      // (initialTorrentToOpen). Browsing from the Cloud hub has no target, so
      // the root list is the resting state — no spurious auto-close.
      Future.delayed(const Duration(seconds: 10), () {
        if (mounted &&
            widget.isPushedRoute &&
            !widget.selectSourceMode &&
            widget.initialTorrentToOpen != null &&
            _sections.folderNavigation.isAtRoot) {
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
      MainPageBridge.registerTabBackHandler(
        'torbox',
        _sections.backNavigation.handleBackNavigation,
      );
      // Register TV sidebar focus handler (tab index 5 = Torbox)
      _focus.tvContentFocusHandler = () {
        // Set flag to focus after data loads
        _focus.shouldFocusOnLoad = true;
        // Try to focus now in case data is already loaded
        _sections.focusActions.focusFirstItemOrFallback();
      };
      MainPageBridge.registerTvContentFocusHandler(
        5,
        _focus.tvContentFocusHandler!,
      );
    }
  }

  @override
  void didUpdateWidget(TorboxDownloadsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialTorrentToOpen != null) {
      _catalog.pendingInitialTorrent = widget.initialTorrentToOpen;
      _catalog.initialActionHandled = false;
      _sections.initialAction.maybeTriggerInitialAction();
    }
  }

  @override
  void dispose() {
    // Unregister back navigation handler
    if (widget.isPushedRoute) {
      MainPageBridge.popRouteBackHandler(
        _sections.backNavigation.handleBackNavigation,
      );
    } else {
      MainPageBridge.unregisterTabBackHandler('torbox');
      if (_focus.tvContentFocusHandler != null) {
        MainPageBridge.unregisterTvContentFocusHandler(
          5,
          _focus.tvContentFocusHandler!,
        );
      }
    }

    _focus.scrollController.dispose();
    _focus.webDownloadScrollController.dispose();
    _addInput.magnetController.dispose();
    _addInput.webLinkController.dispose();
    _addInput.webNameController.dispose();
    _addInput.webPasswordController.dispose();
    _focus.viewModeDropdownFocusNode.dispose();
    _focus.firstItemFocusNode.dispose();
    _focus.backButtonFocusNode.dispose();
    _folderSearch.searchController.dispose();
    _focus.searchFocusNode.dispose();
    _focus.searchButtonFocusNode.dispose();
    _focus.searchClearFocusNode.dispose();
    _torrentSearch.torrentSearchController.dispose();
    _focus.torrentSearchFocusNode.dispose();
    _focus.torrentSearchClearFocusNode.dispose();
    _focus.torrentSearchToggleFocusNode.dispose();
    _focus.deleteButtonFocusNode.dispose();
    super.dispose();
  }

  // ==================== WEB DOWNLOADS METHODS ====================

  // --- Multi-select helpers ---

  // ==================== FILE/FOLDER ACTION METHODS ====================

  // ==================== FOLDER NAVIGATION METHODS ====================

  // ============ Torrent-Level Search Methods ============

  // ============ File Search Methods ============

  @override
  Widget build(BuildContext context) => _sections.rootLayout.build(context);
}

/// Frozen original-code characterization accessor; production does not call it.
@visibleForTesting
Map<String, Object?> torboxDownloadsTestAccess(
  State<TorboxDownloadsScreen> state,
) {
  final s = state as _TorboxDownloadsScreenState;
  return {
    'handleBackNavigation': s._sections.backNavigation.handleBackNavigation,
    'navigateIntoTorrent': s._sections.folderNavigation.navigateIntoTorrent,
    'navigateIntoWebDownload':
        s._sections.folderNavigation.navigateIntoWebDownload,
    'navigateIntoFolder': s._sections.folderNavigation.navigateIntoFolder,
    'navigateUp': s._sections.folderNavigation.navigateUp,
    'toggleSelectionMode': s._sections.selectionActions.toggleSelectionMode,
    'exitSelectionMode': s._sections.selectionActions.exitSelectionMode,
    'toggleTorrentSearch': s._sections.torrentSearch.toggleTorrentSearch,
    'toggleSearch': s._sections.folderSearch.toggleSearch,
    'performSearch': s._sections.folderSearch.performSearch,
    'submitTorrentSearch': s._sections.torrentSearch.submitTorrentSearch,
    'fetchTorrents': s._sections.catalogLoading.fetchTorrents,
    'fetchWebDownloads': s._sections.catalogLoading.fetchWebDownloads,
    'loadMore': s._sections.catalogLoading.loadMore,
    'loadMoreWebDownloads': s._sections.catalogLoading.loadMoreWebDownloads,
    'confirmDeleteTorrent':
        s._sections.torrentDeleteActions.confirmDeleteTorrent,
    'confirmDeleteAll': s._sections.torrentDeleteActions.confirmDeleteAll,
    'confirmDeleteWebDownload':
        s._sections.webDeleteAction.confirmDeleteWebDownload,
    'handleDeleteSelected': s._sections.selectionActions.handleDeleteSelected,
    'showDeleteSelectedProgressDialog':
        s._sections.bulkDelete.showDeleteSelectedProgressDialog,
    'showAddWebDownloadDialog':
        s._sections.webCreateActions.showAddWebDownloadDialog,
    'showAddMagnetDialog': s._sections.magnetActions.showAddMagnetDialog,
    'addMagnetToTorbox': s._sections.magnetActions.addMagnetToTorbox,
    'handleAddToPlaylist':
        s._sections.torrentPlaylistActions.handleAddToPlaylist,
    'handleAddWebDownloadToPlaylist':
        s._sections.webLinkPlaylistActions.handleAddWebDownloadToPlaylist,
    'addFileOrFolderToPlaylist':
        s._sections.filePlaylistLinks.addFileOrFolderToPlaylist,
    'extractSeasonNumber': extractSeasonNumber,
    'extractLeadingNumber': extractLeadingNumber,
    'applySortedView': applySortedView,
    'applySeriesArrangedView': applySeriesArrangedView,
    'detectSeriesPattern': detectSeriesPattern,
    'setViewMode': s._sections.viewModes.setViewMode,
    'getCurrentViewMode': s._sections.viewModes.getCurrentViewMode,
    'torboxDisplayName': torboxDisplayName,
    'torboxFileLooksLikeVideo': torboxFileLooksLikeVideo,
    'findFirstEpisodeIndex': findFirstEpisodeIndex,
    'isValidMagnetLink': isValidMagnetLink,
    'focusFirstItemOrFallback':
        s._sections.focusActions.focusFirstItemOrFallback,
    'selectedView': s._catalog.selectedView,
    'scrollController': s._focus.scrollController,
    'torrents': s._catalog.torrents,
    'magnetController': s._addInput.magnetController,
    'tvContentFocusHandler': s._focus.tvContentFocusHandler,
    'isLoading': s._catalog.isLoading,
    'isLoadingMore': s._catalog.isLoadingMore,
    'hasMore': s._catalog.hasMore,
    'initialLoad': s._catalog.initialLoad,
    'offset': s._catalog.offset,
    'errorMessage': s._catalog.errorMessage,
    'apiKey': s._catalog.apiKey,
    'pendingInitialTorrent': s._catalog.pendingInitialTorrent,
    'initialActionHandled': s._catalog.initialActionHandled,
    'webDownloads': s._web.webDownloads,
    'webDownloadScrollController': s._focus.webDownloadScrollController,
    'isLoadingWebDownloads': s._web.isLoadingWebDownloads,
    'isLoadingMoreWebDownloads': s._web.isLoadingMoreWebDownloads,
    'hasMoreWebDownloads': s._web.hasMoreWebDownloads,
    'webDownloadOffset': s._web.webDownloadOffset,
    'webDownloadErrorMessage': s._web.webDownloadErrorMessage,
    'webLinkController': s._addInput.webLinkController,
    'webNameController': s._addInput.webNameController,
    'webPasswordController': s._addInput.webPasswordController,
    'currentTorrent': s._nav.currentTorrent,
    'currentWebDownload': s._nav.currentWebDownload,
    'currentPath': s._nav.currentPath,
    'currentFolderNode': s._nav.currentFolderNode,
    'navigationStack': s._nav.navigationStack,
    'torrentViewModes': s._view.torrentViewModes,
    'webDownloadViewModes': s._view.webDownloadViewModes,
    'currentViewNodes': s._view.currentViewNodes,
    'viewModeDropdownFocusNode': s._focus.viewModeDropdownFocusNode,
    'firstItemFocusNode': s._focus.firstItemFocusNode,
    'backButtonFocusNode': s._focus.backButtonFocusNode,
    'shouldFocusOnLoad': s._focus.shouldFocusOnLoad,
    'isSearchActive': s._folderSearch.isSearchActive,
    'searchController': s._folderSearch.searchController,
    'searchFocusNode': s._focus.searchFocusNode,
    'searchButtonFocusNode': s._focus.searchButtonFocusNode,
    'searchClearFocusNode': s._focus.searchClearFocusNode,
    'searchResults': s._folderSearch.searchResults,
    'isTorrentSearchActive': s._torrentSearch.isTorrentSearchActive,
    'torrentSearchController': s._torrentSearch.torrentSearchController,
    'torrentSearchFocusNode': s._focus.torrentSearchFocusNode,
    'torrentSearchClearFocusNode': s._focus.torrentSearchClearFocusNode,
    'torrentSearchToggleFocusNode': s._focus.torrentSearchToggleFocusNode,
    'torrentSearchQuery': s._torrentSearch.torrentSearchQuery,
    'allTorrentsForSearch': s._torrentSearch.allTorrentsForSearch,
    'isLoadingTorrentSearch': s._torrentSearch.isLoadingTorrentSearch,
    'hiddenFromNav': s._torrentSearch.hiddenFromNav,
    'isSelectionMode': s._selection.isSelectionMode,
    'selectedTorrentIds': s._selection.selectedTorrentIds,
    'selectedWebDownloadIds': s._selection.selectedWebDownloadIds,
    'deleteButtonFocusNode': s._focus.deleteButtonFocusNode,
    'torrentSearchSubmitFocus': s._focus.torrentSearchSubmitFocus,
    'isAtRoot': s._sections.folderNavigation.isAtRoot,
    'currentItems': s._sections.rootLayout.currentItems,
    'filteredTorrentSearchResults':
        s._sections.torrentSearch.filteredTorrentSearchResults,
  };
}
