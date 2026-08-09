import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../utils/platform_util.dart';
import '../app_light.dart';
import '../app_theme_scope.dart';

/// How text is made legible on top of artwork.
///
/// One widget, four grammars. Sites say "there is text over this image" and
/// the theme decides what that means — a fade, a frosted strip, a hard plate,
/// or a flat dim. Every one of them is invisible to a palette, and they are
/// among the most recognisable differences between real streaming apps.
///
/// Wraps the ARTWORK, not the text: the scrim paints over the image and the
/// caller's [child] (the copy) sits above it.
class AppScrim extends StatelessWidget {
  /// The artwork this scrim protects text on.
  final Widget background;

  /// The text (or anything else) that must stay legible.
  final Widget child;

  /// Where the protected content sits. `bottomLeft` for a hero, `bottomCenter`
  /// for a card caption.
  final AlignmentGeometry alignment;

  /// Override the theme's extent — a card caption needs a sliver where a hero
  /// needs half the frame.
  final double? extent;

  const AppScrim({
    super.key,
    required this.background,
    required this.child,
    this.alignment = Alignment.bottomLeft,
    this.extent,
  });

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final tv = PlatformUtil.isTelevision;
    final l = app.light;
    final reach = extent ?? l.scrimExtent;
    final ground = app.core.ground;

    return Stack(
      fit: StackFit.expand,
      children: [
        background,
        // The scrim proper.
        Positioned.fill(child: _scrim(l, reach, ground, tv)),
        // Corner darkening, if the look asks for it. A static gradient, so it
        // costs the same everywhere and is deliberately NOT platform-gated.
        if (l.vignetteFor(tv) > 0)
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    radius: 1.1,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: l.vignetteFor(tv)),
                    ],
                    stops: const [0.45, 1.0],
                  ),
                ),
              ),
            ),
          ),
        Align(alignment: alignment, child: child),
      ],
    );
  }

  Widget _scrim(LightTokens l, double reach, Color ground, bool tv) {
    switch (l.scrim) {
      case ScrimStyle.bottomGradient:
        return IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [
                  ground.withValues(alpha: l.scrimStrength),
                  ground.withValues(alpha: l.scrimStrength * 0.42),
                  Colors.transparent,
                ],
                stops: [0.0, reach * 0.5, reach],
              ),
            ),
          ),
        );

      case ScrimStyle.blurBand:
        // A frosted strip: the text sits on blurred artwork rather than on a
        // darkened copy of it. On TV there is no blur — the band becomes an
        // opaque plate, the same trade `GlassSurface` makes.
        final band = Align(
          alignment: Alignment.bottomCenter,
          child: FractionallySizedBox(
            heightFactor: reach.clamp(0.05, 1.0),
            widthFactor: 1,
            child: tv
                ? DecoratedBox(
                    decoration: BoxDecoration(
                      color: ground.withValues(alpha: l.scrimStrength * 0.86),
                    ),
                  )
                : ClipRect(
                    child: BackdropFilter(
                      filter: ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: ground.withValues(
                            alpha: l.scrimStrength * 0.42,
                          ),
                        ),
                      ),
                    ),
                  ),
          ),
        );
        return IgnorePointer(child: band);

      case ScrimStyle.plate:
        // A hard-edged slab. The only grammar that guarantees a contrast ratio
        // regardless of what the image beneath is doing.
        return IgnorePointer(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: FractionallySizedBox(
              heightFactor: reach.clamp(0.05, 1.0),
              widthFactor: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: ground.withValues(alpha: l.scrimStrength),
                ),
              ),
            ),
          ),
        );

      case ScrimStyle.fullDim:
        return IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: ground.withValues(alpha: l.scrimStrength * 0.6),
            ),
          ),
        );
    }
  }
}
