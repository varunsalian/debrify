import 'package:flutter/material.dart';

/// What the app does when you stop touching it.
enum IdlePolicy {
  /// Nothing. Today's app, and the legacy pin.
  none,

  /// Chrome fades back; content stays.
  dimChrome,

  /// Chrome fades and the artwork takes the room.
  theater,
}

/// Idle behaviour. TV only in v1 — a phone in a pocket has a screen timeout,
/// and a desktop window that dims itself is a bug report.
@immutable
class IdleTokens {
  final IdlePolicy policy;

  /// How long a rest before the policy engages.
  final Duration after;

  /// How far chrome fades, 0..1.
  final double depth;

  const IdleTokens({
    required this.policy,
    required this.after,
    required this.depth,
  });

  static const IdleTokens legacy = IdleTokens(
    policy: IdlePolicy.none,
    after: Duration(seconds: 30),
    depth: 0,
  );

  /// v1 is TV-only. The token is carried everywhere so a later phone policy is
  /// a one-line change rather than a new dimension.
  IdlePolicy policyFor(bool isTv) => isTv ? policy : IdlePolicy.none;
}

/// What waiting looks like.
///
/// Small, and included because waiting is where cheapness concentrates: a
/// skeleton that shimmers when the rest of the app snaps reads as a different
/// app's component.
enum SkeletonStyle {
  /// A travelling highlight. Today's app.
  shimmer,

  /// Opacity breathes; nothing travels.
  pulse,

  /// A flat block. No animation at all — the cheapest, and the right answer
  /// for a theme whose motion character is `snap`.
  static_,

  /// Horizontal rules, like a signal with no picture.
  scanlines,
}

@immutable
class WaitTokens {
  final SkeletonStyle skeleton;

  /// Cycle length for the animated styles. Ignored by [SkeletonStyle.static_].
  final Duration period;

  const WaitTokens({required this.skeleton, required this.period});

  /// Today's app: the shimmer at the period `Shimmer` already runs.
  static const WaitTokens legacy = WaitTokens(
    skeleton: SkeletonStyle.shimmer,
    period: Duration(milliseconds: 1200),
  );

  /// On TV, anything that animates forever is a repaint forever — the house
  /// playbook says "nothing animates unless it must" there.
  ///
  /// **Shimmer is exempt, and that is not an oversight.** It is what the app
  /// ships today: `Shimmer` runs a 1200ms repeating controller on TV right
  /// now. Degrading it here would make the legacy profile stop being a no-op,
  /// and the one permitted legacy exception is reduced motion, not a TV
  /// optimisation. A look that chooses shimmer knowingly accepts the cost the
  /// app already pays; the newer styles do not get to add to it.
  SkeletonStyle styleFor(bool isTv) => switch (skeleton) {
    SkeletonStyle.shimmer || SkeletonStyle.scanlines => skeleton,
    SkeletonStyle.pulse => isTv ? SkeletonStyle.static_ : skeleton,
    SkeletonStyle.static_ => SkeletonStyle.static_,
  };
}

/// How much room things take.
///
/// Four metrics, not a spacing scale. A general scale would be ~5,300 sites
/// with no chokepoint; these four are the ones that carry the FEELING of
/// density and all live in the shelf/grid widgets.
@immutable
class DensityTokens {
  /// Multiplier on shelf row height. Bounded ±20%.
  final double rowHeight;

  /// Multiplier on card size. Bounded ±15%.
  final double cardScale;

  /// Multiplier on the page's horizontal gutter. Bounded ±25%.
  final double pageGutter;

  /// Multiplier on the gap between sections. Bounded ±30%.
  final double sectionGap;

  const DensityTokens({
    required this.rowHeight,
    required this.cardScale,
    required this.pageGutter,
    required this.sectionGap,
  });

  /// Today's app: every metric exactly as drawn.
  static const DensityTokens legacy = DensityTokens(
    rowHeight: 1,
    cardScale: 1,
    pageGutter: 1,
    sectionGap: 1,
  );

  /// The bounds, applied at derivation rather than trusted from the spec.
  ///
  /// A theme is data, and data that can set `cardScale: 3` would break every
  /// shelf that assumed a card fits. Clamping here means a spec cannot express
  /// a layout change even by accident — which is what makes density a bounded
  /// seam in D8 rather than an exception to it.
  factory DensityTokens.clamped({
    double rowHeight = 1,
    double cardScale = 1,
    double pageGutter = 1,
    double sectionGap = 1,
  }) => DensityTokens(
    rowHeight: rowHeight.clamp(0.80, 1.20),
    cardScale: cardScale.clamp(0.85, 1.15),
    pageGutter: pageGutter.clamp(0.75, 1.25),
    sectionGap: sectionGap.clamp(0.70, 1.30),
  );

  double row(double v) => v * rowHeight;
  double card(double v) => v * cardScale;
  double gutter(double v) => v * pageGutter;
  double section(double v) => v * sectionGap;
}
