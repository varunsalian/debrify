import '../models/home_collection.dart';
import '../models/stremio_addon.dart';

/// A Home board row for one imported collection; its folders are the tiles.
///
/// Subclassing [CatalogSection] (like `HomeListSection`) lets the row ride
/// the classic board ListView, the TV stage layouts, `_rowNodes` focus
/// bookkeeping and row ordering/hiding with no new threading. The items are
/// synthetic [StremioMeta]s (one per folder, `type: 'folder'`, poster = the
/// cover art); the board intercepts opens on this section type and pushes
/// the folder browser instead of a detail page. The addon is a placeholder
/// (empty baseUrl) — nothing may route a /meta or /stream call through it —
/// and [CatalogSection.exhausted] is latched so the row never pages.
class HomeCollectionSection extends CatalogSection {
  final HomeCollection collection;

  /// The row's Home-row id (`collection:<id>`), for ordering/hiding.
  final String rowId;

  static final StremioAddon placeholderAddon = StremioAddon(
    id: 'debrify.home.collection',
    name: 'Collection',
    manifestUrl: '',
    baseUrl: '',
  );

  HomeCollectionSection({required this.collection})
    : rowId = collection.rowId,
      super(
        title: collection.title,
        addon: placeholderAddon,
        catalog: StremioAddonCatalog(
          id: collection.rowId,
          type: 'folder',
          name: collection.title,
        ),
        items: [for (final f in collection.folders) folderMeta(collection, f)],
        exhausted: true,
      );

  /// The folder behind a tile, or null for an item that isn't one of ours.
  /// The folder's animated focus art for [item], when the file carries one.
  String? focusArtOf(StremioMeta item) => folderOf(item)?.focusGifUrl;

  HomeCollectionFolder? folderOf(StremioMeta item) {
    final i = folderIndexOf(item);
    return i < 0 ? null : collection.folders[i];
  }

  /// Index of the folder behind a tile, or -1 for an item that isn't one.
  int folderIndexOf(StremioMeta item) {
    for (var i = 0; i < collection.folders.length; i++) {
      final f = collection.folders[i];
      if (HomeCollectionRowIds.folderMetaId(collection.id, f.id) == item.id) {
        return i;
      }
    }
    return -1;
  }

  /// Width / height of the row's tiles. The first folder decides — a Nuvio
  /// collection is uniform in practice, and one shape per row keeps the rail
  /// grammar intact.
  double get tileAspectRatio => collection.folders.isEmpty
      ? CollectionTileShape.landscape.aspectRatio
      : collection.folders.first.tileShape.aspectRatio;

  bool get landscapeTiles => tileAspectRatio >= 1;

  static StremioMeta folderMeta(HomeCollection c, HomeCollectionFolder f) =>
      StremioMeta(
        id: HomeCollectionRowIds.folderMetaId(c.id, f.id),
        type: 'folder',
        name: f.title,
        poster: f.coverImageUrl,
        background: f.heroBackdropUrl ?? f.coverImageUrl,
        logo: f.titleLogoUrl,
        description: f.sources.isEmpty
            ? null
            : '${f.sources.length} catalog${f.sources.length == 1 ? '' : 's'}',
      );
}
