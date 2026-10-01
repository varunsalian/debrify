import 'package:flutter/material.dart';

import '../../../theme/app_theme_scope.dart';
import '../../../widgets/skeleton_poster.dart' show BrandLoadingStage;
import 'home_board_media.dart';
import 'home_canvas_board.dart';
import 'home_deck_board.dart';
import 'home_display_section.dart';
import 'home_hero_preview.dart';
import 'home_mosaic_board.dart';
import 'home_promenade_board.dart';
import 'home_stage_cells.dart';
import 'home_stage_favorites.dart';
import 'home_stage_geometry.dart';
import 'home_stage_rails.dart';
import 'home_stage_section.dart';

typedef HomeStageBoardsDeps = ({
  BuildContext Function() context,
  bool Function() isTelevision,
  HomeBoardMedia Function() media,
});

/// Canvas, Promenade, Mosaic and Deck layout composition.
class HomeStageBoards {
  HomeStageBoards(
    this._deps,
    this._stageSection,
    this._stageRailsSection,
    this._stageGeometry,
    this._stageCells,
    this._stageFavorites,
    this._displaySection,
    this._heroPreview,
  );
  final HomeStageBoardsDeps _deps;
  final HomeStageSection _stageSection;
  final HomeStageRails _stageRailsSection;
  final HomeStageGeometry _stageGeometry;
  final HomeStageCells _stageCells;
  final HomeStageFavorites _stageFavorites;
  final HomeDisplaySection _displaySection;
  final HomeHeroPreview _heroPreview;

  /// The CANVAS home: full-bleed stage (idle art → ambient trailer via the
  /// same underlay engine, whose hole simply gets the whole canvas) with ONE
  /// shelf of large posters at the bottom and quiet rail tabs above it. No
  /// vertical scrolling, nothing clips at a fold, no row headers.
  Widget buildCanvasBoard() {
    final context = _deps.context();
    final view = _stageSection.resolveStageRail();
    if (view == null) {
      // First batch still streaming (or every loaded row is empty) — hold
      // the brand stage rather than an empty black canvas.
      return BrandLoadingStage(isTelevision: _deps.isTelevision());
    }
    _stageSection.seedStageFocusOnce();
    return buildHomeCanvasBoard(
      hostContext: context,
      view: view,
      media: () => _deps.media(),
      theater: () => _stageSection.canvasTheater,
      trailerActive: () => _heroPreview.heroTrailerActive,
      trailerShowing: _heroPreview.heroTrailerShowing,
      cardAspect: () => _stageGeometry.stageCardAspect(view.rail),
      captionBandHeight: () => _displaySection.homeArtPosterCaptionBand,
      favoriteCount: () =>
          _stageRailsSection.canvasFavItemCount(view.rail.favKind!),
      railTitle: (index) =>
          _stageRailsSection.canvasTabTitle(view.rails, index),
      favoriteBuilder: (_, col) =>
          _stageFavorites.canvasFavCell(view.rail.favKind!, view.key, col),
      itemBuilder: (_, col) => _stageCells.canvasCell(view, col),
    );
  }

  /// PROMENADE: Canvas's stage, symmetric. The identity sits centred in the
  /// lower third and the rail becomes a CENTRE-LOCKED strip — the focused
  /// cell is pinned to the middle of the board and the strip travels under
  /// it. Centre-lock is free: board cards already
  /// `ensureVisible(alignment: 0.5)`; the half-viewport pads below simply let
  /// the FIRST and LAST cell reach the middle too, which a plain list can't.
  Widget buildPromenadeBoard() {
    final context = _deps.context();
    final view = _stageSection.resolveStageRail();
    if (view == null) {
      return BrandLoadingStage(isTelevision: _deps.isTelevision());
    }
    _stageSection.seedStageFocusOnce();
    return buildHomePromenadeBoard(
      hostContext: context,
      view: view,
      media: () => _deps.media(),
      theater: () => _stageSection.canvasTheater,
      trailerActive: () => _heroPreview.heroTrailerActive,
      trailerShowing: _heroPreview.heroTrailerShowing,
      railBoxHeight: _stageGeometry.stageRailBoxH,
      favoriteWidth: _stageGeometry.stageFavW,
      cardAspect: () =>
          _stageGeometry.stageCardAspect(view.rail, fallback: 16 / 9),
      favoriteCount: () =>
          _stageRailsSection.canvasFavItemCount(view.rail.favKind!),
      railTitle: () =>
          _stageRailsSection.canvasTabTitle(view.rails, view.index),
      favoriteBuilder: (_, col) =>
          _stageFavorites.canvasFavCell(view.rail.favKind!, view.key, col),
      itemBuilder: (_, col) => _stageCells.promenadeCell(
        view.rail,
        view.key,
        view.items,
        view.nodes,
        col,
      ),
    );
  }

