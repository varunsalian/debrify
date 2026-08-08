import 'package:flutter/material.dart';

import '../widgets/detail/theme/detail_theme.dart';
import '../widgets/detail/theme/detail_themes.dart';

/// App-wide theme: the details-page token core plus the per-surface role
/// tokens the chrome needs.
///
/// Two kinds of instance exist and only two:
///
/// * **`AppThemes.legacy`** — the compatibility profile. Every subprofile pins
///   the exact literal it replaces (`HomeTheme.focusGold`, `kSeeAllPanel`,
///   `kSettingsDim`, `CloudTheme.amber`, …), so a surface reading tokens under
///   `legacy` renders byte-for-byte what it rendered reading the constants.
///   Pinned by `test/theme/legacy_pins_test.dart` — if a constant and its pin
///   drift apart, that test fails, not a user's screen.
/// * **`AppTheme.fromDetail(core)`** — a real theme. Subprofiles are DERIVED
///   from the 20-theme detail core by the rules below. These derivations are
///   Foundation defaults: sweeps may refine them, but only by editing this
///   file (the no-agent-adds-a-token rule).
///
/// Naming: roles, never screens. `statusWarning` and `categoryFolder` are both
/// amber under legacy Cloud but are separate tokens on purpose — a theme must
/// be able to change one without misclassifying the other.
@immutable
class AppTheme {
  final String id;
  final String label;
  final bool isLegacy;

  /// The token core (grounds, text, meaning, shape, type). For real themes
  /// this is the selected [DetailTheme]; for legacy it is Signal, and the
  /// details page keeps resolving its OWN `detail_theme` pref instead.
  final DetailTheme core;

  final HomeTokens home;
  final SeeAllTokens seeAll;
  final SettingsTokens settings;
  final CloudTokens cloud;
  final CalendarTokens calendar;
  final ShellTokens shell;

  /// Light chrome ⇔ the ground reads light. One stated threshold, everywhere:
  /// `ground.computeLuminance() > 0.5`. Broadsheet (≈0.86) and Concrete
  /// (≈0.57) land light; every other shipped theme lands dark.
  final Brightness brightness;

  const AppTheme._({
    required this.id,
    required this.label,
    required this.isLegacy,
    required this.core,
    required this.home,
    required this.seeAll,
    required this.settings,
    required this.cloud,
    required this.calendar,
    required this.shell,
    required this.brightness,
    required this.sheetSurface,
  });

  bool get isLight => brightness == Brightness.light;

  /// The app's standard modal-sheet / menu ground.
  ///
  /// Top-level rather than per-family because one literal (`0xFF141019`)
  /// really is shared: the Home board's card menu, the merged-details
  /// quick-action sheets and the episode-options sheet all use it. Two
  /// family-scoped tokens for the same value would drift apart.
  ///
  /// It must be a token at all because these sheets' CONTENT inherits
  /// `ThemeData` text — so a surface pinned dark serves a light theme's
  /// near-black ink on a near-black sheet.
  final Color sheetSurface;

  /// Ink for content sitting ON a FILLED swatch — a primary button's label, a
  /// switch thumb, a check glyph inside a filled circle.
  ///
  /// Not [core].tx: that is ink for the PAGE. On a filled swatch it is the
  /// swatch that decides. Half the shipped themes have light accents —
  /// Broadcast's yellow, Verdant's lime, Blueprint's cyan, Noir and Frost's
  /// literal white — where a hardcoded white label ranges from hard to read
  /// to invisible.
  ///
  /// Takes the fill rather than assuming [core].accent: the subprofiles carry
  /// their own accents (legacy's Settings fills are violet while its core
  /// accent is olive), so the ink must be chosen against the swatch actually
  /// being painted.
  ///
  /// KEEPS page ink unless it is genuinely poor, rather than maximising
  /// contrast. Maximising sounds better and is wrong: on legacy's violet,
  /// ground scores 4.49 against white's 4.38, so a max rule would flip the
  /// shipped white label to near-black — a visible change to today's app in
  /// pursuit of a hundredth of a contrast point. The threshold flips only the
  /// cases that are actually unreadable (Broadcast's yellow gives white 1.4,
  /// Signal's olive 2.7).
  Color inkOn(Color fill) {
    final lf = fill.withValues(alpha: 1).computeLuminance();
    double against(Color ink) {
      final li = ink.withValues(alpha: 1).computeLuminance();
      final hi = li > lf ? li : lf;
      final lo = li > lf ? lf : li;
      return (hi + 0.05) / (lo + 0.05);
    }

    const adequate = 4.0;
    if (against(core.tx) >= adequate) return core.tx;
    return against(core.ground) > against(core.tx) ? core.ground : core.tx;
  }

