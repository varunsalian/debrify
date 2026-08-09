import 'dart:math';

import 'package:flutter/material.dart';

import 'launch_ident.dart';

/// Origami — the mark folds itself out of a flat sheet, facet by facet, each
/// one catching the raking light differently. Then the sheet opens along a
/// crease and the name is already printed on it.
///
/// TV notes: four flat-filled triangles scaled about their hinge, two crease
/// hairlines, and a clip-band reveal for the name. No shaders, no blurs, no
/// text alpha — the facets brighten by interpolating a *fill colour*, which
/// is free, unlike interpolating a shader.
///
/// Timeline: .06–.68 four facets fold in · .40–.70 crease shadows ·
/// .50–.92 sheet opens on the name · rest.
class OrigamiIdent extends LaunchIdent {
  const OrigamiIdent();

  @override
  String get id => 'origami';
  @override
  String get label => 'Origami';
  @override
  String get subtitle =>
      'Folded from one sheet of paper — matte ivory facets, raking light';
  @override
  Duration get revealDuration => const Duration(milliseconds: 2400);
  @override
  Color get baseColor => const Color(0xFF0C0A09);
  @override
  BoxDecoration get backdrop => const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(-0.4, -0.64),
          radius: 1.2,
          colors: [Color(0xFF352B22), Color(0xFF0C0A09)],
        ),
      );
  @override
  List<Color> get sweepColors =>
      const [Color(0xFFF2ECE0), Color(0xFF8E8574)];

  @override
  CustomPainter createPainter(
    Animation<double> animation, {
    required bool Function() isTelevision,
    IdentPalette? palette,
  }) =>
      _OrigamiPainter(animation, isTelevision: isTelevision);
}

class _Facet {
  final Path path;
  final double hinge;
  final Color tone;
  const _Facet(this.path, this.hinge, this.tone);
}

class _OrigamiPainter extends CustomPainter {
  final Animation<double> animation;

  Size? _size;
  IdentWordLayout? _word;
  late double _u, _cx, _cy, _baseY, _startX, _g, _creaseY;
  late List<_Facet> _facets;
  late Path _creases;
  late List<TextPainter> _paper;

  // Paper is opaque and flat-shaded: no TV branch needed.
  _OrigamiPainter(this.animation, {required bool Function() isTelevision})
      : super(repaint: animation);

  void _layout(Size size) {
    if (_word != null && _size == size) return;
    _size = size;
    final w = size.width, h = size.height;
    _u = identUnit(size);
    _cx = w / 2;
    _cy = h / 2 - _u * 0.85;
    _baseY = h / 2 + _u * 2.5;
    _g = _u * 3.0;

    // Subdivide the play triangle at its edge midpoints.
    final p = [
      Offset(-0.30 * _g, -0.40 * _g),
      Offset(-0.30 * _g, 0.40 * _g),
      Offset(0.43 * _g, 0),
    ];
    Offset mid(Offset a, Offset b) => (a + b) / 2;
    final m01 = mid(p[0], p[1]), m12 = mid(p[1], p[2]), m20 = mid(p[2], p[0]);
    Path tri(Offset a, Offset b, Offset c) => Path()
      ..moveTo(a.dx, a.dy)
      ..lineTo(b.dx, b.dy)
      ..lineTo(c.dx, c.dy)
      ..close();
    _facets = [
      _Facet(tri(p[0], m01, m20), m20.dx, const Color(0xFFF4EFE4)),
      _Facet(tri(m01, p[1], m12), m12.dx, const Color(0xFFCFC5B2)),
      _Facet(tri(m20, m12, p[2]), m20.dx, const Color(0xFF8F8674)),
      _Facet(tri(m01, m12, m20), m01.dx, const Color(0xFFE3DAC8)),
    ];
    _creases = Path()
      ..moveTo(m01.dx, m01.dy)
      ..lineTo(m12.dx, m12.dy)
      ..moveTo(m20.dx, m20.dy)
      ..lineTo(m12.dx, m12.dy);

    _word = IdentWordLayout.fit(
      styleFor: (fz) => TextStyle(
        fontSize: fz,
        fontWeight: FontWeight.w500,
        height: 1.0,
        color: const Color(0xFFF2ECE0),
      ),
      fontSize: _u * 1.0,
      trackingFactor: 0.34,
      maxWidth: min(w * 0.78, _u * 11),
    );
    _startX = w / 2 - _word!.width / 2;
    _paper = _word!.base;
    _creaseY = _baseY - _word!.fontSize * 0.36;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final t = animation.value;
    _layout(size);
    final word = _word!;

    canvas.save();
    canvas.translate(_cx, _cy);
    for (int i = 0; i < _facets.length; i++) {
      final f = _facets[i];
      final ft = identOutCubic(identClamp((t - (0.06 + i * 0.10)) / 0.32, 0, 1));
      if (ft <= 0) continue;
      canvas.save();
      canvas.translate(f.hinge, 0);
      canvas.scale(max(0.001, ft), 1);
      canvas.translate(-f.hinge, 0);
      // Edge-on facets flash brighter, the way paper does mid-fold.
      canvas.drawPath(
        f.path,
        Paint()
          ..color =
              Color.lerp(Colors.white, f.tone, min(1.0, ft * 1.15))!,
      );
      canvas.restore();
    }
    final set = identClamp((t - 0.40) / 0.30, 0, 1);
    if (set > 0) {
      canvas.drawPath(
        _creases,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = max(1, _u * 0.02)
          ..color = Color.fromRGBO(28, 22, 16, 0.35 * set),
      );
    }
    canvas.restore();

    // The sheet opens along a crease, outward from it.
    final op = identOutCubic(identClamp((t - 0.50) / 0.42, 0, 1));
    if (op > 0) {
      final hh = word.fontSize * 0.9 * op;
      canvas.save();
      canvas.clipRect(
          Rect.fromLTWH(0, _creaseY - hh, size.width, hh * 2));
      for (int i = 0; i < kIdentWord.length; i++) {
        word.paintLetter(canvas, _paper, i, _startX, _baseY);
      }
      canvas.restore();
      final cr = 1 - identClamp((t - 0.62) / 0.30, 0, 1);
      if (cr > 0) {
        canvas.drawRect(
          Rect.fromLTWH(_startX - _u * 0.3, _creaseY - max(0.5, _u * 0.012),
              word.width + _u * 0.6, max(1, _u * 0.024)),
          Paint()..color = Color.fromRGBO(255, 250, 240, cr * 0.5),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _OrigamiPainter old) =>
      old.animation != animation;
}
