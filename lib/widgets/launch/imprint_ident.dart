import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../utils/platform_util.dart';
import 'launch_ident.dart';

/// Imprint — the wordmark is never drawn. It is blind-debossed into uncoated
/// board, and a single warm light rakes across the sheet and finds it.
///
/// The relief is the whole ident, and it is built from three flat text passes
/// per letter rather than from any blur: a shadow wall, a lit wall, and the
/// pressed face that sits between them. A deboss is a VALLEY — the wall on the
/// light's side turns away from it and goes to shadow, and the far wall is the
/// one that catches it. Reversed, this reads as a 2003 bevel-and-emboss, which
/// is the single thing that separates this from looking cheap.
///
/// TV notes: the board (its gradient, its tooth and its vignette) is entirely
/// static, so it lives in the [backdrop] and rasters once — the tooth is
/// thousands of flecks and would be unaffordable per tick, but it is what
/// separates "uncoated stock" from "dark rectangle". The light is ONE radial
/// shader baked into a unit rect and stretched by the canvas, so nothing
/// native is created per frame. Per-letter relief strength goes through
/// [IdentAlphaSets] (quantized, pre-baked) — never a per-frame alpha on text.
///
/// Timeline: .02–.82 the light crosses the sheet, easeInOut so the rake is
/// held long enough to read · relief exists only where the light has been, and
/// stays behind it (the press does not un-press) · the light coasts to a dead
/// stop just right of centre, and the frame is motionless from there.
class ImprintIdent extends LaunchIdent {
  const ImprintIdent();

  @override
  String get id => 'imprint';
  @override
  String get label => 'Imprint';
  @override
  String get subtitle =>
      'A blind deboss on uncoated board, found by one raking light';
  @override
  Duration get revealDuration => const Duration(milliseconds: 2200);
  @override
  Color get baseColor => const Color(0xFF0D0D0F);

  // Density is resolved at build time, not baked in: AppInitializer re-probes
  // for TV after first paint and setStates, so the backdrop has to be able to
  // change with the flag (see _BoardDecoration's ==).
  @override
  Decoration get backdrop =>
      _BoardDecoration(PlatformUtil.isAndroidTvCached);

  /// The board IS this ident — a flat fill would leave a lit rectangle with
  /// nothing in it. So the tooth, the falloff and the vignette are kept and
  /// only the stock's colour moves.
  @override
  Decoration themedBackdrop(IdentPalette p) =>
      _BoardDecoration(PlatformUtil.isAndroidTvCached, base: p.base);

  @override
  List<Color> get sweepColors =>
      const [Color(0xFFF3E4C8), Color(0xFFDADEE6)];

  @override
  CustomPainter createPainter(
    Animation<double> animation, {
    required bool Function() isTelevision,
    IdentPalette? palette,
  }) =>
      _ImprintPainter(animation, isTelevision: isTelevision, palette: palette);
}

/// The sheet. Nothing about it depends on progress, so it belongs on the far
/// side of the painter's RepaintBoundary — rastered once by the DecoratedBox
/// rather than re-scattered at 60fps behind the reveal.
class _BoardDecoration extends Decoration {
  final bool lightweight;

  /// The stock. Defaults to Imprint's own; a themed palette substitutes it
  /// without touching the tooth or the falloff.
  final Color base;

  const _BoardDecoration(
    this.lightweight, {
    this.base = const Color(0xFF0D0D0F),
  });

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) =>
      _BoardBoxPainter(lightweight, base);

  // Equality is what lets a late TV probe swap the tooth density: DecoratedBox
  // keeps its BoxPainter until the decoration compares unequal. The colour
  // joins it for the same reason — a theme change must rebuild the painter.
  @override
  bool operator ==(Object other) =>
      other is _BoardDecoration &&
      other.lightweight == lightweight &&
      other.base == base;

  @override
  int get hashCode => Object.hash(lightweight, base);
}

class _BoardBoxPainter extends BoxPainter {
  final bool lightweight;
  final Color base;
  Size? _size;

  /// Tooth flecks bucketed by (colour, alpha step) so the whole sheet is eight
  /// batched [Canvas.drawRawPoints] calls instead of ten thousand drawRects.
  List<Float32List>? _flecks;

  /// Cached with them: a BoxPainter is re-run whenever its subtree repaints,
  /// so minting these two per call would allocate native shaders outside the
  /// one raster this decoration is supposed to cost.
  Shader? _stock, _vignette;

  static const int _steps = 4;
  static const double _peak = 0.05;

  _BoardBoxPainter(this.lightweight, this.base);

