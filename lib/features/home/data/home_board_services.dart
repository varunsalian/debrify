import '../../../services/home_load_progress.dart';
import '../../../services/home_load_deadline.dart';
import '../../../models/home_collection.dart';
import '../../../models/home_preferences.dart';
import '../../../models/stremio_addon.dart';
import '../../../services/home_list_rows.dart';

/// Borrowed tracker/watched/catalog policies used by a Home load. No resource,
/// cache or retry ownership moves from the existing services into this adapter.
class HomeBoardServices {
  const HomeBoardServices({
    required this.hideWatched,
    required this.startWatched,
    required this.firstWatchedSnapshot,
    required this.resolveLists,
    required this.claimedCatalogs,
  });

  final bool Function() hideWatched;
  final void Function() startWatched;
  final Future<void> Function() firstWatchedSnapshot;
  final Future<List<HomeListSection>> Function(
    List<HomeExtraRow> extras, {
    required List<HomeListSection> previous,
    required bool Function() isCurrent,
    required void Function(List<HomeListSection>) onUpdate,
  })
  resolveLists;
  final Set<String> Function(
    List<HomeCollection> collections,
    List<StremioAddon> addons, {
    required Set<String> disabledRows,
    required bool showsCollectionRows,
  })
  claimedCatalogs;

  static List<HomeListSection> previousLists(List<CatalogSection> rows) =>
      rows.whereType<HomeListSection>().toList();

  static bool isList(CatalogSection row) => row is HomeListSection;

  static List<CatalogSection> replaceLists(
    List<CatalogSection> rows,
    List<HomeListSection> lists,
  ) => replaceHomeListRows(rows, lists);

  static HomeLoadProgress createProgress({
    required bool Function() isCurrent,
    required String Function(CatalogSection) rowId,
    required void Function(List<CatalogSection>, bool) onPublish,
  }) => HomeLoadProgress(
    isCurrent: isCurrent,
    rowId: rowId,
    onPublish: onPublish,
  );

  static Future<void> runWithDeadline({
    required Future<void> Function() load,
    required void Function() retire,
  }) => runHomeLoadWithDeadline(load: load, retire: retire);
}
