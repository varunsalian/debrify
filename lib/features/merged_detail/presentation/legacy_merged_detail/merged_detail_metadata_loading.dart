import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_dependencies.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_metadata_state.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_model_factory.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_trailer_actions.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_trailer_state.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/imdb_enrichment_service.dart';
import 'package:debrify/services/imdb_parents_guide_service.dart';
import 'package:debrify/services/metadata_details_service.dart';
import 'package:debrify/services/metadata_preferences_service.dart';
import 'package:debrify/services/metadata_provider_service.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/theme/artwork_accent.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class MergedDetailMetadataLoading {
  final MergedDetailDependencies _deps;
  MergedDetailMetadataLoading(this._deps);
  StremioMeta get _item => _deps.presentedItem();
  bool get mounted => _deps.mounted();
  VoidCallback get refreshMetadataPresentation =>
      _deps.refreshMetadataPresentation;
  void Function(VoidCallback) get setState => _deps.setState;
  MergedDetailMetadataState get _m => _deps.parts.metadataState;
  MergedDetailModelFactory get _b => _deps.parts.modelFactory;
  MergedDetailTrailerActions get _tr => _deps.parts.trailerActions;
  MergedDetailTrailerState get _t => _deps.parts.trailerState;

  Future<void> loadShowcaseOpeningData() async {
    try {
      await Future.wait<void>([
        _b.loadBoundSources(),
        loadEnrichedMeta(),
        loadImdbEnrichment(),
        loadParentsGuide(),
        loadRecommendations(),
      ]);
    } catch (_) {
      // Each loader is best effort. One failed service must not hold the
      // composed Showcase opening behind its readiness signal.
    } finally {
      if (mounted) setState(() => _m.showcaseOpeningDataReady = true);
    }
  }

  /// Pull a per-title accent from the poster (preferred — posters are more
  /// brand-saturated than backdrops). One tiny 32px decode; silent on failure,
  /// leaving the gold fallback. Extracted from the initial artwork only — a
  /// later enrichment swap isn't worth a second pass.
  ///
  /// Through [DominantColorCache] rather than the extractor directly, so
  /// reopening a title costs nothing and two screens asking at once share one
  /// decode. The cache also remembers a NULL answer, which is the common case
  /// for black-and-white artwork and used to be re-decoded on every visit.
  Future<void> loadAccent() async {
    final url = _deps.item().poster ?? _deps.item().background;
    if (url == null || url.isEmpty) return;
    try {
      final c = await DominantColorCache.of(
        url,
        CachedNetworkImageProvider(url),
      );
      if (c != null && mounted) setState(() => _m.accent = c);
    } catch (_) {}
  }

  Future<void> loadEnrichedMeta() async {
    final enrich = _deps.metaEnricher();
    final item = _deps.item();
    final imdbId = item.effectiveImdbId;
    if (enrich == null || imdbId == null) return;
    // A missing summary is on its own a reason to ask Cinemeta: rows from
    // Trakt / Simkl / MDBList arrive with a year and rating but no overview, and
    // the page has no other source for the description (the IMDb plot is a
    // best-effort scrape that can go away).
    final alreadyRich =
        (item.description?.isNotEmpty ?? false) &&
        ((item.year != null && item.year!.isNotEmpty) ||
            item.imdbRating != null ||
            (item.genres?.isNotEmpty ?? false));
    if (alreadyRich) return;
    try {
      final full = await enrich(imdbId, item.type);
      if (full == null || !mounted) return;
      setState(() {
        _m.enriched = StremioMeta(
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
      refreshMetadataPresentation();
    } catch (_) {}
  }

  void onMetadataPolicyChanged() {
    _m.detailsMetadataGeneration++;
    if (!mounted) return;
    setState(() {
      _m.imdbExtra = null;
      _m.recommendations = [];
    });
    unawaited(loadImdbEnrichment());
    unawaited(loadRecommendations());
    _t.trailerGeneration++;
    setState(() {
      _t.trailerYtId = null;
      _t.trailerCandidates = [];
      _t.trailerStreams = null;
      _t.trailerForeground = false;
      _t.trailerResolving = false;
      _t.trailerLoading = false;
    });
    unawaited(_tr.loadTrailer());
  }

  Future<void> loadImdbEnrichment() async {
    final generation = _m.detailsMetadataGeneration;
    final scope = ProfileRuntime.scope.value;
    final revision = MetadataPreferencesService.revision.value;
    bool valid() =>
        mounted &&
        generation == _m.detailsMetadataGeneration &&
        scope == ProfileRuntime.scope.value &&
        revision == MetadataPreferencesService.revision.value;
    final imdbId = _item.effectiveImdbId;
    try {
      final extra = await MetadataDetailsService.instance.enrich(
        _item,
        loadExisting: () async =>
            imdbId == null ? null : ImdbEnrichmentService.fetch(imdbId),
      );
      if (mounted && valid()) setState(() => _m.imdbExtra = extra);
    } catch (_) {}
  }

  Future<void> loadParentsGuide() async {
    final imdbId = _item.effectiveImdbId;
    if (imdbId == null) return;
    try {
      final guide = await ImdbParentsGuideService.fetch(imdbId);
      if (mounted) setState(() => _m.parentsGuide = guide);
    } catch (_) {}
  }

  Future<void> loadRecommendations() async {
    final generation = _m.detailsMetadataGeneration;
    final scope = ProfileRuntime.scope.value;
    final revision = MetadataPreferencesService.revision.value;
    bool valid() =>
        mounted &&
        generation == _m.detailsMetadataGeneration &&
        scope == ProfileRuntime.scope.value &&
        revision == MetadataPreferencesService.revision.value;
    final loader = _deps.recommendationsLoader();
    try {
      final recs = await MetadataDetailsService.instance.recommendations(
        _item,
        loader,
      );
      if (mounted && valid()) {
        _m.recommendationOriginals.clear();
        setState(() => _m.recommendations = recs);
      }
      if (!valid()) return;
      await for (final batch in MetadataProviderService.instance.presentBatches(
        recs,
        isRelevant: valid,
      )) {
        if (!valid()) return;
        for (var index = 0; index < batch.length; index++) {
          _m.recommendationOriginals[batch[index]] = recs[index];
        }
        setState(() => _m.recommendations = batch);
      }
    } catch (_) {}
  }
}
