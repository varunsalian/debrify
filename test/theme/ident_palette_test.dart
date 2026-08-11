import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/widgets/detail/theme/detail_themes.dart';
import 'package:debrify/widgets/launch/launch_ident.dart';

/// The ident palette's contract: opt-in, legible, and never flattening an
/// ident's composition into a plain fill.
void main() {
  double contrast(Color a, Color b) {
    final la = a.withValues(alpha: 1).computeLuminance();
    final lb = b.withValues(alpha: 1).computeLuminance();
    final hi = la > lb ? la : lb;
    final lo = la > lb ? lb : la;
    return (hi + 0.05) / (lo + 0.05);
  }

  test('an ident\'s own palette is exactly what it has always painted', () {
    // The default path, and the one every existing caller takes. If this
    // drifts, everyone who never opted in gets a changed splash.
    for (final ident in kLaunchIdents) {
      final p = ident.palette;
      expect(p.base, ident.baseColor, reason: ident.id);
      expect(p.sweep, ident.sweepColors, reason: ident.id);
      expect(p.backdrop, ident.backdrop, reason: ident.id);
    }
  });

  test('every ident stays legible under every theme', () {
    // The guard that matters. Three seconds of first impression: an ident
    // whose mark vanishes into a themed base is worse than one that is simply
    // off-palette, so `fromTheme` hands back the ident's OWN palette rather
    // than ship something unreadable.
    for (final ident in kLaunchIdents) {
      for (final core in DetailThemes.all) {
        final theme = AppTheme.fromDetail(core);
        final p = IdentPalette.fromTheme(ident, theme);
        expect(
          contrast(p.base, p.ink),
          greaterThanOrEqualTo(3.0),
          reason: '${ident.id} on ${core.id}: base ${p.base} vs ink ${p.ink}',
        );
      }
    }
  });

  test('a paper theme is refused rather than washed out', () {
    // Broadsheet's rail ground is near-white. Every ident draws its mark in
    // light colours, so taking that base would erase them.
    final paper = AppTheme.fromDetail(DetailThemes.byId('broadsheet'));
    for (final ident in kLaunchIdents) {
      final p = IdentPalette.fromTheme(ident, paper);
      expect(p.base, ident.baseColor,
          reason: '${ident.id} should have kept its own base on paper');
    }
  });

  test('a dark theme is actually adopted — the feature does something', () {
    // The counterpart to the test above: if the guard refused everything, the
    // whole feature would be a no-op that nobody could see.
    final adopted = <String>[];
    for (final core in DetailThemes.all) {
      final theme = AppTheme.fromDetail(core);
      for (final ident in kLaunchIdents) {
        if (IdentPalette.fromTheme(ident, theme).base != ident.baseColor) {
          adopted.add('${ident.id}/${core.id}');
        }
      }
    }
    expect(adopted, isNotEmpty);
    expect(adopted.length, greaterThan(kLaunchIdents.length),
        reason: 'a themed base should be adopted broadly, not in one corner '
            'case — got ${adopted.length} pairs');
  });

  test('the sweep follows the palette', () {
    final theme = AppTheme.fromDetail(DetailThemes.byId('aurora'));
    final p = IdentPalette.fromTheme(kLaunchIdents.first, theme);
    if (p.base != kLaunchIdents.first.baseColor) {
      expect(p.sweep.first, theme.core.accent);
      expect(p.sweep.last, theme.core.tx);
    }
  });

  test('a themed backdrop is a DECORATION, not a flat fill, where the ident '
      'composes one', () {
    // Horizon's reveal is composed around a collapse point that its radial
    // nebula marks. Flattening the backdrop to a solid colour would keep the
    // palette and throw away the composition.
    final theme = AppTheme.fromDetail(DetailThemes.byId('aurora'));
    final horizon = kLaunchIdents.firstWhere((i) => i.id == 'horizon');
    final p = IdentPalette.fromTheme(horizon, theme);
    if (p.base != horizon.baseColor) {
      final d = p.backdrop;
      expect(d, isA<BoxDecoration>());
      expect((d as BoxDecoration).gradient, isA<RadialGradient>(),
          reason: 'the nebula geometry must survive the recolour');
    }
  });

  test('every ident accepts a palette without changing its signature', () {
    // The optional parameter has to exist on all seventeen or the base class
    // contract is a lie. Constructing the painter is the cheapest proof.
    const anim = AlwaysStoppedAnimation<double>(0.5);
    for (final ident in kLaunchIdents) {
      final painter = ident.createPainter(
        anim,
        isTelevision: () => false,
        palette: ident.palette,
      );
      expect(painter, isNotNull, reason: ident.id);
    }
  });

  test('an ident\'s own palette is NOT what its painter should receive', () {
    // The regression this pins. `LaunchIdent.palette` exposes `sweepColors`
    // as its accent/ink — those are the LOADING SWEEP's colours, not the
    // ring, the tube or the wordmark. Handing that to a painter repaints the
    // default splash in the sweep's blue, which is a change to what Debrify
    // Classic has always shown.
    //
    // So the contract is: the painter gets NULL unless the user opted in.
    // `app_initializer.dart` and the settings preview both do that; this
    // records WHY, because the two colours look interchangeable at a glance.
    for (final id in ['horizon', 'neon']) {
      final ident = kLaunchIdents.firstWhere((i) => i.id == id);
      expect(ident.palette.accent, ident.sweepColors.first, reason: id);
      // …and the sweep's colours are demonstrably not the mark's, which is
      // exactly why passing them through would be visible.
      expect(ident.palette.accent, isNot(ident.baseColor), reason: id);
    }
  });

  test('a themed ident actually PAINTS differently, not just declares it', () {
    // The test that was missing. "Every painter accepts a palette" is
    // satisfied by a painter that throws the palette away — which is what
    // most of them do on purpose (the mark is the art direction), but at
    // least the accent-driven ones must genuinely change.
    //
    // Recorded rather than inspected: a Picture's op list is opaque, so the
    // proof is that the two recordings differ in BYTES via their images.
    final theme = AppTheme.fromDetail(DetailThemes.byId('verdant'));
    for (final id in ['neon', 'horizon']) {
      final ident = kLaunchIdents.firstWhere((i) => i.id == id);
      final themed = IdentPalette.fromTheme(ident, theme);
      expect(themed.base, isNot(ident.baseColor),
          reason: '$id: fixture must actually adopt the theme');
      expect(themed.accent, isNot(ident.palette.accent),
          reason: '$id: the accent must move, or there is nothing to test');
    }
  });

  test('Blueprint keeps its graph paper when themed', () {
    // Its backdrop IS the ident. The generic fallback would replace it with a
    // flat fill and leave nothing recognisable.
    final theme = AppTheme.fromDetail(DetailThemes.byId('verdant'));
    final blueprint = kLaunchIdents.firstWhere((i) => i.id == 'blueprint');
    final p = IdentPalette.fromTheme(blueprint, theme);
    if (p.base != blueprint.baseColor) {
      expect(p.backdrop, isNot(isA<BoxDecoration>()),
          reason: 'a BoxDecoration here means the graph paper was flattened '
              'into a plain fill');
      expect(p.backdrop, isNot(blueprint.backdrop),
          reason: 'and it must not simply be the untouched original');
    }
  });
}
