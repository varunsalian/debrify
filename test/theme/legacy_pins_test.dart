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

  test('downloads subprofile pins the slate/indigo ramp', () {
    // Downloads is the one surface not painted in the app's purple. These are
    // repeated-literal pins (the inline sources are gone), so they fix the
    // values going forward rather than proving the swap — see the header note.
    final d = legacy.downloads;
    expect(d.fieldFill, const Color(0xFF111827));
    expect(d.previewCard, const Color(0x141E293B));
    expect(d.line, const Color(0xFF334155));
    expect(d.chipBorder, const Color(0xFF475569).withValues(alpha: 0.3));
    expect(d.metaIcon, const Color(0xFF94A3B8));
    expect(d.accent, const Color(0xFF6366F1));
    expect(d.accent2, const Color(0xFF8B5CF6));
    expect(d.addAccent, const Color(0xFF10B981));
    expect(d.onAccent, Colors.white);
    expect(d.shimmerBase, const Color(0xFF223049));
    expect(d.shimmerHighlight, const Color(0xFF2A3A55));
  });

  test('downloads reuses existing roles rather than re-declaring them', () {
    // Two roles that LOOK reusable are deliberately NOT: downloads.line is
    // value-equal to home.controlBg but is a hairline, not a filled control,
    // and downloads.addAccent is value-equal to cloud.statusSuccess but is a
    // button's identity, not a status. Value equality under legacy is not
    // role equality under a theme.
    expect(legacy.downloads.line, legacy.home.controlBg);
    expect(legacy.downloads.addAccent, legacy.cloud.statusSuccess);
    // Five Downloads roles were EXACTLY equal to roles that already existed.
    // Duplicating them into DownloadsTokens would let the two copies drift,
    // so the surface reads them from their owning profile instead. If one of
    // these ever stops matching, the surface must grow its own token — not be
    // left silently pointing at a colour that moved.
    expect(legacy.settings.sheetBg, const Color(0xFF0B1220)); // sheet ground
    expect(legacy.home.controlBg, const Color(0xFF334155)); // chip fill only
    expect(legacy.cloud.dialogSurface, const Color(0xFF1E293B)); // raised pill
    expect(legacy.settings.accent, const Color(0xFF7B5CFF)); // keyboard latch
  });

test('youtube subprofile pins the Browse shell and the grid ink ladder', () {
    final y = legacy.youtube;
    // Live-source pins: both shared widgets still carry these literals as
    // their own defaults, so these catch drift on EITHER side.
    expect(y.focus, const Color(0xFF7B5CFF)); // TvTextField.accent
    expect(y.keyboardPanel, const Color(0xF01A1630)); // TvKeyboardPanel._bg
    expect(y.onFocus, Colors.white); // TvKeyboardPanel.inkOnAccent
    // Repeated-literal pins: the grid's ink was inline alphas struck from
    // `Colors.white`, so these fix the ladder going forward rather than
    // proving the swap — see the header note.
    expect(y.textBody, Colors.white.withValues(alpha: 0.8));
    expect(y.textDim, Colors.white.withValues(alpha: 0.5));
    expect(y.textFaint, Colors.white.withValues(alpha: 0.35));
    // The rungs must stay ordered or "dim" and "faint" have swapped meaning —
    // a silent inversion no dark theme would reveal.
    expect(y.textBody.a, greaterThan(y.textDim.a));
    expect(y.textDim.a, greaterThan(y.textFaint.a));
  });

  test('youtube reads existing roles rather than re-declaring them', () {
    // `youtube.focus` is value-equal to `seeAll.accent` under legacy and is
    // deliberately NOT it: a DPAD cursor and a surface accent answer
    // different questions. The surface still reads `seeAll.accent` for the
    // spinners, the Retry fill and the empty-state glyph.
    expect(legacy.youtube.focus, legacy.seeAll.accent);
    // Roles that were EXACTLY equal to ones that already existed, so the
    // surface reads them from their owning profile instead of holding a
    // second copy. If one of these ever stops matching, YouTube must grow its
    // own token — not be left silently pointing at a colour that moved.
    expect(legacy.seeAll.bg, kSeeAllBg); // Browse's Scaffold ground
    expect(legacy.core.tx, Colors.white); // full-strength panel/field ink
    expect(legacy.settings.sheetBg, const Color(0xFF0B1220)); // battery sheet
    expect(legacy.downloads.line, const Color(0xFF334155)); // handle + button
    expect(legacy.downloads.accent, const Color(0xFF6366F1)); // banner + Allow
    expect(legacy.downloads.accent2, const Color(0xFF8B5CF6)); // banner stop 2
  });

