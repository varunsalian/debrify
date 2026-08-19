import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../../utils/platform_util.dart';
import '../app_focus.dart';
import '../app_theme_scope.dart';

/// What kind of thing is lifting, which sets how far it may lift.
///
/// 1.1 is a POSTER figure. A 216-wide episode still at 1.1 grows 21px and eats
/// its neighbour's gap; a season pill grows more than its own gap. The
/// reference scales by what the thing is, so this does too.
enum ParallaxShape {
  poster(1.10),
  landscape(1.10),
  sourceCard(1.10),
  episodeStill(1.055),
  castCircle(1.08),
  pill(1.06),

  /// A full-width settings row or category cell. It needs the same lift and
  /// travelling glare as Spotlight cards, but only enough scale to separate
  /// from its neighbours without colliding with the dense list around it.
  settingsRow(1.018);

  const ParallaxShape(this.scale);

  /// Peak scale at full lift.
  final double scale;
}

/// Which way the cursor was travelling when it left the last item.
///
/// A boolean `focused` transition cannot tell you the arrival direction, and
/// the lean depends on it — so the directional handlers record it here
/// immediately before `requestFocus()`, and the arriving card reads it.
///
/// Also records WHEN, because arriving within [_rapid] of the previous move
/// means the user is holding a direction down and travelling, not stepping.
/// Card B's controller cannot inherit card A's velocity — they are different
/// objects — so a rapid arrival gets a larger initial kick instead. That is
/// the achievable version of "holding RIGHT feels continuous".
abstract final class ParallaxTravel {
  static const Duration _rapid = Duration(milliseconds: 220);

  /// A note older than this is not this arrival's — the focus change came from
  /// somewhere else (a tap, a restore) and must not inherit a stale lean.
  static const Duration _stale = Duration(milliseconds: 400);

  static Offset _dir = Offset.zero;
  static Duration _at = -_stale;
  static Duration _prev = -_stale;
  static bool _rapidNow = false;

  static final Stopwatch _clock = Stopwatch()..start();

  /// Injectable so a test can drive cadence without real time.
  @visibleForTesting
  static Duration Function() clock = () => _clock.elapsed;

  /// Call immediately BEFORE moving focus. [dir] is the travel direction:
  /// `(1, 0)` for RIGHT, `(0, -1)` for UP, and so on.
  static void note(Offset dir) {
    final now = clock();
    // "Rapid" is the gap between CONSECUTIVE MOVES, not the gap between this
    // note and the card reading it — focus arrives within a frame, so the
    // latter is always ~0 and would call every single step rapid.
    _rapidNow = (now - _prev) < _rapid;
    _prev = now;
    _dir = dir;
    _at = now;
  }

  /// Non-consuming peek at the cadence: whether the move in flight is part
  /// of a rapid run. BOTH cards of a step read this — the one gaining focus
  /// and the one losing it — so it must not consume the pending note the
  /// way [take] does.
  static bool get isRapid => _rapidNow && (clock() - _at) < _stale;

  /// The pending arrival, consumed by the card that gains focus.
  ///
  /// Returns `Offset.zero` when the move did not come from a directional key,
  /// which correctly produces a lift with no lean.
  static ({Offset dir, bool rapid}) take() {
    if (clock() - _at > _stale) return (dir: Offset.zero, rapid: false);
    final dir = _dir;
    _dir = Offset.zero;
    return (dir: dir, rapid: _rapidNow);
  }

  @visibleForTesting
  static void resetForTest() {
    _dir = Offset.zero;
    _at = -_stale;
    _prev = -const Duration(days: 1);
    _rapidNow = false;
    clock = () => _clock.elapsed;
  }
}

/// Marks a subtree that should get the FULL parallax on Android TV — the
/// spring, the tilt and the specular glare — instead of the cheap lite body
/// the platform otherwise degrades to.
///
/// The lite body exists because the full effect stutters when a whole *board*
/// of cards animates on a weak Mali box. A detail page is a different budget:
/// a handful of focusable cards, one lifting at a time, so it can afford the
/// real thing. Wrapping the detail Showcase in this scope opts it in without
/// touching the home board, settings or onboarding, which stay lite.
///
/// Absent (the default) means lite — so any tree that does not opt in keeps
/// the exact behaviour it shipped with.
class ParallaxRichScope extends InheritedWidget {
  const ParallaxRichScope({super.key, required super.child});

  static bool of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<ParallaxRichScope>() !=
      null;

  @override
  bool updateShouldNotify(ParallaxRichScope oldWidget) => false;
}

