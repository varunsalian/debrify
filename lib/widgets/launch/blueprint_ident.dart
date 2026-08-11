import 'dart:math';

import 'package:flutter/material.dart';

import '../../utils/platform_util.dart';
import 'launch_ident.dart';

/// Blueprint — the mark drafts itself. Construction geometry goes down first,
/// the outline strokes itself along the guides, then it inks solid and the
/// guides evaporate, leaving a dimensioned drawing.
///
/// TV notes: the graph paper is fully static, so it lives in the [backdrop]
/// and rasters once instead of being stroked on every tick. The outline
/// reveal draws pre-extracted partial paths (no per-frame PathMetrics), the
/// ink is a clip-rect wipe over a cached shader, and the name is a typewriter
/// hard cut — no alpha fades on type at all. Guides fade as a single grouped
/// alpha on flat strokes, which is safe (no shader, no text).
///
/// Timeline: 0–.26 construction circle · .22–.56 outline strokes ·
/// .50–.78 inks solid · .58–.88 name types · .80–1 dimension rule.
class BlueprintIdent extends LaunchIdent {
  const BlueprintIdent();

  @override
  String get id => 'blueprint';
  @override
  String get label => 'Blueprint';
  @override
  String get subtitle =>
      'Drafted in cyan hairlines on graph paper, then inked solid';
  @override
  Duration get revealDuration => const Duration(milliseconds: 2500);
  @override
  Color get baseColor => const Color(0xFF080B11);
  // Density is resolved at build time, not baked in: AppInitializer re-probes
  // for TV after first paint and setStates, so the backdrop has to be able to
  // change with the flag (see _GraphPaperDecoration's ==).
  @override
  Decoration get backdrop =>
      _GraphPaperDecoration(PlatformUtil.isAndroidTvCached);

  /// The graph paper IS this ident — a flat fill would leave nothing of it.
  /// So the geometry (line spacing, the major/minor split, the registration to
  /// the mark's crossing) is kept and only the two colours move.
  @override
  Decoration themedBackdrop(IdentPalette p) => _GraphPaperDecoration(
        PlatformUtil.isAndroidTvCached,
        base: p.base,
        line: p.accent,
      );
  @override
  List<Color> get sweepColors =>
      const [Color(0xFF5EE1FF), Color(0xFFDFF6FF)];

  @override
  CustomPainter createPainter(
    Animation<double> animation, {
    required bool Function() isTelevision,
    IdentPalette? palette,
  }) =>
      _BlueprintPainter(animation, isTelevision: isTelevision);
}

/// The graph paper. Nothing about it depends on progress, so it belongs on
/// the far side of the painter's RepaintBoundary — rastered once by the
/// DecoratedBox rather than re-stroked at 60fps behind the drafting.
class _GraphPaperDecoration extends Decoration {
  final bool lightweight;

  /// The paper and its rule. Default to Blueprint's own; a themed palette
  /// substitutes them without touching the geometry.
  final Color base;
  final Color line;

  const _GraphPaperDecoration(
    this.lightweight, {
    this.base = const Color(0xFF080B11),
    this.line = const Color(0xFF5EE1FF),
  });

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) =>
      _GraphPaperBoxPainter(lightweight, base, line);

  // Equality is what lets a late TV probe swap the grid density: DecoratedBox
  // keeps its BoxPainter until the decoration compares unequal. The colours
  // join it for the same reason — a theme change must rebuild the painter.
  @override
  bool operator ==(Object other) =>
      other is _GraphPaperDecoration &&
      other.lightweight == lightweight &&
      other.base == base &&
      other.line == line;

  @override
  int get hashCode => Object.hash(lightweight, base, line);
}

class _GraphPaperBoxPainter extends BoxPainter {
  final bool lightweight;
  final Color base;
  final Color line;
  Size? _size;
  Path? _grid, _major;

  _GraphPaperBoxPainter(this.lightweight, this.base, this.line);

