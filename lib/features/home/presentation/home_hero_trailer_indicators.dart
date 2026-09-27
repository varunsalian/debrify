import 'dart:math';
import 'package:flutter/material.dart';
import '../../../theme/app_theme_scope.dart';
import '../../../utils/platform_util.dart';

/// The hero's "trailer is on its way" chip: the same quiet glass capsule as
/// [HomeHeroAmbientChip] (they hand over in place in the same corner), but with
/// three tiny amber equalizer bars dancing where the ambient dot will sit —
/// "sound and picture incoming", not a generic spinner (the old bordered
/// spinner-pill read dated). Deliberately quiet — a status whisper, never a
/// control — and cheap: no blur (weak-TV rule), the bars are a ~14px-wide
/// repaint inside their own RepaintBoundary, and the controller only runs
/// while [visible], so the 99% of browsing the chip spends hidden costs
/// nothing at all.
class HomeHeroTrailerLoadingPill extends StatefulWidget {
  final bool visible;

  const HomeHeroTrailerLoadingPill({super.key, required this.visible});

  @override
  State<HomeHeroTrailerLoadingPill> createState() =>
      _HomeHeroTrailerLoadingPillState();
}

class _HomeHeroTrailerLoadingPillState extends State<HomeHeroTrailerLoadingPill>
    with SingleTickerProviderStateMixin {
  late final AnimationController _wave;

  @override
  void initState() {
    super.initState();
    _wave = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    if (widget.visible) _wave.repeat();
  }

  @override
  void didUpdateWidget(HomeHeroTrailerLoadingPill oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible && !_wave.isAnimating) {
      _wave.repeat();
    } else if (!widget.visible && _wave.isAnimating) {
      // Freezing mid-wave is invisible: the chip itself is fading to 0.
      _wave.stop();
    }
  }

  @override
  void dispose() {
    _wave.dispose();
    super.dispose();
  }

  /// One equalizer bar: bottom-anchored, height riding a phase-shifted sine
  /// so the three bars roll as a wave rather than pumping in unison.
  /// [color] is passed in, captured once at build — this runs per wave frame.
  Widget _bar(Color color, double t, double phase) {
    final f = 0.30 + 0.70 * (0.5 + 0.5 * sin(2 * pi * (t + phase)));
    return Container(
      width: 2.5,
      height: 11 * f,
      decoration: BoxDecoration(
        color: color, // the ambient dot's amber
        borderRadius: BorderRadius.circular(1.5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final visible = widget.visible;
    return IgnorePointer(
      child: AnimatedSlide(
        offset: visible ? Offset.zero : const Offset(0, -0.25),
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOut,
          // RepaintBoundary: while resolving, the wave produces a frame per
          // vsync — without the boundary each one would dirty the ROUTE's
          // layer and repaint every non-isolated part of the screen for the
          // whole resolve window (measured with the old spinner).
          child: RepaintBoundary(
            child: Container(
              padding: const EdgeInsets.fromLTRB(11, 6, 12, 6),
              decoration: BoxDecoration(
                // Glassy page ink — fade 0.8 pins the legacy 0xCC alpha.
                color: app.fade(app.home.bg, 0.8),
                borderRadius: app.shape.brPill,
                border: Border.all(color: app.fade(app.core.tx, 0.16)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 13,
                    height: 11,
                    child: AnimatedBuilder(
                      animation: _wave,
                      builder: (context, _) {
                        final t = _wave.value;
                        return Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            _bar(app.home.highlight, t, 0.0),
                            _bar(app.home.highlight, t, 0.30),
                            _bar(app.home.highlight, t, 0.60),
                          ],
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 7),
                  Text(
                    'TRAILER',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                      color: app.fade(app.core.tx, 0.62),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The "AMBIENT" chip that replaces the loading pill once trailer frames are
/// on screen: a quiet glass pill with a slowly breathing amber dot — a state
/// affordance ("this motion is intentional"), never a control. Same corner and
/// idioms as [HomeHeroTrailerLoadingPill] (no blur; the pulse ticker is started/
/// stopped with [visible] — TickerMode can't gate it, the ticker belongs to
/// this State which sits above any wrapper — so it costs nothing while hidden;
/// the dot is a 6px repaint, trivia next to the video already playing beneath
/// it).
class HomeHeroAmbientChip extends StatefulWidget {
  final bool visible;

  const HomeHeroAmbientChip({super.key, required this.visible});

  @override
  State<HomeHeroAmbientChip> createState() => _HomeHeroAmbientChipState();
}

class _HomeHeroAmbientChipState extends State<HomeHeroAmbientChip>
    with SingleTickerProviderStateMixin {
  // Created EAGERLY in initState: on TV nothing else touches it, and a `late`
  // field first reached by dispose() would create its Ticker there — a
  // TickerMode ancestor lookup on a defunct context (debug assertion crash).
  late final AnimationController _pulse;

  /// TV never breathes: the pulse would tick + repaint at 60fps for the whole
  /// trailer, compositing over the underlay video every frame — continuous
  /// idle animation is exactly what the TV effects budget bans, and a static
  /// lit dot reads identically from the couch. Phones keep the breath.
  bool get _pulseOk => !PlatformUtil.isTelevision;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    if (widget.visible && _pulseOk) _pulse.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(HomeHeroAmbientChip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_pulseOk) return;
    if (widget.visible && !_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    } else if (!widget.visible && _pulse.isAnimating) {
      // Freezing mid-breath is invisible: the chip itself is fading to 0.
      _pulse.stop();
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final visible = widget.visible;
    return IgnorePointer(
      child: AnimatedSlide(
        offset: visible ? Offset.zero : const Offset(0, -0.25),
        duration: const Duration(milliseconds: 340),
        curve: Curves.easeOutCubic,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: const Duration(milliseconds: 340),
          curve: Curves.easeOut,
          child: RepaintBoundary(
            child: Container(
              padding: const EdgeInsets.fromLTRB(10, 6, 12, 6),
              decoration: BoxDecoration(
                // Glassy page ink — fade 0.8 pins the legacy 0xCC alpha.
                color: app.fade(app.home.bg, 0.8),
                borderRadius: app.shape.brPill,
                border: Border.all(color: app.fade(app.core.tx, 0.16)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Builder(
                    builder: (context) {
                      final dot = SizedBox(
                        width: 6,
                        height: 6,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: app.home.highlight,
                            shape: BoxShape.circle,
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x8CF59E0B),
                                blurRadius: 8,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                        ),
                      );
                      if (!_pulseOk) return dot; // TV: lit, still, free
                      return FadeTransition(
                        opacity: Tween<double>(begin: 0.45, end: 1.0).animate(
                          CurvedAnimation(
                            parent: _pulse,
                            curve: Curves.easeInOut,
                          ),
                        ),
                        child: dot,
                      );
                    },
                  ),
                  const SizedBox(width: 7),
                  Text(
                    'AMBIENT',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                      color: app.fade(app.core.tx, 0.62),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
