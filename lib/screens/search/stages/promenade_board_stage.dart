import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../../models/stremio_addon.dart';
import '../../../theme/app_theme_scope.dart';
import '../../../widgets/skeleton_poster.dart';
import '../fav_row_ref.dart';
import '../search_board_runtime.dart';
import '../stage_visuals.dart';
import 'canvas_board_stage.dart' show canvasTabChevronColumn;

typedef PromenadeStageBindings = ({
  StageRailView? Function() resolveRail,
  VoidCallback seedFocus,
  int Function(FavRowRef) favouriteCount,
  bool Function() readTheater,
  bool Function() readTrailerActive,
  int Function() cacheWidth,
  int Function() cacheHeight,
  ValueListenable<StremioMeta?> heroItem,
  ValueListenable<StremioMeta?> enriched,
  ValueListenable<CanvasFavFocus?> favourite,
  ValueListenable<bool> trailerShowing,
  Widget Function(double) buildTrailer,
  Widget Function(double) buildLive,
  Widget Function(bool) buildScrims,
  double Function(BuildContext, double, {required double maxH}) railBoxHeight,
  double Function(BuildContext, double) favouriteWidth,
  String Function(StageRailView) readTitle,
  Widget Function(FavRowRef, String, int) favouriteCell,
  Widget Function(CanvasRail, String, List<StremioMeta>, List<FocusNode>, int) cell,
});

// Metrics for the PROMENADE bottom column (centred rail label + strip). Same
// single-source-of-truth contract as the shared Canvas metric: the widgets and
// the identity block that must stay clear of them read the same numbers.
const double _kPromLabelFontSize = 12.0;

/// Height of Promenade's centred label row at the current text scale (the
/// chevron column is the floor, exactly as in [canvasTabChevronColumn]).
double _promenadeLabelHeight(BuildContext context) => max(
  canvasTabChevronColumn,
  MediaQuery.textScalerOf(context).scale(_kPromLabelFontSize) * 1.35,
);

/// Promenade's centred rail label. The stacked chevron pair is the same
/// affordance Canvas's tabs carry, and for the same reason: UP/DOWN is what
/// changes rails, and nothing else on this screen says so.
Widget buildPromenadeRailLabel(
  BuildContext context,
  StageRailView view, {
  required String Function(StageRailView) readTitle,
  MainAxisAlignment align = MainAxisAlignment.center,
}) {
  final app = AppThemeScope.of(context);
  final title = readTitle(view);
  return Row(
    mainAxisAlignment: align,
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.keyboard_arrow_up_rounded,
            size: 13,
            color: app.fade(app.core.tx, 0.45),
          ),
          Transform.translate(
            offset: const Offset(0, -5),
            child: Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 13,
              color: app.fade(app.core.tx, 0.45),
            ),
          ),
        ],
      ),
      const SizedBox(width: 12),
      Flexible(
        child: Text(
          title.toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: _kPromLabelFontSize,
            fontWeight: FontWeight.w800,
            letterSpacing: 2.4,
            color: app.fade(app.core.tx, 0.82),
          ),
        ),
      ),
      if (view.rails.length > 1) ...[
        const SizedBox(width: 14),
        // Flexible as well as the title: on a narrow header (Mosaic shares
        // its row with the identity) a rigid counter is what tips the Row
        // into an overflow.
        Flexible(
          child: Text(
            '${view.index + 1}/${view.rails.length}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: _kPromLabelFontSize,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: app.fade(app.core.tx, 0.32),
            ),
          ),
        ),
      ],
    ],
  );
}


/// Gap between the centred rail label and the strip below it.
const double _kPromLabelGap = 14;

/// Trailing spacer under the strip.
const double _kPromStripTail = 24;

/// Air between the identity block and the label row under it.
const double _kPromIdentityGap = 26;

class PromenadeStage extends StatelessWidget {
  const PromenadeStage({super.key, required this.bindings, required this.isTelevision});
  final PromenadeStageBindings bindings;
  final bool isTelevision;

  // ── PROMENADE view ───────────────────────────────────────────────────────

