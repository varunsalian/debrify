import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:debrify/theme/app_motion.dart';
import 'package:debrify/theme/app_shape.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/widgets/detail/theme/detail_theme.dart';
import 'package:debrify/widgets/detail/theme/detail_themes.dart';

/// The non-colour tokens: legacy no-op pins, per-theme derivation, and the two
/// rules that are easy to state and easy to get wrong (growth capping, and the
/// TV policies that cannot be bypassed).
void main() {
  group('legacy is a no-op', () {
    // This is the whole safety argument for the shape sweep. Unlike a colour
    // pin — which asserts one literal equals another and can drift — these are
    // ARITHMETIC identities: if they hold, every one of the ~1,650 converted
    // sites renders the number it was drawn with, and no per-site pin is
    // needed.
    final legacy = AppThemes.legacy;

    test('every site radius survives the shape scale unchanged', () {
      // The real distribution, not round numbers: these are the literals the
      // tree actually draws, including the two pill sentinels.
      const List<double> sites = [
        0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 16, 18,
        20, 22, 24, 26, 28, 30, 2.5, 5.5, 7.5,
      ];
      for (final s in sites) {
        expect(legacy.shape.r(s), s, reason: 'r($s)');
        expect(legacy.shape.br(s), BorderRadius.circular(s), reason: 'br($s)');
        expect(legacy.shape.rImg(s), s, reason: 'rImg($s)');
      }
    });

    test('a pill stays a pill', () {
      expect(legacy.shape.brPill, BorderRadius.circular(999));
    });

    test('type is Inter at scale 1 with no overrides', () {
      expect(legacy.type.displayFamily, isNull);
      expect(legacy.type.bodyFamily, isNull);
      expect(legacy.type.titleScale, 1);
      expect(legacy.type.displayWeight, isNull);
      expect(legacy.type.displayTracking, isNull);
      expect(legacy.type.displayUpper, isFalse);

      const base = TextStyle(fontSize: 16, fontWeight: FontWeight.w600);
      expect(legacy.type.display(base).fontSize, 16);
      expect(legacy.type.display(base).fontFamily, isNull);
      expect(legacy.type.display(base).fontWeight, FontWeight.w600);
      expect(legacy.type.body(base).fontFamily, isNull);
    });

    test('motion is the durations the tree already uses', () {
      expect(legacy.motion.scale, 1);
      expect(legacy.motion.fast, const Duration(milliseconds: 120));
      expect(legacy.motion.base, const Duration(milliseconds: 220));
      expect(legacy.motion.slow, const Duration(milliseconds: 360));
      expect(legacy.motion.standard, Curves.easeOutCubic);
      const m = AppMotion(MotionTokens.legacy, reduced: false);
      expect(m.scaled(const Duration(milliseconds: 333)),
          const Duration(milliseconds: 333));
    });

    test('legacy declares no texture and no elevation', () {
      expect(legacy.shape.grain, 0);
      expect(legacy.shape.grid, isFalse);
      expect(legacy.shape.shadow, isEmpty);
    });
  });

  group('derivation', () {
    test('every shipped theme derives all three token groups', () {
      for (final core in DetailThemes.all) {
        final t = AppTheme.fromDetail(core);
        expect(t.shape.scale, ShapeTokens.dampGrowth(core.radius / 10),
            reason: core.id);
        expect(t.shape.imgScale, ShapeTokens.dampGrowth(core.radiusImg / 8),
            reason: core.id);
        expect(t.type.titleScale, closeTo(1 + (core.displayScale - 1) * 0.5, 1e-9),
            reason: core.id);
        expect(t.motion.scale, inInclusiveRange(0.85, 1.15), reason: core.id);
      }
    });

    test('a square theme squares everything, including its pills', () {
      // Blueprint/Noir/Concrete/Phosphor/Vault all declare radius 0 AND
      // radiusBtn 0. Scale 0 handles the surfaces; `pill` has to handle the
      // sentinels, or a squared theme keeps 999px lozenges.
      for (final id in ['blueprint', 'noir', 'concrete', 'phosphor', 'vault']) {
        final t = AppTheme.fromDetail(DetailThemes.byId(id));
        expect(t.shape.scale, 0, reason: id);
        expect(t.shape.r(20), 0, reason: id);
        expect(t.shape.brPill, BorderRadius.zero, reason: id);
      }
    });

    test('a rounded theme keeps its pills', () {
      for (final id in ['aurora', 'halo', 'frost', 'spectrum']) {
        final t = AppTheme.fromDetail(DetailThemes.byId(id));
        expect(t.shape.pill, 999, reason: id);
      }
    });

    test('a theme that squares only its buttons squares only its pills', () {
      // Sepia: radius 4 (soft surfaces) but radiusBtn 4 (no lozenges).
      final sepia = AppTheme.fromDetail(DetailThemes.byId('sepia'));
      expect(sepia.shape.pill, 4);
      expect(sepia.shape.r(20), closeTo(8, 1e-9)); // surfaces still scale
    });
  });

  group('growth is damped and capped; shrinking is neither', () {
    // Flutter normalises RRect radii to the box, so a control of height H is a
    // pill once its radius reaches H/2. An unbounded scale therefore turns
    // short controls into lozenges and destroys the hierarchy the scale exists
    // to preserve. Aurora's raw 1.8 is the widest growth in the set.
    final aurora = AppTheme.fromDetail(DetailThemes.byId('aurora')).shape;

    test('a raw scale above 1 is halved toward 1', () {
      expect(aurora.scale, closeTo(1.4, 1e-9)); // raw 1.8
      expect(
          AppTheme.fromDetail(DetailThemes.byId('frost')).shape.scale,
          closeTo(1.3, 1e-9)); // raw 1.6
      expect(
          AppTheme.fromDetail(DetailThemes.byId('halo')).shape.scale,
          closeTo(1.2, 1e-9)); // raw 1.4
    });

    test('a small site grows, but never past the cap', () {
      expect(aurora.r(4), closeTo(5.6, 1e-9));
      expect(aurora.r(8), closeTo(11.2, 1e-9));
      expect(aurora.r(11), closeTo(15.4, 1e-9));
      expect(aurora.r(12), 16); // 16.8 capped
      expect(aurora.r(14), 16); // 19.6 capped
    });

    test('growth never exceeds 16, and never exceeds the site itself', () {
      // The precise claim, and deliberately not "nothing is ever a pill": a
      // site that already draws circular(20) renders 20 here exactly as it
      // does today. What this bounds is GROWTH — a theme may not round a
      // corner past 16px, which is under the 18px pill threshold of the 36px
      // controls this app uses.
      const List<double> sites = [
        0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 16, 18,
        20, 22, 24, 26, 28, 30,
      ];
      for (final core in DetailThemes.all) {
        final s = AppTheme.fromDetail(core).shape;
        for (final site in sites) {
          final grown = s.r(site);
          expect(grown, lessThanOrEqualTo(math.max(site, 16.0)),
              reason: '${core.id} grew $site to $grown');
        }
      }
    });

    test('the cap never SHRINKS a site below what it asked for', () {
      // A site already drawn above the cap keeps its own radius — the cap is
      // there to stop small radii climbing, not to flatten large cards.
      expect(aurora.r(20), 20);
      expect(aurora.r(28), 28);
      expect(aurora.r(30), 30);
    });

    test('a shrinking theme is never damped or capped', () {
      final velvet = AppTheme.fromDetail(DetailThemes.byId('velvet')).shape;
      expect(velvet.scale, closeTo(0.3, 1e-9));
      expect(velvet.r(100), closeTo(30, 1e-9));
    });
  });

  group('TV policies cannot be bypassed', () {
    test('the cursor keeps its 2.5px floor on TV', () {
      for (final core in DetailThemes.all) {
        final s = AppTheme.fromDetail(core).shape;
        expect(s.focusWidthFor(true), greaterThanOrEqualTo(2.5), reason: core.id);
        expect(s.focusWidthFor(false), core.focusWidth, reason: core.id);
      }
    });

    test('grain is always off on TV', () {
      for (final core in DetailThemes.all) {
        expect(AppTheme.fromDetail(core).shape.grainFor(true), 0,
            reason: core.id);
      }
      // …and on for the two themes that ask for it, off TV.
      expect(AppTheme.fromDetail(DetailThemes.byId('sepia')).shape.grainFor(false),
          greaterThan(0));
      expect(
          AppTheme.fromDetail(DetailThemes.byId('cinemascope'))
              .shape
              .grainFor(false),
          greaterThan(0));
    });

    test('the grid is off on TV, and only Blueprint asks for it at all', () {
      final blueprint = AppTheme.fromDetail(DetailThemes.byId('blueprint')).shape;
      expect(blueprint.gridFor(false), isTrue);
      expect(blueprint.gridFor(true), isFalse);
      final others =
          DetailThemes.all.where((t) => t.id != 'blueprint').map((t) => t.grid);
      expect(others, everyElement(isFalse));
    });

    test('big blurs are dropped on TV', () {
      for (final core in DetailThemes.all) {
        final s = AppTheme.fromDetail(core).shape;
        expect(s.shadowFor(true).every((b) => b.blurRadius <= 6), isTrue,
            reason: core.id);
      }
    });
  });

  group('reduced motion', () {
    test('collapses every duration this API vends', () {
      const m = AppMotion(MotionTokens.legacy, reduced: true);
      expect(m.fast, Duration.zero);
      expect(m.base, Duration.zero);
      expect(m.slow, Duration.zero);
      expect(m.scaled(const Duration(seconds: 5)), Duration.zero);
    });

    test('applies under LEGACY too — the one considered exception', () {
      // Legacy is byte-identical AT THE PLATFORM'S DEFAULT motion setting.
      // A user who has switched "Remove animations" on has asked for this,
      // and gating accessibility on a cosmetic preference would be worse.
      // Both halves are pinned so neither can be changed by accident.
      const off = AppMotion(MotionTokens.legacy, reduced: false);
      expect(off.scaled(const Duration(milliseconds: 150)),
          const Duration(milliseconds: 150),
          reason: 'legacy at default settings must be exactly what shipped');

      const on = AppMotion(MotionTokens.legacy, reduced: true);
      expect(on.scaled(const Duration(milliseconds: 150)), Duration.zero,
          reason: 'legacy + reduced motion is deliberately NOT the shipped '
              'duration — see the note on AppMotion');
    });

    test('a theme tempo scales without losing precision', () {
      final sepia = AppTheme.fromDetail(DetailThemes.byId('sepia')).motion;
      final m = AppMotion(sepia, reduced: false);
      expect(sepia.scale, 1.15);
      expect(m.base, const Duration(milliseconds: 253)); // 220 × 1.15
    });
  });

  group('font roles', () {
    test('sans is still the platform default, so Signal cannot move', () {
      expect(DetailFontRole.sans.family, isNull);
      final signal = AppTheme.fromDetail(DetailThemes.signal);
      expect(signal.type.displayFamily, isNull);
      expect(signal.type.bodyFamily, isNull);
    });

    test('only the themes that declare a face get one', () {
      // Six themes take a non-Inter DISPLAY face; only two take a non-Inter
      // BODY face, which is what bounds the overflow risk of promoting type
      // app-wide.
      final display = DetailThemes.all
          .where((t) => t.displayFont != DetailFontRole.sans)
          .map((t) => t.id)
          .toSet();
      expect(display,
          {'broadsheet', 'velvet', 'sepia', 'vault', 'phosphor', 'blueprint'});
      final body = DetailThemes.all
          .where((t) => t.bodyFont != DetailFontRole.sans)
          .map((t) => t.id)
          .toSet();
      expect(body, {'broadsheet', 'phosphor'});
    });
  });
}
