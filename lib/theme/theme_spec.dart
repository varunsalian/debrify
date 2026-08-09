import 'package:flutter/material.dart';

import '../widgets/detail/theme/detail_theme.dart';
import 'app_ambience.dart';
import 'app_art.dart';
import 'app_focus.dart';
import 'app_light.dart';
import 'app_motion.dart';
import 'app_sound.dart';
import 'app_surface.dart';
import 'app_theme.dart';

/// A look, as the twelve decisions someone actually makes.
///
/// `DetailTheme` has ~50 fields. Twenty themes × fifty fields is what produced
/// "every colour role lit at once": most of those fields are not decisions,
/// they are consequences, and asking an author to fill them in is asking them
/// to get something wrong. A spec states what the look IS and the derivation
/// works out the rest.
///
/// ## Where authority lives
///
/// One direction, one owner: **spec → complete `DetailTheme` core →
/// `AppTheme.fromDetail` → the twelve colour subprofiles and every token
/// group.** This class does not duplicate `fromDetail`'s rules; it feeds them
/// and then hands `fromDetail` the phase-four groups it cannot infer. The
/// no-agent-adds-a-token rule covers the whole chain.
///
/// ## What may be left unset, and what may not
///
/// **Meaning roles are required.** `state`, `callout`, `calloutText`, `focus`,
/// the button inks — those carry semantics (a measurement, an alert, a
/// cursor), and a silent neutral default would make a theme quietly wrong
/// rather than visibly incomplete. They are either given here or derived by
/// `fromDetail`'s existing reviewed rules.
///
/// **Texture-class dimensions may be omitted**: grain, grade, sound, idle,
/// entrance. A look with no opinion about grain genuinely has no opinion, and
/// the neutral value is correct rather than a guess.
@immutable
class ThemeSpec {
  // ── identity ──────────────────────────────────────────────────────────
  final String id;
  final String label;
  final String subtitle;

  // ── 1. ground and ink ─────────────────────────────────────────────────
  /// The page. Everything else is positioned relative to this.
  final Color ground;

  /// The deepest surface — rails, stages, anything that recedes.
  final Color sunken;

  /// The raised surface — panels, sheets, cards under `fill`.
  final Color raised;

  /// Primary ink. `tx2`/`tx3` derive from it.
  final Color ink;

  // ── 2. accent and meaning ─────────────────────────────────────────────
  /// Identity. The one colour a user would name if asked what this look is.
  final Color accent;

  /// A measurement — progress, watched, bound. Defaults to [accent].
  final Color? state;

  /// An attention flag — UP NEXT, LIVE. Defaults to [accent].
  final Color? callout;

  /// The cursor. Defaults to [accent].
  final Color? focusColor;

  /// Whether the primary button is filled with the accent or with ink.
  ///
  /// An explicit decision because the mockups disagree: Obsidian Glass and
  /// Deep Field use a near-white button, while Warm Room, Console and
  /// Midnight Cinema fill theirs with the accent. Deriving it from the ground
  /// would have silently contradicted three of the five approved concepts.
  final bool accentButton;

  /// Whether this look lets a poster's own colour replace its accent.
  ///
  /// Separate from [reactiveRoom] on purpose. `reactiveRoom` is a MAGNITUDE —
  /// how far the shell tints — while this is a binary permission to substitute
  /// a semantic colour throughout the detail UI. Inferring one from the other
  /// meant a small numeric nudge flipped a large behaviour.
  final bool artworkAccent;

  // ── 3–12. the character dimensions ────────────────────────────────────
  final SeparationModel separation;
  final Map<SurfaceFamily, SeparationModel> separationOverrides;
  final ScrimStyle scrim;
  final ArtFrame frame;
  final ArtGrade grade;
  final FocusExpression focusExpression;
  final MotionCharacter motion;
  final EntranceStyle entrance;
  final IdlePolicy idle;
  final SkeletonStyle skeleton;

  /// Sound and haptics, as one decision — see [FeedbackCharacter].
  final FeedbackCharacter feedback;

  /// Corner character, as the details-page radius the shape scale derives
  /// from. 0 squares everything.
  final double radius;

  /// 999 keeps pills; anything lower squares them.
  final double pillRadius;

  final DetailFontRole displayFont;
  final DetailFontRole bodyFont;

  /// Film grain, 0 = none. Always 0 on TV.
  final double grain;

  /// How far the room follows the focused title, 0..1.
  final double reactiveRoom;

  /// The 1px lit top edge.
  final double sheen;

  /// Vignette weight and focus bloom radius.
  final double vignette;
  final double bloom;