  /// MOSAIC: no hero at all. The active rail becomes a WALL of posters on a
  /// heavily veiled wash of the focused title's art, with the identity moved
  /// to a fixed top band. The cheapest layout on the list: one image, one
  /// flat veil, one grid — and no ambient video (see [_displaySection.stageWantsAmbient]),
  /// which is why it stays smooth on weak TV hardware.
  Widget buildMosaicBoard() {
    final context = _deps.context();
    final app = AppThemeScope.of(context);
    final view = _stageSection.resolveStageRail();
    if (view == null) {
      return BrandLoadingStage(isTelevision: _deps.isTelevision());
    }
    _stageSection.seedStageFocusOnce();
    final count = view.rail.favKind != null
        ? _stageRailsSection.canvasFavItemCount(view.rail.favKind!)
        : view.items.length;
    return buildHomeMosaicBoard(
      hostContext: context,
      view: view,
      itemCount: count,
      media: () => _deps.media(),
      trailerActive: () => _heroPreview.heroTrailerActive,
      trailerShowing: _heroPreview.heroTrailerShowing,
      cardAspect: () => _stageGeometry.stageCardAspect(view.rail),
      captionBandHeight: () => _displaySection.homeArtPosterCaptionBand,
      hintColor: app.fade(app.core.tx, 0.34),
      railTitle: () =>
          _stageRailsSection.canvasTabTitle(view.rails, view.index),
      itemBuilder: (col, perRow, cellWidth) => _stageCells.mosaicCell(
        view.rail,
        view.key,
        view.items,
        view.nodes,
        col,
        count,
        perRow,
        cellWidth,
      ),
    );
  }

  /// DECK: the trailer stops being wallpaper and becomes an OBJECT — a
  /// rounded 16:9 card floating on ink with the next two titles stacked
  /// behind it. The hole follows the card's laid-out rect (Canvas proved that
  /// needs no native work); the rounded corners are four ink wedges painted
  /// ABOVE the layers, because a clip would put a saveLayer over the hole.
  Widget buildDeckBoard() {
    final context = _deps.context();
    final app = AppThemeScope.of(context);
    final view = _stageSection.resolveStageRail();
    if (view == null) {
      return BrandLoadingStage(isTelevision: _deps.isTelevision());
    }
    _stageSection.seedStageFocusOnce();
    return buildHomeDeckBoard(
      hostContext: context,
      view: view,
      itemCount: view.rail.favKind != null
          ? _stageRailsSection.canvasFavItemCount(view.rail.favKind!)
          : view.items.length,
      media: () => _deps.media(),
      theater: () => _stageSection.canvasTheater,
      trailerActive: () => _heroPreview.heroTrailerActive,
      focusedColumn: _stageSection.stageCol,
      trailerShowing: _heroPreview.heroTrailerShowing,
      borderColor: app.fade(app.core.tx, 0.10),
      railBoxHeight: _stageGeometry.stageRailBoxH,
      labelHeight: atriumLabelHeight,
      labelGap: kAtriumLabelGap,
      favoriteWidth: _stageGeometry.stageFavW,
      cardAspect: () => _stageGeometry.stageCardAspect(view.rail),
      railTitle: () =>
          _stageRailsSection.canvasTabTitle(view.rails, view.index),
      favoriteBuilder: (_, col) =>
          _stageFavorites.canvasFavCell(view.rail.favKind!, view.key, col),
      itemBuilder: (_, col) => _stageCells.stageShelfCell(
        view.rail,
        view.key,
        view.items,
        view.nodes,
        col,
      ),
    );
  }
}
