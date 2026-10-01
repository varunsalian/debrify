import 'package:flutter/material.dart';

import '../../../models/stremio_addon.dart';
import '../../../theme/app_theme_scope.dart';
import '../../../utils/platform_util.dart';
import '../../../widgets/skeleton_poster.dart' show BrandLoadingStage;
import 'home_atrium_board.dart';
import 'home_atrium_row.dart';
import 'home_board_media.dart';
import 'home_display_section.dart';
import 'home_hero_preview.dart';
import 'home_stage_cells.dart';
import 'home_stage_favorites.dart';
import 'home_stage_geometry.dart';
import 'home_stage_rails.dart';
import 'home_stage_rows.dart';
import 'home_stage_section.dart';

typedef HomeAtriumSectionDeps = ({
  BuildContext Function() context,
  bool Function() isTelevision,
  HomeBoardMedia Function() media,
  bool Function() canAdvance,
  Future<bool> Function() loadMore,
});

/// Atrium's two-row wall composition and per-row directional dispatch.
class HomeAtriumSection {
  HomeAtriumSection(
    this._deps,
    this._stageSection,
    this._stageRailsSection,
    this._stageGeometry,
    this._stageCells,
    this._stageFavorites,
    this._displaySection,
    this._heroPreview,
  );
  final HomeAtriumSectionDeps _deps;
  final HomeStageSection _stageSection;
  final HomeStageRails _stageRailsSection;
  final HomeStageGeometry _stageGeometry;
  final HomeStageCells _stageCells;
  final HomeStageFavorites _stageFavorites;
  final HomeDisplaySection _displaySection;
  final HomeHeroPreview _heroPreview;

  /// ATRIUM: a hard vertical cut. Left is a flat ink column carrying the
  /// title's dossier and never taking focus; right is the art (and the
  /// trailer, in the same rect — the hole simply follows the layer's box)
  /// with a two-row poster wall standing on its lower half.
  Widget buildAtriumBoard() {
    final context = _deps.context();
    final app = AppThemeScope.of(context);
    final view = _stageSection.resolveStageRail();
    if (view == null) {
      return BrandLoadingStage(isTelevision: _deps.isTelevision());
    }
    _stageSection.seedStageFocusOnce();
    return buildHomeAtriumBoard(
      view: view,
      media: () => _deps.media(),
      trailerActive: () => _heroPreview.heroTrailerActive,
      focusedRailKey: _stageSection.atriumFocusedRailKey,
      trailerShowing: _heroPreview.heroTrailerShowing,
      panelColor: app.home.bg,
      seamColor: app.fade(app.core.tx, 0.09),
      labelHeight: atriumLabelHeight,
      labelGap: kAtriumLabelGap,
      minimumRowHeight: () =>
          _displaySection.homeArtPosterCaptionBand + kStageMinPosterH,
      railBoxHeight: _stageGeometry.stageRailBoxH,
      railKeyOf: _stageSection.canvasRailKeyOf,
      railTitle: (index) =>
          _stageRailsSection.canvasTabTitle(view.rails, index),
      rowBuilder: (index, height, {required isTopRow, required hasRowBelow}) =>
          atriumRow(
            view.rails,
            index,
            height,
            isTopRow: isTopRow,
            hasRowBelow: hasRowBelow,
          ),
    );
  }

  /// One row of Atrium's wall: a quiet rail label over a horizontal strip of
  /// the SAME cells every other board uses.
  Widget atriumRow(
    List<HomeRail> rails,
    int index,
    double rowBoxH, {
    required bool isTopRow,
    required bool hasRowBelow,
  }) {
    final context = _deps.context();
    final rail = rails[index];
    final railKey = _stageSection.canvasRailKeyOf(rail);
    final favRail = rail.favKind != null;
    final items = favRail
        ? const <StremioMeta>[]
        : _stageRailsSection.canvasRailItems(rail);
    final nodes = _stageRailsSection.canvasRailNodes(rail);
    final cardW = favRail
        ? _stageGeometry.stageFavW(context, rowBoxH)
        : rowBoxH * _stageGeometry.stageCardAspect(rail);
    final count = favRail
        ? _stageRailsSection.canvasFavItemCount(rail.favKind!)
        : items.length;

    // The window is [active, active+1]. From the top row UP leaves the
    // window; from the bottom row DOWN scrolls it on. Crossing between them
    // is a plain focus request.
    final onUp = isTopRow
        ? () => _stageSection.stageSwitchRail(-1)
        : () => _stageSection.atriumFocusRail(index - 1);
    final onDown = isTopRow
        ? (hasRowBelow
              ? () => _stageSection.atriumFocusRail(index + 1)
              : (rails.length > index + 1
                    // Only one row is drawn: DOWN scrolls the window on.
                    ? () => _stageSection.stageSwitchRail(1)
                    : () {
                        // No lower row YET — remember the move so focus drops into
                        // it when the batch lands, instead of eating the keypress.
                        if (_deps.canAdvance()) {
                          _stageSection.stageDeferredAdvance.defer(
                            railKey,
                            fillsLower: true,
                          );
                          _deps.loadMore();
                        }
                      }))
        : _stageSection.atriumAdvance;

    return buildHomeAtriumRow(
      context: context,
      title: _stageRailsSection.canvasTabTitle(rails, index),
      androidTv: PlatformUtil.isAndroidTvCached,
      labelGap: kAtriumLabelGap,
      rowHeight: rowBoxH,
      railKey: railKey,
      itemCount: count,
      itemBuilder: (context, col) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7),
        child: Center(
          child: SizedBox(
            width: cardW,
            child: favRail
                ? _stageFavorites.canvasFavCell(
                    rail.favKind!,
                    railKey,
                    col,
                    onUp: () {
                      _stageSection.atriumFocusedRailKey.value = railKey;
                      onUp();
                    },
                    onDown: () {
                      _stageSection.atriumFocusedRailKey.value = railKey;
                      onDown();
                    },
                  )
                : SizedBox(
                    height: rowBoxH,
                    child: _stageCells.stageCards.build(
                      rail: rail,
                      railKey: railKey,
                      item: items[col],
                      readActionItem: () => items[col],
                      nodes: nodes,
                      column: col,
                      onUp: onUp,
                      onDown: onDown,
                      onFocusedExtra: () =>
                          _stageSection.atriumFocusedRailKey.value = railKey,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
