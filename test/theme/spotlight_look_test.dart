import 'package:debrify/theme/app_focus.dart';
import 'package:debrify/theme/app_looks.dart';
import 'package:debrify/theme/app_motion.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_controller.dart';
import 'package:debrify/theme/premium_looks.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The Spotlight Look — the thing that actually switches the focus mechanic on.
///
/// Without a Look naming it, `FocusExpression.parallax` has no consumer and the
/// two layouts render with the app's ordinary ring. So the property that
/// matters most here is not "the prefs were written" but "the theme that
/// arrives is the one with the mechanic in it".
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    LookApplier.debugResetGenerations();
  });

  test('the Look is registered, valid, and names only shipped things', () {
    final look = AppLooks.all.firstWhere((l) => l.id == 'spotlight');
    expect(AppLooks.validate(), isEmpty,
        reason: 'a Look naming a withheld theme walks around the gate');
    expect(look.values['app_theme'], 'spotlight');
    expect(look.values['detail_page_style'], 'showcase');
    expect(look.values['tv_home_style'], 'spotlight');
    expect(look.values['tv_sidebar_style'], 'pill');
  });

  test('the theme it names carries the mechanic', () {
    final spec = PremiumLooks.byId('spotlight');
    expect(spec, isNotNull,
        reason: 'absent from PremiumLooks.all resolves to Signal silently');
    final theme = spec!.build();
    expect(theme.focus.expression, FocusExpression.parallax);
    expect(theme.motion.character, MotionCharacter.settle);
    // The spring has to survive ThemeSpec's `copyWith` rebuild, or the whole
    // mechanic quietly falls back to a curve with no error anywhere.
    expect(theme.motion.focusSpring, isNotNull);
  });

  test('applying it writes every key AND the detail_theme mirror', () async {
    final look = AppLooks.all.firstWhere((l) => l.id == 'spotlight');
    await LookApplier.apply(look);

    expect(StorageService.appThemeCached, 'spotlight');
    expect(StorageService.detailPageStyleCached, 'showcase');
    expect(StorageService.tvHomeStyleCached, 'spotlight');
    expect(StorageService.tvSidebarStyleCached, 'pill');
    // The controller owns this one; the Look must not name it, and must still
    // end up with it correct.
    expect(StorageService.detailThemeCached, 'spotlight');
  });

  test('re-applying repairs a hand-changed Details Theme', () async {
    // The exact sequence that used to leave the Look half-applied: apply,
    // change the mirror by hand, apply again. `select` returned early because
    // the APP theme already matched, and never repaired the mirror — so the
    // Look reported itself active while the details page rendered something
    // else.
    final look = AppLooks.all.firstWhere((l) => l.id == 'spotlight');
    await LookApplier.apply(look);
    expect(StorageService.detailThemeCached, 'spotlight');

    await StorageService.setDetailTheme('noir');
    expect(look.isActive, isFalse,
        reason: 'a hand-changed mirror must read as Custom, not as active');

    LookApplier.debugResetGenerations();
    await LookApplier.apply(look);
    expect(StorageService.detailThemeCached, 'spotlight');
    expect(look.isActive, isTrue);
  });

  test('a manual layout change afterwards sticks', () async {
    final look = AppLooks.all.firstWhere((l) => l.id == 'spotlight');
    await LookApplier.apply(look);
    await StorageService.setTvHomeStyle('canvas');
    expect(StorageService.tvHomeStyleCached, 'canvas');
    expect(look.isActive, isFalse);
  });

  test('the live controller resolves it, not a Signal fallback', () async {
    await AppThemeController.instance.select('spotlight');
    final theme = AppThemeController.instance.theme;
    expect(theme.id, 'spotlight');
    expect(theme.isLegacy, isFalse);
    // This is the path the running app reads. `AppThemes.byId` is not it —
    // that divergence is what left five looks silently inert once before.
    expect(theme.focus.expression, FocusExpression.parallax);
  });
}
