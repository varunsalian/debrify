import 'dart:math';

import 'package:flutter/material.dart';

import 'launch_ident.dart';

/// Trace — a signal locking on. One point of light runs the frame, drawing a
/// hairline rule as it goes, and the letters it passes over ignite in its wake
/// and cool to a steady glow. When the light reaches the end it flares out and
/// the rule retracts to a single centred tick under the name.
///
/// The material is light itself rather than a colour: the pulse is white, its
/// halo is barely blue, and the type is platinum. That is what keeps it from
/// being Monogram's ring redrawn horizontally — here the type is a filament the
/// pulse lights, not a caption that fades up underneath a mark.
///
/// **The cadence is normalised against the WORDMARK, never the frame.** The
/// rule's length is derived from the laid-out word (16% wider), the dot travels
/// that rule, and each letter's ignition is keyed to the dot's *x* crossing it —
/// a spatial ramp, not a per-letter time offset. So the seven letters occupy the
/// same ~82% of the travel on a 21:9 panel, a 16:9 TV and a portrait phone, and
/// no easing exponent has to be retuned per aspect ratio. (Collider learned this
/// the expensive way: normalised against the screen diagonal, its lockup was 11%
/// of the wave's travel and every letter lit at once.)
///
/// TV notes: near the cost floor. Per tick this is three [Canvas.drawLine]s,
/// six circles while the pulse is alive (the five-step `_kHalo` falloff plus
/// its white core — see the comment there for why two steps is not enough on a
/// bright point), none once it has flared out, and one text draw per settled
/// letter — two only for the ~250 ms a letter is igniting. No saveLayer, no
/// shaders, no per-frame native allocation; the only blur is the dot's halo on
/// the phone/desktop path, and it is the disc ladder that replaces it on TV.
/// The ground is a static gradient and rasters once in [backdrop].
///
/// Timeline: 0–.05 the pulse strikes at the left · .02–.60 it crosses, drawing
/// the rule, igniting letters as it passes · .60–.72 it flares out · .66–1.0 the
/// rule retracts to a centred tick · rest, motionless.
class TraceIdent extends LaunchIdent {
  const TraceIdent();

  @override
  String get id => 'trace';
  @override
  String get label => 'Trace';
  @override
  String get subtitle =>
      'One point of light crosses the frame and the name lights in its wake';
  @override
  Duration get revealDuration => const Duration(milliseconds: 2400);
  @override
  Color get baseColor => const Color(0xFF06070A);

  /// A lift behind the lockup so the ground reads as a lit room rather than a
  /// black rectangle. Static, so it rasters once outside the painter.
  @override
  Decoration get backdrop => _ground(baseColor);

  @override
  Decoration themedBackdrop(IdentPalette p) => _ground(p.base);

  static Decoration _ground(Color base) => BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(0, -0.06),
          radius: 0.95,
          colors: [Color.lerp(base, const Color(0xFF9DB2FF), 0.055)!, base],
          stops: const [0, 1],
        ),
      );

  @override
  List<Color> get sweepColors =>
      const [Color(0xFFBFD0FF), Color(0xFFEFF3FA)];

  @override
  CustomPainter createPainter(
    Animation<double> animation, {
    required bool Function() isTelevision,
    IdentPalette? palette,
  }) =>
      _TracePainter(animation, isTelevision: isTelevision, palette: palette);
}

class _TracePainter extends CustomPainter {
  final Animation<double> animation;
  final bool Function() isTelevision;
  final IdentPalette? palette;

  Size? _size;
  IdentWordLayout? _word;
  late IdentAlphaSets _ink, _hot;

  late double _s; // resolved type size — everything else is a multiple of it
  late double _cx, _baseY, _ruleY, _ruleL, _ruleR, _tick, _stroke, _dotR, _span;
  late double _wordLeft;

  /// Letter centres in canvas x, so ignition can be keyed to the dot's
  /// position instead of to seven hand-tuned time offsets.
  late List<double> _centres;

  /// [radius multiple of the core, alpha] — the TV halo's falloff.
  static const List<List<double>> _kHalo = [
    [3.2, 0.045],
    [2.5, 0.060],
    [1.9, 0.085],
    [1.45, 0.120],
    [1.10, 0.180],
  ];

  _TracePainter(
    this.animation, {
    required this.isTelevision,
    this.palette,
  }) : super(repaint: animation);

  Color get _inkColor => palette?.ink ?? const Color(0xFFEFF3FA);

  /// The pulse's halo. Barely a hue — the signature here is the light, and a
  /// saturated dot is what would make this read as a loading spinner.
  Color get _haloColor => palette?.accent ?? const Color(0xFF9DB2FF);

