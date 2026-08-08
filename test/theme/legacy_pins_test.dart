import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:debrify/screens/settings/widgets/settings_widgets.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/widgets/cloud/cloud_theme.dart';
import 'package:debrify/widgets/detail/theme/detail_themes.dart';
import 'package:debrify/widgets/home/home_theme.dart';
import 'package:debrify/widgets/see_all/see_all_theme.dart';

/// The compatibility contract: `AppThemes.legacy` must reproduce the literal
/// each token replaced, so `legacy` renders today's app exactly.
///
/// Two kinds of assertion here, and the difference is worth knowing:
///
/// * **Against a live source** — `HomeTheme.focusGold`, `kSeeAll*`,
///   `kSettings*`, `CloudTheme.*`. Those constants survive because frozen
///   surfaces still import them (the split), so these catch drift on EITHER
///   side. These are the strong ones.
/// * **Against a repeated literal** — tokens whose source literal was inline
///   and is now gone (`seeAll.card`, the calendar profile, most shell and
///   surface tokens). Nothing survives to compare with, so these can only
///   pin the value going forward; they cannot prove the original swap was
///   right. That proof came from review and from `git diff` at the time.
///
/// A reviewer flagged the second group as weaker than the header claimed —
/// correct, hence this note rather than a false claim of uniform strength.
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
    // Surfaces that carry theme ink, so they had to become tokens.
    expect(legacy.home.sheetBg, const Color(0xFF0F172A));
    expect(legacy.home.dialogBg, const Color(0xFF16131F));
    expect(legacy.home.controlBg, const Color(0xFF334155));
    expect(legacy.home.posterPlaceholder, const Color(0xFF111118));
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
    expect(legacy.seeAll.card, const Color(0xFF191B28));
    expect(legacy.seeAll.danger, const Color(0xFFEF4444));
    expect(legacy.seeAll.warning, const Color(0xFFF6B94A));
    expect(legacy.seeAll.listBg, const Color(0xFF0B0910));
    // The Addons hub's bloom is the SAME gradient as Home's, verified rather
    // than assumed — that is why it pins to the shared wash instead of a
    // fourth copy of the same four stops.
    final seeAllWash = legacy.seeAll.wash as RadialGradient;
    final homeWash = legacy.home.wash as RadialGradient;
    expect(seeAllWash.colors, homeWash.colors);
    expect(seeAllWash.stops, homeWash.stops);
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
    expect(legacy.settings.sheetBg, const Color(0xFF0B1220));
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
    expect(legacy.cloud.focusSurface, const Color(0xFF312E81));
    expect(legacy.cloud.dialogSurface, const Color(0xFF1E293B));
    final wash = legacy.cloud.wash as RadialGradient;
    expect(wash.colors, CloudTheme.pageGradient.colors);
    expect(wash.stops, CloudTheme.pageGradient.stops);
    // The hub's bloom is a SEPARATE gradient — brighter, differently stopped.
    // Pinning it against cloud.wash would silently accept the wrong one.
    final hub = legacy.cloud.hubWash as RadialGradient;
    expect(hub.colors, const [
      Color(0xFF322A6B),
      Color(0xFF1A1734),
      Color(0xFF100E20),
      Color(0xFF0D0B1A),
    ]);
    expect(hub.stops, const [0.0, 0.42, 0.72, 1.0]);
    expect(hub.stops, isNot(wash.stops));
  });

  test('the shared sheet surface is one token, not several', () {
    // cw_card_menu, both merged-details quick-action sheets and the episode
    // options sheet all pinned the SAME literal; Cloud's context menu is a
    // different one and keeps its own token. Asserting both halves stops a
    // future edit from quietly collapsing them.
    expect(legacy.sheetSurface, const Color(0xFF141019));
    expect(legacy.cloud.menuSurface, isNot(legacy.sheetSurface));
  });

  test('calendar subprofile pins trakt_calendar_screen literals', () {
    expect(legacy.calendar.bg, const Color(0xFF060816));
    expect(legacy.calendar.sheetBg, const Color(0xFF0C1222));
    expect(legacy.calendar.panel, const Color(0xFF11131B));
    expect(legacy.calendar.card, const Color(0xFF141219));
    expect(legacy.calendar.card2, const Color(0xFF0A0B12));
    expect(legacy.calendar.row, const Color(0xFF181922));
    expect(legacy.calendar.badgeGround, const Color(0xFF191B23));
    // white @ 0.04 — the grid's hairline, pinned as the composited literal.
    expect(legacy.calendar.line, Colors.white.withValues(alpha: 0.04));
    expect(legacy.calendar.accent, const Color(0xFFE50914));
    // ORDER matters: _accentFor hashes a title into this list, so a reorder
    // would silently recolour every show even though the SET is unchanged.
    expect(legacy.calendar.accentPalette, const [
      Color(0xFFE50914),
      Color(0xFFF97316),
      Color(0xFFFB7185),
      Color(0xFFDC2626),
      Color(0xFFEF4444),
      Color(0xFFB91C1C),
    ]);
  });

  test('calendar tones are six, distinct, AND legible on their panel', () {
    // Distinctness alone is not enough: an earlier ramp was six distinct
    // tones that sat at ~1.3:1 on Broadsheet's paper panel, where they carry
    // dates and episode times. Both properties or neither.
    double contrast(Color a, Color b) {
      final la = a.withValues(alpha: 1).computeLuminance();
      final lb = b.withValues(alpha: 1).computeLuminance();
      final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
      return (hi + 0.05) / (lo + 0.05);
    }

    for (final core in DetailThemes.all) {
      final cal = AppTheme.fromDetail(core).calendar;
      expect(cal.accentPalette, hasLength(6), reason: core.id);
      expect(cal.accentPalette.toSet().length, 6,
          reason: '${core.id}: every tone must be distinct — the grid uses '
              'them to tell shows apart');
      for (var i = 0; i < cal.accentPalette.length; i++) {
        expect(contrast(cal.accentPalette[i], cal.panel),
            greaterThanOrEqualTo(3.0),
            reason: '${core.id}: tone $i on the calendar panel');
        expect(contrast(cal.accentPalette[i], cal.bg),
            greaterThanOrEqualTo(3.0),
            reason: '${core.id}: tone $i on the calendar ground');
      }
    }
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
    // Nav chrome, from the four nav widgets. Same rule: change a nav literal
    // and you change BOTH sides knowingly.
    expect(legacy.shell.railBg, const Color(0xFF120F24));
    expect(legacy.shell.railInk, const Color(0xFF0A0910));
    expect(legacy.shell.barBg, const Color(0xF712101F));
    expect(legacy.shell.navAccent, const Color(0xFF7B5CFF));
    expect(legacy.shell.navFocus, const Color(0xFFA78BFA));
    expect(legacy.shell.navLabel, const Color(0xFFC7BFFF));
    expect(legacy.shell.navSheetBg, const Color(0xFF161327));
  });

  test('nav chrome separates from the page and stays legible', () {
    // NOT a luminance-direction claim: separation is directional per theme
    // (dark themes step lighter, paper themes step darker), so asserting
    // "rail is lighter" would encode a dark-theme assumption and fail
    // Broadsheet — as an earlier draft of this test did.
    double lum(Color c) => c.withValues(alpha: 1).computeLuminance();
    double contrast(Color a, Color b) {
      final la = lum(a), lb = lum(b);
      final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
      return (hi + 0.05) / (lo + 0.05);
    }

    for (final core in DetailThemes.all) {
      final app = AppTheme.fromDetail(core);
      final s = app.shell;
      // Deliberately NOT `railBg != ink`: Noir, Phosphor and Vault set
      // pane == ground on purpose (flat, high-contrast looks), and their
      // rails separate with a hairline border rather than a ground step.
      // Asserting a ground difference would outlaw a legitimate theme.
      expect(s.railBg, core.pane,
          reason: '${core.id}: the desktop rail is the theme\'s own surface '
              'step, so its direction follows the theme');
      expect(s.railInk, core.railBg,
          reason: '${core.id}: the TV rail is the theme\'s own rail ground');
      // The label sits ON the rail — the one place chrome can become
      // unreadable when a theme's accent is close to its rail ground.
      expect(contrast(s.navLabel, s.railBg), greaterThanOrEqualTo(3.0),
          reason: '${core.id}: active nav label on the rail');
      expect(contrast(s.navLabel, s.railInk), greaterThanOrEqualTo(3.0),
          reason: '${core.id}: active nav label on the TV rail');
    }
  });

  test('onAccent is legible on the accent it sits on, every theme', () {
    // Half the shipped themes have LIGHT accents (Broadcast yellow, Verdant
    // lime, Blueprint cyan, Noir/Frost white) where a hardcoded white label
    // ranges from hard to read to invisible.
    double contrast(Color a, Color b) {
      final la = a.withValues(alpha: 1).computeLuminance();
      final lb = b.withValues(alpha: 1).computeLuminance();
      final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
      return (hi + 0.05) / (lo + 0.05);
    }

    // Legacy's Settings fills are violet; white is what shipped and must stay.
    expect(legacy.inkOn(legacy.settings.accent), Colors.white);
    expect(legacy.inkOn(legacy.cloud.accent), Colors.white);
    for (final core in DetailThemes.all) {
      final app = AppTheme.fromDetail(core);
      for (final fill in <(String, Color)>[
        ('core', core.accent),
        ('settings', app.settings.accent),
        ('cloud', app.cloud.accent),
        ('home', app.home.chromeAccent),
        ('calendar', app.calendar.accent),
      ]) {
        // 4.0: these are button labels and glyphs on a filled swatch, and it
        // is the bar legacy itself meets (white on violet ≈ 4.38).
        expect(contrast(app.inkOn(fill.$2), fill.$2),
            greaterThanOrEqualTo(4.0),
            reason: '${core.id}: ink on the ${fill.$1} accent swatch');
      }
    }
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
