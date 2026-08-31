import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'see_all/discover_shelf_scope.dart';
import 'see_all/discover_card_settings_scope.dart';
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
    // Discover's stage layout replaces the wall with one bottom shelf — stand
    // in for THAT, or the load state announces a grid that never arrives.
    final shelf = DiscoverShelfScope.of(context);
    if (shelf != null) return _buildShelfSkeleton(shelf);
    final showTitles =
        DiscoverCardSettingsScope.maybeOf(context)?.showTitles ?? true;
    final m = SeeAllGridMetrics.resolve(
      context,
      isTelevision: isTelevision,
      showTitles: showTitles,
    );
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
              if (showTitles) ...[
                const SizedBox(height: SeeAllGridMetrics.titleGap),
                // Two-line title placeholder. Expanded bars flex to fill
                // exactly [titleHeight], so they can never overflow the band
                // at small text scales (unlike fixed-height bars).
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
            ],
          );
        },
      ),
    );
  }

  /// The stage shelf's stand-in: one row of posters at the same height and
  /// pitch the real shelf uses, so the placeholders hand off with no shift.
  /// Over-count so a wide panel never shows a short row (it clips).
  Widget _buildShelfSkeleton(DiscoverShelfMetrics m) {
    return DelayedPulse(
      child: Align(
        alignment: Alignment.bottomLeft,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: m.boxHeight,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                physics: const NeverScrollableScrollPhysics(),
                clipBehavior: Clip.hardEdge,
                padding: EdgeInsets.symmetric(horizontal: m.hPad),
                itemCount: 10,
                itemBuilder: (context, index) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 7),
                  child: Center(
                    child: SizedBox(
                      width: m.cardWidth,
                      height: m.cardHeight,
                      child: const ShimmerBox(radius: 14),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: DiscoverShelfMetrics.tail),
          ],
        ),
      ),
    );
  }
}

/// The home board's load state: a quiet brand moment — the DEBRIFY wordmark
/// centred on the page ink with a thin breathing accent bar beneath — instead
/// of a screenful of skeleton boxes (which read as "broken app", the old
/// complaint). This is the Netflix grammar: brand holds the stage, then the
/// board simply appears.
///
/// Cost-shaped for weak TV hardware: the wordmark is one static text layer
/// (never animates — it must read rock solid, and text that blinks during a
/// CPU-busy load judders); the only motion is the tiny accent bar breathing
/// opacity inside its own [DelayedPulse] compositor layer, which also waits
/// out the busiest first moments of the load before starting.
class BrandLoadingStage extends StatelessWidget {
  final bool isTelevision;

  const BrandLoadingStage({super.key, required this.isTelevision});

  @override
  Widget build(BuildContext context) {
    final tv = isTelevision;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'DEBRIFY',
            // Poppins — the same display face the hero titles wear, so the
            // brand and the content read as one voice.
            style: GoogleFonts.poppins(
              fontSize: tv ? 34 : 26,
              fontWeight: FontWeight.w600,
              letterSpacing: tv ? 10 : 7,
              color: Colors.white.withValues(alpha: 0.92),
            ),
          ),
          SizedBox(height: tv ? 22 : 18),
          // The life sign: a small accent bar breathing slowly. Starts after a
          // short beat so instant loads never show motion at all.
          DelayedPulse(
            delay: const Duration(milliseconds: 400),
            child: Container(
              width: 56,
              height: 3,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(2),
                gradient: const LinearGradient(
                  colors: [Color(0xFF7B5CFF), Color(0xFF818CF8)],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
