import 'dart:math';
import 'package:flutter/material.dart';

class AnimatedPremiumBackground extends StatefulWidget {
  final Widget child;
  final bool isTelevision;
  const AnimatedPremiumBackground({super.key, required this.child, this.isTelevision = false});

  @override
  State<AnimatedPremiumBackground> createState() => _AnimatedPremiumBackgroundState();
}

class _AnimatedPremiumBackgroundState extends State<AnimatedPremiumBackground>
    with TickerProviderStateMixin {
  AnimationController? _gradientCtrl;
  AnimationController? _noiseCtrl;

  @override
  void initState() {
    super.initState();
    if (!widget.isTelevision) {
      _gradientCtrl = AnimationController(
        vsync: this,
        duration: const Duration(seconds: 12),
      )..repeat(reverse: true);
      _noiseCtrl = AnimationController(
        vsync: this,
        duration: const Duration(seconds: 20),
      )..repeat();
    }
  }

  @override
  void dispose() {
    _gradientCtrl?.dispose();
    _noiseCtrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // TV: static gradient, no animations, no CustomPaint, no blur
    if (widget.isTelevision) {
      return Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment(-1, -1),
            end: Alignment(1, 1),
            colors: [Color(0xFF040610), Color(0xFF0A0E1A), Color(0xFF0E1230)],
          ),
        ),
        child: widget.child,
      );
    }

    return AnimatedBuilder(
      animation: Listenable.merge([_gradientCtrl!, _noiseCtrl!]),
      builder: (context, _) {
        final t = _gradientCtrl!.value;
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
                  painter: _ParticlesPainter(_noiseCtrl!.value),
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
    const a = Color(0xFF040610); // deep base
    const b = Color(0xFF0A0E1A); // dark slate
    const c = Color(0xFF0E1230); // indigo deep
    const d = Color(0xFF1E3A6E); // muted blue
    const e = Color(0xFF4338CA); // muted violet
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
      ][i % 4].withValues(alpha: 0.04 + 0.02 * (i % 3));

      canvas.drawCircle(Offset(x, y), 3 + (i % 3) * 1.5, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ParticlesPainter oldDelegate) => oldDelegate.t != t;
} 