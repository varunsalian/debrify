import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../../models/stremio_addon.dart';
import '../../../theme/app_theme_scope.dart';
import '../../../widgets/skeleton_poster.dart';
import '../board_cell.dart';
import '../fav_row_ref.dart';
import '../search_board_runtime.dart';
import '../stage_visuals.dart';
import 'stage_shelf_content.dart';

typedef CanvasStageBindings = ({
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
  double Function() readCaptionBand,
  String Function(List<CanvasRail>, int) tabTitle,
  Widget Function(FavRowRef, String, int) favouriteCell,
  StageShelfContent shelf,
});

// Metrics for the Canvas bottom column (rail tabs + shelf). Same contract as
// the caption band above: the widgets and the identity block that has to stay
// CLEAR of them read the same numbers, so neither can drift into the other.
// (It drifted once: growing the shelf box by the caption band silently ate the
// identity's whole clearance and the tabs landed on the synopsis.)
const double _kCanvasTabFontSize = 12.5;
const double _kCanvasTabUnderlineGap = 6;
const double _kCanvasTabUnderline = 2.5;

/// Floor for the tab row: the stacked chevron pair beside the labels — two
/// 13px icons (the second is only translated, so it still occupies its line)
/// plus 1px of bottom padding.
const double canvasTabChevronColumn = 27;


/// Height of the Canvas rail-tab row at the current text scale.
double _canvasTabsHeight(BuildContext context) => max(
  canvasTabChevronColumn,
  MediaQuery.textScalerOf(context).scale(_kCanvasTabFontSize) * 1.35 +
      _kCanvasTabUnderlineGap +
      _kCanvasTabUnderline,
);

/// Gap between the tab row and the shelf below it.
const double _kCanvasTabsGap = 12;

/// Trailing spacer under the shelf, holding it off the screen edge.
const double _kCanvasShelfTail = 22;

/// Slack inside the shelf box, on top of the cell height — the cells centre
/// in it, so a focused card's scale-up isn't clipped at the box edges.
const double _kCanvasShelfSlack = 10;

/// Breathing room between the identity block's bottom and the tab row's top.
const double _kCanvasIdentityGap = 25;

class CanvasStage extends StatelessWidget {
  const CanvasStage({super.key, required this.bindings, required this.isTelevision});
  final CanvasStageBindings bindings;
  final bool isTelevision;

