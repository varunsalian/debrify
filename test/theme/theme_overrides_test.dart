import 'package:debrify/theme/app_focus.dart';
import 'package:debrify/theme/app_motion.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_controller.dart';
import 'package:debrify/theme/premium_looks.dart';
import 'package:debrify/theme/theme_core_resolver.dart';
import 'package:debrify/theme/theme_override_applier.dart';
import 'package:debrify/theme/theme_overrides.dart';
import 'package:debrify/services/text_brightness.dart';
import 'package:debrify/theme/app_theme_adapter.dart';
import 'package:debrify/theme/theme_palette.dart';
import 'package:debrify/widgets/detail/theme/detail_themes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The override layer: what a user edits, how it survives storage, and — the
/// part that actually breaks things — what it drags along with it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ThemeCoreResolver.debugReset();
  });

  group('storage', () {
    test('round trips, sparsely', () {
      const o = ThemeOverrides(accent: 'ember', focusExpression: 'parallax');
      final back = ThemeOverrides.decode(o.encode());
      expect(back.accent, 'ember');
      expect(back.focusExpression, 'parallax');
      expect(back.motion, isNull);
      expect(back.count, 2);
      // Sparse: an untouched token must not be written, or a Look revision
      // could never reach anyone who had edited anything.
      expect(o.encode().contains('motion'), isFalse);
    });

    test('malformed storage degrades to none rather than throwing', () {
      // A cosmetic preference must never be able to stop the app starting.
      expect(ThemeOverrides.decode('not json').isEmpty, isTrue);
      expect(ThemeOverrides.decode('[1,2,3]').isEmpty, isTrue);
      expect(ThemeOverrides.decode('{"accent":42}').isEmpty, isTrue);
      expect(ThemeOverrides.decode('').isEmpty, isTrue);
      expect(ThemeOverrides.decode(null).isEmpty, isTrue);
    });

    test('an unrecognised value reads as "follow the Look"', () {
      // Written by a newer build, or an enum since renamed. Falling back is the
      // only safe answer; throwing would be a launch crash.
      const o = ThemeOverrides(
        focusExpression: 'something_new',
        accent: 'no_such_swatch',
        radius: 'not_a_number',
      );
      expect(o.resolvedFocusExpression, isNull);
      expect(ThemePalette.colorOf(o.accent), isNull);
      expect(o.resolvedRadius, isNull);
    });

    test('scalars are clamped, not trusted', () {
      expect(const ThemeOverrides(grain: '5').resolvedGrain, 1);
      expect(const ThemeOverrides(grain: '-2').resolvedGrain, 0);
      // `double.tryParse` accepts both of these, and NaN defeats every clamp
      // comparison — so they would reach a radius or an alpha and fail at
      // paint time instead of falling back to the Look.
      expect(const ThemeOverrides(grain: 'NaN').resolvedGrain, isNull);
      expect(const ThemeOverrides(radius: 'Infinity').resolvedRadius, isNull);
    });

    test('with_ sets and clears one key without disturbing the others', () {
      const base = ThemeOverrides(accent: 'ember', motion: 'snap');
      final set = base.with_('grain', '0.4');
      expect(set.grain, '0.4');
      expect(set.accent, 'ember');
      final cleared = set.clear('accent');
      expect(cleared.accent, isNull);
      expect(cleared.grain, '0.4');
      expect(cleared.motion, 'snap');
    });
  });

  group('the core resolver', () {
    test('no overrides returns the registry theme UNTOUCHED', () {
      // The fast path, and the reason an unedited install resolves down
      // exactly the code it did before this layer existed.
      final base = DetailThemes.byId('signal');
      expect(
        identical(ThemeCoreResolver.resolve('signal', ThemeOverrides.none), base),
        isTrue,
      );
    });

    test('a colour override brings its DEPENDENTS with it', () {
      // The whole reason the resolver exists. Patching `ground` alone leaves
      // `lightGround` claiming the opposite — and the detail layouts read that
      // flag rather than the luminance, so a light ground would still render a
      // dark page.
      final dark = ThemeCoreResolver.resolve('signal', ThemeOverrides.none);
      expect(dark.lightGround, isFalse);

      ThemeCoreResolver.debugReset();
      final light = ThemeCoreResolver.resolve(
        'signal',
        const ThemeOverrides(ground: 'white'),
      );
      expect(light.lightGround, isTrue,
          reason: 'a light ground that still says dark renders a dark page');
    });

    test('an edited ink carries its own secondary and tertiary tones', () {
      final base = ThemeCoreResolver.resolve('signal', ThemeOverrides.none);
      ThemeCoreResolver.debugReset();
      final edited = ThemeCoreResolver.resolve(
        'signal',
        const ThemeOverrides(ink: 'amber'),
      );
      expect(edited.tx, isNot(base.tx));
      expect(edited.tx2, isNot(base.tx2),
          reason: 'the old ink must not show through underneath');
      expect(edited.tx3, isNot(base.tx3));
    });

    test('changing state drops a gradient that painted the old colour', () {
      final spectrum = DetailThemes.byId('spectrum');
      // Only meaningful on a theme that actually has one.
      if (spectrum.stateGradient == null) return;
      final edited = ThemeCoreResolver.resolve(
        'spectrum',
        const ThemeOverrides(state: 'emerald'),
      );
      expect(edited.stateGradient, isNull,
          reason: 'a gradient in the replaced colour is worse than a flat bar');
    });

    test('separation reaches the CORE, not just the surface tokens', () {
      // The detail widgets paint panel/hair/ghost directly, so a `space` look
      // resolved only into SurfaceTokens would keep its boxes on the one page
      // where the artwork is the point.
      final spaced = ThemeCoreResolver.resolve(
        'signal',
        const ThemeOverrides(separation: 'space'),
      );
      expect(spaced.panel.a, 0);
      expect(spaced.ghostFill.a, 0);
    });

    test('radius moves the whole family, not one corner', () {
      final edited = ThemeCoreResolver.resolve(
        'signal',
        const ThemeOverrides(radius: '4'),
      );
      expect(edited.radius, 4);
      expect(edited.radiusSm, (4 * 0.7).roundToDouble());
      expect(edited.radiusImg, 4);
    });
  });

  group('the two arms', () {
    test('the spec arm edits the spec, leaving colour to the core', () {
      final spec = PremiumLooks.byId('spotlight')!;
      final edited = ThemeOverrideApplier.applyToSpec(
        spec,
        const ThemeOverrides(motion: 'snap', accent: 'ember'),
      );
      expect(edited.motion, MotionCharacter.snap);
      // Colour is NOT applied here: it reaches the theme through the core that
      // buildWith is handed, and deriving it in both places would derive it
      // twice from different inputs.
      expect(edited.accent, spec.accent);
    });

    test('an entrance-only override keeps the theme\'s own tempo', () {
      // Themes whose authored scale is 0.85 or 1.15 were being reset to 1.0 by
      // an unrelated entrance edit, because the baseline was `legacy` rather
      // than the theme's own.
      final core = DetailThemes.byId('broadsheet');
      final plain = AppTheme.fromDetail(core);
      final edited = ThemeOverrideApplier.buildFromDetail(
        core,
        const ThemeOverrides(entrance: 'rise'),
        authored: core,
      );
      expect(edited.motion.scale, plain.motion.scale);
    });

    test('the non-spec arm supplies only the groups that were edited', () {
      final core = DetailThemes.byId('signal');
      final themed = ThemeOverrideApplier.buildFromDetail(
        core,
        const ThemeOverrides(focusExpression: 'parallax'),
        authored: core,
      );
      expect(themed.focus.expression, FocusExpression.parallax);
      // Everything else stays at the defaults `fromDetail` would have given it.
      final plain = AppTheme.fromDetail(core);
      expect(themed.motion.scale, plain.motion.scale);
    });

    test('editing grain does not silently retime the app', () {
      // `MotionTokens.fromDetail` derives its tempo from grain, so a texture
      // edit could otherwise change every animation in the app — "it feels
      // slower since I changed the look" is not a diagnosable report.
      final core = DetailThemes.byId('signal');
      final plain = AppTheme.fromDetail(core);
      // The edited core carries the new grain; `authored` is the theme as the
      // registry wrote it, which is where the tempo must come from.
      final grainy = ThemeOverrideApplier.buildFromDetail(
        core.withTokens(grain: 0.8),
        const ThemeOverrides(grain: '0.8'),
        authored: core,
      );
      expect(grainy.motion.scale, plain.motion.scale);
    });
  });

  group('the controller', () {
    test('Classic ignores overrides entirely', () async {
      await AppThemeController.instance.select(AppThemes.legacyId);
      await AppThemeController.instance.setOverrides(
        const ThemeOverrides(focusExpression: 'parallax'),
      );
      // Classic is the honestly UNTHEMED option — its token groups are no-ops
      // by construction, and pretending otherwise would make it a theme with
      // nothing to edit rather than a deliberate absence.
      expect(AppThemeController.instance.theme.focus.expression,
          isNot(FocusExpression.parallax));
      await AppThemeController.instance.clearOverrides();
    });

    test('setting an override re-themes live, and clearing restores', () async {
      await AppThemeController.instance.select('signal');
      final before = AppThemeController.instance.theme.focus.expression;

      await AppThemeController.instance.setOverrides(
        const ThemeOverrides(focusExpression: 'parallax'),
      );
      expect(AppThemeController.instance.theme.focus.expression,
          FocusExpression.parallax);

      await AppThemeController.instance.clearOverrides();
      expect(AppThemeController.instance.theme.focus.expression, before,
          reason: 'clearing must return the Look\'s own value');
    });

    test('a change notifies, which is what re-themes the running app',
        () async {
      await AppThemeController.instance.select('signal');
      await AppThemeController.instance.clearOverrides();
      var notified = 0;
      void listener() => notified++;
      AppThemeController.instance.addListener(listener);
      await AppThemeController.instance.setOverrides(
        const ThemeOverrides(motion: 'snap'),
      );
      AppThemeController.instance.removeListener(listener);
      expect(notified, greaterThan(0));
      await AppThemeController.instance.clearOverrides();
    });

    test('setting the same overrides again is a no-op', () async {
      await AppThemeController.instance.select('signal');
      await AppThemeController.instance.setOverrides(
        const ThemeOverrides(motion: 'snap'),
      );
      var notified = 0;
      void listener() => notified++;
      AppThemeController.instance.addListener(listener);
      await AppThemeController.instance.setOverrides(
        const ThemeOverrides(motion: 'snap'),
      );
      AppThemeController.instance.removeListener(listener);
      expect(notified, 0);
      await AppThemeController.instance.clearOverrides();
    });
  });

  group('the companions an edit drags with it', () {
    test('picking a scale or lift focus is not silently inert', () {
      // `FocusTokens.legacy` is a RING's geometry — scale 1, lift 0 — so
      // reusing it made "scale" and "lift" do visibly nothing.
      final core = DetailThemes.byId('signal');
      for (final e in [FocusExpression.scale, FocusExpression.lift]) {
        final t = ThemeOverrideApplier.buildFromDetail(
          core,
          ThemeOverrides(focusExpression: e.name),
          authored: core,
        );
        expect(t.focus.expression, e);
        expect(t.focus.scale > 1 || t.focus.lift > 0, isTrue,
            reason: '${e.name} focus must actually move something');
      }
    });

    test('choosing glass makes a surface that can be seen through', () {
      final core = DetailThemes.byId('signal');
      final t = ThemeOverrideApplier.buildFromDetail(
        core,
        const ThemeOverrides(separation: 'glass'),
        authored: core,
      );
      expect(t.surface.glassOpacity, lessThan(1));
    });

    test('an idle policy dims by something', () {
      final core = DetailThemes.byId('signal');
      final t = ThemeOverrideApplier.buildFromDetail(
        core,
        const ThemeOverrides(idle: 'dimChrome'),
        authored: core,
      );
      expect(t.idle.depth, greaterThan(0));
    });

    test('bloom is a pixel radius, not a fraction', () {
      // Clamped to 0..1 the control was imperceptible; the shipped specs use
      // 18 to 26.
      expect(const ThemeOverrides(bloom: '22').resolvedBloom, 22);
    });

    test('an accent-filled button follows the accent; a neutral one does not',
        () {
      final signal = DetailThemes.byId('signal');
      final edited = signal.withTokens(accent: const Color(0xFFFF6B35));
      if (signal.btnFill.withValues(alpha: 1) ==
          signal.accent.withValues(alpha: 1)) {
        expect(edited.btnFill, const Color(0xFFFF6B35),
            reason: 'an accent button that ignores the accent is not one');
      } else {
        expect(edited.btnFill, signal.btnFill,
            reason: 'a neutral button must not become the accent');
      }
    });
  });

  group('the legibility floor', () {
    double contrast(Color a, Color b) {
      final la = a.withValues(alpha: 1).computeLuminance();
      final lb = b.withValues(alpha: 1).computeLuminance();
      final hi = la > lb ? la : lb;
      final lo = la > lb ? lb : la;
      return (hi + 0.05) / (lo + 0.05);
    }

    test('a white ground cannot keep white text', () {
      // Two taps from an app that cannot be navigated back out of: reaching the
      // reset means reading the screens between here and it.
      final t = ThemeCoreResolver.resolve(
        'signal',
        const ThemeOverrides(ground: 'snow'),
      );
      expect(contrast(t.tx, t.ground), greaterThanOrEqualTo(3.0));
    });

    test('an explicit unreadable ink is overridden, not honoured', () {
      // Hue is free; contrast is not. An unusable app is not a preference.
      ThemeCoreResolver.debugReset();
      final t = ThemeCoreResolver.resolve(
        'signal',
        const ThemeOverrides(ground: 'snow', ink: 'pure_white'),
      );
      expect(contrast(t.tx, t.ground), greaterThanOrEqualTo(3.0));
    });

    test('a readable choice is left exactly alone', () {
      ThemeCoreResolver.debugReset();
      final t = ThemeCoreResolver.resolve(
        'signal',
        const ThemeOverrides(ground: 'snow', ink: 'near_black'),
      );
      expect(t.tx, const Color(0xFF0E0E10));
      expect(t.lightGround, isTrue);
      // And the pane came with it: a white page over a near-black sheet is
      // unsatisfiable for any single ink.
      expect(t.pane.computeLuminance(), greaterThan(0.5));
    });

    test('the floor survives the text-brightness preset', () {
      // The preset blends text toward the ground and runs LAST, so a pair that
      // cleared 3:1 when it was chosen could fall under it afterwards. A floor
      // the final step can undo is not a floor.
      for (final preset in TextBrightness.values) {
        ThemeCoreResolver.debugReset();
        final core = ThemeCoreResolver.resolve(
          'signal',
          const ThemeOverrides(ground: 'putty', ink: 'near_black'),
        );
        final resolved = AppThemeAdapter.resolveCoreText(core, preset);
        expect(contrast(resolved.tx, resolved.ground),
            greaterThanOrEqualTo(3.0),
            reason: 'unreadable under ${preset.name}');
      }
    });

    test('secondary text follows a forced ink, not the old one', () {
      // A ground-only edit can flip the PRIMARY text to the opposite pole; the
      // tones derived from it have to come along or a snow ground gets black
      // titles over translucent white metadata.
      ThemeCoreResolver.debugReset();
      final t = ThemeCoreResolver.resolve(
        'signal',
        const ThemeOverrides(ground: 'snow'),
      );
      expect(contrast(t.tx2.withValues(alpha: 1), t.ground),
          greaterThanOrEqualTo(3.0));
    });

    test('the cursor cannot be made invisible', () {
      // A focus colour you cannot see is a television you cannot navigate. An
      // unreadable choice falls back to the theme's own, which was authored to
      // work — the same rule an unrecognised swatch already follows.
      ThemeCoreResolver.debugReset();
      final t = ThemeCoreResolver.resolve(
        'signal',
        const ThemeOverrides(ground: 'snow', focusColor: 'white'),
      );
      // The authored focus is only the FIRST fallback — Signal's gold is
      // 1.67:1 on snow, so it fails too and a readable pole is used. What is
      // guaranteed is that the cursor can be seen, not which colour it is.
      expect(contrast(t.focus, t.ground), greaterThanOrEqualTo(2.0));
    });

    test('the ground palette actually contains grounds', () {
      // The mark palette is all above 5% luminance so it can be FOUND on a dark
      // background — which means it contains nothing you could use as one.
      expect(ThemePalette.grounds.any((s) => s.color.computeLuminance() < 0.02),
          isTrue);
      expect(ThemePalette.grounds.any((s) => s.color.computeLuminance() > 0.8),
          isTrue);
    });
  });
}
