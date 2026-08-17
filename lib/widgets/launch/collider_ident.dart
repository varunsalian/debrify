import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'launch_ident.dart';

/// Collider — two spiral galaxies fall together, shear each other into tidal
/// bridges, and merge in a white flash. The mark is forged out of the remnant,
/// and the blast front sweeping outward is what ignites the name: each letter
/// lights the instant the shockwave crosses it, hot, then cools into the ink.
///
/// The idea Horizon reaches for and this one commits to: nothing here is
/// decoration bolted onto a fade. The wordmark's cadence IS the shockwave's
/// geometry — letters near the centre light first because the front reaches
/// them first — so the type reads as a consequence of the collision instead of
/// a caption under it. [_maxR] is what makes that legible rather than merely
/// true; see the note there.
///
/// TV notes: stars are motion-streak line segments batched into four
/// drawRawPoints calls (one dim + one bright bucket per galaxy) over reused
/// Float32List buffers — 84 stars per galaxy on TV, 175 elsewhere; the only
/// per-frame allocations are the sublist views. Every gradient that fades is a
/// pre-baked [_Ladder] built at layout, and every gradient that also MOVES or
/// GROWS is authored on the unit circle and placed by canvas transform — so
/// nothing native is minted per frame anywhere in the reveal. Letter fades are
/// quantized alpha sets; the specular pass is a clip-band redraw of a
/// pre-laid-out set. No saveLayer, and no MaskFilter on the TV branch.
///
/// Timeline: .06–.46 in-fall (shear ramps from .28) · .46 impact + flash ·
/// .46–.80 debris disperses · .50–.66 mark ignites · .68–.79 blast front
/// lights the name letter by letter · .90–.99 specular pass · rest.
class ColliderIdent extends LaunchIdent {
  const ColliderIdent();

  @override
  String get id => 'collider';
  @override
  String get label => 'Collider';
  @override
  String get subtitle =>
      'Two galaxies merge — the shockwave forges the mark and lights the name';
  @override
  Duration get revealDuration => const Duration(milliseconds: 3200);
  @override
  Color get baseColor => const Color(0xFF01030C);
  @override
  BoxDecoration get backdrop => const BoxDecoration(
        // Cold intergalactic field, one shade warmer around the impact point
        // so the flash has somewhere to bloom from. Pre-blended opaque.
        gradient: RadialGradient(
          center: Alignment(0, -0.20),
          radius: 1.05,
          colors: [Color(0xFF0A0A1E), Color(0xFF01030C)],
        ),
      );
  @override
  List<Color> get sweepColors =>
      const [Color(0xFFFFB169), Color(0xFFEAF0FF)];

  /// The impact point is the composition's anchor, so the nebula keeps its
  /// radial geometry and only its two colours move.
  @override
  Decoration themedBackdrop(IdentPalette p) => BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(0, -0.20),
          radius: 1.05,
          colors: [Color.lerp(p.base, p.accent, 0.16)!, p.base],
        ),
      );

  @override
  CustomPainter createPainter(
    Animation<double> animation, {
    required bool Function() isTelevision,
    IdentPalette? palette,
  }) =>
      _ColliderPainter(animation, isTelevision: isTelevision, palette: palette);
}

/// One star's place in its disc. Everything here is fixed at layout; the paint
/// pass only evaluates it against progress.
class _Star {
  /// Radius as a fraction of the disc — also what drives tidal stretch, since
  /// the outer disc is what a passing mass tears at first.
  final double f;

  /// Angle at rest: arm index + winding + jitter.
  final double a0;

  /// Per-star angular rate, so the disc shears rather than turning rigidly.
  final double spin;

  /// 0..1, buckets the star into the dim or bright batch.
  final double b;

  const _Star(this.f, this.a0, this.spin, this.b);
}

