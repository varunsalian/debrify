import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../theme/app_theme_scope.dart';

/// Lights-off over the grid while the trailer PLAYS (pre-theater): an animated
/// baked-color wash covering the panel side (posters + filter line recede,
/// Home-rows style), feathered over its first 15% so no hard seam cuts the
/// stage at the pane divide. In THEATER the wash dissolves back to zero — there
/// the panel content fades itself (host-side AnimatedOpacity) and ink here
/// would just bury the now-unveiled video. Sits ABOVE the two-pane. Any DPAD
/// move drops the signals and the lights snap back up in 250ms.
class DiscoverGridDim extends StatelessWidget {
  final ValueListenable<bool> showing;
  final ValueListenable<bool> theater;
  final double leftInset;

  const DiscoverGridDim({
    super.key,
    required this.showing,
    required this.theater,
    required this.leftInset,
  });

  @override
  Widget build(BuildContext context) {
    final ink = AppThemeScope.of(context).home.bg;
    return Positioned(
      left: leftInset,
      top: 0,
      right: 0,
      bottom: 0,
      // RepaintBoundary inside the Positioned (which must stay a direct Stack
      // child): the dim animates a panel-wide gradient per frame during the
      // 250/900ms transitions — keep those frames off the stage layer.
      child: RepaintBoundary(
        child: IgnorePointer(
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
                    : const Duration(milliseconds: 250),
                curve: Curves.easeInOutCubic,
                builder: (_, t, __) {
                  // 0→1: 0 → .52 (playback); 1→2: .52 → 0 (theater unveils).
                  final a = t <= 1.0 ? 0.52 * t : 0.52 * (2.0 - t);
                  if (a <= 0.001) return const SizedBox.shrink();
                  return DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        // withValues (not fade): absolute alphas over an
                        // always-opaque ground token — equivalent, and the
                        // ramp's 0.0 end must stay a true clear.
                        colors: [
                          ink.withValues(alpha: 0.0),
                          ink.withValues(alpha: a),
                        ],
                        stops: const [0.0, 0.15],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
