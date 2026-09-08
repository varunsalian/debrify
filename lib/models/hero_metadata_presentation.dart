import 'metadata_preferences.dart';
import 'stremio_addon.dart';

/// An authoritative provider result, distinct from legacy sparse /meta data.
/// Carries its policy with the result so a delayed consumer cannot mix policies.
class HeroMetadataPresentation extends StremioMeta {
  final MetadataPreferences preferences;

  HeroMetadataPresentation(StremioMeta item, this.preferences)
    : super(
        id: item.id,
        imdbId: item.imdbId,
        type: item.type,
        name: item.name,
        poster: item.poster,
        background: item.background,
        description: item.description,
        year: item.year,
        imdbRating: item.imdbRating,
        genres: item.genres,
        runtime: item.runtime,
        sourceAddon: item.sourceAddon,
        trailerYtId: item.trailerYtId,
        logo: item.logo,
        addedAtMs: item.addedAtMs,
      );
}

/// Resolves sparse legacy data while keeping intentional missing fields intact.
class HeroMetadataFields {
  final StremioMeta original;
  final StremioMeta? enriched;
  HeroMetadataFields(this.original, this.enriched);

  bool selected(MetadataCategory category) =>
      enriched is HeroMetadataPresentation &&
      (enriched as HeroMetadataPresentation).preferences.provider(category) !=
          MetadataPreferences.current;

  bool get allowArtworkFallback =>
      !selected(MetadataCategory.backgrounds) ||
      (enriched as HeroMetadataPresentation).preferences.fallback;

  static String? nonempty(String? value) =>
      value?.trim().isNotEmpty == true ? value : null;
  String? field(String? current, String? previous, MetadataCategory category) =>
      selected(category)
      ? nonempty(current)
      : nonempty(current) ?? nonempty(previous);

  String get name =>
      selected(MetadataCategory.information) ? enriched!.name : original.name;
  String? get description => field(
    enriched?.description,
    original.description,
    MetadataCategory.information,
  );
  String? get runtime =>
      field(enriched?.runtime, original.runtime, MetadataCategory.information);
  List<String>? get genres => selected(MetadataCategory.information)
      ? enriched?.genres
      : (enriched?.genres?.isNotEmpty == true
            ? enriched!.genres
            : original.genres);
  String? get logo =>
      field(enriched?.logo, original.logo, MetadataCategory.backgrounds);
  String? get background => field(
    enriched?.background,
    original.background,
    MetadataCategory.backgrounds,
  );
  String? get posterFallback => allowArtworkFallback
      ? (selected(MetadataCategory.posters)
            ? nonempty(enriched?.poster)
            : nonempty(original.poster))
      : null;
}

/// Builds the fallback baseline before provider policy is applied. Sparse /meta
/// replies enrich catalog fields without replacing source/tracking identity.
StremioMeta mergeHeroMetadata(StremioMeta catalog, StremioMeta? details) {
  if (details == null || identical(catalog, details)) return catalog;
  String? value(String? fresh, String? old) =>
      HeroMetadataFields.nonempty(fresh) ?? old;
  return StremioMeta(
    id: catalog.id,
    type: catalog.type,
    imdbId: catalog.imdbId ?? details.imdbId,
    name: value(details.name, catalog.name)!,
    poster: value(details.poster, catalog.poster),
    background: value(details.background, catalog.background),
    description: value(details.description, catalog.description),
    year: value(details.year, catalog.year),
    imdbRating: details.imdbRating ?? catalog.imdbRating,
    genres: details.genres?.isNotEmpty == true
        ? details.genres
        : catalog.genres,
    runtime: value(details.runtime, catalog.runtime),
    sourceAddon: catalog.sourceAddon,
    trailerYtId: value(details.trailerYtId, catalog.trailerYtId),
    logo: value(details.logo, catalog.logo),
    addedAtMs: catalog.addedAtMs,
  );
}
