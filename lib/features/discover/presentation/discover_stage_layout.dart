import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../theme/app_theme_scope.dart';
import '../../../widgets/see_all/discover_shelf_scope.dart';

/// Discover STAGE: the air between the identity block and the shelf column
/// below it. The block's clearance is [DiscoverShelfMetrics.columnHeight] plus
/// this — derived from what the shelf actually occupies, never guessed.
const double _kDiscStageIdentityGap = 22;

/// Discover STAGE: the band the quiet filter line owns at the top of the
/// panel — its 16px top padding, one line of segments and its 10px tail,
/// measuring ~56, plus a little air. It never needs a second row: the quiet
/// bar scrolls its segments horizontally rather than wrapping.
const double _kDiscStageFilterBand = 62;

/// Stage composition with borrowed visual slots and signals. Identity geometry
/// is fixed for each canvas size, independently of the theater animation.
Widget buildDiscoverStageLayout(
  BuildContext context, {
  required BoxConstraints constraints,
  required Widget panel,
  required Widget Function(double maxWidth, double budget) buildIdentity,
  required Widget backdrop,
  required Widget trailer,
  required Widget veils,
  required ValueListenable<bool> theater,
  required ValueListenable<bool> showing,
  required ValueListenable<bool> loading,
  required ValueListenable<double> takeover,
  required Widget Function(bool visible) loadingIndicator,
  required Widget Function(bool visible) ambientIndicator,
}) {
  final app = AppThemeScope.of(context);
  // Canvas's poster proportion (30% of the board, clamped) so the two
  // full-bleed shelves on this TV read as the same furniture.
  final cardH = (constraints.maxHeight * 0.30).clamp(140.0, 200.0);
  final metrics = DiscoverShelfMetrics(cardHeight: cardH, hPad: 24);
  // The identity block never crosses the middle of the frame — the art on
  // the right half is the point of this layout.
  final identityMax = (constraints.maxWidth * 0.5).clamp(320.0, 560.0);
  // What the identity block may occupy while BROWSING: the canvas less the
  // filter band above and the shelf column below. Computed here and handed
  // down, because theater animates that box open — a block that measured
  // its live constraint would gain a plot line mid-glide and jump.
  final identityBudget =
      constraints.maxHeight -
      _kDiscStageFilterBand -
      (metrics.columnHeight + _kDiscStageIdentityGap);
  return Stack(
    fit: StackFit.expand,
    children: [
      DecoratedBox(decoration: BoxDecoration(gradient: app.home.wash)),
      RepaintBoundary(child: backdrop),
      trailer,
      RepaintBoundary(child: veils),
      // The identity block, bottom-left, clearing exactly what the shelf
      // column below occupies — derived from the same metrics the shelf lays
      // itself out with, never guessed.
      //
      // THEATER: the block glides to the top-left and shrinks — the Canvas
      // board's billboard move, so a clean full-bleed trailer still carries
      // a quiet signature. What actually travels is the title art alone:
      // meta and plot faded out earlier, with [showing], inside
      // the rail widget. Padding/Align/Scale animate on ONE cadence (slow
      // lights-down, instant lights-up) — three transforms and a layout
      // inset, no repaint of the stage under them.
      Positioned.fill(
        child: IgnorePointer(
          child: ValueListenableBuilder<bool>(
            valueListenable: theater,
            child: RepaintBoundary(
              child: buildIdentity(identityMax, identityBudget),
            ),
            builder: (_, deep, kid) => AnimatedPadding(
              // Browse — top: the filter line's band, so a short canvas
              // makes the block shed its plot rather than grow up under the
              // filters; bottom: exactly what the shelf column occupies.
              // Theater — the block rides up to the top corner instead.
              padding: EdgeInsets.only(
                top: deep ? 30 : _kDiscStageFilterBand,
                bottom: deep
                    ? 0
                    : metrics.columnHeight + _kDiscStageIdentityGap,
              ),
              duration: deep
                  ? const Duration(milliseconds: 900)
                  : const Duration(milliseconds: 250),
              curve: Curves.easeInOutCubic,
              child: AnimatedAlign(
                alignment: deep ? Alignment.topLeft : Alignment.bottomLeft,
                duration: deep
                    ? const Duration(milliseconds: 900)
                    : const Duration(milliseconds: 250),
                curve: Curves.easeInOutCubic,
                child: AnimatedScale(
                  scale: deep ? 0.7 : 1.0,
                  alignment: Alignment.topLeft,
                  duration: deep
                      ? const Duration(milliseconds: 900)
                      : const Duration(milliseconds: 250),
                  curve: Curves.easeInOutCubic,
                  child: kid,
                ),
              ),
            ),
          ),
        ),
      ),
      // Filter line + shelf. Theater recede: the Canvas cadence — slow
      // lights-down, instant lights-up — as a slide + fade. The children
      // stay MOUNTED (opacity only), so DPAD focus survives the dark and the
      // wake keypress still performs its normal move. This is the one
      // full-canvas Opacity on the page; it pays its saveLayer during the
      // ease and composites as a cached raster at rest, exactly like the
      // two-pane's panel fade it replaces.
      Positioned.fill(
        child: ValueListenableBuilder<bool>(
          valueListenable: theater,
          child: RepaintBoundary(
            child: DiscoverShelfScope(metrics: metrics, child: panel),
          ),
          builder: (_, deep, kid) => AnimatedSlide(
            offset: deep ? const Offset(0, 0.12) : Offset.zero,
            duration: deep
                ? const Duration(milliseconds: 900)
                : const Duration(milliseconds: 250),
            curve: Curves.easeOut,
            child: AnimatedOpacity(
              opacity: deep ? 0.0 : 1.0,
              duration: deep
                  ? const Duration(milliseconds: 900)
                  : const Duration(milliseconds: 250),
              curve: Curves.easeOut,
              child: kid,
            ),
          ),
        ),
      ),
      // Recede everything as the trailer promotes to a fullscreen takeover —
      // a baked scrim, never an Opacity layer. Dormant while the takeover
      // stays disabled, kept wired for its revival (as in the two-pane).
      ValueListenableBuilder<double>(
        valueListenable: takeover,
        builder: (_, t, __) => t <= 0.001
            ? const SizedBox.shrink()
            : IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: app.fade(app.home.bg, 0.92 * t),
                  ),
                ),
              ),
      ),
      // Status corner: the same TRAILER→AMBIENT chip pair the two-pane
      // shows, moved to the TOP-right — the bottom-left corner belongs to
      // the identity block here.
      Positioned(
        top: 16,
        right: 22,
        child: ValueListenableBuilder<bool>(
          valueListenable: loading,
          builder: (_, loading, __) => loadingIndicator(loading),
        ),
      ),
      Positioned(
        top: 16,
        right: 22,
        child: ValueListenableBuilder<bool>(
          valueListenable: showing,
          builder: (_, showing, __) => ValueListenableBuilder<bool>(
            valueListenable: loading,
            builder: (_, loading, __) => ambientIndicator(showing && !loading),
          ),
        ),
      ),
    ],
  );
}
