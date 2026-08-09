import 'package:flutter/material.dart';

import '../widgets/detail/theme/detail_theme.dart';
import 'app_ambience.dart';
import 'app_art.dart';
import 'app_focus.dart';
import 'app_light.dart';
import 'app_motion.dart';
import 'app_sound.dart';
import 'app_surface.dart';
import 'theme_spec.dart';

/// The five looks, as specs.
///
/// Each is the Dart translation of an approved concept in
/// `premium_looks_mockup/` — the values here and the CSS there are meant to
/// agree, and where they cannot (blur on TV, grain on TV) the mockup's own
/// "on tv" note says so.
///
/// **Provisional until W6 device signoff.** Snapshot tests pin what each spec
/// derives to, so a change to the derivation cannot silently restyle a look;
/// the snapshots themselves are ordinary reviewed diffs until the looks are
/// frozen (plan §4).
///
/// Ids deliberately reuse none of the twenty existing theme ids, so a stored
/// old id can never resolve to a new look (plan §8).
abstract final class PremiumLooks {
  /// **Obsidian Glass** — everything is a floating pane of tinted glass over
  /// the artwork. Cold, quiet, Apple TV+.
  ///
  /// On TV the blur is replaced by the opaque recipe; that is the concept's
  /// stated TV property, not a bug.
  static const glass = ThemeSpec(
    id: 'glass',
    label: 'Obsidian Glass',
    subtitle: 'Floating panes of tinted glass over the artwork',
    ground: Color(0xFF05070A),
    sunken: Color(0xFF030508),
    raised: Color(0xFF101620),
    ink: Color(0xFFF2F5F8),
    accent: Color(0xFF7FD4FF),
    separation: SeparationModel.glass,
    // Settings cannot take glass — a grouped container of translucent rows is
    // unreadable — so it falls to the hairline model.
    separationOverrides: {SurfaceFamily.settingsGroup: SeparationModel.rule},
    scrim: ScrimStyle.blurBand,
    frame: ArtFrame.contained,
    focusExpression: FocusExpression.ring,
    motion: MotionCharacter.glide,
    entrance: EntranceStyle.fadeUp,
    idle: IdlePolicy.dimChrome,
    skeleton: SkeletonStyle.pulse,
    radius: 14,
    reactiveRoom: 0.22,
    sheen: 0.10,
    bloom: 18,
  );

  /// **Deep Field** — no boxes anywhere. Artwork bleeds full-frame and space
  /// alone does the separating.
  ///
  /// The cheapest look on TV: no blur, no fills, shadows only around focus.
  static const field = ThemeSpec(
    id: 'field',
    label: 'Deep Field',
    subtitle: 'Artwork bleeds; space alone separates',
    ground: Color(0xFF000000),
    sunken: Color(0xFF000000),
    raised: Color(0xFF0A0A0C),
    ink: Color(0xFFFFFFFF),
    accent: Color(0xFFE8503A),
    separation: SeparationModel.space,
    scrim: ScrimStyle.bottomGradient,
    frame: ArtFrame.bleed,
    focusExpression: FocusExpression.scale,
    motion: MotionCharacter.settle,
    entrance: EntranceStyle.stagger,
    idle: IdlePolicy.theater,
    skeleton: SkeletonStyle.pulse,
    radius: 3,
    pillRadius: 3,
    // The one look that lets the room take the film's colour.
    reactiveRoom: 0.72,
    // The one look that lets a poster's colour become the accent. The room
    // tints far here, and a fixed hue fighting a tinted room is exactly the
    // "every colour lit at once" failure the cull was for.
    artworkAccent: true,
    vignette: 0.55,
    bloom: 26,
    rowHeight: 1.1,
    cardScale: 1.05,
    pageGutter: 1.18,
    sectionGap: 1.2,
  );

  /// **Warm Room** — matte and unhurried, lit from above. The one you leave on
  /// at eleven at night.
  static const hearth = ThemeSpec(
    id: 'hearth',
    accentButton: true,
    // Weight without chatter: nothing on traversal, a confirmation on
    // activation. A warm room is not a machine room.
    feedback: FeedbackCharacter.confirming,
    label: 'Warm Room',
    subtitle: 'Matte, warm and unhurried',
    ground: Color(0xFF141110),
    sunken: Color(0xFF1D1917),
    raised: Color(0xFF252019),
    ink: Color(0xFFF6EFE6),
    accent: Color(0xFFE8A13C),
    separation: SeparationModel.fill,
    scrim: ScrimStyle.plate,
    frame: ArtFrame.faded,
    grade: ArtGrade.warm,
    focusExpression: FocusExpression.lift,
    motion: MotionCharacter.glide,
    entrance: EntranceStyle.fadeUp,
    idle: IdlePolicy.dimChrome,
    radius: 12,
    reactiveRoom: 0.18,
    sheen: 0.16,
    bloom: 22,
    rowHeight: 1.08,
    pageGutter: 1.1,
    sectionGap: 1.15,
  );

