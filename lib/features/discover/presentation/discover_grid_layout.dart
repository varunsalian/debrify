import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../theme/app_theme_scope.dart';
import 'discover_grid_dim.dart';

/// Two-pane composition with borrowed widgets/signals; owns no data or players.
Widget buildDiscoverGridLayout(
  BuildContext context, {
  required BoxConstraints c,
  required Widget panel,
  required Widget detailRail,
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
  final railW = (c.maxWidth * 0.375).clamp(320.0, 460.0);
  final panelW = c.maxWidth - railW;
  final mq = MediaQuery.of(context);
  final twoPane = Row(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SizedBox(
        width: railW,
        // Theater: the identity block ghosts to 15% so the trailer owns
        // the art zone. AnimatedOpacity is acceptable here — the layer is
        // rail-sized (not full-screen), pays its saveLayer only during
        // the ~1.2s ease, and composites as a cached raster once settled.
        // It wraps a SIBLING of the video layer, so the underlay punch is
        // untouched. Lights-up is fast to match the veils' cadence.
        child: ValueListenableBuilder<bool>(
          valueListenable: theater,
          // RepaintBoundary: the rail rebuilds on every DPAD step (new
          // title, logo, plot) — keep that raster confined to the rail
          // column instead of dirtying the stage layer behind it.
          child: RepaintBoundary(child: detailRail),
          builder: (_, theater, child) => AnimatedOpacity(
            opacity: theater ? 0.15 : 1.0,
            duration: theater
                ? const Duration(milliseconds: 1200)
                : const Duration(milliseconds: 250),
            curve: Curves.easeInOutCubic,
            child: child,
          ),
        ),
      ),
      // The grid derives its column count from MediaQuery width; report
      // the panel's (narrower) width so it lays out for its real box
      // instead of the full screen and overflowing.
      SizedBox(
        width: panelW,
        // Theater: the grid itself ghosts to ~12% — fading the CONTENT is
        // the only way to unveil the trailer on this side (any ink wash
        // painted over the panel darkens the video with it, and the
        // opaque posters block it regardless). Same layer rules as the
        // rail's fade: sibling of the video layer (punch untouched),
        // saveLayer only during the ~1.2s ease, cached raster after.
        child: ValueListenableBuilder<bool>(
          valueListenable: theater,
          // RepaintBoundary: the filter line's focus pills repaint on
          // every DPAD move across it (the grid viewport below is its own
          // boundary already) — keep panel chrome out of the stage layer.
          child: RepaintBoundary(
            child: MediaQuery(
              data: mq.copyWith(size: Size(panelW, mq.size.height)),
              child: panel,
            ),
          ),
          builder: (_, theater, child) => AnimatedOpacity(
            opacity: theater ? 0.12 : 1.0,
            duration: theater
                ? const Duration(milliseconds: 1200)
                : const Duration(milliseconds: 250),
            curve: Curves.easeInOutCubic,
            child: child,
          ),
        ),
      ),
    ],
  );
  // The glass stage (bottom → top): base ink wash → the focused title's
  // full-frame backdrop → the ambient trailer (which replaces the still,
  // frame one, across the whole canvas) → the tint veils that keep both
  // panes legible (direct translucent paint — never an Opacity layer, and
  // safe over the underlay video's punched hole, exactly like the Home
  // hero's feathers) → the panes themselves → status chips.
  //
  // Layer discipline (the Home hero's): each stage stratum sits in its
  // own RepaintBoundary so a rail swap (every DPAD step) or a veil
  // transition frame re-rasters only itself. Without the boundaries they
  // all share one picture and every keypress re-records + re-rasters the
  // full-screen backdrop AND both veil gradients on the weak TV GPU —
  // the whole page reads as laggy. These are plain composited layers,
  // not saveLayers, so the underlay video's punch is unaffected.
  return Stack(
    fit: StackFit.expand,
    children: [
      DecoratedBox(decoration: BoxDecoration(gradient: app.home.wash)),
      RepaintBoundary(child: backdrop),
      trailer,
      RepaintBoundary(child: veils),
      twoPane,
      // Lights-off over the grid side while the trailer plays — the Home
      // rows' recede, transplanted. Above the panes (it dims the posters
      // and filter line), feathered on its left edge so no seam cuts the
      // stage. Animated as a baked color (direct paint), never Opacity.
      DiscoverGridDim(showing: showing, theater: theater, leftInset: railW),
      // Recede the two-pane as the trailer takes over — a baked scrim, not
      // an Opacity layer (whose mid-values force a per-frame full-screen
      // saveLayer on weak TV GPUs). Dormant while the takeover stays
      // disabled, kept wired for its revival.
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
      // Status corner: the Home hero's chip pair, handing over in place —
      // equalizer TRAILER pill while resolving/buffering, AMBIENT chip
      // once frames are up. Anchored bottom-left, in the rail column's
      // permanently-empty zone (the plot is capped at 6 lines, so the
      // identity block never reaches it) — the top-right corner belongs
      // to the filter line, which can wrap two rows on 5-segment sources.
      Positioned(
        bottom: 22,
        left: 24,
        child: ValueListenableBuilder<bool>(
          valueListenable: loading,
          builder: (_, loading, __) => loadingIndicator(loading),
        ),
      ),
      Positioned(
        bottom: 22,
        left: 24,
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
