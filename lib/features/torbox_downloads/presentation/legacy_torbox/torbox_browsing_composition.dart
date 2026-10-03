import 'package:debrify/features/torbox_downloads/presentation/legacy_torbox/torbox_file_row.dart';
import 'package:debrify/features/torbox_downloads/presentation/legacy_torbox/torbox_folder_navigation.dart';
import 'package:debrify/features/torbox_downloads/presentation/legacy_torbox/torbox_folder_search.dart';
import 'package:debrify/features/torbox_downloads/presentation/legacy_torbox/torbox_library_lists.dart';
import 'package:debrify/features/torbox_downloads/presentation/legacy_torbox/torbox_root_layout.dart';
import 'package:debrify/features/torbox_downloads/presentation/legacy_torbox/torbox_sections.dart';
import 'package:debrify/features/torbox_downloads/presentation/legacy_torbox/torbox_selection_bar.dart';
import 'package:debrify/features/torbox_downloads/presentation/legacy_torbox/torbox_toolbar.dart';
import 'package:debrify/features/torbox_downloads/presentation/legacy_torbox/torbox_torrent_row.dart';
import 'package:debrify/features/torbox_downloads/presentation/legacy_torbox/torbox_torrent_search.dart';
import 'package:debrify/features/torbox_downloads/presentation/legacy_torbox/torbox_torrent_search_layout.dart';
import 'package:debrify/features/torbox_downloads/presentation/legacy_torbox/torbox_view_modes.dart';
import 'package:debrify/features/torbox_downloads/presentation/legacy_torbox/torbox_view_selector.dart';
import 'package:debrify/features/torbox_downloads/presentation/legacy_torbox/torbox_web_row.dart';
import 'package:debrify/models/rd_file_node.dart';
import 'package:debrify/models/torbox_torrent.dart';
import 'package:debrify/models/torbox_web_download.dart';

import 'torbox_composition_bindings.dart';