  void _layout(Size size) {
    if (_word != null && _size == size) return;
    _size = size;
    final w = size.width, h = size.height;
    final tall = h > w * 1.1;

    // Off the HEIGHT with a width ceiling, never identUnit: above 16:9
    // identUnit goes width-driven while type stays height-driven, and in
    // portrait it collapses the lockup to a single letter's size.
    final s0 = min(h * 0.105, w * 0.120);
    _word = IdentWordLayout.fit(
      styleFor: (fz) => TextStyle(
        fontSize: fz,
        // Ultralight and widely tracked: the letters have to read as filament,
        // and a heavy face would swallow the ignition entirely.
        fontWeight: FontWeight.w300,
        height: 1.0,
        // Only ever a layout metric — every painted set comes from an
        // IdentAlphaSets ladder that copyWith-overrides this — but it tracks
        // the palette anyway, so `word.base` is not a themed-ident trap for
        // whoever reaches for it next.
        color: _inkColor,
      ),
      fontSize: s0,
      trackingFactor: 0.34,
      // Portrait is the binding case — 0.34em of tracking over seven letters
      // runs a height-derived size straight off both edges of a phone.
      maxWidth: w * (tall ? 0.82 : 0.72),
    );
    final word = _word!;
    _s = word.fontSize;

    _cx = w / 2;
    _baseY = h * (tall ? 0.50 : 0.52);
    _ruleY = _baseY + _s * 0.58;
    // The word's own reach sets the travel. `width` carries tracking only
    // BETWEEN letters, so it is already the exact visual span — subtracting a
    // trailing tracking here would push the whole lockup half a gap right of
    // the tick it is supposed to sit over.
    final visible = word.width;
    _wordLeft = _cx - visible / 2;
    final ruleHalf = min(visible * 0.58, w * 0.46);
    _ruleL = _cx - ruleHalf;
    _ruleR = _cx + ruleHalf;
    _tick = max(9.0, visible * 0.045);
    _stroke = max(1.0, _s * 0.026);
    _dotR = max(1.6, _s * 0.048);
    // How far past a letter the pulse travels while that letter comes up.
    _span = _s * 0.62;

    _centres = [
      for (int i = 0; i < kIdentWord.length; i++)
        _wordLeft + word.lefts[i] + word.widths[i] / 2,
    ];

    _ink = IdentAlphaSets(word, 'trace-ink', _inkColor);
    // The ignition flash: a white pass over the settled letter, peaking
    // mid-ramp. Two draws for ~250 ms per letter, then it is gone.
    _hot = IdentAlphaSets(
      word,
      'trace-hot',
      const Color(0xFFFFFFFF).withValues(alpha: 0.72),
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final t = animation.value;
    _layout(size);
    final word = _word!;
    final lightweight = isTelevision();

    final travel = identIoSine(identClamp((t - 0.02) / 0.58, 0, 1));
    final dotX = identLerp(_ruleL, _ruleR, travel);
    final strike = identClamp(t / 0.05, 0, 1);
    final retract = identOutQuint(identClamp((t - 0.66) / 0.34, 0, 1));

    // ── The rule ────────────────────────────────────────────────────────
    // Drawn behind the pulse, then pulled in to a centred tick. Both ends are
    // lerped from where they actually are, so travel and retract are one
    // continuous move with no seam at the hand-off.
    final left = identLerp(_ruleL, _cx - _tick, retract);
    final right = identLerp(dotX, _cx + _tick, retract);
    if (right > left) {
      canvas.drawLine(
        Offset(left, _ruleY),
        Offset(right, _ruleY),
        Paint()
          ..strokeWidth = _stroke
          ..strokeCap = StrokeCap.round
          ..color = _inkColor.withValues(
              alpha: identLerp(0.26, 0.55, retract) * strike),
      );
      // The hot tail behind the pulse. Two flat segments rather than a
      // gradient: a shader here would be minted every frame, and at this width
      // the step between them reads as falloff.
      if (travel < 1) {
        for (final seg in const [
          [1.7, 0.16],
          [0.55, 0.5],
        ]) {
          final x0 = max(left, dotX - _s * seg[0]);
          if (dotX <= x0) continue;
          canvas.drawLine(
            Offset(x0, _ruleY),
            Offset(dotX, _ruleY),
            Paint()
              ..strokeWidth = _stroke
              ..strokeCap = StrokeCap.round
              ..color = Colors.white.withValues(alpha: seg[1] * strike),
          );
        }
      }
    }

    // ── The letters ─────────────────────────────────────────────────────
    // Keyed to the pulse's x, not to time: monotone with travel, so a frozen
    // progress freezes the reveal, and identical on every aspect ratio.
    for (int i = 0; i < kIdentWord.length; i++) {
      final k = identClamp((dotX - _centres[i]) / _span, 0, 1);
      if (k <= 0) continue;
      final e = identOutCubic(k);
      final dy = identLerp(_s * 0.085, 0, e);
      final set = _ink.at(e);
      if (set != null) {
        word.paintLetter(canvas, set, i, _wordLeft, _baseY, dy: dy);
      }
      // Peaks at k = .5 and is gone by the time the letter has settled.
      final flash = 4 * k * (1 - k);
      if (flash > 0.14) {
        final hot = _hot.at(flash);
        if (hot != null) {
          word.paintLetter(canvas, hot, i, _wordLeft, _baseY, dy: dy);
        }
      }
    }

    // ── The pulse ───────────────────────────────────────────────────────
    final flare = identClamp((t - 0.60) / 0.12, 0, 1);
    if (flare < 1) {
      final a = (1 - flare) * strike;
      final r = identLerp(_dotR, _dotR * 3.4, identOutCubic(flare));
      if (lightweight) {
        // A stepped disc falloff instead of a Gaussian — the house TV idiom,
        // but as FIVE steps rather than the usual two. At two, the flare reads
        // as a drawn target: the ring edges are 0.18 apart in alpha and the eye
        // finds them instantly. Five steps put every edge under 0.06, which is
        // invisible at 10 feet, and five circles is still nothing to draw.
        for (final ring in _kHalo) {
          canvas.drawCircle(
            Offset(dotX, _ruleY),
            r * ring[0],
            Paint()..color = _haloColor.withValues(alpha: ring[1] * a),
          );
        }
      } else {
        canvas.drawCircle(
          Offset(dotX, _ruleY),
          r * 1.5,
          Paint()
            ..color = _haloColor.withValues(alpha: 0.55 * a)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 1.6),
        );
      }
      canvas.drawCircle(
        Offset(dotX, _ruleY),
        r * 0.55,
        Paint()..color = Colors.white.withValues(alpha: a),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TracePainter old) =>
      old.animation != animation || old.palette != palette;
}
