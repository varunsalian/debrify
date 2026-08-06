import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'launch_ident.dart';

/// Neon Noir — a dead sign in the rain. The mark stutters twice, catches, and
/// burns violet; the letters buzz on one by one and the whole sign hums in a
/// puddle-black reflection.
///
/// TV notes: letter flicker is BINARY (a tube is lit or it isn't — which is
/// also how real neon fails), so lit letters come from pre-laid-out stroke
/// sets and no text alpha exists. The tube glow is the two-stroke idiom on TV
/// and a baked blur-stroke set elsewhere. Rain is one batched line draw that
/// freezes when it fades. The mark is a Path, so its continuous flicker alpha
/// is free. All noise is progress-derived — the buzz freezes at rest.
///
/// Timeline: .12/.24 failed strikes · .42 mark catches · .52–.87 letters
/// buzz on · rain fades by .85 · rest (steady sign + reflection).
class NeonIdent extends LaunchIdent {
  const NeonIdent();

  @override
  String get id => 'neon';
  @override
  String get label => 'Neon Noir';
  @override
  String get subtitle =>
      'A dead sign in the rain stutters, catches, and burns violet';
  @override
  Duration get revealDuration => const Duration(milliseconds: 2800);
  @override
  Color get baseColor => const Color(0xFF060310);
  @override
  BoxDecoration get backdrop => const BoxDecoration(
        // Night black with a violet haze top-right, pre-blended opaque.
        gradient: RadialGradient(
          center: Alignment(0.4, -0.7),
          radius: 1.0,
          colors: [Color(0xFF10081F), Color(0xFF060310)],
        ),
      );
  @override
  List<Color> get sweepColors =>
      const [Color(0xFFD06CFF), Color(0xFFB18CFF)];

  @override
  CustomPainter createPainter(
    Animation<double> animation, {
    required bool Function() isTelevision,
  }) =>
      _NeonPainter(animation, isTelevision: isTelevision);
}

class _NeonPainter extends CustomPainter {
  final Animation<double> animation;
  final bool Function() isTelevision;

  Size? _size;
  bool? _lw;
  IdentWordLayout? _word;
  late double _glyphX, _wordX, _baseY, _signY, _floorY, _g;
  late Path _mark;
  late Shader _floorShader;
  late Float32List _rainBuf;
  int _rainCount = 0;
  late List<TextPainter> _glowSet; // wide translucent stroke (or baked blur)
  late List<TextPainter> _coreSet; // thin white core
  late List<TextPainter> _deadSet; // unlit tube ghost
  late List<TextPainter> _reflGlow; // reflection, alpha baked
  late List<TextPainter> _reflCore;

  _NeonPainter(this.animation, {required this.isTelevision})
      : super(repaint: animation);

  static const _violet = Color(0xFFB18CFF);
  static const _markViolet = Color(0xFFD06CFF);

