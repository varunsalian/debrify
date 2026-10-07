import 'package:debrify/models/premiumize_folder_item.dart';

import '../../models/folder_view_mode.dart';
import 'premiumize_back_navigation.dart';
import 'premiumize_catalog_loading.dart';
import 'premiumize_delete_actions.dart';
import 'premiumize_feedback.dart';
import 'premiumize_focus_actions.dart';
import 'premiumize_sections.dart';
import 'premiumize_selection_actions.dart';
import 'premiumize_transfer_actions.dart';

void wirePremiumizeDataSections(
  PremiumizeSections sections,
  PremiumizeScope scope,
  PremiumizeOwners owners,
) {
  sections.selectionActionsSlot = PremiumizeSelectionActions((
    selectionState: owners.selectionState,
    catalogState: owners.catalogState,
    setState: scope.setState,
  ));
  sections.catalogLoadingSlot = PremiumizeCatalogLoading((
    mounted: scope.mounted,
    setState: scope.setState,
    catalogState: owners.catalogState,
    initialFolderId: scope.initialFolderId,
    initialFolderName: scope.initialFolderName,
    navigationState: owners.navigationState,
    initialSearchQuery: scope.initialSearchQuery,
    searchState: owners.searchState,
    performSearch: (String query) =>
        sections.searchActions.performSearch(query),
    getCurrentViewMode: () => sections.viewModes.getCurrentViewMode(),
    applyViewMode:
        (PremiumizeFolderViewMode mode, List<PremiumizeFolderItem> items) =>
            sections.viewModes.applyViewMode(mode, items),
    focusFirstItemOrFallback: () =>
        sections.focusActions.focusFirstItemOrFallback(),
    exitSelectionMode: () => sections.selectionActions.exitSelectionMode(),
    viewState: owners.viewState,
    focusState: owners.focusState,
  ));
  sections.backNavigationSlot = PremiumizeBackNavigation((
    selectionState: owners.selectionState,
    exitSelectionMode: () => sections.selectionActions.exitSelectionMode(),
    searchState: owners.searchState,
    toggleSearch: () => sections.searchActions.toggleSearch(),
    navigationState: owners.navigationState,
    navigateUp: () => sections.folderNavigation.navigateUp(),
    isPushedRoute: scope.isPushedRoute,
    context: scope.context,
  ));
  sections.deleteActionsSlot = PremiumizeDeleteActions((
    context: scope.context,
    selectionState: owners.selectionState,
    catalogState: owners.catalogState,
    showSnackBar: (String message, {bool isError = true, Duration? duration}) =>
        sections.feedback.showSnackBar(
          message,
          isError: isError,
          duration: duration,
        ),
    mounted: scope.mounted,
    setState: scope.setState,
    searchState: owners.searchState,
  ));
  sections.transferActionsSlot = PremiumizeTransferActions((
    catalogState: owners.catalogState,
    context: scope.context,
    mounted: scope.mounted,
    setState: scope.setState,
    showSnackBar: (String message, {bool isError = true, Duration? duration}) =>
        sections.feedback.showSnackBar(
          message,
          isError: isError,
          duration: duration,
        ),
    loadTransfers: () => sections.catalogLoading.loadTransfers(),
  ));
  sections.feedbackSlot = PremiumizeFeedback((
    mounted: scope.mounted,
    context: scope.context,
  ));
  sections.focusActionsSlot = PremiumizeFocusActions((
    focusState: owners.focusState,
    mounted: scope.mounted,
    catalogState: owners.catalogState,
  ));
}
