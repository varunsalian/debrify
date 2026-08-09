import 'package:flutter/material.dart';

/// How artwork is presented — framed, bled, matted, or dissolved into the
/// page.
enum ArtFrame {
  /// A rounded rectangle with a border, sitting on the page. Today's app.
  contained,

  /// Runs to the edge of its region with no visible boundary.
  bleed,

  /// Sits on a plate, like a print in a mount.
  matted,

  /// Masked so it fades into the ground rather than ending at an edge.
  faded,
}

/// A colour treatment applied to the artwork itself.
///
/// The loudest single signal in the whole vocabulary: when the CONTENT wears
/// the theme, nobody can mistake it for a recolour of the chrome.
enum ArtGrade { none, mono, sepia, warm, cool }

/// Artwork framing, grading, and how much of the room the artwork colours.
@immutable
class ArtTokens {
  final ArtFrame frame;
  final ArtGrade grade;

  /// How strongly the shell adopts the focused title's own hue, 0..1, on the
  /// existing `MainPageBridge.tvHeroTint` wire. 0 = the room never moves.
  final double reactiveRoom;

  const ArtTokens({
    required this.frame,
    required this.grade,
    required this.reactiveRoom,
  });

  /// Today's app: framed artwork, no grade, and the tint strength the TV
  /// shell already blends.
  static const ArtTokens legacy = ArtTokens(
    frame: ArtFrame.contained,
    grade: ArtGrade.none,
    reactiveRoom: 0.28,
  );

  /// Grading is off on TV.
  ///
  /// Not a guess — `stremio_tv_tuner.dart` already ships exactly this policy
  /// for its stage backdrop: a `ColorFiltered` off TV, and an explicit refusal
  /// on TV with the reason written into the comment ("a saveLayer that gets
  /// re-composited on every surf settle — heavy on TV"). This method is that
  /// precedent generalised.
  ArtGrade gradeFor(bool isTv) => isTv ? ArtGrade.none : grade;

  /// The blend the grade is applied with.
  ///
  /// Deliberately `Image(color:, colorBlendMode:)` rather than `ColorFiltered`
  /// — the former composites inside the image's own paint, the latter is a
  /// saveLayer per image. `null` means "paint the image untouched".
  ///
  /// **This is a performance HYPOTHESIS until the W1 fling benchmark says
  /// otherwise** (plan D5). If it fails, grading is demoted to the 24
  /// hero/single-image sites and never applied in a scrolling list.
  (Color, BlendMode)? blendFor(bool isTv) => switch (gradeFor(isTv)) {
    ArtGrade.none => null,
    // Saturation against grey desaturates without touching luminance.
    ArtGrade.mono => (const Color(0xFF808080), BlendMode.saturation),
    // `color` keeps the image's luminance and takes the tint's hue.
    ArtGrade.sepia => (const Color(0xFF6B4E2E), BlendMode.color),
    // Low-alpha overlays warm or cool the midtones without flattening them.
    ArtGrade.warm => (const Color(0x33C87A2E), BlendMode.softLight),
    ArtGrade.cool => (const Color(0x332E7AC8), BlendMode.softLight),
  };

  /// Faces are not title art.
  ///
  /// Five of the eight "chrome" image sites are cast headshots (§12). A
  /// saturation or hue move that flatters a poster makes a person look ill,
  /// so portraits opt out of grading entirely regardless of the theme.
  (Color, BlendMode)? blendForPortrait(bool isTv) => null;
}
