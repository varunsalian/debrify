import 'package:debrify/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_feedback.dart';
import 'package:debrify/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_feedback_state.dart';
import 'package:debrify/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_focus_state.dart';
import 'package:debrify/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_library_loading.dart';
import 'package:debrify/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_library_state.dart';
import 'package:debrify/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_navigation.dart';
import 'package:debrify/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_navigation_state.dart';
import 'package:debrify/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_scope.dart';
import 'package:debrify/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_search.dart';
import 'package:debrify/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_search_state.dart';
import 'package:debrify/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_selection.dart';
import 'package:debrify/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_selection_state.dart';
import 'package:debrify/models/alldebrid_magnet.dart';

typedef AllDebridOwners = ({
  AllDebridLibraryState libraryState,
  AllDebridNavigationState navigationState,
  AllDebridSearchState searchState,
  AllDebridFocusState focusState,
  AllDebridSelectionState selectionState,
  AllDebridFeedbackState feedbackState,
});

class AllDebridSections {
  AllDebridNavigation? navigationSlot;
  AllDebridNavigation get navigation => navigationSlot!;
  AllDebridLibraryLoading? libraryLoadingSlot;
  AllDebridLibraryLoading get libraryLoading => libraryLoadingSlot!;
  AllDebridSelection? selectionSlot;
  AllDebridSelection get selection => selectionSlot!;
  AllDebridSearch? searchSlot;
  AllDebridSearch get search => searchSlot!;
  AllDebridFeedback? feedbackSlot;
  AllDebridFeedback get feedback => feedbackSlot!;
}

AllDebridSections createAllDebridSections(
  AllDebridScope scope,
  AllDebridOwners owners,
) {
  final sections = AllDebridSections();
  sections.navigationSlot = AllDebridNavigation((
    navigationState: owners.navigationState,
    selectionState: owners.selectionState,
    searchState: owners.searchState,
    focusState: owners.focusState,
    libraryState: owners.libraryState,
    mounted: scope.mounted,
    setState: scope.setState,
    exitSelectionMode: () => sections.selection.exitSelectionMode(),
    focusFirstItem: () => sections.navigation.focusFirstItem(),
    isAtRoot: () => sections.navigation.isAtRoot,
    load: () => sections.libraryLoading.load(),
    loadLinks: () => sections.libraryLoading.loadLinks(),
    navigateUp: () => sections.navigation.navigateUp(),
    openMagnet: (AllDebridMagnet magnet, {bool force = false}) =>
        sections.navigation.openMagnet(magnet, force: force),
    snack: (String message, {bool isError = true}) =>
        sections.feedback.snack(message, isError: isError),
    toggleSearch: () => sections.search.toggleSearch(),
    visibleLinks: () => sections.search.visibleLinks,
    visibleMagnets: () => sections.search.visibleMagnets,
  ));
  sections.libraryLoadingSlot = AllDebridLibraryLoading((
    libraryState: owners.libraryState,
    selectionState: owners.selectionState,
    mounted: scope.mounted,
    setState: scope.setState,
    focusFirstItem: () => sections.navigation.focusFirstItem(),
  ));
  sections.selectionSlot = AllDebridSelection((
    selectionState: owners.selectionState,
    setState: scope.setState,
    isAllSelected: () => sections.selection.isAllSelected,
    visibleMagnets: () => sections.search.visibleMagnets,
  ));
  sections.searchSlot = AllDebridSearch((
    searchState: owners.searchState,
    focusState: owners.focusState,
    libraryState: owners.libraryState,
    navigationState: owners.navigationState,
    mounted: scope.mounted,
    setState: scope.setState,
  ));
  sections.feedbackSlot = AllDebridFeedback((
    feedbackState: owners.feedbackState,
    context: scope.context,
    mounted: scope.mounted,
  ));
  return sections;
}
