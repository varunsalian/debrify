import '../../../models/stremio_addon.dart';
import '../../../services/home_collection_rows.dart';
import '../../../services/home_list_rows.dart';

/// Detach paging containers for a return snapshot. Metadata stays borrowed,
/// while an outgoing page cannot alter the next view's items or loading latch.
CatalogSection copyHomeRowForReturn(CatalogSection row) {
  if (row is HomeCollectionSection) {
    return HomeCollectionSection(collection: row.collection);
  }
  if (row is HomeListSection) {
    return HomeListSection(
      rowId: row.rowId,
      title: row.title,
      items: List.of(row.items),
      traktChoice: row.traktChoice,
      simklList: row.simklList,
      mdblistList: row.mdblistList,
    );
  }
  return CatalogSection(
    title: row.title,
    addon: row.addon,
    catalog: row.catalog,
    items: List.of(row.items),
    nextSkip: row.nextSkip,
    exhausted: row.exhausted,
    pagingPaused: row.pagingPaused,
    query: row.query,
  );
}
