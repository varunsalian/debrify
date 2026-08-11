import 'dart:math';

import 'package:flutter/material.dart';

/// The indeterminate spinner tucked into the bottom-right corner while the
/// splash holds for the Home board: a faint ring with a bright accent comet
/// sweeping round it, deliberately small enough to read as a status detail
/// rather than a second focal point beside the lockup.
///
/// Tiny fixed canvas + its own RepaintBoundary = a cheap per-frame raster even
/// on the weakest TV GPUs. [colors] come from the active launch ident so the
/// spinner belongs to whatever world the splash is set in.
///
/// TV contract: this one runs CONTINUOUSLY for as long as the splash holds, so
/// unlike the one-shot reveal painters every per-frame cost here repeats
/// indefinitely. Everything that survives a frame — shader, paints, geometry —
/// is built once per size; `paint` only rotates and draws. No saveLayer, no
/// blur, three draws a frame.
class LoadingSweepPainter extends CustomPainter {
  final Animation<double> animation;
  final List<Color> colors;

  /// How much of the ring the comet spans. Short enough to leave the track
  /// visible behind it, long enough to show the gradient's fall-off.
  static const double _arcSweep = 2.2; // radians, ~126°
  static const double _fullTurn = 2 * pi;

  Size? _cache;
  late Offset _center, _head;
  late Rect _box;
  late double _headRadius;
  late Paint _trackPaint, _cometPaint, _headPaint;

  LoadingSweepPainter(this.animation, {required this.colors})
      : super(repaint: animation);

  void _build(Size size) {
    if (_cache == size) return;
    _cache = size;
    final stroke = max(1.5, size.shortestSide * 0.11);
    final r = (size.shortestSide - stroke) / 2;
    _center = Offset(size.width / 2, size.height / 2);
    _box = Rect.fromCircle(center: Offset.zero, radius: r);
    _head = Offset(cos(_arcSweep) * r, sin(_arcSweep) * r);
    _headRadius = stroke * 0.30;

    _trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = const Color(0xFFE9EDFF).withValues(alpha: 0.12);

    // The gradient spans the WHOLE circle even though only `_arcSweep` of it
    // is drawn. Confining it to [0, _arcSweep] would leave the round start cap
    // — which reaches back across the 0/2π seam — outside the gradient, where
    // TileMode.clamp resolves to the last colour and paints a bright sliver on
    // what is meant to be the comet's transparent tail.
    const head = _arcSweep / _fullTurn;
    _cometPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        startAngle: 0,
        endAngle: _fullTurn,
        colors: [
          colors.first.withValues(alpha: 0),
          colors.first,
          colors.last,
          colors.last.withValues(alpha: 0),
        ],
        stops: const [0.0, head * 0.62, head, 1.0],
      ).createShader(_box);

    // A hot core on the leading tip — the one bit of polish that makes it read
    // as a moving light rather than a rotating shape. Deliberately whiter and
    // narrower than the stroke: at the arc's own colour and half-width it
    // would sit exactly under the round cap and be invisible.
    _headPaint = Paint()..color = const Color(0xFFFFFFFF).withValues(alpha: 0.85);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.shortestSide <= 1.5) return;
    _build(size);

    canvas.drawCircle(_center, _box.width / 2, _trackPaint);

    canvas.save();
    canvas.translate(_center.dx, _center.dy);
    // Linear rotation, so the repeating controller loops seamlessly: t == 0
    // and t == 1 are the same frame.
    canvas.rotate(animation.value * _fullTurn);
    canvas.drawArc(_box, 0, _arcSweep, false, _cometPaint);
    canvas.drawCircle(_head, _headRadius, _headPaint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant LoadingSweepPainter old) =>
      old.animation != animation || old.colors != colors;
}
