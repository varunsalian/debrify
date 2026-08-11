import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:debrify/theme/app_surfaces.dart';
import 'package:debrify/theme/app_texture.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:debrify/widgets/detail/detail_style.dart';
import 'package:debrify/widgets/detail/theme/detail_theme.dart';
import 'package:debrify/widgets/detail/theme/detail_themes.dart';

/// The texture layer's two dangerous properties: it sits above the root
/// Navigator, so it must never paint over a frozen surface; and it paints
/// thousands of specks, so its buffer must be cached on the right key.
void main() {
  setUp(() {
    AppSurfaceState.instance.reset();
    GrainPainter.debugResetCache();
  });

  Future<void> pumpTexture(WidgetTester tester, AppTheme theme) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AppThemeScope(
          theme: theme,
          child: const AppTexture(child: SizedBox.expand()),
        ),
      ),
    );
  }

  group('containment', () {
    testWidgets('legacy paints no texture layer at all', (tester) async {
      await pumpTexture(tester, AppThemes.legacy);
      // Not `findsNothing` on CustomPaint — MaterialApp builds several of its
      // own. What must be absent is a paint carrying OUR painters.
      expect(_texturePaint(tester), isNull,
          reason: 'legacy declares neither grain nor grid, so the layer must '
              'short-circuit entirely rather than paint transparently');
    });

    testWidgets('a theme with neither also short-circuits', (tester) async {
      await pumpTexture(tester, AppTheme.fromDetail(DetailThemes.signal));
      expect(_texturePaint(tester), isNull);
    });

    testWidgets('a grain theme paints while the surface is themed',
        (tester) async {
      AppSurfaceState.instance.publishBootstrap(false);
      AppSurfaceState.instance.publishTab(15); // Home — themed
      await pumpTexture(tester, AppTheme.fromDetail(DetailThemes.byId('sepia')));
      expect(_texturePaint(tester), isNotNull);
    });

    testWidgets('…and stops the moment the surface goes frozen',
        (tester) async {
      AppSurfaceState.instance.publishBootstrap(false);
      AppSurfaceState.instance.publishTab(15);
      await pumpTexture(tester, AppTheme.fromDetail(DetailThemes.byId('sepia')));
      expect(_texturePaint(tester), isNotNull);

      // Tab 0 is the inert frozen slot. In the app the equivalent move is the
      // player being pushed, which publishes the same signal.
      AppSurfaceState.instance.publishTab(0);
      await tester.pump();
      expect(_texturePaint(tester), isNull,
          reason: 'a frozen surface owns its own look — the player must never '
              'be grained');
    });

    testWidgets('nothing paints during bootstrap', (tester) async {
      // The launch ident renders under the bootstrap freeze; texturing it
      // would paint the theme over a surface deliberately outside it.
      AppSurfaceState.instance.publishBootstrap(true);
      await pumpTexture(tester, AppTheme.fromDetail(DetailThemes.byId('sepia')));
      expect(_texturePaint(tester), isNull);
    });

    // The hand-off with the REAL `DetailAtmosphere`, not just the marker.
    // An earlier version of these tests only read `AppTexturePainting.of` in
    // a Builder, which proved the marker existed and nothing about whether
    // the widget that reads it actually stands down.
    Future<void> pumpNested(
      WidgetTester tester, {
      required AppTheme app,
      required String detailId,
    }) async {
      AppSurfaceState.instance.publishBootstrap(false);
      AppSurfaceState.instance.publishTab(15);
      await tester.pumpWidget(
        MaterialApp(
          home: AppThemeScope(
            theme: app,
            child: AppTexture(
              child: DetailThemeScope(
                theme: DetailThemes.byId(detailId),
                child: const DetailAtmosphere(child: SizedBox.expand()),
              ),
            ),
          ),
        ),
      );
    }

    int texturePaints(WidgetTester tester) => tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .where((w) => w.painter is GridPainter || w.foregroundPainter is GrainPainter)
        .length;

    testWidgets('app texture ON: the details page does NOT double it',
        (tester) async {
      // App Blueprint (grid) over detail Sepia (grain). Exactly ONE texture
      // layer must exist, and it is the app's — documented on
      // DetailAtmosphere as "the app theme owns every page".
      await pumpNested(
        tester,
        app: AppTheme.fromDetail(DetailThemes.byId('blueprint')),
        detailId: 'sepia',
      );
      expect(texturePaints(tester), 1);
      final only = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .firstWhere((w) => w.painter is GridPainter ||
              w.foregroundPainter is GrainPainter);
      expect(only.painter, isA<GridPainter>(),
          reason: 'the surviving layer must be the APP theme\'s grid, not '
              'the detail theme\'s grain');
    });

    testWidgets('app texture OFF: the details page keeps its own',
        (tester) async {
      // Legacy app theme — the common case — so Sepia's own grain paints here
      // exactly as it always has.
      await pumpNested(
        tester,
        app: AppThemes.legacy,
        detailId: 'sepia',
      );
      expect(texturePaints(tester), 1);
      final only = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .firstWhere((w) => w.painter is GridPainter ||
              w.foregroundPainter is GrainPainter);
      expect(only.foregroundPainter, isA<GrainPainter>());
    });

    testWidgets('neither paints a texture the platform policy forbids',
        (tester) async {
      // The hole this closes: on TV the app-wide layer suppresses itself, so
      // no marker is installed — and DetailAtmosphere used to go on painting
      // the very full-screen overlay the policy exists to prevent.
      // Flips `isTelevision` via the Android probe, which is what it reads on
      // a non-tvOS host. On the Apple TV port `isTvOS` makes it true anyway —
      // which is the whole point of the gate now being `isTelevision`.
      PlatformUtil.debugSetAndroidTvCached(true);
      addTearDown(() => PlatformUtil.debugSetAndroidTvCached(false));
      await pumpNested(
        tester,
        app: AppTheme.fromDetail(DetailThemes.byId('blueprint')),
        detailId: 'blueprint',
      );
      expect(texturePaints(tester), 0);
    });

    testWidgets('Blueprint paints its rule', (tester) async {
      AppSurfaceState.instance.publishBootstrap(false);
      AppSurfaceState.instance.publishTab(15);
      await pumpTexture(
          tester, AppTheme.fromDetail(DetailThemes.byId('blueprint')));
      expect(_texturePaint(tester)?.painter, isA<GridPainter>());
    });
  });

  group('grain buffer', () {
    test('is reused for the same size and grain', () {
      final a = _pointsFor(const Size(400, 300), 0.09);
      final b = _pointsFor(const Size(400, 300), 0.09);
      expect(identical(a, b), isTrue);
    });

    test('is rebuilt when the size changes', () {
      final a = _pointsFor(const Size(400, 300), 0.09);
      final b = _pointsFor(const Size(401, 300), 0.09);
      expect(identical(a, b), isFalse);
    });

    test('two live sizes do not evict each other', () {
      // The shell's layer and a details page's can be alive at once, and a
      // one-slot cache would have them rebuild ~3,000 points each on every
      // single frame.
      final a = _pointsFor(const Size(400, 300), 0.09);
      final b = _pointsFor(const Size(800, 600), 0.09);
      expect(identical(_pointsFor(const Size(400, 300), 0.09), a), isTrue);
      expect(identical(_pointsFor(const Size(800, 600), 0.09), b), isTrue);
    });

    test('the cache is bounded', () {
      for (var i = 0; i < 12; i++) {
        _pointsFor(Size(100.0 + i, 100), 0.09);
      }
      expect(GrainPainter.debugCacheSize, lessThanOrEqualTo(4));
    });

    test('is deterministic — grain must not reshuffle per frame', () {
      final a = Float32List.fromList(_pointsFor(const Size(400, 300), 0.09));
      GrainPainter.debugResetCache();
      final b = Float32List.fromList(_pointsFor(const Size(400, 300), 0.09));
      expect(a, b,
          reason: 'a moving speck field reads as a broken signal, not as film');
    });

    test('speck count is capped', () {
      // A 4K desktop window would otherwise ask for ~9,000 points.
      final pts = _pointsFor(const Size(3840, 2160), 0.09);
      expect(pts.length ~/ 2, lessThanOrEqualTo(3000));
    });

    test('repainting is decided by the inputs, not by identity', () {
      final a = GrainPainter(0.09, const Color(0xFFFFFFFF));
      expect(a.shouldRepaint(GrainPainter(0.09, const Color(0xFFFFFFFF))),
          isFalse);
      expect(a.shouldRepaint(GrainPainter(0.05, const Color(0xFFFFFFFF))),
          isTrue);
      expect(a.shouldRepaint(GrainPainter(0.09, const Color(0xFF000000))),
          isTrue);
    });
  });
}

/// The texture's own `CustomPaint`, or null when it painted nothing.
///
/// `MaterialApp` builds several `CustomPaint`s of its own, so this looks for
/// one carrying one of the texture's painters rather than for the type.
CustomPaint? _texturePaint(WidgetTester tester) {
  for (final w in tester.widgetList<CustomPaint>(find.byType(CustomPaint))) {
    if (w.painter is GridPainter || w.foregroundPainter is GrainPainter) {
      return w;
    }
  }
  return null;
}

/// Drives the private buffer through a real paint, which is the only public
/// door to it.
Float32List _pointsFor(Size size, double grain) {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  GrainPainter(grain, const Color(0xFFFFFFFF)).paint(canvas, size);
  recorder.endRecording().dispose();
  return GrainPainter.debugFieldFor(size, grain)!;
}
