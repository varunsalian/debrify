import 'dart:math' as math;
import 'package:flutter/material.dart';

class TvScanlinesPatternPainter extends CustomPainter {
  final double offset;
  TvScanlinesPatternPainter({required this.offset});

  @override
  void paint(Canvas canvas, Size size) {
    // Match Android: oscillate between -20 and +20 pixels
    final oscillation = math.sin(offset * 2 * math.pi) * 20;

    // Draw horizontal scan lines with slight white overlay
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.05)
      ..strokeWidth = 1;

    // Draw lines every 4 pixels with animated offset
    for (double y = oscillation; y < size.height + 40; y += 4) {
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant TvScanlinesPatternPainter oldDelegate) => true;
}
