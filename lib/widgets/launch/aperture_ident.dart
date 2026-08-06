import 'dart:math';

import 'package:flutter/material.dart';

import 'launch_ident.dart';

/// Aperture — six machined blades unwind off the centre like a lens iris.
/// What they uncover is the mark under one cold key light, and the name
/// resolves out of the opening centre-outward.
///
/// TV notes: the iris is six rotated half-planes (a plain rect each, drawn in
/// blade-local space so ONE cached gradient serves all six), painted last so
/// they occlude. The key bloom is a bounded radial that dies before rest; the
/// name is a clip-band reveal, not a fade. Zero saveLayer.
///
/// Timeline: .05–.67 iris opens (blades spin out) · .26–.60 mark + ring ·
/// .50–.92 name uncovered centre-outward · rest.
class ApertureIdent extends LaunchIdent {
  const ApertureIdent();

  @override
  String get id => 'aperture';
  @override
  String get label => 'Aperture';
  @override
  String get subtitle =>
      'A six-blade lens iris unwinds off the mark under one cold key';
  @override
  Duration get revealDuration => const Duration(milliseconds: 2200);
  @override
  Color get baseColor => const Color(0xFF05070B);
  @override
  BoxDecoration get backdrop => const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0, -0.16),
          radius: 0.78,
          colors: [Color(0xFF141B28), Color(0xFF05070B)],
        ),
      );
  @override
  List<Color> get sweepColors =>
      const [Color(0xFFCFE0FF), Color(0xFF8FA6C8)];

  @override
  CustomPainter createPainter(
    Animation<double> animation, {
    required bool Function() isTelevision,
  }) =>
      _AperturePainter(animation, isTelevision: isTelevision);
}

class _AperturePainter extends CustomPainter {
  final Animation<double> animation;
  final bool Function() isTelevision;

  Size? _size;
  IdentWordLayout? _word;
  late double _u, _cx, _cy, _baseY, _startX, _g, _r;
  late Path _mark, _bevel;
  late Rect _markRect, _bladeRect;
  late Shader _markShader, _bladeShader;
  late List<TextPainter> _letters;

  _AperturePainter(this.animation, {required this.isTelevision})
      : super(repaint: animation);