  /// Density, clamped at derivation — a spec cannot express a layout change.
  final double rowHeight;
  final double cardScale;
  final double pageGutter;
  final double sectionGap;

  const ThemeSpec({
    required this.id,
    required this.label,
    required this.subtitle,
    required this.ground,
    required this.sunken,
    required this.raised,
    required this.ink,
    required this.accent,
    this.state,
    this.callout,
    this.focusColor,
    this.accentButton = false,
    this.artworkAccent = false,
    required this.separation,
    this.separationOverrides = const {},
    required this.scrim,
    required this.frame,
    this.grade = ArtGrade.none,
    required this.focusExpression,
    required this.motion,
    this.entrance = EntranceStyle.none,
    this.idle = IdlePolicy.none,
    this.skeleton = SkeletonStyle.shimmer,
    this.feedback = FeedbackCharacter.none,
    required this.radius,
    this.pillRadius = 999,
    this.displayFont = DetailFontRole.sans,
    this.bodyFont = DetailFontRole.sans,
    this.grain = 0,
    this.reactiveRoom = 0.2,
    this.sheen = 0,
    this.vignette = 0,
    this.bloom = 0,
    this.rowHeight = 1,
    this.cardScale = 1,
    this.pageGutter = 1,
    this.sectionGap = 1,
  });

  /// The complete `DetailTheme` this spec implies.
  ///
  /// Every field `DetailTheme` requires but a spec does not name is derived
  /// here, in one place, by rules that are stated rather than guessed at each
  /// call site.
  DetailTheme toCore() {
    Color mix(Color a, Color b, double t) => Color.lerp(a, b, t)!;
    final isLight = ground.computeLuminance() > 0.5;
    final acc = accent;

    return DetailTheme(
      id: id,
      label: label,
      subtitle: subtitle,
      ground: ground,
      pane: raised,
      railBg: sunken,
      // The body paints its ground opaquely over the shell tint on a light
      // theme. Without this a light spec would be classified light by
      // `AppTheme` and still render as a dark-ground detail page, because the
      // detail layouts read THIS flag rather than the luminance.
      lightGround: isLight,
      // Panel and hairline follow the SEPARATION model, not a fixed alpha.
      // A `space` look that still paints 7%-ink pills has not stopped having
      // boxes — it has boxes the token layer cannot see. The detail widgets
      // paint `panel` and `ghostFill` directly, so this is where those looks
      // actually lose their fills.
      panel: switch (separation) {
        SeparationModel.space => const Color(0x00000000),
        SeparationModel.rule => ink.withValues(alpha: 0.03),
        SeparationModel.glass => ink.withValues(alpha: 0.10),
        SeparationModel.fill => ink.withValues(alpha: 0.07),
      },
      hair: ink.withValues(
        alpha: separation == SeparationModel.rule ? 0.17 : 0.11,
      ),
      tx: ink,
      tx2: ink.withValues(alpha: 0.64),
      tx3: ink.withValues(alpha: 0.40),
      accent: acc,
      state: state ?? acc,
      callout: callout ?? acc,
      // Ink ON the callout swatch, by contrast rather than assumption.
      calloutText: _inkOn(callout ?? acc, ink, ground),
      award: state ?? acc,
      // Ratings are IMDb yellow everywhere; that is data, not identity.
      rating: const Color(0xFFF5C518),
      focus: focusColor ?? acc,
      // An explicit permission, never inferred from the room's magnitude.
      useArtworkAccent: artworkAccent,
      washOpacity: reactiveRoom,
      radius: radius,
      // Rounded to whole pixels, and artwork tracks the main radius rather
      // than sitting at a fraction of it. That is how the existing hard-edged
      // themes relate their radii — Broadsheet 2/2/2, Velvet 3/2/3, Sepia
      // 4/3/4 — and a 1.8px small radius on a 3px look is a number nobody
      // chose.
      radiusSm: (radius * 0.7).roundToDouble(),
      radiusBtn: pillRadius,
      radiusImg: radius,
      radiusCast: pillRadius,
      displayFont: displayFont,
      bodyFont: bodyFont,
      dataFont: DetailFontRole.mono,
      focusWidth: switch (focusExpression) {
        // An invert or a flood needs no ring; a hairline one would fight the
        // fill. The floor still applies on TV via focusWidthFor.
        FocusExpression.invert || FocusExpression.flood => 1,
        FocusExpression.ring => 2.5,
        _ => 2,
      },
      focusOffset: 0,
      shadow: _shadowFor(),
      grain: grain,
      grid: false,
      // Ink on the fill is SCORED either way, so an accent button cannot end
      // up with an unreadable label whatever hue the look picked.
      btnFill: accentButton ? acc : (isLight ? ink : mix(ground, ink, 0.94)),
      btnText: accentButton
          ? _inkOn(acc, ink, ground)
          : (isLight ? ground : mix(ink, ground, 0.94)),
      ghostFill: switch (separation) {
        SeparationModel.space => const Color(0x00000000),
        SeparationModel.rule => const Color(0x00000000),
        _ => ink.withValues(alpha: 0.10),
      },
      ghostBorder: ink.withValues(
        alpha: separation == SeparationModel.space ? 0.0 : 0.16,
      ),
      ghostText: ink,
    );
  }