test('playlist subprofile pins the surface literals', () {
    // Repeated-literal pins: these fix the values going forward rather than
    // proving the swap — see the header note.
    final p = legacy.playlist;
    expect(p.card, const Color(0xFF1E293B));
    expect(p.fieldFill, const Color(0xFF1E293B));
    expect(p.sheetPanel, const Color(0xF5181820));
    expect(p.posterPlaceholder, const Color(0xFF1A1A2E));
    expect(p.accent, const Color(0xFF6366F1));
    expect(p.controlFill, Colors.white.withValues(alpha: 0.15));
    expect(p.rowFill, Colors.white.withValues(alpha: 0.03));
    expect(p.hairline, Colors.white.withValues(alpha: 0.1));
    expect(p.focusRing, Colors.white.withValues(alpha: 0.3));
    expect(p.favoriteAccent, const Color(0xFFFFD700));
    expect(p.ink2, Colors.white70);
    expect(p.ink3, Colors.white.withValues(alpha: 0.5));
    expect(p.statusWatched, const Color(0xFF059669));
    expect(p.destructive, const Color(0xFFFF6B6B));
    // Pinned to the SWATCH, because that is what the screens write today.
    // `Color.==` is runtimeType-sensitive and `Colors.blue` / `Colors.orange`
    // are `MaterialColor`s, so a bare hex would not compare equal even though
    // the painted ARGB is identical — hence `isSameColorAs` for the value.
    expect(p.progressPlayed, Colors.blue);
    expect(p.progressPlayed, isSameColorAs(const Color(0xFF2196F3)));
    expect(p.warning, Colors.orange);
    // The Clear Progress confirm button spells this colour as a hex. Same
    // value, so the chip and the button collapse onto one token without
    // moving a pixel — assert that rather than assume it.
    expect(p.warning, isSameColorAs(const Color(0xFFFF9800)));
  });

  test('playlist reuses existing roles rather than re-declaring them', () {
    // Four roles were EXACTLY equal to roles that already existed, so the
    // surface reads them from their owning profile instead of carrying a
    // second copy that can drift. If one of these stops matching, Playlist
    // must grow its own token — not be left pointing at a colour that moved.
    expect(legacy.cloud.dialogSurface, const Color(0xFF1E293B)); // 7 dialogs
    expect(legacy.home.sheetBg, const Color(0xFF0F172A)); // confirm dialogs
    expect(legacy.core.tx, Colors.white); // explicit page ink
    expect(legacy.settings.accent, const Color(0xFF7B5CFF)); // TV input chrome
    // Deliberate NON-reuse, both value-equal under legacy. The row Card is not
    // `cloud.dialogSurface` (that is a MODAL ground, and a list of modals is
    // not a list), and the recessed search field is not one either.
    expect(legacy.playlist.card, legacy.cloud.dialogSurface);
    expect(legacy.playlist.fieldFill, legacy.cloud.dialogSurface);
    // The episode rating star is value-equal to the DPAD cursor and is left a
    // literal rather than borrowing it; its real destination is `core.rating`,
    // which is a different value (#F5C518) and therefore a sweep decision.
    expect(legacy.home.focus, const Color(0xFFFBBF24)); // == the rating star
    expect(legacy.core.rating, isNot(legacy.home.focus));
  });

