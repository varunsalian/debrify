import 'package:flutter/material.dart';

class TvVignettePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    // Match Android vignette: 60% radius, transparent center to dark edges
    final gradient = RadialGradient(
      center: Alignment.center,
      radius: 0.6, // Match Android gradientRadius="60%"
      colors: const [
        Color(0x00000000), // Transparent center
        Color(0x66000000), // Lighter black edges (102/255 alpha) so static is visible
      ],
      stops: const [0.0, 1.0],
    );
    final paint = Paint()..shader = gradient.createShader(rect);
    canvas.drawRect(rect, paint);
  }

  @override
  bool shouldRepaint(covariant TvVignettePainter oldDelegate) => false;
}