/// A short ladder of pre-baked shaders standing in for one continuous alpha
/// ramp.
///
/// Baking alpha into a gradient's own stops is the only correct way to fade a
/// shader here (a `Paint.color` alpha over a shader is backend-dependent and
/// banned), but doing it straight off progress mints a native gradient every
/// frame — which is the allocation churn the ident contract forbids. This is
/// the same trade [IdentAlphaSets] makes for text: a handful of steps, built
/// once, indistinguishable from a ramp at reveal speed.
class _Ladder {
  static const int steps = 5;
  final List<Shader> _shaders;

  _Ladder(Shader Function(double alpha) build)
      : _shaders = [for (int i = 1; i <= steps; i++) build(i / steps)];

  /// The step nearest [a], or null when effectively invisible.
  Shader? at(double a) {
    if (a <= 1 / (steps * 2)) return null;
    return _shaders[(a * steps).ceil().clamp(1, steps) - 1];
  }

  /// The full-strength step — the one the resting frame uses.
  Shader get full => _shaders[steps - 1];
}

class _ColliderPainter extends CustomPainter {
  final Animation<double> animation;
  final bool Function() isTelevision;

  /// Null keeps Collider's own warm/cool pairing — the default path.
  final IdentPalette? palette;

  // The two galaxies read as different MATTER, not two tints of one colour:
  // a warm sodium-gold disc against a cold indigo one. Their fusion is what
  // the mark is drawn in.
  static const _ownWarm = Color(0xFFFFB169);
  static const _ownCool = Color(0xFF7C8CFF);
  static const _ownInk = Color(0xFFEAF0FF);

  Color get _warm => palette?.accent ?? _ownWarm;

  /// The cold disc. Under a theme this is the accent turned most of the way
  /// round the wheel rather than mixed toward the ink.
  ///
  /// Mixing was the obvious move and it quietly destroys the ident: the
  /// palette guard in [IdentPalette.fromTheme] scores base↔ink and
  /// base↔accent but never accent↔ink, so on a near-monochrome theme the two
  /// discs converged to one colour and the merger stopped being a collision of
  /// two THINGS — the mark's gradient flattened to a solid fill with them. A
  /// hue rotation keeps the theme's own accent as the warm side while
  /// guaranteeing the cold side stays a different matter in every palette.
  Color get _cool {
    final p = palette;
    if (p == null) return _ownCool;
    final hsl = HSLColor.fromColor(p.accent);
    return hsl
        .withHue((hsl.hue + 155) % 360)
        .withSaturation(hsl.saturation.clamp(0.35, 0.85))
        .withLightness(hsl.lightness.clamp(0.55, 0.78))
        .toColor();
  }

  Color get _ink => palette?.ink ?? _ownInk;

  // ── timeline ───────────────────────────────────────────────────────────
  static const double _t0 = 0.06;
  static const double _shearFrom = 0.28;
  static const double _impact = 0.46;

  /// How long the debris takes to disperse and fade out.
  static const double _debris = 0.34;

  /// How long the blast front takes to cross [_maxR].
  static const double _shockDur = 0.50;

  /// How long one letter takes to settle once the front has reached it.
  static const double _letterDur = 0.15;

  /// The wave's travel law, and its exact inverse.
  ///
  /// These two MUST stay a pair: [_waveEase] places the ring on screen and
  /// [_waveInv] decides when each letter lights, so any drift between them
  /// breaks the one idea this ident is built on. The exponent is low because a
  /// blast wave barely decelerates.
  static const double _waveP = 1.5;
  static double _waveEase(double k) => 1 - pow(1 - k, _waveP).toDouble();
  static double _waveInv(double d) => 1 - pow(1 - d, 1 / _waveP).toDouble();

  Size? _size;
  bool? _lw;

  late double _cx, _cy, _r, _unit;