  /// Ink for content on the dark GLASS that floats over artwork — episode
  /// badges, rating chips, type pills on a poster.
  ///
  /// The inverse of the usual trap. Those glass fills are black-at-alpha and
  /// stay black on every theme, because they exist to make text legible over
  /// an arbitrary image. So their ink must NOT follow page text: on a paper
  /// theme `core.tx` is near-black, which would vanish into the glass. Ask
  /// what reads on black instead.
  Color get onGlass => inkOn(const Color(0xFF000000));

  /// Scales a token's OWN alpha — same contract as [DetailTheme.fade].
  Color fade(Color c, double factor) =>
      c.withValues(alpha: (c.a * factor).clamp(0.0, 1.0));

  /// Derive a real app theme from a detail core.
  factory AppTheme.fromDetail(DetailTheme core) {
    final ground = core.ground;
    final light = ground.computeLuminance() > 0.5;
    final tx = core.tx;

    Color mix(Color a, Color b, double t) => Color.lerp(a, b, t)!;
    // Opaque elevated surfaces, stepped toward the text colour — the themed
    // equivalent of the legacy #17132E / #1E1840 panel pair.
    final panel = mix(ground, tx, 0.06);
    final panel2 = mix(ground, tx, 0.10);
    // The hairline flattened onto the ground, so it stays a LINE colour even
    // where it is drawn without the ground behind it.
    final line = Color.alphaBlend(core.hair, ground);

    // Status/category trios are semantic, not theme fields: green means good
    // on every theme. Only their weight changes — the dark-ground trio glares
    // on paper, so light grounds get deepened variants (WCAG-checked in the
    // contrast cross-product test).
    final success = light ? const Color(0xFF1B7F4D) : const Color(0xFF10B981);
    final warning = light ? const Color(0xFFB45309) : const Color(0xFFF59E0B);
    final error = light ? const Color(0xFFB3261E) : const Color(0xFFEF4444);
    final catVideo = light ? const Color(0xFF1D4ED8) : const Color(0xFF60A5FA);
    final catSeason = light ? const Color(0xFF6D28D9) : const Color(0xFFA78BFA);

    final wash = RadialGradient(
      center: const Alignment(0, -0.75),
      radius: 1.35,
      colors: [
        mix(core.pane, core.accent, 0.10),
        mix(core.pane, ground, 0.55),
        ground,
        ground,
      ],
      stops: const [0.0, 0.38, 0.68, 1.0],
    );

    return AppTheme._(
      id: core.id,
      label: core.label,
      isLegacy: false,
      core: core,
      brightness: light ? Brightness.light : Brightness.dark,
      sheetSurface: mix(ground, tx, 0.08),
      home: HomeTokens(
        bg: ground,
        wash: wash,
        chromeAccent: core.accent,
        focus: core.focus,
        focusDeep: core.state,
        highlight: core.callout,
        danger: error,
        sheetBg: core.pane.withValues(alpha: 1),
        dialogBg: mix(ground, tx, 0.05),
        controlBg: mix(ground, tx, 0.20),
        posterPlaceholder: mix(ground, tx, 0.04),
      ),
      seeAll: SeeAllTokens(
        bg: ground,
        accent: core.accent,
        accent2: mix(core.accent, tx, 0.30),
        panel: panel,
        panel2: panel2,
        accentBorder: core.accent.withValues(alpha: 0.38),
        line: line,
        wash: wash,
        card: mix(ground, tx, 0.07),
        danger: error,
        warning: warning,
        listBg: ground,
      ),
      settings: SettingsTokens(
        bg: ground,
        accent: core.accent,
        accent2: mix(core.accent, tx, 0.30),
        panel: panel,
        panel2: panel2,
        success: success,
        danger: error,
        warning: warning,
        line: line,
        dim: tx.withValues(alpha: 0.46),
        dim2: tx.withValues(alpha: 0.28),
        sheetBg: core.pane.withValues(alpha: 1),
      ),
      cloud: CloudTokens(
        bg: ground,
        accent: core.accent,
        // Cloud's own context-menu surface — a DIFFERENT literal from the
        // shared `sheetSurface` (0xFF1E1B2C vs 0xFF141019), so it keeps its
        // own token rather than collapsing into it.
        menuSurface: mix(ground, tx, 0.08),
        wash: wash,
        hubWash: RadialGradient(
          center: const Alignment(0, -0.75),
          radius: 1.35,
          colors: [
            // Brighter than `wash`'s first stop — the hub's bloom is the more
            // pronounced of the two.
            mix(core.pane, core.accent, 0.22),
            mix(core.pane, ground, 0.40),
            mix(core.pane, ground, 0.80),
            ground,
          ],
          stops: const [0.0, 0.42, 0.72, 1.0],
        ),
        // Matches what the ThemeData adapter gives `dialogTheme`, so a Cloud
        // dialog and a Material one read as the same surface.
        dialogSurface: core.pane.withValues(alpha: 1),
        focusSurface: mix(ground, core.accent, 0.30),
        statusSuccess: success,
        statusWarning: warning,
        statusError: error,
        destructive: error,
        categoryVideo: catVideo,
        categoryFolder: warning,
        categorySeason: catSeason,
      ),
      calendar: CalendarTokens(
        bg: ground,
        sheetBg: core.pane,
        panel: panel,
        // These four carry the per-title palette's TEXT, so they must move
        // with it: leaving them dark while the palette deepens for a light
        // theme is precisely the black-on-black trap.
        card: panel,
        card2: mix(ground, tx, 0.02),
        row: panel2,
        badgeGround: panel2,
        line: core.hair,
        accent: core.accent,
        accentPalette: _accentRamp(core.accent, light: light),
      ),
      shell: ShellTokens(
        ink: ground,
        sidebarScrim: Colors.black.withValues(alpha: 0.54),
        railVeil: ground.withValues(alpha: 0.92),
        // The theme's own mild surface step, not a hand-rolled lighten:
        // "separated from the page" is DIRECTIONAL and every theme already
        // encodes its own direction. Dark themes step lighter (Signal's pane
        // #0E0B14 over #0B0B0E, matching legacy's #120F24 over #0D0B1A);
        // paper themes step darker (Broadsheet's #EFEAE0 under #F3EFE7),
        // which is what a rail on paper should do. A `mix(ground, tx)` here
        // read as elevation on dark themes and sank the rail into the page on
        // light ones.
        railBg: core.pane,
        // The theme's OWN rail ground: every DetailTheme already declares one,
        // and it is deeper than its ground in every shipped theme — exactly
        // the TV rail's relationship to the page.
        railInk: core.railBg,
        barBg: ground.withValues(alpha: 0.97),
        navAccent: core.accent,
        navFocus: core.focus,
        navLabel: mix(core.accent, tx, 0.55),
        navSheetBg: mix(ground, tx, 0.06),
      ),
    );
  }
}

