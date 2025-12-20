import 'package:flutter/material.dart';

class BloomOverlayPainter extends CustomPainter {
  final DateTime? startedAt;
  BloomOverlayPainter({required this.startedAt});
  @override
  void paint(Canvas canvas, Size size) {
    if (startedAt == null) return;
    final elapsedMs = DateTime.now()
        .difference(startedAt!)
        .inMilliseconds
        .toDouble();
    final t = (elapsedMs / 1500.0).clamp(0.0, 1.0);
    // Ease in-out opacity using a smooth curve
    final ease = Curves.easeInOut.transform(t);
    final opacity =
        (0.0 + 0.18 * (ease < 0.5 ? (ease * 2.0) : (1.0 - (ease - 0.5) * 2.0)))
            .clamp(0.0, 0.18);

    final rect = Offset.zero & size;
    // Radial soft white bloom at center
    final gradient = RadialGradient(
      center: Alignment.center,
      radius: 0.9,
      colors: [
        Colors.white.withOpacity(opacity),
        Colors.white.withOpacity(0.0),
      ],
      stops: const [0.0, 1.0],
    );
    final paint = Paint()
      ..shader = gradient.createShader(rect)
      ..blendMode = BlendMode.screen;
    canvas.drawRect(rect, paint);
  }

  @override
  bool shouldRepaint(covariant BloomOverlayPainter oldDelegate) => true;
}
