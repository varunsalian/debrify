import 'dart:math';

import 'package:flutter/material.dart';

import '../../../models/home_collection_rows.dart';
import '../../../models/stremio_addon.dart';
import '../application/home_stage_metadata.dart';
import 'home_classic_row_metrics.dart';
import 'home_display_section.dart';
import 'home_stage_row_label.dart';
import 'home_stage_rows.dart';

/// Smallest poster art a stage rail will draw before it is simply too small
/// to recognise — the floor every derived rail box respects.
const double kStageMinPosterH = 56;

// ATRIUM metrics. The wall's height is DERIVED from these (never guessed),
// so the dossier column beside it can't be crowded by a taller row.
const double kAtriumLabelGap = 10;

double atriumLabelHeight(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(homeStageRowLabelFontSize) * 1.35;

/// Shared title/favorite geometry and artwork rules across Home layouts.
class HomeStageGeometry {
  HomeStageGeometry(this._displaySection, this._sections);
  final HomeDisplaySection _displaySection;
  final List<CatalogSection> Function() _sections;

  /// A rail strip reserves ONE box height for every rail kind (invariant: a
  /// per-kind height bounces the layout on every fav↔catalog switch). The two
  /// kinds FILL it differently rather than one wasting the other's space: a
  /// catalog poster is the full box, a favourite's poster is the box minus its
  /// caption band, so both end exactly on the box's bottom edge.
  /// TITLE cards follow the Home Cards orientation setting; everything else
  /// (favourites, channels, playlists) keeps its own fixed shape.
  double get titleCardAspect =>
      homeTitleCardAspect(landscape: _displaySection.homeLandscapeCards);

  /// The art for a title card under the current orientation. Null keeps the
  /// cell's own default (the 2:3 poster) — only landscape needs a derived
  /// wide still.
  String? titleArtUrl(StremioMeta item) =>
      _displaySection.homeLandscapeCards ? homeStageWideArtwork(item) : null;

  HomeCollectionSection? stageCollection(HomeRail rail) {
    final index = rail.sectionIndex;
    if (index == null) return null;
    final section = _sections()[index];
    return section is HomeCollectionSection ? section : null;
  }

  double stageCardAspect(HomeRail rail, {double? fallback}) =>
      stageCollection(rail)?.tileAspectRatio ?? fallback ?? titleCardAspect;

  String? stageCardArt(HomeRail rail, StremioMeta item, {bool wide = false}) =>
      stageCollection(rail) != null
      ? item.poster
      : wide
      ? homeStageWideArtwork(item)
      : titleArtUrl(item);

  double stageFavW(BuildContext context, double boxH) {
    // Poster + caption must equal the box EXACTLY. A width floor here would
    // make the poster taller than the space left by a scaled caption and
    // overflow the row — so the art simply gets whatever is left (never
    // below a hairline, so the cell is still hit-testable).
    final art = boxH - _displaySection.homeArtPosterCaptionBand;
    return (art < 16 ? 16.0 : art) * 2 / 3;
  }

  /// The box height a rail strip may actually use: the layout's preference,
  /// but never less than a favourite cell needs at the CURRENT text scale
  /// (its two-line caption grows with accessibility settings, and a fixed box
  /// would clip it), and never more than [maxH].
  double stageRailBoxH(
    BuildContext context,
    double preferred, {
    required double maxH,
  }) {
    final floor = _displaySection.homeArtPosterCaptionBand + kStageMinPosterH;
    final lo = min(floor, maxH);
    return preferred.clamp(lo, max(lo, maxH));
  }
}
