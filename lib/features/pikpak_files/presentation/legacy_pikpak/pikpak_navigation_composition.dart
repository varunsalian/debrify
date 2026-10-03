import 'package:debrify/features/pikpak_files/models/folder_view_mode.dart';

import 'pikpak_folder_navigation.dart';
import 'pikpak_search_actions.dart';
import 'pikpak_sections.dart';
import 'pikpak_source_binding.dart';
import 'pikpak_view_modes.dart';

void wirePikpakNavigationSections(
  PikpakSections sections,
  PikpakScope scope,
  PikpakOwners owners,
) {
  sections.folderNavigationSlot = PikpakFolderNavigation((
    catalogState: owners.catalogState,
    exitSelectionMode: () => sections.selectionActions.exitSelectionMode(),
    focusState: owners.focusState,
    resetListScroll: () => sections.catalogLoading.resetListScroll(),
    setState: scope.setState,
    navigationState: owners.navigationState,
    loadFiles: () => sections.catalogLoading.loadFiles(),
    showSnackBar: (String message, {bool isError = true, Duration? duration}) =>
        sections.feedback.showSnackBar(
          message,
          isError: isError,
          duration: duration,
        ),
    viewState: owners.viewState,
    getCurrentViewMode: () => sections.viewModes.getCurrentViewMode(),
    setViewMode: (FolderViewMode mode) => sections.viewModes.setViewMode(mode),
    focusFirstItemOrFallback: () =>
        sections.focusActions.focusFirstItemOrFallback(),
  ));
  sections.viewModesSlot = PikpakViewModes((
    viewState: owners.viewState,
    navigationState: owners.navigationState,
    setState: scope.setState,
    catalogState: owners.catalogState,
    mounted: scope.mounted,
    context: scope.context,
  ));
  sections.searchActionsSlot = PikpakSearchActions((
    setState: scope.setState,
    searchState: owners.searchState,
    navigationState: owners.navigationState,
    viewState: owners.viewState,
    catalogState: owners.catalogState,
  ));
  sections.sourceBindingSlot = PikpakSourceBinding((
    showSnackBar: (String message, {bool isError = true, Duration? duration}) =>
        sections.feedback.showSnackBar(
          message,
          isError: isError,
          duration: duration,
        ),
    mounted: scope.mounted,
    context: scope.context,
    onSourceSelected: scope.onSourceSelected,
  ));
}