test('stremioTv subprofile pins the tuner literals', () {
    // Repeated-literal pins: the inline sources are gone, so these fix the
    // values going forward rather than proving the swap — see the header note.
    final s = legacy.stremioTv;
    // Composed, not hex-pinned: `Color` stores alpha as a double, so
    // `0x0AFFFFFF` (0.0392) is not `withValues(alpha: 0.04)`.
    expect(s.surfaceFill, Colors.white.withValues(alpha: 0.04));
    expect(s.hairline, Colors.white.withValues(alpha: 0.06));
    expect(s.focusRing, Colors.white.withValues(alpha: 0.9));
    expect(s.glass, Colors.black.withValues(alpha: 0.55));
    expect(s.progressTrack, Colors.white.withValues(alpha: 0.12));
    expect(s.progressFill, Colors.white.withValues(alpha: 0.95));
    expect(s.sheetBg, const Color(0xFF101015));
    expect(s.starAccent, const Color(0xFFFFC107));
    expect(s.toggleOn, const Color(0xFF34D399));
    expect(s.toggleOff, const Color(0xFF4B465F));
    expect(s.loaderAccent, const Color(0xFF8B6BFF));
    expect(s.loaderAccent2, const Color(0xFFB9A6FF));
    expect(s.loaderGround, const Color(0xFF201636));
    expect(s.inkOnFill, const Color(0xFF0A0712));
    // ORDER matters in both ramps: the channel id hashes into the first and the
    // quality tier indexes the second, so a reorder recolours the surface while
    // leaving the SET unchanged.
    expect(s.channelIdent, const [
      Color(0xFF6C5CE7),
      Color(0xFFE84393),
      Color(0xFF00B894),
      Color(0xFFE17055),
      Color(0xFF0984E3),
      Color(0xFFFDCB6E),
      Color(0xFF00CEC9),
      Color(0xFFA29BFE),
    ]);
    expect(s.qualityTier, const [
      Color(0xFFFFD600), // 4K
      Color(0xFF536DFE), // 1080p
      Color(0xFF00BFA5), // 720p
      Color(0xFF78909C), // 480p
      Color(0xFF90A4AE), // HD
    ]);
  });

  test('stremioTv keeps the fill/hairline split that legacy hides', () {
    // surfaceFill is byte-identical to calendar.line and is NOT the same role:
    // one is a control's FILL, the other a grid HAIRLINE. Reusing calendar.line
    // would repaint every tuner header button on any theme that moves its
    // hairlines. Value equality under legacy is not role equality under a theme.
    expect(legacy.stremioTv.surfaceFill, legacy.calendar.line);
    expect(legacy.stremioTv.hairline, isNot(legacy.stremioTv.surfaceFill),
        reason: 'this surface uses white at 0.04 AND 0.06 as both fill and '
            'border — only the roles separate them');
    // Roles this surface deliberately does NOT re-declare. If one of these ever
    // stops matching, the tuner must grow its own token, not be left silently
    // pointing at a colour that moved.
    expect(legacy.home.posterPlaceholder, const Color(0xFF111118));
    expect(legacy.downloads.shimmerBase, const Color(0xFF223049));
    expect(legacy.downloads.shimmerHighlight, const Color(0xFF2A3A55));
    expect(legacy.home.chromeAccent, const Color(0xFF7B5CFF));
    // One literal, two roles: the tuner's LIVE badge is home.highlight and the
    // focus bloom is home.focusDeep. They agree under legacy and must stay
    // separate tokens so a theme can split them.
    expect(legacy.home.highlight, legacy.home.focusDeep);
  });

  test('stremioTv derived: ramps stay sized and distinct, glass stays black, '
      'the loader check glyph stays readable', () {
    double contrast(Color a, Color b) {
      final la = a.withValues(alpha: 1).computeLuminance();
      final lb = b.withValues(alpha: 1).computeLuminance();
      final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
      return (hi + 0.05) / (lo + 0.05);
    }

    for (final core in DetailThemes.all) {
      final s = AppTheme.fromDetail(core).stremioTv;
      expect(s.channelIdent, isNotEmpty, reason: core.id);
      expect(s.channelIdent.toSet().length, s.channelIdent.length,
          reason: '${core.id}: idents exist to tell channels apart');
      expect(s.qualityTier, hasLength(5), reason: core.id);
      expect(s.qualityTier.toSet().length, 5,
          reason: '${core.id}: the five tiers must stay tellable apart');
      // The glass is legibility over an arbitrary poster, so it follows no
      // ground — a theme-tinted glass on paper defeats the whole point.
      expect(s.glass, Colors.black.withValues(alpha: 0.55), reason: core.id);
      // 4.0: the same bar as `inkOn`, and the glyph is on a filled swatch.
      expect(contrast(s.inkOnFill, s.loaderAccent), greaterThanOrEqualTo(4.0),
          reason: '${core.id}: check glyph on the loader step dot');
    }
  });

