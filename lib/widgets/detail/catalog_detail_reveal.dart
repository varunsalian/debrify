/// The staggered entrance reveal used by every section of
/// `CatalogItemDetailScreen`.
library;

import 'package:flutter/material.dart';

// ── Staggered entrance reveal ───────────────────────────────────────────────

/// Fades + slides a section in from below, on an [Interval] of [parent] so
/// successive sections cascade. Cheap: a single shared controller drives all.
class CatalogDetailReveal extends StatelessWidget {
  final AnimationController parent;

  /// Where on the 0‥1 timeline this section starts (earlier = sooner).
  final double start;

  /// How far (px) it travels up into place.
  final double dy;
  final Widget child;

  const CatalogDetailReveal({
    super.key,
    required this.parent,
    required this.start,
    required this.child,
    this.dy = 26,
  });

  @override
  Widget build(BuildContext context) {
    final anim = CurvedAnimation(
      parent: parent,
      curve: Interval(
        start,
        (start + 0.42).clamp(0.0, 1.0),
        curve: Curves.easeOutCubic,
      ),
    );
    return AnimatedBuilder(
      animation: anim,
      builder: (context, child) => Opacity(
        opacity: anim.value,
        child: Transform.translate(
          offset: Offset(0, (1 - anim.value) * dy),
          child: child,
        ),
      ),
      child: child,
    );
  }
}
