import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'launch_ident.dart';

/// Constellation — not a starfield, a star *chart*. Nodes are plotted, ringed
/// and captioned, then the lines between them close into the mark. It reads
/// like an antique observatory plate rather than a screensaver.
///
/// TV notes: the field is one batched drawRawPoints over a reused
/// Float32List — 32 points on TV, 64 elsewhere — and the twinkle amplitude
/// damps to zero, so the settled frame is motionless. Node positions come
/// from PathMetrics on the mark outline, sampled once at layout, and the
/// closing figure indexes a pre-built chain of prefix paths rather than
/// assembling one per tick.
///
/// Timeline: 0–.30 field fades up · .18–.48 nodes plot · .34–.72 lines close
/// the figure · .62–.90 the figure fills and the plate is captioned.
class ConstellationIdent extends LaunchIdent {
  const ConstellationIdent();

  @override
  String get id => 'constellation';
  @override
  String get label => 'Constellation';
  @override
  String get subtitle =>
      'An observatory plate — plotted nodes and hairlines closing into the mark';
  @override
  Duration get revealDuration => const Duration(milliseconds: 2800);
  @override
  Color get baseColor => const Color(0xFF050A16);
  @override
  BoxDecoration get backdrop => const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0, -0.2),
          radius: 0.85,
          colors: [Color(0xFF121A2E), Color(0xFF050A16)],
        ),
      );
  @override
  List<Color> get sweepColors =>
      const [Color(0xFFEFE7D6), Color(0xFF8A93B8)];

  @override
  CustomPainter createPainter(
    Animation<double> animation, {
    required bool Function() isTelevision,
    IdentPalette? palette,
  }) =>
      _ConstellationPainter(animation, isTelevision: isTelevision);
}

class _ConstellationPainter extends CustomPainter {
  final Animation<double> animation;
  final bool Function() isTelevision;

  Size? _size;
  bool? _lw;
  IdentWordLayout? _word;
  late double _u, _cx, _cy, _baseY, _startX, _g;
  late int _count;
  late Float32List _field;
  late List<Offset> _nodes;
  late Path _mark, _arcs;
  /// One path per whole-segment count, built at layout. The fractional tail
  /// rides on top as a single drawLine, so the closing figure never builds a
  /// native Path on the hot path.
  late List<Path> _chain;
  IdentAlphaSets? _letters;
  late TextPainter _plate, _coord;

  _ConstellationPainter(this.animation, {required this.isTelevision})
      : super(repaint: animation);

