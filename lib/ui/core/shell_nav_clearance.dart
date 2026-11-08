import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Room a page's top-left corner leaves for the shell's floating navigation
/// capsule.
///
/// The 'pill' sidebar style runs pages full-bleed and floats a capsule over
/// their top-left corner. Where the shell provides this, a page either
/// starts its first toolbar row at [leading], or starts its content at
/// [below], so the capsule never covers a control. Everywhere else (the
/// phone layout, TV, desktop, the rail styles, pushed routes) the clearance
/// is zero and pages keep their layout.
class ShellNavClearance extends InheritedWidget {
  const ShellNavClearance({
    super.key,
    required this.leading,
    required this.below,
    required super.child,
  });

  /// Distance from the page's left edge to where a top row may start.
  final double leading;

  /// Distance from the page's top edge to where content clears the capsule.
  final double below;

  static ShellNavClearance? _of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ShellNavClearance>();

  /// Extra left padding for a top row that already starts [ownLeft] from
  /// the page's left edge.
  static double extraLeading(BuildContext context, double ownLeft) =>
      math.max(0, (_of(context)?.leading ?? 0) - ownLeft);

  /// Extra top padding for content that already starts [ownTop] from the
  /// page's top edge.
  static double extraBelow(BuildContext context, double ownTop) =>
      math.max(0, (_of(context)?.below ?? 0) - ownTop);

  /// [extraLeading] as left padding, to add to a row's own padding.
  static EdgeInsets leadingInsets(BuildContext context, double ownLeft) =>
      EdgeInsets.only(left: extraLeading(context, ownLeft));

  /// [extraBelow] as top padding, to add to content's own padding.
  static EdgeInsets belowInsets(BuildContext context, double ownTop) =>
      EdgeInsets.only(top: extraBelow(context, ownTop));

  @override
  bool updateShouldNotify(ShellNavClearance oldWidget) =>
      leading != oldWidget.leading || below != oldWidget.below;
}
