import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import '../../../widgets/home/card_focus_rise.dart' show kCardFocusRing;
import 'home_atrium_layout.dart';
import 'home_board_media.dart';
import 'home_favorite_focus.dart';
import 'home_stage_favorite_identity.dart';
import 'home_stage_identity.dart';
import 'home_stage_rows.dart';

// Atrium's split and wall budget keep the dossier clear of the poster rows.
const double _kAtriumSplit = 0.38;

/// Scaled labels shrink the posters within this budget rather than pushing
/// the wall off the bottom of the board.
const double _kAtriumWallBudget = 0.64;

/// Atrium's dossier and adaptive two-row wall. The selected rails are captured
/// for this build; current focus labels and media use borrowed view signals.
Widget buildHomeAtriumBoard({
  required HomeStageRailView view,
  required HomeBoardMedia Function() media,
  required bool Function() trailerActive,
  required ValueListenable<String?> focusedRailKey,
  required ValueListenable<bool> trailerShowing,
  required Color panelColor,
  required Color seamColor,
  required double Function(BuildContext) labelHeight,
  required double labelGap,
  required double Function() minimumRowHeight,
  required double Function(BuildContext, double, {required double maxH})
  railBoxHeight,
  required String Function(HomeRail) railKeyOf,
  required String Function(int) railTitle,
  required Widget Function(
    int,
    double, {
    required bool isTopRow,
    required bool hasRowBelow,
  })
  rowBuilder,
}) {
  final rails = view.rails;
  final active = view.index;
  final hasSecondRow = active + 1 < rails.length;
  return LayoutBuilder(
    builder: (context, cons) {
      final surfaces = media();
      final boardH = cons.maxHeight;
      final boardW = cons.maxWidth;
      final double splitX = boardW * _kAtriumSplit;
      // ONE row height for every rail kind, filled two ways — reserving the
      // caption band on catalog rows too would cost 45px PER ROW here and
      // push the wall over three quarters of the art.
      //
      // The wall gets a BUDGET (a share of the board) and the row box is
      // derived from what fits inside it, so two scaled labels and a large
      // text scale can shrink the rows instead of running off the board.
      final labelH = labelHeight(context);
      // The wall gets a BUDGET. If two rows at the accessibility floor
      // (scaled caption + a recognisable poster) don't fit inside it, show
      // ONE row rather than two clipped ones — the second rail is still one
      // DOWN away.
      final floorH = minimumRowHeight();
      double chromeFor(int rows) =>
          rows * (labelH + labelGap) +
          (rows - 1) * homeAtriumRowGap +
          homeAtriumWallTail;
      final wallBudget = boardH * _kAtriumWallBudget;
      final twoRowsFit =
          hasSecondRow && wallBudget - chromeFor(2) >= floorH * 2;
      final showSecondRow = hasSecondRow && twoRowsFit;
      final rows = showSecondRow ? 2 : 1;
      final budget = wallBudget - chromeFor(rows);
      final rowBoxH = railBoxHeight(
        context,
        min(boardH * 0.22, budget / rows),
        maxH: max(budget / rows, floorH),
      );
      final rowUnit = labelH + labelGap + rowBoxH;
      final wallH =
          (showSecondRow ? rowUnit * 2 + homeAtriumRowGap : rowUnit) +
          homeAtriumWallTail;

      return buildHomeAtriumLayout(
        splitX: splitX,
        wallH: wallH,
        panelColor: panelColor,
        seamColor: seamColor,
        artwork: surfaces.artwork(),
        trailer: trailerActive()
            ? surfaces.trailerLayer(boardH, fullBleed: true)
            : null,
        live: trailerActive()
            ? surfaces.liveLayer(boardH, fullBleed: true)
            : null,
        railLabel: ValueListenableBuilder<String?>(
          valueListenable: focusedRailKey,
          builder: (context, key, _) {
            final i = key == null
                ? active
                : rails.indexWhere((r) => railKeyOf(r) == key);
            final title = railTitle(i < 0 ? active : i);
            return Text(
              title.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 2.6,
                color: kCardFocusRing,
              ),
            );
          },
        ),
        identity: ValueListenableBuilder<HomeFavoriteFocus?>(
          valueListenable: surfaces.favorite,
          builder: (context, fav, _) => fav != null
              ? HomeStageFavoriteIdentity(fav: fav)
              : HomeStageIdentity(
                  item: surfaces.item,
                  enriched: surfaces.enriched,
                  trailerShowing: trailerShowing,
                  // Drop the synopsis rather than clip it when
                  // the column is short (small board / large
                  // text scale).
                  variant:
                      boardH - 64 >= homeStageNarrowIdentityHeight(context) + 90
                      ? HomeStageIdentityVariant.narrow
                      : HomeStageIdentityVariant.headline,
                  maxWidth: (splitX - homeAtriumPanelPadding * 2).clamp(
                    120.0,
                    520.0,
                  ),
                ),
        ),
        topRow: rowBuilder(
          active,
          rowBoxH,
          isTopRow: true,
          hasRowBelow: showSecondRow,
        ),
        bottomRow: showSecondRow
            ? rowBuilder(
                active + 1,
                rowBoxH,
                isTopRow: false,
                hasRowBelow: false,
              )
            : null,
      );
    },
  );
}