/// Six distinguishable, legible tones around [accent], for the calendar's
/// per-title colouring.
///
/// Two constraints, and both had to be learned the hard way:
///
/// * **Distinctness.** An earlier version spanned the theme's
///   accent/callout/state, which collapses to ONE colour on every theme that
///   deliberately sets those equal — Broadsheet's single oxblood, and it is
///   far from alone. So the ramp varies lightness on a fixed scale instead,
///   which is also truer to legacy: its six "reds" are tones of one hue, not
///   six unrelated colours.
/// * **Legibility.** A single absolute lightness band cannot serve both
///   grounds: 0.34–0.74 reads well on ink and washes out to ~1.3:1 on paper,
///   where these tones carry dates and episode times. The band therefore
///   moves AWAY from the ground — bright on dark themes, deep on light ones.
///
/// [light] is the theme's own brightness verdict, so the two never disagree.
/// A zero-saturation accent (Noir's white) simply yields six greys, which is
/// correct for that theme rather than a degenerate case.
///
/// The steps target LUMINANCE, not HSL lightness. Lightness is not perceptual
/// and hue-dependent by a wide margin: at L=0.46 Aurora's saturated blue
/// lands at luminance 0.09 (≈2.2:1 on its panel) while Broadcast's yellow
/// lands at 0.57. A lightness ramp therefore reads fine on some accents and
/// is invisible on others — measured, not assumed.
///
/// Computed once per theme (the controller memoizes the derived AppTheme), so
/// the search below never runs during a build.
List<Color> _accentRamp(Color accent, {required bool light}) {
  final hsl = HSLColor.fromColor(accent);
  // Dark grounds: rise well clear of a near-black panel. Light grounds: stay
  // deep — Concrete's panel sits at luminance 0.50, so anything above ~0.135
  // drops under 3:1 against it.
  const onDark = [0.25, 0.33, 0.42, 0.52, 0.63, 0.75];
  const onLight = [0.015, 0.035, 0.055, 0.080, 0.105, 0.130];
  final targets = light ? onLight : onDark;
  const hueShift = [0.0, 14.0, -12.0, 6.0, -20.0, 22.0];
  return [
    for (var i = 0; i < 6; i++)
      _atLuminance(hsl.withHue((hsl.hue + hueShift[i]) % 360), targets[i]),
  ];
}