  /// The distance the front is given [_shockDur] to cross — set from the
  /// WORDMARK's own reach, not from the screen diagonal.
  ///
  /// This is the difference between the concept working and merely being
  /// implemented. Normalised against the diagonal, the whole lockup occupied
  /// about 11% of the wave's travel and sat in the fast opening stretch of it,
  /// so the front crossed all seven letters in ~136ms — four ignition steps
  /// two frames apart, which the eye reads as "they all appeared at once". No
  /// choice of [_waveP] can stretch an 11% slice; the normalisation itself was
  /// the bug. Scaled to the lockup the same geometry spreads the letters over
  /// ~350ms, and it holds across aspect ratios instead of collapsing on the
  /// ones where the diagonal grows faster than the composition.
  late double _maxR;

  late double _ax0, _ay0, _bx0, _by0;
  List<_Star> _sa = const [], _sb = const [];
  late Float32List _aDim, _aBright, _bDim, _bBright;

  late Path _mark, _markInner;
  late Rect _markRect;
  late Shader _markShader;
  late _Ladder _markRamp;

  IdentWordLayout? _word;
  late double _startX, _baseY;
  IdentAlphaSets? _inkSets, _hotSets;
  List<TextPainter>? _shineSet;

  /// Progress at which the blast front reaches each letter, and the earliest
  /// of those — which is NOT `_lit.first`: the front radiates from above the
  /// word's centre, so the MIDDLE letters light first and the leftmost is one
  /// of the last.
  late List<double> _lit;
  late double _litFirst;

  /// Unit-circle gradients placed by canvas transform. Each is a [_Ladder]
  /// because its alpha ramps, and each is authored on the unit circle because
  /// its geometry moves or grows — see [_paintUnitGradient].
  late _Ladder _remnant, _markBloom, _bed, _flash;
  late double _remnantR, _bloomR, _bedW, _bedH;

  /// Cores: fixed alpha, so one cached shader each is enough.
  late Shader _coreWarm, _coreCool;

  _ColliderPainter(this.animation,
      {required this.isTelevision, this.palette})
      : super(repaint: animation);

