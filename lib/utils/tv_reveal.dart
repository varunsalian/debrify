import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Minimal DPAD reveal: scroll the VERTICAL ancestor scrollable(s) just
/// enough that [context]'s widget is fully visible (plus [margin]), and not
/// at all when it already is.
///
/// This exists because the two obvious alternatives both misbehave on TV:
///
///  * `Scrollable.ensureVisible(context, alignment: x)` PINS the target at
///    x% of the viewport — focusing something low on the page hauls the
///    whole page down (the "scrolls too much and shows the next section"
///    complaint), and every focus step re-scrolls even when the target is
///    already perfectly visible.
///  * It also walks EVERY ancestor scrollable, including horizontal pagers:
///    inside a TabBarView, "align at 15%" means dragging the pager sideways
///    — focusing a right-aligned button visibly switched tabs.
///    (NeverScrollableScrollPhysics doesn't protect against this — physics
///    gate user swipes, not programmatic scrolls.)
///
/// Deliberately vertical-only: horizontal shelves that WANT sideways reveals
/// (Home rows) keep calling Scrollable.ensureVisible themselves.
void tvRevealMinimal(
  BuildContext context, {
  double margin = 24.0,
  Duration duration = const Duration(milliseconds: 180),
}) {
  var renderObject = context.findRenderObject();
  if (renderObject == null) return;

  // Walk every enclosing scrollable in order (mirroring the framework's
  // Scrollable.ensureVisible walk), but only APPLY a scroll on the vertical
  // ones. The target must still advance through the horizontal levels: each
  // viewport lookup pairs the CURRENT target with its nearest viewport, so
  // skipping a pager without advancing through it would pair a leaf inside
  // the pager (horizontal reveal offsets) with the outer vertical list's
  // position — garbage scroll amounts.
  var ctx = context;
  var scrollable = Scrollable.maybeOf(ctx);
  while (scrollable != null && renderObject != null) {
    final position = scrollable.position;
    if (position.axis == Axis.vertical &&
        position.hasPixels &&
        position.hasContentDimensions) {
      final viewport = RenderAbstractViewport.maybeOf(renderObject);
      if (viewport == null) return;

      final leading =
          viewport.getOffsetToReveal(renderObject, 0.0).offset - margin;
      final trailing =
          viewport.getOffsetToReveal(renderObject, 1.0).offset + margin;

      double? target;
      if (position.pixels > leading) {
        target = leading; // target is (partly) above the viewport
      } else if (position.pixels < trailing) {
        target = trailing; // target is (partly) below — scroll just enough
      }
      if (target != null) {
        final clamped =
            target.clamp(position.minScrollExtent, position.maxScrollExtent);
        if (duration == Duration.zero) {
          position.jumpTo(clamped);
        } else {
          position.animateTo(
            clamped,
            duration: duration,
            curve: Curves.easeOutCubic,
          );
        }
      }
    }

    ctx = scrollable.context;
    renderObject = ctx.findRenderObject();
    scrollable = Scrollable.maybeOf(ctx);
  }
}
