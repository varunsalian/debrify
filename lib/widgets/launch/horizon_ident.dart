import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'launch_ident.dart';

/// Event Horizon — a starfield is pulled into a burning accretion ring; the
/// ring collapses and what is left glowing at the centre is the mark. The
/// name condenses letter by letter, thin and vast, out of the dark.
///
/// TV notes: stars are line segments batched into two drawRawPoints calls
/// (dim / bright buckets) over reused Float32List buffers — 85 stars on TV,
/// 170 elsewhere; the only per-frame allocations are the two sublist views.
/// Ring glow uses stroked ovals (two-pass on TV). Letter fades are quantized
/// alpha sets. Everything is still at rest.
///
/// Timeline: 0–.58 in-fall · .58 collapse + flash · .58–.72 mark ignites ·
/// .68–1 name condenses centre-outward.
class HorizonIdent extends LaunchIdent {
  const HorizonIdent();

  @override
  String get id => 'horizon';
  @override
  String get label => 'Event Horizon';
  @override
  String get subtitle =>
      'A starfield collapses into a burning ring — the mark is what remains';
  @override
  Duration get revealDuration => const Duration(milliseconds: 3000);
  @override
  Color get baseColor => const Color(0xFF000005);
  @override
  BoxDecoration get backdrop => const BoxDecoration(
        // Faint violet nebula around the collapse point, pre-blended opaque.
        gradient: RadialGradient(
          center: Alignment(0, -0.16),
          radius: 0.9,
          colors: [Color(0xFF080718), Color(0xFF000005)],
        ),
      );
  @override
  List<Color> get sweepColors =>
      const [Color(0xFF818CF8), Color(0xFFE9EDFF)];

  /// The nebula keeps its radial geometry — same centre, same radius, same
  /// stop positions — and only its two colours move. A flat fill here would
  /// throw away the collapse point the whole reveal is composed around.
  @override
  Decoration themedBackdrop(IdentPalette p) => RadialGradient(
        center: const Alignment(0, -0.16),
        radius: 0.9,
        colors: [
          // The bright inner stop is the base lifted TOWARD the accent, the
          // same relationship #080718 has to #000005.
          Color.lerp(p.base, p.accent, 0.14)!,
          p.base,
        ],
      ).let((g) => BoxDecoration(gradient: g));

  @override
  CustomPainter createPainter(
    Animation<double> animation, {
    required bool Function() isTelevision,
    IdentPalette? palette,
  }) =>
      _HorizonPainter(animation, isTelevision: isTelevision, palette: palette);
}

class _Star {
  final double a, r0, d, spin;
  const _Star(this.a, this.r0, this.d, this.spin);
}

class _HorizonPainter extends CustomPainter {
  final Animation<double> animation;
  final bool Function() isTelevision;

  /// Null keeps Horizon's own accretion colours — the default path.
  final IdentPalette? palette;

  /// The burning ring and the condensing wordmark. A themed palette moves the
  /// hue; the collapse geometry, the star count and the timeline do not move.
  static const _ownRingInner = Color(0xFF4F74FF);
  static const _ownRingOuter = Color(0xFF8A5CFF);
  static const _ownMarkInk = Color(0xFFD9DEFF);

  Color get _ringInner => palette?.accent ?? _ownRingInner;
  Color get _ringOuter =>
      palette == null ? _ownRingOuter : Color.lerp(palette!.accent, palette!.ink, 0.35)!;
  Color get _markInk => palette?.ink ?? _ownMarkInk;

  /// The ignition glow — Horizon's own indigo, or the theme's accent.
  static const _ownGlow = Color(0xFF818CF8);
  Color get _glow => palette?.accent ?? _ownGlow;

  Size? _size;
  bool? _lw;
  IdentWordLayout? _word;
  List<_Star> _stars = const [];
  late Float32List _dimBuf, _brightBuf;
  late double _cx, _cy, _g, _startX, _baseY;
  late Path _mark, _inner;
  late Rect _markRect;
  late Shader _markShader;
  IdentAlphaSets? _letters;

