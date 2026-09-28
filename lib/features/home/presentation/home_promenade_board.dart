import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'home_board_media.dart';
import 'home_favorite_focus.dart';
import 'home_promenade_layout.dart';
import 'home_stage_favorite_identity.dart';
import 'home_stage_identity.dart';
import 'home_stage_rail_label.dart';
import 'home_stage_rows.dart';

/// Promenade's stage, centered identity and strip. The selected rail is a
/// frame snapshot; live visual settings are read when LayoutBuilder rebuilds.
/// The caller retains focus seeding and card action ownership.
Widget buildHomePromenadeBoard({
  required BuildContext hostContext,
  required HomeStageRailView view,
  required HomeBoardMedia Function() media,
  required bool Function() theater,
  required bool Function() trailerActive,
  required ValueListenable<bool> trailerShowing,
  required double Function(BuildContext, double, {required double maxH})
  railBoxHeight,
  required double Function(BuildContext, double) favoriteWidth,
  required double Function() cardAspect,
  required int Function() favoriteCount,
  required String Function() railTitle,
  required IndexedWidgetBuilder favoriteBuilder,
  required IndexedWidgetBuilder itemBuilder,
}) {
  final rail = view.rail;
  final railKey = view.key;
  final favRail = rail.favKind != null;
  final items = view.items;
  return LayoutBuilder(
    builder: (context, cons) {
      final surfaces = media();
      final boardH = cons.maxHeight;
      final boardW = cons.maxWidth;
      // ONE box height for every rail kind; the kinds fill it differently
      // (see [favoriteWidth]) so neither wastes the other's space.
      final double stripBoxH = railBoxHeight(
        context,
        boardH * 0.27,
        maxH: boardH * 0.42,
      );
      final double cellW = favRail
          ? favoriteWidth(context, stripBoxH)
          : stripBoxH * cardAspect();
      final itemCount = favRail ? favoriteCount() : items.length;
      return buildHomePromenadeLayout(
        boardWidth: boardW,
        stripHeight: stripBoxH,
        cellWidth: cellW,
        labelHeight: homeStageRailLabelHeight(context),
        theater: theater(),
        railKey: railKey,
        itemCount: itemCount,
        artwork: surfaces.artwork(),
        trailer: trailerActive()
            ? surfaces.trailerLayer(boardH, fullBleed: true)
            : null,
        live: trailerActive()
            ? surfaces.liveLayer(boardH, fullBleed: true)
            : null,
        identity: ValueListenableBuilder<HomeFavoriteFocus?>(
          valueListenable: surfaces.favorite,
          builder: (context, fav, _) => fav != null
              ? HomeStageFavoriteIdentity(fav: fav, centered: true)
              : HomeStageIdentity(
                  item: surfaces.item,
                  enriched: surfaces.enriched,
                  trailerShowing: trailerShowing,
                  variant: HomeStageIdentityVariant.centered,
                  maxWidth: boardW - 96,
                ),
        ),
        label: buildHomeStageRailLabel(
          context: hostContext,
          title: railTitle(),
          railIndex: view.index,
          railCount: view.rails.length,
        ),
        itemBuilder: (context, col) => favRail
            ? favoriteBuilder(context, col)
            : SizedBox(height: stripBoxH, child: itemBuilder(context, col)),
      );
    },
  );
}
