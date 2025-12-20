import 'package:flutter/material.dart';
import '../models/hud_state.dart';

class DoubleTapRipplePainter extends CustomPainter {
  final DoubleTapRipple ripple;
  DoubleTapRipplePainter(this.ripple);
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white.withOpacity(0.15);
    canvas.drawCircle(ripple.center, 80, paint);
    final tp = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(ripple.icon.codePoint),
        style: TextStyle(
          fontSize: 48,
          fontFamily: ripple.icon.fontFamily,
          package: ripple.icon.fontPackage,
          color: Colors.white,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    tb(Size s) =>
        Offset(ripple.center.dx - s.width / 2, ripple.center.dy - s.height / 2);
    tp.layout();
    tp.paint(canvas, tb(tp.size));
  }

  @override
  bool shouldRepaint(covariant DoubleTapRipplePainter oldDelegate) => true;
}
