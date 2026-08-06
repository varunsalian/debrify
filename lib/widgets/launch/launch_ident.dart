import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'anamorphic_ident.dart';
import 'aperture_ident.dart';
import 'blueprint_ident.dart';
import 'chrome_ident.dart';
import 'constellation_ident.dart';
import 'drop_bounce_ident.dart';
import 'ember_ident.dart';
import 'horizon_ident.dart';
import 'marquee_ident.dart';
import 'monogram_ident.dart';
import 'neon_ident.dart';
import 'origami_ident.dart';
import 'prism_ident.dart';
import 'rack_focus_ident.dart';
import 'ripple_ident.dart';
import 'silk_ident.dart';
import 'swiss_ident.dart';

/// One selectable launch ident: a full art direction for the splash — its own
/// typography, material and light — not just a motion variant of one lockup.
///
/// The contract every ident must honor (it's what lets the splash double as
/// the cold-start loading screen, see AppInitializer):
///
///  * Anything full-screen and STATIC belongs in [backdrop], which is painted
///    by a DecoratedBox OUTSIDE the painter's RepaintBoundary — it rasters
///    once, not per animation tick. The painter draws only what moves, over
///    a transparent canvas.
///  * The painter is PROGRESS-driven (0..1 from its controller). At progress
///    1.0 the frame is completely STATIC — no time-based noise — because on
///    TV the settled splash is held while Home prepaints behind it.
///  * TV path stays cheap: no saveLayer, no large MaskFilter blurs, batched
///    point/line draws, element counts halved, and every shader/layout cached
///    per (size, TV-flag) — nothing native is created per frame. The shared
///    helpers below encode those idioms; painters should not reinvent them.
abstract class LaunchIdent {
  const LaunchIdent();

  /// Stored pref value.
  String get id;

  /// Picker row title.
  String get label;

  /// Picker row subtitle — the pitch, one line.
  String get subtitle;

  /// Length of the reveal. The splash holds for max(reveal, real init work).
  Duration get revealDuration;

  /// Opaque base behind the painter — also the splash Scaffold color, so any
  /// uncovered edge during the exit fade matches the ident's world.
  Color get baseColor;

  /// The static full-screen backdrop, painted once by a DecoratedBox outside
  /// the painter's RepaintBoundary. Must be fully opaque.
  ///
  /// Typed as [Decoration], not [BoxDecoration], so an ident whose static
  /// field is more than a colour or gradient (Blueprint's graph paper) can
  /// still put it here rather than re-stroking it on every reveal tick.
  Decoration get backdrop => BoxDecoration(color: baseColor);

  /// Loading-sweep gradient while holding for the Home board.
  List<Color> get sweepColors;

  CustomPainter createPainter(
    Animation<double> animation, {
    required bool Function() isTelevision,
  });
}

/// Registry, in picker order. Ids are stable — they are the stored pref —
/// and the FIRST entry is the default (what unknown/unset prefs resolve to).
const List<LaunchIdent> kLaunchIdents = [
  HorizonIdent(),
  DropBounceIdent(),
  MarqueeIdent(),
  PrismIdent(),
  NeonIdent(),
  ChromeIdent(),
  MonogramIdent(),
  // Round 3.
  ApertureIdent(),
  BlueprintIdent(),
  RippleIdent(),
  EmberIdent(),
  SwissIdent(),
  OrigamiIdent(),
  AnamorphicIdent(),
  ConstellationIdent(),
  SilkIdent(),
  RackFocusIdent(),
];

LaunchIdent launchIdentFor(String? id) {
  for (final ident in kLaunchIdents) {
    if (ident.id == id) return ident;
  }
  return kLaunchIdents.first;
}

/// Row caption for the current choice (Appearance row subtitle).
String launchIdentLabel(String? id) => launchIdentFor(id).label;

// ─────────────────────────────────────────────────────────────────────────
// Shared paint helpers
// ─────────────────────────────────────────────────────────────────────────

const String kIdentWord = 'DEBRIFY';

double identClamp(double v, double a, double b) => v < a ? a : (v > b ? b : v);
double identLerp(double a, double b, double t) => a + (b - a) * t;
double identOutCubic(double t) => 1 - pow(1 - t, 3).toDouble();
double identOutQuint(double t) => 1 - pow(1 - t, 5).toDouble();
double identInCubic(double t) => t * t * t;
double identIoSine(double t) => -(cos(pi * t) - 1) / 2;
double identIoCubic(double t) =>
    t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3).toDouble() / 2;

