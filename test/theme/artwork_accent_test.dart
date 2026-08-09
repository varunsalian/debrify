import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/artwork_accent.dart';
import 'package:debrify/widgets/detail/theme/detail_themes.dart';

/// The artwork accent's three dangerous properties: it must not contaminate a
/// fixed-palette theme, it must stay legible on a paper ground, and its scope
/// must survive being captured into a dialog.
void main() {
  double ratio(Color a, Color b) {
    final la = a.withValues(alpha: 1).computeLuminance();
    final lb = b.withValues(alpha: 1).computeLuminance();
    final hi = la > lb ? la : lb;
    final lo = la > lb ? lb : la;
    return (hi + 0.05) / (lo + 0.05);
  }

  group('resolve', () {
    const artwork = Color(0xFF2E86DE);

    testWidgets('a theme that invites the artwork gets it', (tester) async {
      // Signal is the only theme with useArtworkAccent — the shipped look has
      // always taken its accent from the poster.
      final app = AppTheme.fromDetail(DetailThemes.signal);
      late Color got;
      await tester.pumpWidget(
        ArtworkAccentScope(
          accent: artwork,
          child: Builder(builder: (c) {
            got = ArtworkAccentScope.resolve(c, app);
            return const SizedBox();
          }),
        ),
      );
      expect(got, artwork);
    });

    testWidgets('a fixed-palette theme is NEVER contaminated', (tester) async {
      // Noir's white and Phosphor's amber ARE the theme. An arbitrary poster
      // colour landing there would not be a per-title accent, it would be the
      // theme failing to be itself. The gate lives in `resolve` rather than at
      // each call site so a consumer cannot forget it.
      for (final id in ['noir', 'phosphor', 'blueprint', 'broadsheet']) {
        final app = AppTheme.fromDetail(DetailThemes.byId(id));
        late Color got;
        await tester.pumpWidget(
          ArtworkAccentScope(
            accent: artwork,
            child: Builder(builder: (c) {
              got = ArtworkAccentScope.resolve(c, app);
              return const SizedBox();
            }),
          ),
        );
        expect(got, app.core.accent, reason: id);
        expect(got, isNot(artwork), reason: id);
      }
    });

    testWidgets('falls back when there is no artwork', (tester) async {
      final app = AppTheme.fromDetail(DetailThemes.signal);
      late Color got;
      await tester.pumpWidget(
        ArtworkAccentScope(
          accent: null,
          child: Builder(builder: (c) {
            got = ArtworkAccentScope.resolve(c, app);
            return const SizedBox();
          }),
        ),
      );
      expect(got, app.core.accent);
    });

    testWidgets('a caller may name the subprofile accent it normally uses',
        (tester) async {
      final app = AppTheme.fromDetail(DetailThemes.signal);
      late Color got;
      await tester.pumpWidget(
        Builder(builder: (c) {
          got = ArtworkAccentScope.resolve(c, app, fallback: app.cloud.accent);
          return const SizedBox();
        }),
      );
      expect(got, app.cloud.accent,
          reason: 'no scope at all must fall back, not throw');
    });
  });

  testWidgets('the scope survives capture into a dialog', (tester) async {
    // An InheritedTheme, not a plain InheritedWidget: `InheritedTheme.capture`
    // silently SKIPS plain inherited widgets, so a sheet raised from a themed
    // page would lose the accent. This is the test that would have caught the
    // original design mistake.
    const artwork = Color(0xFF2E86DE);
    Color? insideDialog;
    await tester.pumpWidget(
      MaterialApp(
        home: ArtworkAccentScope(
          accent: artwork,
          child: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (c) {
                  insideDialog = ArtworkAccentScope.of(c);
                  return const SizedBox();
                },
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(insideDialog, artwork);
  });

  group('normalisation against the ground', () {
    // extractDominantColor normalises for a DARK ui (saturation ≥ 0.45, value
    // 0.55–0.85). On the two paper themes that lands somewhere illegible, so
    // the colour is re-targeted against the ground it will actually be on.
    const posters = [
      Color(0xFF2E86DE), // blue
      Color(0xFFD64541), // red
      Color(0xFFF1C40F), // yellow
      Color(0xFF27AE60), // green
      Color(0xFF8E44AD), // purple
    ];

    test('every poster colour reads on every theme ground', () {
      for (final core in DetailThemes.all) {
        final app = AppTheme.fromDetail(core);
        for (final raw in posters) {
          final out = normaliseAccentFor(raw, app);
          // 2.9, not 3.0: `normaliseAccentFor` accepts anything already at
          // 3:1 and repairs the rest toward 4.5:1, and the bisection lands
          // within a hair of its target. The bar here is the ACCEPTANCE one
          // with a rounding allowance, not the repair target.
          expect(
            ratio(out, app.core.ground),
            greaterThanOrEqualTo(2.9),
            reason: '${core.id}: $raw normalised to $out',
          );
        }
      }
    });

    test('a colour that already reads is left alone', () {
      // Hue and saturation are the artwork's contribution; moving them when
      // there is no legibility problem would just make every poster the same
      // colour.
      final dark = AppTheme.fromDetail(DetailThemes.signal);
      const bright = Color(0xFF6EC1FF);
      expect(normaliseAccentFor(bright, dark), bright);
    });

    test('hue is preserved when it does move', () {
      final paper = AppTheme.fromDetail(DetailThemes.byId('broadsheet'));
      for (final raw in posters) {
        final out = normaliseAccentFor(raw, paper);
        final inHue = HSLColor.fromColor(raw).hue;
        final outHue = HSLColor.fromColor(out).hue;
        expect((inHue - outHue).abs(), lessThan(1.0),
            reason: 'the artwork\'s hue is the whole point of the feature');
      }
    });
  });

  group('cache policy', () {
    // Deliberately NOT through `of()`. Extraction is real engine work — image
    // resolution never completes under the test binding's clock, so a test
    // that decodes hangs instead of failing. What has bugs in it is the
    // POLICY: bounded size, oldest evicted, a re-read counting as young. That
    // is what these exercise.
    setUp(DominantColorCache.debugClear);

    test('is bounded, and drops the OLDEST first', () {
      for (var i = 0; i < 70; i++) {
        DominantColorCache.debugPut('u$i', const Color(0xFF112233));
      }
      expect(DominantColorCache.debugSize, 64);
      expect(DominantColorCache.debugKeys.first, 'u6');
      expect(DominantColorCache.debugKeys.last, 'u69');
    });

    test('a re-read moves a key to the young end', () {
      for (var i = 0; i < 64; i++) {
        DominantColorCache.debugPut('u$i', const Color(0xFF112233));
      }
      DominantColorCache.debugTouch('u0');
      DominantColorCache.debugPut('new', const Color(0xFF445566));
      expect(DominantColorCache.debugKeys, contains('u0'),
          reason: 'the key just read must not be the one evicted');
      expect(DominantColorCache.debugKeys, isNot(contains('u1')));
    });

    test('a NULL answer is remembered too', () {
      // The black-and-white-poster case. Without this the extractor re-runs on
      // every visit for exactly the titles that will never yield a colour.
      DominantColorCache.debugPut('bw', null);
      expect(DominantColorCache.debugSize, 1);
      expect(DominantColorCache.debugKeys, ['bw']);
    });
  });
}
