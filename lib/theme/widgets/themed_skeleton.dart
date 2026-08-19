import 'package:flutter/material.dart';

import '../../utils/platform_util.dart';
import '../../widgets/shimmer.dart';
import '../app_ambience.dart';
import '../app_theme_scope.dart';

/// What waiting looks like, per theme.
///
/// Small, and included because waiting is where cheapness concentrates: a
/// skeleton that shimmers while the rest of the app snaps reads as a component
/// borrowed from a different product.
///
/// Distinct from the existing `Shimmer` widget, which is deliberately
/// theme-blind so the permanently-legacy player can keep rendering it. This
/// one follows the palette; `Shimmer` stays exactly as it is.
class ThemedSkeleton extends StatefulWidget {
  final double? width;
  final double? height;
  final BorderRadius? borderRadius;

  const ThemedSkeleton({
    super.key,
    this.width,
    this.height,
    this.borderRadius,
  });

  @override
  State<ThemedSkeleton> createState() => _ThemedSkeletonState();
}

class _ThemedSkeletonState extends State<ThemedSkeleton>
    with SingleTickerProviderStateMixin {
  AnimationController? _ctrl;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Resolved here rather than in initState: this is the one lifecycle hook
    // that may depend on inherited widgets AND re-runs when they change, so a
    // theme switch retargets the controller instead of stranding it.
    final app = AppThemeScope.of(context);
    // Classic delegates to the shipped `Shimmer`, which owns its own repeating
    // controller — so this one must not exist at all, or every placeholder on
    // screen runs two tickers to paint one animation.
    final style = app.isLegacy
        ? SkeletonStyle.static_
        : app.wait.styleFor(PlatformUtil.isTelevision);
    final animated =
        style == SkeletonStyle.shimmer || style == SkeletonStyle.pulse;

    if (!animated) {
      _ctrl?.dispose();
      _ctrl = null;
      return;
    }
    // The duration must be set BEFORE `repeat()`: an `AnimationController`
    // with a null duration throws "no default duration" the moment it is
    // asked to run, which would have been an exception on the first frame of
    // any animated wait style — including the shipped shimmer.
    if (_ctrl == null) {
      _ctrl = AnimationController(vsync: this, duration: app.wait.period)
        ..repeat();
    } else {
      // Re-assigning affects the next cycle, which for a repeating controller
      // is soon enough to be invisible.
      _ctrl!.duration = app.wait.period;
    }
  }

  /// Test-only: how many controllers this state is keeping alive.
  @visibleForTesting
  int get debugTickerCount => _ctrl == null ? 0 : 1;

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);

    // Debrify Classic renders the SHIPPED widget, not a token-coloured
    // approximation of it. `Shimmer` paints a hardcoded #223049 → #2A3A55
    // sweep at stops [0.1, 0.3, 0.5]; this widget's shimmer arm paints the
    // theme's ink at 7%/13% across the full width. They are close, and close
    // is a legacy break at every loading screen in the app.
    if (app.isLegacy) {
      return Shimmer(
        width: widget.width,
        height: widget.height,
        borderRadius: widget.borderRadius,
      );
    }

    final tv = PlatformUtil.isTelevision;
    final style = app.wait.styleFor(tv);
    final radius = widget.borderRadius ?? app.shape.br(6);
    final base = app.core.tx.withValues(alpha: 0.07);
    final hi = app.core.tx.withValues(alpha: 0.13);

    Widget paint;
    switch (style) {
      case SkeletonStyle.static_:
        paint = ColoredBox(color: base);

      case SkeletonStyle.scanlines:
        // Horizontal rules — a signal with no picture. No animation, so it is
        // the one animated-looking style that is free on TV.
        paint = DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              tileMode: TileMode.repeated,
              colors: [hi, Colors.transparent],
              stops: const [0.34, 0.35],
            ),
          ),
        );

      case SkeletonStyle.pulse:
        paint = _ctrl == null
            ? ColoredBox(color: base)
            : AnimatedBuilder(
                animation: _ctrl!,
                builder: (_, __) {
                  final t = (_ctrl!.value * 2 - 1).abs();
                  return ColoredBox(color: Color.lerp(base, hi, t)!);
                },
              );

      case SkeletonStyle.shimmer:
        paint = _ctrl == null
            ? ColoredBox(color: base)
            : AnimatedBuilder(
                animation: _ctrl!,
                builder: (_, __) {
                  final x = _ctrl!.value * 2 - 1;
                  return DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment(x - 1, 0),
                        end: Alignment(x + 1, 0),
                        colors: [base, hi, base],
                      ),
                    ),
                  );
                },
              );
    }

    return ClipRRect(
      borderRadius: radius,
      child: SizedBox(
        width: widget.width,
        height: widget.height,
        child: paint,
      ),
    );
  }
}
