import '../../../models/stremio_addon.dart';
import '../../../services/home_row_order.dart';
import '../models/home_catalog_plan.dart';

/// Enumerates manifest catalogs without fetching items or imposing a row cap.
/// Required-search catalogs cannot browse; hidden and collection-owned catalogs
/// stay out of the board. A null order preserves source order for Search/Discover.
HomeCatalogPlan planHomeCatalogs(
  List<StremioAddon> addons, {
  required Set<String> disabled,
  required Set<String> claimed,
  List<String>? rowOrder,
}) {
  final references = <HomeCatalogReference>[
    for (final addon in addons)
      for (final catalog in addon.catalogs)
        if (catalog.isBrowsable &&
            !disabled.contains(homeCatalogRowId((addon, catalog))) &&
            !claimed.contains(homeCatalogRowId((addon, catalog))))
          (addon, catalog),
  ];
  // Metadata fallback keeps the first addon for an ID, even if none of that
  // addon's catalogs survives the board filters.
  final byId = <String, StremioAddon>{};
  for (final addon in addons) {
    byId.putIfAbsent(addon.id, () => addon);
  }
  return HomeCatalogPlan(
    references: rowOrder == null
        ? references
        : HomeRowOrder.apply(references, rowOrder, homeCatalogRowId),
    addonsById: byId,
  );
}
