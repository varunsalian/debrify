import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// The tuning ambience: staggered signal rings expanding from the stage
/// centre, a soft breathing glow behind the logo, and a slow diagonal sheen
/// sweeping the slab. Plain canvas paints only — this layer is the one the
/// video punch-through wipes, so no saveLayer/Opacity is allowed here.
class TuningWavesPainter extends CustomPainter {
  final Color brand;
  final Animation<double> t;
  TuningWavesPainter({required this.brand, required this.t})
    : super(repaint: t);

  @override
  void paint(Canvas canvas, Size size) {
    final v = t.value;
    final center = size.center(Offset.zero);

    // Breathing glow behind the logo.
    final glowAlpha = 0.10 + 0.05 * math.sin(2 * math.pi * v);
    final glowRadius = size.shortestSide * 0.42;
    canvas.drawCircle(
      center,
      glowRadius,
      Paint()
        ..shader = ui.Gradient.radial(center, glowRadius, [
          brand.withValues(alpha: glowAlpha),
          brand.withValues(alpha: 0),
        ]),
    );

    // Signal rings rippling outward from behind the logo.
    final ringColor = Color.lerp(brand, Colors.white, 0.35)!;
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    final maxGrow = size.shortestSide * 0.62;
    for (int i = 0; i < 3; i++) {
      final phase = (v + i / 3) % 1.0;
      final eased = Curves.easeOut.transform(phase);
      final fade = (1 - phase) * (1 - phase);
      ring.color = ringColor.withValues(alpha: 0.16 * fade);
      canvas.drawCircle(center, 30 + eased * maxGrow, ring);
    }

    // Diagonal sheen sweeping across the slab once per cycle.
    final sweep = Curves.easeInOut.transform(v);
    final x = size.width * (-0.35 + 1.7 * sweep);
    final band = Paint()
      ..shader = ui.Gradient.linear(
        Offset(x - 70, 0),
        Offset(x + 70, size.height),
        [
          Colors.white.withValues(alpha: 0),
          Colors.white.withValues(alpha: 0.06),
          Colors.white.withValues(alpha: 0),
        ],
        const [0.0, 0.5, 1.0],
      );
    canvas.drawRect(Offset.zero & size, band);
  }

  @override
  bool shouldRepaint(TuningWavesPainter oldDelegate) =>
      oldDelegate.brand != brand;
}