  void _layout(Size size) {
    if (_word != null && _size == size) return;
    _size = size;
    final w = size.width, h = size.height;
    _u = identUnit(size);
    _cx = w / 2;
    _cy = h / 2 - _u * 0.75;
    _baseY = h / 2 + _u * 2.80;
    _g = _u * 2.9;
    _r = sqrt(w * w + h * h);
    _mark = identPlayPath(_g);
    _bevel = identPlayPath(_g * 0.55);
    _markRect = Rect.fromCenter(
        center: Offset.zero, width: _g * 0.86, height: _g * 0.86);
    _markShader = const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFFFFFFF), Color(0xFFDCE5F5), Color(0xFF8C99B4)],
      stops: [0.0, 0.42, 1.0],
    ).createShader(_markRect);

    // Blade-local: after translate(0, d) every blade is the same rect, so one
    // shader serves all six and nothing is rebuilt per frame.
    _bladeRect = Rect.fromLTWH(-_r, 0, _r * 2, _r);
    _bladeShader = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: const [Color(0xFF171D2A), Color(0xFF0C111B), Color(0xFF05070B)],
      stops: const [0.0, 0.35, 1.0],
    ).createShader(Rect.fromLTWH(-_r, 0, _r * 2, _r * 0.55));

    _word = IdentWordLayout.fit(
      styleFor: (fz) => TextStyle(
        fontSize: fz,
        fontWeight: FontWeight.w600,
        height: 1.0,
        color: const Color(0xFFC3CFE6),
      ),
      fontSize: _u * 1.05,
      trackingFactor: 0.40,
      maxWidth: min(w * 0.80, _u * 12.4),
    );
    _startX = w / 2 - _word!.width / 2;
    _letters = _word!.base;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final t = animation.value;
    final lightweight = isTelevision();
    _layout(size);
    final word = _word!;

    final open = identOutQuint(identClamp((t - 0.05) / 0.62, 0, 1));
    final d = identLerp(_u * 0.08, _r * 0.62, open);

    // Key light blooming through the opening — bounded, gone before rest.
    final bloomT = identClamp((t - 0.05) / 0.55, 0, 1);
    final bloom = sin(bloomT * pi) * 0.55;
    if (bloom > 0.004) {
      final rad = max(d * 1.8, _u * 2);
      if (lightweight) {
        // A per-frame RadialGradient is the one real allocation here; on TV a
        // pair of flat discs reads the same at reveal speed for nothing.
        canvas.drawCircle(Offset(_cx, _cy), rad * 0.55,
            Paint()..color = Color.fromRGBO(214, 231, 255, bloom * 0.12));
        canvas.drawCircle(Offset(_cx, _cy), rad * 0.28,
            Paint()..color = Color.fromRGBO(226, 239, 255, bloom * 0.16));
      } else {
        final rect = Rect.fromCircle(center: Offset(_cx, _cy), radius: rad);
        canvas.drawRect(
          rect,
          Paint()
            ..shader = RadialGradient(colors: [
              Color.fromRGBO(214, 231, 255, bloom * 0.55),
              const Color(0x00D6E7FF),
            ]).createShader(rect),
        );
      }
    }

    // The mark, uncovered under the blades.
    final mk = identOutCubic(identClamp((t - 0.26) / 0.34, 0, 1));
    if (mk > 0) {
      canvas.save();
      canvas.translate(_cx, _cy);
      final s = identLerp(0.86, 1, mk);
      canvas.scale(s, s);
      canvas.drawPath(
        _mark,
        Paint()
          ..shader = mk >= 1
              ? _markShader
              : LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color.fromRGBO(255, 255, 255, mk),
                    Color.fromRGBO(220, 229, 245, mk),
                    Color.fromRGBO(140, 153, 180, mk),
                  ],
                  stops: const [0.0, 0.42, 1.0],
                ).createShader(_markRect),
      );
      canvas.drawPath(
        _bevel,
        Paint()..color = Color.fromRGBO(6, 9, 15, 0.24 * mk),
      );
      canvas.restore();
    }

    // Hairline ring drawing closed around it.
    final ring = identOutCubic(identClamp((t - 0.34) / 0.40, 0, 1));
    if (ring > 0 && mk > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: Offset(_cx, _cy), radius: _g * 0.86),
        -pi / 2,
        pi * 2 * ring,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = max(1, _u * 0.035)
          ..color = Color.fromRGBO(196, 214, 246, 0.42 * mk),
      );
    }

    // The name, uncovered centre-outward (clip band, never an alpha fade).
    final wr = identOutCubic(identClamp((t - 0.50) / 0.42, 0, 1));
    if (wr > 0) {
      canvas.save();
      final half = (word.width / 2 + _u * 0.4) * wr;
      canvas.clipRect(Rect.fromLTWH(
          _cx - half, _baseY - _u * 2, half * 2, _u * 3));
      for (int i = 0; i < kIdentWord.length; i++) {
        word.paintLetter(canvas, _letters, i, _startX, _baseY);
      }
      canvas.restore();
    }

    // Blades last — they occlude everything above.
    if (open < 1) {
      final edge = Paint()
        ..color = Color.fromRGBO(178, 199, 235, 0.55 * (1 - open * 0.9));
      final fill = Paint()..shader = _bladeShader;
      final edgeH = max(1.0, _u * 0.02);
      for (int i = 0; i < 6; i++) {
        canvas.save();
        canvas.translate(_cx, _cy);
        canvas.rotate(identLerp(-0.30, 0, open) + i * pi / 3);
        canvas.translate(0, d);
        canvas.drawRect(_bladeRect, fill);
        canvas.drawRect(Rect.fromLTWH(-_r, 0, _r * 2, edgeH), edge);
        canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(covariant _AperturePainter old) =>
      old.animation != animation;
}
