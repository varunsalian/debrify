import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'home_board_media.dart';
import 'home_deck_layout.dart';
import 'home_deck_peeks.dart';
import 'home_favorite_focus.dart';
import 'home_stage_favorite_identity.dart';
import 'home_stage_identity.dart';
import 'home_stage_row_label.dart';
import 'home_stage_rows.dart';

/// Deck's floating media card, peeks, identity and poster strip. Layout owns
/// geometry; the host supplies borrowed signals and current card actions.
Widget buildHomeDeckBoard({
  required BuildContext hostContext,
  required HomeStageRailView view,
  required int itemCount,
  required HomeBoardMedia Function() media,
  required bool Function() theater,
  required bool Function() trailerActive,
  required ValueListenable<int> focusedColumn,
  required ValueListenable<bool> trailerShowing,
  required Color borderColor,
  required double Function(BuildContext, double, {required double maxH})
  railBoxHeight,
  required double Function(BuildContext) labelHeight,
  required double labelGap,
  required double Function(BuildContext, double) favoriteWidth,
  required double Function() cardAspect,
  required String Function() railTitle,
  required IndexedWidgetBuilder favoriteBuilder,
  required IndexedWidgetBuilder itemBuilder,
}) {
  final railKey = view.key;
  final favRail = view.rail.favKind != null;
  final items = view.items;
  final count = itemCount;
  return LayoutBuilder(
    builder: (context, cons) {
      final surfaces = media();
      final boardW = cons.maxWidth;
      final boardH = cons.maxHeight;
      // RESERVE THE RAIL FIRST, then let the card have what is left — the
      // other way round, a tall card on a short board silently pushes the
      // rail off the bottom edge.
      final railBoxH = railBoxHeight(
        context,
        boardH * 0.24,
        maxH: boardH * 0.34,
      );
      final geometry = HomeDeckGeometry(
        boardW: boardW,
        boardH: boardH,
        railBoxH: railBoxH,
        labelHeight: labelHeight(context),
        labelGap: labelGap,
      );
      return buildHomeDeckLayout(
        geometry: geometry,
        theater: theater(),
        railKey: railKey,
        itemCount: count,
        borderColor: borderColor,
        peeks: ValueListenableBuilder<int>(
          valueListenable: focusedColumn,
          builder: (context, focusedCol, _) => Stack(
            children: buildHomeDeckPeeks(
              items: items,
              favRail: favRail,
              focused: focusedCol,
              left: geometry.cardLeft,
              top: geometry.cardTop,
              width: geometry.cardW,
              height: geometry.cardH,
            ),
          ),
        ),
        artwork: surfaces.artwork(),
        trailer: trailerActive()
            ? surfaces.trailerLayer(geometry.cardH, fullBleed: true)
            : null,
        live: trailerActive()
            ? surfaces.liveLayer(geometry.cardH, fullBleed: true)
            : null,
        identity: ValueListenableBuilder<HomeFavoriteFocus?>(
          valueListenable: surfaces.favorite,
          builder: (context, fav, _) => fav != null
              ? HomeStageFavoriteIdentity(fav: fav)
              : HomeStageIdentity(
                  item: surfaces.item,
                  enriched: surfaces.enriched,
                  trailerShowing: trailerShowing,
                  variant:
                      boardH - geometry.railZoneH >=
                          homeStageNarrowIdentityHeight(context)
                      ? HomeStageIdentityVariant.narrow
                      : HomeStageIdentityVariant.headline,
                  maxWidth: geometry.identityWidth,
                ),
        ),
        railLabel: buildHomeStageRowLabel(
          context: hostContext,
          title: railTitle(),
        ),
        itemBuilder: (context, col) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 7),
          child: Center(
            child: SizedBox(
              width: favRail
                  ? favoriteWidth(context, railBoxH)
                  : railBoxH * cardAspect(),
              child: favRail
                  ? favoriteBuilder(context, col)
                  : SizedBox(
                      height: railBoxH,
                      child: itemBuilder(context, col),
                    ),
            ),
          ),
        ),
      );
    },
  );
}
