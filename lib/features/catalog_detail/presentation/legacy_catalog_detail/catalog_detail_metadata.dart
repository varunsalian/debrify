import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:debrify/features/catalog_detail/presentation/legacy_catalog_detail/catalog_detail_dependencies.dart';
import 'package:debrify/models/play_loader_art.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/imdb_enrichment_service.dart';
import 'package:debrify/services/imdb_parents_guide_service.dart';
import 'package:debrify/services/metadata_details_service.dart';
import 'package:debrify/services/metadata_preferences_service.dart';
import 'package:debrify/services/metadata_provider_service.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/theme/artwork_accent.dart';
import 'package:debrify/widgets/metadata_title_navigation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class CatalogDetailMetadata {
  final CatalogDetailDependencies _deps;

  CatalogDetailMetadata(this._deps);

  bool get mounted => _deps.mounted();

  void Function(VoidCallback) get setState => _deps.setState;

  /// "Watch Next" recommendations. null = not yet loaded / still loading;
  /// empty = loaded but nothing to show (rail stays hidden either way).
  void openMetadataRecommendation(StremioMeta item) {
    final onOpen = _deps.onRecommendationTap();
    if (onOpen != null)
      unawaited(
        openMetadataTitle(
          _deps.context(),
          recommendationOriginals[item] ?? item,
          onOpen,
        ),
      );
  }

  List<StremioMeta>? recommendations;

  final recommendationOriginals = Map<StremioMeta, StremioMeta>.identity();

  /// Catalog-quality metadata fetched after first paint for a sparse item
  /// (a tapped recommendation). null until/unless enrichment succeeds.
  StremioMeta? enriched;

  /// Parents guide data. null = not yet loaded; result with empty categories =
  /// loaded but nothing to show.
  ParentsGuideResult? parentsGuide;

  /// Extra metadata from IMDb GraphQL (runtime, certificate, cast, etc.).
  ImdbEnrichment? imdbExtra;

  bool imdbLoaded = false;

  bool parentsGuideLoaded = false;

  bool recommendationsLoaded = false;

  /// When the item arrived sparse — no year, rating, or genres, the
  /// signature of a "Watch Next" recommendation built straight from an
  /// addon stream entry — fetch full Cinemeta-grade metadata after first
  /// paint and merge it in, so the screen ends up identical to a normal
  /// catalog open. Fail-soft: any failure leaves the original item as-is.
  Future<void> loadEnrichedMeta() async {
    final enrich = _deps.metaEnricher();
    final item = _deps.item();
    final imdbId = item.effectiveImdbId;
    if (enrich == null || imdbId == null) return;

    // An item with no overview is never "rich enough": Trakt / Simkl / MDBList
    // rows carry a year and rating but no description, and the page would show
    // an empty summary if we skipped the fetch on their behalf.
    final alreadyRich =
        (item.description?.isNotEmpty ?? false) &&
        ((item.year != null && item.year!.isNotEmpty) ||
            item.imdbRating != null ||
            (item.genres?.isNotEmpty ?? false));
    if (alreadyRich) return; // a normal catalog item — nothing to add

    try {
      final full = await enrich(imdbId, item.type);
      if (full == null || !mounted) return;
      setState(() {
        // Keep identity/source from the tapped item; take the structured
        // fields and clean overview from the fetched meta, but never let a
        // missing field blank out something we already had.
        enriched = StremioMeta(
          id: item.id,
          imdbId: item.imdbId,
          type: item.type,
          name: full.name.isNotEmpty ? full.name : item.name,
          poster: full.poster ?? item.poster,
          background: full.background ?? item.background,
          description: (full.description?.isNotEmpty ?? false)
              ? full.description
              : item.description,
          year: full.year ?? item.year,
          imdbRating: full.imdbRating ?? item.imdbRating,
          genres: (full.genres?.isNotEmpty ?? false)
              ? full.genres
              : item.genres,
          runtime: full.runtime ?? item.runtime,
          sourceAddon: item.sourceAddon,
          trailerYtId: full.trailerYtId ?? item.trailerYtId,
          logo: full.logo ?? item.logo,
        );
      });
      _deps.refreshMetadataPresentation();
      emitLoaderArt();
    } catch (_) {
      // Non-critical enrichment — swallow and keep the original item.
    }
  }

  /// Publishes the current best artwork for the play loader. Cheap and
  /// idempotent — the host just keeps the latest.
  void emitLoaderArt() {
    final sink = _deps.onLoaderArt();
    if (sink == null) return;
    final art = PlayLoaderArt.fromMeta(
      _deps.presentedItem(),
      certificate: imdbExtra?.certificate,
    );
    if (!art.isEmpty) sink(art);
  }

  int detailsMetadataGeneration = 0;

  void onMetadataPolicyChanged() {
    detailsMetadataGeneration++;
    if (!mounted) return;
    setState(() {
      imdbExtra = null;
      recommendations = [];
    });
    unawaited(loadImdbEnrichment());
    unawaited(loadRecommendations());
  }

  Future<void> loadImdbEnrichment() async {
    final generation = detailsMetadataGeneration;
    final scope = ProfileRuntime.scope.value;
    final revision = MetadataPreferencesService.revision.value;
    bool valid() =>
        mounted &&
        generation == detailsMetadataGeneration &&
        scope == ProfileRuntime.scope.value &&
        revision == MetadataPreferencesService.revision.value;
    final imdbId = _deps.presentedItem().effectiveImdbId;
    try {
      final extra = await MetadataDetailsService.instance.enrich(
        _deps.presentedItem(),
        loadExisting: () async =>
            imdbId == null ? null : ImdbEnrichmentService.fetch(imdbId),
      );
      if (mounted && valid()) {
        setState(() {
          imdbExtra = extra;
          imdbLoaded = true;
        });
        // Adds the certificate to the loader's meta line.
        emitLoaderArt();
      }
    } catch (_) {
      if (mounted && valid()) setState(() => imdbLoaded = true);
    }
  }

  Future<void> loadParentsGuide() async {
    final imdbId = _deps.presentedItem().effectiveImdbId;
    if (imdbId == null) {
      if (mounted) setState(() => parentsGuideLoaded = true);
      return;
    }
    try {
      final guide = await ImdbParentsGuideService.fetch(imdbId);
      if (mounted) {
        setState(() {
          parentsGuide = guide;
          parentsGuideLoaded = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => parentsGuideLoaded = true);
    }
  }

  /// Loads recommendations after first paint so the rail never blocks the
  /// detail screen's appearance. Fail-soft: any error leaves the rail hidden.
  Future<void> loadRecommendations() async {
    final generation = detailsMetadataGeneration;
    final scope = ProfileRuntime.scope.value;
    final revision = MetadataPreferencesService.revision.value;
    bool valid() =>
        mounted &&
        generation == detailsMetadataGeneration &&
        scope == ProfileRuntime.scope.value &&
        revision == MetadataPreferencesService.revision.value;
    final loader = _deps.recommendationsLoader();
    try {
      final recs = await MetadataDetailsService.instance.recommendations(
        _deps.presentedItem(),
        loader,
      );
      if (mounted && valid()) {
        recommendationOriginals.clear();
        setState(() {
          recommendations = recs;
          recommendationsLoaded = true;
        });
      }
      final enrich = _deps.metaEnricher();
      if (enrich != null) {
        for (final rec in recs.take(8)) {
          final id = rec.effectiveImdbId;
          if (id != null) enrich(id, rec.type);
        }
      }
      if (!valid()) return;
      await for (final batch in MetadataProviderService.instance.presentBatches(
        recs,
        isRelevant: valid,
      )) {
        if (!valid()) return;
        for (var index = 0; index < batch.length; index++) {
          recommendationOriginals[batch[index]] = recs[index];
        }
        setState(() => recommendations = batch);
      }
    } catch (_) {
      if (mounted && valid()) setState(() => recommendationsLoaded = true);
    }
  }

  /// This title's own colour, pulled from its poster.
  ///
  /// Same one-tiny-decode path `merged_series_detail_screen` has always had,
  /// through the shared cache so a revisit is free. Published into
  /// [ArtworkAccentScope] rather than applied here, so descendants — including
  /// the sheets and dialogs this screen raises, which inherit it because the
  /// scope is an `InheritedTheme` — can take it where they paint IDENTITY, and
  /// only there.
  Color? artworkAccent;

  Future<void> loadArtworkAccent() async {
    final url =
        _deps.presentedItem().poster ?? _deps.presentedItem().background;
    if (url == null || url.isEmpty) return;
    try {
      final raw = await DominantColorCache.of(
        url,
        CachedNetworkImageProvider(url),
      );
      if (raw == null || !mounted) return;
      // The extractor normalises for a DARK ui; on a paper theme that lands
      // low-contrast, so it is re-targeted against the ground it will be seen
      // on before anything paints with it.
      final app = AppThemeScope.of(_deps.context());
      setState(() => artworkAccent = normaliseAccentFor(raw, app));
    } catch (_) {}
  }
}
