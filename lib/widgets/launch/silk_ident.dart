import 'dart:math';

import 'package:flutter/material.dart';

import 'launch_ident.dart';

/// Silk — a violet satin sheet still moving from being laid down. The name
/// surfaces where the light rolls over the folds, and the mark is stitched in
/// champagne thread, one stitch at a time.
///
/// TV notes: the cloth is N flat-filled vertical bands (15 on TV, 30
/// elsewhere) whose fold phase EASES TO A CONSTANT — at rest it is a static
/// band field, not an animation held still. Letter tone is picked from six
/// pre-baked pearl sets (the quantized-colour idiom), never a per-frame style
/// change. The stitches are pre-combined into two cumulative paths per count
/// (the thread alternates two golds), so the whole seam is two draws.
///
/// Timeline: .14–.60 the mark stitches itself · .44–.88 the name surfaces on
/// the folds · .52–.82 the emblem's inner sheen · fold motion settles by rest.
class SilkIdent extends LaunchIdent {
  const SilkIdent();

  @override
  String get id => 'silk';
  @override
  String get label => 'Silk';
  @override
  String get subtitle =>
      'Violet satin with the name woven in and the mark stitched in thread';
  @override
  Duration get revealDuration => const Duration(milliseconds: 2900);
  @override
  Color get baseColor => const Color(0xFF0A0414);
  @override
  List<Color> get sweepColors =>
      const [Color(0xFFE3C79A), Color(0xFFC9A8F2)];

  @override
  CustomPainter createPainter(
    Animation<double> animation, {
    required bool Function() isTelevision,
    IdentPalette? palette,
  }) =>
      _SilkPainter(animation, isTelevision: isTelevision);
}

class _SilkPainter extends CustomPainter {
  final Animation<double> animation;
  final bool Function() isTelevision;

  Size? _size;
  bool? _lw;
  IdentWordLayout? _word;
  late double _u, _cx, _cy, _baseY, _startX, _g;
  late int _bands;
  /// Cumulative seam geometry: `_seamA[k]`/`_seamB[k]` hold the even/odd
  /// stitches among the first k, so drawing k stitches costs two paths rather
  /// than k. Index 0 is empty.
  late List<Path> _seamA, _seamB;
  late int _stitchCount;
  late Path _mark;
  late Rect _veilRect;
  late Shader _veil;
  late List<List<TextPainter>> _tones;

  static const int _toneSteps = 6;
  static const Color _dim = Color(0xFFB79AD8);
  static const Color _pearl = Color(0xFFFFF8FF);

  _SilkPainter(this.animation, {required this.isTelevision})
      : super(repaint: animation);

