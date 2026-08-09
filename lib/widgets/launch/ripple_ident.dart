import 'dart:math';

import 'package:flutter/material.dart';

import 'launch_ident.dart';

/// Ripple — one drop breaks a still indigo surface. The lockup rises out of
/// the water with its own reflection, and the reflection stops wobbling
/// exactly as the rings die.
///
/// TV notes: the reflection is the word redrawn through N horizontal clip
/// slices, each offset by a sine whose amplitude damps to zero — 5 slices on
/// TV, 12 elsewhere, so the worst frame costs about what the shipped Chrome
/// ident already costs (it draws the word five times over). The mark is not
/// reflected on TV. Rings are stroked ovals and are gone before rest.
///
/// Timeline: 0–.26 the drop falls · .26 impact, rings expand · .30–.76 the
/// lockup rises through the surface · wobble damps to nothing by rest.
class RippleIdent extends LaunchIdent {
  const RippleIdent();

  @override
  String get id => 'ripple';
  @override
  String get label => 'Ripple';
  @override
  String get subtitle =>
      'A drop breaks still water — the lockup rises with its reflection';
  @override
  Duration get revealDuration => const Duration(milliseconds: 2700);
  @override
  Color get baseColor => const Color(0xFF04060F);
  @override
  BoxDecoration get backdrop => const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF070B1B),
            Color(0xFF0E1740),
            Color(0xFF0B1234),
            Color(0xFF04060F),
          ],
          stops: [0.0, 0.60, 0.601, 1.0],
        ),
      );
  @override
  List<Color> get sweepColors =>
      const [Color(0xFF6E8CFF), Color(0xFFDCE4FF)];

  @override
  CustomPainter createPainter(
    Animation<double> animation, {
    required bool Function() isTelevision,
    IdentPalette? palette,
  }) =>
      _RipplePainter(animation, isTelevision: isTelevision);
}

class _RipplePainter extends CustomPainter {
  final Animation<double> animation;
  final bool Function() isTelevision;

  Size? _size;
  bool? _lw;
  IdentWordLayout? _word;
  late double _u, _cx, _yW, _g, _cy, _baseY, _startX;
  late int _slices;
  late Path _mark, _inner;
  late Rect _markRect;
  late Shader _markShader;
  /// Pre-baked alpha steps for the mark's rise. Rebuilding this gradient off
  /// `rise` ran ~75 native shader allocations across the reveal on TV.
  late List<Shader> _markFade;
  static const int _fade = 6;
  IdentAlphaSets? _letters;
  late List<TextPainter> _mirror;

  _RipplePainter(this.animation, {required this.isTelevision})
      : super(repaint: animation);