/// One layout unit: 1/16 of the width on 16:9, dropping to the height on
/// anything wider. Sizing every ident off this is what lets one composition
/// hold on a 720p TV box, a portrait phone and a 21:9 panel.
double identUnit(Size size) => min(size.width / 16, size.height / 9);
double identOutBack(double t, [double s = 1.7]) =>
    1 + (s + 1) * pow(t - 1, 3).toDouble() + s * pow(t - 1, 2).toDouble();
double identOutBounce(double t) {
  const n = 7.5625, d = 2.75;
  if (t < 1 / d) return n * t * t;
  if (t < 2 / d) {
    t -= 1.5 / d;
    return n * t * t + 0.75;
  }
  if (t < 2.5 / d) {
    t -= 2.25 / d;
    return n * t * t + 0.9375;
  }
  t -= 2.625 / d;
  return n * t * t + 0.984375;
}

/// Deterministic noise — progress-derived so a frozen progress freezes the
/// frame (the static-at-rest contract), unlike Random or clock time.
double identNoise(double x) {
  final v = sin(x * 127.1) * 43758.5453;
  return v - v.floorToDouble();
}

/// Rounded right-pointing play triangle centred at the origin, inscribed in
/// ±s/2. Same geometry as the shipped splash mark.
Path identPlayPath(double s) {
  final pts = [
    Offset(-0.30 * s, -0.40 * s),
    Offset(-0.30 * s, 0.40 * s),
    Offset(0.43 * s, 0),
  ];
  final r = 0.14 * s;
  final path = Path();
  for (int i = 0; i < 3; i++) {
    final a = pts[i], b = pts[(i + 1) % 3], c = pts[(i + 2) % 3];
    final v1 = a - b, v2 = c - b;
    final l1 = v1.distance == 0 ? 1.0 : v1.distance;
    final l2 = v2.distance == 0 ? 1.0 : v2.distance;
    final t1 = b + v1 * (r / l1), t2 = b + v2 * (r / l2);
    if (i == 0) {
      path.moveTo(t1.dx, t1.dy);
    } else {
      path.lineTo(t1.dx, t1.dy);
    }
    path.quadraticBezierTo(b.dx, b.dy, t2.dx, t2.dy);
  }
  path.close();
  return path;
}

