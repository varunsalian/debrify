import '../../../models/custom_series_identity.dart';
import '../../../models/media_identity.dart';
import '../../../models/stremio_addon.dart';
import '../models/home_catalog_origin.dart';

/// Shared identity preparation for detail opening and catalog playback. It owns
/// no view state; each action supplies its live acceptance guard independently.
class HomeCatalogOriginRepository {
  const HomeCatalogOriginRepository({
    required this.nativeAddon,
    required this.scopeProgress,
    required this.readCustomOrigin,
    required this.isOwnerCurrent,
  });

  final StremioAddon nativeAddon;
  final Future<StremioMeta> Function(StremioMeta, StremioAddon, bool Function())
  scopeProgress;
  final Future<StremioAddon?> Function(String) readCustomOrigin;
  final bool Function() isOwnerCurrent;

  Future<StremioAddon?> _origin(StremioMeta item, StremioAddon fallback) async {
    if (CustomSeriesIdentity.parse(item.imdbId) == null) return fallback;
    return readCustomOrigin(item.imdbId!);
  }

  Future<HomeCatalogOrigin> prepare(
    StremioMeta item,
    StremioAddon addon, {
    required bool Function() isCurrent,
  }) async {
    bool current() => isOwnerCurrent() && isCurrent();
    if (!current()) return HomeCatalogOrigin.retired(item);
    try {
      if (MediaIdentity.isNative(item.id) &&
          item.imdbId == null &&
          (item.sourceAddon == null || item.sourceAddon!.baseUrl.isEmpty)) {
        addon = nativeAddon;
      }
      item = await scopeProgress(item, addon, current);
    } on StateError {
      return current()
          ? HomeCatalogOrigin.unverified(item)
          : HomeCatalogOrigin.retired(item);
    }
    if (!current()) return HomeCatalogOrigin.retired(item);
    final origin = await _origin(item, addon);
    if (!current()) return HomeCatalogOrigin.retired(item);
    if (origin == null) return HomeCatalogOrigin.unavailable(item);
    if (CustomSeriesIdentity.isCustom(item.imdbId)) {
      item = item.withSourceAddon(origin);
    }
    return HomeCatalogOrigin.ready(item, origin);
  }
}
