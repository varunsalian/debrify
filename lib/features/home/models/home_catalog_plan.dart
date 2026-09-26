import '../../../models/stremio_addon.dart';

typedef HomeCatalogReference = (StremioAddon, StremioAddonCatalog);

/// Read-only inventory containers retaining the original manifest identities.
/// Catalog items, cursors, requests and publication remain with their owners.
class HomeCatalogPlan {
  HomeCatalogPlan({
    required List<HomeCatalogReference> references,
    required Map<String, StremioAddon> addonsById,
  }) : references = List.unmodifiable(references),
       addonsById = Map.unmodifiable(addonsById);

  final List<HomeCatalogReference> references;
  final Map<String, StremioAddon> addonsById;
}

String homeCatalogRowId(HomeCatalogReference reference) =>
    '${reference.$1.id}:${reference.$2.type}:${reference.$2.id}';