  /// **Console** — hairlines, monospace and hard edges. An instrument, not a
  /// store. Focus inverts the way a terminal shows selection.
  ///
  /// Nothing here costs anything on TV: no blur, no shadow, no grading.
  static const console = ThemeSpec(
    id: 'console',
    accentButton: true,
    // The only look that ticks. Console is the one whose whole idea is that
    // the app is an INSTRUMENT — hard corners, invert focus, linear curves —
    // and a mechanism that moves silently is the one detail that would give
    // it away.
    feedback: FeedbackCharacter.mechanical,
    label: 'Console',
    subtitle: 'Hairlines and monospace; focus inverts',
    ground: Color(0xFF080B09),
    sunken: Color(0xFF050706),
    raised: Color(0xFF0C100D),
    ink: Color(0xFFD8E0D8),
    accent: Color(0xFF8CE0A8),
    separation: SeparationModel.rule,
    scrim: ScrimStyle.plate,
    frame: ArtFrame.contained,
    // Deliberately no grade: in this look artwork is data, not mood.
    focusExpression: FocusExpression.invert,
    motion: MotionCharacter.snap,
    skeleton: SkeletonStyle.scanlines,
    radius: 0,
    pillRadius: 0,
    displayFont: DetailFontRole.mono,
    bodyFont: DetailFontRole.mono,
    reactiveRoom: 0,
    rowHeight: 0.88,
    cardScale: 0.9,
    pageGutter: 0.8,
    sectionGap: 0.78,
  );

  /// **Midnight Cinema** — grain, letterbox and a warm grade. The app as a
  /// screening room.
  ///
  /// On TV this look loses BOTH its speckle and its grade: `grainFor` forces
  /// grain to 0 and `gradeFor` forces the sepia to none, for the same reason
  /// in both cases — a per-frame raster cost on a weak GPU. What survives is
  /// what costs nothing: the letterbox mat, the warm ground and ink, the
  /// amber accent and the settle tempo. That is still a screening room; it is
  /// just one with a clean print.
  static const reel = ThemeSpec(
    id: 'reel',
    accentButton: true,
    label: 'Midnight Cinema',
    subtitle: 'Grain, letterbox and a warm grade',
    ground: Color(0xFF0A0908),
    sunken: Color(0xFF070605),
    raised: Color(0xFF12100E),
    ink: Color(0xFFEDE4D8),
    accent: Color(0xFFD9A441),
    separation: SeparationModel.fill,
    scrim: ScrimStyle.plate,
    frame: ArtFrame.matted,
    grade: ArtGrade.sepia,
    focusExpression: FocusExpression.lift,
    motion: MotionCharacter.settle,
    entrance: EntranceStyle.fadeUp,
    idle: IdlePolicy.theater,
    radius: 4,
    pillRadius: 4,
    grain: 0.07,
    reactiveRoom: 0.2,
    bloom: 24,
    rowHeight: 1.05,
    pageGutter: 1.05,
    sectionGap: 1.1,
  );


  /// **Spotlight** — the tvOS idiom.
  ///
  /// The only look whose focus expression is [FocusExpression.parallax], and
  /// the reason that value exists: cards lift, tilt on a 700px perspective and
  /// catch a specular highlight, spring-driven so a fast traversal keeps its
  /// momentum. Everything else here exists to stay out of that mechanic's way.
  ///
  /// `reactiveRoom: 0` because the detail page's own ambient field IS the
  /// ground — the shell's accent wash on top of it is a second, differently
  /// coloured light in the same room.
  static const spotlight = ThemeSpec(
    id: 'spotlight',
    label: 'Spotlight',
    subtitle: 'Full-bleed art, borderless focus, ambient detail',
    // MEASURED off the reference, not chosen: rgb(28,28,28) at every gutter of
    // a scrolled frame — a neutral grey, not black.
    ground: Color(0xFF1B1C1C),
    sunken: Color(0xFF151616),
    raised: Color(0xFF242525),
    ink: Color(0xFFFFFFFF),
    // White, not a hue. The reference has no accent colour anywhere: state is
    // carried by the lift and by a solid-white primary button.
    accent: Color(0xFFFFFFFF),
    accentButton: true,
    separation: SeparationModel.fill,
    scrim: ScrimStyle.bottomGradient,
    frame: ArtFrame.bleed,
    focusExpression: FocusExpression.parallax,
    motion: MotionCharacter.settle,
    entrance: EntranceStyle.fadeUp,
    idle: IdlePolicy.dimChrome,
    radius: 7,
    reactiveRoom: 0,
  );

  /// In picker order.
  static const List<ThemeSpec> all = [glass, field, hearth, console, reel, spotlight];

  static ThemeSpec? byId(String id) {
    for (final s in all) {
      if (s.id == id) return s;
    }
    return null;
  }
}
