import 'dart:async';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_dependencies.dart';
import 'package:debrify/features/merged_detail/presentation/merged_detail_palette.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/imdb_enrichment_service.dart';
import 'package:debrify/services/imdb_parents_guide_service.dart';
import 'package:debrify/widgets/metadata_title_navigation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class MergedDetailMetadataState {
  final MergedDetailDependencies _deps;
  MergedDetailMetadataState(this._deps);

  /// Per-title accent, extracted once from the poster (same cheap 32px decode
  /// the home hero uses). Colors the eyebrow, an ambient wash behind the title
  /// and the Play button's glow, so the page feels made for *this* title rather
  /// than a template with the artwork swapped in. Falls back to [_gold] until a
  /// colorful dominant color is found (or forever, for a B&W poster).
  Color accent = MergedDetailPalette.gold;

  ImdbEnrichment? imdbExtra;
  ParentsGuideResult? parentsGuide;
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
  StremioMeta? enriched;
  bool showcaseOpeningDataReady = false;

  int detailsMetadataGeneration = 0;
}
