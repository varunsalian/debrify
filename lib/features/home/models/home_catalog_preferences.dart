import '../../../models/home_preferences.dart';

/// Read-only settings snapshot. Loading generations and commits belong to the
/// caller; this value owns no cached preference or profile state.
class HomeCatalogPreferences {
  const HomeCatalogPreferences.empty()
    : disabled = const {},
      extras = const [],
      rowOrder = const [],
      heroSource = const (mode: HomeHeroSourceMode.random, ids: <String>[]);

  HomeCatalogPreferences({
    required Set<String> disabled,
    required List<HomeExtraRow> extras,
    required List<String> rowOrder,
    required HomeHeroSource heroSource,
  }) : disabled = Set.unmodifiable(disabled),
       extras = List.unmodifiable(extras),
       rowOrder = List.unmodifiable(rowOrder),
       heroSource = (
         mode: heroSource.mode,
         ids: List<String>.unmodifiable(heroSource.ids),
       );

  final Set<String> disabled;
  final List<HomeExtraRow> extras;
  final List<String> rowOrder;
  final HomeHeroSource heroSource;
}
