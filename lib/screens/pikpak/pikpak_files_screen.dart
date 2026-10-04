import 'package:debrify/features/pikpak_files/models/folder_view_mode.dart';
import 'package:debrify/features/pikpak_files/application/pikpak_sort_policy.dart';
import 'package:debrify/features/pikpak_files/application/pikpak_playlist_titles.dart';
import 'package:debrify/features/pikpak_files/application/pikpak_link_policy.dart';
import 'package:debrify/features/pikpak_files/presentation/legacy_pikpak/pikpak_catalog_state.dart';
import 'package:debrify/features/pikpak_files/presentation/legacy_pikpak/pikpak_navigation_state.dart';
import 'package:debrify/features/pikpak_files/presentation/legacy_pikpak/pikpak_view_state.dart';
import 'package:debrify/features/pikpak_files/presentation/legacy_pikpak/pikpak_focus_state.dart';
import 'package:debrify/features/pikpak_files/presentation/legacy_pikpak/pikpak_selection_state.dart';
import 'package:debrify/features/pikpak_files/presentation/legacy_pikpak/pikpak_search_state.dart';
import 'package:debrify/features/pikpak_files/presentation/legacy_pikpak/pikpak_link_state.dart';
import 'package:debrify/features/pikpak_files/presentation/legacy_pikpak/pikpak_composition.dart';
import 'package:flutter/material.dart';
import '../../services/analytics_service.dart';
import '../../services/main_page_bridge.dart';
import '../../services/series_source_service.dart';

class PikPakFilesScreen extends StatefulWidget {
  final String? initialFolderId;
  final String? initialFolderName;
  final bool selectSourceMode;
  final Future<void> Function(SeriesSource)? onSourceSelected;

  /// When true, this screen was pushed as a route (not displayed in a tab).
  /// Back navigation will pop the route instead of switching tabs.
  final bool isPushedRoute;

  const PikPakFilesScreen({
    super.key,
    this.initialFolderId,
    this.initialFolderName,
    this.isPushedRoute = false,
    this.selectSourceMode = false,
    this.onSourceSelected,
  });

  @override
  State<PikPakFilesScreen> createState() => _PikPakFilesScreenState();
}

class _PikPakFilesScreenState extends State<PikPakFilesScreen> {
  final _catalog = PikpakCatalogState();
  final _nav = PikpakNavigationState();
  final _view = PikpakViewState();
  final _focus = PikpakFocusState();
  final _selection = PikpakSelectionState();
  final _search = PikpakSearchState();
  final _link = PikpakLinkState();
  PikpakSections? _sectionCache;
  PikpakSections get _sections => _sectionCache ??= createPikpakSections(
    (
      setState: setState,
      mounted: () => mounted,
      context: () => context,
      initialFolderId: () => widget.initialFolderId,
      initialFolderName: () => widget.initialFolderName,
      isPushedRoute: () => widget.isPushedRoute,
      selectSourceMode: () => widget.selectSourceMode,
      onSourceSelected: () => widget.onSourceSelected,
    ),
    (
      catalogState: _catalog,
      navigationState: _nav,
      viewState: _view,
      focusState: _focus,
      selectionState: _selection,
      searchState: _search,
      linkState: _link,
    ),
  );

