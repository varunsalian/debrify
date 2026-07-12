import 'package:flutter/material.dart';

import 'see_all/see_all_poster_grid.dart';

/// A rounded shimmer placeholder box driven by a shared [animation] — a muted
/// fill with a soft highlight band sweeping left→right across it. Stateless so a
/// whole grid/row of them shares ONE controller (cheap on weak TV hardware).
///
/// The rounded corners come from the [BoxDecoration.borderRadius] rather than a
/// wrapping ClipRRect: a grid/rail of these is dozens of boxes, and a clip layer
/// per box repainted every frame is what made the skeleton janky on weak TV
/// GPUs. The decoration clips the gradient to the rounded shape with no layer.
class ShimmerBox extends StatelessWidget {
  final Animation<double> animation;
  final double radius;

  const ShimmerBox({super.key, required this.animation, this.radius = 10});

  @override
  Widget build(BuildContext context) {
    final br = BorderRadius.circular(radius);
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final t = animation.value;
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: br,
            gradient: LinearGradient(
              begin: Alignment(-1.6 + 3.2 * t, 0),
              end: Alignment(-0.4 + 3.2 * t, 0),
              colors: [
                Colors.white.withValues(alpha: 0.04),
                Colors.white.withValues(alpha: 0.10),
                Colors.white.withValues(alpha: 0.04),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// A loading placeholder for a See-All poster grid: shimmer poster cards laid
/// out through the SAME [SeeAllGridMetrics] the real [SeeAllPosterGrid] uses, so
/// when the items arrive they fill in place with no layout shift (the geometry
/// lives in one place, so the two can't drift). Non-interactive — no focus
/// nodes, no scroll — purely a nicer stand-in for a spinner. Owns a single
/// [AnimationController] shared by every cell.
class SkeletonPosterGrid extends StatefulWidget {
  final bool isTelevision;

  const SkeletonPosterGrid({super.key, required this.isTelevision});

  @override
  State<SkeletonPosterGrid> createState() => _SkeletonPosterGridState();
}

class _SkeletonPosterGridState extends State<SkeletonPosterGrid>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = SeeAllGridMetrics.resolve(
      context,
      isTelevision: widget.isTelevision,
    );
    return GridView.builder(
      padding: SeeAllGridMetrics.padding,
      // Fills the (bounded) body and clips the overflow — no scrolling a
      // placeholder. The parent is always height-bounded here: the real grid it
      // stands in for is a CustomScrollView, which would itself assert under an
      // unbounded parent. Over-count rows so tall panels never show a short grid.
      physics: const NeverScrollableScrollPhysics(),
      itemCount: m.columns * 6,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: m.columns,
        childAspectRatio: m.childWidth / m.cellHeight,
        mainAxisSpacing: SeeAllGridMetrics.rowGap,
        crossAxisSpacing: SeeAllGridMetrics.columnGap,
      ),
      itemBuilder: (context, index) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: ShimmerBox(animation: _controller)),
            const SizedBox(height: SeeAllGridMetrics.titleGap),
            // Two-line title placeholder. Expanded bars flex to fill exactly
            // [titleHeight], so they can never overflow the band at small text
            // scales (unlike fixed-height bars).
            SizedBox(
              height: m.titleHeight,
              child: Column(
                children: [
                  Expanded(child: ShimmerBox(animation: _controller, radius: 4)),
                  const SizedBox(height: 6),
                  Expanded(
                    child: FractionallySizedBox(
                      widthFactor: 0.6,
                      alignment: Alignment.centerLeft,
                      child: ShimmerBox(animation: _controller, radius: 4),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// A loading stand-in that MIRRORS the real home board so the swap is seamless
/// and uncluttered: an optional hero block on top (matching the TV spotlight),
/// then just a couple of rail placeholders — not a screenful of dense shimmer.
/// Non-interactive, non-scrolling; fills the (bounded) board area and clips.
/// One shared [AnimationController] drives every shimmer.
class SkeletonRailList extends StatefulWidget {
  /// Poster width for a rail cell, from the board's own `_railPosterW`.
  final double posterWidth;

  /// Matches the board's per-platform rail-header padding.
  final bool isTelevision;

  /// Reserve a hero-spotlight placeholder on top (TV home), matching where the
  /// real hero renders so it doesn't reflow when content arrives.
  final bool showHero;

  /// Height of that hero placeholder — the board's own computed `heroH`.
  final double heroHeight;

  final int rails;

  const SkeletonRailList({
    super.key,
    required this.posterWidth,
    required this.isTelevision,
    this.showHero = false,
    this.heroHeight = 0,
    this.rails = 3,
  });

  @override
  State<SkeletonRailList> createState() => _SkeletonRailListState();
}

class _SkeletonRailListState extends State<SkeletonRailList>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // A subtle full-bleed hero placeholder (matching the real spotlight, which is
  // edge-to-edge with hard corners) with a title + two description bars in the
  // lower-left, so the swap into the real hero doesn't shift or reflow.
  Widget _heroPlaceholder(bool tv) {
    return SizedBox(
      height: widget.heroHeight,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // radius 0 → matches the hard-edged, full-width hero backdrop.
          ShimmerBox(animation: _controller, radius: 0),
          Positioned(
            left: tv ? 40 : 20,
            bottom: tv ? 34 : 22,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: tv ? 300 : 200,
                  height: tv ? 28 : 22,
                  child: ShimmerBox(animation: _controller, radius: 7),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: tv ? 460 : 250,
                  height: 12,
                  child: ShimmerBox(animation: _controller, radius: 4),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: tv ? 380 : 200,
                  height: 12,
                  child: ShimmerBox(animation: _controller, radius: 4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _rail(bool tv, double posterW, double cellH, double rowH) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Title-bar placeholder, aligned to the real rail header's padding.
        Padding(
          padding: EdgeInsets.fromLTRB(24, tv ? 14 : 22, 24, tv ? 10 : 12),
          child: SizedBox(
            height: 16,
            width: 150,
            child: ShimmerBox(animation: _controller, radius: 6),
          ),
        ),
        SizedBox(
          height: rowH,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.hardEdge,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 13),
            itemCount: 8,
            itemBuilder: (context, j) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 11),
                child: Center(
                  child: SizedBox(
                    width: posterW,
                    height: cellH,
                    child: ShimmerBox(animation: _controller),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final tv = widget.isTelevision;
    final posterW = widget.posterWidth;
    final cellH = posterW * 3 / 2;
    final rowH = cellH + 14;
    // With a hero on top there's only room for ~2 rails below it — keep it that
    // restrained so the load reads as premium, not a wall of shimmer.
    final railCount = widget.showHero ? 2 : widget.rails;
    // One RepaintBoundary around the whole shimmer: the sweep repaints every
    // frame, and without this it would keep re-rasterising the backdrop gradient,
    // hero and sidebar behind it too. Isolated, only the skeleton's own layer
    // redraws.
    return RepaintBoundary(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.showHero && widget.heroHeight > 0) _heroPlaceholder(tv),
          // Rails fill the remaining bounded height and clip any overflow — no
          // scrolling a placeholder.
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(top: 6, bottom: 32),
              physics: const NeverScrollableScrollPhysics(),
              children: [
                for (int i = 0; i < railCount; i++)
                  _rail(tv, posterW, cellH, rowH),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
