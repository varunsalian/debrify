import 'package:flutter/material.dart';

import '../widgets/detail/theme/detail_theme.dart';
import 'app_theme_scope.dart';

/// A theme's tempo.
///
/// The tree has ~680 hardcoded `Duration(milliseconds:)` sites and no token, so
/// there is no single place to turn motion down on a weak box — a live problem
/// on Amlogic/Xiaomi hardware. The defaults below are the durations already
/// most common in the tree, so adopting a token at a site is usually a no-op.
/// How motion FEELS, as opposed to how long it lasts.
///
/// The tempo scalar shipped in phase three is the weak version of this: a
/// theme that is 15% slower is not a different theme. Character changes the
/// curve and the duration together, which is what makes `snap` feel like a
/// terminal and `settle` feel like something with mass.
enum MotionCharacter {
  /// The shipped feel: ease-out cubic at the shipped durations.
  standard,

  /// No easing worth the name, minimum durations. Instruments do not glide.
  snap,

  /// Long decelerations. Everything arrives late and softly.
  glide,

  /// Slight overshoot, as though the thing has weight.
  settle,
}

/// The focus spring for [MotionCharacter.settle].
///
/// `damping` is spelled out rather than built with
/// `SpringDescription.withDampingRatio` because that factory is not `const`,
/// and [MotionTokens.of] must stay const. It is the same number:
/// `2ζ√(k·m)` = `2 × 0.82 × √210` ≈ 23.77.
///
/// ζ = 0.82 is the reference's damping, and it is under 1 on purpose — at 1.0
/// the spring is critically damped and settles without ever passing its mark,
/// which is exactly the "it moved" feeling this is meant to replace.
const SpringDescription kSettleFocusSpring = SpringDescription(
  mass: 1,
  stiffness: 210,
  damping: 23.77,
);

/// How a page's content arrives.
enum EntranceStyle {
  /// It is simply there. Today's app on TV, and the legacy pin.
  none,

  /// One cross-fade for the whole page.
  fadeUp,

  /// Rows arrive in sequence — the reveal the catalog detail already has, and
  /// already skips on TV.
  stagger,
}

@immutable
class MotionTokens {
  /// A state change the eye should barely register — a chip filling, a ring
  /// appearing.
  ///
  /// The named durations are the VOCABULARY; the sites adopted so far use
  /// [AppMotion.scaled] around their own literal instead, because that is what
  /// keeps legacy exact at a site whose shipped duration is 150 rather than
  /// one of these. New motion should reach for the names; existing motion
  /// migrates by keeping its number and gaining the theme's tempo.
  final Duration fast;

  /// The workhorse: sheets, dialogs, cross-fades.
  final Duration base;

  /// A deliberate, watchable move — a hero settling, a stage taking over.
  final Duration slow;

  /// Everything decelerating into place.
  final Curve standard;

  /// Something arriving with weight. Overshoots; never use it on a size that
  /// clips.
  final Curve emphasized;

  /// The theme's own tempo, deliberately a narrow range. A theme that takes 2×
  /// as long to open a sheet does not read as characterful, it reads as lag.
  final double scale;

  /// The feel. Sets curve and duration together — see [MotionCharacter].
  final MotionCharacter character;

  /// How page content arrives. Skipped on TV by [entranceFor], which is what
  /// the catalog detail's reveal controller already does by hand.
  final EntranceStyle entrance;

  /// Physics for focus travel, when the character has any.
  ///
  /// Null everywhere except [MotionCharacter.settle], whose whole definition
  /// is that things have mass — every other character keeps the curve path and
  /// `ParallaxFocus` falls back to [emphasized].
  ///
  /// A spring rather than a curve because of ONE property: it can be re-seeded
  /// mid-flight with its current velocity. Hold a direction down and travel
  /// six cards and a curve restarts from zero at each one; a spring carries
  /// through. That is the difference the reference has and an eased scale
  /// does not.
  final SpringDescription? focusSpring;

  const MotionTokens({
    required this.fast,
    required this.base,
    required this.slow,
    required this.standard,
    required this.emphasized,
    required this.scale,
    this.character = MotionCharacter.standard,
    this.entrance = EntranceStyle.none,
    this.focusSpring,
  });

  /// [character] resolved into the pair of curves and the tempo it implies.
  ///
  /// Derived rather than stored so a character can never disagree with the
  /// curves beside it — the failure mode where a theme says `snap` and then
  /// eases for 360ms because someone set the fields independently.
  factory MotionTokens.of(MotionCharacter c) => switch (c) {
    MotionCharacter.standard => legacy,
    MotionCharacter.snap => const MotionTokens(
      fast: Duration(milliseconds: 60),
      base: Duration(milliseconds: 90),
      slow: Duration(milliseconds: 140),
      standard: Curves.linear,
      emphasized: Curves.linear,
      // 1.0, NOT 0.85: the durations above already ARE the tempo. `AppMotion`
      // multiplies by `scale` on the way out, so a character that also scaled
      // would apply its own tempo twice — snap's advertised 90ms base would
      // arrive as 76.5ms. `scale` exists for a look that wants the standard
      // durations at a different pace, which is not what a character does.
      scale: 1,
      character: MotionCharacter.snap,
    ),
    MotionCharacter.glide => const MotionTokens(
      fast: Duration(milliseconds: 160),
      base: Duration(milliseconds: 300),
      slow: Duration(milliseconds: 520),
      standard: Curves.easeOutQuart,
      emphasized: Curves.easeOutQuint,
      scale: 1,
      character: MotionCharacter.glide,
    ),
    MotionCharacter.settle => const MotionTokens(
      fast: Duration(milliseconds: 140),
      base: Duration(milliseconds: 260),
      slow: Duration(milliseconds: 420),
      standard: Curves.easeOutCubic,
      emphasized: Curves.easeOutBack,
      scale: 1,
      character: MotionCharacter.settle,
      // ζ 0.82 — under-damped on purpose. At 1.0 the spring is critically
      // damped and never overshoots, which is the whole property `settle`
      // names.
      focusSpring: kSettleFocusSpring,
    ),
  };