  /// The elevation the separation model implies.
  ///
  /// Derived rather than specified because a `rule` or `space` look with a
  /// drop shadow is incoherent — the shadow is a fill's way of lifting, and
  /// those models lift with light or with nothing.
  List<BoxShadow> _shadowFor() => switch (separation) {
    SeparationModel.rule || SeparationModel.space => const <BoxShadow>[],
    SeparationModel.glass => const [
      BoxShadow(color: Color(0x5C000000), blurRadius: 26, offset: Offset(0, 12)),
    ],
    SeparationModel.fill => const [
      BoxShadow(color: Color(0x4D000000), blurRadius: 18, offset: Offset(0, 8)),
    ],
  };

  /// The complete theme.
  AppTheme build() => buildWith(toCore());

  /// The complete theme, over a core someone else has already adjusted.
  ///
  /// The controller resolves text colours against the user's text-brightness
  /// preset BEFORE deriving the subprofiles — the whole token surface follows
  /// that preset, not just Material's `onSurface`. So it needs to hand in its
  /// own core rather than let [build] make a fresh one, or a premium look
  /// would be the only theme in the app that ignores the setting.
  AppTheme buildWith(DetailTheme core) => AppTheme.fromDetail(
    core,
    surface: SurfaceTokens(
      base: separation,
      overrides: separationOverrides,
      glassSigma: separation == SeparationModel.glass ? 28 : 24,
      glassOpacity: 0.52,
      glassOpacityTv: 0.94,
      sheen: sheen,
      restShadow: const <BoxShadow>[],
      raisedShadow: _shadowFor(),
      floatingShadow: _shadowFor(),
    ),
    light_: LightTokens(
      scrim: scrim,
      scrimExtent: scrim == ScrimStyle.plate ? 0.42 : 0.62,
      scrimStrength: scrim == ScrimStyle.fullDim ? 0.68 : 0.92,
      vignette: vignette,
      focusBloom: bloom,
    ),
    art: ArtTokens(frame: frame, grade: grade, reactiveRoom: reactiveRoom),
    focus: FocusTokens(
      expression: focusExpression,
      width: switch (focusExpression) {
        FocusExpression.invert || FocusExpression.flood => 1,
        FocusExpression.ring => 2.5,
        _ => 2,
      },
      offset: 0,
      scale: switch (focusExpression) {
        FocusExpression.scale => 1.06,
        FocusExpression.lift => 1.02,
        _ => 1,
      },
      lift: focusExpression == FocusExpression.lift ? 8 : 0,
    ),
    motion: MotionTokens.of(motion).copyWith(entrance: entrance),
    idle: IdleTokens(
      policy: idle,
      after: const Duration(seconds: 30),
      depth: idle == IdlePolicy.theater ? 0.85 : 0.45,
    ),
    wait: WaitTokens(
      skeleton: skeleton,
      period: const Duration(milliseconds: 1200),
    ),
    density: DensityTokens.clamped(
      rowHeight: rowHeight,
      cardScale: cardScale,
      pageGutter: pageGutter,
      sectionGap: sectionGap,
    ),
    sound: soundTokensFor(feedback),
  );
}

/// Ink for content on a filled swatch, scored rather than assumed — the same
/// rule and threshold as `AppTheme.inkOn`, which cannot be called here because
/// the instance does not exist yet.
Color _inkOn(Color fill, Color ink, Color ground) {
  double against(Color c) {
    final lf = fill.withValues(alpha: 1).computeLuminance();
    final li = c.withValues(alpha: 1).computeLuminance();
    final hi = li > lf ? li : lf;
    final lo = li > lf ? lf : li;
    return (hi + 0.05) / (lo + 0.05);
  }

  if (against(ink) >= 4.0) return ink;
  return against(ground) > against(ink) ? ground : ink;
}