/// [hsl] re-lightened until it reads at [target] luminance.
///
/// Bisection on HSL lightness, which luminance increases monotonically with
/// for a fixed hue and saturation — and whose ends are black and white, so
/// every target in (0,1) is reachable whatever the hue.
Color _atLuminance(HSLColor hsl, double target) {
  var lo = 0.0;
  var hi = 1.0;
  for (var i = 0; i < 18; i++) {
    final mid = (lo + hi) / 2;
    if (hsl.withLightness(mid).toColor().computeLuminance() < target) {
      lo = mid;
    } else {
      hi = mid;
    }
  }
  return hsl.withLightness((lo + hi) / 2).toColor();
}

/// Home / Search / Discover board chrome. Only the LIVE `HomeTheme` colour
/// symbols get roles — the audit found `accent`, `cardBg` and the progress
/// gradients have zero live consumers, and dead symbols get no tokens.
@immutable
class HomeTokens {
  /// `HomeTheme.bg` — the board's page ink.
  final Color bg;

  /// `HomeTheme.pageBackground` — the dim indigo bloom behind the board.
  final Gradient wash;

  /// `HomeTheme.chromeAccent` — active chrome (search pill, mode toggle).
  final Color chromeAccent;

  /// `HomeTheme.focusGold` — the content DPAD cursor.
  final Color focus;

  /// `HomeTheme.focusGoldDeep` — the cursor's soft bloom partner.
  final Color focusDeep;

  /// `HomeTheme.highlight` — live / now-playing indicators only.
  final Color highlight;

  /// `HomeTheme.danger` — destructive actions.
  final Color danger;

  /// Ground for the board's action sheets (stream/source long-press menus).
  final Color sheetBg;

  /// Ground for the board's own dialogs (the source picker).
  final Color dialogBg;

  /// Raised control ground — the multi-select FAB.
  final Color controlBg;

