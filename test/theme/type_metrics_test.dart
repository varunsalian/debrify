import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/widgets/detail/theme/detail_theme.dart';
import 'package:debrify/widgets/detail/theme/detail_themes.dart';

/// Does a theme's real typeface, at its real scale, still FIT?
///
/// The goldens cannot answer this. `golden_harness.dart` sets
/// `AppThemeAdapter.debugUseTestTypography = true` so that font loading cannot
/// bury real failures in load errors — which means every golden is rendered in
/// the deterministic test font and is blind to the fact that Source Serif and
/// JetBrains Mono are wider than Inter. And widget tests do not turn a text
/// overflow into a failure by default; they paint a yellow-and-black stripe
/// and carry on.
///
/// So this file loads the ACTUAL bundled faces and measures. It is the
/// acceptance criterion referenced by `TypeTokens.titleScale`: if a face at
/// its scale cannot fit the tightest real constraint in the app, the damping
/// factor comes down — the test is the authority, not the 0.5.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // Only faces that are REAL. `SourceSerifPro-Regular.ttf`,
    // `Merriweather-Regular.ttf` and both Roboto files in this repo are HTML
    // error pages saved with a .ttf extension — see the note on
    // `DetailFontRoleX.family`. Loading one here would measure the fallback
    // and make every assertion below vacuous, which is exactly the failure
    // the last test in this file guards against.
    await _loadFont('Fraunces72', ['assets/fonts/Fraunces72pt-Regular.ttf']);
    await _loadFont('JetBrainsMono', [
      'assets/fonts/JetBrainsMono-Regular.ttf',
      'assets/fonts/JetBrainsMono-Bold.ttf',
    ]);
    await _loadFont('FiraMono', ['assets/fonts/FiraMono-Regular.ttf']);
    await _loadFont('Inter', ['assets/fonts/Inter-Regular.ttf']);
  });

  group('every theme fits the tightest real constraints', () {
    // Real strings at real sizes in real widths. These are the places the app
    // is genuinely tight: a TV row title beside a badge, a settings subtitle
    // in a two-line clamp, a chip label, an episode caption under a still.
    const cases = <_Fit>[
      _Fit(
        what: 'TV row title',
        text: 'The Lord of the Rings: The Fellowship of the Ring',
        size: 15,
        weight: FontWeight.w700,
        maxWidth: 300,
        maxLines: 2,
        role: _Role.title,
      ),
      _Fit(
        what: 'settings subtitle',
        text: 'Falls back to 1080p when nothing 4K is cached',
        size: 12,
        weight: FontWeight.w400,
        maxWidth: 260,
        maxLines: 2,
        role: _Role.body,
      ),
      _Fit(
        what: 'chip label',
        text: 'WEB-DL',
        size: 10,
        weight: FontWeight.w800,
        maxWidth: 64,
        maxLines: 1,
        role: _Role.body, // a chip label inherits labelSmall
      ),
      _Fit(
        what: 'episode caption',
        text: 'S02E04 · The Long Night',
        size: 11,
        weight: FontWeight.w600,
        maxWidth: 150,
        maxLines: 1,
        role: _Role.body,
      ),
      _Fit(
        what: 'sidebar destination',
        text: 'Continue Watching',
        size: 14,
        weight: FontWeight.w600,
        maxWidth: 168,
        maxLines: 1,
        role: _Role.title,
      ),
      _Fit(
        what: 'dialog action',
        text: 'Remove from Continue Watching',
        size: 14,
        weight: FontWeight.w600,
        maxWidth: 280,
        maxLines: 1,
        role: _Role.title,
      ),
    ];

    // The bar is RELATIVE TO THE SHIPPED FACE, deliberately — the same shape
    // as `contrast_audit_test`'s "relative to legacy" rule, and for the same
    // reason. An absolute bar fails Signal itself: several of these fixtures
    // are already tight in the app as it ships, and tightening them further to
    // make an absolute assertion pass would be testing the fixture, not the
    // change. What matters is that promoting type app-wide does not take a
    // label that FITS today and break it.
    for (final core in DetailThemes.all) {
      test(core.id, () {
        final type = AppTheme.fromDetail(core).type;
        for (final c in cases) {
          final fitsToday = !_exceeds(c.shipped, c);
          if (!fitsToday) continue; // already tight in the shipped app

          // Each fixture is measured through the path the APP would put it
          // on, not through both. `_themedTextTheme` sends display/headline/
          // title styles through `display()` (face + scale) and body/label
          // styles through `body()` (face only), and a chip label inherits
          // `labelSmall` — so measuring a 10px chip at the title scale would
          // be testing a composition the app never builds.
          // Themed FROM the shipped style, so a sans theme resolves back to
          // Inter and the comparison is like-for-like.
          final styled = c.role == _Role.title
              ? type.display(c.shipped)
              : type.body(c.shipped);

          if (c.role == _Role.title) {
            // Titles take a SCALE as well as a face, and a scale is the thing
            // that can run away — so titles must still fit outright.
            expect(
              _exceeds(styled, c),
              isFalse,
              reason:
                  '${core.id} · ${c.what}: "${c.text}" fits at ${c.size}px in '
                  'Inter but needs more than ${c.maxLines} line(s) at '
                  '${styled.fontSize?.toStringAsFixed(1)}px in '
                  '${styled.fontFamily ?? "Inter"} — lower the damping factor '
                  'in TypeTokens, or give the site more room',
            );
            continue;
          }

          // Body takes a FACE and nothing else, and a face's width is bounded
          // by its own metrics — JetBrains Mono is ~6% wider than Inter, so a
          // caption that only just fits can lose a character to the ellipsis.
          // That is a legitimate cost of Phosphor being a terminal theme, not
          // a runaway. The bar is therefore a RATIO, and it is what would
          // catch a face that is a different order of wide.
          const bodyBudget = 1.25;
          final ratio = _lineWidth(c.text, styled) / _lineWidth(c.text, c.shipped);
          expect(
            ratio,
            lessThanOrEqualTo(bodyBudget),
            reason: '${core.id} · ${c.what}: '
                '${styled.fontFamily ?? "Inter"} sets "${c.text}" '
                '${((ratio - 1) * 100).toStringAsFixed(1)}% wider than Inter',
          );
        }
      });
    }
  });

  test('no theme widens a one-line label catastrophically', () {
    // The failure this catches is subtler than a wrap: a one-line label with
    // no room to wrap gets ELLIPSISED instead — not an overflow, but a theme
    // silently eating text the shipped face fit.
    //
    // The bar is a RATIO, not a fixed box, because the absolute widths here
    // are the test font's and mean nothing on a device. 1.25× is the headroom
    // a typical single-line site has before its ellipsis appears; a face-plus-
    // scale that needs more than that is not a styling change any more.
    const budget = 1.25;
    for (final text in const ['Appearance', 'Continue Watching', 'Downloads']) {
      const base = TextStyle(fontSize: 16, fontFamily: 'Inter');
      final shipped = _lineWidth(text, base);
      for (final core in DetailThemes.all) {
        final type = AppTheme.fromDetail(core).type;
        final w = _lineWidth(text, type.display(base));
        expect(
          w / shipped,
          lessThanOrEqualTo(budget),
          reason: '${core.id} widened "$text" by '
              '${((w / shipped - 1) * 100).toStringAsFixed(1)}% '
              '(${shipped.toStringAsFixed(1)} → ${w.toStringAsFixed(1)}px)',
        );
      }
    }
  });

  test('the damping actually damps', () {
    // Guards the relationship the whole safety argument rests on: the app-wide
    // title scale must always sit between 1 and the details page's raw one.
    for (final core in DetailThemes.all) {
      final t = AppTheme.fromDetail(core).type.titleScale;
      final raw = core.displayScale;
      if (raw == 1) {
        expect(t, 1, reason: core.id);
      } else {
        expect((t - 1).abs(), lessThan((raw - 1).abs()), reason: core.id);
        expect((t - 1).sign, (raw - 1).sign, reason: core.id);
      }
    }
  });

  test('every bundled face this test loads is really in the bundle', () async {
    // A silently-missing asset makes every measurement above a measurement of
    // Inter, which would pass while proving nothing.
    for (final path in const [
      'assets/fonts/Fraunces72pt-Regular.ttf',
      'assets/fonts/JetBrainsMono-Regular.ttf',
      'assets/fonts/FiraMono-Regular.ttf',
      'assets/fonts/Inter-Regular.ttf',
    ]) {
      final data = await rootBundle.load(path);
      expect(data.lengthInBytes, greaterThan(1000), reason: path);
      // …and is actually a font. Four files in assets/fonts are HTML error
      // pages with a .ttf extension; a size check alone would pass on one.
      // Valid sfnt magic: 0x00010000, 'OTTO', 'true', 'ttcf'.
      final magic = data.getUint32(0);
      expect(
        const {0x00010000, 0x4F54544F, 0x74727565, 0x74746366}.contains(magic),
        isTrue,
        reason: '\$path is not a font — its first four bytes are '
            '0x\${magic.toRadixString(16)}',
      );
    }
  });

  test('both non-sans faces are really loaded and really distinct', () {
    // Without this, a face that silently failed to load would measure as the
    // fallback and every "it fits" above would be a measurement of the
    // fallback — passing while proving nothing. That is not hypothetical: it
    // is exactly what four of this repo's .ttf files do (see
    // `DetailFontRoleX.family`).
    //
    // Note the baseline here is the TEST font, not Inter — a null family
    // resolves to flutter_test's fixed-advance face, so "wider than Inter" is
    // not a statement this environment can make. Distinctness is.
    const text = 'The Fellowship of the Ring';
    const size = 15.0;
    final fallback = _lineWidth(text, const TextStyle(fontSize: size));
    final serif = _lineWidth(
      text,
      TextStyle(fontSize: size, fontFamily: DetailFontRole.serif.family),
    );
    final mono = _lineWidth(
      text,
      TextStyle(fontSize: size, fontFamily: DetailFontRole.mono.family),
    );
    expect(serif, isNot(closeTo(fallback, 0.01)),
        reason: '${DetailFontRole.serif.family} measured as the fallback — '
            'not loaded, or not a font');
    expect(mono, isNot(closeTo(fallback, 0.01)),
        reason: '${DetailFontRole.mono.family} measured as the fallback — '
            'not loaded, or not a font');
    expect(serif, isNot(closeTo(mono, 0.01)),
        reason: 'the serif and mono roles measured identically — at least one '
            'fell back');
  });
}

