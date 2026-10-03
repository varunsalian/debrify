import 'debrid_browsing_composition.dart';
import 'debrid_catalog_actions_composition.dart';
import 'debrid_composition_bindings.dart';
import 'debrid_file_workflows_composition.dart';
import 'debrid_sections.dart';

export 'debrid_add_input_state.dart' show DebridAddInputState;
// Public composition types used by the facade to construct its nine owners.
export 'debrid_catalog_state.dart' show DebridCatalogState;
export 'debrid_download_state.dart' show DebridDownloadState;
export 'debrid_focus_state.dart' show DebridFocusState;
export 'debrid_folder_search_state.dart' show DebridFolderSearchState;
export 'debrid_navigation_state.dart' show DebridNavigationState;
export 'debrid_selection_state.dart' show DebridSelectionState;
export 'debrid_torrent_search_state.dart' show DebridTorrentSearchState;
export 'debrid_view_state.dart' show DebridViewState;

/// Construct one view's sections in their reviewed assignment order.
DebridSections createDebridSections(
  DebridViewBindings view,
  DebridCompositionStates states,
) {
  final sections = DebridSections();
  wireDebridCatalogActions(sections, view, states);
  wireDebridFileWorkflows(sections, view, states);
  wireDebridBrowsing(sections, view, states);
  return sections;
}
