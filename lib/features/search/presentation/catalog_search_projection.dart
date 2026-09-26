import '../../../models/stremio_addon.dart';
import '../models/catalog_search_row.dart';

/// Temporary bridge to the legacy Home/Search renderer. Search rows never page
/// in place; See All gets a separate growable list and the original raw cursor.
/// This projection is one-way and cannot mutate the notifier's row snapshot.
CatalogSection catalogSearchSection(CatalogSearchRow row) => CatalogSection(
  title: CatalogSection.rowTitle(row.catalog),
  addon: row.addon,
  catalog: row.catalog,
  items: List.of(row.items),
  query: row.query,
  nextSkip: row.nextSkip,
);