  void _layout(Size size, bool lightweight) {
    if (_word != null && _size == size && _lw == lightweight) return;
    _size = size;
    _lw = lightweight;
    final w = size.width, h = size.height;
    _unit = identUnit(size);
    _cx = w / 2;
    _cy = h * 0.40;

    // Sized off HEIGHT with a width ceiling, not off `identUnit`.
    //
    // identUnit is min(w/16, h/9), so on anything taller than 16:9 it becomes
    // width-driven while the type below stays height-driven, and the two
    // silently decouple: on a portrait phone the mark had shrunk to the size
    // of a single letter with a third of the screen of dead black under it.
    // Height drives both, so the lockup's proportions hold on every aspect
    // ratio; the width term only bites on narrow surfaces, where it is what
    // keeps the discs inside the bezel.
    _r = min(h * 0.25, w * 0.30);
    final g = min(h * 0.211, w * 0.30);

    // They arrive on a diagonal so the shear axis runs across the frame — two
    // bodies meeting head-on down the horizontal would read as a wipe, not as
    // gravity.
    //
    // The separation yields to the disc radius rather than the other way
    // round: pushed to a fixed fraction of the width, a narrow surface puts
    // half of each disc off-screen, and a reveal whose first frame is clipped
    // never recovers. Tidal tails may still leave frame — that reads as scale
    // — but the discs and their cores must not.
    final sepX = min(w * 0.31, w * 0.46 - _r);
    final sepY = h * 0.20;
    _ax0 = _cx - sepX;
    _ay0 = _cy - sepY;
    _bx0 = _cx + sepX;
    _by0 = _cy + sepY;

    final count = lightweight ? 84 : 175;
    _sa = _disc(count, 11.3);
    _sb = _disc(count, 27.9);
    _aDim = Float32List(count * 4);
    _aBright = Float32List(count * 4);
    _bDim = Float32List(count * 4);
    _bBright = Float32List(count * 4);

    _mark = identPlayPath(g);
    _markInner = identPlayPath(g * 0.52);
    _markRect = Rect.fromCenter(center: Offset.zero, width: g, height: g);
    // The fusion: the mark is literally drawn in both galaxies' colours.
    _markShader =
        LinearGradient(colors: [_warm, _cool]).createShader(_markRect);
    _markRamp = _Ladder((a) => LinearGradient(colors: [
          _warm.withValues(alpha: a),
          _cool.withValues(alpha: a),
        ]).createShader(_markRect));

    _remnantR = g * 3.2;
    _bloomR = g * 1.15;
    _remnant = _Ladder((a) => _unitRadial([
          Color.lerp(_warm, _cool, 0.5)!.withValues(alpha: 0.30 * a),
          Color.lerp(_warm, _cool, 0.5)!.withValues(alpha: 0.10 * a),
          const Color(0x00000000),
        ], const [0.0, 0.45, 1.0]));
    _markBloom = _Ladder((a) => _unitRadial([
          Color.lerp(_warm, Colors.white, 0.45)!.withValues(alpha: 0.42 * a),
          _warm.withValues(alpha: 0.16 * a),
          const Color(0x00000000),
        ], const [0.0, 0.42, 1.0]));
    _flash = _Ladder((a) => _unitRadial([
          Colors.white.withValues(alpha: 0.92 * a),
          _ink.withValues(alpha: 0.34 * a),
          const Color(0x00000000),
        ], const [0.0, 0.42, 1.0]));
    _coreWarm = _coreGradient(_warm);
    _coreCool = _coreGradient(_cool);

    _word = IdentWordLayout.fit(
      // Heavy and wide: the name is the thing the collision MADE, so it
      // carries mass. Horizon's hairline treatment is the opposite reading —
      // there the mark is what survives, here it is what was forged.
      styleFor: (fz) => TextStyle(
        fontSize: fz,
        fontWeight: FontWeight.w800,
        height: 1.0,
        letterSpacing: 0,
        color: _ink,
      ),
      fontSize: h * 0.115,
      trackingFactor: 0.26,
      maxWidth: w * 0.74,
      scaleX: 1.04,
    );
    _startX = w / 2 - _word!.width / 2;
    _baseY = h * 0.78;
    _inkSets = IdentAlphaSets(_word!, 'ink', _ink);
    _hotSets = IdentAlphaSets(_word!, 'hot', const Color(0xFFFFFFFF));
    _shineSet = _word!.set(
      'shine',
      (s) => s.copyWith(color: Colors.white.withValues(alpha: 0.92)),
    );

    // An ELLIPSE under the word, not a circle. A RadialGradient sizes itself
    // off the rect's shortest side, so the obvious `Rect` twice the word's
    // width described a glow the width of the word's HEIGHT — covering about a
    // quarter of the lockup while the width term did nothing but enlarge a
    // mostly-transparent overdraw. Placed by transform instead, so the bed is
    // as wide as the words it beds.
    _bedW = _word!.width * 0.78;
    _bedH = _word!.fontSize * 1.5;
    _bed = _Ladder((a) => _unitRadial([
          Color.lerp(_cool, _warm, 0.35)!.withValues(alpha: 0.16 * a),
          const Color(0x00000000),
        ], const [0.0, 1.0]));

    // Each letter's ignition is the moment the front reaches it, so the
    // cadence falls out of the geometry instead of a hand-tuned stagger.
    // Inverting the wave law is exact, and doing it here keeps the paint pass
    // free of roots.
    final ly = _baseY - _word!.fontSize * 0.34;
    double far = 0;
    final dists = <double>[];
    for (int i = 0; i < kIdentWord.length; i++) {
      final lx = _startX + _word!.lefts[i] + _word!.widths[i] / 2;
      final dx = lx - _cx, dy = ly - _cy;
      final d = sqrt(dx * dx + dy * dy);
      dists.add(d);
      if (d > far) far = d;
    }
    // The wave is given a quarter more reach than the furthest letter needs,
    // so the front is still travelling (and visible) as the last letter lights
    // rather than dying on top of it.
    _maxR = far * 1.25;
    _lit = [
      for (final d in dists)
        _impact + _waveInv(identClamp(d / _maxR, 0, 0.97)) * _shockDur,
    ];
    _litFirst = _lit.reduce(min);
  }

