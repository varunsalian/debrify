import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Fullscreen transition overlay shown while the next stream resolves.
///
/// Minimal, premium "Apple TV" aesthetic: a frosted dark scrim with a depth
/// vignette, a soft accent glow, a custom gradient-arc spinner, and the title
/// gently fading + sliding up once it's known.
class TransitionOverlay extends StatefulWidget {
  /// Kept for API compatibility with the player (no longer drives the visual).
  final AnimationController rainbowController;

  /// Legacy status message — no longer displayed, kept for call-site stability.
  final String tvStaticMessage;

  /// Title of the video being loaded (shown once known).
  final String tvStaticSubtext;

  /// Accent used for the spinner + glow (app primary by default).
  final Color accent;

  const TransitionOverlay({
    super.key,
    required this.rainbowController,
    required this.tvStaticMessage,
    required this.tvStaticSubtext,
    this.accent = const Color(0xFF818CF8), // Indigo 400 (app primary)
  });

  @override
  State<TransitionOverlay> createState() => _TransitionOverlayState();
}

class _TransitionOverlayState extends State<TransitionOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin;

  @override
  void initState() {
    super.initState();
    _spin = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat();
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.accent;
    return Positioned.fill(
      child: IgnorePointer(
        ignoring: true,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Frosted dark scrim — blurs any peeking frame and adds depth.
            BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 28, sigmaY: 28),
              child: const ColoredBox(color: Color(0xCC0B0B0F)),
            ),

            // Subtle radial vignette for a premium edge falloff.
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  radius: 1.1,
                  colors: [Colors.transparent, Color(0x55000000)],
                  stops: [0.5, 1.0],
                ),
              ),
            ),

            // Centered content with a soft scale + fade entrance.
            Center(
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0, end: 1.0),
                duration: const Duration(milliseconds: 320),
                curve: Curves.easeOutCubic,
                builder: (_, t, child) => Opacity(
                  opacity: t,
                  child: Transform.scale(scale: 0.92 + 0.08 * t, child: child),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(48.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Glow + gradient-arc spinner.
                      SizedBox(
                        width: 96,
                        height: 96,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            // Soft accent glow.
                            Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: RadialGradient(
                                  colors: [
                                    accent.withValues(alpha: 0.22),
                                    accent.withValues(alpha: 0.0),
                                  ],
                                  stops: const [0.0, 1.0],
                                ),
                              ),
                            ),
                            // Rotating gradient arc.
                            RotationTransition(
                              turns: _spin,
                              child: CustomPaint(
                                size: const Size(46, 46),
                                painter: _ArcSpinnerPainter(accent),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (widget.tvStaticSubtext.isNotEmpty) ...[
                        const SizedBox(height: 18),
                        // Title fades + slides up slightly.
                        TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0.0, end: 1.0),
                          duration: const Duration(milliseconds: 420),
                          curve: Curves.easeOut,
                          builder: (_, t, child) => Opacity(
                            opacity: t,
                            child: Transform.translate(
                              offset: Offset(0, (1 - t) * 8),
                              child: child,
                            ),
                          ),
                          child: Text(
                            widget.tvStaticSubtext,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.96),
                              fontSize: 17,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 0.3,
                              height: 1.3,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Thin gradient arc with a rounded cap over a faint full-circle track.
class _ArcSpinnerPainter extends CustomPainter {
  final Color color;

  _ArcSpinnerPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 3.0;
    final center = size.center(Offset.zero);
    final radius = (math.min(size.width, size.height) - stroke) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    // Faint background track.
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = Colors.white.withValues(alpha: 0.08);
    canvas.drawCircle(center, radius, track);

    // Sweep-gradient arc: transparent tail -> solid accent head.
    final shader = SweepGradient(
      startAngle: 0,
      endAngle: math.pi * 2,
      colors: [
        color.withValues(alpha: 0.0),
        color.withValues(alpha: 0.0),
        color.withValues(alpha: 0.85),
        color,
      ],
      stops: const [0.0, 0.25, 0.95, 1.0],
    ).createShader(rect);
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..shader = shader;
    canvas.drawArc(rect, -math.pi / 2, math.pi * 1.5, false, arc);
  }

  @override
  bool shouldRepaint(_ArcSpinnerPainter old) => old.color != color;
}
