import '../../../models/stremio_addon.dart';

/// A single-shot search row. Home's mutable paging model is never published as
/// application state; presentation can create a separate legacy view projection.
class CatalogSearchRow {
  final StremioAddon addon;
  final StremioAddonCatalog catalog;
  final List<StremioMeta> items;
  final String query;
  final int nextSkip;

  CatalogSearchRow({
    required this.addon,
    required this.catalog,
    required List<StremioMeta> items,
    required this.query,
    required this.nextSkip,
  }) : items = List.unmodifiable(items);
}
