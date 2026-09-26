import '../../../models/stremio_addon.dart';
import '../../../services/home_catalog_refresh.dart';
import '../models/home_catalog_plan.dart';

/// Catalog access and parallel row loading. The caller owns cursor reservation,
/// request generations, profile checks and accepted-row publication.
class HomeCatalogRepository {
  const HomeCatalogRepository({
    required this.readAddons,
    required this.fetchPage,
    required this.readHides,
  });

  final Future<List<StremioAddon>> Function() readAddons;
  final Future<List<StremioMeta>> Function(
    StremioAddon addon,
    StremioAddonCatalog catalog,
    int skip,
    void Function(int) onRawCount,
  )
  fetchPage;
  final bool Function(StremioMeta)? Function() readHides;

  Future<List<CatalogSection>> fetchBatch(
    List<HomeCatalogReference> references, {
    Map<String, CatalogSection> previousRows = const {},
    required bool Function() isCurrent,
    void Function(CatalogSection)? onSection,
  }) async {
    final results = await Future.wait(
      references.map((reference) async {
        final (addon, catalog) = reference;
        try {
          final row = await loadHomeCatalogSection(
            addon: addon,
            catalog: catalog,
            previous: previousRows[homeCatalogRowId(reference)],
            isCurrent: isCurrent,
            hides: readHides(),
            fetch: (skip, onRawCount) =>
                fetchPage(addon, catalog, skip, onRawCount),
          );
          if (!isCurrent()) return null;
          if (row != null) onSection?.call(row);
          return row;
        } catch (_) {
          return null;
        }
      }),
    );
    // Callers still accumulate vertical refresh batches into this owned list.
    return results.whereType<CatalogSection>().toList();
  }
}
