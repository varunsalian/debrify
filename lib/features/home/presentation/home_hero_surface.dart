import 'package:flutter/material.dart';

/// Geometry of the Home hero's ambient-trailer REGION — a right-anchored slab
/// that fills the hero band's height and bleeds to the right screen edge, into
/// which the trailer is painted and lightly feathered (slim neutral melts at
/// its left/top/bottom edges — no hard frame, but the picture stays
/// essentially clear). Shared by the hero spotlight (which keeps its title text
/// clear of the region) and the trailer layer (which paints the video) so
/// both agree on the rect. Origin is the hero band's own top-left.
///
/// Width-led: ~56% of the hero, so the title keeps the left ~44%. Returns null
/// for a band too short to read as a trailer (falls back to full-width text).
Rect? homeHeroTrailerRegionRect(double width, double heroH) {
  if (!width.isFinite || !heroH.isFinite || width <= 0 || heroH <= 0) {
    return null;
  }
  if (heroH < 170) return null; // too short — keep the full-width hero instead
  // Below this the region can't be both wide enough to read and leave room for
  // the title — and it also keeps the clamp() below well-formed (lower ≤ upper).
  if (width < 480) return null;
  final regionW = (width * 0.56).clamp(360.0, width);
  final left = width - regionW; // flush to the right screen edge
  return Rect.fromLTWH(left, 0, regionW, heroH);
}

/// Fraction of the region's width over which the IDLE key-art's left edge
/// dissolves into the hero (see the idle-art feathers). The title text ends at
/// the region's left, so at rest it sits over the dark side of this feather.
const double homeHeroTrailerFeatherFrac = 0.34;

/// Fraction for the LIVE video's left-edge melt — deliberately about half the
/// idle art's [homeHeroTrailerFeatherFrac]. The balance (user-tuned): the old
/// full-width feathers read as bleed over the picture, but fully crisp edges
/// read as a legacy boxed player — a slim melt keeps the picture essentially
/// untouched while its edges still dissolve into the stage.
const double homeHeroTrailerVideoFeatherFrac = 0.16;

/// Slight brightness lift painted flat over the live ambient trailer —
/// trailers are graded dark and the ambient region has no other light on it.
/// Low-alpha white: lifts the mids/shadows a touch without visibly milking
/// the highlights. Works in BOTH engine modes: over the underlay hole it
/// alpha-blends onto the native video via the system compositor; over the
/// texture path it's an ordinary fill. Tune the alpha to taste (0 = off).
const Color homeHeroTrailerBrightnessLift = Color(0x14FFFFFF);

/// One edge-feather for the hero's art/trailer region: a gradient from opaque
/// [c] at [begin] dissolving to transparent by [frac]. EASED stops (not a
/// linear two-stop ramp — that reads as a hard "veil edge" where the fade
/// starts): dense at the covered edge, long soft tail into the picture, the
/// Nuvio/Netflix gradient recipe. Still one baked gradient fill — no shader
/// mask, no per-frame cost — shared by the idle key-art and the live trailer
/// (the trailer at roughly half the art's fractions, so the picture stays
/// essentially clear) so the two states dissolve alike at the handover.
Widget homeHeroEdgeFeather(
  Alignment begin,
  Alignment end,
  Color c,
  double frac,
) {
  return DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: begin,
        end: end,
        colors: [
          c,
          c.withValues(alpha: 0.86),
          c.withValues(alpha: 0.42),
          c.withValues(alpha: 0.13),
          c.withValues(alpha: 0.0),
        ],
        stops: [0.0, frac * 0.28, frac * 0.56, frac * 0.80, frac],
      ),
    ),
  );
}