  static Shader _unitRadial(List<Color> colors, List<double> stops) =>
      RadialGradient(colors: colors, stops: stops)
          .createShader(const Rect.fromLTRB(-1, -1, 1, 1));

  static Shader _coreGradient(Color c) => RadialGradient(
        colors: [
          Colors.white.withValues(alpha: 0.95),
          c.withValues(alpha: 0.85),
          c.withValues(alpha: 0.22),
          const Color(0x00000000),
        ],
        stops: const [0.0, 0.30, 0.60, 1.0],
      ).createShader(const Rect.fromLTRB(-1, -1, 1, 1));

  /// One spiral disc: two arms plus a bright, tight core.
  List<_Star> _disc(int count, double seed) => [
        for (int i = 0; i < count; i++)
          () {
            final n1 = identNoise(seed + i * 3.1);
            final n2 = identNoise(seed + i * 5.7);
            final n3 = identNoise(seed + i * 7.3);
            final n4 = identNoise(seed + i * 9.9);
            // Square-rooted so stars distribute by AREA — an even spread in
            // `f` piles everything into the rim and the disc reads as a ring.
            final f = 0.10 + sqrt(n1) * 0.90;
            final arm = (i % 2) * pi;
            return _Star(
              f,
              arm + f * 2.6 + (n2 - 0.5) * 0.85,
              0.75 + n3 * 0.7,
              // The core is where a galaxy's light actually is.
              f < 0.3 ? 0.75 + n4 * 0.25 : n4,
            );
          }(),
      ];

  /// Draws a unit-circle gradient centred at [c], scaled to [rx] × [ry].
  ///
  /// Shaders live in canvas space, so a gradient authored once on the unit
  /// circle can be translated and scaled anywhere — which is what makes a
  /// genuinely smooth, MOVING glow affordable on a TV. Stacking translucent
  /// circles leaves a hard edge at every step, and a blur is banned on that
  /// path.
  void _paintUnitGradient(
    Canvas canvas,
    Shader shader,
    Offset c,
    double rx, [
    double? ry,
  ]) {
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.scale(rx, ry ?? rx);
    canvas.drawCircle(Offset.zero, 1, Paint()..shader = shader);
    canvas.restore();
  }

