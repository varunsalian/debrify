import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../theme/app_theme_scope.dart';
import '../../../utils/platform_util.dart';

/// The Discover glass stage's tint veils — the mock's gradient recipe, painted
/// in the page ink so the art dissolves into the canvas: loudest art behind the
/// detail column, near-opaque under the grid, plus a vertical top kiss and deep
/// bottom melt.
///
/// Three states on a lights ladder, eased between so every step feels staged:
/// browse (art dressed in the mock's tint), playback ([showing] — art-zone
/// stops thin to ~.35 so the video actually reads, 900ms in), and theater
/// ([theater], a few seconds into uninterrupted playback — the veils fall to
/// near-clear (~.12) and the whole page commits to the picture, on a slow
/// 1.2s ease). Lights-up from any state is a snappy 250ms (a DPAD move means
/// the user is browsing again). Direct translucent paint (DecoratedBox with
/// lerped colors, never an Opacity layer), so it is safe over the underlay
/// trailer's punched hole; the gradient only re-paints during the transitions,
/// never at idle.
class DiscoverStageVeils extends StatelessWidget {
  final ValueListenable<bool> showing;
  final ValueListenable<bool> theater;

  /// STAGE layout: there is no pane divide to light for, so the tint moves to
  /// where the text actually is — a left column and a bottom ramp under the
  /// shelf, with the right/upper art left clear. Same browse→playback→theater
  /// ladder and the same baked-alpha paint (never an Opacity layer, which
  /// forces a per-frame full-screen saveLayer on weak TV GPUs).
  final bool stage;

  const DiscoverStageVeils({
    super.key,
    required this.showing,
    required this.theater,
    this.stage = false,
  });

  /// Page ink at an alpha walked along the browse→playback→theater ladder by
  /// [phase] (0..2). [base] is the page ink, captured once at build — this
  /// runs per transition frame. withValues (not fade): the ladder's alphas
  /// are ABSOLUTE, and the ground token is opaque on every theme, so the two
  /// are equivalent here.
  static Color _ink(
    Color base,
    double browse,
    double play,
    double deep,
    double phase,
  ) {
    final a = phase <= 1.0
        ? browse + (play - browse) * phase
        : play + (deep - play) * (phase - 1.0);
    return base.withValues(alpha: a);
  }

  @override
  Widget build(BuildContext context) {
    final ink = AppThemeScope.of(context).home.bg;
    return IgnorePointer(
      child: ValueListenableBuilder<bool>(
        valueListenable: showing,
        builder: (_, on, __) => ValueListenableBuilder<bool>(
          valueListenable: theater,
          builder: (_, deep, __) => TweenAnimationBuilder<double>(
            tween: Tween(end: deep ? 2.0 : (on ? 1.0 : 0.0)),
            duration: deep
                ? const Duration(milliseconds: 1200)
                : on
                ? const Duration(milliseconds: 900)
                // Lights-up fires on the KEYPRESS that interrupts a
                // trailer, and each of its frames re-lerps and repaints
                // three full-screen gradients — on an Amlogic/Mali box
                // that lands as input lag on the exact frame the user
                // pressed. Snap it there; the slow lights-down legs run
                // at rest, where nobody is waiting on a frame.
                : PlatformUtil.isAndroidTvCached
                ? Duration.zero
                : const Duration(milliseconds: 250),
            curve: Curves.easeInOutCubic,
            builder: (_, t, __) => stage
                ? Stack(
                    fit: StackFit.expand,
                    children: [
                      // Left column: seats the identity block. Dissolves by
                      // two thirds across so the art keeps the right half.
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                            colors: [
                              _ink(ink, 0.88, 0.56, 0.10, t),
                              _ink(ink, 0.60, 0.34, 0.06, t),
                              const Color(0x000D0B1A),
                            ],
                            stops: const [0.0, 0.32, 0.66],
                          ),
                        ),
                      ),
                      // Bottom ramp: seats the shelf and the filter line's
                      // opposite edge; top edge gets a whisper so the filter
                      // segments stay legible over bright art.
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [
                              _ink(ink, 0.94, 0.70, 0.16, t),
                              _ink(ink, 0.74, 0.46, 0.10, t),
                              const Color(0x000D0B1A),
                              _ink(ink, 0.30, 0.14, 0.04, t),
                            ],
                            stops: const [0.0, 0.20, 0.52, 1.0],
                          ),
                        ),
                      ),
                      // The text pocket, straight off the Canvas board: the
                      // identity block's meta line and plot are allowed to run
                      // to half the frame, past where the left column has
                      // dissolved, and the bottom ramp alone leaves their
                      // right end sitting on bare artwork. Centred under the
                      // block, gone well before mid-screen so the art keeps
                      // its glow everywhere else.
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: RadialGradient(
                            center: const Alignment(-0.72, 0.55),
                            radius: 0.95,
                            colors: [
                              _ink(ink, 0.80, 0.45, 0.06, t),
                              const Color(0x000D0B1A),
                            ],
                            stops: const [0.12, 1.0],
                          ),
                        ),
                      ),
                    ],
                  )
                : Stack(
                    fit: StackFit.expand,
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                            colors: [
                              _ink(
                                ink,
                                0.58,
                                0.34,
                                0.10,
                                t,
                              ), // art zone / rail text
                              _ink(ink, 0.62, 0.38, 0.12, t),
                              // Theater goes near-clear on the grid side too — the
                              // panel content fades itself, so the video must not be
                              // buried under ink there ("black right side").
                              _ink(ink, 0.84, 0.68, 0.18, t), // the pane divide
                              _ink(ink, 0.94, 0.86, 0.24, t), // under the grid
                              _ink(ink, 1.0, 0.92, 0.30, t),
                            ],
                            stops: const [0.0, 0.34, 0.52, 0.74, 1.0],
                          ),
                        ),
                      ),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              _ink(
                                ink,
                                0.34,
                                0.15,
                                0.06,
                                t,
                              ), // settle the top edge
                              const Color(0x000D0B1A),
                              const Color(0x000D0B1A),
                              _ink(
                                ink,
                                0.88,
                                0.58,
                                0.28,
                                t,
                              ), // melt into the bottom
                            ],
                            stops: const [0.0, 0.26, 0.55, 0.92],
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
