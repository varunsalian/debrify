import 'pikpak_actions_composition.dart';
import 'pikpak_data_composition.dart';
import 'pikpak_layout_composition.dart';
import 'pikpak_navigation_composition.dart';
import 'pikpak_sections.dart';

export 'pikpak_sections.dart';

PikpakSections createPikpakSections(PikpakScope scope, PikpakOwners owners) {
  final sections = PikpakSections();
  wirePikpakDataSections(sections, scope, owners);
  wirePikpakNavigationSections(sections, scope, owners);
  wirePikpakActionsSections(sections, scope, owners);
  wirePikpakLayoutSections(sections, scope, owners);
  return sections;
}
