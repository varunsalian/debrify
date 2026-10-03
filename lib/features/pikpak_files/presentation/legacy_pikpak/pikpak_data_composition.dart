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
  PikpakDeferred deferred,
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
    toggleSearch: deferred.toggleSearch,
    viewState: owners.viewState,
    navigationState: owners.navigationState,
    navigateUpWithVirtual: deferred.navigateUpWithVirtual,
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
    filterFiles: deferred.filterFiles,
    getCurrentViewMode: deferred.getCurrentViewMode,
    applyViewMode: deferred.applyViewMode,
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
