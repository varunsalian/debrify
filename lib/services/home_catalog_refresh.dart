import 'package:collection/collection.dart';
import '../models/stremio_addon.dart';
import 'filtered_catalog_pager.dart';

/// Reuses unchanged rows, including their paging state and any in-flight page.
/// Changed definitions reload the old raw paging extent before replacing a row.
Future<CatalogSection?> loadHomeCatalogSection({
  required StremioAddon addon,
  required StremioAddonCatalog catalog,
  CatalogSection? previous,
  required Future<List<StremioMeta>> Function(
    int skip,
    void Function(int) onRawCount,
  )
  fetch,
  required bool Function() isCurrent,
  bool Function(StremioMeta)? hides,
}) async {
  final sameIdentity =
      previous != null &&
      previous.addon.id == addon.id &&
      previous.catalog.id == catalog.id &&
      previous.catalog.type == catalog.type;
  if (sameIdentity &&
      const DeepCollectionEquality().equals(
        previous.addon.toJson(),
        addon.toJson(),
      ) &&
      const DeepCollectionEquality().equals(
        previous.catalog.toJson(),
        catalog.toJson(),
      )) {
    return previous;
  }
  final targetSkip = sameIdentity ? previous.nextSkip : 0;
  final items = <StremioMeta>[];
  final seen = <String>{};
  var skip = 0;
  var exhausted = false;
  var paused = false;
  do {
    if (!isCurrent()) return null;
    final page = await fetchFilteredPage(
      (cursor, raw) => isCurrent()
          ? fetch(cursor, raw)
          : Future.value(const <StremioMeta>[]),
      skip: skip,
      hides: hides,
      seenIds: seen,
    );
    if (!isCurrent()) return null;
    skip = page.nextSkip;
    exhausted = page.exhausted;
    items.addAll(page.items);
    paused = !exhausted && page.items.isEmpty;
    if (exhausted || paused) break;
  } while (skip < targetSkip);
  if (items.isEmpty && exhausted) return null;
  return CatalogSection(
    title: CatalogSection.rowTitle(catalog),
    addon: addon,
    catalog: catalog,
    items: items,
    nextSkip: skip,
    exhausted: exhausted,
    pagingPaused: paused,
  );
}