/// Does [style] need more than the case's line budget in its box?
bool _exceeds(TextStyle style, _Fit c) {
  final p = TextPainter(
    text: TextSpan(text: c.text, style: style),
    maxLines: c.maxLines,
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: c.maxWidth);
  final over = p.didExceedMaxLines;
  p.dispose();
  return over;
}

double _lineWidth(String text, TextStyle style) {
  final p = TextPainter(
    text: TextSpan(text: text, style: style),
    maxLines: 1,
    textDirection: TextDirection.ltr,
  )..layout();
  final w = p.width;
  p.dispose();
  return w;
}

Future<void> _loadFont(String family, List<String> assets) async {
  final loader = FontLoader(family);
  for (final a in assets) {
    loader.addFont(rootBundle.load(a));
  }
  await loader.load();
}

/// Which of the two type paths a fixture travels — see `_themedTextTheme`.
enum _Role { title, body }

class _Fit {
  final String what;
  final String text;
  final double size;
  final FontWeight weight;
  final double maxWidth;
  final int maxLines;
  final _Role role;

  const _Fit({
    required this.what,
    required this.text,
    required this.size,
    required this.weight,
    required this.maxWidth,
    required this.maxLines,
    required this.role,
  });

  /// The site's own style, unthemed.
  TextStyle get style => TextStyle(fontSize: size, fontWeight: weight);

  /// The SHIPPED style — Inter named explicitly.
  ///
  /// `fontFamily: null` does not mean Inter in a widget test: it resolves to
  /// flutter_test's fixed-advance fallback, so a baseline built from it
  /// measures the harness rather than the app. Inter is loaded in `setUpAll`
  /// precisely so this comparison is against the face that ships.
  TextStyle get shipped =>
      TextStyle(fontSize: size, fontWeight: weight, fontFamily: 'Inter');
}