  static const double _collapse = 0.58;
  static const List<int> _order = [3, 2, 4, 1, 5, 0, 6];

  _HorizonPainter(this.animation,
      {required this.isTelevision, this.palette})
      : super(repaint: animation);

  void _layout(Size size, bool lightweight) {
    if (_word != null && _size == size && _lw == lightweight) return;
    _size = size;
    _lw = lightweight;
    final w = size.width, h = size.height;
    _cx = w / 2;
    _cy = h * 0.42;
    _g = h * 0.20;
    final count = lightweight ? 85 : 170;
    final maxR = sqrt(w * w + h * h);
    _stars = [
      for (int i = 0; i < count; i++)
        _Star(
          identNoise(i * 3.1) * pi * 2,
          maxR * (0.14 + identNoise(i * 5.7) * 0.5),
          identNoise(i * 7.3) * 0.28,
          0.6 + identNoise(i * 9.9) * 1.4,
        ),
    ];
    _dimBuf = Float32List(count * 4);
    _brightBuf = Float32List(count * 4);
    _mark = identPlayPath(_g);
    _inner = identPlayPath(_g * 0.52);
    _markRect = Rect.fromCenter(center: Offset.zero, width: _g, height: _g);
    // No longer `const`: the two stops now come from the palette when one is
    // supplied. Still built once per (size, TV-flag) in `_build`, so this is
    // not a per-frame allocation.
    _markShader = LinearGradient(
      colors: [_ringInner, _ringOuter],
    ).createShader(_markRect);
    _word = IdentWordLayout.fit(
      styleFor: (fz) => TextStyle(
        fontSize: fz,
        fontWeight: FontWeight.w200,
        height: 1.0,
        color: _markInk,
      ),
      fontSize: h * 0.085,
      trackingFactor: 0.85,
      maxWidth: w * 0.60,
    );
    _startX = w / 2 - _word!.width / 2;
    _baseY = h * 0.76;
    _letters = IdentAlphaSets(_word!, 'star', _markInk);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final t = animation.value;
    final lightweight = isTelevision();
    _layout(size, lightweight);

    final ringR = _g * 0.85;

    // Stars: fill the two line buffers, then two batched draws.
    final gone =
        t > _collapse ? identClamp((t - _collapse) / 0.08, 0, 1) : 0.0;
    if (gone < 1) {
      int di = 0, bi = 0;
      for (final s in _stars) {
        final pt = identClamp((t - s.d) / (_collapse - s.d), 0, 1);
        final e = identInCubic(pt);
        final r = identLerp(s.r0, ringR, e);
        final a = s.a + e * s.spin * 2.2;
        final x = _cx + cos(a) * r, y = _cy + sin(a) * r * 0.62;
        final sl = 2 + e * 14;
        final tx = cos(a + pi / 2) * sl, ty = sin(a + pi / 2) * sl * 0.62;
        if (e < 0.5) {
          _dimBuf[di++] = x;
          _dimBuf[di++] = y;
          _dimBuf[di++] = x - tx;
          _dimBuf[di++] = y - ty;
        } else {
          _brightBuf[bi++] = x;
          _brightBuf[bi++] = y;
          _brightBuf[bi++] = x - tx;
          _brightBuf[bi++] = y - ty;
        }
      }
      final fade = 1 - gone;
      if (di > 0) {
        canvas.drawRawPoints(
          ui.PointMode.lines,
          Float32List.sublistView(_dimBuf, 0, di),
          Paint()
            ..strokeWidth = 1
            ..color = Color.fromRGBO(200, 205, 255, 0.40 * fade),
        );
      }
      if (bi > 0) {
        canvas.drawRawPoints(
          ui.PointMode.lines,
          Float32List.sublistView(_brightBuf, 0, bi),
          Paint()
            ..strokeWidth = 1.4
            ..color = Color.fromRGBO(215, 220, 255, 0.90 * fade),
        );
      }
    }

    // Accretion ring + black disc, collapsing after the fall.
    final rlife = identClamp(t / _collapse, 0, 1);
    final shrink = identClamp((t - _collapse) / 0.14, 0, 1);
    if (shrink < 1) {
      final rr = identLerp(ringR, 0, identOutCubic(shrink));
      final glow = 0.25 + 0.75 * rlife;
      canvas.save();
      canvas.translate(_cx, _cy);
      canvas.scale(1, 0.62);
      final oval = Rect.fromCircle(center: Offset.zero, radius: rr);
      // Glow: two-stroke idiom on TV, soft blur elsewhere.
      final glowColor =
          Color.fromRGBO(129, 140, 248, 0.55 * glow * (1 - shrink));
      if (lightweight) {
        canvas.drawOval(
            oval,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 10
              ..color = glowColor.withValues(alpha: glowColor.a * 0.4));
      } else {
        canvas.drawOval(
            oval,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 6
              ..color = glowColor
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12));
      }
      canvas.drawOval(
        oval,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2 + 3 * rlife
          ..color =
              Color.fromRGBO(233, 237, 255, 0.90 * glow * (1 - shrink)),
      );
      canvas.drawOval(
        Rect.fromCircle(center: Offset.zero, radius: rr * 0.82),
        Paint()..color = const Color(0xFF000000),
      );
      canvas.restore();
    }

