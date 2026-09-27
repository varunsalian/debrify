import '../../../models/home_collection.dart';
import 'home_catalog_preferences.dart';

/// Accepted Home configuration. Containers are immutable; legacy collection
/// objects retain identity, as they did in the existing shallow return snapshot.
class HomeBoardConfiguration {
  HomeBoardConfiguration({
    required this.preferences,
    required List<HomeCollection> collections,
    required this.collectionsSignature,
    required this.hideWatched,
  }) : collections = List.unmodifiable(collections);

  const HomeBoardConfiguration.empty()
    : preferences = const HomeCatalogPreferences.empty(),
      collections = const [],
      collectionsSignature = '',
      hideWatched = false;

  final HomeCatalogPreferences preferences;
  final List<HomeCollection> collections;
  final String collectionsSignature;
  final bool hideWatched;
}