  /// PROMENADE: Canvas's stage, symmetric. The identity sits centred in the
  /// lower third and the rail becomes a CENTRE-LOCKED strip — the focused
  /// cell is pinned to the middle of the board and the strip travels under
  /// it. Centre-lock is free: board cards already
  /// `ensureVisible(alignment: 0.5)`; the half-viewport pads below simply let
  /// the FIRST and LAST cell reach the middle too, which a plain list can't.
  @override
  Widget build(BuildContext context) {
    final view = bindings.resolveRail();
    if (view == null) {
      return BrandLoadingStage(isTelevision: isTelevision);
    }
    final rail = view.rail;
    final railKey = view.key;
    final favRail = rail.favKind != null;
    final items = view.items;
    final nodes = view.nodes;
    bindings.seedFocus();

    return LayoutBuilder(
      builder: (context, cons) {
        final boardH = cons.maxHeight;
        final boardW = cons.maxWidth;
        // ONE box height for every rail kind; the kinds fill it differently
        // (see [bindings.favouriteWidth]) so neither wastes the other's space.
        final double stripBoxH = bindings.railBoxHeight(
          context,
          boardH * 0.27,
          maxH: boardH * 0.42,
        );
        final double cellW = favRail
            ? bindings.favouriteWidth(context, stripBoxH)
            : stripBoxH * 16 / 9;
        // Measured bottom-up, exactly like Canvas's shelfColumnH, so the
        // identity's clearance is DERIVED and can never drift into the strip.
        final columnH =
            _kPromStripTail +
            stripBoxH +
            _kPromLabelGap +
            _promenadeLabelHeight(context);
        // Half-viewport pads: without them the list clamps at its ends and
        // the first/last cell can never reach the centre lock.
        final double sidePad = ((boardW - cellW) / 2).clamp(0.0, boardW / 2);
        final itemCount = favRail
            ? bindings.favouriteCount(rail.favKind!)
            : items.length;

        return Stack(
          fit: StackFit.expand,
          children: [
            // Stage floor + full-bleed key art, BELOW the punch hole so the
            // video replaces it in place when the trailer starts.
            CanvasArtLayer(
              item: bindings.heroItem,
              enriched: bindings.enriched,
              fav: bindings.favourite,
              cacheWidth: bindings.cacheWidth(),
              cacheHeight: bindings.cacheHeight(),
            ),
            if (bindings.readTrailerActive())
              bindings.buildTrailer(boardH),
            if (bindings.readTrailerActive())
              bindings.buildLive(boardH),
            IgnorePointer(
              child: bindings.buildScrims(bindings.readTheater()),
            ),
            // Centred identity — which glides to the TOP-LEFT in theater, the
            // Netflix billboard move Canvas already makes. A logo parked in
            // the middle of a clean full-screen trailer reads as something
            // left behind; in the corner it reads as a signature. Meta and
            // synopsis have already faded by then (they go with
            // trailerShowing, before the dwell), so what travels is the logo.
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedPadding(
                  padding: EdgeInsets.only(
                    left: 48,
                    right: 48,
                    top: bindings.readTheater() ? 36 : 0,
                    bottom: bindings.readTheater() ? 0 : columnH + _kPromIdentityGap,
                  ),
                  duration: bindings.readTheater()
                      ? const Duration(milliseconds: 900)
                      : const Duration(milliseconds: 250),
                  curve: Curves.easeInOutCubic,
                  child: AnimatedAlign(
                    alignment: bindings.readTheater()
                        ? Alignment.topLeft
                        : Alignment.bottomCenter,
                    duration: bindings.readTheater()
                        ? const Duration(milliseconds: 900)
                        : const Duration(milliseconds: 250),
                    curve: Curves.easeInOutCubic,
                    child: AnimatedScale(
                      scale: bindings.readTheater() ? 0.7 : 1.0,
                      alignment: Alignment.topLeft,
                      duration: bindings.readTheater()
                          ? const Duration(milliseconds: 900)
                          : const Duration(milliseconds: 250),
                      curve: Curves.easeInOutCubic,
                      child: ValueListenableBuilder<CanvasFavFocus?>(
                        valueListenable: bindings.favourite,
                        builder: (context, fav, _) => fav != null
                            ? StageFavIdentity(fav: fav, centered: true)
                            : CanvasIdentity(
                                item: bindings.heroItem,
                                enriched: bindings.enriched,
                                trailerShowing: bindings.trailerShowing,
                                variant: StageIdentityVariant.centered,
                                maxWidth: boardW - 96,
                              ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // Rail label + the strip. Theater recede: slide + fade, cells stay
            // MOUNTED so focus survives and the wake keypress still moves.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: AnimatedSlide(
                offset: bindings.readTheater() ? const Offset(0, 0.12) : Offset.zero,
                duration: bindings.readTheater()
                    ? const Duration(milliseconds: 900)
                    : const Duration(milliseconds: 250),
                curve: Curves.easeOut,
                child: AnimatedOpacity(
                  opacity: bindings.readTheater() ? 0.0 : 1.0,
                  duration: bindings.readTheater()
                      ? const Duration(milliseconds: 900)
                      : const Duration(milliseconds: 250),
                  curve: Curves.easeOut,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(
                          left: 48,
                          right: 48,
                          bottom: _kPromLabelGap,
                        ),
                        child: buildPromenadeRailLabel(context, view, readTitle: bindings.readTitle),
                      ),
                      SizedBox(
                        height: stripBoxH,
                        child: ListView.builder(
                          // Keyed by rail IDENTITY: insertions above the
                          // active rail must never read as a content swap.
                          key: ValueKey('prom-rail-$railKey'),
                          scrollDirection: Axis.horizontal,
                          clipBehavior: Clip.hardEdge,
                          cacheExtent: 400,
                          padding: EdgeInsets.symmetric(horizontal: sidePad),
                          itemCount: itemCount,
                          itemBuilder: (context, col) => Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 7),
                            child: Center(
                              child: SizedBox(
                                width: cellW,
                                child: favRail
                                    ? bindings.favouriteCell(
                                        rail.favKind!,
                                        railKey,
                                        col,
                                      )
                                    : SizedBox(
                                        height: stripBoxH,
                                        child: bindings.cell(
                                          rail,
                                          railKey,
                                          items,
                                          nodes,
                                          col,
                                        ),
                                      ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: _kPromStripTail),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
