import 'dart:async';

import 'package:flutter/material.dart';

import 'see_all/see_all_poster_grid.dart';

/// Keeps its child perfectly still for [delay], then starts a slow whole-layer
/// opacity breathe so a long load doesn't read as a frozen app.
///
/// The delay is the point: during the first moments of a load the CPU is busy
/// fetching/parsing and ANY animation judders on weak TV hardware — and most
/// loads finish inside the delay anyway, so they stay fully static. Only a
/// slow load (network, cold start) ever animates, by which time the CPU spike
/// has passed. Opacity on one RepaintBoundary layer is compositor-only — no
/// widget repaints per frame.
class DelayedPulse extends StatefulWidget {
  final Widget child;
  final Duration delay;

  const DelayedPulse({
    super.key,
    required this.child,
    this.delay = const Duration(milliseconds: 1500),
  });

  @override
  State<DelayedPulse> createState() => _DelayedPulseState();
}

class _DelayedPulseState extends State<DelayedPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  Timer? _startTimer;

  @override
  void initState() {
    super.initState();
    // value 0 → opacity 1.0: identical to the static skeleton until the timer
    // fires, so a fast load never shows any motion at all.
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
    _opacity = Tween<double>(
      begin: 1.0,
      end: 0.55,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
    _startTimer = Timer(widget.delay, () {
      if (mounted) _controller.repeat(reverse: true);
    });
  }

  @override
  void dispose() {
    _startTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: FadeTransition(opacity: _opacity, child: widget.child),
    );
  }
}

/// A rounded placeholder box for loading skeletons — a muted fill with a fixed
/// diagonal sheen (brighter top-left) that reads like a frosted card.
///
/// Deliberately STATIC: during a load the CPU is busy fetching/parsing, so any
/// per-frame animation drops frames and visibly judders on weak TV hardware. A
/// still placeholder can't stutter. The rounded corners come from the
/// [BoxDecoration.borderRadius] (no ClipRRect layer to rasterise). The only
/// motion is [DelayedPulse] at the container level, which waits out the busy
/// window before breathing.
class ShimmerBox extends StatelessWidget {
  final double radius;

  const ShimmerBox({super.key, this.radius = 10});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: 0.09),
            Colors.white.withValues(alpha: 0.045),
          ],
        ),
      ),
    );
  }
}

/// A loading placeholder for a See-All poster grid: placeholder cards laid out
/// through the SAME [SeeAllGridMetrics] the real [SeeAllPosterGrid] uses, so
/// when the items arrive they fill in place with no layout shift (the geometry
/// lives in one place, so the two can't drift). Non-interactive, static.
class SkeletonPosterGrid extends StatelessWidget {
  final bool isTelevision;

  const SkeletonPosterGrid({super.key, required this.isTelevision});

  @override
  Widget build(BuildContext context) {
    final m = SeeAllGridMetrics.resolve(context, isTelevision: isTelevision);
    return DelayedPulse(
      child: GridView.builder(
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
              const Expanded(child: ShimmerBox()),
              const SizedBox(height: SeeAllGridMetrics.titleGap),
              // Two-line title placeholder. Expanded bars flex to fill exactly
              // [titleHeight], so they can never overflow the band at small text
              // scales (unlike fixed-height bars).
              SizedBox(
                height: m.titleHeight,
                child: const Column(
                  children: [
                    Expanded(child: ShimmerBox(radius: 4)),
                    SizedBox(height: 6),
                    Expanded(
                      child: FractionallySizedBox(
                        widthFactor: 0.6,
                        alignment: Alignment.centerLeft,
                        child: ShimmerBox(radius: 4),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// A loading stand-in that MIRRORS the real home board so the swap is seamless
/// and uncluttered: an optional hero block on top (matching the TV spotlight),
/// then just a couple of rail placeholders — not a screenful of dense shimmer.
/// Non-interactive; still for fast loads, breathing on long ones ([DelayedPulse]).
class SkeletonRailList extends StatelessWidget {
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

  // A subtle full-bleed hero placeholder (matching the real spotlight, which is
  // edge-to-edge with hard corners) with a title + two description bars in the
  // lower-left, so the swap into the real hero doesn't shift or reflow.
  Widget _heroPlaceholder(bool tv) {
    return SizedBox(
      height: heroHeight,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // radius 0 → matches the hard-edged, full-width hero backdrop.
          const ShimmerBox(radius: 0),
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
                  child: const ShimmerBox(radius: 7),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: tv ? 460 : 250,
                  height: 12,
                  child: const ShimmerBox(radius: 4),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: tv ? 380 : 200,
                  height: 12,
                  child: const ShimmerBox(radius: 4),
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
          child: const SizedBox(
            height: 16,
            width: 150,
            child: ShimmerBox(radius: 6),
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
                    child: const ShimmerBox(),
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
    final tv = isTelevision;
    final posterW = posterWidth;
    final cellH = posterW * 3 / 2;
    final rowH = cellH + 14;
    // With a hero on top there's only room for ~2 rails below it — keep it that
    // restrained so the load reads as premium, not a wall of placeholders.
    final railCount = showHero ? 2 : rails;
    return DelayedPulse(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showHero && heroHeight > 0) _heroPlaceholder(tv),
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
