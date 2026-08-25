import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../utils/platform_util.dart';
import 'launch_ident.dart';

/// Frost — the pane is frozen over. Warmth spreads from the mark and clears
/// the glass in the shape of the lockup, letter by letter as it is reached.
///
/// This is the one ident whose GROUND is the bright element: the letters are
/// dark windows cut in a pale frost field, not light drawn on a dark one. Two
/// consequences worth stating, because both were learned the hard way:
///
///  * The frost must stay bright right across the middle. Thinning it toward
///    the centre leaves the letters — which are the same dark glass — with
///    nothing to read against.
///  * Clearing a whole oval around the lockup kills the ident for the same
///    reason: cleared glass and a cleared letter are the same colour. The wash
///    only THINS the pane; the letterforms are the only thing that fully
///    clears.
///
/// TV notes: the frost field is tens of thousands of flecks and is completely
/// static, so it lives in the [backdrop] and rasters once, batched into a
/// handful of [Canvas.drawRawPoints] calls. The thinning wash is ONE radial
/// shader baked into a unit rect and stretched by the canvas — its alpha never
/// changes, only its size, so nothing native is created per frame. Per-letter
/// clearing runs on quantized pre-baked text sets, never a per-frame alpha.
///
/// Timeline: .02–.30 the mark clears first, since the warmth comes from it ·
/// .06–.62 each letter clears as the warmth reaches it, normalised against the
/// LOCKUP's reach rather than the screen diagonal · nothing refreezes, so the
/// last frame is motionless.
class FrostIdent extends LaunchIdent {
  const FrostIdent();

  @override
  String get id => 'frost';
  @override
  String get label => 'Frost';
  @override
  String get subtitle => 'A frozen pane clearing in the shape of the lockup';
  @override
  Duration get revealDuration => const Duration(milliseconds: 2400);
  @override
  Color get baseColor => const Color(0xFF0A1017);

  @override
  Decoration get backdrop =>
      _FrostDecoration(PlatformUtil.isAndroidTvCached);

  /// The frost IS this ident, so the crystal field, its edge weighting and the
  /// mist wash are all kept; only the glass behind it takes the theme.
  @override
  Decoration themedBackdrop(IdentPalette p) =>
      _FrostDecoration(PlatformUtil.isAndroidTvCached, base: p.base);

  @override
  List<Color> get sweepColors =>
      const [Color(0xFFD8E8F3), Color(0xFFA8BCCE)];

  @override
  CustomPainter createPainter(
    Animation<double> animation, {
    required bool Function() isTelevision,
    IdentPalette? palette,
  }) =>
      _FrostPainter(animation, isTelevision: isTelevision, palette: palette);
}

/// The frozen pane. Entirely static, so it belongs on the far side of the
/// painter's RepaintBoundary — rastered once by the DecoratedBox rather than
/// re-scattered at 60fps behind the reveal.
class _FrostDecoration extends Decoration {
  final bool lightweight;

  /// The glass behind the frost. Defaults to Frost's own.
  final Color base;

  const _FrostDecoration(this.lightweight,
      {this.base = const Color(0xFF0A1017)});

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) =>
      _FrostBoxPainter(lightweight, base);

  // Equality is what lets a late TV probe swap the crystal density: a
  // DecoratedBox keeps its BoxPainter until the decoration compares unequal.
  @override
  bool operator ==(Object other) =>
      other is _FrostDecoration &&
      other.lightweight == lightweight &&
      other.base == base;

  @override
  int get hashCode => Object.hash(lightweight, base);
}

class _FrostBoxPainter extends BoxPainter {
  final bool lightweight;
  final Color base;
  Size? _size;

  /// Flecks bucketed by (colour, alpha step): the whole pane is eight batched
  /// point draws instead of forty thousand drawRects.
  List<Float32List>? _flecks;

  /// Larger crystals — centre, radius, squash, angle — so the texture has
  /// structure and not just noise.
  List<double>? _crystals;

  static const int _steps = 4;
  static const double _peak = 0.42;
  static const Color _pale = Color(0xFFC6D6E4);
  static const Color _deep = Color(0xFF87A0B6);
  static const Color _crystalColor = Color(0xFFD6E6F2);

  _FrostBoxPainter(this.lightweight, this.base);