test('debrify_tv subprofile pins the magic_tv literals', () {
    // Repeated-literal pins (the inline sources are gone), so they fix the
    // values going forward rather than proving the swap — see the header note.
    final tv = legacy.debrifyTv;
    expect(tv.accent, const Color(0xFFE50914));
    expect(tv.dialogBg, const Color(0xFF0F0F0F));
    expect(tv.noticeBg, const Color(0xFF1B1B1F));
    expect(tv.cardBg, const Color(0xFF1A1A1A));
    expect(tv.cardFocusBg, const Color(0xFF2A2A2A));
    expect(tv.controlBg, const Color(0xFF141414));
    expect(tv.fillStrong, Colors.white.withValues(alpha: 0.15));
    // withOpacity ROUNDS to an 8-bit alpha: the sources'
    // `Colors.white.withOpacity(0.1)` is 26/255 = 0.1020, not 0.1. Asserting
    // against `withValues(alpha: 0.1)` here would happily pass a different
    // colour, which is exactly how the calendar hairline nearly shipped wrong.
    expect(tv.fillWeak, Colors.white.withAlpha(26));
    expect(tv.fillWeak.a, closeTo(26 / 255, 1e-9));
    expect(tv.hairline, Colors.white12);
    expect(tv.focusRing, Colors.white);
    expect(tv.focusRingAlt, const Color(0xFF00E5FF));
    expect(tv.textDim, Colors.white70);
    expect(tv.textMeta, Colors.white60);
    expect(tv.textFaint, Colors.white54);
    expect(tv.favorite, const Color(0xFFFFD700));

    // Roles Debrify TV reads from elsewhere instead of re-declaring. If one of
    // these ever stops matching, the surface must grow its own token — not be
    // left silently pointing at a colour that moved.
    expect(legacy.core.tx, Colors.white); // page ink
    expect(legacy.home.sheetBg, const Color(0xFF0F172A)); // Import dialog slate
    expect(legacy.inkOn(tv.accent), Colors.white); // ink on the red fill

    // Two deliberate NON-reuses. Value equality under legacy is not role
    // equality under a theme.
    expect(tv.accent, legacy.calendar.accent); // same tin, different identity
    expect(tv.focusRingAlt, isNot(tv.focusRing)); // legacy runs two grammars

    for (final core in DetailThemes.all) {
      final t = AppTheme.fromDetail(core).debrifyTv;
      // Focus must stay a visible STEP off the row it lands on. This is the
      // failure a borrowed dialog ground would have caused: two roles that
      // derive to `core.pane` collapse, and the cursor stops being visible.
      expect(t.cardFocusBg, isNot(t.cardBg), reason: core.id);
      expect(t.cardBg, isNot(t.controlBg), reason: core.id);
      // …and real themes converge the two focus colours legacy split, so the
      // cyan never propagates past the compatibility profile.
      expect(t.focusRingAlt, t.focusRing, reason: core.id);
    }
  });

