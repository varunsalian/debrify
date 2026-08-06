import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'launch_ident.dart';

/// Ember — the letters start as cold iron voids. Heat floods up through them,
/// the mark strikes like a die, and everything cools out to hard steel with
/// one ember still glowing at the base.
///
/// TV notes: the molten-to-steel ramp is FIVE pre-baked letter sets (the
/// [IdentAlphaSets] idiom widened to colour) picked by nearest step — never a
/// per-frame style mutation, which would force a re-layout. The die's shader
/// rides the same five steps, so nothing native is built while it cools.
/// Sparks are one batched drawRawPoints over a reused Float32List and are
/// dead before rest.
///
/// Timeline: .10–.54 the pour rises · .34–.50 the die strikes · .46–.72
/// shock ring · .58–.98 cools to steel · rest.
class EmberIdent extends LaunchIdent {
  const EmberIdent();

  @override
  String get id => 'ember';
  @override
  String get label => 'Ember';
  @override
  String get subtitle =>
      'Poured molten, struck like a die, cooled out to hard steel';
  @override
  Duration get revealDuration => const Duration(milliseconds: 2600);
  @override
  Color get baseColor => const Color(0xFF070605);
  @override
  List<Color> get sweepColors =>
      const [Color(0xFFFF7A2F), Color(0xFFE8EEF9)];

  @override
  CustomPainter createPainter(
    Animation<double> animation, {
    required bool Function() isTelevision,
  }) =>
      _EmberPainter(animation, isTelevision: isTelevision);
}

class _EmberPainter extends CustomPainter {
  final Animation<double> animation;
  final bool Function() isTelevision;

  Size? _size;
  bool? _lw;
  IdentWordLayout? _word;
  late double _u, _cx, _baseY, _startX, _g, _markY, _top;
  late int _sparkCount;
  late Float32List _sparks;
  late Path _mark;
  late Rect _markRect;
  late Shader _markCold;
  /// The die's cooling ramp, pre-baked on the same five steps as the letters.
  /// Driving this gradient straight off `cool` rebuilt a native shader for
  /// ~100 frames, the first ~37 of them identical (cool is pinned at 0 until
  /// progress .58).
  late List<Shader> _markRamp;
  late List<TextPainter> _iron;
  late List<List<TextPainter>> _ramp;

  static const int _steps = 5;
  static const Color _hotTop = Color(0xFFFFD98A);
  static const Color _hotBot = Color(0xFFFF6A18);
  static const Color _coldTop = Color(0xFFE8EEF9);
  static const Color _coldBot = Color(0xFF9DA8BC);

  _EmberPainter(this.animation, {required this.isTelevision})
      : super(repaint: animation);

