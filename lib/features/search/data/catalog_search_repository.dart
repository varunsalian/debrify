import '../../../models/stremio_addon.dart';
import '../models/catalog_search_row.dart';

abstract interface class CatalogSearchRepository {
  bool get isCurrent;
  Future<List<StremioAddon>> searchableAddons();
  Future<Set<String>> readDisabledAddons();
  Future<void> writeDisabledAddons(Set<String> disabled);

  /// Preserves raw cursor counts and watched filtering. Empty visible rows are
  /// omitted; transport failures throw so the caller can count failed sources.
  Future<CatalogSearchRow?> searchCatalog(
    StremioAddon addon,
    StremioAddonCatalog catalog,
    String query,
  );
}
