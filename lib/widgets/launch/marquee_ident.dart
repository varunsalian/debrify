import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'launch_ident.dart';

/// Marquee — prestige-drama title card. The name in gilded serif capitals
/// rising through a baseline clip, a single specular sheen rolling across the
/// gold, hairline flourishes opening around a gold-outlined emblem.
///
/// TV notes: the sheen is a CLIP-BAND (rotated parallelogram clip + a
/// pre-laid-out bright set), not a mask layer; entrance is rise-through-clip,
/// so no text alpha exists anywhere — zero saveLayer at any point.
///
/// Timeline: 0–.40 emblem outline draws · .18–.65 letters rise ·
/// .35–.75 flourishes open · .55–.95 sheen · rest.
class MarqueeIdent extends LaunchIdent {
  const MarqueeIdent();

  @override
  String get id => 'marquee';
  @override
  String get label => 'Marquee';
  @override
  String get subtitle =>
      'Gilded serif première — a specular sheen rolls across the gold';
  @override
  Duration get revealDuration => const Duration(milliseconds: 2600);
  @override
  Color get baseColor => const Color(0xFF0B0804);
  @override
  BoxDecoration get backdrop => const BoxDecoration(
        // Warm black with a candle-warm vignette, pre-blended to opaque.
        gradient: RadialGradient(
          center: Alignment(0, -0.1),
          radius: 1.0,
          colors: [Color(0xFF1A1207), Color(0xFF0B0804)],
        ),
      );
  @override
  List<Color> get sweepColors =>
      const [Color(0xFFD9B95C), Color(0xFFF3E5B0)];

  @override
  CustomPainter createPainter(
    Animation<double> animation, {
    required bool Function() isTelevision,
  }) =>
      _MarqueePainter(animation, isTelevision: isTelevision);
}

class _MarqueePainter extends CustomPainter {
  final Animation<double> animation;
  final bool Function() isTelevision;

  Size? _size;
  IdentWordLayout? _word;
  late double _startX, _baseY, _markY, _g;
  late Path _mark;
  late List<ui.PathMetric> _markMetrics;
  late Shader _markStroke;
  late List<TextPainter> _gold;
  late List<TextPainter> _bright;

  _MarqueePainter(this.animation, {required this.isTelevision})
      : super(repaint: animation);

  static const _goldStops = [
    Color(0xFF8A6A28),
    Color(0xFFF3E5B0),
    Color(0xFFD9B95C),
    Color(0xFF96742C),
    Color(0xFF5C4415),
  ];
  static const _brightStops = [
    Color(0xFFEADFA8),
    Color(0xFFFFFBE8),
    Color(0xFFF7ECC0),
    Color(0xFFE0C878),
    Color(0xFFB89A4E),
  ];