  void _build(Size size) {
    if (_flecks != null && _size == size) return;
    _size = size;
    final w = size.width, h = size.height;
    final cx = w / 2, cy = h / 2;
    final r = sqrt(w * w + h * h) * 0.5;
    // Seeded, not random: the pane must freeze the same way on every launch.
    final rnd = Random(760213);
    final n = (w * h * (lightweight ? 0.022 : 0.040)).round();
    final buckets = List.generate(_steps * 2, (_) => <double>[]);
    for (int i = 0; i < n; i++) {
      final x = rnd.nextDouble() * w;
      final y = rnd.nextDouble() * h;
      final t = sqrt((x - cx) * (x - cx) + (y - cy) * (y - cy)) / r;
      // Only a little heavier at the edges. The field has to stay bright in
      // the middle or the cut letters have nothing to read against.
      if (rnd.nextDouble() > 0.62 + t * 0.38) continue;
      final a = (0.07 + rnd.nextDouble() * 0.34) * (0.72 + t * 0.38);
      final k = identClamp(a / _peak * _steps, 0, _steps - 1.0).floor();
      final pale = rnd.nextDouble() > 0.38 ? 1 : 0;
      buckets[pale * _steps + k]
        ..add(x)
        ..add(y);
    }
    _flecks = [for (final b in buckets) Float32List.fromList(b)];

    final crystals = <double>[];
    for (int i = 0, c = lightweight ? 240 : 520; i < c; i++) {
      final x = rnd.nextDouble() * w;
      final y = rnd.nextDouble() * h;
      final t = sqrt((x - cx) * (x - cx) + (y - cy) * (y - cy)) / r;
      crystals.addAll([
        x,
        y,
        2 + rnd.nextDouble() * 5.5,
        0.28 + rnd.nextDouble() * 0.5,
        rnd.nextDouble() * pi,
        (0.05 + rnd.nextDouble() * 0.10) * (0.6 + t * 0.6),
      ]);
    }
    _crystals = crystals;
  }

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    final size = configuration.size;
    if (size == null || size.isEmpty) return;
    _build(size);
    canvas.save();
    canvas.translate(offset.dx, offset.dy);

    // Opaque glass first — this decoration IS the splash's floor.
    canvas.drawRect(Offset.zero & size, Paint()..color = base);

    final fleck = Paint()
      ..strokeWidth = 1.7
      ..strokeCap = StrokeCap.square;
    for (int i = 0; i < _flecks!.length; i++) {
      final pts = _flecks![i];
      if (pts.isEmpty) continue;
      final a = _peak * ((i % _steps) + 1) / _steps;
      canvas.drawRawPoints(
        ui.PointMode.points,
        pts,
        fleck..color = (i >= _steps ? _pale : _deep).withValues(alpha: a),
      );
    }

    final crystal = Paint();
    final c = _crystals!;
    for (int i = 0; i < c.length; i += 6) {
      canvas.save();
      canvas.translate(c[i], c[i + 1]);
      canvas.rotate(c[i + 4]);
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset.zero,
          width: c[i + 2] * 2,
          height: c[i + 2] * c[i + 3] * 2,
        ),
        crystal..color = _crystalColor.withValues(alpha: c[i + 5]),
      );
      canvas.restore();
    }

    // A mist wash over the whole pane. Flecks alone leave the field's AVERAGE
    // barely above the glass behind them, and the cut letters — which are that
    // same glass — then read as outlines instead of as windows.
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0x26A2BACE),
    );
    canvas.restore();
  }
}

class _FrostPainter extends CustomPainter {
  final Animation<double> animation;
  final bool Function() isTelevision;
  final IdentPalette? palette;

  Size? _size;
  bool? _lw;
  IdentWordLayout? _word;
  late double _s, _baseY, _wordLeft, _markCx, _markCy, _markSize, _total;
  late Path _mark;
  late List<List<TextPainter>> _bank, _glass, _melt;
  late Shader _thin;
  late double _bankWidth, _meltWidth;

  static const Rect _unit = Rect.fromLTRB(-0.5, -0.5, 0.5, 0.5);
  static const int _fade = 4;

  _FrostPainter(
    this.animation, {
    required this.isTelevision,
    this.palette,
  }) : super(repaint: animation);

  Color get _meltColor => palette?.ink ?? const Color(0xFFD8E8F3);
  Color get _glassColor =>
      Color.lerp(palette?.base ?? const Color(0xFF0A1017), Colors.black, 0.62)!;

  /// Nearest pre-baked step for [a] (0..1), or -1 when invisible. Each ladder
  /// is baked at its own PEAK alpha, so the index is the reveal's progress and
  /// not the drawn opacity.
  static int _step(double a) => a < 0.125
      ? -1
      : a < 0.375
          ? 0
          : a < 0.625
              ? 1
              : a < 0.875
                  ? 2
                  : 3;

  List<List<TextPainter>> _fill(IdentWordLayout w, String name, Color c) => [
        for (int k = 1; k <= _fade; k++)
          w.set('$name$k',
              (s) => s.copyWith(color: c.withValues(alpha: c.a * k / _fade))),
      ];

  /// A stroked variant set. Built explicitly rather than through copyWith:
  /// a TextStyle carrying both a colour and a foreground Paint asserts.
  List<List<TextPainter>> _stroke(
    IdentWordLayout w,
    String name,
    Color c,
    double width,
  ) =>
      [
        for (int k = 1; k <= _fade; k++)
          w.set(
            '$name$k',
            (s) => TextStyle(
              fontSize: s.fontSize,
              fontWeight: s.fontWeight,
              height: s.height,
              foreground: Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = width
                ..strokeJoin = StrokeJoin.round
                ..color = c.withValues(alpha: c.a * k / _fade),
            ),
          ),
      ];