  /// Entrance choreography is a full-screen animation on the one platform
  /// that cannot afford one.
  EntranceStyle entranceFor(bool isTv) => isTv ? EntranceStyle.none : entrance;

  /// Lives here rather than as a private extension elsewhere: a reconstruction
  /// helper that sits away from the constructor silently resets any field
  /// added later, and still compiles.
  /// NOTE: every field must be carried here. `ThemeSpec` builds its motion as
  /// `MotionTokens.of(character).copyWith(entrance: …)`, so a field this
  /// method forgets is silently dropped for every themed surface in the app —
  /// no error, just the feature quietly not working.
  MotionTokens copyWith({EntranceStyle? entrance, double? scale}) =>
      MotionTokens(
        fast: fast,
        base: base,
        slow: slow,
        standard: standard,
        emphasized: emphasized,
        scale: scale ?? this.scale,
        character: character,
        entrance: entrance ?? this.entrance,
        focusSpring: focusSpring,
      );

  static const MotionTokens legacy = MotionTokens(
    fast: Duration(milliseconds: 120),
    base: Duration(milliseconds: 220),
    slow: Duration(milliseconds: 360),
    standard: Curves.easeOutCubic,
    emphasized: Curves.easeOutBack,
    scale: 1,
  );

  factory MotionTokens.fromDetail(DetailTheme core) => MotionTokens(
    fast: legacy.fast,
    base: legacy.base,
    slow: legacy.slow,
    standard: legacy.standard,
    emphasized: legacy.emphasized,
    // Editorial themes — the ones with grain or set in caps — carry
    // themselves a little more slowly; technical ones (a hard cursor, no
    // elevation) snap. Everything else is the shipped tempo.
    scale: (core.grain > 0 || core.displayUpper)
        ? 1.15
        : (core.shadow.isEmpty && core.focusWidth <= 1.5)
        ? 0.85
        : 1.0,
  );
}

/// The only supported way to read a duration or curve from the theme.
///
/// Exists as a separate resolver rather than a raw token read because two
/// things can only be answered where a [BuildContext] is: the platform's
/// reduced-motion setting, and the fact that a theme change must retarget
/// controllers that are already alive.
///
/// ## Where a site may call this
///
/// 1. **A `State` that owns an `AnimationController`** resolves in
///    `didChangeDependencies` — build the controller in `initState` with a
///    literal, then assign `controller.duration` here. That is the one hook
///    that may depend on inherited widgets *and* re-runs when they change, so
///    a theme or accessibility switch retargets a live controller. Assigning
///    `duration` mid-flight is safe: Flutter reads it when the controller is
///    next started, and does not disturb a run in progress.
/// 2. **Stateless animated widgets** (`AnimatedContainer`, `AnimatedOpacity`,
///    `AnimatedSwitcher`) read it in `build`, hoisted above any builder
///    callback exactly like `AppThemeScope.of`.
/// 3. **Never inside a transition or `AnimatedBuilder` callback** — that is a
///    per-frame inherited lookup, and the house rule forbids it. Route curves
///    belong to the memoized `ThemeData`, not to a per-frame read.
///
/// ## What reduced motion does and does not reach
///
/// `MediaQuery.disableAnimations` collapses every duration THIS API vends to
/// zero. It cannot reach route-controller duration (a `PageTransitionsBuilder`
/// receives an animation the route already created) and it does not reach
/// literals that have not been migrated. Both are stated limits, not bugs.
///
/// **It applies under the legacy theme too, and that is deliberate.** The
/// house rule is that legacy renders byte-for-byte what it always has — and
/// this is the one considered exception, so it is written down rather than
/// discovered. A site that adopts a motion token stops animating on a device
/// whose owner has switched "Remove animations" on, whichever theme they are
/// using. Gating accessibility on a cosmetic preference would be the wrong
/// trade in the other direction, and the app already honours the flag in one
/// place (`stremio_tv_tuner.dart`). Legacy identity therefore means: **at the
/// platform's default motion setting.** `shape_type_motion_test.dart` pins
/// both halves of that sentence.
@immutable
class AppMotion {
  final MotionTokens tokens;

  /// True when the platform asks for reduced motion, or the caller is a
  /// surface that has opted out.
  final bool reduced;

  const AppMotion(this.tokens, {required this.reduced});

  static AppMotion of(BuildContext context) => AppMotion(
    AppThemeScope.of(context).motion,
    reduced: MediaQuery.maybeDisableAnimationsOf(context) ?? false,
  );

  Duration get fast => scaled(tokens.fast);
  Duration get base => scaled(tokens.base);
  Duration get slow => scaled(tokens.slow);

  Curve get standard => tokens.standard;
  Curve get emphasized => tokens.emphasized;

  /// [d] at this theme's tempo — or nothing at all under reduced motion.
  ///
  /// Rounds to whole microseconds, so a scaled duration is still exact rather
  /// than carrying a float remainder into a controller.
  Duration scaled(Duration d) {
    if (reduced) return Duration.zero;
    if (tokens.scale == 1) return d;
    return Duration(
      microseconds: (d.inMicroseconds * tokens.scale).round(),
    );
  }
}