  /// Fill behind a missing poster. Its title text is theme ink, so it cannot
  /// stay a dark literal while the ink follows a light theme.
  final Color posterPlaceholder;

  const HomeTokens({
    required this.bg,
    required this.wash,
    required this.chromeAccent,
    required this.focus,
    required this.focusDeep,
    required this.highlight,
    required this.danger,
    required this.sheetBg,
    required this.dialogBg,
    required this.controlBg,
    required this.posterPlaceholder,
  });
}

/// See-All / Discover / Addons chrome (the `kSeeAll*` vocabulary).
@immutable
class SeeAllTokens {
  final Color bg;
  final Color accent;
  final Color accent2;
  final Color panel;
  final Color panel2;
  final Color accentBorder;
  final Color line;

  /// The Addons hub's page bloom — byte-identical to the shared legacy wash,
  /// so it pins to the same gradient rather than getting its own literal.
  final Gradient wash;

  /// Opaque addon/engine card ground. Carries inherited `ThemeData` text, so
  /// it has to be a token or those titles invert on a light theme.
  final Color card;

  final Color danger;
  final Color warning;

  /// The MDBList lists screen's ground — a shade deeper than [bg], and its
  /// AppBar title inherits `ThemeData`, so it must be a token.
  final Color listBg;

  const SeeAllTokens({
    required this.bg,
    required this.accent,
    required this.accent2,
    required this.panel,
    required this.panel2,
    required this.accentBorder,
    required this.line,
    required this.wash,
    required this.card,
    required this.danger,
    required this.warning,
    required this.listBg,
  });
}

/// Settings chrome (the `kSettings*` vocabulary).
@immutable
class SettingsTokens {
  final Color bg;
  final Color accent;
  final Color accent2;
  final Color panel;
  final Color panel2;
  final Color success;
  final Color danger;
  final Color warning;
  final Color line;
  final Color dim;
  final Color dim2;

  /// Ground for Settings' own bottom sheets. Its `ListTile` titles carry no
  /// colour, so they inherit `onSurface` — a dark pin would serve a light
  /// theme's near-black text on navy.
  final Color sheetBg;

  const SettingsTokens({
    required this.bg,
    required this.accent,
    required this.accent2,
    required this.panel,
    required this.panel2,
    required this.success,
    required this.danger,
    required this.warning,
    required this.line,
    required this.dim,
    required this.dim2,
    required this.sheetBg,
  });
}

/// Cloud chrome (the `CloudTheme` vocabulary), with the category/status split
/// the plan mandates: legacy amber is BOTH the folder category and the warning
/// badge, and folding those into one `status*` set would misclassify folders.
@immutable
class CloudTokens {
  final Color bg;
  final Color accent;
  final Color menuSurface;
  final Gradient wash;

  /// The Cloud HUB's page bloom. A separate token from [wash]: brighter, and
  /// stopped differently (0/.42/.72/1 vs 0/.38/.68/1), so it is not the same
  /// gradient and cannot borrow that pin.
  final Gradient hubWash;

  /// The slate ground shared by every Cloud dialog, sheet and result card.
  ///
  /// Tokenised because their CONTENT inherits `ThemeData.onSurface` — it
  /// always did — so once that follows a light theme, a dialog pinned to a
  /// dark slate serves near-black text on navy. Surface and ink have to move
  /// together, and here the ink was never ours to pin.
  final Color dialogSurface;

  /// Fill behind a FOCUSED toolbar icon. Tokenised because the icon on top is
  /// theme ink and the fill is conditional — unfocused, those icons sit on the
  /// page itself, so pinning them light would make every toolbar icon vanish
  /// on a light theme in the common state.
  final Color focusSurface;
  final Color statusSuccess;
  final Color statusWarning;
  final Color statusError;
  final Color destructive;
  final Color categoryVideo;
  final Color categoryFolder;
  final Color categorySeason;