  void _build(Size size) {
    if (_flecks != null && _size == size) return;
    _size = size;
    final w = size.width, h = size.height;
    // Seeded, not random: the sheet must be identical on every launch, and
    // the settled frame must be reproducible.
    final rnd = Random(20260806);
    final n = (w * h * (lightweight ? 0.0055 : 0.011)).round();
    final buckets = List.generate(_steps * 2, (_) => <double>[]);
    for (int i = 0; i < n; i++) {
      final x = rnd.nextDouble() * w;
      final y = rnd.nextDouble() * h;
      final light = rnd.nextBool() ? 1 : 0;
      final k = rnd.nextInt(_steps);
      buckets[light * _steps + k]
        ..add(x)
        ..add(y);
    }
    _flecks = [for (final b in buckets) Float32List.fromList(b)];

    _stock = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        Color.lerp(base, Colors.white, 0.045)!,
        base,
        Color.lerp(base, Colors.black, 0.22)!,
      ],
      stops: const [0, 0.60, 1],
    ).createShader(Offset.zero & size);
    // So the sheet reads as lit rather than as a filled rectangle.
    _vignette = const RadialGradient(
      colors: [Color(0x00000000), Color(0x75000000)],
    ).createShader(
      Rect.fromCircle(
        center: Offset(w / 2, h / 2),
        radius: sqrt(w * w + h * h) * 0.60,
      ),
    );
  }

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    final size = configuration.size;
    if (size == null || size.isEmpty) return;
    _build(size);
    canvas.save();
    canvas.translate(offset.dx, offset.dy);

    // Opaque stock first — this decoration IS the splash's floor.
    canvas.drawRect(Offset.zero & size, Paint()..shader = _stock!);

    // Tooth.
    final fleck = Paint()
      ..strokeWidth = 1.35
      ..strokeCap = StrokeCap.square;
    for (int i = 0; i < _flecks!.length; i++) {
      final pts = _flecks![i];
      if (pts.isEmpty) continue;
      final light = i >= _steps;
      final a = _peak * ((i % _steps) + 1) / _steps;
      canvas.drawRawPoints(
        ui.PointMode.points,
        pts,
        fleck
          ..color = (light ? Colors.white : Colors.black).withValues(alpha: a),
      );
    }

    canvas.drawRect(Offset.zero & size, Paint()..shader = _vignette!);
    canvas.restore();
  }
}

class _ImprintPainter extends CustomPainter {
  final Animation<double> animation;
  final bool Function() isTelevision;
  final IdentPalette? palette;

  Size? _size;
  IdentWordLayout? _word;
  late double _s, _baseY, _wordLeft, _markCx, _markCy, _markSize, _d, _poolCy;
  late Path _mark;
  late IdentAlphaSets _shadow, _lit, _face;
  late Shader _pool;

  /// The light lives in a unit rect centred on the origin; the canvas scales
  /// it to the frame, so one shader serves every size and orientation.
  static const Rect _unit = Rect.fromLTRB(-0.5, -0.5, 0.5, 0.5);

  /// Relief passes: [offset scale, shadow alpha, lit alpha]. Two of them — a
  /// hard inner edge and a wider, weaker one — so the valley has a falloff
  /// instead of a single flat offset.
  static const List<List<double>> _walls = [
    [1.0, 0.95, 0.70],
    [0.52, 0.55, 0.40],
  ];

  /// On TV the falloff pass goes, halving the text draws per letter; the
  /// remaining wall carries a little more alpha to hold the same weight.
  static const List<List<double>> _wallsTv = [
    [1.0, 0.98, 0.74],
  ];

  _ImprintPainter(
    this.animation, {
    required this.isTelevision,
    this.palette,
  }) : super(repaint: animation);

  /// How hard the relief is showing at [x]. Static rather than a local
  /// closure over the light's position: this is called once per glyph, every
  /// tick, and a closure allocated per paint is a closure allocated per frame.
  ///
  /// The press stays pressed — once the light has crossed a letter its relief
  /// holds at a floor instead of fading out again behind the pool.
  static double _strength(double x, double lx, double falloff) {
    final k = (x - lx) / falloff;
    return max(exp(-k * k), x < lx ? 0.60 : 0.0);
  }

  Color get _litColor => palette?.ink ?? const Color(0xFFDADEE6);

  /// The pressed face: burnished, very slightly LIGHTER and warmer than the
  /// stock around it, because crushed fibre takes the raking light more evenly
  /// than the tooth does. Darker reads as an ink-filled letter and throws away
  /// the whole conceit — the mark is supposed to exist only as its edges.
  /// It is also what stops the two wall copies reading as a doubled letter.
  Color get _faceColor => Color.lerp(
        palette?.base ?? const Color(0xFF0D0D0F),
        const Color(0xFFFFE8C8),
        0.10,
      )!;