  void _layout(Size size, bool lightweight) {
    if (_word != null && _size == size && _lw == lightweight) return;
    _size = size;
    _lw = lightweight;
    final w = size.width, h = size.height;
    _word = IdentWordLayout.fit(
      styleFor: (fz) => TextStyle(
        fontSize: fz,
        fontWeight: FontWeight.w700,
        fontFamily: 'sans-serif-condensed',
        fontFamilyFallback: const ['Avenir Next Condensed', 'Arial Narrow'],
        height: 1.0,
        color: _violet,
      ),
      fontSize: h * 0.17,
      trackingFactor: 0.16,
      maxWidth: w * 0.52,
    );
    _g = h * 0.15;
    final lock = _g + _g * 0.35 + _word!.width;
    final startX = w / 2 - lock / 2;
    _glyphX = startX + _g / 2;
    _wordX = startX + _g + _g * 0.35;
    _signY = h * 0.40;
    _baseY = h * 0.44;
    _floorY = h * 0.62;
    _mark = identPlayPath(_g);
    _floorShader = const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFF0A0616), Color(0xFF03020A)],
    ).createShader(Rect.fromLTRB(0, _floorY, w, h));

    Paint strokePaint(double width, Color color, {double blur = 0}) {
      final p = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeJoin = StrokeJoin.round
        ..color = color;
      if (blur > 0) {
        p.maskFilter = MaskFilter.blur(BlurStyle.normal, blur);
      }
      return p;
    }

    // Tube glow: baked blur-stroke off TV, wide translucent stroke on TV.
    _glowSet = _word!.set(
      'glow',
      (s) => s.copyWith(
        color: null,
        foreground: lightweight
            ? strokePaint(5.5, _violet.withValues(alpha: 0.45))
            : strokePaint(3.4, _violet.withValues(alpha: 0.95), blur: 7),
      ),
    );
    _coreSet = _word!.set(
      'core',
      (s) => s.copyWith(
        color: null,
        foreground: strokePaint(1.2, const Color(0xFFFFFFFF)),
      ),
    );
    _deadSet = _word!.set(
      'dead',
      (s) => s.copyWith(
        color: null,
        foreground:
            strokePaint(2.4, const Color(0xFF5A4A78).withValues(alpha: 0.10)),
      ),
    );
    _reflGlow = _word!.set(
      'reflGlow',
      (s) => s.copyWith(
        color: null,
        foreground: strokePaint(3.4, _violet.withValues(alpha: 0.14)),
      ),
    );
    _reflCore = _word!.set(
      'reflCore',
      (s) => s.copyWith(
        color: null,
        foreground:
            strokePaint(1.2, const Color(0xFFFFFFFF).withValues(alpha: 0.12)),
      ),
    );

    _rainCount = lightweight ? 20 : 38;
    _rainBuf = Float32List(_rainCount * 4);
  }

  /// Binary flicker: is letter [i]'s tube lit at progress [t]?
  bool _letterOn(double t, int i) {
    final s0 = 0.52 + i * 0.05;
    if (t > s0 + 0.04) return true;
    if (t > s0) return identNoise(i * 13 + (t * 70).floorToDouble()) > 0.4;
    return false;
  }

  /// The mark's continuous flicker envelope (it's a Path — alpha is free).
  double _markOn(double t) {
    if (t > 0.42) return 0.93 + 0.07 * identNoise((t * 90).floorToDouble());
    if (t > 0.12 && t < 0.155) return 0.6;
    if (t > 0.24 && t < 0.31) {
      return 0.4 + 0.5 * (sin(t * 90).abs());
    }
    return 0;
  }

  void _drawMarkTube(Canvas canvas, double alpha, bool lightweight) {
    canvas.save();
    canvas.translate(_glyphX, _signY);
    if (lightweight) {
      canvas.drawPath(
        _mark,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 9
          ..strokeJoin = StrokeJoin.round
          ..color = _markViolet.withValues(alpha: 0.30 * alpha),
      );
    } else {
      canvas.drawPath(
        _mark,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4.2
          ..strokeJoin = StrokeJoin.round
          ..color = _markViolet.withValues(alpha: 0.95 * alpha)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9),
      );
    }
    canvas.drawPath(
      _mark,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.2
        ..strokeJoin = StrokeJoin.round
        ..color = _markViolet.withValues(alpha: 0.9 * alpha),
    );
    canvas.drawPath(
      _mark,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = Colors.white.withValues(alpha: alpha),
    );
    canvas.restore();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final t = animation.value;
    final lightweight = isTelevision();
    _layout(size, lightweight);
    final word = _word!;
    final w = size.width, h = size.height;

    // Rain: batched lines; motion stops as it fades out.
    final rainT = min(t, 0.85);
    final rainAlpha = 0.10 * (1 - identClamp((t - 0.7) / 0.15, 0, 1));
    if (rainAlpha > 0.005) {
      int ri = 0;
      for (int i = 0; i < _rainCount; i++) {
        final sSpeed = 0.5 + identNoise(i * 3.7);
        final yF = identNoise(i * 5.3) + rainT * 1.4 * sSpeed;
        final y = (yF - yF.floorToDouble()) * h;
        final x = identNoise(i * 8.9) * w - y * 0.08;
        _rainBuf[ri++] = x;
        _rainBuf[ri++] = y;
        _rainBuf[ri++] = x - 3;
        _rainBuf[ri++] = y + 14 * sSpeed;
      }
      canvas.drawRawPoints(
        ui.PointMode.lines,
        _rainBuf,
        Paint()
          ..strokeWidth = 1
          ..color = Color.fromRGBO(160, 170, 220, rainAlpha),
      );
    }

    // The sign.
    final markAlpha = _markOn(t);
    if (markAlpha > 0) {
      _drawMarkTube(canvas, markAlpha, lightweight);
    } else {
      canvas.save();
      canvas.translate(_glyphX, _signY);
      canvas.drawPath(
        _mark,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = const Color(0xFF5A4A78).withValues(alpha: 0.10),
      );
      canvas.restore();
    }
    for (int i = 0; i < kIdentWord.length; i++) {
      if (_letterOn(t, i)) {
        word.paintLetter(canvas, _glowSet, i, _wordX, _baseY);
        if (lightweight) {
          // Second TV glow pass: mid stroke, brighter.
          word.paintLetter(canvas, _glowSet, i, _wordX, _baseY);
        }
        word.paintLetter(canvas, _coreSet, i, _wordX, _baseY);
      } else {
        word.paintLetter(canvas, _deadSet, i, _wordX, _baseY);
      }
    }

    // Wet floor — cached shader.
    canvas.drawRect(
      Rect.fromLTRB(0, _floorY, w, h),
      Paint()..shader = _floorShader,
    );
    // Reflection: flipped redraw from alpha-baked sets.
    canvas.save();
    canvas.translate(0, _floorY * 2 + 8);
    canvas.scale(1, -0.55);
    if (markAlpha > 0.4) _drawMarkTube(canvas, 0.16, true);
    for (int i = 0; i < kIdentWord.length; i++) {
      if (!_letterOn(t, i)) continue;
      word.paintLetter(canvas, _reflGlow, i, _wordX, _baseY);
      word.paintLetter(canvas, _reflCore, i, _wordX, _baseY);
    }
    canvas.restore();
    // Shimmer lines on the water — wobble is progress-derived, so it freezes.
    final shimmer = Paint()
      ..strokeWidth = 1
      ..color = _violet.withValues(alpha: 0.06);
    for (int i = 0; i < 5; i++) {
      final y = _floorY + 10 + i * 14 + sin(min(t, 1.0) * 6 + i) * 1.5;
      canvas.drawLine(Offset(w * 0.2, y), Offset(w * 0.8, y), shimmer);
    }
  }

  @override
  bool shouldRepaint(covariant _NeonPainter old) => old.animation != animation;
}