  const CloudTokens({
    required this.bg,
    required this.accent,
    required this.menuSurface,
    required this.wash,
    required this.hubWash,
    required this.dialogSurface,
    required this.focusSurface,
    required this.statusSuccess,
    required this.statusWarning,
    required this.statusError,
    required this.destructive,
    required this.categoryVideo,
    required this.categoryFolder,
    required this.categorySeason,
  });
}

/// Calendar (Trakt/Simkl schedule).
///
/// Its own subprofile because it shares no constant module with anything else
/// — `trakt_calendar_screen.dart` imports no theme file at all, so its
/// vocabulary had to be read off the screen itself.
@immutable
class CalendarTokens {
  /// The page ground.
  final Color bg;

  /// The day-sheet ground — a step off [bg].
  final Color sheetBg;

  /// Row / card ground, used opaque and as gradient stops.
  final Color panel;

  /// The day card's own ground pair (a diagonal gradient), distinct from
  /// [panel].
  final Color card;
  final Color card2;

  /// Episode-row ground.
  final Color row;

  /// The date badge's deep gradient stop, under an accent-tinted top.
  final Color badgeGround;

  /// Hairline borders throughout the grid.
  final Color line;

  /// The schedule's identity accent (Trakt red under legacy).
  final Color accent;

  /// Six tones hashed per title, so a show keeps one colour across the grid.
  /// A LIST token, not six fields: legacy must return these exact six, while
  /// a real theme derives six tones from its own accent — same contract,
  /// different source.
  final List<Color> accentPalette;

  const CalendarTokens({
    required this.bg,
    required this.sheetBg,
    required this.panel,
    required this.card,
    required this.card2,
    required this.row,
    required this.badgeGround,
    required this.line,
    required this.accent,
    required this.accentPalette,
  });
}

/// The app shell: page ink, the TV rail's two scrims, and the navigation
/// chrome's own grounds and accents.
///
/// The three grounds are separate tokens rather than one because they sit at
/// genuinely different elevations, and legacy pins them to three different
/// literals: the desktop rail is LIGHTER than the page (elevated), the TV rail
/// is DEEPER (it sits under the ambient art stage), and the phone bar is
/// translucent over the page.
@immutable
class ShellTokens {
  /// The opaque page ink behind every non-TV page (`HomeTheme.bg` today).
  final Color ink;

  /// Dim over content while the TV sidebar overlay is open (`0x8A05060E`).
  final Color sidebarScrim;

  /// The lights-off veil over the collapsed rail strip (`0xEB0D0B1A`).
  final Color railVeil;

  /// Desktop/tablet sidebar ground — elevated above [ink].
  final Color railBg;

  /// TV sidebar ground — deeper than [ink].
  final Color railInk;

  /// Phone bottom-bar ground; translucent over the page by design.
  final Color barBg;

  /// The active/selected navigation destination.
  final Color navAccent;

  /// TV rail focus ring, and the softer accent its selected states use.
  final Color navFocus;

  /// Ground for the phone bar's More / Edit Navigation sheets.
  final Color navSheetBg;

  /// Active destination LABEL — a light tint of the accent, so the label
  /// reads at a glance without competing with the icon's fill.
  final Color navLabel;

  const ShellTokens({
    required this.ink,
    required this.sidebarScrim,
    required this.railVeil,
    required this.railBg,
    required this.railInk,
    required this.barBg,
    required this.navAccent,
    required this.navFocus,
    required this.navLabel,
    required this.navSheetBg,
  });
}

/// The registry.
abstract final class AppThemes {
  /// The stored sentinel meaning "render today's app exactly".
  static const String legacyId = 'legacy';