  void _layout(Size size, bool lightweight) {
    if (_word != null && _size == size && _lw == lightweight) return;
    _size = size;
    _lw = lightweight;
    final w = size.width, h = size.height;
    _u = identUnit(size);
    _cx = w / 2;
    _cy = h / 2 - _u * 0.9;
    _baseY = h / 2 + _u * 2.7;
    _g = _u * 2.6;
    _mark = identPlayPath(_g);

    _count = lightweight ? 32 : 64;
    _field = Float32List(_count * 2);
    for (int i = 0; i < _count; i++) {
      _field[i * 2] = identNoise(i * 1.7 + 0.3) * w;
      _field[i * 2 + 1] = identNoise(i * 4.3 + 1.1) * h;
    }

    // Nodes: sample the outline itself, so the figure really is the mark.
    _nodes = [];
    for (final m in _mark.computeMetrics()) {
      const n = 7;
      for (int i = 0; i < n; i++) {
        final p = m.getTangentForOffset(m.length * i / n)?.position;
        if (p != null) _nodes.add(p);
      }
    }
    if (_nodes.isEmpty) _nodes = [Offset.zero];

    _arcs = Path();
    for (final r in [_g * 1.5, _g * 2.2, _g * 3.0]) {
      _arcs.addOval(Rect.fromCircle(center: Offset(_cx, _cy), radius: r));
    }

    _chain = [Path()..moveTo(_nodes[0].dx, _nodes[0].dy)];
    for (int i = 1; i <= _nodes.length; i++) {
      final p = _nodes[i % _nodes.length];
      _chain.add(Path.from(_chain.last)..lineTo(p.dx, p.dy));
    }

    _word = IdentWordLayout.fit(
      styleFor: (fz) => TextStyle(
        fontSize: fz,
        fontFamily: 'serif',
        fontFamilyFallback: const ['Iowan Old Style', 'Georgia'],
        fontWeight: FontWeight.w400,
        height: 1.0,
        color: const Color(0xFFEFE7D6),
      ),
      fontSize: _u * 0.92,
      trackingFactor: 0.46,
      maxWidth: min(w * 0.76, _u * 10.5),
    );
    _startX = w / 2 - _word!.width / 2;
    _letters = IdentAlphaSets(_word!, 'plate', const Color(0xFFEFE7D6));

    TextPainter lbl(String s) => TextPainter(
          text: TextSpan(
            text: s,
            style: TextStyle(
              fontSize: _u * 0.28,
              fontWeight: FontWeight.w600,
              height: 1.0,
              letterSpacing: _u * 0.28 * 0.22,
              color: const Color(0x80EFE7D6),
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
    _plate = lbl('PLATE VII');
    _coord = lbl('18h42m +38°');
  }

  @override
  void paint(Canvas canvas, Size size) {
    final t = animation.value;
    final lightweight = isTelevision();
    _layout(size, lightweight);
    final word = _word!;

    canvas.drawPath(
      _arcs,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0x12BECDF5),
    );

    // The field. Twinkle damps to zero, so rest is a still plate.
    final sf = identClamp(t / 0.30, 0, 1);
    final tw = 1 - identOutCubic(identClamp((t - 0.20) / 0.62, 0, 1));
    if (sf > 0) {
      canvas.drawRawPoints(
        ui.PointMode.points,
        _field,
        Paint()
          ..strokeWidth = max(1, _u * 0.045)
          ..strokeCap = StrokeCap.round
          ..color = Color.fromRGBO(
              226, 232, 248, identClamp(sf * (0.55 + 0.30 * tw), 0, 1)),
      );
    }

    canvas.save();
    canvas.translate(_cx, _cy);

    // Plotted nodes.
    final np = identClamp((t - 0.18) / 0.30, 0, 1);
    for (int i = 0; i < _nodes.length; i++) {
      final a = identClamp((np - i / _nodes.length * 0.6) / 0.4, 0, 1);
      if (a <= 0) continue;
      final p = _nodes[i];
      canvas.drawCircle(p, max(1, _u * 0.055),
          Paint()..color = Color.fromRGBO(239, 231, 214, a));
      canvas.drawCircle(
        p,
        _u * 0.20,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = Color.fromRGBO(239, 231, 214, a * 0.35),
      );
    }

    // The lines close the figure.
    final lp = identOutCubic(identClamp((t - 0.34) / 0.38, 0, 1));
    if (lp > 0) {
      final n = _nodes.length;
      final upto = lp * n;
      final whole = upto.floor().clamp(0, n);
      final hair = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = max(1, _u * 0.018)
        ..strokeJoin = StrokeJoin.round
        ..color = const Color(0x9EEFE7D6);
      canvas.drawPath(_chain[whole], hair);
      final f = upto - whole;
      if (f > 0) {
        final a = _nodes[whole % n], b = _nodes[(whole + 1) % n];
        canvas.drawLine(
          a,
          Offset(identLerp(a.dx, b.dx, f), identLerp(a.dy, b.dy, f)),
          hair,
        );
      }
    }

    // The figure fills, faintly.
    final fl = identClamp((t - 0.62) / 0.28, 0, 1);
    if (fl > 0) {
      canvas.drawPath(
        _mark,
        Paint()..color = Color.fromRGBO(214, 224, 255, fl * 0.10),
      );
    }
    canvas.restore();

    // Plate caption.
    final wp = identClamp((t - 0.60) / 0.34, 0, 1);
    for (int i = 0; i < kIdentWord.length; i++) {
      final lt = identClamp((wp - i * 0.05) / 0.5, 0, 1);
      if (lt <= 0) continue;
      final set = _letters!.at(lt);
      if (set == null) continue;
      word.paintLetter(canvas, set, i, _startX, _baseY);
    }
    if (wp > 0.4) {
      final y = _baseY - word.fontSize * 1.25;
      canvas.drawRect(
        Rect.fromLTWH(_startX, y, word.width, 1),
        Paint()..color = const Color(0x47EFE7D6),
      );
      _plate.paint(canvas, Offset(_startX, _baseY + _u * 0.52));
      _coord.paint(
        canvas,
        Offset(_startX + word.width - _coord.width, _baseY + _u * 0.52),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ConstellationPainter old) =>
      old.animation != animation;
}
