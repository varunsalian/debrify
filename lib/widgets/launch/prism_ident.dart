import 'dart:math';

import 'package:flutter/material.dart';

import 'launch_ident.dart';

/// Prism — the name huge and ultralight, its glyphs filled by one spectrum
/// gradient running across the whole word (violet → cyan → rose), while a
/// hairline prism above splits an incoming white ray into a colored fan.
/// Soft aurora fields drift behind everything and ease to a stop.
///
/// TV notes: the spectrum is ONE word-spanning shader baked into the letter
/// set (letters paint in place, sharing canvas space — no per-letter
/// translate, no mask layer). Traveling color bands are clip+redraw of a
/// pre-laid-out set. Aurora fields are three bounded radial fills, and every
/// drift eases to zero by rest.
///
/// Timeline: 0–.25 prism hairline · .2–.7 letters rise · .3–.75 ray + fan ·
/// .55–.9 color bands travel · rest (everything frozen).
class PrismIdent extends LaunchIdent {
  const PrismIdent();

  @override
  String get id => 'prism';
  @override
  String get label => 'Prism';
  @override
  String get subtitle =>
      'Ultralight glass type cut from a spectrum, split by a hairline prism';
  @override
  Duration get revealDuration => const Duration(milliseconds: 2700);
  @override
  Color get baseColor => const Color(0xFF03040C);
  @override
  List<Color> get sweepColors =>
      const [Color(0xFF7B5CFF), Color(0xFF4FD8FF)];

  @override
  CustomPainter createPainter(
    Animation<double> animation, {
    required bool Function() isTelevision,
    IdentPalette? palette,
  }) =>
      _PrismPainter(animation, isTelevision: isTelevision);
}

class _PrismPainter extends CustomPainter {
  final Animation<double> animation;
  final bool Function() isTelevision;

  Size? _size;
  bool? _lw;
  IdentWordLayout? _word;
  late double _startX, _baseY, _markY, _g;
  late Path _mark;
  late List<TextPainter> _spectrum;
  late List<TextPainter> _edge;
  late List<TextPainter> _bandCyan;
  late List<TextPainter> _bandRose;
  // Aurora blob shaders, origin-centred so the canvas translates to each
  // frame's drift position — no shader is created per frame.
  late List<(Shader, double)> _blobShaders; // (shader, radius)

  _PrismPainter(this.animation, {required this.isTelevision})
      : super(repaint: animation);

  void _layout(Size size, bool lightweight) {
    if (_word != null && _size == size && _lw == lightweight) return;
    _size = size;
    _lw = lightweight;
    final w = size.width, h = size.height;
    _word = IdentWordLayout.fit(
      styleFor: (fz) => TextStyle(
        fontSize: fz,
        fontWeight: FontWeight.w100,
        height: 1.0,
        color: const Color(0xFFEAF0FF),
      ),
      fontSize: h * 0.24,
      trackingFactor: 0.20,
      maxWidth: w * 0.84,
    );
    _startX = w / 2 - _word!.width / 2;
    _baseY = h * 0.64;
    _markY = h * 0.27;
    _g = h * 0.17;
    _mark = identPlayPath(_g);
    // One spectrum across the entire word. Letters are painted IN PLACE (no
    // per-letter translate), so a canvas-space shader spanning the word gives
    // each letter its own slice of the gradient.
    final spectrumShader = LinearGradient(
      colors: const [
        Color(0xFF9E7BFF),
        Color(0xFF6FB8FF),
        Color(0xFF4FD8FF),
        Color(0xFFB48CFF),
        Color(0xFFFF8CD9),
      ],
    ).createShader(Rect.fromLTRB(_startX, 0, _startX + _word!.width, 1));
    _spectrum = _word!.set(
      'spectrum',
      (s) => s.copyWith(foreground: Paint()..shader = spectrumShader),
    );
    _edge = _word!.set(
      'edge',
      (s) => s.copyWith(
        color: null,
        foreground: Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = const Color(0xFFEAF0FF).withValues(alpha: 0.30),
      ),
    );
    _bandCyan = _word!.set(
      'bandCyan',
      (s) => s.copyWith(color: const Color(0xFF9FE9FF).withValues(alpha: .5)),
    );
    _bandRose = _word!.set(
      'bandRose',
      (s) => s.copyWith(color: const Color(0xFFFFB3E4).withValues(alpha: .4)),
    );
    final blobR = lightweight ? w * 0.34 : w * 0.46;
    Shader blob(double r, Color color) => RadialGradient(
          colors: [color, color.withValues(alpha: 0)],
        ).createShader(Rect.fromCircle(center: Offset.zero, radius: r));
    _blobShaders = [
      (blob(blobR, const Color(0xFF7B5CFF).withValues(alpha: 0.15)), blobR),
      (
        blob(blobR * 0.9, const Color(0xFF4FD8FF).withValues(alpha: 0.10)),
        blobR * 0.9
      ),
      if (!lightweight)
        (
          blob(blobR * 0.8, const Color(0xFFFF6FD8).withValues(alpha: 0.08)),
          blobR * 0.8
        ),
    ];
  }

