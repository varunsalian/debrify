import 'premiumize_folder_navigation.dart';
import 'premiumize_search_actions.dart';
import 'premiumize_sections.dart';
import 'premiumize_source_binding.dart';
import 'premiumize_view_modes.dart';

void wirePremiumizeNavigationSections(
  PremiumizeSections sections,
  PremiumizeScope scope,
  PremiumizeOwners owners,
) {
  sections.folderNavigationSlot = PremiumizeFolderNavigation((
    navigationState: owners.navigationState,
    exitSelectionMode: () => sections.selectionActions.exitSelectionMode(),
    focusState: owners.focusState,
    setState: scope.setState,
    catalogState: owners.catalogState,
    searchState: owners.searchState,
    loadFolder: () => sections.catalogLoading.loadFolder(),
  ));
  sections.viewModesSlot = PremiumizeViewModes((
    isAtRoot: () => sections.folderNavigation.isAtRoot,
    viewState: owners.viewState,
    navigationState: owners.navigationState,
    setState: scope.setState,
    catalogState: owners.catalogState,
  ));
  sections.searchActionsSlot = PremiumizeSearchActions((
    setState: scope.setState,
    searchState: owners.searchState,
    selectionState: owners.selectionState,
    mounted: scope.mounted,
    focusState: owners.focusState,
    isAtRoot: () => sections.folderNavigation.isAtRoot,
    catalogState: owners.catalogState,
    showSnackBar: (String message, {bool isError = true, Duration? duration}) =>
        sections.feedback.showSnackBar(
          message,
          isError: isError,
          duration: duration,
        ),
  ));
  sections.sourceBindingSlot = PremiumizeSourceBinding((
    catalogState: owners.catalogState,
    showLoadingDialog: (String message) =>
        sections.feedback.showLoadingDialog(message),
    dismissDialog: () => sections.feedback.dismissDialog(),
    mounted: scope.mounted,
    showSnackBar: (String message, {bool isError = true, Duration? duration}) =>
        sections.feedback.showSnackBar(
          message,
          isError: isError,
          duration: duration,
        ),
    onSourceSelected: scope.onSourceSelected,
    context: scope.context,
  ));
}
