import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:debrify/screens/settings/widgets/settings_widgets.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/widgets/cloud/cloud_theme.dart';
import 'package:debrify/widgets/detail/theme/detail_themes.dart';
import 'package:debrify/widgets/home/home_theme.dart';
import 'package:debrify/widgets/see_all/see_all_theme.dart';

/// The compatibility contract: every value in `AppThemes.legacy` PINS a
/// literal that still exists as a constant somewhere in the tree (the split
/// decision keeps those constants alive for frozen surfaces). If either side
/// drifts, this fails — not a user's screen.
void main() {
  final legacy = AppThemes.legacy;

  test('legacy identity', () {
    expect(legacy.id, AppThemes.legacyId);
    expect(legacy.isLegacy, isTrue);
    expect(legacy.brightness, Brightness.dark);
    expect(identical(legacy.core, DetailThemes.signal), isTrue,
        reason: 'legacy core is Signal (details resolve their own pref)');
  });

  test('home subprofile pins HomeTheme', () {
    expect(legacy.home.bg, HomeTheme.bg);
    expect(legacy.home.chromeAccent, HomeTheme.chromeAccent);
    expect(legacy.home.focus, HomeTheme.focusGold);
    expect(legacy.home.focusDeep, HomeTheme.focusGoldDeep);
    expect(legacy.home.highlight, HomeTheme.highlight);
    expect(legacy.home.danger, HomeTheme.danger);
    final wash = legacy.home.wash as RadialGradient;
    final homeWash = HomeTheme.pageBackground.gradient! as RadialGradient;
    expect(wash.colors, homeWash.colors);
    expect(wash.stops, homeWash.stops);
    expect(wash.center, homeWash.center);
    expect(wash.radius, homeWash.radius);
  });

  test('seeAll subprofile pins kSeeAll*', () {
    expect(legacy.seeAll.bg, kSeeAllBg);
    expect(legacy.seeAll.accent, kSeeAllAccent);
    expect(legacy.seeAll.accent2, kSeeAllAccent2);
    expect(legacy.seeAll.panel, kSeeAllPanel);
    expect(legacy.seeAll.panel2, kSeeAllPanel2);
    expect(legacy.seeAll.accentBorder, kSeeAllAccentBorder);
    expect(legacy.seeAll.line, kSeeAllLine);
  });

  test('settings subprofile pins kSettings*', () {
    expect(legacy.settings.bg, kSettingsBg);
    expect(legacy.settings.accent, kSettingsAccent);
    expect(legacy.settings.accent2, kSettingsAccent2);
    expect(legacy.settings.panel, kSettingsPanel);
    expect(legacy.settings.panel2, kSettingsPanel2);
    expect(legacy.settings.success, kSettingsGreen);
    expect(legacy.settings.danger, kSettingsRed);
    expect(legacy.settings.warning, kSettingsAmber);
    expect(legacy.settings.line, kSettingsLine);
    expect(legacy.settings.dim, kSettingsDim);
    expect(legacy.settings.dim2, kSettingsDim2);
  });

  test('cloud subprofile pins CloudTheme, category/status split intact', () {
    expect(legacy.cloud.bg, CloudTheme.bg);
    expect(legacy.cloud.accent, CloudTheme.accent);
    expect(legacy.cloud.menuSurface, CloudTheme.menuSurface);
    expect(legacy.cloud.statusSuccess, CloudTheme.green);
    expect(legacy.cloud.statusWarning, CloudTheme.amber);
    expect(legacy.cloud.statusError, CloudTheme.red);
    expect(legacy.cloud.destructive, CloudTheme.red);
    expect(legacy.cloud.categoryVideo, CloudTheme.blue);
    // Amber is BOTH folder category and warning under legacy — the split
    // exists so a real theme can separate them.
    expect(legacy.cloud.categoryFolder, CloudTheme.amber);
    expect(legacy.cloud.categorySeason, CloudTheme.purple);
    final wash = legacy.cloud.wash as RadialGradient;
    expect(wash.colors, CloudTheme.pageGradient.colors);
    expect(wash.stops, CloudTheme.pageGradient.stops);
  });

  test('shell subprofile pins the main.dart literals', () {
    // These three literals live in main.dart (Scaffold ink, TV sidebar scrim,
    // rail lights-off veil) and cannot be imported — the values are asserted
    // against what main.dart ships. If main.dart's literals change, update
    // BOTH sides knowingly.
    expect(legacy.shell.ink, const Color(0xFF0D0B1A));
    expect(legacy.shell.ink, HomeTheme.bg,
        reason: 'main.dart deliberately uses HomeTheme.bg as shell ink');
    expect(legacy.shell.sidebarScrim, const Color(0x8A05060E));
    expect(legacy.shell.railVeil, const Color(0xEB0D0B1A));
  });

  test('byId falls back to legacy for unknown ids, never a random theme', () {
    expect(AppThemes.byId('legacy').isLegacy, isTrue);
    expect(AppThemes.byId('no_such_theme').isLegacy, isTrue);
    expect(AppThemes.byId('').isLegacy, isTrue);
    expect(AppThemes.byId('broadsheet').id, 'broadsheet');
    expect(AppThemes.byId('broadsheet').isLegacy, isFalse);
  });

  test('brightness threshold: ground luminance > 0.5, agreeing with '
      'lightGround for every shipped theme', () {
    for (final core in DetailThemes.all) {
      final app = AppTheme.fromDetail(core);
      final light = core.ground.computeLuminance() > 0.5;
      expect(app.brightness,
          light ? Brightness.light : Brightness.dark,
          reason: core.id);
      // The detail layer's own flag must agree — a theme marked lightGround
      // whose ground reads dark (or vice versa) is a theme-definition bug.
      expect(core.lightGround, light, reason: core.id);
    }
  });
}
