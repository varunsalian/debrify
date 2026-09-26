import '../../../models/home_preferences.dart';
import '../models/home_catalog_preferences.dart';

/// Sequential reads preserve the existing initial-load and refresh ordering.
/// No cache or profile state is retained; readers resolve their existing scope.
class HomeCatalogPreferencesRepository {
  const HomeCatalogPreferencesRepository({
    required this.readDisabled,
    required this.readExtras,
    required this.readRowOrder,
    required this.readHeroSource,
  });

  final Future<Set<String>> Function() readDisabled;
  final Future<List<HomeExtraRow>> Function() readExtras;
  final Future<List<String>> Function() readRowOrder;
  final Future<HomeHeroSource> Function() readHeroSource;

  Future<HomeCatalogPreferences> read() async {
    final disabled = await readDisabled();
    final extras = await readExtras();
    final rowOrder = await readRowOrder();
    final heroSource = await readHeroSource();
    return HomeCatalogPreferences(
      disabled: disabled,
      extras: extras,
      rowOrder: rowOrder,
      heroSource: heroSource,
    );
  }
}
