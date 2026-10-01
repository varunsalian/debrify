import '../../features/home/presentation/home_catalog_badges.dart';
import '../../features/home/presentation/home_catalog_item_actions.dart';
import '../../features/home/presentation/home_rows_navigation.dart';
import '../../models/stremio_addon.dart';

/// Home's catalog item role over the badges and rows navigation. Both are
/// resolved per call: they are constructed after the sections that use this.
class HomeCatalogItemActionsAdapter implements HomeCatalogItemActions {
  const HomeCatalogItemActionsAdapter({
    required this.badges,
    required this.navigation,
  });
  final HomeCatalogBadges Function() badges;
  final HomeRowsNavigation Function() navigation;

  @override
  bool isBound(StremioMeta item) => badges().isBound(item);
  @override
  bool get pikpakOnly => badges().pikpakOnly;
  @override
  void open(CatalogSection section, StremioMeta item, {String? heroTag}) =>
      navigation().sectionOpenItem(section, item, heroTag: heroTag);
  @override
  void quickPlay(CatalogSection section, StremioMeta item) =>
      navigation().sectionQuickPlay(section, item);
  @override
  void openSeeAll(CatalogSection section) =>
      navigation().openCatalogSeeAll(section);
  @override
  String? sourceTag(CatalogSection section) =>
      navigation().catalogSourceTag(section);
}
