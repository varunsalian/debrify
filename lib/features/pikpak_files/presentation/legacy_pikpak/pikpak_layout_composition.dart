import 'package:debrify/features/pikpak_files/models/folder_view_mode.dart';

import 'pikpak_file_list.dart';
import 'pikpak_root_layout.dart';
import 'pikpak_search_layout.dart';
import 'pikpak_sections.dart';
import 'pikpak_status_layout.dart';
import 'pikpak_toolbar_layout.dart';

void wirePikpakLayoutSections(
  PikpakSections sections,
  PikpakScope scope,
  PikpakOwners owners,
) {
  sections.rootLayoutSlot = PikpakRootLayout((
    isPushedRoute: scope.isPushedRoute,
    initialFolderId: scope.initialFolderId,
    navigationState: owners.navigationState,
    catalogState: owners.catalogState,
    buildNotEnabled: () => sections.statusLayout.buildNotEnabled(),
    buildError: () => sections.statusLayout.buildError(),
    viewState: owners.viewState,
    getCurrentViewMode: () => sections.viewModes.getCurrentViewMode(),
    focusState: owners.focusState,
    handleBackNavigation: () => sections.backNavigation.handleBackNavigation(),
    selectSourceMode: scope.selectSourceMode,
    selectionState: owners.selectionState,
    toggleSelectionMode: () => sections.selectionActions.toggleSelectionMode(),
    searchState: owners.searchState,
    toggleSearch: () => sections.searchActions.toggleSearch(),
    showAddLinkDialog: () => sections.linkActions.showAddLinkDialog(),
    refreshFiles: () => sections.feedback.refreshFiles(),
    buildSelectionBar: () => sections.toolbarLayout.buildSelectionBar(),
    buildViewModeDropdown: () => sections.toolbarLayout.buildViewModeDropdown(),
    buildSearchBar: () => sections.searchLayout.buildSearchBar(),
    buildSearchResults: () => sections.searchLayout.buildSearchResults(),
    buildEmpty: () => sections.statusLayout.buildEmpty(),
    buildFileList: () => sections.fileList.buildFileList(),
  ));
  sections.statusLayoutSlot = PikpakStatusLayout((
    context: scope.context,
    focusState: owners.focusState,
    showSnackBar: (String message, {bool isError = true, Duration? duration}) =>
        sections.feedback.showSnackBar(
          message,
          isError: isError,
          duration: duration,
        ),
    catalogState: owners.catalogState,
    refreshFiles: () => sections.feedback.refreshFiles(),
    navigationState: owners.navigationState,
  ));
  sections.fileListSlot = PikpakFileList((
    catalogState: owners.catalogState,
    focusState: owners.focusState,
    selectSourceMode: scope.selectSourceMode,
    selectBoundSource: (Map<String, dynamic> file) =>
        sections.sourceBinding.selectBoundSource(file),
    navigateIntoFolder: (String folderId, String folderName) =>
        sections.folderNavigation.navigateIntoFolder(folderId, folderName),
    playFolder: (Map<String, dynamic> folder) =>
        sections.folderPlayback.playFolder(folder),
    playFile: (Map<String, dynamic> fileData) =>
        sections.filePlayback.playFile(fileData),
    downloadFolder: (Map<String, dynamic> folder) =>
        sections.folderDownload.downloadFolder(folder),
    downloadFile: (Map<String, dynamic> file) =>
        sections.fileDownload.downloadFile(file),
    handleAddToPlaylist: (Map<String, dynamic> file) =>
        sections.playlistActions.handleAddToPlaylist(file),
    showDeleteDialog: (Map<String, dynamic> file) =>
        sections.deleteActions.showDeleteDialog(file),
    selectionState: owners.selectionState,
    navigateIntoVirtualFolder: (Map<String, dynamic> virtualFolder) =>
        sections.folderNavigation.navigateIntoVirtualFolder(virtualFolder),
    toggleFileSelection: (String id) =>
        sections.selectionActions.toggleFileSelection(id),
  ));
  sections.toolbarLayoutSlot = PikpakToolbarLayout((
    context: scope.context,
    getCurrentViewMode: () => sections.viewModes.getCurrentViewMode(),
    focusState: owners.focusState,
    setViewMode: (FolderViewMode mode) => sections.viewModes.setViewMode(mode),
    selectionState: owners.selectionState,
    toggleSelectAll: () => sections.selectionActions.toggleSelectAll(),
    isAllSelected: () => sections.selectionActions.isAllSelected,
    handleDeleteSelected: () => sections.deleteActions.handleDeleteSelected(),
  ));
  sections.searchLayoutSlot = PikpakSearchLayout((
    context: scope.context,
    searchState: owners.searchState,
    performSearch: (String query) =>
        sections.searchActions.performSearch(query),
    setState: scope.setState,
    selectSourceMode: scope.selectSourceMode,
    selectBoundSource: (Map<String, dynamic> file) =>
        sections.sourceBinding.selectBoundSource(file),
    playFile: (Map<String, dynamic> fileData) =>
        sections.filePlayback.playFile(fileData),
  ));
}
