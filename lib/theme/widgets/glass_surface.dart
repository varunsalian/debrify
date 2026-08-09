import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../utils/platform_util.dart';
import '../app_surface.dart';
import '../app_theme.dart';
import '../app_theme_scope.dart';

/// The one place a blurred surface is built.
///
/// Every existing `BackdropFilter` in the app hand-rolls its own blur, clip
/// and fill, and several carry a bespoke TV bypass copied between files. A
/// bare `glass` token could not be adopted mechanically by any of them — so
/// the token is delivered as a WIDGET that owns all four concerns at once:
/// the filter, the clip, the fill, and the platform fallback.
///
/// ## The TV contract
///
/// `BackdropFilter` is a `saveLayer` per frame. On TV it is not used at all:
/// the same pane renders at [SurfaceTokens.glassOpacityTv], which is
/// deliberately higher than the blurred opacity because an unblurred pane at
/// the blurred alpha is a smear rather than a surface.
///
/// That is a stated property of glass looks on TV, not a degradation bug —
/// and it follows the pattern the player sheets already use, where the TV
/// branch swaps a σ28 blur for an opaque plate.
///
/// ## What this widget is NOT for
///
/// It always clips. A site whose blur deliberately extends BEYOND the pane —
/// the four Torbox dialogs blur their 16px margin ring, the floating-nav
/// barrier blurs the whole screen — cannot be expressed here without changing
/// what it paints, and those sites keep their own `BackdropFilter`. The tell
/// is a filter that wraps a margin-bearing or full-screen widget rather than
/// the panel itself. A full-screen dim is `LightTokens`' territory anyway.
class GlassSurface extends StatelessWidget {
  final Widget child;

  /// Corner radius. Defaults to the theme's own surface radius.
  final BorderRadius? borderRadius;

  /// The blur this SITE shipped, off TV.
  ///
  /// Two jobs, and both matter. Under a glass look it overrides the theme's
  /// own `glassSigma` for sites that have a reason (the Torbox dialogs use
  /// two different strengths). Under a look with **no surface opinion** — that
  /// is Debrify Classic and all twenty pre-`ThemeSpec` themes — it is the
  /// blur that gets painted, because those looks never chose to stop blurring
  /// and adoption must not silently decide for them. A look that explicitly
  /// says `fill`, `rule` or `space` HAS chosen, and gets no blur.
  ///
  /// Leave null at a site that never blurred.
  final double? sigma;

  /// The tint the pane is made of when there is NO blur behind it. Defaults
  /// to the theme's raised surface.
  final Color? tint;

  /// The tint to use when a blur IS painted.
  ///
  /// Every converted site shipped this as a ternary — opaque on TV where the
  /// blur was skipped, translucent elsewhere where the blur does the work —
  /// and collapsing the two would have made the phone sheets opaque under
  /// Debrify Classic. Null means "the same either way", which is the common
  /// case.
  final Color? blurTint;

  /// Hairline. Null uses the theme's; pass `Colors.transparent` to suppress.
  final Color? border;

  /// Hairline width. Sites that shipped a 0.5px edge must say so, or adopting
  /// this widget doubles their hairline — which is a visible change under
  /// Debrify Classic and therefore a legacy break, not a restyle.
  final double borderWidth;

  final EdgeInsetsGeometry? padding;

  /// Which family's separation model decides whether this is glass at all.
  ///
  /// A `GlassSurface` under a non-glass look is not a bug — it renders as that
  /// look's model instead (a plain fill, or a hairline). That is what lets a
  /// site adopt this widget once and then follow every theme.
  final SurfaceFamily family;

  const GlassSurface({
    super.key,
    required this.child,
    this.family = SurfaceFamily.sheet,
    this.borderRadius,
    this.sigma,
    this.tint,
    this.blurTint,
    this.border,
    this.borderWidth = 1,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final tv = PlatformUtil.isTelevision;
    final model = app.surface.modelFor(family);
    final radius = borderRadius ?? app.shape.br(20);

    final blur = _sigma(app, model, tv);
    final decorated = _fill(app, model, tv, radius, blurred: blur > 0);
    if (blur <= 0) {
      // Nothing to filter. The ClipRRect still runs so corners match the glass
      // path exactly.
      return ClipRRect(borderRadius: radius, child: decorated);
    }
    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: decorated,
      ),
    );
  }

  /// How much blur this instance actually paints.
  ///
  /// TV is zero whatever anyone asked for — `BackdropFilter` is a saveLayer
  /// per frame, and every one of the converted sites already carried its own
  /// TV bypass before adoption.
  double _sigma(AppTheme app, SeparationModel model, bool tv) {
    if (tv) return 0;
    if (model == SeparationModel.glass) {
      return sigma ?? app.surface.glassSigmaFor(tv);
    }
    // The legacy-identity case: a look that stated no surface opinion keeps
    // whatever the site shipped. Without this, adopting this widget would
    // remove a real blur from ten phone sheets under Debrify Classic — which
    // is precisely the break the byte-identity rule exists to prevent.
    return app.surface.isNeutral ? (sigma ?? 0) : 0;
  }

  Widget _fill(
    AppTheme app,
    SeparationModel model,
    bool tv,
    BorderRadius radius, {
    required bool blurred,
  }) {
    final base = (blurred ? (blurTint ?? tint) : tint) ?? app.core.pane;
    final Color fill = switch (model) {
      SeparationModel.glass =>
        base.withValues(alpha: app.surface.glassFillFor(tv)),
      SeparationModel.fill => base,
      // A sheet or dialog can never resolve to these (the caps forbid it), so
      // reaching here means a card/hero adopted the widget — where "no fill"
      // is exactly what it asked for.
      SeparationModel.space || SeparationModel.rule => Colors.transparent,
    };
    final Color? asked = switch (model) {
      SeparationModel.space => null,
      SeparationModel.rule => border ?? app.core.hair,
      _ => border ?? app.core.hair,
    };
    // A fully transparent border is a border that was SUPPRESSED, and it must
    // not keep insetting content by its own width: the seven filter-only
    // panes pass `Colors.transparent` precisely because their fill and edge
    // live in their own child, and a phantom 1px inset there would crop the
    // outermost pixels of a gradient that used to reach the clip.
    final Color? edge = (asked == null || asked.a == 0) ? null : asked;
    // `Container` insets its child by the border it draws (`BoxDecoration`
    // reports `border.dimensions` as padding); `DecoratedBox` does not. A
    // converted site whose content shifted by its own hairline would be a
    // legacy break, so the inset is reproduced explicitly.
    final EdgeInsetsGeometry inner = switch ((edge, padding)) {
      (null, final p) => p ?? EdgeInsets.zero,
      (_, null) => EdgeInsets.all(borderWidth),
      (_, final p!) => p.add(EdgeInsets.all(borderWidth)),
    };

    Widget body = Padding(padding: inner, child: child);

    // The lit top edge, where the look asks for one.
    //
    // Painted as its OWN layer, never as this decoration's `gradient`:
    // `BoxDecoration` builds one paint, and a gradient replaces the shader
    // that `color` set. Putting the sheen in the same decoration would have
    // silently thrown the pane's fill away on every look with sheen > 0 —
    // which is three of the five.
    if (app.surface.sheen > 0) {
      body = Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: radius,
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      app.core.tx.withValues(alpha: app.surface.sheen * 0.16),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.16],
                  ),
                ),
              ),
            ),
          ),
          body,
        ],
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: fill,
        borderRadius: radius,
        border: edge == null
            ? null
            : Border.all(color: edge, width: borderWidth),
      ),
      child: body,
    );
  }
}
