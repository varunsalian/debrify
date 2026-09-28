import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'home_board_media.dart';
import 'home_favorite_focus.dart';
import 'home_mosaic_layout.dart';
import 'home_stage_favorite_identity.dart';
import 'home_stage_identity.dart';
import 'home_stage_rail_label.dart';
import 'home_stage_rows.dart';

/// Mosaic's poster wall and fixed identity band. Grid geometry is passed to
/// the host's cell navigation, preserving its row-edge and paging behavior.
Widget buildHomeMosaicBoard({
  required BuildContext hostContext,
  required HomeStageRailView view,
  required int itemCount,
  required HomeBoardMedia Function() media,
  required bool Function() trailerActive,
  required ValueListenable<bool> trailerShowing,
  required double Function() cardAspect,
  required double Function() captionBandHeight,
  required Color hintColor,
  required String Function() railTitle,
  required Widget Function(int column, int perRow, double cellWidth)
  itemBuilder,
}) {
  final railKey = view.key;
  final favRail = view.rail.favKind != null;
  final count = itemCount;
  return LayoutBuilder(
    builder: (context, cons) {
      final surfaces = media();
      final boardW = cons.maxWidth;
      final boardH = cons.maxHeight;
      final geometry = HomeMosaicGeometry(
        boardW: boardW,
        boardH: boardH,
        cellAspect: favRail ? 2 / 3 : cardAspect(),
        captionBandHeight: favRail ? captionBandHeight() : 0,
      );
      return buildHomeMosaicLayout(
        context: context,
        geometry: geometry,
        railKey: railKey,
        itemCount: count,
        liveChannel: surfaces.liveChannel,
        showRailHint: view.rails.length > 1,
        hintColor: hintColor,
        artwork: surfaces.artwork(),
        liveSurface: trailerActive()
            ? surfaces.liveLayer(boardH, fullBleed: true)
            : null,
        identity: ValueListenableBuilder<HomeFavoriteFocus?>(
          valueListenable: surfaces.favorite,
          builder: (context, fav, _) => Align(
            alignment: Alignment.bottomLeft,
            child: fav != null
                ? HomeStageFavoriteIdentity(fav: fav)
                : HomeStageIdentity(
                    item: surfaces.item,
                    enriched: surfaces.enriched,
                    trailerShowing: trailerShowing,
                    variant: HomeStageIdentityVariant.headline,
                    maxWidth: max(1.0, geometry.gridW * 0.5),
                  ),
          ),
        ),
        railLabel: buildHomeStageRailLabel(
          context: hostContext,
          title: railTitle(),
          railIndex: view.index,
          railCount: view.rails.length,
          align: MainAxisAlignment.end,
        ),
        itemBuilder: (context, col) =>
            itemBuilder(col, geometry.perRow, geometry.cellW),
      );
    },
  );
}