  void _layout(Size size, bool lightweight) {
    if (_word != null && _size == size && _lw == lightweight) return;
    _size = size;
    _lw = lightweight;
    final w = size.width, h = size.height;
    _u = identUnit(size);
    _cx = w / 2;
    _baseY = h / 2 + _u * 1.05;
    _g = _u * 1.5;
    _markY = h / 2 - _u * 2.25;
    _mark = identPlayPath(_g);
    _markRect =
        Rect.fromCenter(center: Offset.zero, width: _g, height: _g);
    // Settled state is cached; only the cooling ramp rebuilds.
    _markCold = const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFF1F5FF), Color(0xFF7C879C)],
    ).createShader(_markRect);
    _markRamp = [
      for (int k = 0; k < _steps; k++)
        LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(const Color(0xFFFFC46A), const Color(0xFFF1F5FF),
                k / (_steps - 1))!,
            Color.lerp(const Color(0xFFD9410B), const Color(0xFF7C879C),
                k / (_steps - 1))!,
          ],
        ).createShader(_markRect),
    ];
    _sparkCount = lightweight ? 14 : 26;
    _sparks = Float32List(_sparkCount * 2);

    _word = IdentWordLayout.fit(
      styleFor: (fz) => TextStyle(
        fontSize: fz,
        fontWeight: FontWeight.w900,
        height: 1.0,
        color: const Color(0xFF191512),
      ),
      fontSize: _u * 2.0,
      trackingFactor: 0.02,
      maxWidth: min(w * 0.84, _u * 13),
      scaleX: 0.86,
    );
    _startX = w / 2 - _word!.width / 2;
    _top = _baseY - _word!.fontSize * 0.78;
    _iron = _word!.base;

    // Five colour steps from molten to steel, each a vertical gradient baked
    // into the letter set in letter-local space.
    final fz = _word!.fontSize;
    _ramp = [
      for (int k = 0; k < _steps; k++)
        _word!.set('heat$k', (s) {
          final f = k / (_steps - 1);
          return s.copyWith(
            color: null,
            foreground: Paint()
              ..shader = LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color.lerp(_hotTop, _coldTop, f)!,
                  Color.lerp(_hotBot, _coldBot, f)!,
                ],
              ).createShader(
                  Rect.fromLTRB(-40, -fz * 0.82, 40, fz * 0.10)),
          );
        }),
    ];
  }

  List<TextPainter> _rampAt(double cool) =>
      _ramp[(cool * (_steps - 1)).round().clamp(0, _steps - 1)];

  @override
  void paint(Canvas canvas, Size size) {
    final t = animation.value;
    final lightweight = isTelevision();
    _layout(size, lightweight);
    final word = _word!;

    final heat = identClamp((t - 0.10) / 0.44, 0, 1);
    final cool = identOutCubic(identClamp((t - 0.58) / 0.40, 0, 1));

    // Forge floor glow, dying as it cools.
    final fg = (0.55 * heat) * (1 - cool * 0.72);
    if (fg > 0.01) {
      if (lightweight) {
        canvas.drawCircle(Offset(_cx, _baseY + _u * 0.4), _u * 4.2,
            Paint()..color = Color.fromRGBO(255, 122, 47, fg * 0.10));
        canvas.drawCircle(Offset(_cx, _baseY + _u * 0.4), _u * 2.0,
            Paint()..color = Color.fromRGBO(255, 150, 70, fg * 0.12));
      } else {
        final r =
            Rect.fromCircle(center: Offset(_cx, _baseY + _u * 0.4), radius: _u * 7.5);
        canvas.drawRect(
          r,
          Paint()
            ..shader = RadialGradient(colors: [
              Color.fromRGBO(255, 122, 47, fg * 0.5),
              Color.fromRGBO(180, 48, 10, fg * 0.18),
              const Color(0x00070605),
            ], stops: const [
              0.0,
              0.5,
              1.0
            ]).createShader(r),
        );
      }
    }

    // Cold iron letters, always present once struck in.
    for (int i = 0; i < kIdentWord.length; i++) {
      final lt = identClamp((t - i * 0.018) / 0.18, 0, 1);
      if (lt <= 0) continue;
      final e = identOutCubic(lt);
      word.paintLetter(canvas, _iron, i, _startX, _baseY,
          scale: identLerp(1.04, 1, e));
    }

    // The pour: a rising clip band over the current heat step.
    if (heat > 0) {
      final bandY =
          identLerp(_baseY + _u * 0.1, _top - _u * 0.1, identOutCubic(heat));
      canvas.save();
      canvas.clipRect(Rect.fromLTWH(
          0, bandY, size.width, _baseY - bandY + _u * 0.5));
      final set = _rampAt(cool);
      for (int i = 0; i < kIdentWord.length; i++) {
        word.paintLetter(canvas, set, i, _startX, _baseY);
      }
      canvas.restore();
      if (heat < 1) {
        canvas.drawRect(
          Rect.fromLTWH(_startX - _u * 0.1, bandY - _u * 0.02,
              word.width + _u * 0.2, max(1, _u * 0.04)),
          Paint()..color = Color.fromRGBO(255, 214, 140, 0.5 * (1 - cool)),
        );
      }
    }

    // Sparks — progress-derived, batched, gone by .94.
    final sp = identClamp((t - 0.14) / 0.80, 0, 1);
    if (sp > 0 && sp < 1) {
      int n = 0;
      for (int i = 0; i < _sparkCount; i++) {
        final seed = identNoise(i * 3.7);
        final off = identNoise(i * 7.1) * 0.55;
        final age = identClamp((sp - off) / 0.45, 0, 1);
        if (age <= 0 || age >= 1) continue;
        _sparks[n++] = _startX + seed * word.width + sin(age * 4 + i) * _u * 0.22;
        _sparks[n++] =
            _baseY + _u * 0.2 - age * _u * 3.4 * (0.6 + identNoise(i * 11.3) * 0.8);
      }
      if (n > 0) {
        canvas.drawRawPoints(
          ui.PointMode.points,
          Float32List.sublistView(_sparks, 0, n),
          Paint()
            ..strokeWidth = max(1.5, _u * 0.05)
            ..strokeCap = StrokeCap.round
            ..color = Color.fromRGBO(255, 186, 96, (1 - sp) * (1 - cool * 0.6)),
        );
      }
    }

    // The die strikes.
    final st = identClamp((t - 0.34) / 0.16, 0, 1);
    if (st > 0) {
      final e = identOutCubic(st);
      canvas.save();
      canvas.translate(_cx, _markY - (1 - e) * _u * 2.2);
      final s = identLerp(1.25, 1, e);
      canvas.scale(s, s);
      canvas.drawPath(
        _mark,
        Paint()
          ..shader = cool >= 1
              ? _markCold
              : _markRamp[(cool * (_steps - 1)).round().clamp(0, _steps - 1)],
      );
      canvas.restore();

      final shock = identClamp((t - 0.46) / 0.26, 0, 1);
      if (shock > 0 && shock < 1) {
        canvas.drawCircle(
          Offset(_cx, _markY),
          _g * (0.7 + shock * 2.6),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = max(1, _u * 0.05 * (1 - shock))
            ..color = Color.fromRGBO(255, 180, 90, (1 - shock) * 0.5),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _EmberPainter old) =>
      old.animation != animation;
}