  void _layout(Size size) {
    if (_word != null && _size == size) return;
    _size = size;
    final w = size.width, h = size.height;
    _word = IdentWordLayout.fit(
      styleFor: (fz) => TextStyle(
        fontSize: fz,
        fontWeight: FontWeight.w600,
        fontFamily: 'Didot',
        fontFamilyFallback: const ['Bodoni 72', 'Playfair Display', 'serif'],
        height: 1.0,
        color: const Color(0xFFF3E5B0),
      ),
      fontSize: h * 0.19,
      trackingFactor: 0.12,
      maxWidth: w * 0.64,
    );
    _startX = w / 2 - _word!.width / 2;
    _baseY = h * 0.58;
    _markY = h * 0.30;
    _g = h * 0.14;
    _mark = identPlayPath(_g);
    // Metrics cached: the path never changes, and computing metrics per frame
    // during the outline draw would be per-frame native allocation.
    _markMetrics = _mark.computeMetrics().toList();
    // Gradients live in letter-local space (baseline at y = 0), so one shader
    // serves every letter regardless of x.
    Shader vGrad(List<Color> colors) => LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: colors,
          stops: const [0, 0.35, 0.55, 0.8, 1],
        ).createShader(
          Rect.fromLTRB(-40, -_word!.fontSize, 40, _word!.fontSize * 0.15),
        );
    _gold = _word!.set(
      'gold',
      (s) => s.copyWith(foreground: Paint()..shader = vGrad(_goldStops)),
    );
    _bright = _word!.set(
      'bright',
      (s) => s.copyWith(foreground: Paint()..shader = vGrad(_brightStops)),
    );
    _markStroke = const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFFF3E5B0), Color(0xFF96742C)],
    ).createShader(Rect.fromCircle(center: Offset.zero, radius: _g / 2));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final t = animation.value;
    _layout(size);
    final word = _word!;
    final w = size.width;
    final lightweight = isTelevision();

    // Letters rise through a baseline clip — below the clip they don't exist,
    // so the entrance needs no alpha at all.
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(
      0,
      _baseY - word.fontSize * 1.25,
      w,
      _baseY + word.fontSize * 0.10,
    ));
    for (int i = 0; i < kIdentWord.length; i++) {
      final lt = identClamp((t - (0.18 + i * 0.045)) / 0.34, 0, 1);
      if (lt <= 0) continue;
      final dy = (1 - identOutCubic(lt)) * word.fontSize * 1.15;
      word.paintLetter(canvas, _gold, i, _startX, _baseY, dy: dy);
    }
    canvas.restore();

    // Specular sheen: a rotated clip band travels the word once, revealing
    // the pre-laid-out bright set inside it.
    final sp = identClamp((t - 0.55) / 0.40, 0, 1);
    if (sp > 0 && sp < 1) {
      final x = identLerp(
          _startX - 140, _startX + word.width + 140, identIoSine(sp));
      canvas.save();
      final band = Path()
        ..moveTo(x - 55, _baseY + word.fontSize * 0.2)
        ..lineTo(x + 5, _baseY + word.fontSize * 0.2)
        ..lineTo(x + 55, _baseY - word.fontSize * 1.3)
        ..lineTo(x - 5, _baseY - word.fontSize * 1.3)
        ..close();
      canvas.clipPath(band);
      for (int i = 0; i < kIdentWord.length; i++) {
        final lt = identClamp((t - (0.18 + i * 0.045)) / 0.34, 0, 1);
        if (lt < 1) continue; // only settled letters catch the light
        word.paintLetter(canvas, _bright, i, _startX, _baseY);
      }
      canvas.restore();
    }

    // Emblem: the gold outline draws itself on, then breathes a soft fill.
    final dp = identOutCubic(identClamp(t / 0.40, 0, 1));
    canvas.save();
    canvas.translate(w / 2, _markY);
    if (dp > 0) {
      identGlowPath(
        canvas,
        _mark,
        Color.fromRGBO(243, 229, 176, 0.30 * dp),
        _g * 0.10,
        lightweight: lightweight,
      );
      final strokePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _g * 0.03 < 1.4 ? 1.4 : _g * 0.03
        ..strokeCap = StrokeCap.round
        ..shader = _markStroke;
      if (dp >= 1) {
        canvas.drawPath(_mark, strokePaint);
      } else {
        for (final m in _markMetrics) {
          canvas.drawPath(m.extractPath(0, m.length * dp), strokePaint);
        }
      }
    }
    final fa = identClamp((t - 0.42) / 0.30, 0, 1) * 0.35;
    if (fa > 0) {
      canvas.drawPath(
        _mark,
        Paint()..color = Color.fromRGBO(217, 185, 92, fa),
      );
    }
    canvas.restore();

    // Hairline flourishes either side of the emblem, tipped with gold points.
    final fl = identOutCubic(identClamp((t - 0.35) / 0.40, 0, 1));
    if (fl > 0) {
      final y = _markY, reach = w * 0.16 * fl, gap = _g * 0.85;
      final line = Paint()
        ..color = const Color(0xFFD9B95C).withValues(alpha: 0.55)
        ..strokeWidth = 1;
      canvas.drawLine(
          Offset(w / 2 - gap, y), Offset(w / 2 - gap - reach, y), line);
      canvas.drawLine(
          Offset(w / 2 + gap, y), Offset(w / 2 + gap + reach, y), line);
      final tip = Paint()..color = const Color(0xFFF3E5B0);
      canvas.drawCircle(Offset(w / 2 - gap - reach, y), 1.6, tip);
      canvas.drawCircle(Offset(w / 2 + gap + reach, y), 1.6, tip);
    }
  }

  @override
  bool shouldRepaint(covariant _MarqueePainter old) =>
      old.animation != animation;
}
