import 'dart:math';
import 'package:flutter/material.dart';

class AnimatedPremiumBackground extends StatefulWidget {
  final Widget child;
  const AnimatedPremiumBackground({super.key, required this.child});

  @override
  State<AnimatedPremiumBackground> createState() => _AnimatedPremiumBackgroundState();
}

class _AnimatedPremiumBackgroundState extends State<AnimatedPremiumBackground>
    with TickerProviderStateMixin {
  late final AnimationController _gradientCtrl;
  late final AnimationController _noiseCtrl;

  @override
  void initState() {
    super.initState();
    _gradientCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12), // Reduced from 18s for better performance
    )..repeat(reverse: true);
    _noiseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20), // Reduced from 30s for better performance
    )..repeat();
  }

  @override
  void dispose() {
    _gradientCtrl.dispose();
    _noiseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_gradientCtrl, _noiseCtrl]),
      builder: (context, _) {
        final t = _gradientCtrl.value;
        final colors = _lerpGradient(t);
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment(-1 + 2 * t, -1),
              end: Alignment(1 - 2 * t, 1),
              colors: colors,
            ),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Soft vignette
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0.0, -0.2),
                    radius: 1.2,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.35),
                    ],
                    stops: const [0.6, 1.0],
                  ),
                ),
              ),
              // Floating particles - optimized with RepaintBoundary
              RepaintBoundary(
                child: CustomPaint(
                  painter: _ParticlesPainter(_noiseCtrl.value),
                ),
              ),
              // Blur frosted overlay for content contrast
              Container(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.2),
                ),
              ),
              // RepaintBoundary to prevent child widgets from triggering background repaints
              RepaintBoundary(
                child: widget.child,
              ),
            ],
          ),
        );
      },
    );
  }

  List<Color> _lerpGradient(double t) {
    // Indigo -> Violet -> Cyan blend
    const a = Color(0xFF0B1220); // deep base
    const b = Color(0xFF1E293B); // slate
    const c = Color(0xFF232860); // indigo deep
    const d = Color(0xFF3B82F6); // blue
    const e = Color(0xFF8B5CF6); // violet
    return [
      Color.lerp(a, e, t * 0.8)!,
      Color.lerp(b, d, 0.2 + 0.6 * (1 - t))!,
      Color.lerp(c, e, 0.4 + 0.6 * t)!,
    ];
  }
}

class _ParticlesPainter extends CustomPainter {
  final double t;
  _ParticlesPainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final rnd = Random(7);
    final paint = Paint()
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);

    for (int i = 0; i < 12; i++) { // Reduced from 24 for TV performance
      final baseX = rnd.nextDouble() * size.width;
      final baseY = rnd.nextDouble() * size.height;
      final phase = rnd.nextDouble() * 2 * pi;
      final amp = 10 + rnd.nextDouble() * 40;
      final x = baseX + sin(phase + t * 2 * pi) * amp;
      final y = baseY + cos(phase + t * 2 * pi) * amp * 0.6;

      paint.color = [
        const Color(0xFF6366F1),
        const Color(0xFF22D3EE),
        const Color(0xFF8B5CF6),
        const Color(0xFFF59E0B),
      ][i % 4].withValues(alpha: 0.08 + 0.04 * (i % 3));

      canvas.drawCircle(Offset(x, y), 3 + (i % 3) * 1.5, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ParticlesPainter oldDelegate) => oldDelegate.t != t;
} 