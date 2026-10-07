import 'premiumize_data_composition.dart';
import 'premiumize_sections.dart';

export 'premiumize_sections.dart';

PremiumizeSections createPremiumizeSections(
  PremiumizeScope scope,
  PremiumizeOwners owners,
) {
  final sections = PremiumizeSections();
  wirePremiumizeDataSections(sections, scope, owners);
  return sections;
}
