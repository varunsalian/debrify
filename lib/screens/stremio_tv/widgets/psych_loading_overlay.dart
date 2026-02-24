import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';

/// Psychedelic full-screen loading overlay for Stremio TV playback resolution.
///
/// Shows concentric rotating rings, pulsating orbs, color-shifting gradients,
/// floating particles, and glowing text — all animated.
class PsychLoadingOverlay extends StatefulWidget {
  final String message;

  const PsychLoadingOverlay({super.key, required this.message});

  @override
  State<PsychLoadingOverlay> createState() => _PsychLoadingOverlayState();
}

class _PsychLoadingOverlayState extends State<PsychLoadingOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _mainController;
  late final AnimationController _pulseController;
  late final AnimationController _textController;
  late final List<_Particle> _particles;
  final _random = Random();

  @override
  void initState() {
    super.initState();
    _mainController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    _textController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )..repeat();

    _particles = List.generate(30, (_) => _Particle.random(_random));
  }

  @override
  void dispose() {
    _mainController.dispose();
    _pulseController.dispose();
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Material(
        color: Colors.transparent,
        child: AnimatedBuilder(
          animation: Listenable.merge([
            _mainController,
            _pulseController,
            _textController,
          ]),
          builder: (context, _) {
            return Stack(
              fit: StackFit.expand,
              children: [
                // Dark backdrop with blur
                BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                  child: Container(color: Colors.black.withValues(alpha: 0.85)),
                ),

                // Psychedelic painter
                CustomPaint(
                  painter: _PsychPainter(
                    progress: _mainController.value,
                    pulse: _pulseController.value,
                    particles: _particles,
                  ),
                  size: Size.infinite,
                ),

                // Center content
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Glowing orb stack
                      _buildOrbStack(),
                      const SizedBox(height: 40),
                      // Animated text
                      _buildGlowingText(),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildOrbStack() {
    final pulse = _pulseController.value;
    final rotation = _mainController.value * 2 * pi;

    return SizedBox(
      width: 160,
      height: 160,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Outer glow
          Transform.scale(
            scale: 1.0 + pulse * 0.3,
            child: Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: _lerpHue(rotation).withValues(alpha: 0.3),
                    blurRadius: 60,
                    spreadRadius: 20,
                  ),
                ],
              ),
            ),
          ),

          // Ring 1 — large, slow
          Transform.rotate(
            angle: rotation,
            child: CustomPaint(
              painter: _RingPainter(
                radius: 70,
                strokeWidth: 2.5,
                color1: const Color(0xFFFF00FF),
                color2: const Color(0xFF00FFFF),
                dashCount: 24,
                gapFraction: 0.4,
              ),
              size: const Size(160, 160),
            ),
          ),

          // Ring 2 — medium, reverse
          Transform.rotate(
            angle: -rotation * 1.7,
            child: CustomPaint(
              painter: _RingPainter(
                radius: 52,
                strokeWidth: 2,
                color1: const Color(0xFF00FF88),
                color2: const Color(0xFFFF6600),
                dashCount: 16,
                gapFraction: 0.35,
              ),
              size: const Size(160, 160),
            ),
          ),

          // Ring 3 — small, fast
          Transform.rotate(
            angle: rotation * 2.3,
            child: CustomPaint(
              painter: _RingPainter(
                radius: 34,
                strokeWidth: 1.5,
                color1: const Color(0xFFFFFF00),
                color2: const Color(0xFFFF0088),
                dashCount: 12,
                gapFraction: 0.3,
              ),
              size: const Size(160, 160),
            ),
          ),

          // Center pulsating orb
          Transform.scale(
            scale: 0.8 + pulse * 0.4,
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: SweepGradient(
                  startAngle: rotation,
                  colors: const [
                    Color(0xFFFF00FF),
                    Color(0xFF00FFFF),
                    Color(0xFFFF6600),
                    Color(0xFF00FF88),
                    Color(0xFFFF00FF),
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: _lerpHue(rotation).withValues(alpha: 0.8),
                    blurRadius: 20,
                    spreadRadius: 4,
                  ),
                ],
              ),
            ),
          ),

          // Orbiting dots
          for (int i = 0; i < 5; i++)
            Transform.rotate(
              angle: rotation * (1.2 + i * 0.3) + (i * 2 * pi / 5),
              child: Transform.translate(
                offset: Offset(56 + sin(rotation * 2 + i) * 8, 0),
                child: Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: [
                      const Color(0xFFFF00FF),
                      const Color(0xFF00FFFF),
                      const Color(0xFFFFFF00),
                      const Color(0xFF00FF88),
                      const Color(0xFFFF6600),
                    ][i],
                    boxShadow: [
                      BoxShadow(
                        color: [
                          const Color(0xFFFF00FF),
                          const Color(0xFF00FFFF),
                          const Color(0xFFFFFF00),
                          const Color(0xFF00FF88),
                          const Color(0xFFFF6600),
                        ][i]
                            .withValues(alpha: 0.8),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildGlowingText() {
    final hue = (_textController.value * 360) % 360;
    final glowColor = HSLColor.fromAHSL(1, hue, 1, 0.6).toColor();

    return Column(
      children: [
        // Message text with color-cycling glow
        Text(
          widget.message,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
            shadows: [
              Shadow(color: glowColor, blurRadius: 20),
              Shadow(color: glowColor.withValues(alpha: 0.5), blurRadius: 40),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // Animated dots
        _buildAnimatedDots(glowColor),
      ],
    );
  }

  Widget _buildAnimatedDots(Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (i) {
        final offset = (_textController.value * 3 - i).clamp(0.0, 1.0);
        final opacity = (sin(offset * pi)).clamp(0.2, 1.0);
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: Opacity(
            opacity: opacity,
            child: Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color,
                boxShadow: [
                  BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 6),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }

  Color _lerpHue(double angle) {
    final hue = (angle / (2 * pi) * 360) % 360;
    return HSLColor.fromAHSL(1, hue, 1, 0.55).toColor();
  }
}

// ---------------------------------------------------------------------------
// Ring painter — dashed arc segments with gradient
// ---------------------------------------------------------------------------
class _RingPainter extends CustomPainter {
  final double radius;
  final double strokeWidth;
  final Color color1;
  final Color color2;
  final int dashCount;
  final double gapFraction;

  _RingPainter({
    required this.radius,
    required this.strokeWidth,
    required this.color1,
    required this.color2,
    required this.dashCount,
    required this.gapFraction,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final segmentAngle = 2 * pi / dashCount;
    final drawAngle = segmentAngle * (1 - gapFraction);

    for (int i = 0; i < dashCount; i++) {
      final t = i / dashCount;
      final color = Color.lerp(color1, color2, t)!;
      final paint = Paint()
        ..color = color.withValues(alpha: 0.8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;

      final startAngle = i * segmentAngle;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        drawAngle,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) => false;
}

// ---------------------------------------------------------------------------
// Background painter — radial rays + floating particles
// ---------------------------------------------------------------------------
class _PsychPainter extends CustomPainter {
  final double progress;
  final double pulse;
  final List<_Particle> particles;

  _PsychPainter({
    required this.progress,
    required this.pulse,
    required this.particles,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxDim = max(size.width, size.height);
    final rotation = progress * 2 * pi;

    // Radial rays
    final rayCount = 18;
    for (int i = 0; i < rayCount; i++) {
      final angle = rotation * 0.3 + (i * 2 * pi / rayCount);
      final hue = ((i / rayCount * 360) + progress * 360) % 360;
      final color = HSLColor.fromAHSL(1, hue, 0.9, 0.5).toColor();
      final opacity = 0.04 + pulse * 0.03;

      final paint = Paint()
        ..shader = RadialGradient(
          colors: [
            color.withValues(alpha: opacity),
            color.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: center, radius: maxDim * 0.6));

      final endX = center.dx + cos(angle) * maxDim;
      final endY = center.dy + sin(angle) * maxDim;

      final path = Path()
        ..moveTo(center.dx, center.dy)
        ..lineTo(
          center.dx + cos(angle - 0.04) * maxDim,
          center.dy + sin(angle - 0.04) * maxDim,
        )
        ..lineTo(endX, endY)
        ..close();

      canvas.drawPath(path, paint);
    }

    // Floating particles
    for (final p in particles) {
      final t = (progress * p.speed + p.phase) % 1.0;
      final x = p.x * size.width;
      final y = (p.y + t * 0.6 - 0.3) * size.height;
      final alpha = sin(t * pi) * p.maxAlpha;
      final radius = p.radius * (0.8 + pulse * 0.4);

      if (y < 0 || y > size.height) continue;

      final hue = (p.hue + progress * 180) % 360;
      final color = HSLColor.fromAHSL(1, hue, 1, 0.6).toColor();

      final paint = Paint()
        ..color = color.withValues(alpha: alpha.clamp(0.0, 1.0))
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

      canvas.drawCircle(Offset(x, y), radius, paint);
    }
  }

  @override
  bool shouldRepaint(_PsychPainter old) => true;
}

// ---------------------------------------------------------------------------
// Particle data
// ---------------------------------------------------------------------------
class _Particle {
  final double x, y, speed, phase, maxAlpha, radius, hue;

  _Particle({
    required this.x,
    required this.y,
    required this.speed,
    required this.phase,
    required this.maxAlpha,
    required this.radius,
    required this.hue,
  });

  factory _Particle.random(Random r) {
    return _Particle(
      x: r.nextDouble(),
      y: r.nextDouble(),
      speed: 0.3 + r.nextDouble() * 0.7,
      phase: r.nextDouble(),
      maxAlpha: 0.15 + r.nextDouble() * 0.35,
      radius: 1.5 + r.nextDouble() * 3.5,
      hue: r.nextDouble() * 360,
    );
  }
}

// ---------------------------------------------------------------------------
// Helper to show/dismiss the overlay (drop-in replacement for showDialog)
// ---------------------------------------------------------------------------

/// Shows the psychedelic loading overlay. Returns nothing — dismiss via
/// `Navigator.of(context).pop()` just like a regular dialog.
void showPsychLoading(BuildContext context, String message) {
  showGeneralDialog(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 400),
    pageBuilder: (_, __, ___) => PsychLoadingOverlay(message: message),
    transitionBuilder: (_, anim, __, child) {
      return FadeTransition(
        opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
        child: child,
      );
    },
  );
}
