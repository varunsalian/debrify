import 'package:flutter/widgets.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'home_stage_scrims.dart';

/// Gap between the centred rail label and the strip below it.
const double _kPromLabelGap = 14;

/// Trailing spacer under the strip.
const double _kPromStripTail = 24;

/// Air between the identity block and the label row under it.
const double _kPromIdentityGap = 26;

/// Promenade's centered identity and padded strip, with caller-owned surfaces.
/// The caller chooses the rail and its card dimensions, supplies cell actions,
/// and retains focus, metadata and playback lifetimes.
Widget buildHomePromenadeLayout({
  required double boardWidth,
  required double stripHeight,
  required double cellWidth,
  required double labelHeight,
  required bool theater,
  required String railKey,
  required int itemCount,
  required Widget artwork,
  required Widget? trailer,
  required Widget? live,
  required Widget identity,
  required Widget label,
  required IndexedWidgetBuilder itemBuilder,
}) {
  // Measured bottom-up, exactly like Canvas's shelfColumnH, so the
  // identity's clearance is DERIVED and can never drift into the strip.
  final columnH = _kPromStripTail + stripHeight + _kPromLabelGap + labelHeight;
  // Half-viewport pads: without them the list clamps at its ends and
  // the first/last cell can never reach the centre lock.
  final double sidePad = ((boardWidth - cellWidth) / 2).clamp(
    0.0,
    boardWidth / 2,
  );
  return Stack(
    fit: StackFit.expand,
    children: [
      // Stage floor + full-bleed key art, BELOW the punch hole so the
      // video replaces it in place when the trailer starts.
      artwork,
      if (trailer != null) trailer,
      if (live != null) live,
      IgnorePointer(
        child: HomeStageScrims(
          theater: theater,
          variant: HomeStageScrimVariant.centered,
        ),
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
              top: theater ? 36 : 0,
              bottom: theater ? 0 : columnH + _kPromIdentityGap,
            ),
            duration: theater
                ? const Duration(milliseconds: 900)
                : const Duration(milliseconds: 250),
            curve: Curves.easeInOutCubic,
            child: AnimatedAlign(
              alignment: theater ? Alignment.topLeft : Alignment.bottomCenter,
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
                child: identity,
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
              children: [
                Padding(
                  padding: const EdgeInsets.only(
                    left: 48,
                    right: 48,
                    bottom: _kPromLabelGap,
                  ),
                  child: label,
                ),
                SizedBox(
                  height: stripHeight,
                  child: ListView.builder(
                    // Keyed by rail IDENTITY: insertions above the
                    // active rail must never read as a content swap.
                    key: ValueKey('prom-rail-$railKey'),
                    scrollDirection: Axis.horizontal,
                    clipBehavior: Clip.hardEdge,
                    scrollCacheExtent: const ScrollCacheExtent.pixels(400),
                    padding: EdgeInsets.symmetric(horizontal: sidePad),
                    itemCount: itemCount,
                    itemBuilder: (context, col) => Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 7),
                      child: Center(
                        child: SizedBox(
                          width: cellWidth,
                          child: itemBuilder(context, col),
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
}