/// The tvOS focus effect: lift, rise, tilt, shift, travelling shadow and a
/// specular glare, spring-driven.
///
/// **Stateless on purpose.** It reads the expression and either returns
/// [child] verbatim or mounts [_ParallaxBody]. Returning `child` from a
/// `State.build` would not avoid that `State`'s controller — the split is what
/// makes "themes other than parallax add nothing to the tree" true rather than
/// aspirational.
class ParallaxFocus extends StatelessWidget {
  final bool focused;
  final Widget child;
  final ParallaxShape shape;

  /// A visual layer that follows the card but keeps its resting scale.
  ///
  /// Poster captions are the motivating case: scaling a small TV label with
  /// the artwork makes its glyphs look soft, while leaving it outside the
  /// transform makes it visibly detach from the lifted card. Counter-scaling
  /// this layer about the card's bottom edge preserves both attachment and
  /// optical sharpness. It is also painted above the specular glare so the
  /// highlight cannot wash through text.
  final Widget? fixedScaleForeground;

  /// Clips the glare. Should match the child's own corner radius, or the
  /// highlight paints over the corners the artwork rounded off.
  final BorderRadius? radius;

  const ParallaxFocus({
    super.key,
    required this.focused,
    required this.child,
    this.shape = ParallaxShape.poster,
    this.radius,
    this.fixedScaleForeground,
  });

  /// Animated bodies currently mounted. Zero under every expression but
  /// `parallax` — which is the claim worth pinning, since "no Transform is
  /// painted" would still pass with an idle controller sitting in the tree.
  @visibleForTesting
  static int get debugLiveBodies => _ParallaxBodyState.debugLiveBodies;

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    if (app.focus.expression != FocusExpression.parallax) {
      return _withFixedScaleForeground(
        child: child,
        foreground: fixedScaleForeground,
        scale: 1,
      );
    }
    return _ParallaxBody(
      focused: focused,
      shape: shape,
      radius: radius,
      spring: app.motion.focusSpring,
      curve: app.motion.emphasized,
      duration: app.motion.base,
      fixedScaleForeground: fixedScaleForeground,
      // Android TV degrades to the lite body unless a [ParallaxRichScope]
      // above opts this subtree into the full effect (the detail page does).
      richTv: ParallaxRichScope.of(context),
      child: child,
    );
  }
}

Widget _withFixedScaleForeground({
  required Widget child,
  required Widget? foreground,
  required double scale,
}) {
  if (foreground == null) return child;

  final layer = scale == 1
      ? foreground
      : Transform.scale(
          alignment: Alignment.bottomCenter,
          scale: 1 / scale,
          child: foreground,
        );

  return Stack(
    fit: StackFit.passthrough,
    children: [
      child,
      Positioned.fill(child: layer),
    ],
  );
}

class _ParallaxBody extends StatefulWidget {
  final bool focused;
  final Widget child;
  final ParallaxShape shape;
  final BorderRadius? radius;
  final SpringDescription? spring;
  final Curve curve;
  final Duration duration;
  final Widget? fixedScaleForeground;

  /// Opts this body into the full effect on Android TV (spring + tilt + glare)
  /// rather than the lite body. Set by a [ParallaxRichScope] ancestor.
  final bool richTv;

  const _ParallaxBody({
    required this.focused,
    required this.child,
    required this.shape,
    required this.radius,
    required this.spring,
    required this.curve,
    required this.duration,
    required this.fixedScaleForeground,
    required this.richTv,
  });

  @override
  State<_ParallaxBody> createState() => _ParallaxBodyState();
}

