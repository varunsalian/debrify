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
import 'package:debrify/features/debrid_downloads/presentation/legacy_debrid/debrid_folder_navigation.dart';
import 'package:debrify/features/debrid_downloads/presentation/legacy_debrid/debrid_view_modes.dart';
import 'package:debrify/features/debrid_downloads/presentation/legacy_debrid/debrid_folder_search.dart';
import 'package:debrify/features/debrid_downloads/presentation/legacy_debrid/debrid_torrent_search.dart';
import 'package:debrify/features/debrid_downloads/presentation/legacy_debrid/debrid_torrent_download_action.dart';
import 'package:debrify/features/debrid_downloads/presentation/legacy_debrid/debrid_torrent_playlist_actions.dart';
import 'package:debrify/features/debrid_downloads/presentation/legacy_debrid/debrid_multifile_playback.dart';
import 'package:debrify/features/debrid_downloads/presentation/legacy_debrid/debrid_magnet_actions.dart';
import 'package:debrify/features/debrid_downloads/presentation/legacy_debrid/debrid_link_actions.dart';
import 'package:debrify/features/debrid_downloads/presentation/legacy_debrid/debrid_file_playback.dart';
import 'package:debrify/features/debrid_downloads/presentation/legacy_debrid/debrid_file_downloads.dart';
import 'package:debrify/features/debrid_downloads/presentation/legacy_debrid/debrid_node_playlist_links.dart';
import 'package:debrify/features/debrid_downloads/presentation/legacy_debrid/debrid_dormant_torrent_actions.dart';
import 'package:debrify/features/debrid_downloads/presentation/legacy_debrid/debrid_dormant_file_actions.dart';
import 'package:debrify/features/debrid_downloads/presentation/legacy_debrid/debrid_modern_file_card.dart';
import 'package:debrify/features/debrid_downloads/presentation/legacy_debrid/debrid_dormant_series_browser.dart';
import 'package:debrify/features/debrid_downloads/presentation/legacy_debrid/debrid_dormant_seasons_list.dart';
import 'package:debrify/features/debrid_downloads/presentation/legacy_debrid/debrid_sections.dart';
import 'package:debrify/features/debrid_downloads/models/debrid_downloads_view.dart';
import 'package:debrify/features/debrid_downloads/models/folder_view_mode.dart';
import 'package:debrify/features/debrid_downloads/models/rd_search_result.dart';
import 'package:debrify/features/debrid_downloads/application/debrid_folder_policy.dart';
import 'package:debrify/features/debrid_downloads/application/debrid_input_policy.dart';
import 'package:debrify/features/debrid_downloads/application/debrid_error_policy.dart';

