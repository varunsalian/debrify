import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../widgets/detail/theme/detail_theme.dart';

/// The non-colour half of a look: corner geometry, focus ring, elevation and
/// surface texture, promoted from the details page to the whole app.
///
/// ## Why a SCALE and not five named radii
///
/// The tree has ~1,650 `BorderRadius.circular` sites. Mapping each onto one of
/// [DetailTheme]'s five named radii would be ~1,650 judgement calls, every one
/// of which can be wrong and none of which a test can check.
///
/// The details page already solved this once, for artwork:
///
/// ```dart
/// BorderRadius imgRadius(double site) => BorderRadius.circular(site * radiusImg / 8);
/// ```
///
/// **The site owns the hierarchy; the theme owns the scale.** A site keeps the
/// number it was drawn with and the theme multiplies it, so migrating a site is
/// mechanical, a half-finished sweep is coherent rather than broken, and legacy
/// is identical by construction because its scale is exactly 1.
///
/// ## Growth is damped AND capped; shrinking is neither
///
/// Flutter normalises an `RRect`'s radii to the box it is drawn in, so a theme
/// with `scale > 1` can turn a short control into a lozenge: a control of
/// height `H` becomes a pill once its radius reaches `H / 2`. Aurora's raw 1.8
/// would take a 14px radius to 25px — a pill on any control under 50px tall,
/// and a row of pills has lost exactly the hierarchy the scale exists to keep.
///
/// Two bounds, both only on the growing side:
///
/// * **Damping.** A raw scale above 1 is halved toward 1, the same treatment
///   and the same reasoning as `TypeTokens.titleScale`: the statement a
///   details-page hero is allowed to make is not one a settings row can make.
///   Aurora 1.80 → 1.40, Frost 1.60 → 1.30, Halo 1.40 → 1.20.
/// * **A cap of [_growthCap] = 16**, chosen against the geometry rather than
///   against the literals: standard controls in this app are 36px and taller,
///   and `36 / 2 = 18`, so a radius GROWN to at most 16 cannot pill one.
///
/// And growth never *shrinks*: a site already drawn above the cap keeps its own
/// radius (`max(site, cap)`), because the cap exists to stop small radii
/// climbing, not to flatten large cards.
///
/// **What that does and does not guarantee.** The precise claim is: *this
/// class never makes a corner rounder than 16px, and never rounder than the
/// site already asked for.* It is NOT "no control is ever a pill" — a site
/// that already draws `circular(20)` renders 20 here exactly as it does today,
/// and if that pills something, it pills it in the shipped app too. Growth is
/// what this bounds; the existing design is not this class's to second-guess.
///
/// The residual case is a control SHORTER than 32px whose authored radius is
/// between ~11 and 16: a growing theme can round it further than today. That
/// is a softening of something already nearly circular, not the collapse of a
/// rectangle — and a rule that could promise more would need the receiving
/// box's height, which a token cannot see.
///
/// `scale <= 1` is untouched by all of this — every square theme, and
/// critically legacy, whose arithmetic is exactly the identity.
@immutable
class ShapeTokens {
  /// Multiplies a site's own surface radius. `core.radius / 10`, the shipped
  /// body radius being the baseline every site was drawn against.
  final double scale;

  /// The same idea for artwork: `core.radiusImg / 8`, matching the baseline
  /// [DetailTheme.imgRadius] uses.
  ///
  /// **It is damped like [scale], so it deliberately diverges from
  /// `imgRadius` on a growing theme** — Aurora is 1.375 here against 1.75
  /// there. Same reasoning as `TypeTokens.titleScale`: a details-page hero
  /// poster can wear a 24px corner, and a 40px channel logo in a rail cannot.
  /// The details page keeps its own undamped formula; this is the app's.
  final double imgScale;

  /// What a pill sentinel becomes. 999 keeps the pill; a theme that squares
  /// its buttons (`radiusBtn` below 999) squares every pill with it.
  final double pill;

  /// The DPAD cursor. Read through [focusWidthFor]/[focusOffset] — never
  /// bypassed, so the 2.5px TV floor cannot be lost.
  ///
  /// Adoption is per-site and deliberately partial: `TvFocusableCard` reads it
  /// (gated on `isLegacy`, because its shipped 3px is thicker than Signal's
  /// own 2.5), and the remaining focus sites keep their literals until someone
  /// judges each one. A cursor is the single most safety-critical thing on a
  /// TV screen, so this is not a dimension to sweep mechanically.
  final double focusWidth;

