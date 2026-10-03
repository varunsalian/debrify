import 'package:debrify/features/debrid_downloads/models/folder_view_mode.dart';
import 'package:debrify/features/debrid_downloads/presentation/legacy_debrid/debrid_download_row.dart';
import 'package:debrify/features/debrid_downloads/presentation/legacy_debrid/debrid_download_toolbar.dart';
import 'package:debrify/features/debrid_downloads/presentation/legacy_debrid/debrid_folder_layout.dart';
import 'package:debrify/features/debrid_downloads/presentation/legacy_debrid/debrid_folder_search_layout.dart';
import 'package:debrify/features/debrid_downloads/presentation/legacy_debrid/debrid_library_lists.dart';
import 'package:debrify/features/debrid_downloads/presentation/legacy_debrid/debrid_node_row.dart';
import 'package:debrify/features/debrid_downloads/presentation/legacy_debrid/debrid_root_layout.dart';
import 'package:debrify/features/debrid_downloads/presentation/legacy_debrid/debrid_sections.dart';
import 'package:debrify/features/debrid_downloads/presentation/legacy_debrid/debrid_selection_bar.dart';
import 'package:debrify/features/debrid_downloads/presentation/legacy_debrid/debrid_torrent_row.dart';
import 'package:debrify/features/debrid_downloads/presentation/legacy_debrid/debrid_torrent_search_layout.dart';
import 'package:debrify/features/debrid_downloads/presentation/legacy_debrid/debrid_torrent_toolbar.dart';
import 'package:debrify/features/debrid_downloads/presentation/legacy_debrid/debrid_view_selector.dart';
import 'package:debrify/models/debrid_download.dart';
import 'package:debrify/models/rd_file_node.dart';
import 'package:debrify/models/rd_torrent.dart';

import 'debrid_composition_bindings.dart';

