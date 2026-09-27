import '../../../models/stremio_addon.dart';

enum HomeCatalogOriginStatus { ready, unavailable, unverified, retired }

/// A classified item is retained for the existing unavailable-history dialog.
class HomeCatalogOrigin {
  const HomeCatalogOrigin.ready(this.item, StremioAddon value)
    : addon = value,
      status = HomeCatalogOriginStatus.ready;
  const HomeCatalogOrigin.unavailable(this.item)
    : addon = null,
      status = HomeCatalogOriginStatus.unavailable;
  const HomeCatalogOrigin.unverified(this.item)
    : addon = null,
      status = HomeCatalogOriginStatus.unverified;
  const HomeCatalogOrigin.retired(this.item)
    : addon = null,
      status = HomeCatalogOriginStatus.retired;

  final StremioMeta item;
  final StremioAddon? addon;
  final HomeCatalogOriginStatus status;
}