  /// Quiet rail-name tabs above the Canvas shelf — a window around the
  /// active rail (display only; UP/DOWN does the switching). The window is
  /// sized to what actually FITS: at some Screen Size settings the board is
  /// narrow enough that four capped labels + chevrons + the "+N more" tail
  /// would overflow the Row.
  Widget _canvasTabs(BuildContext context, List<CanvasRail> rails, int active) {
    final app = AppThemeScope.of(context);
    return LayoutBuilder(
      builder: (context, cons) {
        // Worst-case per-tab footprint: 170px label cap + 26px gap. Reserve
        // the chevron affordance (~25px) and the "+N more" tail (~92px).
        const perTab = 196.0;
        const reserved = 25.0 + 92.0;
        // May legitimately be ZERO: a narrow board (Mosaic's header shares its
        // width with the identity, and Screen Size can shrink the board) has
        // room for the chevrons and the "+N more" tail but not a label — and
        // an unflexible label there would overflow the Row.
        final maxTabs = (((cons.maxWidth - reserved) / perTab).floor()).clamp(
          0,
          4,
        );
        // Zero tabs fit: show no labels at all, but still say how many rails
        // there are (otherwise the row is a pair of chevrons with no context).
        // Leading CONTEXT (starting one rail early) only makes sense once there
        // is room for more than one label. With a single slot, starting at
        // `active - 1` put the ONLY visible label on the rail BEFORE the active
        // one — so the strip named a rail the board wasn't showing, and nothing
        // was styled active because `i == active` never matched. The window must
        // always contain the active rail.
        var start = switch (maxTabs) {
          0 => 0,
          1 => active,
          _ => active - 1,
        };
        if (maxTabs > 0 && start > rails.length - maxTabs) {
          start = rails.length - maxTabs;
        }
        if (start < 0) start = 0;
        var end = start + maxTabs;
        if (end > rails.length) end = rails.length;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // UP/DOWN affordance: a quiet stacked chevron pair in front of the
            // rail names — the one visual clue that vertical DPAD is what
            // switches them (they sit above the shelf, so nothing else says so).
            Padding(
              padding: const EdgeInsets.only(right: 12, bottom: 1),
              child: Column(
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
            ),
            for (var i = start; i < end; i++)
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.only(right: 26),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 170),
                        child: Text(
                          bindings.tabTitle(rails, i),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: _kCanvasTabFontSize,
                            fontWeight: i == active
                                ? FontWeight.w800
                                : FontWeight.w600,
                            letterSpacing: 0.3,
                            color: i == active
                                ? app.core.tx
                                : app.fade(app.core.tx, 0.5),
                          ),
                        ),
                      ),
                      const SizedBox(height: _kCanvasTabUnderlineGap),
                      Container(
                        height: _kCanvasTabUnderline,
                        width: 26,
                        decoration: BoxDecoration(
                          borderRadius: app.shape.br(2),
                          color: i == active ? app.core.tx : Colors.transparent,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (end < rails.length)
              Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: Text(
                  '+${rails.length - end} more',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: app.fade(app.core.tx, 0.24),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  /// The CANVAS home: full-bleed stage (idle art → ambient trailer via the
  /// same underlay engine, whose hole simply gets the whole canvas) with ONE
  /// shelf of large posters at the bottom and quiet rail tabs above it. No
  /// vertical scrolling, nothing clips at a fold, no row headers.
  @override
  Widget build(BuildContext context) {
    final view = bindings.resolveRail();
    if (view == null) {
      // First batch still streaming (or every loaded row is empty) — hold
      // the brand stage rather than an empty black canvas.
      return BrandLoadingStage(isTelevision: isTelevision);
    }
    final rails = view.rails;
    final railIndex = view.index;
    final rail = view.rail;
    final railKey = view.key;
    final bool favRail = rail.favKind != null;
    final items = view.items;
    final nodes = view.nodes;

    bindings.seedFocus();

    return LayoutBuilder(
      builder: (context, cons) {
        final boardH = cons.maxHeight;
        final double cardH = (boardH * 0.30).clamp(150.0, 220.0);
        // Title cards follow the Home Cards orientation (full shelf height
        // either way — the same grammar as Promenade's strip); favourites
        // keep their portrait cell whatever the setting says.
        final cardW = cardH * bindings.shelf.bindings.titleAspect();
        final favCardW = cardH * 2 / 3;
        // ONE height for the whole bottom column, measured bottom-up, so the
        // identity block above can reserve exactly what the tabs and shelf
        // actually occupy — at any text scale, and whatever the shelf box
        // grows to next.
        final shelfBoxH =
            cardH + bindings.readCaptionBand() + _kCanvasShelfSlack;
        final shelfColumnH =
            _kCanvasShelfTail +
            shelfBoxH +
            _kCanvasTabsGap +
            _canvasTabsHeight(context);
        return Stack(
          fit: StackFit.expand,
          children: [
            // Stage floor + full-bleed key art. Sits BELOW the punch hole,
            // so the video replaces it in place when the trailer starts.
            // While a favourites cell has focus, the favourite's own art
            // overrides the hero pipeline's.
            CanvasArtLayer(
              item: bindings.heroItem,
              enriched: bindings.enriched,
              fav: bindings.favourite,
              cacheWidth: bindings.cacheWidth(),
              cacheHeight: bindings.cacheHeight(),
            ),
            // Full-bleed ambient trailer: same engine, whole-canvas region.
            if (bindings.readTrailerActive())
              bindings.buildTrailer(boardH),
            // A focused IPTV favourite's live feed, full-bleed in the SAME
            // region — above the catalog trailer layer so it simply wins
            // whenever a channel has focus (shrinks to nothing otherwise),
            // exactly like the classic board's boxed version.
            if (bindings.readTrailerActive())
              bindings.buildLive(boardH),
            // ONE scrim set painted above art AND video — identical in both
            // states so trailer start never swaps the lighting. Plain
            // gradient draws over the hole: the proven feather pattern. In
            // theater the BOTTOM ramp fades with the shelf it exists for.
            IgnorePointer(child: bindings.buildScrims(bindings.readTheater())),
            // Identity (logo art + meta line), settle-driven like the hero.
            // THEATER: the logo glides to the top-left and shrinks — Netflix
            // billboard style — so the clean full-bleed video still carries a
            // quiet signature. Meta + synopsis are already faded by then
            // (they go with trailerShowing, before the dwell), so what
            // travels is effectively just the logo.
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedPadding(
                  padding: EdgeInsets.only(
                    left: 48,
                    right: 48,
                    top: bindings.readTheater() ? 36 : 0,
                    bottom: bindings.readTheater()
                        ? 0
                        : shelfColumnH + _kCanvasIdentityGap,
                  ),
                  duration: bindings.readTheater()
                      ? const Duration(milliseconds: 900)
                      : const Duration(milliseconds: 250),
                  curve: Curves.easeInOutCubic,
                  child: AnimatedAlign(
                    alignment: bindings.readTheater()
                        ? Alignment.topLeft
                        : Alignment.bottomLeft,
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
                      // Favourites focus: the favourite's own name replaces
                      // the hero identity (favourites aren't StremioMeta, so
                      // the logo/meta pipeline has nothing true to say).
                      // Notifier-driven, so a fav scrub repaints only this.
                      child: ValueListenableBuilder<CanvasFavFocus?>(
                        valueListenable: bindings.favourite,
                        builder: (context, fav, _) => fav != null
                            ? StageFavIdentity(fav: fav)
                            : CanvasIdentity(
                                item: bindings.heroItem,
                                enriched: bindings.enriched,
                                trailerShowing: bindings.trailerShowing,
                              ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // Rail tabs + the shelf. Theater recede: slide down a touch +
            // fade out (house cadence — slow lights-down, instant lights-up).
            // Opacity/slide only, cells stay MOUNTED: focus survives, and the
            // wake keypress still performs its normal move.
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
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(
                          left: 48,
                          right: 48,
                          bottom: _kCanvasTabsGap,
                        ),
                        child: _canvasTabs(context, rails, railIndex),
                      ),
                      SizedBox(
                        // ONE height for every rail (favourites cells carry a
                        // caption band; meta cells centre in the extra slack):
                        // a per-rail height made the tabs row jump ~45px on
                        // every fav↔meta switch and squeezed the outgoing fav
                        // list into a RenderFlex overflow mid-crossfade.
                        // Whatever this becomes, [shelfColumnH] measures it — the
                        // identity block's clearance is derived, never guessed.
                        height: shelfBoxH,
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeOutCubic,
                          child: favRail
                              ? ListView.builder(
                                  // Keyed by rail IDENTITY, like the meta shelf.
                                  key: ValueKey('canvas-rail-$railKey'),
                                  scrollDirection: Axis.horizontal,
                                  clipBehavior: Clip.hardEdge,
                                  cacheExtent: 400,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 48,
                                  ),
                                  itemCount: bindings.favouriteCount(rail.favKind!),
                                  itemBuilder: (context, col) => Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 7,
                                    ),
                                    // Centred like the meta cells: splits the
                                    // vertical slack so the focus scale's lift
                                    // isn't clipped at the viewport's top edge.
                                    child: Center(
                                      child: SizedBox(
                                        width: favCardW,
                                        child: bindings.favouriteCell(
                                          rail.favKind!,
                                          railKey,
                                          col,
                                        ),
                                      ),
                                    ),
                                  ),
                                )
                              : ListView.builder(
                                  // Keyed by rail IDENTITY: insertions above the active
                                  // rail must never read as a content swap.
                                  key: ValueKey('canvas-rail-$railKey'),
                                  scrollDirection: Axis.horizontal,
                                  clipBehavior: Clip.hardEdge,
                                  cacheExtent: 400,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 48,
                                  ),
                                  itemCount: items.length,
                                  itemBuilder: (context, col) {
                                    final item = items[col];
                                    return Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 7,
                                      ),
                                      child: Center(
                                        child: SizedBox(
                                          width: cardW,
                                          height: cardH,
                                          child: BoardCell(
                                            item: item,
                                            isTelevision: true,
                                            focusNode: nodes[col],
                                            column: col,
                                            rowNodes: nodes,
                                            hasBoundSource: bindings.shelf.bindings.isBound(item),
                                            // Canvas focus grammar: white ring (the
                                            // violet stays with classic chrome).
                                            ringColor: Colors.white,
                                            aspectRatio: bindings.shelf.bindings.titleAspect(),
                                            artUrl: bindings.shelf.bindings.titleArt(item),
                                            progress: rail.cw?.progressOf(item),
                                            episodeLabel: rail.cw?.episodeOf(
                                              item,
                                            ),
                                            onQuickPlay:
                                                rail.cw != null || bindings.shelf.bindings.pikpakOnly()
                                                ? null
                                                : () => bindings.shelf.bindings.quickPlay(
                                                    bindings.shelf.board.sections[rail
                                                        .sectionIndex!],
                                                    item,
                                                  ),
                                            onLongPress: rail.cw == null
                                                ? null
                                                : () => bindings.shelf.bindings.openCwMenu(
                                                    rail.cw!,
                                                    item,
                                                    rail.cwIndex,
                                                    col,
                                                  ),
                                            onFocused: () {
                                              bindings.shelf.bindings.setHero(item);
                                              bindings.shelf.columns[railKey] = col;
                                            },
                                            onUp: () => bindings.shelf.bindings.switchRail(-1),
                                            onDown: () => bindings.shelf.bindings.switchRail(1),
                                            onOpen: () {
                                              if (rail.cw != null) {
                                                rail.cw!.onOpen(item);
                                              } else {
                                                bindings.shelf.bindings.openItem(
                                                  bindings.shelf.board.sections[rail.sectionIndex!],
                                                  item,
                                                );
                                              }
                                            },
                                            onNearEnd: rail.sectionIndex == null
                                                ? null
                                                : () => bindings.shelf.board.loadMoreRow(
                                                    rail.sectionIndex!,
                                                  ),
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                        ),
                      ),
                      const SizedBox(height: _kCanvasShelfTail),
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