void wireDebridBrowsing(
  DebridSections sections,
  DebridViewBindings view,
  DebridCompositionStates states,
) {
  sections.rootLayout = DebridRootLayout((
    navigationState: states.navigationState,
    buildFolderBrowserScaffold: () =>
        sections.folderLayout.buildFolderBrowserScaffold(),
    catalogState: states.catalogState,
    buildTorrentContent: () => sections.libraryLists.buildTorrentContent(),
    buildDownloadContent: () => sections.libraryLists.buildDownloadContent(),
    focusState: states.focusState,
    isPushedRoute: view.isPushedRoute,
    selectSourceMode: view.selectSourceMode,
    initialTorrentForOptions: view.initialTorrentForOptions,
  ));
  sections.folderLayout = DebridFolderLayout((
    getCurrentViewMode: () => sections.viewModes.getCurrentViewMode(),
    focusState: states.focusState,
    handleBackNavigation: () => sections.backNavigation.handleBackNavigation(),
    getCurrentFolderTitle: () =>
        sections.folderNavigation.getCurrentFolderTitle(),
    folderSearchState: states.folderSearchState,
    toggleSearch: () => sections.folderSearch.toggleSearch(),
    navigationState: states.navigationState,
    navigateIntoTorrent: (RDTorrent torrent) =>
        sections.folderNavigation.navigateIntoTorrent(torrent),
    buildViewModeDropdown: () => sections.viewSelector.buildViewModeDropdown(),
    buildSearchBar: () => sections.folderSearchLayout.buildSearchBar(),
    buildSearchResults: () => sections.folderSearchLayout.buildSearchResults(),
    buildNodeCard: (RDFileNode node, int index) =>
        sections.nodeRow.buildNodeCard(node, index),
  ));
  sections.folderSearchLayout = DebridFolderSearchLayout((
    context: view.context,
    folderSearchState: states.folderSearchState,
    focusState: states.focusState,
    performSearch: (String query) => sections.folderSearch.performSearch(query),
    setState: view.setState,
    playFile: (RDFileNode file) => sections.filePlayback.playFile(file),
  ));
  sections.viewSelector = DebridViewSelector((
    context: view.context,
    getCurrentViewMode: () => sections.viewModes.getCurrentViewMode(),
    focusState: states.focusState,
    setViewMode: (FolderViewMode mode) => sections.viewModes.setViewMode(mode),
    catalogState: states.catalogState,
    exitSelectionMode: () => sections.selectionActions.exitSelectionMode(),
    resetListScroll: () => sections.catalogLoading.resetListScroll(),
    setState: view.setState,
  ));
  sections.selectionBar = DebridSelectionBar((
    context: view.context,
    activeSelectedIds: () => sections.selectionActions.activeSelectedIds,
    toggleSelectAll: () => sections.selectionActions.toggleSelectAll(),
    isAllSelected: () => sections.selectionActions.isAllSelected,
    focusState: states.focusState,
    handleDeleteSelected: () =>
        sections.selectionActions.handleDeleteSelected(),
  ));
  sections.nodeRow = DebridNodeRow((
    playFolder: (RDFileNode folder) => sections.filePlayback.playFolder(folder),
    playFile: (RDFileNode file) => sections.filePlayback.playFile(file),
    downloadFolder: (RDFileNode folder) =>
        sections.fileDownloads.downloadFolder(folder),
    downloadFile: (RDFileNode file) =>
        sections.fileDownloads.downloadFile(file),
    addFolderToPlaylist: (RDFileNode folder) =>
        sections.nodePlaylistLinks.addFolderToPlaylist(folder),
    addNodeFileToPlaylist: (RDFileNode file) =>
        sections.nodePlaylistLinks.addNodeFileToPlaylist(file),
    copyNodeDownloadLink: (RDFileNode node) =>
        sections.nodePlaylistLinks.copyNodeDownloadLink(node),
    navigateIntoFolder: (RDFileNode folder) =>
        sections.folderNavigation.navigateIntoFolder(folder),
    focusState: states.focusState,
  ));
  sections.torrentToolbar = DebridTorrentToolbar((
    isPushedRoute: view.isPushedRoute,
    selectSourceMode: view.selectSourceMode,
    initialTorrentForOptions: view.initialTorrentForOptions,
    context: view.context,
    torrentSearchState: states.torrentSearchState,
    toggleTorrentSearch: () => sections.torrentSearch.toggleTorrentSearch(),
    catalogState: states.catalogState,
    selectionState: states.selectionState,
    toggleSelectionMode: () => sections.selectionActions.toggleSelectionMode(),
    handleDeleteAllTorrents: () =>
        sections.deleteAllActions.handleDeleteAllTorrents(),
    showAddMagnetDialog: () => sections.magnetActions.showAddMagnetDialog(),
  ));
  sections.downloadToolbar = DebridDownloadToolbar((
    context: view.context,
    isBrowsePush: () => sections.torrentToolbar.isBrowsePush,
    downloadState: states.downloadState,
    selectionState: states.selectionState,
    toggleSelectionMode: () => sections.selectionActions.toggleSelectionMode(),
    handleDeleteAllDownloads: () =>
        sections.deleteAllActions.handleDeleteAllDownloads(),
    showAddLinkDialog: () => sections.linkActions.showAddLinkDialog(),
  ));
  sections.libraryLists = DebridLibraryLists((
    catalogState: states.catalogState,
    fetchTorrents: (String apiKey, {bool reset = false}) =>
        sections.catalogLoading.fetchTorrents(apiKey, reset: reset),
    focusState: states.focusState,
    buildTorrentCard: (RDTorrent torrent, int index) =>
        sections.torrentRow.buildTorrentCard(torrent, index),
    buildTorrentToolbar: () => sections.torrentToolbar.buildTorrentToolbar(),
    buildViewSelectorBar: () => sections.viewSelector.buildViewSelectorBar(),
    torrentSearchState: states.torrentSearchState,
    buildTorrentSearchBar: () =>
        sections.torrentSearchLayout.buildTorrentSearchBar(),
    selectionState: states.selectionState,
    buildSelectionBar: () => sections.selectionBar.buildSelectionBar(),
    navigationState: states.navigationState,
    buildFolderLoadingView: () =>
        sections.folderLayout.buildFolderLoadingView(),
    buildTorrentSearchResults: () =>
        sections.torrentSearchLayout.buildTorrentSearchResults(),
    selectSourceMode: view.selectSourceMode,
    downloadState: states.downloadState,
    fetchDownloads: (String apiKey, {bool reset = false}) =>
        sections.catalogLoading.fetchDownloads(apiKey, reset: reset),
    buildDownloadCard: (DebridDownload download, int index) =>
        sections.downloadRow.buildDownloadCard(download, index),
    buildDownloadToolbar: () => sections.downloadToolbar.buildDownloadToolbar(),
  ));
  sections.torrentSearchLayout = DebridTorrentSearchLayout((
    context: view.context,
    torrentSearchState: states.torrentSearchState,
    focusState: states.focusState,
    submitTorrentSearch: () => sections.torrentSearch.submitTorrentSearch(),
    setState: view.setState,
    filteredSearchTorrents: () => sections.torrentSearch.filteredSearchTorrents,
    buildTorrentCard: (RDTorrent torrent, int index) =>
        sections.torrentRow.buildTorrentCard(torrent, index),
  ));
  sections.torrentRow = DebridTorrentRow((
    selectionState: states.selectionState,
    focusState: states.focusState,
    torrentSearchState: states.torrentSearchState,
    context: view.context,
    handlePlayMultiFileTorrent: (RDTorrent torrent) =>
        sections.multifilePlayback.handlePlayMultiFileTorrent(torrent),
    handleDownloadTorrent: (RDTorrent torrent) =>
        sections.torrentDownloadAction.handleDownloadTorrent(torrent),
    handleAddTorrentToPlaylist: (RDTorrent torrent) =>
        sections.torrentPlaylistActions.handleAddTorrentToPlaylist(torrent),
    handleAddTorrentToDebrifyTv: (RDTorrent torrent) =>
        sections.torrentPlaylistActions.handleAddTorrentToDebrifyTv(torrent),
    handleDeleteTorrent: (RDTorrent torrent) =>
        sections.singleDeleteActions.handleDeleteTorrent(torrent),
    navigateIntoTorrent: (RDTorrent torrent) =>
        sections.folderNavigation.navigateIntoTorrent(torrent),
    toggleTorrentSelection: (String id) =>
        sections.selectionActions.toggleTorrentSelection(id),
    selectSourceMode: view.selectSourceMode,
    onSourceSelected: view.onSourceSelected,
  ));
  sections.downloadRow = DebridDownloadRow((
    context: view.context,
    focusState: states.focusState,
    handlePlayDownload: (DebridDownload download) =>
        sections.downloadRowActions.handlePlayDownload(download),
    handleQueueDownload: (DebridDownload download) =>
        sections.downloadRowActions.handleQueueDownload(download),
    handleDownloadAction: (DebridDownload download) =>
        sections.downloadRowActions.handleDownloadAction(download),
    handleDeleteDownload: (DebridDownload download) =>
        sections.singleDeleteActions.handleDeleteDownload(download),
    selectionState: states.selectionState,
    toggleDownloadSelection: (String id) =>
        sections.selectionActions.toggleDownloadSelection(id),
    selectSourceMode: view.selectSourceMode,
    onSourceSelected: view.onSourceSelected,
  ));
}