  /// Fills one disc's two streak buffers and batches them into two draws.
  ///
  /// [shear] stretches every star along the axis toward the other core, scaled
  /// by its own projection onto that axis — which produces the leading bridge
  /// and the trailing tail from a single term, the way tides actually work.
  ///
  /// Named rather than positional: the two call sites differ only in a run of
  /// bare doubles, and a transposed pair there would be silent.
  void _paintDisc(
    Canvas canvas, {
    required List<_Star> stars,
    required Float32List dimBuf,
    required Float32List brightBuf,
    required double gx,
    required double gy,
    required double axisX,
    required double axisY,
    required double shear,
    required double spinPhase,
    required double tiltCos,
    required double tiltSin,
    required double squash,
    required double blast,
    required double streak,
    required double fade,
    required Color dim,
    required Color bright,
  }) {
    final flung = blast > 0;
    int di = 0, bi = 0;
    for (final s in stars) {
      final ang = s.a0 + spinPhase * s.spin;
      final r = s.f * _r;
      var lx = cos(ang) * r;
      var ly = sin(ang) * r * squash;
      if (shear > 0) {
        final proj = lx * axisX + ly * axisY;
        lx += axisX * proj * shear;
        ly += axisY * proj * shear;
      }
      // Dispersal: push outward along the star's own radius vector, which is
      // a scale rather than a normalise — no square root in the hot loop.
      if (flung) {
        final k = 1 + blast / (s.f + 0.12);
        lx *= k;
        ly *= k;
      }
      final x = gx + lx * tiltCos - ly * tiltSin;
      final y = gy + lx * tiltSin + ly * tiltCos;

      // Motion streak: orbital while bound, radial once the merger throws it.
      final mx = flung ? cos(ang) : -sin(ang);
      final my = (flung ? sin(ang) : cos(ang)) * squash;
      final dx = (mx * tiltCos - my * tiltSin) * streak;
      final dy = (mx * tiltSin + my * tiltCos) * streak;

      if (s.b < 0.62) {
        dimBuf[di++] = x;
        dimBuf[di++] = y;
        dimBuf[di++] = x - dx;
        dimBuf[di++] = y - dy;
      } else {
        brightBuf[bi++] = x;
        brightBuf[bi++] = y;
        brightBuf[bi++] = x - dx;
        brightBuf[bi++] = y - dy;
      }
    }
    if (di > 0) {
      canvas.drawRawPoints(
        ui.PointMode.lines,
        Float32List.sublistView(dimBuf, 0, di),
        Paint()
          ..strokeWidth = 1
          ..color = dim.withValues(alpha: dim.a * fade),
      );
    }
    if (bi > 0) {
      canvas.drawRawPoints(
        ui.PointMode.lines,
        Float32List.sublistView(brightBuf, 0, bi),
        Paint()
          ..strokeWidth = 1.5
          ..color = bright.withValues(alpha: bright.a * fade),
      );
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final t = animation.value;
    final lightweight = isTelevision();
    _layout(size, lightweight);
    if (t < _t0) return; // one dark beat before anything moves

    // ── the fall ─────────────────────────────────────────────────────────
    final fall = identClamp((t - _t0) / (_impact - _t0), 0, 1);
    // Gravity, not a slide: almost nothing happens for the first half of the
    // approach and the last stretch is violent.
    final e = identInCubic(fall);
    final gax = identLerp(_ax0, _cx, e), gay = identLerp(_ay0, _cy, e);
    final gbx = identLerp(_bx0, _cx, e), gby = identLerp(_by0, _cy, e);

    final post = t > _impact ? identClamp((t - _impact) / _debris, 0, 1) : 0.0;
    final blast = post > 0 ? identOutCubic(post) * 2.4 : 0.0;
    final fade = post > 0 ? (1 - post) : 1.0;

    if (fade > 0.01) {
      // Axis between the cores, normalised. Once merged it is degenerate, so
      // the shear term is retired at impact anyway.
      var axX = gbx - gax, axY = gby - gay;
      final len = sqrt(axX * axX + axY * axY);
      if (len > 0.001) {
        axX /= len;
        axY /= len;
      }
      final shear = identClamp((t - _shearFrom) / (_impact - _shearFrom), 0, 1);
      final spin = e * 3.1 + fall * 0.9;
      final streak = _unit * (0.10 + 0.55 * e + 1.9 * post);

      _paintDisc(
        canvas,
        stars: _sa,
        dimBuf: _aDim,
        brightBuf: _aBright,
        gx: gax,
        gy: gay,
        axisX: axX,
        axisY: axY,
        shear: shear * 1.35,
        spinPhase: spin,
        tiltCos: 0.94,
        tiltSin: 0.34,
        squash: 0.42,
        blast: blast,
        streak: streak,
        fade: fade,
        dim: _warm.withValues(alpha: 0.42),
        bright: _warm.withValues(alpha: 0.95),
      );
      _paintDisc(
        canvas,
        stars: _sb,
        dimBuf: _bDim,
        brightBuf: _bBright,
        gx: gbx,
        gy: gby,
        axisX: -axX,
        axisY: -axY,
        shear: shear * 1.35,
        spinPhase: -spin,
        tiltCos: 0.87,
        tiltSin: -0.49,
        squash: 0.38,
        blast: blast,
        streak: streak,
        fade: fade,
        dim: _cool.withValues(alpha: 0.40),
        bright: _cool.withValues(alpha: 0.92),
      );

      // Cores. They swell as they fall and are consumed by the flash, whose
      // bright inner stop is deliberately wider than the core they replace so
      // no frame shows an uncovered edge.
      if (post <= 0) {
        final cr = _unit * (0.55 + 0.55 * e);
        _paintUnitGradient(canvas, _coreWarm, Offset(gax, gay), cr);
        _paintUnitGradient(canvas, _coreCool, Offset(gbx, gby), cr);
      }
    }

    // ── impact ───────────────────────────────────────────────────────────
    final ft = identClamp((t - _impact) / 0.13, 0, 1);
    // `t > _impact` is load-bearing, not belt-and-braces: before impact the
    // clamp pins ft at 0, and the ladder is indexed by `1 - ft` — so a guard
    // on ft alone paints the flash at FULL strength through the entire
    // approach, which is a white sun sitting where the collision has not
    // happened yet.
    if (t > _impact && ft < 1) {
      final fs = _flash.at(1 - ft);
      if (fs != null) {
        _paintUnitGradient(
            canvas, fs, Offset(_cx, _cy), _unit * (3.5 + 9 * ft));
      }
    }

    // The blast front — the clock every letter below is set by. A trailing
    // wave behind it gives the front depth.
    if (t > _impact) {
      final k = identClamp((t - _impact) / _shockDur, 0, 1);
      for (int ring = 0; ring < 2; ring++) {
        // The trailing ring is DELAYED, not slowed. Scaling its rate instead
        // meant it saturated at 0.62 of the travel and never reached the exit
        // — leaving a full-frame circle at 0.0202 alpha against a 0.02 cutoff,
        // frozen into the resting frame and held there for the whole cold-start
        // hold. A delay reaches 1 exactly when the leader does, so both retire.
        final rk = ring == 0 ? k : identClamp((k - 0.16) / 0.84, 0, 1);
        if (rk <= 0 || rk >= 1) continue;
        final rr = _maxR * _waveEase(rk);
        // Squared falloff: a full-frame ring held at even alpha reads as a
        // drawn circle sitting on the picture rather than as energy leaving.
        final a = pow(1 - rk, 2.0).toDouble() * (ring == 0 ? 0.42 : 0.14);
        if (a < 0.02) continue;
        // A front is a soft band with a bright edge, never a keyline. One
        // blurred pass off TV, a three-step width ladder on it — a single
        // hairline at this diameter reads as a circle SHAPE laid over the
        // picture, which is the tell that gives away vector art.
        if (!lightweight) {
          canvas.drawCircle(
            Offset(_cx, _cy),
            rr,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = _unit * 0.34
              ..color = Color.lerp(_warm, Colors.white, 0.5)!
                  .withValues(alpha: a * 0.45)
              ..maskFilter = MaskFilter.blur(BlurStyle.normal, _unit * 0.5),
          );
          canvas.drawCircle(
            Offset(_cx, _cy),
            rr,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = _unit * 0.05
              ..color = _ink.withValues(alpha: a * 0.75),
          );
        } else {
          const widths = <double>[0.62, 0.28, 0.09];
          const alphas = <double>[0.16, 0.32, 0.80];
          for (int s = 0; s < widths.length; s++) {
            canvas.drawCircle(
              Offset(_cx, _cy),
              rr,
              Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = _unit * widths[s]
                ..color = _ink.withValues(alpha: a * alphas[s]),
            );
          }
        }
      }
    }

    // The remnant the mark comes to rest in.
    final rem = identClamp((t - _impact) / 0.20, 0, 1);
    if (rem > 0) {
      final rs = rem >= 1 ? _remnant.full : _remnant.at(rem);
      if (rs != null) {
        _paintUnitGradient(canvas, rs, Offset(_cx, _cy), _remnantR);
      }
    }

    // ── the mark ─────────────────────────────────────────────────────────
    final ma = identClamp((t - _impact - 0.04) / 0.16, 0, 1);
    if (ma > 0) {
      final bs = ma >= 1 ? _markBloom.full : _markBloom.at(ma);
      if (bs != null) {
        _paintUnitGradient(canvas, bs, Offset(_cx, _cy), _bloomR);
      }
      canvas.save();
      canvas.translate(_cx, _cy);
      if (!lightweight) {
        // Off TV a real blur can hug the triangle's silhouette, which a radial
        // fill cannot — worth the one masked pass where it is cheap. Hot, not
        // averaged: warm and cool are near-complements, so their midpoint
        // desaturates to a mauve grey that reads as pencil rather than light.
        identGlowPath(
          canvas,
          _mark,
          Color.lerp(_warm, Colors.white, 0.35)!.withValues(alpha: 0.4 * ma),
          _unit * 0.2,
          lightweight: false,
        );
      }
      canvas.drawPath(
        _mark,
        Paint()..shader = ma >= 1 ? _markShader : _markRamp.at(ma)!,
      );
      canvas.drawPath(
        _markInner,
        Paint()..color = Colors.white.withValues(alpha: 0.18 * ma),
      );
      canvas.restore();
    }

    // ── the name ─────────────────────────────────────────────────────────
    final word = _word!;
    // Keyed to the EARLIEST ignition, which is a middle letter — the front
    // comes from above the word's centre, so `_lit.first` (the leftmost) is
    // one of the LAST and the bed would have arrived a second after the type
    // it exists to seat.
    final bedA = identClamp((t - _litFirst) / 0.22, 0, 1);
    if (bedA > 0) {
      final bs = bedA >= 1 ? _bed.full : _bed.at(bedA);
      if (bs != null) {
        _paintUnitGradient(
          canvas,
          bs,
          Offset(_cx, _baseY - word.fontSize * 0.34),
          _bedW,
          _bedH,
        );
      }
    }

    for (int i = 0; i < kIdentWord.length; i++) {
      final lt = identClamp((t - _lit[i]) / _letterDur, 0, 1);
      if (lt <= 0) continue;
      final o = identOutQuint(lt);
      final dy = (1 - o) * word.fontSize * 0.10;
      final scale = identLerp(1.16, 1, o);
      final set = _inkSets!.at(o);
      if (set != null) {
        // The front hands the letter its energy: it arrives slightly oversized
        // and settles as the wave passes through.
        word.paintLetter(canvas, set, i, _startX, _baseY, dy: dy, scale: scale);
      }
      // The heat, cooling out of it. Drawn over the ink rather than blended
      // into it, so neither set is ever re-laid-out.
      final hot = _hotSets!.at((1 - lt) * 0.9);
      if (hot != null) {
        word.paintLetter(canvas, hot, i, _startX, _baseY, dy: dy, scale: scale);
      }
    }

    // One specular pass across the finished lockup, gone before rest.
    final sh = identClamp((t - 0.90) / 0.09, 0, 1);
    if (sh > 0 && sh < 1) {
      final bw = word.width * 0.17;
      final x = _startX + identLerp(-bw * 1.6, word.width + bw * 0.6, sh);
      final top = _baseY - word.fontSize * 1.06;
      final bottom = _baseY + word.fontSize * 0.26;
      final skew = word.fontSize * 0.34;
      final band = Path()
        ..moveTo(x, top)
        ..lineTo(x + bw, top)
        ..lineTo(x + bw - skew, bottom)
        ..lineTo(x - skew, bottom)
        ..close();
      canvas.save();
      canvas.clipPath(band);
      for (int i = 0; i < kIdentWord.length; i++) {
        word.paintLetter(canvas, _shineSet!, i, _startX, _baseY);
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ColliderPainter old) =>
      old.animation != animation;
}
