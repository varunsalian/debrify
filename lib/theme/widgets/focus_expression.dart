import 'package:flutter/material.dart';

import '../../utils/platform_util.dart';
import '../app_focus.dart';
import '../app_motion.dart';
import '../app_theme_scope.dart';

/// The cursor, as the theme expresses it.
///
/// On a TV this is what the user looks at essentially all of the time, and
/// every theme currently expresses it identically — a ring, sometimes with a
/// glow. Six expressions is the single highest feel-per-line change in the
/// vocabulary, and it is cheap because focus is already centralised in a
/// handful of widgets.
///
/// Stateless about focus itself: the caller passes [focused], the way
/// `DetailFocusRing` and `CardFocusRise` already do. Three different
/// focus-detection mechanisms exist in the tree (`onFocusChange`,
/// `node.addListener`, `hasFocus` polling), so this widget deliberately knows
/// about none of them.
class FocusExpressionBox extends StatelessWidget {
  final Widget child;
  final bool focused;

  /// The site's own corner radius, before the theme's scale.
  final double radius;

  /// The surface this cursor sits ON. Used to rescue a ring that would vanish
  /// into what it is drawn over — Noir's white on a white button was the
  /// original case, and `DetailTheme.focusOn` is the rule.
  final Color? on;

  /// For [FocusExpression.invert]: what the content becomes when inverted.
  /// Supplied by the caller because only it knows which of its children are
  /// ink.
  final Widget Function(BuildContext, Color ink)? inverted;

  const FocusExpressionBox({
    super.key,
    required this.child,
    required this.focused,
    required this.radius,
    this.on,
    this.inverted,
  });

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final tv = PlatformUtil.isTelevision;
    final f = app.focus;
    final motion = AppMotion.of(context);
    final ring = on == null ? app.core.focus : app.core.focusOn(on!);
    // The cursor SNAPS on TV. Everything else here is already gated on the
    // platform for raster cost; this one is gated for feel — a ring that
    // tweens across a shelf at three metres reads as lag, and the two TV focus
    // widgets this replaced both used `Duration.zero` for exactly that reason.
    final duration = tv ? Duration.zero : motion.fast;

    // `flood` and `invert` REPLACE the surface, and this widget paints behind
    // its child — so over an opaque card (artwork, a gradient, a tinted row)
    // neither would be visible at all. The caller opts in by supplying
    // [inverted], which is the only thing that knows which of its children are
    // ink; without it the expression degrades to the ring, which is a cursor
    // that always works rather than one that silently does nothing.
    final replacesSurface = f.expression == FocusExpression.flood ||
        f.expression == FocusExpression.invert;
    final expression = replacesSurface && inverted == null
        ? FocusExpression.ring
        : f.expression;

    Widget body = child;

    if (focused && replacesSurface && inverted != null) {
      body = ColoredBox(
        color: app.core.accent,
        child: inverted!(context, app.inkOn(app.core.accent)),
      );
    }

    // The ring, where the expression draws one.
    if (expression == FocusExpression.ring) {
      body = AnimatedContainer(
        duration: duration,
        curve: motion.standard,
        foregroundDecoration: BoxDecoration(
          borderRadius: app.shape.br(radius),
          border: Border.all(
            color: focused ? ring : Colors.transparent,
            width: f.widthFor(tv),
          ),
        ),
        child: body,
      );
    }

    // Underline: a bar beneath, nothing around.
    if (expression == FocusExpression.underline) {
      body = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(child: body),
          AnimatedContainer(
            duration: duration,
            height: f.widthFor(tv),
            color: focused ? ring : Colors.transparent,
          ),
        ],
      );
    }

    // The bloom. Off on TV — a blurred shadow that re-rasters on every focus
    // move is the most expensive thing a cursor can do on a weak GPU.
    final bloom = app.light.bloomFor(tv);
    if (focused && bloom > 0) {
      body = DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: app.shape.br(radius),
          boxShadow: [
            BoxShadow(
              color: ring.withValues(alpha: 0.28),
              blurRadius: bloom,
              spreadRadius: 1,
            ),
          ],
        ),
        child: body,
      );
    }

    // Lift: rises with the theme's elevation.
    if (expression == FocusExpression.lift) {
      body = AnimatedContainer(
        duration: duration,
        curve: motion.standard,
        transform: Matrix4.translationValues(0, focused ? -f.lift : 0, 0),
        decoration: BoxDecoration(
          borderRadius: app.shape.br(radius),
          boxShadow: focused
              ? app.surface.shadowFor(app.surface.floatingShadow, tv)
              : app.surface.shadowFor(app.surface.restShadow, tv),
        ),
        child: body,
      );
    }

    // Scale, for both `scale` and `lift`. A transform, so it is affordable on
    // TV — unlike the shadow it usually travels with.
    final scale = f.scaleFor(tv);
    if (scale != 1) {
      body = AnimatedScale(
        scale: focused ? scale : 1,
        duration: duration,
        curve: motion.standard,
        child: body,
      );
    }

    return body;
  }
}