  void _build(Size size) {
    if (_grid != null && _size == size) return;
    _size = size;
    final w = size.width, h = size.height;
    final u = identUnit(size);
    // Registered to the same centre the painter drafts around, so the mark
    // lands on a crossing rather than between two lines.
    final cx = w / 2, cy = h / 2 - u * 1.20;
    // Coarser on TV — half the line count, same read at a distance.
    final step = u * (lightweight ? 0.92 : 0.62);
    final grid = Path();
    for (double x = cx % step; x < w; x += step) {
      grid
        ..moveTo(x, 0)
        ..lineTo(x, h);
    }
    for (double y = cy % step; y < h; y += step) {
      grid
        ..moveTo(0, y)
        ..lineTo(w, y);
    }
    final major = Path();
    for (double x = cx % (step * 5); x < w; x += step * 5) {
      major
        ..moveTo(x, 0)
        ..lineTo(x, h);
    }
    _grid = grid;
    _major = major;
  }

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    final size = configuration.size;
    if (size == null || size.isEmpty) return;
    _build(size);
    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    // Opaque base first — this decoration IS the splash's floor.
    canvas.drawRect(Offset.zero & size, Paint()..color = base);
    final hair = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    // The mock's two rule weights, as alphas OF the line colour — composed
    // `0xNN / 0xFF` so Blueprint's own #0E/#21 are reproduced exactly.
    canvas.drawPath(
        _grid!, hair..color = line.withValues(alpha: 0x0E / 0xFF));
    canvas.drawPath(
        _major!, hair..color = line.withValues(alpha: 0x21 / 0xFF));
    canvas.restore();
  }
}

class _BlueprintPainter extends CustomPainter {
  final Animation<double> animation;
  final bool Function() isTelevision;

  Size? _size;
  bool? _lw;
  IdentWordLayout? _word;
  late double _u, _cx, _cy, _baseY, _startX, _g, _cr;
  late Path _mark, _ticks, _dim;
  /// Pre-extracted prefixes of the outline, indexed 0.._kDraw. Walking
  /// PathMetrics per frame would mint a fresh native Path on every tick.
  late List<Path> _draw;
  static const int _kDraw = 32;
  late Rect _inkRect;
  late Shader _inkShader;
  late List<TextPainter> _ink;
  late TextPainter _caption;

  _BlueprintPainter(this.animation, {required this.isTelevision})
      : super(repaint: animation);

