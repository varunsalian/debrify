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
import 'package:debrify/screens/settings/detail_theme_page.dart'
    show kDetailThemesShipped;
import 'package:debrify/services/storage_service.dart';
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

    test('a NEW animated skeleton degrades on TV; shimmer is exempt', () {
      // "Nothing animates unless it must" — an endlessly looping skeleton is
      // an endless repaint. But the rule can only apply to what this work
      // ADDS: `Shimmer` already runs a 1200ms repeating controller on TV in
      // the shipped app, so degrading it here would make the legacy profile
      // stop being a no-op. The one permitted legacy exception is reduced
      // motion, not a TV optimisation.
      expect(
        const WaitTokens(skeleton: SkeletonStyle.pulse, period: Duration.zero)
            .styleFor(true),
        SkeletonStyle.static_,
      );
      expect(WaitTokens.legacy.styleFor(true), SkeletonStyle.shimmer);
      for (final s in PremiumLooks.all) {
        final st = s.build().wait.styleFor(true);
        expect(st, isNot(SkeletonStyle.pulse), reason: '${s.id} -> ${st.name}');
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
      expect(PremiumLooks.all.map((s) => s.id).toSet().length,
          PremiumLooks.all.length);
      expect(PremiumLooks.all.map((s) => s.label).toSet().length,
          PremiumLooks.all.length);
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

    test('an unstated meaning role falls back to the accent, never to grey',
        () {
      // The rule from §4: state/callout/focus carry semantics, so they are
      // given or derived — never defaulted into nothing. `isNotNull` cannot
      // express that (the fields are non-nullable); what it means in practice
      // is that a spec which names no `state` gets the ACCENT, so the colour
      // still says something.
      for (final s in PremiumLooks.all) {
        final c = s.build().core;
        expect(c.state, s.state ?? s.accent, reason: '${s.id} state');
        expect(c.callout, s.callout ?? s.accent, reason: '${s.id} callout');
        expect(c.focus, s.focusColor ?? s.accent, reason: '${s.id} focus');
      }
    });

    test('the primary button is the decision the spec made, and is readable',
        () {
      // Three of the five mockups fill the primary button with the accent;
      // two use near-white ink. Deriving it would have contradicted whichever
      // three it guessed against, so it is stated — and this pins that the
      // stated value is what arrives.
      for (final s in PremiumLooks.all) {
        final c = s.build().core;
        if (s.accentButton) {
          expect(c.btnFill, s.accent, reason: '${s.id} wants an accent button');
        } else {
          expect(c.btnFill, isNot(s.accent), reason: '${s.id} wants ink');
        }
        expect(_ratio(c.btnText, c.btnFill), greaterThan(4.5),
            reason: '${s.id}: label on its own button');
      }
    });

    test('a fill-less separation model reaches the colours the detail page '
        'actually paints', () {
      // `panel` and `ghostFill` are painted DIRECTLY by the detail widgets —
      // a `space` look whose SurfaceTokens say "no fill" while its core still
      // carries a 7%-ink panel has not stopped having boxes.
      for (final s in PremiumLooks.all) {
        final c = s.build().core;
        switch (s.separation) {
          case SeparationModel.space:
            expect(c.panel.a, 0, reason: '${s.id} panel');
            expect(c.ghostFill.a, 0, reason: '${s.id} ghostFill');
            expect(c.ghostBorder.a, 0, reason: '${s.id} ghostBorder');
          case SeparationModel.rule:
            expect(c.ghostFill.a, 0, reason: '${s.id} ghostFill');
            expect(c.hair.a, greaterThan(0.14),
                reason: '${s.id}: a rule look lives on its hairline');
          case SeparationModel.fill || SeparationModel.glass:
            expect(c.panel.a, greaterThan(0), reason: '${s.id} panel');
        }
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

    test('only the look that ASKED invites poster colour into its palette', () {
      // An explicit spec decision, not a threshold on `reactiveRoom`: a small
      // numeric nudge to the room's magnitude must not flip whether posters
      // may replace semantic colours across the whole detail UI.
      final reactive =
          PremiumLooks.all.where((s) => s.build().core.useArtworkAccent);
      expect(reactive.map((s) => s.id), ['field']);
      for (final s in PremiumLooks.all) {
        expect(s.build().core.useArtworkAccent, s.artworkAccent, reason: s.id);
      }
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
      expect(snap.standard, Curves.linear);
      expect(snap.emphasized, Curves.linear);
      final glide = PremiumLooks.glass.build().motion;
      expect(glide.character, MotionCharacter.glide);
      expect(glide.base.inMilliseconds, greaterThan(250));
      expect(glide.standard, isNot(Curves.linear));
    });

    test('a character does not apply its tempo twice', () {
      // The bug this pins: `MotionTokens.of` chooses character-specific
      // durations AND could also set `scale`, and `AppMotion` multiplies by
      // scale on the way out — so snap's advertised 90ms would have arrived
      // as 76.5ms. What a consumer receives must be what the character says.
      for (final s in PremiumLooks.all) {
        final t = s.build().motion;
        final live = AppMotion(t, reduced: false);
        expect(live.fast, t.fast, reason: '${s.id} fast');
        expect(live.base, t.base, reason: '${s.id} base');
        expect(live.slow, t.slow, reason: '${s.id} slow');
      }
      expect(AppMotion(PremiumLooks.console.build().motion, reduced: false).base,
          const Duration(milliseconds: 90));
      expect(AppMotion(PremiumLooks.glass.build().motion, reduced: false).slow,
          const Duration(milliseconds: 520));
    });

    test('reduced motion collapses every look, legacy included', () {
      for (final t in [
        AppThemes.legacy.motion,
        for (final s in PremiumLooks.all) s.build().motion,
      ]) {
        final off = AppMotion(t, reduced: true);
        expect(off.fast, Duration.zero);
        expect(off.base, Duration.zero);
        expect(off.slow, Duration.zero);
      }
    });

    test('a ring-less expression does not also draw a ring', () {
      // Every expression, not a sample: `invert` and `flood` REPLACE the
      // surface, so a ring around an already-inverted cell is a second cursor
      // drawn on top of the first, and Console is the look that would have
      // shipped with it.
      for (final e in FocusExpression.values) {
        final draws = FocusTokens(
          expression: e,
          width: 2,
          offset: 0,
          scale: 1,
          lift: 0,
        ).drawsRing;
        expect(draws, e == FocusExpression.ring, reason: e.name);
      }
      expect(PremiumLooks.field.build().focus.drawsRing, isFalse,
          reason: 'scale + a ring reads as two cursors');
      expect(PremiumLooks.console.build().focus.drawsRing, isFalse,
          reason: 'invert replaces the surface');
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

  group('the twenty existing cores inherit NEUTRAL phase-four groups', () {
    // The review's sharpest point: nothing changes today only because nobody
    // reads these groups yet. The moment the sweeps land, any non-neutral
    // default would activate new rendering on twenty shipped themes at once.
    // So the defaults are pinned as identities, not merely "looks fine".
    for (final core in DetailThemes.all) {
      test(core.id, () {
        final t = AppTheme.fromDetail(core);
        expect(t.surface.base, SurfaceTokens.legacy.base);
        expect(t.surface.overrides, isEmpty);
        expect(t.surface.glassSigma, SurfaceTokens.legacy.glassSigma);
        expect(t.surface.sheen, SurfaceTokens.legacy.sheen);
        // Shadow above all: `ShapeTokens` documents that app-wide shadow is
        // CARRIED because replace-vs-compose needs a design pass, so a
        // theme's detail shadow must not have been promoted app-wide here.
        expect(t.surface.restShadow, isEmpty);
        expect(t.surface.raisedShadow, isEmpty);
        expect(t.surface.floatingShadow, isEmpty);

        expect(t.light.scrim, LightTokens.legacy.scrim);
        expect(t.light.vignette, LightTokens.legacy.vignette);
        expect(t.light.bloomFor(false), LightTokens.legacy.bloomFor(false));

        expect(t.art.frame, ArtTokens.legacy.frame);
        expect(t.art.grade, ArtTokens.legacy.grade);
        // `washOpacity` is a detail-SHELL alpha; the TV room blends its own
        // 0.25–0.50 tints. Inheriting one as the other would have retuned
        // every existing theme's room.
        expect(t.art.reactiveRoom, ArtTokens.legacy.reactiveRoom);

        expect(t.focus.expression, FocusTokens.legacy.expression);
        expect(t.focus.width, FocusTokens.legacy.width);
        expect(t.focus.offset, FocusTokens.legacy.offset);
        expect(t.focus.scale, FocusTokens.legacy.scale);
        expect(t.focus.lift, FocusTokens.legacy.lift);

        expect(t.idle.policy, IdleTokens.legacy.policy);
        expect(t.wait.skeleton, WaitTokens.legacy.skeleton);
        expect(t.density.rowHeight, DensityTokens.legacy.rowHeight);
        expect(t.density.cardScale, DensityTokens.legacy.cardScale);
        expect(t.density.pageGutter, DensityTokens.legacy.pageGutter);
        expect(t.density.sectionGap, DensityTokens.legacy.sectionGap);

        expect(t.motion.character, MotionCharacter.standard);
        expect(t.motion.entrance, EntranceStyle.none);
      });
    }
  });

  group('the five looks can be selected, stored and resolved', () {
    test('every id is an accepted stored value', () {
      for (final s in PremiumLooks.all) {
        expect(StorageService.kDetailThemes, contains(s.id),
            reason: '${s.id} would normalize to legacy on select');
        expect(kDetailThemesShipped, contains(s.id),
            reason: '${s.id} would be withheld from every picker');
      }
    });

    test('AppThemes.byId returns the LOOK, not a core-only theme', () {
      for (final s in PremiumLooks.all) {
        final t = AppThemes.byId(s.id);
        expect(t.id, s.id);
        expect(t.isLegacy, isFalse);
        // The half that `fromDetail(core)` alone could not have supplied: if
        // this is legacy's model, the look resolved through the wrong path.
        expect(t.surface.modelFor(SurfaceFamily.card), s.separation,
            reason: '${s.id} lost its phase-four groups');
        expect(t.focus.expression, s.focusExpression);
        expect(t.motion.character, s.motion);
      }
    });

    test('byId is memoized — one build per look, not one per lookup', () {
      expect(identical(AppThemes.byId('glass'), AppThemes.byId('glass')),
          isTrue);
    });

    test('an unknown id still falls back to legacy, never to a look', () {
      expect(AppThemes.byId('no-such-theme').isLegacy, isTrue);
      expect(AppThemes.byId('').isLegacy, isTrue);
    });

    test('the details page resolves them too', () {
      // The app-theme picker mirrors its id into `detail_theme`, so a look
      // that AppThemes can resolve but DetailThemes cannot would leave the
      // details page on Signal while the shell restyled.
      for (final s in PremiumLooks.all) {
        expect(DetailThemes.byId(s.id).id, s.id);
      }
      expect(DetailThemes.byId('no-such-theme').id, 'signal');
    });

    test('the pickers show them first, and show all twenty-five', () {
      final ids = DetailThemes.catalogue.map((t) => t.id).toList();
      expect(ids.take(PremiumLooks.all.length), PremiumLooks.all.map((s) => s.id));
      expect(ids.length, DetailThemes.all.length + PremiumLooks.all.length);
      expect(ids.toSet().length, ids.length, reason: 'id collision');
    });
  });

  group('the surface families have live consumers, not just declarations', () {
    // The rule the review caught twice: a token with no consumer is
    // decorative. These pin that the families a look addresses are the
    // families a widget actually asks about.
    test('settingsGroup is capped to fill-or-rule, and both are reachable', () {
      expect(
        SurfaceTokens.legacy.modelFor(SurfaceFamily.settingsGroup),
        SeparationModel.fill,
      );
      // Deep Field says `space` app-wide; a settings group cannot survive it
      // (zero inter-row gap, in-place border), so it is clamped — to `rule`,
      // not to `fill`, because losing the fill is the part it CAN do.
      expect(
        PremiumLooks.field.build().surface.modelFor(SurfaceFamily.settingsGroup),
        SeparationModel.rule,
      );
      expect(
        PremiumLooks.console
            .build()
            .surface
            .modelFor(SurfaceFamily.settingsGroup),
        SeparationModel.rule,
      );
    });

    test('shelfRow may take every model — the row made that true', () {
      // `TorrentResultRow`'s border used to sit in the layout path, which is
      // what made `space` illegal on a shelf row. Splitting it is the §12
      // precondition; this is the assertion that the cap now matches.
      for (final m in SeparationModel.values) {
        expect(
          SurfaceTokens(
            base: m,
            glassSigma: 0,
            glassOpacity: 1,
            glassOpacityTv: 1,
            sheen: 0,
            restShadow: const <BoxShadow>[],
            raisedShadow: const <BoxShadow>[],
            floatingShadow: const <BoxShadow>[],
          ).modelFor(SurfaceFamily.shelfRow),
          m,
          reason: m.name,
        );
      }
    });

    test('a sheet or dialog can never lose its fill', () {
      // The fill IS the modal; remove it and the page shows through.
      for (final f in [SurfaceFamily.sheet, SurfaceFamily.dialog]) {
        for (final m in SeparationModel.values) {
          final got = SurfaceTokens(
            base: m,
            glassSigma: 0,
            glassOpacity: 1,
            glassOpacityTv: 1,
            sheen: 0,
            restShadow: const <BoxShadow>[],
            raisedShadow: const <BoxShadow>[],
            floatingShadow: const <BoxShadow>[],
          ).modelFor(f);
          expect(
            got == SeparationModel.fill || got == SeparationModel.glass,
            isTrue,
            reason: '${f.name} + ${m.name} -> ${got.name}',
          );
        }
      }
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
      'spotlight': (SeparationModel.fill, ScrimStyle.bottomGradient,
          ArtFrame.bleed, ArtGrade.none, FocusExpression.parallax,
          MotionCharacter.settle),
    };

    // Everything the enums do NOT cover, pinned as the numbers a consumer
    // actually receives: derived colours, radii, effective motion, density,
    // and the two ambience policies. Six enum values copied out of the spec
    // could not have failed; these can.
    const derived = {
      //        ground      ink         accent      btnFill     radius sm  img
      'glass': (0xFF05070A, 0xFFF2F5F8, 0xFF7FD4FF, 0xFFE4E7EA, 14.0, 10.0, 14.0),
      'field': (0xFF000000, 0xFFFFFFFF, 0xFFE8503A, 0xFFF0F0F0, 3.0, 2.0, 3.0),
      'hearth': (0xFF141110, 0xFFF6EFE6, 0xFFE8A13C, 0xFFE8A13C, 12.0, 8.0, 12.0),
      'console': (0xFF080B09, 0xFFD8E0D8, 0xFF8CE0A8, 0xFF8CE0A8, 0.0, 0.0, 0.0),
      'reel': (0xFF0A0908, 0xFFEDE4D8, 0xFFD9A441, 0xFFD9A441, 4.0, 3.0, 4.0),
      // Was `0xFF1B1C1C` with a white accent and a white button fill — the
      // reference carries no accent colour at all, state being the lift and a
      // solid-white primary. Both were retired when this Look became the
      // default: the mid grey and the colourless accent are affordable when
      // artwork covers the screen, and this app has whole surfaces with none.
      'spotlight': (
        // True black in round three; Deep Navy in round four, chosen against
        // the real Apple TV app on a panel — see PremiumLooks.spotlight.
        0xFF0D1420,
        0xFFFFFFFF,
        0xFFE23D4C,
        // Not the accent: crimson with a white label scores 4.19:1, under the
        // bar the primary-button test holds, so the fill stays the
        // near-white — which is also what the reference's primary is. It
        // derives off the ground, so the Deep Navy move gave it this faint
        // cool cast.
        0xFFF0F1F2,
        7.0,
        5.0,
        7.0
      ),
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

        final d = derived[s.id]!;
        final c = t.core;
        expect(c.ground.toARGB32(), d.$1, reason: 'ground');
        expect(c.tx.toARGB32(), d.$2, reason: 'ink');
        expect(c.accent.toARGB32(), d.$3, reason: 'accent');
        expect(c.btnFill.toARGB32(), d.$4, reason: 'btnFill');
        expect(c.radius, d.$5, reason: 'radius');
        expect(c.radiusSm, d.$6, reason: 'radiusSm');
        expect(c.radiusImg, d.$7, reason: 'radiusImg');

        // Effective, not raw: this is what a widget receives.
        final m = AppMotion(t.motion, reduced: false);
        expect(m.base, t.motion.base, reason: 'tempo applied twice');

        // Density is clamped at derivation, so what the spec asked for and
        // what arrives can legally differ — pin what ARRIVES.
        expect(t.density.rowHeight, s.rowHeight.clamp(0.80, 1.20));
        expect(t.density.cardScale, s.cardScale.clamp(0.85, 1.15));
        expect(t.density.pageGutter, s.pageGutter.clamp(0.75, 1.25));
        expect(t.density.sectionGap, s.sectionGap.clamp(0.70, 1.30));

        expect(t.idle.policy, s.idle, reason: 'idle');
        expect(t.wait.skeleton, s.skeleton, reason: 'skeleton');

        // Shadows are a fill's way of lifting; a rule/space look must not
        // have acquired one on the way through the derivation.
        final lifts = s.separation == SeparationModel.fill ||
            s.separation == SeparationModel.glass;
        expect(t.surface.raisedShadow.isNotEmpty, lifts, reason: 'raised');
      });
    }

    test('the snapshot table covers every shipped look', () {
      expect(expected.keys.toSet(),
          PremiumLooks.all.map((s) => s.id).toSet());
    });
  });
}

/// WCAG relative-contrast ratio between two opaque colours.
double _ratio(Color a, Color b) {
  final la = a.withValues(alpha: 1).computeLuminance();
  final lb = b.withValues(alpha: 1).computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}