import 'package:debrify/services/storage/real_debrid_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/rd_torrent.dart';
import '../models/rd_file_node.dart';
import '../models/debrid_download.dart';
import '../services/analytics_service.dart';
import '../theme/app_theme_scope.dart';
import '../services/series_source_service.dart';
import '../utils/formatters.dart';
import '../utils/file_utils.dart';
import '../utils/rd_folder_tree_builder.dart';
import '../services/main_page_bridge.dart';
import '../widgets/cloud/cloud_file_row.dart';
import '../widgets/cloud/cloud_row_skeleton.dart';
import '../widgets/cloud/cloud_segmented_tabs.dart';
import '../widgets/cloud/cloud_theme.dart';
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
    toggleSearch: () => sections.folderSearch.toggleSearch(),
    navigationState: _nav,
    navigateUp: () => sections.folderNavigation.navigateUp(),
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
    submitTorrentSearch: () => sections.torrentSearch.submitTorrentSearch(),
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
    sections.folderNavigation = DebridFolderNavigation((
    catalogState: _catalog,
    exitSelectionMode: () => sections.selectionActions.exitSelectionMode(),
    focusState: _focus,
    resetListScroll: () => sections.catalogLoading.resetListScroll(),
    setState: setState,
    navigationState: _nav,
    mounted: () => mounted,
    context: () => context,
    copyToClipboard: (String text) => sections.feedback.copyToClipboard(text),
    showError: (String message) => sections.feedback.showError(message),
    viewState: _view,
    focusFirstItemOrFallback: () => sections.focusActions.focusFirstItemOrFallback(),
    getCurrentViewMode: () => sections.viewModes.getCurrentViewMode(),
    ));
    sections.viewModes = DebridViewModes((
    navigationState: _nav,
    viewState: _view,
    setState: setState,
    context: () => context,
    ));
    sections.folderSearch = DebridFolderSearch((
    setState: setState,
    folderSearchState: _folderSearch,
    focusState: _focus,
    navigationState: _nav,
    ));
    sections.torrentSearch = DebridTorrentSearch((
    setState: setState,
    torrentSearchState: _torrentSearch,
    selectSourceMode: () => widget.selectSourceMode,
    initialSearchQuery: () => widget.initialSearchQuery,
    focusState: _focus,
    context: () => context,
    mounted: () => mounted,
    catalogState: _catalog,
    ));
    sections.torrentDownloadAction = DebridTorrentDownloadAction((
    catalogState: _catalog,
    context: () => context,
    mounted: () => mounted,
    showError: (String message) => sections.feedback.showError(message),
    downloadSelectedRealDebridFiles: ({required List<Map<String, dynamic>> selectedFiles, required List<String> links, required String folderName}) => sections.fileDownloads.downloadSelectedRealDebridFiles(selectedFiles: selectedFiles, links: links, folderName: folderName),
    ));
    sections.torrentPlaylistActions = DebridTorrentPlaylistActions((
    catalogState: _catalog,
    mounted: () => mounted,
    context: () => context,
    showError: (String message) => sections.feedback.showError(message),
    torrentSearchState: _torrentSearch,
    showSuccess: (String message) => sections.feedback.showSuccess(message),
    ));
    sections.multifilePlayback = DebridMultifilePlayback((
    catalogState: _catalog,
    context: () => context,
    mounted: () => mounted,
    showError: (String message) => sections.feedback.showError(message),
    ));
    sections.magnetActions = DebridMagnetActions((
    context: () => context,
    addInputState: _addInput,
    showError: (String message) => sections.feedback.showError(message),
    mounted: () => mounted,
    setState: setState,
    catalogState: _catalog,
    fetchTorrents: (String apiKey, {bool reset = false}) => sections.catalogLoading.fetchTorrents(apiKey, reset: reset),
    ));
    sections.linkActions = DebridLinkActions((
    context: () => context,
    addInputState: _addInput,
    showError: (String message) => sections.feedback.showError(message),
    mounted: () => mounted,
    setState: setState,
    catalogState: _catalog,
    fetchDownloads: (String apiKey, {bool reset = false}) => sections.catalogLoading.fetchDownloads(apiKey, reset: reset),
    ));
    sections.filePlayback = DebridFilePlayback((
    catalogState: _catalog,
    navigationState: _nav,
    context: () => context,
    mounted: () => mounted,
    showError: (String message) => sections.feedback.showError(message),
    ));
    sections.fileDownloads = DebridFileDownloads((
    catalogState: _catalog,
    navigationState: _nav,
    showError: (String message) => sections.feedback.showError(message),
    context: () => context,
    mounted: () => mounted,
    showSuccess: (String message) => sections.feedback.showSuccess(message),
    ));
    sections.nodePlaylistLinks = DebridNodePlaylistLinks((
    navigationState: _nav,
    mounted: () => mounted,
    showSuccess: (String message) => sections.feedback.showSuccess(message),
    showError: (String message) => sections.feedback.showError(message),
    catalogState: _catalog,
    ));
    sections.dormantTorrentActions = DebridDormantTorrentActions((
    catalogState: _catalog,
    mounted: () => mounted,
    context: () => context,
    showError: (String message) => sections.feedback.showError(message),
    navigateIntoTorrent: (RDTorrent torrent) => sections.folderNavigation.navigateIntoTorrent(torrent),
    showSuccess: (String message) => sections.feedback.showSuccess(message),
    ));
    sections.dormantFileActions = DebridDormantFileActions((
    catalogState: _catalog,
    mounted: () => mounted,
    context: () => context,
    showError: (String message) => sections.feedback.showError(message),
    copyToClipboard: (String text) => sections.feedback.copyToClipboard(text),
    ));
    sections.modernFileCard = DebridModernFileCard();
    sections.dormantSeriesBrowser = DebridDormantSeriesBrowser((
    context: () => context,
    buildSeasonsList: ({required Map<int, List<Map<String, dynamic>>> seasonMap, required List<int> sortedSeasons, required Set<int> selectedFiles, required Set<int> added, required Map<int, bool> unrestrictingFiles, required bool showPlayButtons, required RDTorrent torrent, required StateSetter setLocal, required StateSetter setBrowserState, required  Function(int?) onSeasonChanged}) => sections.dormantSeasonsList.buildSeasonsList(seasonMap: seasonMap, sortedSeasons: sortedSeasons, selectedFiles: selectedFiles, added: added, unrestrictingFiles: unrestrictingFiles, showPlayButtons: showPlayButtons, torrent: torrent, setLocal: setLocal, setBrowserState: setBrowserState, onSeasonChanged: onSeasonChanged),
    buildEpisodesList: ({required List<Map<String, dynamic>> seasonFiles, required Set<int> selectedFiles, required Set<int> added, required Map<int, bool> unrestrictingFiles, required bool showPlayButtons, required RDTorrent torrent, required StateSetter setLocal}) => sections.dormantSeasonsList.buildEpisodesList(seasonFiles: seasonFiles, selectedFiles: selectedFiles, added: added, unrestrictingFiles: unrestrictingFiles, showPlayButtons: showPlayButtons, torrent: torrent, setLocal: setLocal),
    ));
    sections.dormantSeasonsList = DebridDormantSeasonsList((
    context: () => context,
    buildModernFileCard: ({required String fileName, required int fileSize, required bool isVideo, required bool isAdded, required bool isSelected, required bool isUnrestricting, required bool showPlayButtons, required VoidCallback onPlay, required VoidCallback onAddToPlaylist, required VoidCallback onDownload, required VoidCallback onCopy, required VoidCallback onSelect, required int index, required Color surface, String? episodeInfo}) => sections.modernFileCard.buildModernFileCard(fileName: fileName, fileSize: fileSize, isVideo: isVideo, isAdded: isAdded, isSelected: isSelected, isUnrestricting: isUnrestricting, showPlayButtons: showPlayButtons, onPlay: onPlay, onAddToPlaylist: onAddToPlaylist, onDownload: onDownload, onCopy: onCopy, onSelect: onSelect, index: index, surface: surface, episodeInfo: episodeInfo),
    playFileOnDemand: (RDTorrent torrent, int index, StateSetter setLocal, Map<int, bool> unrestrictingFiles) => sections.dormantFileActions.playFileOnDemand(torrent, index, setLocal, unrestrictingFiles),
    addFileToPlaylist: (RDTorrent torrent, int index, StateSetter setLocal) => sections.dormantFileActions.addFileToPlaylist(torrent, index, setLocal),
    downloadFileOnDemand: (RDTorrent torrent, int index, String fileName, StateSetter setLocal, Set<int> added, Map<int, bool> unrestrictingFiles) => sections.dormantFileActions.downloadFileOnDemand(torrent, index, fileName, setLocal, added, unrestrictingFiles),
    copyFileLinkOnDemand: (RDTorrent torrent, int index, StateSetter setLocal, Map<int, bool> unrestrictingFiles) => sections.dormantFileActions.copyFileLinkOnDemand(torrent, index, setLocal, unrestrictingFiles),
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
          await _sections.folderNavigation.navigateIntoTorrent(widget.initialTorrentForOptions!);
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

  // Downloads methods

  // Download action methods

  // --- Multi-select helpers ---

  // ========== Folder Navigation Methods ==========

  // ============ Search Methods ============

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
              onChanged: _sections.folderSearch.performSearch,
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
          onTap: () => _sections.filePlayback.playFile(node),
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
    final mode = _sections.viewModes.getCurrentViewMode();

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
            if (value != null) _sections.viewModes.setViewMode(value);
          },
        ),
      ),
    );
  }

  Widget _buildFolderBrowserScaffold() {
    // Back navigation is handled via MainPageBridge.handleBackNavigation
    final currentMode = _sections.viewModes.getCurrentViewMode();
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
        title: Text(_sections.folderNavigation.getCurrentFolderTitle()),
        actions: [
          if (showSearch)
            IconButton(
              focusNode: _focus.searchButtonFocusNode,
              icon: Icon(_folderSearch.isSearchActive ? Icons.close : Icons.search),
              onPressed: _sections.folderSearch.toggleSearch,
              tooltip: _folderSearch.isSearchActive ? 'Close search' : 'Search files',
            ),
          IconButton(
            focusNode: _focus.refreshButtonFocusNode,
            icon: const Icon(Icons.refresh),
            onPressed: _nav.currentTorrent != null
                ? () => _sections.folderNavigation.navigateIntoTorrent(_nav.currentTorrent!)
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
              _sections.filePlayback.playFolder(node);
            } else {
              _sections.filePlayback.playFile(node);
            }
          },
        ),
      CloudRowAction(
        icon: Icons.download_rounded,
        label: 'Download',
        showInStrip: true,
        onSelected: () {
          if (isFolder) {
            _sections.fileDownloads.downloadFolder(node);
          } else {
            _sections.fileDownloads.downloadFile(node);
          }
        },
      ),
      if (isFolder || isVideo)
        CloudRowAction(
          icon: Icons.playlist_add,
          label: 'Add to Playlist',
          onSelected: () {
            if (isFolder) {
              _sections.nodePlaylistLinks.addFolderToPlaylist(node);
            } else {
              _sections.nodePlaylistLinks.addNodeFileToPlaylist(node);
            }
          },
        ),
      if (!isFolder)
        CloudRowAction(
          icon: Icons.link,
          label: 'Copy Download Link',
          onSelected: () => _sections.nodePlaylistLinks.copyNodeDownloadLink(node),
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
          ? () => _sections.folderNavigation.navigateIntoFolder(node)
          : isVideo
          ? () => _sections.filePlayback.playFile(node)
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
                  onPressed: _sections.torrentSearch.toggleTorrentSearch,
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
                  onPressed: _sections.magnetActions.showAddMagnetDialog,
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
                  onPressed: _sections.linkActions.showAddLinkDialog,
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
              onSubmitted: (_) => _sections.torrentSearch.submitTorrentSearch(),
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

    final results = _sections.torrentSearch.filteredSearchTorrents;

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
        onSelected: () => _sections.multifilePlayback.handlePlayMultiFileTorrent(torrent),
      ),
      CloudRowAction(
        icon: Icons.download,
        label: 'Download',
        showInStrip: true,
        onSelected: () => _sections.torrentDownloadAction.handleDownloadTorrent(torrent),
      ),
      CloudRowAction(
        icon: Icons.playlist_add,
        label: 'Add to Playlist',
        onSelected: () => _sections.torrentPlaylistActions.handleAddTorrentToPlaylist(torrent),
      ),
      CloudRowAction(
        icon: Icons.live_tv_rounded,
        label: 'Add to Debrify TV',
        onSelected: () => _sections.torrentPlaylistActions.handleAddTorrentToDebrifyTv(torrent),
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
      onTap: () => _sections.folderNavigation.navigateIntoTorrent(torrent),
      actions: actions,
      selectionMode: _selection.isSelectionMode,
      selected: _selection.selectedTorrentIds.contains(torrent.id),
      onToggleSelected: () => _sections.selectionActions.toggleTorrentSelection(torrent.id),
      focusNode: index == 0 ? _focus.firstItemFocusNode : null,
      upFocusNode: upNode,
    );
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

  // Link input methods

  // New on-demand action handlers

  // ========== File/Folder Action Methods ==========

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
    'toggleTorrentSearch': s._sections.torrentSearch.toggleTorrentSearch,
    'queryMatchesInitialTitle': s._sections.torrentSearch.queryMatchesInitialTitle,
    'submitTorrentSearch': s._sections.torrentSearch.submitTorrentSearch,
    'completeTorrentSearchSubmitFocus': s._sections.torrentSearch.completeTorrentSearchSubmitFocus,
    'fetchAllTorrentsForSearch': s._sections.torrentSearch.fetchAllTorrentsForSearch,
    'filteredSearchTorrents': s._sections.torrentSearch.filteredSearchTorrents,
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
    'isBrowsePush': s._isBrowsePush,
    'handleDownloadTorrent': s._sections.torrentDownloadAction.handleDownloadTorrent,
    'handleAddTorrentToPlaylist': s._sections.torrentPlaylistActions.handleAddTorrentToPlaylist,
    'handleAddTorrentToDebrifyTv': s._sections.torrentPlaylistActions.handleAddTorrentToDebrifyTv,
    'handlePlayMultiFileTorrent': s._sections.multifilePlayback.handlePlayMultiFileTorrent,
    'showAddMagnetDialog': s._sections.magnetActions.showAddMagnetDialog,
    'autoPasteMagnetLink': s._sections.magnetActions.autoPasteMagnetLink,
    'isValidMagnetLink': isValidMagnetLink,
    'addMagnetWithDefaultSelection': s._sections.magnetActions.addMagnetWithDefaultSelection,
    'showAdvancedMagnetDialog': s._sections.magnetActions.showAdvancedMagnetDialog,
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
    'downloadSelectedRealDebridFiles': s._sections.fileDownloads.downloadSelectedRealDebridFiles,
    'addNodeFileToPlaylist': s._sections.nodePlaylistLinks.addNodeFileToPlaylist,
    'addFolderToPlaylist': s._sections.nodePlaylistLinks.addFolderToPlaylist,
    'formatDate': s._formatDate,
    'copyNodeDownloadLink': s._sections.nodePlaylistLinks.copyNodeDownloadLink,
    'rawMode': FolderViewMode.raw,
    'sortedMode': FolderViewMode.sortedAZ,
    'seriesMode': FolderViewMode.seriesArrange,
  };
}