  /// How far outside its bounds a theme draws the cursor. **Carried, not yet
  /// consumed**: Signal draws in-bounds and every current focus site assumes
  /// that, so honouring an outward offset means each site making room for it —
  /// a layout change, not a token read.
  final double focusOffset;

  /// The theme's elevation. Read through [shadowFor], which drops blurs a weak
  /// TV GPU cannot re-raster on every focus move.
  ///
  /// **Carried, not yet consumed app-wide.** The details page reads its own
  /// `DetailTheme.shadow`; promoting elevation means deciding per surface
  /// whether a theme's shadow replaces or composes with what the site already
  /// draws, and that is a design pass rather than a token wiring.
  final List<BoxShadow> shadow;

  /// Film grain, 0 = off. Read through [grainFor] — always 0 on TV.
  final double grain;

  /// Blueprint's 32px rule. Gated on TV by [gridFor] for the same reason.
  final bool grid;

  const ShapeTokens({
    required this.scale,
    required this.imgScale,
    required this.pill,
    required this.focusWidth,
    required this.focusOffset,
    required this.shadow,
    required this.grain,
    required this.grid,
  });

  /// The largest radius a growing theme may produce for a site drawn below it.
  ///
  /// Chosen from control geometry, not from the literal distribution: the
  /// app's standard controls are 36px and taller, and a box becomes a pill at
  /// `height / 2` = 18, so 16 leaves a margin and cannot lozenge one.
  static const double _growthCap = 16;

  /// A raw scale above 1, halved toward 1. See the class doc.
  static double dampGrowth(double raw) => raw <= 1 ? raw : 1 + (raw - 1) * 0.5;

  /// Today's app: every site renders the number it was drawn with.
  static const ShapeTokens legacy = ShapeTokens(
    scale: 1,
    imgScale: 1,
    pill: 999,
    // Signal's shipped cursor.
    focusWidth: 2.5,
    focusOffset: 0,
    shadow: <BoxShadow>[],
    grain: 0,
    grid: false,
  );

  factory ShapeTokens.fromDetail(DetailTheme core) => ShapeTokens(
    scale: dampGrowth(core.radius / 10),
    imgScale: dampGrowth(core.radiusImg / 8),
    pill: core.radiusBtn >= 999 ? 999 : core.radiusBtn,
    focusWidth: core.focusWidth,
    focusOffset: core.focusOffset,
    shadow: core.shadow,
    grain: core.grain,
    grid: core.grid,
  );

  /// A site's own radius, scaled. See the class doc for the growth cap.
  double r(double site) => scale <= 1
      ? site * scale
      : math.min(site * scale, math.max(site, _growthCap));

  /// Any surface — cards, chips, sheets, buttons with a numeric radius.
  BorderRadius br(double site) => BorderRadius.circular(r(site));

  /// Artwork — posters, stills, backdrops, channel logos.
  double rImg(double site) => imgScale <= 1
      ? site * imgScale
      : math.min(site * imgScale, math.max(site, _growthCap));

  BorderRadius brImg(double site) => BorderRadius.circular(rImg(site));

  /// What `BorderRadius.circular(999)` and `circular(99)` meant.
  ///
  /// Both sentinels are in the tree (999 × 85, 99 × 9) and both mean "a pill",
  /// so both migrate here and the shape ratchet forbids either from coming
  /// back as a literal.
  BorderRadius get brPill => BorderRadius.circular(pill);

  /// The cursor must survive at three metres whatever the theme asked for —
  /// the same rule and the same floor as [DetailTheme.focusWidthFor].
  double focusWidthFor(bool isTv) => isTv ? math.max(focusWidth, 2.5) : focusWidth;

  /// Only cheap, near-hard shadows survive on TV — big blurs re-raster on
  /// every focus move.
  List<BoxShadow> shadowFor(bool isTv) => isTv
      ? [
          for (final s in shadow)
            if (s.blurRadius <= 6) s,
        ]
      : shadow;

  /// Grain is a full-screen foreground layer; never on TV.
  double grainFor(bool isTv) => isTv ? 0 : grain;

  /// The rule overlay composites over everything that scrolls beneath it, so
  /// it follows grain's policy rather than being "just lines".
  ///
  /// (The details page's own [DetailTheme] does NOT gate grid on TV today.
  /// This is the app-wide policy; changing the details page's would move
  /// shipped pixels on Blueprint and belongs in its own change.)
  bool gridFor(bool isTv) => isTv ? false : grid;
}
