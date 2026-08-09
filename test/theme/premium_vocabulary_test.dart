import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:debrify/theme/app_ambience.dart';
import 'package:debrify/theme/app_art.dart';
import 'package:debrify/theme/app_focus.dart';
import 'package:debrify/theme/app_light.dart';
import 'package:debrify/theme/app_motion.dart';
import 'package:debrify/theme/app_surface.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/premium_looks.dart';
import 'package:debrify/theme/theme_spec.dart';
import 'package:debrify/widgets/detail/theme/detail_themes.dart';

/// Phase four's vocabulary: the legacy no-ops, the geometry caps that make
/// `space` legal at all, the TV policies, and what each of the five looks
/// derives to.
void main() {
  group('legacy is a no-op across every new group', () {
    // Same argument as phase three's: these are not colour pins that could
    // drift, they are identities. If they hold, a surface reading the new
    // tokens under Debrify Classic renders exactly what it renders now.
    final l = AppThemes.legacy;

    test('separation is fill for every family', () {
      for (final f in SurfaceFamily.values) {
        expect(l.surface.modelFor(f), SeparationModel.fill, reason: f.name);
      }
    });

    test('no blur, no sheen, no elevation ramp', () {
      expect(l.surface.glassSigmaFor(false), 0);
      expect(l.surface.glassSigmaFor(true), 0);
      expect(l.surface.sheen, 0);
      expect(l.surface.restShadow, isEmpty);
      expect(l.surface.raisedShadow, isEmpty);
      expect(l.surface.floatingShadow, isEmpty);
    });

    test('the scrim is the gradient the hero already draws', () {
      expect(l.light.scrim, ScrimStyle.bottomGradient);
      expect(l.light.vignette, 0);
      expect(l.light.bloomFor(false), 0);
    });

    test('artwork is framed and ungraded', () {
      expect(l.art.frame, ArtFrame.contained);
      expect(l.art.grade, ArtGrade.none);
      expect(l.art.blendFor(false), isNull);
    });

    test('focus is an in-bounds ring at Signal\'s width', () {
      expect(l.focus.expression, FocusExpression.ring);
      expect(l.focus.width, 2.5);
      expect(l.focus.offset, 0,
          reason: 'Signal draws in bounds and every site assumes it');
      expect(l.focus.scale, 1);
      expect(l.focus.lift, 0);
    });

    test('no idle policy, the shipped shimmer, density of exactly 1', () {
      expect(l.idle.policyFor(true), IdlePolicy.none);
      expect(l.wait.skeleton, SkeletonStyle.shimmer);
      for (final v in [
        l.density.rowHeight,
        l.density.cardScale,
        l.density.pageGutter,
        l.density.sectionGap,
      ]) {
        expect(v, 1);
      }
      expect(l.density.row(48), 48);
      expect(l.density.card(120), 120);
    });

    test('motion character is standard', () {
      expect(l.motion.character, MotionCharacter.standard);
      expect(l.motion.entranceFor(false), EntranceStyle.none);
    });
  });

  group('the family caps are geometry, not taste', () {
    // Each cap exists because the §12 inventory found that violating it moves
    // content. A theme asking for something illegal is clamped, not asserted —
    // a theme is data, and the clamp IS the contract.
    SurfaceTokens want(SeparationModel m) => SurfaceTokens(
      base: m,
      glassSigma: 20,
      glassOpacity: .5,
      glassOpacityTv: .94,
      sheen: 0,
      restShadow: const [],
      raisedShadow: const [],
      floatingShadow: const [],
    );

    test('settings may never take glass or space', () {
      // SettingsSection is one filled container whose rows have ZERO
      // inter-row gap and an in-place Border.all — dropping it shifts every
      // row 1px and dissolves the grouping.
      expect(want(SeparationModel.glass).modelFor(SurfaceFamily.settingsGroup),
          SeparationModel.fill);
      expect(want(SeparationModel.space).modelFor(SurfaceFamily.settingsGroup),
          SeparationModel.rule,
          reason: 'a look that asked for "no boxes" is better served by '
              'hairlines than by the boxes it was removing');
    });

    test('sheets and dialogs may never take space or rule', () {
      // The fill IS the modal; remove it and the page shows through.
      for (final f in [SurfaceFamily.sheet, SurfaceFamily.dialog]) {
        expect(want(SeparationModel.space).modelFor(f), SeparationModel.fill,
            reason: f.name);
        expect(want(SeparationModel.rule).modelFor(f), SeparationModel.fill,
            reason: f.name);
        expect(want(SeparationModel.glass).modelFor(f), SeparationModel.glass,
            reason: '${f.name} may take glass');
      }
    });

    test('cards, shelf rows and heroes may take all four', () {
      for (final f in [
        SurfaceFamily.card,
        SurfaceFamily.shelfRow,
        SurfaceFamily.hero,
      ]) {
        for (final m in SeparationModel.values) {
          expect(want(m).modelFor(f), m, reason: '${f.name}/${m.name}');
        }
      }
    });

    test('an explicit override still obeys the cap', () {
      final t = SurfaceTokens(
        base: SeparationModel.fill,
        overrides: const {SurfaceFamily.settingsGroup: SeparationModel.glass},
        glassSigma: 20,
        glassOpacity: .5,
        glassOpacityTv: .94,
        sheen: 0,
        restShadow: const [],
        raisedShadow: const [],
        floatingShadow: const [],
      );
      expect(t.modelFor(SurfaceFamily.settingsGroup), SeparationModel.fill);
    });
  });

  group('TV policies cannot be bypassed', () {
    test('glass loses its blur and gains opacity', () {
      for (final s in PremiumLooks.all) {
        final t = s.build();
        expect(t.surface.glassSigmaFor(true), 0, reason: s.id);
        expect(t.surface.glassFillFor(true),
            greaterThan(t.surface.glassFillFor(false)),
            reason: '${s.id}: an unblurred pane at the blurred opacity is a '
                'smear, not a surface');
      }
    });

    test('grading is off on TV for every look', () {
      for (final s in PremiumLooks.all) {
        final t = s.build();
        expect(t.art.gradeFor(true), ArtGrade.none, reason: s.id);
        expect(t.art.blendFor(true), isNull, reason: s.id);
      }
    });

    test('portraits never grade, on any platform or look', () {
      // Five of the eight "chrome" image sites are cast headshots. A move that
      // flatters a poster makes a person look ill.
      for (final s in PremiumLooks.all) {
        expect(s.build().art.blendForPortrait(false), isNull, reason: s.id);
      }
    });

    test('the focus ring keeps its 2.5px floor', () {
      for (final s in PremiumLooks.all) {
        expect(s.build().focus.widthFor(true), greaterThanOrEqualTo(2.5),
            reason: s.id);
      }
    });

    test('grain is off on TV, and only Midnight Cinema asks for it', () {
      for (final s in PremiumLooks.all) {
        expect(s.build().shape.grainFor(true), 0, reason: s.id);
      }
      expect(PremiumLooks.reel.build().shape.grainFor(false), greaterThan(0));
      final asking = PremiumLooks.all.where((s) => s.grain > 0).map((s) => s.id);
      expect(asking, ['reel']);
    });

    test('idle is TV-only, and entrance choreography is not run on TV', () {
      for (final s in PremiumLooks.all) {
        final t = s.build();
        expect(t.idle.policyFor(false), IdlePolicy.none, reason: s.id);
        expect(t.motion.entranceFor(true), EntranceStyle.none, reason: s.id);
      }
    });

    test('an animated skeleton degrades to a static block on TV', () {
      // "Nothing animates unless it must" — an endlessly looping skeleton is
      // an endless repaint.
      for (final s in PremiumLooks.all) {
        final st = s.build().wait.styleFor(true);
        expect(st == SkeletonStyle.static_ || st == SkeletonStyle.scanlines,
            isTrue, reason: '${s.id} -> ${st.name}');
      }
    });
  });

  group('density is a bounded seam, not a layout escape hatch', () {
    test('a spec cannot express a layout change', () {
      final wild = DensityTokens.clamped(
        rowHeight: 3,
        cardScale: 0.1,
        pageGutter: 9,
        sectionGap: 0,
      );
      expect(wild.rowHeight, 1.20);
      expect(wild.cardScale, 0.85);
      expect(wild.pageGutter, 1.25);
      expect(wild.sectionGap, 0.70);
    });

    test('every shipped look stays inside the bounds', () {
      for (final s in PremiumLooks.all) {
        final d = s.build().density;
        expect(d.rowHeight, inInclusiveRange(0.80, 1.20), reason: s.id);
        expect(d.cardScale, inInclusiveRange(0.85, 1.15), reason: s.id);
        expect(d.pageGutter, inInclusiveRange(0.75, 1.25), reason: s.id);
        expect(d.sectionGap, inInclusiveRange(0.70, 1.30), reason: s.id);
      }
    });
  });

  group('the five looks', () {
    test('ids reuse none of the twenty existing theme ids', () {
      // A stored old id must never resolve to a new look.
      final old = DetailThemes.all.map((t) => t.id).toSet();
      for (final s in PremiumLooks.all) {
        expect(old.contains(s.id), isFalse,
            reason: '${s.id} collides with an existing theme id');
      }
    });

    test('ids and labels are unique', () {
      expect(PremiumLooks.all.map((s) => s.id).toSet().length, 5);
      expect(PremiumLooks.all.map((s) => s.label).toSet().length, 5);
    });

    test('every look builds, and none is legacy', () {
      for (final s in PremiumLooks.all) {
        final t = s.build();
        expect(t.isLegacy, isFalse, reason: s.id);
        expect(t.id, s.id);
        expect(t.label, s.label);
      }
    });

    test('all five are dark — D1, which is what deletes the light-ink debt',
        () {
      for (final s in PremiumLooks.all) {
        expect(s.build().isLight, isFalse, reason: s.id);
      }
    });

    test('text reads on every look\'s ground', () {
      for (final s in PremiumLooks.all) {
        final t = s.build();
        final lg = t.core.ground.withValues(alpha: 1).computeLuminance();
        final li = t.core.tx.withValues(alpha: 1).computeLuminance();
        final ratio = (li + 0.05) / (lg + 0.05);
        expect(ratio, greaterThan(7), reason: '${s.id}: ink on ground');
      }
    });

    test('meaning roles are never silently null', () {
      // The rule from §4: state/callout/focus carry semantics, so they are
      // given or derived — never defaulted into nothing.
      for (final s in PremiumLooks.all) {
        final c = s.build().core;
        expect(c.state, isNotNull, reason: s.id);
        expect(c.callout, isNotNull, reason: s.id);
        expect(c.focus, isNotNull, reason: s.id);
        expect(c.calloutText, isNotNull, reason: s.id);
      }
    });

    test('callout ink is scored against its own fill', () {
      for (final s in PremiumLooks.all) {
        final c = s.build().core;
        final lf = c.callout.withValues(alpha: 1).computeLuminance();
        final lt = c.calloutText.withValues(alpha: 1).computeLuminance();
        final hi = lt > lf ? lt : lf;
        final lo = lt > lf ? lf : lt;
        expect((hi + 0.05) / (lo + 0.05), greaterThan(3.0), reason: s.id);
      }
    });

    test('only the reactive look invites poster colour into its palette', () {
      // useArtworkAccent is derived from reactiveRoom, so a fixed-palette look
      // cannot be contaminated by an arbitrary poster.
      final reactive =
          PremiumLooks.all.where((s) => s.build().core.useArtworkAccent);
      expect(reactive.map((s) => s.id), ['field']);
    });

    test('shape follows the spec\'s corner character', () {
      expect(PremiumLooks.console.build().shape.scale, 0,
          reason: 'Console squares everything');
      expect(PremiumLooks.console.build().shape.brPill, BorderRadius.zero);
      expect(PremiumLooks.glass.build().shape.scale, greaterThan(1));
    });

    test('motion character and curves cannot disagree', () {
      // MotionTokens.of derives both together for exactly this reason.
      final snap = PremiumLooks.console.build().motion;
      expect(snap.character, MotionCharacter.snap);
      expect(snap.base.inMilliseconds, lessThan(150));
      final glide = PremiumLooks.glass.build().motion;
      expect(glide.character, MotionCharacter.glide);
      expect(glide.base.inMilliseconds, greaterThan(250));
    });

    test('a ring-less expression does not also draw a ring', () {
      expect(PremiumLooks.field.build().focus.drawsRing, isFalse,
          reason: 'scale + a ring reads as two cursors');
      expect(PremiumLooks.glass.build().focus.drawsRing, isTrue);
    });

    test('elevation agrees with separation', () {
      // A rule/space look with a drop shadow is incoherent: the shadow is a
      // fill's way of lifting.
      expect(PremiumLooks.console.build().surface.raisedShadow, isEmpty);
      expect(PremiumLooks.field.build().surface.raisedShadow, isEmpty);
      expect(PremiumLooks.hearth.build().surface.raisedShadow, isNotEmpty);
    });
  });

  group('spec snapshots — provisional until W6 signoff', () {
    // Pins what each look's twelve decisions DERIVE to, so a change to the
    // derivation cannot silently restyle a shipped look. These are ordinary
    // reviewed diffs while the looks are provisional; they freeze at device
    // signoff.
    const expected = {
      'glass': (SeparationModel.glass, ScrimStyle.blurBand, ArtFrame.contained,
          ArtGrade.none, FocusExpression.ring, MotionCharacter.glide),
      'field': (SeparationModel.space, ScrimStyle.bottomGradient,
          ArtFrame.bleed, ArtGrade.none, FocusExpression.scale,
          MotionCharacter.settle),
      'hearth': (SeparationModel.fill, ScrimStyle.plate, ArtFrame.faded,
          ArtGrade.warm, FocusExpression.lift, MotionCharacter.glide),
      'console': (SeparationModel.rule, ScrimStyle.plate, ArtFrame.contained,
          ArtGrade.none, FocusExpression.invert, MotionCharacter.snap),
      'reel': (SeparationModel.fill, ScrimStyle.plate, ArtFrame.matted,
          ArtGrade.sepia, FocusExpression.lift, MotionCharacter.settle),
    };

    for (final s in PremiumLooks.all) {
      test(s.id, () {
        final t = s.build();
        final e = expected[s.id]!;
        expect(t.surface.modelFor(SurfaceFamily.card), e.$1);
        expect(t.light.scrim, e.$2);
        expect(t.art.frame, e.$3);
        expect(t.art.grade, e.$4);
        expect(t.focus.expression, e.$5);
        expect(t.motion.character, e.$6);
      });
    }

    test('the snapshot table covers every shipped look', () {
      expect(expected.keys.toSet(),
          PremiumLooks.all.map((s) => s.id).toSet());
    });
  });
}