  void _layout(Size size) {
    if (_word != null && _size == size) return;
    _size = size;
    final w = size.width, h = size.height;
    final tall = h > w * 1.1;

    // Sized off the HEIGHT with a width ceiling, never off identUnit: above
    // 16:9 identUnit goes width-driven while type stays height-driven, and in
    // portrait it collapses the mark to a single letter's size.
    final s0 = min(h * 0.105, w * 0.120);
    // Reserve the inline mark and its gap before fitting the word.
    const reserve = 0.74 * 0.73 + 0.42;
    _word = IdentWordLayout.fit(
      styleFor: (fz) => TextStyle(
        fontSize: fz,
        fontWeight: FontWeight.w800,
        height: 1.0,
        color: const Color(0xFF000000),
      ),
      fontSize: s0,
      trackingFactor: 0.10,
      maxWidth: max(s0 * 2, w * 0.76 - s0 * reserve),
    );
    // The lockup stays proportional if fit() had to shrink the type.
    _s = _word!.fontSize;
    _markSize = _s * 0.74;
    final markW = _markSize * 0.73;
    final gap = _s * 0.42;
    final total = markW + gap + _word!.width;
    final left = w / 2 - total / 2;
    // identPlayPath spans -0.30s..0.43s, so its left edge sits 0.30s left of
    // the centre it is drawn about.
    _markCx = left + _markSize * 0.30;
    _wordLeft = left + markW + gap;
    _baseY = h * (tall ? 0.50 : 0.52);
    _markCy = _baseY - _s * 0.35;
    _mark = identPlayPath(_markSize);
    _d = max(1, _s * 0.034);
    _poolCy = _baseY - h * 0.07;

    _shadow = IdentAlphaSets(_word!, 'imp-sh', const Color(0xFF000000));
    _lit = IdentAlphaSets(_word!, 'imp-lit', _litColor);
    _face = IdentAlphaSets(_word!, 'imp-face', _faceColor);

    // The light: warm, and raked a few degrees off horizontal so it reads as
    // a source above and to the side rather than as a spotlight. Its alpha
    // never changes — only its position — so ONE shader serves the reveal.
    _pool = const RadialGradient(
      colors: [
        Color(0x36FFF6E6),
        Color(0x13FFF3E0),
        Color(0x00FFF0DC),
      ],
      stops: [0, 0.40, 1],
    ).createShader(_unit);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final t = animation.value;
    final walls = isTelevision() ? _wallsTv : _walls;
    _layout(size);
    final w = size.width, h = size.height;
    final word = _word!;

    // The board is in the backdrop — nothing static is drawn here.

    // easeInOut, not easeOut: an easeOut rake is over inside the first third
    // and the reveal it exists to perform is gone before you register it.
    // Zero derivative at both ends, so the settled frame is dead still. It
    // also starts only just off the lockup — easeInOut is slow at the top, and
    // a light that spends its first quarter off-screen wastes a quarter of the
    // ident.
    final travel = identIoCubic(identClamp((t - 0.02) / 0.80, 0, 1));
    final lx = identLerp(-w * 0.22, w * 0.40, travel);

    canvas.save();
    canvas.translate(lx, _poolCy);
    canvas.rotate(-0.14);
    canvas.scale(w * 1.24, h * 1.42);
    canvas.drawRect(_unit, Paint()..shader = _pool);
    canvas.restore();

    final falloff = w * 0.36;
    for (int i = 0; i < kIdentWord.length; i++) {
      final gx = _wordLeft + word.lefts[i];
      final s = _strength(gx + word.widths[i] / 2, lx, falloff);
      if (s <= 0.012) continue;
      final dir = gx < lx ? -1.0 : 1.0;
      for (final pass in walls) {
        final sc = pass[0];
        final sh = _shadow.at(s * pass[1]);
        if (sh != null) {
          word.paintLetter(canvas, sh, i, _wordLeft, _baseY,
              dx: -dir * _d * sc, dy: -_d * 0.92 * sc);
        }
        final li = _lit.at(s * pass[2]);
        if (li != null) {
          word.paintLetter(canvas, li, i, _wordLeft, _baseY,
              dx: dir * _d * sc, dy: _d * 0.92 * sc);
        }
      }
      final fa = _face.at(s);
      if (fa != null) word.paintLetter(canvas, fa, i, _wordLeft, _baseY);
    }

    // The mark, pressed by the same die.
    final ms = _strength(_markCx, lx, falloff);
    if (ms > 0.012) {
      final dir = _markCx < lx ? -1.0 : 1.0;
      void die(double ox, double oy, Color c) {
        canvas.save();
        canvas.translate(_markCx + ox, _markCy + oy);
        canvas.drawPath(_mark, Paint()..color = c);
        canvas.restore();
      }

      for (final pass in walls) {
        final sc = pass[0];
        die(-dir * _d * sc, -_d * 0.92 * sc,
            Colors.black.withValues(alpha: ms * pass[1]));
        die(dir * _d * sc, _d * 0.92 * sc,
            _litColor.withValues(alpha: ms * pass[2]));
      }
      die(0, 0, _faceColor.withValues(alpha: ms));
    }
  }

  @override
  bool shouldRepaint(covariant _ImprintPainter old) =>
      old.animation != animation || old.palette != palette;
}