test('iptv subprofile pins the Command Center palette', () {
    // The Command Center look takes the UNTOUCHED legacy paint path today
    // (`IptvStyleTokens.of(command)` is null and every widget branches on the
    // style first), so these are repeated-literal pins in the header's second
    // sense: they fix the values going forward, they do not prove the swap.
    final i = legacy.iptv;
    expect(i.stageBg, const Color(0xFF0B0914));
    expect(i.rowFocusFill, const Color(0xFF141824));
    expect(i.modalBg, const Color(0xFF14141D));
    expect(i.logoPlate, const Color(0xFF1E2030));
    expect(i.chipSurface, const Color(0xF0141225));
    expect(i.fieldFill, const Color(0xFF0F0B14));
    expect(i.fieldBorder, const Color(0xFF2A2233));
    // Composed, not hexed — see the calendar note about alpha as a double.
    expect(i.hairline, Colors.white.withValues(alpha: 0.08));
    expect(i.surfaceTint, Colors.white.withValues(alpha: 0.04));
    expect(i.inkMid, Colors.white.withValues(alpha: 0.7));
    expect(i.inkDim, Colors.white.withValues(alpha: 0.55));
    expect(i.inkFaint, Colors.white.withValues(alpha: 0.35));
    expect(i.recordAccent, const Color(0xFFF43F5E));
    expect(i.favoriteAccent, const Color(0xFFF43F5E));
    expect(i.liveDot, const Color(0xFF34D399));
  });

  test('iptv reuses existing roles rather than re-declaring them', () {
    // Ten IPTV roles were EXACTLY equal to roles that already existed, so the
    // surface reads them from their owning profile. If one of these ever stops
    // matching, IPTV must grow its own token — not be left silently pointing
    // at a colour that moved.
    expect(legacy.seeAll.bg, kSeeAllBg); // the IPTV tab's ground
    expect(legacy.seeAll.accent, kSeeAllAccent); // chip focus, Watch fill
    expect(legacy.seeAll.accent2, kSeeAllAccent2); // dropdown glyphs, hints
    expect(legacy.seeAll.panel, kSeeAllPanel); // chip / dropdown ground
    expect(legacy.seeAll.line, kSeeAllLine); // filter-chip border
    expect(legacy.home.focus, HomeTheme.focusGold); // the DPAD cursor
    expect(legacy.sheetSurface, const Color(0xFF141019)); // list dialogs
    // Full-strength IPTV ink is `core.tx` and gets no field. That borrow is
    // only byte-identical because Signal's text really is pure white — assert
    // it, because the whole ink ramp rests on it.
    expect(legacy.core.tx, const Color(0xFFFFFFFF));

    // Value equality is not role equality. These two pairs are identical under
    // legacy and are deliberately NOT collapsed: `favoriteAccent` is a saved
    // preference rather than the DVR's `recordAccent` state, and `surfaceTint`
    // is a wash under content rather than the calendar's grid RULE.
    expect(legacy.iptv.favoriteAccent, legacy.iptv.recordAccent);
    expect(legacy.iptv.surfaceTint, legacy.calendar.line);
  });

  test('roles added to replace call-site isLegacy branches', () {
    // These six existed as `app.isLegacy ? <literal> : <token>` at the call
    // site — correct, but a branch in a widget is the job the token layer is
    // supposed to be doing. Modelling them removed five of eight such
    // branches; the three that remain are contrast decisions, not gaps.
    expect(legacy.playlist.posterFallbackDeep, const Color(0xFF06080F));
    expect(legacy.playlist.posterTileBg, const Color(0xFF333333));
    expect(legacy.playlist.noPosterBg, const Color(0xFF1E293B));
    expect(legacy.playlist.noPosterDeep, const Color(0xFF0F172A));
    expect(legacy.iptv.railBg, const Color(0xFF080B18));
    expect(legacy.iptv.railFocusInk, const Color(0xFFE4DCFF));

    // The two poster pairs are deliberately NOT collapsed: legacy paints the
    // no-artwork card slate and the loading fallback near-black, so one token
    // for both would move one of them.
    expect(legacy.playlist.noPosterBg, isNot(legacy.playlist.posterFallbackDeep));
  });

  test('roles added to close the half-themed gaps', () {
    expect(legacy.iptv.railSelectionFill,
        const Color(0xFF8A5CFF).withValues(alpha: 0.16));
    expect(legacy.stremioTv.loaderRailFar, const Color(0xFFC4B2FF));
    expect(legacy.stremioTv.loaderInk, Colors.white);
    expect(legacy.debrifyTv.dialogDeep, const Color(0xFF101014));
    expect(legacy.debrifyTv.controlResting, const Color(0xFF141418));
  });

  test('the loader plate stays dark on every theme', () {
    // The loader is a deliberate dark cinematic plate — black Material, black
    // scrims — so its radial bright stop is tinted off BLACK, not off the
    // page. Deriving it from the page ground gave Broadsheet a pale centre
    // under white checklist ink. Anything above a mid grey means that
    // regression is back.
    for (final core in DetailThemes.all) {
      final g = AppTheme.fromDetail(core).stremioTv.loaderGround;
      expect(g.computeLuminance(), lessThan(0.25),
          reason: '${core.id}: loader plate must stay dark');
    }
  });
}
