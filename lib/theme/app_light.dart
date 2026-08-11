import 'package:flutter/material.dart';

/// How text is made legible on top of artwork.
///
/// One of the most recognisable differences between real streaming apps, and
/// completely invisible to a palette: the same poster with a bottom gradient,
/// a frosted band or a hard plate under its title reads as three different
/// products.
enum ScrimStyle {
  /// A vertical fade from the ground up. Today's app, and the legacy pin.
  bottomGradient,

  /// A frosted strip — the text sits on blurred artwork rather than on a
  /// darkened version of it. Delivered through `GlassSurface`, so it inherits
  /// the opaque TV fallback.
  blurBand,

  /// A solid slab. Hard-edged, editorial; the only style that guarantees a
  /// contrast ratio regardless of the image beneath.
  plate,

  /// The whole image dims, with no localised treatment.
  fullDim,
}

/// Where the light in a scene comes from, and how text survives it.
@immutable
class LightTokens {
  final ScrimStyle scrim;

  /// How far the scrim reaches, as a fraction of the surface it covers.
  /// A hero's gradient is tall; a card caption's is a sliver.
  final double scrimExtent;

  /// Peak opacity of the scrim at its strongest point.
  final double scrimStrength;

  /// Corner-darkening across the whole page. 0 = flat.
  final double vignette;

  /// Glow radius around the focused item, in logical pixels. 0 = none.
  /// Forced to 0 on TV by [bloomFor] — this is a blurred shadow that
  /// re-rasters on every focus move, which is the single most expensive thing
  /// a cursor can do on a weak GPU.
  final double focusBloom;

  const LightTokens({
    required this.scrim,
    required this.scrimExtent,
    required this.scrimStrength,
    required this.vignette,
    required this.focusBloom,
  });

  /// Today's app: a bottom gradient at the extent and strength the hero
  /// already uses, no vignette, no bloom.
  static const LightTokens legacy = LightTokens(
    scrim: ScrimStyle.bottomGradient,
    scrimExtent: 0.62,
    scrimStrength: 0.92,
    vignette: 0,
    focusBloom: 0,
  );

  double bloomFor(bool isTv) => isTv ? 0 : focusBloom;

  /// The vignette is a static gradient, not a filter, so unlike the bloom it
  /// costs the same everywhere and is NOT gated. Stated so nobody adds a gate
  /// out of caution and quietly removes a look's identity on TV.
  double vignetteFor(bool isTv) => vignette;
}
