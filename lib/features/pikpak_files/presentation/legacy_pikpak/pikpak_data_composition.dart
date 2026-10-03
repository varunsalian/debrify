import 'package:debrify/features/pikpak_files/models/folder_view_mode.dart';

import 'pikpak_back_navigation.dart';
import 'pikpak_catalog_loading.dart';
import 'pikpak_delete_actions.dart';
import 'pikpak_feedback.dart';
import 'pikpak_focus_actions.dart';
import 'pikpak_sections.dart';
import 'pikpak_selection_actions.dart';

void wirePikpakDataSections(
  PikpakSections sections,
  PikpakScope scope,
  PikpakOwners owners,
) {
  sections.focusActionsSlot = PikpakFocusActions((
    focusState: owners.focusState,
    mounted: scope.mounted,
    catalogState: owners.catalogState,
  ));
  sections.backNavigationSlot = PikpakBackNavigation((
    selectionState: owners.selectionState,
    exitSelectionMode: () => sections.selectionActions.exitSelectionMode(),
    searchState: owners.searchState,
    toggleSearch: () => sections.searchActions.toggleSearch(),
    viewState: owners.viewState,
    navigationState: owners.navigationState,
    navigateUpWithVirtual: () =>
        sections.folderNavigation.navigateUpWithVirtual(),
    isPushedRoute: scope.isPushedRoute,
    context: scope.context,
  ));
  sections.catalogLoadingSlot = PikpakCatalogLoading((
    mounted: scope.mounted,
    setState: scope.setState,
    catalogState: owners.catalogState,
    navigationState: owners.navigationState,
    initialFolderId: scope.initialFolderId,
    initialFolderName: scope.initialFolderName,
    showSnackBar: (String message, {bool isError = true, Duration? duration}) =>
        sections.feedback.showSnackBar(
          message,
          isError: isError,
          duration: duration,
        ),
    filterFiles: (List<Map<String, dynamic>> files) =>
        sections.folderNavigation.filterFiles(files),
    getCurrentViewMode: () => sections.viewModes.getCurrentViewMode(),
    applyViewMode: (FolderViewMode mode, List<Map<String, dynamic>> items) =>
        sections.viewModes.applyViewMode(mode, items),
    focusFirstItemOrFallback: () =>
        sections.focusActions.focusFirstItemOrFallback(),
    focusState: owners.focusState,
  ));
  sections.deleteActionsSlot = PikpakDeleteActions((
    showSnackBar: (String message, {bool isError = true, Duration? duration}) =>
        sections.feedback.showSnackBar(
          message,
          isError: isError,
          duration: duration,
        ),
    context: scope.context,
    mounted: scope.mounted,
    setState: scope.setState,
    catalogState: owners.catalogState,
    selectionState: owners.selectionState,
    exitSelectionMode: () => sections.selectionActions.exitSelectionMode(),
  ));
  sections.selectionActionsSlot = PikpakSelectionActions((
    catalogState: owners.catalogState,
    selectionState: owners.selectionState,
    setState: scope.setState,
  ));
  sections.feedbackSlot = PikpakFeedback((
    exitSelectionMode: () => sections.selectionActions.exitSelectionMode(),
    navigationState: owners.navigationState,
    viewState: owners.viewState,
    setState: scope.setState,
    loadFiles: () => sections.catalogLoading.loadFiles(),
    mounted: scope.mounted,
    context: scope.context,
  ));
}
