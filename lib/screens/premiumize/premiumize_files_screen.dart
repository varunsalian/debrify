import 'package:debrify/features/premiumize_files/presentation/legacy_premiumize/premiumize_composition.dart';
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
import 'package:flutter/material.dart';
// re-exports PlaylistEntry
import '../../services/analytics_service.dart';
import '../../services/main_page_bridge.dart';
import '../../services/series_source_service.dart';

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
  @override
  Widget build(BuildContext context) => _sections.rootLayout.build(context);

  PremiumizeSections? _sectionCache;
  PremiumizeSections get _sections =>
      _sectionCache ??= createPremiumizeSections(
        (
          context: () => context,
          mounted: () => mounted,
          setState: setState,
          initialFolderId: () => widget.initialFolderId,
          initialFolderName: () => widget.initialFolderName,
          initialSearchQuery: () => widget.initialSearchQuery,
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

  final _catalog = PremiumizeCatalogState();
  final _nav = PremiumizeNavigationState();
  final _view = PremiumizeViewState();
  final _focus = PremiumizeFocusState();
  final _selection = PremiumizeSelectionState();
  final _search = PremiumizeSearchState();
  final _link = PremiumizeLinkState();

  // Premiumize tab index in main.dart's page list (for TV focus + back handler).
  static const int _tabIndex = 11;

  @override
  void initState() {
    super.initState();
    AnalyticsService.screenView('premiumize_files');
    _sections.catalogLoading.loadSettings();

    if (widget.isPushedRoute) {
      MainPageBridge.pushRouteBackHandler(
        _sections.backNavigation.handleBackNavigation,
      );
    } else {
      MainPageBridge.registerTabBackHandler(
        'premiumize',
        _sections.backNavigation.handleBackNavigation,
      );
      _focus.tvContentFocusHandler = () {
        _focus.shouldFocusOnLoad = true;
        _sections.focusActions.focusFirstItemOrFallback();
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
      MainPageBridge.popRouteBackHandler(
        _sections.backNavigation.handleBackNavigation,
      );
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

  // ── Series helpers (shared shape with PikPak/playlist player) ────────────────
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
    'isAllSelected': s._sections.selectionActions.isAllSelected,
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
    'isAtRoot': s._sections.folderNavigation.isAtRoot,
    'loadSettings': s._sections.catalogLoading.loadSettings,
    'loadFolder': s._sections.catalogLoading.loadFolder,
    'loadTransfers': s._sections.catalogLoading.loadTransfers,
    'refresh': s._sections.catalogLoading.refresh,
    'switchView': s._sections.catalogLoading.switchView,
    'navigateIntoFolder': s._sections.folderNavigation.navigateIntoFolder,
    'navigateUp': s._sections.folderNavigation.navigateUp,
    'handleBackNavigation': s._sections.backNavigation.handleBackNavigation,
    'getCurrentViewMode': s._sections.viewModes.getCurrentViewMode,
    'setViewMode': s._sections.viewModes.setViewMode,
    'applyViewMode': s._sections.viewModes.applyViewMode,
    'applySortedView': applySortedView,
    'extractSeasonNumber': extractSeasonNumber,
    'extractLeadingNumber': extractLeadingNumber,
    'toggleSearch': s._sections.searchActions.toggleSearch,
    'performSearch': s._sections.searchActions.performSearch,
    'runCloudSearch': s._sections.searchActions.runCloudSearch,
    'selectBoundSource': s._sections.sourceBinding.selectBoundSource,
    'playFile': s._sections.filePlayback.playFile,
    'playFolder': s._sections.folderPlayback.playFolder,
    'playPremiumizeVideos': s._sections.folderPlayback.playPremiumizeVideos,
    'downloadFile': s._sections.fileDownload.downloadFile,
    'downloadFolder': s._sections.folderDownload.downloadFolder,
    'downloadSelectedFiles': s._sections.folderDownload.downloadSelectedFiles,
    'addToPlaylist': s._sections.playlistActions.addToPlaylist,
    'addFileToPlaylist': s._sections.playlistActions.addFileToPlaylist,
    'addFolderToPlaylist': s._sections.playlistActions.addFolderToPlaylist,
    'showDeleteDialog': s._sections.deleteActions.showDeleteDialog,
    'handleDeleteSelected': s._sections.deleteActions.handleDeleteSelected,
    'executeDelete': s._sections.deleteActions.executeDelete,
    'deleteTransfer': s._sections.transferActions.deleteTransfer,
    'clearFinishedTransfers':
        s._sections.transferActions.clearFinishedTransfers,
    'showAddLinkDialog': s._sections.linkActions.showAddLinkDialog,
    'autoPasteLink': s._sections.linkActions.autoPasteLink,
    'addLink': s._sections.linkActions.addLink,
    'toggleSelectionMode': s._sections.selectionActions.toggleSelectionMode,
    'exitSelectionMode': s._sections.selectionActions.exitSelectionMode,
    'toggleSelection': s._sections.selectionActions.toggleSelection,
    'toggleSelectAll': s._sections.selectionActions.toggleSelectAll,
    'showLoadingDialog': s._sections.feedback.showLoadingDialog,
    'dismissDialog': s._sections.feedback.dismissDialog,
    'focusFirstItemOrFallback':
        s._sections.focusActions.focusFirstItemOrFallback,
    'showSnackBar': s._sections.feedback.showSnackBar,
    'formatUnixDate': s._sections.dateFormat.formatUnixDate,
    'formatPlaylistTitle': formatPlaylistTitle,
    'composeEntryTitle': composeEntryTitle,
    'findFirstEpisodeIndex': findFirstEpisodeIndex,
    'isBrowsePush': s._sections.rootLayout.isBrowsePush,
    'rawMode': PremiumizeFolderViewMode.raw,
    'sortedMode': PremiumizeFolderViewMode.sortedAZ,
    'filesView': PremiumizeView.files,
    'transfersView': PremiumizeView.transfers,
  };
}
