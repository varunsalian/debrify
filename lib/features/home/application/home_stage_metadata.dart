import '../../../models/stremio_addon.dart';

/// Metahub title-logo URL derived synchronously from an IMDb id (same trick
/// the hero uses) — lets the Canvas identity show studio title art without
/// waiting for /meta enrichment. Null when the item has no IMDb-shaped id.
String? homeStageLogoUrl(StremioMeta item) {
  final tt = item.imdbId ?? (item.id.startsWith('tt') ? item.id : null);
  return tt == null ? null : 'https://images.metahub.space/logo/medium/$tt/img';
}

/// Whether [enriched] describes the same title as [item]. Raw id equality is
/// not enough: an addon can list a title as `tmdb:603` while the /meta
/// record — fetched via the IMDb id the addon supplied — comes back as
/// `tt0133093`. Compare canonical IMDb identity too, or valid enrichment
/// gets rejected and Canvas loses its backdrop/description/rating.
bool sameHomeStageTitle(StremioMeta item, StremioMeta enriched) {
  if (enriched.id == item.id) return true;
  final itTt = item.imdbId ?? (item.id.startsWith('tt') ? item.id : null);
  final enTt =
      enriched.imdbId ?? (enriched.id.startsWith('tt') ? enriched.id : null);
  return itTt != null && itTt == enTt;
}
