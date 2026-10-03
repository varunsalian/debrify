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
import 'package:debrify/features/debrid_downloads/presentation/legacy_debrid/debrid_root_layout.dart';
import 'package:debrify/features/debrid_downloads/presentation/legacy_debrid/debrid_folder_layout.dart';
import 'package:debrify/features/debrid_downloads/presentation/legacy_debrid/debrid_folder_search_layout.dart';
import 'package:debrify/features/debrid_downloads/presentation/legacy_debrid/debrid_view_selector.dart';
import 'package:debrify/features/debrid_downloads/presentation/legacy_debrid/debrid_selection_bar.dart';
import 'package:debrify/features/debrid_downloads/presentation/legacy_debrid/debrid_node_row.dart';
import 'package:debrify/features/debrid_downloads/presentation/legacy_debrid/debrid_torrent_toolbar.dart';
import 'package:debrify/features/debrid_downloads/presentation/legacy_debrid/debrid_download_toolbar.dart';
import 'package:debrify/features/debrid_downloads/presentation/legacy_debrid/debrid_library_lists.dart';
import 'package:debrify/features/debrid_downloads/presentation/legacy_debrid/debrid_torrent_search_layout.dart';
import 'package:debrify/features/debrid_downloads/presentation/legacy_debrid/debrid_torrent_row.dart';
import 'package:debrify/features/debrid_downloads/presentation/legacy_debrid/debrid_download_row.dart';
import 'package:debrify/features/debrid_downloads/presentation/legacy_debrid/debrid_sections.dart';
import 'package:debrify/features/debrid_downloads/models/folder_view_mode.dart';
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
    sections.rootLayout = DebridRootLayout((
    navigationState: _nav,
    buildFolderBrowserScaffold: () => sections.folderLayout.buildFolderBrowserScaffold(),
    catalogState: _catalog,
    buildTorrentContent: () => sections.libraryLists.buildTorrentContent(),
    buildDownloadContent: () => sections.libraryLists.buildDownloadContent(),
    focusState: _focus,
    isPushedRoute: () => widget.isPushedRoute,
    selectSourceMode: () => widget.selectSourceMode,
    initialTorrentForOptions: () => widget.initialTorrentForOptions,
    ));
    sections.folderLayout = DebridFolderLayout((
    getCurrentViewMode: () => sections.viewModes.getCurrentViewMode(),
    focusState: _focus,
    handleBackNavigation: () => sections.backNavigation.handleBackNavigation(),
    getCurrentFolderTitle: () => sections.folderNavigation.getCurrentFolderTitle(),
    folderSearchState: _folderSearch,
    toggleSearch: () => sections.folderSearch.toggleSearch(),
    navigationState: _nav,
    navigateIntoTorrent: (RDTorrent torrent) => sections.folderNavigation.navigateIntoTorrent(torrent),
    buildViewModeDropdown: () => sections.viewSelector.buildViewModeDropdown(),
    buildSearchBar: () => sections.folderSearchLayout.buildSearchBar(),
    buildSearchResults: () => sections.folderSearchLayout.buildSearchResults(),
    buildNodeCard: (RDFileNode node, int index) => sections.nodeRow.buildNodeCard(node, index),
    ));
    sections.folderSearchLayout = DebridFolderSearchLayout((
    context: () => context,
    folderSearchState: _folderSearch,
    focusState: _focus,
    performSearch: (String query) => sections.folderSearch.performSearch(query),
    setState: setState,
    playFile: (RDFileNode file) => sections.filePlayback.playFile(file),
    ));
    sections.viewSelector = DebridViewSelector((
    context: () => context,
    getCurrentViewMode: () => sections.viewModes.getCurrentViewMode(),
    focusState: _focus,
    setViewMode: (FolderViewMode mode) => sections.viewModes.setViewMode(mode),
    catalogState: _catalog,
    exitSelectionMode: () => sections.selectionActions.exitSelectionMode(),
    resetListScroll: () => sections.catalogLoading.resetListScroll(),
    setState: setState,
    ));
    sections.selectionBar = DebridSelectionBar((
    context: () => context,
    activeSelectedIds: () => sections.selectionActions.activeSelectedIds,
    toggleSelectAll: () => sections.selectionActions.toggleSelectAll(),
    isAllSelected: () => sections.selectionActions.isAllSelected,
    focusState: _focus,
    handleDeleteSelected: () => sections.selectionActions.handleDeleteSelected(),
    ));
    sections.nodeRow = DebridNodeRow((
    playFolder: (RDFileNode folder) => sections.filePlayback.playFolder(folder),
    playFile: (RDFileNode file) => sections.filePlayback.playFile(file),
    downloadFolder: (RDFileNode folder) => sections.fileDownloads.downloadFolder(folder),
    downloadFile: (RDFileNode file) => sections.fileDownloads.downloadFile(file),
    addFolderToPlaylist: (RDFileNode folder) => sections.nodePlaylistLinks.addFolderToPlaylist(folder),
    addNodeFileToPlaylist: (RDFileNode file) => sections.nodePlaylistLinks.addNodeFileToPlaylist(file),
    copyNodeDownloadLink: (RDFileNode node) => sections.nodePlaylistLinks.copyNodeDownloadLink(node),
    navigateIntoFolder: (RDFileNode folder) => sections.folderNavigation.navigateIntoFolder(folder),
    focusState: _focus,
    ));
    sections.torrentToolbar = DebridTorrentToolbar((
    isPushedRoute: () => widget.isPushedRoute,
    selectSourceMode: () => widget.selectSourceMode,
    initialTorrentForOptions: () => widget.initialTorrentForOptions,
    context: () => context,
    torrentSearchState: _torrentSearch,
    toggleTorrentSearch: () => sections.torrentSearch.toggleTorrentSearch(),
    catalogState: _catalog,
    selectionState: _selection,
    toggleSelectionMode: () => sections.selectionActions.toggleSelectionMode(),
    handleDeleteAllTorrents: () => sections.deleteAllActions.handleDeleteAllTorrents(),
    showAddMagnetDialog: () => sections.magnetActions.showAddMagnetDialog(),
    ));
    sections.downloadToolbar = DebridDownloadToolbar((
    context: () => context,
    isBrowsePush: () => sections.torrentToolbar.isBrowsePush,
    downloadState: _downloadState,
    selectionState: _selection,
    toggleSelectionMode: () => sections.selectionActions.toggleSelectionMode(),
    handleDeleteAllDownloads: () => sections.deleteAllActions.handleDeleteAllDownloads(),
    showAddLinkDialog: () => sections.linkActions.showAddLinkDialog(),
    ));
    sections.libraryLists = DebridLibraryLists((
    catalogState: _catalog,
    fetchTorrents: (String apiKey, {bool reset = false}) => sections.catalogLoading.fetchTorrents(apiKey, reset: reset),
    focusState: _focus,
    buildTorrentCard: (RDTorrent torrent, int index) => sections.torrentRow.buildTorrentCard(torrent, index),
    buildTorrentToolbar: () => sections.torrentToolbar.buildTorrentToolbar(),
    buildViewSelectorBar: () => sections.viewSelector.buildViewSelectorBar(),
    torrentSearchState: _torrentSearch,
    buildTorrentSearchBar: () => sections.torrentSearchLayout.buildTorrentSearchBar(),
    selectionState: _selection,
    buildSelectionBar: () => sections.selectionBar.buildSelectionBar(),
    navigationState: _nav,
    buildFolderLoadingView: () => sections.folderLayout.buildFolderLoadingView(),
    buildTorrentSearchResults: () => sections.torrentSearchLayout.buildTorrentSearchResults(),
    selectSourceMode: () => widget.selectSourceMode,
    downloadState: _downloadState,
    fetchDownloads: (String apiKey, {bool reset = false}) => sections.catalogLoading.fetchDownloads(apiKey, reset: reset),
    buildDownloadCard: (DebridDownload download, int index) => sections.downloadRow.buildDownloadCard(download, index),
    buildDownloadToolbar: () => sections.downloadToolbar.buildDownloadToolbar(),
    ));
    sections.torrentSearchLayout = DebridTorrentSearchLayout((
    context: () => context,
    torrentSearchState: _torrentSearch,
    focusState: _focus,
    submitTorrentSearch: () => sections.torrentSearch.submitTorrentSearch(),
    setState: setState,
    filteredSearchTorrents: () => sections.torrentSearch.filteredSearchTorrents,
    buildTorrentCard: (RDTorrent torrent, int index) => sections.torrentRow.buildTorrentCard(torrent, index),
    ));
    sections.torrentRow = DebridTorrentRow((
    selectionState: _selection,
    focusState: _focus,
    torrentSearchState: _torrentSearch,
    context: () => context,
    handlePlayMultiFileTorrent: (RDTorrent torrent) => sections.multifilePlayback.handlePlayMultiFileTorrent(torrent),
    handleDownloadTorrent: (RDTorrent torrent) => sections.torrentDownloadAction.handleDownloadTorrent(torrent),
    handleAddTorrentToPlaylist: (RDTorrent torrent) => sections.torrentPlaylistActions.handleAddTorrentToPlaylist(torrent),
    handleAddTorrentToDebrifyTv: (RDTorrent torrent) => sections.torrentPlaylistActions.handleAddTorrentToDebrifyTv(torrent),
    handleDeleteTorrent: (RDTorrent torrent) => sections.singleDeleteActions.handleDeleteTorrent(torrent),
    navigateIntoTorrent: (RDTorrent torrent) => sections.folderNavigation.navigateIntoTorrent(torrent),
    toggleTorrentSelection: (String id) => sections.selectionActions.toggleTorrentSelection(id),
    selectSourceMode: () => widget.selectSourceMode,
    onSourceSelected: () => widget.onSourceSelected,
    ));
    sections.downloadRow = DebridDownloadRow((
    context: () => context,
    focusState: _focus,
    handlePlayDownload: (DebridDownload download) => sections.downloadRowActions.handlePlayDownload(download),
    handleQueueDownload: (DebridDownload download) => sections.downloadRowActions.handleQueueDownload(download),
    handleDownloadAction: (DebridDownload download) => sections.downloadRowActions.handleDownloadAction(download),
    handleDeleteDownload: (DebridDownload download) => sections.singleDeleteActions.handleDeleteDownload(download),
    selectionState: _selection,
    toggleDownloadSelection: (String id) => sections.selectionActions.toggleDownloadSelection(id),
    selectSourceMode: () => widget.selectSourceMode,
    onSourceSelected: () => widget.onSourceSelected,
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

    @override
  Widget build(BuildContext context) => _sections.rootLayout.build(context);

  // Focus nodes for torrent search DPAD navigation

  // Link input methods

  // New on-demand action handlers

  // ========== File/Folder Action Methods ==========

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
    'isBrowsePush': s._sections.torrentToolbar.isBrowsePush,
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
    'formatDate': s._sections.torrentRow.formatDate,
    'copyNodeDownloadLink': s._sections.nodePlaylistLinks.copyNodeDownloadLink,
    'rawMode': FolderViewMode.raw,
    'sortedMode': FolderViewMode.sortedAZ,
    'seriesMode': FolderViewMode.seriesArrange,
  };
}
