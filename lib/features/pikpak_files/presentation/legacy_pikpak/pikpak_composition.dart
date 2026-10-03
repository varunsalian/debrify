import 'pikpak_data_composition.dart';
import 'pikpak_sections.dart';

export 'pikpak_sections.dart';

PikpakSections createPikpakSections(
  PikpakScope scope,
  PikpakOwners owners,
  PikpakDeferred deferred,
) {
  final sections = PikpakSections();
  wirePikpakDataSections(sections, scope, owners, deferred);
  return sections;
}