void wireTorboxBrowsing(
  TorboxSections sections,
  TorboxViewBindings view,
  TorboxCompositionStates states,
) {
  sections.folderNavigation = TorboxFolderNavigation((
    exitSelectionMode: () => sections.selectionActions.exitSelectionMode(),
    focusState: states.focusState,
    resetListScroll: () => sections.catalogLoading.resetListScroll(),
    viewState: states.viewState,
    setState: view.setState,
    navigationState: states.navigationState,
    focusFirstItemOrFallback: () =>
        sections.focusActions.focusFirstItemOrFallback(),
    getCurrentViewMode: () => sections.viewModes.getCurrentViewMode(),
  ));
  sections.viewModes = TorboxViewModes((
    navigationState: states.navigationState,
    viewState: states.viewState,
    context: view.context,
    setState: view.setState,
    focusState: states.focusState,
  ));
  sections.torrentSearch = TorboxTorrentSearch((
    setState: view.setState,
    torrentSearchState: states.torrentSearchState,
    focusState: states.focusState,
    selectSourceMode: view.selectSourceMode,
    initialSearchQuery: view.initialSearchQuery,
    context: view.context,
    mounted: view.mounted,
    catalogState: states.catalogState,
  ));
  sections.folderSearch = TorboxFolderSearch((
    setState: view.setState,
    folderSearchState: states.folderSearchState,
    focusState: states.focusState,
    navigationState: states.navigationState,
    context: view.context,
    playVideoFile: (RDFileNode fileNode) =>
        sections.fileActions.playVideoFile(fileNode),
  ));
  sections.rootLayout = TorboxRootLayout((
    isAtRoot: () => sections.folderNavigation.isAtRoot,
    catalogState: states.catalogState,
    webState: states.webState,
    viewState: states.viewState,
    navigationState: states.navigationState,
    getCurrentViewMode: () => sections.viewModes.getCurrentViewMode(),
    focusState: states.focusState,
    handleBackNavigation: () => sections.backNavigation.handleBackNavigation(),
    currentFolderName: () => sections.folderNavigation.currentFolderName,
    folderSearchState: states.folderSearchState,
    toggleSearch: () => sections.folderSearch.toggleSearch(),
    buildToolbar: () => sections.toolbar.buildToolbar(),
    buildViewSelectorBar: () => sections.viewSelector.buildViewSelectorBar(),
    torrentSearchState: states.torrentSearchState,
    buildTorrentSearchBar: () =>
        sections.torrentSearchLayout.buildTorrentSearchBar(),
    selectionState: states.selectionState,
    buildSelectionBar: () => sections.selectionBar.buildSelectionBar(),
    buildViewModeDropdown: () => sections.viewModes.buildViewModeDropdown(),
    buildSearchBar: () => sections.folderSearch.buildSearchBar(),
    buildTorrentSearchResults: () =>
        sections.torrentSearchLayout.buildTorrentSearchResults(),
    buildSearchResults: () => sections.folderSearch.buildSearchResults(),
    refresh: () => sections.catalogLoading.refresh(),
    buildFilesFoldersList: () => sections.libraryLists.buildFilesFoldersList(),
    isPushedRoute: view.isPushedRoute,
    selectSourceMode: view.selectSourceMode,
    initialTorrentToOpen: view.initialTorrentToOpen,
  ));
  sections.libraryLists = TorboxLibraryLists((
    isAtRoot: () => sections.folderNavigation.isAtRoot,
    catalogState: states.catalogState,
    currentItems: () => sections.rootLayout.currentItems,
    context: view.context,
    openSettings: () => sections.magnetActions.openSettings(),
    focusState: states.focusState,
    buildTorrentFolderCard: (TorboxTorrent torrent, int index) =>
        sections.torrentRow.buildTorrentFolderCard(torrent, index),
    buildFileOrFolderCard: (RDFileNode node, int index) =>
        sections.fileRow.buildFileOrFolderCard(node, index),
    webState: states.webState,
    buildWebDownloadCard: (TorboxWebDownload webDownload, int index) =>
        sections.webRow.buildWebDownloadCard(webDownload, index),
  ));
  sections.webRow = TorboxWebRow((
    context: view.context,
    focusState: states.focusState,
    handlePlayWebDownload: (TorboxWebDownload webDownload) =>
        sections.webPlayback.handlePlayWebDownload(webDownload),
    showWebDownloadOptionsDialog: (TorboxWebDownload webDownload) =>
        sections.webOptions.showWebDownloadOptionsDialog(webDownload),
    navigateIntoWebDownload: (TorboxWebDownload webDownload) =>
        sections.folderNavigation.navigateIntoWebDownload(webDownload),
    copyWebDownloadLink: (TorboxWebDownload webDownload) =>
        sections.webLinkPlaylistActions.copyWebDownloadLink(webDownload),
    confirmDeleteWebDownload: (TorboxWebDownload webDownload) =>
        sections.webDeleteAction.confirmDeleteWebDownload(webDownload),
    selectionState: states.selectionState,
    toggleWebDownloadSelection: (int id) =>
        sections.selectionActions.toggleWebDownloadSelection(id),
    selectSourceMode: view.selectSourceMode,
    onSourceSelected: view.onSourceSelected,
  ));
  sections.torrentRow = TorboxTorrentRow((
    torrentSearchState: states.torrentSearchState,
    focusState: states.focusState,
    context: view.context,
    handlePlayTorrent: (TorboxTorrent torrent) =>
        sections.torrentPlayback.handlePlayTorrent(torrent),
    showDownloadOptionsDialog: (TorboxTorrent torrent) =>
        sections.downloadOptions.showDownloadOptionsDialog(torrent),
    navigateIntoTorrent: (TorboxTorrent torrent) =>
        sections.folderNavigation.navigateIntoTorrent(torrent),
    copyTorboxZipLink: (TorboxTorrent torrent) =>
        sections.torrentLinkActions.copyTorboxZipLink(torrent),
    handleAddToPlaylist: (TorboxTorrent torrent) =>
        sections.torrentPlaylistActions.handleAddToPlaylist(torrent),
    handleAddToDebrifyTv: (TorboxTorrent torrent) =>
        sections.torrentPlaylistActions.handleAddToDebrifyTv(torrent),
    confirmDeleteTorrent: (TorboxTorrent torrent) =>
        sections.torrentDeleteActions.confirmDeleteTorrent(torrent),
    selectionState: states.selectionState,
    toggleTorrentSelection: (int id) =>
        sections.selectionActions.toggleTorrentSelection(id),
    selectSourceMode: view.selectSourceMode,
    onSourceSelected: view.onSourceSelected,
  ));
  sections.fileRow = TorboxFileRow((
    playFolderVideos: (RDFileNode folderNode) =>
        sections.fileActions.playFolderVideos(folderNode),
    playVideoFile: (RDFileNode fileNode) =>
        sections.fileActions.playVideoFile(fileNode),
    downloadFileOrFolder: (RDFileNode node) =>
        sections.fileActions.downloadFileOrFolder(node),
    navigationState: states.navigationState,
    addFileOrFolderToPlaylist: (RDFileNode node) =>
        sections.filePlaylistLinks.addFileOrFolderToPlaylist(node),
    copyFileLink: (RDFileNode node) =>
        sections.filePlaylistLinks.copyFileLink(node),
    navigateIntoFolder: (RDFileNode folderNode) =>
        sections.folderNavigation.navigateIntoFolder(folderNode),
    focusState: states.focusState,
  ));
  sections.viewSelector = TorboxViewSelector((
    catalogState: states.catalogState,
    resetListScroll: () => sections.catalogLoading.resetListScroll(),
    setState: view.setState,
    torrentSearchState: states.torrentSearchState,
    selectionState: states.selectionState,
  ));
  sections.selectionBar = TorboxSelectionBar((
    context: view.context,
    activeSelectedIds: () => sections.selectionActions.activeSelectedIds,
    toggleSelectAll: () => sections.selectionActions.toggleSelectAll(),
    isAllSelected: () => sections.selectionActions.isAllSelected,
    focusState: states.focusState,
    handleDeleteSelected: () =>
        sections.selectionActions.handleDeleteSelected(),
  ));
  sections.torrentSearchLayout = TorboxTorrentSearchLayout((
    context: view.context,
    torrentSearchState: states.torrentSearchState,
    focusState: states.focusState,
    submitTorrentSearch: () => sections.torrentSearch.submitTorrentSearch(),
    setState: view.setState,
    filteredTorrentSearchResults: () =>
        sections.torrentSearch.filteredTorrentSearchResults,
    buildTorrentFolderCard: (TorboxTorrent torrent, int index) =>
        sections.torrentRow.buildTorrentFolderCard(torrent, index),
  ));
  sections.toolbar = TorboxToolbar((
    isPushedRoute: view.isPushedRoute,
    selectSourceMode: view.selectSourceMode,
    initialTorrentToOpen: view.initialTorrentToOpen,
    context: view.context,
    catalogState: states.catalogState,
    webState: states.webState,
    selectionState: states.selectionState,
    toggleSelectionMode: () => sections.selectionActions.toggleSelectionMode(),
    confirmDeleteAll: () => sections.torrentDeleteActions.confirmDeleteAll(),
    torrentSearchState: states.torrentSearchState,
    focusState: states.focusState,
    toggleTorrentSearch: () => sections.torrentSearch.toggleTorrentSearch(),
    showAddMagnetDialog: () => sections.magnetActions.showAddMagnetDialog(),
    showAddWebDownloadDialog: () =>
        sections.webCreateActions.showAddWebDownloadDialog(),
  ));
}
