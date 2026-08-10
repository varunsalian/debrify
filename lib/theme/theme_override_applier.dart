import '../widgets/detail/theme/detail_theme.dart';
import 'app_ambience.dart';
import 'app_art.dart';
import 'app_focus.dart';
import 'app_light.dart';
import 'app_motion.dart';
import 'app_sound.dart';
import 'app_surface.dart';
import 'app_theme.dart';
import 'theme_overrides.dart';
import 'theme_spec.dart';

/// Puts [ThemeOverrides] onto a theme, by whichever of the two routes the
/// selected theme has.
///
/// **Two arms, not one synthesised spec.** Only `spotlight` of the shipped
/// Looks has a `ThemeSpec`; the other themes resolve a core and take the
/// `*.legacy` token groups. Manufacturing a spec for those would give them a
/// baseline they were never authored against, and the first thing anyone would
/// notice is that changing the accent also moved the shadows. So a spec theme
/// has its spec edited, and a non-spec theme has its token groups supplied —
/// and a theme with no overrides goes down neither path.
abstract final class ThemeOverrideApplier {
  /// The spec arm: edit the authored values, then let `buildWith` derive as it
  /// always has.
  static ThemeSpec applyToSpec(ThemeSpec spec, ThemeOverrides o) => spec.copyWith(
        separation: o.resolvedSeparation,
        scrim: o.resolvedScrim,
        frame: o.resolvedFrame,
        grade: o.resolvedGrade,
        focusExpression: o.resolvedFocusExpression,
        motion: o.resolvedMotion,
        entrance: o.resolvedEntrance,
        idle: o.resolvedIdle,
        skeleton: o.resolvedSkeleton,
        feedback: o.resolvedFeedback,
        grain: o.resolvedGrain,
        sheen: o.resolvedSheen,
        vignette: o.resolvedVignette,
        bloom: o.resolvedBloom,
        reactiveRoom: o.resolvedReactiveRoom,
        artworkAccent: o.resolvedArtworkAccent,
        // Colour, radius and fonts are NOT set here. They go through the core,
        // which `buildWith` is handed — setting them in both places would
        // derive them twice from different inputs.
      );

  /// The non-spec arm: hand `fromDetail` the token groups the user has edited,
  /// and let it default the rest exactly as it does today.
  ///
  /// [authored] is the theme as the registry wrote it — BEFORE any core edits.
  /// It is needed because some token groups are derived from the core, and
  /// deriving them from the EDITED core is how a cosmetic change leaks into
  /// behaviour.
  static AppTheme buildFromDetail(
    DetailTheme core,
    ThemeOverrides o, {
    required DetailTheme authored,
  }) {
    // From the AUTHORED core, never the edited one.
    //
    // `MotionTokens.fromDetail` derives its tempo from grain, displayUpper,
    // shadow and focusWidth — so nudging the film grain would otherwise retime
    // every animation in the app. "It feels slower since I changed the texture"
    // is not a report anyone can act on.
    //
    // And it must be the theme's OWN tempo, not `MotionTokens.legacy`: themes
    // whose authored scale is 0.85 or 1.15 would be reset to 1.0 by an
    // unrelated entrance override.
    final motionBase = MotionTokens.fromDetail(authored);

    // The companion values matter as much as the expression.
    //
    // `FocusTokens.legacy` is a RING's geometry — scale 1, lift 0 — so picking
    // "scale" or "lift" and keeping them produces a focus effect that does
    // nothing at all. These are the same numbers `ThemeSpec.buildWith` derives,
    // deliberately, so the two arms express a given choice identically.
    final expression = o.resolvedFocusExpression;
    final focus = expression == null
        ? null
        : FocusTokens(
            expression: expression,
            width: switch (expression) {
              FocusExpression.invert || FocusExpression.flood => 1,
              FocusExpression.ring => 2.5,
              _ => 2,
            },
            offset: 0,
            scale: switch (expression) {
              FocusExpression.scale => 1.06,
              FocusExpression.lift => 1.02,
              _ => 1,
            },
            lift: expression == FocusExpression.lift ? 8 : 0,
          );

    final motionChar = o.resolvedMotion;
    final entrance = o.resolvedEntrance;
    // ALWAYS supplied, not just when motion was edited. Left null, `fromDetail`
    // derives the tempo from the edited core — which is the exact leak the
    // baseline above exists to prevent.
    final motion = (motionChar == null ? motionBase : MotionTokens.of(motionChar))
        .copyWith(entrance: entrance);

    final separation = o.resolvedSeparation;
    final sheen = o.resolvedSheen;
    final surface = (separation == null && sheen == null)
        ? null
        : SurfaceTokens(
            base: separation ?? SurfaceTokens.legacy.base,
            overrides: SurfaceTokens.legacy.overrides,
            // Glass has to be TRANSLUCENT to be glass. The legacy values are a
            // solid surface's, so choosing glass and keeping them yields an
            // opaque panel with a blur nobody can see through — the same
            // numbers the spec arm uses are applied here instead.
            glassSigma: separation == SeparationModel.glass
                ? 28
                : SurfaceTokens.legacy.glassSigma,
            glassOpacity: separation == SeparationModel.glass
                ? 0.52
                : SurfaceTokens.legacy.glassOpacity,
            glassOpacityTv: separation == SeparationModel.glass
                ? 0.94
                : SurfaceTokens.legacy.glassOpacityTv,
            sheen: sheen ?? SurfaceTokens.legacy.sheen,
            restShadow: SurfaceTokens.legacy.restShadow,
            raisedShadow: SurfaceTokens.legacy.raisedShadow,
            floatingShadow: SurfaceTokens.legacy.floatingShadow,
          );

    final scrim = o.resolvedScrim;
    final vignette = o.resolvedVignette;
    final bloom = o.resolvedBloom;
    final light = (scrim == null && vignette == null && bloom == null)
        ? null
        : LightTokens(
            scrim: scrim ?? LightTokens.legacy.scrim,
            scrimExtent: LightTokens.legacy.scrimExtent,
            scrimStrength: LightTokens.legacy.scrimStrength,
            vignette: vignette ?? LightTokens.legacy.vignette,
            focusBloom: bloom ?? LightTokens.legacy.focusBloom,
          );

    final frame = o.resolvedFrame;
    final grade = o.resolvedGrade;
    final room = o.resolvedReactiveRoom;
    final art = (frame == null && grade == null && room == null)
        ? null
        : ArtTokens(
            frame: frame ?? ArtTokens.legacy.frame,
            grade: grade ?? ArtTokens.legacy.grade,
            reactiveRoom: room ?? ArtTokens.legacy.reactiveRoom,
          );

    final idlePolicy = o.resolvedIdle;
    final idle = idlePolicy == null
        ? null
        : IdleTokens(
            policy: idlePolicy,
            after: IdleTokens.legacy.after,
            // Legacy's depth is 0 — "dim by nothing" — which would make every
            // idle policy but `none` a no-op.
            depth: idlePolicy == IdlePolicy.none ? 0 : 0.35,
          );

    final skeleton = o.resolvedSkeleton;
    final wait = skeleton == null
        ? null
        : WaitTokens(skeleton: skeleton, period: WaitTokens.legacy.period);

    final feedback = o.resolvedFeedback;
    final sound = feedback == null ? null : soundTokensFor(feedback);

    return AppTheme.fromDetail(
      core,
      focus: focus,
      motion: motion,
      surface: surface,
      light_: light,
      art: art,
      idle: idle,
      wait: wait,
      sound: sound,
    );
  }
}
