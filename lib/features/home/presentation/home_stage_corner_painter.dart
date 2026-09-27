import 'package:flutter/material.dart';

/// Paints the four corner "wedges" that make a rectangle read as a rounded
/// card — the area between the rect and its rounded inset, filled with the
/// page ink. Used instead of a ClipRRect wherever the box contains the
/// underlay trailer: a clip would introduce a saveLayer over the punch hole
/// and break its BlendMode.clear against the translucent surface, while a
/// plain fill painted ABOVE the hole is the proven pattern.
class HomeStageCornerPainter extends CustomPainter {
  final double radius;
  final Color color;
  const HomeStageCornerPainter({required this.radius, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final path = Path.combine(
      PathOperation.difference,
      Path()..addRect(rect),
      Path()..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius))),
    );
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(HomeStageCornerPainter old) =>
      old.radius != radius || old.color != color;
}
