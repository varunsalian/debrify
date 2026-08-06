import 'dart:math';

import 'package:flutter/material.dart';

import 'launch_ident.dart';

/// Anamorphic — a cyan lens streak rakes across the letterbox and detonates
/// at centre. The lockup arrives with a chromatic fringe that pulls itself
/// back into register.
///
/// TV notes: the fringe is two pre-baked colour sets drawn at a shrinking
/// offset — when the offset reaches zero they stop being drawn at all, so the
/// settled frame is one clean set. The streak's gradients are baked ONCE into
/// a unit rect and stretched by the canvas, with alpha quantized into a short
/// ladder (the [IdentAlphaSets] idiom applied to shaders), so no native
/// shader is created per frame. The bars are flat rects. Zero saveLayer, no
/// blurs.
///
/// Timeline: 0–.42 the streak travels in · .28–.64 flare peak, mark blooms ·
/// .48–.88 the name converges out of its fringe · rest.
class AnamorphicIdent extends LaunchIdent {
  const AnamorphicIdent();

  @override
  String get id => 'anamorphic';
  @override
  String get label => 'Anamorphic';
  @override
  String get subtitle =>
      'A cyan lens flare rakes the letterbox and the lockup snaps into register';
  @override
  Duration get revealDuration => const Duration(milliseconds: 2400);
  @override
  Color get baseColor => const Color(0xFF020304);
  @override
  List<Color> get sweepColors =>
      const [Color(0xFF5FD0FF), Color(0xFFE8F4FF)];

  @override
  CustomPainter createPainter(
    Animation<double> animation, {
    required bool Function() isTelevision,
  }) =>
      _AnamorphicPainter(animation, isTelevision: isTelevision);
}

class _AnamorphicPainter extends CustomPainter {
  final Animation<double> animation;
  final bool Function() isTelevision;

  Size? _size;
  IdentWordLayout? _word;
  late double _u, _cx, _cy, _baseY, _startX, _g, _bar;
  late Path _mark;
  late Rect _markRect;
  late Shader _markShader;
  late List<TextPainter> _white, _red, _cyan;
  IdentAlphaSets? _letters;

  /// Streak gradients live in a unit rect centred on the origin; the canvas
  /// scales it to the frame's geometry, so one shader serves every size the
  /// streak passes through. Index is [_streaks][spec][alpha step].
  static const Rect _unit = Rect.fromLTRB(-0.5, -0.5, 0.5, 0.5);
  static const int _fade = 5;
  // len factor, thickness factor, peak alpha.
  static const List<List<double>> _spec = [
    [1.0, 0.55, 0.16],
    [0.7, 0.16, 0.34],
    [0.45, 0.045, 0.85],
  ];
  late List<List<Shader>> _streaks;
  late List<Shader> _vstreak;

  _AnamorphicPainter(this.animation, {required this.isTelevision})
      : super(repaint: animation);

  /// Nearest pre-baked alpha step for [a] (0..1), or -1 when invisible.
  static int _step(double a) =>
      a <= 0.02 ? -1 : (identClamp(a, 0, 1) * (_fade - 1)).round();