  /// The compatibility profile. Every value below is a PIN of a literal that
  /// exists elsewhere in the tree; `legacy_pins_test.dart` asserts agreement
  /// with the real constants so the two can never drift silently.
  ///
  /// `final`, not `const`: the handful of `withValues(alpha:)` pins
  /// (`kSeeAllAccentBorder`, `kSettingsDim`, …) cannot be const, and splitting
  /// the profile across const/non-const halves for their sake would not be
  /// worth the reading cost.
  static final AppTheme legacy = AppTheme._(
    id: legacyId,
    label: 'Debrify Classic',
    isLegacy: true,
    core: DetailThemes.signal,
    brightness: Brightness.dark,
    // cw_card_menu, the two detail quick-action sheets, the episode sheet
    sheetSurface: const Color(0xFF141019),
    home: HomeTokens(
      bg: const Color(0xFF0D0B1A), // HomeTheme.bg
      wash: _legacyWash, // HomeTheme.pageBackground
      chromeAccent: const Color(0xFF7B5CFF), // HomeTheme.chromeAccent
      focus: const Color(0xFFFBBF24), // HomeTheme.focusGold
      focusDeep: const Color(0xFFF59E0B), // HomeTheme.focusGoldDeep
      highlight: const Color(0xFFF59E0B), // HomeTheme.highlight
      danger: const Color(0xFFEF4444), // HomeTheme.danger
      sheetBg: const Color(0xFF0F172A), // search stream/source sheets
      dialogBg: const Color(0xFF16131F), // search source dialog
      controlBg: const Color(0xFF334155), // multi-select FAB
      posterPlaceholder: const Color(0xFF111118), // catalog tile placeholder
    ),
    seeAll: SeeAllTokens(
      bg: const Color(0xFF0D0B1A), // kSeeAllBg
      accent: const Color(0xFF7B5CFF), // kSeeAllAccent
      accent2: const Color(0xFF9B7BFF), // kSeeAllAccent2
      panel: const Color(0xFF17132E), // kSeeAllPanel
      panel2: const Color(0xFF1E1840), // kSeeAllPanel2
      accentBorder: // kSeeAllAccentBorder
          const Color(0xFF7B5CFF).withValues(alpha: 0.38),
      line: // kSeeAllLine
          const Color(0xFFB4A0FF).withValues(alpha: 0.12),
      wash: _legacyWash, // addon_hub bloom — the same gradient, verified
      card: const Color(0xFF191B28), // addon_hub _kCardBg
      danger: const Color(0xFFEF4444), // addon_hub destructive
      warning: const Color(0xFFF6B94A), // addon_hub "needs debrid" caveat
      listBg: const Color(0xFF0B0910), // mdblist_lists_see_all ground
    ),
    settings: SettingsTokens(
      bg: const Color(0xFF0D0B1A), // kSettingsBg
      accent: const Color(0xFF7B5CFF), // kSettingsAccent
      accent2: const Color(0xFF9B7BFF), // kSettingsAccent2
      panel: const Color(0xFF17132E), // kSettingsPanel
      panel2: const Color(0xFF1E1840), // kSettingsPanel2
      success: const Color(0xFF39D98A), // kSettingsGreen
      danger: const Color(0xFFE5484D), // kSettingsRed
      warning: const Color(0xFFF5A623), // kSettingsAmber
      line: // kSettingsLine
          const Color(0xFFB4A0FF).withValues(alpha: 0.12),
      dim: Colors.white.withValues(alpha: 0.46), // kSettingsDim
      dim2: Colors.white.withValues(alpha: 0.28), // kSettingsDim2
      sheetBg: const Color(0xFF0B1220), // download-location sheet
    ),
    cloud: CloudTokens(
      bg: const Color(0xFF0D0B1A), // CloudTheme.bg
      accent: const Color(0xFF7B5CFF), // CloudTheme.accent
      menuSurface: const Color(0xFF1E1B2C), // CloudTheme.menuSurface
      wash: _legacyWash, // CloudTheme.pageGradient (same stops)
      hubWash: _legacyHubWash, // cloud_screen's own, brighter bloom
      dialogSurface: const Color(0xFF1E293B), // shared slate dialog ground
      focusSurface: const Color(0xFF312E81), // webdav toolbar focus fill
      statusSuccess: const Color(0xFF10B981), // CloudTheme.green
      statusWarning: const Color(0xFFF59E0B), // CloudTheme.amber (warning use)
      statusError: const Color(0xFFEF4444), // CloudTheme.red
      destructive: const Color(0xFFEF4444), // CloudTheme.red
      categoryVideo: const Color(0xFF60A5FA), // CloudTheme.blue
      categoryFolder: const Color(0xFFF59E0B), // CloudTheme.amber (folder use)
      categorySeason: const Color(0xFFA78BFA), // CloudTheme.purple
    ),
    calendar: CalendarTokens(
      bg: const Color(0xFF060816), // trakt_calendar_screen scaffold
      sheetBg: const Color(0xFF0C1222), // day-sheet scaffold
      panel: const Color(0xFF11131B), // day-header strip veil
      card: const Color(0xFF141219), // day-card gradient, top
      card2: const Color(0xFF0A0B12), // day-card gradient, bottom
      row: const Color(0xFF181922), // episode row
      badgeGround: const Color(0xFF191B23), // date badge, deep stop
      // Composed the SAME way the source composes it. A hex pin would not do:
      // Color stores alpha as a double now, so 0x0AFFFFFF is 0.0392 while
      // `withValues(alpha: 0.04)` is exactly 0.04 — a real, if tiny, mismatch
      // that the pin test caught.
      line: Colors.white.withValues(alpha: 0.04), // grid hairlines
      accent: const Color(0xFFE50914), // _kNetflixRed
      accentPalette: const [
        // _accentFor's palette, in order — the hash indexes this list, so the
        // ORDER is part of the contract, not just the set.
        Color(0xFFE50914),
        Color(0xFFF97316),
        Color(0xFFFB7185),
        Color(0xFFDC2626),
        Color(0xFFEF4444),
        Color(0xFFB91C1C),
      ],
    ),
    shell: const ShellTokens(
      ink: Color(0xFF0D0B1A), // main.dart Scaffold backgroundColor
      sidebarScrim: Color(0x8A05060E), // main.dart TV sidebar scrim
      railVeil: Color(0xEB0D0B1A), // main.dart lights-off rail veil
      railBg: Color(0xFF120F24), // desktop_sidebar_nav _kRailBg
      railInk: Color(0xFF0A0910), // tv_sidebar_nav _ink
      barBg: Color(0xF712101F), // mobile_classic_nav bar ground
      navAccent: Color(0xFF7B5CFF), // tv_sidebar_nav _accent
      navFocus: Color(0xFFA78BFA), // tv_sidebar_nav _accentSoft
      navLabel: Color(0xFFC7BFFF), // mobile_classic_nav active label
      navSheetBg: Color(0xFF161327), // mobile_classic_nav More / Edit sheets
    ),
  );

