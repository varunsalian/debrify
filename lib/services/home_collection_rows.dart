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
  String? focusArtOf(StremioMeta item) {
    final folder = folderOf(item);
    return folder?.focusGifEnabled == true ? folder?.focusGifUrl : null;
  }

  double tileAspectOf(StremioMeta item) =>
      folderOf(item)?.tileShape.aspectRatio ?? tileAspectRatio;

  String? focusVideoOf(StremioMeta item) {
    final folder = folderOf(item);
    if (folder == null || !folder.focusVideoEnabled) return null;
    final url = folder.focusVideoUrl;
    final uri = url == null ? null : Uri.tryParse(url);
    return uri != null &&
            (uri.scheme == 'https' || uri.scheme == 'http') &&
            uri.host.isNotEmpty
        ? url
        : null;
  }

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

  /// Maximum aspect reserves enough room in fixed-cell stage layouts.
  /// Each card still renders its own folder shape inside that space.
  double get tileAspectRatio => collection.folders.isEmpty
      ? CollectionTileShape.landscape.aspectRatio
      : collection.folders
            .map((f) => f.tileShape.aspectRatio)
            .reduce((a, b) => a > b ? a : b);

  bool get landscapeTiles => tileAspectRatio >= 1;

  static StremioMeta folderMeta(HomeCollection c, HomeCollectionFolder f) =>
      CollectionFolderMeta(c, f);
}

/// Folder-only presentation data travels with the card through every Home layout.
class CollectionFolderMeta extends StremioMeta {
  final HomeCollectionFolder folder;
  CollectionFolderMeta(HomeCollection collection, this.folder)
    : super(
        id: HomeCollectionRowIds.folderMetaId(collection.id, folder.id),
        type: 'folder',
        name: folder.title,
        poster: folder.coverImageUrl,
        background:
            folder.heroBackdropUrl ??
            collection.backdropImageUrl ??
            folder.coverImageUrl,
        logo: folder.titleLogoUrl,
        description: folder.sources.isEmpty
            ? null
            : '${folder.sources.length} ${folder.sources.length == 1 ? 'list' : 'lists'}',
      );
}