  void _layout(Size size) {
    if (_word != null && _size == size) return;
    _size = size;
    final w = size.width, h = size.height;
    _u = identUnit(size);
    _cx = w / 2;
    _cy = h / 2 - _u * 1.0;
    _baseY = h / 2 + _u * 2.35;
    _g = _u * 2.2;
    _bar = h * 0.085;
    _mark = identPlayPath(_g);
    _markRect = Rect.fromCenter(center: Offset.zero, width: _g, height: _g);
    _markShader = const LinearGradient(
      colors: [Color(0xFFEAF7FF), Color(0xFF7FC7EE)],
    ).createShader(_markRect);

    _streaks = [
      for (final s in _spec)
        [
          for (int k = 0; k < _fade; k++)
            LinearGradient(colors: [
              const Color(0x005FD0FF),
              Color.fromRGBO(150, 225, 255, s[2] * k / (_fade - 1)),
              const Color(0x005FD0FF),
            ]).createShader(_unit),
        ],
    ];
    _vstreak = [
      for (int k = 0; k < _fade; k++)
        LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0x0096E1FF),
            Color.fromRGBO(190, 235, 255, 0.30 * k / (_fade - 1)),
            const Color(0x0096E1FF),
          ],
        ).createShader(_unit),
    ];

    _word = IdentWordLayout.fit(
      styleFor: (fz) => TextStyle(
        fontSize: fz,
        fontWeight: FontWeight.w600,
        height: 1.0,
        color: const Color(0xFFE8F4FF),
      ),
      fontSize: _u * 1.25,
      trackingFactor: 0.26,
      maxWidth: min(w * 0.78, _u * 11.5),
      scaleX: 1.12,
    );
    _startX = w / 2 - _word!.width / 2;
    _white = _word!.base;
    _red = _word!.set('fr',
        (s) => s.copyWith(color: const Color(0xFFFF4D62).withValues(alpha: .5)));
    _cyan = _word!.set('fc',
        (s) => s.copyWith(color: const Color(0xFF4DD8FF).withValues(alpha: .5)));
    _letters = IdentAlphaSets(_word!, 'ana', const Color(0xFFE8F4FF));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final t = animation.value;
    final lightweight = isTelevision();
    _layout(size);
    final word = _word!;
    final w = size.width, h = size.height;

    final land = identClamp(t / 0.42, 0, 1);
    final fx = identLerp(-w * 0.15, _cx, identIoCubic(land));
    final flen = identLerp(w * 1.05, w * 0.52, identOutCubic(land));
    final hot = sin(identClamp((t - 0.28) / 0.36, 0, 1) * pi);

    // The streak — cached shaders stretched into place, gone before rest.
    if (t < 0.94) {
      final tail = t > 0.82 ? 1 - (t - 0.82) / 0.12 : 1.0;
      final k = _step(tail);
      if (k >= 0) {
        for (int i = 0; i < _spec.length; i++) {
          final len = flen * _spec[i][0], th = _u * _spec[i][1];
          canvas.save();
          canvas.translate(fx, _cy);
          canvas.scale(len, th);
          canvas.drawRect(_unit, Paint()..shader = _streaks[i][k]);
          canvas.restore();
        }
      }
      if (hot > 0.01 && !lightweight) {
        final r = Rect.fromCircle(center: Offset(fx, _cy), radius: _u * 3.2 * hot);
        canvas.drawRect(
          r,
          Paint()
            ..shader = RadialGradient(colors: [
              Color.fromRGBO(214, 242, 255, 0.55 * hot),
              const Color(0x005FD0FF),
            ]).createShader(r),
        );
      } else if (hot > 0.01) {
        canvas.drawCircle(Offset(fx, _cy), _u * 1.7 * hot,
            Paint()..color = Color.fromRGBO(214, 242, 255, 0.16 * hot));
      }
      final vk = _step(hot);
      if (vk >= 0) {
        canvas.save();
        canvas.translate(fx, _cy);
        canvas.scale(max(1, _u * 0.10), _u * 6.4);
        canvas.drawRect(_unit, Paint()..shader = _vstreak[vk]);
        canvas.restore();
      }
    }

    // The mark blooms at the focus.
    final mk = identOutCubic(identClamp((t - 0.34) / 0.30, 0, 1));
    if (mk > 0) {
      canvas.save();
      canvas.translate(_cx, _cy);
      final s = identLerp(1.18, 1, mk);
      canvas.scale(s, s);
      canvas.drawPath(
        _mark,
        Paint()
          ..shader = mk >= 1
              ? _markShader
              : LinearGradient(colors: [
                  Color.fromRGBO(234, 247, 255, mk),
                  Color.fromRGBO(127, 199, 238, mk),
                ]).createShader(_markRect),
      );
      canvas.restore();
    }

    // The name, chromatic fringe converging to nothing.
    final wr = identClamp((t - 0.48) / 0.40, 0, 1);
    if (wr > 0) {
      final o = _u * 0.55 * (1 - identOutCubic(wr));
      final e = identOutCubic(wr);
      final set = e >= 1 ? _white : _letters!.at(e);
      for (int i = 0; i < kIdentWord.length; i++) {
        if (o > _u * 0.03) {
          word.paintLetter(canvas, _red, i, _startX, _baseY, dx: -o);
          word.paintLetter(canvas, _cyan, i, _startX, _baseY, dx: o);
        }
        if (set != null) {
          word.paintLetter(canvas, set, i, _startX, _baseY);
        }
      }
    }

    // Letterbox bars, always on top.
    final bp = Paint()..color = const Color(0xFF000000);
    canvas.drawRect(Rect.fromLTWH(0, 0, w, _bar), bp);
    canvas.drawRect(Rect.fromLTWH(0, h - _bar, w, _bar), bp);
    final hair = Paint()..color = const Color(0x1F78BEEB);
    canvas.drawRect(Rect.fromLTWH(0, _bar, w, 1), hair);
    canvas.drawRect(Rect.fromLTWH(0, h - _bar - 1, w, 1), hair);
  }

  @override
  bool shouldRepaint(covariant _AnamorphicPainter old) =>
      old.animation != animation;
}
