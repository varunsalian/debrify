import 'package:flutter/material.dart';

/// The indeterminate sweep under the lockup while the splash holds for the
/// Home board: a faint track with a bright accent segment gliding across it.
/// Small fixed canvas + own RepaintBoundary = a cheap per-frame raster even on
/// the weakest TV GPUs. [colors] come from the active launch ident so the
/// sweep belongs to whatever world the splash is set in.
class LoadingSweepPainter extends CustomPainter {
  final Animation<double> animation;
  final List<Color> colors;

  // The segment shader is origin-anchored and cached per size; the canvas
  // translates to the segment's position each frame, so the continuously
  // running sweep creates nothing native per frame.
  Shader? _seg;
  Size? _segSize;

  LoadingSweepPainter(this.animation, {required this.colors})
      : super(repaint: animation);

  @override
  void paint(Canvas canvas, Size size) {
    final t = animation.value;
    final track = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, (size.height - 3) / 2, size.width, 3),
      const Radius.circular(2),
    );
    canvas.drawRRect(
      track,
      Paint()..color = const Color(0xFFE9EDFF).withValues(alpha: 0.10),
    );

    final segW = size.width * 0.34;
    if (_seg == null || _segSize != size) {
      _segSize = size;
      _seg = LinearGradient(colors: colors)
          .createShader(Rect.fromLTWH(0, 0, segW, 3));
    }
    final eased = Curves.easeInOutSine.transform(t);
    final x = -segW + eased * (size.width + segW);
    canvas.save();
    canvas.clipRRect(track);
    canvas.translate(x, (size.height - 3) / 2);
    canvas.drawRect(Rect.fromLTWH(0, 0, segW, 3), Paint()..shader = _seg);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant LoadingSweepPainter old) =>
      old.animation != animation || old.colors != colors;
}
