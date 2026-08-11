import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../utils/platform_util.dart';
import 'app_surfaces.dart';
import 'app_theme_scope.dart';

/// The theme's whole-page texture — film grain and Blueprint's rule — promoted
/// from the details page to the app.
///
/// Both are properties of the PAGE, not of any widget on it, so they belong at
/// one insertion point rather than being reproduced by every screen. That is
/// how the details page already does it (`DetailAtmosphere`); this is the same
/// idea one level up, with three things that version does not have.
///
/// ## 1 · It cannot paint over a frozen surface
///
/// The scope lives above the root Navigator (`main.dart`), so a naive layer
/// there would texture the permanently-legacy player and the frozen launch
/// ident — surfaces that deliberately do not follow the palette. [AppTexture]
/// therefore listens to [AppSurfaceState] and paints **nothing** while the
/// active surface is frozen. That signal already exists for exactly this class
/// of question (it is what system-bar ownership reads), so this adds a
/// consumer rather than a mechanism.
///
/// ## 2 · The grain is batched, not thousands of draw calls
///
/// `_GrainPainter` on the details page issues up to 3,000 `drawRect` calls per
/// repaint. Here the speck positions are computed ONCE into a reused
/// [Float32List] and emitted with a single [Canvas.drawRawPoints] — the idiom
/// the launch idents already use for starfields, and the reason they hold
/// frame on an Amlogic box.
///
/// [PointMode.points] with a square cap and a `strokeWidth` of **one logical
/// pixel** reproduces the 1×1 logical rect the old painter drew — not a round
/// dot, and not a physical pixel. An earlier version divided by DPR, which
/// made every speck a quarter of its area on a 2× screen.
///
/// Because both the positions and the stroke are logical, nothing about the
/// grain depends on device pixel ratio, so the buffer is keyed on
/// `(size, grain)` alone. (The one surviving difference from the rect: a point
/// is centred on its coordinate where a rect starts there, so the field is
/// shifted half a pixel. On a random speck field that is not observable.)
///
/// ## 3 · The grid follows the same platform policy as the grain
///
/// The details page gates grain off on TV and leaves the grid on. A
/// full-screen rule composited over everything that scrolls beneath it is not
/// free on a 2 GB box, so app-wide both follow [ShapeTokens.gridFor] /
/// [ShapeTokens.grainFor].
class AppTexture extends StatelessWidget {
  final Widget child;

  const AppTexture({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    // `isTelevision`, not `isAndroidTvCached`: the Apple TV port is a
    // television by every measure this policy cares about, and gating on the
    // Android-only probe left Sepia's grain and Blueprint's rule running on
    // tvOS — a full-screen per-frame layer on exactly the hardware the
    // policy exists to protect.
    final tv = PlatformUtil.isTelevision;
    final grain = app.shape.grainFor(tv);
    final grid = app.shape.gridFor(tv);
    // Nothing to draw for legacy or for the seventeen themes that declare
    // neither — no listener, no painter, no layer.
    if (!grid && grain <= 0) return child;

    return ListenableBuilder(
      listenable: AppSurfaceState.instance,
      builder: (context, _) {
        // A frozen surface owns its own look. Rebuilding to `child` unchanged
        // also drops the painters entirely rather than drawing transparent
        // ones.
        if (AppSurfaceState.instance.active == SurfaceKind.frozen) {
          return child;
        }
        return CustomPaint(
          painter: grid ? GridPainter(app.core.hair) : null,
          foregroundPainter: grain > 0 ? GrainPainter(grain, app.core.tx) : null,
          // Tells `DetailAtmosphere` to stand down. Without it a details page
          // under a grain theme is grained twice — once here and once there —
          // which doubles the speck density and draws Blueprint's rule over
          // itself. The rule, stated in full on `DetailAtmosphere`: when the
          // APP theme declares a texture it owns every page, and the details
          // page's own texture applies only where the app has none.
          child: AppTexturePainting(child: child),
        );
      },
      child: child,
    );
  }
}

/// Blueprint's 32px rule.
@visibleForTesting
class GridPainter extends CustomPainter {
  final Color color;
  const GridPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (var x = 0.0; x < size.width; x += 32) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    }
    for (var y = 0.0; y < size.height; y += 32) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
  }

  @override
  bool shouldRepaint(GridPainter old) => old.color != color;
}

/// Film grain, as one batched point draw.
@visibleForTesting
class GrainPainter extends CustomPainter {
  final double strength;
  final Color ink;

  GrainPainter(this.strength, this.ink);

  /// Speck fields, keyed by `(size, grain)`.
  ///
  /// A map rather than a single slot because two texture layers can be alive
  /// at different sizes — the shell's and a details page's, or two desktop
  /// windows — and a one-entry cache would have them evict each other on
  /// every frame. Bounded at [_maxCached] entries, dropped oldest-first: the
  /// realistic worst case is a handful of sizes across a rotation.
  static final Map<String, Float32List> _cache = <String, Float32List>{};
  static const int _maxCached = 4;

  /// One speck per ~900 logical px², the density the details page uses,
  /// capped so a desktop window cannot ask for a hundred thousand points.
  static const int _maxSpecks = 3000;

  static Float32List _points(Size size, double grain) {
    final key = '${size.width}x${size.height}@$grain';
    final hit = _cache[key];
    if (hit != null) return hit;
    // A FIXED seed: grain that reshuffles on every repaint reads as a broken
    // signal rather than as film.
    final rnd = math.Random(7);
    final count =
        (size.width * size.height / 900).clamp(0, _maxSpecks.toDouble()).toInt();
    final buf = Float32List(count * 2);
    for (var i = 0; i < count; i++) {
      buf[i * 2] = rnd.nextDouble() * size.width;
      buf[i * 2 + 1] = rnd.nextDouble() * size.height;
    }
    if (_cache.length >= _maxCached) _cache.remove(_cache.keys.first);
    _cache[key] = buf;
    return buf;
  }

  /// TEST-ONLY: the field for a key, so a test can assert the cache without
  /// the painter growing a public accessor.
  @visibleForTesting
  static Float32List? debugFieldFor(Size size, double grain) =>
      _cache['${size.width}x${size.height}@$grain'];

  /// TEST-ONLY: how many fields are held right now.
  @visibleForTesting
  static int get debugCacheSize => _cache.length;

  /// TEST-ONLY: forget every field so a test can assert on rebuilds.
  @visibleForTesting
  static void debugResetCache() => _cache.clear();

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final pts = _points(size, strength);
    if (pts.isEmpty) return;
    final paint = Paint()
      ..color = ink.withValues(alpha: strength)
      // ONE LOGICAL pixel, square — the same 1×1 logical rect the old painter
      // drew. Not `1 / dpr`: that made each speck a quarter of its area on a
      // 2× screen.
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.square;
    canvas.drawRawPoints(ui.PointMode.points, pts, paint);
  }

  @override
  bool shouldRepaint(GrainPainter old) =>
      old.strength != strength || old.ink != ink;
}

/// Marks the subtree where [AppTexture] is already painting.
///
/// Read by `DetailAtmosphere`, which draws the same two textures for the
/// details page and must not double them up when the shell has it covered.
class AppTexturePainting extends InheritedWidget {
  const AppTexturePainting({super.key, required super.child});

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppTexturePainting>() != null;

  @override
  bool updateShouldNotify(AppTexturePainting oldWidget) => false;
}
