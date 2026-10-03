import 'torbox_browsing_composition.dart';
import 'torbox_catalog_actions_composition.dart';
import 'torbox_composition_bindings.dart';
import 'torbox_file_workflows_composition.dart';
import 'torbox_sections.dart';

/// Construct one view's sections in their reviewed assignment order.
TorboxSections createTorboxSections(
  TorboxViewBindings view,
  TorboxCompositionStates states,
) {
  final sections = TorboxSections();
  wireTorboxCatalogActions(sections, view, states);
  wireTorboxFileWorkflows(sections, view, states);
  wireTorboxBrowsing(sections, view, states);
  return sections;
}
