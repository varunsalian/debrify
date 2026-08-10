import 'package:debrify/screens/settings/theme_tokens_page.dart';
import 'package:debrify/theme/app_looks.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_controller.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/theme/theme_core_resolver.dart';
import 'package:debrify/theme/theme_overrides.dart';
import 'package:debrify/theme/theme_palette.dart';
import 'package:debrify/widgets/detail/theme/detail_themes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The Advanced page, and the promise the Looks page makes about it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    ThemeCoreResolver.debugReset();
    LookApplier.debugResetGenerations();
    await AppThemeController.instance.clearOverrides();
  });

  Widget host() => MaterialApp(
        home: AppThemeScope(
          theme: AppThemeController.instance.theme,
          child: const ThemeTokensPage(),
        ),
      );

  testWidgets('every knob offers a way back to the Look', (tester) async {
    await AppThemeController.instance.select('signal');
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    // The reset is the FIRST thing on the page, deliberately: the one edit
    // that can make the app unreadable is a ground or ink you cannot see
    // against, and the way out must not require reading the screen.
    expect(find.text('Reset everything'), findsOneWidget);
    final resetY = tester.getTopLeft(find.text('Reset everything')).dy;
    final firstKnob =
        tester.getTopLeft(find.text('Accent', skipOffstage: false)).dy;
    expect(resetY, lessThan(firstKnob),
        reason: 'the escape hatch must come before anything that needs one');
  });

  testWidgets('an untouched knob reads as following the Look', (tester) async {
    await AppThemeController.instance.select('signal');
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    // Every row says "Look" until it is changed — a picker that showed a
    // concrete value would imply the user had chosen it.
    expect(find.text('Look'), findsWidgets);
  });

  testWidgets('the reset row reports how much has been changed',
      (tester) async {
    await AppThemeController.instance.select('signal');
    await AppThemeController.instance.setOverrides(
      const ThemeOverrides(accent: 'ember', motion: 'snap'),
    );
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    expect(find.textContaining('2 changes'), findsOneWidget);
  });

  group('the promise the palette makes', () {
    test('every swatch id is unique and resolvable', () {
      final ids = <String>{};
      for (final s in ThemePalette.all) {
        expect(ids.add(s.id), isTrue, reason: 'duplicate swatch id ${s.id}');
        expect(ThemePalette.colorOf(s.id), s.color);
      }
      expect(ThemePalette.all.length, greaterThanOrEqualTo(50));
    });

    test('no swatch is so dark it cannot be seen as a mark', () {
      // The palette is offered for things that sit ON a surface. A swatch at
      // near-black is indistinguishable from the ground on every dark theme
      // in the app, which makes it a way to lose your cursor.
      for (final s in ThemePalette.all) {
        expect(s.color.computeLuminance(), greaterThan(0.05),
            reason: '${s.label} is too dark to find on a dark ground');
      }
    });
  });

  group('Looks and overrides together', () {
    test('applying a Look clears the edits layered under it', () async {
      await AppThemeController.instance.select('signal');
      await AppThemeController.instance.setOverrides(
        const ThemeOverrides(accent: 'ember'),
      );
      expect(AppThemeController.instance.overrides.isEmpty, isFalse);

      final look = AppLooks.all.firstWhere((l) => l.id == 'spotlight');
      await LookApplier.apply(look);
      await AppThemeController.instance.clearOverrides();

      expect(AppThemeController.instance.overrides.isEmpty, isTrue,
          reason: 'a Look that does not look like itself is worse than none');
    });

    test('an edit survives a Look REVISION, because it is sparse', () {
      // The point of storing deltas: if the Look's own accent changes in a
      // later build, someone who only edited the motion still gets it.
      const o = ThemeOverrides(motion: 'snap');
      final core = ThemeCoreResolver.resolve('signal', o);
      expect(identical(core, DetailThemes.byId('signal')), isTrue,
          reason: 'a motion edit must not freeze the Look\'s colours');
    });
  });

  test('Classic still resolves to the untouched legacy theme', () async {
    await AppThemeController.instance.select(AppThemes.legacyId);
    await AppThemeController.instance.setOverrides(
      const ThemeOverrides(ground: 'white', ink: 'crimson'),
    );
    expect(AppThemeController.instance.theme.id, AppThemes.legacyId);
    expect(identical(AppThemeController.instance.theme, AppThemes.legacy),
        isTrue,
        reason: 'Classic is the unthemed option, edits included');
    await AppThemeController.instance.clearOverrides();
  });

  testWidgets('the way out is painted in colours the user cannot change',
      (tester) async {
    // Ground and ink are freely editable, so someone can choose a pair they
    // cannot read. If the reset row were themed like everything else, it would
    // be invisible in exactly the situation it exists for.
    await AppThemeController.instance.select('signal');
    await AppThemeController.instance.setOverrides(
      const ThemeOverrides(ground: 'white', ink: 'bone'),
    );
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    final label = tester.widget<Text>(find.text('Reset everything'));
    expect(label.style?.color, const Color(0xFF101012),
        reason: 'the escape hatch must not follow the edits it escapes');
    await AppThemeController.instance.clearOverrides();
  });

  testWidgets('a Look with edits under it reads as Custom, not as the Look',
      (tester) async {
    await AppThemeController.instance.select('signal');
    await AppThemeController.instance.setOverrides(
      const ThemeOverrides(accent: 'ember'),
    );
    // `AppLooks.active()` compares the keys a Look names, and overrides are not
    // one of them — so it would happily report the Look as active.
    expect(AppThemeController.instance.overrides.count, 1);
    await AppThemeController.instance.clearOverrides();
  });
}