  /// `HomeTheme.pageBackground` / `CloudTheme.pageGradient` — one gradient,
  /// two legacy constants with identical stops.
  static const RadialGradient _legacyWash = RadialGradient(
    center: Alignment(0, -0.75),
    radius: 1.35,
    colors: [
      Color(0xFF241E44),
      Color(0xFF161327),
      Color(0xFF0F0D1D),
      Color(0xFF0D0B1A),
    ],
    stops: [0.0, 0.38, 0.68, 1.0],
  );

  /// `cloud_screen.dart`'s bloom — brighter and differently stopped than
  /// [_legacyWash], which is why Cloud carries two gradient tokens.
  static const RadialGradient _legacyHubWash = RadialGradient(
    center: Alignment(0, -0.75),
    radius: 1.35,
    colors: [
      Color(0xFF322A6B),
      Color(0xFF1A1734),
      Color(0xFF100E20),
      Color(0xFF0D0B1A),
    ],
    stops: [0.0, 0.42, 0.72, 1.0],
  );

  /// Resolve a stored id. Unknown or removed ids fall back to LEGACY, never to
  /// a random theme — a downgraded build must render the app it shipped.
  static AppTheme byId(String id) {
    if (id == legacyId) return legacy;
    for (final core in DetailThemes.all) {
      if (core.id == id) return AppTheme.fromDetail(core);
    }
    return legacy;
  }
}
