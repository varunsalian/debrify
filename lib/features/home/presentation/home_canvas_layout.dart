import 'package:flutter/widgets.dart';
import 'home_stage_scrims.dart';

/// Gap between the tab row and the shelf below it.
const double _kCanvasTabsGap = 12;

/// Trailing spacer under the shelf, holding it off the screen edge.
const double _kCanvasShelfTail = 22;

/// Slack inside the shelf box, on top of the cell height — the cells centre
/// in it, so a focused card's scale-up isn't clipped at the box edges.
const double _kCanvasShelfSlack = 10;

/// Breathing room between the identity block's bottom and the tab row's top.
const double _kCanvasIdentityGap = 25;

/// Canvas geometry and theater transitions, composed from caller-owned surfaces.
/// The parent retains rail selection, card actions, focus and native ownership.
/// Returning the original tree keeps its native surfaces and shelf elements in
/// the same positions while the identity and shelf animate around them.
Widget buildHomeCanvasLayout({
  required double boardHeight,
  required double cardAspect,
  required double captionBand,
  required double tabsHeight,
  required bool theater,
  required Widget artwork,
  required Widget? trailer,
  required Widget? live,
  required Widget identity,
  required Widget tabs,
  required Widget Function(
    double cardHeight,
    double cardWidth,
    double favoriteWidth,
  )
  shelfBuilder,
}) {
  final boardH = boardHeight;
  final double cardH = (boardH * 0.30).clamp(150.0, 220.0);
  // Title cards follow the Home Cards orientation (full shelf height
  // either way — the same grammar as Promenade's strip); favourites
  // keep their portrait cell whatever the setting says.
  final cardW = cardH * cardAspect;
  final favCardW = cardH * 2 / 3;
  // ONE height for the whole bottom column, measured bottom-up, so the
  // identity block above can reserve exactly what the tabs and shelf
  // actually occupy — at any text scale, and whatever the shelf box
  // grows to next.
  final shelfBoxH = cardH + captionBand + _kCanvasShelfSlack;
  final shelfColumnH =
      _kCanvasShelfTail + shelfBoxH + _kCanvasTabsGap + tabsHeight;
  return Stack(
    fit: StackFit.expand,
    children: [
      // Stage floor + full-bleed key art. Sits BELOW the punch hole,
      // so the video replaces it in place when the trailer starts.
      // While a favourites cell has focus, the favourite's own art
      // overrides the hero pipeline's.
      artwork,
      // Full-bleed ambient trailer: same engine, whole-canvas region.
      if (trailer != null) trailer,
      // A focused IPTV favourite's live feed, full-bleed in the SAME
      // region — above the catalog trailer layer so it simply wins
      // whenever a channel has focus (shrinks to nothing otherwise),
      // exactly like the classic board's boxed version.
      if (live != null) live,
      // ONE scrim set painted above art AND video — identical in both
      // states so trailer start never swaps the lighting. Plain
      // gradient draws over the hole: the proven feather pattern. In
      // theater the BOTTOM ramp fades with the shelf it exists for.
      IgnorePointer(child: HomeStageScrims(theater: theater)),
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
              top: theater ? 36 : 0,
              bottom: theater ? 0 : shelfColumnH + _kCanvasIdentityGap,
            ),
            duration: theater
                ? const Duration(milliseconds: 900)
                : const Duration(milliseconds: 250),
            curve: Curves.easeInOutCubic,
            child: AnimatedAlign(
              alignment: theater ? Alignment.topLeft : Alignment.bottomLeft,
              duration: theater
                  ? const Duration(milliseconds: 900)
                  : const Duration(milliseconds: 250),
              curve: Curves.easeInOutCubic,
              child: AnimatedScale(
                scale: theater ? 0.7 : 1.0,
                alignment: Alignment.topLeft,
                duration: theater
                    ? const Duration(milliseconds: 900)
                    : const Duration(milliseconds: 250),
                curve: Curves.easeInOutCubic,
                // Favourites focus: the favourite's own name replaces
                // the hero identity (favourites aren't StremioMeta, so
                // the logo/meta pipeline has nothing true to say).
                // Notifier-driven, so a fav scrub repaints only this.
                child: identity,
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
          offset: theater ? const Offset(0, 0.12) : Offset.zero,
          duration: theater
              ? const Duration(milliseconds: 900)
              : const Duration(milliseconds: 250),
          curve: Curves.easeOut,
          child: AnimatedOpacity(
            opacity: theater ? 0.0 : 1.0,
            duration: theater
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
                  child: tabs,
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
                    child: shelfBuilder(cardH, cardW, favCardW),
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
}