  @override
  void initState() {
    super.initState();
    AnalyticsService.screenView('pikpak_files');
    _focus.scrollController.addListener(_sections.catalogLoading.onScroll);
    _sections.catalogLoading.loadSettings();

    // Register back navigation handler for folder navigation
    if (widget.isPushedRoute) {
      MainPageBridge.pushRouteBackHandler(
        _sections.backNavigation.handleBackNavigation,
      );
      // Set up timeout - only when DEEP-LINKED into a specific folder
      // (initialFolderId). Browsing from the Cloud hub has no target, so the
      // root is the resting state — no spurious auto-close.
      Future.delayed(const Duration(seconds: 10), () {
        if (mounted &&
            widget.isPushedRoute &&
            widget.initialFolderId != null &&
            _nav.currentFolderId == null) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to open folder. Please try again.'),
              backgroundColor: Color(0xFFEF4444),
            ),
          );
        }
      });
    } else {
      MainPageBridge.registerTabBackHandler(
        'pikpak',
        _sections.backNavigation.handleBackNavigation,
      );
      // Register TV sidebar focus handler (tab index 6 = PikPak)
      _focus.tvContentFocusHandler = () {
        // Set flag to focus after data loads
        _focus.shouldFocusOnLoad = true;
        // Try to focus now in case data is already loaded
        _sections.focusActions.focusFirstItemOrFallback();
      };
      MainPageBridge.registerTvContentFocusHandler(
        6,
        _focus.tvContentFocusHandler!,
      );
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
      MainPageBridge.unregisterTabBackHandler('pikpak');
      if (_focus.tvContentFocusHandler != null) {
        MainPageBridge.unregisterTvContentFocusHandler(
          6,
          _focus.tvContentFocusHandler!,
        );
      }
    }

    _focus.scrollController.dispose();
    _link.linkController.dispose();
    _focus.refreshButtonFocusNode.dispose();
    _focus.backButtonFocusNode.dispose();
    _focus.retryButtonFocusNode.dispose();
    _focus.settingsButtonFocusNode.dispose();
    _focus.viewModeDropdownFocusNode.dispose();
    _focus.addLinkButtonFocusNode.dispose();
    _focus.firstItemFocusNode.dispose();
    _search.searchController.dispose();
    _search.searchFocusNode.dispose();
    _search.searchButtonFocusNode.dispose();
    _search.searchClearFocusNode.dispose();
    _focus.deleteButtonFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _sections.rootLayout.build(context);
}

