import 'dart:math';

import 'package:flutter/material.dart';

import 'launch_ident.dart';

/// Rack Focus — opens on a field of out-of-focus champagne lights with nothing
/// to read. The lens racks: every circle collapses to a point on a letter, and
/// the lockup arrives already sharp.
///
/// TV notes: defocus is faked with radius and a rim stroke rather than any
/// blur filter — 11 bokeh on TV, 22 elsewhere, two draws each. The rim is
/// dropped once a circle is near focus, so the settled frame is a handful of
/// small flat discs. Letter fades are quantized alpha sets.
///
/// Timeline: 0–.30 the bokeh field drifts in · .30–.80 the rack (circles
/// collapse onto the letters) · .44–.70 the mark snaps in with one bloom ·
/// .58–.86 the name, already sharp.
class RackFocusIdent extends LaunchIdent {
  const RackFocusIdent();

  @override
  String get id => 'rackfocus';
  @override
  String get label => 'Rack Focus';
  @override
  String get subtitle =>
      'Champagne bokeh pulls sharp and the lockup is already in focus';
  @override
  Duration get revealDuration => const Duration(milliseconds: 2600);
  @override
  Color get baseColor => const Color(0xFF06070A);
  @override
  BoxDecoration get backdrop => const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment.center,
          radius: 0.9,
          colors: [Color(0xFF1B1710), Color(0xFF06070A)],
        ),
      );
  @override
  List<Color> get sweepColors =>
      const [Color(0xFFFFD9A0), Color(0xFFF6EBDA)];

  @override
  CustomPainter createPainter(
    Animation<double> animation, {
    required bool Function() isTelevision,
  }) =>
      _RackFocusPainter(animation, isTelevision: isTelevision);
}

class _Bokeh {
  final double x0, y0, r0, x1, y1, d;
  const _Bokeh(this.x0, this.y0, this.r0, this.x1, this.y1, this.d);
}

class _RackFocusPainter extends CustomPainter {
  final Animation<double> animation;
  final bool Function() isTelevision;

  Size? _size;
  bool? _lw;
  IdentWordLayout? _word;
  late double _u, _cx, _cy, _baseY, _startX, _g;
  late List<_Bokeh> _dots;
  late Path _mark;
  late Rect _markRect;
  late Shader _markShader;
  IdentAlphaSets? _letters;

  _RackFocusPainter(this.animation, {required this.isTelevision})
      : super(repaint: animation);

  void _layout(Size size, bool lightweight) {
    if (_word != null && _size == size && _lw == lightweight) return;
    _size = size;
    _lw = lightweight;
    final w = size.width, h = size.height;
    _u = identUnit(size);
    _cx = w / 2;
    _cy = h / 2 - _u * 1.25;
    _baseY = h / 2 + _u * 2.3;
    _g = _u * 2.15;
    _mark = identPlayPath(_g);
    _markRect = Rect.fromCenter(center: Offset.zero, width: _g, height: _g);
    _markShader = const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFFFF1D8), Color(0xFFE0A85B)],
    ).createShader(_markRect);

    _word = IdentWordLayout.fit(
      styleFor: (fz) => TextStyle(
        fontSize: fz,
        fontWeight: FontWeight.w300,
        height: 1.0,
        color: const Color(0xFFF6EBDA),
      ),
      fontSize: _u * 1.30,
      trackingFactor: 0.34,
      maxWidth: min(w * 0.80, _u * 11.5),
    );
    _startX = w / 2 - _word!.width / 2;
    _letters = IdentAlphaSets(_word!, 'rack', const Color(0xFFF6EBDA));

    final n = lightweight ? 11 : 22;
    _dots = [
      for (int i = 0; i < n; i++)
        () {
          final li = i % kIdentWord.length;
          double lx = _startX;
          for (int k = 0; k < li; k++) {
            lx += _word!.widths[k] + _word!.tracking;
          }
          return _Bokeh(
            identNoise(i * 2.1 + 0.7) * w,
            identNoise(i * 6.7 + 1.9) * h,
            _u * (1.0 + identNoise(i * 3.3) * 1.7),
            lx + _word!.widths[li] / 2 + (identNoise(i * 9.1) - 0.5) * _u * 0.5,
            _baseY -
                _word!.fontSize * 0.34 +
                (identNoise(i * 4.7) - 0.5) * _u * 0.5,
            identNoise(i * 1.9) * 0.22,
          );
        }(),
    ];
  }

  @override
  void paint(Canvas canvas, Size size) {
    final t = animation.value;
    final lightweight = isTelevision();
    _layout(size, lightweight);
    final word = _word!;

    final rack = identOutCubic(identClamp((t - 0.30) / 0.50, 0, 1));
    for (final d in _dots) {
      final app = identClamp((t - d.d) / 0.26, 0, 1);
      if (app <= 0) continue;
      final k = identClamp((rack - d.d * 0.3) / 0.7, 0, 1);
      final e = identIoCubic(k);
      final x = identLerp(d.x0, d.x1, e), y = identLerp(d.y0, d.y1, e);
      final r = identLerp(d.r0, max(1, _u * 0.045), identOutCubic(k));
      final soft = 1 - k;
      canvas.drawCircle(
        Offset(x, y),
        r,
        Paint()
          ..color = Color.fromRGBO(
              255, 217, 160, app * (0.055 + 0.5 * pow(k, 3).toDouble())),
      );
      if (soft > 0.05) {
        // The rim is what actually sells defocus — no blur filter anywhere.
        canvas.drawCircle(
          Offset(x, y),
          r * 0.94,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = max(1, r * 0.10)
            ..color = Color.fromRGBO(255, 232, 196, app * 0.16 * soft),
        );
      }
    }

    // The mark snaps in at focus.
    final mk = identClamp((t - 0.44) / 0.26, 0, 1);
    if (mk > 0) {
      final e = identClamp(identOutBack(mk, 1.1), 0, 1);
      final a = identClamp(mk * 1.6, 0, 1);
      canvas.save();
      canvas.translate(_cx, _cy);
      final s = identLerp(1.10, 1, e);
      canvas.scale(s, s);
      canvas.drawPath(
        _mark,
        Paint()
          ..shader = a >= 1
              ? _markShader
              : LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color.fromRGBO(255, 241, 216, a),
                    Color.fromRGBO(224, 168, 91, a),
                  ],
                ).createShader(_markRect),
      );
      canvas.restore();

      final bl = sin(identClamp((t - 0.44) / 0.34, 0, 1) * pi);
      if (bl > 0.01) {
        if (lightweight) {
          canvas.drawCircle(Offset(_cx, _cy), _g * 1.5,
              Paint()..color = Color.fromRGBO(255, 225, 175, bl * 0.07));
        } else {
          final r = Rect.fromCircle(center: Offset(_cx, _cy), radius: _g * 2.6);
          canvas.drawRect(
            r,
            Paint()
              ..shader = RadialGradient(colors: [
                Color.fromRGBO(255, 225, 175, bl * 0.28),
                const Color(0x00FFE1AF),
              ]).createShader(r),
          );
        }
      }
    }

    // The name, arriving already sharp.
    for (int i = 0; i < kIdentWord.length; i++) {
      final lt = identClamp((t - (0.58 + i * 0.022)) / 0.24, 0, 1);
      if (lt <= 0) continue;
      final set = _letters!.at(lt);
      if (set == null) continue;
      word.paintLetter(canvas, set, i, _startX, _baseY,
          scale: identLerp(1.05, 1, identOutCubic(lt)));
    }
  }

  @override
  bool shouldRepaint(covariant _RackFocusPainter old) =>
      old.animation != animation;
}
