import '../data/home_catalog_preferences_repository.dart';
import '../data/home_collections_repository.dart';
import '../models/home_board_configuration.dart';
import 'home_catalog_controller.dart';
import 'home_configuration_changes.dart';

/// One settings refresh. The existing catalog controller owns accepted state;
/// the caller owns refresh/profile lifetime and dispatches the returned effects.
class HomeConfigurationRefresh {
  const HomeConfigurationRefresh({
    required this.catalog,
    required this.preferences,
    required this.collections,
    required this.readHideWatched,
  });

  final HomeCatalogController catalog;
  final HomeCatalogPreferencesRepository preferences;
  final HomeCollectionsRepository collections;
  final bool Function() readHideWatched;

  Future<HomeConfigurationChanges?> run({
    required bool Function() isCurrent,
    required bool isHome,
  }) async {
    if (!isCurrent()) return null;
    final settings = await preferences.read();
    if (!isCurrent()) return null;
    final savedCollections = await collections.read();
    if (!isCurrent()) return null;
    // Preserve the pre-hash watched comparison, even if another accepted board
    // configuration arrives while the worker-isolate signature is pending.
    final hideWatched = readHideWatched();
    final previousHideWatched = catalog.current.configuration.hideWatched;
    final signature = await collections.signature(savedCollections);
    if (!isCurrent()) return null;
    final previous = catalog.current.configuration;
    final changes = homeConfigurationChanges(
      previous: previous.preferences,
      next: settings,
      previousHideWatched: previousHideWatched,
      hideWatched: hideWatched,
      previousCollectionsSignature: previous.collectionsSignature,
      collectionsSignature: signature,
      isHome: isHome,
    );
    if (changes.changed) {
      catalog.applyConfiguration(
        HomeBoardConfiguration(
          preferences: settings,
          collections: savedCollections,
          collectionsSignature: signature,
          hideWatched: hideWatched,
        ),
      );
    }
    return changes;
  }
}
