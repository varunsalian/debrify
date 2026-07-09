import 'package:flutter/material.dart';

import 'see_all/see_all_poster_grid.dart';

/// A rounded shimmer placeholder box driven by a shared [animation] — a muted
/// fill with a soft highlight band sweeping left→right across it. Stateless so a
/// whole grid/row of them shares ONE controller (cheap on weak TV hardware).
class ShimmerBox extends StatelessWidget {
  final Animation<double> animation;
  final double radius;

  const ShimmerBox({super.key, required this.animation, this.radius = 10});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, _) {
          final t = animation.value;
          return DecoratedBox(
            decoration: BoxDecoration(
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
      ),
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
