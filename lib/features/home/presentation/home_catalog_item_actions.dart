import '../../../models/stremio_addon.dart';

/// How a Home catalog card or row interacts with its title: the bound-source
/// and PikPak-only badges, and the open, quick-play, See-All and source-tag
/// actions. Classic rows, stage cards, Tonight and the Spotlight shelves all
/// use this one role; the screen composition implements it.
abstract interface class HomeCatalogItemActions {
  bool isBound(StremioMeta item);

  /// PikPak-only mode hides quick play.
  bool get pikpakOnly;
  void open(CatalogSection section, StremioMeta item, {String? heroTag});
  void quickPlay(CatalogSection section, StremioMeta item);
  void openSeeAll(CatalogSection section);
  String? sourceTag(CatalogSection section);
}