  void _layout(Size size, bool lightweight) {
    if (_word != null && _size == size && _lw == lightweight) return;
    _size = size;
    _lw = lightweight;
    final w = size.width, h = size.height;
    _u = identUnit(size);
    _cx = w / 2;
    _cy = h / 2 - _u * 1.15;
    _baseY = h / 2 + _u * 2.4;
    _g = _u * 2.0;
    _bands = lightweight ? 15 : 30;
    _mark = identPlayPath(_g);

    // Stitches: short segments walked off the outline, accumulated into two
    // alternating-thread paths per count so the seam is two draws at any
    // point in the reveal.
    final stitches = <Path>[];
    for (final m in _mark.computeMetrics()) {
      final step = _u * 0.29;
      for (double d = 0; d < m.length; d += step) {
        stitches.add(m.extractPath(d, min(d + step * 0.55, m.length)));
      }
    }
    _stitchCount = stitches.length;
    _seamA = [Path()];
    _seamB = [Path()];
    for (int i = 0; i < _stitchCount; i++) {
      final even = i.isEven;
      _seamA.add(even
          ? (Path.from(_seamA.last)..addPath(stitches[i], Offset.zero))
          : _seamA.last);
      _seamB.add(even
          ? _seamB.last
          : (Path.from(_seamB.last)..addPath(stitches[i], Offset.zero)));
    }

    _veilRect = Rect.fromLTWH(0, 0, w, h);
    _veil = const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0x8C06030C), Color(0x0006030C), Color(0xB8040208)],
      stops: [0.0, 0.45, 1.0],
    ).createShader(_veilRect);

    _word = IdentWordLayout.fit(
      styleFor: (fz) => TextStyle(
        fontSize: fz,
        fontFamily: 'serif',
        fontFamilyFallback: const ['Didot', 'Bodoni 72', 'Georgia'],
        fontWeight: FontWeight.w500,
        height: 1.0,
        color: _pearl,
      ),
      fontSize: _u * 1.25,
      trackingFactor: 0.24,
      maxWidth: min(w * 0.76, _u * 11),
    );
    _startX = w / 2 - _word!.width / 2;
    _tones = [
      for (int k = 0; k < _toneSteps; k++)
        _word!.set(
          'tone$k',
          (s) => s.copyWith(
              color: Color.lerp(_dim, _pearl, k / (_toneSteps - 1))),
        ),
    ];
  }

  /// Fold brightness at horizontal position [u] (0..1) for this phase.
  double _fold(double u, double phase, double amp) =>
      0.5 + 0.5 * sin(u * pi * 5.2 + phase + sin(u * 7.3 + phase * 0.6) * 0.75 * amp);

  @override
  void paint(Canvas canvas, Size size) {
    final t = animation.value;
    final lightweight = isTelevision();
    _layout(size, lightweight);
    final word = _word!;
    final w = size.width, h = size.height;

    // Fold phase eases to a constant — motion stops, the cloth stays.
    final ease = identIoSine(identClamp(t / 0.92, 0, 1));
    final phase = ease * pi * 1.35;
    final amp = 1 - ease * 0.55;

    final bw = w / _bands;
    for (int i = 0; i < _bands; i++) {
      final b = _fold((i + 0.5) / _bands, phase, amp);
      final lit = Color.lerp(
          const Color(0xFF4B2A74), const Color(0xFFC6A6F2), pow(b, 4).toDouble())!;
      canvas.drawRect(
        Rect.fromLTWH(i * bw, 0, bw + 1, h),
        Paint()
          ..color =
              Color.lerp(const Color(0xFF160A26), lit, pow(b, 0.9).toDouble())!,
      );
    }
    // Top-to-bottom fall-off so it reads as cloth, not stripes.
    canvas.drawRect(_veilRect, Paint()..shader = _veil);

    // The stitched emblem.
    final sp = identOutCubic(identClamp((t - 0.14) / 0.46, 0, 1));
    if (sp > 0) {
      canvas.save();
      canvas.translate(_cx, _cy);
      final upto = (sp * _stitchCount).floor();
      final thread = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = max(1.4, _u * 0.055)
        ..strokeCap = StrokeCap.round;
      canvas.drawPath(
          _seamA[upto], thread..color = const Color(0xFFF3E2BE));
      canvas.drawPath(
          _seamB[upto], thread..color = const Color(0xFFD8B77E));
      final fill = identClamp((t - 0.52) / 0.30, 0, 1);
      if (fill > 0) {
        canvas.drawPath(
          _mark,
          Paint()..color = Color.fromRGBO(243, 226, 190, fill * 0.13),
        );
      }
      canvas.restore();
    }

    // The name surfaces where the light rolls.
    final wr = identClamp((t - 0.44) / 0.44, 0, 1);
    for (int i = 0; i < kIdentWord.length; i++) {
      final lt = identClamp((wr - i * 0.045) / 0.5, 0, 1);
      if (lt <= 0) continue;
      double x = _startX;
      for (int k = 0; k < i; k++) {
        x += word.widths[k] + word.tracking;
      }
      final b = _fold((x + word.widths[i] / 2) / w, phase, amp);
      final tone = identClamp(pow(b, 2).toDouble() * 0.85 + lt * 0.15, 0, 1);
      final set = _tones[(tone * (_toneSteps - 1)).round()];
      // Reveal is a rise-through-clip, so no per-letter alpha is needed.
      canvas.save();
      canvas.clipRect(Rect.fromLTWH(
        x - _u * 0.1,
        _baseY - word.fontSize * 0.95,
        word.widths[i] + _u * 0.2,
        word.fontSize * 1.15 * identOutCubic(lt),
      ));
      word.paintLetter(canvas, set, i, _startX, _baseY);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _SilkPainter old) =>
      old.animation != animation;
}