    // Flash at collapse. The shader is rebuilt per frame with the fade baked
    // into its colors, but ONLY inside this ~8-frame window — Paint.color's
    // alpha is not reliable over a shader across backends (the API docs say
    // shader overrides color), so it is never used for fades.
    final ft = identClamp((t - _collapse) / 0.14, 0, 1);
    if (ft > 0 && ft < 1) {
      final fr = Rect.fromCircle(center: Offset(_cx, _cy), radius: _g * 2.6);
      canvas.drawRect(
        fr,
        Paint()
          ..shader = RadialGradient(colors: [
            Color.fromRGBO(233, 237, 255, 0.80 * (1 - ft)),
            const Color(0x00818CF8),
          ]).createShader(fr),
      );
    }

    // The mark, left glowing at the centre.
    final ma = identClamp((t - _collapse - 0.05) / 0.18, 0, 1);
    if (ma > 0) {
      canvas.save();
      canvas.translate(_cx, _cy);
      identGlowPath(
        canvas,
        _mark,
        // The glow around the ignited mark. Alpha is animated, so the colour
        // is composed rather than named — `_glow` is the ident's own #818CF8
        // unless a palette replaced it.
        _glow.withValues(alpha: 0.55 * ma),
        _g * 0.12,
        lightweight: lightweight,
      );
      // Cached full-alpha shader at rest; alpha-baked rebuild only during the
      // ~11-frame ignition ramp (shader+Paint.color fades are backend-
      // dependent and banned).
      canvas.drawPath(
        _mark,
        Paint()
          ..shader = ma >= 1
              ? _markShader
              : LinearGradient(colors: [
                  // The same two ring stops as `_markShader`, alpha-baked for
                  // the ignition ramp (shader/Paint.color fades are
                  // backend-dependent and banned here).
                  _ringInner.withValues(alpha: ma),
                  _ringOuter.withValues(alpha: ma),
                ]).createShader(_markRect),
      );
      canvas.drawPath(
        _inner,
        Paint()..color = Color.fromRGBO(223, 230, 255, 0.20 * ma),
      );
      canvas.restore();
    }

    // The name condenses centre-outward.
    final word = _word!;
    for (int k = 0; k < _order.length; k++) {
      final i = _order[k];
      final lt = identClamp((t - (0.68 + k * 0.045)) / 0.26, 0, 1);
      if (lt <= 0) continue;
      final e = identOutCubic(lt);
      final set = _letters!.at(e);
      if (set == null) continue;
      word.paintLetter(canvas, set, i, _startX, _baseY,
          dy: (1 - e) * word.fontSize * 0.15);
    }
  }

  @override
  bool shouldRepaint(covariant _HorizonPainter old) =>
      old.animation != animation;
}


/// Tiny helper so the gradient above reads as one expression.
extension _Let<T> on T {
  R let<R>(R Function(T) f) => f(this);
}
