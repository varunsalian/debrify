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
}
