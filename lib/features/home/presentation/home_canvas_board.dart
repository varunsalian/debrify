import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'home_board_media.dart';
import 'home_canvas_layout.dart';
import 'home_canvas_shelf.dart';
import 'home_canvas_tabs.dart';
import 'home_favorite_focus.dart';
import 'home_stage_favorite_identity.dart';
import 'home_stage_identity.dart';
import 'home_stage_rows.dart';

/// Canvas's media stage, identity, tabs and active shelf. Cell actions/focus
/// remain with the host; the view borrows signals and captures rail identity.
Widget buildHomeCanvasBoard({
  required BuildContext hostContext,
  required HomeStageRailView view,
  required HomeBoardMedia Function() media,
  required bool Function() theater,
  required bool Function() trailerActive,
  required ValueListenable<bool> trailerShowing,
  required double Function() cardAspect,
  required double Function() captionBandHeight,
  required int Function() favoriteCount,
  required String Function(int) railTitle,
  required IndexedWidgetBuilder favoriteBuilder,
  required IndexedWidgetBuilder itemBuilder,
}) {
  final rails = view.rails;
  final railIndex = view.index;
  final railKey = view.key;
  final favRail = view.rail.favKind != null;
  final items = view.items;
  return LayoutBuilder(
    builder: (context, cons) {
      final surfaces = media();
      final boardH = cons.maxHeight;
      return buildHomeCanvasLayout(
        boardHeight: boardH,
        cardAspect: cardAspect(),
        captionBand: captionBandHeight(),
        tabsHeight: homeCanvasTabsHeight(context),
        theater: theater(),
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
              ? HomeStageFavoriteIdentity(fav: fav)
              : HomeStageIdentity(
                  item: surfaces.item,
                  enriched: surfaces.enriched,
                  trailerShowing: trailerShowing,
                ),
        ),
        tabs: buildHomeCanvasTabs(
          context: hostContext,
          railCount: rails.length,
          active: railIndex,
          titleAt: railTitle,
        ),
        shelfBuilder: (cardH, cardW, favCardW) => buildHomeCanvasShelf(
          railKey: railKey,
          itemCount: favRail ? favoriteCount() : items.length,
          cardWidth: favRail ? favCardW : cardW,
          cardHeight: favRail ? null : cardH,
          itemBuilder: (context, col) => favRail
              ? favoriteBuilder(context, col)
              : itemBuilder(context, col),
        ),
      );
    },
  );
}
