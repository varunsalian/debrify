import 'dart:math';

import 'package:flutter/material.dart';

import 'launch_ident.dart';

/// Monogram — confidence by subtraction. A single hairline ring draws itself
/// closed around a small, perfect mark; the name appears underneath in quiet,
/// wide-tracked capitals, closed by one accent dot.
///
/// TV notes: one arc, one dot, a path fill and quantized-alpha type — the
/// cheapest ident on the card by an order of magnitude.
///
/// Timeline: 0–.55 ring draws (a point of light leads it) · .34–.68 mark
/// breathes in · .62–.9 name fades up · .85 the full stop · rest.
class MonogramIdent extends LaunchIdent {
  const MonogramIdent();

  @override
  String get id => 'monogram';
  @override
  String get label => 'Monogram';
  @override
  String get subtitle =>
      'A hairline ring closes around a small perfect mark — pure restraint';
  @override
  Duration get revealDuration => const Duration(milliseconds: 2200);
  @override
  Color get baseColor => const Color(0xFF030309);
  @override
  List<Color> get sweepColors =>
      const [Color(0xFF818CF8), Color(0xFFAAB1D6)];

  @override
  CustomPainter createPainter(
    Animation<double> animation, {
    required bool Function() isTelevision,
    IdentPalette? palette,
  }) =>
      _MonogramPainter(animation, isTelevision: isTelevision);
}

class _MonogramPainter extends CustomPainter {
  final Animation<double> animation;
  final bool Function() isTelevision;

  Size? _size;
  IdentWordLayout? _word;
  IdentAlphaSets? _letters;
  late double _cx, _cy, _r, _startX;
  late Path _markFull;
  late Path _markInner;
  late Rect _markRect;
  late Shader _markShader;

  _MonogramPainter(this.animation, {required this.isTelevision})
      : super(repaint: animation);

  void _layout(Size size) {
    if (_word != null && _size == size) return;
    _size = size;
    final w = size.width, h = size.height;
    _cx = w / 2;
    _cy = h * 0.42;
    _r = min(w, h) * 0.17;
    final s = _r * 0.74;
    _markFull = identPlayPath(s);
    _markInner = identPlayPath(s * 0.52);
    _markRect = Rect.fromLTRB(-s / 2, 0, s / 2, 1);
    _markShader = LinearGradient(
      colors: const [Color(0xFF4F74FF), Color(0xFF8A5CFF)],
    ).createShader(_markRect);
    _word = IdentWordLayout.fit(
      styleFor: (fz) => TextStyle(
        fontSize: fz,
        fontWeight: FontWeight.w500,
        height: 1.0,
        color: const Color(0xFFAAB1D6),
      ),
      fontSize: h * 0.052,
      trackingFactor: 1.1,
      maxWidth: w * 0.42,
    );
    _startX = w / 2 - _word!.width / 2;
    _letters = IdentAlphaSets(
        _word!, 'mono', const Color(0xFFAAB1D6).withValues(alpha: 0.85));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final t = animation.value;
    _layout(size);
    final word = _word!;
    final lightweight = isTelevision();

    // Ring draws on from the top, clockwise. (The flat backdrop is the
    // DecoratedBox outside this painter.)
    final sweep = identIoSine(identClamp(t / 0.55, 0, 1));
    if (sweep > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: Offset(_cx, _cy), radius: _r),
        -pi / 2,
        sweep * pi * 2,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = const Color(0xFFE9EDFF).withValues(alpha: 0.8),
      );
    }
    // The travelling point of light leading the draw.
    if (sweep < 1) {
      final a = -pi / 2 + sweep * pi * 2;
      final p = Offset(_cx + cos(a) * _r, _cy + sin(a) * _r);
      if (!lightweight) {
        canvas.drawCircle(
          p,
          4,
          Paint()
            ..color = const Color(0xFF818CF8).withValues(alpha: 0.9)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
        );
      } else {
        canvas.drawCircle(
            p, 3.4, Paint()..color = const Color(0x59818CF8));
      }
      canvas.drawCircle(p, 1.8, Paint()..color = const Color(0xFFE9EDFF));
    }

    // Small mark breathes in at centre.
    final mk = identOutCubic(identClamp((t - 0.34) / 0.34, 0, 1));
    if (mk > 0) {
      canvas.save();
      canvas.translate(_cx, _cy);
      final grow = identLerp(0.92, 1, mk);
      canvas.scale(grow, grow);
      // Cached shader once settled; alpha-baked rebuild only during the short
      // breathe-in ramp (shader+Paint.color fades are backend-dependent).
      canvas.drawPath(
        _markFull,
        Paint()
          ..shader = mk >= 1
              ? _markShader
              : LinearGradient(colors: [
                  Color.fromRGBO(79, 116, 255, mk),
                  Color.fromRGBO(138, 92, 255, mk),
                ]).createShader(_markRect),
      );
      canvas.drawPath(
        _markInner,
        Paint()..color = Color.fromRGBO(223, 230, 255, 0.18 * mk),
      );
      canvas.restore();
    }

    // The name, small and wide.
    for (int i = 0; i < kIdentWord.length; i++) {
      final lt = identClamp((t - (0.62 + i * 0.02)) / 0.30, 0, 1);
      if (lt <= 0) continue;
      final set = _letters!.at(identOutCubic(lt));
      if (set == null) continue;
      word.paintLetter(canvas, set, i, _startX, _cy + _r + 40);
    }

    // One accent dot below — the full stop.
    final dot = identClamp((t - 0.85) / 0.15, 0, 1);
    if (dot > 0) {
      canvas.drawCircle(
        Offset(_cx, _cy + _r + 62),
        1.6,
        Paint()..color = Color.fromRGBO(129, 140, 248, dot),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MonogramPainter old) =>
      old.animation != animation;
}
