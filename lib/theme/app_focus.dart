import 'dart:math' as math;

import 'package:flutter/material.dart';

/// What the cursor DOES when it lands on something.
///
/// Disproportionately important: on a TV the focus indicator is what the user
/// looks at essentially all of the time. Every theme currently expresses it
/// identically — a ring, optionally with a glow — which is a large part of why
/// they feel like one app.
enum FocusExpression {
  /// A border around the item. Today's app, and the legacy pin.
  ring,

  /// The item grows. No border.
  scale,

  /// The item rises with a shadow.
  lift,

  /// Foreground and background swap — the way a terminal shows selection.
  invert,

  /// The item fills with the accent.
  flood,

  /// A bar under the item only.
  underline,
}

/// The cursor's character.
@immutable
class FocusTokens {
  final FocusExpression expression;

  /// Ring thickness. Read through [widthFor], which keeps the 2.5px floor a
  /// cursor needs to survive at three metres.
  final double width;

  /// How far outside its bounds the ring sits. Requires the site to have room;
  /// see the note on [FocusTokens.legacy].
  final double offset;

  /// Scale factor for [FocusExpression.scale] and [FocusExpression.lift].
  final double scale;

  /// Vertical rise, in logical pixels, for [FocusExpression.lift].
  final double lift;

  const FocusTokens({
    required this.expression,
    required this.width,
    required this.offset,
    required this.scale,
    required this.lift,
  });

  /// Today's app: an in-bounds ring at Signal's shipped width, no scale, no
  /// lift.
  ///
  /// `offset: 0` matters — Signal draws its ring IN BOUNDS, and every focus
  /// site in the app assumes that. An outward offset needs each site to make
  /// room for it, which is why `ShapeTokens.focusOffset` shipped
  /// carried-not-adopted.
  static const FocusTokens legacy = FocusTokens(
    expression: FocusExpression.ring,
    width: 2.5,
    offset: 0,
    scale: 1,
    lift: 0,
  );

  /// The cursor must survive at three metres whatever the theme asked for —
  /// the same rule and the same floor as `ShapeTokens.focusWidthFor` and
  /// `DetailTheme.focusWidthFor`.
  double widthFor(bool isTv) => isTv ? math.max(width, 2.5) : width;

  /// Whether this expression paints a border at all.
  ///
  /// `scale` and `lift` deliberately do not: a ring on top of a scale reads as
  /// two cursors, and the whole point of those expressions is that motion,
  /// not decoration, tells you where you are.
  bool get drawsRing => switch (expression) {
    FocusExpression.ring || FocusExpression.invert => true,
    FocusExpression.scale ||
    FocusExpression.lift ||
    FocusExpression.flood ||
    FocusExpression.underline => false,
  };

  /// Scale is honoured on TV — it is a transform, not a raster — but the lift
  /// shadow it usually travels with is filtered by the surface layer.
  double scaleFor(bool isTv) => scale;
}