  void _layout(Size size, bool lightweight) {
    if (_word != null && _size == size && _lw == lightweight) return;
    _size = size;
    _lw = lightweight;
    final w = size.width, h = size.height;
    final tall = h > w * 1.1;

    // Sized off the HEIGHT with a width ceiling, never off identUnit: above
    // 16:9 identUnit goes width-driven while type stays height-driven, and in
    // portrait it collapses the mark to a single letter's size.
    final s0 = min(h * 0.105, w * 0.120);
    const reserve = 0.74 * 0.73 + 0.42;
    _word = IdentWordLayout.fit(
      styleFor: (fz) => TextStyle(
        fontSize: fz,
        fontWeight: FontWeight.w500,
        height: 1.0,
        color: const Color(0xFF000000),
      ),
      fontSize: s0,
      trackingFactor: 0.22,
      maxWidth: max(s0 * 2, w * 0.78 - s0 * reserve),
    );
    _s = _word!.fontSize;
    _markSize = _s * 0.74;
    final markW = _markSize * 0.73;
    final gap = _s * 0.42;
    _total = markW + gap + _word!.width;
    final left = w / 2 - _total / 2;
    // identPlayPath spans -0.30s..0.43s, so its left edge sits 0.30s left of
    // the centre it is drawn about.
    _markCx = left + _markSize * 0.30;
    _wordLeft = left + markW + gap;
    _baseY = h * (tall ? 0.50 : 0.52);
    _markCy = _baseY - _s * 0.35;
    _mark = identPlayPath(_markSize);

    _bankWidth = _s * 0.085;
    _meltWidth = max(1, _s * 0.013);
    // Thicker frost banked around the cut, the clear glass seen through it,
    // and meltwater on the edge catching the light. Each ladder is baked at
    // its own peak alpha and indexed by the letter's clearing progress.
    _bank = _stroke(_word!, 'fr-bank',
        const Color(0xFF9FB6C8).withValues(alpha: 0.30), _bankWidth);
    _glass = _fill(_word!, 'fr-glass', _glassColor);
    _melt = _stroke(
        _word!, 'fr-melt', _meltColor.withValues(alpha: 0.55), _meltWidth);

    _thin = RadialGradient(
      colors: [
        (palette?.base ?? const Color(0xFF0A1017)).withValues(alpha: 0.34),
        (palette?.base ?? const Color(0xFF0A1017)).withValues(alpha: 0.20),
        (palette?.base ?? const Color(0xFF0A1017)).withValues(alpha: 0),
      ],
      stops: const [0, 0.55, 1],
    ).createShader(_unit);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final t = animation.value;
    final lightweight = isTelevision();
    _layout(size, lightweight);
    final word = _word!;

    // The pane is in the backdrop — nothing static is drawn here.

    // The warmth only thins the frost; it never clears it. See the class doc.
    final grow = identIoCubic(identClamp((t - 0.04) / 0.66, 0, 1));
    canvas.save();
    canvas.translate(_markCx + _total * 0.42, _baseY - _s * 0.30);
    canvas.scale(_total * identLerp(0.6, 2.2, grow),
        _s * identLerp(1.6, 4.4, grow));
    canvas.drawRect(_unit, Paint()..shader = _thin);
    canvas.restore();

    // Normalised against the LOCKUP's reach. Against the screen diagonal the
    // whole cadence collapses into a handful of frames and every letter
    // appears to clear at once.
    final reach = _total * 1.02;
    for (int i = 0; i < kIdentWord.length; i++) {
      final gx = _wordLeft + word.lefts[i] + word.widths[i] / 2;
      final q = identClamp((gx - _markCx) / reach, 0, 1);
      final start = 0.06 + q * 0.46;
      final e = identOutCubic(identClamp((t - start) / 0.30, 0, 1));
      final k = _step(e);
      if (k < 0) continue;
      // Banked frost, then the window, then the meltwater edge. On TV the
      // banked pass goes: it is the widest stroke and the least of the read.
      if (!lightweight) {
        word.paintLetter(canvas, _bank[k], i, _wordLeft, _baseY);
      }
      word.paintLetter(canvas, _glass[k], i, _wordLeft, _baseY);
      word.paintLetter(canvas, _melt[k], i, _wordLeft, _baseY);
    }

    // The mark clears first — it is where the warmth is coming from.
    final me = identOutCubic(identClamp((t - 0.02) / 0.28, 0, 1));
    if (me > 0.01) {
      canvas.save();
      canvas.translate(_markCx, _markCy);
      if (!lightweight) {
        canvas.drawPath(
          _mark,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = _bankWidth
            ..strokeJoin = StrokeJoin.round
            ..color = const Color(0xFF9FB6C8).withValues(alpha: 0.30 * me),
        );
      }
      canvas.drawPath(
          _mark, Paint()..color = _glassColor.withValues(alpha: me));
      canvas.drawPath(
        _mark,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = _meltWidth
          ..strokeJoin = StrokeJoin.round
          ..color = _meltColor.withValues(alpha: 0.55 * me),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _FrostPainter old) =>
      old.animation != animation || old.palette != palette;
}
