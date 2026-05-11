import 'package:flutter/material.dart';

/// Cinematic dark gradient backdrop with a red ambient glow.
///
/// Used across redesigned Netflix-style screens (Settings, Addons, Engines,
/// Downloads, Real-Debrid, Torbox, PikPak, WebDAV). Place inside a Stack as
/// the first child; subsequent children render on top.
class CinematicBackdrop extends StatelessWidget {
  final Color glowColor;
  final double glowTop;
  final double glowSize;

  const CinematicBackdrop({
    super.key,
    this.glowColor = const Color(0xFFED1C24),
    this.glowTop = -200,
    this.glowSize = 560,
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        children: [
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFF14101C),
                    Color(0xFF0A0810),
                    Color(0xFF030305),
                  ],
                  stops: [0.0, 0.35, 1.0],
                ),
              ),
            ),
          ),
          Positioned(
            top: glowTop,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                width: glowSize,
                height: glowSize * 0.68,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      glowColor.withValues(alpha: 0.22),
                      glowColor.withValues(alpha: 0.06),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.5, 1.0],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Constants for the Netflix red cinematic theme.
class CinematicTheme {
  CinematicTheme._();

  static const Color accent = Color(0xFFED1C24);
  static const Color accentDeep = Color(0xFFB81D24);
  static const Color bgTop = Color(0xFF14101C);
  static const Color positive = Color(0xFF34D399);
  static const Color positiveDeep = Color(0xFF10B981);

  static const Duration focusDuration = Duration(milliseconds: 160);

  /// Standard glass card decoration with optional focus highlight.
  static BoxDecoration glassCard({bool focused = false, double radius = 16}) {
    return BoxDecoration(
      borderRadius: BorderRadius.circular(radius),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: focused
            ? [accent.withValues(alpha: 0.18), accent.withValues(alpha: 0.06)]
            : [
                Colors.white.withValues(alpha: 0.05),
                Colors.white.withValues(alpha: 0.02),
              ],
      ),
      border: Border.all(
        color: focused
            ? accent.withValues(alpha: 0.9)
            : Colors.white.withValues(alpha: 0.07),
        width: focused ? 2 : 1,
      ),
      boxShadow: focused
          ? [
              BoxShadow(
                color: accent.withValues(alpha: 0.3),
                blurRadius: 22,
                spreadRadius: -4,
              ),
            ]
          : null,
    );
  }
}
