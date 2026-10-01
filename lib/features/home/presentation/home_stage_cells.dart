import 'package:flutter/material.dart';

import '../../../models/stremio_addon.dart';
import 'home_catalog_item_actions.dart';
import 'home_continuation_menu.dart';
import 'home_hero_section.dart';
import 'home_mosaic_cell_navigation.dart';
import 'home_stage_cards.dart';
import 'home_stage_favorites.dart';
import 'home_stage_geometry.dart';
import 'home_stage_rows.dart';
import 'home_stage_section.dart';

/// Dim painted over every strip cell that isn't focused, so the centre-locked
/// cell reads as the lit one. A flat fill inside the card's own clip (see
/// [CardFocusRise.restVeil]) — no Opacity, no saveLayer.
const Color _kPromRestVeil = Color(0x8C0D0B1A);

typedef HomeStageCellsDeps = ({
  CatalogSection Function(int) sectionAt,
  HomeCatalogItemActions items,
  VoidCallback sidebar,
  Future<void> Function(int) loadMore,
});

/// Catalog cells and directional grammar shared by the stage layout builders.
class HomeStageCells {
  HomeStageCells(
    this._deps,
    this._stageGeometry,
    this._stageSection,
    this._stageFavorites,
    this._heroSection,
    this._continuationMenu,
  );
  final HomeStageCellsDeps _deps;
  final HomeStageGeometry _stageGeometry;
  final HomeStageSection _stageSection;
  final HomeStageFavorites _stageFavorites;
  final HomeHeroSection _heroSection;
  final HomeContinuationMenu _continuationMenu;

  late final stageCards = HomeStageCards(
    sectionAt: (index) => _deps.sectionAt(index),
    collectionFor: _stageGeometry.stageCollection,
    aspectOf: _stageGeometry.stageCardAspect,
    artOf: _stageGeometry.stageCardArt,
    items: _deps.items,
    openContinuationMenu: _continuationMenu.openCwCardMenu,
    onFocused: (railKey, item, column) {
      _heroSection.setHero(item);
      _stageSection.canvasCols[railKey] = column;
    },
    focusSidebar: _deps.sidebar,
    switchRail: _stageSection.stageSwitchRail,
    loadMore: _deps.loadMore,
  );

  Widget canvasCell(HomeStageRailView view, int col) {
    final rail = view.rail;
    final railKey = view.key;
    final items = view.items;
    final nodes = view.nodes;
    return stageCards.build(
      rail: rail,
      railKey: railKey,
      item: items[col],
      nodes: nodes,
      column: col,
    );
  }

  /// One wide strip cell — the SAME [HomeBoardCell] every board uses, in a 16:9
  /// box with derived landscape art, so hold-OK menus, quick-play, paging and
  /// the focus grammar are identical to Canvas's shelf.
  Widget promenadeCell(
    HomeRail rail,
    String railKey,
    List<StremioMeta> items,
    List<FocusNode> nodes,
    int col,
  ) {
    return stageCards.build(
      rail: rail,
      railKey: railKey,
      item: items[col],
      nodes: nodes,
      column: col,
      wide: true,
      restVeil: _kPromRestVeil,
    );
  }

  /// One wall cell. The grid overrides all four arrows: LEFT hands off to the
  /// sidebar only at a ROW edge (a grid's leftmost cell is not column 0, so
  /// the row grammar would leave the sidebar unreachable from every row but
  /// the first), and UP/DOWN step a whole row before falling through to rail
  /// switching.
  Widget mosaicCell(
    HomeRail rail,
    String railKey,
    List<StremioMeta> items,
    List<FocusNode> nodes,
    int col,
    int count,
    int perRow,
    double cellW,
  ) {
    final navigation = HomeMosaicCellNavigation(
      column: col,
      count: count,
      perRow: perRow,
      nodes: nodes,
      hold: _stageSection.stageHold,
      focusSidebar: _deps.sidebar,
      switchRail: _stageSection.stageSwitchRail,
      loadMore: rail.sectionIndex == null
          ? null
          : () => _deps.loadMore(rail.sectionIndex!),
      deferRight: () => _stageSection.stageDeferredRight.defer(railKey, col),
    );

    if (rail.favKind != null) {
      return _stageFavorites.canvasFavCell(
        rail.favKind!,
        railKey,
        col,
        onUp: navigation.up,
        onDown: navigation.down,
        onLeft: navigation.left,
        onRight: navigation.right,
        onUpHold: navigation.upHold,
        onDownHold: navigation.downHold,
      );
    }
    return SizedBox(
      height: cellW / _stageGeometry.stageCardAspect(rail),
      child: stageCards.build(
        rail: rail,
        railKey: railKey,
        item: items[col],
        nodes: nodes,
        column: col,
        pageNearEnd: false,
        onUp: navigation.up,
        onDown: navigation.down,
        onUpHold: navigation.upHold,
        onDownHold: navigation.downHold,
        onLeft: navigation.left,
        onRight: navigation.right,
      ),
    );
  }

  /// The shared poster shelf cell (Canvas grammar: L/R along the rail, U/D
  /// switches rails) — used by Deck and Tonight's bottom strip.
  Widget stageShelfCell(
    HomeRail rail,
    String railKey,
    List<StremioMeta> items,
    List<FocusNode> nodes,
    int col, {
    VoidCallback? onUp,
    VoidCallback? onDown,
    VoidCallback? onUpHold,
    VoidCallback? onDownHold,
    VoidCallback? onFocusedExtra,
  }) {
    return stageCards.build(
      rail: rail,
      railKey: railKey,
      item: items[col],
      nodes: nodes,
      column: col,
      onUp: onUp,
      onDown: onDown,
      onUpHold: onUpHold,
      onDownHold: onDownHold,
      onFocusedExtra: () {
        _stageSection.stageCol.value = col;
        onFocusedExtra?.call();
      },
    );
  }
}