/// Glow idiom: on TV two translucent strokes (the trick shipped in the
/// original splash — no Gaussian over a TV-sized shape), elsewhere a real
/// blur. [radius] is the visual glow reach in logical px.
void identGlowPath(
  Canvas canvas,
  Path path,
  Color color,
  double radius, {
  required bool lightweight,
}) {
  if (lightweight) {
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = radius * 1.4
        ..color = color.withValues(alpha: color.a * 0.35),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = radius * 0.6
        ..color = color.withValues(alpha: color.a * 0.7),
    );
  } else {
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Word machinery
// ─────────────────────────────────────────────────────────────────────────

/// Per-letter layout of DEBRIFY for one type treatment, with any number of
/// pre-laid-out [TextPainter] "sets" (fill variants: base, highlight,
/// reflection…). Everything is laid out ONCE per canvas size and cached by
/// the owning painter — per-frame work is transforms and paint only.
///
/// Continuously-varying text alpha is deliberately NOT supported: mutating a
/// TextPainter's style forces re-layout, and per-letter saveLayer is the TV
/// killer the house rules ban. Fades go through [IdentAlphaSets] (quantized
/// pre-baked steps) or a clip-band reveal instead.
class IdentWordLayout {
  final double fontSize;
  final double tracking;
  final double scaleX;
  final List<double> widths; // visual widths (already ×scaleX)
  final List<double> lefts; // left edge per letter, from 0
  final double width; // total visual width
  final List<double> baselines;
  final Map<String, List<TextPainter>> _sets = {};
  final TextStyle Function(double fontSize) styleFor;

  IdentWordLayout._({
    required this.fontSize,
    required this.tracking,
    required this.scaleX,
    required this.widths,
    required this.lefts,
    required this.width,
    required this.baselines,
    required this.styleFor,
  });

  /// Lays out the word to fit [maxWidth]. [trackingFactor] is tracking as a
  /// fraction of font size.
  factory IdentWordLayout.fit({
    required TextStyle Function(double fontSize) styleFor,
    required double fontSize,
    required double trackingFactor,
    required double maxWidth,
    double scaleX = 1,
  }) {
    List<TextPainter> lay(double fz) => [
          for (final ch in kIdentWord.split(''))
            TextPainter(
              text: TextSpan(text: ch, style: styleFor(fz)),
              textDirection: TextDirection.ltr,
            )..layout(),
        ];
    var fz = fontSize;
    var tps = lay(fz);
    double total() {
      var t = 0.0;
      for (var i = 0; i < tps.length; i++) {
        t += tps[i].width * scaleX;
        if (i < tps.length - 1) t += fz * trackingFactor;
      }
      return t;
    }

    var w = total();
    if (w > maxWidth) {
      fz *= maxWidth / w;
      tps = lay(fz);
      w = total();
    }
    final tracking = fz * trackingFactor;
    final widths = [for (final tp in tps) tp.width * scaleX];
    final lefts = <double>[];
    var x = 0.0;
    for (var i = 0; i < widths.length; i++) {
      lefts.add(x);
      x += widths[i] + tracking;
    }
    final layout = IdentWordLayout._(
      fontSize: fz,
      tracking: tracking,
      scaleX: scaleX,
      widths: widths,
      lefts: lefts,
      width: w,
      baselines: [
        for (final tp in tps)
          tp.computeDistanceToActualBaseline(TextBaseline.alphabetic),
      ],
      styleFor: styleFor,
    );
    layout._sets['base'] = tps;
    return layout;
  }

  /// Registers (or returns) a pre-laid-out variant set. [restyle] receives
  /// the base style at this layout's font size.
  List<TextPainter> set(String name, TextStyle Function(TextStyle) restyle) {
    return _sets.putIfAbsent(
      name,
      () => [
        for (final ch in kIdentWord.split(''))
          TextPainter(
            text: TextSpan(text: ch, style: restyle(styleFor(fontSize))),
            textDirection: TextDirection.ltr,
          )..layout(),
      ],
    );
  }

  List<TextPainter> get base => _sets['base']!;

  /// Paints letter [i] of [tps] with its baseline at ([originX]+lefts[i],
  /// [baselineY]), applying the layout's x-scale plus per-call transform.
  void paintLetter(
    Canvas canvas,
    List<TextPainter> tps,
    int i,
    double originX,
    double baselineY, {
    double dx = 0,
    double dy = 0,
    double scale = 1,
  }) {
    final tp = tps[i];
    canvas.save();
    canvas.translate(originX + lefts[i] + widths[i] / 2 + dx, baselineY + dy);
    canvas.scale(scaleX * scale, scale);
    tp.paint(canvas, Offset(-tp.width / 2, -baselines[i]));
    canvas.restore();
  }
}

/// Quantized alpha steps for text fades — four pre-baked sets instead of a
/// per-frame saveLayer or re-layout. At reveal speeds (150–350 ms) the steps
/// read as a fade.
class IdentAlphaSets {
  static const List<double> steps = [0.25, 0.5, 0.75, 1.0];
  final List<List<TextPainter>> sets;

  IdentAlphaSets(IdentWordLayout layout, String name, Color color)
      : sets = [
          for (final a in steps)
            layout.set(
              '$name-$a',
              (s) => s.copyWith(color: color.withValues(alpha: color.a * a)),
            ),
        ];

  /// The set nearest to [alpha], or null when effectively invisible.
  List<TextPainter>? at(double alpha) {
    if (alpha < 0.125) return null;
    if (alpha < 0.375) return sets[0];
    if (alpha < 0.625) return sets[1];
    if (alpha < 0.875) return sets[2];
    return sets[3];
  }
}

/// Partial stroke of [path] — the dash-draw idiom (Marquee emblem, ring
/// draws).
///
/// NOT for the hot path: [ui.PathMetric.extractPath] mints a fresh native
/// Path on every call, so driving this straight off progress allocates per
/// frame. Pre-extract a quantized ladder of prefixes at layout instead (see
/// Blueprint's `_draw`) and index into it.
void identDrawPathPartial(
  Canvas canvas,
  Path path,
  double t,
  Paint paint,
) {
  if (t <= 0) return;
  if (t >= 1) {
    canvas.drawPath(path, paint);
    return;
  }
  for (final metric in path.computeMetrics()) {
    canvas.drawPath(metric.extractPath(0, metric.length * t), paint);
  }
}