  void _layout(Size size, bool lightweight) {
    if (_word != null && _size == size && _lw == lightweight) return;
    _size = size;
    _lw = lightweight;
    final w = size.width, h = size.height;
    _u = identUnit(size);
    _cx = w / 2;
    _yW = h * 0.60;
    _g = _u * 2.4;
    _slices = lightweight ? 5 : 12;
    _mark = identPlayPath(_g);
    _inner = identPlayPath(_g * 0.52);
    _markRect = Rect.fromCenter(center: Offset.zero, width: _g, height: _g);
    _markShader = const LinearGradient(
      colors: [Color(0xFF5B7BFF), Color(0xFF9C7BFF)],
    ).createShader(_markRect);
    _markFade = [
      for (int k = 0; k < _fade; k++)
        LinearGradient(colors: [
          Color.fromRGBO(91, 123, 255, k / (_fade - 1)),
          Color.fromRGBO(156, 123, 255, k / (_fade - 1)),
        ]).createShader(_markRect),
    ];

    _word = IdentWordLayout.fit(
      styleFor: (fz) => TextStyle(
        fontSize: fz,
        fontWeight: FontWeight.w300,
        height: 1.0,
        color: const Color(0xFFDCE4FF),
      ),
      fontSize: _u * 1.15,
      trackingFactor: 0.30,
      maxWidth: min(w * 0.80, _u * 11.5),
    );
    _startX = w / 2 - _word!.width / 2;
    // Stack bottom-up off the waterline so the mark can never reach the word.
    _baseY = _yW - _u * 0.55;
    _cy = _baseY - _word!.fontSize * 0.75 - _u * 0.85 - _g * 0.40;
    _letters = IdentAlphaSets(_word!, 'water', const Color(0xFFDCE4FF));
    _mirror = _word!.set(
      'mirror',
      (s) => s.copyWith(color: const Color(0xFFDCE4FF).withValues(alpha: 0.30)),
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final t = animation.value;
    final lightweight = isTelevision();
    _layout(size, lightweight);
    final word = _word!;
    final w = size.width, h = size.height;

    canvas.drawRect(
      Rect.fromLTWH(0, _yW, w, max(1, _u * 0.02)),
      Paint()..color = const Color(0x2996AFFF),
    );

    // The drop.
    if (t < 0.30) {
      final f = identClamp(t / 0.26, 0, 1);
      final y = identLerp(-_u, _yW, identInCubic(f) * 0.6 + f * 0.4);
      canvas.drawOval(
        Rect.fromCenter(
            center: Offset(_cx, y),
            width: _u * 0.14,
            height: _u * 0.32 * (1 + f)),
        Paint()..color = const Color(0xE6C8D8FF),
      );
    }

    // Rings — all dead before rest.
    for (int k = 0; k < 5; k++) {
      final age = (t - 0.26 - k * 0.055) / 0.62;
      if (age <= 0 || age >= 1) continue;
      final r = _u * 11 * identOutCubic(age);
      canvas.drawOval(
        Rect.fromCenter(center: Offset(_cx, _yW), width: r * 2, height: r * 0.34),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = max(1, _u * 0.035 * (1 - age))
          ..color = Color.fromRGBO(160, 186, 255, (1 - age) * (1 - age) * 0.45),
      );
    }

    final rise = identOutCubic(identClamp((t - 0.30) / 0.46, 0, 1));
    if (rise <= 0) return;

    // Upright lockup, clipped to above the waterline and rising through it.
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, w, _yW));
    canvas.save();
    canvas.translate(0, identLerp(_u * 1.3, 0, rise));
    canvas.save();
    canvas.translate(_cx, _cy);
    final s = identLerp(0.9, 1, rise);
    canvas.scale(s, s);
    canvas.drawPath(
      _mark,
      Paint()
        ..shader = rise >= 1
            ? _markShader
            : _markFade[(rise * (_fade - 1)).round()],
    );
    canvas.drawPath(
      _inner,
      Paint()..color = Color.fromRGBO(226, 233, 255, 0.20 * rise),
    );
    canvas.restore();
    for (int i = 0; i < kIdentWord.length; i++) {
      final lt = identClamp((t - (0.42 + i * 0.026)) / 0.34, 0, 1);
      if (lt <= 0) continue;
      final set = _letters!.at(identOutCubic(lt));
      if (set == null) continue;
      word.paintLetter(canvas, set, i, _startX, _baseY);
    }
    canvas.restore();
    canvas.restore();

    // The reflection: horizontal slices, wobble damping to zero.
    final damp = 1 - identOutCubic(identClamp((t - 0.30) / 0.68, 0, 1));
    final hgt = h - _yW;
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, _yW, w, hgt));
    for (int i = 0; i < _slices; i++) {
      final y0 = _yW + i / _slices * hgt;
      final y1 = _yW + (i + 1) / _slices * hgt;
      // Progress-derived phase: frozen frame ⇒ frozen water.
      final dx = sin(i * 0.9 + t * 22) * _u * 0.28 * damp * (1 - i / _slices * 0.4);
      canvas.save();
      canvas.clipRect(Rect.fromLTWH(0, y0, w, y1 - y0 + 1));
      canvas.translate(dx, _yW * 2);
      canvas.scale(1, -1);
      for (int k = 0; k < kIdentWord.length; k++) {
        // Mirror only what has actually surfaced.
        if (t < 0.42 + k * 0.026) continue;
        word.paintLetter(canvas, _mirror, k, _startX, _baseY);
      }
      canvas.restore();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _RipplePainter old) =>
      old.animation != animation;
}
