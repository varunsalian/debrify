import 'package:flutter/material.dart';

/// How a surface is told apart from what is behind it.
///
/// The single biggest lever in the vocabulary, because it changes the
/// SILHOUETTE of a screen rather than its colour — and a user reads silhouette
/// first. Every surface in the app is currently the same idea (a tinted panel
/// with a hairline), which is why twenty themes read as one app in twenty
/// tints.
enum SeparationModel {
  /// A tinted panel plus a hairline. Today's app, and the legacy pin.
  fill,

  /// Translucent and blurred, so the artwork behind is never fully hidden.
  /// Delivered only through `GlassSurface`, which owns the opaque TV fallback.
  glass,

  /// No fill and no border at all — separation by rhythm and light alone.
  /// Only legal where dropping decoration changes no geometry; see
  /// [SurfaceFamily] and the caps in [SurfaceTokens.modelFor].
  space,

  /// Hairlines only, no fill.
  rule,
}

/// The surface families a theme may address separately.
///
/// A single `model` field cannot express "space on cards, rule in settings",
/// and that distinction is not cosmetic: it is what keeps `space` legal at all
/// (see the caps below). The families map to the widgets that actually own
/// the decoration, inventoried in `plan/PREMIUM_LOOKS_PLAN.md` §12.
enum SurfaceFamily {
  /// `CatalogItemTile`, `PlaylistGridCard`, `PlaylistLandscapeCard`.
  card,

  /// `CloudFileRow`, `SourceRow`, `TorrentResultRow`.
  shelfRow,

  /// `_HeroSpotlight`, `HeroTrailerBackdrop`, `TvAmbientArtStage`.
  hero,

  /// Modal bottom sheets.
  sheet,

  /// `showDialog` surfaces.
  dialog,

  /// `SettingsSection` and its rows.
  settingsGroup,
}

/// The separation, material and elevation half of a look.
@immutable
class SurfaceTokens {
  /// The theme's default separation, used by any family that does not
  /// override it.
  final SeparationModel base;

  /// Per-family overrides. Clamped by [modelFor] — a family may never take a
  /// model its geometry cannot survive.
  final Map<SurfaceFamily, SeparationModel> overrides;

  /// Blur radius for [SeparationModel.glass], in logical pixels.
  final double glassSigma;

  /// Fill opacity behind the blur, off TV.
  final double glassOpacity;

  /// Fill opacity on TV, where there is no blur to hide behind — see
  /// [glassFillFor]. Deliberately higher: an unblurred pane at the blurred
  /// opacity is a smear, not a surface.
  final double glassOpacityTv;

  /// The 1px lit top edge. 0 = off. The cheapest depth cue in UI, and the
  /// thing that separates "matte card" from "flat rectangle".
  final double sheen;

  /// Elevation at rest / raised / floating. Read through [shadowFor], which
  /// drops what a weak TV GPU cannot re-raster on every focus move.
  final List<BoxShadow> restShadow;
  final List<BoxShadow> raisedShadow;
  final List<BoxShadow> floatingShadow;

  const SurfaceTokens({
    required this.base,
    this.overrides = const {},
    required this.glassSigma,
    required this.glassOpacity,
    required this.glassOpacityTv,
    required this.sheen,
    required this.restShadow,
    required this.raisedShadow,
    required this.floatingShadow,
  });

  /// Today's app: filled panels, no blur, no sheen, no elevation ramp.
  ///
  /// Every value is a no-op — `fill` everywhere is exactly what every surface
  /// draws now, and the three shadow lists are empty so a site reading
  /// `shadowFor` gets what it already had (nothing from this layer; its own
  /// literals are untouched until it migrates).
  static const SurfaceTokens legacy = SurfaceTokens(
    base: SeparationModel.fill,
    glassSigma: 0,
    glassOpacity: 1,
    glassOpacityTv: 1,
    sheen: 0,
    restShadow: <BoxShadow>[],
    raisedShadow: <BoxShadow>[],
    floatingShadow: <BoxShadow>[],
  );

  /// What [family] may legally take.
  ///
  /// The caps are not style guidance — they are geometry facts, established by
  /// the §12 inventory:
  ///
  /// * **`settingsGroup`** is one filled container whose rows have ZERO
  ///   inter-row gap and an in-place `Border.all`. Dropping fill and border
  ///   both shifts every row by 1px and dissolves the grouping into an
  ///   undifferentiated stack. So: `fill` or `rule` only.
  /// * **`sheet` / `dialog`** — the fill IS the modal. Remove it and the page
  ///   shows through. So: `fill` or `glass` only.
  /// * **`card` / `shelfRow` / `hero`** carry their decoration outside the
  ///   layout path (focus borders are `Positioned.fill` overlays, row rhythm
  ///   comes from margin), so all four models are safe.
  ///
  /// A theme asking for something illegal is silently clamped rather than
  /// asserted, because a theme is data: the clamp is the contract, and
  /// `surface_tokens_test.dart` pins it.
  SeparationModel modelFor(SurfaceFamily family) {
    final want = overrides[family] ?? base;
    return _legal(family).contains(want) ? want : _fallbackFor(family, want);
  }

  static Set<SeparationModel> _legal(SurfaceFamily family) =>
      switch (family) {
        SurfaceFamily.settingsGroup => const {
          SeparationModel.fill,
          SeparationModel.rule,
        },
        SurfaceFamily.sheet ||
        SurfaceFamily.dialog => const {
          SeparationModel.fill,
          SeparationModel.glass,
        },
        SurfaceFamily.card ||
        SurfaceFamily.shelfRow ||
        SurfaceFamily.hero => const {
          SeparationModel.fill,
          SeparationModel.glass,
          SeparationModel.space,
          SeparationModel.rule,
        },
      };

  /// Where an illegal ask lands.
  ///
  /// `space` degrades to `rule` rather than to `fill` — a theme that asked for
  /// "no boxes" is better served by hairlines than by the boxes it was trying
  /// to remove. Everything else degrades to `fill`, the universal safe model.
  static SeparationModel _fallbackFor(
    SurfaceFamily family,
    SeparationModel want,
  ) {
    if (want == SeparationModel.space &&
        _legal(family).contains(SeparationModel.rule)) {
      return SeparationModel.rule;
    }
    return SeparationModel.fill;
  }

  /// The fill opacity a glass surface paints, given the platform.
  ///
  /// On TV there is no `BackdropFilter` — a full-screen blur is a per-frame
  /// saveLayer, and the existing player sheets already prove the pattern by
  /// swapping to an opaque plate. So a glass theme on TV renders the same
  /// panes at [glassOpacityTv]. That is a stated property of glass themes on
  /// TV, not a degradation bug.
  double glassFillFor(bool isTv) => isTv ? glassOpacityTv : glassOpacity;

  /// Blur sigma, or 0 on TV.
  double glassSigmaFor(bool isTv) => isTv ? 0 : glassSigma;

  /// Elevation, with the TV filter the shape layer already established:
  /// only cheap, near-hard shadows survive a focus move on a weak GPU.
  List<BoxShadow> shadowFor(List<BoxShadow> level, bool isTv) => isTv
      ? [
          for (final s in level)
            if (s.blurRadius <= 6) s,
        ]
      : level;
}