  void _layout(Size size, bool lightweight) {
    if (_word != null && _size == size && _lw == lightweight) return;
    _size = size;
    _lw = lightweight;
    final w = size.width, h = size.height;
    _u = identUnit(size);
    _cx = w / 2;
    _cy = h / 2 - _u * 1.20;
    _baseY = h / 2 + _u * 1.95;
    _g = _u * 2.8;
    _cr = _u * 2.02;

    _mark = identPlayPath(_g);
    // Quantized draw-on states, extracted once. At reveal speed the steps are
    // finer than the eye tracks on a stroking hairline.
    _draw = [Path()];
    for (int k = 1; k <= _kDraw; k++) {
      final f = k / _kDraw;
      final p = Path();
      // Re-measured per step on purpose: a PathMetrics iterator is single-use.
      for (final m in _mark.computeMetrics()) {
        p.addPath(m.extractPath(0, m.length * f), Offset.zero);
      }
      _draw.add(p);
    }
    _inkRect = Rect.fromCenter(
        center: Offset.zero, width: _g, height: _g);
    _inkShader = const LinearGradient(
      begin: Alignment.bottomCenter,
      end: Alignment.topCenter,
      colors: [Color(0xFF2FA9D6), Color(0xFFC9F6FF)],
    ).createShader(_inkRect);

    _ticks = Path();
    for (int i = 0; i < 12; i++) {
      final a = i * pi / 6, c = cos(a), s = sin(a);
      _ticks
        ..moveTo(_cx + c * _cr, _cy + s * _cr)
        ..lineTo(_cx + c * (_cr + _u * 0.14), _cy + s * (_cr + _u * 0.14));
    }

    _word = IdentWordLayout.fit(
      styleFor: (fz) => TextStyle(
        fontSize: fz,
        fontFamily: 'monospace',
        fontFamilyFallback: const ['Roboto Mono', 'Courier New'],
        fontWeight: FontWeight.w600,
        height: 1.0,
        color: const Color(0xFFDFF6FF),
      ),
      fontSize: _u * 0.92,
      trackingFactor: 0.30,
      maxWidth: min(w * 0.80, _u * 11),
    );
    _startX = w / 2 - _word!.width / 2;
    _ink = _word!.base;

    final dy = _baseY + _u * 0.62, x0 = _startX, x1 = _startX + _word!.width;
    _dim = Path()
      ..moveTo(x0, dy)
      ..lineTo(x1, dy)
      ..moveTo(x0, dy - _u * 0.13)
      ..lineTo(x0, dy + _u * 0.13)
      ..moveTo(x1, dy - _u * 0.13)
      ..lineTo(x1, dy + _u * 0.13);

    _caption = TextPainter(
      text: TextSpan(
        text: 'PLAY · ANYTHING',
        style: TextStyle(
          fontSize: _u * 0.30,
          fontFamily: 'monospace',
          fontFamilyFallback: const ['Roboto Mono', 'Courier New'],
          fontWeight: FontWeight.w600,
          height: 1.0,
          letterSpacing: _u * 0.30 * 0.24,
          color: const Color(0xBF5EE1FF),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final t = animation.value;
    final lightweight = isTelevision();
    _layout(size, lightweight);
    final word = _word!;

    // The graph paper is in the backdrop — nothing static is drawn here.

    // Construction geometry, fading out once the mark is inked.
    final guides = 1 - identOutCubic(identClamp((t - 0.62) / 0.30, 0, 1));
    if (guides > 0.01) {
      final gp = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = max(1, _u * 0.014)
        ..color = Color.fromRGBO(94, 225, 255, 0.55 * guides);
      canvas.drawArc(
        Rect.fromCircle(center: Offset(_cx, _cy), radius: _cr),
        -pi / 2,
        pi * 2 * identOutCubic(identClamp(t / 0.26, 0, 1)),
        false,
        gp,
      );
      final cross = identClamp((t - 0.10) / 0.20, 0, 1) * _cr * 1.35;
      if (cross > 0) {
        canvas.drawLine(
            Offset(_cx - cross, _cy), Offset(_cx + cross, _cy), gp);
        canvas.drawLine(
            Offset(_cx, _cy - cross), Offset(_cx, _cy + cross), gp);
      }
      if (t > 0.14) canvas.drawPath(_ticks, gp);
    }

    // The outline strokes itself.
    final dr = identOutCubic(identClamp((t - 0.22) / 0.34, 0, 1));
    final drawn = (dr * _kDraw).round();
    if (drawn > 0) {
      canvas.save();
      canvas.translate(_cx, _cy);
      canvas.drawPath(
        _draw[drawn],
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = max(1.2, _u * 0.03)
          ..strokeJoin = StrokeJoin.round
          ..color = const Color(0xFF7FEBFF),
      );
      canvas.restore();
    }

    // Ink wipe: a clip rect rising over the cached shader.
    final ink = identOutCubic(identClamp((t - 0.50) / 0.28, 0, 1));
    if (ink > 0) {
      canvas.save();
      canvas.translate(_cx, _cy);
      canvas.clipRect(
          Rect.fromLTWH(-_g, _g * 0.5 - _g * ink, _g * 2, _g * 1.2));
      canvas.drawPath(_mark, Paint()..shader = _inkShader);
      canvas.restore();
    }

    // The name types itself — whole letters only, no partial alpha.
    final typed =
        (identClamp((t - 0.58) / 0.30, 0, 1) * kIdentWord.length).floor();
    for (int i = 0; i < typed; i++) {
      word.paintLetter(canvas, _ink, i, _startX, _baseY);
    }
    if (typed < kIdentWord.length && t > 0.58) {
      double x = _startX;
      for (int k = 0; k < typed; k++) {
        x += word.widths[k] + word.tracking;
      }
      canvas.drawRect(
        Rect.fromLTWH(x, _baseY - word.fontSize * 0.72,
            max(1.5, _u * 0.03), word.fontSize * 0.86),
        Paint()..color = const Color(0xBF5EE1FF),
      );
    }

    // Dimension rule + caption, hard cut in.
    if (t > 0.80) {
      canvas.drawPath(
        _dim,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = const Color(0x995EE1FF),
      );
      _caption.paint(
        canvas,
        Offset(_cx - _caption.width / 2, _baseY + _u * 0.62 + _u * 0.30),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BlueprintPainter old) =>
      old.animation != animation;
}