/// Original-code characterization seam: fresh state and real action tear-offs.
@visibleForTesting
Map<String, Object?> pikpakFilesTestAccess(State<PikPakFilesScreen> state) {
  final s = state as _PikPakFilesScreenState;
  return {
    'scrollController': s._focus.scrollController,
    'files': s._catalog.files,
    'tvContentFocusHandler': s._focus.tvContentFocusHandler,
    'isLoading': s._catalog.isLoading,
    'initialLoad': s._catalog.initialLoad,
    'errorMessage': s._catalog.errorMessage,
    'pikpakEnabled': s._catalog.pikpakEnabled,
    'showVideosOnly': s._catalog.showVideosOnly,
    'ignoreSmallVideos': s._catalog.ignoreSmallVideos,
    'linkController': s._link.linkController,
    'isAddingLink': s._link.isAddingLink,
    'nextPageToken': s._catalog.nextPageToken,
    'hasMore': s._catalog.hasMore,
    'isLoadingMore': s._catalog.isLoadingMore,
    'currentFolderId': s._nav.currentFolderId,
    'currentFolderName': s._nav.currentFolderName,
    'navigationStack': s._nav.navigationStack,
    'restrictedFolderId': s._nav.restrictedFolderId,
    'restrictedFolderName': s._nav.restrictedFolderName,
    'isAtRestrictedRoot': s._nav.isAtRestrictedRoot,
    'folderViewModes': s._view.folderViewModes,
    'isInVirtualFolder': s._view.isInVirtualFolder,
    'virtualFolderName': s._view.virtualFolderName,
    'virtualFolderFiles': s._view.virtualFolderFiles,
    'recursiveFileCache': s._view.recursiveFileCache,
    'refreshButtonFocusNode': s._focus.refreshButtonFocusNode,
    'backButtonFocusNode': s._focus.backButtonFocusNode,
    'retryButtonFocusNode': s._focus.retryButtonFocusNode,
    'settingsButtonFocusNode': s._focus.settingsButtonFocusNode,
    'viewModeDropdownFocusNode': s._focus.viewModeDropdownFocusNode,
    'addLinkButtonFocusNode': s._focus.addLinkButtonFocusNode,
    'firstItemFocusNode': s._focus.firstItemFocusNode,
    'shouldFocusOnLoad': s._focus.shouldFocusOnLoad,
    'isSelectionMode': s._selection.isSelectionMode,
    'selectedFileIds': s._selection.selectedFileIds,
    'deleteButtonFocusNode': s._focus.deleteButtonFocusNode,
    'isSearchActive': s._search.isSearchActive,
    'searchController': s._search.searchController,
    'searchFocusNode': s._search.searchFocusNode,
    'searchButtonFocusNode': s._search.searchButtonFocusNode,
    'searchClearFocusNode': s._search.searchClearFocusNode,
    'searchResults': s._search.searchResults,
    'selectableFileCount': s._sections.selectionActions.selectableFileCount,
    'isAllSelected': s._sections.selectionActions.isAllSelected,
    'selectBoundSource': s._sections.sourceBinding.selectBoundSource,
    'onScroll': s._sections.catalogLoading.onScroll,
    'resetListScroll': s._sections.catalogLoading.resetListScroll,
    'focusFirstItemOrFallback':
        s._sections.focusActions.focusFirstItemOrFallback,
    'handleBackNavigation': s._sections.backNavigation.handleBackNavigation,
    'loadSettings': s._sections.catalogLoading.loadSettings,
    'handleRestrictedFolderDeleted':
        s._sections.catalogLoading.handleRestrictedFolderDeleted,
    'loadFiles': s._sections.catalogLoading.loadFiles,
    'loadMoreFiles': s._sections.catalogLoading.loadMoreFiles,
    'filterFiles': s._sections.folderNavigation.filterFiles,
    'navigateIntoFolder': s._sections.folderNavigation.navigateIntoFolder,
    'navigateUp': s._sections.folderNavigation.navigateUp,
    'navigateUpWithVirtual': s._sections.folderNavigation.navigateUpWithVirtual,
    'navigateIntoVirtualFolder':
        s._sections.folderNavigation.navigateIntoVirtualFolder,
    'playFile': s._sections.filePlayback.playFile,
    'downloadFile': s._sections.fileDownload.downloadFile,
    'downloadFolder': s._sections.folderDownload.downloadFolder,
    'downloadSelectedPikPakFiles':
        s._sections.folderDownload.downloadSelectedPikPakFiles,
    'refreshFiles': s._sections.feedback.refreshFiles,
    'showDeleteDialog': s._sections.deleteActions.showDeleteDialog,
    'deleteFile': s._sections.deleteActions.deleteFile,
    'toggleSelectionMode': s._sections.selectionActions.toggleSelectionMode,
    'exitSelectionMode': s._sections.selectionActions.exitSelectionMode,
    'toggleFileSelection': s._sections.selectionActions.toggleFileSelection,
    'toggleSelectAll': s._sections.selectionActions.toggleSelectAll,
    'handleDeleteSelected': s._sections.deleteActions.handleDeleteSelected,
    'executeDeleteSelected': s._sections.deleteActions.executeDeleteSelected,
    'showSnackBar': s._sections.feedback.showSnackBar,
    'getCurrentViewMode': s._sections.viewModes.getCurrentViewMode,
    'setViewMode': s._sections.viewModes.setViewMode,
    'showFallbackToSorted': s._sections.viewModes.showFallbackToSorted,
    'applyViewMode': s._sections.viewModes.applyViewMode,
    'applySortedView': applySortedView,
    'extractSeasonNumber': extractSeasonNumber,
    'extractLeadingNumber': extractLeadingNumber,
    'applySeriesArrangeView': s._sections.viewModes.applySeriesArrangeView,
    'toggleSearch': s._sections.searchActions.toggleSearch,
    'performSearch': s._sections.searchActions.performSearch,
    'isBrowsePush': s._sections.rootLayout.isBrowsePush,
    'formatDate': s._sections.fileList.formatDate,
    'playFolder': s._sections.folderPlayback.playFolder,
    'playPikPakVideos': s._sections.folderPlayback.playPikPakVideos,
    'handleAddToPlaylist': s._sections.playlistActions.handleAddToPlaylist,
    'addSingleFileToPlaylist':
        s._sections.playlistActions.addSingleFileToPlaylist,
    'addFolderToPlaylist': s._sections.playlistActions.addFolderToPlaylist,
    'pikpakDisplayName': pikpakDisplayName,
    'formatPikPakPlaylistTitle': formatPikPakPlaylistTitle,
    'combineSeriesAndEpisodeTitle': combineSeriesAndEpisodeTitle,
    'findFirstEpisodeIndex': findFirstEpisodeIndex,
    'showAddLinkDialog': s._sections.linkActions.showAddLinkDialog,
    'autoPasteLink': s._sections.linkActions.autoPasteLink,
    'isValidPikPakLink': isValidPikPakLink,
    'addLink': s._sections.linkActions.addLink,
    'rawMode': FolderViewMode.raw,
    'sortedMode': FolderViewMode.sortedAZ,
    'seriesMode': FolderViewMode.seriesArrange,
  };
}