  /// Letters paint in place so they share one canvas-space spectrum shader.
  /// [risen] draws with the entrance rise; [settledOnly] callers (the light
  /// bands) skip any letter whose entrance hasn't fully finished.
  void _paintWordInPlace(
    Canvas canvas,
    List<TextPainter> tps,
    double t, {
    required bool risen,
    bool settledOnly = false,
  }) {
    final word = _word!;
    for (int i = 0; i < kIdentWord.length; i++) {
      final lt = identClamp((t - (0.20 + i * 0.05)) / 0.40, 0, 1);
      if (settledOnly ? lt < 1 : lt <= 0) continue;
      final dy =
          risen ? (1 - identOutCubic(lt)) * word.fontSize * 0.55 : 0.0;
      tps[i].paint(
        canvas,
        Offset(_startX + word.lefts[i], _baseY - word.baselines[i] + dy),
      );
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final t = animation.value;
    final lightweight = isTelevision();
    _layout(size, lightweight);
    final word = _word!;
    final w = size.width, h = size.height;

    // Aurora fields: cached origin-centred shaders, translated to each
    // frame's drift position; the drift eases to a stop by rest.
    final drift = identOutCubic(identClamp(t / 0.9, 0, 1));
    final centers = [
      Offset(w * (0.28 + 0.10 * sin(drift * 4.2)), h * 0.82),
      Offset(w * (0.66 + 0.12 * sin(2 + drift * 3.1)), h * 0.55),
      Offset(w * (0.5 + 0.14 * sin(5 + drift * 2.4)), h * 0.9),
    ];
    for (int i = 0; i < _blobShaders.length; i++) {
      final (shader, r) = _blobShaders[i];
      canvas.save();
      canvas.translate(centers[i].dx, centers[i].dy);
      canvas.drawRect(
        Rect.fromCircle(center: Offset.zero, radius: r),
        Paint()..shader = shader,
      );
      canvas.restore();
    }

    // Letters rise through a clip — no text alpha anywhere.
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(
        0, _baseY - word.fontSize * 1.2, w, _baseY + word.fontSize * 0.12));
    _paintWordInPlace(canvas, _spectrum, t, risen: true);
    _paintWordInPlace(canvas, _edge, t, risen: true);

    // Two colored light bands travel the settled word once.
    final bp1 = identClamp((t - 0.55) / 0.32, 0, 1);
    if (bp1 > 0 && bp1 < 1) {
      final x = identLerp(
          _startX - 90, _startX + word.width + 90, identIoSine(bp1));
      canvas.save();
      canvas.clipRect(Rect.fromLTRB(
          x - 45, _baseY - word.fontSize * 1.2, x + 45, _baseY + 8));
      _paintWordInPlace(canvas, _bandCyan, t, risen: false, settledOnly: true);
      canvas.restore();
    }
    final bp2 = identClamp((t - 0.66) / 0.32, 0, 1);
    if (bp2 > 0 && bp2 < 1) {
      final x = identLerp(
          _startX + word.width + 90, _startX - 90, identIoSine(bp2));
      canvas.save();
      canvas.clipRect(Rect.fromLTRB(
          x - 45, _baseY - word.fontSize * 1.2, x + 45, _baseY + 8));
      _paintWordInPlace(canvas, _bandRose, t, risen: false, settledOnly: true);
      canvas.restore();
    }
    canvas.restore();

    // The prism: hairline mark.
    final mk = identClamp(t / 0.25, 0, 1);
    if (mk > 0) {
      canvas.save();
      canvas.translate(w / 2, _markY);
      canvas.drawPath(
        _mark,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = const Color(0xFFEAF0FF).withValues(alpha: 0.85 * mk),
      );
      canvas.restore();
    }

    // Incoming ray + refracted fan.
    final ray = identClamp((t - 0.30) / 0.45, 0, 1);
    if (ray > 0) {
      final hit = Offset(w / 2 - _g * 0.28, _markY);
      final from = Offset(-w * 0.05, _markY - h * 0.34);
      final p = identOutCubic(min(ray * 1.6, 1.0));
      canvas.drawLine(
        from,
        Offset.lerp(from, hit, p)!,
        Paint()
          ..strokeWidth = 1.4
          ..color = const Color(0xFFF0F4FF)
              .withValues(alpha: 0.75 * identClamp(ray * 2, 0, 1)),
      );
      final fan = identClamp((ray - 0.35) / 0.65, 0, 1);
      if (fan > 0) {
        final exit = Offset(w / 2 + _g * 0.40, _markY);
        const cols = [
          Color(0xFFFF6FD8),
          Color(0xFF7B5CFF),
          Color(0xFF4FD8FF),
          Color(0xFFEAF0FF),
        ];
        for (int i = 0; i < cols.length; i++) {
          final ang = (-1.5 + i) * 0.16;
          final len = w * 0.34 * identOutCubic(fan);
          canvas.drawLine(
            exit,
            exit + Offset(cos(ang) * len, sin(ang) * len),
            Paint()
              ..strokeWidth = 1.2
              ..color = cols[i].withValues(alpha: 0.65 * fan),
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PrismPainter old) => old.animation != animation;
}
