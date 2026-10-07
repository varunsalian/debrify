import 'package:debrify/models/premiumize_folder_item.dart';
import 'package:debrify/models/premiumize_transfer.dart';

import '../../models/folder_view_mode.dart';
import '../../models/premiumize_view.dart';
import 'premiumize_file_list.dart';
import 'premiumize_root_layout.dart';
import 'premiumize_search_layout.dart';
import 'premiumize_sections.dart';
import 'premiumize_status_layout.dart';
import 'premiumize_toolbar_layout.dart';
import 'premiumize_transfer_list.dart';

void wirePremiumizeLayoutSections(
  PremiumizeSections sections,
  PremiumizeScope scope,
  PremiumizeOwners owners,
) {
  sections.rootLayoutSlot = PremiumizeRootLayout((
    isPushedRoute: scope.isPushedRoute,
    initialFolderId: scope.initialFolderId,
    isAtRoot: () => sections.folderNavigation.isAtRoot,
    catalogState: owners.catalogState,
    buildNotEnabled: () => sections.statusLayout.buildNotEnabled(),
    buildError: () => sections.statusLayout.buildError(),
    viewState: owners.viewState,
    navigationState: owners.navigationState,
    focusState: owners.focusState,
    handleBackNavigation: () => sections.backNavigation.handleBackNavigation(),
    selectSourceMode: scope.selectSourceMode,
    searchState: owners.searchState,
    selectionState: owners.selectionState,
    toggleSelectionMode: () => sections.selectionActions.toggleSelectionMode(),
    toggleSearch: () => sections.searchActions.toggleSearch(),
    showAddLinkDialog: () => sections.linkActions.showAddLinkDialog(),
    refresh: () => sections.catalogLoading.refresh(),
    buildViewSelector: () => sections.toolbarLayout.buildViewSelector(),
    buildSelectionBar: () => sections.toolbarLayout.buildSelectionBar(),
    buildViewModeDropdown: () => sections.toolbarLayout.buildViewModeDropdown(),
    buildSearchBar: () => sections.searchLayout.buildSearchBar(),
    buildSearchResults: () => sections.searchLayout.buildSearchResults(),
    buildTransfersList: () => sections.transferList.buildTransfersList(),
    buildEmpty: () => sections.statusLayout.buildEmpty(),
    buildFileList: () => sections.fileList.buildFileList(),
  ));
  sections.toolbarLayoutSlot = PremiumizeToolbarLayout((
    viewState: owners.viewState,
    switchView: (PremiumizeView view) =>
        sections.catalogLoading.switchView(view),
    context: scope.context,
    getCurrentViewMode: () => sections.viewModes.getCurrentViewMode(),
    focusState: owners.focusState,
    setViewMode: (PremiumizeFolderViewMode mode) =>
        sections.viewModes.setViewMode(mode),
    selectionState: owners.selectionState,
    toggleSelectAll: () => sections.selectionActions.toggleSelectAll(),
    isAllSelected: () => sections.selectionActions.isAllSelected,
    handleDeleteSelected: () => sections.deleteActions.handleDeleteSelected(),
  ));
  sections.searchLayoutSlot = PremiumizeSearchLayout((
    context: scope.context,
    searchState: owners.searchState,
    focusState: owners.focusState,
    isAtRoot: () => sections.folderNavigation.isAtRoot,
    performSearch: (String query) =>
        sections.searchActions.performSearch(query),
    setState: scope.setState,
    buildFileCard:
        (PremiumizeFolderItem item, int index, {bool autofocusFirst = true}) =>
            sections.fileList.buildFileCard(
              item,
              index,
              autofocusFirst: autofocusFirst,
            ),
  ));
  sections.fileListSlot = PremiumizeFileList((
    focusState: owners.focusState,
    catalogState: owners.catalogState,
    formatUnixDate: (int seconds) =>
        sections.dateFormat.formatUnixDate(seconds),
    selectSourceMode: scope.selectSourceMode,
    selectBoundSource: (PremiumizeFolderItem item) =>
        sections.sourceBinding.selectBoundSource(item),
    navigateIntoFolder: (PremiumizeFolderItem folder) =>
        sections.folderNavigation.navigateIntoFolder(folder),
    playFolder: (PremiumizeFolderItem folder) =>
        sections.folderPlayback.playFolder(folder),
    playFile: (PremiumizeFolderItem file) =>
        sections.filePlayback.playFile(file),
    downloadFolder: (PremiumizeFolderItem folder) =>
        sections.folderDownload.downloadFolder(folder),
    downloadFile: (PremiumizeFolderItem file) =>
        sections.fileDownload.downloadFile(file),
    addToPlaylist: (PremiumizeFolderItem item) =>
        sections.playlistActions.addToPlaylist(item),
    showDeleteDialog: (PremiumizeFolderItem item) =>
        sections.deleteActions.showDeleteDialog(item),
    selectionState: owners.selectionState,
    toggleSelection: (String id) =>
        sections.selectionActions.toggleSelection(id),
  ));
  sections.transferListSlot = PremiumizeTransferList((
    catalogState: owners.catalogState,
    context: scope.context,
    clearFinishedTransfers: () =>
        sections.transferActions.clearFinishedTransfers(),
    deleteTransfer: (PremiumizeTransfer transfer) =>
        sections.transferActions.deleteTransfer(transfer),
  ));
  sections.statusLayoutSlot = PremiumizeStatusLayout((
    isAtRoot: () => sections.folderNavigation.isAtRoot,
    context: scope.context,
    focusState: owners.focusState,
    showSnackBar: (String message, {bool isError = true, Duration? duration}) =>
        sections.feedback.showSnackBar(
          message,
          isError: isError,
          duration: duration,
        ),
    catalogState: owners.catalogState,
    refresh: () => sections.catalogLoading.refresh(),
  ));
}