class _ParallaxBodyState extends State<_ParallaxBody>
    with SingleTickerProviderStateMixin {
  /// How many animated bodies are alive. Lets a test assert the STRONG claim —
  /// that a non-parallax theme builds no controller at all — rather than the
  /// weak one that no Transform is painted.
  @visibleForTesting
  static int debugLiveBodies = 0;

  /// Perspective. The reference's `m34 = -1/700` at 1×, and this tree is drawn
  /// in logical pixels, so 700 is the logical figure.
  static const double _perspective = 700;

  /// Peak tilt, degrees, about each axis.
  static const double _tilt = 10;

  /// Travel with the tilt, logical px per degree.
  static const double _shiftPerDeg = 0.4;

  /// The shadow moves OPPOSITE the tilt — the light source stays put.
  static const double _shadowPerDeg = 1.1;

  /// Rise, logical px per unit of scale growth. The reference's `-140 × (s−1)`
  /// at 1920 is `-70 × (s−1)` logical, so a poster (1.10) rises 7 and an
  /// episode still (1.055) rises 3.85 — the rise is proportional to the lift,
  /// not a constant every shape shares.
  ///
  /// Derived from the ANIMATED scale rather than from `unit`, so it inherits
  /// the spring's overshoot instead of being clamped flat at the top.
  static const double _risePerScale = 70;

  /// Velocity that counts as a full-strength lean. Chosen against the settle
  /// spring's actual peak (k 210, ζ 0.82 travels 0→1 at roughly 6/s), so a
  /// normal step reaches most of the tilt and nothing is clipped for long.
  static const double _kickRef = 6;

  /// UNBOUNDED. A bounded controller clamps at 1.0 and an under-damped spring
  /// would lose exactly the overshoot this whole widget exists for.
  late final AnimationController _c = AnimationController.unbounded(
    vsync: this,
  );

  /// The lean's decay, driven off the same controller rather than a second
  /// one: it is a function of how far the lift has progressed, so two springs
  /// could only ever drift out of phase with each other.
  Offset _lean = Offset.zero;

  @override
  void initState() {
    super.initState();
    debugLiveBodies++;
    if (widget.focused) {
      _c.value = 1;
    }
  }

  @override
  void didUpdateWidget(_ParallaxBody old) {
    super.didUpdateWidget(old);
    if (widget.focused != old.focused) {
      // Re-read rather than trusting the cached flag: focus and the
      // accessibility setting can change in the SAME rebuild, and
      // didUpdateWidget runs before didChangeDependencies.
      _reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
      _drive();
    }
  }

  void _drive() {
    if (widget.focused) {
      final t = ParallaxTravel.take();
      // Rapid traversal leans harder and settles less — the felt difference
      // between stepping through a row and blasting through it.
      _lean = t.dir * (t.rapid ? 1.0 : 0.62);
    } else {
      _lean = Offset.zero;
    }

    final target = widget.focused ? 1.0 : 0.0;

    // Reduced motion keeps the STATE and drops the movement. A focused card
    // that does not lift is a card with no cursor.
    if (_reduceMotion) {
      _c.stop();
      _c.value = target;
      return;
    }

    // Android TV: a ζ0.82 settle spring animates for the best part of a
    // second, and on a box that pays real raster cost for every animated
    // frame the tail IS the lag — a held key keeps two cards perpetually
    // mid-spring. A short ease-out reaches the same endpoint in about a
    // tenth of the frames and reads crisper under DPAD repeat. Same
    // policy family as the lite body below.
    //
    // Rich subtrees hybridize on Android TV: DURING a rapid run both cards
    // of every step drop to this same lite pipeline — the tilt's perspective
    // re-raster and the glare's saveLayer, ×2 cards ×every repeat frame,
    // measured ~44ms of raster per janky frame on the Mi Box, for motion
    // nobody can see at repeat speed. The full spring returns on the settle
    // step, and the arriving card swaps its paint back to rich once the
    // short ease-out lands (a static highlight appearing at rest, not a
    // mid-motion style change).
    final lite = PlatformUtil.isAndroidTvCached &&
        (!widget.richTv || ParallaxTravel.isRapid);
    if (lite != _lite) setState(() => _lite = lite);
    if (lite) {
      _c
          .animateTo(
            target,
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOutCubic,
          )
          .whenCompleteOrCancel(() {
        if (mounted &&
            widget.richTv &&
            widget.focused &&
            _lite &&
            !_c.isAnimating) {
          setState(() => _lite = false);
        }
      });
      return;
    }

    final spring = widget.spring;
    if (spring == null) {
      _c.animateTo(target, duration: widget.duration, curve: widget.curve);
      return;
    }
    // Seeded with the CURRENT velocity, which is what lets an interrupted
    // move continue rather than restart.
    _c.animateWith(SpringSimulation(spring, _c.value, target, _c.velocity))
    // A spring stops when it is within tolerance of its target, not ON it
    // — measured ~2% high, which leaves a settled card permanently that
    // much oversized. Land it exactly, and only if this is still the move
    // that was started (a later one will have set its own target).
    .whenCompleteOrCancel(() {
      if (mounted && _c.value != target && !_c.isAnimating) {
        _c.value = target;
      }
    });
  }

  bool _reduceMotion = false;

  /// Whether the CURRENT move runs the lite pipeline on a rich-TV subtree
  /// (rapid-travel hybrid — see [_drive]). Paint follows the same flag so
  /// the animation style and the body style can never disagree mid-flight.
  bool _lite = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Read here, never in the tick: an inherited lookup per frame is the thing
    // the TV budget forbids.
    final was = _reduceMotion;
    _reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    // Turning the setting ON mid-flight has to stop what is already running.
    // Someone who enables reduced motion because motion is hurting them should
    // not have to wait out the animation that prompted it.
    if (_reduceMotion && !was && _c.isAnimating) {
      _c.stop();
      _c.value = widget.focused ? 1.0 : 0.0;
    }
  }

  @override
  void dispose() {
    debugLiveBodies--;
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final radius = widget.radius ?? BorderRadius.zero;
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, child) {
          // Clamped for the DERIVED values only — the controller itself must
          // stay unbounded so the spring can overshoot, but a shadow alpha or
          // a glare opacity outside 0..1 throws.
          final v = _c.value;
          final lift = v.clamp(0.0, 1.4);
          final unit = lift.clamp(0.0, 1.0);
          if (lift <= 0.0001 && _c.velocity.abs() < 0.01) {
            return _withFixedScaleForeground(
              child: child!,
              foreground: widget.fixedScaleForeground,
              scale: 1,
            );
          }

          final scale = 1 + (widget.shape.scale - 1) * lift;

          // The Android TV LITE body — the per-frame raster budget of an
          // Amlogic/Mali GLES2 box. Keeps what makes the cursor a cursor
          // (lift, rise, a soft shadow) and sheds what it pays for every
          // animated frame ×2 cards per step: the tilt (whose perspective
          // matrix re-rasters the subtree), the specular glare (a full-card
          // RadialGradient) and with it the rounded ClipRRect (a saveLayer
          // on that pipeline). Same compromise-per-box family as grain-off
          // and the flattened ground gradient; Apple TV and pointer devices
          // keep the full effect below — as does any subtree inside a
          // [ParallaxRichScope] (the detail page), which is why [richTv] skips
          // this branch.
          if (PlatformUtil.isAndroidTvCached && (!widget.richTv || _lite)) {
            return Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..translateByDouble(0, -_risePerScale * (scale - 1), 0, 1)
                ..scaleByDouble(scale, scale, 1, 1),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: radius == BorderRadius.zero ? null : radius,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.45 * unit),
                      offset: const Offset(0, 16),
                      blurRadius: 12,
                    ),
                  ],
                ),
                child: _withFixedScaleForeground(
                  child: child!,
                  foreground: widget.fixedScaleForeground,
                  scale: scale,
                ),
              ),
            );
          }

          // Tilt rides the spring's VELOCITY, not a bell curve over its
          // position. That is what makes the card swing THROUGH neutral: the
          // velocity is positive climbing to the target and negative on the
          // rebound, so the lean reverses on its own and decays as the spring
          // settles — which is the "kick the velocity" the reference does.
          //
          // A position-derived curve can only ever pulse on one side, and at
          // overshoot it reads as the card freezing flat and then leaning the
          // same way again.
          final swing = (_c.velocity / _kickRef).clamp(-1.0, 1.0);
          final rx = -_lean.dy * _tilt * swing;
          final ry = _lean.dx * _tilt * swing;

          return Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, -1 / _perspective)
              ..translateByDouble(
                -ry * _shiftPerDeg,
                rx * _shiftPerDeg - _risePerScale * (scale - 1),
                0,
                1,
              )
              ..rotateX(rx * math.pi / 180)
              ..rotateY(ry * math.pi / 180)
              ..scaleByDouble(scale, scale, 1, 1),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: radius == BorderRadius.zero ? null : radius,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.45 * unit),
                    offset: Offset(
                      -ry * _shadowPerDeg,
                      16 + rx * _shadowPerDeg,
                    ),
                    blurRadius: 25,
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: radius,
                child: _withFixedScaleForeground(
                  scale: scale,
                  foreground: widget.fixedScaleForeground,
                  child: Stack(
                    fit: StackFit.passthrough,
                    children: [
                      child!,
                      // The specular highlight: a blurry white disc ~1.7× the
                      // card, parked above its top edge so only the lower arc
                      // catches the face, sliding with the tilt.
                      //
                      // Painted as a gradient whose own stops carry the alpha —
                      // an Opacity here would be a saveLayer per frame, which is
                      // the one thing a TV cursor cannot afford.
                      Positioned.fill(
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: RadialGradient(
                                center: Alignment(
                                  (-ry * 0.042).clamp(-1.0, 1.0),
                                  (-1.05 + rx * 0.042).clamp(-2.0, 1.0),
                                ),
                                radius: 0.85,
                                colors: [
                                  Colors.white.withValues(alpha: 0.31 * unit),
                                  Colors.white.withValues(alpha: 0.14 * unit),
                                  Colors.white.withValues(alpha: 0),
                                ],
                                stops: const [0, 0.26, 0.58],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
        child: widget.child,
      ),
    );
  }
}
