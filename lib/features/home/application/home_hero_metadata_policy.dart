import '../../../models/hero_metadata_presentation.dart';
import '../../../models/metadata_preferences.dart';
import '../../../models/stremio_addon.dart';
import 'home_stage_metadata.dart';

/// Sparse catalog entries need /meta even when their artwork and plot exist:
/// runtime and title-treatment logos are often available only in the details.
/// A selected provider must also run for complete catalog entries.
bool needsHomeHeroMetadata(StremioMeta item, {required bool currentProvider}) {
  final needsBg = item.background == null || item.background!.isEmpty;
  final needsDesc = item.description == null || item.description!.isEmpty;
  final needsRating = item.imdbRating == null;
  final needsRuntime = item.runtime == null;
  final needsLogo = item.logo == null || item.logo!.isEmpty;
  return !(currentProvider &&
      !needsBg &&
      !needsDesc &&
      !needsRating &&
      !needsRuntime &&
      !needsLogo);
}

/// A shell-art publication. A null policy result means retain the current
/// publication; a result whose [art] is null explicitly clears the shell.
class HomeHeroAmbientArtUpdate {
  const HomeHeroAmbientArtUpdate({required this.itemId, required this.art});

  final String? itemId;
  final String? art;
}

/// Resolve metadata without publishing UI state. Layout eligibility and the
/// ordered bridge writes remain the caller's responsibility.
HomeHeroAmbientArtUpdate? homeHeroAmbientArtUpdate({
  required StremioMeta? item,
  required StremioMeta? enriched,
  required String? publishedItemId,
  required String? publishedArt,
}) {
  final authoritative =
      enriched is HeroMetadataPresentation &&
      item != null &&
      sameHomeStageTitle(item, enriched);
  final resolvedFields = authoritative
      ? HeroMetadataFields(item, enriched)
      : null;
  final fields =
      resolvedFields != null &&
          (resolvedFields.selected(MetadataCategory.backgrounds) ||
              resolvedFields.selected(MetadataCategory.posters))
      ? resolvedFields
      : null;
  final backdrop = fields != null
      ? fields.background
      : (item?.background?.isNotEmpty == true
            ? item!.background
            : (enriched?.background?.isNotEmpty == true
                  ? enriched!.background
                  : null));
  // Keep already-published art for the same title during sparse enrichment.
  // Selected-provider policy is authoritative, including intentional absence.
  if (fields == null &&
      backdrop == null &&
      item?.id != null &&
      item!.id == publishedItemId &&
      publishedArt != null) {
    return null;
  }
  final art =
      backdrop ?? (fields != null ? fields.posterFallback : item?.poster);
  return HomeHeroAmbientArtUpdate(
    itemId: item?.id,
    art: (art == null || art.isEmpty) ? null : art,
  );
}
